"""Audit recorded JS/Wasm primitive cohorts; never executes Dart or Node."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
from urllib.parse import unquote, urljoin, urlparse

parser = argparse.ArgumentParser()
parser.add_argument('raw', type=Path)
parser.add_argument('--collector', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--summary', type=Path, required=True)
parser.add_argument('--vectors', type=Path, required=True)
args = parser.parse_args()
encoded = args.raw.read_bytes()
blob = gzip.decompress(encoded) if args.raw.suffix == '.gz' else encoded
raw = json.loads(blob)
counts, findings = Counter(), []

def check(value, context):
    counts['checks'] += 1
    if not value:
        findings.append(context)

def sha(value):
    return hashlib.sha256(value).hexdigest()

def instant(value):
    return datetime.fromisoformat(value)

def local_uri(base, relative):
    parsed = urlparse(urljoin(base, relative))
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
        raise ValueError('Expected local URI')
    return Path(unquote(parsed.path)).resolve()

def pct(before, after):
    return 100 * (after / before - 1) if before else None

check(raw['status'] == 'complete', 'portable collector completed')
check(raw['rounds'] == 3 and raw['modes'] == ['js', 'wasm'], 'expected pairs and modes')
check(sha(args.collector.read_bytes()) == raw['collector_sha256'], 'reviewed collector matches recorded bytes')
roots = {label: Path(identity['resolved_root']) for label, identity in raw['revisions'].items()}
check(set(roots) == {'before', 'after'} and roots['before'] != roots['after'], 'two distinct source roots')
for label, root in roots.items():
    identity = raw['revisions'][label]
    config = root / '.dart_tool/package_config.json'
    own = [p for p in json.loads(config.read_text())['packages'] if p['name'] == 'dart_csp']
    check(len(own) == 1 and own[0] == identity['package_mapping'], [label, 'own-package mapping'])
    package_root = local_uri(config.as_uri(), own[0]['rootUri'])
    library = local_uri(package_root.as_uri() + '/', own[0].get('packageUri', ''))
    check(package_root == root and str(library) == identity['resolved_library'] and library == root / 'lib', [label, 'independent package resolution'])
    check(sha(config.read_bytes()) == identity['package_config_sha256'], [label, 'package configuration digest'])
    check(sha((root / 'pubspec.lock').read_bytes()) == identity['dependency_lock_sha256'], [label, 'lock digest'])
    for file, field in (('benchmark/interval_rounding.dart', 'harness_sha256'), ('tool/run_dart_node.cjs', 'launcher_sha256')):
        check(sha((root / file).read_bytes()) == identity[field], [label, file, 'current byte identity'])
    def git(*argv):
        return subprocess.check_output(['git', *argv], cwd=root)
    commit = identity['commit']
    check(git('rev-parse', commit + ':lib').decode().strip() == identity['library_tree'], [label, 'frozen library tree'])
    files = git('ls-tree', '-r', '--name-only', commit, '--', 'lib').decode().splitlines()
    check(set(files) == set(identity['library_file_sha256']), [label, 'complete recorded source inventory'])
    for name, expected in identity['library_file_sha256'].items():
        frozen = git('show', commit + ':' + name)
        check(sha(frozen) == expected and (root / name).read_bytes() == frozen, [label, name, 'frozen/current bytes'])
        counts['library_files'] += 1
    check(not git('status', '--porcelain=v1', '--', 'lib').strip(), [label, 'clean library'])

for field in ('dependency_lock_sha256', 'harness_sha256', 'launcher_sha256'):
    check(raw['revisions']['before'][field] == raw['revisions']['after'][field], [field, 'identical before/after'])
old_files, new_files = (raw['revisions'][label]['library_file_sha256'] for label in ('before', 'after'))
changed = sorted(name for name in set(old_files) | set(new_files) if old_files.get(name) != new_files.get(name))
check(changed == ['lib/src/continuous.dart'], 'sole production delta is rounding source')
check(new_files['lib/src/continuous.dart'] == '6ae21fd6dba5fc9e4fd49017fb54ddcd270773a8dc3e14f0fc2c7ca219aa83f3', 'reviewed guarded source hash')
for runtime in ('dart', 'node'):
    check(sha(Path(raw[runtime]['executable']).read_bytes()) == raw[runtime]['sha256'], [runtime, 'current executable digest'])
    counts['runtime_binary_hashes'] += 1

compile_records, version_records = {}, {}
previous_finish = None
for i, process in enumerate(raw['process_records']):
    check(process['exit_code'] == 0 and process['timed_out'] is False, [i, 'successful non-timeout exit'])
    start, finish = (instant(process[k]) for k in ('started_at_utc', 'finished_at_utc'))
    check(finish >= start and (previous_finish is None or start >= previous_finish), [i, 'sequential subprocess timestamps'])
    previous_finish = finish
    for stream in ('stdout', 'stderr'):
        check(sha(process[stream].encode('utf-8', 'surrogateescape')) == process[stream + '_sha256'], [i, stream, 'lossless stream hash'])
        counts['stream_hashes'] += 1
    check(process['stderr'] == '', [i, 'no hidden stderr diagnostics'])
    phase, command = process['phase'], process['command']
    if phase == 'identity':
        label = next((label for label, root in roots.items() if str(root) == process['cwd']), None)
        check(label is not None, [i, 'identity worktree'])
        identity = raw['revisions'][label]
        expected = {
            ('git', 'status', '--porcelain', '--untracked-files=all', '--ignored=matching', '--', 'lib'): '',
            ('git', 'rev-parse', 'HEAD'): identity['commit'],
            ('git', 'rev-parse', 'HEAD:lib'): identity['library_tree'],
        }
        check(tuple(command) in expected and process['stdout'].strip() == expected.get(tuple(command)), [i, 'acquisition-time source identity'])
    elif phase == 'runtime_version':
        runtime = next((k for k in ('dart', 'node') if command == [raw[k]['executable'], '--version']), None)
        check(runtime is not None and runtime not in version_records, [i, 'runtime version command'])
        version_records[runtime] = process
        check((process['stdout'] + process['stderr']).strip() == raw[runtime]['version'], [i, 'runtime version text'])
    elif phase.startswith('compile_'):
        _, mode, label = phase.split('_')
        check((mode, label) not in compile_records, [i, 'unique compile'])
        compile_records[mode, label] = process
        root = roots[label]
        check(process['cwd'] == str(root), [i, 'compile cwd'])
        check(command[:6] == [raw['dart']['executable'], 'compile', mode, '-O2', '--packages=' + str(root / '.dart_tool/package_config.json'), 'benchmark/interval_rounding.dart'], [i, 'explicit target/package/harness'])
        check(len(command) == 8 and command[6] == '-o', [i, 'compile output argument'])
        check(not any('dart.library.io' in arg for arg in command), [i, 'no capability override'])
    elif phase.startswith('benchmark_'):
        counts['benchmark_processes'] += 1
    else:
        check(False, [i, 'unexpected phase'])
    counts['process_records'] += 1

expected_phases = []
for label in ('before', 'after'):
    expected_phases += [('identity', str(roots[label]))] * 3
expected_phases += [('runtime_version', str(roots['before']))] * 2
for mode in raw['modes']:
    for label in ('before', 'after'):
        expected_phases += [('identity', str(roots[label]))] * 3
        expected_phases += [('compile_' + mode + '_' + label, str(roots[label]))]
        expected_phases += [('identity', str(roots[label]))] * 3
for mode in raw['modes']:
    for repeat in range(1, raw['rounds'] + 1):
        for label in (('before', 'after') if repeat % 2 else ('after', 'before')):
            expected_phases += [('identity', str(roots[label]))] * 3
            expected_phases += [('benchmark_' + mode + '_' + label, str(roots[label]))]
            expected_phases += [('identity', str(roots[label]))] * 3
check([(p['phase'], p['cwd']) for p in raw['process_records']] == expected_phases, 'complete pre/post identity and process acquisition order')

artifacts = {(a['mode'], a['revision']): a for a in raw['compiled_artifacts']}
check(len(artifacts) == len(raw['compiled_artifacts']) == 4, 'four unique artifact manifests')
artifact_comparisons = []
for mode in raw['modes']:
    expected_names = {'rounding.js', 'rounding.js.deps', 'rounding.js.map'} if mode == 'js' else {'rounding.wasm', 'rounding.mjs', 'rounding.support.js', 'rounding.wasm.map'}
    executable_names = {'rounding.js'} if mode == 'js' else {'rounding.wasm', 'rounding.mjs', 'rounding.support.js'}
    for label in ('before', 'after'):
        files = artifacts[mode, label]['files_sha256']
        check(set(files) == expected_names, [mode, label, 'complete generated-file manifest'])
        check(all(len(h) == 64 and all(c in '0123456789abcdef' for c in h) for h in files.values()), [mode, label, 'SHA-256 strings'])
    for name in sorted(expected_names):
        before = artifacts[mode, 'before']['files_sha256'][name]
        after = artifacts[mode, 'after']['files_sha256'][name]
        artifact_comparisons.append({'mode': mode, 'file': name, 'role': 'executable' if name in executable_names else 'metadata', 'before_sha256': before, 'after_sha256': after, 'identical_recorded_bytes': before == after})
        if name in executable_names:
            check(before == after, [mode, name, 'runtime artifact byte identity'])
        counts['artifact_comparisons'] += 1

SIGN = 1 << 63
EXP = 0x7ff0000000000000
MANTISSA = (1 << 52) - 1
NAN = 0x7ff8000000000000
def canonical(bits):
    return NAN if bits & EXP == EXP and bits & MANTISSA else bits
def up(bits):
    if bits & EXP == EXP and bits & MANTISSA:
        return NAN
    if bits == EXP:
        return bits
    if bits & ~SIGN == 0:
        return 1
    return bits - 1 if bits & SIGN else bits + 1
def step(bits, downward):
    return canonical(up(bits ^ SIGN) ^ SIGN) if downward else canonical(up(bits))
def words(bits):
    return [bits >> 32, bits & 0xffffffff]
input_values = [0, SIGN, 1, SIGN | 1, 0x000fffffffffffff, 0x800fffffffffffff,
    0x0010000000000000, 0x8010000000000000, 0x3ff0000000000000, 0xbff0000000000000,
    0x7fefffffffffffff, 0xffefffffffffffff, EXP, SIGN | EXP, NAN, NAN]
for exponent in (2, 512, 1022, 1023, 1024, 1534, 2045, 2046):
    for low in (0, 1, 0xffffffff):
        positive = (((exponent << 20) | 0xfffff) << 32) | low
        input_values.extend((positive, SIGN | positive))
input_words = [words(value) for value in input_values]
expected_vectors = {name: [words(step(value, name == 'next_down')) for value in input_values] for name in ('next_up', 'next_down')}
check(raw['expected_work']['input_bits'] == input_words and len(input_words) == 64, 'independent input-bit corpus')
expected_checksums = {name: sum(sum(vectors[i & 63]) for i in range(8192)) % (1 << 32) for name, vectors in expected_vectors.items()}
check(raw['expected_work']['expected_checksums'] == list(expected_checksums.values()), 'full-integer independent checksum reconstruction')

grouped, seen = defaultdict(dict), set()
expected_run_order = [(mode, repeat, label) for mode in raw['modes'] for repeat in range(1, 4) for label in (('before', 'after') if repeat % 2 else ('after', 'before'))]
check([tuple(r[k] for k in ('mode', 'round', 'revision')) for r in raw['runs']] == expected_run_order, 'complete alternating Node runs')
for run in raw['runs']:
    mode, repeat, label = (run[k] for k in ('mode', 'round', 'revision'))
    identity = [mode, repeat, label]
    pointer = run['process_record']
    check(type(pointer) is int and 0 <= pointer < len(raw['process_records']) and pointer not in seen, [identity, 'unique process pointer'])
    seen.add(pointer)
    process = raw['process_records'][pointer]
    root = roots[label]
    compiled = compile_records[mode, label]
    artifact = compiled['command'][-1]
    command = [raw['node']['executable'], str(root / 'tool/run_dart_node.cjs'), artifact, '--samples=50', '--warmups=20', '--batch=8192']
    check(run['command'] == process['command'] == command, [identity, 'Node/launcher/compiled-artifact and sampling argv'])
    check(process['phase'] == 'benchmark_' + mode + '_' + label and process['cwd'] == str(root), [identity, 'phase/source cwd'])
    check(run['benchmark'] == 'interval_rounding', [identity, 'fixture identity'])
    check(run['started_at_utc'] == process['started_at_utc'] and run['finished_at_utc'] == process['finished_at_utc'], [identity, 'retained process timestamps'])
    check(instant(compiled['finished_at_utc']) <= instant(process['started_at_utc']), [identity, 'compiled before execution'])
    check(json.loads(process['stdout']) == run['result'], [identity, 'lossless stdout equals retained result'])
    report = run['result']
    check(report['schema'] == 'interval_rounding_v1' and report['check_only'] is False, [identity, 'normal primitive schema'])
    check((report['samples'], report['warmups']) == (50, 20), [identity, 'sampling metadata'])
    check(report['input_bits'] == input_words, [identity, 'exact input bits'])
    check([r['name'] for r in report['results']] == ['next_up', 'next_down'], [identity, 'two primitive directions'])
    for measurement in report['results']:
        name = measurement['name']
        samples, checksums = measurement['samples_us'], measurement['checksums']
        check(measurement['operations_per_batch'] == 8192 and len(samples) == len(checksums) == 50, [identity, name, 'batch and sample counts'])
        check(measurement['expected_checksum'] == expected_checksums[name], [identity, name, 'independent expected checksum'])
        for index, (duration, checksum) in enumerate(zip(samples, checksums)):
            check(type(duration) is int and duration >= 0, [identity, name, index, 'nonnegative integer timing'])
            check(checksum == expected_checksums[name], [identity, name, index, 'verified checksum'])
            counts['samples'] += 1
            counts['checksum_records'] += 1
        ordered = sorted(samples)
        values = {f'p{p}': ordered[math.ceil(len(samples) * p / 100) - 1] for p in (50, 95, 99)}
        for field in ('p50', 'p95'):
            check(values[field] == measurement[field], [identity, name, field, 'nearest-rank percentile'])
            counts['reported_percentiles'] += 1
        check((label, repeat) not in grouped[mode, name], [identity, name, 'unique distribution'])
        grouped[mode, name][label, repeat] = {'percentiles': values, 'samples': samples}
        counts['distributions'] += 1
    counts['process_reports'] += 1
check(counts['benchmark_processes'] == counts['process_reports'] == len(seen) == 12, 'all benchmark processes represented')
rows = []
for (mode, name), records in grouped.items():
    row = {'mode': mode, 'benchmark': 'interval_rounding', 'measurement': name, 'operations_per_batch': 8192}
    for field in ('p50', 'p95', 'p99'):
        before = [records['before', i]['percentiles'][field] for i in range(1, 4)]
        after = [records['after', i]['percentiles'][field] for i in range(1, 4)]
        b, a = statistics.median(before), statistics.median(after)
        pair_changes = [pct(x, y) for x, y in zip(before, after)]
        nonnull = [x for x in pair_changes if x is not None]
        row[field] = {'before_us': b, 'after_us': a, 'before_process_values': before, 'after_process_values': after,
            'aggregate_change_percent': pct(b, a), 'paired_change_percent': pair_changes,
            'median_paired_change_percent': statistics.median(nonnull) if nonnull else None,
            'faster_pairs': sum(y < x for x, y in zip(before, after)),
            'slower_pairs': sum(y > x for x, y in zip(before, after)),
            'equal_pairs': sum(y == x for x, y in zip(before, after))}
    all_samples = [v for record in records.values() for v in record['samples']]
    row['observed_timer_values_us'] = sorted(set(all_samples))
    row['zero_samples'] = sum(x == 0 for x in all_samples)
    rows.append(row)
vectors = {'method': 'Python arbitrary-precision whole-64-bit adjacency with IEEE special-value rules; NaNs use one canonical checksum token. These are independent reference vectors, not serialized benchmark outputs.',
    'input_bits': input_words, 'expected_output_bits': expected_vectors,
    'batch_operations': 8192, 'expected_checksums': expected_checksums}
args.vectors.write_text(json.dumps(vectors, indent=2) + '\n')
summary = {'source': args.raw.name, 'input_sha256': sha(blob), 'status': 'passed' if not findings else 'failed',
    'rounds': 3, 'samples': 50, 'warmups': 20,
    'method': 'Median of three process percentiles; nearest-rank p50 uses lower middle at even sample counts; p95 nearest rank; derived p99 is the maximum at 50 samples. No sample pooling or exclusion.',
    'rows': rows}
args.summary.write_text(json.dumps(summary, indent=2) + '\n')
report = {'status': 'passed' if not findings else 'failed', 'counts': dict(counts), 'findings': findings,
    'input_sha256': sha(blob), 'collector_sha256': raw['collector_sha256'],
    'revisions': {label: {k: identity[k] for k in ('commit', 'library_tree', 'resolved_root', 'resolved_library', 'harness_sha256', 'launcher_sha256')} for label, identity in raw['revisions'].items()},
    'artifact_comparisons': artifact_comparisons, 'changed_library_paths': changed,
    'runtime_binary_hashes': {k: raw[k] for k in ('dart', 'node')},
    'independent_expected_checksums': expected_checksums,
    'reference_vectors_sha256': sha(args.vectors.read_bytes()), 'summary_sha256': sha(args.summary.read_bytes()),
    'method': 'Independent source/package/runtime/stream hashes, phase/argv/compile-run linkage, input corpus, arbitrary-precision bit-adjacency checksum reconstruction, every retained checksum, nearest-rank percentile and pair direction. No project code imported; no Dart or Node workload.',
    'limitations': ['Generated artifacts were in a deleted temporary directory. Equal executable bytes are evidenced by recorded SHA-256 manifests and the reviewed collector rehashing artifacts before every execution; this audit cannot rehash the removed files.', 'Runtime/harness source was hashed and checked, but individual benchmark output vectors are not serialized. Exact per-output checks are established by reviewed harness validation and successful process completion; only their checksums are retained.', 'JS samples are entirely 0 or 1000 microseconds and every process median is zero, so these batches cannot resolve JS throughput changes.', 'The Wasm module and both executable support files have equal before/after recorded hashes. Its measured timing differences therefore do not demonstrate a generated-code change for this harness.', 'Only 64-entry primitive nextUp/nextDown batches under Node are covered. This is neither a browser benchmark nor complete CAD/solver latency or a portable speedup guarantee.', 'At 50 samples derived p99 is the process maximum and cannot support a reliable p99-tail estimate.']}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'status': report['status'], 'counts': dict(counts), 'findings': findings, 'checksums': expected_checksums}, indent=2))
for row in rows:
    print(json.dumps({k: v for k, v in row.items() if k != 'observed_timer_values_us'}))

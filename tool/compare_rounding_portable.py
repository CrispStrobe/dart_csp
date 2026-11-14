"""Sequential JS/Wasm rounding pairs with complete subprocess evidence."""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
for name in ('before', 'after', 'output'):
    parser.add_argument('--' + name, type=pathlib.Path, required=True)
parser.add_argument('--dart', required=True)
parser.add_argument('--node', default='node')
parser.add_argument('--rounds', type=int, default=3)
parser.add_argument('--samples', type=int, default=50)
parser.add_argument('--warmups', type=int, default=20)
parser.add_argument('--batch', type=int, default=8192)
parser.add_argument('--timeout', type=int, default=180)
args = parser.parse_args()
if min(args.rounds, args.samples, args.timeout) < 1 or args.warmups < 0 or args.batch < 64:
    parser.error('Positive rounds/samples/timeout, nonnegative warmups and batch >=64 required')
if args.output.exists():
    parser.error('Output already exists; choose a new path to preserve earlier evidence')
roots = {'before': args.before.resolve(), 'after': args.after.resolve()}
args.output.parent.mkdir(parents=True, exist_ok=True)
result = {'status': 'running', 'rounds': args.rounds, 'modes': ['js', 'wasm'],
          'platform': platform.platform(), 'revisions': {}, 'runs': [],
          'collector_sha256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
          'process_records': [], 'compiled_artifacts': [],
          'cpu_affinity': sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else None,
          'method': 'Fresh sequential Node processes, alternating before/after each round; '
                    'JS/Wasm -O2 compilation outside measurement, fixed identical harnesses. '
                    'Each timer measures a primitive batch including output writes; '
                    'ByteData oracles and checksums are checked outside timers. '
                    'All process output and acquisition-order samples retained; no pooling.'}


def save():
    temporary = args.output.with_name(args.output.name + '.tmp')
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.replace(args.output)


def fail(message):
    result.update(status='failed', failure=message)
    save()
    raise SystemExit(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, root, phase):
    entry = {'command': [str(x) for x in command], 'cwd': str(root), 'phase': phase,
             'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'timed_out': False}
    try:
        completed = subprocess.run(entry['command'], cwd=root, capture_output=True, timeout=args.timeout)
        out, err = completed.stdout, completed.stderr
        entry['exit_code'] = completed.returncode
    except subprocess.TimeoutExpired as error:
        out, err = error.stdout or b'', error.stderr or b''
        entry.update(exit_code=None, timed_out=True, error=str(error))
    except OSError as error:
        out, err = b'', b''
        entry.update(exit_code=None, error=str(error))
    entry.update(finished_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 stdout=out.decode('utf-8', 'surrogateescape'), stderr=err.decode('utf-8', 'surrogateescape'),
                 output_encoding='UTF-8 with surrogateescape; encode the same way to recover exact bytes',
                 stdout_sha256=hashlib.sha256(out).hexdigest(), stderr_sha256=hashlib.sha256(err).hexdigest())
    result['process_records'].append(entry)
    save()
    if entry['exit_code'] != 0:
        fail('Subprocess failed; exact output saved in process_records')
    return entry


def local_uri(uri):
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
        fail('Expected a local package URI: ' + uri)
    return pathlib.Path(urllib.request.url2pathname(parsed.path)).resolve()


def identity(root):
    def git(*arguments):
        return run(['git', *arguments], root, 'identity')['stdout'].strip()
    if git('status', '--porcelain', '--untracked-files=all', '--ignored=matching', '--', 'lib'):
        fail('Library must be clean and committed: ' + str(root))
    config = root / '.dart_tool/package_config.json'
    own = [p for p in json.loads(config.read_text())['packages'] if p['name'] == 'dart_csp']
    if len(own) != 1:
        fail('Expected exactly one dart_csp package in ' + str(config))
    package_root = local_uri(urllib.parse.urljoin(config.as_uri(), own[0]['rootUri']))
    library = local_uri(urllib.parse.urljoin(package_root.as_uri() + '/', own[0].get('packageUri', '')))
    if package_root != root or library != (root / 'lib').resolve():
        fail('Package mapping points outside the measured source tree: ' + str(config))
    return {'commit': git('rev-parse', 'HEAD'), 'library_tree': git('rev-parse', 'HEAD:lib'),
            'package_mapping': own[0], 'resolved_root': str(package_root), 'resolved_library': str(library),
            'package_config_sha256': digest(config), 'dependency_lock_sha256': digest(root / 'pubspec.lock'),
            'library_file_sha256': {str(p.relative_to(root)): digest(p)
                                    for p in sorted((root / 'lib').rglob('*')) if p.is_file()},
            'harness_sha256': digest(root / 'benchmark/interval_rounding.dart'),
            'launcher_sha256': digest(root / 'tool/run_dart_node.cjs')}


def check_source(label):
    if identity(roots[label]) != result['revisions'][label]:
        fail('Source, package mapping or harness changed during measurement: ' + label)


def check_report(report):
    if (report['schema'] != 'interval_rounding_v1' or report['check_only'] or
            report['samples'] != args.samples or report['warmups'] != args.warmups or
            len(report['input_bits']) != 64 or
            [row['name'] for row in report['results']] != ['next_up', 'next_down']):
        fail('Unexpected benchmark schema or sampling configuration')
    for row in report['results']:
        times = row['samples_us']
        if (row['operations_per_batch'] != args.batch or len(times) != args.samples or
                any(type(t) is not int or t < 0 for t in times) or
                row['checksums'] != [row['expected_checksum']] * args.samples):
            fail('Invalid batch samples or independent checksum evidence')
        for percentile in (50, 95):
            if row['p' + str(percentile)] != sorted(times)[(args.samples * percentile + 99) // 100 - 1]:
                fail('Reported percentile does not reconstruct from raw samples')
    work = {'input_bits': report['input_bits'],
            'expected_checksums': [row['expected_checksum'] for row in report['results']]}
    if work != result.setdefault('expected_work', work):
        fail('Input patterns or expected checksums differ across processes')


try:
    for label, root in roots.items():
        result['revisions'][label] = identity(root)
    for key in ('dependency_lock_sha256', 'harness_sha256', 'launcher_sha256'):
        if len({revision[key] for revision in result['revisions'].values()}) != 1:
            fail('Before/after identity mismatch: ' + key)
    for name in ('dart', 'node'):
        executable = shutil.which(getattr(args, name))
        if executable is None:
            fail('Executable not found: ' + name)
        setattr(args, name, str(pathlib.Path(executable).resolve()))
        version = run([getattr(args, name), '--version'], roots['before'], 'runtime_version')
        result[name] = {'executable': getattr(args, name), 'sha256': digest(pathlib.Path(getattr(args, name))),
                        'version': (version['stdout'] + version['stderr']).strip()}
    with tempfile.TemporaryDirectory(prefix='portable-rounding-') as directory:
        artifacts = {}
        for mode in result['modes']:
            for label, root in roots.items():
                check_source(label)
                folder = pathlib.Path(directory) / (mode + '-' + label)
                folder.mkdir()
                artifact = folder / ('rounding.' + mode)
                run([args.dart, 'compile', mode, '-O2', '--packages=' + str(root / '.dart_tool/package_config.json'),
                     'benchmark/interval_rounding.dart', '-o', artifact], root, 'compile_' + mode + '_' + label)
                files = {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob('*')) if p.is_file()}
                if mode == 'wasm' and 'rounding.mjs' not in files:
                    fail('Wasm runtime artifact is missing')
                result['compiled_artifacts'].append({'mode': mode, 'revision': label, 'files_sha256': files})
                artifacts[mode, label] = (artifact, files)
                check_source(label)
                save()
        for mode in result['modes']:
            for repeat in range(1, args.rounds + 1):
                for label in (('before', 'after') if repeat % 2 else ('after', 'before')):
                    root = roots[label]
                    check_source(label)
                    artifact, files = artifacts[mode, label]
                    if any(digest(artifact.parent / path) != expected for path, expected in files.items()):
                        fail('Compiled artifact changed before execution')
                    entry = run([args.node, root / 'tool/run_dart_node.cjs', artifact,
                                 f'--samples={args.samples}', f'--warmups={args.warmups}', f'--batch={args.batch}'],
                                root, 'benchmark_' + mode + '_' + label)
                    report = json.loads(entry['stdout'])
                    check_report(report)
                    result['runs'].append({'mode': mode, 'round': repeat, 'revision': label,
                                           'benchmark': 'interval_rounding', 'result': report,
                                           'process_record': len(result['process_records']) - 1,
                                           'command': entry['command'], 'started_at_utc': entry['started_at_utc'],
                                           'finished_at_utc': entry['finished_at_utc']})
                    save()
                    check_source(label)
                    print(f'{mode} round {repeat} {label}: saved', flush=True)
    result['status'] = 'complete'
    save()
except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
    fail(str(error))

"""Sequential paired revision benchmarks; raw harness output stays in JSON."""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import tempfile
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--before', type=pathlib.Path, required=True)
parser.add_argument('--after', type=pathlib.Path, required=True)
parser.add_argument('--dart', required=True)
parser.add_argument('--benchmarks', nargs='+', required=True)
parser.add_argument('--modes', nargs='+', choices=('jit', 'aot'), default=['jit', 'aot'],
                    help='Single-mode runs are diagnostic; final audits require both modes')
parser.add_argument('--rounds', type=int, default=3)
parser.add_argument('--samples', type=int,
                    help='Measured samples per case (default: 40 for cad_instances, 25 otherwise)')
parser.add_argument('--warmups', type=int, default=5)
parser.add_argument('--cumulative-durations', default='1000,3000')
parser.add_argument('--cad-graph-sizes', default='1000,10000')
parser.add_argument('--geometry-fork-components', default='100,1000')
parser.add_argument('--run-timeout', type=int, default=180)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
if args.rounds < 1 or (args.samples is not None and args.samples < 1) or args.warmups < 0 or args.run_timeout < 1:
    parser.error('rounds/samples/timeout must be positive and warmups nonnegative')
if len(set(args.modes)) != len(args.modes):
    parser.error('modes must not repeat')
args.output.parent.mkdir(parents=True, exist_ok=True)
roots = {'before': args.before.resolve(), 'after': args.after.resolve()}

def save():
    temporary = args.output.with_name(args.output.name + '.tmp')
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.replace(args.output)

def fail(message):
    result['status'] = 'failed'
    result['failure'] = message
    save()
    raise SystemExit(message)

def run(command, cwd, timeout=None, context=None):
    entry = {'command': [str(item) for item in command], 'cwd': str(cwd),
             'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'context': context, 'timed_out': False}
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True,
                                   timeout=timeout or args.run_timeout)
        stdout, stderr = completed.stdout, completed.stderr
        entry['exit_code'] = completed.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        entry.update(exit_code=None, timed_out=True, error=str(error))
    except OSError as error:
        stdout, stderr = b'', b''
        entry.update(exit_code=None, error=str(error))
    entry.update(
        finished_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        stdout=stdout.decode('utf-8', errors='surrogateescape'),
        stderr=stderr.decode('utf-8', errors='surrogateescape'),
        output_encoding='UTF-8 with surrogateescape; encode the same way to recover exact bytes',
        stdout_sha256=hashlib.sha256(stdout).hexdigest(),
        stderr_sha256=hashlib.sha256(stderr).hexdigest())
    result['process_records'].append(entry)
    save()
    if entry['exit_code'] != 0:
        result['failed_process_record'] = len(result['process_records']) - 1
        fail(f'{command!r} failed in {cwd}; complete process evidence saved')
    return entry['stdout'].strip(), entry['stderr'].strip()

def digest(path):
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        fail(f'Cannot read identity for {path}: {error}')

def local_uri(uri):
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
        fail('Package configuration must resolve to a local file URI: ' + uri)
    return pathlib.Path(urllib.request.url2pathname(parsed.path)).resolve()

def source_identity(root):
    dirty, _ = run(['git', 'status', '--porcelain', '--untracked-files=all',
                    '--ignored=matching', '--', 'lib'], root)
    if dirty:
        fail(f'Library must be clean and committed: {root}\n{dirty}')
    config = root / '.dart_tool/package_config.json'
    try:
        packages = json.loads(config.read_text())['packages']
        own = [package for package in packages if package['name'] == 'dart_csp']
        if len(own) != 1:
            fail('Package configuration must identify exactly one dart_csp package')
        package_root = local_uri(urllib.parse.urljoin(config.as_uri(), own[0]['rootUri']))
        library = local_uri(urllib.parse.urljoin(package_root.as_uri() + '/', own[0].get('packageUri', '')))
    except (OSError, ValueError, KeyError, TypeError) as error:
        fail(f'Invalid package configuration at {config}: {error}')
    if package_root != root or library != (root / 'lib').resolve():
        fail(f'Package configuration points at another source tree: {config} -> {library}')
    return {
        'dependency_lock_sha256': digest(root / 'pubspec.lock'),
        'package_config_sha256': digest(config),
        'package_mapping': {'file': str(config), 'dart_csp': own[0],
                            'resolved_root': str(package_root), 'resolved_library': str(library)},
        'library_file_sha256': {str(path.relative_to(root)): digest(path)
                                for path in sorted((root / 'lib').rglob('*')) if path.is_file()},
    }

def check_source(label):
    if source_identity(roots[label]) != identities[label]:
        fail('Source or package configuration changed during comparison: ' + label)
    for relative, expected in harness_files.items():
        if digest(roots[label] / relative) != expected:
            fail('Harness changed during comparison: ' + label + '/' + relative)

def hardware():
    info = {'execution': 'Shared container with inherited CPU affinity'}
    try:
        cpu = pathlib.Path('/proc/cpuinfo').read_text()
        info['cpu_model'] = next(line.split(':', 1)[1].strip()
                                 for line in cpu.splitlines()
                                 if line.startswith('model name'))
    except (OSError, StopIteration):
        info['cpu_model'] = platform.processor() or 'unavailable'
    if hasattr(os, 'sched_getaffinity'):
        info['cpu_affinity'] = sorted(os.sched_getaffinity(0))
        info['available_logical_cpus'] = len(info['cpu_affinity'])
    return info

result = {
    'runtime': None,
    'platform': platform.platform(),
    'hardware': hardware(),
    'method': 'Three fresh processes per revision and runtime by default. Runs are sequential, with revision order alternated each round. AOT compilation is outside measured sections. CAD/geometry and cumulative cold/range paths exclude independent checks from timing; matching/GCC and cumulative prepared batches include bounded solution assertions. Sampling flags apply to matching, GCC, cumulative, geometry_qr, geometry_small_qr, geometry_fork, cad_graph, cad_linkage, cad_instances, cad and incremental_assumptions; other CAD/geometry harnesses retain their documented counts. Each entry is a separate harness run; percentiles are not pooled across runs. Incremental and small-QR timings are operation batches; consult each row operations_per_batch. Incremental batches include result retention and search-stat snapshots; independent checks and aggregation are outside timers.',
    'rounds': args.rounds,
    'modes': args.modes,
    'diagnostic_only': set(args.modes) != {'jit', 'aot'},
    'status': 'running',
    'revisions': {},
    'harnesses': {},
    'runs': [],
    'process_records': [],
}
result['runtime'] = ' '.join(run([args.dart, '--version'], args.before))
identities = {}
harness_files = {}
for label, root in roots.items():
    identities[label] = source_identity(root)
    head, _ = run(['git', 'rev-parse', 'HEAD'], root)
    diff, _ = run(['git', 'diff', '--binary', 'HEAD', '--', 'lib'], root)
    result['revisions'][label] = {
        'commit': head,
        'library_tree': run(['git', 'rev-parse', 'HEAD:lib'], root)[0],
        'library_diff_sha256': hashlib.sha256(diff.encode()).hexdigest() if diff else None,
        **identities[label],
    }
if len({revision['dependency_lock_sha256'] for revision in result['revisions'].values()}) != 1:
    fail('Dependency locks differ between source revisions')
for name in args.benchmarks:
    relative = pathlib.Path('benchmark') / (name + '.dart')
    before_hash, after_hash = [digest(root / relative) for root in roots.values()]
    if before_hash != after_hash:
        fail('Harness differs: ' + name)
    result['harnesses'][name] = {'file': str(relative), 'sha256': before_hash}
    harness_files[str(relative)] = before_hash
    dependencies = {
        'cad': ['example/parametric_bracket.dart'],
        'cad_instances': ['example/parametric_assembly.dart'],
        'cad_linkage': ['example/parametric_linkage.dart',
                        'example/nonlinear_linkage.dart'],
        'geometry_nonlinear': ['example/nonlinear_linkage.dart'],
    }
    for dependency in dependencies.get(name, []):
        hashes = [digest(root / dependency) for root in roots.values()]
        if hashes[0] != hashes[1]:
            fail('Benchmark dependency differs: ' + dependency)
        result['harnesses'][name].setdefault('dependency_sha256', {})[dependency] = hashes[0]
        harness_files[dependency] = hashes[0]
    if name in ('matching', 'gcc', 'cumulative'):
        hashes = [digest(root / 'benchmark/sampling.dart') for root in roots.values()]
        if hashes[0] != hashes[1]:
            fail('Sampling helper differs')
        result['harnesses'][name]['sampling_helper_sha256'] = hashes[0]
        harness_files['benchmark/sampling.dart'] = hashes[0]
save()

with tempfile.TemporaryDirectory(prefix='paired-benchmark-') as directory:
    executables = {}
    for name in args.benchmarks if 'aot' in args.modes else []:
        for label, root in roots.items():
            check_source(label)
            binary = str(pathlib.Path(directory) / (name + '-' + label))
            run([args.dart, 'compile', 'exe', '--packages=' + str(root / '.dart_tool/package_config.json'),
                 'benchmark/' + name + '.dart', '-o', binary], root,
                context={'phase': 'compile', 'benchmark': name, 'revision': label})
            check_source(label)
            executables[name, label] = binary
        print('compiled ' + name, flush=True)
    for mode in args.modes:
        for repeat in range(args.rounds):
            labels = ('before', 'after') if repeat % 2 == 0 else ('after', 'before')
            for name in args.benchmarks:
                samples = args.samples if args.samples is not None else (40 if name == 'cad_instances' else 25)
                extra = ([f'--samples={samples}', f'--warmups={args.warmups}']
                         if name in ('matching', 'gcc', 'cumulative', 'geometry_qr',
                                     'geometry_small_qr', 'geometry_fork',
                                     'cad_graph', 'cad_linkage', 'cad_instances', 'cad',
                                     'incremental_assumptions') else [])
                if name == 'cumulative':
                    extra.append('--durations=' + args.cumulative_durations)
                if name == 'cad_graph':
                    extra.append('--sizes=' + args.cad_graph_sizes)
                if name == 'geometry_fork':
                    extra.append('--components=' + args.geometry_fork_components)
                for label in labels:
                    check_source(label)
                    command = ([args.dart, '--packages=' + str(roots[label] / '.dart_tool/package_config.json'),
                                'benchmark/' + name + '.dart']
                               if mode == 'jit' else [executables[name, label]]) + extra
                    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    stdout, stderr = run(command, roots[label], context={
                        'phase': 'benchmark', 'mode': mode, 'round': repeat + 1,
                        'benchmark': name, 'revision': label})
                    try:
                        output = json.loads(stdout)
                    except json.JSONDecodeError:
                        output = {'output_lines': stdout.splitlines()}
                    entry = {'mode': mode, 'round': repeat + 1, 'benchmark': name,
                             'revision': label, 'arguments': extra, 'result': output,
                             'process_record': len(result['process_records']) - 1,
                             'command': command, 'started_at_utc': started,
                             'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
                    if stderr:
                        entry['stderr'] = stderr
                    result['runs'].append(entry)
                    save()
                    print(mode + ' ' + str(repeat + 1) + ' ' + name + ' ' + label + ': saved', flush=True)
for label in roots:
    check_source(label)
result['status'] = 'completed'
save()

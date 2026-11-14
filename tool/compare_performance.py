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

parser = argparse.ArgumentParser()
parser.add_argument('--before', type=pathlib.Path, required=True)
parser.add_argument('--after', type=pathlib.Path, required=True)
parser.add_argument('--dart', required=True)
parser.add_argument('--benchmarks', nargs='+', required=True)
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
if args.rounds < 1 or (args.samples is not None and args.samples < 1) or args.warmups < 0:
    parser.error('rounds/samples must be positive and warmups nonnegative')
args.output.parent.mkdir(parents=True, exist_ok=True)
roots = {'before': args.before.resolve(), 'after': args.after.resolve()}

def run(command, cwd, timeout=None):
    completed = subprocess.run(command, cwd=cwd, capture_output=True,
                               text=True, timeout=timeout or args.run_timeout)
    if completed.returncode:
        raise RuntimeError(f'{command!r} failed in {cwd}:\n'
                           f'{completed.stdout}\n{completed.stderr}')
    return completed.stdout.strip(), completed.stderr.strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hardware():
    info = {'execution': 'Shared unpinned container'}
    try:
        cpu = pathlib.Path('/proc/cpuinfo').read_text()
        info['cpu_model'] = next(line.split(':', 1)[1].strip()
                                 for line in cpu.splitlines()
                                 if line.startswith('model name'))
    except (OSError, StopIteration):
        info['cpu_model'] = platform.processor() or 'unavailable'
    if hasattr(os, 'sched_getaffinity'):
        info['available_logical_cpus'] = len(os.sched_getaffinity(0))
    return info

result = {
    'runtime': ' '.join(run([args.dart, '--version'], args.before)),
    'platform': platform.platform(),
    'hardware': hardware(),
    'method': 'Three fresh processes per revision and runtime by default. Runs are sequential, with revision order alternated each round. AOT compilation is outside measured sections. CAD/geometry and cumulative cold/range paths exclude independent checks from timing; matching/GCC and cumulative prepared batches include bounded solution assertions. Sampling flags apply to matching, GCC, cumulative, geometry_qr, geometry_small_qr, geometry_fork, cad_graph, cad_linkage, cad_instances, cad and incremental_assumptions; other CAD/geometry harnesses retain their documented counts. Each entry is a separate harness run; percentiles are not pooled across runs. Incremental and small-QR timings are operation batches; consult each row operations_per_batch. Incremental batches include result retention and search-stat snapshots; independent checks and aggregation are outside timers.',
    'rounds': args.rounds,
    'revisions': {},
    'harnesses': {},
    'runs': [],
}
for label, root in roots.items():
    head, _ = run(['git', 'rev-parse', 'HEAD'], root)
    diff, _ = run(['git', 'diff', '--binary', 'HEAD', '--', 'lib'], root)
    result['revisions'][label] = {
        'commit': head,
        'library_tree': run(['git', 'rev-parse', 'HEAD:lib'], root)[0],
        'dependency_lock_sha256': digest(root / 'pubspec.lock'),
        'library_diff_sha256': hashlib.sha256(diff.encode()).hexdigest() if diff else None,
    }
if len({revision['dependency_lock_sha256'] for revision in result['revisions'].values()}) != 1:
    raise SystemExit('Dependency locks differ between source revisions')
for name in args.benchmarks:
    relative = pathlib.Path('benchmark') / (name + '.dart')
    before_hash, after_hash = [digest(root / relative) for root in roots.values()]
    if before_hash != after_hash:
        raise SystemExit('Harness differs: ' + name)
    result['harnesses'][name] = {'file': str(relative), 'sha256': before_hash}
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
            raise SystemExit('Benchmark dependency differs: ' + dependency)
        result['harnesses'][name].setdefault('dependency_sha256', {})[dependency] = hashes[0]
    if name in ('matching', 'gcc', 'cumulative'):
        hashes = [digest(root / 'benchmark/sampling.dart') for root in roots.values()]
        if hashes[0] != hashes[1]:
            raise SystemExit('Sampling helper differs')
        result['harnesses'][name]['sampling_helper_sha256'] = hashes[0]

def save():
    temporary = args.output.with_name(args.output.name + '.tmp')
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.replace(args.output)

with tempfile.TemporaryDirectory(prefix='paired-benchmark-') as directory:
    executables = {}
    for name in args.benchmarks:
        for label, root in roots.items():
            binary = str(pathlib.Path(directory) / (name + '-' + label))
            run([args.dart, 'compile', 'exe', 'benchmark/' + name + '.dart', '-o', binary], root)
            executables[name, label] = binary
        print('compiled ' + name, flush=True)
    for mode in ('jit', 'aot'):
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
                    command = ([args.dart, 'run', 'benchmark/' + name + '.dart']
                               if mode == 'jit' else [executables[name, label]]) + extra
                    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    stdout, stderr = run(command, roots[label])
                    try:
                        output = json.loads(stdout)
                    except json.JSONDecodeError:
                        output = {'output_lines': stdout.splitlines()}
                    entry = {'mode': mode, 'round': repeat + 1, 'benchmark': name,
                             'revision': label, 'arguments': extra, 'result': output,
                             'command': command, 'started_at_utc': started,
                             'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
                    if stderr:
                        entry['stderr'] = stderr
                    result['runs'].append(entry)
                    save()
                    print(mode + ' ' + str(repeat + 1) + ' ' + name + ' ' + label + ': saved', flush=True)

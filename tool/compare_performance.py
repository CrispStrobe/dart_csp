"""Sequential paired revision benchmarks; raw harness output stays in JSON."""
import argparse
import hashlib
import json
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
parser.add_argument('--samples', type=int, default=25)
parser.add_argument('--warmups', type=int, default=5)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
if args.rounds < 1 or args.samples < 1 or args.warmups < 0:
    parser.error('rounds/samples must be positive and warmups nonnegative')
args.output.parent.mkdir(parents=True, exist_ok=True)
roots = {'before': args.before.resolve(), 'after': args.after.resolve()}

def run(command, cwd, timeout=90):
    completed = subprocess.run(command, cwd=cwd, capture_output=True,
                               text=True, timeout=timeout)
    if completed.returncode:
        raise RuntimeError(f'{command!r} failed in {cwd}:\n'
                           f'{completed.stdout}\n{completed.stderr}')
    return completed.stdout.strip(), completed.stderr.strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

result = {
    'runtime': ' '.join(run([args.dart, '--version'], args.before)),
    'platform': platform.platform(),
    'hardware': 'Shared unpinned Linux x64 container; reported AMD EPYC 9V74.',
    'method': 'Three fresh processes per revision and runtime by default. Runs are sequential, with revision order alternated each round. AOT compilation is outside measured sections. CAD/geometry exclude independent checks from timing; matching/GCC include bounded solution assertions in each query batch. Each entry is a separate harness run; percentiles are not pooled across runs.',
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
        'library_diff_sha256': hashlib.sha256(diff.encode()).hexdigest() if diff else None,
    }
for name in args.benchmarks:
    relative = pathlib.Path('benchmark') / (name + '.dart')
    before_hash, after_hash = [digest(root / relative) for root in roots.values()]
    if before_hash != after_hash:
        raise SystemExit('Harness differs: ' + name)
    result['harnesses'][name] = {'file': str(relative), 'sha256': before_hash}
    if name in ('matching', 'gcc'):
        hashes = [digest(root / 'benchmark/sampling.dart') for root in roots.values()]
        if hashes[0] != hashes[1]:
            raise SystemExit('Sampling helper differs')
        result['harnesses'][name]['sampling_helper_sha256'] = hashes[0]

def save():
    args.output.write_text(json.dumps(result, indent=2) + '\n')

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
                extra = ([f'--samples={args.samples}', f'--warmups={args.warmups}']
                         if name in ('matching', 'gcc') else [])
                for label in labels:
                    command = ([args.dart, 'run', 'benchmark/' + name + '.dart']
                               if mode == 'jit' else [executables[name, label]]) + extra
                    stdout, stderr = run(command, roots[label])
                    try:
                        output = json.loads(stdout)
                    except json.JSONDecodeError:
                        output = {'output_lines': stdout.splitlines()}
                    entry = {'mode': mode, 'round': repeat + 1, 'benchmark': name,
                             'revision': label, 'arguments': extra, 'result': output}
                    if stderr:
                        entry['stderr'] = stderr
                    result['runs'].append(entry)
                    save()
                    print(mode + ' ' + str(repeat + 1) + ' ' + name + ' ' + label + ': ' + stdout, flush=True)

"""Bounded AOT QR A/A and historical paired controls; prepare never runs timings.

Use prepare once, then run only when timing execution is authorized. The original
geometry_small_qr.dart stays byte-identical and checks every result outside its
timers. rank_5x4 is already its first case. No library or harness edits are made.
"""

import argparse
import datetime
import gzip
import hashlib
import io
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tarfile
import urllib.parse


HARNESS = 'benchmark/geometry_small_qr.dart'
COMMITS = {
    'before': 'd43a8b0fca74c6bc893d68ca6ec8190e74b423c9',
    'after': '4325386e689566a903309accd66aca3ced1159f7',
}
CASES = ['rank_5x4', 'rank_8x4', 'rank_4x5', 'rank_4x8', 'rank_9x4',
         'rank_12x4', 'rank_16x8', 'rank_16x9', 'rank_17x8', 'rank_48x48',
         'damped_solve_8x4', 'nullspace_4x8']
WARMUPS, SAMPLES = 2000, 101


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, data):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def pin(cpu):
    allowed = sorted(os.sched_getaffinity(0))
    require(cpu in allowed, f'CPU {cpu} is not in allowed affinity {allowed}')
    os.sched_setaffinity(0, {cpu})
    return allowed


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def source(root):
    config = root / '.dart_tool/package_config.json'
    mapping = [p for p in json.loads(config.read_text())['packages'] if p['name'] == 'dart_csp']
    require(len(mapping) == 1, 'Expected one dart_csp package mapping')
    resolved = urllib.parse.urlparse(urllib.parse.urljoin(config.as_uri(), mapping[0]['rootUri']))
    require(resolved.scheme == 'file' and not resolved.netloc
            and Path(urllib.parse.unquote(resolved.path)).resolve() == root,
            f'Effective package root does not match {root}')
    require(mapping[0].get('packageUri') == 'lib/', 'Unexpected package library URI')
    dirty = git(root, 'status', '--porcelain', '--untracked-files=all',
                '--ignored=matching', '--', 'lib', HARNESS)
    require(not dirty, f'Library/harness must remain clean: {root}: {dirty}')
    paths = sorted([p for p in (root / 'lib').rglob('*') if p.is_file()]
                   + [root / HARNESS, root / 'pubspec.yaml', root / 'pubspec.lock', config])
    require(all(not p.is_symlink() for p in paths), 'Source snapshots require regular files')
    content = {p.relative_to(root).as_posix(): p.read_bytes() for p in paths}
    return dict(root=str(root), commit=git(root, 'rev-parse', 'HEAD'),
                library_tree=git(root, 'rev-parse', 'HEAD:lib'), source_status=dirty,
                package_mapping=mapping[0],
                files={name: {'bytes': len(data), 'sha256': sha(data)}
                       for name, data in content.items()}), content


def archive_source(path, files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for name, data in sorted(files.items()):
            member = tarfile.TarInfo(name)
            member.mode, member.size = 0o644, len(data)
            archive.addfile(member, io.BytesIO(data))
    path.write_bytes(gzip.compress(buffer.getvalue(), mtime=0))


def process(command, cwd, directory, timeout):
    record = dict(command=list(map(str, command)), cwd=str(cwd), started_utc=now(),
                  timeout_seconds=timeout, affinity=sorted(os.sched_getaffinity(0)),
                  environment={k: os.environ.get(k) for k in ('PUB_CACHE', 'TMPDIR', 'PATH')})
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=timeout)
        stdout, stderr = result.stdout, result.stderr
        record.update(exit_code=result.returncode, timed_out=False)
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        record.update(exit_code=None, timed_out=True)
    except OSError as error:
        stdout, stderr = b'', str(error).encode()
        record.update(exit_code=None, timed_out=False, launch_error=str(error))
    (directory / 'stdout.json').write_bytes(stdout)
    (directory / 'stderr.log').write_bytes(stderr)
    record.update(finished_utc=now(), stdout='stdout.json', stderr='stderr.log',
                  stdout_sha256=sha(stdout), stderr_sha256=sha(stderr),
                  stdout_bytes=len(stdout), stderr_bytes=len(stderr))
    save(directory / 'process.json', record)
    return record, stdout


def schedule(include_fused=False):
    jobs = []
    # Each comparison gets ABBA then BAAB: four adjacent pairs, with each
    # label first twice. Interleave comparison blocks to spread host drift.
    for block, order in enumerate((('a', 'b', 'b', 'a'), ('b', 'a', 'a', 'b'))):
        comparisons = ['historical', 'same_binary_aa']
        if include_fused:
            comparisons.append('packed_to_fused')
        for comparison in comparisons:
            for position, label in enumerate(order):
                if comparison == 'historical':
                    variant = 'before' if label == 'a' else 'after'
                elif comparison == 'packed_to_fused':
                    variant = 'after' if label == 'a' else 'fused'
                else:
                    variant = 'after'
                jobs.append(dict(index=len(jobs), comparison=comparison, label=label,
                                 variant=variant, block=block + 1,
                                 round=block * 2 + position // 2 + 1,
                                 within_pair=position % 2 + 1))
    return jobs


def prepare(args):
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    allowed = pin(args.cpu)
    dart = args.dart.resolve(strict=True)
    report = dict(schema_version=1, status='preparing', started_utc=now(),
                  purpose=__doc__, invocation=[sys.executable, *sys.argv],
                  compiler_cpu=args.cpu, allowed_cpus=allowed,
                  runner_sha256=sha(Path(__file__).read_bytes()),
                  dart={'path': str(dart), 'sha256': sha(dart.read_bytes())},
                  warmup_batches=WARMUPS, measured_batches=SAMPLES,
                  cases=CASES, first_position_case=CASES[0],
                  harness_modified=False, timings_executed=False,
                  schedule=schedule(), variants={})
    manifest = out / 'prepared.json'
    (out / 'preparation-runner.py').write_bytes(Path(__file__).read_bytes())
    save(manifest, report)
    version_dir = out / 'sdk-version'
    version_dir.mkdir()
    record, stdout = process([str(dart), '--version'], out, version_dir, 30)
    require(record['exit_code'] == 0, 'Dart version check failed')
    report['dart'].update(version=stdout.decode().strip(), version_record=record)
    for label, root in [('before', args.before.resolve()), ('after', args.after.resolve())]:
        identity, files = source(root)
        require(identity['commit'] == COMMITS[label], f'Unexpected {label} revision')
        if report['variants']:
            prior = report['variants']['before']['source']['files']
            for name in (HARNESS, 'pubspec.lock'):
                require(identity['files'][name] == prior[name], f'Paired input differs: {name}')
        target = out / label
        target.mkdir()
        archive_source(target / 'source.tar.gz', files)
        executable = target / 'geometry-small-qr'
        command = [str(dart), 'compile', 'exe', '--packages=' + str(root / '.dart_tool/package_config.json'),
                   str(root / HARNESS), '-o', str(executable)]
        item = dict(source=identity, source_archive=f'{label}/source.tar.gz',
                    source_archive_sha256=sha((target / 'source.tar.gz').read_bytes()),
                    executable=str(executable), build_command=command)
        report['variants'][label] = item
        save(manifest, report)
        item['build'], _ = process(command, root, target, 300)
        save(manifest, report)
        require(item['build']['exit_code'] == 0, f'{label} AOT compilation failed')
        require(source(root)[0] == identity, f'{label} source changed during compilation')
        item['executable_sha256'] = sha(executable.read_bytes())
        item['executable_bytes'] = executable.stat().st_size
        save(manifest, report)
    report.update(status='prepared', finished_utc=now())
    save(manifest, report)
    print(json.dumps({'prepared': str(manifest), 'timings_executed': False,
                      'executable_sha256': {k: v['executable_sha256']
                                            for k, v in report['variants'].items()}}, indent=2))


def add_candidate(args):
    out = args.prepared.resolve()
    manifest = out / 'prepared.json'
    original = manifest.read_bytes()
    report = json.loads(original)
    require(report['status'] == 'prepared' and 'fused' not in report['variants'],
            'Expected completed historical preparation without a fused candidate')
    require(sha((out / 'preparation-runner.py').read_bytes()) == report['runner_sha256'],
            'Original preparation runner is missing or changed')
    require(not (out / 'prepared.before-fused.json').exists(), 'Fused preparation already started')
    pin(args.cpu)
    root = args.source.resolve()
    identity, files = source(root)
    require(identity['commit'] == args.commit, 'Candidate checkout does not match requested frozen commit')
    for name in (HARNESS, 'pubspec.lock'):
        require(identity['files'][name] == report['variants']['after']['source']['files'][name],
                f'Candidate must preserve paired input: {name}')
    dart = Path(report['dart']['path'])
    require(sha(dart.read_bytes()) == report['dart']['sha256'], 'Compiler changed')
    (out / 'prepared.before-fused.json').write_bytes(original)
    (out / 'fused-preparation-runner.py').write_bytes(Path(__file__).read_bytes())
    target = out / 'fused'
    target.mkdir()
    archive_source(target / 'source.tar.gz', files)
    executable = target / 'geometry-small-qr'
    command = [str(dart), 'compile', 'exe', '--packages=' + str(root / '.dart_tool/package_config.json'),
               str(root / HARNESS), '-o', str(executable)]
    item = dict(source=identity, source_archive='fused/source.tar.gz',
                source_archive_sha256=sha((target / 'source.tar.gz').read_bytes()),
                executable=str(executable), build_command=command,
                preparation_command=[sys.executable, *sys.argv],
                preparation_runner_sha256=sha(Path(__file__).read_bytes()))
    report['variants']['fused'] = item
    report['status'] = 'preparing-fused'
    save(manifest, report)
    item['build'], _ = process(command, root, target, 300)
    save(manifest, report)
    require(item['build']['exit_code'] == 0, 'Fused AOT compilation failed')
    require(source(root)[0] == identity, 'Fused source changed during compilation')
    item['executable_sha256'] = sha(executable.read_bytes())
    item['executable_bytes'] = executable.stat().st_size
    report.update(status='prepared', schedule=schedule(include_fused=True), finished_utc=now())
    save(manifest, report)
    print(json.dumps({'prepared': str(manifest), 'timings_executed': False,
                      'fused_executable_sha256': item['executable_sha256'],
                      'planned_processes': len(report['schedule'])}, indent=2))


def validate_output(raw):
    result = json.loads(raw)
    require(result['independent_checks'] == 'passed' and result['warmups'] == WARMUPS
            and result['samples'] == SAMPLES and result['units'] == 'microseconds_per_batch',
            'Incorrect harness validation or sampling policy')
    require([row['name'] for row in result['results']] == CASES, 'Missing/reordered QR cases')
    for row in result['results']:
        samples = row['samples_us']
        require(len(samples) == SAMPLES and all(type(x) is int and x > 0 for x in samples),
                'Invalid or partial timing samples')
        require(row['operations_per_batch'] == (8 if row['name'] == 'rank_48x48' else 256),
                'Unexpected operation batch size')
        ordered = sorted(samples)
        for name, fraction in [('p50', .5), ('p95', .95)]:
            require(row[name] == ordered[math.ceil((SAMPLES - 1) * fraction)],
                    f'Incorrect {name} in {row["name"]}')
    return result


def summarize(jobs):
    rows = []
    for comparison in dict.fromkeys(job['comparison'] for job in jobs):
        for case in CASES:
            processes = []
            for job in jobs:
                if job['comparison'] != comparison:
                    continue
                result = next(r for r in job['result']['results'] if r['name'] == case)
                ordered = sorted(result['samples_us'])
                processes.append(dict(round=job['round'], label=job['label'], index=job['index'],
                                      executable_sha256=job['executable_sha256'],
                                      **{name: ordered[math.ceil((SAMPLES - 1) * p)]
                                         for name, p in [('p50', .5), ('p95', .95), ('p99', .99)]}))
            metrics = {}
            for metric in ('p50', 'p95', 'p99'):
                a = [p[metric] for p in processes if p['label'] == 'a']
                b = [p[metric] for p in processes if p['label'] == 'b']
                pairs = []
                for repeat in range(1, 5):
                    pair = {p['label']: p[metric] for p in processes if p['round'] == repeat}
                    pairs.append(dict(round=repeat, a=pair['a'], b=pair['b'], b_over_a=pair['b'] / pair['a']))
                metrics[metric] = dict(a_process_median=statistics.median(a),
                                       b_process_median=statistics.median(b),
                                       b_over_a=statistics.median(b) / statistics.median(a),
                                       pairs=pairs)
            rows.append(dict(comparison=comparison, case=case, units='microseconds_per_batch',
                             operations_per_batch=8 if case == 'rank_48x48' else 256,
                             processes=processes, metrics=metrics))
    return dict(rows=rows, note='Four process pairs per comparison; process percentiles are not pooled. '
                               'A/A uses the exact same packed executable. No timing outliers are discarded. '
                               'This bounded negative control does not prove the cause of elapsed-time differences.')


def run(args):
    prepared_path = args.prepared.resolve() / 'prepared.json'
    prepared_bytes = prepared_path.read_bytes()
    prepared = json.loads(prepared_bytes)
    require(prepared['status'] == 'prepared', 'Preparation is incomplete')
    require(prepared['runner_sha256'] == sha((prepared_path.parent / 'preparation-runner.py').read_bytes()),
            'Original preparation runner is missing or changed')
    allowed = pin(args.cpu)
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = dict(schema_version=1, status='running', started_utc=now(),
                  invocation=[sys.executable, *sys.argv], prepared=str(prepared_path),
                  prepared_sha256=sha(prepared_bytes), cpu=args.cpu, allowed_cpus=allowed,
                  run_runner_sha256=sha(Path(__file__).read_bytes()),
                  warmup_batches=WARMUPS, measured_batches=SAMPLES, schedule=prepared['schedule'], jobs=[])
    (out / 'run-runner.py').write_bytes(Path(__file__).read_bytes())
    manifest = out / 'run.json'
    save(manifest, report)
    try:
        for planned in prepared['schedule']:
            item = prepared['variants'][planned['variant']]
            root = Path(item['source']['root'])
            binary = Path(item['executable'])
            require(source(root)[0] == item['source'], 'Prepared source identity changed')
            require(sha(binary.read_bytes()) == item['executable_sha256'], 'Prepared executable changed')
            target = out / f'{planned["index"]:02d}-{planned["comparison"]}-r{planned["round"]}-{planned["label"]}'
            target.mkdir()
            job = dict(planned, directory=target.name, executable_sha256=item['executable_sha256'])
            report['in_progress'] = job
            save(manifest, report)
            job['process'], raw = process([str(binary), f'--warmups={WARMUPS}', f'--samples={SAMPLES}'],
                                           root, target, args.timeout)
            report['jobs'].append(job)
            report.pop('in_progress', None)
            save(manifest, report)
            require(job['process']['exit_code'] == 0, 'QR benchmark process failed; raw output preserved')
            job['result'] = validate_output(raw)
            require(source(root)[0] == item['source'], 'Source changed during QR execution')
            require(sha(binary.read_bytes()) == item['executable_sha256'], 'Executable changed during QR execution')
            save(manifest, report)
            print(json.dumps({k: job[k] for k in ('index', 'comparison', 'round', 'label')}
                             | {'validated_cases': len(job['result']['results'])}), flush=True)
        require(len(report['jobs']) == len(prepared['schedule']), 'Incomplete planned process inventory')
        report.update(status='complete', finished_utc=now())
        save(out / 'summary.json', summarize(report['jobs']))
    except Exception as error:
        report.update(status='failed', failure=str(error), finished_utc=now())
        raise
    finally:
        save(manifest, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prep = commands.add_parser('prepare')
    prep.add_argument('--before', type=Path, required=True)
    prep.add_argument('--after', type=Path, required=True)
    prep.add_argument('--dart', type=Path, required=True)
    prep.add_argument('--output', type=Path, required=True)
    prep.add_argument('--cpu', type=int, default=8)
    candidate = commands.add_parser('add-candidate')
    candidate.add_argument('--prepared', type=Path, required=True)
    candidate.add_argument('--source', type=Path, required=True)
    candidate.add_argument('--commit', required=True)
    candidate.add_argument('--cpu', type=int, default=8)
    execute = commands.add_parser('run')
    execute.add_argument('--prepared', type=Path, required=True)
    execute.add_argument('--output', type=Path, required=True)
    execute.add_argument('--cpu', type=int, default=0)
    execute.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    {'prepare': prepare, 'add-candidate': add_candidate, 'run': run}[args.command](args)


if __name__ == '__main__':
    main()

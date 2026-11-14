#!/usr/bin/env python3
"""Freeze two pure-Dart AOT adapters, then compare bounded physical operations.

Preparation never measures a solver. Run mode never compiles. Every completed
job retains the existing runner's exact request/stdout/stderr and checked records.
"""
from __future__ import annotations

import argparse
import datetime
import gzip
import hashlib
import io
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile

from analyze import analyze_runs, write_report
from fixtures import corpus, request
from run import run_job

HERE = Path(__file__).resolve().parent
ADAPTERS = ('benchmark/solver_comparison/dart_adapter.dart',
            'benchmark/solver_comparison/dart_adapter_core.dart')
HARNESSES = ('paired_dart_backends.py', 'run.py', 'oracle.py', 'fixtures.py', 'analyze.py')
ENGINES = ('dart_3d_ad', 'dart_2d_ad', 'dart_2d_analytic')
SUITES = ('smoke', 'screen', 'confirm', 'boundaries', 'coupled')


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha(path: Path) -> str:
    return digest(path.read_bytes())


def dump(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def snapshot(root: Path) -> tuple[dict, dict[str, bytes]]:
    """Snapshot tracked source and the actual package-resolution inputs."""
    frozen_paths = ['lib', 'test', *ADAPTERS, 'pubspec.yaml']
    if git(root, 'diff', '--name-only', 'HEAD', '--', *frozen_paths):
        raise ValueError(f'Commit source changes before preparation: {root}')
    if git(root, 'ls-files', '--others', '--exclude-standard', '--', *frozen_paths):
        raise ValueError(f'Untracked source cannot be omitted from the snapshot: {root}')
    names = git(root, 'ls-files', '--', *frozen_paths).splitlines()
    names += ['pubspec.lock', '.dart_tool/package_config.json']
    files = {}
    for name in sorted(set(names)):
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Missing source/package input or unsupported symlink: {path}')
        files[name] = path.read_bytes()
    package = json.loads(files['.dart_tool/package_config.json'])
    own = next(p for p in package['packages'] if p['name'] == 'dart_csp')
    from urllib.parse import unquote, urljoin, urlparse
    location = urlparse(urljoin((root / '.dart_tool/package_config.json').as_uri(), own['rootUri']))
    if location.scheme != 'file' or Path(unquote(location.path)).resolve() != root:
        raise ValueError(f'Package dart_csp resolves outside its requested worktree: {root}')
    return dict(root=str(root), source_commit=git(root, 'rev-parse', 'HEAD'),
                source_tree=git(root, 'rev-parse', 'HEAD^{tree}'),
                library_tree=git(root, 'rev-parse', 'HEAD:lib'),
                test_tree=git(root, 'rev-parse', 'HEAD:test'),
                source_status=git(root, 'status', '--porcelain'),
                source_sha256={name: digest(data) for name, data in files.items()}), files


def require_identical_adapters(before: dict, after: dict) -> None:
    for name in (*ADAPTERS, 'pubspec.yaml', 'pubspec.lock'):
        if before['source_sha256'][name] != after['source_sha256'][name]:
            raise ValueError(f'Paired adapters/package inputs differ: {name}')


def archive_source(path: Path, files: dict[str, bytes]) -> None:
    with path.open('wb') as output:
        with gzip.GzipFile(fileobj=output, mode='wb', mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w') as archive:
                for name, data in sorted(files.items()):
                    member = tarfile.TarInfo(name)
                    member.size, member.mode = len(data), 0o644
                    archive.addfile(member, io.BytesIO(data))


def prepare(args: argparse.Namespace) -> int:
    if not math.isfinite(args.build_timeout) or args.build_timeout <= 0:
        raise ValueError('Build timeout must be finite and positive')
    roots = {'before': args.before.resolve(strict=True), 'after': args.after.resolve(strict=True)}
    dart_path = shutil.which(args.dart)
    if dart_path is None:
        raise ValueError(f'Dart executable not found: {args.dart}')
    dart = Path(dart_path).resolve()
    snapshots = {name: snapshot(root) for name, root in roots.items()}
    require_identical_adapters(snapshots['before'][0], snapshots['after'][0])
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = dict(schema_version=1, status='preparing', started_utc=now(),
                    purpose='Pure-Dart AOT preparation; compilation is outside all solver timers',
                    dart=dict(executable=str(dart), sha256=sha(dart),
                              version=subprocess.check_output([str(dart), '--version'], text=True).strip()),
                    platform=platform.platform(), variants={},
                    harness_source_commit=git(HERE.parents[1], 'rev-parse', 'HEAD'),
                    environment={name: os.environ.get(name) for name in ('PUB_CACHE', 'TMPDIR')},
                    harness_sha256={name: sha(HERE / name) for name in HARNESSES})
    for name in HARNESSES:
        destination = output / 'harness' / name
        destination.parent.mkdir(exist_ok=True)
        shutil.copyfile(HERE / name, destination)
    dump(output / 'prepared.json', manifest)
    try:
        for name, root in roots.items():
            source, files = snapshots[name]
            directory = output / name
            directory.mkdir()
            archive_source(directory / 'source.tar.gz', files)
            binary = directory / 'dart-adapter'
            command = [str(dart), 'compile', 'exe', ADAPTERS[0], '-o', str(binary)]
            build = dict(command=command, command_sha256=digest(json.dumps(command).encode()),
                         cwd=str(root), started_utc=now(), timeout_seconds=args.build_timeout)
            manifest['variants'][name] = dict(source=source, build=build,
                                              source_archive=f'{name}/source.tar.gz',
                                              source_archive_sha256=sha(directory / 'source.tar.gz'))
            dump(output / 'prepared.json', manifest)
            with (directory / 'build.stdout.log').open('wb') as stdout, (directory / 'build.stderr.log').open('wb') as stderr:
                try:
                    result = subprocess.run(command, cwd=root, stdout=stdout, stderr=stderr,
                                            timeout=args.build_timeout)
                    build.update(exit_code=result.returncode, timed_out=False)
                except subprocess.TimeoutExpired:
                    build.update(exit_code=None, timed_out=True)
            build.update(completed_utc=now(), stdout_sha256=sha(directory / 'build.stdout.log'),
                         stderr_sha256=sha(directory / 'build.stderr.log'))
            if build['exit_code'] != 0 or build['timed_out']:
                raise RuntimeError(f'{name} AOT compilation failed; exact output retained')
            current, _ = snapshot(root)
            if current['source_sha256'] != source['source_sha256']:
                raise RuntimeError(f'{name} source changed during compilation')
            if sha(dart) != manifest['dart']['sha256']:
                raise RuntimeError('Dart executable changed during compilation')
            manifest['variants'][name].update(executable=f'{name}/dart-adapter', executable_sha256=sha(binary))
            dump(output / 'prepared.json', manifest)
            print(json.dumps({'prepared': name, 'source': source['source_commit'],
                              'executable_sha256': sha(binary)}), flush=True)
        manifest['status'] = 'complete'
    except Exception as error:
        manifest.update(status='failed', error=str(error))
        raise
    finally:
        manifest['finished_utc'] = now()
        dump(output / 'prepared.json', manifest)
    return 0


def verify_artifacts(prepared: Path, manifest: dict, variants: list[str]) -> None:
    if manifest.get('status') != 'complete':
        raise ValueError('Preparation is incomplete')
    for name, expected in manifest['harness_sha256'].items():
        if sha(HERE / name) != expected or sha(prepared / 'harness' / name) != expected:
            raise ValueError(f'Prepared/current harness mismatch: {name}')
    for variant in variants:
        item = manifest['variants'][variant]
        for field in ('source_archive', 'executable'):
            if sha(prepared / item[field]) != item[field + '_sha256']:
                raise ValueError(f'Frozen {variant} {field} changed')


def selected_cases(suites: str, selected: str | None) -> list[dict]:
    found = {}
    for suite in suites.split(','):
        if suite not in SUITES:
            raise ValueError(f'Unknown suite: {suite}')
        for case in corpus(suite):
            identity = case['fixture']['id']
            if identity in found and found[identity] != case:
                raise ValueError(f'Conflicting fixture definitions: {identity}')
            found[identity] = case
    if selected:
        requested = selected.split(',')
        if len(set(requested)) != len(requested) or not set(requested) <= found.keys():
            raise ValueError('Duplicate or unknown fixture selection')
        return [found[name] for name in requested]
    return list(found.values())


def paired_order(repeat: int, case: int, mode: int, engine: int, variants: list[str]) -> list[str]:
    return variants[::-1] if (repeat + case + mode + engine) % 2 else variants[:]


def qualified_ratio(before: dict | None, after: dict | None, field: str) -> float | None:
    if not before or not after or not before['qualified_latency'] or not after['qualified_latency']:
        return None
    a, b = before[field], after[field]
    return b / a if a is not None and b is not None and a > 0 else None


def run(args: argparse.Namespace) -> int:
    if args.rounds < 1 or args.samples < 1 or args.warmups < 0 or not math.isfinite(args.timeout) or args.timeout <= 0:
        raise ValueError('Invalid run counts or timeout')
    variants, engines, modes = args.variants.split(','), args.engines.split(','), args.modes.split(',')
    for values, allowed in ((variants, ('before', 'after')), (engines, ENGINES), (modes, ('cold', 'warm'))):
        if not values or len(set(values)) != len(values) or not set(values) <= set(allowed):
            raise ValueError('Invalid or duplicated variant/engine/mode selection')
    cases = selected_cases(args.suites, args.fixtures)
    prepared = args.prepared.resolve(strict=True)
    build = json.loads((prepared / 'prepared.json').read_text())
    verify_artifacts(prepared, build, variants)
    allowed_cpus = sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else []
    cpu = (allowed_cpus[0] if allowed_cpus else None) if args.cpu == 'auto' else (
        None if args.cpu == 'none' else int(args.cpu))
    if cpu is not None and cpu not in allowed_cpus:
        raise ValueError('Requested CPU is outside allowed affinity')
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = dict(schema_version=1, status='running', started_utc=now(),
                    purpose=args.purpose, prepared_manifest_sha256=sha(prepared / 'prepared.json'),
                    preparation=build, variants=variants, engines=engines, modes=modes,
                    suites=args.suites, fixture_ids=[c['fixture']['id'] for c in cases],
                    rounds=args.rounds, samples=args.samples, warmups=args.warmups,
                    timeout_seconds=args.timeout, allowed_cpus=allowed_cpus, pinned_cpu=cpu,
                    platform=platform.platform(), python=platform.python_version(),
                    cpu_model=next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                                    if line.startswith('model name')), '') if Path('/proc/cpuinfo').exists() else '',
                    thread_environment={name: '1' for name in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
                                                             'MKL_NUM_THREADS', 'RAYON_NUM_THREADS')},
                    timing_contract='native build/update + solve + extraction; excludes process startup, '
                                    'JSON serialization and independent checker; pure Dart without FFI',
                    percentile_method='sorted[ceil((n-1)*p)]; median of process percentiles, not pooled',
                    harness_sha256=build['harness_sha256'], extra_artifact_sha256={}, jobs=[])
    per_variant = {}
    for variant in variants:
        item = build['variants'][variant]
        source = item['source']
        lane = {key: value for key, value in manifest.items() if key not in ('jobs', 'preparation')}
        lane.update(source_commit=source['source_commit'], library_tree=source['library_tree'],
                    test_tree=source['test_tree'], source_status=source['source_status'],
                    suite=args.suites, variant=variant, executable_sha256={engine: item['executable_sha256'] for engine in engines})
        per_variant[variant] = dict(manifest=lane, jobs=[])

    def checkpoint() -> None:
        dump(output / 'manifest.json', manifest)
        for variant, lane in per_variant.items():
            # These describe the paired run's collection/analysis lifecycle.
            # Refresh them at every checkpoint rather than retaining the initial
            # 'running' snapshot in otherwise complete variant archives.
            for key in ('status', 'finished_utc', 'analysis_finished_utc',
                        'protocol_ok', 'qualification_passed', 'error'):
                if key in manifest:
                    lane['manifest'][key] = manifest[key]
                else:
                    lane['manifest'].pop(key, None)
            lane['manifest']['completed_jobs'] = len(lane['jobs'])
            dump(output / variant / 'manifest.json', lane['manifest'])
            dump(output / variant / 'summary.json', lane)

    checkpoint()
    try:
        for repeat in range(args.rounds):
            for ci, case in enumerate(cases):
                for mi, mode in enumerate(modes):
                    for ei, engine in enumerate(engines):
                        req = request(case, engine, mode, args.warmups, args.samples)
                        physical_hash = None
                        for variant in paired_order(repeat, ci, mi, ei, variants):
                            verify_artifacts(prepared, build, [variant])
                            lane = per_variant[variant]
                            key = f'{len(lane["jobs"]):04d}-r{repeat+1}-{engine}-{mode}-{case["fixture"]["id"]}'
                            started = now()
                            manifest['in_progress'] = dict(variant=variant, job=key, started_utc=started)
                            checkpoint()
                            row = run_job([str(prepared / build['variants'][variant]['executable'])], req,
                                          output / variant / key, args.timeout, cpu, len(lane['jobs']))
                            row.update(round=repeat + 1, variant=variant, started_utc=started, completed_utc=now())
                            row['command_sha256'] = digest(json.dumps(row['command']).encode())
                            checked = [json.loads(line) for line in gzip.decompress(
                                (output / variant / key / 'checked.jsonl.gz').read_bytes()).splitlines()]
                            row['qualification_operation_failures'] = sum(
                                bool(record.get('adapter_error')) or
                                record['oracle']['accepted'] != case['fixture']['expected_feasible']
                                for record in checked)
                            dump(output / variant / key / 'job.json', row)
                            lane['jobs'].append(row)
                            manifest['jobs'].append(dict(variant=variant, job=key, summary=row['summary'],
                                                         started_utc=started, completed_utc=row['completed_utc']))
                            manifest.pop('in_progress', None)
                            checkpoint()
                            verify_artifacts(prepared, build, [variant])
                            if physical_hash is not None and row['physical_request_sha256'] != physical_hash:
                                raise RuntimeError('Paired physical requests differ')
                            physical_hash = row['physical_request_sha256']
                            print(json.dumps(dict(variant=variant, job=key, complete=row['summary']['complete'],
                                                  accepted=row['summary']['accepted_samples'], expected=args.samples,
                                                  timed_out=row['timed_out'])), flush=True)
        manifest['status'] = 'collected'
    except Exception as error:
        manifest.update(status='failed', error=str(error))
        raise
    finally:
        manifest['finished_utc'] = now()
        checkpoint()
    groups = {}
    for variant in variants:
        report = analyze_runs([output / variant], include_metrics=True)
        write_report(report, output / f'analysis-{variant}')
        for group in report['groups']:
            key = (group['fixture_id'], group['mode'], group['engine'])
            groups.setdefault(key, {})[variant] = group
    comparisons = []
    for (fixture, mode, engine), pair in sorted(groups.items()):
        comparisons.append(dict(fixture_id=fixture, mode=mode, engine=engine, **pair,
                                after_over_before_p50=qualified_ratio(pair.get('before'), pair.get('after'),
                                                                    'median_process_accepted_p50_ms'),
                                after_over_before_p95=qualified_ratio(pair.get('before'), pair.get('after'),
                                                                    'median_process_accepted_p95_ms')))
    all_jobs = [job for lane in per_variant.values() for job in lane['jobs']]
    protocol_ok = all(not job['parse_errors'] and not job['summary']['acceptance_disagreements'] for job in all_jobs)
    qualification_ok = all(job['summary']['complete'] and not job['qualification_operation_failures'] and
                           not job['summary']['adapter_exception_samples'] and
                           job['summary']['accepted_samples'] == (args.samples if job['summary']['known_feasible'] else 0)
                           for job in all_jobs) and protocol_ok
    dump(output / 'comparison.json', dict(purpose=args.purpose, protocol_ok=protocol_ok,
                                         qualification_passed=qualification_ok, groups=comparisons,
                                         note='Ratios require complete raw evidence and accepted measured samples on both sides. '
                                              'Failed or timed-out baseline jobs remain visible without successful-latency ratios.'))
    manifest.update(status='complete', analysis_finished_utc=now(),
                    protocol_ok=protocol_ok, qualification_passed=qualification_ok)
    checkpoint()
    return 0 if protocol_ok and (args.purpose != 'qualification' or qualification_ok) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    prep = sub.add_parser('prepare')
    prep.add_argument('--before', type=Path, required=True)
    prep.add_argument('--after', type=Path, required=True)
    prep.add_argument('--dart', default='dart')
    prep.add_argument('--build-timeout', type=float, default=300)
    prep.add_argument('--out', type=Path, required=True)
    execute = sub.add_parser('run')
    execute.add_argument('--prepared', type=Path, required=True)
    execute.add_argument('--out', type=Path, required=True)
    execute.add_argument('--variants', default='before,after')
    execute.add_argument('--purpose', choices=('qualification', 'measurement'), default='measurement')
    execute.add_argument('--engines', default='dart_2d_analytic')
    execute.add_argument('--suites', default='confirm,coupled')
    execute.add_argument('--fixtures')
    execute.add_argument('--modes', default='cold,warm')
    execute.add_argument('--rounds', type=int, default=3)
    execute.add_argument('--samples', type=int, default=7)
    execute.add_argument('--warmups', type=int, default=2)
    execute.add_argument('--timeout', type=float, default=20)
    execute.add_argument('--cpu', default='auto')
    args = parser.parse_args()
    return prepare(args) if args.action == 'prepare' else run(args)


if __name__ == '__main__':
    raise SystemExit(main())

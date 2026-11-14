#!/usr/bin/env python3
"""Run real solver adapters sequentially and preserve all observations/failures."""

from __future__ import annotations

import argparse
import datetime
import gzip
import hashlib
import json
import math
import os
import pathlib
import platform
import subprocess
import time

from fixtures import corpus, request
from oracle import check


def dump(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact_hashes(paths: list[pathlib.Path]) -> dict[str, str]:
    result = {}
    for supplied in paths:
        path = supplied.resolve(strict=True)
        if not path.is_file():
            raise ValueError(f'extra artifact is not a file: {path}')
        result[str(path)] = sha(path)
    return result


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    return values[math.ceil((len(values) - 1) * p)]


def git(*args: str) -> str:
    return subprocess.check_output(['git', *args], text=True).strip()


def summarize(records: list[dict], req: dict) -> dict:
    samples = [r for r in records if not r.get('warmup', True)]
    accepted = [r for r in samples if r['oracle']['accepted']]
    times = [r['elapsed_ns'] / 1e6 for r in samples]
    valid_times = [r['elapsed_ns'] / 1e6 for r in accepted]
    max_error = max((r['oracle']['max_error'] for r in samples
                     if r['oracle']['max_error'] is not None), default=None)
    normalized_error = max_error / req['tolerance'] if max_error is not None else None
    if normalized_error is not None and not math.isfinite(normalized_error):
        normalized_error = None
    return dict(expected_samples=req['samples'], completed_samples=len(samples),
                accepted_samples=len(accepted),
                rejected_samples=len(samples) - len(accepted),
                reported_success_rejected=sum(bool(r.get('reported_success')) and
                                              not r['oracle']['accepted'] for r in samples),
                acceptance_disagreements=sum(bool(r.get('accepted')) !=
                                             r['oracle']['accepted'] for r in records),
                adapter_exception_samples=sum(bool(r.get('adapter_error')) for r in samples),
                valid_physical_rejections=sum(not r['oracle']['accepted'] and
                                              not r.get('adapter_error') for r in samples),
                all_p50_ms=percentile(times, .50), all_p95_ms=percentile(times, .95),
                accepted_p50_ms=percentile(valid_times, .50),
                accepted_p95_ms=percentile(valid_times, .95),
                max_error=max_error, max_error_over_tolerance=normalized_error,
                known_feasible=req['fixture']['expected_feasible'])


def validate_record(record: dict, req: dict, previous: int) -> None:
    """Reject malformed output before it contributes any latency evidence."""
    if type(record.get('schema_version')) is not int or record['schema_version'] != 1:
        raise ValueError('unsupported schema_version')
    if record.get('fixture_id') != req['fixture']['id']:
        raise ValueError('fixture identity mismatch')
    if record.get('engine') != req['engine'] or record.get('mode') != req['mode']:
        raise ValueError('engine/mode mismatch')
    index = record.get('index')
    if type(index) is not int or not -req['warmups'] <= index < req['samples']:
        raise ValueError('index outside requested range')
    if type(record.get('warmup')) is not bool or record['warmup'] != (index < 0):
        raise ValueError('warmup/index mismatch')
    if index != previous - req['warmups']:
        raise ValueError('missing, duplicated, or unordered operation')
    if any(type(record.get(k)) not in (int, float) or not math.isfinite(record[k])
           or record[k] < 0 for k in ('build_ns', 'solve_ns', 'elapsed_ns')):
        raise ValueError('invalid timing')
    # Dart converts separate stopwatch intervals to integer nanoseconds.
    # Two conversions may differ by a few ns, but overlap is a protocol error.
    if record['elapsed_ns'] + 10 < record['build_ns'] + record['solve_ns']:
        raise ValueError('total elapsed time does not cover build plus solve')
    if type(record.get('accepted')) is not bool:
        raise ValueError('accepted must be a physical-gate boolean')
    if req['engine'] == 'dart_3d_ad':
        z = record.get('max_z')
        if type(z) not in (int, float) or not math.isfinite(z) or z < 0:
            raise ValueError('invalid or missing workplane max_z')


def run_job(command: list[str], req: dict, path: pathlib.Path,
            timeout: float, cpu: int | None, index: int) -> dict:
    path.mkdir(parents=True, exist_ok=False)
    req_bytes = (json.dumps(req, separators=(',', ':'), allow_nan=False) + '\n').encode()
    request_path = path / 'request.json'
    request_path.write_bytes(req_bytes)
    stdout_path, stderr_path = path / 'stdout.jsonl', path / 'stderr.txt'
    env = os.environ.copy()
    env.update(OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1',
               MKL_NUM_THREADS='1', RAYON_NUM_THREADS='1')
    def pin() -> None:
        if cpu is not None:
            os.sched_setaffinity(0, {cpu})
    timed_out = False
    started = time.perf_counter_ns()
    with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
        proc = subprocess.Popen([*command, str(request_path.resolve())],
                                stdout=stdout, stderr=stderr, env=env,
                                preexec_fn=pin if cpu is not None else None)
        try:
            returncode = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            returncode = proc.wait()
    process_ns = time.perf_counter_ns() - started
    records, metadata, errors = [], [], []
    for line_number, line in enumerate(stdout_path.read_text().splitlines(), 1):
        try:
            def reject_constant(value: str) -> None:
                raise ValueError(f'nonfinite JSON constant: {value}')
            record = json.loads(line, parse_constant=reject_constant)
            if record.get('record') == 'metadata':
                metadata.append(record)
                continue
            validate_record(record, req, len(records))
            record['oracle'] = check(req, record)
            if req['engine'] == 'dart_3d_ad' and record['max_z'] > req['tolerance']:
                record['oracle']['accepted'] = False
                record['oracle']['violations'].append('workplane_z')
            records.append(record)
        except (ValueError, KeyError, TypeError, AttributeError, OverflowError) as error:
            errors.append(dict(line=line_number, error=str(error)))
    expected_records = req['warmups'] + req['samples']
    complete = (not timed_out and returncode == 0 and not errors and
                len(records) == expected_records)
    summary = summarize(records, req)
    summary.update(complete=complete, expected_records=expected_records,
                   completed_records=len(records),
                   latency_evidence='complete' if complete else 'partial_or_invalid',
                   ranking_eligible=complete and not summary['acceptance_disagreements']
                   and summary['accepted_samples'] == req['samples']
                   and req['fixture']['expected_feasible'])
    physical_request = {k: v for k, v in req.items() if k != 'engine'}
    result = dict(job_index=index, engine=req['engine'], mode=req['mode'],
                  fixture_id=req['fixture']['id'], geometric_free_coordinates=
                  req['fixture'].get('geometric_free_coordinates'),
                  logical_components=req['fixture'].get('logical_components'),
                  request_sha256=hashlib.sha256(req_bytes).hexdigest(),
                  physical_request_sha256=hashlib.sha256(json.dumps(
                      physical_request, sort_keys=True, separators=(',', ':'),
                      allow_nan=False).encode()).hexdigest(),
                  command=[*command, str(request_path)],
                  process_wall_ns=process_ns, timeout_seconds=timeout,
                  timed_out=timed_out, returncode=returncode,
                  metadata=metadata, parse_errors=errors,
                  summary=summary, raw_directory=str(path))
    with gzip.open(path / 'checked.jsonl.gz', 'wt') as f:
        for record in records:
            f.write(json.dumps(record, allow_nan=False) + '\n')
    # Exact native output and requests remain available, compactly, for replay.
    for original in (request_path, stdout_path):
        with gzip.open(str(original) + '.gz', 'wb') as f:
            f.write(original.read_bytes())
        original.unlink()
    dump(path / 'job.json', result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commands', type=pathlib.Path, required=True,
                        help='JSON map of engine name to command argument array')
    parser.add_argument('--engines', help='Comma-separated subset, in initial order')
    parser.add_argument('--suite', choices=['smoke', 'screen', 'confirm', 'boundaries', 'coupled'],
                        default='screen')
    parser.add_argument('--fixtures', help='Comma-separated fixture IDs to include')
    parser.add_argument('--modes', default='cold,warm')
    parser.add_argument('--rounds', type=int, default=1)
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--warmups', type=int, default=2)
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--cpu', default='auto', help='auto, none, or allowed CPU number')
    parser.add_argument('--artifacts', type=pathlib.Path, nargs='+', default=[],
                        help='Additional loaded libraries/artifacts to hash into the manifest')
    parser.add_argument('--out', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.rounds < 1 or args.samples < 1 or args.warmups < 0:
        parser.error('positive rounds/samples and nonnegative warmups are required')
    if args.out.exists():
        parser.error('output already exists; preserve it and choose a new run directory')
    try:
        extra_artifact_sha256 = artifact_hashes(args.artifacts)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    commands = json.loads(args.commands.read_text())
    engines = args.engines.split(',') if args.engines else list(commands)
    cases = corpus(args.suite)
    if args.fixtures:
        selected = set(args.fixtures.split(','))
        cases = [c for c in cases if c['fixture']['id'] in selected]
        if {c['fixture']['id'] for c in cases} != selected:
            parser.error('unknown fixture selection')
    modes = args.modes.split(',')
    if not set(modes) <= {'cold', 'warm'}:
        parser.error('invalid mode')
    allowed = sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else []
    cpu = (allowed[0] if allowed else None) if args.cpu == 'auto' else (
        None if args.cpu == 'none' else int(args.cpu))
    if cpu is not None and cpu not in allowed:
        parser.error('CPU is not in allowed affinity')
    for engine in engines:
        if engine not in commands or not commands[engine]:
            parser.error(f'no command for {engine}')
        commands[engine][0] = str(pathlib.Path(commands[engine][0]).resolve())
        if not pathlib.Path(commands[engine][0]).is_file():
            parser.error(f'missing executable for {engine}')
    cpu_model = ''
    try:
        cpu_model = next(line.split(':', 1)[1].strip()
                         for line in pathlib.Path('/proc/cpuinfo').read_text().splitlines()
                         if line.startswith('model name'))
    except (OSError, StopIteration):
        pass
    manifest = dict(schema_version=1, started_utc=datetime.datetime.now(
        datetime.timezone.utc).isoformat(), source_commit=git('rev-parse', 'HEAD'),
        library_tree=git('rev-parse', 'HEAD:lib'),
        harness_sha256={str(p): sha(p) for p in sorted(
            pathlib.Path('benchmark/solver_comparison').rglob('*'))
            if p.is_file() and not any(x in p.parts for x in ('target', '__pycache__', 'out'))
            and p.suffix in ('.py', '.dart', '.rs', '.cpp', '.h', '.md', '.toml', '.lock', '.txt', '.sh')},
        source_status=git('status', '--short'), suite=args.suite,
        rounds=args.rounds, warmups=args.warmups, samples=args.samples,
        timeout_seconds=args.timeout, engines=engines, modes=modes,
        platform=platform.platform(), python=platform.python_version(),
        cpu_model=cpu_model, allowed_cpus=allowed, pinned_cpu=cpu,
        thread_environment={k: '1' for k in ['OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
                                           'MKL_NUM_THREADS', 'RAYON_NUM_THREADS']},
        commands={e: commands[e] for e in engines},
        executable_sha256={e: sha(pathlib.Path(commands[e][0])) for e in engines},
        extra_artifact_sha256=extra_artifact_sha256,
        fixture_ids=[c['fixture']['id'] for c in cases],
        timing_contract='native build/update + solve + extraction; excludes input parsing, '
                        'JSON serialization and independent checker; not Dart FFI/browser latency',
        tail_qualification='Screening/small-sample tails are descriptive, not stable p99 estimates')
    manifest['percentile_method'] = 'upper order statistic: sorted[ceil((n-1)*p)]'
    dump(args.out / 'manifest.json', manifest)
    jobs = []
    try:
        for repeat in range(args.rounds):
            order = engines[repeat % len(engines):] + engines[:repeat % len(engines)]
            for case in cases:
                for mode in modes:
                    for engine in order:
                        req = request(case, engine, mode, args.warmups, args.samples)
                        key = f'{len(jobs):04d}-r{repeat+1}-{engine}-{mode}-{case["fixture"]["id"]}'
                        result = run_job(commands[engine], req, args.out / key,
                                         args.timeout, cpu, len(jobs))
                        result['round'] = repeat + 1
                        jobs.append(result)
                        dump(args.out / 'summary.json', dict(manifest=manifest, jobs=jobs))
                        s = result['summary']
                        print(json.dumps(dict(job=key, accepted=s['accepted_samples'],
                                              completed=s['completed_samples'], expected=args.samples,
                                              p50_ms=s['accepted_p50_ms'],
                                              timed_out=result['timed_out'],
                                              complete=s['complete'],
                                              ranking_eligible=s['ranking_eligible'],
                                              discrepancies=s['acceptance_disagreements'],
                                              parse_errors=len(result['parse_errors']))), flush=True)
    finally:
        manifest['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        manifest['completed_jobs'] = len(jobs)
        dump(args.out / 'manifest.json', manifest)
        dump(args.out / 'summary.json', dict(manifest=manifest, jobs=jobs))
    if any(j['parse_errors'] or j['summary']['acceptance_disagreements'] for j in jobs):
        raise SystemExit('Adapter protocol/oracle disagreement; do not interpret timings before fixing')


if __name__ == '__main__':
    main()

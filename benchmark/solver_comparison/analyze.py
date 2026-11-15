#!/usr/bin/env python3
"""Aggregate saved solver runs without executing a solver or rechecking geometry.

Usage: analyze.py RUN_DIR [RUN_DIR ...] --out OUTPUT_DIR [--metrics]

Reads manifest.json, summary.json[.gz], and saved checked/request files. When
job directories are absent, raw-*.tar.gz archives are read directly. Writes
analysis.json and analysis.md; original evidence is never changed.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import gzip
import hashlib
import io
import json
import math
import pathlib
import re
import statistics
import tarfile


NUMERIC_METRICS = (
    'build_ns', 'solve_ns', 'iterations', 'active_coordinates', 'equations', 'parameter_blocks',
    'components', 'jacobian_nonzeros', 'components_solved', 'components_reused',
    'residual_evaluations', 'jacobian_evaluations', 'auto_diff_derivative_coordinates',
    'linear_solves', 'linear_iterations', 'rank_factorizations', 'rank_reuses',
    'local_degrees_of_freedom', 'physical_callback_checks',
)
BOOLEAN_METRICS = (
    'model_reused', 'session_reused', 'coordinate_seed_reset', 'plan_fell_back',
    'engine_degenerate',
)


def reject_constant(value: str) -> None:
    raise ValueError(f'Nonfinite JSON constant: {value}')


def decode_json(data: bytes | str) -> object:
    return json.loads(data, parse_constant=reject_constant)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fingerprint(value: object) -> str:
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':'),
                             allow_nan=False).encode())


def finite(value: object) -> bool:
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    return values[math.ceil((len(values) - 1) * fraction)]


def median(values: list[float | None]) -> float | None:
    available = [value for value in values if value is not None]
    return statistics.median(available) if available else None


def total(values: list[int | None]) -> int | None:
    return sum(values) if all(value is not None for value in values) else None


class RunFiles:
    """Read only named run evidence, including relocated packed runs."""

    def __init__(self, root: pathlib.Path, job_names: set[str]):
        self.root = root
        self.job_names = job_names
        self.archives = iter(sorted(root.glob('raw-*.tar.gz')))
        self.cached: dict[str, bytes] = {}
        self.used_archives: list[dict] = []

    def read(self, job_name: str, filename: str) -> bytes | None:
        relative = f'{job_name}/{filename}'
        local = self.root / job_name / filename
        if local.is_file():
            return local.read_bytes()
        if relative in self.cached:
            return self.cached.pop(relative)
        for archive in self.archives:
            self.used_archives.append(dict(path=str(archive),
                                           sha256=digest(archive.read_bytes())))
            # Sequential archive traversal avoids repeatedly decompressing a
            # large tar for each requested member. Cache only useful compressed
            # evidence, not duplicate stdout, coordinates or stderr files.
            with tarfile.open(archive, mode='r|gz') as stream:
                for member in stream:
                    parts = pathlib.PurePosixPath(member.name).parts
                    if not member.isfile() or len(parts) < 2:
                        continue
                    parent, name = parts[-2:]
                    if parent not in self.job_names or name not in (
                            'checked.jsonl.gz', 'request.json.gz', 'request.json'):
                        continue
                    handle = stream.extractfile(member)
                    if handle is not None:
                        self.cached[f'{parent}/{name}'] = handle.read()
            if relative in self.cached:
                return self.cached.pop(relative)
        return None


def record_counts(records: list[dict]) -> dict:
    accepted = [record for record in records if record['oracle']['accepted']]
    times = [record['elapsed_ns'] / 1e6 for record in records]
    accepted_times = [record['elapsed_ns'] / 1e6 for record in accepted]
    errors = [record['oracle'].get('max_error') for record in records]
    finite_errors = [error for error in errors if finite(error)]
    return dict(
        completed=len(records), accepted=len(accepted),
        rejected=len(records) - len(accepted),
        adapter_exceptions=sum(bool(record.get('adapter_error')) for record in records),
        native_success_rejected=sum(bool(record.get('reported_success')) and
                                    not record['oracle']['accepted'] for record in records),
        acceptance_disagreements=sum(record.get('accepted') != record['oracle']['accepted']
                                     for record in records),
        valid_rejections=sum(not record['oracle']['accepted'] and
                             not record.get('adapter_error') for record in records),
        all_p50_ms=percentile(times, .50), all_p95_ms=percentile(times, .95),
        accepted_p50_ms=percentile(accepted_times, .50),
        accepted_p95_ms=percentile(accepted_times, .95),
        max_finite_error=max(finite_errors, default=None),
        error_unavailable=len(errors) - len(finite_errors),
    )


def read_records(data: bytes, job: dict, warmups: int, samples: int,
                 issues: list[str]) -> list[dict]:
    records = []
    with gzip.open(io.BytesIO(data), 'rt') as source:
        for line_number, line in enumerate(source, 1):
            try:
                record = decode_json(line)
                if not isinstance(record, dict) or record.get('schema_version') != 1:
                    raise ValueError('unsupported record schema')
                if any(record.get(key) != job[key] for key in ('engine', 'fixture_id', 'mode')):
                    raise ValueError('record identity mismatch')
                index = record.get('index')
                if type(index) is not int or not -warmups <= index < samples:
                    raise ValueError('record index outside requested range')
                if index != len(records) - warmups:
                    raise ValueError('missing, duplicated or unordered record')
                if type(record.get('warmup')) is not bool or record['warmup'] != (index < 0):
                    raise ValueError('warmup/index mismatch')
                if type(record.get('accepted')) is not bool:
                    raise ValueError('missing physical acceptance')
                if not isinstance(record.get('oracle'), dict) or (
                        type(record['oracle'].get('accepted')) is not bool):
                    raise ValueError('missing saved oracle verdict')
                if any(not finite(record.get(key)) or record[key] < 0
                       for key in ('elapsed_ns', 'build_ns', 'solve_ns')):
                    raise ValueError('invalid timing')
                if record['elapsed_ns'] + 10 < record['build_ns'] + record['solve_ns']:
                    raise ValueError('overlapping timing intervals')
                # The verdict is the saved oracle's result, not a re-evaluation
                # with today's checker. Coordinates remain in the source files.
                record.pop('coordinates', None)
                records.append(record)
            except (ValueError, KeyError, TypeError, AttributeError, OverflowError) as error:
                issues.append(f'checked_record:{line_number}:{error}')
    return records


def metric_summary(records: list[dict]) -> dict:
    output = {}
    for name in NUMERIC_METRICS:
        values = [record[name] for record in records if finite(record.get(name))]
        if values:
            output[name] = dict(observations=len(values), median=statistics.median(values),
                                minimum=min(values), maximum=max(values))
    for name in BOOLEAN_METRICS:
        values = [record[name] for record in records if type(record.get(name)) is bool]
        if values:
            output[name] = dict(observations=len(values), true_count=sum(values))
    return output


def inspect_job(job: dict, manifest: dict, files: RunFiles, run_id: str,
                include_metrics: bool) -> dict:
    saved = job['summary']
    issues: list[str] = []
    job_name = pathlib.Path(job['raw_directory']).name
    compressed_request = files.read(job_name, 'request.json.gz')
    request_bytes = (gzip.decompress(compressed_request) if compressed_request is not None
                     else files.read(job_name, 'request.json'))
    req = decode_json(request_bytes) if request_bytes is not None else None
    if req is not None and any(req.get(key) != job[key] for key in ('engine', 'mode')):
        issues.append('request_identity_mismatch')
    if req is not None and req.get('fixture', {}).get('id') != job['fixture_id']:
        issues.append('request_fixture_mismatch')
    if request_bytes is not None and job.get('request_sha256') not in (
            None, digest(request_bytes)):
        issues.append('request_hash_mismatch')
    expected = req['samples'] if req else saved.get('expected_samples', manifest['samples'])
    warmups = req['warmups'] if req else manifest['warmups']
    tolerance = req.get('tolerance') if req else None
    known_feasible = (req['fixture']['expected_feasible'] if req
                      else saved.get('known_feasible'))
    raw = files.read(job_name, 'checked.jsonl.gz')
    records = read_records(raw, job, warmups, expected, issues) if raw is not None else None

    if records is not None:
        main_records = [record for record in records if not record['warmup']]
        warmup_records = [record for record in records if record['warmup']]
        main, warm = record_counts(main_records), record_counts(warmup_records)
        disagreements = main['acceptance_disagreements'] + warm['acceptance_disagreements']
        checks = {
            'expected_samples': expected, 'completed_samples': main['completed'],
            'accepted_samples': main['accepted'], 'rejected_samples': main['rejected'],
            'adapter_exception_samples': main['adapter_exceptions'],
            'reported_success_rejected': main['native_success_rejected'],
            'valid_physical_rejections': main['valid_rejections'],
            'acceptance_disagreements': disagreements,
        }
        for key, actual in checks.items():
            if key in saved and saved[key] != actual:
                issues.append(f'summary_mismatch:{key}')
        complete_count = len(records) == expected + warmups
        evidence = 'checked_raw'
    else:
        # Keep saved summary evidence visible, but do not qualify publication
        # timing without the checked records that establish its population.
        evidence = 'summary_only'
        main = dict(
            completed=saved.get('completed_samples', 0),
            accepted=saved.get('accepted_samples', 0),
            rejected=saved.get('rejected_samples', 0),
            adapter_exceptions=saved.get('adapter_exception_samples'),
            native_success_rejected=saved.get('reported_success_rejected',
                                               saved.get('false_positive_samples')),
            acceptance_disagreements=saved.get('acceptance_disagreements'),
            valid_rejections=saved.get('valid_physical_rejections'),
            all_p50_ms=saved.get('all_p50_ms'), all_p95_ms=saved.get('all_p95_ms'),
            accepted_p50_ms=saved.get('accepted_p50_ms'),
            accepted_p95_ms=saved.get('accepted_p95_ms'),
            max_finite_error=saved.get('max_error'), error_unavailable=None,
        )
        warm = {key: None for key in record_counts([])}
        disagreements = saved.get('acceptance_disagreements')
        complete_count = saved.get('completed_records') == expected + warmups
        main_records = []
        issues.append('checked_raw_unavailable')
    if req is None:
        issues.append('saved_request_unavailable')
    if tolerance is not None and (not finite(tolerance) or tolerance <= 0):
        issues.append('invalid_request_tolerance')

    error = main['max_finite_error']
    ratio = (error / tolerance if finite(error) and finite(tolerance) and tolerance > 0
             else saved.get('max_error_over_tolerance'))
    if ratio is not None and not finite(ratio):
        ratio = None
    main['max_finite_error_over_tolerance'] = ratio
    main['expected'] = expected
    main['missing'] = max(0, expected - main['completed'])
    warm['expected'] = warmups
    warm['missing'] = (max(0, warmups - warm['completed'])
                       if warm['completed'] is not None else None)
    parse_errors = job.get('parse_errors', [])
    complete = (not job.get('timed_out', False) and job.get('returncode') == 0
                and not parse_errors and not issues and complete_count
                and saved.get('complete', True))
    eligible = (complete and known_feasible is True and disagreements == 0
                and main['accepted'] == expected and main['adapter_exceptions'] == 0)
    valid_rejection_job = (complete and known_feasible is False and disagreements == 0
                          and main['valid_rejections'] == expected
                          and main['adapter_exceptions'] == 0)
    semantic_request = ({key: value for key, value in req.items()
                         if key not in ('engine', 'samples', 'warmups')} if req else None)
    environment = {key: manifest.get(key) for key in (
        'platform', 'cpu_model', 'pinned_cpu', 'thread_environment', 'timing_contract')}
    return dict(
        run_id=run_id, job_name=job_name, round=job['round'], present=True,
        engine=job['engine'], fixture_id=job['fixture_id'], mode=job['mode'],
        expected_feasible=known_feasible,
        geometric_free_coordinates=job.get('geometric_free_coordinates'),
        logical_components=job.get('logical_components'), tolerance=tolerance,
        complete=complete, qualified_latency=eligible, valid_rejection_job=valid_rejection_job,
        evidence=evidence, main=main, warmups=warm,
        acceptance_disagreements=disagreements,
        timed_out=bool(job.get('timed_out')), returncode=job.get('returncode'),
        parse_error_count=len(parse_errors), analysis_issues=issues,
        source_commit=manifest.get('source_commit'), library_tree=manifest.get('library_tree'),
        executable_sha256=manifest.get('executable_sha256', {}).get(job['engine']),
        extra_artifact_sha256=manifest.get('extra_artifact_sha256', {}),
        extra_artifact_content_sha256=fingerprint(sorted(
            manifest.get('extra_artifact_sha256', {}).values())),
        semantic_request_sha256=fingerprint(semantic_request) if semantic_request else None,
        physical_request_sha256=job.get('physical_request_sha256'),
        request_sha256=digest(request_bytes) if request_bytes is not None else None,
        checked_gzip_sha256=digest(raw) if raw is not None else None,
        environment_sha256=fingerprint(environment),
        command_options=job.get('command', [])[1:-1],
        adapter_metadata=job.get('metadata', []),
        metrics=metric_summary(main_records) if include_metrics else None,
    )


def missing_job(manifest: dict, run_id: str, engine: str, fixture: str, mode: str,
                repeat: int, expected_feasible: bool | None) -> dict:
    main = record_counts([])
    main.update(expected=manifest['samples'], missing=manifest['samples'],
                max_finite_error_over_tolerance=None)
    warm = record_counts([])
    warm.update(expected=manifest['warmups'], missing=manifest['warmups'])
    return dict(
        run_id=run_id, job_name=None, round=repeat, present=False, engine=engine,
        fixture_id=fixture, mode=mode, expected_feasible=expected_feasible,
        geometric_free_coordinates=None, logical_components=None, tolerance=None,
        complete=False, qualified_latency=False, valid_rejection_job=False,
        evidence='missing_planned_job', main=main, warmups=warm,
        acceptance_disagreements=0, timed_out=False, returncode=None,
        parse_error_count=0, analysis_issues=['missing_planned_job'],
        source_commit=manifest.get('source_commit'), library_tree=manifest.get('library_tree'),
        executable_sha256=manifest.get('executable_sha256', {}).get(engine),
        extra_artifact_sha256=manifest.get('extra_artifact_sha256', {}),
        extra_artifact_content_sha256=fingerprint(sorted(
            manifest.get('extra_artifact_sha256', {}).values())),
        semantic_request_sha256=None, physical_request_sha256=None,
        request_sha256=None, checked_gzip_sha256=None, environment_sha256=None,
        command_options=[], adapter_metadata=[], metrics=None,
    )


def load_run(root: pathlib.Path, run_id: str, include_metrics: bool) -> tuple[dict, list[dict]]:
    summary_path = root / 'summary.json'
    if summary_path.is_file():
        summary_bytes = summary_path.read_bytes()
    else:
        summary_path = root / 'summary.json.gz'
        summary_bytes = gzip.decompress(summary_path.read_bytes())
    summary = decode_json(summary_bytes)
    manifest_path = root / 'manifest.json'
    manifest = (decode_json(manifest_path.read_bytes()) if manifest_path.is_file()
                else summary['manifest'])
    start_round = manifest.get('start_round', 0)
    if type(start_round) is not int or start_round < 0:
        raise ValueError(f'Invalid start_round in {root}: {start_round}')
    original_jobs = summary['jobs']
    names = {pathlib.Path(job['raw_directory']).name for job in original_jobs}
    files = RunFiles(root, names)
    jobs, seen = [], set()
    for original in original_jobs:
        job = dict(original)
        repeat = job.get('round')
        if repeat is None:
            match = re.search(r'(?:^|-)r(\d+)-', pathlib.Path(job['raw_directory']).name)
            repeat = int(match.group(1)) if match else (start_round + 1 if manifest['rounds'] == 1 else None)
        if type(repeat) is not int:
            raise ValueError(f'Unknown round in {root}: {job["raw_directory"]}')
        job['round'] = repeat
        key = (job['engine'], job['fixture_id'], job['mode'], repeat)
        if key in seen:
            raise ValueError(f'Duplicate job identity in {root}: {key}')
        seen.add(key)
        jobs.append(inspect_job(job, manifest, files, run_id, include_metrics))
    feasibility = {}
    for job in jobs:
        if job['expected_feasible'] is not None:
            feasibility[job['fixture_id']] = job['expected_feasible']
    for repeat in range(start_round + 1, start_round + manifest['rounds'] + 1):
        for fixture in manifest['fixture_ids']:
            for mode in manifest['modes']:
                for engine in manifest['engines']:
                    if (engine, fixture, mode, repeat) not in seen:
                        jobs.append(missing_job(manifest, run_id, engine, fixture, mode, repeat,
                                                feasibility.get(fixture)))
    provenance = dict(
        run_id=run_id, directory=str(root), summary_file=str(summary_path),
        summary_json_sha256=digest(summary_bytes),
        manifest_sha256=(digest(manifest_path.read_bytes()) if manifest_path.is_file() else None),
        manifest=manifest, archives_read=files.used_archives,
        present_jobs=sum(job['present'] for job in jobs),
        missing_planned_jobs=sum(not job['present'] for job in jobs),
    )
    return provenance, jobs


def aggregate_group(jobs: list[dict]) -> dict:
    first = jobs[0]
    reasons = []
    if not all(job['complete'] for job in jobs):
        reasons.append('incomplete_or_invalid_jobs')
    feasible = {job['expected_feasible'] for job in jobs if job['expected_feasible'] is not None}
    expected_feasible = next(iter(feasible)) if len(feasible) == 1 else None
    if expected_feasible is not True:
        reasons.append('expected_infeasible' if expected_feasible is False else 'unknown_or_mixed_feasibility')
    if any(job['main']['accepted'] != job['main']['expected'] for job in jobs):
        reasons.append('not_all_measured_samples_accepted')
    if any(job['acceptance_disagreements'] not in (0,) for job in jobs):
        reasons.append('oracle_disagreement_or_unknown')
    if any(job['main']['adapter_exceptions'] not in (0,) for job in jobs):
        reasons.append('adapter_exceptions_or_unknown')
    for field, reason in (
            ('semantic_request_sha256', 'different_physical_requests'),
            ('executable_sha256', 'different_executable_builds'),
            ('extra_artifact_content_sha256', 'different_extra_artifact_builds'),
            ('environment_sha256', 'different_execution_environments')):
        values = {job[field] for job in jobs if job[field] is not None}
        if len(values) > 1:
            reasons.append(reason)
    if any(job['present'] and not job['executable_sha256'] for job in jobs):
        reasons.append('executable_provenance_unavailable')
    if len({tuple(job['command_options']) for job in jobs if job['present']}) > 1:
        reasons.append('different_command_options')
    eligible = not reasons and all(job['qualified_latency'] for job in jobs)
    main = {}
    warm = {}
    for field in ('expected', 'completed', 'accepted', 'rejected', 'missing',
                  'valid_rejections', 'adapter_exceptions', 'native_success_rejected',
                  'acceptance_disagreements', 'error_unavailable'):
        main[field] = total([job['main'][field] for job in jobs])
        warm[field] = total([job['warmups'][field] for job in jobs])
    ratios = [job['main']['max_finite_error_over_tolerance'] for job in jobs
              if finite(job['main']['max_finite_error_over_tolerance'])]
    main['max_finite_error_over_tolerance'] = max(ratios, default=None)
    tolerances = sorted({job['tolerance'] for job in jobs if finite(job['tolerance'])})
    return dict(
        engine=first['engine'], fixture_id=first['fixture_id'], mode=first['mode'],
        expected_feasible=expected_feasible, jobs=len(jobs),
        present_jobs=sum(job['present'] for job in jobs),
        complete_jobs=sum(job['complete'] for job in jobs),
        missing_jobs=sum(not job['present'] for job in jobs),
        timeout_jobs=sum(job['timed_out'] for job in jobs),
        nonzero_exit_jobs=sum(job['present'] and job['returncode'] not in (0, None) for job in jobs),
        parse_errors=sum(job['parse_error_count'] for job in jobs),
        analysis_issue_jobs=sum(bool(job['analysis_issues']) for job in jobs),
        acceptance_disagreements=total([job['acceptance_disagreements'] for job in jobs]),
        valid_rejection_jobs=sum(job['valid_rejection_job'] for job in jobs),
        all_infeasible_jobs_validly_rejected=(expected_feasible is False and
                                             all(job['valid_rejection_job'] for job in jobs)),
        main=main, warmups=warm, physical_tolerances=tolerances,
        qualified_latency=eligible, exclusion_reasons=reasons,
        median_process_accepted_p50_ms=(median([job['main']['accepted_p50_ms'] for job in jobs])
                                        if eligible else None),
        median_process_accepted_p95_ms=(median([job['main']['accepted_p95_ms'] for job in jobs])
                                        if eligible else None),
        descriptive_only=dict(
            available_accepted_processes=sum(job['main']['accepted_p50_ms'] is not None for job in jobs),
            median_available_process_accepted_p50_ms=median([job['main']['accepted_p50_ms'] for job in jobs]),
            median_available_process_accepted_p95_ms=median([job['main']['accepted_p95_ms'] for job in jobs]),
            median_available_process_all_p50_ms=median([job['main']['all_p50_ms'] for job in jobs]),
            median_available_process_all_p95_ms=median([job['main']['all_p95_ms'] for job in jobs]),
        ),
        sample_counts_per_process=sorted({job['main']['expected'] for job in jobs}),
        warmup_counts_per_process=sorted({job['warmups']['expected'] for job in jobs}),
        source_commits=sorted({job['source_commit'] for job in jobs if job['source_commit']}),
        executable_sha256=sorted({job['executable_sha256'] for job in jobs if job['executable_sha256']}),
        extra_artifact_content_sha256=sorted({job['extra_artifact_content_sha256'] for job in jobs}),
        semantic_request_sha256=sorted({job['semantic_request_sha256'] for job in jobs
                                        if job['semantic_request_sha256']}),
        job_refs=[dict(run_id=job['run_id'], job_name=job['job_name'], round=job['round']) for job in jobs],
    )


def analyze_runs(roots: list[pathlib.Path], include_metrics: bool = False) -> dict:
    roots = [root.resolve() for root in roots]
    if len(set(roots)) != len(roots):
        raise ValueError('The same run directory was supplied more than once')
    inputs, jobs = [], []
    for index, root in enumerate(roots, 1):
        provenance, found = load_run(root, f'run-{index:03d}', include_metrics)
        inputs.append(provenance)
        jobs.extend(found)
    grouped = defaultdict(list)
    for job in jobs:
        grouped[(job['fixture_id'], job['mode'], job['engine'])].append(job)
    groups = [aggregate_group(grouped[key]) for key in sorted(grouped)]
    return dict(
        schema_version=1, analyzer_sha256=digest(pathlib.Path(__file__).read_bytes()),
        method=dict(
            source='Saved checked oracle verdicts and request/summary/manifests; no solver execution',
            process_percentiles='sorted elapsed milliseconds at ceil((n-1)*p)',
            aggregation='Unweighted median of per-process accepted p50 and p95; not pooled samples',
            qualification='Every planned/included job complete, checked raw available, every measured sample accepted, '
                          'no measured-sample adapter exception or oracle disagreement, '
                          'compatible request/executable/extra-artifact-content/environment/options',
            warmups='Excluded from latency; accepted and exceptional counts disclosed separately',
            invalid_or_partial='Retained in counts and descriptive_only; never qualified successful-solve latency',
            valid_rejection='A checked emitted physical rejection without adapter_error; not an infeasibility proof',
            contradictions='No success credit for exceptions, missing operations or timeouts; reported separately',
            normalized_error='Maximum finite saved physical error divided by the exact request tolerance; '
                             'error_unavailable counts omitted/nonfinite errors',
            tail='Per-process p95 with small samples is descriptive; no p99 or composite score is produced',
            scope='Native adapter construction/update + solve + extraction, not browser/FFI/application latency',
        ),
        inputs=inputs, groups=groups, jobs=jobs,
        totals=dict(inputs=len(inputs), groups=len(groups), jobs=len(jobs),
                    complete_jobs=sum(job['complete'] for job in jobs),
                    qualified_latency_groups=sum(group['qualified_latency'] for group in groups),
                    missing_planned_jobs=sum(not job['present'] for job in jobs)),
    )


def cell(value: object) -> str:
    if value is None:
        return '—'
    return str(value).replace('|', '\\|').replace('\n', ' ')


def number(value: float | None) -> str:
    return '—' if value is None else f'{value:.6g}'


def fraction(a: int | None, b: int | None) -> str:
    return f'{cell(a)}/{cell(b)}'


def table(headers: list[str], rows: list[list[object]]) -> list[str]:
    return ['| ' + ' | '.join(headers) + ' |',
            '| ' + ' | '.join('---' for _ in headers) + ' |',
            *['| ' + ' | '.join(cell(value) for value in row) + ' |' for row in rows]]


def markdown(report: dict) -> str:
    lines = ['# Saved solver benchmark analysis', '',
             'This report reads saved evidence only. It does not execute solvers or reinterpret '
             'geometry using a newer oracle. Detailed job records and source manifests are in analysis.json.', '',
             '## Input provenance', '']
    lines += table(['Run', 'Suite', 'Source commit', 'Jobs present / planned', 'Summary file'], [
        [item['run_id'], item['manifest'].get('suite'),
         (item['manifest'].get('source_commit') or '')[:12],
         fraction(item['present_jobs'], item['present_jobs'] + item['missing_planned_jobs']),
         pathlib.Path(item['summary_file']).name]
        for item in report['inputs']])
    lines += ['', 'Input directories:', '']
    lines += [f'- {item["run_id"]}: {item["directory"]}' for item in report['inputs']]
    lines += ['', '## Completeness and physical outcomes', '',
              'Accepted counts refer to the independent saved physical oracle. Native numerical '
              'success followed by physical rejection is a separate observation, not automatically '
              'an incorrect claim of hard feasibility. Missing operations and adapter exceptions '
              'receive no credit as successful rejection of contradictory inputs.', '']
    lines += table(
        ['Fixture', 'Engine', 'Mode', 'Complete jobs', 'Accepted / expected',
         'Warmup accepted / expected', 'Valid rejections', 'Exceptions',
         'Native success rejected', 'Oracle disagreements', 'Timeout jobs'], [
            [group['fixture_id'], group['engine'], group['mode'],
             fraction(group['complete_jobs'], group['jobs']),
             fraction(group['main']['accepted'], group['main']['expected']),
             fraction(group['warmups']['accepted'], group['warmups']['expected']),
             group['main']['valid_rejections'], group['main']['adapter_exceptions'],
             group['main']['native_success_rejected'], group['acceptance_disagreements'],
             group['timeout_jobs']]
            for group in report['groups']])
    lines += ['', '## Qualified successful-solve latency', '',
              'Each value is the median of per-process accepted-sample percentiles, giving each '
              'process equal weight. It is not a percentile of pooled observations. Both columns '
              'are withheld unless every included/planned job is complete and every measured '
              'sample is accepted, without oracle disagreement or incompatible build/request conditions. '
              'Warmups are counted above but excluded from latency.', '',
              'A five-sample process p95 is its largest observation under the recorded upper-order '
              'statistic method. These tables do not establish stable p99 performance.', '']
    lines += table(
        ['Fixture', 'Engine', 'Mode', 'Processes', 'Median process p50 ms',
         'Median process p95 ms', 'Max finite error / tolerance', 'Qualification'], [
            [group['fixture_id'], group['engine'], group['mode'], group['jobs'],
             number(group['median_process_accepted_p50_ms']),
             number(group['median_process_accepted_p95_ms']),
             number(group['main']['max_finite_error_over_tolerance']),
             'qualified' if group['qualified_latency'] else ', '.join(group['exclusion_reasons'])]
            for group in report['groups']])
    excluded = [group for group in report['groups'] if not group['qualified_latency']]
    if excluded:
        lines += ['', '## Partial or rejected results: descriptive only', '',
                  'These statistics retain completed observations from excluded groups. They must '
                  'not be ranked as successful-solve latency. An accepted subset can be easier than '
                  'the missing or rejected operations. Process timeouts are whole-job limits.', '']
        lines += table(
            ['Fixture', 'Engine', 'Mode', 'Observed / expected', 'Accepted subset processes',
             'Available accepted p50 ms', 'Available accepted p95 ms', 'All-observation p50 ms'], [
                [group['fixture_id'], group['engine'], group['mode'],
                 fraction(group['main']['completed'], group['main']['expected']),
                 group['descriptive_only']['available_accepted_processes'],
                 number(group['descriptive_only']['median_available_process_accepted_p50_ms']),
                 number(group['descriptive_only']['median_available_process_accepted_p95_ms']),
                 number(group['descriptive_only']['median_available_process_all_p50_ms'])]
                for group in excluded])
    inconsistent = [group for group in report['groups'] if group['expected_feasible'] is False]
    if inconsistent:
        lines += ['', '## Contradictory fixtures', '',
                  'Valid rejection means a checked emitted physical rejection without an adapter '
                  'exception. It is not a mathematical infeasibility certificate.', '']
        lines += table(['Fixture', 'Engine', 'Mode', 'Valid rejected / expected',
                        'Complete valid-rejection jobs', 'All jobs validly rejected'], [
            [group['fixture_id'], group['engine'], group['mode'],
             fraction(group['main']['valid_rejections'], group['main']['expected']),
             fraction(group['valid_rejection_jobs'], group['jobs']),
             group['all_infeasible_jobs_validly_rejected']]
            for group in inconsistent])
    lines += ['', '## Reading limits', '',
              '- Native adapter measurements exclude JSON, the external checker, browser/FFI '
              'integration and the full CAD application.',
              '- Scalar coordinates are unfixed parameters before geometric constraints, not remaining DOF.',
              '- Different sample or warmup counts per process are retained in JSON; select a consistent '
              'confirmation cohort when making a publication claim.',
              '- Error ratios use each request tolerance. Missing/nonfinite errors are counted separately '
              'in JSON and are not silently converted into zero.',
              '- Full manifests, binary/source hashes, archive hashes when read, per-job checksums, '
              'exclusions and optional engine metrics are in analysis.json.', '']
    return '\n'.join(lines)


def write_report(report: dict, output: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    output.mkdir(parents=True, exist_ok=True)
    json_path, markdown_path = output / 'analysis.json', output / 'analysis.md'
    json_path.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    markdown_path.write_text(markdown(report))
    return json_path, markdown_path


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', type=pathlib.Path, nargs='+')
    parser.add_argument('--out', type=pathlib.Path, required=True)
    parser.add_argument('--metrics', action='store_true',
                        help='Include optional scalar engine work/decomposition metrics per process')
    args = parser.parse_args(argv)
    report = analyze_runs(args.runs, include_metrics=args.metrics)
    json_path, markdown_path = write_report(report, args.out)
    print(json.dumps(dict(json=str(json_path), markdown=str(markdown_path), **report['totals'])))


if __name__ == '__main__':
    main()

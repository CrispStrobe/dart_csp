#!/usr/bin/env python3
"""Replay the five preserved blocks; an incomplete cohort can never retain.

This recovery wrapper does not change the frozen auditor or decision rules.
It first runs that auditor and requires its missing-block rejection, then uses
the same frozen source, schedule, geometry, percentile and transport checks on
every available block. It never runs a solver, compiler or measurement.
"""
from __future__ import annotations

import argparse
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace


SAVED = Path('benchmark/results/2026-11-15-cg-norm-fusion')
RECOVERED_HEAD = '9418d2284e8eb55a2e9c989fb655788c391cc0a4'
BLOCKS = ('norm-round1', 'aa-round1', 'norm-round2', 'aa-round2', 'norm-round3')
MISSING = ('aa-round3', 'norm-round4', 'aa-round4')
STRICT_ERROR = ('ValueError: Measurement block population differs; '
                'qualification belongs outside runs/')


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def save_report(path, value):
    data = (json.dumps(value, indent=2, allow_nan=False) + '\n').encode()
    path.write_bytes(gzip.compress(data, mtime=0))


def checksums(out, wrapper):
    """Bind report files relative to out, and the reusable source separately."""
    files = {}
    for path in sorted(out.iterdir()):
        if path.is_file() and path.name != 'checksums.json':
            files[path.name] = {
                'bytes': path.stat().st_size, 'sha256': digest(path)}
    save(out / 'checksums.json', {
        'schema': 'dart-csp-norm-replay-checksums-v1',
        'files_relative_to': 'directory containing checksums.json',
        'reusable_wrapper': {'filename': wrapper.name,
                             'bytes': wrapper.stat().st_size,
                             'sha256': digest(wrapper)},
        'files': files,
    })


def markdown(report):
    lines = ['# Recovered partial CG norm-fusion evidence', '',
             '**Decision: revert the provisional candidate because the declared '
             'same-session cohort is incomplete.**', '',
             f"Available-evidence replay passed: **{report['available_evidence_passed']}**. "
             'The complete eight-block protocol did **not** pass; retention is '
             'not allowed. The original auditor remains unchanged and rejects '
             'the missing measurement inventory.', '',
             'Five of eight blocks survive: candidate rounds 1–3 and A/A rounds '
             '1–2. Missing: A/A round 3, candidate round 4, A/A round 4. No new '
             'measurement was collected and no replacement session was pooled.', '',
             '## Recovered populations', '',
             '| Population | Processes | Measured | Warmups | Raw records | Exact non-timing pairs |',
             '| --- | ---: | ---: | ---: | ---: | ---: |']
    for name, cohort in report.get('cohorts', {}).items():
        counts = cohort['counts']
        lines.append(f"| {name} | {counts['jobs']} | {counts['measured_operations']} | "
                     f"{counts['warmup_operations']} | {counts['raw_records']} | "
                     f"{counts['paired_non_time_operations_compared']} |")
    if report.get('qualification'):
        c = report['qualification']['counts']
        lines.extend(['', f"Qualification is separate: {c['processes']} processes, "
                      f"{c['raw_records']} raw operations, {c['accepted']} accepted, "
                      f"{c['expected_rejections']} expected contradictory rejections, "
                      f"{c['exact_non_time_pairs']} exact non-timing pairs."])
    lines += ['', '## Descriptive observations only', '',
              'All complete-operation p50 and p95 values below are recomputed '
              'from raw measurements. Each process pair has equal weight. '
              'Candidate strata have unequal pair counts (two versus one); '
              'A/A strata have one pair each. Four-round performance, stability '
              'and tail gates are **not evaluated** on these partial data. '
              'A/A is never subtracted and cannot excuse adverse results. '
              'These short-cohort percentiles are not population tail bounds.', '']
    def pct(value):
        return 'n/a' if value is None else f'{100 * (value - 1):+.2f}%'
    for name, cohort in report.get('cohorts', {}).items():
        lines += [f'### {name}: rounds ' + ', '.join(map(str, cohort['round_numbers'])), '',
                  '| Fixture | Engine | Mode | Before / after median process p50, ms | Median paired p50 change | Ratio of median process p50 change | Round p50 changes | Round p95 changes | Before-first / after-first p50 changes (pair counts) |',
                  '| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |']
        for row in cohort['groups']:
            p = row['timing']['elapsed_ns']['p50_ms']
            q = row['timing']['elapsed_ns']['p95_ms']
            strata = p['order_strata']
            orders = ' / '.join(pct(strata[k]['median_paired_ratio']) +
                                f" ({strata[k]['pairs']})" for k in
                                ('before_first', 'after_first'))
            lines.append('| ' + ' | '.join((row['fixture_id'], row['engine'], row['mode'],
                f"{p['before_median_process_statistic']:.6f} / {p['after_median_process_statistic']:.6f}",
                pct(p['median_paired_ratio']), pct(p['ratio_of_median_process_statistics']),
                ', '.join(map(pct, p['round_ratios'])), ', '.join(map(pct, q['round_ratios'])),
                orders)) + ' |')
        lines.append('')
    if report['errors']:
        lines += ['## Replay failures', '', *('- ' + e for e in report['errors'])]
    lines += ['', '## Machine-readable evidence', '',
              '`partial-audit.json.gz` contains the complete JSON report. '
              'It uses gzip with zero modification time; decompression recovers '
              'the exact report bytes. `executed-evidence-replay.py.gz` preserves '
              'the wrapper executed for this audit and matches the report’s '
              '`script_sha256`. The checksum manifest also binds the current '
              'reusable wrapper separately. Its file entries use paths relative '
              'to this audit directory.', '']
    return '\n'.join(lines).rstrip() + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True,
                        help='New scratch directory for restored artifacts')
    parser.add_argument('--out', type=Path, required=True,
                        help='New report directory; contains no duplicated raw archives')
    args = parser.parse_args()
    repo, workspace, out = (p.resolve() for p in (args.repo, args.workspace, args.out))
    if workspace.exists() or out.exists():
        raise ValueError('Choose new workspace and output directories; recovery never overwrites')
    out.mkdir(parents=True)
    (out / 'executed-evidence-replay.py.gz').write_bytes(
        gzip.compress(Path(__file__).read_bytes(), mtime=0))
    saved = repo / SAVED
    report = {
        'schema': 'dart-csp-norm-partial-replay-v1',
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'script_sha256': digest(Path(__file__)),
        'recovered_remote_commit': RECOVERED_HEAD,
        'available_blocks': list(BLOCKS), 'missing_blocks': list(MISSING),
        'available_evidence_passed': False,
        'full_declared_same_session_protocol': False,
        'retain_allowed': False,
        'performance_gates_evaluated': False,
        'overall_decision': 'revert_incomplete_cohort',
        'reason': 'Mandatory eight-block same-session completion is absent; '
                  'the declaration forbids new-session appends or replacement runs.',
        'solver_executions': 0, 'new_measurements': 0,
        'cohorts': {}, 'errors': [],
    }
    try:
        frozen = load_module('frozen_norm_audit', saved / 'audit_norm_fusion.py')
        transport = load_module('norm_recovery_transport', repo / frozen.SCRIPT_PATHS['packer'])
        declaration = frozen.read(saved / 'declaration.json')
        recovery = frozen.read(saved / 'recovery.json')
        frozen.require(tuple(declaration['protocol']['block_order']) == BLOCKS + MISSING,
                       'Recovered block prefix differs from declared order')
        frozen.require(declaration['auditor_sha256'] == digest(saved / 'audit_norm_fusion.py'),
                       'Frozen auditor was modified')
        frozen.require(declaration['protocol'] == frozen.PROTOCOL and
                       declaration['decision_rules'] == frozen.DECISION_RULES,
                       'Frozen protocol or decision rules were modified')
        evidence_names = sorted(p.name.removesuffix('-evidence.json')
                                for p in saved.glob('*-round*-evidence.json'))
        frozen.require(evidence_names == sorted(BLOCKS), 'Unexpected saved block inventory')
        original_paths = {saved / 'declaration.json', saved / 'recovery.json',
                          saved / 'audit_norm_fusion.py', saved / 'validation-index.json'}
        for name in ('prepared', 'qualification', *BLOCKS):
            manifest_path = saved / (name + '-evidence.json')
            manifest = frozen.read(manifest_path)
            original_paths.add(manifest_path)
            original_paths.update(saved / item['file'] for item in manifest['archive_parts'])
        for name in ('qualification', *BLOCKS):
            original_paths.update(saved / (name + suffix)
                                  for suffix in ('-status.json', '-summary.json', '.log'))
        for path in sorted(original_paths):
            previous = frozen.git(repo, 'show', RECOVERED_HEAD + ':' + path.relative_to(repo).as_posix())
            frozen.require(previous == path.read_bytes(), 'Saved original changed: ' + str(path))
        report['original_files_verified_against_recovered_commit'] = len(original_paths)
        report['frozen_declaration_sha256'] = digest(saved / 'declaration.json')
        report['frozen_auditor_sha256'] = digest(saved / 'audit_norm_fusion.py')
        restores = {}
        for name in ('prepared', 'qualification', *BLOCKS):
            destination = (workspace / name if name in ('prepared', 'qualification')
                           else workspace / 'runs' / name)
            restores[name] = transport.restore(saved / (name + '-evidence.json'), destination)
        report['exact_archive_restores'] = restores
        report['exact_archive_files_restored'] = sum(v['files'] for v in restores.values())
        strict_dir = workspace / 'strict-full-audit'
        command = [sys.executable, str(saved / 'audit_norm_fusion.py'), '--repo', str(repo),
                   '--prepared', str(workspace / 'prepared'), '--runs', str(workspace / 'runs'),
                   '--qualification', str(workspace / 'qualification'), '--saved', str(saved),
                   '--declaration', str(saved / 'declaration.json'),
                   '--validation-index', str(saved / 'validation-index.json'), '--out', str(strict_dir)]
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=180)
        (out / 'full-protocol.stdout.log').write_text(result.stdout)
        (out / 'full-protocol.stderr.log').write_text(result.stderr)
        strict = frozen.read(strict_dir / 'audit.json')
        for name in ('audit.json', 'audit.md'):
            shutil.copyfile(strict_dir / name, out / ('full-protocol-' + name))
        report['original_full_auditor'] = {
            'command': command, 'exit_code': result.returncode,
            'evidence_passed': strict['evidence_passed'],
            'overall_decision': strict['overall_decision'], 'errors': strict['errors'],
            'expected_missing_inventory_rejection': True,
        }
        frozen.require(result.returncode == 1 and strict['evidence_passed'] is False and
                       strict['errors'] == [STRICT_ERROR],
                       'Full auditor did not reject solely the expected missing inventory')
        analyzer = frozen.module('norm_partial_raw', repo / frozen.SCRIPT_PATHS['raw_analyzer'])
        oracle = frozen.module('norm_partial_oracle', repo / frozen.SCRIPT_PATHS['oracle'])
        fixtures = frozen.module('norm_partial_fixtures', repo / frozen.SCRIPT_PATHS['fixtures'])
        cases = {}
        for suite in ('smoke', 'confirm', 'coupled'):
            for case in fixtures.corpus(suite):
                identity = case['fixture']['id']
                frozen.require(identity not in cases or cases[identity] == case,
                               'Conflicting frozen corpus fixture')
                cases[identity] = case
        requests = {}
        for fid in set(frozen.FIXTURES) | set(frozen.QUALIFICATION):
            for engine, mode in itertools.product(frozen.ENGINES, frozen.MODES):
                for samples, warmups in ((21, 8), (2, 1)):
                    requests[(fid, engine, mode, samples, warmups)] = analyzer.canonical(
                        fixtures.request(cases[fid], engine, mode, warmups, samples))
        inputs = SimpleNamespace(repo=repo, prepared=workspace / 'prepared')
        preparations, provenance = frozen.check_preparations(inputs, declaration, analyzer)
        qualification, qualification_intervals = frozen.audit_qualification(
            workspace / 'qualification', preparations['norm'], declaration, recovery,
            analyzer, oracle, requests)
        report['qualification'] = qualification
        report['preparation_audit'] = provenance
        statuses = {'declaration': digest(saved / 'declaration.json'),
                    'recovery': digest(saved / 'recovery.json')}
        groups, transports = collections.defaultdict(list), {}
        totals = collections.Counter()
        intervals, block_intervals, environments = list(qualification_intervals), [], set()
        for name in BLOCKS:
            cohort, number = name.split('-round')
            number = int(number)
            directory = workspace / 'runs' / name
            status = frozen.read(saved / (name + '-status.json'))
            _, jobs = frozen.metadata_run(directory, preparations[cohort], declaration, recovery,
                name, cohort, number, status, statuses, expected_requests=requests)
            frozen.require(frozen.stamp(qualification['finished_utc']) <= frozen.stamp(status['started_utc']),
                           'Measurement started before qualification finished')
            transports[name] = frozen.audit_transport(saved, directory, name, workspace / 'transport-recheck',
                                                      transport, status)
            raw = analyzer.audit_run(directory, number, preparations[cohort], provenance[cohort], oracle)
            frozen.require(not raw['non_time_mismatches'], name + ': paired non-timing records differ')
            wanted = {'jobs': 32, 'measured_operations': 672, 'warmup_operations': 256,
                      'raw_records': 928, 'accepted_operations': 928,
                      'process_percentiles_verified': 64, 'paired_non_time_operations_compared': 464}
            frozen.require(raw['counts'] == wanted, name + ': raw population differs')
            intervals.extend(jobs)
            block_intervals.append((frozen.stamp(status['started_utc']),
                                    frozen.stamp(status['packed_utc']), name))
            environments.add(raw['environment_sha256'])
            totals.update(raw['counts'])
            groups[cohort].append(raw)
            print(json.dumps({'block': name, 'available_evidence_passed': True,
                              'counts': raw['counts']}), flush=True)
        ordered = frozen.nonoverlap(block_intervals, 'Recovered collection and packing')
        frozen.require([item[2] for item in ordered] == list(BLOCKS), 'Recovered block prefix out of order')
        frozen.nonoverlap(intervals, 'Recovered qualification and measured solver processes')
        frozen.require(len(environments) == 1, 'Saved blocks span different runtime environments')
        for cohort, rounds in groups.items():
            counts = collections.Counter()
            for raw in rounds:
                counts.update(raw['counts'])
            report['cohorts'][cohort] = {
                'round_numbers': [r['round'] for r in rounds], 'counts': dict(counts),
                'rounds': rounds, 'groups': analyzer.aggregate([row for r in rounds for row in r['rows']]),
            }
        validation = frozen.check_validation(saved / 'validation-index.json', declaration, repo, ordered[0][0])
        frozen.require(validation['passed'], 'Original source-bound correctness evidence did not verify')
        report.update(available_evidence_passed=True, counts=dict(totals),
                      block_transport_recheck=transports, correctness_validation=validation,
                      original_measurement_session=declaration['session_id'],
                      complete_cohort_expected_counts=declaration['protocol'],
                      observed_environment_sha256=next(iter(environments)))
    except Exception as error:
        report['errors'].append(type(error).__name__ + ': ' + str(error))
    finally:
        report['completed_utc'] = datetime.now(timezone.utc).isoformat()
        save_report(out / 'partial-audit.json.gz', report)
        (out / 'partial-audit.md').write_text(markdown(report))
        checksums(out, Path(__file__))
    print(json.dumps({k: report[k] for k in ('available_evidence_passed', 'retain_allowed',
                                            'overall_decision', 'errors')}), flush=True)
    return 0 if report['available_evidence_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

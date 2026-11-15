#!/usr/bin/env python3
"""Audit the 13 immutable saved blocks against the declared protocol.

Uses the saved independent coordinate/percentile analyzer, with an additional
fixed declaration/population check and archive hash verification. Does not run
a solver and does not pool measurements with a later session.
"""
from __future__ import annotations
import argparse
import collections
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

FIXTURES = ['axis_rectangle', 'ladder_3_components_1',
            'ladder_25_components_1', 'ladder_500_components_1',
            'laman_free_100', 'laman_free_500']
ROUNDS = {'cg': 4, 'identity': 3, 'combined': 3, 'aa': 3}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def ensure(value, label):
    if not value:
        raise ValueError(label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--runs', type=Path, required=True)
    parser.add_argument('--saved', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    ROOT, PREP, OUT = args.repo.resolve(), args.prepared.resolve(), args.out.resolve()
    SAVED = (args.saved or ROOT / 'benchmark/results/2026-11-14-optimization-final').resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    audit = load_module('saved_analyzer', ROOT / 'benchmark/results/2026-11-14-optimization-recovery/analyze_recovery.py')
    oracle = load_module('independent_physical_oracle', ROOT / 'benchmark/solver_comparison/oracle.py')
    report = {'schema_version': 1, 'passed': False,
              'scope': 'All 13 complete immutable blocks from original final session d1244c09828b; excludes new resumed-session blocks.',
              'declaration': {'samples': 21, 'warmups': 8, 'timeout_seconds': 30,
                              'pinned_cpu': 0, 'engines': ['dart_2d_analytic', 'dart_3d_ad'],
                              'modes': ['cold', 'warm'], 'rounds': ROUNDS,
                              'expected_processes': 600, 'expected_measured_operations': 12600,
                              'expected_warmup_operations': 4800},
              'cohorts': {}, 'non_time_mismatch_count': 0,
              'artifact_checks': [], 'errors': []}
    recovery_sha = digest((SAVED / 'recovery.json').read_bytes())
    all_environments = set()
    intervals = []
    try:
        for cohort, total in ROUNDS.items():
            preparation, provenance = audit.audit_prepared(PREP / ('prepared-' + cohort), ROOT)
            ensure(all(v['executable_bytes_present_and_verified'] for v in provenance['variants'].values()), 'Missing executable bytes')
            if cohort == 'aa':
                before, after = (preparation['variants'][s] for s in ('before', 'after'))
                ensure(before['executable_sha256'] == after['executable_sha256'], 'A/A binary mismatch')
                ensure(before['source_archive_sha256'] == after['source_archive_sha256'], 'A/A source archive mismatch')
            runs = []
            for n in range(1, total + 1):
                name = f'{cohort}-round{n}'
                directory = args.runs / name
                manifest = load(directory / 'manifest.json')
                status = load(SAVED / (name + '-status.json'))
                ensure(status['session_id'] == 'd1244c09828b', name + ': wrong session')
                ensure(status['recovery_sha256'] == recovery_sha, name + ': recovery manifest changed')
                ensure(status['passed'] and status['exit_code'] == 0 and status['pack_exit_code'] == 0,
                       name + ': status not complete and passing')
                for k in ('samples', 'warmups', 'timeout_seconds', 'pinned_cpu', 'engines', 'modes'):
                    ensure(manifest[k] == report['declaration'][k], name + ': declaration mismatch ' + k)
                ensure(manifest['fixture_ids'] == (FIXTURES[:-1] if cohort == 'aa' else FIXTURES), name + ': fixture declaration differs')
                ensure(manifest['purpose'] == 'measurement', name + ': wrong purpose')
                evidence = load(SAVED / (name + '-evidence.json'))
                data = b''.join((SAVED / p['file']).read_bytes() for p in evidence['archive_parts'])
                ensure(digest(data) == evidence['archive_sha256'] and len(data) == evidence['archive_bytes'], name + ': archive integrity')
                for part in evidence['archive_parts']:
                    raw = (SAVED / part['file']).read_bytes()
                    ensure(digest(raw) == part['sha256'] and len(raw) == part['bytes'], name + ': part integrity')
                paths = {p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file()}
                ensure(paths == set(evidence['files']), name + ': restored file membership')
                for path, entry in evidence['files'].items():
                    raw = (directory / path).read_bytes()
                    ensure(digest(raw) == entry['sha256'] and len(raw) == entry['bytes'], name + ': restored file digest ' + path)
                ensure((directory / 'comparison.json').read_bytes() == (SAVED / (name + '-summary.json')).read_bytes(), name + ': external summary differs')
                result = audit.audit_run(directory, n, preparation, provenance, oracle)
                for row in result['rows']:
                    parity = ((n - 1) + manifest['fixture_ids'].index(row['fixture_id'])
                              + manifest['modes'].index(row['mode'])
                              + manifest['engines'].index(row['engine'])) % 2
                    expected_first = 'after' if parity else 'before'
                    ensure(row['first'] == expected_first,
                           name + ': process order differs from declared harness')
                counts = result['counts']
                jobs = 40 if cohort == 'aa' else 48
                for field, expected in [('jobs', jobs), ('measured_operations', jobs*21),
                                        ('warmup_operations', jobs*8), ('accepted_operations', jobs*29),
                                        ('paired_non_time_operations_compared', jobs*29//2),
                                        ('process_percentiles_verified', jobs*2)]:
                    ensure(counts[field] == expected, name + ': raw count mismatch ' + field)
                all_environments.add(result['environment_sha256'])
                report['non_time_mismatch_count'] += len(result['non_time_mismatches'])
                report['artifact_checks'].append({'block': name, 'files': len(paths),
                    'archive_sha256': evidence['archive_sha256'], 'summary_sha256': digest((directory/'comparison.json').read_bytes()),
                    'all_declared_inputs_and_counts_match': True})
                intervals.append({'block': name, 'started': manifest['started_utc'],
                                  'finished': manifest['finished_utc'], 'analysis_finished': manifest['analysis_finished_utc']})
                runs.append(result)
                print(json.dumps({'block': name, 'verified': counts, 'mismatches': len(result['non_time_mismatches'])}), flush=True)
            counts = collections.Counter()
            for r in runs:
                counts.update(r['counts'])
            report['cohorts'][cohort] = {'preparation_audit': provenance, 'counts': dict(counts),
                                       'rounds': runs, 'groups': audit.aggregate([row for r in runs for row in r['rows']])}
        actual_order = [v['block'] for v in sorted(intervals, key=lambda v: v['started'])]
        expected_order = [f'{c}-round{n}' for n in range(1, 5) for c in ROUNDS if n <= ROUNDS[c]]
        ensure(actual_order == expected_order, 'Block order differs from declaration')
        ordered = sorted(intervals, key=lambda v: v['started'])
        ensure(all(a['analysis_finished'] <= b['started'] for a,b in zip(ordered,ordered[1:])), 'Blocks or block audits overlapped')
        ensure(len(all_environments) == 1, 'Saved blocks have different environment fingerprints')
        ensure(report['non_time_mismatch_count'] == 0, 'Non-timing outputs differ')
        totals = collections.Counter()
        for c in report['cohorts'].values():
            totals.update(c['counts'])
        for field, expected in [('jobs', 600), ('measured_operations', 12600),
                                ('warmup_operations', 4800), ('raw_records', 17400),
                                ('paired_non_time_operations_compared', 8700)]:
            ensure(totals[field] == expected, 'Total declaration mismatch: ' + field)
        controls = {audit.key_for(g): g for g in report['cohorts']['aa']['groups']}
        for cohort in report['cohorts'].values():
            for group in cohort['groups']:
                control = controls.get(audit.key_for(group))
                if control:
                    p = control['timing']['elapsed_ns']['p50_ms']
                    group['aa_observation'] = {'p50_min_ratio': p['minimum_paired_ratio'],
                        'p50_max_ratio': p['maximum_paired_ratio'],
                        'interpretation': 'Observed original-session three-round variation only; no noise subtraction or causal exemption.'}
                else:
                    group['aa_observation'] = None
        report['counts'] = dict(totals)
        report['chronology'] = ordered
        report['environment_sha256'] = next(iter(all_environments))
        report['passed'] = True
    except Exception as error:
        report['errors'].append(f'{type(error).__name__}: {error}')
        raise
    finally:
        (OUT / 'saved-block-audit.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n')
        if report['cohorts']:
            rendered = audit.markdown(report).replace('Four round p50 effects', 'Recorded round p50 effects')
            rendered = rendered.replace('# Independent recovery benchmark audit',
                '# Independent audit of 13 saved blocks\n\nOriginal session `d1244c09828b` only. CG has four rounds; identity, combined and A/A have three.\nLater resumed-session evidence must remain separate.\n')
            (OUT / 'saved-block-audit.md').write_text(rendered)
    print(json.dumps({'passed':report['passed'], 'counts':report.get('counts'), 'out':str(OUT)}), flush=True)


if __name__ == '__main__':
    main()

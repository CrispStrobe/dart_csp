#!/usr/bin/env python3
"""Reconcile and assess the two isolated tail cohorts without rerunning Dart.

Only standard-library code is used. No project summarizer or auditor is imported.
Every summary row and adverse pair is retained. Derived p99 values for a
25-sample legacy control are maxima, not reliable estimates of population p99.
"""
import argparse
import collections
import datetime
import hashlib
import io
import json
import math
from pathlib import Path
import statistics
import subprocess
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments])


def scan(value, path=(), metadata=None):
    metadata = dict(metadata or {})
    if isinstance(value, list):
        for index, child in enumerate(value):
            label = f"features={child['feature_count']}" if isinstance(child, dict) and 'feature_count' in child else str(index)
            yield from scan(child, (*path, label), metadata)
        return
    if not isinstance(value, dict):
        return
    for key in ('units', 'operations_per_batch', 'feature_count', 'components', 'rows', 'columns'):
        if key in value:
            metadata[key] = value[key]
    if 'p50' in value and 'p95' in value:
        yield '/'.join(path), value, metadata
    else:
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                yield from scan(child, (*path, key), metadata)


class Audit:
    def __init__(self):
        self.checks = 0
        self.findings = []
        self.counts = collections.Counter()

    def check(self, condition, message):
        self.checks += 1
        if not condition:
            self.findings.append(message)

    def same(self, actual, expected, message):
        self.check(actual == expected, message)


def compare(values_before, values_after):
    before, after = statistics.median(values_before), statistics.median(values_after)
    changes = [100 * (a / b - 1) if b else None
               for b, a in zip(values_before, values_after)]
    finite_changes = [value for value in changes if value is not None]
    return {
        'before': values_before, 'after': values_after,
        'median_before': before, 'median_after': after,
        'aggregate_change_percent': 100 * (after / before - 1) if before else None,
        'paired_change_percent': changes,
        'median_paired_change_percent': statistics.median(finite_changes) if finite_changes else None,
        'faster_pairs': sum(a < b for b, a in zip(values_before, values_after)),
        'slower_pairs': sum(a > b for b, a in zip(values_before, values_after)),
        'equal_pairs': sum(a == b for b, a in zip(values_before, values_after)),
    }


def check_sources(audit, raw, before_root, after_root, expected_changed):
    roots = {'before': before_root, 'after': after_root}
    for label, root in roots.items():
        identity = raw['revisions'][label]
        commit = identity['commit']
        audit.same(identity['library_diff_sha256'], None, f'{label}: recorded library patch')
        audit.same(git(root, 'rev-parse', commit + ':lib').decode().strip(),
                   identity['library_tree'], f'{label}: library tree')
        archive = git(root, 'archive', commit, 'lib')
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            for member in source.getmembers():
                if member.isfile():
                    audit.same((root / member.name).read_bytes(),
                               source.extractfile(member).read(), f'{label}: source {member.name}')
                    audit.counts['committed_library_files_checked'] += 1
        audit.same(git(root, 'status', '--porcelain=v1', '--', 'lib'), b'',
                   f'{label}: dirty source worktree')
        audit.same(sha((root / 'pubspec.lock').read_bytes()), identity['dependency_lock_sha256'],
                   f'{label}: dependency lock')
        for fixture, harness in raw['harnesses'].items():
            audit.same(sha((root / harness['file']).read_bytes()), harness['sha256'],
                       f'{label}/{fixture}: harness identity')
            for path, expected in harness.get('dependency_sha256', {}).items():
                audit.same(sha((root / path).read_bytes()), expected,
                           f'{label}/{fixture}: example identity {path}')
        config_path = root / '.dart_tool/package_config.json'
        package = next(item for item in json.loads(config_path.read_bytes())['packages']
                       if item['name'] == 'dart_csp')
        audit.same((config_path.parent / package['rootUri']).resolve(), root.resolve(),
                   f'{label}: own package root')
    audit.same(raw['revisions']['before']['dependency_lock_sha256'],
               raw['revisions']['after']['dependency_lock_sha256'], 'same dependency lock')
    changed = git(before_root, 'diff', '--name-only', raw['revisions']['before']['commit'],
                  raw['revisions']['after']['commit'], '--', 'lib').decode().splitlines()
    audit.same(changed, [expected_changed], 'isolated candidate source scope')


def physical_work(audit, fixture, case, work, index, warmups, label):
    fields = ('residual_evaluations', 'jacobian_evaluations', 'linear_solves',
              'linear_iterations', 'nonlinear_iterations', 'rank_factorizations', 'rank_reuses')
    audit.check(all(type(work[field]) is int and work[field] >= 0 for field in fields),
                label + ': physical counter types/ranges')
    if fixture == 'cad':
        thickness = case.startswith('thickness')
        closure = ['plate', 'mesh'] if thickness else ['sketch', 'profile', 'plate', 'mesh']
        audit.same(work['rebuilt_features'], closure, label + ': plate closure')
        audit.same(work['geometry_solve_invoked'], not thickness, label + ': plate solve')
        if thickness:
            audit.check(all(work[field] == 0 for field in fields), label + ': thickness numerical work')
        audit.check(work['vertices'] > 0 and work['triangles'] > 0, label + ': mesh content')
    elif fixture == 'cad_linkage':
        parts = ['ground', 'crank', 'coupler', 'rocker']
        moving = parts[1:]
        closures = {
            'cold_build_solve_solids_meshes': ['linkage'] + [f'{p}.{k}' for p in parts for k in ('profile', 'body', 'mesh')] + parts,
            'retained_angle_edit': ['linkage', *moving],
            'selective_coupler_length_edit': ['linkage', 'coupler.profile', 'coupler.body', 'coupler.mesh', *moving],
            'placement_only_layer_edit': moving,
            'downstream_rejected_angle_edit': ['linkage', *moving, 'gate'],
        }
        closure = closures[case]
        kernel = {p: int(case.startswith('cold') or (case.startswith('selective') and p == 'coupler')) for p in parts}
        audit.same(work['extrusions_by_part'], kernel, label + ': linkage extrusions')
        audit.same(work['tessellations_by_part'], kernel, label + ': linkage tessellations')
        audit.same(work['rebuilt_features'], closure, label + ': linkage closure')
        solve = case != 'placement_only_layer_edit'
        audit.same(work['geometry_solve_invoked'], solve, label + ': linkage solve')
        if not solve:
            audit.check(all(work[field] == 0 for field in fields), label + ': placement-only numerical work')
    elif fixture == 'cad_instances':
        cold = case.startswith('cold')
        closure = ['profile', 'plate', 'mesh', 'base', 'assembly', 'upright'] if cold else ['assembly', 'upright']
        audit.same(work['gap'], 12 if (warmups + index) % 2 == 0 else 5, label + ': alternating gap')
        audit.same(work['rebuilt_features'], closure, label + ': assembly closure')
        audit.same((work['extrusions'], work['tessellations']), (int(cold), int(cold)), label + ': assembly kernel work')
        audit.same((work['prototype_reused'], work['mesh_reused']), (not cold, not cold), label + ': prototype/mesh reuse')
        audit.same(work['geometry_solve_invoked'], True, label + ': assembly fresh solve')
    else:
        raise ValueError('Unexpected aligned-work fixture ' + fixture)
    audit.same(work['scheduled_features'], len(closure), label + ': scheduled closure')


def cohort(name, evidence, before_root, after_root):
    audit = Audit()
    raw_path, summary_path = [evidence / f'{name}-{kind}.json' for kind in ('paired', 'summary')]
    raw_bytes, summary_bytes = raw_path.read_bytes(), summary_path.read_bytes()
    raw, summary = json.loads(raw_bytes), json.loads(summary_bytes)
    check_sources(audit, raw, before_root, after_root,
                  'lib/src/geometry/solver.dart' if name == 'geometry' else 'lib/src/cad/placement.dart')
    rounds = raw['rounds']
    audit.same(rounds, 3, 'three process pairs')
    order = [(mode, round_number, fixture, revision) for mode in ('jit', 'aot')
             for round_number in range(1, rounds + 1) for fixture in raw['harnesses']
             for revision in (('before', 'after') if round_number % 2 else ('after', 'before'))]
    audit.same([(r['mode'], r['round'], r['benchmark'], r['revision']) for r in raw['runs']],
               order, 'complete alternating process order')
    audit.same(summary['revisions'], raw['revisions'], 'summary source identities')
    audit.same(summary['source'], raw_path.name, 'summary source file')
    entries = {}
    prior_finish = None
    for run in raw['runs']:
        fixture, result = run['benchmark'], run['result']
        label = f"{run['mode']}/{run['round']}/{fixture}/{run['revision']}"
        started, finished = [datetime.datetime.fromisoformat(run[key])
                             for key in ('started_at_utc', 'finished_at_utc')]
        audit.check(finished >= started and (prior_finish is None or started >= prior_finish), label + ': sequential process timestamps')
        prior_finish = finished
        arguments = dict(argument.split('=', 1) for argument in run['arguments'])
        configurable = fixture in ('cad', 'cad_linkage', 'cad_instances', 'cad_graph')
        expected_samples = int(arguments['--samples']) if configurable else 25
        expected_warmups = int(arguments['--warmups']) if configurable else (3 if fixture == 'geometry' else 5)
        sample_key, warmup_key = ('measured_iterations', 'warmup_iterations') if fixture == 'cad_linkage' else ('measured_pairs', 'warmup_pairs')
        if fixture == 'cad_graph':
            expected_sizes = [int(value) for value in arguments['--sizes'].split(',')]
            audit.same([value['feature_count'] for value in result['results']], expected_sizes, label + ': graph sizes')
            for shape in result['results']:
                audit.same((shape['samples'], shape['warmups']), (expected_samples, expected_warmups), label + ': graph sample/warmup metadata')
        else:
            audit.same((result[sample_key], result[warmup_key]), (expected_samples, expected_warmups), label + ': sample/warmup metadata')
        audit.same(result['units'], 'microseconds', label + ': units')
        audit.check(result.get('operation_tracing_enabled', False) is False and result.get('check_only', False) is False,
                    label + ': uninstrumented measured cohort')
        oracle = [value for key, value in result.items() if key.endswith('_checks')]
        audit.check(oracle and all(value == 'passed' for value in oracle), label + ': physical oracle completion')
        for path, distribution, metadata in scan(result):
            key = run['mode'], fixture, path, run['revision'], run['round']
            audit.check(key not in entries, label + ': duplicate distribution')
            item = {'distribution': distribution, 'metadata': metadata,
                    'sample_count': expected_samples, 'p99': None}
            entries[key] = item
            audit.counts['distributions'] += 1
            audit.check(all(isinstance(distribution[p], (int, float)) and math.isfinite(distribution[p])
                            and distribution[p] >= 0 for p in ('p50', 'p95')), label + ': percentile values')
            audit.check(distribution['p95'] >= distribution['p50'], label + ': percentile order')
            if 'samples_us' in distribution:
                samples = distribution['samples_us']
                audit.same(len(samples), expected_samples, label + ': complete sample count')
                audit.check(all(type(value) is int and value >= 0 for value in samples), label + ': raw sample values')
                ordered = sorted(samples)
                audit.same(distribution['p50'], ordered[len(ordered) // 2], label + ': p50 from raw samples')
                p95_index = math.ceil((len(ordered) - 1) * .95) if fixture in ('geometry_nonlinear', 'geometry_coupled') else math.ceil(len(ordered) * .95) - 1
                audit.same(distribution['p95'], ordered[p95_index], label + ': p95 from raw samples')
                item['p99'] = ordered[math.ceil(len(ordered) * .99) - 1]
                if 'p99' in distribution:
                    audit.same(distribution['p99'], item['p99'], label + ': reported p99 from raw samples')
                    audit.counts['reported_p99_values'] += 1
                audit.counts['raw_samples'] += len(samples)
                audit.counts['raw_distributions'] += 1
            else:
                audit.same(fixture, 'geometry', label + ': unsupported missing raw samples')
                audit.counts['distributions_without_raw_samples'] += 1
            if 'work_per_sample' in distribution:
                works = distribution['work_per_sample']
                audit.same(len(works), expected_samples, label + ': aligned work count')
                for index, work in enumerate(works):
                    physical_work(audit, fixture, path.split('/')[-1], work, index, expected_warmups,
                                  label + '/' + path + '/' + str(index))
                audit.counts['aligned_work_records'] += len(works)
                audit.counts['aligned_work_distributions'] += 1
    rows = []
    seen = set()
    excluded = {'p50', 'p95', 'p99', 'samples_us', 'work_per_sample', 'feature_count'}
    for row in summary['rows']:
        base = row['mode'], row['benchmark'], row['measurement']
        audit.check(base not in seen, str(base) + ': duplicate summary row')
        seen.add(base)
        derived = {'mode': base[0], 'benchmark': base[1], 'measurement': base[2]}
        for percentile in ('p50', 'p95'):
            series = {}
            for revision in ('before', 'after'):
                audit.same([v['round'] for v in row[revision]], [1, 2, 3], str(base) + ': summary rounds')
                series[revision] = [entries[(*base, revision, number)]['distribution'][percentile]
                                    for number in (1, 2, 3)]
                audit.same([v[percentile + '_us'] for v in row[revision]], series[revision], str(base) + ': summary percentiles')
                audit.same(row[revision + '_median_' + percentile + '_us'], statistics.median(series[revision]),
                           str(base) + ': aggregate median')
            derived[percentile] = compare(series['before'], series['after'])
        audit.same(row['elapsed_change_percent'], derived['p50']['aggregate_change_percent'], str(base) + ': median change')
        b, a = derived['p50']['median_before'], derived['p50']['median_after']
        audit.same(row['elapsed_ratio_before_over_after'], b / a if a else None, str(base) + ': elapsed ratio')
        p99s = {revision: [entries[(*base, revision, number)]['p99'] for number in (1, 2, 3)]
                for revision in ('before', 'after')}
        derived['p99_derived'] = None if any(value is None for series in p99s.values() for value in series) else compare(p99s['before'], p99s['after'])
        derived['samples_per_process'] = entries[(*base, 'before', 1)]['sample_count']
        for number in (1, 2, 3):
            before, after = [entries[(*base, revision, number)] for revision in ('before', 'after')]
            audit.same(before['metadata'], after['metadata'], str(base) + ': paired metadata')
            audit.check(all(row.get(key) == value for key, value in before['metadata'].items()), str(base) + ': summary metadata')
            left, right = [entry['distribution'] for entry in (before, after)]
            if 'work_per_sample' in left or 'work_per_sample' in right:
                audit.same(left.get('work_per_sample'), right.get('work_per_sample'), str(base) + ': exact ordered work parity')
                audit.counts['paired_work_records'] += len(left.get('work_per_sample', []))
            snapshots = [{key: value for key, value in item.items() if key not in excluded} for item in (left, right)]
            audit.same(*snapshots, str(base) + ': paired last-operation counters')
            if snapshots[0]:
                audit.counts['paired_counter_snapshots'] += 1
        rows.append(derived)
    audit.same(seen, {key[:3] for key in entries}, 'every raw/summary row included')
    return {
        'status': 'passed' if not audit.findings else 'failed', 'checks': audit.checks,
        'findings': audit.findings, 'counts': dict(audit.counts),
        'process_reports': len(raw['runs']), 'summary_rows': len(rows),
        'source_identities': raw['revisions'], 'harnesses': raw['harnesses'],
        'raw_sha256': sha(raw_bytes), 'summary_sha256': sha(summary_bytes),
        'rows': rows,
        'consistent_regressions': [
            {'mode': row['mode'], 'benchmark': row['benchmark'], 'measurement': row['measurement'], 'metric': metric,
             **row[metric]}
            for row in rows for metric in ('p50', 'p95') if row[metric]['slower_pairs'] == 3
        ],
        'aggregate_improvement_with_majority_slower_pairs': [
            {'mode': row['mode'], 'benchmark': row['benchmark'], 'measurement': row['measurement'], 'metric': metric,
             **row[metric]}
            for row in rows for metric in ('p50', 'p95')
            if row[metric]['aggregate_change_percent'] is not None and row[metric]['aggregate_change_percent'] < 0 and row[metric]['slower_pairs'] >= 2
        ],
    }


def percent(value):
    return 'n/a' if value is None else f'{value:+.1f}%'


def markdown(report):
    lines = ['# Independent review of isolated tail candidates', '',
        'This review independently reconstructs all rows and pair directions from the preserved JSON. It runs no Dart, profiler, tests, or timing workloads.', '',
        '## Retention assessment', '',
        'The placement candidate has the more consistent evidence for the targeted retained linkage edits. Preserve its AOT cold-build and JIT assembly costs; aggregate medians alone conceal adverse paired results in the assembly rows. The fresh final CAD cohort strengthens the AOT retained-edit result but also shows a substantial AOT assembly cold regression in every pair. Placement is a targeted candidate with a material tradeoff, not an unconditional overall improvement.', '',
        'The geometry candidate has useful direct warm-solver gains, but also large coupled/assembly cold AOT p95 regressions in every pair, and mixed or adverse linkage/assembly medians. The isolated evidence supports its rejection from this tail-focused candidate. Preserve its branch, tests and all results. Placement retention remains conditional on the complete tradeoff assessment; eliminating structural allocations alone is insufficient.', '',
        'A combined candidate versus baseline would not isolate the incremental benefit or cost of adding geometry to placement. These separate cohorts must not be multiplied or combined into an estimated combined speedup.', '',
        '## Evidence limits', '',
        '- Three fresh process pairs per runtime on a shared, unpinned host; no significance, deterministic latency or SLA claim.',
        '- Each cohort containing the legacy geometry control has twenty-four distributions without raw samples; their p50/p95 reconcile to process reports but cannot be reconstructed from samples.',
        '- Legacy numerical controls expose the last operation’s counters, not work aligned with every timing sample.',
        '- Derived p99 on the 25-sample controls is the sample maximum; the 300-sample CAD cases have only three observations in the upper one percent per process.',
        '- Physical correctness completion is established by pass records plus reviewed harness code; full coordinates are not serialized for independent replay.',
        '- Raw files preserve parsed harness JSON, argv and process timestamps. They do not preserve lossless original stdout bytes or explicit exit-code fields; the collector records completed successful calls.',
        '- These normal cohorts contain no allocated-byte measurement or GC/CPU attribution. Paired adverse results and unchanged-work controls remain evidence even when the aggregate median improves.', '',
        'The final controls exercise numerical and graph code with no retained production changes in those implementations. Their sizeable changes are still reported, but cannot be causally attributed to placement validation. Likewise, plate-only controls do not execute rigid-instance validation. This observed context variability limits transfer of isolated percentage changes between cohorts.', '',
        '## Complete results', '',
        'Times are microseconds. “Pairs F/S/E” counts faster, slower and equal paired processes; “paired median” is the median of the three paired percentage changes. It is distinct from the percentage change between aggregate medians.', '']
    for name, data in report['cohorts'].items():
        lines += [f'### {name.capitalize()}', '',
            f"Audit: **{data['status']}**, {data['checks']:,} checks; {data['process_reports']} reports and {data['summary_rows']} rows. Counts: `{json.dumps(data['counts'], sort_keys=True)}`.", '',
            '| Runtime / fixture / operation | p50 before → after | Aggregate Δ / paired median Δ | p50 pairs F/S/E | p95 before → after | Aggregate Δ / paired median Δ | p95 pairs F/S/E | Derived p99 aggregate Δ; pairs F/S/E |',
            '|---|---:|---:|---:|---:|---:|---:|---:|']
        for row in data['rows']:
            cells = [f"{row['mode']} / {row['benchmark']} / `{row['measurement']}`"]
            for metric in ('p50', 'p95'):
                item = row[metric]
                cells += [f"{item['median_before']:g} → {item['median_after']:g}",
                          percent(item['aggregate_change_percent']) + ' / ' + percent(item['median_paired_change_percent']),
                          f"{item['faster_pairs']}/{item['slower_pairs']}/{item['equal_pairs']}"]
            p99 = row['p99_derived']
            cells += ['unavailable' if p99 is None else percent(p99['aggregate_change_percent']) + f"; {p99['faster_pairs']}/{p99['slower_pairs']}/{p99['equal_pairs']}"]
            lines.append('| ' + ' | '.join(cells) + ' |')
        lines += ['', 'Consistent regressions (all three paired processes worse):', '']
        for row in data['consistent_regressions']:
            lines.append(f"- {row['mode']} {row['benchmark']} `{row['measurement']}` {row['metric']}: aggregate {percent(row['aggregate_change_percent'])}; individual pairs " + ', '.join(percent(value) for value in row['paired_change_percent']) + '.')
        lines.append('')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--placement-after', type=Path, required=True)
    parser.add_argument('--geometry-after', type=Path, required=True)
    parser.add_argument('--final-after', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--markdown', type=Path, required=True)
    args = parser.parse_args()
    cohorts = {name: cohort(name, args.evidence, args.before, root)
               for name, root in (('placement', args.placement_after), ('geometry', args.geometry_after))}
    if args.final_after:
        for name in ('final-cad', 'final-controls'):
            cohorts[name] = cohort(name, args.evidence, args.before, args.final_after)
    report = {'schema': 'independent-isolated-tail-review-v1',
              'reviewed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'auditor_sha256': sha(Path(__file__).read_bytes()),
              'status': 'passed' if all(value['status'] == 'passed' for value in cohorts.values()) else 'failed',
              'cohorts': cohorts}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    args.markdown.write_text(markdown(report))
    print(json.dumps({'status': report['status'], 'cohorts': {
        name: {key: value[key] for key in ('status', 'checks', 'findings', 'counts', 'process_reports', 'summary_rows')}
        for name, value in cohorts.items()}}, indent=2))
    return report['status'] != 'passed'


if __name__ == '__main__':
    raise SystemExit(main())

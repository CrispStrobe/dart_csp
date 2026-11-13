"""Independently reconcile paired CAD reports; never executes Dart or timings.

Usage: python audit_cad_measurements.py RAW SUMMARY --output AUDIT
Optional --before/--after worktrees verify recorded source and harness bytes.
RAW may be JSON or gzip. Supported fixtures are the nine reviewed CAD/geometry
harnesses; no project summarizer code is imported.
"""
import argparse
import collections
import datetime
import gzip
import hashlib
import json
import math
import pathlib
import statistics
import subprocess

FLAGS = {
    'cad_graph': 'independent_value_identity_evaluation_and_rollback_checks',
    'geometry_fork': 'independent_checks',
    'cad_linkage': 'independent_physical_reuse_rollback_checks',
    'cad_workspace': 'independent_coordinate_checks',
    'geometry_coupled': 'independent_coordinate_and_residual_checks',
    'geometry_nonlinear': 'independent_coordinate_branch_and_closure_checks',
    'cad': 'analytic_volume_and_mesh_checks',
    'cad_instances': 'coordinate_volume_reuse_checks',
    'geometry': 'independent_geometry_checks',
}
PARTS = ['ground', 'crank', 'coupler', 'rocker']
MOVING = PARTS[1:]
FEATURES = {
    'cold_build_solve_solids_meshes': ['linkage'] +
        [f'{part}.{kind}' for part in PARTS for kind in ('profile', 'body', 'mesh')] + PARTS,
    'retained_angle_edit': ['linkage', *MOVING],
    'selective_coupler_length_edit': ['linkage', 'coupler.profile', 'coupler.body', 'coupler.mesh', *MOVING],
    'placement_only_layer_edit': MOVING,
    'downstream_rejected_angle_edit': ['linkage', *MOVING, 'gate'],
}
EDGES = dict(zip(FEATURES, [0, 3, 6, 0, 5]))
PHYSICAL = ('residual_evaluations', 'jacobian_evaluations', 'linear_solves',
            'linear_iterations', 'nonlinear_iterations', 'rank_factorizations', 'rank_reuses')
CASES = {
    'cad_graph': {'cold_build_regenerate', 'sparse_edit', 'no_op_edit', 'unused_parameter_edit', 'rejected_edit'},
    'geometry_fork': {'fork_only', 'clean_fork_solve', 'sparse_fork_edit', 'direct_sparse_edit'},
    'cad_linkage': set(FEATURES),
    'cad_workspace': {'cold_build_compile_regenerate', 'warm_edit_regenerate'},
    'geometry_coupled': {'cold_build_compile_solve', 'warm_edit_solve'},
    'geometry_nonlinear': {'cold_build_compile_solve', 'warm_edit_solve'},
    'cad': {'cold_build_compile_regenerate', 'profile_edit_regenerate', 'thickness_edit_regenerate'},
    'cad_instances': {'cold_build_solve_regenerate', 'solved_pose_edit'},
    'geometry': {'cold_build_compile_solve', 'warm_edit_solve'},
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    file_bytes = path.read_bytes()
    content = gzip.decompress(file_bytes) if path.suffix == '.gz' else file_bytes
    return json.loads(content), digest(content), digest(file_bytes)


def distributions(name, result):
    inherited = {key: result[key] for key in ('units', 'operations_per_batch',
                 'feature_count', 'components', 'rows', 'columns') if key in result}
    if name in ('cad_graph', 'geometry_fork'):
        field, label = ('feature_count', 'features') if name == 'cad_graph' else ('components', 'components')
        for shape in result['results']:
            for case, value in shape.items():
                if isinstance(value, dict) and 'p50' in value:
                    yield f'results/{label}={shape[field]}/{case}', case, value, {**inherited, field: shape[field]}, shape
    elif name == 'cad_linkage':
        for case, value in result['measurements'].items():
            yield 'measurements/' + case, case, value, {**inherited, 'feature_count': value['feature_count']}, result
    else:
        for case, value in result.items():
            if isinstance(value, dict) and 'p50' in value:
                yield case, case, value, inherited, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=pathlib.Path)
    parser.add_argument('summary', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--before', type=pathlib.Path)
    parser.add_argument('--after', type=pathlib.Path)
    args = parser.parse_args()
    raw, raw_hash, raw_file_hash = read(args.raw)
    summary, summary_hash, _ = read(args.summary)
    findings, counts, provenance = [], collections.Counter(), {}

    def check(condition, message):
        counts['assertions'] += 1
        if not condition:
            findings.append(message)

    names, rounds = list(raw['harnesses']), raw['rounds']
    expected_order = [(mode, repeat, name, label) for mode in ('jit', 'aot')
                      for repeat in range(1, rounds + 1) for name in names
                      for label in (('before', 'after') if repeat % 2 else ('after', 'before'))]
    actual_order = [(r['mode'], r['round'], r['benchmark'], r['revision']) for r in raw['runs']]
    check(actual_order == expected_order, 'Process sequence does not match complete alternating revision order')
    check(len(set(actual_order)) == len(actual_order), 'Duplicate process keys')
    check(summary['revisions'] == raw['revisions'], 'Summary source revisions differ')
    check(summary['source'] in (args.raw.name, args.raw.name.removesuffix('.gz')), 'Summary source filename differs')
    check(all(name in FLAGS for name in names), 'Unsupported fixture in this audit')

    for label, root in (('before', args.before), ('after', args.after)):
        revision = raw['revisions'][label]
        check(revision['library_diff_sha256'] is None, f'{label}: recorded dirty library source')
        if root is None:
            continue
        def git(*command):
            return subprocess.check_output(['git', *command], cwd=root)
        expected = revision['commit']
        check(not git('diff', '--name-only', expected, '--', 'lib').strip(), f'{label}: library differs from frozen commit')
        check(not git('status', '--porcelain=v1', '--', 'lib').strip(), f'{label}: dirty library worktree')
        paths = git('ls-tree', '-r', '--name-only', expected, '--', 'lib').decode().splitlines()
        for path in paths:
            check((root / path).read_bytes() == git('show', expected + ':' + path), f'{label}: library byte mismatch {path}')
            counts['library_file_byte_comparisons'] += 1
        provenance[label] = {'frozen_commit': expected, 'library_tree': git('rev-parse', expected + ':lib').decode().strip(), 'file_count': len(paths)}
        for name, harness in raw['harnesses'].items():
            check(digest((root / harness['file']).read_bytes()) == harness['sha256'], f'{label}: harness mismatch {name}')
            counts['harness_hash_comparisons'] += 1
            for path, expected_hash in harness.get('dependency_sha256', {}).items():
                check(digest((root / path).read_bytes()) == expected_hash, f'{label}: dependency mismatch {name}/{path}')
                check(digest(git('show', expected + ':' + path)) == expected_hash, f'{label}: dependency differs from frozen source {path}')
                counts['dependency_hash_comparisons'] += 1

    measurements, paired_work, snapshots = {}, {}, {}
    for run in raw['runs']:
        name, result = run['benchmark'], run['result']
        context = (run['mode'], name, run['revision'], run['round'])
        if name not in FLAGS:
            continue
        check(result.get(FLAGS[name]) == 'passed', f'{context}: missing/failed physical oracle')
        counts['oracle_pass_records'] += 1
        flags = dict(value.split('=', 1) for value in run.get('arguments', []) if '=' in value)
        configurable = name in ('geometry_fork', 'cad_linkage', 'cad_graph')
        sample_count = int(flags.get('--samples', 25)) if configurable else (40 if name == 'cad_instances' else 25)
        warmups = int(flags.get('--warmups', 5)) if configurable else (3 if name in ('cad', 'geometry') else 5)
        if name == 'cad_linkage':
            check(result['measured_iterations'] == sample_count and result['warmup_iterations'] == warmups, f'{context}: sampling metadata')
        elif name == 'geometry_fork':
            check(result['samples'] == sample_count and result['warmups'] == warmups, f'{context}: sampling metadata')
        elif name != 'cad_graph':
            check(result['measured_pairs'] == sample_count and result['warmup_pairs'] == warmups, f'{context}: sampling metadata')
        if name == 'cad_instances':
            check(result['retained_document_total_extrusions'] == result['retained_document_total_tessellations'] == 1, f'{context}: retained solid/mesh rebuilt')
        check(result['units'] == 'microseconds', f'{context}: incorrect timing units')
        cases = list(distributions(name, result))
        check({entry[1] for entry in cases} == CASES[name], f'{context}: missing/extra operation cases')
        expected_count = len(CASES[name])
        if name in ('cad_graph', 'geometry_fork'):
            field, option, default = ('feature_count', '--sizes', '1000,10000') if name == 'cad_graph' else ('components', '--components', '100,1000')
            sizes = [int(value) for value in flags.get(option, default).split(',')]
            check([shape[field] for shape in result['results']] == sizes, f'{context}: fixture sizes differ from arguments')
            check(len(sizes) == len(set(sizes)), f'{context}: duplicate fixture sizes')
            expected_count *= len(sizes)
            if name == 'geometry_fork':
                check(all(shape['active_coordinates'] == 3 * shape['components'] for shape in result['results']), f'{context}: active coordinate count')
        check(len(cases) == expected_count, f'{context}: operation count differs')

        for path, case, distribution, metadata, shape in cases:
            key = (run['mode'], name, path, run['revision'], run['round'])
            check(key not in measurements, f'{key}: duplicate raw measurement')
            measurements[key] = distribution, metadata
            counts['process_percentile_pairs'] += 1
            check(all(isinstance(distribution[p], (int, float)) and math.isfinite(distribution[p]) and distribution[p] >= 0 for p in ('p50', 'p95')), f'{key}: invalid percentile')
            check(distribution['p95'] >= distribution['p50'], f'{key}: reversed percentiles')
            if name == 'cad_graph':
                check(shape['samples'] == sample_count and shape['warmups'] == warmups and shape['affected_features'] == 4, f'{key}: graph sampling/closure metadata')
            if 'samples_us' in distribution:
                samples = distribution['samples_us']
                check(len(samples) == sample_count and all(isinstance(v, int) and v >= 0 for v in samples), f'{key}: sample count/type')
                ordered = sorted(samples)
                p50 = math.ceil((len(ordered) - 1) * .5) if name in ('geometry_coupled', 'geometry_nonlinear') else len(ordered) // 2
                p95 = math.ceil((len(ordered) - 1) * .95) if name in ('geometry_coupled', 'geometry_nonlinear') else math.ceil(len(ordered) * .95) - 1
                check(distribution['p50'] == ordered[p50] and distribution['p95'] == ordered[p95], f'{key}: sample-derived percentile mismatch')
                counts['raw_sample_distributions'] += 1
                counts['raw_samples'] += len(samples)
            else:
                check(name in ('geometry', 'cad', 'cad_instances'), f'{key}: unexpected missing samples')
                counts['distributions_without_raw_samples'] += 1

            counters = {k: v for k, v in distribution.items() if k not in ('p50', 'p95', 'samples_us', 'work_per_sample', 'feature_count')}
            if counters:
                snapshots[key] = counters
                counts['last_sample_counter_snapshots'] += 1
            if name in ('cad_workspace', 'geometry_coupled'):
                check(tuple(distribution[k] for k in ('residual_evaluations', 'jacobian_evaluations', 'linear_solves')) == (336, 168, 6), f'{key}: coupled physical work changed')
                if name == 'geometry_coupled':
                    check((distribution['components_solved'], distribution['components_reused'], distribution['linear_iterations']) == (1, 0, 144), f'{key}: coupled solve/reuse counters changed')
                else:
                    check((distribution['rank_factorizations'], distribution['rank_reuses']) == ((1, 0) if case.startswith('cold') else (0, 1)), f'{key}: CAD rank reuse changed')
            elif name == 'geometry_nonlinear':
                check(tuple(distribution[k] for k in PHYSICAL) == (60, 30, 4, 24, 4, 2, 0), f'{key}: nonlinear work changed')
                check((distribution['components_solved'], distribution['components_reused']) == (1, 0), f'{key}: nonlinear component counts')
            elif name == 'geometry':
                check((distribution['components_solved'], distribution['linear_solves']) == ((100, 300) if case.startswith('cold') else (1, 2)), f'{key}: circle work changed')
                if case.startswith('warm'):
                    check(distribution['components_reused'] == 99, f'{key}: circle reuse changed')
            elif name == 'cad' and not case.startswith('cold'):
                check(distribution['rebuilt_features'] == (['sketch', 'profile', 'plate', 'mesh'] if case.startswith('profile') else ['plate', 'mesh']), f'{key}: plate rebuild closure')
            elif name == 'cad_instances' and not case.startswith('cold'):
                check(distribution['rebuilt_features'] == ['assembly', 'upright'], f'{key}: assembly rebuild closure')

            if 'work_per_sample' not in distribution:
                continue
            works = distribution['work_per_sample']
            check(len(works) == len(distribution['samples_us']) == sample_count, f'{key}: unaligned work records')
            paired_work[key] = works
            counts['aligned_work_distributions'] += 1
            counts['aligned_work_records'] += len(works)
            for index, work in enumerate(works):
                location = f'{key}/sample={index}'
                if name == 'geometry_fork':
                    count = metadata['components']
                    expected = ({'components_copied': count, 'solve_performed': False} if case == 'fork_only' else
                                {'components_solved': int(case != 'clean_fork_solve'), 'components_reused': count - int(case != 'clean_fork_solve'),
                                 'rank_factorizations': 0, 'rank_reuses': int(case != 'clean_fork_solve'),
                                 'residual_evaluations': 0 if case == 'clean_fork_solve' else 8,
                                 'jacobian_evaluations': 0 if case == 'clean_fork_solve' else 4,
                                 'linear_solves': 0 if case == 'clean_fork_solve' else 3})
                    check(work == expected, f'{location}: fork work invariant')
                elif name == 'cad_linkage':
                    parts = {p: int(case == 'cold_build_solve_solids_meshes' or (case == 'selective_coupler_length_edit' and p == 'coupler')) for p in PARTS}
                    check(work['extrusions_by_part'] == work['tessellations_by_part'] == parts, f'{location}: kernel work')
                    check(work['rebuilt_features'] == FEATURES[case] and work['scheduled_features'] == len(FEATURES[case]), f'{location}: rebuild closure/order')
                    check(work['dependency_edges_visited'] == EDGES[case], f'{location}: edge count')
                    copies = 0 if case in ('cold_build_solve_solids_meshes', 'downstream_rejected_angle_edit') else 17
                    check(work['state_entries_copied'] == copies and work['state_directory_entries_copied'] == int(copies != 0), f'{location}: state copy count')
                    solve = case != 'placement_only_layer_edit'
                    check(work['geometry_solve_invoked'] == solve and work['components_solved'] == int(solve) and work['components_reused'] == 0, f'{location}: solve invocation')
                    allowed = {(0, 0, 0, 0, 0, 0, 0)} if not solve else ({(48, 24, 3, 18, 3, 2, 0), (60, 30, 4, 24, 4, 2, 0)} if case == 'selective_coupler_length_edit' else {(60, 30, 4, 24, 4, 2, 0)})
                    check(tuple(work[k] for k in PHYSICAL) in allowed, f'{location}: nonlinear physical work')
                    check(metadata['feature_count'] == (18 if case == 'downstream_rejected_angle_edit' else 17), f'{location}: fixture feature count')

    for label, series in (('work', paired_work), ('snapshot', snapshots)):
        for key, value in series.items():
            if key[3] != 'before':
                continue
            other = (*key[:3], 'after', key[4])
            check(other in series and value == series[other], f'{key}: paired {label} differs')
            counts['paired_' + label + '_comparisons'] += 1

    seen = set()
    for row in summary['rows']:
        base = (row['mode'], row['benchmark'], row['measurement'])
        check(base not in seen, f'{base}: duplicate summary row')
        seen.add(base)
        for revision in ('before', 'after'):
            samples = row[revision]
            check([value['round'] for value in samples] == list(range(1, rounds + 1)), f'{base}/{revision}: missing/duplicate summary rounds')
            for value in samples:
                key = (*base, revision, value['round'])
                check(key in measurements, f'{key}: summary has no raw pair')
                if key not in measurements:
                    continue
                distribution, metadata = measurements[key]
                check(value['p50_us'] == distribution['p50'] and value['p95_us'] == distribution['p95'], f'{key}: summary percentiles differ')
                check(all(row.get(k) == v for k, v in metadata.items()), f'{key}: summary metadata differs')
                counts['summary_percentile_pairs_reconciled'] += 1
            for percentile in ('p50', 'p95'):
                check(row[revision + '_median_' + percentile + '_us'] == statistics.median(value[percentile + '_us'] for value in samples), f'{base}: aggregate median differs')
                counts['aggregate_values_reconciled'] += 1
        before, after = row['before_median_p50_us'], row['after_median_p50_us']
        check(row['elapsed_change_percent'] == (100 * (after / before - 1) if before else None), f'{base}: elapsed change differs')
        check(row['elapsed_ratio_before_over_after'] == (before / after if after else None), f'{base}: ratio differs')
        counts['aggregate_values_reconciled'] += 2
    check(seen == {key[:3] for key in measurements}, 'Raw/summary case sets differ')
    report = {
        'status': 'passed' if not findings else 'failed',
        'audited_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'auditor': 'Independent fixture-specific Python reconciliation; no project summarizer imported and no timings rerun',
        'inputs': {'raw': str(args.raw), 'raw_sha256': raw_hash, 'raw_file_sha256': raw_file_hash,
                   'summary': str(args.summary), 'summary_sha256': summary_hash},
        'process_reports': len(raw['runs']), 'summary_rows': len(summary['rows']),
        'rounds': rounds, 'counts': dict(counts), 'source_provenance': provenance,
        'findings': findings,
        'limitations': [
            'Legacy geometry, cad and cad_instances report no raw timing samples; their percentile summaries cannot be recomputed from absent samples.',
            'Legacy physical counters/rebuild lists describe the last measured solve; only geometry_fork and cad_linkage expose aligned work for every sample.',
            'Physical oracle completion is checked from pass records and reviewed harness control flow; serialized reports do not contain full coordinates for independent replay.',
            'Source/harness bytes are checked only when the matching before/after worktrees are supplied.',
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('status', 'process_reports', 'summary_rows', 'counts', 'findings')}, indent=2))
    raise SystemExit(bool(findings))


if __name__ == '__main__':
    main()

"""Independently reconcile paired CAD reports; never executes Dart or timings.

Usage: python audit_qr_screen.py RAW SUMMARY --output AUDIT
  --expected-before COMMIT --expected-after COMMIT
  --rounds N --samples N --warmups N
Optional --before/--after worktrees verify recorded source and harness bytes.
RAW may be JSON or gzip. This preserved extension adds exact small-QR inventory, shape and batched-percentile
checks to the repository CAD audit; no project summarizer code is imported.
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

QR_SHAPES = [(5, 4), (8, 4), (4, 5), (4, 8), (9, 4), (12, 4), (16, 8), (16, 9), (17, 8), (48, 48)]
QR_NAMES = [f'rank_{r}x{c}' for r, c in QR_SHAPES] + ['damped_solve_8x4', 'nullspace_4x8']

FLAGS = {
    'geometry_small_qr': 'independent_checks',
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
    'geometry_small_qr': set(QR_NAMES),
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
    elif name == 'geometry_small_qr':
        for value in result['results']:
            meta = {**inherited, **{key: value[key] for key in ('operations_per_batch', 'rows', 'columns') if key in value}}
            yield 'results/' + value['name'], value['name'], value, meta, result
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
    parser.add_argument('--expected-before', required=True)
    parser.add_argument('--expected-after', required=True)
    parser.add_argument('--rounds', type=int, required=True)
    parser.add_argument('--samples', type=int, required=True)
    parser.add_argument('--warmups', type=int, required=True)
    args = parser.parse_args()
    if args.rounds < 1 or args.samples < 1 or args.warmups < 0:
        parser.error('Require positive rounds/samples and nonnegative warmups')
    raw, raw_hash, raw_file_hash = read(args.raw)
    summary, summary_hash, _ = read(args.summary)
    findings, counts, provenance = [], collections.Counter(), {}

    def check(condition, message):
        counts['assertions'] += 1
        if not condition:
            findings.append(message)

    names, rounds = list(raw['harnesses']), raw['rounds']
    check(raw['status'] == 'completed' and raw['diagnostic_only'] is False, 'Complete both-runtime cohort')
    check(raw['modes'] == ['jit', 'aot'] and rounds == args.rounds, 'Exactly the declared modes and rounds')
    expected_commits = {'before': args.expected_before, 'after': args.expected_after}
    check(set(raw['revisions']) == set(expected_commits), 'Exactly the before/after revisions')
    for label, commit in expected_commits.items():
        check(raw['revisions'][label]['commit'] == commit, f'{label}: expected measured commit')
    check(len({revision['dependency_lock_sha256'] for revision in raw['revisions'].values()}) == 1,
          'Both revisions use the same dependency lock')
    check(names == ['geometry_small_qr', 'cad', 'cad_linkage'], 'Exact final control fixture inventory')
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
        if 'library_tree' in revision:
            check(revision['library_tree'] == git('rev-parse', expected + ':lib').decode().strip(), f'{label}: recorded library tree differs')
        if 'dependency_lock_sha256' in revision:
            check(digest((root / 'pubspec.lock').read_bytes()) == revision['dependency_lock_sha256'], f'{label}: dependency lock differs')
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
        check(result.get('operation_tracing_enabled', False) is False, f'{context}: diagnostic tracing included in normal timings')
        check(result.get('check_only', False) is False, f'{context}: check-only placeholders included in normal timings')
        counts['oracle_pass_records'] += 1
        flags = dict(value.split('=', 1) for value in run.get('arguments', []) if '=' in value)
        sample_count, warmups = args.samples, args.warmups
        check(run['arguments'] == [f'--samples={sample_count}', f'--warmups={warmups}'],
              f'{context}: declared sampling flags')
        if name == 'geometry_small_qr':
            check(result['samples'] == sample_count and result['warmups'] == warmups, f'{context}: QR sampling metadata')
            qr = result['results']
            check([row['name'] for row in qr] == QR_NAMES, f'{context}: exact QR shape/operation order')
            for item, (r, c) in zip(qr, QR_SHAPES):
                check((item['rows'], item['columns'], item['expected_rank']) == (r, c, min(r, c)), f'{context}: QR rank shape {item["name"]}')
                check(item['operations_per_batch'] == (8 if r >= 48 else 256), f'{context}: rank batch {item["name"]}')
            check((qr[-2]['jacobian_rows'], qr[-2]['columns'], qr[-2]['augmented_rows'], qr[-2]['operations_per_batch']) == (8, 4, 12, 256), f'{context}: damped-solve fixture')
            check((qr[-1]['jacobian_rows'], qr[-1]['columns'], qr[-1]['expected_rank'], qr[-1]['operations_per_batch']) == (4, 8, 4, 256), f'{context}: nullspace fixture')
        elif name == 'cad_linkage':
            check(result['measured_iterations'] == sample_count and result['warmup_iterations'] == warmups, f'{context}: sampling metadata')
        elif name == 'geometry_fork':
            check(result['samples'] == sample_count and result['warmups'] == warmups, f'{context}: sampling metadata')
        elif name != 'cad_graph':
            check(result['measured_pairs'] == sample_count and result['warmup_pairs'] == warmups, f'{context}: sampling metadata')
        if name == 'cad_instances':
            check(result['retained_document_total_extrusions'] == result['retained_document_total_tessellations'] == 1, f'{context}: retained solid/mesh rebuilt')
        check(result['units'] == ('microseconds_per_batch' if name == 'geometry_small_qr' else 'microseconds'), f'{context}: incorrect timing units')
        cases = list(distributions(name, result))
        check({entry[1] for entry in cases} == CASES[name], f'{context}: missing/extra operation cases')
        if name == 'cad_instances' and ('counter_alignment' in result or
                any('samples_us' in entry[2] or 'work_per_sample' in entry[2] for entry in cases)):
            check(result.get('operations_per_batch') == 1 and result.get('feature_count') == 6, f'{context}: assembly operation/feature counts')
            check(bool(result.get('counter_alignment')), f'{context}: missing assembly alignment declaration')
            check(all(all(field in entry[2] for field in ('samples_us', 'work_per_sample', 'p99')) for entry in cases), f'{context}: incomplete assembly sample/work/p99 evidence')
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
            check('samples_us' in distribution, f'{key}: complete raw samples required')
            if name in ('cad', 'cad_linkage'):
                check('work_per_sample' in distribution, f'{key}: complete aligned CAD work required')
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
                p50 = math.ceil((len(ordered) - 1) * .5) if name in ('geometry_small_qr', 'geometry_coupled', 'geometry_nonlinear') else len(ordered) // 2
                p95 = math.ceil((len(ordered) - 1) * .95) if name in ('geometry_small_qr', 'geometry_coupled', 'geometry_nonlinear') else math.ceil(len(ordered) * .95) - 1
                check(distribution['p50'] == ordered[p50] and distribution['p95'] == ordered[p95], f'{key}: sample-derived percentile mismatch')
                counts['raw_sample_distributions'] += 1
                counts['raw_samples'] += len(samples)
            else:
                check(name in ('geometry', 'cad', 'cad_instances'), f'{key}: unexpected missing samples')
                counts['distributions_without_raw_samples'] += 1

            if 'p99' in distribution:
                check('samples_us' in distribution, f'{key}: p99 lacks raw samples')
                if 'samples_us' in distribution:
                    check(distribution['p99'] == ordered[math.ceil(len(ordered) * .99) - 1], f'{key}: p99 sample-derived percentile mismatch')
                    counts['p99_values_reconciled'] += 1
            counters = {k: v for k, v in distribution.items() if k not in ('p50', 'p95', 'p99', 'samples_us', 'work_per_sample', 'feature_count')}
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
            check('samples_us' in distribution, f'{key}: work records lack raw samples')
            if 'samples_us' not in distribution:
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
                elif name == 'cad':
                    thickness = case.startswith('thickness')
                    features = ['plate', 'mesh'] if thickness else ['sketch', 'profile', 'plate', 'mesh']
                    check(work['rebuilt_features'] == features and work['scheduled_features'] == len(features), f'{location}: plate rebuild closure')
                    check(work['geometry_solve_invoked'] == (not thickness), f'{location}: plate solve invocation')
                    check(work['vertices'] > 0 and work['triangles'] > 0, f'{location}: empty plate mesh')
                    if thickness:
                        check(all(work[k] == 0 for k in PHYSICAL), f'{location}: unexpected thickness solve work')
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
                elif name == 'cad_instances':
                    cold = case == 'cold_build_solve_regenerate'
                    features = ['profile', 'plate', 'mesh', 'base', 'assembly', 'upright'] if cold else ['assembly', 'upright']
                    check(work['rebuilt_features'] == features and work['scheduled_features'] == len(features), f'{location}: assembly rebuild closure/order')
                    check(work['gap'] == (12 if (warmups + index) % 2 == 0 else 5), f'{location}: assembly alternating gap')
                    check(work['extrusions'] == work['tessellations'] == int(cold), f'{location}: assembly kernel work')
                    check(work['geometry_solve_invoked'] is True, f'{location}: missing fresh assembly solve')
                    check(work['prototype_reused'] == work['mesh_reused'] == (not cold), f'{location}: assembly prototype/mesh retention')
                    check(work['dependency_edges_visited'] == (0 if cold else 1), f'{location}: assembly edge count')
                    check((work['state_chunks_copied'], work['state_entries_copied'], work['state_directory_entries_copied']) == ((0, 0, 0) if cold else (1, 6, 1)), f'{location}: assembly state copy counts')
                    physical = (*PHYSICAL, 'components_solved', 'components_reused', 'jacobian_nonzeros', 'auto_diff_derivative_coordinates')
                    check(all(isinstance(work[field], int) and work[field] >= 0 for field in physical), f'{location}: invalid assembly physical counters')
                    check(work['residual_evaluations'] > 0 and work['jacobian_evaluations'] > 0 and work['components_solved'] > 0, f'{location}: missing assembly evaluation work')

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
    expected_distributions = 2 * 2 * args.rounds * (len(QR_NAMES) + len(CASES['cad']) + len(CASES['cad_linkage']))
    expected_work_distributions = 2 * 2 * args.rounds * (len(CASES['cad']) + len(CASES['cad_linkage']))
    check(len(raw['runs']) == 2 * 2 * args.rounds * 3, 'Complete expected report count')
    check(len(summary['rows']) == 2 * (len(QR_NAMES) + len(CASES['cad']) + len(CASES['cad_linkage'])),
          'Complete expected summary-row count')
    check(counts['raw_sample_distributions'] == expected_distributions,
          'Every expected distribution has raw samples')
    check(counts['raw_samples'] == expected_distributions * args.samples, 'All expected raw samples counted')
    check(counts['aligned_work_distributions'] == expected_work_distributions,
          'Every expected CAD distribution has aligned work')
    check(counts['aligned_work_records'] == expected_work_distributions * args.samples,
          'All expected CAD work records counted')
    check(counts['paired_work_comparisons'] == expected_work_distributions // 2,
          'Every CAD distribution has an equal before/after pair')
    report = {
        'status': 'passed' if not findings else 'failed',
        'audited_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'auditor': 'Independent fixture-specific Python reconciliation; no project summarizer imported and no timings rerun',
        'inputs': {'raw': str(args.raw), 'raw_sha256': raw_hash, 'raw_file_sha256': raw_file_hash,
                   'summary': str(args.summary), 'summary_sha256': summary_hash},
        'process_reports': len(raw['runs']), 'summary_rows': len(summary['rows']),
        'rounds': rounds, 'counts': dict(counts), 'source_provenance': provenance,
        'expected_configuration': {'commits': expected_commits, 'rounds': args.rounds,
                                   'samples': args.samples, 'warmups': args.warmups,
                                   'benchmarks': ['geometry_small_qr', 'cad', 'cad_linkage']},
        'findings': findings,
        'limitations': [
            (f"{counts['distributions_without_raw_samples']} distributions expose summary percentiles without raw samples; those percentiles cannot be independently reconstructed."
             if counts['distributions_without_raw_samples'] else
             'Every timing distribution in this cohort exposes raw samples, and every reported percentile is reconstructed.'),
            (f"{counts['aligned_work_distributions']} distributions expose aligned work for every sample; other work counters describe the last measured operation."
             if counts['aligned_work_distributions'] != counts['process_percentile_pairs'] else
             'Every timing distribution in this cohort exposes aligned work for every sample.'),
            'Physical oracle completion is checked from pass records and reviewed harness control flow; serialized reports do not contain full coordinates or QR values for independent replay.',
            'QR timings are batches: 256 operations except rank_48x48, which has eight; raw times must not be described as individual solves.',
            'Source/harness bytes are checked only when the matching before/after worktrees are supplied.',
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ('status', 'process_reports', 'summary_rows', 'counts', 'findings')}, indent=2))
    raise SystemExit(bool(findings))


if __name__ == '__main__':
    main()

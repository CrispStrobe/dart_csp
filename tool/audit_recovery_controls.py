"""Reconstruct the numerical-control cohort without project audit imports."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics

parser = argparse.ArgumentParser()
parser.add_argument('raw', type=Path)
parser.add_argument('summary', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
def load(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data)

raw, summary = (load(p) for p in (args.raw, args.summary))
counts, findings, grouped = Counter(), [], defaultdict(dict)

def check(value, context):
    counts['checks'] += 1
    if not value:
        findings.append(context)

def percent(before, after):
    return 100 * (after / before - 1) if before else None

def close(actual, expected):
    return actual == expected if actual is None or expected is None else math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-10)

oracles = {
    'geometry_nonlinear': 'independent_coordinate_branch_and_closure_checks',
    'geometry_coupled': 'independent_coordinate_and_residual_checks',
    'cad_workspace': 'independent_coordinate_checks',
    'cad_graph': 'independent_value_identity_evaluation_and_rollback_checks',
}
graph_cases = ['cold_build_regenerate', 'sparse_edit', 'no_op_edit', 'unused_parameter_edit', 'rejected_edit']
check(raw['status'] == 'completed' and raw['diagnostic_only'] is False, 'complete normal cohort')
check(raw['modes'] == ['jit', 'aot'] and raw['rounds'] == 3, 'expected runtimes and pairs')
check(list(raw['harnesses']) == list(oracles), 'complete fixture inventory')
expected_order = [(mode, repeat, fixture, revision)
    for mode in raw['modes'] for repeat in range(1, raw['rounds'] + 1)
    for fixture in raw['harnesses']
    for revision in (('before', 'after') if repeat % 2 else ('after', 'before'))]
actual_order = [tuple(r[k] for k in ('mode', 'round', 'benchmark', 'revision')) for r in raw['runs']]
check(expected_order == actual_order, 'complete alternating sequential cohort')
check(summary['revisions'] == raw['revisions'], 'summary source identities')
previous_finish = None
for run in raw['runs']:
    ident = tuple(run[k] for k in ('mode', 'round', 'benchmark', 'revision'))
    fixture, result = run['benchmark'], run['result']
    start, end = (datetime.fromisoformat(run[k]) for k in ('started_at_utc', 'finished_at_utc'))
    check(end >= start and (previous_finish is None or start >= previous_finish), [ident, 'sequential run times'])
    previous_finish = end
    check(result[oracles[fixture]] == 'passed', [ident, 'independent oracle pass'])
    check(result['units'] == 'microseconds', [ident, 'timing units'])
    check(not result.get('check_only', False) and not result.get('operation_tracing_enabled', False), [ident, 'normal timing flags'])
    records = []
    if fixture == 'cad_graph':
        check(run['arguments'] == ['--samples=25', '--warmups=5', '--sizes=1000,10000'], [ident, 'graph sampling arguments'])
        check([v['feature_count'] for v in result['results']] == [1000, 10000], [ident, 'graph fixture sizes'])
        for shape in result['results']:
            check((shape['warmups'], shape['samples'], shape['affected_features']) == (5, 25, 4), [ident, 'graph shape metadata'])
            cases = [k for k, v in shape.items() if isinstance(v, dict) and 'p50' in v]
            check(cases == graph_cases, [ident, 'graph operation inventory'])
            records.extend((f"results/features={shape['feature_count']}/{case}", shape[case]) for case in cases)
    else:
        check(run['arguments'] == [], [ident, 'fixture uses source-defined counts'])
        check((result['warmup_pairs'], result['measured_pairs']) == (5, 25), [ident, 'fixture sampling metadata'])
        cases = [k for k, v in result.items() if isinstance(v, dict) and 'p50' in v]
        expected = ['cold_build_compile_regenerate', 'warm_edit_regenerate'] if fixture == 'cad_workspace' else ['cold_build_compile_solve', 'warm_edit_solve']
        check(cases == expected, [ident, 'operation inventory'])
        records.extend((case, result[case]) for case in cases)
    counts['process_reports'] += 1
    for name, distribution in records:
        values = distribution['samples_us']
        check(len(values) == 25, [ident, name, 'sample count'])
        check(all(type(x) is int and x >= 0 for x in values), [ident, name, 'finite nonnegative integer samples'])
        sorted_values = sorted(values)
        rebuilt = {f'p{p}': sorted_values[math.ceil(len(values) * p / 100) - 1] for p in (50, 95, 99)}
        for p in ('p50', 'p95'):
            check(distribution[p] == rebuilt[p], [ident, name, p, 'reported percentile'])
            counts['reported_percentiles'] += 1
        physical = {k: v for k, v in distribution.items() if k not in ('samples_us', 'p50', 'p95', 'p99')}
        expected_physical = None
        if fixture == 'geometry_nonlinear':
            expected_physical = {'components_solved': 1, 'components_reused': 0,
                'residual_evaluations': 60, 'jacobian_evaluations': 30,
                'linear_solves': 4, 'linear_iterations': 24, 'nonlinear_iterations': 4,
                'rank_factorizations': 2, 'rank_reuses': 0}
        elif fixture == 'geometry_coupled':
            expected_physical = {'components_solved': 1, 'components_reused': 0,
                'residual_evaluations': 336, 'jacobian_evaluations': 168,
                'linear_solves': 6, 'linear_iterations': 144}
        elif fixture == 'cad_workspace':
            cold = name.startswith('cold')
            expected_physical = {'rank_factorizations': int(cold), 'rank_reuses': int(not cold),
                'residual_evaluations': 336, 'jacobian_evaluations': 168, 'linear_solves': 6}
        if expected_physical is not None:
            check(physical == expected_physical, [ident, name, 'fixed physical-work snapshot'])
            counts['physical_snapshots'] += 1
        else:
            check(physical == {}, [ident, name, 'no unrecognized graph metadata'])
        key, pair = (run['mode'], fixture, name), (run['revision'], run['round'])
        check(pair not in grouped[key], [ident, name, 'unique distribution'])
        grouped[key][pair] = {'percentiles': rebuilt, 'physical': physical}
        counts['distributions'] += 1
        counts['samples'] += len(values)

saved_rows = {(r['mode'], r['benchmark'], r['measurement']): r for r in summary['rows']}
check(len(saved_rows) == len(summary['rows']) and set(saved_rows) == set(grouped), 'complete unique summary rows')
rows = []
for key, processes in grouped.items():
    saved, row = saved_rows[key], dict(zip(('mode', 'benchmark', 'measurement'), key))
    for field in ('p50', 'p95', 'p99'):
        before = [processes['before', i]['percentiles'][field] for i in range(1, raw['rounds'] + 1)]
        after = [processes['after', i]['percentiles'][field] for i in range(1, raw['rounds'] + 1)]
        b, a = statistics.median(before), statistics.median(after)
        pairs = [percent(x, y) for x, y in zip(before, after)]
        row[field] = {'before_us': b, 'after_us': a,
            'before_process_values': before, 'after_process_values': after,
            'aggregate_change_percent': percent(b, a), 'paired_change_percent': pairs,
            'median_paired_change_percent': statistics.median([x for x in pairs if x is not None]) if any(x is not None for x in pairs) else None,
            'faster_pairs': sum(y < x for x, y in zip(before, after)),
            'slower_pairs': sum(y > x for x, y in zip(before, after)),
            'equal_pairs': sum(y == x for x, y in zip(before, after))}
        if field != 'p99':
            for revision, values in (('before', before), ('after', after)):
                check([r['round'] for r in saved[revision]] == [1, 2, 3], [key, revision, 'summary rounds'])
                check([r[field + '_us'] for r in saved[revision]] == values, [key, revision, field, 'summary process values'])
                check(saved[revision + '_median_' + field + '_us'] == statistics.median(values), [key, revision, field, 'summary aggregate'])
    check(close(saved['elapsed_change_percent'], row['p50']['aggregate_change_percent']), [key, 'summary percent'])
    b, a = row['p50']['before_us'], row['p50']['after_us']
    check(close(saved['elapsed_ratio_before_over_after'], b / a if a else None), [key, 'summary ratio'])
    for i in range(1, 4):
        check(processes['before', i]['physical'] == processes['after', i]['physical'], [key, i, 'paired physical snapshots'])
        if processes['before', i]['physical']:
            counts['paired_physical_snapshots'] += 1
    rows.append(row)
report = {'status': 'passed' if not findings else 'failed', 'counts': dict(counts),
    'findings': findings, 'rounds': raw['rounds'], 'samples': 25, 'warmups': 5,
    'input_sha256': hashlib.sha256(args.raw.read_bytes()).hexdigest(),
    'summary_sha256': hashlib.sha256(args.summary.read_bytes()).hexdigest(),
    'method': 'Source-free reconstruction of samples, fixture-specific metadata, fixed work snapshots, summary values and pair directions. No project summarizer/auditor imports; no Dart workload.',
    'rows': rows,
    'limitations': ['At 25 samples, derived nearest-rank p99 is each process maximum, not reliable percentile-tail evidence.', 'Only aggregate physical-work snapshots and oracle pass records are retained; per-sample work or complete geometry outputs are not serialized.', 'Short control workloads in fresh JIT processes include warmup/compilation/host variability; timing movement is not causal attribution to the unexecuted rounding routine.']}
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'rows'}, indent=2))
for row in rows:
    print(json.dumps(row))

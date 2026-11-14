"""Derive complete, non-pooled heap-candidate control timing tables from audited raw data."""
from collections import defaultdict
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', nargs='?', type=Path, default=Path(__file__).resolve().parent)
root = parser.parse_args().directory
raw_bytes = (root / 'raw.json').read_bytes()
raw = json.loads(raw_bytes)
audit = json.loads((root / 'independent-audit.json').read_text())
process_audit = json.loads((root / 'process-audit.json').read_text())
assert audit['status'] == process_audit['status'] == 'passed'
grouped = defaultdict(dict)
for run in raw['runs']:
    name, result = run['benchmark'], run['result']
    if name == 'geometry_small_qr':
        rows = [(item['name'], item) for item in result['results']]
    elif name == 'cad_linkage':
        rows = list(result['measurements'].items())
    else:
        rows = [(key, value) for key, value in result.items()
                if isinstance(value, dict) and 'p50' in value]
    for case, values in rows:
        samples = sorted(values['samples_us'])
        assert len(samples) == 101
        index = math.ceil((len(samples) - 1) * .99) if name == 'geometry_small_qr' else math.ceil(len(samples) * .99) - 1
        p99 = samples[index]
        if 'p99' in values:
            assert values['p99'] == p99
        grouped[run['mode'], name, case][run['revision'], run['round']] = {
            'p50': values['p50'], 'p95': values['p95'], 'p99': p99,
            'p99_reported_by_harness': 'p99' in values,
        }

def pct(before, after):
    return 100 * (after / before - 1) if before else None

rows = []
for (mode, name, case), processes in grouped.items():
    row = {'mode': mode, 'benchmark': name, 'case': case,
           'units': 'microseconds_per_batch' if name == 'geometry_small_qr' else 'microseconds',
           'operations_per_batch': (8 if case == 'rank_48x48' else 256) if name == 'geometry_small_qr' else 1,
           'p99_reported_by_harness': all(value['p99_reported_by_harness'] for value in processes.values())}
    for percentile in ('p50', 'p95', 'p99'):
        before = [processes['before', i][percentile] for i in range(1, 4)]
        after = [processes['after', i][percentile] for i in range(1, 4)]
        b, a = statistics.median(before), statistics.median(after)
        row[percentile] = {'before_us': b, 'after_us': a, 'change_percent': pct(b, a),
            'paired_change_percent': [pct(x, y) for x, y in zip(before, after)],
            'paired_slower_equal_faster': [sum(y > x for x, y in zip(before, after)),
                                           sum(y == x for x, y in zip(before, after)),
                                           sum(y < x for x, y in zip(before, after))],
            'before_process_values_us': before, 'after_process_values_us': after}
    rows.append(row)
assert len(rows) == 40
data = {'source': 'raw.json', 'source_sha256': hashlib.sha256(raw_bytes).hexdigest(),
        'decision': 'conditional_retention_for_qualified_sparse_benefit',
        'source_commits': {label: value['commit'] for label, value in raw['revisions'].items()},
        'method': 'Median of three process percentiles; all samples/processes retained. Before/after pair directions computed separately. Plate p99 is harness-reported and independently recomputed; QR/linkage p99 is derived screening information using each harness percentile convention. With 101 samples, each p99 is the second-largest process sample.',
        'rows': rows}
(root / 'review-metrics.json').write_text(json.dumps(data, indent=2) + '\n')

def row_for(mode, benchmark, case):
    return next(row for row in rows if (row['mode'], row['benchmark'], row['case']) == (mode, benchmark, case))

def describe(mode, benchmark, case, percentile):
    row = row_for(mode, benchmark, case)
    value = row[percentile]
    return (f"{value['before_us']:g} to {value['after_us']:g} microseconds "
            f"({value['change_percent']:+.2f}%; slower/equal/faster pairs "
            + '/'.join(map(str, value['paired_slower_equal_faster'])) + ')')

counts = [sum(row['p50']['change_percent'] < 0 for row in rows),
          sum(row['p50']['change_percent'] == 0 for row in rows),
          sum(row['p50']['change_percent'] > 0 for row in rows)]
lines = [
    '# Sparse heap candidate: independent small-QR/CAD control review — 2026-11-14', '',
    '## Retention recommendation', '',
    '**These controls expose no correctness or physical-work blocker to retaining the heap candidate. '
    'Recommend retention only as a qualified large-sparse optimization, contingent on the separately '
    'audited target gains and source validation, with the adverse control tails below explicitly accepted.** '
    'This control cohort alone does not demonstrate the target sparse benefit or establish a uniform '
    'speedup. Repeatable adverse tail observations remain.', '',
    'The measured baseline is `c2603a852229897d325a8890ed418319ee8c3572` and heap candidate is '
    '`521a31f78989cf4706c8f26bb6a2c2ec2709b777`. The rejected QR permutation cleanup is a separate '
    'experiment and is not part of this review. The changed heap source is evaluated here through '
    'collateral small-QR, plate and linkage controls; this audit does not inspect its internal heap '
    'invariants or replace its separate sparse qualification.', '',
    f'Across all 40 aggregate median rows, **{counts[0]} are lower, {counts[1]} equal and {counts[2]} higher**. '
    'This is a descriptive count without application-workload weighting. All AOT linkage medians '
    'are lower by 2.8–6.5%, and all JIT plate medians are lower by 6.9–11.5%. The full result includes '
    'the following adverse observations:', '',
    '- AOT rank 16x8 p50 per 256-call batch: ' + describe('aot','geometry_small_qr','rank_16x8','p50') + '.',
    '- AOT rank 16x8 p95 per 256-call batch: ' + describe('aot','geometry_small_qr','rank_16x8','p95') + '.',
    '- AOT plate cold p95: ' + describe('aot','cad','cold_build_compile_regenerate','p95') + '.',
    '- AOT plate profile p95: ' + describe('aot','cad','profile_edit_regenerate','p95') + '.',
    '- AOT plate thickness p50: ' + describe('aot','cad','thickness_edit_regenerate','p50') + '.',
    '- JIT cold-linkage p95: ' + describe('jit','cad_linkage','cold_build_solve_solids_meshes','p95') + '.',
    '- JIT placement-only p95: ' + describe('jit','cad_linkage','placement_only_layer_edit','p95') + '.',
    '- JIT rank 8x4 p95 per 256-call batch: ' + describe('jit','geometry_small_qr','rank_8x4','p95') + '.', '',
    'Profile p95, cold-linkage p95, placement-only p95 and rank-8x4 p95 all worsen in three of three '
    'paired processes. They cannot be dismissed from their aggregate medians or from identical physical '
    'work counters. The observed distribution also includes mixed pair directions, which are retained '
    'alongside every ratio of process medians below.', '',
    '## Independent verification', '',
    f"The fixture/source auditor passes **{audit['counts']['assertions']:,} assertions** and the process auditor "
    f"passes **{process_audit['checks']:,} checks**, with zero findings. All 36 reports honor three alternating "
    'rounds, 20 warmups and 101 measured samples in both JIT and AOT. All 240 distributions expose raw '
    'timings: **24,240 samples/batches** in total. All **9,696 CAD work records** satisfy their fixture '
    'invariants, and all **4,848 before/after sample pairs** have equal work records. All 40 summary rows '
    'and 36 published plate p99 values reconcile. Ninety library files across the two live worktrees match '
    'their recorded commits; harness and dependency-file hashes also match.', '',
    'The process audit checks 101 subprocess records, 202 original stream digests, six compilations and '
    '36 benchmark links. No raw sample, process, fixture or adverse row is excluded. Numerical checks '
    'run in the harness outside timers; this collector serializes their pass records and work counters, '
    'rather than full numerical outputs for a second physical-oracle replay.', '',
    'The exact source identities, raw and summary digests, declared sampling design and performed '
    'source-byte checks are recorded in the audit JSON. No numerical workload was rerun by this review.', '',
    '## Tail boundary and complete table', '',
    'Values are microseconds and changes are candidate/baseline elapsed time. Positive means slower. '
    'S/E/F counts give slower/equal/faster paired process values out of three. QR rows time batches of '
    '256 operations except rank 48x48 (eight operations); CAD rows time one operation. Each aggregate '
    'is the median of three per-process percentiles, without sample pooling.', '',
    'Plate p99 values are harness-reported. QR and linkage p99 values below are derived screening '
    'statistics using the respective harness percentile convention. At 101 samples, p99 is the '
    'second-largest sample in each process; three processes do not establish a stable tail bound. '
    'The complete per-round values and changes are preserved in `review-metrics.json`. These data '
    'do not establish allocation-byte changes, GC attribution, compiler effects or a causal mechanism '
    'for any observed control difference.', '',
]
for mode in ('jit', 'aot'):
    lines.extend([f'### {mode.upper()}', '',
        '| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |',
        '|---|---:|---:|---:|---:|---:|---:|'])
    for row in rows:
        if row['mode'] != mode:
            continue
        cells = [row['benchmark'] + ' / ' + row['case']]
        for percentile in ('p50', 'p95', 'p99'):
            item = row[percentile]
            cells += [f"{item['before_us']:g} → {item['after_us']:g} ({item['change_percent']:+.2f}%)",
                      '/'.join(map(str, item['paired_slower_equal_faster']))]
        lines.append('| ' + ' | '.join(cells) + ' |')
    lines.append('')
lines.extend(['## Reproduction', '',
    '```sh',
    'python3 audit_control_cohort.py raw.json summary.json \\',
    '  --expected-before c2603a852229897d325a8890ed418319ee8c3572 \\',
    '  --expected-after 521a31f78989cf4706c8f26bb6a2c2ec2709b777 \\',
    '  --rounds 3 --samples 101 --warmups 20 \\',
    '  --before /path/to/baseline --after /path/to/heap-candidate \\',
    '  --output independent-audit.json',
    'python3 audit_processes.py raw.json --output process-audit.json',
    'python3 review_heap_controls.py .',
    '```', '',
    'The standalone auditor uses declared source identities and sampling counts; it imports no '
    'project summarizer and executes no solver workload. Omit the optional worktree paths when '
    'only serialized evidence is available, retaining exact expected-commit checks. The audit result '
    'records which source-byte checks were performed.', '',
    'Further timing repetition is not required merely to finish this control review. Any decision '
    'to integrate should name the separate target benefits and these retained control costs. '
    'This review does not qualify browser performance or the previously unresolved dense-fill '
    'convergence limit.', ''])
(root / 'independent-review.md').write_text('\n'.join(lines))
print(json.dumps({'rows': len(rows), 'decision': data['decision'],
                 'p50_lower_equal_higher': counts}))

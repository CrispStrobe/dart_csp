"""Derive complete, non-pooled QR experiment timing tables from audited raw data."""
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
        'decision': 'reject_candidate',
        'source_commits': {label: value['commit'] for label, value in raw['revisions'].items()},
        'method': 'Median of three process percentiles; all samples/processes retained. Before/after pair directions computed separately. Plate p99 is harness-reported and independently recomputed; QR/linkage p99 is derived screening information using each harness percentile convention. With 101 samples, each p99 is the second-largest process sample.',
        'rows': rows}
(root / 'review-metrics.json').write_text(json.dumps(data, indent=2) + '\n')

lines = [
    '# QR permutation-allocation experiment: independent review — 2026-11-14', '',
    '## Decision', '',
    '**Reject the candidate for integration and preserve its source and complete measurements.** '
    'The one-list source cleanup is numerically valid, but this prespecified screen does not support retaining it. '
    'AOT plate cold/profile/thickness medians are 7.03%, 10.29% and 9.61% higher, and their p95 values '
    'are 6.18%, 28.26% and 27.81% higher. Every one of those six percentile comparisons is worse in all '
    'three process pairs. JIT cold-linkage median is 33.92% higher, also worse in all three pairs. '
    'AOT QR gains, including rank 4x8 at -12.15%, do not justify these collateral observations.', '',
    'The observed tails are mixed and remain fully visible: AOT plate cold/thickness p99 increases '
    '28.83%/44.95%, each in all three pairs. The derived JIT damped-solve p99 rises 252.09%, also in '
    'all three pairs. Conversely, the derived JIT rank-4x8 p99 falls 49.93%, with all three pairs faster. '
    'These screening p99 values describe the sampled cohort and do not identify a causal mechanism.', '',
    'The experiment source is `748febd527cda9eeb611cdf2dcba3c9c3af388ec`, compared with '
    '`c2603a852229897d325a8890ed418319ee8c3572`. The only production change directly initializes '
    'the QR identity permutation in `Int32List`, avoiding the explicit temporary generated list. '
    'It preserves initialization before the first cancellation callback and all QR arithmetic. '
    'This does not establish reduced allocated bytes, fewer GC events, or any cause of the observed tails. '
    'In particular, the plate thickness operation performs no geometry solve; its adverse result remains '
    'a control observation rather than proof that this QR expression causes that cost.', '',
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
    '## Complete timing table', '',
    'Values are microseconds and changes are candidate/baseline elapsed time. Positive means slower. '
    'S/E/F counts give slower/equal/faster paired process values out of three. QR rows time batches of '
    '256 operations except rank 48x48 (eight operations); CAD rows time one operation. '
    'Each aggregate is the median of three per-process percentiles, without sample pooling.', '',
    'Plate p99 values are harness-reported. QR and linkage p99 values below are derived screening '
    'statistics using the respective harness percentile convention. At 101 samples, p99 is the '
    'second-largest sample in each process; three processes do not establish a stable tail bound. '
    'The complete per-round values and changes are preserved in `review-metrics.json`.', '',
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
    'python3 audit_qr_screen.py raw.json summary.json \\',
    '  --expected-before c2603a852229897d325a8890ed418319ee8c3572 \\',
    '  --expected-after 748febd527cda9eeb611cdf2dcba3c9c3af388ec \\',
    '  --rounds 3 --samples 101 --warmups 20 \\',
    '  --before /path/to/baseline --after /path/to/qr-candidate \\',
    '  --output independent-audit.json',
    'python3 tool/audit_recovery_processes.py raw.json --output process-audit.json',
    '```', '',
    'The standalone auditor uses declared source identities and sampling counts; it imports no '
    'project summarizer and executes no solver workload. Omit the optional worktree paths when '
    'only serialized evidence is available, retaining exact expected-commit checks. The audit result '
    'records which source-byte checks were performed.', '',
    'No further timing run is needed merely to accept this rejection. The separate sparse-ordering '
    'experiment remains an independent candidate; this rejected QR change should not be combined '
    'with it or silently retained.', ''])
(root / 'independent-review.md').write_text('\n'.join(lines))
print(json.dumps({'rows': len(rows), 'decision': data['decision'],
    'p50_lower_equal_higher': [sum(row['p50']['change_percent'] < 0 for row in rows),
                             sum(row['p50']['change_percent'] == 0 for row in rows),
                             sum(row['p50']['change_percent'] > 0 for row in rows)]}))

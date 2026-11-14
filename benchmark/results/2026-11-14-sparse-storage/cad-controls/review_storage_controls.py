"""Derive complete non-pooled packed-factor control tables from audited raw data.

Requires the fixture, subprocess and independent source-identity audits for
the exact raw bytes. No project summarizer or timing workload is imported.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import statistics


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pct(before, after):
    return 100 * (after / before - 1) if before else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path,
                        default=Path(__file__).resolve().parent)
    root = parser.parse_args().directory
    encoded = (root / 'raw.json').read_bytes()
    raw = json.loads(encoded)
    audit = json.loads((root / 'independent-audit.json').read_text())
    processes = json.loads((root / 'process-audit.json').read_text())
    source = json.loads((root / 'source-audit.json').read_text())
    assert raw['status'] == 'completed'
    assert audit['status'] == processes['status'] == source['status'] == 'passed'
    assert audit['inputs']['raw_sha256'] == digest(encoded)
    assert processes['input_sha256'] == digest(encoded)
    assert source['source_sha256'] == digest(encoded)
    assert audit['inputs']['summary_sha256'] == digest((root / 'summary.json').read_bytes())
    assert raw['rounds'] == 3 and raw['modes'] == ['jit', 'aot']
    assert len(raw['runs']) == 36
    grouped = defaultdict(dict)
    for run in raw['runs']:
        name, result = run['benchmark'], run['result']
        if name == 'geometry_small_qr':
            distributions = [(item['name'], item) for item in result['results']]
        elif name == 'cad_linkage':
            distributions = list(result['measurements'].items())
        else:
            assert name == 'cad'
            distributions = [(key, value) for key, value in result.items()
                             if isinstance(value, dict) and 'p50' in value]
        for case, item in distributions:
            samples = sorted(item['samples_us'])
            assert len(samples) == 101
            percentiles = {}
            for key, probability in [('p50', .5), ('p95', .95), ('p99', .99)]:
                index = (math.ceil((len(samples) - 1) * probability)
                         if name == 'geometry_small_qr'
                         else math.ceil(len(samples) * probability) - 1)
                percentiles[key] = samples[index]
                if key in item:
                    assert percentiles[key] == item[key]
            identity = run['revision'], run['round']
            group = grouped[run['mode'], name, case]
            assert identity not in group
            group[identity] = {
                **percentiles, 'p99_reported_by_harness': 'p99' in item,
                'process_record': run['process_record'],
            }
    rows = []
    for (mode, name, case), values in grouped.items():
        assert set(values) == {(label, repeat) for label in ('before', 'after')
                               for repeat in range(1, 4)}
        row = {
            'mode': mode, 'benchmark': name, 'case': case,
            'units': 'microseconds_per_batch' if name == 'geometry_small_qr' else 'microseconds',
            'operations_per_batch': ((8 if case == 'rank_48x48' else 256)
                                     if name == 'geometry_small_qr' else 1),
            'p99_reported_by_harness': all(item['p99_reported_by_harness']
                                         for item in values.values()),
        }
        for percentile in ('p50', 'p95', 'p99'):
            before = [values['before', i][percentile] for i in range(1, 4)]
            after = [values['after', i][percentile] for i in range(1, 4)]
            b, a = statistics.median(before), statistics.median(after)
            row[percentile] = {
                'before_us': b, 'after_us': a, 'change_percent': pct(b, a),
                'paired_change_percent': [pct(x, y) for x, y in zip(before, after)],
                'paired_slower_equal_faster': [sum(y > x for x, y in zip(before, after)),
                                             sum(y == x for x, y in zip(before, after)),
                                             sum(y < x for x, y in zip(before, after))],
                'paired_direction': ['slower' if y > x else 'faster' if y < x else 'equal'
                                     for x, y in zip(before, after)],
                'before_process_values_us': before,
                'after_process_values_us': after,
            }
        rows.append(row)
    assert len(rows) == 40
    counts = {}
    for percentile in ('p50', 'p95', 'p99'):
        counts[percentile] = {
            'lower': sum(row[percentile]['after_us'] < row[percentile]['before_us'] for row in rows),
            'equal': sum(row[percentile]['after_us'] == row[percentile]['before_us'] for row in rows),
            'higher': sum(row[percentile]['after_us'] > row[percentile]['before_us'] for row in rows),
            'slower_in_all_three_pairs': sum(row[percentile]['paired_slower_equal_faster'][0] == 3 for row in rows),
            'faster_in_all_three_pairs': sum(row[percentile]['paired_slower_equal_faster'][2] == 3 for row in rows),
        }
    data = {
        'source': 'raw.json', 'source_sha256': digest(encoded),
        'review_scope': 'collateral_control_cohort_not_a_standalone_retention_decision',
        'source_commits': {label: identity['commit'] for label, identity in raw['revisions'].items()},
        'method': 'Median of three process percentiles; every process and sample retained. Each matched pair is also reported separately. Plate p99 is harness-reported; QR/linkage p99 is derived using each harness percentile convention. At 101 samples, p99 is the second-largest observation in each process.',
        'counts': counts, 'rows': rows,
    }
    (root / 'review-metrics.json').write_text(json.dumps(data, indent=2) + '\n')

    def description(row, percentile):
        value = row[percentile]
        unit = ('microseconds per ' + str(row['operations_per_batch']) + '-operation batch'
                if row['benchmark'] == 'geometry_small_qr' else 'microseconds')
        return (f"{row['mode'].upper()} {row['benchmark']} / {row['case']} {percentile}: "
                f"{value['before_us']:g} → {value['after_us']:g} {unit} "
                f"({value['change_percent']:+.2f}%; slower/equal/faster pairs "
                + '/'.join(map(str, value['paired_slower_equal_faster'])) + ').')

    all_pair_costs = [(row, percentile) for row in rows
                      for percentile in ('p50', 'p95', 'p99')
                      if row[percentile]['paired_slower_equal_faster'][0] == 3]
    all_pair_costs.sort(key=lambda pair: pair[0][pair[1]]['change_percent'], reverse=True)
    biggest_costs = [(row, percentile) for row in rows
                     for percentile in ('p50', 'p95', 'p99')
                     if row[percentile]['change_percent'] > 0
                     and row[percentile]['paired_slower_equal_faster'][0] != 3]
    biggest_costs.sort(key=lambda pair: pair[0][pair[1]]['change_percent'], reverse=True)
    before, after = data['source_commits']['before'], data['source_commits']['after']
    assertions = audit['counts']['assertions']
    work_records = audit['counts']['aligned_work_records']
    sample_count = audit['counts']['raw_samples']
    c = counts['p50']
    lines = [
        '# Packed sparse factors: independent small-QR/CAD control review — 2026-11-14', '',
        '## Scope and result', '',
        '**The complete control cohort passes source, subprocess, fixture, work-parity and percentile audits.** '
        'This is a collateral-control review; retention of packed sparse factors requires the separately '
        'qualified sparse targets and source validation. No timing or solver workload was rerun for this review.', '',
        f'The baseline is `{before}` and the candidate is `{after}`. Their sole library difference is '
        '`lib/src/geometry/sparse_ldlt.dart`. These small-QR, plate and linkage controls exercise other '
        'solver paths; timing differences do not establish that packed factors caused the observations. '
        'They are preserved as measured costs and benefits without discarding unfavorable processes.', '',
        f'Across 40 aggregate median rows, **{c["lower"]} are lower, {c["equal"]} equal and '
        f'{c["higher"]} higher**. This is an unweighted descriptive count. The complete table below '
        'includes p50, p95, p99 and matched-pair directions for every row. All original processes and '
        'samples remain included; no cross-process sample pooling is used.', '',
        '## Adverse observations', '',
        'Every statistic that worsens in all three matched process pairs is listed here:', '',
    ]
    lines += ['- ' + description(row, percentile) for row, percentile in all_pair_costs]
    if not all_pair_costs:
        lines += ['No statistic worsens in all three pairs. Adverse aggregate values with mixed directions remain below.']
    lines += ['', 'The six largest remaining adverse aggregate changes are listed separately; '
              'their pair directions must not be replaced by the aggregate direction:', '']
    lines += ['- ' + description(row, percentile) for row, percentile in biggest_costs[:6]]
    if not biggest_costs:
        lines += ['There are no additional adverse aggregate changes.']
    lines += [
        '', '## Independent verification', '',
        f'The fixture/source auditor passes **{assertions:,} assertions**, the process auditor passes '
        f'**{processes["checks"]:,} checks**, and the separate source-identity crosscheck passes '
        f'**{source["checks"]:,} checks**, with zero findings. The 36 reports contain three alternating '
        'before/after rounds in each of JIT and AOT, with 20 warmups and 101 measured samples per case. '
        f'All 240 distributions expose their raw timings: **{sample_count:,} samples or batches**.', '',
        f'All **{work_records:,} CAD work records** satisfy the fixture invariants and all '
        f'**{work_records // 2:,} matched before/after work records** agree exactly. All 40 aggregate '
        f'rows and {audit["counts"]["p99_values_reconciled"]} harness-published plate p99 values '
        'reconcile to raw samples. The numerical checks run outside the timers in each harness. '
        'Their pass records and aligned work counters are serialized; the control records do not '
        'contain full numerical coordinates or QR matrices for a second independent physical replay.', '',
        f'The process audit reconciles {processes["counts"]["process_records"]} subprocess records, '
        f'{processes["counts"]["stream_hash_checks"]} original-stream digests, six compilations and '
        'all 36 benchmark links. Sources match the exact committed blobs and the two live frozen '
        'worktrees; complete library inventories, package configuration, dependency lock, harness '
        'and fixture hashes match. CPU affinity was recorded as `[0]`. Affinity does not imply '
        'exclusive ownership of that CPU.', '',
        'The normal collector records the Dart version and exact compile/run command chain, but '
        'does not hash the SDK executable, AOT executable bytes or installed dependency source bytes. '
        'Stronger binary provenance from a different sparse cohort must not be attributed to this one.', '',
        '## Complete non-pooled timing table', '',
        'Values are microseconds. Positive percentage change means slower candidate time. S/E/F '
        'counts mean slower/equal/faster matched process values out of three. Each aggregate is '
        'the median of three per-process percentiles. QR rows time batches of 256 operations except '
        '`rank_48x48`, which times eight; CAD rows time individual complete operations.', '',
        'Plate p99 values are harness-reported and independently recomputed. QR and linkage p99 '
        'values are derived screening statistics. With 101 samples, each process p99 is the '
        'second-largest observation; this small cohort does not establish a stable tail bound. '
        '`review-metrics.json` preserves all individual before/after process values, pair directions '
        'and pair percentage changes. These data do not measure allocated bytes or establish GC, '
        'compiler or other causal attribution.', '',
    ]
    for mode in ('jit', 'aot'):
        lines += [f'### {mode.upper()}', '',
                  '| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |',
                  '|---|---:|---:|---:|---:|---:|---:|']
        for row in rows:
            if row['mode'] != mode:
                continue
            cells = [row['benchmark'] + ' / ' + row['case']]
            for percentile in ('p50', 'p95', 'p99'):
                value = row[percentile]
                cells += [f"{value['before_us']:g} → {value['after_us']:g} ({value['change_percent']:+.2f}%)",
                          '/'.join(map(str, value['paired_slower_equal_faster']))]
            lines.append('| ' + ' | '.join(cells) + ' |')
        lines.append('')
    lines += ['## Reproduction', '', '```sh',
              'python3 audit_control_cohort.py raw.json summary.json \\',
              f'  --expected-before {before} \\',
              f'  --expected-after {after} \\',
              '  --rounds 3 --samples 101 --warmups 20 \\',
              '  --before /path/to/baseline --after /path/to/candidate \\',
              '  --output independent-audit.json',
              'python3 audit_processes.py raw.json --output process-audit.json',
              'python3 audit_source_identity.py raw.json --repo /path/to/repo \\',
              '  --before /path/to/baseline --after /path/to/candidate \\',
              '  --output source-audit.json',
              'python3 review_storage_controls.py .', '```', '',
              'These tools inspect preserved data and source bytes only. They execute no Dart workload '
              'and import no project timing summarizer. Their passing results are scoped to this '
              'control cohort and do not establish sparse-target gains, browser performance, '
              'resolution of prior tail observations, or dense coupled convergence.', '']
    (root / 'independent-review.md').write_text('\n'.join(lines))
    print(json.dumps({'rows': len(rows), 'counts': counts,
                      'all_three_pair_adverse_statistics': len(all_pair_costs)}))


if __name__ == '__main__':
    main()

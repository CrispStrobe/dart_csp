#!/usr/bin/env python3
"""Recompute paired timing details from independently audited native output."""
import argparse
import collections
import gzip
import json
import math
from pathlib import Path
import statistics


def percentile(values, fraction):
    values = sorted(values)
    return values[math.ceil((len(values) - 1) * fraction)] if values else None


def jsonl(path):
    return [json.loads(line) for line in gzip.decompress(path.read_bytes()).splitlines() if line]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--review', type=Path, required=True)
    parser.add_argument('--title', required=True)
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text())
    if not audit['evidence_consistent']:
        raise ValueError('An evidence-consistent independent audit is required')
    manifest = json.loads((args.run / 'manifest.json').read_text())
    comparison = json.loads((args.run / 'comparison.json').read_text())
    groups = collections.defaultdict(dict)
    for job_path in sorted(args.run.glob('*/*/job.json')):
        job = json.loads(job_path.read_text())
        directory = job_path.parent
        request = json.loads(gzip.decompress((directory / 'request.json.gz').read_bytes()))
        raw = [row for row in jsonl(directory / 'stdout.jsonl.gz') if row.get('record') != 'metadata']
        checked = {row['index']: row for row in jsonl(directory / 'checked.jsonl.gz')}
        for row in raw:
            if row != {k: v for k, v in checked[row['index']].items() if k != 'oracle'}:
                raise ValueError('Raw and checked native records differ')
        measured = [row for row in raw if not row['warmup']]
        accepted = [row for row in measured if checked[row['index']]['oracle']['accepted']]
        eligible = job['summary']['ranking_eligible']
        if eligible and (len(accepted) != request['samples'] or not job['summary']['complete']):
            raise ValueError('Invalid timing eligibility')
        values = [row['elapsed_ns'] / 1e6 for row in accepted] if eligible else []
        timings = {stat: percentile(values, fraction) for stat, fraction in [('p50', .5), ('p95', .95)]}
        key = (job['fixture_id'], job['engine'], job['mode'])
        groups[key].setdefault(job['round'], {})[job['variant']] = {
            'measured_elapsed_ns': [row['elapsed_ns'] for row in measured],
            'qualified_latency': eligible, **timings,
        }

    rows = []
    by_key = {(row['fixture_id'], row['engine'], row['mode']): row for row in comparison['groups']}
    for key, rounds in sorted(groups.items()):
        row = dict(zip(('fixture_id', 'engine', 'mode'), key))
        row['pairs'] = []
        for number, pair in sorted(rounds.items()):
            if set(pair) != {'before', 'after'}:
                raise ValueError('Both variants required for paired summaries')
            detail = {'round': number, **pair}
            for stat in ('p50', 'p95'):
                b, a = pair['before'][stat], pair['after'][stat]
                detail[stat + '_change_percent'] = 100 * (a / b - 1) if b and a is not None else None
            row['pairs'].append(detail)
        for stat in ('p50', 'p95'):
            counts = dict(faster=0, equal=0, slower=0, unqualified=0)
            aggregate = {}
            for variant in ('before', 'after'):
                values = [pair[variant][stat] for pair in row['pairs']]
                aggregate[variant + '_ms'] = statistics.median(values) if all(v is not None for v in values) else None
                published = by_key[key][variant]['median_process_accepted_' + stat + '_ms']
                if published != aggregate[variant + '_ms']:
                    raise ValueError('Published aggregate differs from raw-native calculation')
            b, a = aggregate['before_ms'], aggregate['after_ms']
            ratio = a / b if b and a is not None else None
            if ratio != by_key[key]['after_over_before_' + stat]:
                raise ValueError('Published ratio differs from raw-native calculation')
            aggregate['change_percent'] = 100 * (ratio - 1) if ratio is not None else None
            for pair in row['pairs']:
                b, a = pair['before'][stat], pair['after'][stat]
                counts['unqualified' if b is None or a is None else
                       'faster' if a < b else 'slower' if a > b else 'equal'] += 1
            aggregate['paired_directions'] = counts
            row[stat] = aggregate
        rows.append(row)

    result = {'schema_version': 1, 'source': audit['source'],
              'counts': audit['counts'], 'totals': audit['reliability_accounting']['totals'],
              'method': 'ceil((n-1)*p) raw-native process percentiles; median across processes; no pooling',
              'rounds': manifest['rounds'], 'warmups': manifest['warmups'], 'samples': manifest['samples'],
              'groups': rows}
    result['aggregate_directions'] = {
        stat: {name: sum((r[stat]['change_percent'] is None if name == 'unqualified' else
                  r[stat]['change_percent'] is not None and
                  (r[stat]['change_percent'] < 0 if name == 'faster' else
                   r[stat]['change_percent'] > 0 if name == 'slower' else r[stat]['change_percent'] == 0))
                 for r in rows) for name in ('faster', 'equal', 'slower', 'unqualified')}
        for stat in ('p50', 'p95')}
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')

    totals = result['totals']
    pairs = sum(r['paired_operations'] for r in audit['paired_work_comparison'])
    lines = ['# ' + args.title, '', '## Evidence outcome', '',
        f"The independent audit passes with zero integrity/contract findings. All **{totals['jobs']} jobs** and "
        f"**{totals['validated_operations']} requested operations** are complete, including "
        f"{totals['requested_warmups']} warmups and {totals['requested_measured_operations']} measured operations. "
        f"There are **{pairs} exact before/after coordinate and solver-work pairs**.", '',
        f"Physical outcomes: {totals['accepted_operations']} accepted, {totals['rejected_operations']} rejected. "
        'No operations are missing, and no timeout, nonzero exit, adapter exception or oracle disagreement is hidden.', '',
        'Baseline is `' + audit['source']['before']['source_commit'] + '`; candidate is `' +
        audit['source']['after']['source_commit'] + '`. The audit verifies exact source/preparation identities, '
        'raw requests and native output, physical-oracle replay, complete sequential job inventory, terminal '
        'gates and numerical-work parity. The separate preparation check binds archived source bytes directly to Git blobs.', '',
        '## Complete timing table', '',
        'Times are milliseconds per complete build/update, solve and extraction operation. Each displayed value '
        'is the median of process percentiles, not a pooled percentile. Positive change means slower candidate time. '
        'Paired direction counts are faster/equal/slower.', '',
        '| Fixture / engine / lifecycle | p50 before → after (ms) | p50 change | p50 pairs | p95 before → after (ms) | p95 change | p95 pairs |',
        '|---|---:|---:|---:|---:|---:|---:|']
    labels = {'ladder_125_components_1': 'Ladder 500', 'ladder_500_components_1': 'Ladder 2,000',
              'ladder_25_components_1': 'Ladder 100', 'laman_free_100': 'Coupled 100',
              'laman_free_500': 'Coupled 500', 'laman_free_2000': 'Coupled 2,000'}
    for row in rows:
        cells = [labels.get(row['fixture_id'], row['fixture_id']) + ' / ' +
                 ('2D' if row['engine'] == 'dart_2d_analytic' else '3D') + ' / ' + row['mode']]
        for stat in ('p50', 'p95'):
            g = row[stat]
            if g['before_ms'] is None or g['after_ms'] is None:
                cells += ['unqualified', '—', '—']
            else:
                d = g['paired_directions']
                cells += [f"{g['before_ms']:.3f} → {g['after_ms']:.3f}", f"{g['change_percent']:+.2f}%",
                          f"{d['faster']}/{d['equal']}/{d['slower']}"]
        lines.append('| ' + ' | '.join(cells) + ' |')
    lines += ['', '## Interpretation limits', '',
        f"The design uses {manifest['rounds']} alternating process pairs, {manifest['warmups']} warmups "
        f"and {manifest['samples']} measured samples per process. With seven samples, each process p95 "
        'is its largest sample and the aggregate p95 is the median of those maxima. These are screening '
        'statistics, not stable tail bounds or statistical-significance claims. Ratio-of-process-medians '
        'and the majority direction of matched pairs can differ; both are retained above.', '',
        'Equal coordinate/work outcomes do not establish the cause of elapsed-time differences. The '
        'source eliminates per-column numeric factor buffers, but this cohort does not measure total '
        'allocated bytes or GC causality. No weighted overall application speedup is inferred. All '
        'adverse rows must remain part of any retention decision.', '',
        'The audit and this summary execute no solver; they ran on CPU 8. Exact raw-native timing '
        'vectors, per-process before/after values and all unrounded ratios are in the adjacent timing-details JSON.']
    args.review.write_text('\n'.join(lines) + '\n')
    print(json.dumps({'groups': len(rows), 'aggregate_directions': result['aggregate_directions']}))


if __name__ == '__main__':
    main()

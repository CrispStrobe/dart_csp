"""Summarize paired harness reports without pooling or discarding samples."""
import argparse
import gzip
import json
import pathlib
import re
import statistics


def distributions(value, path=(), metadata=None):
    metadata = dict(metadata or {})
    if isinstance(value, dict):
        if 'output_lines' in value:
            for line in value['output_lines']:
                match = re.match(r'^(.*?); median=(\d+)us p95=(\d+)us', line)
                if match:
                    label, p50, p95 = match.groups()
                    edits = re.search(r'\bedits=(\d+)\b', label)
                    yield label, {
                        'units': 'microseconds_per_batch',
                        'operations_per_batch': int(edits[1]) if edits else 1,
                    }, {'p50': int(p50), 'p95': int(p95)}
            return
        for field in ('units', 'operations_per_batch', 'feature_count', 'components',
                      'rows', 'columns'):
            if field in value:
                metadata[field] = value[field]
        if 'p50' in value and 'p95' in value:
            yield '/'.join(path), metadata, value
            return
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                yield from distributions(child, path + (key,), metadata)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            if not isinstance(child, (dict, list)):
                continue
            label = str(index)
            if isinstance(child, dict):
                if 'name' in child:
                    label = child['name']
                elif 'feature_count' in child:
                    label = 'features=' + str(child['feature_count'])
                elif 'components' in child:
                    label = 'components=' + str(child['components'])
                elif 'rows' in child and 'columns' in child:
                    label = str(child['rows']) + 'x' + str(child['columns'])
            yield from distributions(child, path + (label,), metadata)


def summarize(data):
    grouped = {}
    rounds = data['rounds']
    for run in data['runs']:
        found = list(distributions(run['result']))
        if not found:
            raise ValueError('No timing distributions: ' + repr(run))
        for path, metadata, measurement in found:
            key = (run['mode'], run['benchmark'], path)
            row = grouped.setdefault(key, {
                'mode': run['mode'], 'benchmark': run['benchmark'],
                'measurement': path, **metadata, 'before': [], 'after': [],
            })
            for name, value in metadata.items():
                if row[name] != value:
                    raise ValueError('Measurement metadata differs: ' + str(key))
            row[run['revision']].append({
                'round': run['round'],
                'p50_us': measurement['p50'],
                'p95_us': measurement['p95'],
            })
    for row in grouped.values():
        for revision in ('before', 'after'):
            samples = sorted(row[revision], key=lambda value: value['round'])
            if [value['round'] for value in samples] != list(range(1, rounds + 1)):
                raise ValueError('Missing/duplicate rounds: ' + repr(row))
            row[revision] = samples
            for percentile in ('p50', 'p95'):
                row[revision + '_median_' + percentile + '_us'] = \
                    statistics.median(value[percentile + '_us']
                                      for value in samples)
        before, after = (row[revision + '_median_p50_us']
                         for revision in ('before', 'after'))
        row['elapsed_change_percent'] = \
            (100 * (after / before - 1)) if before else None
        row['elapsed_ratio_before_over_after'] = before / after if after else None
    return list(grouped.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    opener = gzip.open if args.source.suffix == '.gz' else open
    with opener(args.source, 'rt', encoding='utf-8') as source:
        data = json.load(source)
    output = {
        'source': args.source.name,
        'revisions': data['revisions'],
        'method': 'Median of per-process p50/p95 values, not pooled percentiles. '
                  'No samples or processes removed. All reported times are '
                  'microseconds, including rows that measure operation batches. '
                  'A zero denominator produces null rather than an infinite ratio.',
        'rows': summarize(data),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print(f"Summarized {len(data['runs'])} reports into {len(output['rows'])} rows.")


if __name__ == '__main__':
    main()

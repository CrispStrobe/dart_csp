#!/usr/bin/env python3
"""Independently recheck frozen paired-Dart evidence, without running solvers.

Reads directories or tar archives, including archives wrapped in a common
directory containing prepared.json or manifest.json. Nested source archives
retain their original paths. Reexecutes only the preserved physical oracle,
verifies requests/native records/checksums and computes process percentiles and
per-round paired ratios directly from raw operation timers. Failed/rejected
jobs remain counted and are excluded from successful-solve latency ratios.
"""

import argparse
import collections
import datetime
import gzip
import hashlib
import io
import itertools
import json
import math
from pathlib import Path
import statistics
import subprocess
import tarfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Reader:
    def __init__(self, path=None, data=None):
        self.path = Path(path) if path is not None else None
        self.archive_bytes = None
        self.tar = None
        self.root_prefix = ''
        if data is not None or not self.path.is_dir():
            self.archive_bytes = data if data is not None else self.path.read_bytes()
            self.tar = tarfile.open(fileobj=io.BytesIO(self.archive_bytes))
        if self.tar:
            names = [m.name for m in self.tar.getmembers() if m.isfile()]
            roots = {name[:-len(marker)]
                     for name in names
                     for marker in ('prepared.json', 'manifest.json')
                     if name == marker or name.endswith('/' + marker)}
            common_roots = [prefix for prefix in roots
                            if all(name.startswith(prefix) for name in names)]
            if common_roots:
                self.root_prefix = min(common_roots, key=len)
            self._names = [name[len(self.root_prefix):] for name in names]
        else:
            self._names = [str(p.relative_to(self.path))
                           for p in self.path.rglob('*') if p.is_file()]

    def names(self):
        return self._names

    def read(self, name):
        if self.tar:
            return self.tar.extractfile(self.root_prefix + name).read()
        return (self.path / name).read_bytes()

    def json(self, name):
        return json.loads(self.read(name))

    def compressed(self, name):
        if name in self.names():
            return self.read(name)
        return gzip.decompress(self.read(name + '.gz'))

    def jsonl(self, name):
        return [json.loads(line) for line in self.compressed(name).splitlines() if line]


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[math.ceil((len(ordered) - 1) * fraction)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--prepared', required=True, type=Path)
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = {
        'schema_version': 1,
        'audited_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'audit_script_sha256': sha(Path(__file__).read_bytes()),
        'inputs': {key: str(getattr(args, key).resolve()) for key in ('repo', 'prepared', 'run')},
        'errors': [], 'source': {}, 'counts': {}, 'groups': [],
        'method': 'Raw native timers; upper-order-statistic process percentiles; separate paired process ratios; no pooling across processes or hosts.',
    }

    def require(condition, label):
        if not condition:
            report['errors'].append(label)

    def git(*words):
        return subprocess.check_output(['git', '-C', str(args.repo), *words])

    prep, run = Reader(args.prepared), Reader(args.run)
    prep_names, run_names = prep.names(), run.names()
    require(len(prep_names) == len(set(prep_names)), 'duplicate preparation archive member')
    require(len(run_names) == len(set(run_names)), 'duplicate run archive member')
    prepared_raw, manifest_raw = prep.read('prepared.json'), run.read('manifest.json')
    prepared, manifest = json.loads(prepared_raw), json.loads(manifest_raw)
    report['input_hashes'] = {'prepared_manifest': sha(prepared_raw), 'run_manifest': sha(manifest_raw)}
    report['archive_roots'] = {'prepared': prep.root_prefix, 'run': run.root_prefix}
    for label, reader in [('prepared', prep), ('run', run)]:
        if reader.archive_bytes is not None:
            report['input_hashes'][label + '_archive'] = sha(reader.archive_bytes)
    require(prepared['status'] == 'complete', 'preparation status')
    require(manifest['status'] == 'complete', 'run status')
    require(prepared['finished_utc'] <= manifest['started_utc'], 'builds finished before measurements')
    require(sha(prepared_raw) == manifest['prepared_manifest_sha256'], 'prepared manifest identity')
    harness = {name: sha(prep.read('harness/' + name)) for name in prepared['harness_sha256']}
    require(harness == prepared['harness_sha256'], 'prepared harness checksums')
    require(harness == manifest['harness_sha256'], 'run harness checksums')
    oracle = {'__name__': 'preserved_physical_oracle'}
    exec(compile(prep.read('harness/oracle.py'), 'preserved-oracle.py', 'exec'), oracle)
    for variant, info in prepared['variants'].items():
        source = info['source']
        report['source'][variant] = {key: source[key] for key in (
            'source_commit', 'source_tree', 'library_tree', 'test_tree', 'source_status')}
        require(source['source_status'] == '', variant + ' clean source snapshot')
        raw = prep.read(info['source_archive'])
        require(sha(raw) == info['source_archive_sha256'], variant + ' source archive hash')
        snapshot = Reader(data=raw)
        require(set(snapshot.names()) == set(source['source_sha256']), variant + ' source member set')
        for name, expected in source['source_sha256'].items():
            require(sha(snapshot.read(name)) == expected, variant + ' source hash ' + name)
        for key, suffix in [('source_tree', '^{tree}'), ('library_tree', ':lib'), ('test_tree', ':test')]:
            require(git('rev-parse', source['source_commit'] + suffix).decode().strip() == source[key], variant + ' git ' + key)
        for stream in ('stdout', 'stderr'):
            require(sha(prep.read(variant + '/build.' + stream + '.log')) == info['build'][stream + '_sha256'], variant + ' build ' + stream)
        if info['executable'] in prep_names:
            require(sha(prep.read(info['executable'])) == info['executable_sha256'], variant + ' executable hash')
        report['source'][variant]['executable_available_and_checked'] = info['executable'] in prep_names

    expected_keys = set(itertools.product(manifest['variants'], range(1, manifest['rounds'] + 1), manifest['fixture_ids'], manifest['engines'], manifest['modes']))
    actual_keys = set()
    scheduled = {row['variant'] + '/' + row['job'] + '/job.json': row for row in manifest['jobs']}
    expected_order = []
    for repeat in range(manifest['rounds']):
        for ci, fixture in enumerate(manifest['fixture_ids']):
            for mi, mode in enumerate(manifest['modes']):
                for ei, engine in enumerate(manifest['engines']):
                    labels = manifest['variants'][::-1] if (repeat + ci + mi + ei) % 2 else manifest['variants'][:]
                    expected_order.extend((variant, repeat + 1, fixture, engine, mode) for variant in labels)
    actual_order = []
    for scheduled_name, row in scheduled.items():
        job = run.json(scheduled_name)
        actual_order.append((job['variant'], job['round'], job['fixture_id'], job['engine'], job['mode']))
    require(actual_order == expected_order, 'alternating paired process order')
    for previous, following in zip(manifest['jobs'], manifest['jobs'][1:]):
        require(previous['completed_utc'] <= following['started_utc'], 'overlapping solver processes')
    job_names = sorted(name for name in run_names if name.endswith('/job.json'))
    require(set(job_names) == set(scheduled), 'manifest and raw job sets')
    require(len(scheduled) == len(manifest['jobs']), 'duplicate scheduled job')
    counts = collections.defaultdict(collections.Counter)
    grouped = collections.defaultdict(dict)
    physical_pairs = collections.defaultdict(list)
    job_reports = []
    for name in job_names:
        prefix = name.rsplit('/', 1)[0] + '/'
        job = run.json(name)
        request_raw = run.compressed(prefix + 'request.json')
        request = json.loads(request_raw)
        require(sha(request_raw) == job['request_sha256'], name + ' raw request hash')
        physical = {k: v for k, v in request.items() if k != 'engine'}
        physical_hash = sha(json.dumps(physical, sort_keys=True, separators=(',', ':'), allow_nan=False).encode())
        require(physical_hash == job['physical_request_sha256'], name + ' physical request hash')
        require(sha(json.dumps(job['command']).encode()) == job['command_sha256'], name + ' command hash')
        require(request['samples'] == manifest['samples'] and request['warmups'] == manifest['warmups'], name + ' requested counts')
        require(job['summary'] == scheduled[name]['summary'], name + ' scheduled summary')
        require(job['started_utc'] == scheduled[name]['started_utc'] and job['completed_utc'] == scheduled[name]['completed_utc'], name + ' scheduled timestamps')
        require(job['started_utc'] <= job['completed_utc'], name + ' timestamp order')
        key = (job['variant'], job['round'], job['fixture_id'], job['engine'], job['mode'])
        require(key not in actual_keys, name + ' duplicate job tuple')
        actual_keys.add(key)
        pair_key = (job['round'], job['fixture_id'], job['engine'], job['mode'])
        physical_pairs[pair_key].append(physical_hash)
        raw_rows = run.jsonl(prefix + 'stdout.jsonl')
        metadata = [row for row in raw_rows if row.get('record') == 'metadata']
        require(metadata == job['metadata'], name + ' metadata preservation')
        native = [row for row in raw_rows if row.get('record') != 'metadata']
        checked = run.jsonl(prefix + 'checked.jsonl')
        require(len(native) == len(checked), name + ' native/checked count')
        indices = list(range(-request['warmups'], request['samples']))
        complete = [row['index'] for row in native] == indices
        require(complete == job['summary']['complete'], name + ' completeness summary')
        c = counts[job['variant']]
        c.update(jobs=1, complete_jobs=int(complete), timeouts=int(job['timed_out']), nonzero_exit_jobs=int(job['returncode'] != 0), parse_error_jobs=int(bool(job['parse_errors'])))
        accepted = []
        for row, saved in zip(native, checked):
            require({k: v for k, v in saved.items() if k != 'oracle'} == row, name + ' native preservation ' + str(row['index']))
            require(row['warmup'] == (row['index'] < 0), name + ' warmup flag ' + str(row['index']))
            require(row['engine'] == job['engine'] and row['mode'] == job['mode'] and row['fixture_id'] == job['fixture_id'], name + ' operation identity')
            for timer in ['build_ns', 'solve_ns', 'elapsed_ns']:
                value = row[timer]
                require(type(value) in (int, float) and math.isfinite(value) and value >= 0, name + ' timer ' + timer)
            require(row['elapsed_ns'] + 10 >= row['build_ns'] + row['solve_ns'], name + ' timer consistency')
            verdict = oracle['check'](request, row)
            require(verdict == saved['oracle'], name + ' physical oracle ' + str(row['index']))
            c.update(operations=1, warmups=int(row['warmup']), accepted=int(verdict['accepted']), rejected=int(not verdict['accepted']), adapter_errors=int(row.get('adapter_error') is not None), qualification_mismatches=int(verdict['accepted'] != request['fixture']['expected_feasible']), contradictions_rejected=int(not request['fixture']['expected_feasible'] and not verdict['accepted']))
            if verdict['accepted']:
                accepted.append(row)
        measured = [row for row in native if not row['warmup']]
        accepted_measured = [row for row in accepted if not row['warmup']]
        independent = {}
        for label, rows in [('all', measured), ('accepted', accepted_measured)]:
            times = [row['elapsed_ns'] / 1e6 for row in rows]
            for pct, fraction in [('p50', .5), ('p95', .95)]:
                value = percentile(times, fraction)
                independent[label + '_' + pct + '_ms'] = value
                require(value == job['summary'][label + '_' + pct + '_ms'], name + ' percentile ' + label + '_' + pct)
        qualified = complete and job['returncode'] == 0 and not job['timed_out'] and not job['parse_errors'] and len(accepted_measured) == request['samples'] and len(accepted) == len(native)
        row = {'job': name, 'round': job['round'], 'variant': job['variant'], 'fixture': job['fixture_id'], 'engine': job['engine'], 'mode': job['mode'], 'qualified_latency': qualified, 'measured': len(measured), 'accepted_measured': len(accepted_measured), **independent}
        job_reports.append(row)
        grouped[(job['fixture_id'], job['engine'], job['mode'])].setdefault(job['round'], {})[job['variant']] = row
    require(actual_keys == expected_keys, 'full expected job Cartesian product')
    for key, hashes in physical_pairs.items():
        require(len(set(hashes)) == 1, 'paired physical request mismatch ' + str(key))
    comparison = run.json('comparison.json')
    saved_groups = {(row['fixture_id'], row['engine'], row['mode']): row for row in comparison['groups']}
    for key, rounds in sorted(grouped.items()):
        group = dict(zip(('fixture', 'engine', 'mode'), key))
        group['rounds'] = []
        for round_number, sides in sorted(rounds.items()):
            pair = {'round': round_number, 'qualified_latency': len(sides) == 2 and all(row['qualified_latency'] for row in sides.values())}
            for label, row in sides.items():
                for pct in ('p50', 'p95'):
                    pair[label + '_' + pct + '_ms'] = row['accepted_' + pct + '_ms']
            if pair['qualified_latency']:
                for pct in ('p50', 'p95'):
                    pair['after_over_before_' + pct] = pair['after_' + pct + '_ms'] / pair['before_' + pct + '_ms']
            group['rounds'].append(pair)
        group['qualified_latency'] = all(row['qualified_latency'] for row in group['rounds'])
        if group['qualified_latency']:
            for pct in ('p50', 'p95'):
                ratios = [row['after_over_before_' + pct] for row in group['rounds']]
                for variant in ('before', 'after'):
                    value = statistics.median(row[variant + '_' + pct + '_ms'] for row in group['rounds'])
                    group[variant + '_median_process_' + pct + '_ms'] = value
                    require(value == saved_groups[key][variant]['median_process_accepted_' + pct + '_ms'], str(key) + ' comparison median ' + variant + pct)
                value = group['after_median_process_' + pct + '_ms'] / group['before_median_process_' + pct + '_ms']
                group['ratio_of_process_medians_' + pct] = value
                require(value == saved_groups[key]['after_over_before_' + pct], str(key) + ' comparison ratio ' + pct)
                group['paired_' + pct] = {'median_ratio': statistics.median(ratios), 'min_ratio': min(ratios), 'max_ratio': max(ratios), 'after_slower_rounds': sum(r > 1 for r in ratios), 'after_faster_rounds': sum(r < 1 for r in ratios), 'equal_rounds': sum(r == 1 for r in ratios)}
        report['groups'].append(group)
    report['counts'] = {k: dict(v) for k, v in sorted(counts.items())}
    report['run'] = {k: manifest.get(k) for k in ('status', 'purpose', 'rounds', 'warmups', 'samples', 'protocol_ok', 'qualification_passed', 'started_utc', 'finished_utc', 'pinned_cpu', 'cpu_model', 'platform')}
    report['expected_jobs'] = len(expected_keys)
    report['jobs'] = job_reports
    report['audit_passed'] = not report['errors']
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'output': str(args.output.resolve()), 'audit_passed': report['audit_passed'], 'errors': report['errors'], 'counts': report['counts'], 'groups': [{k: v for k, v in row.items() if k != 'rounds'} for row in report['groups']]}, indent=2))
    return bool(report['errors'])


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Independently audit complete paired CSP runs and describe bounded timing effects.

This never launches a solver. It rechecks archived coordinates using the physical
oracle, recomputes process percentiles from raw records, compares all non-timing
outputs, and keeps rounds/process order distinct. A/A ranges describe observed
variation only; they are never subtracted or used to erase adverse observations.
"""
from __future__ import annotations
import argparse
import collections
import gzip
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys
import tarfile

TIMES = ('build_ns', 'solve_ns', 'elapsed_ns')
ENVIRONMENT = ('platform', 'cpu_model', 'pinned_cpu', 'thread_environment', 'timing_contract')


def fail_unless(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(data):
    def reject(value):
        raise ValueError('Nonfinite JSON constant: ' + value)
    return json.loads(data, parse_constant=reject)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return read_json(path.read_bytes())


def read_maybe_gzip(path):
    if path.exists():
        return path.read_bytes()
    return gzip.decompress(path.with_name(path.name + '.gz').read_bytes())


def quantile(values, p):
    ordered = sorted(values)
    return ordered[math.ceil((len(ordered) - 1) * p)] if ordered else None


def median(values):
    return statistics.median(values) if values else None


def ratio(numerator, denominator):
    return numerator / denominator if denominator is not None and denominator > 0 and numerator is not None else None


def distribution(values):
    return {'observations': len(values), 'sum_ms': sum(values) / 1e6,
            'p50_ms': quantile(values, .5) / 1e6 if values else None,
            'p95_ms': quantile(values, .95) / 1e6 if values else None,
            'minimum_ms': min(values) / 1e6 if values else None,
            'maximum_ms': max(values) / 1e6 if values else None}


def key_for(item):
    return item['fixture_id'], item['engine'], item['mode']


def prepared_dir(runs, cohort):
    choices = [runs.parent / ('prepared-' + cohort), runs / 'prepared' / cohort,
               runs.parent / 'prepared' / cohort]
    for directory in choices:
        if (directory / 'prepared.json').is_file():
            return directory
    raise ValueError(f'Missing prepared manifest for {cohort}; tried {choices}')


def audit_prepared(directory, repo):
    path = directory / 'prepared.json'
    manifest = load(path)
    verified = {'manifest_sha256': sha(path.read_bytes()), 'variants': {}, 'harness_files': 0}
    for name, expected in manifest['harness_sha256'].items():
        saved = directory / 'harness' / name
        fail_unless(sha(saved.read_bytes()) == expected, f'Frozen harness mismatch: {saved}')
        fail_unless(sha((repo / 'benchmark/solver_comparison' / name).read_bytes()) == expected,
                    f'Current harness differs from frozen {name}')
        verified['harness_files'] += 1
    for label, item in manifest['variants'].items():
        source = item['source']
        archive_bytes = (directory / item['source_archive']).read_bytes()
        fail_unless(sha(archive_bytes) == item['source_archive_sha256'], 'Source archive mismatch')
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:gz') as archive:
            members = archive.getmembers()
            fail_unless(all(member.isfile() for member in members), 'Non-regular source archive member')
            files = {member.name: archive.extractfile(member).read() for member in members}
        fail_unless(len(files) == len(members), 'Duplicate source archive paths')
        fail_unless(set(files) == set(source['source_sha256']), 'Source archive population differs')
        for name, data in files.items():
            fail_unless(sha(data) == source['source_sha256'][name], 'Frozen source hash mismatch: ' + name)
        ref = source['source_commit']
        for field, suffix in [('source_tree', '^{tree}'), ('library_tree', ':lib'), ('test_tree', ':test')]:
            actual = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', ref + suffix], text=True).strip()
            fail_unless(actual == source[field], 'Source provenance tree mismatch: ' + field)
        tracked = sorted(set(files) - {'.dart_tool/package_config.json', 'pubspec.lock'})
        committed_archive = subprocess.check_output(['git', '-C', str(repo), 'archive', '--format=tar', ref, '--', *tracked])
        with tarfile.open(fileobj=io.BytesIO(committed_archive), mode='r:') as committed:
            committed_files = {m.name: committed.extractfile(m).read() for m in committed if m.isfile()}
        fail_unless(set(committed_files) == set(tracked), 'Committed source population differs')
        for name in tracked:
            fail_unless(committed_files[name] == files[name], 'Frozen source differs from git commit: ' + name)
        exe = directory / item['executable']
        exe_present = exe.is_file()
        if exe_present:
            fail_unless(sha(exe.read_bytes()) == item['executable_sha256'], 'Executable hash mismatch')
        verified['variants'][label] = {
            'source_commit': ref, 'library_tree': source['library_tree'], 'test_tree': source['test_tree'],
            'source_files_verified': len(files), 'git_source_files_verified': len(tracked),
            'source_archive_sha256': item['source_archive_sha256'],
            'pubspec_lock_sha256': source['source_sha256']['pubspec.lock'],
            'executable_sha256': item['executable_sha256'], 'executable_bytes_present_and_verified': exe_present}
    before, after = manifest['variants']['before'], manifest['variants']['after']
    for name in ('benchmark/solver_comparison/dart_adapter.dart', 'benchmark/solver_comparison/dart_adapter_core.dart',
                 'pubspec.yaml', 'pubspec.lock'):
        fail_unless(before['source']['source_sha256'][name] == after['source']['source_sha256'][name],
                    'Paired adapter/dependency inputs differ: ' + name)
    return manifest, verified


def audit_run(directory, expected_round, preparation, prep_audit, oracle):
    manifest, summary = load(directory / 'manifest.json'), load(directory / 'comparison.json')
    fail_unless(manifest['status'] == 'complete', 'Run incomplete: ' + str(directory))
    fail_unless(summary['protocol_ok'] and summary['qualification_passed'], 'Run failed qualification')
    fail_unless(manifest['rounds'] == 1 and manifest['start_round'] == expected_round - 1, 'Round index mismatch')
    fail_unless(manifest['prepared_manifest_sha256'] == prep_audit['manifest_sha256'], 'Preparation manifest digest mismatch')
    fail_unless(manifest['preparation'] == preparation, 'Embedded preparation differs')
    fail_unless(manifest['harness_sha256'] == preparation['harness_sha256'], 'Harness hashes differ')
    fail_unless(manifest['variants'] == ['before', 'after'], 'Expected a paired run')
    expected_keys = {(fixture, engine, mode) for fixture in manifest['fixture_ids']
                     for engine in manifest['engines'] for mode in manifest['modes']}
    groups = {key_for(group): group for group in summary['groups']}
    fail_unless(set(groups) == expected_keys and len(groups) == len(summary['groups']), 'Incomplete/duplicate summary groups')
    paired = collections.defaultdict(dict)
    counts = collections.Counter()
    non_time_mismatches = []
    timestamps = []
    fingerprint = sha(canonical({key: manifest.get(key) for key in ENVIRONMENT}).encode())
    for side in ('before', 'after'):
        lane = load(directory / side / 'manifest.json')
        for field in ('source_commit', 'library_tree', 'test_tree'):
            fail_unless(lane[field] == preparation['variants'][side]['source'][field], 'Lane provenance mismatch')
        job_paths = sorted((directory / side).glob('*/job.json'))
        fail_unless(len(job_paths) == len(expected_keys), 'Incorrect job population')
        for jp in job_paths:
            job, parent = load(jp), jp.parent
            identity = key_for(job)
            fail_unless(identity in expected_keys and side not in paired[identity], 'Unexpected/duplicate job')
            fail_unless(job['round'] == expected_round and job['variant'] == side, 'Job round or side mismatch')
            fail_unless(not job['timed_out'] and job['returncode'] == 0 and not job['parse_errors'], 'Process timeout/exit/parse failure')
            request_bytes = read_maybe_gzip(parent / 'request.json')
            fail_unless(sha(request_bytes) == job['request_sha256'], 'Request digest mismatch')
            request = read_json(request_bytes)
            fail_unless(request['samples'] == manifest['samples'] and request['warmups'] == manifest['warmups'], 'Request operation count mismatch')
            fail_unless((request['fixture']['id'], request['engine'], request['mode']) == identity, 'Request identity mismatch')
            checked = [read_json(line) for line in read_maybe_gzip(parent / 'checked.jsonl').splitlines()]
            output = [read_json(line) for line in read_maybe_gzip(parent / 'stdout.jsonl').splitlines()]
            metadata = [item for item in output if item.get('record') == 'metadata']
            raw = [item for item in output if item.get('record') != 'metadata']
            fail_unless(metadata == job['metadata'], 'Raw adapter metadata mismatch')
            expected_indices = list(range(-request['warmups'], request['samples']))
            fail_unless([item.get('index') for item in raw] == expected_indices, 'Missing, duplicate or unordered raw indices')
            fail_unless(len(raw) == len(checked), 'Checked/raw population mismatch')
            for record, saved in zip(raw, checked):
                fail_unless(key_for(record) == identity, 'Raw record identity mismatch')
                fail_unless(record['warmup'] == (record['index'] < 0), 'Warmup/index mismatch')
                verdict = oracle.check(request, record)
                fail_unless(canonical(saved) == canonical(dict(record, oracle=verdict)), 'Saved raw/oracle record differs from independent recheck')
                fail_unless(verdict['accepted'] == request['fixture']['expected_feasible'], 'Unexpected physical outcome')
                fail_unless(record['accepted'] == verdict['accepted'] and not record.get('adapter_error'), 'Adapter/oracle disagreement or exception')
                for field in TIMES:
                    fail_unless(type(record[field]) in (int, float) and math.isfinite(record[field]) and record[field] >= 0, 'Invalid timing field')
                fail_unless(record['elapsed_ns'] + 10 >= record['build_ns'] + record['solve_ns'], 'Overlapping timer intervals')
                counts['raw_records'] += 1
                counts['measured_operations' if record['index'] >= 0 else 'warmup_operations'] += 1
                counts['accepted_operations' if verdict['accepted'] else 'valid_rejected_operations'] += 1
            main = [record for record in raw if record['index'] >= 0]
            accepted = [record for record in main if record['accepted']]
            counts['jobs'] += 1
            counts['process_percentiles_verified'] += 2
            stats = {field: distribution([record[field] for record in main]) for field in TIMES}
            group_side = groups[identity][side]
            for p, label in ((.5, 'p50'), (.95, 'p95')):
                actual = quantile([record['elapsed_ns'] / 1e6 for record in accepted], p)
                fail_unless(actual == group_side['median_process_accepted_' + label + '_ms'], 'Saved comparison percentile mismatch')
                fail_unless(actual == job['summary']['accepted_' + label + '_ms'], 'Saved job percentile mismatch')
            fail_unless(group_side['main']['completed'] == len(main) and group_side['main']['accepted'] == len(accepted), 'Saved group counts mismatch')
            fail_unless(job['summary']['completed_records'] == len(raw) and job['summary']['completed_samples'] == len(main), 'Saved job counts mismatch')
            fail_unless(job['summary']['complete'] and group_side['qualified_latency'], 'Saved job not qualified')
            timestamps.append((job['started_utc'], job['completed_utc']))
            paired[identity][side] = {'job': job, 'request': request, 'raw': raw, 'stats': stats,
                                     'raw_sha256': sha(read_maybe_gzip(parent / 'stdout.jsonl')),
                                     'checked_sha256': sha(read_maybe_gzip(parent / 'checked.jsonl'))}
    ordered = sorted(timestamps)
    fail_unless(all(a[1] <= b[0] for a,b in zip(ordered, ordered[1:])), 'Solver process intervals overlap')
    rows=[]
    for identity, pair in sorted(paired.items()):
        before, after = pair['before'], pair['after']
        fail_unless(canonical(before['request']) == canonical(after['request']), 'Paired requests differ')
        first = 'before' if before['job']['started_utc'] < after['job']['started_utc'] else 'after'
        for a,b in zip(before['raw'],after['raw']):
            left, right = ({key: value for key, value in record.items() if key not in TIMES} for record in (a,b))
            if canonical(left) != canonical(right):
                different = [key for key in sorted(set(left) | set(right)) if canonical(left.get(key)) != canonical(right.get(key))]
                non_time_mismatches.append({'round': expected_round, 'fixture_id':identity[0], 'engine':identity[1],
                                            'mode':identity[2], 'index':a['index'], 'fields':different})
            counts['paired_non_time_operations_compared'] += 1
        stats = {side:pair[side]['stats'] for side in ('before','after')}
        ratios = {field:{metric:ratio(stats['after'][field][metric],stats['before'][field][metric])
                         for metric in ('sum_ms','p50_ms','p95_ms')} for field in TIMES}
        for metric in ('p50','p95'):
            fail_unless(ratios['elapsed_ns'][metric+'_ms'] == groups[identity]['after_over_before_'+metric], 'Saved ratio mismatch')
        rows.append({'round':expected_round, 'fixture_id':identity[0], 'engine':identity[1], 'mode':identity[2],
                     'geometric_free_coordinates':before['job'].get('geometric_free_coordinates'),
                     'first':first, 'physical_tolerance':before['request']['tolerance'],
                     'process_statistics':stats, 'after_over_before':ratios,
                     'raw_sha256':{side:pair[side]['raw_sha256'] for side in ('before','after')},
                     'checked_sha256':{side:pair[side]['checked_sha256'] for side in ('before','after')}})
    return {'round':expected_round,'directory':str(directory),'manifest_sha256':sha((directory/'manifest.json').read_bytes()),
            'comparison_sha256':sha((directory/'comparison.json').read_bytes()),'environment':{k:manifest.get(k) for k in ENVIRONMENT},
            'environment_sha256':fingerprint,'counts':dict(counts), 'non_time_mismatches':non_time_mismatches,
            'rows':rows}


def aggregate(rows):
    result=[]
    grouped=collections.defaultdict(list)
    for row in rows:
        grouped[key_for(row)].append(row)
    for identity,pairs in sorted(grouped.items()):
        metrics={}
        for field in TIMES:
            metrics[field]={}
            for metric in ('sum_ms','p50_ms','p95_ms'):
                ratios=[p['after_over_before'][field][metric] for p in pairs]
                valid=[r for r in ratios if r is not None]
                before=[p['process_statistics']['before'][field][metric] for p in pairs]
                after=[p['process_statistics']['after'][field][metric] for p in pairs]
                by_order={}
                for first in ('before','after'):
                    selected=[p for p in pairs if p['first']==first]
                    rs=[p['after_over_before'][field][metric] for p in selected]
                    available=[v for v in rs if v is not None]
                    by_order[first+'_first']={'pairs':len(selected),'ratios':rs,'median_paired_ratio':median(available),
                        'ratio_of_median_process_statistics':ratio(median([p['process_statistics']['after'][field][metric] for p in selected]),
                                                                  median([p['process_statistics']['before'][field][metric] for p in selected]))}
                regressions=[p['round'] for p in pairs if p['after_over_before'][field][metric] is not None and p['after_over_before'][field][metric]>1.05]
                improvements=[p['round'] for p in pairs if p['after_over_before'][field][metric] is not None and p['after_over_before'][field][metric]<.95]
                metrics[field][metric]={'before_median_process_statistic':median(before), 'after_median_process_statistic':median(after),
                    'ratio_of_median_process_statistics':ratio(median(after),median(before)),
                    'median_paired_ratio':median(valid),
                    'geometric_mean_paired_ratio':math.exp(sum(math.log(r) for r in valid)/len(valid)) if valid and all(r>0 for r in valid) else None,
                    'minimum_paired_ratio':min(valid) if valid else None,'maximum_paired_ratio':max(valid) if valid else None,
                    'round_ratios':ratios,'order_strata':by_order,
                    'regression_over_5pct_rounds':regressions,'improvement_over_5pct_rounds':improvements,
                    'repeated_regression_over_5pct':len(regressions)>=2,
                    'regression_over_5pct_in_both_orders':all(any(p['round'] in regressions and p['first']==first for p in pairs) for first in ('before','after'))}
        totals={side:{field:{'observations':sum(p['process_statistics'][side][field]['observations'] for p in pairs),
                             'sum_ms':sum(p['process_statistics'][side][field]['sum_ms'] for p in pairs)} for field in TIMES} for side in ('before','after')}
        result.append({'fixture_id':identity[0],'engine':identity[1],'mode':identity[2],
                       'geometric_free_coordinates':pairs[0]['geometric_free_coordinates'],
                       'pairs':len(pairs),'process_order':[p['first'] for p in pairs],
                       'timing':metrics,'observations_and_totals':totals})
    return result


def pct(value):
    return 'n/a' if value is None else f'{100*(value-1):+.1f}%'


def markdown(report):
    text=['# Independent recovery benchmark audit','',
          'All effects below are after/before within one process pair and one recovered host cohort. '
          'Each process has equal weight; raw operations are not pooled across processes for percentile claims. '
          'A/A observed ranges describe this run only and do not prove that any candidate effect is noise.','',
          f"Audit passed: **{report['passed']}**. "
          f"Non-timing output mismatches: **{report['non_time_mismatch_count']}**.",'',
          '## Raw and provenance checks','']
    for name,cohort in report['cohorts'].items():
        c=cohort['counts']
        text.append(f"- {name}: {c.get('jobs',0)} processes; {c.get('measured_operations',0)} measured operations; "
                    f"{c.get('warmup_operations',0)} warmups; {c.get('accepted_operations',0)} accepted operations. "
                    f"{c.get('paired_non_time_operations_compared',0)} paired non-timing records compared.")
    text+=['','## Per-case effects','',
           'Median pair and median-process ratio are different summaries and both are shown. '
           'Repeated regression means more than 5% higher elapsed p50 in at least two rounds; this is a descriptive flag, not a significance test.','']
    for name,cohort in report['cohorts'].items():
        text += [f'### {name}','',
                 '| Fixture | Engine | Mode | Before / after p50 (ms) | Ratio of median p50 | Median paired p50 | Four round p50 effects | p95 median pair | Before-first / after-first p50 | Repeated >5% | A/A p50 range |',
                 '|---|---|---|---:|---:|---:|---|---:|---|---|---|']
        for group in cohort['groups']:
            p=group['timing']['elapsed_ns']['p50_ms']; q=group['timing']['elapsed_ns']['p95_ms']; a=group.get('aa_observation')
            control='not measured' if a is None else f"{pct(a['p50_min_ratio'])} to {pct(a['p50_max_ratio'])}"
            text.append('| '+' | '.join([group['fixture_id'],group['engine'],group['mode'],
                f"{p['before_median_process_statistic']:.4f} / {p['after_median_process_statistic']:.4f}",
                pct(p['ratio_of_median_process_statistics']),pct(p['median_paired_ratio']),', '.join(map(pct,p['round_ratios'])),pct(q['median_paired_ratio']),
                pct(p['order_strata']['before_first']['median_paired_ratio'])+' / '+pct(p['order_strata']['after_first']['median_paired_ratio']),
                ', '.join(map(str,p['regression_over_5pct_rounds'])) if p['repeated_regression_over_5pct'] else 'no',control])+' |')
        text.append('')
    text+=['## Limits and retention criteria','',
           '- Keep correctness and bounded-resource behavior as gates. Physical acceptance, tolerances, callback ordering, work caps, cancellation, and result ownership are not performance tuning parameters.',
           '- Judge useful gain on the code path that executes the candidate, and report both favorable and adverse controls. A/A is a descriptive context, never a correction to subtract.',
           '- Four process pairs provide limited replication. A gain that reverses with process order or has large control variation remains uncertain; no universal nonregression follows from this experiment.',
           '- Preserve historical cohorts separately. This audit does not join the recovered-host timing population to an earlier workspace or runtime.',
           '- Timing is native build/update through solve and extraction, excluding process startup, JSON serialization, and the independent oracle. Build/solve/elapsed observations and sums are in the JSON report.',
           '- Bit-sensitive canonical JSON comparison is used for every non-timing record, including coordinates and work counters. Mismatches are retained explicitly; they are never silently excluded.','']
    return '\n'.join(text)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runs',type=Path,required=True)
    parser.add_argument('--repo',type=Path,default=Path.cwd())
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--cohorts',default='cg,identity,combined,aa')
    parser.add_argument('--rounds',type=int,default=4)
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    oracle_path=args.repo/'benchmark/solver_comparison/oracle.py'
    spec=importlib.util.spec_from_file_location('physical_oracle',oracle_path)
    oracle=importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
    report={'schema_version':1,'passed':False,'runs':str(args.runs.resolve()),
            'script_sha256':sha(Path(__file__).read_bytes()),'oracle_sha256':sha(oracle_path.read_bytes()),
            'definitions':{'process_percentile':'sorted[ceil((n-1)*p)]',
                           'aggregation':'Each process pair has equal weight. Separate median pair ratios and ratios of median process percentiles.',
                           'non_time_comparison':'Canonical JSON equality of all raw record fields except build_ns,solve_ns,elapsed_ns; preserves numeric signed-zero text.',
                           'regression_flag':'after/before > 1.05 in at least two rounds; descriptive, no significance assertion',
                           'aa':'Observed range only; never subtracted from candidate ratios or used to prove absence of regression'},
            'cohorts':{},'non_time_mismatch_count':0}
    try:
        all_environment=set()
        for name in args.cohorts.split(','):
            directory=prepared_dir(args.runs,name); preparation,prep_audit=audit_prepared(directory,args.repo)
            if name=='aa':
                fail_unless(preparation['variants']['before']['executable_sha256']==preparation['variants']['after']['executable_sha256'], 'A/A executables differ')
                fail_unless(preparation['variants']['before']['source_archive_sha256']==preparation['variants']['after']['source_archive_sha256'], 'A/A source archives differ')
            rounds=[]
            for n in range(1,args.rounds+1):
                run=audit_run(args.runs/f'{name}-round{n}',n,preparation,prep_audit,oracle)
                rounds.append(run); all_environment.add(run['environment_sha256'])
                report['non_time_mismatch_count']+=len(run['non_time_mismatches'])
            counts=collections.Counter()
            for run in rounds:counts.update(run['counts'])
            groups=aggregate([row for run in rounds for row in run['rows']])
            for group in groups:
                fail_unless(len(set(group['process_order']))==2,'Both process orders were not measured')
                if args.rounds%2==0:
                    fail_unless(group['process_order'].count('before')==args.rounds//2,'Process orders not balanced')
            report['cohorts'][name]={'preparation_audit':prep_audit,'counts':dict(counts),'rounds':rounds,'groups':groups}
        fail_unless(len(all_environment)==1,'Refusing to aggregate different runtime/CPU/affinity environments')
        controls={key_for(g):g for g in report['cohorts'].get('aa',{}).get('groups',[])}
        for name,cohort in report['cohorts'].items():
            for group in cohort['groups']:
                control=controls.get(key_for(group))
                if control is not None:
                    p=control['timing']['elapsed_ns']['p50_ms'];q=control['timing']['elapsed_ns']['p95_ms']
                    effect=group['timing']['elapsed_ns']['p50_ms']
                    group['aa_observation']={'p50_min_ratio':p['minimum_paired_ratio'],'p50_max_ratio':p['maximum_paired_ratio'],
                        'p50_median_pair_ratio':p['median_paired_ratio'],'p95_min_ratio':q['minimum_paired_ratio'],'p95_max_ratio':q['maximum_paired_ratio'],
                        'candidate_rounds_outside_aa_p50_range':[i+1 for i,v in enumerate(effect['round_ratios']) if v<p['minimum_paired_ratio'] or v>p['maximum_paired_ratio']],
                        'interpretation':'Descriptive same-cohort variation; this range is not a confidence interval and does not establish causality or no regression.'}
                else:group['aa_observation']=None
        report['passed']=report['non_time_mismatch_count']==0
    except Exception as error:
        report['error']=f'{type(error).__name__}: {error}'
        (args.out/'audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        raise
    (args.out/'audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    (args.out/'audit.md').write_text(markdown(report))
    print(json.dumps({'passed':report['passed'],'cohorts':{name:c['counts'] for name,c in report['cohorts'].items()},
                      'non_time_mismatch_count':report['non_time_mismatch_count'],'out':str(args.out)}))
    return 0 if report['passed'] else 1

if __name__=='__main__':
    sys.exit(main())

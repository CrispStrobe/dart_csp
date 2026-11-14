"""Reconstruct paired normal benchmark rows without importing project code."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics

p = argparse.ArgumentParser()
p.add_argument('raw', type=Path)
p.add_argument('summary', type=Path)
p.add_argument('--output', type=Path, required=True)
args = p.parse_args()

def load(path):
    blob = path.read_bytes()
    return json.loads(gzip.decompress(blob) if path.suffix == '.gz' else blob,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))

raw, summary = load(args.raw), load(args.summary)
counts, findings = Counter(), []

def check(value, context):
    counts['checks'] += 1
    if not value:
        findings.append(context)

def distributions(value, prefix=''):
    if not isinstance(value, dict):
        return
    if 'p50' in value and 'p95' in value and 'samples_us' in value:
        yield prefix, value
        return
    for name, child in value.items():
        if isinstance(child, dict):
            yield from distributions(child, prefix + ('/' if prefix else '') + name)

def pct(before, after):
    return (after / before - 1) * 100 if before else None

def close(actual, expected):
    return actual == expected if actual is None or expected is None else math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-10)

expected_sequence = [(mode, round_, benchmark, revision)
    for mode in raw.get('modes', ('jit','aot'))
    for round_ in range(1,raw['rounds']+1)
    for benchmark in raw['harnesses']
    for revision in (('before','after') if round_ % 2 else ('after','before'))]
actual_sequence = [tuple(run[k] for k in ('mode','round','benchmark','revision')) for run in raw['runs']]
check(actual_sequence == expected_sequence,'complete alternating process order')
check(summary['revisions'] == raw['revisions'],'summary source identities')
grouped = defaultdict(dict)
previous_finish = None
sample_counts, warmup_counts = set(), set()
for run in raw['runs']:
    identity = tuple(run[k] for k in ('mode','round','benchmark','revision'))
    started, finished = [datetime.fromisoformat(run[k]) for k in ('started_at_utc','finished_at_utc')]
    check(finished >= started,[identity,'negative process duration'])
    check(previous_finish is None or started >= previous_finish,[identity,'overlapping processes'])
    previous_finish = finished
    result = run['result']
    flags = dict(x[2:].split('=',1) for x in run['arguments'])
    n, warmups = int(flags['samples']),int(flags['warmups'])
    sample_counts.add(n)
    warmup_counts.add(warmups)
    sample_meta = 'measured_iterations' if run['benchmark']=='cad_linkage' else 'measured_pairs'
    warm_meta = 'warmup_iterations' if run['benchmark']=='cad_linkage' else 'warmup_pairs'
    oracle = {'cad_linkage':'independent_physical_reuse_rollback_checks','cad_instances':'coordinate_volume_reuse_checks','cad':'analytic_volume_and_mesh_checks'}[run['benchmark']]
    check(result[sample_meta] == n and result[warm_meta] == warmups,[identity,'sampling metadata'])
    check(result.get('check_only',False) is False and result.get('operation_tracing_enabled',False) is False,[identity,'normal timing flags'])
    check(result[oracle] == 'passed',[identity,'oracle pass record'])
    counts['process_reports'] += 1
    for name, distribution in distributions(result):
        samples = distribution['samples_us']
        work = distribution['work_per_sample']
        check(len(samples)==len(work)==n,[identity,name,'sample/work count'])
        check(all(type(x) is int and x>=0 for x in samples),[identity,name,'finite nonnegative integer samples'])
        ordered = sorted(samples)
        values = {'p50':ordered[n//2], 'p95':ordered[math.ceil(.95*n)-1], 'p99':ordered[math.ceil(.99*n)-1]}
        for field, value in values.items():
            if field in distribution:
                check(value == distribution[field],[identity,name,field,'raw percentile mismatch'])
                counts['reported_percentiles_checked'] += 1
        grouped[run['mode'],run['benchmark'],name][run['revision'],run['round']] = {'values':values,'work':work}
        counts['distributions'] += 1
        counts['raw_samples'] += n
        counts['aligned_work_records'] += n

summary_rows = {(r['mode'],r['benchmark'],r['measurement']):r for r in summary['rows']}
check(len(summary_rows) == len(summary['rows']), 'unique summary row identities')
check(set(summary_rows)==set(grouped),'complete summary row identities')
rows = []
for key, processes in grouped.items():
    saved = summary_rows[key]
    row = {'mode':key[0],'benchmark':key[1],'measurement':key[2]}
    for field in ('p50','p95','p99'):
        before = [processes['before',i]['values'][field] for i in range(1,raw['rounds']+1)]
        after = [processes['after',i]['values'][field] for i in range(1,raw['rounds']+1)]
        b,a = statistics.median(before),statistics.median(after)
        pairs = [pct(x,y) for x,y in zip(before,after)]
        row[field] = {'before_us':b,'after_us':a,'aggregate_change_percent':pct(b,a),
            'paired_change_percent':pairs,
            'median_paired_change_percent':statistics.median(x for x in pairs if x is not None) if any(x is not None for x in pairs) else None,
            'faster_pairs':sum(y<x for x,y in zip(before,after)),
            'slower_pairs':sum(y>x for x,y in zip(before,after)),
            'equal_pairs':sum(y==x for x,y in zip(before,after))}
        if field in ('p50','p95'):
            for label,values in [('before',before),('after',after)]:
                check([record[field+'_us'] for record in saved[label]]==values,[key,label,field,'summary process values'])
                check([record['round'] for record in saved[label]]==list(range(1,raw['rounds']+1)),[key,label,'summary rounds'])
                check(saved[label+'_median_'+field+'_us']==statistics.median(values),[key,label,field,'summary aggregate'])
    check(close(saved['elapsed_change_percent'],row['p50']['aggregate_change_percent']),[key,'summary p50 percent'])
    check(close(saved['elapsed_ratio_before_over_after'],row['p50']['before_us']/row['p50']['after_us'] if row['p50']['after_us'] else None),[key,'summary p50 ratio'])
    for i in range(1,raw['rounds']+1):
        b,a = processes['before',i]['work'],processes['after',i]['work']
        for j,(old,new) in enumerate(zip(b,a)):
            check(old==new,[key,i,j,'paired physical/work record'])
            counts['paired_work_record_checks'] += 1
    rows.append(row)

report = {'status':'passed' if not findings else 'failed','method':'Independent JSON/sample reconstruction; no project collector, summarizer or auditor imported; no Dart workload.',
    'inputs':{str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in (args.raw,args.summary)},
    'revisions':raw['revisions'],'runtime':raw['runtime'],'counts':dict(counts),'findings':findings,'rows':rows,
    'rounds':raw['rounds'],'samples_per_distribution':sorted(sample_counts),
    'warmups_per_process':sorted(warmup_counts),
    'limitations':[f"{raw['rounds']} fresh pairs in a shared environment; no significance or causal attribution is established.", 'Percentiles aggregate by median of per-process values, not by pooling samples. Derived p99 remains limited tail evidence at the recorded sample counts.', 'Physical checks are supported by harness pass records and exact paired work records; full geometry coordinates are not serialized for independent replay.', 'Raw subprocess provenance, where retained, is audited separately. Current source/configuration inspection is also a separate check.']}
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'status':report['status'],'counts':dict(counts),'findings':findings}))
for row in rows:
    print(json.dumps(row))

import bisect
import collections
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics

source = Path('/workspace/scratch/5eda8163e92d/dart_csp/benchmark/results/2026-11-14-tail-operation-profile.json.gz')
data = json.loads(gzip.decompress(source.read_bytes()))
checks = 0
findings = []

def check(condition, context):
    global checks
    checks += 1
    if not condition:
        findings.append(context)

def coverage(spans):
    deltas = collections.defaultdict(int)
    for a, b in spans:
        deltas[a] += 1
        deltas[b] -= 1
    points = sorted(deltas)
    integral, depth, previous = [], 0, points[0] if points else 0
    area = 0
    for p in points:
        if depth:
            area += p - previous
        integral.append(area)
        depth += deltas[p]
        previous = p
    def prefix(t):
        i = bisect.bisect_right(points, t) - 1
        if i < 0:
            return 0
        # Union endpoint events are alternating starts/stops after coalescing.
        return integral[i] + (t - points[i] if active[i] else 0)
    active, depth = [], 0
    for p in points:
        depth += deltas[p]
        active.append(depth > 0)
    return lambda a, b: prefix(b) - prefix(a)

runs = []
counts = collections.Counter()
for run in data['runs']:
    identity = [run[k] for k in ('mode', 'round', 'benchmark', 'revision')]
    events = json.loads(run['trace_utf8'])
    check(hashlib.sha256(run['trace_utf8'].encode('utf-8', 'surrogateescape')).hexdigest() == run['trace_sha256'], [identity, 'trace digest'])
    stacks = collections.defaultdict(list)
    spans = []
    for index, event in enumerate(events):
        key = event.get('pid'), event.get('tid')
        phase = event.get('ph')
        if phase == 'B':
            stacks[key].append((index, event))
        elif phase == 'E':
            check(bool(stacks[key]), [identity, index, 'unmatched E'])
            if not stacks[key]:
                continue
            start_index, begin = stacks[key].pop()
            check((begin.get('name'), begin.get('cat')) == (event.get('name'), event.get('cat')), [identity, index, 'mismatched span'])
            spans.append((begin, begin['ts'], event['ts'], start_index, index))
        elif phase == 'X':
            spans.append((event, event['ts'], event['ts'] + event['dur'], index, index))
    unmatched = [(i,e) for stack in stacks.values() for i,e in stack]
    check(not any(e.get('cat') == 'GC' or e.get('name', '').startswith('cad_operation/') for _,e in unmatched), [identity,'unmatched GC/operation begin'])
    by_category_thread, by_category_pid = collections.defaultdict(list), collections.defaultdict(list)
    for event,a,b,_,_ in spans:
        by_category_thread[event.get('cat'), event.get('pid'), event.get('tid')].append((a,b))
        by_category_pid[event.get('cat'), event.get('pid')].append((a,b))
    thread_cover = {k:coverage(v) for k,v in by_category_thread.items()}
    pid_cover = {k:coverage(v) for k,v in by_category_pid.items()}
    operations = sorted((s for s in spans if s[0].get('name','').startswith('cad_operation/')), key=lambda s:s[1])
    expected = run['result'].get('measurements') or {k:run['result'][k] for k in ('cold_build_solve_regenerate','solved_pose_edit')}
    recorded = run['analysis']['operation_spans']
    check(len(operations) == len(recorded), [identity,'operation count'])
    by_case = collections.defaultdict(list)
    for rebuilt, stored in zip(operations, recorded):
        event,a,b,begin_index,end_index = rebuilt
        args = event['args']
        case, iteration = args['case'], args['iteration']
        check((a,b,begin_index,end_index,case,iteration) == (stored['start_us'],stored['end_us'],stored['begin_event'],stored['end_event'],stored['case'],stored['iteration']), [identity,case,iteration,'span identity'])
        pid,tid = event['pid'],event['tid']
        same_gc = thread_cover.get(('GC',pid,tid), lambda a,b:0)(a,b)
        any_gc = pid_cover.get(('GC',pid), lambda a,b:0)(a,b)
        same_compiler = thread_cover.get(('Compiler',pid,tid),lambda a,b:0)(a,b)
        for key,value in [('same_thread_gc_overlap_us',same_gc),('any_thread_gc_overlap_us',any_gc),('same_thread_compiler_overlap_us',same_compiler)]:
            check(value == stored[key], [identity,case,iteration,key,value,stored[key]])
        counts['operations'] += 1
        if iteration >= 0:
            us = expected[case]['samples_us'][iteration]
            check(us == stored['stopwatch_us'],[identity,case,iteration,'sample alignment'])
            check(0 <= us <= b-a,[identity,case,iteration,'sample inside span'])
            by_case[case].append({'iteration':iteration,'us':us,'same_gc':same_gc,'any_gc':any_gc,'compiler':same_compiler})
            counts['measured_operations'] += 1
    cases = {}
    for case, records in by_case.items():
        check([r['iteration'] for r in records] == list(range(data['samples'])),[identity,case,'complete ordered samples'])
        us = [r['us'] for r in records]
        no_gc = [r['us'] for r in records if not r['same_gc']]
        with_gc = [r['us'] for r in records if r['same_gc']]
        cutoff = sorted(us)[math.ceil(.95*len(us))-1]
        cases[case] = {
            'samples':len(records),
            'p50_us':statistics.median(us),'p95_us':cutoff,
            'p99_us':sorted(us)[math.ceil(.99*len(us))-1],
            'without_same_thread_gc_count':len(no_gc),
            'without_same_thread_gc_p50_us':statistics.median(no_gc) if no_gc else None,
            'with_same_thread_gc_count':len(with_gc),
            'with_same_thread_gc_p50_us':statistics.median(with_gc) if with_gc else None,
            'same_thread_gc_overlap_sum_us':sum(r['same_gc'] for r in records),
            'any_thread_gc_overlap_sum_us':sum(r['any_gc'] for r in records),
            'p95_tail_count':sum(r['us']>=cutoff for r in records),
            'p95_tail_with_same_thread_gc_count':sum(r['us']>=cutoff and r['same_gc']>0 for r in records),
            'same_thread_compiler_operation_count':sum(r['compiler']>0 for r in records),
        }
    counts['events'] += len(events)
    counts['completed_spans'] += len(spans)
    counts['unmatched_begins'] += len(unmatched)
    runs.append({'identity':identity,'cases':cases,'unmatched_begin_count':len(unmatched)})
report = {
    'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'checks':checks,'findings':findings,'counts':dict(counts),'runs':runs,
    'limitations':['This reconstructs retained operation traces and temporal GC/compiler overlap; it does not measure causation, allocation bytes, CPU attribution, or normal uninstrumented latency.', 'Package configuration original bytes are not embedded in these results; source/root checks relied on the saved collector and need fresh validation in a new cohort.']}
Path('/workspace/scratch/5eda8163e92d/recovery_operation_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'checks':checks,'findings':findings,'counts':dict(counts)}))
for run in runs:
    if run['identity'][0] == 'aot' and run['identity'][2] == 'cad_instances':
        print(json.dumps(run))

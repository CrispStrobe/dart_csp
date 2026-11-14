"""Independently reconcile saved normal-runner subprocess records."""
import argparse
from collections import Counter
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('input',type=Path)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
encoded=args.input.read_bytes()
data=json.loads(gzip.decompress(encoded) if args.input.suffix=='.gz' else encoded)
findings=[]
checks=0
counts=Counter()

def check(condition,context):
    global checks
    checks+=1
    if not condition:
        findings.append(context)

def instant(value):
    return datetime.fromisoformat(value)

check(data['status']=='completed','cohort completed')
check(set(data['modes'])=={'jit','aot'} and not data['diagnostic_only'],'both modes and final flag')
previous_finish=None
compile_records={}
for i,p in enumerate(data['process_records']):
    counts['process_records']+=1
    check(p['exit_code']==0 and p['timed_out'] is False,[i,'successful non-timeout exit'])
    started,finished=instant(p['started_at_utc']),instant(p['finished_at_utc'])
    check(finished>=started,[i,'nonnegative duration'])
    check(previous_finish is None or started>=previous_finish,[i,'sequential subprocess times'])
    previous_finish=finished
    for name in ('stdout','stderr'):
        actual=hashlib.sha256(p[name].encode('utf-8','surrogateescape')).hexdigest()
        check(actual==p[name+'_sha256'],[i,name,'original-byte digest'])
        counts['stream_hash_checks']+=1
    context=p.get('context')
    if not context:
        continue
    counts[context['phase']+'_records']+=1
    revision=context['revision']
    mapping=data['revisions'][revision]['package_mapping']
    check(p['cwd']==mapping['resolved_root'],[i,'source cwd'])
    if context['phase']=='compile':
        key=context['benchmark'],revision
        check(key not in compile_records,[i,'unique compile identity'])
        compile_records[key]=p
        check('--packages='+mapping['file'] in p['command'],[i,'compile package mapping'])
        check('benchmark/'+context['benchmark']+'.dart' in p['command'],[i,'compiled harness'])

seen_records=set()
for run in data['runs']:
    pointer=run['process_record']
    identity=tuple(run[k] for k in ('mode','round','benchmark','revision'))
    check(type(pointer) is int and 0<=pointer<len(data['process_records']),[identity,'process reference'])
    check(pointer not in seen_records,[identity,'unique process reference'])
    seen_records.add(pointer)
    p=data['process_records'][pointer]
    context=p['context']
    check(context=={'phase':'benchmark',**{k:run[k] for k in ('mode','round','benchmark','revision')}},[identity,'context identity'])
    check(p['command']==run['command'],[identity,'argv identity'])
    check(json.loads(p['stdout'])==run['result'],[identity,'raw stdout parses to retained result'])
    check(instant(run['started_at_utc'])<=instant(p['started_at_utc'])<=instant(p['finished_at_utc'])<=instant(run['finished_at_utc']),[identity,'run bounds enclose subprocess'])
    check(p['command'][-len(run['arguments']):]==run['arguments'],[identity,'sampling argv'])
    mapping=data['revisions'][run['revision']]['package_mapping']
    if run['mode']=='jit':
        check('--packages='+mapping['file'] in p['command'],[identity,'JIT package mapping'])
        check('benchmark/'+run['benchmark']+'.dart' in p['command'],[identity,'JIT harness'])
    else:
        compiled=compile_records[run['benchmark'],run['revision']]
        binary=compiled['command'][compiled['command'].index('-o')+1]
        check(p['command'][0]==binary,[identity,'AOT uses recorded compile output'])
        check(instant(compiled['finished_at_utc'])<=instant(p['started_at_utc']),[identity,'AOT compiled first'])
    counts['matched_benchmark_records']+=1

for benchmark in data['harnesses']:
    binaries=[]
    for revision in ('before','after'):
        p=compile_records[benchmark,revision]
        binaries.append(p['command'][p['command'].index('-o')+1])
    check(binaries[0]!=binaries[1],[benchmark,'distinct AOT binaries'])
check(counts['benchmark_records']==len(data['runs'])==len(seen_records),'every benchmark process represented once')
check(counts['compile_records']==2*len(data['harnesses']),'one compile per revision and harness')
report={'status':'passed' if not findings else 'failed','checks':checks,'counts':dict(counts),'findings':findings,
    'input':str(args.input),'input_sha256':hashlib.sha256(encoded).hexdigest(),
    'method':'Reversible original stream hashes, subprocess status/timestamps/argv, result parsing, explicit package mappings and compile/run linkage independently checked without importing project runner code.',
    'limitations':['Subprocess records establish the command/result chain, not SDK or executable byte identity; those binaries were not hashed.', 'Package configuration and project source hashes are recorded; installed dependency source bytes are not.', 'The review does not infer allocated bytes, GC attribution, significance or a performance guarantee.']}
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))

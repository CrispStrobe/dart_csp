from pathlib import Path
import gzip,hashlib,json,math,sys,statistics
REPO=Path('/workspace/scratch/9c3bd1b484d5/dart_csp')
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(REPO/'benchmark/solver_comparison'))
import oracle
sha=lambda b: hashlib.sha256(b).hexdigest()
allrows=[]; totals={}; mismatches=[]
for rnd in [1,2]:
 base=ROOT/f'cg-round{rnd}'; comp=json.loads((base/'comparison.json').read_text()); manifest=json.loads((base/'manifest.json').read_text()); assert comp==json.loads((REPO/f'benchmark/results/2026-11-14-local-completion/cg-round{rnd}-summary.json').read_text())
 assert manifest['prepared_manifest_sha256']==sha((ROOT/'prepared/cg/prepared.json').read_bytes())
 for file,h in manifest['harness_sha256'].items(): assert h==sha((REPO/'benchmark/solver_comparison'/file).read_bytes())
 groups={(g['fixture_id'],g['engine'],g['mode']):g for g in comp['groups']}; paired={}; total=0; measured=0
 for side in ['before','after']:
  jobs=sorted((base/side).glob('*/job.json')); assert len(jobs)==24
  for jp in jobs:
   p=jp.parent; job=json.loads(jp.read_text()); reqbytes=gzip.decompress((p/'request.json.gz').read_bytes()); req=json.loads(reqbytes); assert sha(reqbytes)==job['request_sha256']; assert job['returncode']==0 and not job['timed_out']
   checked=[json.loads(s) for s in gzip.decompress((p/'checked.jsonl.gz').read_bytes()).decode().splitlines()]
   stdout=[json.loads(s) for s in gzip.decompress((p/'stdout.jsonl.gz').read_bytes()).decode().splitlines()]; raw=[v for v in stdout if v.get('record')!='metadata']; assert len(raw)==len(checked)==29
   assert [v['index'] for v in raw]==list(range(-8,21))
   for v,c in zip(raw,checked):
    expected=oracle.check(req,v); assert c==dict(v,oracle=expected); assert expected['accepted'] and v['accepted']; total+=1; measured+=v['index']>=0
   key=(job['fixture_id'],job['engine'],job['mode']); grp=groups[key][side]
   vals=sorted(v['elapsed_ns']/1e6 for v in raw if v['index']>=0)
   assert vals[math.ceil((len(vals)-1)*.50)]==grp['median_process_accepted_p50_ms']
   assert vals[math.ceil((len(vals)-1)*.95)]==grp['median_process_accepted_p95_ms']
   paired.setdefault(key,{})[side]=(job,req,raw)
 for key,pair in paired.items():
  a,reqa,ra=pair['before']; b,reqb,rb=pair['after']; assert reqa==reqb
  first='before' if a['started_utc']<b['started_utc'] else 'after'
  if first=='before': assert a['completed_utc']<=b['started_utc']
  else: assert b['completed_utc']<=a['started_utc']
  excluded={'elapsed_ns','build_ns','solve_ns'}
  for va,vb in zip(ra,rb):
   ca={k:v for k,v in va.items() if k not in excluded}; cb={k:v for k,v in vb.items() if k not in excluded}
   if ca!=cb: mismatches.append({'round':rnd,'fixture':key,'index':va['index'],'keys':[k for k in ca if ca[k]!=cb[k]]})
  g=groups[key]; p50=g['after']['median_process_accepted_p50_ms']/g['before']['median_process_accepted_p50_ms']; p95=g['after']['median_process_accepted_p95_ms']/g['before']['median_process_accepted_p95_ms']; assert p50==g['after_over_before_p50']; assert p95==g['after_over_before_p95']
  allrows.append(dict(round=rnd,fixture=key[0],engine=key[1],mode=key[2],first=first,before_p50_ms=g['before']['median_process_accepted_p50_ms'],after_p50_ms=g['after']['median_process_accepted_p50_ms'],p50_ratio=p50,p95_ratio=p95))
 totals[str(rnd)]=dict(jobs=48,raw_records=total,measured_operations=measured,accepted=total,summary_exact=True,oracle_recomputed=True)
print(json.dumps(totals,indent=2)); print('Non-timing record differences:',len(mismatches))
for key in sorted({(r['fixture'],r['engine'],r['mode']) for r in allrows}):
 rows=[r for r in allrows if (r['fixture'],r['engine'],r['mode'])==key]
 print('%-25s %-17s %-4s'%key, ' | '.join(f"R{r['round']} {r['first']}-first p50 {r['before_p50_ms']:.3f}→{r['after_p50_ms']:.3f}ms ({100*(r['p50_ratio']-1):+.1f}%) p95 {100*(r['p95_ratio']-1):+.1f}%" for r in rows))
(ROOT/'raw-audit.json').write_text(json.dumps(dict(totals=totals,non_timing_record_differences=mismatches,rows=allrows),indent=2)+'\n')

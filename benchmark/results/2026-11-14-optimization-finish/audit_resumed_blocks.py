#!/usr/bin/env python3
"""Audit only the three declared resumed-session blocks, without timing pooling."""
from __future__ import annotations
import argparse
import collections
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

FIXTURES = ['axis_rectangle', 'ladder_3_components_1',
            'ladder_25_components_1', 'ladder_500_components_1',
            'laman_free_100', 'laman_free_500']


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def ensure(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--runs', type=Path, required=True)
    parser.add_argument('--saved', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--original-audit', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    audit = load_module('saved_independent_analyzer', args.repo/'benchmark/results/2026-11-14-optimization-recovery/analyze_recovery.py')
    oracle = load_module('independent_oracle', args.repo/'benchmark/solver_comparison/oracle.py')
    transport = load_module('exact_evidence_transport', args.repo/'tool/pack_optimization_evidence.py')
    recovery = load(args.saved/'recovery.json')
    original = load(args.original_audit)
    ensure(recovery['session_id'] == 'b51b355c4f64', 'Unexpected resumed session')
    ensure(original['passed'], 'Original-session audit not passing')
    report = {'schema_version': 1, 'passed': False,
              'session_id': recovery['session_id'],
              'scope': 'Only identity-round4, combined-round4, aa-round4 in resumed session b51b355c4f64; timing results remain separate from original session d1244c09828b.',
              'original_audit_sha256': digest(args.original_audit.read_bytes()),
              'recovery_sha256': digest((args.saved/'recovery.json').read_bytes()),
              'blocks': {}, 'errors': [], 'non_time_mismatches': 0}
    chronology = []
    try:
        environments = set()
        for cohort in ('identity', 'combined', 'aa'):
            name = cohort+'-round4'
            directory = args.runs/name
            preparation, provenance = audit.audit_prepared(args.prepared/('prepared-'+cohort), args.repo)
            ensure(all(v['executable_bytes_present_and_verified'] for v in provenance['variants'].values()), 'Executable bytes missing')
            if cohort == 'aa':
                b,a = (preparation['variants'][s] for s in ('before','after'))
                ensure(b['executable_sha256'] == a['executable_sha256'], 'A/A binary mismatch')
                ensure(b['source_archive_sha256'] == a['source_archive_sha256'], 'A/A source mismatch')
            status = load(args.saved/(name+'-status.json'))
            ensure(status['session_id'] == report['session_id'], name+': session differs')
            ensure(status['recovery_sha256'] == report['recovery_sha256'], name+': recovery digest differs')
            ensure(status['passed'] and status['exit_code'] == 0 and status['pack_exit_code'] == 0, name+': incomplete status')
            manifest = load(directory/'manifest.json')
            expected = {'samples':21,'warmups':8,'timeout_seconds':30,'pinned_cpu':0,
                        'engines':['dart_2d_analytic','dart_3d_ad'],'modes':['cold','warm'],
                        'fixture_ids':FIXTURES[:-1] if cohort=='aa' else FIXTURES,
                        'purpose':'measurement','rounds':1,'start_round':3}
            for field,value in expected.items():
                ensure(manifest[field] == value, name+': fixed declaration differs: '+field)
            evidence = load(args.saved/(name+'-evidence.json'))
            restored = args.out/'restored'/name
            restore_result = transport.restore(args.saved/(name+'-evidence.json'), restored)
            parts=[]
            for part in evidence['archive_parts']:
                data=(args.saved/part['file']).read_bytes()
                ensure(len(data)==part['bytes'] and digest(data)==part['sha256'], name+': archive part mismatch')
                parts.append(data)
            packed=b''.join(parts)
            ensure(len(packed)==evidence['archive_bytes'] and digest(packed)==evidence['archive_sha256'], name+': archive hash mismatch')
            population={p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file()}
            ensure(population==set(evidence['files']), name+': exact file set differs')
            for path,entry in evidence['files'].items():
                data=(directory/path).read_bytes()
                ensure(len(data)==entry['bytes'] and digest(data)==entry['sha256'], name+': raw file differs: '+path)
                ensure((restored/path).read_bytes()==data,name+': archive restoration differs from raw file: '+path)
            ensure((directory/'comparison.json').read_bytes()==(args.saved/(name+'-summary.json')).read_bytes(), name+': saved summary differs')
            raw=audit.audit_run(directory,4,preparation,provenance,oracle)
            for row in raw['rows']:
                parity=(3+manifest['fixture_ids'].index(row['fixture_id'])+
                        manifest['modes'].index(row['mode'])+
                        manifest['engines'].index(row['engine']))%2
                ensure(row['first']==('after' if parity else 'before'),name+': incorrect process order')
            jobs=40 if cohort=='aa' else 48
            for field,count in [('jobs',jobs),('measured_operations',jobs*21),
                                ('warmup_operations',jobs*8),('accepted_operations',jobs*29),
                                ('paired_non_time_operations_compared',jobs*29//2),
                                ('process_percentiles_verified',jobs*2)]:
                ensure(raw['counts'][field]==count,name+': incorrect raw population '+field)
            report['non_time_mismatches']+=len(raw['non_time_mismatches'])
            report['blocks'][name]={'preparation_audit':provenance,'artifact_files':len(population),
                                   'archive_sha256':evidence['archive_sha256'],
                                   'exact_archive_restoration':restore_result,'run':raw}
            environments.add(raw['environment_sha256'])
            chronology.append({'block':name,'started':manifest['started_utc'],
                               'finished':manifest['finished_utc'],
                               'analysis_finished':manifest['analysis_finished_utc']})
            print(json.dumps({'block':name,'passed':True,'counts':raw['counts']}),flush=True)
        ensure(len(environments)==1,'Resumed environment fingerprints differ')
        ensure(report['non_time_mismatches']==0,'Non-timing outputs differ')
        ordered=sorted(chronology,key=lambda r:r['started'])
        ensure([r['block'] for r in ordered]==['identity-round4','combined-round4','aa-round4'],'Resumed block order differs')
        ensure(all(a['analysis_finished']<=b['started'] for a,b in zip(ordered,ordered[1:])),'Resumed blocks overlap')
        totals=collections.Counter()
        for block in report['blocks'].values():totals.update(block['run']['counts'])
        ensure(totals['jobs']==136 and totals['measured_operations']==2856 and totals['warmup_operations']==1088,'Resumed totals differ from fixed declaration')
        combined=collections.Counter(original['counts']);combined.update(totals)
        ensure(combined['jobs']==736 and combined['measured_operations']==15456 and combined['warmup_operations']==5888,'Complete declaration population differs')
        report['counts']=dict(totals)
        report['complete_protocol_population_counts_only']=dict(combined)
        report['population_note']='These are correctness/completion counts only. No process latency population is pooled across sessions.'
        report['environment_fingerprint_matches_original']=next(iter(environments))==original['environment_sha256']
        report['environment_note']='Matching recorded environment fields do not establish an identical runtime session and do not authorize pooled timing claims.'
        report['chronology']=ordered
        report['passed']=True
    except Exception as error:
        report['errors'].append(type(error).__name__+': '+str(error))
        raise
    finally:
        (args.out/'resumed-block-audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    print(json.dumps({'passed':report['passed'],'counts':report['counts'],'complete_population':report['complete_protocol_population_counts_only']}),flush=True)


if __name__=='__main__':
    main()

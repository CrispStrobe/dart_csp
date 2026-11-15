#!/usr/bin/env python3
"""Audit the separately declared CG norm-fusion experiment; never run a solver.

The old CG/manifold protocol is unchanged. This auditor independently checks the
new fixed inventory/schedule, then reuses its existing raw geometry/provenance
analyzer. Decision functions are pure and can be checked with synthetic ratios.
"""
from __future__ import annotations

import argparse
import collections
from datetime import datetime, timezone
import gzip
import hashlib
import importlib.util
import itertools
import json
import math
from pathlib import Path, PurePosixPath
import statistics
import subprocess
import sys

SCHEMA = 'dart-csp-cg-norm-protocol-v1'
COHORTS = ('norm', 'aa')
FIXTURES = ('axis_rectangle', 'ladder_25_components_1',
            'ladder_500_components_1', 'laman_free_500')
QUALIFICATION = ('canonical_cell', 'axis_rectangle', 'coincidence',
    'contradictory_distance', 'ladder_3_components_1',
    'ladder_1_components_1_scale_1e-06', 'ladder_125_components_1',
    'ladder_500_components_1', 'laman_free_500')
ENGINES = ('dart_2d_analytic', 'dart_3d_ad')
MODES = ('cold', 'warm')
SIDES = ('before', 'after')
TARGETS = frozenset(('ladder_25_components_1', 'laman_free_500'))
CONTROLS = frozenset(('axis_rectangle', 'ladder_500_components_1'))
PRIMARY = ('laman_free_500', 'dart_3d_ad', 'warm')
BLOCKS = tuple(f'{c}-round{n}' for n in range(1, 5) for c in COHORTS)
SDK_SHA = '6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b'
LOCK_SHA = 'a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a'
PROTOCOL = {
    'fixtures': list(FIXTURES), 'engines': list(ENGINES), 'modes': list(MODES),
    'rounds': 4, 'samples': 21, 'warmups': 8, 'timeout_seconds': 30,
    'block_order': list(BLOCKS), 'qualification_fixtures': list(QUALIFICATION),
    'qualification_samples': 2, 'qualification_warmups': 1,
    'expected_blocks': 8, 'expected_processes': 256,
    'expected_measured_operations': 5376, 'expected_warmup_operations': 2048,
    'pair_order': '(round_zero_based + fixture_index + mode_index + engine_index) % 2; odd=after-first',
}
DECISION_RULES = {
    'primary': list(PRIMARY), 'primary_max_median_paired_p50': .95,
    'primary_min_improving_pairs': 3, 'primary_both_order_medians_below': 1.0,
    'aa_primary_median_inclusive': [.95, 1.05],
    'aa_primary_order_medians_inclusive': [.90, 1.10],
    'other_cg_p50_reject_if_median_and_both_orders_exceed': 1.05,
    'untouched_control_p50_reject_if_median_and_both_orders_exceed': 1.10,
    'cg_p95_reject_threshold_strict': 1.25,
    'cg_p95_reject_min_rounds': 3, 'cg_p95_reject_requires_both_orders': True,
    'no_extra_rounds_restarts_or_cross_session_pooling': True,
    'interpretation': 'Practical engineering gates, not statistical significance or confidence bounds; no A/A subtraction.',
}
SCRIPT_PATHS = {
    'raw_analyzer': 'benchmark/results/2026-11-14-optimization-recovery/analyze_recovery.py',
    'oracle': 'benchmark/solver_comparison/oracle.py',
    'collector': 'benchmark/solver_comparison/paired_dart_backends.py',
    'fixtures': 'benchmark/solver_comparison/fixtures.py',
    'packer': 'tool/pack_optimization_evidence.py',
}
VALIDATION_GATES = {('baseline', 'browser')} | {
    ('candidate', name) for name in
    ('format', 'analyze', 'focused', 'native', 'dart2js', 'dart2wasm', 'browser')}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def parse(data):
    def reject(value):
        raise ValueError('Nonfinite JSON constant: '+value)
    return json.loads(data, parse_constant=reject)


def read(path):
    return parse(path.read_bytes())


def stamp(value):
    result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(result.tzinfo is not None, 'Unzoned timestamp')
    return result.astimezone(timezone.utc)


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


def key(row):
    return row['fixture_id'], row['engine'], row['mode']


def safe_relative(value):
    path = PurePosixPath(value)
    require(isinstance(value, str) and value and not path.is_absolute()
            and '..' not in path.parts and str(path) == value,
            'Unsafe relative artifact path')
    return path


def session_path(value, root):
    path, parent = PurePosixPath(value), PurePosixPath(root)
    require(path.is_absolute() and '..' not in path.parts and path.is_relative_to(parent),
            'Command path falls outside declared session root: '+value)
    return path


def nonoverlap(intervals, label):
    ordered = sorted(intervals)
    for start, end, name in ordered:
        require(start < end, label+' empty/reversed interval: '+name)
    for a,b in zip(ordered, ordered[1:]):
        require(a[1] <= b[0], label+' overlap: '+a[2]+' / '+b[2])
    return ordered


def positive_ratio(value):
    require(type(value) in (float, int) and math.isfinite(value) and value > 0,
            'Ratio must be finite and strictly positive')
    return value


def summarize_pairs(pairs):
    require(len(pairs) == 4 and {r['round'] for r in pairs} == {1,2,3,4},
            'Decision requires exactly four distinct round pairs')
    pairs = sorted(pairs, key=lambda r:r['round'])
    require(all(r['first'] in SIDES for r in pairs), 'Unknown pair order')
    orders = {side:[r for r in pairs if r['first'] == side] for side in SIDES}
    require(all(len(v) == 2 for v in orders.values()), 'Decision requires two pairs per order stratum')
    p50 = [positive_ratio(r['p50_ratio']) for r in pairs]
    p95 = [positive_ratio(r['p95_ratio']) for r in pairs]
    return {
        'rounds': [r['round'] for r in pairs], 'first': [r['first'] for r in pairs],
        'p50_ratios': p50, 'p95_ratios': p95,
        'median_paired_p50': statistics.median(p50),
        'median_paired_p95': statistics.median(p95),
        'improving_p50_pairs': sum(v < 1 for v in p50),
        'order_median_p50': {side:statistics.median(positive_ratio(r['p50_ratio']) for r in rows)
                             for side, rows in orders.items()},
        'p95_over_125_rounds': [r['round'] for r in pairs if r['p95_ratio'] > 1.25],
        'p95_over_125_orders': sorted({r['first'] for r in pairs if r['p95_ratio'] > 1.25}),
    }


def decide(candidate_rows, aa_rows):
    """Pure, immutable engineering rules; rows grouped by (fixture,engine,mode)."""
    expected = set(itertools.product(FIXTURES, ENGINES, MODES))
    require(set(candidate_rows) == expected and set(aa_rows) == expected,
            'Decision matrix differs from the four-fixture declaration')
    norm = {k:summarize_pairs(v) for k,v in candidate_rows.items()}
    aa = {k:summarize_pairs(v) for k,v in aa_rows.items()}
    primary, control = norm[PRIMARY], aa[PRIMARY]
    gates = []

    def gate(name, passed, observed, criterion):
        gates.append({'name':name, 'passed':bool(passed), 'observed':observed,
                      'criterion':criterion})

    gate('primary_p50_improvement', primary['median_paired_p50'] <= .95,
         primary['median_paired_p50'], 'median paired p50 <= 0.95')
    gate('primary_improves_in_both_orders',
         all(v < 1 for v in primary['order_median_p50'].values()),
         primary['order_median_p50'], 'each order-stratum median paired p50 < 1.0')
    gate('primary_three_improving_pairs', primary['improving_p50_pairs'] >= 3,
         primary['improving_p50_pairs'], 'at least three of four p50 ratios < 1.0')
    gate('aa_primary_median_stability', .95 <= control['median_paired_p50'] <= 1.05,
         control['median_paired_p50'], 'A/A primary median paired p50 in inclusive [0.95,1.05]')
    gate('aa_primary_order_stability',
         all(.90 <= v <= 1.10 for v in control['order_median_p50'].values()),
         control['order_median_p50'], 'each A/A primary order median in inclusive [0.90,1.10]')
    adverse, tails = [], []
    for identity, row in sorted(norm.items()):
        fixture = identity[0]
        threshold = 1.05 if fixture in TARGETS else 1.10
        if identity != PRIMARY and (row['median_paired_p50'] > threshold
                and all(v > threshold for v in row['order_median_p50'].values())):
            adverse.append({'fixture_id':identity[0], 'engine':identity[1], 'mode':identity[2],
                'threshold_strict':threshold, 'median_paired_p50':row['median_paired_p50'],
                'order_median_p50':row['order_median_p50']})
        if fixture in TARGETS and len(row['p95_over_125_rounds']) >= 3 and len(row['p95_over_125_orders']) == 2:
            tails.append({'fixture_id':identity[0], 'engine':identity[1], 'mode':identity[2],
                'rounds':row['p95_over_125_rounds'], 'orders':row['p95_over_125_orders'],
                'ratios':row['p95_ratios']})
    gate('no_repeated_adverse_p50_gate', not adverse, adverse,
         'Reject another CG target >1.05, or untouched control >1.10, in overall median and both order medians')
    gate('no_repeated_target_tail_gate', not tails, tails,
         'Reject CG-target p95 >1.25 in >=3 rounds spanning both orders')
    passed = all(g['passed'] for g in gates)
    return {'passed':passed, 'recommendation':'retain' if passed else 'revert',
            'rules':DECISION_RULES, 'gates':gates,
            'failed_gates':[g['name'] for g in gates if not g['passed']],
            'interpretation':'Descriptive process-pair engineering decision; no significance claim, no A/A subtraction, no run extension.'}


def command_options(command):
    require(len(command) >= 3 and command[2] == 'run', 'Unexpected collection command')
    items = command[3:]
    require(len(items) % 2 == 0, 'Malformed collection command options')
    opts = {}
    for name,value in zip(items[::2], items[1::2]):
        require(name.startswith('--') and name not in opts, 'Duplicate/malformed collection option')
        opts[name] = value
    return opts


def check_preparation_boundary(prepared, declared_utc):
    require(prepared.get('status')=='complete','Preparation status is not complete')
    started,finished=stamp(prepared['started_utc']),stamp(prepared['finished_utc'])
    require(started<=finished<=stamp(declared_utc),
            'Preparation finishes after declaration or has inconsistent timestamps')
    for side in SIDES:
        build=prepared['variants'][side]['build']
        require(build.get('exit_code')==0 and build.get('timed_out') is False,
                'Preparation build failed or timed out: '+side)
        require(started<=stamp(build['started_utc'])<=stamp(build['completed_utc'])<=finished,
                'Build/preparation timestamps inconsistent: '+side)


def check_runner_identity(repo, declaration):
    if 'runner_sha256' not in declaration and 'runner_path' not in declaration:
        return None
    require('runner_sha256' in declaration and 'runner_path' in declaration,
            'Optional runner path and digest must be supplied together')
    path=repo/safe_relative(declaration['runner_path'])
    require(sha(path.read_bytes())==declaration['runner_sha256'],
            'Block runner differs from frozen declaration')
    return {'path':declaration['runner_path'],'sha256':declaration['runner_sha256']}


def check_pack_boundary(status, evidence):
    require(stamp(status['completed_utc'])<=stamp(evidence['saved_utc'])<=stamp(status['packed_utc']),
            'Compact archive saved_utc falls outside collection-completed/packed interval')


def check_solver_request_argument(command, raw_directory, session_root):
    require(len(command)==2,'Solver command must contain executable and request path')
    raw_dir=session_path(raw_directory,session_root)
    request=session_path(command[1],session_root)
    require(request==raw_dir/'request.json','Solver request argument differs from its raw directory')
    return raw_dir


def check_preparations(args, declaration, analyzer):
    result, manifests = {}, {}
    expected_pairs = {'norm':('baseline','candidate'), 'aa':('baseline','baseline')}
    for c in COHORTS:
        directory = args.prepared/('prepared-'+c)
        require(sha((directory/'prepared.json').read_bytes()) == declaration['prepared_sha256'][c],
                'Frozen preparation hash differs: '+c)
        prepared, verified = analyzer.audit_prepared(directory, args.repo)
        check_preparation_boundary(prepared,declaration['declared_utc'])
        require(prepared['dart']['sha256'] == declaration['sdk_sha256'] == SDK_SHA,
                'Pinned compiler identity differs')
        require(prepared['dart']['version'] == declaration['sdk_version'], 'Compiler version differs')
        for side, endpoint_name in zip(SIDES, expected_pairs[c]):
            actual = verified['variants'][side]
            expected = declaration['endpoints'][endpoint_name]
            for field in ('source_commit','library_tree','test_tree','source_archive_sha256','executable_sha256'):
                require(actual[field] == expected[field], 'Endpoint provenance differs: '+c+'/'+side+'/'+field)
            require(actual['executable_bytes_present_and_verified'], 'Actual executable bytes missing')
            require(actual['pubspec_lock_sha256'] == declaration['lock_sha256'] == LOCK_SHA,
                    'Canonical dependency lock differs')
        result[c], manifests[c] = verified, prepared
    norm_before = manifests['norm']['variants']['before']
    for side in SIDES:
        aa_side = manifests['aa']['variants'][side]
        require(aa_side['executable_sha256'] == norm_before['executable_sha256'], 'A/A does not reuse exact baseline executable')
        require(aa_side['source_archive_sha256'] == norm_before['source_archive_sha256'], 'A/A does not reuse exact baseline source archive')
    before, after = (declaration['endpoints'][n]['source_commit'] for n in ('baseline','candidate'))
    changed = git(args.repo, 'diff', '--name-only', before, after, '--', 'lib').decode().splitlines()
    require(changed == ['lib/src/geometry/numeric.dart'], 'Candidate production-file scope differs')
    patch = git(args.repo, 'diff', '--binary', before, after, '--', 'lib')
    require(sha(patch) == declaration['production_diff_sha256'], 'Frozen production diff differs')
    return manifests, result


def metadata_run(directory, preparation, declaration, recovery, name, cohort, number,
                 status=None, status_sha=None, qualification=False, expected_requests=None):
    require(expected_requests is not None,'Frozen exact fixture requests are required')
    m = read(directory/'manifest.json')
    fixtures = QUALIFICATION if qualification else FIXTURES
    samples, warmups = (2,1) if qualification else (21,8)
    expected = {'status':'complete','purpose':'qualification' if qualification else 'measurement',
        'rounds':1,'start_round':number-1,'samples':samples,'warmups':warmups,
        'timeout_seconds':30,'pinned_cpu':declaration['cpu'],
        'fixture_ids':list(fixtures),'engines':list(ENGINES),'modes':list(MODES),
        'variants':list(SIDES),'suites':'smoke,confirm,coupled',
        'protocol_ok':True,'qualification_passed':True,'preparation':preparation,
        'prepared_manifest_sha256':declaration['prepared_sha256'][cohort],
        'harness_sha256':preparation['harness_sha256'],
        'platform':recovery['platform'],'cpu_model':recovery['cpu_model'],
        'allowed_cpus':recovery['affinity'],
        'thread_environment':{k:'1' for k in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','RAYON_NUM_THREADS')}}
    for field,value in expected.items():
        require(m.get(field) == value, name+': declared '+field+' differs')
    start,end = stamp(m['started_utc']),stamp(m['finished_utc'])
    require(stamp(recovery['observed_utc']) <= start < end <= stamp(m['analysis_finished_utc']),
            name+': collection time precedes frozen session or is inconsistent')
    expected_keys = set(itertools.product(fixtures,ENGINES,MODES,SIDES))
    index = {(r['variant'],r['job']):r for r in m['jobs']}
    require(len(index) == len(m['jobs']) == len(expected_keys), name+': manifest job population differs')
    require({p.name for p in directory.iterdir() if p.is_dir() and p.name in SIDES} == set(SIDES),
            name+': paired lane missing')
    recorded_out = None
    recorded_prepared = None
    if status is not None:
        se = {'name':name,'cohort':cohort,'round':number,
            'environment_cohort':declaration['timing_cohort'], 'session_id':declaration['session_id'],
            'declaration_sha256':status_sha['declaration'], 'recovery_sha256':status_sha['recovery'],
            'state':'ready_for_remote_checkpoint','passed':True,'exit_code':0,'pack_exit_code':0,
            'groups':len(expected_keys)//2,'measured_operations':len(expected_keys)*samples,
            'compact_evidence':True}
        for field,value in se.items():require(status.get(field)==value,name+': saved '+field+' differs')
        opts = command_options(status['command'])
        wanted = {'--purpose':'measurement','--variants':'before,after',
            '--suites':'smoke,confirm,coupled','--fixtures':','.join(fixtures),
            '--engines':','.join(ENGINES),'--modes':','.join(MODES),
            '--rounds':'1','--start-round':str(number-1),'--warmups':'8','--samples':'21',
            '--timeout':'30','--cpu':str(declaration['cpu'])}
        for field,value in wanted.items():
            # The frozen collector defaults to both variants when omitted.
            require(opts.get(field, 'before,after' if field=='--variants' else None)==value,
                    name+': command '+field+' differs')
        require(set(opts) <= set(wanted)|{'--prepared','--out'},name+': unexpected collection option')
        session_path(status['command'][1],declaration['session_root'])
        recorded_out = session_path(opts['--out'],declaration['session_root'])
        recorded_prepared = session_path(opts['--prepared'],declaration['session_root'])
        require(recorded_out.parts[-2:] == ('runs',name),name+': wrong original output path')
        require(recorded_prepared.name == 'prepared-'+cohort,name+': wrong original preparation path')
        require(stamp(declaration['declared_utc']) <= stamp(status['started_utc']) <= start
                and stamp(m['analysis_finished_utc']) <= stamp(status['completed_utc']) <= stamp(status['packed_utc']),
                name+': status/packing timestamps inconsistent')
    seen, intervals, sequence = set(),[],[]
    for side in SIDES:
        for path in sorted((directory/side).glob('*/job.json')):
            job = read(path)
            identity = (job['fixture_id'],job['engine'],job['mode'],side)
            require(identity in expected_keys and identity not in seen,name+': duplicate/unexpected job')
            seen.add(identity)
            require(job['round']==number and job['variant']==side and job['timeout_seconds']==30
                    and job['timed_out'] is False and job['returncode']==0 and job['parse_errors']==[],
                    name+': job protocol failed')
            summary=job['summary']
            feasible=identity[0]!='contradictory_distance'
            for field,value in {'complete':True,'expected_samples':samples,
                    'completed_samples':samples,'accepted_samples':samples if feasible else 0,
                    'expected_records':samples+warmups,'completed_records':samples+warmups,
                    'known_feasible':feasible}.items():
                require(summary.get(field)==value,name+': incorrect job '+field)
            request_path=path.parent/'request.json'
            request_data=(request_path.read_bytes() if request_path.exists() else
                          gzip.decompress(request_path.with_suffix('.json.gz').read_bytes()))
            expected_request=expected_requests[(*identity[:3],samples,warmups)]
            require(json.dumps(parse(request_data),sort_keys=True,separators=(',',':'))==expected_request,
                    name+': request geometry/edits/tolerance differ from frozen corpus')
            raw_dir=check_solver_request_argument(job['command'],job['raw_directory'],declaration['session_root'])
            exe=session_path(job['command'][0],declaration['session_root'])
            require(exe.parts[-3:]==('prepared-'+cohort,side,'dart-adapter'),name+': wrong solver executable path')
            if recorded_prepared is not None:
                require(exe==recorded_prepared/side/'dart-adapter',name+': job uses another preparation directory')
            require(job['command_sha256']==sha(json.dumps(job['command']).encode()),
                    name+': job command digest differs')
            if recorded_out is not None:
                require(raw_dir==recorded_out/side/path.parent.name,name+': wrong original job directory')
            js,je=stamp(job['started_utc']),stamp(job['completed_utc'])
            require(start<=js<je<=end,name+': job outside block time interval')
            declared=index.pop((side,path.parent.name))
            require(declared['summary']==summary and stamp(declared['started_utc'])==js
                    and stamp(declared['completed_utc'])==je,name+': embedded job disagrees')
            intervals.append((js,je,name+'/'+side+'/'+path.parent.name));sequence.append((js,identity))
    require(seen==expected_keys and not index,name+': missing declared jobs')
    schedule=[]
    for fi,fixture in enumerate(fixtures):
        for mi,mode in enumerate(MODES):
            for ei,engine in enumerate(ENGINES):
                sides=SIDES[::-1] if (number-1+fi+mi+ei)%2 else SIDES
                schedule.extend((fixture,engine,mode,s) for s in sides)
    require([v for _,v in sorted(sequence)]==schedule,name+': process schedule differs')
    nonoverlap(intervals,'Solver')
    return m,intervals


def audit_qualification(directory, preparation, declaration, recovery, analyzer, oracle, expected_requests):
    manifest,intervals=metadata_run(directory,preparation,declaration,recovery,
        'qualification','norm',1,qualification=True,expected_requests=expected_requests)
    pairs=collections.defaultdict(dict);counts=collections.Counter()
    for side in SIDES:
        lane=read(directory/side/'manifest.json')
        for field in ('source_commit','library_tree','test_tree'):
            require(lane[field]==preparation['variants'][side]['source'][field],'Qualification lane provenance differs')
        for path in (directory/side).glob('*/job.json'):
            job=read(path);parent=path.parent
            request_bytes=analyzer.read_maybe_gzip(parent/'request.json')
            require(sha(request_bytes)==job['request_sha256'],'Qualification request hash differs')
            request=analyzer.read_json(request_bytes)
            require(request['samples']==2 and request['warmups']==1,'Qualification request operation counts differ')
            identity=(job['fixture_id'],job['engine'],job['mode'])
            require((request['fixture']['id'],request['engine'],request['mode'])==identity,'Qualification request identity differs')
            raw=[analyzer.read_json(line) for line in analyzer.read_maybe_gzip(parent/'stdout.jsonl').splitlines()]
            metadata=[r for r in raw if r.get('record')=='metadata']
            require(metadata==job['metadata'],'Qualification metadata differs')
            raw=[r for r in raw if r.get('record')!='metadata']
            checked=[analyzer.read_json(line) for line in analyzer.read_maybe_gzip(parent/'checked.jsonl').splitlines()]
            require([r['index'] for r in raw]==[-1,0,1] and len(checked)==3,'Qualification raw population differs')
            for r,c in zip(raw,checked):
                verdict=oracle.check(request,r)
                require(analyzer.canonical(c)==analyzer.canonical(dict(r,oracle=verdict)), 'Qualification raw/oracle differs')
                require(key(r)==identity and r['warmup']==(r['index']<0),'Qualification raw identity differs')
                require(verdict['accepted']==request['fixture']['expected_feasible']
                        and r['accepted']==verdict['accepted'] and not r.get('adapter_error'),
                        'Qualification physical result differs')
                for field in analyzer.TIMES:
                    require(type(r[field]) in (int,float) and math.isfinite(r[field]) and r[field]>=0,
                            'Invalid qualification timing field')
                require(r['elapsed_ns']+10>=r['build_ns']+r['solve_ns'],
                        'Overlapping qualification timer intervals')
                counts['raw_records']+=1
                counts['accepted' if verdict['accepted'] else 'expected_rejections']+=1
            pairs[identity][side]={'request':request,'raw':raw}
            counts['processes']+=1
    for identity,pair in pairs.items():
        require(set(pair)==set(SIDES),'Qualification pair incomplete')
        require(analyzer.canonical(pair['before']['request'])==analyzer.canonical(pair['after']['request']), 'Qualification paired requests differ')
        for b,a in zip(pair['before']['raw'],pair['after']['raw']):
            bn={k:v for k,v in b.items() if k not in analyzer.TIMES};an={k:v for k,v in a.items() if k not in analyzer.TIMES}
            require(analyzer.canonical(bn)==analyzer.canonical(an),'Qualification non-timing pair differs')
            counts['exact_non_time_pairs']+=1
    require(dict(counts)=={'raw_records':216,'accepted':192,'processes':72,
                          'expected_rejections':24,'exact_non_time_pairs':108}, 'Qualification total population differs')
    return {'passed':True,'counts':dict(counts),'manifest_sha256':sha((directory/'manifest.json').read_bytes()),
            'finished_utc':manifest['analysis_finished_utc']},intervals


def audit_transport(saved,directory,name,out,transport,status):
    path=saved/(name+'-evidence.json')
    evidence=read(path)
    check_pack_boundary(status,evidence)
    result=transport.restore(path,out/'restored'/name)
    expected=set(evidence['files'])
    actual={p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file()}
    require(actual==expected,name+': archive/raw file population differs')
    for relative,entry in evidence['files'].items():
        data=(directory/relative).read_bytes()
        require(len(data)==entry['bytes'] and sha(data)==entry['sha256'],name+': raw artifact hash differs')
        require((out/'restored'/name/relative).read_bytes()==data,name+': restored artifact differs')
    require((directory/'comparison.json').read_bytes()==(saved/(name+'-summary.json')).read_bytes(),
            name+': saved summary differs')
    return {'manifest_sha256':sha(path.read_bytes()),'archive_sha256':evidence['archive_sha256'],
            'files':len(expected),'restore':result}


def check_validation(path,declaration,repo,first_measurement):
    if path is None:
        return {'passed':False,'status':'not_supplied','missing':[list(v) for v in sorted(VALIDATION_GATES)]}
    data=read(path)
    require(data.get('schema')=='dart-csp-norm-validation-v1','Unknown validation-index schema')
    observed={};artifacts=[]
    for record in data['records']:
        identity=(record['endpoint'],record['gate'])
        require(identity in VALIDATION_GATES and identity not in observed,'Unexpected/duplicate validation record')
        expected=declaration['endpoints'][identity[0]]
        require(record['passed'] is True,'Validation gate not passing: '+str(identity))
        require(record.get('exit_code',0)==0 and not record.get('timed_out',False),'Validation execution failed')
        require(record['library_tree']==expected['library_tree'] and record['test_tree']==expected['test_tree'],
                'Validation source trees differ: '+str(identity))
        for field,suffix in (('library_tree',':lib'),('test_tree',':test')):
            require(git(repo,'rev-parse',record['source_commit']+suffix).decode().strip()==record[field],
                    'Validation Git source binding differs')
        require(stamp(record['completed_utc']) <= first_measurement,
                'Validation gate finished after measurement started: '+str(identity))
        require(record['artifacts'],'Validation record has no preserved evidence')
        for item in record['artifacts']:
            artifact=path.parent/safe_relative(item['path'])
            require(sha(artifact.read_bytes())==item['sha256'],'Validation evidence hash differs')
            artifacts.append({'gate':list(identity),'path':item['path'],'sha256':item['sha256']})
        observed[identity]=record
    missing=VALIDATION_GATES-set(observed)
    return {'passed':not missing,'status':'complete' if not missing else 'missing_gates',
            'index_sha256':sha(path.read_bytes()),'missing':[list(v) for v in sorted(missing)],
            'artifacts':artifacts,
            'interpretation':'Verified source-bound passing records and evidence hashes; this auditor does not execute tests.'}


def markdown(report):
    text=['# CG residual-norm experiment audit','',
        f"Raw/protocol audit passed: **{report.get('evidence_passed',False)}**. "
        f"Overall decision: **{report.get('overall_decision','blocked_invalid_or_incomplete_evidence')}**.",'',
        'All timings belong to the declared new session. Process pairs receive equal weight. '
        'Median paired ratios and ratios of median process p50s are separate descriptions. '
        'A/A is diagnostic; it is never subtracted. No statistical significance is claimed.','']
    if report.get('decision'):
        text+=['## Predeclared performance gates','','| Gate | Pass | Criterion |','| --- | --- | --- |']
        for g in report['decision']['gates']:text.append(f"| {g['name']} | {g['passed']} | {g['criterion']} |")
    for name,cohort in report.get('cohorts',{}).items():
        text += ['',f'## {name}','','| Fixture | Engine | Mode | Before / after median process p50, ms | Median paired p50 change | Ratio of median p50 change | Round p50 changes | Median paired p95 change | Before-first / after-first p50 changes |','| --- | --- | --- | ---: | ---: | ---: | --- | ---: | --- |']
        def pct(value):return 'n/a' if value is None else f'{100*(value-1):+.2f}%'
        for row in cohort['groups']:
            p=row['timing']['elapsed_ns']['p50_ms'];q=row['timing']['elapsed_ns']['p95_ms']
            text.append('| '+' | '.join([row['fixture_id'],row['engine'],row['mode'],
                f"{p['before_median_process_statistic']:.6f} / {p['after_median_process_statistic']:.6f}",
                pct(p['median_paired_ratio']),pct(p['ratio_of_median_process_statistics']),
                ', '.join(pct(v) for v in p['round_ratios']),pct(q['median_paired_ratio']),
                pct(p['order_strata']['before_first']['median_paired_ratio'])+' / '+pct(p['order_strata']['after_first']['median_paired_ratio'])])+' |')
    if report.get('errors'):text+=['','## Errors','',*('- '+e for e in report['errors'])]
    return '\n'.join(text)+'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,default=Path.cwd())
    parser.add_argument('--prepared',type=Path,required=True,help='Parent of prepared-norm and prepared-aa')
    parser.add_argument('--runs',type=Path,required=True)
    parser.add_argument('--saved',type=Path,required=True,help='Statuses, compact archive parts, recovery.json')
    parser.add_argument('--declaration',type=Path,required=True)
    parser.add_argument('--qualification',type=Path,required=True)
    parser.add_argument('--validation-index',type=Path)
    parser.add_argument('--out',type=Path,required=True,help='New, nonexistent directory')
    args=parser.parse_args()
    args.repo=args.repo.resolve()
    args.out.mkdir(parents=True,exist_ok=False)
    report={'schema_version':1,'evidence_passed':False,'decision':None,'cohorts':{},'errors':[],
        'script_sha256':sha(Path(__file__).read_bytes()),'rules':DECISION_RULES,
        'overall_decision':'blocked_invalid_or_incomplete_evidence'}
    try:
        declaration=read(args.declaration)
        require(declaration['schema']==SCHEMA,'Wrong declaration schema')
        require(declaration['auditor_sha256']==report['script_sha256'],
                'Auditor differs from the version frozen before collection')
        require(declaration['protocol']==PROTOCOL and declaration['decision_rules']==DECISION_RULES,
                'Declared protocol/decision rules differ from adopted fixed rules')
        require(declaration['session_id'] and PurePosixPath(declaration['session_root']).parts[:4]==
                ('/','workspace','scratch',declaration['session_id']),'Session root does not match identity')
        require(type(declaration['cpu']) is int and declaration['cpu']>=0,'Invalid CPU')
        require(declaration['timing_cohort'] != '2026-11-14-optimization-final','Old experiment must not be relabeled')
        recovery_path=args.saved/'recovery.json';recovery=read(recovery_path)
        declaration_sha=sha(args.declaration.read_bytes());recovery_sha=sha(recovery_path.read_bytes())
        for field in ('session_id','timing_cohort'):
            require(recovery[field]==declaration[field],'Recovery session/cohort differs')
        require(recovery['declaration_sha256']==declaration_sha,'Recovery declaration binding differs')
        require(stamp(declaration['declared_utc'])<=stamp(recovery['observed_utc']),'Recovery predates declaration')
        require(declaration['cpu'] in recovery['affinity'],'Pinned CPU outside declared affinity')
        for name,path in SCRIPT_PATHS.items():
            require(sha((args.repo/path).read_bytes())==declaration['script_sha256'][name],
                    'Frozen audit/harness script differs: '+name)
        report['runner_identity']=check_runner_identity(args.repo,declaration)
        analyzer=module('norm_raw_analyzer',args.repo/SCRIPT_PATHS['raw_analyzer'])
        oracle=module('norm_physical_oracle',args.repo/SCRIPT_PATHS['oracle'])
        transport=module('norm_exact_transport',args.repo/SCRIPT_PATHS['packer'])
        fixtures=module('norm_frozen_fixtures',args.repo/SCRIPT_PATHS['fixtures'])
        cases={}
        for suite in ('smoke','confirm','coupled'):
            for case in fixtures.corpus(suite):
                fid=case['fixture']['id']
                require(fid not in cases or cases[fid]==case,'Conflicting frozen corpus fixture')
                cases[fid]=case
        expected_requests={}
        for fid in set(FIXTURES)|set(QUALIFICATION):
            for engine,mode in itertools.product(ENGINES,MODES):
                for samples,warmups in ((21,8),(2,1)):
                    value=fixtures.request(cases[fid],engine,mode,warmups,samples)
                    expected_requests[(fid,engine,mode,samples,warmups)]=analyzer.canonical(value)
        preparations,provenance=check_preparations(args,declaration,analyzer)
        qualification,q_intervals=audit_qualification(args.qualification,preparations['norm'],
            declaration,recovery,analyzer,oracle,expected_requests)
        report.update(declaration_sha256=declaration_sha,recovery_sha256=recovery_sha,
            session_id=declaration['session_id'],timing_cohort=declaration['timing_cohort'],
            qualification=qualification,preparation_audit=provenance)
        observed={p.name for p in args.runs.iterdir() if p.is_dir()}
        require(observed==set(BLOCKS),'Measurement block population differs; qualification belongs outside runs/')
        all_intervals=[];block_intervals=[];raw_by_cohort=collections.defaultdict(list)
        artifacts={};counts=collections.Counter();environment=set()
        for name in BLOCKS:
            cohort,number=name.split('-round');number=int(number)
            directory=args.runs/name;status=read(args.saved/(name+'-status.json'))
            manifest,intervals=metadata_run(directory,preparations[cohort],declaration,recovery,
                name,cohort,number,status,{'declaration':declaration_sha,'recovery':recovery_sha},
                expected_requests=expected_requests)
            require(stamp(qualification['finished_utc'])<=stamp(status['started_utc']),
                    'Qualification overlaps/precedes incomplete timing preparation')
            artifact=audit_transport(args.saved,directory,name,args.out,transport,status)
            raw=analyzer.audit_run(directory,number,preparations[cohort],provenance[cohort],oracle)
            require(not raw['non_time_mismatches'],name+': non-timing pairs differ')
            for field,value in {'jobs':32,'measured_operations':672,'warmup_operations':256,
                'raw_records':928,'accepted_operations':928,'process_percentiles_verified':64,
                'paired_non_time_operations_compared':464}.items():
                require(raw['counts'].get(field)==value,name+': fixed raw population differs: '+field)
            all_intervals.extend(intervals)
            block_intervals.append((stamp(status['started_utc']),stamp(status['packed_utc']),name))
            environment.add(raw['environment_sha256']);counts.update(raw['counts'])
            raw_by_cohort[cohort].append(raw);artifacts[name]=artifact
            print(json.dumps({'block':name,'passed':True,'counts':raw['counts']}),flush=True)
        ordered=nonoverlap(block_intervals,'Collection and packing')
        require([v[2] for v in ordered]==list(BLOCKS),'Global block schedule differs')
        nonoverlap(all_intervals,'Global solver')
        require(len(environment)==1,'Refusing to aggregate different recorded runtime environments')
        require(counts['jobs']==256 and counts['measured_operations']==5376 and counts['warmup_operations']==2048,
                'Complete protocol count mismatch')
        decision_input={}
        for cohort,runs in raw_by_cohort.items():
            rows=[row for run in runs for row in run['rows']]
            grouped=collections.defaultdict(list)
            for row in rows:
                grouped[key(row)].append({'round':row['round'],'first':row['first'],
                    'p50_ratio':row['after_over_before']['elapsed_ns']['p50_ms'],
                    'p95_ratio':row['after_over_before']['elapsed_ns']['p95_ms']})
            decision_input[cohort]=dict(grouped)
            report['cohorts'][cohort]={'rounds':runs,'groups':analyzer.aggregate(rows)}
        decision=decide(decision_input['norm'],decision_input['aa'])
        report.update(evidence_passed=True,counts=dict(counts),transport=artifacts,
            decision=decision,full_declared_same_session_protocol=True)
        try:
            validation=check_validation(args.validation_index,declaration,args.repo,ordered[0][0])
        except Exception as error:
            validation={'passed':False,'status':'invalid_or_failing',
                        'error':type(error).__name__+': '+str(error)}
            report['errors'].append(validation['error'])
        report.update(correctness_validation=validation,
            overall_decision=('revert' if not decision['passed'] else
                              'retain' if validation['passed'] else 'blocked_missing_correctness_evidence'))
    except Exception as error:
        report['errors'].append(type(error).__name__+': '+str(error))
    finally:
        (args.out/'audit.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        (args.out/'audit.md').write_text(markdown(report))
    print(json.dumps({k:report.get(k) for k in ('evidence_passed','overall_decision','counts','errors')}),flush=True)
    # Reversion is a valid completed experiment, not an audit execution failure.
    return 0 if report['evidence_passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())

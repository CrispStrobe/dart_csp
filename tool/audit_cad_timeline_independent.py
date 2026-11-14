"""Independently reconcile saved CAD Chrome traces; never runs Dart workloads.

Uses per-thread event reconstruction and an endpoint-sweep coverage integral,
not the collector's parser or sorted-interval merge. All findings are saved,
including unmatched event identities and the limits of temporal GC overlap.
"""

import argparse
import bisect
import collections
import datetime
import gzip
import hashlib
import io
import json
import math
import pathlib
import random
import subprocess
import sys
import urllib.parse


CASES = {
    'cad_linkage': (
        'cold_build_solve_solids_meshes', 'retained_angle_edit',
        'selective_coupler_length_edit', 'placement_only_layer_edit',
        'downstream_rejected_angle_edit'),
    'cad_instances': ('cold_build_solve_regenerate', 'solved_pose_edit'),
}
DEPENDENCIES = {
    'cad_linkage': ('benchmark/cad_linkage.dart',
                    'example/parametric_linkage.dart',
                    'example/nonlinear_linkage.dart'),
    'cad_instances': ('benchmark/cad_instances.dart',
                      'example/parametric_assembly.dart'),
}
LIMITS = [
    'This audits a separate instrumented cohort, not normal latency results.',
    'GC and compiler overlap is temporal coincidence, not causal delay, '
    'allocated bytes, CPU sampling, or measured stop-the-world pause time.',
    'Operation markers enclose the Stopwatch; overlaps can include adjacent '
    'marker overhead outside the exact Stopwatch interval.',
    'Only completed B/E and X spans contribute to overlap. Unmatched raw '
    'events are preserved explicitly and cannot establish complete intervals.',
    'Any-thread GC includes other threads in the same process. It does not '
    'establish that the operation thread was paused or delayed.',
    'A complete GC span on the operation thread is counted even when nested '
    'inside other GC spans; endpoint union prevents double counting.',
    'Library content is checked against committed Git blobs. Harness, '
    'collector and package-configuration checks use the supplied source tree '
    'and recorded process paths; these files must remain available for replay.',
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def raw(text):
    return text.encode('utf-8', 'surrogateescape')


def load_json(data):
    def invalid_constant(value):
        raise ValueError('Non-finite JSON token: ' + value)
    return json.loads(data, parse_constant=invalid_constant)


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


class Checks:
    def __init__(self):
        self.count = 0
        self.findings = []

    def check(self, condition, context, detail=None):
        self.count += 1
        if not condition:
            finding = {'context': context}
            if detail is not None:
                finding['detail'] = detail
            self.findings.append(finding)
        return bool(condition)

    def equal(self, actual, expected, context):
        return self.check(actual == expected, context,
                          {'actual': actual, 'expected': expected})


class Coverage:
    """Exact union integral from signed endpoint events, including nesting."""

    def __init__(self, intervals):
        changes = collections.defaultdict(int)
        for begin, end in intervals:
            if not finite_number(begin) or not finite_number(end) or end < begin:
                raise ValueError('Invalid coverage interval')
            if end == begin:
                continue
            changes[begin] += 1
            changes[end] -= 1
        self.starts, self.ends, self.prefix = [], [], []
        active, opened, area = 0, None, 0
        for point in sorted(changes):
            previous = active
            active += changes[point]
            if active < 0:
                raise ValueError('Unbalanced endpoint sweep')
            if previous == 0 and active > 0:
                opened = point
            elif previous > 0 and active == 0:
                self.starts.append(opened)
                self.ends.append(point)
                self.prefix.append(area)
                area += point - opened
        if active != 0:
            raise ValueError('Unterminated endpoint sweep')
        self.total = area

    def until(self, point):
        index = bisect.bisect_right(self.starts, point) - 1
        if index < 0:
            return 0
        return self.prefix[index] + min(point, self.ends[index]) - self.starts[index]

    def inside(self, begin, end):
        return self.until(end) - self.until(begin)


def reconstruct(events):
    """Group native event order by thread, then pair each thread separately."""
    by_thread = collections.defaultdict(list)
    spans, unpaired = [], []
    for number, event in enumerate(events):
        if not isinstance(event, dict):
            raise ValueError('Trace event is not an object')
        if event.get('ph') in ('B', 'E', 'X'):
            if not finite_number(event.get('ts')):
                raise ValueError('Non-finite or absent timestamp')
            by_thread[(event.get('pid'), event.get('tid'))].append((number, event))
    for (pid, tid), sequence in by_thread.items():
        opened = []
        for number, event in sequence:
            phase = event['ph']
            if phase == 'B':
                opened.append((number, event))
                continue
            if phase == 'E':
                if not opened:
                    unpaired.append({'event_index': number, 'role': 'end',
                                     'event': event})
                    continue
                first_number, first = opened.pop()
                if (first.get('name'), first.get('cat')) != (
                        event.get('name'), event.get('cat')):
                    raise ValueError(f'Mismatched B/E events {first_number}/{number}')
                start, end = first['ts'], event['ts']
            else:
                first_number, first = number, event
                if not finite_number(event.get('dur')) or event['dur'] < 0:
                    raise ValueError(f'Invalid complete-span duration at {number}')
                start, end = event['ts'], event['ts'] + event['dur']
            if end < start:
                raise ValueError(f'Negative B/E duration at {first_number}/{number}')
            spans.append({'name': first.get('name'), 'category': first.get('cat'),
                          'pid': pid, 'tid': tid, 'start_us': start, 'end_us': end,
                          'arguments': first.get('args', {}),
                          'begin_event': first_number, 'end_event': number})
        unpaired.extend({'event_index': number, 'role': 'begin', 'event': event}
                        for number, event in opened)
    return spans, sorted(unpaired, key=lambda item: item['event_index'])


def median(values):
    ordered = sorted(values)
    count = len(ordered)
    return (ordered[count // 2] if count % 2 else
            (ordered[count // 2 - 1] + ordered[count // 2]) / 2)


def p95(values):
    return sorted(values)[(len(values) * 95 + 99) // 100 - 1]


def inspect_trace(run, samples, warmups, checks, context):
    events = load_json(run['trace_utf8'])
    checks.check(isinstance(events, list), context + ': raw event array')
    spans, unmatched = reconstruct(events)
    analysis, result = run['analysis'], run['result']
    benchmark = run['benchmark']
    expected_cases = CASES[benchmark]
    if benchmark == 'cad_linkage':
        distributions = result['measurements']
        declared = (result['measured_iterations'], result['warmup_iterations'])
        independent = result.get('independent_physical_reuse_rollback_checks')
    else:
        distributions = {case: result[case] for case in expected_cases}
        declared = (result['measured_pairs'], result['warmup_pairs'])
        independent = result.get('coordinate_volume_reuse_checks')
        checks.equal(result.get('check_only'), False, context + ': normal operation mode')
    checks.equal(set(distributions), set(expected_cases), context + ': all expected cases')
    checks.equal(declared, (samples, warmups), context + ': declared sample/warmup counts')
    checks.equal(independent, 'passed', context + ': independent harness checks')
    checks.equal(result.get('units'), 'microseconds', context + ': stopwatch units')
    checks.equal(result.get('operations_per_batch'), 1, context + ': complete single operations')
    checks.equal(result.get('operation_tracing_enabled'), True, context + ': tracing enabled')

    checks.equal(analysis['trace_events'], len(events), context + ': trace event count')
    checks.equal(analysis['completed_spans'], len(spans), context + ': completed span count')
    checks.equal(analysis['phase_counts'], dict(collections.Counter(
        event.get('ph') for event in events)), context + ': all event phases retained')
    checks.equal(analysis['category_counts'], dict(collections.Counter(
        event.get('cat', '') for event in events)), context + ': all event categories retained')
    for role in ('begin', 'end'):
        indexes = [item['event_index'] for item in unmatched if item['role'] == role]
        checks.equal(sorted(analysis['unmatched_' + role + '_events']), indexes,
                     context + ': unmatched ' + role + ' events')
    unmatched_gc = [item['event_index'] for item in unmatched if item['event'].get('cat') == 'GC']
    checks.equal(sorted(analysis['unmatched_gc_events']), unmatched_gc,
                 context + ': unmatched GC spans retained')
    checks.check(not any(str(item['event'].get('name', '')).startswith('cad_operation/')
                         for item in unmatched), context + ': operation markers complete')

    interval_sets = collections.defaultdict(list)
    for span in spans:
        category = span['category']
        if category not in ('GC', 'Compiler'):
            continue
        interval = (span['start_us'], span['end_us'])
        interval_sets[(category, span['pid'], span['tid'])].append(interval)
        if category == 'GC':
            interval_sets[(category, span['pid'], '*')].append(interval)
    coverage = {key: Coverage(intervals) for key, intervals in interval_sets.items()}
    empty = Coverage([])
    operations = sorted((dict(span) for span in spans
                         if str(span['name']).startswith('cad_operation/')),
                        key=lambda span: (span['start_us'], span['begin_event']))
    recorded = analysis['operation_spans']
    checks.equal(len(operations), (samples + warmups) * len(expected_cases),
                 context + ': operation marker count')
    checks.equal(len(recorded), len(operations), context + ': published operation count')
    by_case = collections.defaultdict(list)
    previous_end = {}
    for number, operation in enumerate(operations):
        label = context + f': operation {number}'
        case = operation['arguments'].get('case')
        iteration = operation['arguments'].get('iteration')
        if not checks.check(case in expected_cases and type(iteration) is int and
                            -warmups <= iteration < samples, label + ' identity'):
            continue
        checks.equal(operation['name'], 'cad_operation/' + case, label + ' name')
        checks.equal(operation['category'], 'Dart', label + ' category')
        begin, end = operation['start_us'], operation['end_us']
        thread = (operation['pid'], operation['tid'])
        checks.check(begin >= previous_end.get(thread, begin), label + ' nonoverlap')
        previous_end[thread] = end
        operation.update(case=case, iteration=iteration, duration_us=end-begin)
        for field, key in [
                ('same_thread_gc_overlap_us', ('GC', *thread)),
                ('any_thread_gc_overlap_us', ('GC', thread[0], '*')),
                ('same_thread_compiler_overlap_us', ('Compiler', *thread))]:
            amount = coverage.get(key, empty).inside(begin, end)
            checks.check(0 <= amount <= end-begin, label + ' ' + field + ' bounds')
            operation[field] = amount
        checks.check(operation['same_thread_gc_overlap_us'] <=
                     operation['any_thread_gc_overlap_us'], label + ' GC inclusion')
        if iteration >= 0:
            value = distributions[case]['samples_us'][iteration]
            checks.check(finite_number(value) and value >= 0, label + ' finite Stopwatch sample')
            checks.check(value <= end - begin + 1, label + ' Stopwatch enclosed by marker')
            operation['stopwatch_us'] = value
        if number < len(recorded):
            checks.equal(operation, recorded[number], label + ' exact independent reconstruction')
        by_case[case].append(operation)

    summaries, any_thread_summary = {}, {}
    for case in expected_cases:
        label = context + ': ' + case
        series = by_case[case]
        checks.equal([op['iteration'] for op in series], list(range(-warmups, samples)),
                     label + ' sample/marker alignment')
        distribution = distributions[case]
        values = distribution['samples_us']
        checks.equal(len(values), samples, label + ' raw sample count')
        checks.equal(len(distribution['work_per_sample']), samples,
                     label + ' aligned work-record count')
        checks.equal(distribution['p50'], sorted(values)[len(values) // 2],
                     label + ' harness upper-middle p50')
        checks.equal(distribution['p95'], p95(values), label + ' harness nearest-rank p95')
        measured = [op for op in series if op['iteration'] >= 0]
        has_gc = [op['stopwatch_us'] for op in measured if op['same_thread_gc_overlap_us'] > 0]
        no_gc = [op['stopwatch_us'] for op in measured if op['same_thread_gc_overlap_us'] == 0]
        tail_threshold = p95(values)
        tail = [op for op in measured if op['stopwatch_us'] >= tail_threshold]
        summaries[case] = {
            'samples': len(measured),
            'operations_with_same_thread_gc': len(has_gc),
            'operations_with_same_thread_compiler': sum(op['same_thread_compiler_overlap_us'] > 0 for op in measured),
            'same_thread_gc_overlap_sum_us': sum(op['same_thread_gc_overlap_us'] for op in measured),
            'same_thread_compiler_overlap_sum_us': sum(op['same_thread_compiler_overlap_us'] for op in measured),
            'instrumented_stopwatch_p50_us': median(values),
            'instrumented_stopwatch_p95_us': tail_threshold,
            'instrumented_with_gc_p50_us': median(has_gc) if has_gc else None,
            'instrumented_without_gc_p50_us': median(no_gc) if no_gc else None,
            'at_or_above_p95_count': len(tail),
            'at_or_above_p95_with_same_thread_gc': sum(op['same_thread_gc_overlap_us'] > 0 for op in tail),
        }
        any_thread_summary[case] = {
            'operations_with_any_thread_gc': sum(op['any_thread_gc_overlap_us'] > 0 for op in measured),
            'any_thread_gc_overlap_sum_us': sum(op['any_thread_gc_overlap_us'] for op in measured),
            'at_or_above_p95_with_any_thread_gc': sum(op['any_thread_gc_overlap_us'] > 0 for op in tail),
        }
    checks.equal(analysis['cases'], summaries, context + ': all independently computed case summaries')
    checks.equal(analysis['completed_gc_span_names'], dict(collections.Counter(
        span['name'] for span in spans if span['category'] == 'GC')),
        context + ': completed GC phase counts')
    return {
        'trace_events': len(events), 'completed_spans': len(spans),
        'operation_markers': len(operations), 'measured_operations': samples * len(expected_cases),
        'warmup_operations': warmups * len(expected_cases),
        'aligned_work_records': samples * len(expected_cases),
        'unmatched_events': unmatched,
        'unmatched_gc_event_count': len(unmatched_gc),
        'phase_counts': dict(collections.Counter(event.get('ph') for event in events)),
        'recomputed_cases': summaries,
        'additional_any_thread_summary': any_thread_summary,
    }


def git_bytes(repository, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=repository)


def committed_manifest(repository, commit):
    listing = git_bytes(repository, 'ls-tree', '-r', '-z', commit, '--', 'lib')
    objects = []
    for item in listing.split(b'\0'):
        if item:
            metadata, path = item.split(b'\t', 1)
            _mode, kind, oid = metadata.split()
            if kind != b'blob':
                raise ValueError('Library entry is not a Git blob')
            objects.append((path.decode(), oid.decode()))
    response = subprocess.run(['git', 'cat-file', '--batch'], cwd=repository,
                              input=''.join(oid + '\n' for _, oid in objects).encode(),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    stream, manifest = io.BytesIO(response), {}
    for path, expected_oid in objects:
        oid, kind, size = stream.readline().decode().strip().split()
        if oid != expected_oid or kind != 'blob':
            raise ValueError('Unexpected Git batch response')
        content = stream.read(int(size))
        if stream.read(1) != b'\n':
            raise ValueError('Truncated Git batch response')
        manifest[path] = sha(content)
    return manifest


def inspect_provenance(data, repository, harness_root, collector, checks):
    checks.equal(sha(raw(data['wrapper_template'])), data['wrapper_sha256'], 'wrapper template hash')
    checks.equal(sha(collector.read_bytes()), data['collector_sha256'], 'collector source hash')
    lock_hash = sha(raw(data['dependency_lock_utf8']))
    revisions = data['revisions']
    checks.equal(set(revisions), {'before', 'after'}, 'source revision labels')
    source_summaries = {}
    for label, revision in revisions.items():
        checks.equal(revision['dependency_lock_sha256'], lock_hash, label + ' dependency-lock bytes/hash')
        checks.equal(revision['library_diff_sha256'], None, label + ' committed clean library declaration')
        tree = git_bytes(repository, 'rev-parse', revision['commit'] + ':lib').decode().strip()
        checks.equal(revision['library_tree'], tree, label + ' committed library tree identity')
        manifest = committed_manifest(repository, revision['commit'])
        checks.equal(revision['library_file_sha256'], manifest,
                     label + ' every source hash matches recorded committed library')
        source_summaries[label] = {'commit': revision['commit'], 'library_tree': tree,
                                   'library_files': len(manifest)}
    for benchmark, hashes in data['harnesses'].items():
        checks.equal(set(hashes), set(DEPENDENCIES[benchmark]), benchmark + ' full direct example harness dependency inventory')
        for relative, expected in hashes.items():
            checks.equal(sha((harness_root / relative).read_bytes()), expected,
                         'harness source hash: ' + relative)

    records = data['process_records']
    for index, record in enumerate(records):
        for field in ('stdout', 'stderr'):
            checks.equal(sha(raw(record[field])), record[field + '_sha256'],
                         f'process {index}: lossless {field} hash')
        checks.equal(record['exit_code'], 0, f'process {index}: successful exit')
        checks.equal(record['timed_out'], False, f'process {index}: no timeout')
        checks.check(finite_number(record['elapsed_seconds']) and record['elapsed_seconds'] >= 0,
                     f'process {index}: elapsed metadata')
        started = datetime.datetime.fromisoformat(record['started_at_utc'])
        finished = datetime.datetime.fromisoformat(record['finished_at_utc'])
        checks.check(started <= finished, f'process {index}: timestamp order')
        if index:
            previous_finished = datetime.datetime.fromisoformat(records[index - 1]['finished_at_utc'])
            checks.check(started >= previous_finished, f'process {index}: sequential processes')
    checks.equal(records[0]['command'][1:], ['--version'], 'recorded SDK query command')
    sdk = records[0]['command'][0]
    checks.check('Dart SDK version:' in records[0]['stdout'] + records[0]['stderr'], 'recorded SDK version output')
    binaries, wrappers, roots = {}, {}, {}
    compile_count = 2 * len(data['harnesses'])
    for record in records[1:1 + compile_count]:
        command = record['command']
        checks.equal(command[:4], [sdk, 'compile', 'exe', '-Ddart_csp_profile=true'], 'instrumented AOT compile command prefix')
        checks.equal(len(command), 8, 'instrumented AOT compile command arity')
        checks.equal(command[-2], '-o', 'instrumented AOT executable output flag')
        wrapper = pathlib.Path(command[-3])
        label, benchmark = wrapper.stem.split('-', 1)
        checks.check(label in revisions and benchmark in data['harnesses'], 'compiled wrapper identity')
        root = pathlib.Path(record['cwd'])
        checks.equal(command[4], '--packages=' + str(root / '.dart_tool/package_config.json'), 'AOT package-config argument')
        previous = roots.setdefault(label, root)
        checks.equal(root, previous, label + ' consistent source working directory')
        wrappers[(label, benchmark)] = str(wrapper)
        binaries[(label, benchmark)] = command[-1]
    for label, root in roots.items():
        config_path = root / '.dart_tool/package_config.json'
        configuration = config_path.read_bytes()
        checks.equal(sha(configuration), revisions[label]['package_config_sha256'], label + ' exact package config')
        own = [package for package in load_json(configuration)['packages'] if package['name'] == 'dart_csp']
        checks.equal(len(own), 1, label + ' single dart_csp package entry')
        root_uri = urllib.parse.urljoin(config_path.as_uri(), own[0]['rootUri'])
        actual_root = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(root_uri).path)).resolve()
        checks.equal(str(actual_root), str(root.resolve()), label + ' package resolves to recorded source root')
        checks.equal(own[0].get('packageUri'), 'lib/', label + ' package library directory')
        checks.equal(sha((root / 'pubspec.lock').read_bytes()), lock_hash, label + ' on-disk lock contents')
        for benchmark, hashes in data['harnesses'].items():
            for relative, expected in hashes.items():
                checks.equal(sha((root / relative).read_bytes()), expected, label + ' actual harness dependency: ' + relative)
    return source_summaries, sdk, wrappers, binaries, roots


def self_check():
    rng = random.Random(20261114)
    for _ in range(300):
        intervals = [tuple(sorted((rng.randrange(-20, 21), rng.randrange(-20, 21))))
                     for _ in range(rng.randrange(30))]
        coverage = Coverage(intervals)
        for begin, end in [(-20, 20), (-7, 4), (0, 1), (3, 3)]:
            oracle = sum(any(left <= coordinate < right for left, right in intervals)
                         for coordinate in range(begin, end))
            assert coverage.inside(begin, end) == oracle
    fixture = [
        {'ph': 'B', 'name': 'op', 'cat': 'Dart', 'pid': 1, 'tid': 1, 'ts': 0},
        {'ph': 'B', 'name': 'gc', 'cat': 'GC', 'pid': 1, 'tid': 1, 'ts': 2},
        {'ph': 'X', 'name': 'nested', 'cat': 'GC', 'pid': 1, 'tid': 1, 'ts': 3, 'dur': 1},
        {'ph': 'X', 'name': 'worker', 'cat': 'GC', 'pid': 1, 'tid': 2, 'ts': 1, 'dur': 3},
        {'ph': 'E', 'name': 'gc', 'cat': 'GC', 'pid': 1, 'tid': 1, 'ts': 6},
        {'ph': 'E', 'name': 'op', 'cat': 'Dart', 'pid': 1, 'tid': 1, 'ts': 10},
        {'ph': 'E', 'name': 'unpaired-end', 'cat': 'GC', 'pid': 1, 'tid': 2, 'ts': 10},
        {'ph': 'B', 'name': 'unpaired-begin', 'cat': 'Compiler', 'pid': 1, 'tid': 1, 'ts': 12},
        {'ph': 'C', 'name': 'counter', 'pid': 1, 'tid': 1, 'ts': 5},
        {'ph': 'M', 'name': 'thread_name', 'pid': 1, 'tid': 1},
    ]
    spans, unpaired = reconstruct(fixture)
    assert len(spans) == 4
    assert [(item['event_index'], item['role']) for item in unpaired] == [(6, 'end'), (7, 'begin')]
    own = Coverage((span['start_us'], span['end_us']) for span in spans
                   if span['category'] == 'GC' and span['tid'] == 1)
    all_threads = Coverage((span['start_us'], span['end_us']) for span in spans if span['category'] == 'GC')
    assert own.inside(0, 10) == 4 and all_threads.inside(0, 10) == 5
    for malformed in [
            [{'ph': 'X', 'name': 'bad', 'ts': 0, 'dur': -1}],
            [{'ph': 'B', 'name': 'a', 'ts': 0}, {'ph': 'E', 'name': 'b', 'ts': 1}],
            [{'ph': 'B', 'name': 'a', 'ts': 2}, {'ph': 'E', 'name': 'a', 'ts': 1}]]:
        try:
            reconstruct(malformed)
        except ValueError:
            pass
        else:
            raise AssertionError('Malformed span was not rejected')
    return {'endpoint_sweep_integer_grid_sets': 300,
            'window_checks_per_set': 4, 'mixed_phase_fixture': 'passed',
            'malformed_span_rejections': 3}


def audit(args):
    original = args.input.read_bytes()
    document = gzip.decompress(original) if args.input.suffix == '.gz' else original
    data = load_json(document)
    checks = Checks()
    output = {'schema': 'dart-csp-independent-timeline-audit-v1',
              'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'input': str(args.input.resolve()), 'input_sha256': sha(original),
              'uncompressed_json_sha256': sha(document),
              'auditor_sha256': sha(pathlib.Path(__file__).read_bytes()),
              'method': 'Independent per-thread B/E/X reconstruction and endpoint-sweep coverage integral; collector code is never imported.',
              'limitations': LIMITS, 'synthetic_self_checks': self_check(),
              'runs': []}
    checks.equal(data['schema'], 'dart-csp-operation-timeline-v1', 'collector schema')
    samples, warmups, rounds = data['samples'], data['warmups'], data['rounds']
    checks.check(type(samples) is int and samples > 0 and type(warmups) is int and warmups >= 0
                 and type(rounds) is int and rounds > 0, 'positive sampling metadata')
    try:
        sources, sdk, wrappers, binaries, roots = inspect_provenance(
            data, args.repository, args.harness_root, args.collector, checks)
        output['source_provenance'] = sources
    except Exception as error:
        checks.check(False, 'provenance could not be completed', repr(error))
        sdk, wrappers, binaries, roots = None, {}, {}, {}
    expected_order = [
        (mode, round_number, benchmark, label)
        for mode in ('jit', 'aot')
        for round_number in range(1, rounds + 1)
        for benchmark in data['harnesses']
        for label in (('before', 'after') if round_number % 2 else ('after', 'before'))]
    actual_order = [(run['mode'], run['round'], run['benchmark'], run['revision']) for run in data['runs']]
    checks.equal(actual_order, expected_order, 'complete alternating paired run order')
    compile_count = 2 * len(data['harnesses'])
    checks.equal(len(data['process_records']), 1 + compile_count + len(expected_order),
                 'SDK, AOT compilation, and run process counts')
    paired = {}
    for index, run in enumerate(data['runs']):
        identity = actual_order[index]
        context = '/'.join(map(str, identity))
        report = {'identity': list(identity), 'findings_before': len(checks.findings)}
        output['runs'].append(report)
        try:
            checks.equal(run['status'], 'passed', context + ': collector completion')
            checks.equal(run['process_record'], 1 + compile_count + index,
                         context + ': unique sequential process record')
            process = data['process_records'][run['process_record']]
            checks.equal(sha(raw(run['trace_utf8'])), run['trace_sha256'], context + ': lossless trace hash')
            checks.equal(load_json(process['stdout']), run['result'], context + ': result matches original process stdout')
            flags = [f'--samples={samples}', f'--warmups={warmups}']
            checks.equal(run['arguments'], flags, context + ': declared command arguments')
            command = process['command']
            mode, round_number, benchmark, label = identity
            if roots:
                root = roots[label]
                trace_path = command[-3]
                expected = ([sdk, '-Ddart_csp_profile=true', '--packages=' + str(root / '.dart_tool/package_config.json'),
                             wrappers[label, benchmark]] if mode == 'jit' else [binaries[label, benchmark]]) + [trace_path, *flags]
                checks.equal(command, expected, context + ': exact JIT/AOT launch without extra VM flags')
                checks.equal(process['cwd'], str(root), context + ': correct source working directory')
                checks.equal(pathlib.Path(trace_path).name,
                             f'{mode}-{round_number}-{benchmark}-{label}.json', context + ': unique trace output path')
            report.update(inspect_trace(run, samples, warmups, checks, context))
            result = run['result']
            cases = result['measurements'] if benchmark == 'cad_linkage' else {case: result[case] for case in CASES[benchmark]}
            paired[(mode, round_number, benchmark, label)] = {case: dist['work_per_sample'] for case, dist in cases.items()}
        except Exception as error:
            checks.check(False, context + ': reconstruction could not be completed', repr(error))
        report['finding_count'] = len(checks.findings) - report.pop('findings_before')
    work_pairs = []
    for mode in ('jit', 'aot'):
        for round_number in range(1, rounds + 1):
            for benchmark in data['harnesses']:
                before = paired.get((mode, round_number, benchmark, 'before'))
                after = paired.get((mode, round_number, benchmark, 'after'))
                identical = before is not None and before == after
                work_pairs.append({'mode': mode, 'round': round_number, 'benchmark': benchmark,
                                   'aligned_work_records_identical': identical})
                checks.check(identical, f'{mode}/{round_number}/{benchmark}: paired physical work identity')
    output['paired_work_checks'] = work_pairs
    output['counts'] = {key: sum(run.get(key, 0) for run in output['runs']) for key in (
        'trace_events', 'completed_spans', 'operation_markers', 'measured_operations',
        'warmup_operations', 'aligned_work_records', 'unmatched_gc_event_count')}
    output['counts'].update(runs=len(data['runs']), process_records=len(data['process_records']))
    output['checks'] = checks.count
    output['findings'] = checks.findings
    output['status'] = 'passed' if not checks.findings else 'failed'
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--repository', type=pathlib.Path, required=True)
    parser.add_argument('--harness-root', type=pathlib.Path)
    parser.add_argument('--collector', type=pathlib.Path)
    args = parser.parse_args()
    args.repository = args.repository.resolve()
    args.harness_root = (args.harness_root or args.repository).resolve()
    args.collector = (args.collector or args.repository / 'tool/profile_cad_phases.py').resolve()
    try:
        report = audit(args)
    except Exception as error:
        report = {'schema': 'dart-csp-independent-timeline-audit-v1', 'status': 'failed',
                  'input': str(args.input), 'fatal_error': repr(error), 'limitations': LIMITS}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True, default=str,
                                      allow_nan=False) + '\n')
    print(json.dumps({key: report[key] for key in ('status', 'checks', 'counts', 'findings', 'fatal_error') if key in report}, default=str))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())

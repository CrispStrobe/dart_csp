"""Separate offline Chrome timeline capture for complete CAD operations.

Requires a native Dart SDK >=3.11 for NativeRuntime.streamTimelineTo. Normal
benchmark builds do not enable dart_csp_profile; no VM-service socket is used.
All trace events and process outputs are retained. Interval overlap describes
instrumented execution, not allocated bytes, CPU samples, or normal latency.
"""

import argparse
import collections
import datetime
import gzip
import hashlib
import json
import os
import pathlib
import platform
import statistics
import subprocess
import tempfile
import time
import urllib.parse


WRAPPER = '''// @dart=3.11
import 'dart:developer';
import HARNESS as harness;
void main(List<String> arguments) {
  NativeRuntime.streamTimelineTo(TimelineRecorder.chrome,
      path: arguments.first,
      streams: [TimelineStream.dart, TimelineStream.gc, TimelineStream.compiler]);
  try {
    harness.main(arguments.sublist(1));
  } finally {
    NativeRuntime.stopStreamingTimeline();
  }
}
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()


def process(command, cwd, timeout=180):
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    clock = time.monotonic()
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True,
                                   timeout=timeout, check=False)
        stdout, stderr = completed.stdout, completed.stderr
        exit_code, timed_out = completed.returncode, False
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        exit_code, timed_out = None, True
    return dict(command=[str(x) for x in command], cwd=str(cwd),
                started_at_utc=started,
                finished_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                elapsed_seconds=time.monotonic() - clock,
                exit_code=exit_code, timed_out=timed_out,
                stdout=stdout.decode('utf-8', errors='surrogateescape'),
                stderr=stderr.decode('utf-8', errors='surrogateescape'),
                output_encoding='UTF-8 with surrogateescape; hashes cover original bytes',
                stdout_sha256=digest(stdout), stderr_sha256=digest(stderr))


def save(path, data):
    encoded = (json.dumps(data, indent=2, allow_nan=False) + '\n').encode()
    if path.suffix == '.gz':
        encoded = gzip.compress(encoded, mtime=0)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(encoded)
    temporary.replace(path)


def union_duration(intervals):
    """Duration of a union, so nested/concurrent spans are not double-counted."""
    total = 0
    end = None
    for start, stop in sorted(intervals):
        if stop <= start:
            continue
        total += max(0, stop - max(start, end if end is not None else start))
        end = stop if end is None else max(end, stop)
    return total


def analyze_trace(events, result, samples, warmups):
    if 'measurements' in result:
        count_fields = 'measured_iterations', 'warmup_iterations'
        check_field = 'independent_physical_reuse_rollback_checks'
    else:
        count_fields = 'measured_pairs', 'warmup_pairs'
        check_field = 'coordinate_volume_reuse_checks'
    if (result.get(count_fields[0]) != samples or
            result.get(count_fields[1]) != warmups or result.get(check_field) != 'passed'):
        raise ValueError('Harness sampling metadata or independent checks failed')
    stacks = collections.defaultdict(list)
    spans, unmatched_ends, mismatches = [], [], []
    for number, event in enumerate(events):
        phase = event.get('ph')
        key = event.get('pid'), event.get('tid')
        if phase == 'B':
            stacks[key].append((number, event))
        elif phase == 'E':
            if not stacks[key]:
                unmatched_ends.append(number)
                continue
            begin_number, begin = stacks[key].pop()
            if (begin.get('name'), begin.get('cat')) != (event.get('name'), event.get('cat')):
                mismatches.append([begin_number, number])
                continue
            if event['ts'] < begin['ts']:
                raise ValueError('Negative timeline duration')
            spans.append(dict(name=begin.get('name'), category=begin.get('cat'),
                              pid=key[0], tid=key[1], start_us=begin['ts'],
                              end_us=event['ts'], arguments=begin.get('args', {}),
                              begin_event=begin_number, end_event=number))
        elif phase == 'X':
            if event['dur'] < 0:
                raise ValueError('Negative complete timeline duration')
            spans.append(dict(name=event.get('name'), category=event.get('cat'),
                              pid=key[0], tid=key[1], start_us=event['ts'],
                              end_us=event['ts'] + event['dur'],
                              arguments=event.get('args', {}), begin_event=number,
                              end_event=number))
    unmatched_begins = [number for stack in stacks.values() for number, _ in stack]
    if mismatches:
        raise ValueError(f'Mismatched timeline nesting: {mismatches[:5]}')
    unpaired = unmatched_ends + unmatched_begins
    if any(events[i].get('name', '').startswith('cad_operation/') for i in unpaired):
        raise ValueError('An operation marker is not paired')
    operations = sorted((s for s in spans if s['name'].startswith('cad_operation/')),
                        key=lambda s: s['start_us'])
    expected = result.get('measurements') or {
        name: result[name] for name in ('cold_build_solve_regenerate', 'solved_pose_edit')}
    by_case = collections.defaultdict(list)
    gc = [s for s in spans if s['category'] == 'GC']
    compiler = [s for s in spans if s['category'] == 'Compiler']
    for operation in operations:
        args = operation['arguments']
        case, iteration = args['case'], args['iteration']
        if type(iteration) is not int or case not in expected:
            raise ValueError('Unexpected operation identity')
        start, end = operation['start_us'], operation['end_us']
        def overlap(candidates, same_thread):
            selected = [s for s in candidates if s['pid'] == operation['pid'] and
                        (not same_thread or s['tid'] == operation['tid']) and
                        s['start_us'] < end and s['end_us'] > start]
            return union_duration((max(start, s['start_us']), min(end, s['end_us']))
                                  for s in selected)
        operation.update(case=case, iteration=iteration, duration_us=end-start,
                         same_thread_gc_overlap_us=overlap(gc, True),
                         any_thread_gc_overlap_us=overlap(gc, False),
                         same_thread_compiler_overlap_us=overlap(compiler, True))
        for field in ('same_thread_gc_overlap_us', 'any_thread_gc_overlap_us',
                      'same_thread_compiler_overlap_us'):
            if not 0 <= operation[field] <= end-start:
                raise ValueError('Invalid interval-union duration')
        if iteration >= 0:
            operation['stopwatch_us'] = expected[case]['samples_us'][iteration]
        by_case[case].append(operation)
    for case, distribution in expected.items():
        actual = by_case[case]
        if [s['iteration'] for s in actual] != list(range(-warmups, samples)):
            raise ValueError(f'Missing, reordered or duplicate operation markers: {case}')
        if (len(distribution['samples_us']) != samples or
                len(distribution.get('work_per_sample', [])) != samples):
            raise ValueError(f'Wrong or unaligned harness sample count: {case}')
    def percentile(values, p):
        import math
        return sorted(values)[math.ceil(len(values) * p) - 1]
    cases = {}
    for case, operations_for_case in by_case.items():
        measured = [s for s in operations_for_case if s['iteration'] >= 0]
        with_gc = [s for s in measured if s['same_thread_gc_overlap_us'] > 0]
        without_gc = [s for s in measured if s['same_thread_gc_overlap_us'] == 0]
        tail_cutoff = percentile([s['stopwatch_us'] for s in measured], .95)
        tail = [s for s in measured if s['stopwatch_us'] >= tail_cutoff]
        cases[case] = dict(
            samples=len(measured), operations_with_same_thread_gc=len(with_gc),
            operations_with_same_thread_compiler=sum(s['same_thread_compiler_overlap_us'] > 0 for s in measured),
            same_thread_gc_overlap_sum_us=sum(s['same_thread_gc_overlap_us'] for s in measured),
            same_thread_compiler_overlap_sum_us=sum(s['same_thread_compiler_overlap_us'] for s in measured),
            instrumented_stopwatch_p50_us=statistics.median(s['stopwatch_us'] for s in measured),
            instrumented_stopwatch_p95_us=tail_cutoff,
            instrumented_with_gc_p50_us=statistics.median(s['stopwatch_us'] for s in with_gc) if with_gc else None,
            instrumented_without_gc_p50_us=statistics.median(s['stopwatch_us'] for s in without_gc) if without_gc else None,
            at_or_above_p95_count=len(tail),
            at_or_above_p95_with_same_thread_gc=sum(s['same_thread_gc_overlap_us'] > 0 for s in tail))
    return dict(trace_events=len(events), completed_spans=len(spans),
                phase_counts=dict(collections.Counter(e.get('ph') for e in events)),
                category_counts=dict(collections.Counter(e.get('cat', '') for e in events)),
                unmatched_begin_events=unmatched_begins, unmatched_end_events=unmatched_ends,
                unmatched_gc_events=[i for i in unpaired if events[i].get('cat') == 'GC'],
                operation_spans=operations, cases=cases,
                completed_gc_span_names=dict(collections.Counter(s['name'] for s in gc)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=pathlib.Path, required=True)
    parser.add_argument('--after', type=pathlib.Path, required=True)
    parser.add_argument('--dart', type=pathlib.Path, required=True)
    parser.add_argument('--benchmarks', nargs='+', choices=['cad_linkage', 'cad_instances'],
                        default=['cad_linkage', 'cad_instances'])
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--samples', type=int, default=300)
    parser.add_argument('--warmups', type=int, default=30)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.rounds < 1 or args.samples < 1 or args.warmups < 0:
        parser.error('Use positive rounds/samples and nonnegative warmups')
    roots = {'before': args.before.resolve(), 'after': args.after.resolve()}
    dart = str(args.dart.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    data = dict(schema='dart-csp-operation-timeline-v1',
                scope='Separate instrumented cohort. Markers enclose complete operations and sit outside Stopwatch boundaries; overlap can include immediately adjacent marker overhead. GC/compiler interval unions describe temporal overlap of completed spans, not allocated bytes, CPU samples, causal delay, or normal uninstrumented latency. Unmatched spans are retained but excluded from overlap. Warmups, checks and setup remain in full traces but outside measured operation summaries. No VM-service socket or GC tuning is used.',
                platform=platform.platform(), rounds=args.rounds, samples=args.samples,
                warmups=args.warmups, order='Sequential, before/after reversed in alternate rounds',
                wrapper_template=WRAPPER, wrapper_sha256=digest(WRAPPER.encode()),
                collector_sha256=digest(pathlib.Path(__file__).read_bytes()),
                revisions={}, harnesses={}, process_records=[], runs=[])
    sdk = process([dart, '--version'], args.before)
    data['process_records'].append(sdk)
    if sdk['exit_code'] != 0:
        save(args.output, data)
        raise ValueError('SDK version command failed')
    for label, root in roots.items():
        diff = git(root, 'diff', '--binary', 'HEAD', '--', 'lib')
        if diff or git(root, 'ls-files', '--others', '--exclude-standard', '--', 'lib'):
            raise ValueError(f'Library must be clean and committed: {root}')
        package_config = root/'.dart_tool/package_config.json'
        packages = json.loads(package_config.read_text())['packages']
        own = [p for p in packages if p['name'] == 'dart_csp']
        if len(own) != 1:
            raise ValueError('Package configuration does not identify dart_csp')
        uri = urllib.parse.urljoin(package_config.as_uri(), own[0]['rootUri'])
        configured_root = pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
        if configured_root.resolve() != root:
            raise ValueError('Package configuration points at another source tree')
        data['revisions'][label] = dict(commit=git(root, 'rev-parse', 'HEAD'),
            library_tree=git(root, 'rev-parse', 'HEAD:lib'),
            library_diff_sha256=digest(diff.encode()) if diff else None,
            package_config_sha256=digest(package_config.read_bytes()),
            dependency_lock_sha256=digest((root/'pubspec.lock').read_bytes()),
            library_file_sha256={path: digest((root/path).read_bytes()) for path in
                                git(root, 'ls-files', '--', 'lib').splitlines()})
    if len({r['dependency_lock_sha256'] for r in data['revisions'].values()}) != 1:
        raise ValueError('Dependency locks differ')
    data['dependency_lock_utf8'] = (roots['before']/'pubspec.lock').read_text()
    for name in args.benchmarks:
        files = [f'benchmark/{name}.dart'] + (
            ['example/parametric_linkage.dart', 'example/nonlinear_linkage.dart'] if name == 'cad_linkage'
            else ['example/parametric_assembly.dart'])
        hashes = {}
        for name_relative in files:
            values = [digest((r/name_relative).read_bytes()) for r in roots.values()]
            if values[0] != values[1]:
                raise ValueError(f'Harness dependency differs: {name_relative}')
            hashes[name_relative] = values[0]
        data['harnesses'][name] = hashes
    save(args.output, data)
    with tempfile.TemporaryDirectory(prefix='cad-phase-trace-') as directory:
        scratch = pathlib.Path(directory)
        wrappers, binaries = {}, {}
        for label, root in roots.items():
            for name in args.benchmarks:
                wrapper = scratch/f'{label}-{name}.dart'
                wrapper.write_text(WRAPPER.replace('HARNESS', json.dumps((root/f'benchmark/{name}.dart').as_uri())))
                binary = scratch/f'{label}-{name}'
                wrappers[label, name], binaries[label, name] = wrapper, binary
                compiled = process([dart, 'compile', 'exe', '-Ddart_csp_profile=true',
                    '--packages='+str(root/'.dart_tool/package_config.json'), str(wrapper), '-o', str(binary)], root)
                data['process_records'].append(compiled)
                save(args.output, data)
                if compiled['exit_code'] != 0:
                    raise RuntimeError(compiled['stderr'] + compiled['stdout'])
        for mode in ['jit', 'aot']:
            for round_index in range(1, args.rounds+1):
                for name in args.benchmarks:
                    for label in (['before', 'after'] if round_index % 2 else ['after', 'before']):
                        root = roots[label]
                        trace = scratch/f'{mode}-{round_index}-{name}-{label}.json'
                        flags = [f'--samples={args.samples}', f'--warmups={args.warmups}']
                        command = ([dart, '-Ddart_csp_profile=true',
                            '--packages='+str(root/'.dart_tool/package_config.json'), str(wrappers[label, name])]
                            if mode == 'jit' else [str(binaries[label, name])]) + [str(trace), *flags]
                        ran = process(command, root)
                        data['process_records'].append(ran)
                        entry = dict(mode=mode, round=round_index, benchmark=name, revision=label,
                                     process_record=len(data['process_records'])-1, arguments=flags)
                        data['runs'].append(entry)
                        try:
                            if trace.exists():
                                raw = trace.read_bytes()
                                entry['trace_utf8'] = raw.decode('utf-8', errors='surrogateescape')
                                entry['trace_sha256'] = digest(raw)
                            if ran['exit_code'] != 0:
                                raise RuntimeError('Instrumented operation process did not succeed')
                            entry['result'] = json.loads(ran['stdout'])
                            if 'trace_utf8' not in entry:
                                raise ValueError('Timeline file was not produced')
                            events = json.loads(entry['trace_utf8'])
                            entry['analysis'] = analyze_trace(events, entry['result'], args.samples, args.warmups)
                            entry['status'] = 'passed'
                        except Exception as error:
                            entry['status'], entry['error'] = 'failed', repr(error)
                            save(args.output, data)
                            raise
                        save(args.output, data)
                        print(f'{mode} round {round_index} {name} {label}: saved', flush=True)


if __name__ == '__main__':
    main()

"""Separate, lossless whole-process GC cohorts for paired CAD revisions.

This tool does not change the normal benchmark harness or attach GC events to
individual timed operations. It saves the instrumented harness output as well
as every stderr byte, including compiler/service-isolate diagnostics.
"""

import argparse
import collections
import datetime
import decimal
import gzip
import hashlib
import json
import os
import pathlib
import platform
import re
import subprocess
import tempfile
import time


_NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
_GC_ROW = re.compile(
    r"^\[\s*(?P<isolate>[^,\]|]+),\s*"
    r"(?P<space>[^(),]+)\(\s*(?P<reason>[^)]*)\),\s*"
    rf"(?P<sequence>\d+),\s*(?P<start>{_NUMBER}),\s*"
    rf"(?P<duration>{_NUMBER}),"
)


def parse_gc(stderr):
    """Summarize recognized main-isolate rows; retain unmatched row numbers."""
    main = []
    other = collections.Counter()
    unparsed = []
    durations = collections.defaultdict(list)
    for line_number, line in enumerate(stderr.splitlines(), 1):
        match = _GC_ROW.match(line)
        if match is None:
            # Headers use pipes, not commas. Never silently discard a new GC
            # row layout: report its location and retain the original stderr.
            if line.lstrip().startswith('[') and ',' in line and '|' not in line:
                unparsed.append(line_number)
            continue
        fields = {key: value.strip() for key, value in match.groupdict().items()}
        if fields['isolate'] != 'main':
            other[fields['isolate']] += 1
            continue
        duration = decimal.Decimal(fields['duration'])
        main.append({
            'stderr_line': line_number,
            'space': fields['space'],
            'reason': fields['reason'],
            'gc_number': int(fields['sequence']),
            'start_seconds': float(fields['start']),
            'reported_duration_ms': float(duration),
        })
        durations[fields['space'], fields['reason']].append(duration)
    flat_durations = [duration for group in durations.values() for duration in group]
    return {
        'main_isolate': {
            'event_count': len(main),
            'counts_by_space': dict(sorted(collections.Counter(
                row['space'] for row in main).items())),
            'counts_by_reason': dict(sorted(collections.Counter(
                row['reason'] for row in main).items())),
            'by_space_and_reason': [
                {'space': space, 'reason': reason, 'event_count': len(values),
                 'sum_reported_event_ms': float(sum(values)),
                 'max_reported_event_ms': float(max(values))}
                for (space, reason), values in sorted(durations.items())
            ],
            'sum_reported_event_ms': float(sum(flat_durations)),
            'max_reported_event_ms': float(max(flat_durations, default=0)),
            'rows': main,
        },
        'other_isolate_event_counts': dict(sorted(other.items())),
        'unparsed_gc_row_stderr_lines': unparsed,
    }


def _digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _process(command, cwd, timeout):
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True,
                                timeout=timeout, check=False)
        stdout, stderr = result.stdout, result.stderr
        exit_code, timed_out = result.returncode, False
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        exit_code, timed_out = None, True
    # No universal-newline conversion: these strings round-trip every original
    # byte with encode('utf-8', 'surrogateescape'), even for invalid UTF-8.
    return {
        'command': [str(part) for part in command],
        'cwd': str(cwd),
        'exit_code': exit_code,
        'timed_out': timed_out,
        'instrumented_process_wall_seconds': time.monotonic() - started,
        'stdout': stdout.decode('utf-8', 'surrogateescape'),
        'stderr': stderr.decode('utf-8', 'surrogateescape'),
        'stdout_sha256': hashlib.sha256(stdout).hexdigest(),
        'stderr_sha256': hashlib.sha256(stderr).hexdigest(),
    }


def _git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root).decode('utf-8').strip()


def _source(root):
    difference = subprocess.check_output(['git', 'diff', '--binary', 'HEAD', '--', 'lib'], cwd=root)
    files = subprocess.check_output(['git', 'ls-files', '-z', 'lib'], cwd=root).decode('utf-8').split('\0')
    lock = root / 'pubspec.lock'
    return {
        'root': str(root),
        'commit': _git(root, 'rev-parse', 'HEAD'),
        'committed_library_tree': _git(root, 'rev-parse', 'HEAD:lib'),
        'library_diff_sha256': hashlib.sha256(difference).hexdigest() if difference else None,
        'library_files_sha256': {path: _digest(root / path) for path in files if path},
        'pubspec_lock_sha256': _digest(lock),
        'pubspec_lock': lock.read_bytes().decode('utf-8', 'surrogateescape'),
    }


def _validate_harness(name, result, samples, warmups):
    if name == 'cad':
        measured, warmed = 'measured_pairs', 'warmup_pairs'
        flag = 'analytic_volume_and_mesh_checks'
        cases = [result.get(key, {}) for key in
                 ['cold_build_compile_regenerate', 'profile_edit_regenerate',
                  'thickness_edit_regenerate']]
    else:
        measured, warmed = 'measured_iterations', 'warmup_iterations'
        flag = 'independent_physical_reuse_rollback_checks'
        measurements = result.get('measurements', {})
        cases = [measurements.get(key, {}) for key in
                 ['cold_build_solve_solids_meshes', 'retained_angle_edit',
                  'selective_coupler_length_edit', 'placement_only_layer_edit',
                  'downstream_rejected_angle_edit']]
    if result.get(measured) != samples or result.get(warmed) != warmups:
        return 'Harness did not honor the requested sample/warmup counts'
    if result.get(flag) != 'passed':
        return 'Harness did not report successful independent checks'
    if any(len(case.get('samples_us', [])) != samples or
           len(case.get('work_per_sample', [])) != samples for case in cases):
        return 'Harness omitted raw samples or aligned work records'
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=pathlib.Path, required=True)
    parser.add_argument('--after', type=pathlib.Path, required=True)
    parser.add_argument('--dart', type=pathlib.Path, required=True)
    parser.add_argument('--benchmarks', nargs='+', choices=['cad', 'cad_linkage'],
                        default=['cad', 'cad_linkage'])
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--samples', type=int, default=300)
    parser.add_argument('--warmups', type=int, default=30)
    parser.add_argument('--run-timeout', type=int, default=180)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.rounds < 1 or args.samples < 1 or args.warmups < 0 or args.run_timeout < 1:
        parser.error('rounds/samples/timeout must be positive and warmups nonnegative')
    if len(set(args.benchmarks)) != len(args.benchmarks):
        parser.error('benchmarks must not repeat')
    roots = {'before': args.before.resolve(), 'after': args.after.resolve()}
    dart = args.dart.resolve()
    runtime = dart.with_name('dartaotruntime.exe' if dart.suffix == '.exe' else 'dartaotruntime')
    if not dart.is_file() or not runtime.is_file():
        parser.error('dart and its sibling dartaotruntime must both exist')
    result = {
        'schema': 'dart-csp-cad-whole-process-gc-v1',
        'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'complete': False,
        'platform': platform.platform(),
        'execution': 'Shared unpinned host; sequential fresh processes, alternating revision order.',
        'scope': (
            'Separate verbose-GC diagnostic cohort. Main-isolate summaries cover the whole '
            'process, including model setup, warmups, measured operations, independent '
            'checks and JSON serialization. Kernel/service-isolate output is preserved but '
            'excluded from main-isolate summaries. Reported event times are rounded VM '
            'diagnostics, may describe overlapping GC phases, and their sum is not total '
            'stop-the-world pause time. No GC-to-operation attribution or allocated-byte '
            'measurement is provided. Instrumented harness timings must not be substituted '
            'for the separate normal timing cohort. AOT compilation is outside run cohorts.'),
        'log_encoding': "Original bytes decoded as UTF-8 with surrogateescape; no newline conversion.",
        'rounds': args.rounds,
        'samples': args.samples,
        'warmups': args.warmups,
        'tool_sha256': _digest(pathlib.Path(__file__)),
        'environment': {key: os.environ.get(key) for key in
                        ['PUB_CACHE', 'TMPDIR', 'DART_DISABLE_ANALYTICS']},
        'dart_version': _process([str(dart), '--version'], roots['before'], args.run_timeout),
        'revisions': {label: _source(root) for label, root in roots.items()},
        'harnesses': {},
        'compilations': [],
        'runs': [],
    }
    if result['dart_version']['exit_code'] != 0:
        raise SystemExit('Cannot query Dart version')
    if result['revisions']['before']['pubspec_lock_sha256'] != result['revisions']['after']['pubspec_lock_sha256']:
        raise SystemExit('Dependency lockfiles differ')
    dependencies = {
        'cad': ['example/parametric_bracket.dart'],
        'cad_linkage': ['example/parametric_linkage.dart', 'example/nonlinear_linkage.dart'],
    }
    for name in args.benchmarks:
        paths = ['benchmark/' + name + '.dart', *dependencies[name]]
        hashes = {}
        for path in paths:
            before_hash, after_hash = [_digest(root / path) for root in roots.values()]
            if before_hash != after_hash:
                raise SystemExit('Harness/dependency differs: ' + path)
            hashes[path] = before_hash
        result['harnesses'][name] = hashes
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        payload = (json.dumps(result, indent=2, ensure_ascii=True) + '\n').encode('utf-8')
        if args.output.suffix == '.gz':
            payload = gzip.compress(payload, mtime=0)
        temporary = args.output.with_name(args.output.name + '.tmp')
        temporary.write_bytes(payload)
        temporary.replace(args.output)

    def require_success(record):
        if record['exit_code'] != 0:
            result['error'] = {'command': record['command'],
                               'exit_code': record['exit_code'],
                               'timed_out': record['timed_out']}
            save()
            raise SystemExit('Process failed; complete partial evidence saved to ' + str(args.output))

    save()
    with tempfile.TemporaryDirectory(prefix='cad-gc-cohort-') as directory:
        snapshots = {}
        for name in args.benchmarks:
            for label, root in roots.items():
                snapshot = str(pathlib.Path(directory) / (name + '-' + label + '.aot'))
                command = [str(dart), 'compile', 'aot-snapshot',
                           'benchmark/' + name + '.dart', '-o', snapshot]
                record = {'benchmark': name, 'revision': label,
                          **_process(command, root, args.run_timeout)}
                result['compilations'].append(record)
                save()
                require_success(record)
                snapshots[name, label] = snapshot
            print('compiled ' + name, flush=True)
        arguments = [f'--samples={args.samples}', f'--warmups={args.warmups}']
        for mode in ['jit', 'aot']:
            for repeat in range(args.rounds):
                labels = ['before', 'after'] if repeat % 2 == 0 else ['after', 'before']
                for name in args.benchmarks:
                    for label in labels:
                        command = ([str(dart), '--verbose_gc', 'benchmark/' + name + '.dart']
                                   if mode == 'jit' else
                                   [str(runtime), '--verbose_gc', snapshots[name, label]]) + arguments
                        record = {'mode': mode, 'round': repeat + 1,
                                  'benchmark': name, 'revision': label,
                                  **_process(command, roots[label], args.run_timeout)}
                        record['gc'] = parse_gc(record['stderr'])
                        result['runs'].append(record)
                        save()
                        require_success(record)
                        try:
                            record['result'] = json.loads(record['stdout'])
                        except json.JSONDecodeError as error:
                            result['error'] = {'invalid_harness_json': str(error),
                                               'command': command}
                            save()
                            raise SystemExit('Harness JSON could not be parsed; raw output saved') from error
                        problem = _validate_harness(name, record['result'], args.samples, args.warmups)
                        if problem:
                            result['error'] = {'invalid_harness_result': problem, 'command': command}
                            save()
                            raise SystemExit(problem + '; raw output saved')
                        save()
                        count = record['gc']['main_isolate']['event_count']
                        print(f'{mode} {repeat + 1} {name} {label}: {count} main-isolate events', flush=True)
    result['complete'] = True
    result['completed_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save()


if __name__ == '__main__':
    main()

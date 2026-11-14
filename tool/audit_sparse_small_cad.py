"""Independently audit the complete sparse-solver small-QR/CAD control cohort.

No project collector, summarizer, auditor, or Dart workload is imported/executed.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys


BENCHMARKS = ['geometry_small_qr', 'cad', 'cad_linkage']
SHAPES = [(5, 4), (8, 4), (4, 5), (4, 8), (9, 4), (12, 4),
          (16, 8), (16, 9), (17, 8), (48, 48)]
QR_CASES = [f'rank_{m}x{n}' for m, n in SHAPES] + [
    'damped_solve_8x4', 'nullspace_4x8']
PLATE_CASES = ['cold_build_compile_regenerate', 'profile_edit_regenerate',
               'thickness_edit_regenerate']
LINKAGE_CASES = ['cold_build_solve_solids_meshes', 'retained_angle_edit',
                 'selective_coupler_length_edit', 'placement_only_layer_edit',
                 'downstream_rejected_angle_edit']
PARTS = ['ground', 'crank', 'coupler', 'rocker']
MOVING = ['crank', 'coupler', 'rocker']
ALL_FEATURES = ['linkage'] + [f'{part}.{kind}' for part in PARTS
    for kind in ('profile', 'body', 'mesh')] + PARTS
COMMON_WORK = ['scheduled_features', 'dependency_edges_visited',
    'state_entries_copied', 'state_directory_entries_copied',
    'residual_evaluations', 'jacobian_evaluations', 'linear_solves',
    'linear_iterations', 'nonlinear_iterations', 'rank_factorizations',
    'rank_reuses']
GEOMETRY_WORK = ['residual_evaluations', 'jacobian_evaluations',
    'linear_solves', 'linear_iterations', 'nonlinear_iterations',
    'rank_factorizations', 'rank_reuses']
DEPENDENCIES = {'geometry_small_qr': [], 'cad': ['example/parametric_bracket.dart'],
    'cad_linkage': ['example/parametric_linkage.dart', 'example/nonlinear_linkage.dart']}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == '.gz' else data,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('summary', type=Path)
    parser.add_argument('--repo', type=Path, required=True,
        help='Git repository containing both measured source commits')
    parser.add_argument('--check-live', action='store_true',
        help='Also verify the original mapped lock/config/library files still exist unchanged')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw, summary = load(args.raw), load(args.summary)
    counts, findings = Counter(), []
    grouped = defaultdict(dict)

    def check(condition, context):
        counts['checks'] += 1
        if not condition:
            findings.append(context)

    def close(actual, expected):
        return actual == expected if actual is None or expected is None else \
            math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-10)

    def instant(value):
        return datetime.fromisoformat(value)

    def git(*arguments, data=None):
        return subprocess.run(['git', '-C', str(args.repo), *arguments], input=data,
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def source_blob_hashes(commit, paths):
        # Git returns the recorded commit's exact blobs, not current worktree data.
        query = ''.join(f'{commit}:{path}\n' for path in paths).encode()
        output = git('cat-file', '--batch', data=query)
        offset, hashes = 0, {}
        for path in paths:
            header_end = output.index(b'\n', offset)
            header = output[offset:header_end].decode().split()
            if len(header) != 3 or header[1] != 'blob':
                raise ValueError(f'Expected committed blob {commit}:{path}: {header}')
            size = int(header[2])
            offset = header_end + 1
            hashes[path] = digest(output[offset:offset + size])
            offset += size + 1
        check(offset == len(output), [commit, 'complete source blob stream'])
        return hashes

    check(raw['status'] == 'completed', 'completed cohort')
    check(raw['modes'] == ['jit', 'aot'] and raw['diagnostic_only'] is False,
          'both runtimes, not diagnostic')
    check(raw['rounds'] == 3, 'three complete paired rounds')
    check(list(raw['harnesses']) == BENCHMARKS, 'exact complete fixture inventory')
    check(list(raw['revisions']) == ['before', 'after'], 'exact revision inventory')
    check(raw['revisions']['before']['commit'] == '135a6eed93b46ad7d40d0f5288686d2cd26ddd48',
          'intended consolidated-main baseline')
    check(raw['revisions']['after']['library_tree'] == 'eb20b0ea6dc251142e6109f04bb7fe768d967db1',
          'intended retained sparse candidate source')
    check('Dart SDK version: 3.14.0 ' in raw['runtime'], 'intended Dart 3.14.0 compiler')
    check(raw['hardware']['cpu_affinity'] and
          len(raw['hardware']['cpu_affinity']) == 1, 'one inherited pinned CPU')
    check(summary['revisions'] == raw['revisions'], 'summary source identities')

    source_checks = {}
    for label, identity in raw['revisions'].items():
        commit = identity['commit']
        check(identity['library_diff_sha256'] is None, [label, 'committed clean source'])
        tree = git('rev-parse', commit + ':lib').decode().strip()
        check(tree == identity['library_tree'], [label, 'committed library tree'])
        entries = git('ls-tree', '-r', '-z', commit, '--', 'lib').split(b'\0')
        paths = [entry.split(b'\t', 1)[1].decode() for entry in entries if entry]
        source_hashes = source_blob_hashes(commit, paths)
        check(source_hashes == identity['library_file_sha256'],
              [label, 'all source blob hashes and exact library inventory'])
        counts['source_blobs_checked'] += len(paths)
        harness_paths = [raw['harnesses'][name]['file'] for name in BENCHMARKS]
        harness_paths += [path for name in BENCHMARKS for path in DEPENDENCIES[name]]
        actual_harnesses = source_blob_hashes(commit, harness_paths)
        for name in BENCHMARKS:
            declared = raw['harnesses'][name]
            check(declared['file'] == f'benchmark/{name}.dart',
                  [label, name, 'exact harness path'])
            check(actual_harnesses[declared['file']] == declared['sha256'],
                  [label, name, 'committed harness bytes'])
            expected_dependencies = {path: actual_harnesses[path]
                for path in DEPENDENCIES[name]}
            check(declared.get('dependency_sha256', {}) == expected_dependencies,
                  [label, name, 'complete harness dependency hashes'])
        mapping = identity['package_mapping']
        check(Path(mapping['resolved_library']) == Path(mapping['resolved_root']) / 'lib',
              [label, 'package library root'])
        if args.check_live:
            root, config = Path(mapping['resolved_root']), Path(mapping['file'])
            check(digest((root / 'pubspec.lock').read_bytes()) == identity['dependency_lock_sha256'],
                  [label, 'live dependency lock'])
            check(digest(config.read_bytes()) == identity['package_config_sha256'],
                  [label, 'live package config'])
            live_files = {str(path.relative_to(root)): digest(path.read_bytes())
                for path in sorted((root / 'lib').rglob('*')) if path.is_file()}
            check(live_files == source_hashes, [label, 'live exact source inventory and bytes'])
        source_checks[label] = {'commit': commit, 'library_tree': tree,
            'source_blob_count': len(paths), 'live_paths_checked': args.check_live}
    check(len({v['dependency_lock_sha256'] for v in raw['revisions'].values()}) == 1,
          'identical revision dependency locks')

    expected_sequence = [(mode, round_, name, revision)
        for mode in ['jit', 'aot'] for round_ in range(1, 4) for name in BENCHMARKS
        for revision in (('before', 'after') if round_ % 2 else ('after', 'before'))]
    actual_sequence = [tuple(run[k] for k in ('mode', 'round', 'benchmark', 'revision'))
        for run in raw['runs']]
    check(actual_sequence == expected_sequence, 'complete 36-report alternating order')

    records, compiled, seen_records = raw['process_records'], {}, set()
    previous_finish = None
    benchmark_records = set()
    versions = []
    for index, process in enumerate(records):
        counts['process_records'] += 1
        start, finish = (instant(process[key]) for key in ('started_at_utc', 'finished_at_utc'))
        check(finish >= start and (previous_finish is None or start >= previous_finish),
              [index, 'sequential nonnegative subprocess interval'])
        previous_finish = finish
        check(process['exit_code'] == 0 and process['timed_out'] is False,
              [index, 'successful non-timeout subprocess'])
        for stream in ('stdout', 'stderr'):
            check(digest(process[stream].encode('utf-8', 'surrogateescape')) == process[stream + '_sha256'],
                  [index, stream, 'original byte digest'])
            counts['stream_hash_checks'] += 1
        command = process['command']
        if len(command) == 2 and command[1] == '--version':
            versions.append(process)
            check((process['stdout'].strip() + ' ' + process['stderr'].strip()).strip() == raw['runtime'].strip(),
                  [index, 'recorded runtime version'])
        context = process.get('context')
        if not context:
            continue
        mapping = raw['revisions'][context['revision']]['package_mapping']
        check(process['cwd'] == mapping['resolved_root'], [index, 'mapped source cwd'])
        if context['phase'] == 'compile':
            key = context['benchmark'], context['revision']
            check(key not in compiled, [index, 'unique compile'])
            compiled[key] = process
            binary = command[command.index('-o') + 1]
            check(command == [command[0], 'compile', 'exe', '--packages=' + mapping['file'],
                f"benchmark/{context['benchmark']}.dart", '-o', binary], [index, 'exact compile command'])
        elif context['phase'] == 'benchmark':
            benchmark_records.add(index)
        else:
            check(False, [index, 'unknown subprocess phase'])
    check(len(versions) == 1, 'one runtime version subprocess')
    executable = versions[0]['command'][0]
    check(set(compiled) == {(name, revision) for name in BENCHMARKS
        for revision in ('before', 'after')}, 'six distinct source compilations')
    for name in BENCHMARKS:
        binaries = []
        for label in ('before', 'after'):
            command = compiled[name, label]['command']
            check(command[0] == executable, [name, label, 'identical runtime executable'])
            binaries.append(command[command.index('-o') + 1])
        check(binaries[0] != binaries[1], [name, 'distinct before/after AOT executables'])

    def check_work(name, case, work, context):
        no_solve = (name == 'cad' and case == 'thickness_edit_regenerate') or \
                   (name == 'cad_linkage' and case == 'placement_only_layer_edit')
        for field in COMMON_WORK:
            check(type(work.get(field)) is int and work[field] >= 0, [context, field, 'work count'])
        check(work['geometry_solve_invoked'] is (not no_solve), [context, 'solve invocation'])
        if no_solve:
            check(all(work[field] == 0 for field in GEOMETRY_WORK), [context, 'zero new geometry work'])
        if name == 'cad':
            expected = ['plate', 'mesh'] if no_solve else ['sketch', 'profile', 'plate', 'mesh']
            check(work['rebuilt_features'] == expected, [context, 'plate rebuild closure'])
            check(all(type(work[field]) is int and work[field] > 0 for field in ('vertices', 'triangles')),
                  [context, 'positive mesh size'])
        else:
            closures = {'cold_build_solve_solids_meshes': ALL_FEATURES,
                'retained_angle_edit': ['linkage'] + MOVING,
                'selective_coupler_length_edit': ['linkage', 'coupler.profile', 'coupler.body', 'coupler.mesh'] + MOVING,
                'placement_only_layer_edit': MOVING,
                'downstream_rejected_angle_edit': ['linkage'] + MOVING + ['gate']}
            check(work['rebuilt_features'] == closures[case], [context, 'linkage rebuild closure'])
            expected = {part: int(case == 'cold_build_solve_solids_meshes' or
                (case == 'selective_coupler_length_edit' and part == 'coupler')) for part in PARTS}
            for field in ('extrusions_by_part', 'tessellations_by_part'):
                check(work[field] == expected, [context, field, 'exact kernel work'])
            for field in ('components_solved', 'components_reused'):
                check(type(work[field]) is int and work[field] >= 0 and (not no_solve or work[field] == 0),
                      [context, field, 'new component work'])

    for run in raw['runs']:
        identity = tuple(run[k] for k in ('mode', 'round', 'benchmark', 'revision'))
        mode, round_, name, label = identity
        pointer = run['process_record']
        check(type(pointer) is int and 0 <= pointer < len(records) and pointer not in seen_records,
              [identity, 'unique valid process pointer'])
        seen_records.add(pointer)
        process = records[pointer]
        check(process['context'] == {'phase': 'benchmark', **{k: run[k] for k in ('mode', 'round', 'benchmark', 'revision')}},
              [identity, 'exact process context'])
        check(json.loads(process['stdout']) == run['result'], [identity, 'raw output equals retained result'])
        check(instant(run['started_at_utc']) <= instant(process['started_at_utc']) <=
              instant(process['finished_at_utc']) <= instant(run['finished_at_utc']),
              [identity, 'run bounds enclose process'])
        check(run.get('stderr', '') == process['stderr'].strip(), [identity, 'retained stderr'])
        check(run['arguments'] == ['--samples=25', '--warmups=5'], [identity, 'exact sampling flags'])
        mapping = raw['revisions'][label]['package_mapping']
        compile_record = compiled[name, label]
        binary = compile_record['command'][compile_record['command'].index('-o') + 1]
        prefix = [executable, '--packages=' + mapping['file'], f'benchmark/{name}.dart'] if mode == 'jit' else [binary]
        check(run['command'] == process['command'] == prefix + run['arguments'], [identity, 'complete run command'])
        check(instant(compile_record['finished_at_utc']) <= instant(process['started_at_utc']),
              [identity, 'compile precedes timed run'])
        result = run['result']
        check(not result.get('check_only', False) and not result.get('operation_tracing_enabled', False),
              [identity, 'ordinary uninstrumented timing'])
        if name == 'geometry_small_qr':
            check((result['warmups'], result['samples'], result['units'], result['independent_checks']) ==
                  (5, 25, 'microseconds_per_batch', 'passed'), [identity, 'small QR metadata and checks'])
            check([row['name'] for row in result['results']] == QR_CASES, [identity, 'all 12 QR cases'])
            distributions = [('results/' + row['name'], row) for row in result['results']]
            for index, row in enumerate(result['results']):
                batch = 8 if row['name'] == 'rank_48x48' else 256
                check(row['operations_per_batch'] == batch, [identity, row['name'], 'batch size'])
                if index < len(SHAPES):
                    m, n = SHAPES[index]
                    check((row['rows'], row['columns'], row['expected_rank']) == (m, n, min(m, n)),
                          [identity, row['name'], 'known-rank fixture'])
                elif row['name'] == 'damped_solve_8x4':
                    check((row['jacobian_rows'], row['columns'], row['augmented_rows']) == (8, 4, 12),
                          [identity, row['name'], 'known damped solve fixture'])
                else:
                    check((row['jacobian_rows'], row['columns'], row['expected_rank']) == (4, 8, 4),
                          [identity, row['name'], 'known nullspace fixture'])
        elif name == 'cad':
            check((result['warmup_pairs'], result['measured_pairs'], result['units'], result['analytic_volume_and_mesh_checks']) ==
                  (5, 25, 'microseconds', 'passed'), [identity, 'plate metadata and checks'])
            observed = [key for key, value in result.items() if isinstance(value, dict) and 'samples_us' in value]
            check(observed == PLATE_CASES, [identity, 'all three plate cases'])
            distributions = [(case, result[case]) for case in PLATE_CASES]
        else:
            check((result['warmup_iterations'], result['measured_iterations'], result['units'], result['independent_physical_reuse_rollback_checks']) ==
                  (5, 25, 'microseconds', 'passed'), [identity, 'linkage metadata and checks'])
            check((result['feature_count'], result['rejected_fixture_feature_count'], result['operations_per_batch']) == (17, 18, 1),
                  [identity, 'linkage feature and batch counts'])
            check(list(result['measurements']) == LINKAGE_CASES, [identity, 'all five linkage cases'])
            distributions = [('measurements/' + case, result['measurements'][case]) for case in LINKAGE_CASES]
        counts['process_reports'] += 1
        for path, distribution in distributions:
            samples = distribution['samples_us']
            check(len(samples) == 25 and all(type(v) is int and v >= 0 for v in samples),
                  [identity, path, '25 nonnegative integer samples'])
            ordered = sorted(samples)
            # QR uses ceil((n-1)*p); CAD uses nearest-rank ceil(n*p)-1.
            def percentile(fraction):
                index = math.ceil((len(ordered) - 1) * fraction) if name == 'geometry_small_qr' else math.ceil(len(ordered) * fraction) - 1
                return ordered[index]
            values = {'p50': percentile(.5), 'p95': percentile(.95)}
            if 'p99' in distribution:
                values['p99'] = percentile(.99)
            for field, value in values.items():
                check(distribution[field] == value, [identity, path, field, 'recomputed raw percentile'])
                counts['percentiles_checked'] += 1
            work = distribution.get('work_per_sample')
            if name != 'geometry_small_qr':
                check(isinstance(work, list) and len(work) == 25, [identity, path, 'aligned per-sample work'])
                for index, item in enumerate(work):
                    check_work(name, path.split('/')[-1], item, [identity, path, index])
                    counts['work_records_checked'] += 1
            key, pair = (mode, name, path), (label, round_)
            check(pair not in grouped[key], [identity, path, 'unique distribution'])
            grouped[key][pair] = {'values': values, 'work': work,
                'metadata': {k: v for k, v in distribution.items()
                    if k not in ('samples_us', 'work_per_sample', 'p50', 'p95', 'p99')}}
            counts['distributions'] += 1
            counts['measured_samples_or_batches'] += len(samples)
    check(seen_records == benchmark_records, 'all benchmark subprocesses represented exactly once')
    check((counts['process_reports'], counts['distributions'], counts['measured_samples_or_batches']) == (36, 240, 6000),
          'complete report/distribution/sample inventory')

    summary_rows = {(row['mode'], row['benchmark'], row['measurement']): row for row in summary['rows']}
    check(len(summary_rows) == len(summary['rows']) == len(grouped) == 40,
          '40 unique complete aggregate rows')
    check(set(summary_rows) == set(grouped), 'exact summary row inventory')
    rows = []
    for key, processes in grouped.items():
        saved = summary_rows[key]
        check(set(processes) == {(label, round_) for label in ('before', 'after') for round_ in range(1, 4)},
              [key, 'three complete before/after process pairs'])
        row = dict(zip(('mode', 'benchmark', 'measurement'), key))
        check(saved.get('units') == ('microseconds_per_batch' if key[1] == 'geometry_small_qr' else 'microseconds'),
              [key, 'summary units'])
        if key[1] == 'geometry_small_qr':
            batch = 8 if key[2] == 'results/rank_48x48' else 256
            check(saved.get('operations_per_batch') == batch, [key, 'summary batch count'])
        elif key[1] == 'cad_linkage':
            expected_features = 18 if key[2].endswith('downstream_rejected_angle_edit') else 17
            check(saved.get('operations_per_batch') == 1 and saved.get('feature_count') == expected_features,
                  [key, 'summary linkage scope'])
        for field in ('p50', 'p95'):
            before = [processes['before', i]['values'][field] for i in range(1, 4)]
            after = [processes['after', i]['values'][field] for i in range(1, 4)]
            b, a = statistics.median(before), statistics.median(after)
            ratios = [y / x if x else None for x, y in zip(before, after)]
            row[field] = {'before_us': b, 'after_us': a,
                'candidate_over_baseline': a / b if b else None,
                'change_percent': 100 * (a / b - 1) if b else None,
                'before_process_values': before, 'after_process_values': after,
                'paired_candidate_over_baseline': ratios,
                'faster_pairs': sum(y < x for x, y in zip(before, after)),
                'slower_pairs': sum(y > x for x, y in zip(before, after)),
                'equal_pairs': sum(y == x for x, y in zip(before, after))}
            for label, values in (('before', before), ('after', after)):
                check([value['round'] for value in saved[label]] == [1, 2, 3] and
                      [value[field + '_us'] for value in saved[label]] == values and
                      saved[label + '_median_' + field + '_us'] == statistics.median(values),
                      [key, label, field, 'summary process and aggregate values'])
        check(close(saved['elapsed_change_percent'], row['p50']['change_percent']), [key, 'summary p50 percent'])
        b, a = row['p50']['before_us'], row['p50']['after_us']
        check(close(saved['elapsed_ratio_before_over_after'], b / a if a else None), [key, 'summary inverse p50 ratio'])
        for i in range(1, 4):
            before, after = processes['before', i], processes['after', i]
            check(before['metadata'] == after['metadata'], [key, i, 'paired physical metadata'])
            check(before['work'] == after['work'], [key, i, 'exact paired sample work'])
            if before['work'] is not None:
                counts['paired_work_records_checked'] += len(before['work'])
        rows.append(row)
    report = {'status': 'passed' if not findings else 'failed', 'counts': dict(counts),
        'findings': findings, 'method': 'Independent committed-source, subprocess, fixture-specific sample/work and paired-summary reconstruction; no project audit imports and no Dart workloads.',
        'inputs': {str(path): digest(path.read_bytes()) for path in (args.raw, args.summary)},
        'runtime': raw['runtime'], 'source_checks': source_checks,
        'rounds': 3, 'warmups': 5, 'samples': 25, 'rows': rows,
        'limitations': ['Three fresh process pairs per runtime in a shared environment; no significance or causal attribution established.',
            'Medians aggregate per-process percentiles; raw samples and adverse rows are not discarded or pooled.',
            'CAD physical acceptance is supported by per-operation harness checks and paired work records; coordinates are not serialized for independent physical replay.',
            'Small-QR microseconds measure batches (8 or 256 operations), not individual calls.',
            'Runtime identity is recorded by --version and command; this collector does not hash AOT executables or installed dependency source bytes.',
            'At 25 samples, the recorded plate p99 is the process maximum, not strong tail evidence.']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'counts': report['counts'], 'findings': findings}))
    return int(bool(findings))


if __name__ == '__main__':
    sys.exit(main())

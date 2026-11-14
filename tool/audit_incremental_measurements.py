"""Independently reconcile the complete incremental-assumption comparison.

Usage: python audit_incremental_measurements.py RAW SUMMARY --output AUDIT
Optional --before/--after worktrees verify frozen library bytes, harness bytes
and the recorded dependency lock. RAW and SUMMARY may be JSON or gzip. This
auditor imports no project analysis code and never executes a timing workload.
It checks the reviewed nine-case harness, three paired rounds and both JIT/AOT.
All discovered discrepancies are retained in the output; a failure exits 1.
"""

import argparse
import collections
import datetime
import gzip
import hashlib
import json
import math
import pathlib
import re
import subprocess


BENCHMARK = 'incremental_assumptions'
HARNESS = 'benchmark/incremental_assumptions.dart'
# Reviewed at b626b30; also identifies the precise percentile/work contract.
HARNESS_SHA256 = '50a800b3bf7909adf29e3d6119280f951f1359b0bdc7bb87347e7941de756c2a'
MODES = ('jit', 'aot')
REVISIONS = ('before', 'after')
ROUNDS = (1, 2, 3)
MEASUREMENT = 'complete_assumption_solve_us'
UNITS = 'microseconds_per_batch'
OPERATIONS = 8
DEFAULT_FLAGS = {'--samples': 25, '--warmups': 5, '--operations': OPERATIONS}
WORK_FIELDS = {'operations', 'decisions', 'propagations', 'nary_revises', 'backtracks'}
CASES = {
    f'{fixture}/{assumption}': (cardinality, compact)
    for fixture, cardinality, compact in (
        ('explicit_100', 100, False),
        ('range_1000', 1000, True),
        ('range_1000000', 1000000, True),
    )
    for assumption in ('equals', 'not_equals', 'in_set')
}
TIMED_WORK = ('model and wrapper construction, assumption posting, solve, '
              'result retention and statistics snapshot; excludes independent '
              'checks and work aggregation')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def number(value):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value) and value >= 0
    except OverflowError:
        return False


def median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    return (ordered[middle] if len(ordered) % 2 else
            (ordered[middle - 1] + ordered[middle]) / 2)


def derived_equal(actual, expected):
    if expected is None:
        return actual is None
    return type(actual) in (int, float) and actual == expected


def measurement_path(case):
    return f'results/{case}/{MEASUREMENT}'


class Audit:
    def __init__(self):
        self.findings = []
        self.counts = collections.Counter()
        self.inputs = {}

    def check(self, condition, message):
        self.counts['assertions'] += 1
        if not condition:
            self.findings.append(message)
        return bool(condition)

    def mapping(self, value, location):
        return value if self.check(type(value) is dict, f'{location}: expected object') else {}

    def sequence(self, value, location):
        return value if self.check(type(value) is list, f'{location}: expected array') else []

    def read(self, path, label):
        try:
            data = path.read_bytes()
            content = gzip.decompress(data) if path.suffix == '.gz' else data
            self.inputs[label] = {
                'path': str(path), 'file_sha256': sha256(data),
                'content_sha256': sha256(content),
            }

            def pairs(items):
                result = {}
                for key, value in items:
                    self.check(key not in result, f'{label}: duplicate JSON object key {key!r}')
                    result[key] = value
                return result

            return self.mapping(json.loads(content, object_pairs_hook=pairs), label)
        except (OSError, ValueError, EOFError, UnicodeError) as error:
            self.check(False, f'{label}: could not read JSON: {error}')
            return {}

    def git(self, root, *arguments):
        try:
            result = subprocess.run(['git', *arguments], cwd=root,
                                    capture_output=True, check=False)
        except OSError as error:
            self.check(False, f'{root}: git {arguments!r} failed: {error}')
            return None
        if not self.check(result.returncode == 0,
                          f'{root}: git {arguments!r} failed: '
                          f'{result.stderr.decode(errors="replace").strip()}'):
            return None
        return result.stdout

    def file(self, root, relative):
        path = pathlib.PurePosixPath(relative)
        if not self.check(not path.is_absolute() and '..' not in path.parts,
                          f'{root}: unsafe recorded relative path {relative!r}'):
            return None
        try:
            return (root / path).read_bytes()
        except OSError as error:
            self.check(False, f'{root}/{relative}: could not read bytes: {error}')
            return None


def verify_sources(audit, raw, roots):
    revisions = audit.mapping(raw.get('revisions'), 'raw.revisions')
    audit.check(set(revisions) == set(REVISIONS), 'raw.revisions: expected before and after only')
    harnesses = audit.mapping(raw.get('harnesses'), 'raw.harnesses')
    audit.check(set(harnesses) == {BENCHMARK}, 'raw.harnesses: expected incremental_assumptions only')
    harness = audit.mapping(harnesses.get(BENCHMARK), 'raw.harnesses.incremental_assumptions')
    audit.check(harness.get('file') == HARNESS, 'Recorded harness path differs')
    audit.check(harness.get('sha256') == HARNESS_SHA256, 'Recorded harness differs from reviewed contract')
    provenance, lock_hashes = {}, {}
    for label in REVISIONS:
        location = f'raw.revisions.{label}'
        revision = audit.mapping(revisions.get(label), location)
        commit = revision.get('commit')
        valid_commit = isinstance(commit, str) and re.fullmatch(r'[0-9a-f]{40}', commit)
        audit.check(valid_commit, f'{location}: invalid source commit')
        audit.check('library_diff_sha256' in revision and revision['library_diff_sha256'] is None,
                    f'{location}: absent cleanliness record or dirty measured library')
        lock_hash = revision.get('dependency_lock_sha256')
        if lock_hash is not None:
            audit.check(isinstance(lock_hash, str) and re.fullmatch(r'[0-9a-f]{64}', lock_hash),
                        f'{location}: invalid recorded dependency lock hash')
            lock_hashes[label] = lock_hash
        root = roots[label]
        if root is None:
            continue
        root = root.resolve()
        record = provenance[label] = {
            'worktree': str(root), 'frozen_commit': commit if valid_commit else None,
        }
        audit.check(lock_hash is not None, f'{location}: dependency lock hash not recorded for byte verification')
        lock_bytes = audit.file(root, 'pubspec.lock')
        if lock_bytes is not None:
            record['dependency_lock_sha256'] = sha256(lock_bytes)
            audit.check(record['dependency_lock_sha256'] == lock_hash, f'{label}: dependency lock bytes differ')
            audit.counts['dependency_lock_hash_comparisons'] += 1
        harness_bytes = audit.file(root, HARNESS)
        if harness_bytes is not None:
            record['harness_sha256'] = sha256(harness_bytes)
            audit.check(record['harness_sha256'] == harness.get('sha256') == HARNESS_SHA256,
                        f'{label}: worktree harness bytes differ')
            audit.counts['harness_hash_comparisons'] += 1
        if not valid_commit:
            audit.check(False, f'{label}: cannot verify library without a valid source commit')
            continue
        tree = audit.git(root, 'rev-parse', commit + ':lib')
        if tree is not None:
            record['library_tree'] = tree.decode().strip()
            if 'library_tree' in revision:
                audit.check(revision['library_tree'] == record['library_tree'],
                            f'{label}: recorded library tree differs from frozen commit')
        diff = audit.git(root, 'diff', '--binary', commit, '--', 'lib', 'pubspec.yaml')
        if diff is not None:
            audit.check(not diff, f'{label}: library or package declaration differs from frozen commit')
        status = audit.git(root, 'status', '--porcelain=v1', '--untracked-files=all', '--', 'lib')
        if status is not None:
            audit.check(not status.strip(), f'{label}: dirty or untracked library files')
        paths = audit.git(root, 'ls-tree', '-r', '-z', '--name-only', commit, '--', 'lib')
        if paths is not None:
            names = [name.decode() for name in paths.split(b'\0') if name]
            record['library_files'] = len(names)
            for name in names:
                actual = audit.file(root, name)
                expected = audit.git(root, 'show', f'{commit}:{name}')
                if actual is not None and expected is not None:
                    audit.check(actual == expected, f'{label}: library byte mismatch {name}')
                    audit.counts['library_file_byte_comparisons'] += 1
        dependencies = audit.mapping(harness.get('dependency_sha256', {}), 'harness dependencies')
        for path, expected_hash in dependencies.items():
            audit.check(isinstance(expected_hash, str) and re.fullmatch(r'[0-9a-f]{64}', expected_hash),
                        f'{label}: invalid dependency hash for {path}')
            actual = audit.file(root, path)
            frozen = audit.git(root, 'show', f'{commit}:{path}')
            if actual is not None and frozen is not None:
                audit.check(sha256(actual) == sha256(frozen) == expected_hash,
                            f'{label}: harness dependency differs: {path}')
                audit.counts['dependency_hash_comparisons'] += 1
    if lock_hashes:
        audit.check(set(lock_hashes) == set(REVISIONS), 'Only one revision records a dependency lock hash')
        audit.check(lock_hashes.get('before') == lock_hashes.get('after'),
                    'Recorded before/after dependency lock hashes differ')
    return provenance


def arguments(audit, value, location):
    result, seen = dict(DEFAULT_FLAGS), set()
    for item in audit.sequence(value, location + '.arguments'):
        if not audit.check(isinstance(item, str) and '=' in item,
                           f'{location}: malformed argument {item!r}'):
            continue
        key, text = item.split('=', 1)
        audit.check(key not in seen, f'{location}: duplicate argument {key}')
        seen.add(key)
        if not audit.check(key in DEFAULT_FLAGS, f'{location}: unknown argument {key}'):
            continue
        if not audit.check(re.fullmatch(r'[0-9]+', text) is not None,
                           f'{location}: non-integer argument {item}'):
            continue
        result[key] = int(text)
    audit.check(result['--samples'] > 0, f'{location}: sample count must be positive')
    audit.check(result['--operations'] == OPERATIONS, f'{location}: expected eight operations per batch')
    return result


def audit_runs(audit, raw):
    audit.check(type(raw.get('rounds')) is int and raw['rounds'] == 3,
                'raw.rounds: this audit requires three rounds')
    runs = audit.sequence(raw.get('runs'), 'raw.runs')
    expected_order = [(mode, repeat, BENCHMARK, label)
                      for mode in MODES for repeat in ROUNDS
                      for label in (REVISIONS if repeat % 2 else REVISIONS[::-1])]
    actual_order, sampling, measurements = [], [], {}
    for index, value in enumerate(runs):
        location = f'run[{index}]'
        run = audit.mapping(value, location)
        mode, repeat, name, label = (run.get(key) for key in ('mode', 'round', 'benchmark', 'revision'))
        valid_key = (mode in MODES and type(repeat) is int and repeat in ROUNDS and
                     name == BENCHMARK and label in REVISIONS)
        audit.check(valid_key, f'{location}: invalid process key {(mode, repeat, name, label)!r}')
        key = (mode, repeat, name, label) if valid_key else None
        actual_order.append(key)
        flags = arguments(audit, run.get('arguments'), location)
        sampling.append(tuple(flags.items()))
        samples, warmups = flags['--samples'], flags['--warmups']
        result = audit.mapping(run.get('result'), location + '.result')
        audit.check(result.get('benchmark') == BENCHMARK, f'{location}: incorrect benchmark marker')
        audit.check(result.get('units') == UNITS, f'{location}: incorrect batch timing units')
        audit.check(type(result.get('operations_per_batch')) is int and
                    result['operations_per_batch'] == flags['--operations'] == OPERATIONS,
                    f'{location}: operations metadata differs')
        audit.check(type(result.get('samples')) is int and result['samples'] == samples,
                    f'{location}: samples metadata differs from arguments')
        audit.check(type(result.get('warmups')) is int and result['warmups'] == warmups,
                    f'{location}: warmup metadata differs from arguments')
        audit.check(result.get('independent_checks') == 'passed', f'{location}: missing independent oracle pass marker')
        audit.check(result.get('timed_work') == TIMED_WORK, f'{location}: measured operation boundary differs')
        audit.counts['process_reports'] += 1
        shapes = audit.sequence(result.get('results'), location + '.results')
        seen_cases = []
        for case_index, shape_value in enumerate(shapes):
            case_location = f'{location}/case[{case_index}]'
            shape = audit.mapping(shape_value, case_location)
            case = shape.get('name')
            valid_case = isinstance(case, str) and case in CASES
            audit.check(valid_case, f'{case_location}: unknown fixture {case!r}')
            seen_cases.append(case if isinstance(case, str) else None)
            audit.check(set(shape) == {'name', 'domain_cardinality', 'compact', MEASUREMENT},
                        f'{case_location}: missing or unexpected fixture fields')
            if valid_case:
                cardinality, compact = CASES[case]
                audit.check(type(shape.get('domain_cardinality')) is int and
                            shape['domain_cardinality'] == cardinality,
                            f'{case_location}: incorrect domain cardinality')
                audit.check(type(shape.get('compact')) is bool and shape['compact'] == compact,
                            f'{case_location}: incorrect compact-domain marker')
            distribution = audit.mapping(shape.get(MEASUREMENT), case_location + '/' + MEASUREMENT)
            audit.check(set(distribution) == {'p50', 'p95', 'samples_us', 'work_per_sample'},
                        f'{case_location}: missing or unexpected measurement fields')
            timing = audit.sequence(distribution.get('samples_us'), case_location + '/samples_us')
            works = audit.sequence(distribution.get('work_per_sample'), case_location + '/work_per_sample')
            audit.check(len(timing) == samples, f'{case_location}: timing sample count differs')
            audit.check(len(works) == samples == len(timing), f'{case_location}: work/timing records are unaligned')
            valid_samples = bool(timing)
            for sample_index, elapsed in enumerate(timing):
                valid = audit.check(integer(elapsed) and elapsed <= (1 << 63) - 1,
                                    f'{case_location}/sample[{sample_index}]: invalid microseconds {elapsed!r}')
                valid_samples &= valid
            for work_index, work_value in enumerate(works):
                work_location = f'{case_location}/work[{work_index}]'
                work = audit.mapping(work_value, work_location)
                audit.check(set(work) == WORK_FIELDS, f'{work_location}: missing or unexpected work fields')
                for field in WORK_FIELDS:
                    audit.check(integer(work.get(field)), f'{work_location}: invalid {field} counter')
                audit.check(work.get('operations') == result.get('operations_per_batch') == OPERATIONS,
                            f'{work_location}: operation count differs from batch metadata')
            recomputed = None
            for percentile in ('p50', 'p95'):
                audit.check(number(distribution.get(percentile)), f'{case_location}: invalid {percentile}')
            if valid_samples:
                ordered = sorted(timing)
                recomputed = {'p50': median(timing), 'p95': ordered[(95 * len(ordered) + 99) // 100 - 1]}
                for percentile, expected in recomputed.items():
                    audit.check(distribution.get(percentile) == expected,
                                f'{case_location}: raw {percentile} differs from independently computed samples')
                audit.counts['sample_derived_percentiles'] += 2
            else:
                audit.check(False, f'{case_location}: cannot recompute percentiles from missing/invalid samples')
            if valid_key and valid_case:
                measurement_key = (mode, case, label, repeat)
                audit.check(measurement_key not in measurements, f'{measurement_key}: duplicate raw distribution')
                # Keep the first record; a duplicate never replaces evidence.
                if measurement_key not in measurements:
                    measurements[measurement_key] = {'computed': recomputed, 'raw': distribution, 'works': works}
            audit.counts['raw_distributions'] += 1
            audit.counts['raw_samples'] += len(timing)
            audit.counts['aligned_work_records'] += len(works)
        audit.check(seen_cases == list(CASES), f'{location}: nine fixture cases are missing, duplicated, extra or reordered')
    audit.check(actual_order == expected_order, 'Process sequence is not complete JIT/AOT, alternating before/after for three rounds')
    actual_counts = collections.Counter(key for key in actual_order if key is not None)
    for key in expected_order:
        audit.check(actual_counts[key] == 1, f'{key}: expected exactly one process report; got {actual_counts[key]}')
    audit.check(len(set(sampling)) == 1, 'Sampling/operation arguments differ across process reports')
    for mode in MODES:
        for case in CASES:
            for repeat in ROUNDS:
                before = measurements.get((mode, case, 'before', repeat))
                after = measurements.get((mode, case, 'after', repeat))
                if not audit.check(before is not None and after is not None,
                                   f'{mode}/{case}/{repeat}: missing raw pair for aligned work comparison'):
                    continue
                left, right = before['works'], after['works']
                audit.check(len(left) == len(right), f'{mode}/{case}/{repeat}: paired work lengths differ')
                for index in range(max(len(left), len(right))):
                    audit.check(index < len(left) and index < len(right) and left[index] == right[index],
                                f'{mode}/{case}/{repeat}/work[{index}]: paired work differs')
                    audit.counts['paired_work_record_comparisons'] += 1
    return measurements, len(runs)


def audit_summary(audit, raw, summary, measurements, raw_path):
    audit.check(summary.get('revisions') == raw.get('revisions'), 'Summary revision metadata differs from raw')
    audit.check(summary.get('source') in (raw_path.name, raw_path.name.removesuffix('.gz')),
                'Summary source filename differs from raw input')
    rows = audit.sequence(summary.get('rows'), 'summary.rows')
    expected_keys = {(mode, measurement_path(case)) for mode in MODES for case in CASES}
    seen, recomputed_rows = collections.Counter(), []
    for index, row_value in enumerate(rows):
        location = f'summary.row[{index}]'
        row = audit.mapping(row_value, location)
        expected_fields = {
            'mode', 'benchmark', 'measurement', 'units', 'operations_per_batch',
            'before', 'after', 'elapsed_change_percent',
            'elapsed_ratio_before_over_after',
            *(f'{label}_median_{percentile}_us'
              for label in REVISIONS for percentile in ('p50', 'p95')),
        }
        audit.check(set(row) == expected_fields,
                    f'{location}: missing or unexpected summary fields')
        mode, path = row.get('mode'), row.get('measurement')
        key = (mode, path) if isinstance(mode, str) and isinstance(path, str) else None
        audit.check(key in expected_keys, f'{location}: unknown or missing measurement identity {key!r}')
        if key is not None:
            seen[key] += 1
        audit.check(row.get('benchmark') == BENCHMARK, f'{location}: incorrect benchmark')
        audit.check(row.get('units') == UNITS, f'{location}: incorrect units')
        audit.check(type(row.get('operations_per_batch')) is int and row['operations_per_batch'] == OPERATIONS,
                    f'{location}: incorrect operations metadata')
        case = next((name for name in CASES if measurement_path(name) == path), None)
        aggregates = {}
        for label in REVISIONS:
            points = audit.sequence(row.get(label), f'{location}/{label}')
            found_rounds, independent = [], []
            for point_index, point_value in enumerate(points):
                point_location = f'{location}/{label}[{point_index}]'
                point = audit.mapping(point_value, point_location)
                repeat = point.get('round')
                found_rounds.append(repeat)
                audit.check(set(point) == {'round', 'p50_us', 'p95_us'}, f'{point_location}: unexpected/missing process percentile fields')
                raw_key = (mode, case, label, repeat) if type(repeat) is int and isinstance(mode, str) else None
                measurement = measurements.get(raw_key)
                valid = measurement is not None and measurement['computed'] is not None
                audit.check(valid, f'{point_location}: no independently recomputable raw distribution')
                for percentile in ('p50', 'p95'):
                    field = percentile + '_us'
                    audit.check(number(point.get(field)), f'{point_location}: invalid {field}')
                    if valid:
                        audit.check(point.get(field) == measurement['raw'].get(percentile) == measurement['computed'][percentile],
                                    f'{point_location}: summary/raw/recomputed {percentile} differ')
                        audit.counts['summary_process_percentiles_reconciled'] += 1
                if valid:
                    independent.append(measurement['computed'])
            audit.check(all(type(value) is int for value in found_rounds) and found_rounds == list(ROUNDS),
                        f'{location}/{label}: missing, duplicated, extra or reordered rounds')
            if len(independent) == len(ROUNDS) and found_rounds == list(ROUNDS):
                for percentile in ('p50', 'p95'):
                    field = f'{label}_median_{percentile}_us'
                    expected = median([value[percentile] for value in independent])
                    aggregates[field] = expected
                    audit.check(number(row.get(field)) and row.get(field) == expected,
                                f'{location}: independently recomputed {field} differs')
                    audit.counts['aggregate_medians_reconciled'] += 1
            else:
                audit.check(False, f'{location}/{label}: incomplete independent process data for aggregate median')
        if len(aggregates) == 4:
            before, after = (aggregates[f'{label}_median_p50_us'] for label in REVISIONS)
            change = 100 * (after / before - 1) if before else None
            ratio = before / after if after else None
            audit.check(derived_equal(row.get('elapsed_change_percent'), change),
                        f'{location}: elapsed change percent differs')
            audit.check(derived_equal(row.get('elapsed_ratio_before_over_after'), ratio),
                        f'{location}: elapsed ratio differs')
            audit.counts['derived_ratios_reconciled'] += 2
            before95, after95 = (aggregates[f'{label}_median_p95_us'] for label in REVISIONS)
            recomputed_rows.append({
                'mode': mode, 'case': case, 'units': UNITS,
                'operations_per_batch': OPERATIONS, **aggregates,
                'elapsed_change_percent': change,
                'p95_change_percent': 100 * (after95 / before95 - 1) if before95 else None,
                'elapsed_ratio_before_over_after': ratio,
            })
    for key in sorted(expected_keys):
        audit.check(seen[key] == 1, f'{key}: expected exactly one summary row; got {seen[key]}')
    audit.check(set(seen) == expected_keys, 'Raw/summary measurement identity sets differ')
    return recomputed_rows, len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=pathlib.Path)
    parser.add_argument('summary', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--before', type=pathlib.Path)
    parser.add_argument('--after', type=pathlib.Path)
    args = parser.parse_args()
    audit = Audit()
    raw, summary = audit.read(args.raw, 'raw'), audit.read(args.summary, 'summary')
    provenance = verify_sources(audit, raw, {'before': args.before, 'after': args.after})
    measurements, processes = audit_runs(audit, raw)
    rows, row_count = audit_summary(audit, raw, summary, measurements, args.raw)
    report = {
        'status': 'passed' if not audit.findings else 'failed',
        'audited_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'auditor': 'Independent fixture-specific Python reconciliation; no project summarizer imports or timing execution',
        'reviewed_harness_sha256': HARNESS_SHA256,
        'inputs': audit.inputs, 'process_reports': processes, 'summary_rows': row_count,
        'rounds': raw.get('rounds') if type(raw.get('rounds')) is int else None,
        'counts': dict(audit.counts),
        'source_provenance': provenance, 'recomputed_rows': rows,
        'findings': audit.findings,
        'limitations': [
            'The recorded oracle pass marker and reviewed harness control flow establish check completion; raw result coordinates are not serialized for independent replay.',
            'Recorded run ordering is checked; the JSON alone cannot independently attest process scheduling or host isolation.',
            'Worktree library/harness/dependency-lock bytes are checked only for the --before/--after paths supplied.',
            'Medians are medians of process percentiles, not pooled sample percentiles; timings remain complete eight-operation batches.',
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print(json.dumps({key: report[key] for key in ('status', 'process_reports', 'summary_rows', 'counts', 'findings')}, indent=2))
    raise SystemExit(bool(audit.findings))


if __name__ == '__main__':
    main()

/// Bounded cold rank-diagnostic workload. Identical copies run on revisions
/// predating norm-work counters; missing counters stay absent. The chain is
/// triangular with unit diagonal, so full rank is independently known.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';

Float64List _chain(int n, int stride) {
  final matrix = Float64List(n * n);
  for (var row = 0; row < n; row++) {
    matrix[row * n + row] = 1;
    if (row >= stride) matrix[row * n + row - stride] = -1;
  }
  return matrix;
}

void _check(GeometryRankInfo? info, int n) {
  if (info == null ||
      info.rank != n ||
      info.independentColumns.toSet().length != n ||
      info.independentColumns.any((i) => i < 0 || i >= n) ||
      info.dependentColumns.isNotEmpty) {
    throw StateError('The unit-triangular chain must have full rank $n.');
  }
}

Map<String, int> _work(GeometryRankInfo info) {
  // Dynamic access lets the same source run at the earlier audit baseline.
  final dynamic candidate = info;
  try {
    return {
      'column_norm_evaluations': candidate.columnNormEvaluations as int,
      'column_norm_entry_visits': candidate.columnNormEntryVisits as int,
      'norm_downdates': candidate.normDowndates as int,
    };
    // An older comparison revision deliberately lacks these optional counters.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return {};
  }
}

double _percentile(List<int> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * fraction).ceil()].toDouble();
}

void main(List<String> arguments) {
  var samples = 25, warmups = 5;
  final checkOnly = arguments.contains('--check-only');
  for (final argument in arguments) {
    if (argument == '--check-only') continue;
    final parts = argument.split('=');
    if (parts.length != 2 ||
        (parts.first != '--samples' && parts.first != '--warmups')) {
      throw ArgumentError('Use --check-only, --samples=N, or --warmups=N.');
    }
    final value = int.tryParse(parts.last);
    if (value == null || value < (parts.first == '--samples' ? 1 : 0)) {
      throw ArgumentError('Invalid sample count: $argument');
    }
    if (parts.first == '--samples') {
      samples = value;
    } else {
      warmups = value;
    }
  }
  final results = <Map<String, Object>>[];
  for (final n in [48, 72, 96]) {
    final matrix = _chain(n, 3);
    final timings = <int>[];
    final count = checkOnly ? 1 : samples;
    late GeometryRankInfo result;
    for (var sample = checkOnly ? 0 : -warmups; sample < count; sample++) {
      final watch = Stopwatch()..start();
      final rank = geometryRank(matrix, n, n);
      watch.stop();
      _check(rank, n);
      result = rank!;
      if (sample >= 0) timings.add(watch.elapsedMicroseconds);
    }
    results.add({
      'rows': n,
      'columns': n,
      'expected_rank': n,
      'actual_rank': result.rank,
      'previous_full_rescan_entry_count': n * (n + 1) * (2 * n + 1) ~/ 6,
      'work': _work(result),
      if (!checkOnly) ...{
        'p50': _percentile(timings, 0.5),
        'p95': _percentile(timings, 0.95),
        'samples_us': timings,
      },
    });
  }
  print(jsonEncode({
    'fixture': 'Unit triangular XYZ chains; cold rank factorization',
    'units': 'microseconds',
    'warmups': checkOnly ? 0 : warmups,
    'samples': checkOnly ? 1 : samples,
    'independent_rank_checks': 'passed',
    'results': results,
  }));
}

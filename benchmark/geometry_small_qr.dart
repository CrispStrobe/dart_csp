/// Small CAD-sized dense rank, solve and nullspace workloads. This harness uses
/// baseline public APIs so identical copies can compare revisions. Timings are
/// batches, with independent checks outside the timed region for every result.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';

Float64List _matrix(int rows, int columns) {
  final result = Float64List(rows * columns);
  final rank = math.min(rows, columns);
  // The leading rank square is triangular with unit diagonal. Extra columns
  // repeat canonical axes; extra rows do not reduce its known full rank.
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < columns; col++) {
      if (row == col % rank) result[row * columns + col] = 1;
      if (row == (col % rank) + 1) result[row * columns + col] = -0.5;
    }
  }
  return result;
}

SparseGeometryJacobian _dense(List<List<double>> rows) =>
    SparseGeometryJacobian(
      rows: rows.length,
      columns: rows.first.length,
      rowOffsets: Int32List.fromList([
        for (var i = 0; i <= rows.length; i++) i * rows.first.length,
      ]),
      columnIndices: Int32List.fromList([
        for (final _ in rows)
          for (var col = 0; col < rows.first.length; col++) col,
      ]),
      values: Float64List.fromList(rows.expand((row) => row).toList()),
    );

double _percentile(List<int> samples, double fraction) {
  final sorted = [...samples]..sort();
  return sorted[((sorted.length - 1) * fraction).ceil()].toDouble();
}

Map<String, Object> _measure<T>(
    String name, T Function() operation, void Function(T result) check,
    {required int batch,
    required int warmups,
    required int samples,
    required bool checkOnly,
    Map<String, Object> details = const {}}) {
  final results = List<T?>.filled(checkOnly ? 1 : batch, null);
  final timings = <int>[];
  for (var sample = checkOnly ? 0 : -warmups;
      sample < (checkOnly ? 1 : samples);
      sample++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < results.length; i++) {
      results[i] = operation();
    }
    watch.stop();
    for (final result in results) {
      check(result as T);
    }
    if (sample >= 0) timings.add(watch.elapsedMicroseconds);
  }
  return {
    'name': name,
    ...details,
    'operations_per_batch': results.length,
    if (!checkOnly) ...{
      'p50': _percentile(timings, 0.5),
      'p95': _percentile(timings, 0.95),
      'samples_us': timings,
    },
  };
}

void main(List<String> arguments) {
  var samples = 25, warmups = 5;
  final checkOnly = arguments.contains('--check-only');
  for (final argument in arguments) {
    if (argument == '--check-only') continue;
    final pair = argument.split('=');
    if (pair.length != 2 ||
        (pair.first != '--samples' && pair.first != '--warmups')) {
      throw ArgumentError('Use --check-only, --samples=N or --warmups=N.');
    }
    final value = int.tryParse(pair.last);
    if (value == null || value < (pair.first == '--samples' ? 1 : 0)) {
      throw ArgumentError('Invalid sample count: $argument');
    }
    if (pair.first == '--samples') {
      samples = value;
    } else {
      warmups = value;
    }
  }
  final reports = <Map<String, Object>>[];
  for (final shape in [
    (5, 4),
    (8, 4),
    (4, 5),
    (4, 8),
    (9, 4),
    (12, 4),
    (16, 8),
    (16, 9),
    (17, 8),
    (48, 48),
  ]) {
    final (rows, columns) = shape;
    final matrix = _matrix(rows, columns);
    final rank = math.min(rows, columns);
    reports.add(_measure(
      'rank_${rows}x$columns',
      () => geometryRank(matrix, rows, columns),
      (result) {
        if (result == null ||
            result.rank != rank ||
            result.independentColumns.toSet().length != rank ||
            {...result.independentColumns, ...result.dependentColumns}.length !=
                columns) {
          throw StateError('Independent rank check failed for $shape.');
        }
      },
      batch: rows >= 48 ? 8 : 256,
      warmups: warmups,
      samples: samples,
      checkOnly: checkOnly,
      details: {'rows': rows, 'columns': columns, 'expected_rank': rank},
    ));
  }

  // Orthogonal columns give an independent damped normal-equation solution.
  final solveRows = List.generate(8, (_) => List<double>.filled(4, 0));
  final residual = Float64List(8);
  final diagonal = Float64List.fromList([1, 2, 3, 4]);
  final expected = Float64List(4);
  for (var i = 0; i < 4; i++) {
    final a = (i + 1).toDouble(), b = -(i + 2).toDouble();
    solveRows[i * 2][i] = a;
    solveRows[i * 2 + 1][i] = b;
    residual[i * 2] = a * 0.3;
    residual[i * 2 + 1] = b * 0.7;
    expected[i] = -(a * residual[i * 2] + b * residual[i * 2 + 1]) /
        (a * a + b * b + 0.125 * diagonal[i]);
  }
  final jacobian = _dense(solveRows);
  reports.add(_measure(
    'damped_solve_8x4',
    () => const DenseQrGeometrySolver()
        .solve(jacobian, residual, damping: 0.125, diagonal: diagonal),
    (result) {
      if (result.status != GeometryLinearStatus.converged ||
          result.relativeResidual > 1e-10) {
        throw StateError('Small damped solve failed.');
      }
      for (var i = 0; i < 4; i++) {
        if ((result.step[i] - expected[i]).abs() > 1e-11) {
          throw StateError('Independent diagonal solve oracle failed.');
        }
      }
    },
    batch: 256,
    warmups: warmups,
    samples: samples,
    checkOnly: checkOnly,
    details: {'jacobian_rows': 8, 'columns': 4, 'augmented_rows': 12},
  ));

  final projectionRows = <List<double>>[
    for (var row = 0; row < 4; row++)
      [
        for (var col = 0; col < 8; col++)
          if (col == row || col == row + 4) 1 else 0
      ],
  ];
  final projectionJacobian = _dense(projectionRows);
  final vector = Float64List.fromList([1, 2, -3, 4, -5, 6, 7, -8]);
  reports.add(_measure(
    'nullspace_4x8',
    () => projectGeometryNullspace(projectionJacobian, vector),
    (result) {
      if (result.status != GeometryLinearStatus.converged || result.rank != 4) {
        throw StateError('Small nullspace projection failed.');
      }
      for (var i = 0; i < 4; i++) {
        final expected = (vector[i] - vector[i + 4]) / 2;
        if ((result.vector[i] - expected).abs() > 1e-11 ||
            (result.vector[i + 4] + expected).abs() > 1e-11) {
          throw StateError('Independent nullspace oracle failed.');
        }
      }
    },
    batch: 256,
    warmups: warmups,
    samples: samples,
    checkOnly: checkOnly,
    details: {'jacobian_rows': 4, 'columns': 8, 'expected_rank': 4},
  ));
  print(jsonEncode({
    'fixture': 'Small CAD-sized QR with threshold-adjacent and larger controls',
    'units': 'microseconds_per_batch',
    'warmups': checkOnly ? 0 : warmups,
    'samples': checkOnly ? 1 : samples,
    'independent_checks': 'passed',
    'results': reports,
  }));
}

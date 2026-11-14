/// Small independent residual and existing-backend cross-checks; no timing claims.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';

import 'eigen_backend.dart';

SparseGeometryJacobian sparse(List<List<double>> matrix) {
  final offsets = <int>[0], columns = <int>[];
  final values = <double>[];
  for (final row in matrix) {
    for (var column = 0; column < row.length; column++) {
      if (row[column] != 0) {
        columns.add(column);
        values.add(row[column]);
      }
    }
    offsets.add(values.length);
  }
  return SparseGeometryJacobian(
      rows: matrix.length,
      columns: matrix.first.length,
      rowOffsets: Int32List.fromList(offsets),
      columnIndices: Int32List.fromList(columns),
      values: Float64List.fromList(values));
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1)
    throw ArgumentError('usage: verify_linear.dart LIBRARY.so');
  final direct =
      EigenSparseGeometrySolver(arguments.single, denseParameterLimit: 0);
  var count = 0;
  void compare(String name, SparseGeometryJacobian jacobian, List<double> r,
      double damping, List<double> d) {
    final residual = Float64List.fromList(r),
        diagonal = Float64List.fromList(d);
    final a = direct.solve(jacobian, residual,
        damping: damping,
        diagonal: diagonal,
        maxIterations: 1000,
        relativeTolerance: 1e-8);
    final q = const DenseQrGeometrySolver().solve(jacobian, residual,
        damping: damping,
        diagonal: diagonal,
        maxIterations: 1000,
        relativeTolerance: 1e-8);
    final c = const SparseCgGeometrySolver().solve(jacobian, residual,
        damping: damping,
        diagonal: diagonal,
        maxIterations: 5000,
        relativeTolerance: 1e-8);
    for (final (label, result) in [
      ('direct', a),
      ('dense_qr', q),
      ('stock_cg', c)
    ]) {
      final checked = checkedNormalResidual(
          jacobian, residual, diagonal, damping, result.step);
      require(
          result.status == GeometryLinearStatus.converged &&
              checked <= 1e-8 &&
              result.step.every((x) => x.isFinite),
          '$name/$label did not solve the supplied system');
    }
    double difference(Float64List left, Float64List right) =>
        geometryNorm(
            [for (var i = 0; i < left.length; i++) left[i] - right[i]]) /
        math.max(1.0, geometryNorm(right));
    final qrDifference = difference(a.step, q.step),
        cgDifference = difference(a.step, c.step);
    require(qrDifference < 1e-6 && cgDifference < 1e-6,
        '$name step disagrees with existing backends');
    stdout.writeln(jsonEncode({
      'case': name,
      'passed': true,
      'direct_relative_residual': a.relativeResidual,
      'qr_relative_residual': q.relativeResidual,
      'cg_relative_residual': c.relativeResidual,
      'step_difference_qr': qrDifference,
      'step_difference_cg': cgDifference
    }));
    count++;
  }

  try {
    compare(
        'overdetermined',
        sparse([
          [1, 2],
          [3, -1],
          [0, 4]
        ]),
        [.3, -.4, 1.2],
        .001,
        [5, 5]);
    compare(
        'underdetermined_damped',
        sparse([
          [1, 2, 0],
          [0, 1, -1]
        ]),
        [1, -.2],
        .2,
        [2, 3, 4]);
    compare(
        'nonuniform_metric',
        sparse([
          [.001, 0, 0],
          [0, 2, 0],
          [0, 0, 40]
        ]),
        [.1, -.3, 2],
        .001,
        [1, 2, 3]);
    final chain = List.generate(73, (_) => List<double>.filled(72, 0));
    chain[0][0] = 1;
    for (var i = 1; i < 72; i++) {
      chain[i][i - 1] = -.9;
      chain[i][i] = 1;
    }
    chain[72][71] = 1;
    compare('sparse_chain_72', sparse(chain),
        List.generate(73, (i) => math.sin(i * .7)), .03, List.filled(72, 2));
    compare(
        'duplicate_csr_columns',
        SparseGeometryJacobian(
            rows: 2,
            columns: 2,
            rowOffsets: Int32List.fromList([0, 3, 5]),
            columnIndices: Int32List.fromList([0, 0, 1, 0, 1]),
            values: Float64List.fromList([1, 2, .5, -1, 2])),
        [.4, -.7],
        .01,
        [3, 3]);

    final reusable = sparse([
      [1, 2],
      [3, -1],
      [0, 4]
    ]);
    direct.beginOperation(cold: true);
    compare('reuse_first', reusable, [.3, -.4, 1.2], .001, [5, 5]);
    reusable.values[0] =
        0; // Same structural pattern, a numerical zero crossing.
    compare('reuse_zero_crossing', reusable, [-.1, .4, .7], .003, [6, 6]);
    require(direct.symbolicAnalyses == 1 && direct.nativeFactorizations == 2,
        'symbolic pattern was not reused across a value change');
    direct.beginOperation(cold: true);
    compare('cold_symbolic_reset', reusable, [-.1, .4, .7], .003, [6, 6]);
    require(direct.symbolicAnalyses == 1,
        'cold operation did not recreate its symbolic workspace');

    final singular = sparse([
      [1, 1]
    ]);
    final singularResult = direct.solve(singular, Float64List.fromList([1]),
        damping: 0, diagonal: Float64List.fromList([1, 1]));
    require(singularResult.status == GeometryLinearStatus.numericalFailure,
        'singular undamped factor must not be reported as converged');
    stdout.writeln(jsonEncode({
      'case': 'singular_undamped',
      'passed': true,
      'status': singularResult.status.name
    }));
    count++;

    final valid = sparse([
      [1, 0],
      [0, 2]
    ]);
    final residual = Float64List.fromList([1, 1]),
        diagonal = Float64List.fromList([1, 1]);
    for (final kind in [
      'nan_jacobian',
      'negative_damping',
      'negative_diagonal',
      'invalid_tolerance'
    ]) {
      final bad = sparse([
        [1, 0],
        [0, 2]
      ]);
      final metric = Float64List.fromList(diagonal);
      if (kind == 'nan_jacobian') bad.values[0] = double.nan;
      if (kind == 'negative_diagonal') metric[0] = -1;
      final result = direct.solve(bad, residual,
          damping: kind == 'negative_damping' ? -1 : .1,
          diagonal: metric,
          relativeTolerance: kind == 'invalid_tolerance' ? 0 : 1e-8);
      require(result.status == GeometryLinearStatus.numericalFailure,
          '$kind was accepted');
      stdout.writeln(jsonEncode(
          {'case': kind, 'passed': true, 'status': result.status.name}));
      count++;
    }
    final budget = direct.solve(valid, residual,
        damping: .1, diagonal: diagonal, maxIterations: 0);
    require(budget.status == GeometryLinearStatus.iterationLimit,
        'zero budget was not respected');
    stdout.writeln(jsonEncode(
        {'case': 'zero_budget', 'passed': true, 'status': budget.status.name}));
    count++;
    final cancelled = direct.solve(valid, residual,
        damping: .1, diagonal: diagonal, shouldStop: () => true);
    require(cancelled.status == GeometryLinearStatus.cancelled,
        'cancellation was not respected');
    var polls = 0;
    final cancelledAfter = direct.solve(valid, residual,
        damping: .1, diagonal: diagonal, shouldStop: () => ++polls >= 3);
    require(
        cancelledAfter.status == GeometryLinearStatus.cancelled && polls == 3,
        'post-factor cancellation was not respected');
    stdout.writeln(
        jsonEncode({'case': 'cancellation_before_and_after', 'passed': true}));
    count++;
    stdout.writeln(
        jsonEncode({'record': 'summary', 'passed': true, 'cases': count}));
  } finally {
    direct.clear();
  }
}

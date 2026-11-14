import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

const _rows = <List<(int, double)>>[
  [(0, 1)],
  [(1, 1)],
  [(2, 1)],
  [(3, 1)],
  [(4, 1)],
  [(5, 1)],
  [(3, .5), (0, 2), (1, -1)],
  [(4, .25), (2, -2), (1, 3)],
  [(5, 2), (0, 1), (3, -.5)],
  [(4, 4), (2, .125), (5, -1)],
  [(4, .5), (2, 1), (4, -.5), (0, 0)],
  [],
];

class _System {
  _System(this.damping) {
    final offsets = <int>[0];
    final columns = <int>[];
    final values = <double>[];
    for (var row = 0; row < _rows.length; row++) {
      for (final (column, value) in _rows[row]) {
        columns.add(column);
        values.add(value);
        dense[row][column] += value;
      }
      offsets.add(columns.length);
      for (var column = 0; column < expected.length; column++) {
        residual[row] -= dense[row][column] * expected[column];
      }
    }
    // The first six rows are identity anchors, so these residual adjustments
    // give the prescribed answer for the damped original normal equation.
    for (var column = 0; column < expected.length; column++) {
      residual[column] -= damping * diagonal[column] * expected[column];
    }
    residual.last = 17; // An empty row has no effect on the normal system.
    jacobian = SparseGeometryJacobian(
      rows: _rows.length,
      columns: expected.length,
      rowOffsets: Int32List.fromList(offsets),
      columnIndices: Int32List.fromList(columns),
      values: Float64List.fromList(values),
    );
  }

  final double damping;
  final expected = Float64List.fromList([.25, -1.5, 2, .75, -.5, 1.25]);
  final diagonal = Float64List.fromList([.5, 2, 1.25, 3, .75, 1.5]);
  final residual = Float64List(_rows.length);
  final dense = List.generate(_rows.length, (_) => List<double>.filled(6, 0));
  late final SparseGeometryJacobian jacobian;

  GeometryLinearStep solve(
          {int maxIterations = 40, bool Function()? shouldStop}) =>
      const SparseCgGeometrySolver().solve(jacobian, residual,
          damping: damping,
          diagonal: diagonal,
          maxIterations: maxIterations,
          relativeTolerance: 1e-12,
          shouldStop: shouldStop);

  // Compute the original equation using the independently assembled dense J,
  // without calling a production matrix-vector or norm helper.
  double relativeResidual(List<double> step) {
    final initial = List<double>.filled(expected.length, 0);
    final actual = List<double>.filled(expected.length, 0);
    for (var row = 0; row < dense.length; row++) {
      var value = residual[row];
      for (var column = 0; column < expected.length; column++) {
        value += dense[row][column] * step[column];
      }
      for (var column = 0; column < expected.length; column++) {
        initial[column] += dense[row][column] * residual[row];
        actual[column] += dense[row][column] * value;
      }
    }
    var initialSquared = 0.0;
    var actualSquared = 0.0;
    for (var column = 0; column < expected.length; column++) {
      actual[column] += damping * diagonal[column] * step[column];
      initialSquared += initial[column] * initial[column];
      actualSquared += actual[column] * actual[column];
    }
    return math.sqrt(actualSquared / initialSquared);
  }
}

void main() {
  group('sparse conjugate gradients', () {
    test('solves the original equation with mixed rows and nonuniform damping',
        () {
      for (final damping in [0.0, .125, 8.0]) {
        final system = _System(damping);
        final result = system.solve();
        expect(result.status, GeometryLinearStatus.converged);
        expect(result.iterations, greaterThan(1));
        expect(system.relativeResidual(result.step), lessThanOrEqualTo(1e-12));
        expect(result.relativeResidual,
            closeTo(system.relativeResidual(result.step), 1e-14));
        for (var column = 0; column < system.expected.length; column++) {
          expect(result.step[column], closeTo(system.expected[column], 1e-10));
        }
      }
    });

    test('cancellation retains each completed iterate and its snapshot', () {
      final system = _System(.125);
      var completePolls = 0;
      final complete = system.solve(shouldStop: () {
        completePolls++;
        return false;
      });
      expect(complete.status, GeometryLinearStatus.converged);
      expect(completePolls, greaterThan(1));
      expect(completePolls, complete.iterations);

      for (var stopAt = 1; stopAt <= completePolls; stopAt++) {
        var polls = 0;
        final cancelled = system.solve(shouldStop: () => ++polls == stopAt);
        expect(cancelled.status, GeometryLinearStatus.cancelled);
        expect(cancelled.iterations, stopAt - 1);
        expect(polls, stopAt);
        final snapshot = cancelled.step.toList();
        final limited = system.solve(maxIterations: stopAt - 1);
        expect(limited.status, GeometryLinearStatus.iterationLimit);
        expect(limited.iterations, stopAt - 1);
        expect(limited.step, snapshot);
        expect(limited.relativeResidual,
            closeTo(system.relativeResidual(limited.step), 1e-14));
        expect(cancelled.step, snapshot);
      }
    });

    test('reentrant solves at every iteration leave outer results independent',
        () {
      final system = _System(.125);
      final expected = system.solve();
      final expectedSnapshot = expected.step.toList();
      final nested = <(GeometryLinearStep, List<double>)>[];
      final outer = system.solve(shouldStop: () {
        final result = system.solve(maxIterations: 1);
        nested.add((result, result.step.toList()));
        return false;
      });
      expect(outer.status, expected.status);
      expect(outer.iterations, expected.iterations);
      expect(outer.relativeResidual, expected.relativeResidual);
      expect(outer.step, expectedSnapshot);
      expect(expected.step, expectedSnapshot);
      expect(nested.length, expected.iterations);
      for (final (result, snapshot) in nested) {
        expect(result.status, GeometryLinearStatus.iterationLimit);
        expect(result.iterations, 1);
        expect(result.step, snapshot);
        expect(result.relativeResidual,
            closeTo(system.relativeResidual(result.step), 1e-14));
      }
    });

    test('nonfinite dot products retain cancellation and iteration precedence',
        () {
      final jacobian = SparseGeometryJacobian(
        rows: 1,
        columns: 1,
        rowOffsets: Int32List.fromList([0, 1]),
        columnIndices: Int32List.fromList([0]),
        values: Float64List.fromList([1e-100]),
      );
      GeometryLinearStep solve(
              {int maxIterations = 10, bool Function()? shouldStop}) =>
          const SparseCgGeometrySolver().solve(
              jacobian, Float64List.fromList([1e200]),
              damping: 0,
              diagonal: Float64List.fromList([1]),
              maxIterations: maxIterations,
              shouldStop: shouldStop);

      final failed = solve();
      expect(failed.status, GeometryLinearStatus.numericalFailure);
      final cancelled = solve(shouldStop: () => true);
      expect(cancelled.status, GeometryLinearStatus.cancelled);
      final limited = solve(maxIterations: 0);
      expect(limited.status, GeometryLinearStatus.iterationLimit);
      for (final result in [failed, cancelled, limited]) {
        expect(result.iterations, 0);
        expect(result.step, [0]);
        expect(result.relativeResidual, 1);
      }
    });
  });
}

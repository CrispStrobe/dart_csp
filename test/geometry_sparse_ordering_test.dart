import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

SparseGeometryJacobian _fixture(int columns,
    [List<(int, int)> edges = const []]) {
  final offsets = <int>[0];
  final indices = <int>[];
  final values = <double>[];
  for (var column = 0; column < columns; column++) {
    indices.add(column);
    values.add(1);
    offsets.add(indices.length);
  }
  for (final (left, right) in edges) {
    indices.addAll([left, right]);
    values.addAll([1, -.5]);
    offsets.add(indices.length);
  }
  return SparseGeometryJacobian(
    rows: offsets.length - 1,
    columns: columns,
    rowOffsets: Int32List.fromList(offsets),
    columnIndices: Int32List.fromList(indices),
    values: Float64List.fromList(values),
  );
}

Float64List _expected(int columns) => Float64List.fromList([
      for (var column = 0; column < columns; column++)
        ((column * 7) % 31 - 15) / 8,
    ]);

Float64List _residual(SparseGeometryJacobian jacobian) {
  final expected = _expected(jacobian.columns);
  return Float64List.fromList([
    for (var row = 0; row < jacobian.rows; row++)
      -[
        for (var k = jacobian.rowOffsets[row];
            k < jacobian.rowOffsets[row + 1];
            k++)
          jacobian.values[k] * expected[jacobian.columnIndices[k]],
      ].fold<double>(0, (sum, value) => sum + value),
  ]);
}

GeometryLinearStep _solve(
  SparseLdltGeometrySolver solver,
  SparseGeometryJacobian jacobian, {
  bool Function()? shouldStop,
}) =>
    solver.solve(
      jacobian,
      _residual(jacobian),
      damping: 0,
      diagonal: Float64List(jacobian.columns)
        ..fillRange(0, jacobian.columns, 1),
      maxIterations: 1,
      relativeTolerance: 1e-10,
      shouldStop: shouldStop,
    );

void _checkSolution(GeometryLinearStep result, int columns) {
  expect(result.status, GeometryLinearStatus.converged);
  expect(result.iterations, 1);
  expect(result.relativeResidual, lessThanOrEqualTo(1e-10));
  final expected = _expected(columns);
  for (var column = 0; column < columns; column++) {
    expect(result.step[column], closeTo(expected[column], 1e-9),
        reason: 'coordinate $column');
  }
}

void main() {
  group('bounded large sparse ordering', () {
    test('4096 independent coordinates fit a subquadratic symbolic budget', () {
      const columns = 4096;
      final jacobian = _fixture(columns);
      // A live-column scan alone would require 8,390,656 visits. Heap
      // initialization/comparisons/removals and all other recorded structural
      // work fit this cap without increasing any factor or numeric limit.
      final result = _solve(
        const SparseLdltGeometrySolver(
          maxSymbolicWork: 150000,
          maxNumericWork: 0,
          maxFactorEntries: columns,
          maxAssemblyWork: columns,
        ),
        jacobian,
      );
      _checkSolution(result, columns);
      expect(result.step, _expected(columns));
    });

    test('degree updates preserve original-index ties and exact numeric cap',
        () {
      const vertices = [1, 7, 31, 44, 99, 127, 180, 233, 255];
      const localEdges = [
        (0, 5),
        (0, 6),
        (0, 7),
        (0, 8),
        (1, 2),
        (1, 4),
        (1, 6),
        (2, 4),
        (2, 5),
        (2, 7),
        (2, 8),
        (3, 4),
        (3, 6),
        (3, 7),
        (4, 5),
        (4, 8),
        (5, 7),
        (6, 8),
      ];
      final jacobian = _fixture(256, [
        for (final (a, b) in localEdges) (vertices[a], vertices[b]),
      ]);
      // After isolated columns, independent exact minimum-degree elimination
      // visits local vertices 1,3,0,2,4,5,6,7,8. Their live degrees are
      // 3,3,4,5,4,3,2,1,0, requiring 57 Schur updates. Several keys increase
      // during fill before decreasing later. Reversed-index ties would use
      // only 52 updates, so they would incorrectly accept the 56-update cap.
      final declined = _solve(
        const SparseLdltGeometrySolver(maxNumericWork: 56),
        jacobian,
      );
      expect(declined.status, GeometryLinearStatus.iterationLimit);
      expect(declined.iterations, 0);
      _checkSolution(
        _solve(const SparseLdltGeometrySolver(maxNumericWork: 57), jacobian),
        256,
      );
    });

    test('large heap work limits apply to fresh, negative and positive caches',
        () {
      final jacobian = _fixture(256);
      const limited = SparseLdltGeometrySolver(maxSymbolicWork: 1024);
      const permissive = SparseLdltGeometrySolver(maxSymbolicWork: 15000);
      for (var call = 0; call < 2; call++) {
        final declined = _solve(limited, jacobian);
        expect(declined.status, GeometryLinearStatus.iterationLimit);
        expect(declined.iterations, 0);
      }
      _checkSolution(_solve(permissive, jacobian), 256);
      final cached = _solve(limited, jacobian);
      expect(cached.status, GeometryLinearStatus.iterationLimit);
      expect(cached.iterations, 0);
      _checkSolution(_solve(permissive, jacobian), 256);
    });

    test('cancellation during heap ordering does not cache an incomplete shape',
        () {
      const columns = 1024;
      final jacobian = _fixture(columns);
      var polls = 0;
      final cancelled = _solve(
        const SparseLdltGeometrySolver(),
        jacobian,
        // Entry validation and the 1024 original-row checks finish first;
        // this later callback interrupts ordering before numeric assembly.
        shouldStop: () => ++polls >= columns + 64,
      );
      expect(cancelled.status, GeometryLinearStatus.cancelled);
      expect(cancelled.iterations, 0);
      expect(polls, columns + 64);
      _checkSolution(
          _solve(const SparseLdltGeometrySolver(), jacobian), columns);
    });
  });
}

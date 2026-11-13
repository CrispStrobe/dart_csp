import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

SparseGeometryJacobian _dense(List<List<double>> rows) =>
    SparseGeometryJacobian(
      rows: rows.length,
      columns: rows.first.length,
      rowOffsets: Int32List.fromList([
        for (var i = 0; i <= rows.length; i++) i * rows.first.length,
      ]),
      columnIndices: Int32List.fromList([
        for (final _ in rows)
          for (var j = 0; j < rows.first.length; j++) j,
      ]),
      values: Float64List.fromList(rows.expand((row) => row).toList()),
    );

// The starting columns span exactly rank canonical axes. Orthogonal row
// rotations and permutations preserve their known span without using QR.
Float64List _knownRank(
    int rows, int columns, int rank, double scale, math.Random random) {
  final values = List.generate(rows, (_) => List<double>.filled(columns, 0));
  if (rank != 0) {
    for (var column = 0; column < columns; column++) {
      values[column % rank][column] = 0.75 + random.nextDouble();
    }
    for (var rotation = 0; rotation < rows * 3; rotation++) {
      final first = random.nextInt(rows);
      final second = (first + 1 + random.nextInt(rows - 1)) % rows;
      final angle = random.nextDouble() * math.pi;
      final c = math.cos(angle), s = math.sin(angle);
      for (var column = 0; column < columns; column++) {
        final x = values[first][column], y = values[second][column];
        values[first][column] = c * x + s * y;
        values[second][column] = -s * x + c * y;
      }
    }
  }
  final order = List.generate(columns, (i) => i)..shuffle(random);
  return Float64List.fromList([
    for (final row in values)
      for (final column in order) row[column] * scale,
  ]);
}

void main() {
  group('small QR numerical oracles', () {
    test('known ranks survive aspect, scale and matrix-shape changes', () {
      final random = math.Random(912047);
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
      ]) {
        final (rows, columns) = shape;
        for (var rank = 0; rank <= math.min(rows, columns); rank++) {
          for (final scale in [1e-150, 1.0, 1e150]) {
            final matrix = _knownRank(rows, columns, rank, scale, random);
            final original = Float64List.fromList(matrix);
            final actual = geometryRank(matrix, rows, columns)!;
            expect(actual.rank, rank,
                reason: '$rows x $columns, rank=$rank, scale=$scale');
            expect(actual.independentColumns.length, rank);
            expect({
              ...actual.independentColumns,
              ...actual.dependentColumns,
            }, {
              for (var i = 0; i < columns; i++) i
            });
            expect(matrix, original);
          }
        }
      }
    });

    test('rectangular and larger matrices retain guarded scan savings', () {
      for (final shape in [(16, 9), (17, 8), (48, 48)]) {
        final (rows, columns) = shape;
        final matrix = Float64List(rows * columns);
        for (var row = 0; row < rows; row++) {
          if (row < columns) matrix[row * columns + row] = 1;
          if (row >= 3 && row - 3 < columns) {
            matrix[row * columns + row - 3] = -1;
          }
        }
        final actual = geometryRank(matrix, rows, columns)!;
        expect(actual.rank, columns);
        expect(actual.normDowndates, greaterThan(0));
        if (rows == 48) {
          const fullScanEntries = 48 * 49 * 97 ~/ 6;
          expect(actual.columnNormEntryVisits, lessThan(fullScanEntries ~/ 3));
        }
      }
    });

    test('rank cutoff is relative and checked at every tiny pivot', () {
      for (final scale in [1e-150, 1.0, 1e150]) {
        final matrix = Float64List.fromList([
          scale,
          0,
          0,
          0,
          scale * 1e-8,
          0,
          0,
          0,
          scale * 1e-12,
          0,
          0,
          0,
        ]);
        expect(geometryRank(matrix, 4, 3)!.rank, 2);
        expect(geometryRank(matrix, 4, 3, relativeTolerance: 1e-14)!.rank, 3);
        expect(geometryRank(matrix, 4, 3, relativeTolerance: 1e-6)!.rank, 1);
      }
    });

    test('nonfinite later columns cannot hide behind a finite pivot', () {
      for (final invalid in [double.nan, double.infinity, -double.infinity]) {
        final matrix = Float64List.fromList([
          2,
          0,
          invalid,
          0,
          1,
          0,
          1,
          0,
          0,
        ]);
        expect(geometryRank(matrix, 3, 3), isNull);
      }
    });

    test('small rank work remains cancellable', () {
      final matrix = _knownRank(12, 4, 4, 1, math.Random(184));
      var polls = 0;
      expect(
          geometryRank(matrix, 12, 4, shouldStop: () => ++polls >= 3), isNull);
      expect(polls, 3);
      expect(geometryRank(matrix, 12, 4)!.rank, 4);
    });
  });

  group('tiny checked solves and projections', () {
    test('damped solve matches an independently diagonalized system', () {
      // Each coordinate has two disjoint signed observations; J'J is diagonal.
      for (final n in [1, 2, 4, 5]) {
        final rows = List.generate(n * 2, (_) => List<double>.filled(n, 0));
        final residual = Float64List(n * 2), diagonal = Float64List(n);
        for (var i = 0; i < n; i++) {
          rows[i * 2][i] = (i + 1).toDouble();
          rows[i * 2 + 1][i] = -(i + 2).toDouble();
          residual[i * 2] = 0.3 * (i + 1);
          residual[i * 2 + 1] = -0.7 * (i + 2);
          diagonal[i] = 0.5 + i;
        }
        const damping = 0.125;
        final solved = const DenseQrGeometrySolver().solve(
            _dense(rows), residual,
            damping: damping, diagonal: diagonal);
        expect(solved.status, GeometryLinearStatus.converged);
        for (var i = 0; i < n; i++) {
          final a = rows[i * 2][i], b = rows[i * 2 + 1][i];
          final expected = -(a * residual[i * 2] + b * residual[i * 2 + 1]) /
              (a * a + b * b + damping * diagonal[i]);
          expect(solved.step[i], closeTo(expected, 1e-12));
        }
        expect(solved.relativeResidual, lessThan(1e-12));
      }
    });

    test('projection is orthogonal even with redundant tiny equations', () {
      for (final redundant in [false, true]) {
        final rows = <List<double>>[
          for (var i = 0; i < 4; i++)
            [
              for (var j = 0; j < 8; j++)
                if (j == i || j == i + 4) 1.0 else 0.0
            ],
          if (redundant) ...[
            [2.0, 0, 0, 0, 2, 0, 0, 0],
            [0.0, -3, 0, 0, 0, -3, 0, 0],
            [0.0, 0, 4, 0, 0, 0, 4, 0],
          ],
        ];
        final vector = Float64List.fromList([1, -2, 3, 4, -5, 6, 7, -8]);
        final result = projectGeometryNullspace(_dense(rows), vector);
        expect(result.status, GeometryLinearStatus.converged);
        expect(result.rank, 4);
        for (var i = 0; i < 4; i++) {
          final expected = (vector[i] - vector[i + 4]) / 2;
          expect(result.vector[i], closeTo(expected, 1e-12));
          expect(result.vector[i + 4], closeTo(-expected, 1e-12));
        }
        expect(result.relativeConstraintError, lessThan(1e-12));
      }
    });

    test('tiny solves and projections honor zero and partial pivot budgets',
        () {
      final j = _dense([
        [1, 0, 0, 0],
        [0, 2, 0, 0],
        [0, 0, 3, 0],
        [0, 0, 0, 4],
      ]);
      final vector = Float64List.fromList([1, 2, 3, 4]);
      for (final budget in [0, 1, 3]) {
        final solve = const DenseQrGeometrySolver().solve(j, vector,
            damping: 0.1,
            diagonal: Float64List.fromList([1, 1, 1, 1]),
            maxIterations: budget);
        expect(solve.status, GeometryLinearStatus.iterationLimit);
        expect(solve.iterations, lessThanOrEqualTo(budget));
        final projection =
            projectGeometryNullspace(j, vector, maxIterations: budget);
        expect(projection.status, GeometryLinearStatus.iterationLimit);
        expect(projection.iterations, lessThanOrEqualTo(budget));
      }
      final complete = const DenseQrGeometrySolver().solve(j, vector,
          damping: 0.1,
          diagonal: Float64List.fromList([1, 1, 1, 1]),
          maxIterations: 4);
      expect(complete.status, GeometryLinearStatus.converged);
    });

    test('tiny backend cancellation never reports convergence', () {
      final j = _dense([
        [1, 1, 0],
        [0, 1, 1],
        [1, 0, 1],
      ]);
      final vector = Float64List.fromList([1, -2, 3]);
      var solvePolls = 0;
      final solve = const DenseQrGeometrySolver().solve(j, vector,
          damping: 0.1,
          diagonal: Float64List.fromList([1, 1, 1]),
          shouldStop: () => ++solvePolls >= 3);
      expect(solve.status, GeometryLinearStatus.cancelled);
      var projectionPolls = 0;
      final projection = projectGeometryNullspace(j, vector,
          shouldStop: () => ++projectionPolls >= 3);
      expect(projection.status, GeometryLinearStatus.cancelled);
    });
  });
}

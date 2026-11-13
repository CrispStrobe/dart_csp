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

// Independent partial-pivot elimination, used only for the small dense oracle.
List<double> _eliminate(List<List<double>> coefficients, List<double> rhs) {
  final n = rhs.length;
  final matrix = [
    for (var i = 0; i < n; i++) [...coefficients[i], rhs[i]],
  ];
  for (var column = 0; column < n; column++) {
    var pivot = column;
    for (var row = column + 1; row < n; row++) {
      if (matrix[row][column].abs() > matrix[pivot][column].abs()) {
        pivot = row;
      }
    }
    final swap = matrix[pivot];
    matrix[pivot] = matrix[column];
    matrix[column] = swap;
    for (var row = column + 1; row < n; row++) {
      final scale = matrix[row][column] / matrix[column][column];
      for (var j = column; j <= n; j++) {
        matrix[row][j] -= scale * matrix[column][j];
      }
    }
  }
  final out = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var rhs = matrix[i][n];
    for (var j = i + 1; j < n; j++) {
      rhs -= matrix[i][j] * out[j];
    }
    out[i] = rhs / matrix[i][i];
  }
  return out;
}

void main() {
  group('checked QR norm updates', () {
    test('full-rank chain avoids cubic repeated column norm scans', () {
      const n = 72;
      final matrix = Float64List(n * n);
      for (var i = 0; i < n; i++) {
        matrix[i * n + i] = 1;
        if (i >= 3) matrix[i * n + i - 3] = -1;
      }
      final result = geometryRank(matrix, n, n)!;
      expect(result.rank, n);
      expect(
          result.independentColumns.toSet(), {for (var i = 0; i < n; i++) i});
      // The previous implementation read all remaining columns at each pivot.
      const previousNormEntries = n * (n + 1) * (2 * n + 1) ~/ 6;
      expect(result.columnNormEntryVisits, lessThan(previousNormEntries ~/ 3));
      expect(result.normDowndates, greaterThan(n));
      expect(result.columnNormEvaluations, greaterThanOrEqualTo(n));
      // Ranking copies its argument; reusable caller storage must not change.
      for (var i = 0; i < n; i++) {
        expect(matrix[i * n + i], 1);
      }
    });

    test('almost parallel columns refresh before a false rank cutoff', () {
      const n = 24;
      for (final scale in [1e-150, 1.0, 1e150]) {
        final matrix = Float64List((n + 1) * n);
        for (var column = 0; column < n; column++) {
          matrix[column] = scale;
          matrix[(column + 1) * n + column] = 1e-8 * scale;
        }
        final precise = geometryRank(matrix, n + 1, n)!;
        expect(precise.rank, n, reason: 'scale=$scale');
        final coarse = geometryRank(matrix, n + 1, n, relativeTolerance: 1e-6)!;
        expect(coarse.rank, 1, reason: 'scale=$scale');
      }
    });

    test('rank respects known independent columns after permutations/scaling',
        () {
      final random = math.Random(97122);
      for (var sample = 0; sample < 48; sample++) {
        const rows = 11, columns = 9;
        final rank = 1 + sample % columns;
        final a = List.generate(rows, (_) => List<double>.filled(columns, 0));
        // Distinct canonical columns span exactly rank dimensions. Subsequent
        // orthogonal row rotations and column permutations preserve that rank.
        for (var column = 0; column < columns; column++) {
          a[column % rank][column] = 0.5 + random.nextDouble();
        }
        for (var rotation = 0; rotation < 50; rotation++) {
          final first = random.nextInt(rows);
          final second = (first + 1 + random.nextInt(rows - 1)) % rows;
          final angle = random.nextDouble() * 2 * math.pi;
          final c = math.cos(angle), s = math.sin(angle);
          for (var column = 0; column < columns; column++) {
            final x = a[first][column], y = a[second][column];
            a[first][column] = c * x + s * y;
            a[second][column] = -s * x + c * y;
          }
        }
        final permutation = List.generate(columns, (i) => i)..shuffle(random);
        final scale = sample.isEven ? 1e-120 : 1e120;
        final matrix = Float64List.fromList([
          for (final row in a)
            for (final column in permutation) row[column] * scale,
        ]);
        final actual = geometryRank(matrix, rows, columns)!;
        expect(actual.rank, rank, reason: 'sample $sample');
        expect(actual.independentColumns.length, rank);
        expect({
          ...actual.independentColumns,
          ...actual.dependentColumns,
        }, {
          for (var i = 0; i < columns; i++) i
        });
      }
    });

    test('damped QR agrees with independently eliminated normal equations', () {
      final random = math.Random(77331);
      for (var sample = 0; sample < 32; sample++) {
        const m = 8, n = 5;
        final rows = List.generate(
            m, (_) => List.generate(n, (_) => random.nextDouble() * 2 - 1));
        final residual = Float64List.fromList(
            List.generate(m, (_) => random.nextDouble() * 6 - 3));
        final diagonal = Float64List.fromList(
            List.generate(n, (_) => 0.5 + random.nextDouble()));
        const damping = 0.01;
        final normal = List.generate(
            n,
            (i) => List.generate(n, (j) {
                  var sum = i == j ? damping * diagonal[i] : 0.0;
                  for (var row = 0; row < m; row++) {
                    sum += rows[row][i] * rows[row][j];
                  }
                  return sum;
                }));
        final rhs = List.generate(n, (i) {
          var sum = 0.0;
          for (var row = 0; row < m; row++) {
            sum -= rows[row][i] * residual[row];
          }
          return sum;
        });
        final expected = _eliminate(normal, rhs);
        final actual = const DenseQrGeometrySolver().solve(
            _dense(rows), residual,
            damping: damping, diagonal: diagonal);
        expect(actual.status, GeometryLinearStatus.converged);
        for (var i = 0; i < n; i++) {
          expect(actual.step[i], closeTo(expected[i], 1e-10));
        }
        expect(actual.relativeResidual, lessThan(1e-10));
      }
    });

    test('projected coordinates match an independent row-space solve', () {
      final random = math.Random(7722);
      for (var sample = 0; sample < 32; sample++) {
        const m = 4, n = 7;
        // The first m columns form the identity, so the row rank is known.
        final rows = List.generate(
            m,
            (i) => List.generate(
                n, (j) => j < m ? (j == i ? 1.0 : 0.0) : random.nextDouble()));
        final vector = Float64List.fromList(
            List.generate(n, (_) => random.nextDouble() * 4 - 2));
        final normal = List.generate(
            m,
            (i) => List.generate(m, (j) {
                  var sum = 0.0;
                  for (var col = 0; col < n; col++) {
                    sum += rows[i][col] * rows[j][col];
                  }
                  return sum;
                }));
        final rhs = List.generate(m, (i) {
          var sum = 0.0;
          for (var col = 0; col < n; col++) {
            sum += rows[i][col] * vector[col];
          }
          return sum;
        });
        final lambda = _eliminate(normal, rhs);
        final result = projectGeometryNullspace(_dense(rows), vector);
        expect(result.status, GeometryLinearStatus.converged);
        expect(result.rank, m);
        for (var col = 0; col < n; col++) {
          var expected = vector[col];
          for (var row = 0; row < m; row++) {
            expected -= rows[row][col] * lambda[row];
          }
          expect(result.vector[col], closeTo(expected, 1e-11));
        }
      }
    });

    test('norm scans and rank work remain cancellable', () {
      final matrix = Float64List(96 * 96);
      for (var i = 0; i < 96; i++) {
        matrix[i * 96 + i] = 1;
      }
      var polls = 0;
      expect(
          geometryRank(matrix, 96, 96, shouldStop: () => ++polls >= 5), isNull);
      expect(polls, 5);
      expect(geometryRank(matrix, 96, 96)!.rank, 96);
    });
  });

  group('dense linear budgets', () {
    final j = _dense([
      [1, 0, 0],
      [0, 2, 0],
      [0, 0, 3],
    ]);
    test('direct QR reports a pivot budget instead of silently exceeding it',
        () {
      for (final budget in [0, 1, 2]) {
        final result = const DenseQrGeometrySolver().solve(
          j,
          Float64List.fromList([1, 2, 3]),
          damping: 0.01,
          diagonal: Float64List.fromList([1, 1, 1]),
          maxIterations: budget,
        );
        expect(result.status, GeometryLinearStatus.iterationLimit);
        expect(result.iterations, lessThanOrEqualTo(budget));
      }
      final complete = const DenseQrGeometrySolver().solve(
        j,
        Float64List.fromList([1, 2, 3]),
        damping: 0.01,
        diagonal: Float64List.fromList([1, 1, 1]),
        maxIterations: 3,
      );
      expect(complete.status, GeometryLinearStatus.converged);
    });

    test('nullspace projection applies the budget on the dense path', () {
      for (final budget in [0, 1, 2]) {
        final result = projectGeometryNullspace(
          j,
          Float64List.fromList([1, 2, 3]),
          maxIterations: budget,
        );
        expect(result.status, GeometryLinearStatus.iterationLimit);
        expect(result.iterations, lessThanOrEqualTo(budget));
      }
    });

    test('small-component solve cannot bypass maxLinearIterations zero', () {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0, 0]),
      ], constraints: [
        GeometryResidualBlock.autoDiff(
          id: 'position',
          parameterIds: ['point'],
          residualCount: 3,
          evaluate: (p) => [p[0][0] - 1, p[0][1] - 2, p[0][2] - 3],
        ),
      ]).compile().createSession();
      final result = session.solve(
          options: const GeometrySolveOptions(maxLinearIterations: 0));
      expect(result.status, GeometrySolveStatus.iterationLimit);
      expect(result.stats.linearIterations, 0);
      expect(session.committedValues, isNull);
      final complete = session.solve();
      expect(complete.isSuccess, isTrue);
      expect(complete.values['point']![0], closeTo(1, 1e-8));
    });
  });

  test('residual-only dual arithmetic has no mutable derivative coordinates',
      () {
    final x = Dual.constant(0.7), y = Dual.constant(1.3);
    final value = x.sin() * y + x.square() / y;
    expect(value.value, closeTo(math.sin(0.7) * 1.3 + 0.49 / 1.3, 1e-14));
    expect(value.derivatives, isEmpty);
    final unit = Dual.normalized([x, y]);
    expect(unit[0].value, closeTo(0.7 / math.sqrt(2.18), 1e-14));
    expect(unit[1].derivatives, isEmpty);
    expect(() => value.derivatives.add(1), throwsUnsupportedError);
    // Active derivatives continue to own independent mutable storage.
    final active = Dual.variable(0.7, 0, 1);
    final derived = active.square();
    derived.derivatives[0] = 42;
    expect(active.derivatives, [1]);
    expect(value.derivatives, isEmpty);
  });
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

SparseGeometryJacobian _rows(int columns, List<List<(int, double)>> rows) {
  final offsets = <int>[0];
  final indices = <int>[];
  final values = <double>[];
  for (final row in rows) {
    for (final (column, value) in row) {
      indices.add(column);
      values.add(value);
    }
    offsets.add(indices.length);
  }
  return SparseGeometryJacobian(
    rows: rows.length,
    columns: columns,
    rowOffsets: Int32List.fromList(offsets),
    columnIndices: Int32List.fromList(indices),
    values: Float64List.fromList(values),
  );
}

SparseGeometryJacobian _dense(List<List<double>> matrix) =>
    _rows(matrix.first.length, [
      for (final row in matrix)
        [
          for (var column = 0; column < row.length; column++)
            if (row[column] != 0) (column, row[column]),
        ],
    ]);

// Independent dense materialization deliberately sums duplicate CSR entries.
List<List<double>> _materialize(SparseGeometryJacobian j) {
  final matrix = List.generate(
    j.rows,
    (_) => List<double>.filled(j.columns, 0),
  );
  for (var row = 0; row < j.rows; row++) {
    for (var entry = j.rowOffsets[row];
        entry < j.rowOffsets[row + 1];
        entry++) {
      matrix[row][j.columnIndices[entry]] += j.values[entry];
    }
  }
  return matrix;
}

// Tiny-system oracle: assemble in dense row order, then use pivoted Gaussian
// elimination, independently of the sparse factorization and production QR.
List<double> _reference(
  SparseGeometryJacobian j,
  Float64List residual,
  double damping,
  Float64List diagonal,
) {
  final dense = _materialize(j);
  final n = j.columns;
  final augmented = List.generate(n, (_) => List<double>.filled(n + 1, 0));
  for (var i = 0; i < n; i++) {
    for (var row = 0; row < j.rows; row++) {
      augmented[i][n] -= dense[row][i] * residual[row];
      for (var k = 0; k < n; k++) {
        augmented[i][k] += dense[row][i] * dense[row][k];
      }
    }
    augmented[i][i] += damping * diagonal[i];
  }
  for (var column = 0; column < n; column++) {
    var pivot = column;
    for (var row = column + 1; row < n; row++) {
      if (augmented[row][column].abs() > augmented[pivot][column].abs()) {
        pivot = row;
      }
    }
    if (augmented[pivot][column] == 0) {
      throw StateError('The reference fixture must be nonsingular.');
    }
    final temporary = augmented[column];
    augmented[column] = augmented[pivot];
    augmented[pivot] = temporary;
    for (var row = column + 1; row < n; row++) {
      final multiplier = augmented[row][column] / augmented[column][column];
      for (var k = column; k <= n; k++) {
        augmented[row][k] -= multiplier * augmented[column][k];
      }
    }
  }
  final answer = List<double>.filled(n, 0);
  for (var row = n - 1; row >= 0; row--) {
    var value = augmented[row][n];
    for (var column = row + 1; column < n; column++) {
      value -= augmented[row][column] * answer[column];
    }
    answer[row] = value / augmented[row][row];
  }
  return answer;
}

double _norm(List<double> values) =>
    math.sqrt(values.fold<double>(0, (sum, value) => sum + value * value));

double _checkedResidual(
  SparseGeometryJacobian j,
  Float64List residual,
  double damping,
  Float64List diagonal,
  Float64List step,
) {
  final dense = _materialize(j);
  final error = List<double>.filled(j.columns, 0);
  final rhs = List<double>.filled(j.columns, 0);
  for (var row = 0; row < j.rows; row++) {
    var value = residual[row];
    for (var column = 0; column < j.columns; column++) {
      value += dense[row][column] * step[column];
    }
    for (var column = 0; column < j.columns; column++) {
      error[column] += dense[row][column] * value;
      rhs[column] += dense[row][column] * residual[row];
    }
  }
  for (var column = 0; column < j.columns; column++) {
    error[column] += damping * diagonal[column] * step[column];
  }
  final initial = _norm(rhs);
  return initial == 0 ? _norm(error) : _norm(error) / initial;
}

GeometryLinearStep _check(
  GeometryLinearSolver solver,
  SparseGeometryJacobian j,
  Float64List residual,
  double damping,
  Float64List diagonal, {
  bool Function()? shouldStop,
}) {
  final expected = _reference(j, residual, damping, diagonal);
  final result = solver.solve(
    j,
    residual,
    damping: damping,
    diagonal: diagonal,
    relativeTolerance: 1e-10,
    shouldStop: shouldStop,
  );
  expect(result.status, GeometryLinearStatus.converged);
  expect(result.step.every((value) => value.isFinite), isTrue);
  expect(result.relativeResidual, lessThanOrEqualTo(1e-10));
  expect(
    _checkedResidual(j, residual, damping, diagonal, result.step),
    lessThanOrEqualTo(1e-10),
  );
  for (var column = 0; column < j.columns; column++) {
    expect(
      result.step[column],
      closeTo(expected[column], 1e-9 * math.max(1, expected[column].abs())),
      reason: 'coordinate $column',
    );
  }
  return result;
}

SparseGeometryJacobian _chain(int columns) => _rows(columns, [
      [(0, 1.0)],
      for (var column = 1; column < columns; column++)
        [(column - 1, -1.0), (column, 1.0)],
    ]);

void main() {
  group('sparse LDLT original-system correctness', () {
    test(
      'matches independent tiny dense solutions with nonuniform damping',
      () {
        final random = math.Random(20261114);
        for (var size = 1; size <= 7; size++) {
          for (var variant = 0; variant < 3; variant++) {
            final matrix = [
              for (var row = 0; row < size + variant + 1; row++)
                [
                  for (var column = 0; column < size; column++)
                    if (random.nextInt(4) == 0)
                      0.0
                    else
                      random.nextDouble() * 4 - 2,
                ],
            ];
            _check(
              const SparseLdltGeometrySolver(),
              _dense(matrix),
              Float64List.fromList([
                for (var row = 0; row < matrix.length; row++)
                  random.nextDouble() * 2 - 1,
              ]),
              .03 + variant * .1,
              Float64List.fromList([
                for (var column = 0; column < size; column++) 1 + column * .25,
              ]),
            );
          }
        }
      },
    );

    test(
      'unsorted duplicates include diagonal cross terms and cancellation',
      () {
        final j = _rows(3, [
          [(2, .5), (0, 1.0), (2, -.5), (0, 2.0), (1, -1.0)],
          [(1, 2.0), (0, -.4), (1, -.7), (2, 3.0)],
          [(2, 1.0), (0, 2.0), (2, 2.0), (1, .25)],
        ]);
        _check(
          const SparseLdltGeometrySolver(),
          j,
          Float64List.fromList([.7, -.2, 1.3]),
          .02,
          Float64List.fromList([1, 3, 2]),
        );
      },
    );

    test('129 linked coordinates solve within one factorization budget', () {
      const columns = 129;
      final j = _chain(columns);
      final expected = [
        for (var i = 0; i < columns; i++) math.sin(i * .13) + .003 * i,
      ];
      final residual = Float64List.fromList([
        -expected.first,
        for (var i = 1; i < columns; i++) expected[i - 1] - expected[i],
      ]);
      final diagonal = Float64List.fromList(List.filled(columns, 1.0));
      final result = const SparseLdltGeometrySolver().solve(
        j,
        residual,
        damping: 0,
        diagonal: diagonal,
        maxIterations: 1,
      );
      expect(result.status, GeometryLinearStatus.converged);
      expect(result.iterations, 1);
      expect(
        _checkedResidual(j, residual, 0, diagonal, result.step),
        lessThan(1e-8),
      );
      for (var i = 0; i < columns; i++) {
        expect(result.step[i], closeTo(expected[i], 1e-8));
      }
    });

    test('value changes and zero crossings do not reuse numeric factors', () {
      const solver = SparseLdltGeometrySolver();
      final j = _dense([
        [1, 2, 0],
        [0, 3, -1],
        [2, 0, 4],
      ]);
      final residual = Float64List.fromList([1, -.3, .4]);
      final diagonal = Float64List.fromList([2, 3, 4]);
      final first = _check(solver, j, residual, .1, diagonal);
      final firstSnapshot = first.step.toList();
      j.values[0] = 0;
      j.values[3] = 2.5;
      residual[1] = 1.2;
      diagonal[2] = .7;
      _check(solver, j, residual, .003, diagonal);
      j.values[0] = -2;
      _check(solver, j, residual, .03, diagonal);
      expect(
        first.step,
        firstSnapshot,
        reason: 'later solves must not mutate a returned step',
      );
    });

    test('same-object CSR column and row-boundary mutations are respected', () {
      const solver = SparseLdltGeometrySolver();
      final j = _rows(4, [
        [(0, 1.0), (1, 2.0)],
        [(1, 3.0), (2, -.5)],
        [(2, 2.0), (3, 4.0)],
        [(0, 1.5)],
      ]);
      final residual = Float64List.fromList([.3, -.2, .7, 1.1]);
      final diagonal = Float64List.fromList([1, 2, 3, 4]);
      _check(solver, j, residual, .03, diagonal);
      j.columnIndices[1] = 3;
      _check(solver, j, residual, .03, diagonal);
      j.rowOffsets[1] = 1;
      _check(solver, j, residual, .03, diagonal);
    });
  });

  group('sparse LDLT bounded work', () {
    final j = _dense([
      [1, 2, 3, 4],
      [2, -1, .5, 3],
      [4, 3, 2, 1],
      [.5, 1, -2, 3],
    ]);
    final residual = Float64List.fromList([1, .2, -.3, .7]);
    final diagonal = Float64List.fromList([1, 2, 3, 4]);

    test('zero budget cannot perform a factorization', () {
      final result = const SparseLdltGeometrySolver().solve(
        j,
        residual,
        damping: .1,
        diagonal: diagonal,
        maxIterations: 0,
      );
      expect(result.status, GeometryLinearStatus.iterationLimit);
      expect(result.iterations, 0);
    });

    const limited = <String, SparseLdltGeometrySolver>{
      'columns': SparseLdltGeometrySolver(maxColumns: 1),
      'factor entries': SparseLdltGeometrySolver(maxFactorEntries: 1),
      'symbolic work': SparseLdltGeometrySolver(maxSymbolicWork: 1),
      'numeric work': SparseLdltGeometrySolver(maxNumericWork: 1),
      'assembly work': SparseLdltGeometrySolver(maxAssemblyWork: 1),
    };
    for (final entry in limited.entries) {
      test('${entry.key} cap applies even after a permissive cached solve', () {
        _check(const SparseLdltGeometrySolver(), j, residual, .1, diagonal);
        final result = entry.value.solve(
          j,
          residual,
          damping: .1,
          diagonal: diagonal,
        );
        expect(result.status, GeometryLinearStatus.iterationLimit);
        expect(result.iterations, 0);
        _check(const SparseLdltGeometrySolver(), j, residual, .1, diagonal);
      });
    }

    test('raw duplicate row work is capped despite a one-vertex graph', () {
      final duplicates = _rows(1, [
        [for (var i = 0; i < 40; i++) (0, 1.0)],
      ]);
      final result = const SparseLdltGeometrySolver(maxAssemblyWork: 100).solve(
        duplicates,
        Float64List.fromList([1]),
        damping: .01,
        diagonal: Float64List.fromList([1]),
      );
      expect(result.status, GeometryLinearStatus.iterationLimit);
      expect(result.iterations, 0);
    });

    test('cancellation is reported at entry and during bounded processing', () {
      final linked = _chain(96);
      final r = Float64List.fromList(List.filled(96, 1.0));
      final d = Float64List.fromList(List.filled(96, 1.0));
      for (final stopAt in [1, 2, 10, 50]) {
        var polls = 0;
        final result = const SparseLdltGeometrySolver().solve(
          linked,
          r,
          damping: .01,
          diagonal: d,
          maxIterations: 1,
          shouldStop: () => ++polls >= stopAt,
        );
        expect(
          result.status,
          GeometryLinearStatus.cancelled,
          reason: 'stop after $stopAt callback polls',
        );
        expect(result.iterations, lessThanOrEqualTo(1));
        expect(polls, greaterThanOrEqualTo(stopAt));
      }
    });
  });

  group('sparse LDLT failure and ownership contracts', () {
    test('invalid vector lengths and negative budgets reject the invocation',
        () {
      final j = _chain(3);
      final residual = Float64List.fromList([1, 2, 3]);
      final diagonal = Float64List.fromList([1, 1, 1]);
      expect(
          () => const SparseLdltGeometrySolver().solve(
              j, Float64List.fromList([1, 2]),
              damping: .1, diagonal: diagonal),
          throwsArgumentError);
      expect(
          () => const SparseLdltGeometrySolver().solve(j, residual,
              damping: .1, diagonal: Float64List.fromList([1, 1])),
          throwsArgumentError);
      expect(
          () => const SparseLdltGeometrySolver().solve(j, residual,
              damping: .1, diagonal: diagonal, maxIterations: -1),
          throwsArgumentError);
    });

    test('a nonpositive undamped pivot cannot report convergence', () {
      final result = const SparseLdltGeometrySolver().solve(
        _dense([
          [1, 1],
        ]),
        Float64List.fromList([1]),
        damping: 0,
        diagonal: Float64List.fromList([1, 1]),
        maxIterations: 1,
      );
      expect(result.status, GeometryLinearStatus.numericalFailure);
      expect(result.iterations, lessThanOrEqualTo(1));
    });

    for (final invalid in [
      'nan Jacobian',
      'infinite Jacobian',
      'nan residual',
      'nan diagonal',
      'negative diagonal',
      'negative damping',
      'nan damping',
      'infinite damping',
      'zero tolerance',
      'nan tolerance',
      'infinite tolerance',
      'overflowing normal product',
    ]) {
      test('$invalid is not accepted as a converged linear step', () {
        final j = _dense([
          [1, .3],
          [.4, 2],
        ]);
        final residual = Float64List.fromList([1, -.2]);
        final diagonal = Float64List.fromList([1, 1]);
        var damping = .1;
        var tolerance = 1e-8;
        switch (invalid) {
          case 'nan Jacobian':
            j.values[0] = double.nan;
          case 'infinite Jacobian':
            j.values[0] = double.infinity;
          case 'nan residual':
            residual[0] = double.nan;
          case 'nan diagonal':
            diagonal[0] = double.nan;
          case 'negative diagonal':
            diagonal[0] = -1;
          case 'negative damping':
            damping = -1;
          case 'nan damping':
            damping = double.nan;
          case 'infinite damping':
            damping = double.infinity;
          case 'zero tolerance':
            tolerance = 0;
          case 'nan tolerance':
            tolerance = double.nan;
          case 'infinite tolerance':
            tolerance = double.infinity;
          case 'overflowing normal product':
            j.values[0] = 1e308;
        }
        if (invalid.endsWith('tolerance')) {
          expect(
              () => const SparseLdltGeometrySolver().solve(j, residual,
                  damping: damping,
                  diagonal: diagonal,
                  relativeTolerance: tolerance),
              throwsArgumentError);
        } else {
          final result = const SparseLdltGeometrySolver().solve(j, residual,
              damping: damping,
              diagonal: diagonal,
              relativeTolerance: tolerance);
          expect(result.status, GeometryLinearStatus.numericalFailure);
        }
      });
    }

    test(
      'reentrant solves through shouldStop do not share numeric workspace',
      () {
        const solver = SparseLdltGeometrySolver();
        final j = _dense([
          [1, .2, -.3, .1],
          [.4, 2, .5, -.2],
          [.3, -.4, 3, .7],
          [.1, .2, .3, 4],
          [-.4, .3, .5, .2],
        ]);
        final outerResidual = Float64List.fromList([1, -.2, .3, -.4, .5]);
        final innerResidual = Float64List.fromList([-.2, .3, -.4, .5, -.6]);
        final diagonal = Float64List.fromList([1, 2, 3, 4]);
        _check(solver, j, outerResidual, .03, diagonal);
        var nestedSolves = 0;
        for (final trigger in [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]) {
          var polls = 0;
          var reentered = false;
          _check(
            solver,
            j,
            outerResidual,
            .03,
            diagonal,
            shouldStop: () {
              polls++;
              if (!reentered && polls == trigger) {
                reentered = true;
                nestedSolves++;
                _check(solver, j, innerResidual, .2, diagonal);
              }
              return false;
            },
          );
        }
        expect(nestedSolves, greaterThanOrEqualTo(3));
      },
    );
  });

  group('adaptive sparse fallback budgets', () {
    test('a structural decline leaves the complete CG budget available', () {
      final j = _dense([
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
      ]);
      final result = const AdaptiveGeometryLinearSolver(
              denseParameterLimit: 0,
              sparseParameterThreshold: 0,
              sparseDirectSolver: SparseLdltGeometrySolver(maxColumns: 1))
          .solve(j, Float64List.fromList([1, 2, 3]),
              damping: .1,
              diagonal: Float64List.fromList([1, 1, 1]),
              maxIterations: 1);
      expect(result.status, GeometryLinearStatus.converged);
      expect(result.iterations, 1);
      for (var i = 0; i < 3; i++) {
        expect(result.step[i], closeTo(-(i + 1) / 1.1, 1e-12));
      }
    });

    test('a failed direct factor and successful CG share the supplied budget',
        () {
      final j = _dense([
        [1, 1],
      ]);
      final residual = Float64List.fromList([1]);
      final diagonal = Float64List.fromList([1, 1]);
      const solver = AdaptiveGeometryLinearSolver(
          denseParameterLimit: 0, sparseParameterThreshold: 0);
      final exhausted = solver.solve(j, residual,
          damping: 0, diagonal: diagonal, maxIterations: 1);
      expect(exhausted.status, isNot(GeometryLinearStatus.converged));
      expect(exhausted.iterations, 1);
      final result = solver.solve(j, residual,
          damping: 0, diagonal: diagonal, maxIterations: 2);
      expect(result.status, GeometryLinearStatus.converged);
      expect(result.iterations, 2);
      expect(_checkedResidual(j, residual, 0, diagonal, result.step),
          lessThan(1e-12));
    });

    test('the default moderate-size path preserves the existing CG budget', () {
      final j = _chain(96);
      final residual = Float64List.fromList(List.filled(96, 1.0));
      final diagonal = Float64List.fromList(List.filled(96, 1.0));
      final expected = const SparseCgGeometrySolver().solve(j, residual,
          damping: .01, diagonal: diagonal, maxIterations: 1);
      final result = const AdaptiveGeometryLinearSolver().solve(j, residual,
          damping: .01, diagonal: diagonal, maxIterations: 1);
      expect(expected.status, GeometryLinearStatus.iterationLimit);
      expect(result.status, expected.status);
      expect(result.iterations, expected.iterations);
      expect(result.step, expected.step);
    });

    test('a cancellation is terminal on the forced sparse path', () {
      final j = _chain(96);
      var polls = 0;
      final result = const AdaptiveGeometryLinearSolver(
              denseParameterLimit: 0, sparseParameterThreshold: 0)
          .solve(j, Float64List.fromList(List.filled(96, 1.0)),
              damping: .1,
              diagonal: Float64List.fromList(List.filled(96, 1.0)),
              maxIterations: 1, shouldStop: () {
        polls++;
        return true;
      });
      expect(result.status, GeometryLinearStatus.cancelled);
      expect(result.iterations, 0);
      expect(polls, greaterThanOrEqualTo(1));
    });
  });
}

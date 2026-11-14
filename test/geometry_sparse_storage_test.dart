import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

// Identity rows let us prescribe the answer even with nonuniform damping.
// The remaining rows produce irregular fill, duplicate entries and structural
// zeroes. No factorization or production matrix-vector helper is used as an
// oracle.
class _Fixture {
  _Fixture(this.jacobian, this.anchors);

  final SparseGeometryJacobian jacobian;
  final List<int> anchors;
}

_Fixture _fixture(int columns, {Set<int> emptyColumns = const {}}) {
  final rows = <List<(int, double)>>[];
  final anchors = List<int>.filled(columns, -1);
  for (var column = 0; column < columns; column++) {
    if (emptyColumns.contains(column)) continue;
    anchors[column] = rows.length;
    rows.add([(column, 1.0)]);
  }
  final active = [
    for (var column = 0; column < columns; column++)
      if (!emptyColumns.contains(column)) column,
  ];
  final vertices = [
    for (var i = 0; i < 8; i++) active[i * (active.length - 1) ~/ 7],
  ];
  const edges = [
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (4, 5),
    (5, 6),
    (6, 7),
    (7, 0),
    (0, 3),
    (2, 5),
    (1, 6),
  ];
  for (var i = 0; i < edges.length; i++) {
    final (a, b) = edges[i];
    rows.add([(vertices[b], .25 + i / 32), (vertices[a], -.5)]);
  }
  rows.add([
    (vertices[7], .3),
    (vertices[2], -.2),
    (vertices[5], .6),
  ]);
  rows.add([
    (vertices[6], .4),
    (vertices[2], -.3),
    (vertices[6], -.4),
    (vertices[0], 0),
  ]);
  rows.add([]);
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
  return _Fixture(
    SparseGeometryJacobian(
      rows: rows.length,
      columns: columns,
      rowOffsets: Int32List.fromList(offsets),
      columnIndices: Int32List.fromList(indices),
      values: Float64List.fromList(values),
    ),
    anchors,
  );
}

Float64List _answer(_Fixture fixture, [int variant = 0]) =>
    Float64List.fromList([
      for (var column = 0; column < fixture.jacobian.columns; column++)
        if (fixture.anchors[column] < 0)
          0
        else
          ((column * 11 + variant * 7) % 23 - 11) / 8,
    ]);

Float64List _diagonal(int columns) => Float64List.fromList([
      for (var column = 0; column < columns; column++) .5 + (column % 7) / 4,
    ]);

Float64List _residualFor(_Fixture fixture, Float64List expected, double damping,
    Float64List diagonal) {
  final j = fixture.jacobian;
  final residual = Float64List(j.rows);
  for (var row = 0; row < j.rows; row++) {
    for (var k = j.rowOffsets[row]; k < j.rowOffsets[row + 1]; k++) {
      residual[row] -= j.values[k] * expected[j.columnIndices[k]];
    }
  }
  for (var column = 0; column < j.columns; column++) {
    final anchor = fixture.anchors[column];
    if (anchor >= 0) {
      residual[anchor] -= damping * diagonal[column] * expected[column];
    }
  }
  // An empty Jacobian row must have no influence on the normal system.
  residual.last = 17;
  return residual;
}

void _verify(
  GeometryLinearStep result,
  _Fixture fixture,
  Float64List residual,
  Float64List expected,
  double damping,
  Float64List diagonal,
) {
  expect(result.status, GeometryLinearStatus.converged);
  expect(result.iterations, 1);
  expect(result.relativeResidual, lessThanOrEqualTo(1e-10));
  final j = fixture.jacobian;
  final dense = List.generate(j.rows, (_) => List<double>.filled(j.columns, 0));
  for (var row = 0; row < j.rows; row++) {
    for (var k = j.rowOffsets[row]; k < j.rowOffsets[row + 1]; k++) {
      dense[row][j.columnIndices[k]] += j.values[k];
    }
  }
  final error = List<double>.filled(j.columns, 0);
  final rhs = List<double>.filled(j.columns, 0);
  for (var row = 0; row < j.rows; row++) {
    var projected = residual[row];
    for (var column = 0; column < j.columns; column++) {
      projected += dense[row][column] * result.step[column];
    }
    for (var column = 0; column < j.columns; column++) {
      error[column] += dense[row][column] * projected;
      rhs[column] -= dense[row][column] * residual[row];
    }
  }
  var squaredError = 0.0, squaredRhs = 0.0;
  for (var column = 0; column < j.columns; column++) {
    error[column] += damping * diagonal[column] * result.step[column];
    squaredError += error[column] * error[column];
    squaredRhs += rhs[column] * rhs[column];
    expect(result.step[column], closeTo(expected[column], 2e-10),
        reason: 'coordinate $column');
  }
  expect(math.sqrt(squaredError / squaredRhs), lessThanOrEqualTo(1e-10),
      reason: 'independently evaluated original normal equation');
}

GeometryLinearStep _solveKnown(_Fixture fixture, Float64List expected,
    double damping, Float64List diagonal,
    {bool Function()? shouldStop}) {
  final residual = _residualFor(fixture, expected, damping, diagonal);
  final result = const SparseLdltGeometrySolver().solve(
    fixture.jacobian,
    residual,
    damping: damping,
    diagonal: diagonal,
    maxIterations: 1,
    relativeTolerance: 1e-10,
    shouldStop: shouldStop,
  );
  _verify(result, fixture, residual, expected, damping, diagonal);
  return result;
}

void main() {
  group('sparse factor storage boundaries', () {
    for (final columns in [19, 257]) {
      test('irregular filled columns preserve a known $columns-coordinate step',
          () {
        final fixture = _fixture(columns);
        _solveKnown(fixture, _answer(fixture), .125, _diagonal(columns));
      });
    }

    test('empty columns and zero-valued edges keep independent diagonal slots',
        () {
      final fixture = _fixture(19, emptyColumns: {0, 9, 18});
      final result =
          _solveKnown(fixture, _answer(fixture), .375, _diagonal(19));
      for (final empty in [0, 9, 18]) {
        expect(fixture.jacobian.columnIndices, isNot(contains(empty)));
        expect(result.step[empty], 0);
      }
    });

    test('warm numeric changes leave earlier packed-factor results untouched',
        () {
      final fixture = _fixture(19, emptyColumns: {0, 9, 18});
      final j = fixture.jacobian;
      final originalValues = j.values.toList();
      final diagonal = _diagonal(19);
      final results = <GeometryLinearStep>[];
      final snapshots = <List<double>>[];
      final firstExtra =
          j.rowOffsets[fixture.anchors.where((r) => r >= 0).length];
      for (var variant = 0; variant < 4; variant++) {
        // Identity rows stay fixed; all later entries change, including exact
        // duplicate cancellation and zero-to-nonzero structural edges.
        for (var k = firstExtra; k < j.values.length; k++) {
          j.values[k] = variant == 1
              ? 0
              : originalValues[k] * (1 - variant) +
                  (variant == 3 ? (k % 3 - 1) / 16 : 0);
        }
        for (var column = 0; column < j.columns; column++) {
          diagonal[column] = .25 + ((column + variant) % 9) / 4;
        }
        final result = _solveKnown(fixture, _answer(fixture, variant),
            [.125, .25, 1.0, .015625][variant], diagonal);
        results.add(result);
        snapshots.add(result.step.toList());
      }
      for (var i = 0; i < results.length; i++) {
        expect(results[i].step, snapshots[i],
            reason: 'result $i must own its numeric storage');
      }
    });

    test('nested solves at every warm callback boundary preserve both answers',
        () {
      final fixture = _fixture(19, emptyColumns: {0, 9, 18});
      final outer = _answer(fixture);
      final inner = _answer(fixture, 2);
      final diagonal = _diagonal(19);
      _solveKnown(fixture, outer, .125, diagonal);
      var boundaryCount = 0;
      _solveKnown(fixture, outer, .125, diagonal, shouldStop: () {
        boundaryCount++;
        return false;
      });
      expect(boundaryCount, greaterThan(19 * 3));
      for (var trigger = 1; trigger <= boundaryCount; trigger++) {
        var polls = 0;
        GeometryLinearStep? nested;
        List<double>? nestedSnapshot;
        final result =
            _solveKnown(fixture, outer, .125, diagonal, shouldStop: () {
          if (++polls == trigger) {
            nested = _solveKnown(fixture, inner, .75, diagonal);
            nestedSnapshot = nested!.step.toList();
          }
          return false;
        });
        expect(polls, boundaryCount);
        expect(nested, isNotNull, reason: 'callback boundary $trigger');
        expect(nested!.step, nestedSnapshot,
            reason: 'outer solve must not overwrite the nested result');
        expect(identical(result.step, nested!.step), isFalse);
      }
    });

    test('cancelling each warm callback leaves later numeric factors usable',
        () {
      final fixture = _fixture(19, emptyColumns: {0, 9, 18});
      final expected = _answer(fixture);
      final diagonal = _diagonal(19);
      final residual = _residualFor(fixture, expected, .125, diagonal);
      final previous = _solveKnown(fixture, expected, .125, diagonal);
      final previousSnapshot = previous.step.toList();
      var boundaryCount = 0;
      _solveKnown(fixture, expected, .125, diagonal, shouldStop: () {
        boundaryCount++;
        return false;
      });
      for (var trigger = 1; trigger <= boundaryCount; trigger++) {
        var polls = 0;
        final cancelled = const SparseLdltGeometrySolver().solve(
          fixture.jacobian,
          residual,
          damping: .125,
          diagonal: diagonal,
          maxIterations: 1,
          relativeTolerance: 1e-10,
          shouldStop: () => ++polls == trigger,
        );
        expect(cancelled.status, GeometryLinearStatus.cancelled,
            reason: 'callback boundary $trigger');
        expect(polls, trigger);
        expect(cancelled.iterations, lessThanOrEqualTo(1));
        final snapshot = cancelled.step.toList();
        _solveKnown(fixture, _answer(fixture, 1), .5, diagonal);
        expect(cancelled.step, snapshot);
        expect(previous.step, previousSnapshot);
      }
    });
  });
}

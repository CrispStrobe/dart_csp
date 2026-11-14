import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

SparseGeometryJacobian _matrix(int columns, List<List<(int, double)>> rows) {
  final offsets = <int>[0];
  final indices = <int>[];
  final values = <double>[];
  for (final row in rows) {
    for (final (column, value) in row) {
      indices.add(column);
      values.add(value);
    }
    offsets.add(values.length);
  }
  return SparseGeometryJacobian(
    rows: rows.length,
    columns: columns,
    rowOffsets: Int32List.fromList(offsets),
    columnIndices: Int32List.fromList(indices),
    values: Float64List.fromList(values),
  );
}

SparseGeometryJacobian _smallChain() => _matrix(3, [
      [(0, 1.0)],
      [(0, -1.0), (1, 1.0)],
      [(1, -1.0), (2, 1.0)],
    ]);

SparseGeometryJacobian _largeChain() => _matrix(256, [
      [(0, 1.0)],
      for (var column = 1; column < 256; column++)
        [(column - 1, -1.0), (column, 1.0)],
    ]);

SparseGeometryJacobian _highFill() => _matrix(256, [
      for (var column = 0; column < 256; column++) [(column, 1.0)],
      [for (var column = 0; column < 64; column++) (column, 1.0)],
    ]);

void main() {
  group('current CSR validation after cached solves', () {
    final corruptions = <String, void Function(SparseGeometryJacobian)>{
      'nonzero first row offset': (j) => j.rowOffsets[0] = 1,
      'negative interior row offset': (j) => j.rowOffsets[1] = -1,
      'decreasing interior row offsets': (j) {
        j.rowOffsets[1] = 3;
        j.rowOffsets[2] = 2;
      },
      'row end beyond values': (j) => j.rowOffsets[2] = j.values.length + 1,
      'final row offset mismatch': (j) => j.rowOffsets[3]--,
      'negative column index': (j) => j.columnIndices[1] = -1,
      'column index at column count': (j) => j.columnIndices[1] = j.columns,
    };

    for (final corruption in corruptions.entries) {
      test(corruption.key, () {
        final jacobian = _smallChain();
        final residual = Float64List.fromList([1, 2, 3]);
        final diagonal = Float64List.fromList([1, 1, 1]);
        const solver = SparseLdltGeometrySolver();
        final first =
            solver.solve(jacobian, residual, damping: .1, diagonal: diagonal);
        expect(first.status, GeometryLinearStatus.converged);

        final offsets = Int32List.fromList(jacobian.rowOffsets);
        final columns = Int32List.fromList(jacobian.columnIndices);
        corruption.value(jacobian);
        expect(
          () =>
              solver.solve(jacobian, residual, damping: .1, diagonal: diagonal),
          throwsArgumentError,
          reason: 'a cached valid pattern cannot hide malformed caller arrays',
        );

        jacobian.rowOffsets.setAll(0, offsets);
        jacobian.columnIndices.setAll(0, columns);
        final restored =
            solver.solve(jacobian, residual, damping: .1, diagonal: diagonal);
        expect(restored.status, GeometryLinearStatus.converged);
        expect(restored.step, first.step,
            reason: 'failed validation must not poison the valid shape cache');
      });
    }

    test('a cached structural decline is reconsidered after valid CSR edits',
        () {
      const columns = 6;
      final jacobian = _matrix(columns, [
        for (var row = 0; row < columns; row++)
          [
            (row, 1.0),
            ((row + 1) % columns, .5),
            ((row + 2) % columns, -.25),
          ],
      ]);
      final residual = Float64List.fromList([1, 2, 3, 4, 5, 6]);
      final diagonal = Float64List.fromList(List.filled(columns, 1.0));
      const solver = SparseLdltGeometrySolver(maxNumericWork: 0);

      for (var repetition = 0; repetition < 2; repetition++) {
        final declined = solver.solve(jacobian, residual,
            damping: .1, diagonal: diagonal, maxIterations: 1);
        expect(declined.status, GeometryLinearStatus.iterationLimit);
        expect(declined.iterations, 0);
      }

      // Preserve all array identities and lengths, but remove every graph edge.
      // Each row becomes a diagonal entry 1 + .5 - .25 = 1.25, represented by
      // three duplicates. There are no Schur updates for this diagonal system.
      for (var row = 0; row < columns; row++) {
        for (var k = jacobian.rowOffsets[row];
            k < jacobian.rowOffsets[row + 1];
            k++) {
          jacobian.columnIndices[k] = row;
        }
      }
      final result = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(result.status, GeometryLinearStatus.converged);
      expect(result.iterations, 1);
      for (var column = 0; column < columns; column++) {
        expect(result.step[column],
            closeTo(-1.25 * residual[column] / (1.25 * 1.25 + .1), 1e-12));
      }
    });
  });

  group('exact structural work boundaries', () {
    test('a four-column clique requires ten Schur updates', () {
      final jacobian = _matrix(4, [
        for (var column = 0; column < 4; column++) [(column, 1.0)],
        [(0, 1.0), (1, 1.0), (2, 1.0), (3, 1.0)],
      ]);
      final residual = Float64List.fromList([0, 0, 0, 0, 1]);
      final diagonal = Float64List.fromList([1, 1, 1, 1]);
      final declined = const SparseLdltGeometrySolver(maxNumericWork: 9).solve(
          jacobian, residual,
          damping: .5, diagonal: diagonal, maxIterations: 1);
      expect(declined.status, GeometryLinearStatus.iterationLimit);
      expect(declined.iterations, 0);

      final accepted = const SparseLdltGeometrySolver(maxNumericWork: 10).solve(
          jacobian, residual,
          damping: .5, diagonal: diagonal, maxIterations: 1);
      expect(accepted.status, GeometryLinearStatus.converged);
      expect(accepted.iterations, 1);
      // J'J + .5 I = 1.5 I + 11', while -J'r = -1. This gives an
      // independent closed-form solution, without reconstructing the factor.
      for (final value in accepted.step) {
        expect(value, closeTo(-1 / 5.5, 1e-12));
      }
    });

    test('zero right-hand side and empty columns obey finite-data checks', () {
      final empty = _matrix(0, [<(int, double)>[]]);
      final emptyResult = const SparseLdltGeometrySolver().solve(
        empty,
        Float64List.fromList([2]),
        damping: .1,
        diagonal: Float64List(0),
      );
      expect(emptyResult.status, GeometryLinearStatus.converged);
      expect(emptyResult.iterations, 0);
      expect(emptyResult.step, isEmpty);

      final jacobian = _smallChain();
      final residual = Float64List(3);
      final diagonal = Float64List.fromList([1, 1, 1]);
      final valid = const SparseLdltGeometrySolver()
          .solve(jacobian, residual, damping: .1, diagonal: diagonal);
      expect(valid.status, GeometryLinearStatus.converged);
      expect(valid.iterations, 0);
      jacobian.values[0] = double.nan;
      final invalid = const SparseLdltGeometrySolver()
          .solve(jacobian, residual, damping: .1, diagonal: diagonal);
      expect(invalid.status, GeometryLinearStatus.numericalFailure);
      expect(invalid.iterations, 0);
    });

    test('cancellation during the final residual check remains terminal', () {
      const columns = 200;
      final jacobian = _matrix(columns, [
        [(0, 1.0)],
        for (var column = 1; column < columns; column++)
          [(column - 1, -1.0), (column, 1.0)],
      ]);
      final residual = Float64List.fromList(List.filled(columns, 1.0));
      final diagonal = Float64List.fromList(List.filled(columns, 1.0));
      const solver = SparseLdltGeometrySolver();
      final warm = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(warm.status, GeometryLinearStatus.converged);

      var completedPolls = 0;
      final counted = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1, shouldStop: () {
        completedPolls++;
        return false;
      });
      expect(counted.status, GeometryLinearStatus.converged);
      expect(completedPolls, greaterThan(2));

      // The cached shape and unchanged data give the same deterministic path.
      // The final explicit poll follows residual verification; its preceding
      // periodic poll is inside that verification for this 200-column matrix.
      var cancelledPolls = 0;
      final cancelled = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1, shouldStop: () {
        cancelledPolls++;
        return cancelledPolls >= completedPolls - 1;
      });
      expect(cancelled.status, GeometryLinearStatus.cancelled);
      expect(cancelled.iterations, 1);
      expect(cancelledPolls, completedPolls - 1);
      final recovered = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(recovered.status, GeometryLinearStatus.converged);
      expect(recovered.step, counted.step);
    });
  });

  group('adaptive factor-work policy', () {
    test('default rejects expensive fill and preserves the complete CG budget',
        () {
      final jacobian = _highFill();
      final residual = Float64List(jacobian.rows)..[0] = 1;
      final diagonal = Float64List.fromList(List.filled(jacobian.columns, 1.0));
      final cg = const SparseCgGeometrySolver().solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(cg.status, GeometryLinearStatus.iterationLimit);

      final adaptive = const AdaptiveGeometryLinearSolver().solve(
          jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(adaptive.status, cg.status);
      expect(adaptive.iterations, cg.iterations);
      expect(adaptive.step, cg.step);
      expect(adaptive.relativeResidual, cg.relativeResidual);
    });

    test(
        'looser and stricter policies reconsider both decline and factor caches',
        () {
      final jacobian = _highFill();
      final residual = Float64List(jacobian.rows)..[0] = 1;
      final diagonal = Float64List.fromList(List.filled(jacobian.columns, 1.0));
      const defaultPolicy = AdaptiveGeometryLinearSolver();
      const disabledPolicy =
          AdaptiveGeometryLinearSolver(sparseNumericWorkPerNonzero: null);
      const relaxedPolicy =
          AdaptiveGeometryLinearSolver(sparseNumericWorkPerNonzero: 200);

      GeometryLinearStep solve(GeometryLinearSolver solver) => solver.solve(
            jacobian,
            residual,
            damping: .1,
            diagonal: diagonal,
            maxIterations: 1,
          );

      expect(solve(defaultPolicy).status, GeometryLinearStatus.iterationLimit);
      for (final solver in <GeometryLinearSolver>[
        disabledPolicy,
        defaultPolicy,
        relaxedPolicy,
        defaultPolicy,
        const SparseLdltGeometrySolver(),
        defaultPolicy,
      ]) {
        final result = solve(solver);
        expect(result.iterations, 1);
        if (identical(solver, defaultPolicy)) {
          expect(result.status, GeometryLinearStatus.iterationLimit);
        } else {
          expect(result.status, GeometryLinearStatus.converged);
          // A = 1.1 I + vv', where v is one in the first 64 coordinates.
          // Sherman-Morrison gives this solution for A x = -e_0.
          for (var column = 0; column < jacobian.columns; column++) {
            final expected = column < 64
                ? (column == 0 ? -1 / 1.1 : 0) + 1 / (1.1 * 65.1)
                : 0.0;
            expect(result.step[column], closeTo(expected, 1e-11));
          }
        }
      }
    });

    test('low-fill chain stays eligible under the default automatic cap', () {
      final jacobian = _largeChain();
      final residual = Float64List(jacobian.rows)..[0] = -1;
      final diagonal = Float64List.fromList(List.filled(jacobian.columns, 1.0));
      final result = const AdaptiveGeometryLinearSolver().solve(
          jacobian, residual,
          damping: 0, diagonal: diagonal, maxIterations: 1);
      expect(result.status, GeometryLinearStatus.converged);
      expect(result.iterations, 1);
      for (final value in result.step) {
        expect(value, closeTo(1, 1e-10));
      }
    });

    test('zero multiplier permits diagonal factors but declines linked factors',
        () {
      const solver =
          AdaptiveGeometryLinearSolver(sparseNumericWorkPerNonzero: 0);
      final diagonalJacobian = _matrix(256, [
        for (var column = 0; column < 256; column++) [(column, 1.0)],
      ]);
      final residual = Float64List.fromList(List.filled(256, 1.0));
      final diagonal = Float64List.fromList(List.filled(256, 1.0));
      final diagonalResult = solver.solve(diagonalJacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(diagonalResult.status, GeometryLinearStatus.converged);
      expect(diagonalResult.iterations, 1);
      for (final value in diagonalResult.step) {
        expect(value, closeTo(-1 / 1.1, 1e-12));
      }

      final linkedJacobian = _largeChain();
      final cg = const SparseCgGeometrySolver().solve(linkedJacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      final linked = solver.solve(linkedJacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(cg.status, GeometryLinearStatus.iterationLimit);
      expect(linked.status, cg.status);
      expect(linked.iterations, cg.iterations);
      expect(linked.step, cg.step);
    });

    test('disabling automatic cap preserves explicit direct resource limits',
        () {
      final jacobian = _highFill();
      final residual = Float64List(jacobian.rows)..[0] = 1;
      final diagonal = Float64List.fromList(List.filled(jacobian.columns, 1.0));
      const solver = AdaptiveGeometryLinearSolver(
        sparseNumericWorkPerNonzero: null,
        sparseDirectSolver: SparseLdltGeometrySolver(maxNumericWork: 1024),
      );
      final cg = const SparseCgGeometrySolver().solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      final result = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(result.status, cg.status);
      expect(result.iterations, cg.iterations);
      expect(result.step, cg.step);
    });

    test('very large multiplier saturates at explicit cap without overflow',
        () {
      final jacobian = _highFill();
      final residual = Float64List(jacobian.rows)..[0] = 1;
      final diagonal = Float64List.fromList(List.filled(jacobian.columns, 1.0));
      const solver = AdaptiveGeometryLinearSolver(
          sparseNumericWorkPerNonzero: 0x1fffffffffffff);
      final result = solver.solve(jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      final explicit = const SparseLdltGeometrySolver().solve(
          jacobian, residual,
          damping: .1, diagonal: diagonal, maxIterations: 1);
      expect(result.status, GeometryLinearStatus.converged);
      expect(result.iterations, 1);
      expect(result.step, explicit.step);
    });

    test('negative multiplier rejects even when the dense path is eligible',
        () {
      final jacobian = _smallChain();
      expect(
        () =>
            const AdaptiveGeometryLinearSolver(sparseNumericWorkPerNonzero: -1)
                .solve(jacobian, Float64List.fromList([1, 2, 3]),
                    damping: .1, diagonal: Float64List.fromList([1, 1, 1])),
        throwsArgumentError,
      );
    });
  });
}

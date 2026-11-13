import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/src/geometry/solver.dart';
import 'package:test/test.dart';

GeometryParameterBlock scalar(String id, double value,
        {bool fixed = false, double? lower, double? upper}) =>
    GeometryParameterBlock(
        id: id,
        values: [value],
        fixed: fixed,
        lowerBounds: lower == null ? null : [lower],
        upperBounds: upper == null ? null : [upper]);

GeometryResidualBlock equal(String id, String a, String b) =>
    GeometryResidualBlock.autoDiff(
        id: id,
        parameterIds: [a, b],
        residualCount: 1,
        evaluate: (p) => [p[0][0] - p[1][0]]);

void main() {
  group('local derivatives and linear algebra', () {
    test('dual derivatives agree with independent closed forms', () {
      final x = Dual.variable(0.7, 0, 2);
      final y = Dual.variable(1.3, 1, 2);
      final value = x.sin() * y + x.square() / y;
      expect(value.value, closeTo(math.sin(0.7) * 1.3 + 0.49 / 1.3, 1e-14));
      expect(value.derivatives[0],
          closeTo(math.cos(0.7) * 1.3 + 1.4 / 1.3, 1e-14));
      expect(value.derivatives[1], closeTo(math.sin(0.7) - 0.49 / 1.69, 1e-14));
      final angle = y.atan2(x);
      expect(angle.derivatives[0], closeTo(-1.3 / (0.49 + 1.69), 1e-14));
      expect(angle.derivatives[1], closeTo(0.7 / (0.49 + 1.69), 1e-14));
    });

    test('rank distinguishes duplicate equations from dimension count', () {
      final info =
          geometryRank(Float64List.fromList([1, 1, 2, 2, 0, 0]), 3, 2)!;
      expect(info.rank, 1);
      final full = geometryRank(Float64List.fromList([1, 1, 1, -1]), 2, 2)!;
      expect(full.rank, 2);
    });

    test('dense QR and sparse CG solve the same damped system', () {
      final j = SparseGeometryJacobian(
          rows: 3,
          columns: 2,
          rowOffsets: Int32List.fromList([0, 2, 4, 6]),
          columnIndices: Int32List.fromList([0, 1, 0, 1, 0, 1]),
          values: Float64List.fromList([1, 2, 3, -1, 2, 4]));
      final residual = Float64List.fromList([-3, -2, -6]);
      final diagonal = Float64List.fromList([1, 1]);
      final dense = const DenseQrGeometrySolver()
          .solve(j, residual, damping: 0.01, diagonal: diagonal);
      final sparse = const SparseCgGeometrySolver()
          .solve(j, residual, damping: 0.01, diagonal: diagonal);
      expect(dense.status, GeometryLinearStatus.converged);
      expect(sparse.status, GeometryLinearStatus.converged);
      for (var i = 0; i < 2; i++) {
        expect(dense.step[i], closeTo(sparse.step[i], 1e-12));
      }
      // Independent direct 2x2 normal-equation oracle.
      const a = 14.01, b = 7.0, d = 21.01;
      const determinant = a * d - b * b;
      expect(dense.step[0], closeTo((21 * d - b * 28) / determinant, 1e-12));
      expect(dense.step[1], closeTo((a * 28 - b * 21) / determinant, 1e-12));
    });

    test('linear budget and cancellation are explicit', () {
      final j = SparseGeometryJacobian(
          rows: 1,
          columns: 1,
          rowOffsets: Int32List.fromList([0, 1]),
          columnIndices: Int32List.fromList([0]),
          values: Float64List.fromList([1]));
      final budget = const SparseCgGeometrySolver().solve(
          j, Float64List.fromList([1]),
          damping: 1, diagonal: Float64List.fromList([1]), maxIterations: 0);
      expect(budget.status, GeometryLinearStatus.iterationLimit);
      final cancelled = const SparseCgGeometrySolver().solve(
          j, Float64List.fromList([1]),
          damping: 1,
          diagonal: Float64List.fromList([1]),
          shouldStop: () => true);
      expect(cancelled.status, GeometryLinearStatus.cancelled);
    });
  });

  group('compiled geometric sessions', () {
    test('fixed dimensions do not join independent active components', () {
      final compiled = GeometryModel(parameters: [
        scalar('x', 0),
        scalar('y', 0),
        scalar('d', 2, fixed: true)
      ], constraints: [
        equal('x=d', 'x', 'd'),
        equal('y=d', 'y', 'd')
      ]).compile();
      expect(compiled.componentCount, 2);
      expect(compiled.activeTangentDimension, 2);
      expect(compiled.jacobianNonzeros, 2);
      final session = compiled.createSession();
      final first = session.solve();
      expect(first.isSuccess, isTrue, reason: first.message);
      expect(first.localDegreesOfFreedom, 0);
      expect(session.parameterValues('x').single, closeTo(2, 1e-8));
      session.setParameterValues('d', [5]);
      expect(session.dirtyComponentCount, 2);
      final second = session.solve();
      expect(second.isSuccess, isTrue);
      expect(second.stats.componentsSolved, 2);
      expect(second.values['y']!.single, closeTo(5, 1e-8));
    });

    test('a dimension edit reuses unaffected components and warm coordinates',
        () {
      final compiled = GeometryModel(parameters: [
        scalar('x', 0),
        scalar('y', 0),
        scalar('dx', 2, fixed: true),
        scalar('dy', 3, fixed: true)
      ], constraints: [
        equal('x=dx', 'x', 'dx'),
        equal('y=dy', 'y', 'dy')
      ]).compile();
      final session = compiled.createSession();
      expect(session.solve().isSuccess, isTrue);
      final unchanged = session.solve();
      expect(unchanged.stats.componentsReused, 2);
      expect(unchanged.stats.residualEvaluations, 0);
      session.setParameterValues('dx', [2.01]);
      final edited = session.solve();
      expect(edited.isSuccess, isTrue);
      expect(edited.stats.componentsSolved, 1);
      expect(edited.stats.componentsReused, 1);
      expect(edited.values['x']!.single, closeTo(2.01, 1e-8));
      expect(edited.values['y']!.single, closeTo(3, 1e-8));
      expect(() => edited.values['x']![0] = 100, throwsUnsupportedError);
    });

    test('nonlinear dimensions preserve the warm-start solution branch', () {
      final session = GeometryModel(parameters: [
        scalar('x', -2),
        scalar('d', 9, fixed: true)
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'square',
            parameterIds: ['x', 'd'],
            residualCount: 1,
            evaluate: (p) => [p[0][0].square() - p[1][0]])
      ]).compile().createSession();
      final first = session.solve();
      expect(first.isSuccess, isTrue, reason: first.message);
      expect(first.values['x']!.single, closeTo(-3, 1e-8));
      session.setParameterValues('d', [16]);
      final second = session.solve();
      expect(second.isSuccess, isTrue);
      expect(second.values['x']!.single, closeTo(-4, 1e-8));
    });

    test('underdetermined constraints report actual Jacobian freedoms', () {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0])
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'line',
            parameterIds: ['point'],
            residualCount: 1,
            evaluate: (p) => [p[0][0] + p[0][1] - 3])
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isTrue);
      expect(result.localDegreesOfFreedom, 1);
      expect(result.values['point']![0] + result.values['point']![1],
          closeTo(3, 1e-8));
    });

    test('duplicate and contradictory dimensions are distinguished', () {
      final session = GeometryModel(parameters: [
        scalar('x', 0),
        scalar('d1', 1, fixed: true),
        scalar('d2', 1, fixed: true)
      ], constraints: [
        equal('one', 'x', 'd1'),
        equal('two', 'x', 'd2')
      ]).compile().createSession();
      final first = session.solve();
      expect(first.isSuccess, isTrue);
      expect(first.components.single.numericalRank, 1);
      expect(first.components.single.dependentEquationCount, 1);
      expect(
          first.components.single.locallyDependentConstraintIds, hasLength(1));
      final committed = session.committedValues;
      session.setParameterValues('d2', [2]);
      final failed = session.solve();
      expect(failed.isSuccess, isFalse);
      expect(failed.status, isNot(GeometrySolveStatus.satisfied));
      expect(session.committedValues, committed);
      expect(session.pendingValues, committed);
      // Fixed inputs are rolled back atomically; the next solve is again valid.
      expect(session.solve().isSuccess, isTrue);
    });

    test('stationarity is not geometric feasibility', () {
      final session = GeometryModel(parameters: [
        scalar('x', 0)
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'impossible-square',
            parameterIds: ['x'],
            residualCount: 1,
            evaluate: (p) => [p[0][0].square() + 1]),
      ]).compile().createSession();
      final result = session.solve();
      expect(result.status, GeometrySolveStatus.stalled);
      expect(result.constraintResiduals['impossible-square']!.single, 1);
      expect(session.committedValues, isNull);
    });

    test('residual scaling cannot bypass physical acceptance tolerance', () {
      final session = GeometryModel(parameters: [
        scalar('x', 0, fixed: true)
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'required',
            parameterIds: ['x'],
            residualCount: 1,
            tolerance: 1e-10,
            scale: 1e20,
            evaluate: (p) => [p[0][0] - 1]),
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isFalse);
      expect(result.constraintResiduals['required']!.single, -1);
    });

    test('bounds are respected and an excluded root is not accepted', () {
      final session = GeometryModel(parameters: [
        scalar('x', 0, lower: 0, upper: 1),
        scalar('d', 2, fixed: true)
      ], constraints: [
        equal('root', 'x', 'd')
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isFalse);
      expect(result.values['x']!.single, inInclusiveRange(0, 1));
      expect(session.committedValues, isNull);
      expect(() => session.setParameterValues('x', [2]), throwsArgumentError);
    });

    test('analytic derivatives use the same manifold-aware pipeline', () {
      final session = GeometryModel(parameters: [
        scalar('x', 1)
      ], constraints: [
        GeometryResidualBlock(
            id: 'cube',
            parameterIds: ['x'],
            residualCount: 1,
            evaluate: (p, r, j) {
              final x = p[0][0];
              r[0] = x * x * x - 8;
              if (j != null) j[0][0] = 3 * x * x;
            }),
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.values['x']!.single, closeTo(2, 1e-8));
    });

    test('invalid callback results fail explicitly without throwing', () {
      final session = GeometryModel(parameters: [
        scalar('x', 0)
      ], constraints: [
        GeometryResidualBlock(
            id: 'degenerate',
            parameterIds: ['x'],
            residualCount: 1,
            evaluate: (p, r, j) => throw StateError('zero length line')),
      ]).compile().createSession();
      final result = session.solve();
      expect(result.status, GeometrySolveStatus.numericalFailure);
      expect(result.message, contains('zero length line'));
      expect(session.committedValues, isNull);
    });

    test('a verified root may have undefined rank at a singularity', () {
      final session = GeometryModel(parameters: [
        scalar('x', 0)
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'sqrt',
            parameterIds: ['x'],
            residualCount: 1,
            evaluate: (p) => [p[0][0].sqrt()]),
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isTrue);
      expect(result.localDegreesOfFreedom, isNull);
    });
  });

  group('3D manifolds and sparse systems', () {
    test('quaternion local derivative matches independent perturbations', () {
      const manifold = QuaternionGeometryManifold();
      final q = Float64List.fromList([0.5, 0.5, 0.5, 0.5]);
      final jacobian = Float64List(12);
      manifold.plusJacobian(q, jacobian);
      for (var col = 0; col < 3; col++) {
        final delta = Float64List(3)..[col] = 1e-6;
        final plus = Float64List(4), minus = Float64List(4);
        manifold.plus(q, delta, plus);
        delta[col] = -1e-6;
        manifold.plus(q, delta, minus);
        for (var row = 0; row < 4; row++) {
          expect((plus[row] - minus[row]) / 2e-6,
              closeTo(jacobian[row * 3 + col], 1e-9));
        }
      }
    });

    test('unit quaternion uses three tangent degrees of freedom', () {
      final target = math.sqrt(0.5);
      final compiled = GeometryModel(parameters: [
        GeometryParameterBlock(
            id: 'q',
            values: [1, 0, 0, 0],
            manifold: const QuaternionGeometryManifold())
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'orientation',
            parameterIds: ['q'],
            residualCount: 4,
            evaluate: (p) =>
                [p[0][0] - target, p[0][1], p[0][2], p[0][3] - target])
      ]).compile();
      expect(compiled.activeTangentDimension, 3);
      final result = compiled.createSession().solve();
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.localDegreesOfFreedom, 0);
      expect(geometryNorm(result.values['q']!), closeTo(1, 1e-14));
      expect(result.values['q']![3], closeTo(target, 1e-8));
    });

    test('scaled underconstrained circle drags retain radial direction', () {
      // A per-column damping metric used to send the weak x coordinate on a
      // large tangential excursion. The explicit tangent metric must remain
      // isotropic through a change of model units.
      for (final unit in [1e-9, 1.0, 1e9]) {
        final compiled = GeometryModel(parameters: [
          GeometryParameterBlock(
              id: 'point',
              values: [0.5 * unit, 4 * unit, 0.1 * unit],
              scales: [unit, unit, unit]),
        ], constraints: [
          GeometryResidualBlock.autoDiff(
              id: 'circle',
              parameterIds: ['point'],
              residualCount: 2,
              tolerance: unit * 1e-9,
              scale: unit,
              evaluate: (p) => [
                    p[0][2],
                    (p[0][0].square() + p[0][1].square() + p[0][2].square())
                            .sqrt() -
                        3 * unit
                  ]),
        ]).compile();
        final result = compiled.createSession().solve();
        expect(result.isSuccess, isTrue, reason: 'unit=$unit ${result.status}');
        expect(result.localDegreesOfFreedom, 1);
        final point = result.values['point']!;
        expect(geometryNorm(point) / unit, closeTo(3, 1e-9));
        expect(point[0] / point[1], closeTo(0.125, 1e-10));
        expect(result.stats.nonlinearIterations, lessThan(12));
      }
    });

    test('product pose retraction preserves translation and quaternion layout',
        () {
      final manifold = ProductGeometryManifold([
        const EuclideanGeometryManifold(3),
        const QuaternionGeometryManifold()
      ]);
      final base = Float64List.fromList([1, 2, 3, 1, 0, 0, 0]);
      final out = Float64List(7);
      manifold.plus(
          base, Float64List.fromList([1, -1, 2, 0, 0, math.pi / 2]), out);
      expect(out.sublist(0, 3), [2, 1, 5]);
      expect(out[3], closeTo(math.sqrt(0.5), 1e-14));
      expect(out[6], closeTo(math.sqrt(0.5), 1e-14));
      expect(manifold.isValid(out), isTrue);
    });

    test('large sparse chain uses linear-size structure and bounded rank work',
        () {
      const count = 160;
      final parameters = [for (var i = 0; i < count; i++) scalar('p$i', 0)];
      final constraints = <GeometryResidualBlock>[
        GeometryResidualBlock.autoDiff(
            id: 'anchor',
            parameterIds: ['p0'],
            residualCount: 1,
            evaluate: (p) => [p[0][0]]),
        for (var i = 1; i < count; i++)
          GeometryResidualBlock.autoDiff(
              id: 'edge$i',
              parameterIds: ['p${i - 1}', 'p$i'],
              residualCount: 1,
              evaluate: (p) => [p[1][0] - p[0][0] - 1]),
      ];
      final compiled =
          GeometryModel(parameters: parameters, constraints: constraints)
              .compile();
      expect(compiled.componentCount, 1);
      expect(compiled.jacobianNonzeros, count * 2 - 1);
      final result = compiled
          .createSession()
          .solve(options: const GeometrySolveOptions(rankParameterLimit: 32));
      expect(result.isSuccess, isTrue,
          reason: '${result.status}: ${result.message}');
      expect(result.values['p${count - 1}']!.single, closeTo(count - 1, 1e-6));
      expect(result.components.single.numericalRank, isNull);
      for (final residual in result.constraintResiduals.values) {
        expect(residual.single.abs(), lessThanOrEqualTo(1e-8));
      }
    });
  });

  group('limits, cancellation and revisions', () {
    GeometrySolveSession makeSession() => GeometryModel(
        parameters: [scalar('x', 0), scalar('target', 2, fixed: true)],
        constraints: [equal('edit', 'x', 'target')]).compile().createSession();

    test('iteration, time and cancellation verdicts remain distinct', () {
      expect(
          makeSession()
              .solve(options: const GeometrySolveOptions(maxIterations: 0))
              .status,
          GeometrySolveStatus.iterationLimit);
      expect(makeSession().solve(timeLimit: Duration.zero).status,
          GeometrySolveStatus.deadlineExceeded);
      expect(makeSession().solve(shouldCancel: () => true).status,
          GeometrySolveStatus.cancelled);
    });

    test('cancelled edits retain the committed coordinates and dimensions', () {
      final session = makeSession();
      expect(session.solve().isSuccess, isTrue);
      final committed = session.values;
      session.setParameterValues('target', [100]);
      var checks = 0;
      final result = session.solve(shouldCancel: () => ++checks > 8);
      expect(result.status, GeometrySolveStatus.cancelled);
      expect(session.values, committed);
      expect(session.pendingValues, committed);
    });

    test('stale expected revisions do not solve or overwrite pending edits',
        () {
      final session = makeSession();
      final oldRevision = session.revision;
      session.setParameterValues('target', [3]);
      final result = session.solve(expectedRevision: oldRevision);
      expect(result.status, GeometrySolveStatus.staleRevision);
      expect(result.stats.residualEvaluations, 0);
      expect(session.pendingValues['target'], [3]);
    });

    test('edits inside a stop callback also invalidate the captured revision',
        () {
      final session = makeSession();
      var edit = true;
      final result = session.solve(shouldCancel: () {
        if (edit) {
          edit = false;
          session.setParameterValues('target', [9]);
        }
        return false;
      });
      expect(result.status, GeometrySolveStatus.staleRevision);
      expect(session.pendingValues['target'], [9]);
      expect(session.committedValues, isNull);
    });

    test('cooperative async solves reject edits from a newer revision',
        () async {
      final session = makeSession();
      final future = session.solveAsync();
      session.setParameterValues('target', [7]);
      final result = await future;
      expect(result.status, GeometrySolveStatus.staleRevision);
      expect(session.pendingValues['target'], [7]);
      final current = await session.solveAsync();
      expect(current.isSuccess, isTrue);
      expect(current.values['x']!.single, closeTo(7, 1e-8));
    });

    test('cooperative async solves observe event-loop cancellation', () async {
      final session = makeSession();
      var cancel = false;
      final future = session.solveAsync(shouldCancel: () => cancel);
      await Future<void>.delayed(Duration.zero);
      cancel = true;
      final result = await future;
      expect(result.status, GeometrySolveStatus.cancelled);
    });
  });
}

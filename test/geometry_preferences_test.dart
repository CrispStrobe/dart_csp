import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/src/geometry/solver.dart';
import 'package:test/test.dart';

GeometrySolveSession circleSession({double radius = 3}) => GeometryModel(
      parameters: [
        GeometryParameterBlock(id: 'point', values: [radius, 0, 0]),
        GeometryParameterBlock(id: 'radius', values: [radius], fixed: true)
      ],
      constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'circle',
            parameterIds: ['point', 'radius'],
            residualCount: 2,
            evaluate: (p) => [
                  p[0][2],
                  (p[0][0].square() + p[0][1].square() + p[0][2].square())
                          .sqrt() -
                      p[1][0]
                ])
      ],
    ).compile().createSession();

void main() {
  test(
      'dense and matrix-free nullspace projections match an independent oracle',
      () {
    final j = SparseGeometryJacobian(
        rows: 3,
        columns: 3,
        rowOffsets: Int32List.fromList([0, 2, 3, 5]),
        columnIndices: Int32List.fromList([0, 1, 2, 0, 1]),
        values: Float64List.fromList([1, 1, 1, 2, 2]));
    final v = Float64List.fromList([3, 1, 9]);
    for (final denseLimit in [96, 0]) {
      final projection =
          projectGeometryNullspace(j, v, denseColumnLimit: denseLimit);
      expect(projection.status, GeometryLinearStatus.converged);
      expect(projection.vector[0], closeTo(1, 1e-10));
      expect(projection.vector[1], closeTo(-1, 1e-10));
      expect(projection.vector[2], closeTo(0, 1e-10));
      expect(projection.relativeConstraintError, lessThan(1e-10));
    }
  });

  test('an unconstrained coordinate target reaches the requested position', () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'point', values: [0, 0, 0]),
    ], constraints: []).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'point', values: [2, -1, 0.5])
    ]);
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    expect(result.values['point'], [2, -1, 0.5]);
    expect(result.preferenceReport!.status,
        GeometryPreferenceStatus.targetReached);
    expect(result.preferenceReport!.finalCost, 0);
  });

  test('weighted conflicting preferences have the independent weighted optimum',
      () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [0])
    ], constraints: []).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'x', values: [0]),
      GeometryParameterTarget(parameterId: 'x', values: [10], weight: 3),
    ]);
    expect(result.isSuccess, isTrue);
    expect(result.values['x']!.single, closeTo(7.5, 1e-10));
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
    expect(result.preferenceReport!.finalCost, closeTo(37.5, 1e-10));
  });

  test(
      'a planar hard equation is preserved while the reachable target improves',
      () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'p', values: [0, 0])
    ], constraints: [
      GeometryResidualBlock.autoDiff(
          id: 'plane',
          parameterIds: ['p'],
          residualCount: 1,
          evaluate: (p) => [p[0][1]])
    ]).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'p', values: [4, 5])
    ]);
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(result.values['p']![0], closeTo(4, 1e-8));
    expect(result.values['p']![1], closeTo(0, 1e-8));
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
    expect(result.preferenceReport!.finalCost, closeTo(12.5, 1e-8));
    expect(result.localDegreesOfFreedom, 1);
  });

  test(
      'a circle drag reaches its independently computed closest feasible point',
      () {
    final session = circleSession();
    expect(session.solve().isSuccess, isTrue);
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'point', values: [1, 4, 1])
    ]);
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    final point = result.values['point']!;
    final expected = [3 / math.sqrt(17), 12 / math.sqrt(17), 0.0];
    expect(geometryNorm(point), closeTo(3, 1e-8));
    expect(point[2], closeTo(0, 1e-8));
    for (var i = 0; i < 3; i++) {
      expect(point[i], closeTo(expected[i], 2e-6));
    }
    expect(result.preferenceReport!.finalCost,
        lessThan(result.preferenceReport!.initialCost));
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
    expect(result.values['radius'], [3]);
  });

  test(
      'repeated circle targets retain the continuous positive-orientation branch',
      () {
    final session = circleSession();
    expect(session.solve().isSuccess, isTrue);
    var prior = session.parameterValues('point');
    for (var i = 1; i <= 8; i++) {
      final angle = i * math.pi / 16;
      final target = [3 * math.cos(angle), 3 * math.sin(angle), 0.0];
      final result = session.solve(preferences: [
        GeometryParameterTarget(parameterId: 'point', values: target)
      ]);
      expect(result.isSuccess, isTrue,
          reason: '${result.status}: ${result.message}');
      final p = result.values['point']!;
      expect(geometryNorm(p), closeTo(3, 1e-8));
      expect(geometryDot(prior, p), greaterThan(8));
      expect(p[0], closeTo(target[0], 1e-6));
      expect(p[1], closeTo(target[1], 1e-6));
      prior = p;
    }
  });

  test('very large preference weights cannot buy hard constraint violations',
      () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [2])
    ], constraints: [
      GeometryResidualBlock.autoDiff(
          id: 'fixed-length',
          parameterIds: ['x'],
          residualCount: 1,
          evaluate: (p) => [p[0][0] - 2])
    ]).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'x', values: [100], weight: 1e20)
    ]);
    expect(result.isSuccess, isTrue);
    expect(result.values['x']!.single, closeTo(2, 1e-8));
    expect(result.constraintResiduals['fixed-length']!.single.abs(),
        lessThanOrEqualTo(1e-8));
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
    expect(result.preferenceReport!.maxTargetError, closeTo(98, 1e-8));
  });

  test('fixed parameter targets are honestly unmet and never alter dimensions',
      () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'anchor', values: [0], fixed: true)
    ], constraints: []).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'anchor', values: [5])
    ]);
    expect(result.isSuccess, isTrue);
    expect(result.values['anchor'], [0]);
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
    expect(result.preferenceReport!.acceptedSteps, 0);
  });

  test('a bound-conflicting target stops at the boundary', () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(
          id: 'x', values: [0], lowerBounds: [0], upperBounds: [1])
    ], constraints: []).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'x', values: [5])
    ]);
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(result.values['x'], [1]);
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
  });

  test('quaternion targets preserve unit norm and equivalent signs', () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(
          id: 'q',
          values: [1, 0, 0, 0],
          manifold: const QuaternionGeometryManifold())
    ], constraints: []).compile().createSession();
    final value = math.sqrt(0.5);
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'q', values: [-value, 0, 0, -value])
    ]);
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    final q = result.values['q']!;
    expect(geometryNorm(q), closeTo(1, 1e-13));
    expect(q[0], closeTo(value, 1e-7));
    expect(q[3], closeTo(value, 1e-7));
    expect(result.preferenceReport!.status,
        GeometryPreferenceStatus.targetReached);
  });

  test('hinge orientation preferences keep forbidden axes constrained', () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(
          id: 'q',
          values: [1, 0, 0, 0],
          manifold: const QuaternionGeometryManifold())
    ], constraints: [
      GeometryResidualBlock.autoDiff(
          id: 'axis',
          parameterIds: ['q'],
          residualCount: 2,
          evaluate: (p) => [p[0][1], p[0][2]]),
    ]).compile().createSession();
    final result = session.solve(preferences: [
      GeometryParameterTarget(
          parameterId: 'q', values: [math.cos(0.6), 0, 0, math.sin(0.6)])
    ]);
    expect(result.isSuccess, isTrue, reason: result.message);
    final q = result.values['q']!;
    expect(q[1].abs(), lessThanOrEqualTo(1e-8));
    expect(q[2].abs(), lessThanOrEqualTo(1e-8));
    expect(q[3], closeTo(math.sin(0.6), 1e-7));
    expect(geometryNorm(q), closeTo(1, 1e-13));
    expect(result.localDegreesOfFreedom, 1);
  });

  test(
      'sparse coupled cluster follows one target without a dense global matrix',
      () {
    const count = 160;
    final model = GeometryModel(parameters: [
      for (var i = 0; i < count; i++)
        GeometryParameterBlock(id: 'p$i', values: [0])
    ], constraints: [
      for (var i = 1; i < count; i++)
        GeometryResidualBlock.autoDiff(
            id: 'link$i',
            parameterIds: ['p${i - 1}', 'p$i'],
            residualCount: 1,
            evaluate: (p) => [p[1][0] - p[0][0]]),
    ]).compile();
    final result = model.createSession().solve(preferences: [
      GeometryParameterTarget(parameterId: 'p0', values: [5])
    ]);
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    expect(result.preferenceReport!.acceptedSteps, lessThan(4));
    expect(model.jacobianNonzeros, 2 * (count - 1));
    for (var i = 0; i < count; i++) {
      expect(result.values['p$i']!.single, closeTo(5, 1e-7));
    }
    for (final residual in result.constraintResiduals.values) {
      expect(residual.single.abs(), lessThanOrEqualTo(1e-8));
    }
  });

  test('preference iteration limits retain the last committed state', () {
    final session = circleSession();
    expect(session.solve().isSuccess, isTrue);
    final before = session.committedValues;
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'point', values: [0, 3, 0])
    ], preferenceOptions: const GeometryPreferenceOptions(maxIterations: 0));
    expect(result.status, GeometrySolveStatus.iterationLimit);
    expect(result.preferenceReport!.status,
        GeometryPreferenceStatus.iterationLimit);
    expect(session.committedValues, before);
  });

  test('cancellation during preference work rolls back coordinates', () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [0])
    ], constraints: []).compile().createSession();
    expect(session.solve().isSuccess, isTrue);
    var checks = 0;
    final result = session.solve(
        preferences: [
          GeometryParameterTarget(parameterId: 'x', values: [100])
        ],
        preferenceOptions: const GeometryPreferenceOptions(
            maxIterations: 1000, maxTangentStep: 0.1),
        shouldCancel: () => ++checks > 100);
    expect(result.status, GeometrySolveStatus.cancelled);
    expect(result.preferenceReport!.status, GeometryPreferenceStatus.cancelled);
    expect(result.preferenceReport!.acceptedSteps, greaterThan(0));
    expect(session.parameterValues('x'), [0]);
  });

  test('async preference work cannot overwrite a newer input revision',
      () async {
    final session = circleSession();
    expect(session.solve().isSuccess, isTrue);
    final future = session.solveAsync(
        preferences: [
          GeometryParameterTarget(parameterId: 'point', values: [0, 3, 0])
        ],
        preferenceOptions:
            const GeometryPreferenceOptions(maxTangentStep: 0.05));
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    session.setParameterValues('radius', [4]);
    final result = await future;
    expect(result.status, GeometrySolveStatus.staleRevision);
    expect(session.pendingValues['radius'], [4]);
    expect(session.committedValues!['radius'], [3]);
  });

  test('preferences reuse components that have no target', () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'a', values: [0]),
      GeometryParameterBlock(id: 'b', values: [7])
    ], constraints: []).compile().createSession();
    expect(session.solve().isSuccess, isTrue);
    final result = session.solve(preferences: [
      GeometryParameterTarget(parameterId: 'a', values: [3])
    ]);
    expect(result.isSuccess, isTrue);
    expect(result.stats.componentsSolved, 1);
    expect(result.stats.componentsReused, 1);
    expect(result.values['b'], [7]);
  });

  test('preference projection limits are explicit and leave the commit intact',
      () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'p', values: [0, 0])
    ], constraints: [
      GeometryResidualBlock.autoDiff(
          id: 'plane',
          parameterIds: ['p'],
          residualCount: 1,
          evaluate: (p) => [p[0][1]])
    ]).compile().createSession();
    expect(session.solve().isSuccess, isTrue);
    final result = session.solve(
        preferences: [
          GeometryParameterTarget(parameterId: 'p', values: [4, 5])
        ],
        options: const GeometrySolveOptions(rankParameterLimit: 0),
        preferenceOptions:
            const GeometryPreferenceOptions(maxLinearIterations: 0));
    expect(result.status, GeometrySolveStatus.iterationLimit);
    expect(result.preferenceReport!.status,
        GeometryPreferenceStatus.iterationLimit);
    expect(session.parameterValues('p'), [0, 0]);
  });

  test('a one-shot cancellation signal remains latched during preference work',
      () {
    final session = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [0])
    ], constraints: []).compile().createSession();
    expect(session.solve().isSuccess, isTrue);
    var checks = 0;
    final result = session.solve(
        preferences: [
          GeometryParameterTarget(parameterId: 'x', values: [100])
        ],
        preferenceOptions: const GeometryPreferenceOptions(
            maxIterations: 1000, maxTangentStep: 0.1),
        shouldCancel: () => ++checks == 30);
    expect(result.status, GeometrySolveStatus.cancelled);
    expect(result.preferenceReport!.status, GeometryPreferenceStatus.cancelled);
    expect(result.preferenceReport!.acceptedSteps, greaterThan(0));
    expect(session.parameterValues('x'), [0]);
  });

  test(
      'explicit coordinate and residual scales preserve drag behavior across units',
      () {
    for (final unit in [1e-9, 1.0, 1e9]) {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(
            id: 'point', values: [3 * unit, 0, 0], scales: [unit, unit, unit])
      ], constraints: [
        GeometryResidualBlock.autoDiff(
            id: 'circle',
            parameterIds: ['point'],
            residualCount: 2,
            tolerance: 1e-8 * unit,
            scale: unit,
            evaluate: (p) => [
                  p[0][2],
                  (p[0][0].square() + p[0][1].square() + p[0][2].square())
                          .sqrt() -
                      3 * unit
                ]),
      ]).compile().createSession();
      final result = session.solve(preferences: [
        GeometryParameterTarget(
            parameterId: 'point',
            values: [unit, 4 * unit, 0],
            coordinateScales: [unit, unit, unit])
      ]);
      expect(result.isSuccess, isTrue,
          reason: 'unit=$unit ${result.status}: ${result.message}');
      final point = result.values['point']!;
      expect(geometryNorm(point) / unit, closeTo(3, 1e-8));
      expect(point[0] / unit, closeTo(3 / math.sqrt(17), 2e-6));
      expect(point[1] / unit, closeTo(12 / math.sqrt(17), 2e-6));
      expect(point[2] / unit, closeTo(0, 1e-8));
    }
  });
}

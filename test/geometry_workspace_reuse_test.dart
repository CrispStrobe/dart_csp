import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

import '../benchmark/geometry_coupled.dart' as coupled;

class _MutableRankOptions extends GeometrySolveOptions {
  double tolerance = 1e-10;

  @override
  double get rankTolerance => tolerance;
}

GeometrySolveSession _duplicateDimensionSession() => GeometryModel(
      parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0]),
        GeometryParameterBlock(id: 'target', values: [2], fixed: true),
      ],
      constraints: [
        for (final id in ['dimension', 'duplicate'])
          GeometryResidualBlock.autoDiff(
            id: id,
            parameterIds: ['point', 'target'],
            residualCount: 1,
            evaluate: (p) => [p[0][0] - p[1][0]],
          ),
      ],
    ).compile().createSession();

void main() {
  group('active automatic derivatives', () {
    test('fixed blocks are constant while direct evaluation keeps full blocks',
        () {
      final dimensions = <int>{};
      final residual = GeometryResidualBlock.autoDiff(
        id: 'mixed blocks',
        parameterIds: ['factors', 'xy', 'target', 'z'],
        residualCount: 3,
        evaluate: (p) {
          dimensions.add(p[0][0].derivatives.length);
          return [
            p[1][0] * p[0][0] - p[2][0],
            p[1][1] * p[0][1] - p[2][0],
            p[3][0] - p[2][0],
          ];
        },
      );
      final directResidual = Float64List(3);
      final directJacobians = [
        Float64List(6),
        Float64List(6),
        Float64List(3),
        Float64List(3)
      ];
      residual.evaluate([
        Float64List.fromList([2, 3]),
        Float64List.fromList([3, 2]),
        Float64List.fromList([6]),
        Float64List.fromList([6]),
      ], directResidual, directJacobians);
      expect(directResidual, [0, 0, 0]);
      expect(directJacobians[0], [3, 0, 0, 2, 0, 0]);
      expect(directJacobians[1], [2, 0, 0, 3, 0, 0]);
      expect(directJacobians[2], [-1, -1, -1]);
      expect(directJacobians[3], [0, 0, 1]);
      expect(dimensions, {6});

      dimensions.clear();
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'factors', values: [2, 3], fixed: true),
        GeometryParameterBlock(id: 'xy', values: [0, 0]),
        GeometryParameterBlock(id: 'target', values: [6], fixed: true),
        GeometryParameterBlock(id: 'z', values: [0]),
      ], constraints: [
        residual
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(dimensions, {0, 3});
      expect(result.values['xy']![0], closeTo(3, 1e-8));
      expect(result.values['xy']![1], closeTo(2, 1e-8));
      expect(result.values['z']!.single, closeTo(6, 1e-8));
      expect(result.stats.autoDiffDerivativeCoordinates,
          3 * result.stats.jacobianEvaluations);
      session.setParameterValues('factors', [3, 2]);
      final edited = session.solve();
      expect(edited.isSuccess, isTrue, reason: edited.message);
      expect(edited.values['xy']![0], closeTo(2, 1e-8));
      expect(edited.values['xy']![1], closeTo(3, 1e-8));
      expect(edited.stats.rankReuses, 0);
    });

    test('analytic callbacks retain fixed-input Jacobian buffer shapes', () {
      final seenShapes = <List<int>>[];
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'target', values: [2, 3], fixed: true),
        GeometryParameterBlock(id: 'point', values: [0, 0]),
      ], constraints: [
        GeometryResidualBlock(
          id: 'analytic',
          parameterIds: ['target', 'point'],
          residualCount: 2,
          evaluate: (p, residual, jacobians) {
            residual[0] = p[1][0] - p[0][0];
            residual[1] = p[1][1] - p[0][1];
            if (jacobians != null) {
              seenShapes.add([for (final block in jacobians) block.length]);
              jacobians[0].setAll(0, [-1, 0, 0, -1]);
              jacobians[1].setAll(0, [1, 0, 0, 1]);
            }
          },
        ),
      ]).compile().createSession();
      final result = session.solve();
      expect(result.isSuccess, isTrue, reason: result.message);
      expect(result.values['point']![0], closeTo(2, 1e-8));
      expect(result.values['point']![1], closeTo(3, 1e-8));
      expect(seenShapes, isNotEmpty);
      expect(seenShapes, everyElement([4, 4]));
      expect(result.stats.autoDiffDerivativeCoordinates, 0);
    });

    test('analytic argument lists stay populated and private across forks', () {
      var phase = 'source';
      final targets = <String, List<double>>{
        'source': [2, -3],
        'child': [-5, 7],
        'sibling': [3, 4],
      };
      final argumentLists = <String, List<Float64List>>{};
      final evaluationKinds = <String, Set<bool>>{};
      GeometryResidualBlock constraint(String id, {bool reversed = false}) =>
          GeometryResidualBlock(
            id: id,
            parameterIds: reversed
                ? ['gain', 'target', 'point']
                : ['point', 'target', 'gain'],
            residualCount: reversed ? 1 : 2,
            evaluate: (arguments, residuals, jacobians) {
              final key = '$phase/$id';
              expect(
                  identical(argumentLists.putIfAbsent(key, () => arguments),
                      arguments),
                  isTrue);
              evaluationKinds.putIfAbsent(key, () => {}).add(jacobians != null);
              expect(arguments.map((a) => a.length),
                  reversed ? [1, 2, 2] : [2, 2, 1]);
              expect(
                  arguments.every((a) => a.every((v) => v.isFinite)), isTrue);
              final pointIndex = reversed ? 2 : 0;
              final gainIndex = reversed ? 0 : 2;
              final point = arguments[pointIndex];
              final target = arguments[1];
              final gain = arguments[gainIndex].single;
              expect(target, targets[phase]);
              expect(gain, 2);
              if (jacobians != null) {
                expect(jacobians.map((j) => j.length),
                    reversed ? [1, 2, 2] : [4, 4, 2]);
              }
              for (var row = 0; row < residuals.length; row++) {
                residuals[row] = point[row] - target[row] * gain;
                if (jacobians != null) {
                  jacobians[pointIndex][row * 2 + row] = 1;
                  jacobians[1][row * 2 + row] = -gain;
                  jacobians[gainIndex][row] = -target[row];
                }
              }
            },
          );

      final source = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0]),
        GeometryParameterBlock(
            id: 'target', values: targets[phase]!, fixed: true),
        GeometryParameterBlock(id: 'gain', values: [2], fixed: true),
      ], constraints: [
        constraint('axes'),
        constraint('duplicate x', reversed: true),
      ]).compile().createSession();

      void check(GeometrySolveResult result) {
        expect(result.isSuccess, isTrue, reason: result.message);
        for (var row = 0; row < 2; row++) {
          expect(result.values['point']![row],
              closeTo(2 * targets[phase]![row], 1e-8));
        }
      }

      final initial = source.solve();
      check(initial);
      for (final name in ['child', 'sibling']) {
        phase = name;
        final fork = source.fork()
          ..setParameterValues('target', targets[name]!);
        check(fork.solve());
        expect(source.values, initial.values);
        expect(identical(source.lastResult, initial), isTrue);
      }
      expect(argumentLists, hasLength(6));
      expect(argumentLists.values.toSet(), hasLength(6));
      expect(evaluationKinds.values, everyElement({false, true}));
    });
  });

  group('bounded exact-Jacobian rank reuse', () {
    test('dimension edits reuse rank and row dependencies with fresh residuals',
        () {
      final session = _duplicateDimensionSession();
      final first = session.solve();
      expect(first.isSuccess, isTrue);
      expect(first.components.single.numericalRank, 1);
      expect(
          first.components.single.locallyDependentConstraintIds, hasLength(1));
      expect(first.stats.rankFactorizations, 2);
      expect(first.stats.rankReuses, 0);
      session.setParameterValues('target', [4]);
      final edited = session.solve();
      expect(edited.isSuccess, isTrue, reason: edited.message);
      expect(edited.values['point']![0], closeTo(4, 1e-8));
      expect(edited.values['point']![1], 0);
      expect(edited.components.single.numericalRank, 1);
      expect(edited.components.single.locallyDependentConstraintIds,
          first.components.single.locallyDependentConstraintIds);
      expect(edited.components.single.maxToleranceRatio, lessThanOrEqualTo(1));
      expect(edited.stats.rankFactorizations, 0);
      expect(edited.stats.rankReuses, 1);
      expect(edited.stats.residualEvaluations, greaterThan(0));
      final untouched = session.solve();
      expect(untouched.stats.componentsReused, 1);
      expect(untouched.stats.rankReuses, 0);
      expect(untouched.stats.rankFactorizations, 0);
      expect(untouched.stats.residualEvaluations, 0);
    });

    test('a fixed coefficient can change rank without changing dependencies',
        () {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0]),
        GeometryParameterBlock(id: 'gain', values: [1], fixed: true),
      ], constraints: [
        GeometryResidualBlock.autoDiff(
          id: 'x',
          parameterIds: ['point'],
          residualCount: 1,
          evaluate: (p) => [p[0][0]],
        ),
        GeometryResidualBlock.autoDiff(
          id: 'scaled y',
          parameterIds: ['point', 'gain'],
          residualCount: 1,
          evaluate: (p) => [p[0][1] * p[1][0]],
        ),
      ]).compile().createSession();
      final first = session.solve();
      expect(first.isSuccess, isTrue);
      expect(first.localDegreesOfFreedom, 0);
      expect(first.stats.rankFactorizations, 1);
      session.setParameterValues('gain', [0]);
      final singular = session.solve();
      expect(singular.isSuccess, isTrue);
      expect(singular.localDegreesOfFreedom, 1);
      expect(singular.components.single.locallyDependentConstraintIds,
          ['scaled y']);
      expect(singular.stats.rankFactorizations, 2);
      expect(singular.stats.rankReuses, 0);
      session.setParameterValues('gain', [1]);
      final restored = session.solve();
      expect(restored.isSuccess, isTrue);
      expect(restored.localDegreesOfFreedom, 0);
      expect(restored.stats.rankFactorizations, 1);
      expect(restored.stats.rankReuses, 0);
    });

    test('changed rank tolerance refreshes an otherwise unchanged component',
        () {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0]),
      ], constraints: [
        GeometryResidualBlock.autoDiff(
          id: 'axes',
          parameterIds: ['point'],
          residualCount: 2,
          evaluate: (p) => [p[0][0], p[0][1] * 1e-8],
        ),
      ]).compile().createSession();
      final first = session.solve();
      expect(first.isSuccess, isTrue);
      expect(first.components.single.numericalRank, 2);
      final coarse = session.solve(
          options: const GeometrySolveOptions(rankTolerance: 1e-6));
      expect(coarse.isSuccess, isTrue);
      expect(coarse.components.single.numericalRank, 1);
      expect(coarse.stats.rankFactorizations, 2);
      expect(coarse.stats.rankReuses, 0);
      final bounded = session.solve(
          options: const GeometrySolveOptions(rankParameterLimit: 1));
      expect(bounded.isSuccess, isTrue);
      expect(bounded.components.single.numericalRank, isNull);
      expect(bounded.stats.rankFactorizations, 0);
      expect(bounded.stats.rankReuses, 0);
      final entryBounded =
          session.solve(options: const GeometrySolveOptions(rankEntryLimit: 3));
      expect(entryBounded.isSuccess, isTrue);
      expect(entryBounded.components.single.numericalRank, isNull);
      expect(entryBounded.stats.rankFactorizations, 0);
      final restored = session.solve();
      expect(restored.isSuccess, isTrue);
      expect(restored.components.single.numericalRank, 2);
      expect(restored.stats.rankFactorizations, 1);
      expect(restored.stats.rankReuses, 0);
    });

    test('mutable option getters cannot alter a run or retained rank options',
        () {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'point', values: [0, 0]),
      ], constraints: [
        GeometryResidualBlock.autoDiff(
          id: 'axes',
          parameterIds: ['point'],
          residualCount: 2,
          evaluate: (p) => [p[0][0], p[0][1] * 1e-8],
        ),
      ]).compile().createSession();
      final options = _MutableRankOptions();
      final first = session.solve(
          options: options,
          shouldCancel: () {
            options.tolerance = 1e-6;
            return false;
          });
      expect(first.isSuccess, isTrue);
      expect(first.components.single.numericalRank, 2);
      final second = session.solve(options: options);
      expect(second.isSuccess, isTrue);
      expect(second.components.single.numericalRank, 1);
      expect(second.stats.rankFactorizations, 2);
      expect(second.stats.rankReuses, 0);
    });

    test('invalid derivatives do not borrow a formerly valid rank', () {
      var invalid = false;
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'x', values: [0]),
      ], constraints: [
        GeometryResidualBlock(
          id: 'x=0',
          parameterIds: ['x'],
          residualCount: 1,
          evaluate: (p, residual, jacobians) {
            residual[0] = p[0][0];
            if (jacobians != null) {
              jacobians[0][0] = invalid ? double.nan : 1;
            }
          },
        ),
      ]).compile().createSession();
      expect(session.solve().localDegreesOfFreedom, 0);
      invalid = true;
      session.invalidateConstraint('x=0');
      final result = session.solve();
      expect(result.isSuccess, isTrue);
      expect(result.components.single.numericalRank, isNull);
      expect(result.stats.rankReuses, 0);
      expect(result.stats.rankFactorizations, 0);
    });

    test('a non-finite rank factorization is not cached as a known rank', () {
      final session = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'x', values: [0]),
      ], constraints: [
        GeometryResidualBlock(
          id: 'large coefficients',
          parameterIds: ['x'],
          residualCount: 4,
          evaluate: (p, residual, jacobians) {
            residual.fillRange(0, 4, p[0][0] * 1e308);
            // Every derivative is finite, but their column norm overflows.
            jacobians?.single.fillRange(0, 4, 1e308);
          },
        ),
      ]).compile().createSession();
      for (var attempt = 0; attempt < 2; attempt++) {
        session.invalidateConstraint('large coefficients');
        final result = session.solve();
        expect(result.isSuccess, isTrue);
        expect(result.components.single.numericalRank, isNull);
        expect(result.stats.rankFactorizations, 1);
        expect(result.stats.rankReuses, 0);
      }
    });

    test('failed edit rolls coordinates back before cached rank can be reused',
        () {
      final session = _duplicateDimensionSession();
      expect(session.solve().isSuccess, isTrue);
      final committed = session.committedValues;
      session.setParameterValues('target', [9]);
      final failed =
          session.solve(options: const GeometrySolveOptions(maxIterations: 0));
      expect(failed.isSuccess, isFalse);
      expect(failed.components.single.numericalRank, isNull);
      expect(failed.stats.rankReuses, 0);
      expect(session.committedValues, committed);
      expect(session.pendingValues, committed);
      final restored = session.solve();
      expect(restored.isSuccess, isTrue);
      expect(restored.values['point']![0], closeTo(2, 1e-8));
      expect(restored.stats.rankReuses, 1);
      expect(restored.stats.rankFactorizations, 0);
      expect(
          restored.components.single.maxToleranceRatio, lessThanOrEqualTo(1));
    });

    test('stale async edits cannot publish cached diagnostics or coordinates',
        () async {
      final session = _duplicateDimensionSession();
      expect(session.solve().isSuccess, isTrue);
      final committed = session.committedValues;
      session.setParameterValues('target', [3]);
      final pending = session.solveAsync();
      session.setParameterValues('target', [4]);
      final stale = await pending;
      expect(stale.status, GeometrySolveStatus.staleRevision);
      expect(session.committedValues, committed);
      expect(session.pendingValues['target'], [4]);
      final next = session.solve();
      expect(next.isSuccess, isTrue);
      expect(next.values['point']![0], closeTo(4, 1e-8));
      expect(next.stats.rankReuses, 1);
      expect(next.components.single.maxToleranceRatio, lessThanOrEqualTo(1));
    });
  });

  test('coupled 3D pitch edit passes an independent coordinate oracle', () {
    final model = coupled.buildCoupledChain();
    expect(model.componentCount, 1);
    expect(model.activeTangentDimension, 72);
    final session = model.createSession();
    final first = session.solve();
    coupled.checkCoupledChain(first, coupled.coupledInitialPitch);
    expect(first.stats.rankFactorizations, 1);
    session.setParameterValues('pitch', [1.1, 0.3, -0.1]);
    final edited = session.solve();
    coupled.checkCoupledChain(edited, [1.1, 0.3, -0.1]);
    expect(edited.stats.rankFactorizations, 0);
    expect(edited.stats.rankReuses, 1);
    // One active point in the anchored link; two in each remaining link.
    const activeCoordinatesPerPass = 3 + (coupled.coupledPointCount - 1) * 6;
    expect(
        edited.stats.autoDiffDerivativeCoordinates,
        activeCoordinatesPerPass *
            edited.stats.jacobianEvaluations ~/
            coupled.coupledPointCount);
  });
}

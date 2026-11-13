import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

Model amplifiedModel() {
  final model = Model();
  model.problem.floatRounding = IntervalRounding.outward;
  final x = model.realVar('x', -1e-7, 1e-7);
  final y = model.realVar('y', -1e-7, 1e-7);
  (x * y * 1e14).eq(1);
  return model;
}

Problem narrowInequality({MixedValidationOptions? options}) {
  final problem = Problem()
    ..floatRounding = IntervalRounding.outward
    ..floatValidation = options;
  for (final name in ['x', 'y', 'z']) {
    problem.addFloatVariable(name, 0, 1e-7);
  }
  problem.addLinearLeq(['x', 'y', 'z'], [1, 1, 1], 1e-7, label: 'length-mm');
  return problem;
}

void main() {
  group('mixed original-equation validation', () {
    test('a hidden error amplified by 1e14 is not returned as a solution',
        () async {
      final model = amplifiedModel();
      final result = await model.problem.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.candidateRejected);
      expect(result.solution, isNull);
      expect(result.candidate, {'x': 0.0, 'y': 0.0});
      expect(
          result.residuals.any((residual) => residual.violation >= 1), isTrue);
      expect(result.maxNormalizedViolation, greaterThan(1));
      expect(result.certifiedInfeasible, isFalse);
      // Independent feasible witness: rejection of the midpoint must not be
      // reported as a proof that this real-valued model is impossible.
      expect(1e-7 * 1e-7 * 1e14, closeTo(1, 1e-15));
      expect(await model.problem.getSolution(), 'FAILURE');
      expect(model.problem.lastMixedValidation!.accepted, isFalse);
    });

    test('nested linear and product expressions are recomputed in order',
        () async {
      final model = Model();
      model.problem.floatRounding = IntervalRounding.outward;
      final x = model.realVar('x', 2, 2);
      final y = model.realVar('y', 3, 3);
      (((x + y) * x + 1) * y).eq(33);
      final result = await model.problem.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.satisfied);
      final solvedX = result.solution!['x'] as double;
      final solvedY = result.solution!['y'] as double;
      expect(((solvedX + solvedY) * solvedX + 1) * solvedY, 33);
      expect(result.residuals.every((r) => r.isSatisfied), isTrue);
    });

    test('compensated evaluation retains a unit through large cancellation',
        () async {
      final model = Model();
      model.problem.floatRounding = IntervalRounding.outward;
      final x = model.realVar('x', 1e16, 1e16);
      final y = model.realVar('y', 1, 1);
      final z = model.realVar('z', -1e16, -1e16);
      final w = model.realVar('w', 1, 1);
      ((x + y + z) * w).eq(1);
      final result = await model.problem.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.satisfied);
      expect(result.maxNormalizedViolation, 0);
    });

    test('absolute physical tolerance is independent of terminal box width',
        () async {
      final defaultResult = await narrowInequality().getSolutionDetailed();
      expect(defaultResult.status, MixedSolveStatus.satisfied);
      final strict = await narrowInequality(
              options: MixedValidationOptions(
                  defaultTolerance:
                      const MixedTolerance(absolute: 1e-12, relative: 0)))
          .getSolutionDetailed();
      expect(strict.status, MixedSolveStatus.candidateRejected);
      final values = strict.candidate!;
      final actual = (values['x'] as num) +
          (values['y'] as num) +
          (values['z'] as num) -
          1e-7;
      expect(actual, greaterThan(1e-8));
      expect(strict.residuals.single.violation, closeTo(actual, 1e-22));
      expect(strict.residuals.single.tolerance, 1e-12);
    });

    test('label overrides apply physical units only to the named equation',
        () async {
      final options = MixedValidationOptions(
          defaultTolerance: const MixedTolerance(absolute: 1e-4, relative: 0),
          byLabel: const {
            'length-mm': MixedTolerance(absolute: 1e-12, relative: 0),
          });
      final result =
          await narrowInequality(options: options).getSolutionDetailed();
      expect(result.status, MixedSolveStatus.candidateRejected);
      expect(result.residuals.single.label, 'length-mm');
      expect(result.residuals.single.tolerance, 1e-12);
    });

    test('ordinary user product variables are not rewritten as generated ones',
        () async {
      final p = Problem()..floatRounding = IntervalRounding.outward;
      p.addFloatVariable('x', -1e-7, 1e-7);
      p.addFloatVariable('y', -1e-7, 1e-7);
      p.addFloatVariable('xy', 1e-14, 1e-14);
      p.addFloatProduct('xy', 'x', 'y', label: 'area');
      p.floatValidation = MixedValidationOptions(
          defaultTolerance: const MixedTolerance(absolute: 1e-18, relative: 0));
      final result = await p.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.candidateRejected);
      expect(result.candidate!['xy'], 1e-14);
      expect(result.residuals.single.violation, closeTo(1e-14, 1e-29));
    });

    test('copy preserves generated provenance and physical tolerances',
        () async {
      final source = amplifiedModel().problem;
      source.floatValidation = MixedValidationOptions(
          defaultTolerance: const MixedTolerance(absolute: 1e-12, relative: 0));
      final copy = source.copy();
      source.clear();
      final result = await copy.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.candidateRejected);
      expect(result.residuals.last.tolerance, 1e-12);
      expect(copy.floatAuxiliaries, isNotEmpty);
      expect(source.floatAuxiliaries, isEmpty);
    });

    test('generated names do not overwrite a user variable with the prefix',
        () async {
      final model = Model();
      model.realVar('__mul0', 9, 9);
      final x = model.realVar('x', 2, 2);
      (x * x).eq(4);
      final result = await model.problem.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.satisfied);
      expect(result.solution!['__mul0'], 9);
      expect(result.solution!['x'], 2);
    });
  });

  group('mixed legacy entry-point acceptance', () {
    final modes = <String, Future<dynamic> Function(Problem)>{
      'plain': (p) => p.getSolution(),
      'CBJ': (p) => p.getSolution(enableConflictBackjumping: true),
      'dom/wdeg': (p) => p.getSolutionWithDomWdeg(),
      'activity': (p) => p.getSolutionWithActivity(),
      'impact': (p) => p.getSolutionWithImpact(),
      'last conflict': (p) => p.getSolutionWithLastConflict(),
      'restarts': (p) => p.getSolutionWithRestarts(seed: 1),
      'LCG': (p) => p.solveWithLcg(),
      'minimize': (p) => p.minimize('x'),
      'maximize with CBJ': (p) =>
          p.maximize('x', enableConflictBackjumping: true),
    };
    for (final entry in modes.entries) {
      test('${entry.key} rejects the original-equation violation', () async {
        final p = amplifiedModel().problem;
        expect(await entry.value(p).timeout(const Duration(seconds: 2)),
            'FAILURE');
        expect(p.lastMixedValidation!.accepted, isFalse);
        expect(p.lastMixedValidation!.maxNormalizedViolation, greaterThan(1));
        expect(p.lastStats!.learnedClauses, 0);
      });
    }

    for (final cbj in [false, true]) {
      test('stream with CBJ=$cbj emits no rejected candidate or solution trace',
          () async {
        final p = amplifiedModel().problem;
        final events = <PropagationEvent>[];
        p.setOptions(onPropagation: events.add);
        expect(await p.getSolutions(enableConflictBackjumping: cbj).toList(),
            isEmpty);
        expect(
            events
                .where((event) => event.kind == PropagationEventKind.solution),
            isEmpty);
        expect(p.lastMixedValidation!.accepted, isFalse);
      });
    }
  });

  group('mixed numerical statuses', () {
    test('sub-ULP unmet residual has an explicit precision limit', () async {
      final p = Problem()..floatRounding = IntervalRounding.outward;
      p.addFloatVariable('x', 1, IntervalRounding.nextUp(1));
      p.setFloatEpsilon(1e-30);
      p.addLinearEquals(['x'], [2], IntervalRounding.nextUp(2));
      final result = await p.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.precisionLimit);
      expect(result.precisionLimited, isTrue);
      expect(result.solution, isNull);
      expect(result.certifiedInfeasible, isFalse);
      expect(result.stats.decisions, 0);
      expect(result.residuals.single.violation, greaterThan(1e-16));
    });

    test(
        'representable stagnation can still return an accepted numerical point',
        () async {
      final p = Problem();
      p.addFloatVariable('x', -1e308, 1e308);
      final result = await p.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.satisfied);
      expect((result.solution!['x'] as double).isFinite, isTrue);
      expect((result.solution!['x'] as double).abs(), lessThanOrEqualTo(1e308));
      expect(result.precisionLimited, isTrue);
    });

    test('non-finite enumerated values are not returned as a successful point',
        () async {
      final p = Problem()..addVariable('x', [double.infinity]);
      final result = await p.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.numericalFailure);
      expect(result.solution, isNull);
      expect(result.certifiedInfeasible, isFalse);
      expect(await p.getSolution(), 'FAILURE');
    });

    test('non-finite generated evaluation is a numerical failure', () async {
      final p = Problem();
      p.addFloatVariable('x', 1e308, 1e308);
      p.addFloatVariable('derived', 0, 1);
      p.registerFloatAuxiliary(
          FloatAuxiliaryDefinition.linear('derived', {'x': 1e308}));
      final result = await p.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.numericalFailure);
      expect(result.certifiedInfeasible, isFalse);
      expect(result.message, contains('not finite'));
    });

    test('cancellation and exhausted interval search are distinct', () async {
      final p = amplifiedModel().problem;
      final cancelled = await p.getSolutionDetailed(
          cancelToken: CancellationToken()..cancel());
      expect(cancelled.status, MixedSolveStatus.cancelled);
      expect(cancelled.certifiedInfeasible, isFalse);
      final m = Model();
      final x = m.realVar('x', -1, 1);
      (x * x).eq(-1);
      final excluded = await m.problem.getSolutionDetailed();
      expect(excluded.status, MixedSolveStatus.searchExhausted);
      expect(excluded.certifiedInfeasible, isFalse);
    });

    test('detailed results remain local across concurrent solve calls',
        () async {
      final valid = Problem()..addVariable('n', [3]);
      final invalid = amplifiedModel().problem;
      final results = await Future.wait([
        valid.getSolutionDetailed(),
        invalid.getSolutionDetailed(),
      ]);
      expect(results[0].status, MixedSolveStatus.satisfied);
      expect(results[0].solution, {'n': 3});
      expect(results[1].status, MixedSolveStatus.candidateRejected);
      expect(results[1].solution, isNull);
      expect(identical(results[0].stats, results[1].stats), isFalse);
    });

    test('invalid residual controls and expression cycles are rejected',
        () async {
      for (final value in [-1.0, double.nan, double.infinity]) {
        final p = narrowInequality(
            options: MixedValidationOptions(
                defaultTolerance: MixedTolerance(absolute: value)));
        await expectLater(p.getSolutionDetailed(), throwsArgumentError);
      }
      final p = Problem();
      p.addFloatVariable('a', 0, 1);
      p.addFloatVariable('b', 0, 1);
      p.registerFloatAuxiliary(FloatAuxiliaryDefinition.linear('a', {'b': 1}));
      p.registerFloatAuxiliary(FloatAuxiliaryDefinition.linear('b', {'a': 1}));
      await expectLater(p.getSolutionDetailed(), throwsArgumentError);
      expect(() => p.setFloatEpsilon(double.infinity), throwsArgumentError);
    });
  });

  group('mixed proof and unsupported-engine boundaries', () {
    test('numerical failure in a finite domain cannot become an UNSAT proof',
        () async {
      final p = Problem()..addVariable('x', [double.infinity]);
      await expectLater(p.findMinimalUnsatisfiableSubset(), throwsStateError);
      await expectLater(
          p.findMinimalUnsatisfiableSubsetQuickXplain(), throwsStateError);
    });

    test('finite-domain MUS APIs do not turn a rejected midpoint into a proof',
        () async {
      final p = amplifiedModel().problem;
      await expectLater(
          p.findMinimalUnsatisfiableSubset(), throwsUnsupportedError);
      await expectLater(p.findMinimalUnsatisfiableSubsetQuickXplain(),
          throwsUnsupportedError);
    });

    test('direct min-conflicts cannot silently omit continuous variables',
        () async {
      final csp = CspProblem(
          variables: {}, floatVariables: {'x': const Interval(0, 1)});
      await expectLater(CSP.solveWithMinConflicts(csp), throwsArgumentError);
    });

    test('finite unsatisfiability remains a finite-domain exhausted proof',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b'], [1]);
      p.addAllDifferent(['a', 'b']);
      final result = await p.getSolutionDetailed();
      expect(result.status, MixedSolveStatus.infeasible);
      expect(result.certifiedInfeasible, isTrue);
    });
  });
}

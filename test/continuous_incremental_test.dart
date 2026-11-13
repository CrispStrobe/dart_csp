import 'dart:math';

import 'package:dart_csp/src/continuous.dart';
import 'package:test/test.dart';

void main() {
  group('compiled standalone continuous contractors', () {
    test('bisection only wakes the affected independent component', () {
      for (final rounding in IntervalRounding.values) {
        final model = ContinuousModel();
        final x = model.addVar('x', 0, 1);
        final y = model.addVar('y', 0, 1);
        (x + y).eq(1);
        const unaffected = 80;
        for (var i = 0; i < unaffected; i++) {
          model.addVar('fixed$i', i.toDouble(), i.toDouble()).eq(i);
        }
        final result = model.solveDetailed(epsilon: 1e-8, rounding: rounding);
        expect(result.status, ContinuousSolveStatus.satisfied);
        final point = result.solution!.midpoint;
        expect(point['x']! + point['y']!, closeTo(1, 2e-8));
        expect(result.splits, greaterThan(10));
        expect(result.stats.constraintEvaluations['linear:0'], greaterThan(1));
        for (var i = 0; i < unaffected; i++) {
          expect(point['fixed$i'], i);
          expect(result.stats.constraintEvaluations['linear:${i + 1}'], 1,
              reason:
                  'A disconnected fixed constraint should run only at the root.');
        }
        expect(result.stats.contractorEvaluations, lessThan(unaffected + 200));
        expect(result.stats.propagationCalls, greaterThan(10));
      }
    });

    test('linear contraction work scales with arity rather than its square',
        () {
      ContinuousSolveResult run(int size) {
        final model = ContinuousModel();
        FloatExpr? sum;
        for (var i = 0; i < size; i++) {
          final v = model.addVar('x$i', i.toDouble(), i.toDouble());
          sum = sum == null ? v : sum + v;
        }
        sum!.eq(size * (size - 1) / 2);
        final result = model.solveDetailed();
        expect(result.status, ContinuousSolveStatus.satisfied);
        expect(result.solution!.midpoint.values.reduce((a, b) => a + b),
            size * (size - 1) / 2);
        return result;
      }

      final small = run(100), large = run(400);
      expect(large.stats.linearTermVisits / small.stats.linearTermVisits,
          lessThanOrEqualTo(4.1));
      expect(large.stats.linearEvaluations, small.stats.linearEvaluations);
    });

    test('unchanged solves reuse structure and additions invalidate it', () {
      final model = ContinuousModel();
      final x = model.addVar('x', 0, 10);
      x.ge(2);
      final first = model.solveDetailed();
      final again = model.solveDetailed();
      expect(first.status, ContinuousSolveStatus.satisfied);
      expect(again.status, ContinuousSolveStatus.satisfied);
      expect(first.stats.structureReused, isFalse);
      expect(again.stats.structureReused, isTrue);
      expect(again.stats.structuralRevision, first.stats.structuralRevision);
      expect(again.solution!.midpoint, first.solution!.midpoint);

      x.ge(7);
      final edited = model.solveDetailed();
      expect(edited.status, ContinuousSolveStatus.satisfied);
      expect(edited.stats.structureReused, isFalse);
      expect(edited.stats.structuralRevision,
          greaterThan(first.stats.structuralRevision));
      expect(edited.solution!.midpoint['x'], greaterThanOrEqualTo(7 - 1e-6));
      expect(edited.stats.constraintCount, 2);
      model.addVar('y', 3, 3);
      final withVariable = model.solveDetailed();
      expect(withVariable.stats.structureReused, isFalse);
      expect(withVariable.stats.variableCount, 2);
      expect(withVariable.solution!.midpoint['y'], 3);
    });

    test('new product auxiliaries register all reverse dependencies', () {
      final model = ContinuousModel();
      final x = model.addVar('x', 0, 10);
      x.ge(2);
      expect(model.solveDetailed().isSatisfied, isTrue);
      (x * x).eq(9);
      final result = model.solveDetailed(epsilon: 1e-8);
      expect(result.status, ContinuousSolveStatus.satisfied);
      expect(result.solution!.midpoint['x'], closeTo(3, 1e-8));
      expect(result.stats.structureReused, isFalse);
      expect(result.stats.productEvaluations, greaterThan(0));
      expect(result.stats.variableCount, 2); // x and the compiled product
    });

    test('long dependency chains propagate to independently known coordinates',
        () {
      final model = ContinuousModel();
      final vars = [
        for (var i = 0; i < 64; i++) model.addVar('x$i', -100, 100)
      ];
      for (var i = 0; i < vars.length - 1; i++) {
        (vars[i + 1] - vars[i]).eq(1);
      }
      vars.last.eq(63);
      final result = model.solveDetailed(epsilon: 1e-8);
      expect(result.status, ContinuousSolveStatus.satisfied);
      for (var i = 0; i < vars.length; i++) {
        expect(result.solution!.midpoint['x$i'], closeTo(i, 1e-8));
      }
    });

    test('seeded determined linear systems agree with analytic solutions', () {
      final random = Random(1337);
      for (var trial = 0; trial < 60; trial++) {
        final a = random.nextInt(7) + 1, b = random.nextInt(7) + 1;
        final c = random.nextInt(7) + 1, d = -(random.nextInt(7) + 1);
        final targetX = (random.nextInt(13) - 6) / 2;
        final targetY = (random.nextInt(13) - 6) / 2;
        final rhs1 = a * targetX + b * targetY;
        final rhs2 = c * targetX + d * targetY;
        final determinant = a * d - b * c;
        final expectedX = (rhs1 * d - b * rhs2) / determinant;
        final expectedY = (a * rhs2 - rhs1 * c) / determinant;
        final model = ContinuousModel();
        final x = model.addVar('x', -10, 10), y = model.addVar('y', -10, 10);
        (x * a + y * b).eq(rhs1);
        (x * c + y * d).eq(rhs2);
        final result = model.solveDetailed(epsilon: 1e-8);
        expect(result.status, ContinuousSolveStatus.satisfied,
            reason: 'trial $trial');
        expect(result.solution!.midpoint['x'], closeTo(expectedX, 2e-8));
        expect(result.solution!.midpoint['y'], closeTo(expectedY, 2e-8));
      }
    });

    test('contradictory disconnected component is still found at the root', () {
      final model = ContinuousModel();
      model.addVar('free', 0, 100);
      final bad = model.addVar('bad', 0, 1);
      bad.ge(2);
      final result = model.solveDetailed();
      expect(result.status, ContinuousSolveStatus.infeasible);
      expect(result.splits, 0);
      expect(result.stats.contractorEvaluations, 1);
    });

    test(
        'long contractor evaluation observes cancellation and reports partial work',
        () {
      final model = ContinuousModel();
      FloatExpr? sum;
      for (var i = 0; i < 400; i++) {
        final v = model.addVar('x$i', 0, 1);
        sum = sum == null ? v : sum + v;
      }
      sum!.eq(200);
      var checks = 0;
      final result = model.solveDetailed(shouldCancel: () => ++checks > 100);
      expect(result.status, ContinuousSolveStatus.cancelled);
      expect(result.stats.linearTermVisits, greaterThan(0));
      expect(result.stats.linearTermVisits, lessThan(400));
      expect(result.splits, 0);
    });

    test('returned work counters are immutable per-call snapshots', () {
      final model = ContinuousModel();
      model.addVar('x', 0, 1).eq(0);
      final first = model.solveDetailed();
      final counts = Map<String, int>.of(first.stats.constraintEvaluations);
      model.solveDetailed(epsilon: 1e-9);
      expect(first.stats.constraintEvaluations, counts);
      expect(first.stats.constraintEvaluations.clear, throwsUnsupportedError);
    });
  });
}

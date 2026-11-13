import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('continuous audit: safe arithmetic', () {
    test('midpoints remain inside extreme finite intervals', () {
      const intervals = [
        Interval(-1e308, 1e308),
        Interval(1e308, 1.6e308),
        Interval(-1.6e308, -1e308),
        Interval(-1e308, 1.6e308),
        Interval(0, 5e-324),
      ];
      for (final interval in intervals) {
        expect(interval.mid.isFinite, isTrue, reason: '$interval');
        expect(interval.contains(interval.mid), isTrue, reason: '$interval');
      }
      expect(const Interval(-1e308, 1e308).mid, 0);
    });

    test('square ranges preserve repeated-operand nonnegativity', () {
      for (final rounding in IntervalRounding.values) {
        final crossing = rounding.square(const Interval(-2, 3));
        expect(crossing.lo, 0);
        expect(crossing.hi, greaterThanOrEqualTo(9));
        final negative = rounding.square(const Interval(-3, -2));
        expect(negative.lo, lessThanOrEqualTo(4));
        expect(negative.hi, greaterThanOrEqualTo(9));
        expect(negative.lo, greaterThanOrEqualTo(0));
      }
    });

    test('typed DSL auxiliary bounds enclose cancellation-sensitive sums',
        () async {
      final m = Model();
      m.problem.floatRounding = IntervalRounding.outward;
      final x = m.realVar('x', 1e16, 1e16);
      final y = m.realVar('y', 1, 1);
      final z = m.realVar('z', -1e16, -1e16);
      final w = m.realVar('w', 1, 1);
      ((x + y + z) * w).eq(1);
      expect(await m.problem.getSolution(), isA<Map<String, dynamic>>());
    });

    test('standalone auxiliary names cannot overwrite user domains', () {
      final m = ContinuousModel();
      m.addVar('__aux0', 0, 0);
      final x = m.addVar('x', 2, 2);
      (x * x).eq(4);
      final result = m.solveDetailed();
      expect(result.status, ContinuousSolveStatus.satisfied);
      expect(result.solution!.midpoint['__aux0'], 0);
      expect(result.solution!.midpoint['x'], 2);
    });
  });

  group('continuous audit: termination and result contracts', () {
    test('a feasible problem exhausting its split budget is not infeasible',
        () {
      final m = ContinuousModel()..addVar('x', 0, 1);
      final result = m.solveDetailed(maxSplits: 0);
      expect(result.status, ContinuousSolveStatus.splitLimit);
      expect(result.splits, 0);
      expect(result.certifiedInfeasible, isFalse);
      expect(result.solution, isNull);
      expect(m.solve(maxSplits: 0), isNull);
    });

    test('sub-ULP precision terminates without identical-child recursion', () {
      final m = ContinuousModel()..addVar('x', 1, IntervalRounding.nextUp(1));
      final result = m.solveDetailed(epsilon: 1e-30);
      expect(result.status, ContinuousSolveStatus.precisionLimit);
      expect(result.splits, 0);
      expect(result.candidate!.midpoint['x']!.isFinite, isTrue);
      expect(m.solve(epsilon: 1e-30), isNull);
    });

    test('immediate and in-work cancellation are explicit', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      x.ge(1);
      x.le(9);
      expect(m.solveDetailed(shouldCancel: () => true).status,
          ContinuousSolveStatus.cancelled);
      var checks = 0;
      final result = m.solveDetailed(shouldCancel: () => ++checks >= 3);
      expect(result.status, ContinuousSolveStatus.cancelled);
      expect(result.certifiedInfeasible, isFalse);
    });

    test('invalid numeric solve controls are rejected', () {
      final m = ContinuousModel()..addVar('x', 0, 1);
      for (final epsilon in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => m.solveDetailed(epsilon: epsilon), throwsArgumentError);
      }
      expect(() => m.solveDetailed(maxSplits: -1), throwsArgumentError);
      expect(() => m.solveDetailed(absoluteTolerance: 0), throwsArgumentError);
      expect(() => m.solveDetailed(relativeTolerance: double.nan),
          throwsArgumentError);
    });

    test('non-finite derived arithmetic is a numerical failure', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 1e308, 1e308);
      final y = m.addVar('y', 1e308, 1e308);
      (x * y).ge(0);
      final result = m.solveDetailed();
      expect(result.status, ContinuousSolveStatus.numericalFailure);
      expect(result.certifiedInfeasible, isFalse);
    });
  });

  group('continuous audit: original-expression residuals', () {
    test('an impossible negative square is excluded before bisection', () {
      final m = ContinuousModel();
      final x = m.addVar('x', -1e-7, 1e-7);
      (x * x * 1e14).eq(-1);
      final result = m.solveDetailed();
      expect(result.status, ContinuousSolveStatus.infeasible);
      expect(result.splits, 0);
      expect(result.solution, isNull);
      expect(m.solve(), isNull);
    });

    test('a narrow box cannot conceal an amplified auxiliary residual', () {
      final m = ContinuousModel();
      final x = m.addVar('x', -1e-7, 1e-7);
      final y = m.addVar('y', -1e-7, 1e-7);
      (x * y * 1e14).eq(1);
      final result = m.solveDetailed();
      // Feasible endpoints exist, but the initial narrow box's midpoint is
      // not a solution. Return a candidate rather than inventing infeasibility.
      expect(result.status, ContinuousSolveStatus.candidate);
      expect(result.candidate!.midpoint, {'x': 0.0, 'y': 0.0});
      expect(result.residuals.any((r) => r.violation >= 1), isTrue);
      expect(result.maxNormalizedViolation, greaterThan(1));
      expect(result.solution, isNull);
      expect(m.solve(), isNull);
    });

    test('derived expressions are evaluated in topological order', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 2, 2);
      final y = m.addVar('y', 3, 3);
      (((x + y) * x + 1) * y).eq(33);
      final result = m.solveDetailed();
      expect(result.status, ContinuousSolveStatus.satisfied);
      expect(result.residuals.every((r) => r.isSatisfied), isTrue);
      expect(result.maxNormalizedViolation, lessThanOrEqualTo(1));
    });

    test('compensated evaluation preserves cancellation-sensitive expressions',
        () {
      final m = ContinuousModel();
      final x = m.addVar('x', 1e16, 1e16);
      final y = m.addVar('y', 1, 1);
      final z = m.addVar('z', -1e16, -1e16);
      final w = m.addVar('w', 1, 1);
      ((x + y + z) * w).eq(1);
      final result = m.solveDetailed();
      expect(result.status, ContinuousSolveStatus.satisfied);
      expect(result.residuals.every((r) => r.isSatisfied), isTrue);
    });

    test('ordinary circle-line intersection passes independent geometry checks',
        () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 1);
      final y = m.addVar('y', 0, 1);
      (x * x + y * y).eq(1);
      x.eq(y);
      final result = m.solveDetailed(epsilon: 1e-8);
      expect(result.status, ContinuousSolveStatus.satisfied);
      final point = result.solution!.midpoint;
      expect(point['x']! * point['x']! + point['y']! * point['y']!,
          closeTo(1, 3e-8));
      expect(point['x'], closeTo(point['y']!, 1e-8));
    });
  });
}

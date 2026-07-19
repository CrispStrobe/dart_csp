import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Interval', () {
    test('width, mid, contains', () {
      const i = Interval(2, 6);
      expect(i.width, 4);
      expect(i.mid, 4);
      expect(i.contains(2), isTrue);
      expect(i.contains(6), isTrue);
      expect(i.contains(6.1), isFalse);
    });

    test('arithmetic', () {
      const a = Interval(1, 2);
      const b = Interval(3, 5);
      expect((a + b).lo, 4);
      expect((a + b).hi, 7);
      expect((a - b).lo, closeTo(-4, 1e-12)); // 1-5
      expect((a - b).hi, closeTo(-1, 1e-12)); // 2-3
      expect(a.scale(2).lo, 2);
      expect(a.scale(2).hi, 4);
      expect(a.scale(-1).lo, -2); // orientation preserved
      expect(a.scale(-1).hi, -1);
    });

    test('intersect and emptiness', () {
      expect(const Interval(0, 5).intersect(const Interval(3, 9)).lo, 3);
      expect(const Interval(0, 5).intersect(const Interval(3, 9)).hi, 5);
      expect(
          const Interval(0, 2).intersect(const Interval(5, 9)).isEmpty, isTrue);
    });
  });

  group('solving linear continuous problems', () {
    // Assert a solution's midpoint satisfies each constraint within a
    // tolerance scaled to the requested epsilon.
    void expectSatisfies(
        Map<String, double> pt, double Function(Map<String, double>) lhs,
        {required String op, required double rhs, double tol = 1e-3}) {
      final v = lhs(pt);
      switch (op) {
        case '<=':
          expect(v, lessThanOrEqualTo(rhs + tol));
        case '>=':
          expect(v, greaterThanOrEqualTo(rhs - tol));
        case '==':
          expect(v, closeTo(rhs, tol));
      }
    }

    test('a determined 2x2 equality system converges to its solution',
        () async {
      // x + y == 10, x - y == 4  ->  x = 7, y = 3.
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      final y = m.addVar('y', 0, 10);
      (x + y).eq(10);
      (x - y).eq(4);
      final sol = m.solve()!;
      final p = sol.midpoint;
      expect(p['x'], closeTo(7, 1e-3));
      expect(p['y'], closeTo(3, 1e-3));
      // Every returned box is narrow.
      for (final iv in sol.box.values) {
        expect(iv.width, lessThanOrEqualTo(1e-6 + 1e-12));
      }
    });

    test('inequalities isolate a feasible point', () {
      // 2 <= x <= 3, no equality: any x in [2,3] is valid.
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      x.le(3);
      x.ge(2);
      final p = m.solve()!.midpoint;
      expect(p['x'], inInclusiveRange(2, 3));
    });

    test('a scaled linear constraint', () {
      // 3x + 2y == 12, x == 2  -> y = 3.
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      final y = m.addVar('y', 0, 10);
      (x * 3 + y * 2).eq(12);
      x.eq(2);
      final p = m.solve(epsilon: 1e-7)!.midpoint;
      expectSatisfies(p, (pt) => 3 * pt['x']! + 2 * pt['y']!,
          op: '==', rhs: 12);
      expect(p['y'], closeTo(3, 1e-3));
    });

    test('a small LP-feasibility region', () {
      // x + y <= 4, x >= 1, y >= 1, x,y in [0,10].
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      final y = m.addVar('y', 0, 10);
      (x + y).le(4);
      x.ge(1);
      y.ge(1);
      final p = m.solve()!.midpoint;
      expectSatisfies(p, (pt) => pt['x']! + pt['y']!, op: '<=', rhs: 4);
      expectSatisfies(p, (pt) => pt['x']!, op: '>=', rhs: 1);
      expectSatisfies(p, (pt) => pt['y']!, op: '>=', rhs: 1);
    });

    test('fractional solution the integer engine could not represent', () {
      // 2x == 1 -> x = 0.5.
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 1);
      (x * 2).eq(1);
      expect(m.solve(epsilon: 1e-8)!.midpoint['x'], closeTo(0.5, 1e-3));
    });
  });

  group('infeasibility', () {
    test('contradictory bounds -> null', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      x.ge(5);
      x.le(3);
      expect(m.solve(), isNull);
    });

    test('inconsistent equalities -> null', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      final y = m.addVar('y', 0, 10);
      (x + y).eq(5);
      (x + y).eq(9); // same sum can't be both
      expect(m.solve(), isNull);
    });
  });

  group('DSL and validation', () {
    test('unary minus and subtraction', () {
      // -x + 10 == y, x == 4 -> y = 6.
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 10);
      final y = m.addVar('y', 0, 10);
      (-x + 10).eq(y);
      x.eq(4);
      expect(m.solve(epsilon: 1e-7)!.midpoint['y'], closeTo(6, 1e-3));
    });

    test('a trivially-true constant relation is a no-op', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      expect(() => (x - x).le(0), returnsNormally); // 0 <= 0
    });

    test('a contradictory constant relation throws', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      expect(() => (x - x).eq(1), throwsArgumentError); // 0 == 1
    });

    test('mixing two models throws', () {
      final m1 = ContinuousModel();
      final m2 = ContinuousModel();
      final x = m1.addVar('x', 0, 5);
      final y = m2.addVar('y', 0, 5);
      expect(() => (x + y).eq(1), throwsArgumentError);
    });

    test('bad variable bounds throw', () {
      final m = ContinuousModel();
      expect(() => m.addVar('x', 5, 3), throwsArgumentError); // lo > hi
      expect(() => m.addVar('y', double.infinity, 1), throwsArgumentError);
      m.addVar('z', 0, 1);
      expect(() => m.addVar('z', 0, 2), throwsArgumentError); // duplicate
    });

    test('epsilon must be positive', () {
      final m = ContinuousModel();
      m.addVar('x', 0, 1);
      expect(() => m.solve(epsilon: 0), throwsArgumentError);
    });
  });
}

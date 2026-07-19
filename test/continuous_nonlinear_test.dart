import 'dart:math' as math;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Interval multiplication and division', () {
    test('product spans the four endpoint products', () {
      expect((const Interval(2, 3) * const Interval(4, 5)).lo, 8);
      expect((const Interval(2, 3) * const Interval(4, 5)).hi, 15);
      // Sign-crossing operands.
      final p = const Interval(-2, 3) * const Interval(-1, 4);
      expect(p.lo, -8); // 2 * -4? no: min(2, -8, -3, 12) = -8
      expect(p.hi, 12);
    });

    test('division by a zero-free interval', () {
      final q = const Interval(6, 12).divide(const Interval(2, 3));
      expect(q.lo, closeTo(2, 1e-12)); // 6/3
      expect(q.hi, closeTo(6, 1e-12)); // 12/2
    });

    test('division by a zero-straddling interval returns the hull', () {
      final q = const Interval(1, 2).divide(const Interval(-1, 1));
      expect(q.lo, double.negativeInfinity);
      expect(q.hi, double.infinity);
    });
  });

  group('non-linear solving', () {
    void expectClose(double? got, double want, {double tol = 1e-2}) {
      expect(got, isNotNull);
      expect(got, closeTo(want, tol));
    }

    test('x * y == 6 and x + y == 5 -> {2,3}', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      final y = m.addVar('y', 0, 5);
      (x * y).eq(6);
      (x + y).eq(5);
      final sol = m.solve(epsilon: 1e-7)!;
      final p = sol.midpoint;
      // Either ordering is valid; check the product and sum hold.
      expect(p['x']! * p['y']!, closeTo(6, 1e-2));
      expect(p['x']! + p['y']!, closeTo(5, 1e-2));
      // The solution reports only the user's variables, no aux.
      expect(sol.box.keys.toSet(), {'x', 'y'});
    });

    test('x squared == 2 -> x ≈ sqrt(2)', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 2);
      (x * x).eq(2);
      expectClose(m.solve(epsilon: 1e-9)!.midpoint['x'], math.sqrt(2));
    });

    test('a product with a linear factor: (x + 1) * y == 6, x == 2', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      final y = m.addVar('y', 0, 5);
      ((x + 1) * y).eq(6); // (2+1)*y = 6 -> y = 2
      x.eq(2);
      final p = m.solve(epsilon: 1e-8)!.midpoint;
      expect(p['x'], closeTo(2, 1e-2));
      expect(p['y'], closeTo(2, 1e-2));
    });

    test('scalar multiply still stays linear (no aux introduced)', () {
      // 2 * x == 5 -> x = 2.5, purely linear.
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      (x * 2).eq(5);
      final sol = m.solve(epsilon: 1e-9)!;
      expect(sol.box.keys.toSet(), {'x'}); // no aux var created
      expect(sol.midpoint['x'], closeTo(2.5, 1e-6));
    });

    test('infeasible non-linear system -> null', () {
      // x * y == 100 with x, y in [0, 5] is impossible (max product 25).
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      final y = m.addVar('y', 0, 5);
      (x * y).eq(100);
      expect(m.solve(), isNull);
    });

    test('a circle-line intersection: x^2 + y^2 == 1, y == x', () {
      // x^2 + y^2 = 1 with y = x -> 2x^2 = 1 -> x = ±1/sqrt(2).
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 1); // pick the positive branch
      final y = m.addVar('y', 0, 1);
      (x * x + y * y).eq(1);
      y.eq(x);
      final p = m.solve(epsilon: 1e-7)!.midpoint;
      final r = math.sqrt(p['x']! * p['x']! + p['y']! * p['y']!);
      expect(r, closeTo(1, 1e-2));
      expect(p['x'], closeTo(1 / math.sqrt(2), 1e-2));
    });
  });

  group('soundness sweep (random non-linear systems)', () {
    test('every returned solution satisfies its constraints', () {
      final rng = math.Random(20260719);
      var solved = 0;
      for (var trial = 0; trial < 200; trial++) {
        // Random target for x*y == t and x + y == s with x,y in [0,6].
        final xv = rng.nextDouble() * 5 + 0.5; // [0.5, 5.5]
        final yv = rng.nextDouble() * 5 + 0.5;
        final s = xv + yv;
        final t = xv * yv;
        final m = ContinuousModel();
        final x = m.addVar('x', 0, 6);
        final y = m.addVar('y', 0, 6);
        (x * y).eq(t);
        (x + y).eq(s);
        final sol = m.solve();
        if (sol == null) continue; // some may hit the split budget
        solved++;
        final p = sol.midpoint;
        expect(p['x']! + p['y']!, closeTo(s, 1e-2));
        expect(p['x']! * p['y']!, closeTo(t, 1e-2));
      }
      // The construction is always feasible, so the vast majority solve.
      expect(solved, greaterThan(180));
    });
  });
}

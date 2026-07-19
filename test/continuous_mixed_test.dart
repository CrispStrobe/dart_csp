import 'dart:math' as math;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Whether [v] is (within tolerance) a whole number.
bool _isInt(double v) => (v - v.roundToDouble()).abs() < 1e-6;

void main() {
  group('integer variables', () {
    test('a pure integer linear equation', () {
      // 2n == 6 -> n = 3.
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 10);
      (n * 2).eq(6);
      final p = m.solve()!.midpoint;
      expect(p['n'], 3.0);
    });

    test('an integer variable never returns a fractional value', () {
      // 3n == 7 has no integer solution -> infeasible.
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 10);
      (n * 3).eq(7);
      expect(m.solve(), isNull);
    });

    test('integer range with inequalities enumerates a whole value', () {
      // 2 < n < 5, n integer -> n in {3, 4}; solver returns one of them.
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 10);
      n.ge(3);
      n.le(4);
      final v = m.solve()!.midpoint['n']!;
      expect(_isInt(v), isTrue);
      expect([3.0, 4.0], contains(v));
    });

    test('a non-linear integer equation: n squared == 9 -> n = 3', () {
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 5);
      (n * n).eq(9);
      expect(m.solve()!.midpoint['n'], 3.0);
    });

    test('n squared == 8 has no integer solution -> null', () {
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 5);
      (n * n).eq(8);
      expect(m.solve(), isNull);
    });

    test('empty / duplicate integer domains throw', () {
      final m = ContinuousModel();
      expect(() => m.addIntVar('n', 5, 3), throwsArgumentError);
      m.addIntVar('k', 0, 3);
      expect(() => m.addIntVar('k', 0, 3), throwsArgumentError);
      expect(() => m.addVar('k', 0, 3), throwsArgumentError); // name clash
    });
  });

  group('mixed integer + continuous models', () {
    test('x == 2.5 * n with n integer, x continuous', () {
      // n in [1,4] int, x in [0,20] real, x == 2.5 n. A solution must have
      // n integral and x == 2.5 n.
      final m = ContinuousModel();
      final n = m.addIntVar('n', 1, 4);
      final x = m.addVar('x', 0, 20);
      (x - n * 2.5).eq(0);
      final p = m.solve(epsilon: 1e-7)!.midpoint;
      expect(_isInt(p['n']!), isTrue);
      expect(p['x'], closeTo(2.5 * p['n']!, 1e-2));
    });

    test('a fractional constraint forces a specific integer', () {
      // x == n / 2, x == 1.5  ->  n == 3 (integer), x == 1.5 (real).
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 10);
      final x = m.addVar('x', 0, 10);
      (x * 2 - n * 1).eq(0); // 2x == n  -> x == n/2
      x.eq(1.5);
      final p = m.solve(epsilon: 1e-8)!.midpoint;
      expect(p['n'], 3.0);
      expect(p['x'], closeTo(1.5, 1e-3));
    });

    test('mixed infeasibility: x == n + 0.5 with x integer too', () {
      // Both integer, differing by 0.5 -> impossible.
      final m = ContinuousModel();
      final n = m.addIntVar('n', 0, 5);
      final k = m.addIntVar('k', 0, 5);
      (k - n).eq(0.5); // integer difference can't be 0.5
      expect(m.solve(), isNull);
    });

    test('a small mixed optimization-flavoured feasibility problem', () {
      // area == w * h, w integer in [1,10], h real in [0,10], area == 15,
      // and w <= 5. Feasible: e.g. w=3, h=5 or w=5,h=3.
      final m = ContinuousModel();
      final w = m.addIntVar('w', 1, 10);
      final h = m.addVar('h', 0, 10);
      (w * h).eq(15);
      w.le(5);
      final p = m.solve()!.midpoint;
      expect(_isInt(p['w']!), isTrue);
      expect(p['w'], lessThanOrEqualTo(5));
      expect(p['w']! * p['h']!, closeTo(15, 1e-2));
    });
  });

  group('soundness sweep (mixed int/float)', () {
    test('every solution has integral integer vars and satisfies constraints',
        () {
      final rng = math.Random(20260719);
      var solved = 0;
      for (var trial = 0; trial < 150; trial++) {
        final nv = rng.nextInt(6) + 1; // integer target 1..6
        final scale = (rng.nextInt(20) + 1) / 4.0; // 0.25 .. 5.0
        final target = nv * scale;
        final m = ContinuousModel();
        final n = m.addIntVar('n', 0, 8);
        final x = m.addVar('x', 0, 40);
        (x - n * scale).eq(0); // x == scale * n
        x.eq(target); // pins n == nv
        final sol = m.solve();
        if (sol == null) continue;
        solved++;
        final p = sol.midpoint;
        expect(_isInt(p['n']!), isTrue,
            reason: 'integer variable must resolve to a whole number');
        expect(p['x'], closeTo(scale * p['n']!, 1e-2));
      }
      expect(solved, greaterThan(140));
    });
  });
}

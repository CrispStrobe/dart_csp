// Directed rounding for interval arithmetic (`IntervalRounding`).
//
// Two things are under test. First `nextUp` / `nextDown`, the ULP-step
// primitives — they are pure bit manipulation and every interesting case
// is an edge case (zero, subnormals, sign changes, infinities), so they
// are checked exhaustively rather than by example. Second the
// containment property that everything else rests on: an `outward`
// result must enclose the corresponding `exact` one.

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

const up = IntervalRounding.nextUp;
const down = IntervalRounding.nextDown;

void main() {
  group('nextUp / nextDown', () {
    test('step to an adjacent double', () {
      expect(up(1.0), 1.0 + 2.220446049250313e-16); // 1 + 2^-52
      expect(down(1.0), 0.9999999999999999);
      expect(up(1.0), greaterThan(1.0));
      expect(down(1.0), lessThan(1.0));
    });

    test('are exact inverses, i.e. the step is minimal', () {
      // If any double lay strictly between x and nextUp(x), stepping
      // back down would not return x.
      for (final x in [
        1.0, -1.0, 0.5, -0.5, 123.456, -123.456,
        1e300, -1e300, 1e-300, -1e-300,
        5e-324, -5e-324, // subnormals
        double.maxFinite, -double.maxFinite,
      ]) {
        expect(down(up(x)), x, reason: 'down(up($x))');
        expect(up(down(x)), x, reason: 'up(down($x))');
      }
    });

    test('cross zero correctly', () {
      // Zero is the discontinuity in the sign-magnitude bit layout.
      expect(up(0.0), 5e-324); // smallest positive subnormal
      expect(down(0.0), -5e-324);
      expect(up(-0.0), 5e-324);
      expect(down(-0.0), -5e-324);
      expect(down(5e-324), 0.0);
      expect(up(-5e-324), isZero);
    });

    test('saturate at the infinities', () {
      expect(up(double.infinity), double.infinity);
      expect(down(double.negativeInfinity), double.negativeInfinity);
      // Stepping inward from an infinity lands on the extreme finite.
      expect(up(double.negativeInfinity), -double.maxFinite);
      expect(down(double.infinity), double.maxFinite);
      // And stepping outward from the extreme finite reaches infinity.
      expect(up(double.maxFinite), double.infinity);
      expect(down(-double.maxFinite), double.negativeInfinity);
    });

    test('propagate NaN', () {
      expect(up(double.nan).isNaN, isTrue);
      expect(down(double.nan).isNaN, isTrue);
    });

    test('are strictly monotone over random doubles', () {
      final rng = Random(31337);
      for (var i = 0; i < 2000; i++) {
        final x = (rng.nextDouble() - 0.5) * pow(10, rng.nextInt(40) - 20);
        expect(up(x), greaterThan(x), reason: '$x');
        expect(down(x), lessThan(x), reason: '$x');
      }
    });
  });

  group('rounded interval operations', () {
    test('exact mode leaves the arithmetic untouched', () {
      const a = Interval(1, 2), b = Interval(3, 5);
      const e = IntervalRounding.exact;
      expect(e.add(a, b).lo, 4);
      expect(e.add(a, b).hi, 7);
      expect(e.sub(a, b).lo, closeTo(-4, 1e-12));
      expect(e.mul(a, b).lo, 3);
      expect(e.mul(a, b).hi, 10);
      expect(e.scale(a, -1).lo, -2);
    });

    test('outward mode encloses the exact result', () {
      // The containment property everything else rests on: whatever the
      // exact arithmetic computed, the outward result contains it — and
      // therefore also contains the true real result, which lies within
      // half an ULP of the exact one.
      final rng = Random(24680);
      const e = IntervalRounding.exact, o = IntervalRounding.outward;
      Interval randInterval() {
        final a = (rng.nextDouble() - 0.5) * 200;
        final b = (rng.nextDouble() - 0.5) * 200;
        return Interval(min(a, b), max(a, b));
      }

      void encloses(Interval outer, Interval inner, String op) {
        expect(outer.lo, lessThanOrEqualTo(inner.lo), reason: '$op lo');
        expect(outer.hi, greaterThanOrEqualTo(inner.hi), reason: '$op hi');
      }

      for (var i = 0; i < 500; i++) {
        final a = randInterval(), b = randInterval();
        encloses(o.add(a, b), e.add(a, b), 'add');
        encloses(o.sub(a, b), e.sub(a, b), 'sub');
        encloses(o.mul(a, b), e.mul(a, b), 'mul');
        final c = (rng.nextDouble() - 0.5) * 20;
        encloses(o.scale(a, c), e.scale(a, c), 'scale');
        // Division is only defined away from a zero-containing divisor;
        // when the divisor straddles zero both modes return the whole
        // line, which trivially encloses.
        encloses(o.div(a, b), e.div(a, b), 'div');
      }
    });

    test('division by a zero-containing interval stays the whole line', () {
      for (final r in IntervalRounding.values) {
        final q = r.div(const Interval(1, 2), const Interval(-1, 3));
        expect(q.lo, double.negativeInfinity);
        expect(q.hi, double.infinity);
      }
    });
  });

  group('rounding in the isolated solver', () {
    test('both modes solve a linear system to within epsilon', () {
      for (final r in IntervalRounding.values) {
        final m = ContinuousModel();
        final x = m.addVar('x', 0, 10);
        final y = m.addVar('y', 0, 10);
        (x + y).eq(10);
        (x - y).eq(4);
        final sol = m.solve(epsilon: 1e-9, rounding: r);
        expect(sol, isNotNull, reason: '$r');
        expect(sol!.midpoint['x'], closeTo(7, 1e-6), reason: '$r');
        expect(sol.midpoint['y'], closeTo(3, 1e-6), reason: '$r');
      }
    });

    test('outward rounding still solves a non-linear system', () {
      final m = ContinuousModel();
      final x = m.addVar('x', 0, 5);
      (x * x).eq(2);
      final sol = m.solve(epsilon: 1e-9, rounding: IntervalRounding.outward);
      expect(sol, isNotNull);
      expect(sol!.midpoint['x'], closeTo(sqrt2, 1e-6));
    });
  });

  group('rounding in the main engine', () {
    test('outward never loses a solution that exact finds', () async {
      // The property that makes the mode worth having. Outward rounding
      // only ever widens, so it can report SAT where exact reports
      // FAILURE (it prunes less) — but never the reverse. A violation
      // would mean the widening is not actually outward.
      final rng = Random(13579);
      for (var trial = 0; trial < 150; trial++) {
        Problem build(IntervalRounding r) {
          final p = Problem()..floatRounding = r;
          p.addRangeVariable('n', 0, 6);
          p.addFloatVariable('x', -5, 5);
          p.setFloatEpsilon(1e-7);
          return p;
        }

        final cn = (rng.nextInt(9) - 4).toDouble();
        final cx = (rng.nextInt(9) - 4).toDouble();
        final b = (rng.nextInt(41) - 20) / 2.0;
        final op = rng.nextInt(3);
        void post(Problem p) {
          switch (op) {
            case 0:
              p.addLinearEquals(['n', 'x'], [cn, cx], b);
            case 1:
              p.addLinearLeq(['n', 'x'], [cn, cx], b);
            default:
              p.addLinearGeq(['n', 'x'], [cn, cx], b);
          }
        }

        final pe = build(IntervalRounding.exact);
        post(pe);
        final po = build(IntervalRounding.outward);
        post(po);

        final re = await pe.getSolution();
        final ro = await po.getSolution();
        if (re is Map) {
          expect(ro, isA<Map<String, dynamic>>(),
              reason: 'trial $trial: exact found a solution but outward '
                  'reported FAILURE (cn=$cn cx=$cx op=$op b=$b)');
        }
      }
    });

    test('outward rounding solves mixed and product models', () async {
      final p = Problem()..floatRounding = IntervalRounding.outward;
      p.addRangeVariable('units', 0, 20);
      p.addFloatVariable('price', 0.0, 100.0);
      p.addLinearLeq(['units', 'price'], [2, 1.5], 40);
      p.addLinearGeq(['units'], [1], 12);
      final sol = await p.getSolution() as Map<String, dynamic>;
      expect(2 * (sol['units'] as int) + 1.5 * (sol['price'] as double),
          lessThanOrEqualTo(40 + 1e-6));

      final q = Problem()..floatRounding = IntervalRounding.outward;
      q.addFloatVariable('x', 0, 10);
      q.addFloatVariable('y', 0, 10);
      q.addFloatVariable('xy', 0, 100);
      q.addFloatProduct('xy', 'x', 'y');
      q.addLinearEquals(['xy'], [1], 6);
      q.addLinearEquals(['x', 'y'], [1, 1], 5);
      final qs = await q.getSolution() as Map<String, dynamic>;
      final x = qs['x'] as double, y = qs['y'] as double;
      expect(x * y, closeTo(6, 1e-4));
      expect(x + y, closeTo(5, 1e-4));
    });

    test('outward rounding optimizes and copy() carries the mode', () async {
      final p = Problem()..floatRounding = IntervalRounding.outward;
      p.addRangeVariable('n', 3, 9);
      p.addFloatVariable('cost', 0.0, 100.0);
      p.addLinearGeq(['cost', 'n'], [1, -2], 1.5);
      expect(p.copy().floatRounding, IntervalRounding.outward);
      final best = await p.minimize('cost') as Map<String, dynamic>;
      expect(best['n'], 3);
      expect(best['cost'] as double, closeTo(7.5, 1e-4));
    });

    test('an infeasible model is still infeasible under outward rounding',
        () async {
      // Outward prunes strictly less, so this is the direction where a
      // FAILURE actually means something: nothing was discarded by
      // arithmetic error.
      final p = Problem()..floatRounding = IntervalRounding.outward;
      p.addRangeVariable('n', 5, 10);
      p.addFloatVariable('f', 0.0, 1.0);
      p.addLinearLeq(['n', 'f'], [1, 1], 3);
      expect(await p.getSolution(), 'FAILURE');
    });
  });
}

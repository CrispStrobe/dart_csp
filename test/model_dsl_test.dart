import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('LinearExpr arithmetic', () {
    test('+, -, * build the expected term map (via a solved model)', () async {
      // 2x + 3y == 12, x,y in 0..5 — check a known solution satisfies it and
      // the expression lowered correctly by solving.
      final m = Model();
      final x = m.intVar('x', 0, 5);
      final y = m.intVar('y', 0, 5);
      (x * 2 + y * 3).eq(12);
      final sol = await m.problem.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      final xv = sol['x'] as int, yv = sol['y'] as int;
      expect(2 * xv + 3 * yv, 12);
    });

    test('unary minus and subtraction: x - y == 0 forces equality', () async {
      final m = Model();
      final x = m.intVar('x', 0, 4);
      final y = m.intVar('y', 0, 4);
      (x - y).eq(0);
      await for (final s in m.problem.getSolutions()) {
        expect(s['x'], equals(s['y']));
      }
    });

    test('scaled() matches operator *', () async {
      final m = Model();
      final x = m.intVar('x', 0, 10);
      x.scaled(2).eq(6);
      final sol = await m.problem.getSolution();
      expect(sol['x'], 3);
    });

    test('LinearExpr.sum over a list', () async {
      final m = Model();
      final xs = m.intVarList(['a', 'b', 'c'], 1, 9);
      LinearExpr.sum(xs).eq(24);
      m.problem.addAllDifferent(['a', 'b', 'c']);
      final sol = await m.problem.getSolution();
      final total = (sol['a'] as int) + (sol['b'] as int) + (sol['c'] as int);
      expect(total, 24);
      expect({sol['a'], sol['b'], sol['c']}, hasLength(3));
    });
  });

  group('relations', () {
    test('eq to a constant pins the variable', () async {
      final m = Model();
      final x = m.intVar('x', 0, 10);
      x.eq(7);
      expect((await m.problem.getSolution())['x'], 7);
    });

    test('le / ge bound the domain', () async {
      final m = Model();
      final x = m.intVar('x', 0, 10);
      x.le(3);
      x.ge(2);
      final vals = <int>{};
      await for (final s in m.problem.getSolutions()) {
        vals.add(s['x'] as int);
      }
      expect(vals, {2, 3});
    });

    test('lt / gt use integer-strict semantics', () async {
      final m = Model();
      final x = m.intVar('x', 0, 10);
      x.lt(3); // <= 2
      x.gt(0); // >= 1
      final vals = <int>{};
      await for (final s in m.problem.getSolutions()) {
        vals.add(s['x'] as int);
      }
      expect(vals, {1, 2});
    });

    test('ne between two variables (binary predicate path)', () async {
      final m = Model();
      final x = m.intVar('x', 0, 2);
      final y = m.intVar('y', 0, 2);
      x.ne(y);
      await for (final s in m.problem.getSolutions()) {
        expect(s['x'], isNot(equals(s['y'])));
      }
    });

    test('ne on a 3-term linear expression (nary predicate path)', () async {
      final m = Model();
      final x = m.intVar('x', 0, 2);
      final y = m.intVar('y', 0, 2);
      final z = m.intVar('z', 0, 2);
      (x + y + z).ne(3);
      await for (final s in m.problem.getSolutions()) {
        expect((s['x'] as int) + (s['y'] as int) + (s['z'] as int),
            isNot(equals(3)));
      }
    });

    test('ne to a constant', () async {
      final m = Model();
      final x = m.intVar('x', 0, 3);
      x.ne(2);
      final vals = <int>{};
      await for (final s in m.problem.getSolutions()) {
        vals.add(s['x'] as int);
      }
      expect(vals, {0, 1, 3});
    });
  });

  group('end-to-end models', () {
    test('a small system: x + y = 10, x - y = 2', () async {
      final m = Model();
      final x = m.intVar('x', 0, 10);
      final y = m.intVar('y', 0, 10);
      (x + y).eq(10);
      (x - y).eq(2);
      final sol = await m.problem.getSolution();
      expect(sol['x'], 6);
      expect(sol['y'], 4);
    });

    test('4-queens expressed with the DSL', () async {
      final m = Model();
      final q = m.intVarList(['q0', 'q1', 'q2', 'q3'], 0, 3);
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          q[i].ne(q[j]); // distinct columns
          // no two on the same diagonal: qi - qj != ±(j - i)
          (q[i] - q[j]).ne(j - i);
          (q[i] - q[j]).ne(-(j - i));
        }
      }
      final sol = await m.problem.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      final cols = [for (var i = 0; i < 4; i++) sol['q$i'] as int];
      // Verify it's a real solution.
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect(cols[i], isNot(equals(cols[j])));
          expect((cols[i] - cols[j]).abs(), isNot(equals(j - i)));
        }
      }
    });

    test('wraps an existing Problem and mixes with ref()', () async {
      final p = Problem();
      p.addRangeVariable('a', 0, 5);
      final m = Model(p);
      final b = m.intVar('b', 0, 5);
      final a = m.ref('a');
      (a + b).eq(5);
      a.eq(2);
      final sol = await p.getSolution();
      expect(sol['a'], 2);
      expect(sol['b'], 3);
    });
  });

  group('error handling', () {
    test('mixing two Models throws', () {
      final m1 = Model();
      final m2 = Model();
      final x = m1.intVar('x', 0, 5);
      final y = m2.intVar('y', 0, 5);
      expect(() => (x + y).eq(1), throwsArgumentError);
    });

    test('a contradictory constant relation throws', () {
      final m = Model();
      final x = m.intVar('x', 0, 5);
      // x - x reduces to 0; 0 == 1 is contradictory.
      expect(() => (x - x).eq(1), throwsArgumentError);
    });

    test('a trivially-true constant relation is a no-op', () async {
      final m = Model();
      final x = m.intVar('x', 0, 5);
      expect(() => (x - x).eq(0), returnsNormally); // 0 == 0
      x.eq(3);
      expect((await m.problem.getSolution())['x'], 3);
    });

    test('ref() to an unknown variable throws', () {
      final m = Model();
      expect(() => m.ref('nope'), throwsArgumentError);
    });
  });

  group('continuous variables in the DSL', () {
    const tol = 1e-4;

    test('realVar joins ordinary expressions', () async {
      final m = Model();
      final n = m.intVar('units', 0, 20);
      final price = m.realVar('price', 0, 100);
      (n * 2 + price * 1.5).le(40);
      n.ge(12);
      price.ge(10);
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      final u = sol['units'] as int;
      final pr = sol['price'] as double;
      expect(u, greaterThanOrEqualTo(12));
      expect(pr, greaterThanOrEqualTo(10 - tol));
      expect(2 * u + 1.5 * pr, lessThanOrEqualTo(40 + tol));
    });

    test('realVarList and ref', () async {
      final m = Model();
      final vs = m.realVarList(['a', 'b'], 0, 10);
      expect(vs, hasLength(2));
      (vs[0] + vs[1]).eq(7);
      vs[0].eq(3);
      expect(m.ref('a'), isA<RealVar>());
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      expect(sol['b'] as double, closeTo(4, tol));
    });

    test('expression * expression builds a product', () async {
      final m = Model();
      final x = m.realVar('x', 0, 10);
      final y = m.realVar('y', 0, 10);
      (x * y).eq(6);
      (x + y).eq(5);
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      final xv = sol['x'] as double, yv = sol['y'] as double;
      expect(xv * yv, closeTo(6, tol));
      expect(xv + yv, closeTo(5, tol));
    });

    test('the auxiliary variables stay out of the solution', () async {
      final m = Model();
      final x = m.realVar('x', 0, 5);
      (x * x).eq(2);
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      expect(sol.keys, ['x'], reason: 'aux product variables must be hidden');
      expect(sol['x'] as double, closeTo(1.4142135623730951, tol));
    });

    test('a sum of products: circle meets line', () async {
      final m = Model();
      final a = m.realVar('a', 0, 10);
      final b = m.realVar('b', 0, 10);
      (a * a + b * b).eq(25);
      (a + b).eq(7);
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      final av = sol['a'] as double, bv = sol['b'] as double;
      expect(av * av + bv * bv, closeTo(25, 1e-3));
      expect(av + bv, closeTo(7, tol));
      expect(sol.keys.toSet(), {'a', 'b'});
    });

    test('a mixed integer x continuous product', () async {
      final m = Model();
      final k = m.intVar('k', 1, 20);
      final pr = m.realVar('pr', 0, 100);
      (k * pr).eq(100);
      pr.ge(12);
      pr.le(15);
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      expect(sol['k'], 7);
      expect(sol['pr'] as double, closeTo(100 / 7, tol));
    });

    test('Model.maximize takes an expression, and reports it', () async {
      final m = Model();
      final w = m.realVar('w', 0, 10);
      final h = m.realVar('h', 0, 4);
      (w + h).le(10);
      m.problem.setFloatEpsilon(1e-4);
      final best = await m.maximize(w * h) as Map<String, dynamic>;
      expect(best['w'] as double, closeTo(6, 1e-2));
      expect(best['h'] as double, closeTo(4, 1e-2));
      // The objective is an auxiliary, but an optimization result would be
      // useless without it, so it is reported anyway.
      final objective =
          best.entries.firstWhere((e) => e.key.startsWith('__mul'));
      expect(objective.value as double, closeTo(24, 1e-2));
    });

    test('Model.minimize takes a plain variable too', () async {
      final m = Model();
      final n = m.intVar('units', 0, 20);
      final price = m.realVar('price', 0, 100);
      (n * 2 + price * 1.5).ge(30);
      n.le(12);
      final best = await m.minimize(price) as Map<String, dynamic>;
      // 2*12 + 1.5*price >= 30  =>  price >= 4.
      expect(best['price'] as double, closeTo(4, 1e-3));
    });

    test('!= is rejected once a continuous variable is in scope', () {
      final m = Model();
      final r = m.realVar('r', 0, 1);
      expect(
        () => r.ne(0.5),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message.toString(), 'message', contains('!='))),
      );
    });

    test('strict < and > are rejected over the reals', () {
      final m = Model();
      final r = m.realVar('r', 0, 1);
      expect(() => r.lt(0.5), throwsArgumentError);
      expect(() => r.gt(0.5), throwsArgumentError);
      // The non-strict forms are fine.
      expect(() => r.le(0.5), returnsNormally);
      expect(() => r.ge(0.1), returnsNormally);
    });

    test('multiplying two enumerated expressions is rejected', () {
      final m = Model();
      final i = m.intVar('i', 0, 3);
      final j = m.intVar('j', 0, 3);
      expect(
        () => (i * j).eq(4),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message.toString(), 'message', contains('continuous'))),
      );
    });

    test('integer-only models keep strict and != relations', () async {
      // The guards above must not leak into a pure-integer model.
      final m = Model();
      final x = m.intVar('x', 0, 5);
      final y = m.intVar('y', 0, 5);
      x.ne(y);
      x.lt(3);
      y.gt(3);
      final sol = await m.problem.getSolution() as Map<String, dynamic>;
      expect(sol['x'] as int, lessThan(3));
      expect(sol['y'] as int, greaterThan(3));
    });
  });
}

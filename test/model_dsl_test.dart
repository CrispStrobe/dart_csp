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
}

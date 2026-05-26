import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Helper: parse + lower + solve and parse the standard FlatZinc
/// output back into a `Map<String, dynamic>` for assertion-friendliness.
/// Only the `name = value;` lines are decoded; array literals and the
/// `==========` / `=====UNSATISFIABLE=====` markers are returned via the
/// `meta` map.
({Map<String, int> values, Map<String, String> meta}) parseOutput(String out) {
  final values = <String, int>{};
  final meta = <String, String>{};
  for (final raw in out.trim().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line == '----------' || line == '==========') {
      meta['terminator'] = line;
      continue;
    }
    if (line.startsWith('=====') && line.endsWith('=====')) {
      meta['status'] = line;
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final name = line.substring(0, eq).trim();
    final rhs = line.substring(eq + 1, line.length - 1).trim();
    // Bool-typed outputs render as true/false; normalize back to 0/1
    // so the assertion code stays integer-only.
    if (rhs == 'true') {
      values[name] = 1;
      continue;
    }
    if (rhs == 'false') {
      values[name] = 0;
      continue;
    }
    final intVal = int.tryParse(rhs);
    if (intVal != null) values[name] = intVal;
  }
  return (values: values, meta: meta);
}

void main() {
  group('FlatZinc M2 — integer comparisons', () {
    test('int_eq(var, var) constrains both vars to share a value', () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'var 1..3: y :: output_var;\n'
        'constraint int_eq(x, y);\n'
        'solve satisfy;\n',
      );
      final p = parseOutput(out);
      expect(p.values['x'], p.values['y']);
    });

    test('int_eq(var, const) pins var to the constant', () async {
      final out = await FlatZinc.solve(
        'var 1..9: x :: output_var;\n'
        'constraint int_eq(x, 7);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['x'], 7);
    });

    test('int_eq(const, var) — symmetric form works too', () async {
      final out = await FlatZinc.solve(
        'var 1..9: x :: output_var;\n'
        'constraint int_eq(7, x);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['x'], 7);
    });

    test('int_ne forces values apart', () async {
      // With both x and y in {1, 2} and x != y, search picks x=1, y=2.
      final out = await FlatZinc.solve(
        'var 1..2: x :: output_var;\n'
        'var 1..2: y :: output_var;\n'
        'constraint int_ne(x, y);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x'], isNot(v['y']));
    });

    test('int_lt(x, y) — strict less-than', () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'var 1..3: y :: output_var;\n'
        'constraint int_lt(x, y);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x']! < v['y']!, isTrue);
    });

    test('int_le(x, y) — less-or-equal', () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'var 1..3: y :: output_var;\n'
        'constraint int_le(x, y);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x']! <= v['y']!, isTrue);
    });

    test('int_eq(const, const) tautology — solver still succeeds', () async {
      // `constraint int_eq(5, 5);` is a no-op; the model is sat as long
      // as everything else is sat.
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'constraint int_eq(5, 5);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['x'], isNotNull);
    });

    test('int_eq(const, const) contradiction marks UNSAT', () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'constraint int_eq(5, 6);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('=====UNSATISFIABLE====='));
    });
  });

  group('FlatZinc M2 — linear arithmetic', () {
    test('int_lin_eq with all vars solves a tiny linear system', () async {
      // 2*x + 3*y == 12  with x,y in 0..6 has many sols; first is x=0,y=4.
      final out = await FlatZinc.solve(
        'var 0..6: x :: output_var;\n'
        'var 0..6: y :: output_var;\n'
        'constraint int_lin_eq([2, 3], [x, y], 12);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(2 * v['x']! + 3 * v['y']!, 12);
    });

    test('int_lin_eq with parameter coefficient array', () async {
      final out = await FlatZinc.solve(
        'array[1..2] of int: coef = [2, 3];\n'
        'var 0..6: x :: output_var;\n'
        'var 0..6: y :: output_var;\n'
        'constraint int_lin_eq(coef, [x, y], 12);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(2 * v['x']! + 3 * v['y']!, 12);
    });

    test('int_lin_le bounds the weighted sum', () async {
      // x + y + z <= 5 with vars in 1..5 → first sol uses lowest values.
      final out = await FlatZinc.solve(
        'var 1..5: x :: output_var;\n'
        'var 1..5: y :: output_var;\n'
        'var 1..5: z :: output_var;\n'
        'constraint int_lin_le([1, 1, 1], [x, y, z], 5);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x']! + v['y']! + v['z']! <= 5, isTrue);
    });

    test('int_lin_eq with embedded constant fold-in', () async {
      // 1*x + 1*5 + 1*y == 10  is the same as x + y == 5.
      final out = await FlatZinc.solve(
        'var 0..5: x :: output_var;\n'
        'var 0..5: y :: output_var;\n'
        'constraint int_lin_eq([1, 1, 1], [x, 5, y], 10);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x']! + v['y']!, 5);
    });

    test('int_lin_ne — sum must not equal target', () async {
      // x + y != 0, with x,y in 0..2 — first sol must avoid (0,0).
      final out = await FlatZinc.solve(
        'var 0..2: x :: output_var;\n'
        'var 0..2: y :: output_var;\n'
        'constraint int_lin_ne([1, 1], [x, y], 0);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x']! + v['y']!, isNot(0));
    });

    test('int_lin_eq length mismatch is rejected', () {
      expect(
        () => FlatZinc.solve(
          'var 0..6: x;\nvar 0..6: y;\n'
          'constraint int_lin_eq([2, 3, 4], [x, y], 12);\n'
          'solve satisfy;\n',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('FlatZinc M2 — boolean primitives', () {
    test('bool_clause acts as a 2-SAT clause', () async {
      // p ∨ q must hold, with both vars unconstrained otherwise.
      // The solver picks p=0,q=0 first if free, so the clause should
      // force at least one to flip.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'constraint bool_clause([p, q], []);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect((v['p'] == 1) || (v['q'] == 1), isTrue);
    });

    test('bool_clause with negative literal', () async {
      // ¬p ∨ q, with p forced to true via a separate constraint, so q
      // must be true.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'constraint bool_eq(p, true);\n'
        'constraint bool_clause([q], [p]);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['p'], 1);
      expect(v['q'], 1);
    });

    test('empty bool_clause is UNSAT', () async {
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'constraint bool_clause([], []);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('=====UNSATISFIABLE====='));
    });

    test('bool_clause with literal-true short-circuits to tautology',
        () async {
      // [true, p] always holds, so this is a no-op.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'constraint bool_clause([true, p], []);\n'
        'solve satisfy;\n',
      );
      // Tautological clause leaves p free; first sol is 0.
      expect(parseOutput(out).values['p'], 0);
    });

    test('bool_eq(var, const) pins the variable', () async {
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'constraint bool_eq(p, true);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['p'], 1);
    });

    test('bool_not(a, b) — reified negation', () async {
      // b ⇔ ¬a, with a forced to 1, so b must be 0.
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'constraint bool_eq(a, true);\n'
        'constraint bool_not(a, b);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['a'], 1);
      expect(v['b'], 0);
    });

    test('bool_and(a, b, r) — r ⇔ a ∧ b', () async {
      // Force a=1, b=1, free r — must be 1.
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(a, true);\n'
        'constraint bool_eq(b, true);\n'
        'constraint bool_and(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['r'], 1);
    });

    test('bool_or(a, b, r) with mixed inputs', () async {
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(a, false);\n'
        'constraint bool_eq(b, true);\n'
        'constraint bool_or(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['r'], 1);
    });

    test('bool_xor(a, b, r)', () async {
      // a=1, b=1 → r=0.
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(a, true);\n'
        'constraint bool_eq(b, true);\n'
        'constraint bool_xor(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['r'], 0);
    });

    test('bool2int(b, x) — equality', () async {
      final out = await FlatZinc.solve(
        'var bool: b :: output_var;\n'
        'var 0..1: x :: output_var;\n'
        'constraint bool_eq(b, true);\n'
        'constraint bool2int(b, x);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['b'], 1);
      expect(v['x'], 1);
    });
  });

  group('FlatZinc M2 — variable aliasing', () {
    test('var int: x = y; — x tracks y', () async {
      final out = await FlatZinc.solve(
        'var 3..5: y :: output_var;\n'
        'var 3..5: x :: output_var = y;\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      expect(v['x'], v['y']);
    });

    test('aliased array slot equals the referenced variable', () async {
      final out = await FlatZinc.solve(
        'var 1..9: pivot :: output_var;\n'
        'array[1..2] of var 1..9: a :: output_array([1..2]) = [pivot, pivot];\n'
        'solve satisfy;\n',
      );
      expect(out, contains('pivot = 1;'));
      expect(out, contains('a = array1d(1..2, [1, 1]);'));
    });
  });

  group('FlatZinc M2 — parameter substitution', () {
    test('scalar int parameter substitutes into a constraint', () async {
      final out = await FlatZinc.solve(
        'int: target = 7;\n'
        'var 1..9: x :: output_var;\n'
        'constraint int_eq(x, target);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['x'], 7);
    });

    test('scalar bool parameter substitutes into bool_eq', () async {
      final out = await FlatZinc.solve(
        'bool: target = true;\n'
        'var bool: b :: output_var;\n'
        'constraint bool_eq(b, target);\n'
        'solve satisfy;\n',
      );
      expect(parseOutput(out).values['b'], 1);
    });
  });

  group('FlatZinc M2 — small composed problems', () {
    test('3-SAT: (p ∨ q) ∧ (¬p ∨ ¬q) ∧ (p ∨ ¬q) — unique sol p=1,q=0',
        () async {
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'constraint bool_clause([p, q], []);\n'
        'constraint bool_clause([], [p, q]);\n'
        'constraint bool_clause([p], [q]);\n'
        'solve satisfy;\n',
      );
      final v = parseOutput(out).values;
      // The only assignment satisfying all three is p=1, q=0.
      expect(v['p'], 1);
      expect(v['q'], 0);
    });

    test('coin problem: 2*x + 5*y == 13 has sol (4, 1) or (9, ...)',
        () async {
      // Minimize x to get a deterministic solution.
      final out = await FlatZinc.solve(
        'var 0..10: x :: output_var;\n'
        'var 0..10: y :: output_var;\n'
        'constraint int_lin_eq([2, 5], [x, y], 13);\n'
        'solve minimize x;\n',
      );
      final v = parseOutput(out).values;
      expect(2 * v['x']! + 5 * v['y']!, 13);
      expect(v['x'], lessThanOrEqualTo(4));
    });
  });
}

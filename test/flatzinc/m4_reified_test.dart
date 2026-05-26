import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

({Map<String, int> values, Map<String, List<int>> arrays}) parse(String out) {
  final values = <String, int>{};
  final arrays = <String, List<int>>{};
  for (final raw in out.trim().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('---') || line.startsWith('===')) {
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final name = line.substring(0, eq).trim();
    final rhs = line.substring(eq + 1, line.length - 1).trim();
    if (rhs.startsWith('array1d')) {
      final start = rhs.indexOf('[');
      final end = rhs.lastIndexOf(']');
      arrays[name] = rhs
          .substring(start + 1, end)
          .split(',')
          .map((s) => _parseBoolOrInt(s.trim()))
          .toList();
    } else if (rhs == 'true') {
      values[name] = 1;
    } else if (rhs == 'false') {
      values[name] = 0;
    } else {
      final v = int.tryParse(rhs);
      if (v != null) values[name] = v;
    }
  }
  return (values: values, arrays: arrays);
}

int _parseBoolOrInt(String s) {
  if (s == 'true') return 1;
  if (s == 'false') return 0;
  return int.parse(s);
}

void main() {
  group('FlatZinc M4 — int_*_reif', () {
    test('int_eq_reif tracks a == b', () async {
      // Force a = b = 5 ⇒ r must be 1.
      final out = await FlatZinc.solve(
        'var 1..9: a :: output_var;\n'
        'var 1..9: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(a, 5);\n'
        'constraint int_eq(b, 5);\n'
        'constraint int_eq_reif(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('int_eq_reif tracks a != b ⇒ r = 0', () async {
      final out = await FlatZinc.solve(
        'var 1..9: a :: output_var;\n'
        'var 1..9: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(a, 3);\n'
        'constraint int_eq(b, 4);\n'
        'constraint int_eq_reif(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 0);
    });

    test('int_lt_reif var/const', () async {
      // r ⇔ (x < 5). Force x = 3.
      final out = await FlatZinc.solve(
        'var 1..9: x :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(x, 3);\n'
        'constraint int_lt_reif(x, 5, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('int_lt_reif var/var', () async {
      // r ⇔ (a < b). Force a = 2, b = 7.
      final out = await FlatZinc.solve(
        'var 1..9: a :: output_var;\n'
        'var 1..9: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(a, 2);\n'
        'constraint int_eq(b, 7);\n'
        'constraint int_lt_reif(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('int_le_reif with reversed (const, var) ordering', () async {
      // r ⇔ (5 <= x). Force x = 7. Reversed → equivalent to (x >= 5).
      final out = await FlatZinc.solve(
        'var 1..9: x :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(x, 7);\n'
        'constraint int_le_reif(5, x, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('int_ne_reif var/var', () async {
      // r ⇔ (a != b). Force a = 1, b = 1 ⇒ r = 0.
      final out = await FlatZinc.solve(
        'var 1..3: a :: output_var;\n'
        'var 1..3: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(a, 1);\n'
        'constraint int_eq(b, 1);\n'
        'constraint int_ne_reif(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 0);
    });

    test('int_eq_reif with r forced true acts as int_eq', () async {
      final out = await FlatZinc.solve(
        'var 1..9: a :: output_var;\n'
        'var 1..9: b :: output_var;\n'
        'constraint int_eq_reif(a, b, true);\n'
        'constraint int_eq(a, 5);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['b'], 5);
    });

    test('int_eq_reif with r forced false acts as int_ne', () async {
      // r = false ⇒ a != b. Force a = 5, the first sol picks b = 1.
      final out = await FlatZinc.solve(
        'var 1..9: a :: output_var;\n'
        'var 1..9: b :: output_var;\n'
        'constraint int_eq_reif(a, b, false);\n'
        'constraint int_eq(a, 5);\n'
        'solve satisfy;\n',
      );
      final v = parse(out).values;
      expect(v['a'], isNot(v['b']));
    });
  });

  group('FlatZinc M4 — int_lin_*_reif', () {
    test('int_lin_eq_reif fires r=1 when sum matches target', () async {
      final out = await FlatZinc.solve(
        'var 0..9: x :: output_var;\n'
        'var 0..9: y :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint int_eq(x, 4);\n'
        'constraint int_eq(y, 6);\n'
        'constraint int_lin_eq_reif([1, 1], [x, y], 10, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('int_lin_le_reif with r=0 forces the sum above the bound',
        () async {
      // r=0 ⇒ NOT (x + y <= 3) ⇒ x + y > 3.
      // With x,y in 1..3 the first sol with x+y > 3 is x=1, y=3.
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'var 1..3: y :: output_var;\n'
        'var bool: r;\n'
        'constraint int_eq(r, 0);\n'
        'constraint int_lin_le_reif([1, 1], [x, y], 3, r);\n'
        'solve satisfy;\n',
      );
      final v = parse(out).values;
      expect(v['x']! + v['y']! > 3, isTrue);
    });

    test('int_lin_ne_reif as a variable', () async {
      // r ⇔ (x + y != 0). Default x,y in 0..2 → first sol is (0,0)
      // with r=0; we force r=1 to push search away.
      final out = await FlatZinc.solve(
        'var 0..2: x :: output_var;\n'
        'var 0..2: y :: output_var;\n'
        'var bool: r;\n'
        'constraint int_eq(r, 1);\n'
        'constraint int_lin_ne_reif([1, 1], [x, y], 0, r);\n'
        'solve satisfy;\n',
      );
      final v = parse(out).values;
      expect(v['x']! + v['y']! != 0, isTrue);
    });
  });

  group('FlatZinc M4 — bool reified', () {
    test('bool_eq_reif tracks a == b', () async {
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(a, true);\n'
        'constraint bool_eq(b, false);\n'
        'constraint bool_eq_reif(a, b, r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 0);
    });

    test('bool_clause_reif tracks the clause', () async {
      // r ⇔ (p ∨ ¬q). Force p=false, q=true ⇒ clause is false ⇒ r=0.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(p, false);\n'
        'constraint bool_eq(q, true);\n'
        'constraint bool_clause_reif([p], [q], r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 0);
    });

    test('bool_clause_reif fires r=1 when clause holds', () async {
      // r ⇔ (p ∨ ¬q). Force p=true ⇒ clause holds ⇒ r=1 regardless of q.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(p, true);\n'
        'constraint bool_clause_reif([p], [q], r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });
  });

  group('FlatZinc M4 — composed: MAX-SAT', () {
    test('maximize number of satisfied clauses (4 clauses, 3 vars)',
        () async {
      // Clauses over (p, q, r):
      //   C1: p ∨ q
      //   C2: ¬p ∨ r
      //   C3: q ∨ r
      //   C4: ¬q
      // Satisfying p=true, q=false, r=true gives C1, C2, C3, C4 → all 4.
      // Maximize the sum of reified clause indicators.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'var bool: rv :: output_var;\n'
        'var bool: s1;\n'
        'var bool: s2;\n'
        'var bool: s3;\n'
        'var bool: s4;\n'
        'var 0..4: total :: output_var;\n'
        'constraint bool_clause_reif([p, q], [], s1);\n'
        'constraint bool_clause_reif([rv], [p], s2);\n'
        'constraint bool_clause_reif([q, rv], [], s3);\n'
        'constraint bool_clause_reif([], [q], s4);\n'
        'constraint int_lin_eq([1, 1, 1, 1, -1], [s1, s2, s3, s4, total], 0);\n'
        'solve maximize total;\n',
      );
      final v = parse(out).values;
      expect(v['total'], 4);
    });
  });

  group('FlatZinc M4 — composed: soft-CSP', () {
    test('minimize violations of distinctness on a 3-variable array',
        () async {
      // Soft `all_different` over (a, b, c) all in 1..2: at least two
      // are equal (pigeonhole). Reify the three pairwise equalities and
      // minimize their sum — the optimal is 1 (one pair coincides).
      final out = await FlatZinc.solve(
        'var 1..2: a :: output_var;\n'
        'var 1..2: b :: output_var;\n'
        'var 1..2: c :: output_var;\n'
        'var bool: e_ab;\n'
        'var bool: e_ac;\n'
        'var bool: e_bc;\n'
        'var 0..3: viol :: output_var;\n'
        'constraint int_eq_reif(a, b, e_ab);\n'
        'constraint int_eq_reif(a, c, e_ac);\n'
        'constraint int_eq_reif(b, c, e_bc);\n'
        'constraint int_lin_eq([1, 1, 1, -1], [e_ab, e_ac, e_bc, viol], 0);\n'
        'solve minimize viol;\n',
      );
      expect(parse(out).values['viol'], 1);
    });
  });
}

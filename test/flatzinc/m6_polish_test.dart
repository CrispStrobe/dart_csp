// Tests for the post-M5 polish round: extra builtins (set_in,
// array_bool_*, int_pow, array_int_min/max), search-annotation
// passthrough, and the int_lin_* duplicate-variable merge.

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
  group('FlatZinc extra builtins', () {
    test('set_in with range literal restricts the variable', () async {
      final out = await FlatZinc.solve(
        'var 1..10: x :: output_var;\n'
        'constraint set_in(x, 3..5);\n'
        'solve satisfy;\n',
      );
      // First sol is the lower bound of the allowed set.
      expect(parse(out).values['x'], 3);
    });

    test('set_in with enumerated set picks from the set', () async {
      final out = await FlatZinc.solve(
        'var 1..10: x :: output_var;\n'
        'constraint set_in(x, {2, 4, 6});\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['x'], 2);
    });

    test('array_bool_and(bs, r): force all-true ⇒ r=1', () async {
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(a, true);\n'
        'constraint bool_eq(b, true);\n'
        'constraint array_bool_and([a, b], r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('array_bool_or(bs, r): if any is true, r=1', () async {
      final out = await FlatZinc.solve(
        'var bool: a :: output_var;\n'
        'var bool: b :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_eq(a, false);\n'
        'constraint bool_eq(b, true);\n'
        'constraint array_bool_or([a, b], r);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['r'], 1);
    });

    test('int_pow: 2^3 == 8', () async {
      final out = await FlatZinc.solve(
        'var 0..100: c :: output_var;\n'
        'constraint int_pow(2, 3, c);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['c'], 8);
    });

    test('array_int_minimum picks the smallest', () async {
      final out = await FlatZinc.solve(
        'var 1..9: a;\n'
        'var 1..9: b;\n'
        'var 1..9: c;\n'
        'var 0..9: m :: output_var;\n'
        'constraint int_eq(a, 5);\n'
        'constraint int_eq(b, 3);\n'
        'constraint int_eq(c, 7);\n'
        'constraint array_int_minimum(m, [a, b, c]);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['m'], 3);
    });

    test('array_int_maximum picks the largest', () async {
      final out = await FlatZinc.solve(
        'var 1..9: a;\n'
        'var 1..9: b;\n'
        'var 1..9: c;\n'
        'var 0..9: m :: output_var;\n'
        'constraint int_eq(a, 5);\n'
        'constraint int_eq(b, 3);\n'
        'constraint int_eq(c, 7);\n'
        'constraint array_int_maximum(m, [a, b, c]);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['m'], 7);
    });
  });

  group('FlatZinc int_lin duplicate-variable merge', () {
    test('int_lin_eq with the same var listed twice accumulates coeffs',
        () async {
      // 2*x + 3*x == 10 ⇒ 5*x == 10 ⇒ x = 2.
      final out = await FlatZinc.solve(
        'var 1..9: x :: output_var;\n'
        'constraint int_lin_eq([2, 3], [x, x], 10);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['x'], 2);
    });

    test('SEND + MORE = MONEY via a single int_lin_eq (real cryptarithm)',
        () async {
      final out = await FlatZinc.solve('''
var 1..9: s :: output_var;
var 0..9: e :: output_var;
var 0..9: n :: output_var;
var 0..9: d :: output_var;
var 1..9: m :: output_var;
var 0..9: o :: output_var;
var 0..9: r :: output_var;
var 0..9: y :: output_var;
constraint all_different_int([s, e, n, d, m, o, r, y]);
constraint int_lin_eq(
  [1000, 100, 10, 1, 1000, 100, 10, 1, -10000, -1000, -100, -10, -1],
  [s, e, n, d, m, o, r, e, m, o, n, e, y],
  0);
solve satisfy;
''');
      final v = parse(out).values;
      // The unique sol is S=9 E=5 N=6 D=7 M=1 O=0 R=8 Y=2.
      expect(v['s'], 9);
      expect(v['e'], 5);
      expect(v['n'], 6);
      expect(v['d'], 7);
      expect(v['m'], 1);
      expect(v['o'], 0);
      expect(v['r'], 8);
      expect(v['y'], 2);
    });

    test('cancelling coefficients drop the variable entirely', () async {
      // 1*x + (-1)*x + y == 5 ⇒ y == 5 (x cancels out).
      final out = await FlatZinc.solve(
        'var 1..9: x :: output_var;\n'
        'var 1..9: y :: output_var;\n'
        'constraint int_lin_eq([1, -1, 1], [x, x, y], 5);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['y'], 5);
    });
  });

  group('FlatZinc search-annotation passthrough', () {
    test('int_search with dom_w_deg solves (acts as a hint, not a contract)',
        () async {
      // The annotation should route through getSolutionWithDomWdeg
      // without changing solution validity. We assert that a sol is
      // produced; the specific assignment depends on heuristic order.
      final out = await FlatZinc.solve(
        'array[1..4] of var 1..4: q :: output_array([1..4]);\n'
        'constraint all_different_int(q);\n'
        'solve :: int_search(q, dom_w_deg, indomain_min, complete) '
        'satisfy;\n',
      );
      expect(out, isNot(contains('UNSATISFIABLE')));
      expect(out, contains('q = array1d'));
    });

    test('int_search with input_order falls back to default heuristic',
        () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'solve :: int_search([x], input_order, indomain_min, complete) '
        'satisfy;\n',
      );
      expect(parse(out).values['x'], 1);
    });

    test('unknown varSelect keyword falls back to default (no crash)',
        () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'solve :: int_search([x], some_unknown_heuristic, indomain_min, '
        'complete) satisfy;\n',
      );
      expect(parse(out).values['x'], 1);
    });
  });
}

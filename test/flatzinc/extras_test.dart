// Tests for the post-M5 follow-ups: bool-typed output rendering and
// the arithmetic primitive handlers.

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('FlatZinc bool output rendering', () {
    test('var bool outputs as true / false, not 0 / 1', () async {
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'constraint bool_eq(p, true);\n'
        'constraint bool_eq(q, false);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('p = true;'));
      expect(out, contains('q = false;'));
    });

    test('var bool arrays render as array1d with true/false elements',
        () async {
      final out = await FlatZinc.solve(
        'array[1..2] of var bool: bs :: output_array([1..2]);\n'
        'constraint bool_eq(bs[1], true);\n'
        'constraint bool_eq(bs[2], false);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('bs = array1d(1..2, [true, false]);'));
    });

    test('var int outputs still render as integers', () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'constraint int_eq(x, 2);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('x = 2;'));
      expect(out, isNot(contains('true')));
    });
  });

  group('FlatZinc arithmetic primitives', () {
    Future<int?> solveValue(String source, String varName) async {
      final out = await FlatZinc.solve(source);
      for (final raw in out.split('\n')) {
        final line = raw.trim();
        if (line.startsWith('$varName = ')) {
          final rhs = line.substring(line.indexOf('=') + 1, line.length - 1)
              .trim();
          return int.tryParse(rhs);
        }
      }
      return null;
    }

    test('int_abs(a, b) — b = |a|, var/var', () async {
      final v = await solveValue(
        'var -5..-5: a;\n'
        'var 0..9: b :: output_var;\n'
        'constraint int_abs(a, b);\n'
        'solve satisfy;\n',
        'b',
      );
      expect(v, 5);
    });

    test('int_plus(a, b, c) — all-var routes through linear', () async {
      final v = await solveValue(
        'var 1..5: a;\n'
        'var 1..5: b;\n'
        'var 0..9: c :: output_var;\n'
        'constraint int_eq(a, 3);\n'
        'constraint int_eq(b, 4);\n'
        'constraint int_plus(a, b, c);\n'
        'solve satisfy;\n',
        'c',
      );
      expect(v, 7);
    });

    test('int_minus(a, b, c) with mixed const/var', () async {
      final v = await solveValue(
        'var 0..9: a :: output_var;\n'
        'constraint int_minus(10, 4, a);\n'
        'solve satisfy;\n',
        'a',
      );
      expect(v, 6);
    });

    test('int_times(a, b, c)', () async {
      final v = await solveValue(
        'var 1..9: a;\n'
        'var 1..9: b;\n'
        'var 0..81: c :: output_var;\n'
        'constraint int_eq(a, 6);\n'
        'constraint int_eq(b, 7);\n'
        'constraint int_times(a, b, c);\n'
        'solve satisfy;\n',
        'c',
      );
      expect(v, 42);
    });

    test('int_div truncates toward zero', () async {
      final v = await solveValue(
        'var -10..10: q :: output_var;\n'
        'constraint int_div(-7, 2, q);\n'
        'solve satisfy;\n',
        'q',
      );
      // Dart's `~/`: -7 ~/ 2 == -3 (truncate toward zero).
      expect(v, -3);
    });

    test('int_mod uses dividend sign', () async {
      final v = await solveValue(
        'var -10..10: r :: output_var;\n'
        'constraint int_mod(-7, 2, r);\n'
        'solve satisfy;\n',
        'r',
      );
      // -7 % 2: dividend-signed remainder is -1.
      expect(v, -1);
    });

    test('int_div by zero is unsatisfiable', () async {
      final out = await FlatZinc.solve(
        'var 0..9: q :: output_var;\n'
        'constraint int_div(5, 0, q);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('=====UNSATISFIABLE====='));
    });

    test('int_min(a, b, c) — c = min(a, b)', () async {
      final v = await solveValue(
        'var 0..9: c :: output_var;\n'
        'constraint int_min(3, 7, c);\n'
        'solve satisfy;\n',
        'c',
      );
      expect(v, 3);
    });

    test('int_max(a, b, c) — c = max(a, b)', () async {
      final v = await solveValue(
        'var 0..9: c :: output_var;\n'
        'constraint int_max(3, 7, c);\n'
        'solve satisfy;\n',
        'c',
      );
      expect(v, 7);
    });

    test('int_negate(a, b)', () async {
      final v = await solveValue(
        'var -9..9: b :: output_var;\n'
        'constraint int_negate(4, b);\n'
        'solve satisfy;\n',
        'b',
      );
      expect(v, -4);
    });

    test('composed: c = max(a + 1, b)', () async {
      final v = await solveValue(
        'var 1..9: a;\n'
        'var 1..9: b;\n'
        'var 0..99: ap1;\n'
        'var 0..99: c :: output_var;\n'
        'constraint int_eq(a, 4);\n'
        'constraint int_eq(b, 7);\n'
        'constraint int_plus(a, 1, ap1);\n'
        'constraint int_max(ap1, b, c);\n'
        'solve satisfy;\n',
        'c',
      );
      expect(v, 7);
    });
  });
}

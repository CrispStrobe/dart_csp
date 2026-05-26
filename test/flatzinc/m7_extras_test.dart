// Tests for the post-M5 polish round 3: array_var_int_element
// (variable-index lookup into a variable array) and multi-dimensional
// output_array rendering (array2d, array3d, ...).

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('FlatZinc array_var_int_element', () {
    test('idx const + arr vars: pins the selected slot', () async {
      // arr = [4, 7, 9]; idx = 2 ⇒ val = 7.
      final out = await FlatZinc.solve(
        'array[1..3] of var 0..9: arr;\n'
        'var 1..3: idx;\n'
        'var 0..9: val :: output_var;\n'
        'constraint int_eq(arr[1], 4);\n'
        'constraint int_eq(arr[2], 7);\n'
        'constraint int_eq(arr[3], 9);\n'
        'constraint int_eq(idx, 2);\n'
        'constraint array_var_int_element(idx, arr, val);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('val = 7;'));
    });

    test('idx var + arr vars: idx is uniquely determined by val', () async {
      // arr = [4, 7, 9]; val = 9 ⇒ idx must be 3.
      final out = await FlatZinc.solve(
        'array[1..3] of var 0..9: arr;\n'
        'var 1..3: idx :: output_var;\n'
        'var 0..9: val;\n'
        'constraint int_eq(arr[1], 4);\n'
        'constraint int_eq(arr[2], 7);\n'
        'constraint int_eq(arr[3], 9);\n'
        'constraint int_eq(val, 9);\n'
        'constraint array_var_int_element(idx, arr, val);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('idx = 3;'));
    });

    test('idx out of range with const idx is UNSAT', () async {
      final out = await FlatZinc.solve(
        'array[1..2] of var 0..9: arr;\n'
        'var 0..9: val;\n'
        'constraint array_var_int_element(5, arr, val);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('=====UNSATISFIABLE====='));
    });

    test('idx var + val var: full n-ary predicate over all vars', () async {
      // arr = [10, 20, 30]; val = 30 should force idx = 3.
      final out = await FlatZinc.solve(
        'array[1..3] of var 0..50: arr :: output_array([1..3]);\n'
        'var 1..3: idx :: output_var;\n'
        'var 0..50: val :: output_var;\n'
        'constraint int_eq(arr[1], 10);\n'
        'constraint int_eq(arr[2], 20);\n'
        'constraint int_eq(arr[3], 30);\n'
        'constraint int_eq(val, 30);\n'
        'constraint array_var_int_element(idx, arr, val);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('idx = 3;'));
      expect(out, contains('val = 30;'));
    });

    test('array_var_bool_element shares the same code path', () async {
      // bools = [false, true]; idx = 2 ⇒ val = true.
      final out = await FlatZinc.solve(
        'array[1..2] of var bool: bools;\n'
        'var 1..2: idx;\n'
        'var bool: val :: output_var;\n'
        'constraint bool_eq(bools[1], false);\n'
        'constraint bool_eq(bools[2], true);\n'
        'constraint int_eq(idx, 2);\n'
        'constraint array_var_bool_element(idx, bools, val);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('val = true;'));
    });
  });

  group('FlatZinc N-dimensional output_array', () {
    test('1D output renders as array1d', () async {
      final out = await FlatZinc.solve(
        'array[1..3] of var 1..3: a :: output_array([1..3]);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('a = array1d(1..3, ['));
    });

    test('2D output renders as array2d with both dims', () async {
      // 2x3 matrix (six flat slots), all free.
      final out = await FlatZinc.solve(
        'array[1..6] of var 1..3: m :: output_array([1..2, 1..3]);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('m = array2d(1..2, 1..3, ['));
      // Flat list order matches declaration order; first sol is all 1s.
      expect(out, contains('[1, 1, 1, 1, 1, 1]'));
    });

    test('3D output renders as array3d', () async {
      // 2x2x2 cube (eight flat slots).
      final out = await FlatZinc.solve(
        'array[1..8] of var 0..1: c :: output_array([1..2, 1..2, 1..2]);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('c = array3d(1..2, 1..2, 1..2, ['));
    });
  });

  group('FlatZinc bool_lin_* (shares the int_lin_* path)', () {
    test('bool_lin_eq encodes a cardinality constraint', () async {
      // exactly two of [p, q, r] must be true ⇔ 1*p + 1*q + 1*r == 2.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint bool_lin_eq([1, 1, 1], [p, q, r], 2);\n'
        'solve satisfy;\n',
      );
      // Parse out the three values and check the sum.
      var sum = 0;
      for (final line in out.split('\n')) {
        final t = line.trim();
        if (t == 'p = true;' || t == 'q = true;' || t == 'r = true;') {
          sum++;
        }
      }
      expect(sum, 2);
    });

    test('bool_lin_le caps the count', () async {
      // at most 1 of [p, q] true ⇔ 1*p + 1*q <= 1.
      final out = await FlatZinc.solve(
        'var bool: p :: output_var;\n'
        'var bool: q :: output_var;\n'
        'constraint bool_lin_le([1, 1], [p, q], 1);\n'
        'solve satisfy;\n',
      );
      // First sol picks lowest values; both should be false ⇒ sum 0 ≤ 1.
      expect(out, contains('p = false;'));
      expect(out, contains('q = false;'));
    });
  });
}

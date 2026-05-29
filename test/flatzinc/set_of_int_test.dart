// Tests for `var set of int` support in the FlatZinc frontend: bounded
// set-variable declarations, set parameters, the set-relation /
// set-operation builtins, their reified variants, and set-valued output
// formatting. The frontend maps each set variable onto the shipped
// set-variable layer (one 0/1 indicator per universe element) and posts
// the constraints element-wise via Problem.memberIndicator.

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('FlatZinc set variable declarations', () {
    test('bounded set var solves and renders as a set literal', () async {
      final out = await FlatZinc.solve(
        'var set of 1..5: S :: output_var;\n'
        'constraint set_card(S, 2);\n'
        'constraint set_in(3, S);\n'
        'solve satisfy;\n',
      );
      // 3 is forced in; cardinality 2 ⇒ exactly one more element.
      expect(out, matches(RegExp(r'S = (\{[^}]*\}|\d+\.\.\d+);')));
      expect(out, contains('3'));
    });

    test('empty set renders as {}', () async {
      final out = await FlatZinc.solve(
        'var set of 1..5: S :: output_var;\n'
        'constraint set_card(S, 0);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('S = {};'));
    });

    test('a contiguous run renders as a range', () async {
      final out = await FlatZinc.solve(
        'var set of 1..5: S :: output_var;\n'
        'constraint set_eq(S, 2..4);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('S = 2..4;'));
    });

    test('literal-aliased set var is pinned to its value', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: A :: output_var = {1, 3};\n'
        'solve satisfy;\n',
      );
      expect(out, contains('A = {1, 3};'));
    });

    test('identifier-aliased set var equals its source', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: A :: output_var = {2, 4};\n'
        'var set of 1..4: B :: output_var = A;\n'
        'solve satisfy;\n',
      );
      expect(out, contains('A = {2, 4};'));
      expect(out, contains('B = {2, 4};'));
    });

    test('unbounded var set of int is rejected at lowering', () {
      expect(
        () => FlatZinc.build('var set of int: S;\nsolve satisfy;\n'),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('a value outside the declared universe is rejected', () {
      expect(
        () => FlatZinc.build(
            'var set of 1..3: S :: output_var = {1, 7};\nsolve satisfy;\n'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('FlatZinc set_card', () {
    test('with a variable cardinality, links |S| to a counter', () async {
      final out = await FlatZinc.solve(
        'var set of 1..5: A :: output_var;\n'
        'var 0..5: k :: output_var;\n'
        'constraint set_card(A, k);\n'
        'constraint set_in(2, A);\n'
        'solve minimize k;\n',
      );
      expect(out, contains('A = {2};'));
      expect(out, contains('k = 1;'));
    });

    test('over a constant set checks the fixed cardinality', () async {
      final out = await FlatZinc.solve(
        'var 0..9: k :: output_var;\n'
        'constraint set_card({2, 4, 6}, k);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('k = 3;'));
    });
  });

  group('FlatZinc set relations', () {
    test('set_eq forces equality', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: A :: output_var;\n'
        'var set of 1..4: B :: output_var;\n'
        'constraint set_eq(A, {1, 4});\n'
        'constraint set_eq(A, B);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('A = {1, 4};'));
      expect(out, contains('B = {1, 4};'));
    });

    test('set_subset forbids extra elements', () async {
      // A ⊆ {1,2}, and 1 ∈ A; A can only be {1} or {1,2}, never contain 3.
      final out = await FlatZinc.solve(
        'var set of 1..3: A :: output_var;\n'
        'constraint set_subset(A, {1, 2});\n'
        'constraint set_in(1, A);\n'
        'constraint set_card(A, 2);\n'
        'solve satisfy;\n',
      );
      // {1, 2} is contiguous, so it renders as the range 1..2.
      expect(out, contains('A = 1..2;'));
    });

    test('set_superset is set_subset with arguments swapped', () async {
      // A ⊇ {1,3} ⇒ both forced in.
      final out = await FlatZinc.solve(
        'var set of 1..3: A :: output_var;\n'
        'constraint set_superset(A, {1, 3});\n'
        'constraint set_card(A, 2);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('A = {1, 3};'));
    });

    test('set_ne enumerates distinct singletons', () async {
      var solutions = 0;
      final out = await FlatZinc.solve(
        'var set of 1..3: A :: output_var;\n'
        'var set of 1..3: B :: output_var;\n'
        'constraint set_card(A, 1);\n'
        'constraint set_card(B, 1);\n'
        'constraint set_superset(A, {1});\n'
        'constraint set_ne(A, B);\n'
        'solve satisfy;\n',
        all: true,
      );
      for (final line in out.split('\n')) {
        if (line.startsWith('A = ')) solutions++;
      }
      // A is pinned to {1}; B is any singleton other than {1}: {2} or {3}.
      expect(solutions, 2);
      expect(out, isNot(contains('B = {1};')));
    });

    test('set_ne over two equal constant sets is unsatisfiable', () async {
      final out = await FlatZinc.solve(
        'var set of 1..3: S :: output_var;\n'
        'constraint set_card(S, 1);\n'
        'constraint set_ne({1}, {1});\n'
        'solve satisfy;\n',
      );
      expect(out.trim(), '=====UNSATISFIABLE=====');
    });
  });

  group('FlatZinc set operations', () {
    test('set_union', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: A :: output_var;\n'
        'var set of 1..4: B :: output_var;\n'
        'var set of 1..4: C :: output_var;\n'
        'constraint set_eq(A, {1, 2});\n'
        'constraint set_eq(B, {2, 3});\n'
        'constraint set_union(A, B, C);\n'
        'solve satisfy;\n',
      );
      // {1, 2, 3} is contiguous, so it renders as the range 1..3.
      expect(out, contains('C = 1..3;'));
    });

    test('set_intersect', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: A;\n'
        'var set of 1..4: B;\n'
        'var set of 1..4: C :: output_var;\n'
        'constraint set_eq(A, {1, 2, 3});\n'
        'constraint set_eq(B, {2, 3, 4});\n'
        'constraint set_intersect(A, B, C);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('C = 2..3;'));
    });

    test('set_diff', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: D :: output_var;\n'
        'constraint set_diff({1, 2, 3}, {2}, D);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('D = {1, 3};'));
    });

    test('set_symdiff', () async {
      final out = await FlatZinc.solve(
        'var set of 1..4: E :: output_var;\n'
        'constraint set_symdiff({1, 2}, {2, 3}, E);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('E = {1, 3};'));
    });

    test('union across mismatched universes', () async {
      // A over 1..3, B over 3..6, C over 1..6 — the element-wise
      // decomposition handles the differing universes correctly.
      final out = await FlatZinc.solve(
        'var set of 1..3: A;\n'
        'var set of 3..6: B;\n'
        'var set of 1..6: C :: output_var;\n'
        'constraint set_eq(A, {1, 3});\n'
        'constraint set_eq(B, {3, 5});\n'
        'constraint set_union(A, B, C);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('C = {1, 3, 5};'));
    });
  });

  group('FlatZinc reified set constraints', () {
    test('set_in_reif true forces membership', () async {
      final out = await FlatZinc.solve(
        'var set of 1..3: S :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint set_card(S, 1);\n'
        'constraint set_in_reif(2, S, r);\n'
        'constraint bool_eq(r, true);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('S = {2};'));
      expect(out, contains('r = true;'));
    });

    test('set_in_reif false forbids membership', () async {
      final out = await FlatZinc.solve(
        'var set of 1..2: S :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint set_card(S, 1);\n'
        'constraint set_in_reif(1, S, r);\n'
        'constraint bool_eq(r, false);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('S = {2};'));
    });

    test('set_subset_reif reflects the subset relation', () async {
      final out = await FlatZinc.solve(
        'var set of 1..3: A :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint set_eq(A, {1, 2});\n'
        'constraint set_subset_reif(A, {1, 2, 3}, r);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('r = true;'));
    });

    test('set_eq_reif false when the sets differ', () async {
      final out = await FlatZinc.solve(
        'var set of 1..3: A :: output_var;\n'
        'var bool: r :: output_var;\n'
        'constraint set_eq(A, {1});\n'
        'constraint set_eq_reif(A, {1, 2}, r);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('r = false;'));
    });
  });

  group('FlatZinc set parameters', () {
    test('set parameter resolves inside set_in', () async {
      final out = await FlatZinc.solve(
        'set of int: U = 2..4;\n'
        'var 0..9: x :: output_var;\n'
        'constraint set_in(x, U);\n'
        'constraint int_le(x, 2);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('x = 2;'));
    });

    test('set parameter resolves inside a set relation', () async {
      final out = await FlatZinc.solve(
        'set of int: U = {1, 2, 3};\n'
        'var set of 1..5: A :: output_var;\n'
        'constraint set_subset(A, U);\n'
        'constraint set_card(A, 3);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('A = 1..3;'));
    });
  });

  group('FlatZinc array of set variables', () {
    test('declares one set var per slot and renders array1d', () async {
      final out = await FlatZinc.solve(
        'array[1..2] of var set of 1..5: arr :: output_array([1..2]);\n'
        'constraint set_eq(arr[1], 1..4);\n'
        'constraint set_card(arr[2], 0);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('arr = array1d(1..2, [1..4, {}]);'));
    });
  });

  group('FlatZinc set-of-int lowering metadata', () {
    test('build exposes set vars and a solvable Problem', () {
      final lowered = FlatZinc.build(
        'var set of 1..4: S :: output_var;\n'
        'constraint set_card(S, 2);\n'
        'solve satisfy;\n',
      );
      expect(lowered.setVars, contains('S'));
      // The set var is materialized as four indicator variables.
      expect(lowered.problem.setVariableNames, contains('S'));
      expect(lowered.problem.setUniverse('S'), <int>[1, 2, 3, 4]);
    });

    test('parser keeps the universe ascending and de-duplicated', () {
      final type = (FlatZinc.parse('var set of {5, 1, 5, 3}: s;\n'
              'solve satisfy;\n')
          .vars
          .first
          .type) as VarTypeSetOfInt;
      expect(type.universe, <int>[1, 3, 5]);
    });
  });
}

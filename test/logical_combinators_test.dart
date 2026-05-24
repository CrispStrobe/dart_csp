import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('addAtLeast / addAtMost / addExactly', () {
    test('addAtLeast(bools, 2) enforces at least 2 ones', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [0, 1])
        ..addAtLeast(['a', 'b', 'c'], 2);
      for (final s in await p.getAllSolutions()) {
        final ones = ['a', 'b', 'c'].where((v) => s[v] == 1).length;
        expect(ones, greaterThanOrEqualTo(2));
      }
    });

    test('addAtMost(bools, 1) enforces at most 1 one', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [0, 1])
        ..addAtMost(['a', 'b', 'c'], 1);
      for (final s in await p.getAllSolutions()) {
        final ones = ['a', 'b', 'c'].where((v) => s[v] == 1).length;
        expect(ones, lessThanOrEqualTo(1));
      }
    });

    test('addExactly(bools, 2) enforces exactly 2 ones', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [0, 1])
        ..addExactly(['a', 'b', 'c'], 2);
      final solutions = await p.getAllSolutions();
      // C(3, 2) = 3 ways to choose which two are 1.
      expect(solutions, hasLength(3));
      for (final s in solutions) {
        final ones = ['a', 'b', 'c'].where((v) => s[v] == 1).length;
        expect(ones, equals(2));
      }
    });

    test('addAtLeast / addAtMost / addExactly throw on non-bool var', () {
      final p = Problem()..addVariable('x', [0, 1, 2]); // not a bool
      expect(() => p.addAtLeast(['x'], 1), throwsArgumentError);
      expect(() => p.addAtMost(['x'], 1), throwsArgumentError);
      expect(() => p.addExactly(['x'], 1), throwsArgumentError);
    });
  });

  group('addImplies', () {
    test('antecedent = 1 forces consequent = 1', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [0, 1])
        ..addImplies('a', 'b')
        ..addStringConstraint('a == 1');
      final result = await p.getSolution();
      expect((result as Map)['b'], equals(1));
    });

    test('antecedent = 0 leaves consequent unconstrained', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [0, 1])
        ..addImplies('a', 'b')
        ..addStringConstraint('a == 0');
      final solutions = await p.getAllSolutions();
      // b is free: both values appear.
      final bValues = solutions.map((s) => s['b']).toSet();
      expect(bValues, equals({0, 1}));
    });

    test('addImplies rules out exactly the (1, 0) case', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [0, 1])
        ..addImplies('a', 'b');
      final solutions = await p.getAllSolutions();
      // (0,0), (0,1), (1,1) are valid; (1,0) is not.
      expect(solutions, hasLength(3));
      for (final s in solutions) {
        expect(s['a'] == 1 && s['b'] == 0, isFalse);
      }
    });
  });

  group('addReifiedAnd / addReifiedOr / addReifiedNot', () {
    test('addReifiedAnd: bool ⇔ all are 1', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [0, 1])
        ..addReifiedAnd('allOnes', ['a', 'b', 'c']);
      for (final s in await p.getAllSolutions()) {
        final allOnes = s['a'] == 1 && s['b'] == 1 && s['c'] == 1;
        expect(s['allOnes'], equals(allOnes ? 1 : 0));
      }
    });

    test('addReifiedOr: bool ⇔ any is 1', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [0, 1])
        ..addReifiedOr('anyOne', ['a', 'b', 'c']);
      for (final s in await p.getAllSolutions()) {
        final anyOne = s['a'] == 1 || s['b'] == 1 || s['c'] == 1;
        expect(s['anyOne'], equals(anyOne ? 1 : 0));
      }
    });

    test('addReifiedNot: bool ⇔ ¬other', () async {
      final p = Problem()
        ..addVariable('a', [0, 1])
        ..addReifiedNot('notA', 'a');
      for (final s in await p.getAllSolutions()) {
        expect(s['notA'], equals(1 - (s['a'] as int)));
      }
    });
  });

  group('composing combinators with reified constraints', () {
    test('"at least 2 of (X==1, Y==1, Z==1)" via reified + addAtLeast',
        () async {
      // Reify three equalities, then require at least 2.
      final p = Problem()
        ..addVariables(['X', 'Y', 'Z'], [1, 2])
        ..addReifiedEquals('bX', 'X', 1)
        ..addReifiedEquals('bY', 'Y', 1)
        ..addReifiedEquals('bZ', 'Z', 1)
        ..addAtLeast(['bX', 'bY', 'bZ'], 2);
      for (final s in await p.getAllSolutions()) {
        final ones = [s['X'], s['Y'], s['Z']].where((v) => v == 1).length;
        expect(ones, greaterThanOrEqualTo(2));
      }
    });

    test('reified-AND of two reified constraints', () async {
      // (X == 1) AND (Y == 2)
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2])
        ..addReifiedEquals('bX', 'X', 1)
        ..addReifiedEquals('bY', 'Y', 2)
        ..addReifiedAnd('both', ['bX', 'bY'])
        ..addStringConstraint('both == 1');
      final result = await p.getSolution();
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(1));
      expect(s['Y'], equals(2));
    });

    test('implies between two reified constraints: (X==1) → (Y==1)', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [0, 1])
        ..addReifiedEquals('bX', 'X', 1)
        ..addReifiedEquals('bY', 'Y', 1)
        ..addImplies('bX', 'bY');
      for (final s in await p.getAllSolutions()) {
        // If X == 1, then Y == 1.
        if (s['X'] == 1) expect(s['Y'], equals(1));
      }
    });
  });
}

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('addReifiedEquals / NotEquals', () {
    test('b = 1 forces variable == constant', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3, 4, 5])
        ..addReifiedEquals('b', 'X', 3)
        ..addStringConstraint('b == 1');
      final result = await p.getSolution();
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(3));
      expect(s['b'], equals(1));
    });

    test('b = 0 forces variable != constant', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addReifiedEquals('b', 'X', 2)
        ..addStringConstraint('b == 0');
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(2));
      for (final s in solutions) {
        expect(s['X'], isNot(equals(2)));
        expect(s['b'], equals(0));
      }
    });

    test('variable == constant forces b = 1 (other direction)', () async {
      final p = Problem()
        ..addVariable('X', [3]) // pinned
        ..addReifiedEquals('b', 'X', 3);
      final result = await p.getSolution();
      final s = result as Map<String, dynamic>;
      expect(s['b'], equals(1));
    });

    test('variable != constant forces b = 0', () async {
      final p = Problem()
        ..addVariable('X', [7])
        ..addReifiedEquals('b', 'X', 3);
      final result = await p.getSolution();
      final s = result as Map<String, dynamic>;
      expect(s['b'], equals(0));
    });

    test('addReifiedNotEquals: complementary semantics', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addReifiedNotEquals('b', 'X', 2);
      final solutions = await p.getAllSolutions();
      // X=1 → b=1; X=2 → b=0; X=3 → b=1
      for (final s in solutions) {
        if (s['X'] == 2) {
          expect(s['b'], equals(0));
        } else {
          expect(s['b'], equals(1));
        }
      }
    });
  });

  group('reified ordering: <, <=, >, >=', () {
    test('addReifiedLessThan with constant', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3, 4, 5])
        ..addReifiedLessThan('b', 'X', 3);
      for (final s in await p.getAllSolutions()) {
        expect(s['b'], equals((s['X'] as int) < 3 ? 1 : 0));
      }
    });

    test('addReifiedLessOrEqual', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addReifiedLessOrEqual('b', 'X', 2);
      for (final s in await p.getAllSolutions()) {
        expect(s['b'], equals((s['X'] as int) <= 2 ? 1 : 0));
      }
    });

    test('addReifiedGreaterThan + addReifiedGreaterOrEqual', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3, 4])
        ..addReifiedGreaterThan('gt2', 'X', 2)
        ..addReifiedGreaterOrEqual('ge3', 'X', 3);
      for (final s in await p.getAllSolutions()) {
        final x = s['X'] as int;
        expect(s['gt2'], equals(x > 2 ? 1 : 0));
        expect(s['ge3'], equals(x >= 3 ? 1 : 0));
      }
    });
  });

  group('addReifiedInSet', () {
    test('membership tracked by b', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3, 4, 5])
        ..addReifiedInSet('b', 'X', {2, 4});
      for (final s in await p.getAllSolutions()) {
        final inSet = const {2, 4}.contains(s['X']);
        expect(s['b'], equals(inSet ? 1 : 0));
      }
    });
  });

  group('addReifiedEqualsVar', () {
    test('b tracks whether two vars are equal', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3])
        ..addReifiedEqualsVar('eq', 'X', 'Y');
      for (final s in await p.getAllSolutions()) {
        expect(s['eq'], equals(s['X'] == s['Y'] ? 1 : 0));
      }
    });

    test('forcing eq = 1 makes the vars equal', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3])
        ..addReifiedEqualsVar('eq', 'X', 'Y')
        ..addStringConstraint('eq == 1');
      for (final s in await p.getAllSolutions()) {
        expect(s['X'], equals(s['Y']));
      }
    });
  });

  group('counting via reified bools', () {
    test('"at least 2 of 3 equalities hold" via b1 + b2 + b3 >= 2', () async {
      // Three variables in [1,2,3]; b_i tracks whether X_i == 1.
      // Count of b_i = number of variables equal to 1.
      final p = Problem()
        ..addVariables(['X1', 'X2', 'X3'], [1, 2, 3])
        ..addReifiedEquals('b1', 'X1', 1)
        ..addReifiedEquals('b2', 'X2', 1)
        ..addReifiedEquals('b3', 'X3', 1)
        ..addStringConstraint('b1 + b2 + b3 >= 2');
      final solutions = await p.getAllSolutions();
      expect(solutions, isNotEmpty);
      for (final s in solutions) {
        final hits = [s['X1'], s['X2'], s['X3']].where((v) => v == 1).length;
        expect(hits, greaterThanOrEqualTo(2));
      }
    });

    test('"exactly one of these holds" via sum == 1', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [0, 1, 2])
        ..addReifiedEquals('bA', 'A', 0)
        ..addReifiedEquals('bB', 'B', 0)
        ..addReifiedEquals('bC', 'C', 0)
        ..addStringConstraint('bA + bB + bC == 1');
      for (final s in await p.getAllSolutions()) {
        final zeros = [s['A'], s['B'], s['C']].where((v) => v == 0).length;
        expect(zeros, equals(1));
      }
    });
  });

  group('addReified (generic)', () {
    test('generic reification of an arbitrary predicate', () async {
      // b ⇔ (X + Y == 5)
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4])
        ..addReified('b', ['X', 'Y'],
            (Map<String, dynamic> a) => (a['X'] as int) + (a['Y'] as int) == 5);
      for (final s in await p.getAllSolutions()) {
        final sum = (s['X'] as int) + (s['Y'] as int);
        expect(s['b'], equals(sum == 5 ? 1 : 0));
      }
    });
  });

  group('validation', () {
    test('addReifiedEquals throws on unknown variable', () {
      final p = Problem();
      expect(() => p.addReifiedEquals('b', 'X', 1), throwsArgumentError);
    });

    test('addReifiedEquals throws if bool var has non-{0,1} domain', () {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addVariable('b', [0, 1, 2]); // bad domain for a bool
      expect(() => p.addReifiedEquals('b', 'X', 1), throwsArgumentError);
    });

    test('auto-adds bool var if absent', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addReifiedEquals('newBool', 'X', 2);
      // The bool var was added with domain [0, 1].
      expect(p.variables.containsKey('newBool'), isTrue);
      expect(p.variables['newBool']!.toSet(), equals({0, 1}));
    });
  });
}

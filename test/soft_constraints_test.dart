import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('declareSoft + maximizeSatisfaction', () {
    test('uniform weights: maximizes count of satisfied soft constraints',
        () async {
      // Three "X == 1" preferences. Without hard conflict, all three
      // can be satisfied — but only one X exists per problem. Use
      // distinct variables.
      final p = Problem()
        ..addVariables(['X1', 'X2', 'X3'], [0, 1])
        ..addReifiedEquals('b1', 'X1', 1)
        ..addReifiedEquals('b2', 'X2', 1)
        ..addReifiedEquals('b3', 'X3', 1)
        ..declareSoft('b1', 1)
        ..declareSoft('b2', 1)
        ..declareSoft('b3', 1);
      final result = await p.maximizeSatisfaction();
      final s = result as Map<String, dynamic>;
      expect(s['X1'], equals(1));
      expect(s['X2'], equals(1));
      expect(s['X3'], equals(1));
      // All three soft constraints satisfied.
      expect(s['b1'], equals(1));
      expect(s['b2'], equals(1));
      expect(s['b3'], equals(1));
    });

    test('hard constraint conflicts with two of three soft prefs', () async {
      // We have to set X to one value. Each soft prefers a different
      // value. Maximize satisfaction: pick the value with highest
      // total weight (here, soft for value 2 has weight 5, beats
      // 1+1=2 for the other two).
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addReifiedEquals('b1', 'X', 1)
        ..addReifiedEquals('b2', 'X', 2)
        ..addReifiedEquals('b3', 'X', 3)
        ..declareSoft('b1', 1)
        ..declareSoft('b2', 5)
        ..declareSoft('b3', 1);
      final result = await p.maximizeSatisfaction();
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(2)); // highest-weight soft wins
    });

    test('weighted soft constraints: pick the higher weight when conflict',
        () async {
      // X can be 1 or 2. Both soft prefer different values; the
      // higher-weight one wins.
      final p = Problem()
        ..addVariable('X', [1, 2])
        ..addReifiedEquals('preferOne', 'X', 1)
        ..addReifiedEquals('preferTwo', 'X', 2)
        ..declareSoft('preferOne', 3)
        ..declareSoft('preferTwo', 10);
      final result = await p.maximizeSatisfaction();
      expect((result as Map)['X'], equals(2));
    });

    test('no soft constraints: falls back to feasibility', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addStringConstraint('X > 1');
      final result = await p.maximizeSatisfaction();
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map)['X'], greaterThan(1));
    });

    test('hard infeasibility returns FAILURE even with soft constraints',
        () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3])
        ..addReifiedEquals('b', 'X', 2)
        ..declareSoft('b', 10)
        ..addStringConstraint('X == 1')
        ..addStringConstraint('X == 3'); // conflicting hards
      final result = await p.maximizeSatisfaction();
      expect(result, equals('FAILURE'));
    });

    test('does not mutate the original problem', () async {
      final p = Problem()
        ..addVariable('X', [1, 2])
        ..addReifiedEquals('b', 'X', 1)
        ..declareSoft('b', 5);
      final beforeVars = p.variableCount;
      final beforeConstraints = p.constraintCount;
      await p.maximizeSatisfaction();
      expect(p.variableCount, equals(beforeVars));
      expect(p.constraintCount, equals(beforeConstraints));
    });
  });

  group('addSoftConstraint (one-step helper)', () {
    test('reifies + declares soft in one call', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3])
        ..addSoftConstraint(
          10,
          ['X', 'Y'],
          (Map<String, dynamic> a) => (a['X'] as int) + (a['Y'] as int) == 4,
        );
      final result = await p.maximizeSatisfaction();
      // Pairs summing to 4 in [1..3]: (1,3), (2,2), (3,1) — any wins.
      final s = result as Map<String, dynamic>;
      expect((s['X'] as int) + (s['Y'] as int), equals(4));
    });

    test('returns the bool name so caller can compose further', () async {
      final p = Problem()..addVariable('X', [1, 2, 3]);
      final name = p.addSoftConstraint(
          5, ['X'], (Map<String, dynamic> a) => a['X'] == 2);
      expect(p.variables.containsKey(name), isTrue);
    });
  });

  group('validation', () {
    test('declareSoft throws on unknown variable', () {
      final p = Problem();
      expect(() => p.declareSoft('b', 1), throwsArgumentError);
    });

    test('declareSoft throws on non-bool variable', () {
      final p = Problem()..addVariable('x', [0, 1, 2]);
      expect(() => p.declareSoft('x', 1), throwsArgumentError);
    });

    test('declareSoft throws on negative weight', () {
      final p = Problem()..addVariable('b', [0, 1]);
      expect(() => p.declareSoft('b', -1), throwsArgumentError);
    });
  });
}

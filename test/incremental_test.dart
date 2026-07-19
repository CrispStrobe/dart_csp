import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

Problem _base() => Problem()
  ..addVariables(['x', 'y'], [1, 2, 3])
  ..addStringConstraint('x != y');

void main() {
  group('assumptions and retraction', () {
    test('assumeEquals narrows the solution set', () async {
      final s = IncrementalSolver(_base())..assumeEquals('x', 2);
      await for (final sol in s.getSolutions()) {
        expect(sol['x'], 2);
        expect(sol['y'], isNot(2));
      }
      expect(await s.countSolutions(), 2); // y in {1,3}
    });

    test('the base problem is never mutated', () async {
      final base = _base();
      final before = base.constraintCount;
      final s = IncrementalSolver(base)
        ..assumeEquals('x', 1)
        ..assumeEquals('y', 2);
      await s.solve();
      expect(base.constraintCount, before);
      // base still has all its original solutions (3*3 minus x==y = 6)
      expect(await base.countSolutions(), 6);
    });

    test('resetAssumptions returns to the base solution set', () async {
      final s = IncrementalSolver(_base());
      expect(await s.countSolutions(), 6);
      s.assumeEquals('x', 1);
      expect(await s.countSolutions(), 2);
      s.resetAssumptions();
      expect(await s.countSolutions(), 6);
      expect(s.assumptionCount, 0);
    });

    test('an unsatisfiable assumption yields FAILURE, retract restores SAT',
        () async {
      final s = IncrementalSolver(_base());
      s.assumeEquals('x', 2);
      s.assumeNotEquals('x', 2); // contradictory with the above
      expect(await s.isSatisfiable(), isFalse);
      s.resetAssumptions();
      expect(await s.isSatisfiable(), isTrue);
    });
  });

  group('scopes: push / pop', () {
    test('pop retracts exactly the top scope', () async {
      final s = IncrementalSolver(_base())..assumeEquals('x', 3);
      expect(await s.countSolutions(), 2); // x=3, y in {1,2}

      s.push();
      s.assumeEquals('y', 1);
      expect(await s.countSolutions(), 1); // x=3, y=1
      expect(s.depth, 1);

      s.pop();
      expect(s.depth, 0);
      expect(await s.countSolutions(), 2); // back to just x=3
    });

    test('nested scopes stack and unwind', () async {
      final s =
          IncrementalSolver(Problem()..addVariables(['a', 'b', 'c'], [0, 1]));
      expect(await s.countSolutions(), 8); // 2^3

      s.push();
      s.assumeEquals('a', 0);
      expect(await s.countSolutions(), 4);

      s.push();
      s.assumeEquals('b', 0);
      expect(await s.countSolutions(), 2);

      s.push();
      s.assumeEquals('c', 0);
      expect(await s.countSolutions(), 1);

      s.pop();
      expect(await s.countSolutions(), 2);
      s.pop();
      expect(await s.countSolutions(), 4);
      s.pop();
      expect(await s.countSolutions(), 8);
    });

    test('popping the root scope throws', () {
      final s = IncrementalSolver(_base());
      expect(s.pop, throwsStateError);
    });

    test('assumptions and assumptionCount reflect all scopes', () {
      final s = IncrementalSolver(_base())..assumeEquals('x', 1);
      s.push();
      s.assumeConstraint('y != 3');
      expect(s.assumptionCount, 2);
      expect(s.assumptions, ['x == 1', 'y != 3']);
    });
  });

  group('assumption flavours', () {
    test('assumeInSet', () async {
      final s = IncrementalSolver(_base())..assumeInSet('x', {1, 3});
      await for (final sol in s.getSolutions()) {
        expect([1, 3], contains(sol['x']));
      }
    });

    test('assumeConstraint', () async {
      final s = IncrementalSolver(_base())..assumeConstraint('x > y');
      await for (final sol in s.getSolutions()) {
        expect(sol['x'] as int, greaterThan(sol['y'] as int));
      }
    });

    test('assumePredicate', () async {
      final s = IncrementalSolver(_base())
        ..assumePredicate(
            ['x', 'y'], (m) => (m['x'] as int) + (m['y'] as int) == 4);
      await for (final sol in s.getSolutions()) {
        expect((sol['x'] as int) + (sol['y'] as int), 4);
      }
    });

    test('assuming an unknown variable throws', () {
      final s = IncrementalSolver(_base());
      expect(() => s.assumeEquals('z', 1), throwsArgumentError);
    });
  });

  group('optimization under assumptions', () {
    test('minimize / maximize respect assumptions', () async {
      final p = Problem()..addVariables(['x'], [1, 2, 3, 4, 5]);
      final s = IncrementalSolver(p);
      expect((await s.maximize('x'))['x'], 5);
      s.assumeConstraint('x < 4');
      expect((await s.maximize('x'))['x'], 3);
      s.resetAssumptions();
      expect((await s.minimize('x'))['x'], 1);
    });
  });

  group('interactive re-solve pattern', () {
    test('a sequence of assume/solve/retract stays consistent', () async {
      // Simulate an editor: try x=1, then also y=2, retract y, try y=3.
      final s = IncrementalSolver(_base());
      s.assumeEquals('x', 1);
      expect((await s.solve())['x'], 1);

      s.push();
      s.assumeEquals('y', 2);
      final withY = await s.solve();
      expect(withY['x'], 1);
      expect(withY['y'], 2);
      s.pop();

      s.push();
      s.assumeEquals('y', 3);
      final withY3 = await s.solve();
      expect(withY3['y'], 3);
      s.pop();

      // Back to just x==1: both y=2 and y=3 possible again.
      expect(await s.countSolutions(), 2);
    });
  });
}

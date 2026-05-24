import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Tests for the `SetVariables` extension on [Problem]:
/// `addSetVariable` / `addSetVariables` declaration, the cardinality
/// / membership / pairwise / ternary helpers, the materialization of
/// set vars in every solve entry point, and an integration problem
/// (team selection with disjoint bench).
///
/// Set variables decompose to per-element 0/1 indicator variables, so
/// the helpers are sugar over the existing linear / reified / generic
/// nary infrastructure. These tests assert observable user-facing
/// behavior: the returned solutions expose set vars as `Set<dynamic>`,
/// the indicators are stripped from the map, and the constraints
/// behave as their mathematical specification.
void main() {
  group('addSetVariable basics', () {
    test('rejects empty universe', () {
      final p = Problem();
      expect(() => p.addSetVariable('S', universe: const <dynamic>[]),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects duplicate elements in the universe', () {
      final p = Problem();
      expect(() => p.addSetVariable('S', universe: <dynamic>[1, 2, 2]),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects duplicate set variable names', () {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2]);
      expect(() => p.addSetVariable('S', universe: <dynamic>[3]),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects clash with a regular variable name', () {
      final p = Problem()..addVariable('S', <dynamic>[0, 1]);
      expect(() => p.addSetVariable('S', universe: <dynamic>[1, 2]),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects required element outside the universe', () {
      final p = Problem();
      expect(
          () => p.addSetVariable('S',
              universe: <dynamic>[1, 2], required: <dynamic>[3]),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects excluded element outside the universe', () {
      final p = Problem();
      expect(
          () => p.addSetVariable('S',
              universe: <dynamic>[1, 2], excluded: <dynamic>[3]),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects element that is both required and excluded', () {
      final p = Problem();
      expect(
          () => p.addSetVariable('S',
              universe: <dynamic>[1, 2],
              required: <dynamic>[1],
              excluded: <dynamic>[1]),
          throwsA(isA<ArgumentError>()));
    });

    test('records the universe in declaration order', () {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>['c', 'a', 'b']);
      expect(p.setUniverse('S'), equals(<dynamic>['c', 'a', 'b']));
      expect(p.setVariableNames, contains('S'));
    });
  });

  group('solution materialization', () {
    test('free 3-element universe enumerates all 8 subsets', () async {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2, 3]);
      // Sets in Dart use identity equality, so compare by canonical
      // string keys instead.
      String key(Set<dynamic> s) {
        final sorted = s.map((e) => '$e').toList()..sort();
        return '{${sorted.join(",")}}';
      }

      final keys = <String>{};
      var count = 0;
      await for (final sol in p.getSolutions()) {
        expect(sol['S'], isA<Set<dynamic>>());
        keys.add(key(sol['S'] as Set<dynamic>));
        count++;
      }
      expect(count, equals(8));
      // Every subset of {1, 2, 3} appears exactly once.
      expect(keys.length, equals(8));
      expect(keys, contains('{}'));
      expect(keys, contains('{1}'));
      expect(keys, contains('{1,2,3}'));
    });

    test('required / excluded pin elements at declaration time', () async {
      final p = Problem()
        ..addSetVariable('S',
            universe: <dynamic>[1, 2, 3, 4],
            required: <dynamic>[1],
            excluded: <dynamic>[4]);
      final solutions = <Set<dynamic>>[];
      await for (final sol in p.getSolutions()) {
        final s = sol['S'] as Set<dynamic>;
        expect(s, contains(1));
        expect(s, isNot(contains(4)));
        solutions.add(s);
      }
      // 2 and 3 each free → 4 solutions.
      expect(solutions.length, equals(4));
    });

    test('strips internal indicator variables from the returned map', () async {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2]);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      final map = sol as Map<String, dynamic>;
      expect(map.keys, equals(<String>{'S'}));
      for (final k in map.keys) {
        expect(k.startsWith('__set__'), isFalse);
      }
    });

    test('non-set variables are preserved alongside set variables', () async {
      final p = Problem()
        ..addVariable('x', <dynamic>[1, 2, 3])
        ..addSetVariable('S', universe: <dynamic>[10, 20]);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      final map = sol as Map<String, dynamic>;
      expect(map.containsKey('x'), isTrue);
      expect(map.containsKey('S'), isTrue);
      expect(map['S'], isA<Set<dynamic>>());
    });

    test('FAILURE result is passed through unchanged', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2])
        ..addRequiredInSet('S', 1)
        ..addExcludedFromSet('S', 1); // unsatisfiable
      final sol = await p.getSolution();
      expect(sol, equals('FAILURE'));
    });
  });

  group('addSetCardinality', () {
    test('exact cardinality limits the solution set', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3, 4])
        ..addSetCardinality('S', 2);
      final solutions = <Set<dynamic>>[];
      await for (final sol in p.getSolutions()) {
        expect((sol['S'] as Set<dynamic>).length, equals(2));
        solutions.add(sol['S'] as Set<dynamic>);
      }
      // C(4, 2) = 6 distinct subsets of size 2.
      expect(solutions.length, equals(6));
    });

    test('range cardinality covers an inclusive band', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>['a', 'b', 'c'])
        ..addSetCardinalityRange('S', 1, 2);
      final solutions = <Set<dynamic>>[];
      await for (final sol in p.getSolutions()) {
        final s = sol['S'] as Set<dynamic>;
        expect(s.length, inInclusiveRange(1, 2));
        solutions.add(s);
      }
      // C(3,1) + C(3,2) = 3 + 3 = 6.
      expect(solutions.length, equals(6));
    });

    test('cardinality variable composes with minimize', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3, 4, 5])
        ..addVariable('k', <dynamic>[0, 1, 2, 3, 4, 5])
        ..addSetCardinalityVar('S', 'k')
        ..addRequiredInSet('S', 2);
      final sol = await p.minimize('k');
      expect(sol, isA<Map<String, dynamic>>());
      final s = sol as Map<String, dynamic>;
      expect(s['k'], equals(1));
      expect(s['S'], equals(<dynamic>{2}));
    });

    test('rejects k outside [0, |U|]', () {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2]);
      expect(() => p.addSetCardinality('S', -1), throwsA(isA<ArgumentError>()));
      expect(() => p.addSetCardinality('S', 3), throwsA(isA<ArgumentError>()));
    });

    test('rejects malformed cardinality range', () {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2]);
      expect(() => p.addSetCardinalityRange('S', 2, 1),
          throwsA(isA<ArgumentError>()));
      expect(() => p.addSetCardinalityRange('S', -1, 1),
          throwsA(isA<ArgumentError>()));
      expect(() => p.addSetCardinalityRange('S', 0, 3),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('addSubset / addSetEquals / addSetDisjoint', () {
    test('addSubset: subset enumerates only sets contained in super', () async {
      final p = Problem()
        ..addSetVariables(['A', 'B'], universe: <dynamic>[1, 2, 3])
        ..addSubset('A', 'B');
      final solutions = <(Set<dynamic>, Set<dynamic>)>[];
      await for (final sol in p.getSolutions()) {
        final a = sol['A'] as Set<dynamic>;
        final b = sol['B'] as Set<dynamic>;
        expect(a.every(b.contains), isTrue, reason: 'A ($a) ⊄ B ($b)');
        solutions.add((a, b));
      }
      // Number of (A, B) with A ⊆ B ⊆ {1,2,3}: for each B of size k,
      // 2^k choices of A. Sum_{k=0..3} C(3,k)*2^k = 1+6+12+8 = 27.
      expect(solutions.length, equals(27));
    });

    test('addSubset with asymmetric universes excludes sub-only elements',
        () async {
      final p = Problem()
        ..addSetVariable('A', universe: <dynamic>[1, 2, 9])
        ..addSetVariable('B', universe: <dynamic>[1, 2])
        ..addSubset('A', 'B');
      await for (final sol in p.getSolutions()) {
        final a = sol['A'] as Set<dynamic>;
        expect(a, isNot(contains(9)),
            reason: '9 cannot be in A since B cannot contain it.');
      }
    });

    test('addSetEquals forces equal membership', () async {
      final p = Problem()
        ..addSetVariables(['A', 'B'], universe: <dynamic>[1, 2, 3])
        ..addSetEquals('A', 'B');
      final solutions = <Set<dynamic>>[];
      await for (final sol in p.getSolutions()) {
        expect(sol['A'], equals(sol['B']));
        solutions.add(sol['A'] as Set<dynamic>);
      }
      // 8 equal pairs (one per subset of {1,2,3}).
      expect(solutions.length, equals(8));
    });

    test('addSetEquals rejects mismatched universes', () {
      final p = Problem()
        ..addSetVariable('A', universe: <dynamic>[1, 2, 3])
        ..addSetVariable('B', universe: <dynamic>[1, 2]);
      expect(() => p.addSetEquals('A', 'B'), throwsA(isA<ArgumentError>()));
    });

    test('addSetDisjoint prevents overlap', () async {
      final p = Problem()
        ..addSetVariables(['A', 'B'], universe: <dynamic>[1, 2, 3])
        ..addSetDisjoint('A', 'B')
        ..addSetCardinality('A', 1)
        ..addSetCardinality('B', 1);
      var count = 0;
      await for (final sol in p.getSolutions()) {
        final a = sol['A'] as Set<dynamic>;
        final b = sol['B'] as Set<dynamic>;
        expect(a.intersection(b), isEmpty);
        count++;
      }
      // 3 * 2 = 6 ordered pairs of distinct singletons.
      expect(count, equals(6));
    });
  });

  group('addSetUnion / addSetIntersection / addSetDifference', () {
    test('union: result is exactly A ∪ B', () async {
      final p = Problem()
        ..addSetVariables(['A', 'B', 'C'], universe: <dynamic>[1, 2, 3])
        ..addSetUnion('A', 'B', 'C');
      await for (final sol in p.getSolutions()) {
        final a = sol['A'] as Set<dynamic>;
        final b = sol['B'] as Set<dynamic>;
        final c = sol['C'] as Set<dynamic>;
        expect(c, equals(a.union(b)));
      }
    });

    test('intersection: result is exactly A ∩ B', () async {
      final p = Problem()
        ..addSetVariables(['A', 'B', 'C'], universe: <dynamic>[1, 2, 3])
        ..addSetIntersection('A', 'B', 'C');
      await for (final sol in p.getSolutions()) {
        final a = sol['A'] as Set<dynamic>;
        final b = sol['B'] as Set<dynamic>;
        final c = sol['C'] as Set<dynamic>;
        expect(c, equals(a.intersection(b)));
      }
    });

    test('difference: result is exactly A \\ B', () async {
      final p = Problem()
        ..addSetVariables(['A', 'B', 'C'], universe: <dynamic>[1, 2, 3])
        ..addSetDifference('A', 'B', 'C');
      await for (final sol in p.getSolutions()) {
        final a = sol['A'] as Set<dynamic>;
        final b = sol['B'] as Set<dynamic>;
        final c = sol['C'] as Set<dynamic>;
        expect(c, equals(a.difference(b)));
      }
    });

    test('ternary helpers require all three to share a universe', () {
      final p = Problem()
        ..addSetVariable('A', universe: <dynamic>[1, 2, 3])
        ..addSetVariable('B', universe: <dynamic>[1, 2, 3])
        ..addSetVariable('C', universe: <dynamic>[1, 2]);
      expect(() => p.addSetUnion('A', 'B', 'C'), throwsA(isA<ArgumentError>()));
    });
  });

  group('addRequiredInSet / addExcludedFromSet', () {
    test('post-declaration required pinning forces inclusion', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3])
        ..addRequiredInSet('S', 2);
      await for (final sol in p.getSolutions()) {
        expect(sol['S'] as Set<dynamic>, contains(2));
      }
    });

    test('post-declaration excluded pinning forces exclusion', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3])
        ..addExcludedFromSet('S', 2);
      await for (final sol in p.getSolutions()) {
        expect(sol['S'] as Set<dynamic>, isNot(contains(2)));
      }
    });

    test('pin to an element outside the universe throws', () {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2]);
      expect(() => p.addRequiredInSet('S', 3), throwsA(isA<ArgumentError>()));
      expect(() => p.addExcludedFromSet('S', 3), throwsA(isA<ArgumentError>()));
    });
  });

  group('memberIndicator escape hatch', () {
    test('exposes the internal indicator for advanced composition', () async {
      // Compose with reified: "if x == 7 then 7 ∈ S".
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[5, 6, 7])
        ..addVariable('x', <dynamic>[5, 6, 7])
        ..addSetCardinality('S', 1);
      final ind7 = p.memberIndicator('S', 7);
      p.addReifiedEquals('bx7', 'x', 7);
      // bx7 == 1 ⇒ ind7 == 1: i.e. !(bx7=1 ∧ ind7=0).
      p.addConstraint(
          <String>['bx7', ind7], (dynamic b, dynamic i) => !(b == 1 && i == 0));
      var checked = 0;
      await for (final sol in p.getSolutions()) {
        final x = sol['x'] as int;
        final s = sol['S'] as Set<dynamic>;
        if (x == 7) {
          expect(s, equals(<dynamic>{7}));
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });

    test('rejects an unknown set variable', () {
      final p = Problem();
      expect(() => p.memberIndicator('X', 1), throwsA(isA<ArgumentError>()));
    });

    test('rejects an element outside the universe', () {
      final p = Problem()..addSetVariable('S', universe: <dynamic>[1, 2]);
      expect(() => p.memberIndicator('S', 3), throwsA(isA<ArgumentError>()));
    });
  });

  group('integration with other solve entry points', () {
    test('materializes through getSolutionWithDomWdeg', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3])
        ..addSetCardinality('S', 2);
      final sol = await p.getSolutionWithDomWdeg();
      expect(sol, isA<Map<String, dynamic>>());
      expect(((sol as Map<String, dynamic>)['S'] as Set<dynamic>).length,
          equals(2));
    });

    test('materializes through getSolutionWithRestarts', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3])
        ..addSetCardinality('S', 2);
      final sol = await p.getSolutionWithRestarts(seed: 1);
      expect(sol, isA<Map<String, dynamic>>());
      expect(((sol as Map<String, dynamic>)['S'] as Set<dynamic>).length,
          equals(2));
    });

    test('materializes through solveWithMinConflicts', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3])
        ..addRequiredInSet('S', 1);
      final sol = await p.solveWithMinConflicts(maxSteps: 200, seed: 7);
      expect(sol, isA<Map<String, dynamic>>());
      final s = sol as Map<String, dynamic>;
      expect(s['S'], contains(1));
    });

    test('materializes inside maximize objective', () async {
      // Maximize |S| with |S| <= 3 over universe of size 5.
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3, 4, 5])
        ..addVariable('k', <dynamic>[0, 1, 2, 3])
        ..addSetCardinalityVar('S', 'k');
      final sol = await p.maximize('k');
      expect(sol, isA<Map<String, dynamic>>());
      final s = sol as Map<String, dynamic>;
      expect(s['k'], equals(3));
      expect((s['S'] as Set<dynamic>).length, equals(3));
    });

    test(
        'materializes inside maximizeSatisfaction (copy() carries '
        'the registry)', () async {
      final p = Problem()
        ..addSetVariable('S', universe: <dynamic>[1, 2, 3])
        ..addSetCardinality('S', 2);
      final indFor1 = p.memberIndicator('S', 1);
      p.addSoftConstraint(
          1, <String>[indFor1], (Map<String, dynamic> a) => a[indFor1] == 1);
      final sol = await p.maximizeSatisfaction();
      expect(sol, isA<Map<String, dynamic>>());
      final s = sol as Map<String, dynamic>;
      expect(s['S'], contains(1));
      expect((s['S'] as Set<dynamic>).length, equals(2));
    });
  });

  group('integration: team selection', () {
    test('disjoint Team and Bench, exact sizes, required captain', () async {
      const roster = <String>['alice', 'bob', 'carol', 'dave', 'erin'];
      final p = Problem()
        ..addSetVariables(['Team', 'Bench'], universe: roster)
        ..addSetCardinality('Team', 3)
        ..addSetCardinality('Bench', 2)
        ..addSetDisjoint('Team', 'Bench')
        ..addRequiredInSet('Team', 'alice');

      var count = 0;
      await for (final sol in p.getSolutions()) {
        final team = sol['Team'] as Set<dynamic>;
        final bench = sol['Bench'] as Set<dynamic>;
        expect(team.length, equals(3));
        expect(bench.length, equals(2));
        expect(team.intersection(bench), isEmpty);
        expect(team, contains('alice'));
        count++;
      }
      // alice fixed in Team. Choose 2 more from {bob, carol, dave, erin}
      // for Team: C(4,2) = 6. Remaining 2 go to Bench.
      expect(count, equals(6));
    });
  });

  group('equivalence with manual indicator decomposition', () {
    test('two-set disjoint cardinality matches a hand-built encoding',
        () async {
      // Set-var form.
      final pSet = Problem()
        ..addSetVariables(['A', 'B'], universe: <dynamic>[1, 2, 3, 4])
        ..addSetCardinality('A', 2)
        ..addSetCardinality('B', 2)
        ..addSetDisjoint('A', 'B');
      var setCount = 0;
      await for (final _ in pSet.getSolutions()) {
        setCount++;
      }

      // Manual encoding: 8 indicator vars + 3 linear + 4 disjoint.
      final pManual = Problem();
      for (var i = 1; i <= 4; i++) {
        pManual.addVariable('a$i', <dynamic>[0, 1]);
        pManual.addVariable('b$i', <dynamic>[0, 1]);
      }
      final aNames = [for (var i = 1; i <= 4; i++) 'a$i'];
      final bNames = [for (var i = 1; i <= 4; i++) 'b$i'];
      pManual.addLinearEquals(aNames, List<num>.filled(4, 1), 2);
      pManual.addLinearEquals(bNames, List<num>.filled(4, 1), 2);
      for (var i = 1; i <= 4; i++) {
        pManual.addConstraint(<String>['a$i', 'b$i'],
            (dynamic x, dynamic y) => !((x as int) == 1 && (y as int) == 1));
      }
      var manualCount = 0;
      await for (final _ in pManual.getSolutions()) {
        manualCount++;
      }

      expect(setCount, equals(manualCount));
    });
  });
}

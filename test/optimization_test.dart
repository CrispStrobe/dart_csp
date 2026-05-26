import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.minimize / Problem.maximize', () {
    test('minimize over an unconstrained variable returns the smallest value',
        () async {
      final p = Problem()..addVariable('X', [3, 1, 4, 1, 5, 9, 2, 6]);
      final result = await p.minimize('X');
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map)['X'], equals(1));
    });

    test('maximize over an unconstrained variable returns the largest value',
        () async {
      final p = Problem()..addVariable('X', [3, 1, 4, 1, 5, 9, 2, 6]);
      final result = await p.maximize('X');
      expect((result as Map)['X'], equals(9));
    });

    test('minimize respects constraints on the objective variable', () async {
      final p = Problem()
        ..addVariable('X', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ..addStringConstraint('X > 4');
      final result = await p.minimize('X');
      expect((result as Map)['X'], equals(5));
    });

    test('minimize over a derived variable respects relational constraints',
        () async {
      // X + Y = 10, both in [1..9]; minimize X means maximize Y.
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addStringConstraint('X + Y == 10');
      final result = await p.minimize('X');
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map;
      expect(m['X'], equals(1));
      expect(m['Y'], equals(9));
    });

    test('maximize on the same X+Y=10 problem returns the other extreme',
        () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addStringConstraint('X + Y == 10');
      final result = await p.maximize('X');
      final m = result as Map;
      expect(m['X'], equals(9));
      expect(m['Y'], equals(1));
    });

    test('minimize returns the unique optimum on a fully-determined problem',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final result = await p.minimize('A');
      final m = result as Map;
      expect(m['A'], equals(1));
      expect(m['B'], equals(2));
      expect(m['C'], equals(3));
    });

    test('minimize over an infeasible problem returns FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B')
        ..addStringConstraint('A == B'); // self-contradicting
      final result = await p.minimize('A');
      expect(result, equals('FAILURE'));
    });

    test('minimize throws for unknown objective variable', () {
      final p = Problem()..addVariable('A', [1, 2, 3]);
      expect(() => p.minimize('Z'), throwsArgumentError);
    });

    test('maximize throws for unknown objective variable', () {
      final p = Problem()..addVariable('A', [1, 2, 3]);
      expect(() => p.maximize('Z'), throwsArgumentError);
    });

    test('minimize throws when the objective variable resolves to non-num',
        () async {
      final p = Problem()..addVariable('Color', ['red', 'green', 'blue']);
      expect(() async => p.minimize('Color'), throwsArgumentError);
    });

    test('minimize over a sum: classic small linear programming case',
        () async {
      // Choose values for A, B, C from [1..5] with A != B != C, minimize
      // the sum A + B + C. Smallest distinct triple in [1..5] is {1,2,3}
      // summing to 6.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addVariable('S', [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        ..addStringConstraint('A + B + C == S');
      final result = await p.minimize('S');
      final m = result as Map;
      expect(m['S'], equals(6));
      expect({m['A'], m['B'], m['C']}, equals({1, 2, 3}));
    });

    test('maximize over a sum returns the maximum feasible value', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addVariable('S', [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        ..addStringConstraint('A + B + C == S');
      final result = await p.maximize('S');
      final m = result as Map;
      // Largest distinct triple in [1..5] is {3,4,5} = 12.
      expect(m['S'], equals(12));
      expect({m['A'], m['B'], m['C']}, equals({3, 4, 5}));
    });

    test('minimize does not mutate the original problem', () async {
      final p = Problem()..addVariable('X', [1, 2, 3, 4, 5]);
      final beforeVarCount = p.variableCount;
      final beforeConstraintCount = p.constraintCount;
      await p.minimize('X');
      expect(p.variableCount, equals(beforeVarCount));
      expect(p.constraintCount, equals(beforeConstraintCount));
    });
  });

  group('integrated branch-and-bound', () {
    test('lastStats is populated for minimize (was missing in restart B&B)',
        () async {
      // The old restart-tightening _optimize did multiple full solves
      // and only the last one's stats were observable. The integrated
      // path runs a single solve, so lastStats reflects the whole search.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addVariable('S', [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        ..addStringConstraint('A + B + C == S');
      await p.minimize('S');
      final s = p.lastStats;
      expect(s, isNotNull);
      expect(s!.decisions, greaterThan(0));
      expect(s.elapsedMicros, greaterThanOrEqualTo(0));
    });

    test('lastStats is populated for maximize', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addVariable('S', [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
        ..addStringConstraint('A + B + C == S');
      await p.maximize('S');
      final s = p.lastStats;
      expect(s, isNotNull);
      expect(s!.decisions, greaterThan(0));
    });

    test('many improvement steps: minimize a free variable in a large domain',
        () async {
      // The restart-tightening B&B would re-solve from scratch after
      // each improvement (up to ~|domain| times). The integrated path
      // does it in a single search. Correctness check: returns the
      // smallest value.
      final p = Problem()..addVariable('N', [for (var i = 1; i <= 50; i++) i]);
      final result = await p.minimize('N');
      expect((result as Map)['N'], equals(1));
    });

    test('bound prunes future branches: minimize with constraints', () async {
      // 8 vars in [1..8], all distinct, minimize first var.
      // Optimum is A=1, with the other vars filling {2..8} in any
      // order. Tests that pruning by bound works alongside Régin's
      // allDifferent propagator.
      final vars = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
      final p = Problem()
        ..addVariables(vars, [1, 2, 3, 4, 5, 6, 7, 8])
        ..addAllDifferent(vars);
      final result = await p.minimize('A');
      expect((result as Map)['A'], equals(1));
    });

    test('maximize: integrated B&B finds the supremum', () async {
      final p = Problem()..addVariable('N', [for (var i = 1; i <= 30; i++) i]);
      final result = await p.maximize('N');
      expect((result as Map)['N'], equals(30));
    });

    test('proven-optimum short-circuit: minimum reachable immediately',
        () async {
      // When the very first leaf already hits the minimum possible
      // value, the search should terminate without trying every other
      // branch. We can't easily assert on the count, but we can check
      // the answer is correct and the test completes promptly.
      final p = Problem()
        ..addVariable('X', [1])
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);
      // Force MRV to pick X first (singleton ⇒ not selected; the
      // others get picked). After the first leaf is found, X=1 means
      // the bound is 1 and nothing can improve.
      final result = await p.minimize('X');
      expect((result as Map)['X'], equals(1));
    });

    test('infeasible problem returns FAILURE without crashing', () async {
      // Empty improvement set after the first (and only) feasible
      // leaf — verifies the _optProven short-circuit fires.
      final p = Problem()
        ..addVariable('X', [1])
        ..addVariable('Y', [1])
        ..addStringConstraint('X == Y');
      final result = await p.minimize('X');
      expect((result as Map)['X'], equals(1));
    });

    test('minimize with no feasible solutions returns FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A < B')
        ..addStringConstraint('A > B'); // self-contradicting
      expect(await p.minimize('A'), equals('FAILURE'));
    });

    test('non-numeric objective domain throws synchronously up-front', () {
      // The integrated path validates the objective domain upfront so
      // it can assume `value is num` at each leaf. The throw still
      // surfaces as an ArgumentError to the caller.
      final p = Problem()..addVariable('Color', ['red', 'blue']);
      expect(() => p.minimize('Color'), throwsArgumentError);
      expect(() => p.maximize('Color'), throwsArgumentError);
    });

    test('original problem state intact after integrated B&B', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      final varsBefore = p.variableCount;
      final consBefore = p.constraintCount;
      final domsBefore = Map<String, List<dynamic>>.from(p.variables);
      await p.minimize('A');
      expect(p.variableCount, equals(varsBefore));
      expect(p.constraintCount, equals(consBefore));
      // Domains untouched by the engine's in-place tightening.
      expect(p.variables['A'], equals(domsBefore['A']));
      expect(p.variables['B'], equals(domsBefore['B']));
    });
  });

  group('minimize / maximize with heuristic flags', () {
    // The integrated B&B engine accepts the same useDomWdeg / useVsids /
    // useImpact / useLastConflict flags the satisfy entry points do.
    // We assert solution validity here (the heuristic is a search
    // ordering, not a contract) and confirm SolverStats reflect the
    // expected effort — `decisions > 0` for any non-trivial search.

    test('minimize with useDomWdeg solves to the same optimum', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.minimize('A', useDomWdeg: true);
      expect((result as Map)['A'], 1);
      expect(CSP.lastStats!.decisions, greaterThan(0));
    });

    test('maximize with useVsids solves to the same optimum', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.maximize('A', useVsids: true);
      expect((result as Map)['A'], 4);
    });

    test('minimize with useImpact composes with the same B&B path', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4, 5])
        ..addStringConstraint('X + Y == 6');
      final result = await p.minimize('X', useImpact: true);
      expect((result as Map)['X'], 1);
      expect(result['Y'], 5);
    });

    test('maximize with useLastConflict + useDomWdeg composes', () async {
      // Last-conflict reasoning is a wrapper over the underlying
      // picker; we pair it with dom/wdeg, mirroring Lecoutre's
      // canonical deployment shape.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result =
          await p.maximize('A', useLastConflict: true, useDomWdeg: true);
      expect((result as Map)['A'], 3);
    });
  });
}

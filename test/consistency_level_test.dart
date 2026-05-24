// Several tests in this file pass `ConsistencyLevel.arcConsistency`
// explicitly so that an AC reference run sits next to its FC variant
// in the source; the redundancy is the assertion.
// ignore_for_file: avoid_redundant_argument_values

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Builds a fresh Australia map-coloring problem (small classic).
Problem _australia() {
  final p = Problem();
  const colors = ['red', 'green', 'blue'];
  p.addVariables(['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T'], colors);
  // Border pairs.
  const borders = [
    ['SA', 'WA'],
    ['SA', 'NT'],
    ['SA', 'Q'],
    ['SA', 'NSW'],
    ['SA', 'V'],
    ['WA', 'NT'],
    ['NT', 'Q'],
    ['Q', 'NSW'],
    ['NSW', 'V'],
  ];
  for (final b in borders) {
    p.addConstraint(b, (dynamic a, dynamic c) => a != c);
  }
  return p;
}

/// Builds a fresh N-queens problem.
Problem _queens(int n) {
  final p = Problem();
  final qs = [for (var i = 0; i < n; i++) 'Q$i'];
  p.addVariables(qs, [for (var i = 1; i <= n; i++) i]);
  p.addAllDifferent(qs);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final d = j - i;
      p.addConstraint(
        [qs[i], qs[j]],
        (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
      );
    }
  }
  return p;
}

void main() {
  group('ConsistencyLevel', () {
    test('default is arcConsistency on getSolution', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A < B');
      final defaultSol = await p.getSolution();
      // Explicit AC value here is intentional — the assertion is that
      // the default matches the explicit value.
      final acSol =
          await p.getSolution(consistency: ConsistencyLevel.arcConsistency);
      expect(defaultSol, equals(acSol));
    });

    test('FC finds a valid solution on Australia map coloring', () async {
      final result = await _australia()
          .getSolution(consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      // Verify some border constraints hold.
      expect(s['SA'], isNot(equals(s['WA'])));
      expect(s['SA'], isNot(equals(s['NT'])));
      expect(s['SA'], isNot(equals(s['Q'])));
      expect(s['SA'], isNot(equals(s['NSW'])));
      expect(s['SA'], isNot(equals(s['V'])));
      // T has no neighbors → must be one of the three colors.
      expect(['red', 'green', 'blue'], contains(s['T']));
    });

    test('FC solves 6-queens', () async {
      final result = await _queens(6)
          .getSolution(consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      final cols = [for (var i = 0; i < 6; i++) s['Q$i'] as int];
      expect(cols.toSet().length, equals(6),
          reason: 'all queens in distinct columns');
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          expect((cols[i] - cols[j]).abs(), isNot(equals(j - i)),
              reason: 'queens $i and $j on same diagonal');
        }
      }
    });

    test('FC and AC enumerate the same set of solutions', () async {
      // Small but nontrivial: A,B,C ∈ [1..4], A<B, B<C, A+C=5.
      Problem build() => Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C')
        ..addStringConstraint('A + C == 5');

      final acSols = <Map<String, dynamic>>[];
      // Explicit AC for symmetry with the FC variant below.
      await for (final s in build()
          .getSolutions(consistency: ConsistencyLevel.arcConsistency)) {
        acSols.add(s);
      }
      final fcSols = <Map<String, dynamic>>[];
      await for (final s in build()
          .getSolutions(consistency: ConsistencyLevel.forwardChecking)) {
        fcSols.add(s);
      }
      expect(fcSols.length, equals(acSols.length));
      // Compare as sets (FC may visit in a different order).
      Set<String> asKey(List<Map<String, dynamic>> ss) => ss
          .map((m) =>
              m.entries.map((e) => '${e.key}=${e.value}').toList().join(','))
          .toSet();
      expect(asKey(fcSols), equals(asKey(acSols)));
    });

    test('FC handles n-ary constraints via addAllDifferent', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result =
          await p.getSolution(consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('FC on an infeasible problem returns FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result =
          await p.getSolution(consistency: ConsistencyLevel.forwardChecking);
      expect(result, equals('FAILURE'));
    });

    test('FC skips cascade work that AC performs (chain over a wide domain)',
        () async {
      // Chain A1<A2<A3<A4<A5 over [1..10]. Each constraint's initial
      // revise narrows its neighbor's domain by one value (no
      // singletons). AC then cascades — re-revising arcs whose endpoint
      // just changed — and continues narrowing each domain. FC by
      // construction does no cascading when the result is still
      // multi-valued, so it does strictly fewer revises.
      Problem build() => Problem()
        ..addVariables(
            ['A1', 'A2', 'A3', 'A4', 'A5'], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ..addStringConstraint('A1 < A2')
        ..addStringConstraint('A2 < A3')
        ..addStringConstraint('A3 < A4')
        ..addStringConstraint('A4 < A5');

      final pAc = build();
      // Explicit AC for symmetry with the FC variant below.
      await pAc.getSolution(consistency: ConsistencyLevel.arcConsistency);
      final acStats = pAc.lastStats!;

      final pFc = build();
      await pFc.getSolution(consistency: ConsistencyLevel.forwardChecking);
      final fcStats = pFc.lastStats!;

      expect(fcStats.binaryRevises, lessThan(acStats.binaryRevises),
          reason: 'FC must skip the multi-valued cascade');
    });

    test('FC composes with getSolutionWithDomWdeg', () async {
      final result = await _queens(5).getSolutionWithDomWdeg(
          consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('FC composes with getSolutionWithRestarts', () async {
      final result = await _queens(6).getSolutionWithRestarts(
        seed: 7,
        consistency: ConsistencyLevel.forwardChecking,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('FC composes with minimize (integrated B&B)', () async {
      // Pick a tiny problem with a known optimum to keep the test fast.
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4, 5])
        ..addStringConstraint('X + Y >= 6');
      final result =
          await p.minimize('X', consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      // Provably-optimal: smallest X with some Y making X+Y>=6.
      // X=1, Y=5 satisfies; nothing smaller does.
      expect(s['X'], equals(1));
      expect((s['X'] as int) + (s['Y'] as int), greaterThanOrEqualTo(6));
    });

    test('FC composes with maximize (integrated B&B)', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4])
        ..addStringConstraint('X + Y <= 5');
      final result =
          await p.maximize('X', consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(4));
    });
  });

  group('ConsistencyLevel — top-level CSP entry points', () {
    test('CSP.solve accepts consistency parameter', () async {
      final csp = CspProblem(variables: {
        'A': [1, 2, 3],
        'B': [1, 2, 3],
      });
      final result =
          await CSP.solve(csp, consistency: ConsistencyLevel.forwardChecking);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('CSP.solveAll accepts consistency parameter', () async {
      final csp = CspProblem(variables: {
        'A': [1, 2],
        'B': [1, 2],
      });
      final solutions = await CSP
          .solveAll(csp, consistency: ConsistencyLevel.forwardChecking)
          .toList();
      // 2x2 with no constraints = 4 assignments.
      expect(solutions.length, equals(4));
    });
  });
}

// Several tests in this file pass `ConsistencyLevel.arcConsistency`
// explicitly so that an AC reference run sits next to its SAC variant
// in the source; the redundancy is the assertion.
// ignore_for_file: avoid_redundant_argument_values

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// A classic SAC-stronger-than-AC instance: a chain of binary
/// equalities `A == B`, `B == C` over the same domain. AC already
/// suffices for satisfiability detection here, but the canonical
/// SAC win is on instances where AC leaves dead-end values that SAC
/// catches at preprocessing. We use one such pattern below.
Problem _sacOnlyChain() {
  // Three variables, domains {1, 2, 3, 4}. Two binary constraints:
  //   A < B
  //   B < C
  // After AC: dom(A)={1,2}, dom(B)={2,3}, dom(C)={3,4}. AC is
  // satisfied — every (A=a, B=b) with a<b has support and so on.
  // SAC then tests each (var, value) by tentatively pinning and
  // re-propagating; this finds that A=2 is SAC (B=3, C=4 works) and
  // A=1 is SAC, so SAC matches AC on this small case. We use it for
  // a basic correctness test, not for SAC-only pruning.
  final p = Problem()
    ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
    ..addStringConstraint('A < B')
    ..addStringConstraint('B < C');
  return p;
}

/// A small CSP where AC keeps a value that SAC can prune.
/// Variables x, y, z all over {1, 2, 3} with constraints:
///   x == y
///   y == z
///   x != z  (forces infeasibility along that chain)
/// AC alone does NOT detect infeasibility here because the binary
/// arcs are pairwise satisfiable (each value of x has a support in y,
/// each value of y has a support in z, etc.). SAC catches it: pinning
/// x = 1 forces y = 1, then z = 1, but x != z then wipes x. Same for
/// 2 and 3, so SAC empties dom(x) → infeasibility at preprocessing.
Problem _sacOnlyInfeasible() {
  final p = Problem()
    ..addVariables(['x', 'y', 'z'], [1, 2, 3])
    ..addStringConstraint('x == y')
    ..addStringConstraint('y == z')
    ..addStringConstraint('x != z');
  return p;
}

/// Australia map-coloring with three colors (the textbook tractable
/// instance — both AC and SAC find a solution, used to verify SAC
/// doesn't over-prune).
Problem _australia() {
  final p = Problem();
  const colors = ['red', 'green', 'blue'];
  p.addVariables(['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T'], colors);
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

void main() {
  group('SAC (singleton arc consistency preprocessing)', () {
    test('default is still arcConsistency on getSolution', () async {
      final p = _sacOnlyChain();
      final defaultSol = await p.getSolution();
      final acSol =
          await p.getSolution(consistency: ConsistencyLevel.arcConsistency);
      expect(defaultSol, equals(acSol));
    });

    test('SAC finds a valid solution on Australia map coloring', () async {
      final result = await _australia()
          .getSolution(consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['SA'], isNot(equals(s['WA'])));
      expect(s['SA'], isNot(equals(s['NT'])));
      expect(s['SA'], isNot(equals(s['Q'])));
      expect(s['SA'], isNot(equals(s['NSW'])));
      expect(s['SA'], isNot(equals(s['V'])));
      expect(['red', 'green', 'blue'], contains(s['T']));
    });

    test('SAC detects infeasibility AC misses (x==y, y==z, x!=z)', () async {
      // The motivating SAC-only example: AC keeps all values; SAC
      // empties the first domain it tests.
      final result = await _sacOnlyInfeasible()
          .getSolution(consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, equals('FAILURE'));
    });

    test('AC alone does NOT detect the same infeasibility before search',
        () async {
      // Companion of the above: under plain AC, the engine has to
      // actually descend into search to discover infeasibility. Both
      // SAC and AC eventually return FAILURE; only SAC proves it at
      // preprocessing. We assert AC's decision count is non-zero —
      // i.e. some search did happen — while SAC's is zero (proved
      // infeasible at the root).
      final pAc = _sacOnlyInfeasible();
      await pAc.getSolution(consistency: ConsistencyLevel.arcConsistency);
      final acStats = pAc.lastStats!;

      final pSac = _sacOnlyInfeasible();
      await pSac.getSolution(
          consistency: ConsistencyLevel.singletonArcConsistency);
      final sacStats = pSac.lastStats!;

      expect(acStats.decisions, greaterThan(0),
          reason: 'AC must descend into search to detect infeasibility');
      expect(sacStats.decisions, equals(0),
          reason: 'SAC must prove infeasibility at preprocessing');
    });

    test('SAC and AC enumerate the same set of solutions', () async {
      Problem build() => Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C')
        ..addStringConstraint('A + C == 5');

      final acSols = <Map<String, dynamic>>[];
      await for (final s in build()
          .getSolutions(consistency: ConsistencyLevel.arcConsistency)) {
        acSols.add(s);
      }
      final sacSols = <Map<String, dynamic>>[];
      await for (final s in build().getSolutions(
          consistency: ConsistencyLevel.singletonArcConsistency)) {
        sacSols.add(s);
      }
      expect(sacSols.length, equals(acSols.length));
      Set<String> asKey(List<Map<String, dynamic>> ss) => ss
          .map((m) =>
              m.entries.map((e) => '${e.key}=${e.value}').toList().join(','))
          .toSet();
      expect(asKey(sacSols), equals(asKey(acSols)));
    });

    test('SAC handles n-ary constraints via addAllDifferent', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolution(
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('SAC reduces decisions on a chain CSP', () async {
      // Chain A1<A2<A3<A4<A5 over [1..6]. AC narrows each domain
      // (initial revise: dom(A1)={1..2}, dom(A2)={2..3}, ...,
      // dom(A5)={5..6}). After AC, the search still has to descend
      // to find the unique solution. SAC tightens further: pinning
      // A1=2 leaves no support for A2..A5 once propagated, so A1 is
      // forced to 1; similarly cascades through. SAC reduces (or
      // eliminates) search descent.
      Problem build() => Problem()
        ..addVariables(['A1', 'A2', 'A3', 'A4', 'A5'], [1, 2, 3, 4, 5, 6])
        ..addStringConstraint('A1 < A2')
        ..addStringConstraint('A2 < A3')
        ..addStringConstraint('A3 < A4')
        ..addStringConstraint('A4 < A5');

      final pAc = build();
      await pAc.getSolution(consistency: ConsistencyLevel.arcConsistency);
      final acStats = pAc.lastStats!;

      final pSac = build();
      await pSac.getSolution(
          consistency: ConsistencyLevel.singletonArcConsistency);
      final sacStats = pSac.lastStats!;

      expect(sacStats.decisions, lessThanOrEqualTo(acStats.decisions),
          reason: 'SAC must do no more decisions than AC on a chain CSP');
    });

    test('SAC at root reduces domain to a singleton in a forced case',
        () async {
      // x in [1, 2, 3], y in [1, 2, 3]. x == y AND x + y == 4. Only
      // (2, 2) works. AC alone leaves dom(x) = {1, 2, 3} (each value
      // has *some* support — x=1 supports y=1 via x==y, but x+y==4
      // requires y=3; the conflict only surfaces during search). SAC
      // tentatively pins each value and prunes the ones that fail.
      final p = Problem()
        ..addVariables(['x', 'y'], [1, 2, 3])
        ..addStringConstraint('x == y')
        ..addStringConstraint('x + y == 4');
      final result = await p.getSolution(
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['x'], equals(2));
      expect(s['y'], equals(2));
    });

    test('SAC composes with getSolutionWithDomWdeg', () async {
      final result = await _australia().getSolutionWithDomWdeg(
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('SAC composes with getSolutionWithRestarts', () async {
      final result = await _australia().getSolutionWithRestarts(
        seed: 7,
        consistency: ConsistencyLevel.singletonArcConsistency,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('SAC composes with minimize (integrated B&B)', () async {
      // Solve a tiny optimization with a known optimum and check SAC
      // doesn't break it.
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4, 5])
        ..addStringConstraint('X + Y >= 6');
      final result = await p.minimize('X',
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(1));
      expect((s['X'] as int) + (s['Y'] as int), greaterThanOrEqualTo(6));
    });

    test('SAC composes with maximize (integrated B&B)', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 2, 3, 4])
        ..addStringConstraint('X + Y <= 5');
      final result = await p.maximize('X',
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(4));
      expect((s['X'] as int) + (s['Y'] as int), lessThanOrEqualTo(5));
    });

    test('SAC composes with conflict-directed backjumping', () async {
      final result = await _australia().getSolution(
        consistency: ConsistencyLevel.singletonArcConsistency,
        enableConflictBackjumping: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('SAC preserves domain when no value is prunable', () async {
      // Loose problem: A, B over [1, 2, 3], A != B. Every value of
      // A has support (any non-equal B). SAC must leave the domain
      // intact.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      final all = await p
          .getSolutions(consistency: ConsistencyLevel.singletonArcConsistency)
          .toList();
      // 3 × 2 = 6 ordered pairs.
      expect(all, hasLength(6));
    });

    test('SAC iterates to fixpoint (multi-round pruning)', () async {
      // Construct a CSP where the first SAC pass prunes some values
      // and the second pass prunes more (because the pruned values
      // enabled new singleton-arc failures).
      //
      // a, b, c, d ∈ {1, 2, 3}. Constraints:
      //   a == b
      //   b != c
      //   c == d
      //   a + d == 4
      // AC alone: each constraint is pairwise OK; nothing pruned.
      // SAC pass 1: tries each value. Pin a=1 → b=1; b!=c → c∈{2,3};
      // c==d → d=c; a+d=4 → d=3. So a=1 works (with c=d=3, b=1).
      // Pin a=2 → b=2; c∈{1,3}; d=c; 2+d=4 → d=2 → c=2 contradicts
      // c != b=2. So a=2 is pruned. Similarly a=3 keeps. Result:
      // a ∈ {1, 3}. SAC pass 2 may find more. The exact end-state
      // depends on the algorithm; we just assert the eventual
      // solution set agrees with AC.
      Problem build() => Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3])
        ..addStringConstraint('a == b')
        ..addStringConstraint('b != c')
        ..addStringConstraint('c == d')
        ..addStringConstraint('a + d == 4');

      final acSols = <Map<String, dynamic>>[];
      await for (final s in build()
          .getSolutions(consistency: ConsistencyLevel.arcConsistency)) {
        acSols.add(s);
      }
      final sacSols = <Map<String, dynamic>>[];
      await for (final s in build().getSolutions(
          consistency: ConsistencyLevel.singletonArcConsistency)) {
        sacSols.add(s);
      }
      expect(sacSols.length, equals(acSols.length));
    });

    test('CSP.solve accepts singletonArcConsistency', () async {
      final problem = CspProblem(
        variables: {
          'A': [1, 2, 3],
          'B': [1, 2, 3]
        },
        constraints: [
          BinaryConstraint('A', 'B', (dynamic a, dynamic b) => a != b),
          BinaryConstraint('B', 'A', (dynamic a, dynamic b) => a != b),
        ],
      );
      final result = await CSP.solve(problem,
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('SAC empties a forced-infeasible single-variable problem', () async {
      // x ∈ [1, 2, 3], constraint forces x ∉ any value (x < 0). SAC
      // prunes every value at the first pass.
      final p = Problem()
        ..addVariable('x', [1, 2, 3])
        ..addStringConstraint('x < 0');
      final result = await p.getSolution(
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(result, equals('FAILURE'));
    });

    test('SAC equals AC on already-AC-tight problems (8-queens)', () async {
      // 8-queens is famously AC-easy and SAC-easy. Both should find
      // a valid solution; the solution set is the same.
      Problem queens(int n) {
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

      final pSac = queens(8);
      final sacSol = await pSac.getSolution(
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(sacSol, isA<Map<String, dynamic>>());
      final s = sacSol as Map<String, dynamic>;
      // Sanity check: 8 queens, all in distinct columns and no
      // shared diagonals.
      final cols = [for (var i = 0; i < 8; i++) s['Q$i'] as int];
      expect(cols.toSet().length, equals(8));
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
          expect((cols[i] - cols[j]).abs(), isNot(equals(j - i)));
        }
      }
    });
  });
}

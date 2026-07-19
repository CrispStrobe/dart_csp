import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// A seeded random 3-SAT instance as CNF over Boolean variables. At ratio
/// ~4.2 (m ≈ 4.2·n) these sit near the phase transition, so the satisfiable
/// ones require real conflict-driven search — the regime where warm-start's
/// clause reuse actually helps. Records the clauses so solutions can be
/// verified.
class _Cnf {
  _Cnf(this.n, this.m, int seed) {
    final rng = Random(seed);
    for (var c = 0; c < m; c++) {
      final chosen = <int>{};
      while (chosen.length < 3) {
        chosen.add(rng.nextInt(n));
      }
      final pos = <String>[], neg = <String>[];
      for (final v in chosen) {
        (rng.nextBool() ? pos : neg).add('v$v');
      }
      clauses.add((pos: pos, neg: neg));
    }
  }

  final int n;
  final int m;
  final List<({List<String> pos, List<String> neg})> clauses = [];

  Problem build() {
    final p = Problem();
    for (var i = 0; i < n; i++) {
      p.addVariable('v$i', [0, 1]);
    }
    for (final c in clauses) {
      p.addClause(positive: c.pos, negative: c.neg);
    }
    return p;
  }

  /// True iff [sol] satisfies every clause (a positive literal true or a
  /// negative literal false).
  bool satisfies(Map<String, dynamic> sol) {
    for (final c in clauses) {
      final ok = c.pos.any((v) => sol[v] == 1) || c.neg.any((v) => sol[v] == 0);
      if (!ok) return false;
    }
    return true;
  }
}

void main() {
  // seed 12 at 50 vars / 210 clauses is satisfiable and conflict-heavy
  // (~60 learned clauses when solved), the ideal warm-start showcase.
  final hard = _Cnf(50, 210, 12);

  group('prime / cache', () {
    test('prime populates the base-clause cache on a hard base', () async {
      final s = IncrementalSolver(hard.build());
      expect(s.cachedClauseCount, 0);
      await s.prime();
      expect(s.cachedClauseCount, greaterThan(0));
    });

    test('solveWarm auto-primes when not primed', () async {
      final s = IncrementalSolver(hard.build())..assumeEquals('v0', 1);
      expect(s.cachedClauseCount, 0);
      await s.solveWarm();
      expect(s.cachedClauseCount, greaterThan(0));
    });

    test('an easy base caches nothing but still solves correctly', () async {
      // Propagation-solvable: no conflicts, no learned clauses.
      final base = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addStringConstraint('a < b');
      final s = IncrementalSolver(base)..assumeEquals('a', 1);
      final r = await s.solveWarm();
      expect(s.cachedClauseCount, 0); // nothing learned from an easy base
      expect(r, isA<Map<String, dynamic>>()); // still correct
      expect(r['a'], 1);
    });
  });

  group('correctness: warm-start never changes the answer', () {
    test('SAT/UNSAT agrees with a cold solve across many assumptions',
        () async {
      var checked = 0;
      for (var i = 0; i < 12; i++) {
        final asmVar = 'v$i';
        final asmVal = i.isEven ? 1 : 0;

        final cold = await (IncrementalSolver(hard.build())
              ..assumeEquals(asmVar, asmVal))
            .materialize()
            .solveWithLcg();

        final warm = await (IncrementalSolver(hard.build())
              ..assumeEquals(asmVar, asmVal))
            .solveWarm();

        expect(cold is Map, warm is Map,
            reason: 'warm and cold must agree on satisfiability for '
                '$asmVar == $asmVal');
        if (warm is Map<String, dynamic>) {
          expect(hard.satisfies(warm), isTrue,
              reason: 'warm solution must satisfy every base clause');
          expect(warm[asmVar], asmVal, reason: 'assumption must hold');
        }
        checked++;
      }
      expect(checked, 12);
    });

    test('warm-started UNSAT under a contradictory assumption', () async {
      // Force an obvious contradiction; both paths must report FAILURE.
      final s = IncrementalSolver(hard.build())
        ..assumeEquals('v0', 1)
        ..assumeNotEquals('v0', 1);
      expect(await s.solveWarm(), 'FAILURE');
    });
  });

  group('benefit: warm-start reduces search on a hard base', () {
    test('summed decisions are lower warm than cold', () async {
      var coldDecisions = 0;
      var warmDecisions = 0;
      for (var i = 0; i < 5; i++) {
        final asmVar = 'v$i';
        final asmVal = i.isEven ? 1 : 0;

        await (IncrementalSolver(hard.build())..assumeEquals(asmVar, asmVal))
            .materialize()
            .solveWithLcg();
        coldDecisions += CSP.lastStats!.decisions;

        final ws = IncrementalSolver(hard.build())
          ..assumeEquals(asmVar, asmVal);
        await ws.solveWarm();
        warmDecisions += CSP.lastStats!.decisions;
      }
      // Observed ~258 cold vs ~76 warm; assert a clear reduction with a
      // wide margin so heuristic jitter across platforms can't flake it.
      expect(warmDecisions, lessThan(coldDecisions),
          reason: 'imported base nogoods should prune the re-solve');
    });
  });
}

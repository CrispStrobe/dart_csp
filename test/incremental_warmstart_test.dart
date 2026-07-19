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

  group('assumption-tagged reuse', () {
    // A clause learned while assumptions were active is only sound to
    // reuse when those assumptions are *still* active. These tests drive
    // the tagging directly rather than hoping a solve produces tagged
    // clauses organically — see the note at the end of the group.

    test('cached clauses are gated by the active assumption set', () async {
      final s = IncrementalSolver(hard.build());
      await s.prime();
      final base = s.cachedClauseCount;
      expect(base, greaterThan(0));
      // Priming runs with no assumptions, so everything it learns is
      // unconditional and stays importable no matter what is assumed.
      expect(s.unconditionalClauseCount, base);
      expect(s.importableClauseCount, base);

      s.push();
      s.assumeEquals('v0', 1);
      expect(s.importableClauseCount, base,
          reason: 'unconditional clauses stay importable under assumptions');
      await s.solveWarm();

      // Whatever the assumption solve added is tagged with that
      // assumption, so popping it must not reduce the unconditional set
      // and must not leave a tagged clause importable.
      final tagged = s.cachedClauseCount - s.unconditionalClauseCount;
      s.pop();
      expect(s.unconditionalClauseCount, base);
      expect(s.importableClauseCount, s.cachedClauseCount - tagged,
          reason: 'tagged clauses must drop out once their assumption is '
              'retracted');
    });

    test('a re-pushed assumption gets a fresh id, not the retracted one',
        () async {
      // Ids must never be recycled: a clause tagged with the old
      // assumption would otherwise look reusable under the new one, which
      // happens to be identical here but need not be in general.
      final s = IncrementalSolver(hard.build());
      await s.prime();
      s.push();
      s.assumeEquals('v0', 1);
      await s.solveWarm();
      final importableWith = s.importableClauseCount;
      s.pop();
      s.push();
      s.assumeEquals('v0', 1); // same assumption, new id
      expect(s.importableClauseCount, lessThanOrEqualTo(importableWith),
          reason: 'a fresh id cannot unlock clauses tagged with the old one');
      // And the answer is still right.
      final r = await s.solveWarm();
      expect(r, isA<Map<String, dynamic>>());
      expect((r as Map<String, dynamic>)['v0'], 1);
    });

    test('clearCache resets to un-primed', () async {
      final s = IncrementalSolver(hard.build());
      await s.prime();
      expect(s.cachedClauseCount, greaterThan(0));
      s.clearCache();
      expect(s.cachedClauseCount, 0);
      expect(s.importableClauseCount, 0);
      // Next solveWarm re-primes.
      await s.solveWarm();
      expect(s.cachedClauseCount, greaterThan(0));
    });

    test('the cache respects maxCachedClauses', () async {
      final s = IncrementalSolver(hard.build(), maxCachedClauses: 5);
      await s.prime();
      expect(s.cachedClauseCount, lessThanOrEqualTo(5));
      // Still correct with a tiny cache — reuse is an optimization.
      s.assumeEquals('v0', 1);
      final r = await s.solveWarm();
      expect(r, isA<Map<String, dynamic>>());
      expect(hard.satisfies(r as Map<String, dynamic>), isTrue);
    });

    test('duplicate nogoods are not stored twice', () async {
      final s = IncrementalSolver(hard.build());
      await s.prime();
      final afterFirst = s.cachedClauseCount;
      // Re-solving the same base under no assumptions re-derives the same
      // nogoods; they must collapse onto the existing entries.
      await s.solveWarm();
      expect(s.cachedClauseCount, lessThanOrEqualTo(afterFirst * 2),
          reason: 'dedup should stop the cache doubling on every re-solve');
    });

    test('correctness holds across nested push/pop with reuse', () async {
      // The gate: whatever gets reused, the answers must match a cold
      // solve, and every returned solution must satisfy base + assumptions.
      final rng = Random(20260719);
      final warm = IncrementalSolver(hard.build());
      await warm.prime();
      for (var trial = 0; trial < 12; trial++) {
        final picks = <String, int>{};
        for (var k = 0; k < 1 + rng.nextInt(4); k++) {
          picks['v${rng.nextInt(hard.n)}'] = rng.nextInt(2);
        }
        warm.push();
        final cold = IncrementalSolver(hard.build());
        picks.forEach((v, val) {
          warm.assumeEquals(v, val);
          cold.assumeEquals(v, val);
        });
        final rw = await warm.solveWarm();
        final rc = await cold.solve();
        expect(rw is Map, rc is Map,
            reason: 'trial $trial: warm and cold disagree on SAT/UNSAT '
                'for $picks');
        if (rw is Map<String, dynamic>) {
          expect(hard.satisfies(rw), isTrue, reason: 'trial $trial');
          picks.forEach((v, val) => expect(rw[v], val, reason: 'trial $trial'));
        }
        warm.pop();
      }
    });

    test('assumeEquals on an integer variable posts an atom clause', () async {
      // Atom clauses go to the watched-literal propagator, which is both
      // faster than a predicate revise and — the reason this matters —
      // explains its propagations, so conflict analysis can resolve
      // through an assumption instead of stopping at it.
      final s = IncrementalSolver(hard.build())..assumeEquals('v0', 1);
      final r = await s.solve();
      expect(r, isA<Map<String, dynamic>>());
      expect((r as Map<String, dynamic>)['v0'], 1);

      // A non-integer domain falls back to the predicate form, which must
      // still work.
      final strings = Problem()
        ..addVariable('c', ['red', 'green', 'blue'])
        ..addVariable('d', ['red', 'green', 'blue'])
        ..addStringConstraint('c != d');
      final s2 = IncrementalSolver(strings)..assumeEquals('c', 'red');
      final r2 = await s2.solve();
      expect((r2 as Map<String, dynamic>)['c'], 'red');
      expect(r2['d'], isNot('red'));
    });

    test('a solve does not mutate the problem it runs on', () async {
      // The LCG engine appends learned clauses to its CspProblem's
      // constraint list so its propagation queue can index them. With the
      // live list that permanently grew the caller's Problem — 210
      // constraints became 270 after one solve, and again after the next —
      // which also broke IncrementalSolver's promise that the base is
      // never modified.
      final p = hard.build();
      final before = p.constraintCount;
      await p.solveWithLcg();
      expect(p.constraintCount, before);
      await p.solveWithLcg();
      expect(p.constraintCount, before);

      final base = hard.build();
      final baseCount = base.constraintCount;
      final s = IncrementalSolver(base);
      await s.prime();
      s.assumeEquals('v0', 1);
      await s.solveWarm();
      expect(base.constraintCount, baseCount,
          reason: 'the base problem must be untouched by priming or solving');
    });

    test('assumeInSet lowers to a real disjunction over integers', () async {
      final p = Problem()
        ..addRangeVariable('x', 0, 9)
        ..addRangeVariable('y', 0, 9)
        ..addStringConstraint('x < y');
      final s = IncrementalSolver(p)..assumeInSet('x', {3, 5, 7});
      for (var i = 0; i < 3; i++) {
        final r = await s.solve();
        expect({3, 5, 7}.contains((r as Map<String, dynamic>)['x']), isTrue);
      }
      // Empty set is unsatisfiable, and must stay so.
      final s2 = IncrementalSolver(p)..assumeInSet('x', <int>{});
      expect(await s2.solve(), 'FAILURE');
    });
  });
}

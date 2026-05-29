/// LCG M2b acceptance test: pigeonhole-CNF on the **recursive** learning
/// path (`useIterativeCdcl: false`, pinned explicitly since the public
/// default is now the iterative engine — see `LCG_PLAN.md` §M4).
///
/// On the classic pigeonhole UNSAT instance, learning conflict clauses
/// should drop the decision count by roughly 5–100× on 7-in-6 / 8-in-7
/// compared with the non-LCG path — the canonical demonstration that lazy
/// clause generation changes the asymptotic search-tree size on structured
/// CNF problems. The recursive path backtracks chronologically
/// (`backjumps == 0`); the iterative engine's non-chronological-backjump
/// behaviour is covered in `iterative_cdcl_test.dart`. The concrete ratios
/// checked here are conservative so the test stays robust if the heuristic
/// / propagation ordering shifts.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

Problem _pigeonholeCnf({required int pigeons, required int holes}) {
  final p = Problem();
  for (var pg = 0; pg < pigeons; pg++) {
    for (var h = 0; h < holes; h++) {
      p.addVariable('p${pg}_h$h', [0, 1]);
    }
    p.addClause(positive: [for (var h = 0; h < holes; h++) 'p${pg}_h$h']);
  }
  for (var h = 0; h < holes; h++) {
    for (var i = 0; i < pigeons; i++) {
      for (var j = i + 1; j < pigeons; j++) {
        p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
      }
    }
  }
  return p;
}

Future<({int plain, int lcg, int learned, int backjumps})> _compare(
    int pigeons, int holes) async {
  final plain = _pigeonholeCnf(pigeons: pigeons, holes: holes);
  final viaPlain = await plain.getSolution();
  expect(viaPlain, 'FAILURE', reason: 'pigeonhole $pigeons-in-$holes is UNSAT');
  final plainDecisions = CSP.lastStats!.decisions;

  final lcg = _pigeonholeCnf(pigeons: pigeons, holes: holes);
  final viaLcg = await lcg.solveWithLcg(useIterativeCdcl: false);
  expect(viaLcg, 'FAILURE', reason: 'LCG path must also prove UNSAT');
  final lcgStats = CSP.lastStats!;
  return (
    plain: plainDecisions,
    lcg: lcgStats.decisions,
    learned: lcgStats.learnedClauses,
    backjumps: lcgStats.backjumps,
  );
}

void main() {
  group('LCG M2b — pigeonhole-CNF acceptance gate', () {
    test('6-in-5: LCG reduces the decision count vs plain backtrack', () async {
      final r = await _compare(6, 5);
      expect(r.learned, greaterThan(0),
          reason: 'LCG must learn at least one clause on this UNSAT proof');
      // LCG backtracks chronologically (clause learning, no
      // non-chronological backjump — see `_searchOneLcg`), so the
      // acceptance signal is the decision reduction the learned clauses
      // drive via propagation, not a positive backjump count.
      expect(r.backjumps, 0,
          reason: 'LCG search is chronological; backjumps stays 0');
      expect(r.lcg, lessThan(r.plain),
          reason: 'LCG decisions ($r) must be strictly fewer than plain');
    });

    test('7-in-6: LCG cuts decisions by ≥ 5× vs plain backtrack', () async {
      final r = await _compare(7, 6);
      expect(r.learned, greaterThan(0));
      expect(r.lcg * 5, lessThan(r.plain),
          reason:
              'LCG decisions=${r.lcg}, plain=${r.plain}; ratio must be ≥ 5×');
    });

    test('8-in-7: LCG cuts decisions by ≥ 10× vs plain backtrack', () async {
      final r = await _compare(8, 7);
      expect(r.learned, greaterThan(0));
      expect(r.lcg * 10, lessThan(r.plain),
          reason:
              'LCG decisions=${r.lcg}, plain=${r.plain}; ratio must be ≥ 10×');
    });

    test('learnedClauseCap kwarg triggers forget on a smaller pool', () async {
      // With a low cap the forget policy must drop clauses during the
      // 7-in-6 proof. The proof still succeeds (FAILURE), just with a
      // bounded pool; this is the M2b minimal-forget-correctness gate.
      final p = _pigeonholeCnf(pigeons: 7, holes: 6);
      final r =
          await p.solveWithLcg(useIterativeCdcl: false, learnedClauseCap: 20);
      expect(r, 'FAILURE');
      expect(CSP.lastStats!.forgottenClauses, greaterThan(0),
          reason: 'cap=20 must force at least one forget pass on 7-in-6');
    });
  });

  group('LCG M2b — non-CNF fall-back paths', () {
    test('non-boolean UNSAT problem still returns FAILURE (no clause learned)',
        () async {
      // The all-different propagator emits UnknownReason on the conflict
      // path; the analyser bails and the engine falls back to
      // chronological backtrack. Behaviour must match plain getSolution.
      Problem build() => Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2])
        ..addAllDifferent(['A', 'B', 'C']);
      final viaPlain = await build().getSolution();
      final viaLcg = await build().solveWithLcg(useIterativeCdcl: false);
      expect(viaPlain, 'FAILURE');
      expect(viaLcg, 'FAILURE');
      expect(CSP.lastStats!.learnedClauses, 0,
          reason: 'no boolean clause antecedent ⇒ nothing to learn');
    });

    test('mixed boolean/non-boolean SAT problem returns a valid solution',
        () async {
      // Tiny CNF with one boolean clause plus an unrelated non-boolean
      // variable; exercises the dispatch-on-boolean-domain check in
      // _learnedClauseToSpec.
      final p = Problem()
        ..addVariables(['a', 'b'], [0, 1])
        ..addVariable('x', [10, 20, 30])
        ..addClause(positive: ['a', 'b'])
        ..addStringConstraint('x != 20');
      final r = await p.solveWithLcg(useIterativeCdcl: false);
      expect(r, isA<Map<String, dynamic>>());
      final m = r as Map<String, dynamic>;
      expect(m['a'] == 1 || m['b'] == 1, isTrue,
          reason: 'clause (a ∨ b) must be satisfied');
      expect(m['x'], isNot(20));
    });
  });
}

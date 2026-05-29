/// LCG M4 item 1 — recursive (self-subsuming) learned-clause
/// minimisation (Sörensson & Eén 2009).
///
/// `firstUipAnalyse(..., minimize: true)` drops every non-UIP literal
/// that is *implied* by the conjunction of the remaining clause
/// literals via the implication trail. The result is a shorter,
/// logically stronger implicate that preserves the asserting UIP.
///
/// Two layers of coverage:
///   1. **Unit** — hand-built trails exercising the redundancy logic
///      (single removal, recursive removal, kept premises, root facts,
///      UIP preservation, on/off parity).
///   2. **End-to-end** — `solveWithLcg(useIterativeCdcl: true)` reports
///      `lcgMinimisedLiterals > 0`, stays sound (verdict + assignment),
///      and the stronger clauses enable deeper backjumps on the larger
///      pigeonhole UNSAT proofs.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

ImplicationEntry _entry(int trailIndex, int decisionLevel, Atom atom,
        ImplicationReason reason) =>
    ImplicationEntry(
      prunedAtom: atom,
      reason: reason,
      trailIndex: trailIndex,
      decisionLevel: decisionLevel,
    );

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

void main() {
  group('clause minimisation — unit', () {
    test('removes a non-UIP literal implied by another clause literal', () {
      // L1: decide A; B ⇐ (¬A ∨ B), i.e. reason([A]).
      // L2: decide C; D ⇐ reason([A, B, C]).
      // Conflict: (D, C) at L2 → 1-UIP clause is {C, A, B}, UIP = C.
      // B is implied by A (B's reason antecedent A is in the clause),
      // so minimisation drops it.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(
            1, 1, const AtomEq('B', 1), const ClauseReason([AtomEq('A', 1)])),
        _entry(2, 2, const AtomEq('C', 1), const DecisionReason()),
        _entry(
            3,
            2,
            const AtomEq('D', 1),
            const ClauseReason(
                [AtomEq('A', 1), AtomEq('B', 1), AtomEq('C', 1)])),
      ];
      const conflict = ClauseReason([AtomEq('D', 1), AtomEq('C', 1)]);

      final plain = firstUipAnalyse(trail, conflict);
      expect(
          plain!.learnedClause,
          unorderedEquals([
            const AtomNe('A', 1),
            const AtomNe('B', 1),
            const AtomNe('C', 1)
          ]));
      expect(plain.minimisedLiterals, 0);

      final min = firstUipAnalyse(trail, conflict, minimize: true);
      expect(min, isNotNull);
      expect(min!.uipAtom, const AtomEq('C', 1),
          reason: 'minimisation preserves the asserting UIP');
      expect(min.learnedClause,
          unorderedEquals([const AtomNe('A', 1), const AtomNe('C', 1)]));
      expect(min.minimisedLiterals, 1);
      expect(min.backjumpLevel, 1);
    });

    test('removes literals recursively (two-step implication chain)', () {
      // L1: decide A; B ⇐ reason([A]); E ⇐ reason([B]).
      // L2: decide C; D ⇐ reason([A, B, E, C]).
      // 1-UIP clause = {C, A, B, E}. E ⇐ B ⇐ A, all reachable in the
      // clause, so both E and B are redundant → minimised {C, A}.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(
            1, 1, const AtomEq('B', 1), const ClauseReason([AtomEq('A', 1)])),
        _entry(
            2, 1, const AtomEq('E', 1), const ClauseReason([AtomEq('B', 1)])),
        _entry(3, 2, const AtomEq('C', 1), const DecisionReason()),
        _entry(
            4,
            2,
            const AtomEq('D', 1),
            const ClauseReason([
              AtomEq('A', 1),
              AtomEq('B', 1),
              AtomEq('E', 1),
              AtomEq('C', 1)
            ])),
      ];
      final min = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('D', 1), AtomEq('C', 1)]),
          minimize: true);
      expect(min!.learnedClause,
          unorderedEquals([const AtomNe('A', 1), const AtomNe('C', 1)]));
      expect(min.minimisedLiterals, 2);
    });

    test('keeps a literal whose reason needs an out-of-clause premise', () {
      // B ⇐ reason([F]); F is a decision NOT in the learned clause, so
      // B is not implied by the clause and must be kept.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(1, 1, const AtomEq('F', 1), const DecisionReason()),
        _entry(
            2, 1, const AtomEq('B', 1), const ClauseReason([AtomEq('F', 1)])),
        _entry(3, 2, const AtomEq('C', 1), const DecisionReason()),
        _entry(
            4,
            2,
            const AtomEq('D', 1),
            const ClauseReason(
                [AtomEq('A', 1), AtomEq('B', 1), AtomEq('C', 1)])),
      ];
      final min = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('D', 1), AtomEq('C', 1)]),
          minimize: true);
      // A (decision) and B (needs F ∉ clause) both stay; nothing removed.
      expect(
          min!.learnedClause,
          unorderedEquals([
            const AtomNe('A', 1),
            const AtomNe('B', 1),
            const AtomNe('C', 1)
          ]));
      expect(min.minimisedLiterals, 0);
    });

    test('drops an always-true root-level (decision-level-0) literal', () {
      // Z fixed at the root (level 0); A decided at level 1.
      // Conflict reason references both → clause {A, Z}, UIP = A.
      // Z is a root fact, unconditionally entailed, so it is redundant.
      final trail = [
        _entry(0, 0, const AtomEq('Z', 1), const ClauseReason([])),
        _entry(1, 1, const AtomEq('A', 1), const DecisionReason()),
      ];
      final plain = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('A', 1), AtomEq('Z', 1)]));
      expect(plain!.learnedClause,
          unorderedEquals([const AtomNe('A', 1), const AtomNe('Z', 1)]));

      final min = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('A', 1), AtomEq('Z', 1)]),
          minimize: true);
      expect(min!.learnedClause, [const AtomNe('A', 1)]);
      expect(min.uipAtom, const AtomEq('A', 1),
          reason: 'the UIP is never the literal removed');
      expect(min.minimisedLiterals, 1);
      expect(min.backjumpLevel, 0, reason: 'unit clause backjumps to root');
    });

    test('never removes the UIP, leaving a non-asserting clause', () {
      // A unit 1-UIP clause (only the UIP survives) is untouched —
      // minimisation needs at least two literals to consider a removal.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
      ];
      final min = firstUipAnalyse(trail, const ClauseReason([AtomEq('A', 1)]),
          minimize: true);
      expect(min!.learnedClause, [const AtomNe('A', 1)]);
      expect(min.minimisedLiterals, 0);
    });
  });

  group('clause minimisation — end-to-end (iterative CDCL)', () {
    test('pigeonhole 7-in-6 reports minimised literals and proves UNSAT',
        () async {
      final r = await _pigeonholeCnf(pigeons: 7, holes: 6)
          .solveWithLcg(useIterativeCdcl: true);
      expect(r, 'FAILURE');
      expect(CSP.lastStats!.lcgMinimisedLiterals, greaterThan(0),
          reason: 'self-subsuming minimisation removes redundant literals');
    });

    test('minimisation co-exists with a healthy backjump profile (UNSAT)',
        () async {
      // The off-line A/B (LCG_PLAN.md §M4 item 1) shows minimisation
      // lowers backjump levels and cuts decisions/backtracks on the
      // larger pigeonholes; that comparison needs both flag settings, so
      // here we anchor on the shipped-config invariants: minimisation
      // fires, real backjumps still happen, and UNSAT is proven.
      final r = await _pigeonholeCnf(pigeons: 8, holes: 7)
          .solveWithLcg(useIterativeCdcl: true);
      expect(r, 'FAILURE');
      final s = CSP.lastStats!;
      expect(s.backjumps, greaterThan(0));
      expect(s.backjumpLevelsSkipped, greaterThan(0));
      expect(s.lcgMinimisedLiterals, greaterThan(0));
    });

    test('minimisation stays sound on a SAT problem (correct assignment)',
        () async {
      // 4-queens via binary constraints + a couple of clauses; the
      // iterative engine with minimisation must still return a valid
      // assignment.
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [0, 1])
        ..addClause(positive: ['a', 'b'])
        ..addClause(negative: ['a', 'c'])
        ..addClause(positive: ['c', 'd'])
        ..addClause(negative: ['b', 'd']);
      final r = await p.solveWithLcg(useIterativeCdcl: true);
      expect(r, isA<Map<String, dynamic>>());
      final m = r as Map<String, dynamic>;
      bool sat(List<String> pos, List<String> neg) =>
          pos.any((v) => m[v] == 1) || neg.any((v) => m[v] == 0);
      expect(sat(['a', 'b'], const []), isTrue);
      expect(sat(const [], ['a', 'c']), isTrue);
      expect(sat(['c', 'd'], const []), isTrue);
      expect(sat(const [], ['b', 'd']), isTrue);
    });
  });
}

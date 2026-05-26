import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Convenience for hand-crafted trails: build an [ImplicationEntry]
/// where `trailIndex` equals the position in the input list.
ImplicationEntry _entry(int trailIndex, int decisionLevel, Atom atom,
        ImplicationReason reason) =>
    ImplicationEntry(
      prunedAtom: atom,
      reason: reason,
      trailIndex: trailIndex,
      decisionLevel: decisionLevel,
    );

void main() {
  group('firstUipAnalyse — degenerate cases', () {
    test('empty trail returns null', () {
      final result =
          firstUipAnalyse(const [], const ClauseReason([AtomEq('A', 1)]));
      expect(result, isNull);
    });

    test('conflict with empty antecedents returns null', () {
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
      ];
      expect(firstUipAnalyse(trail, const ClauseReason([])), isNull);
    });

    test('conflict at decision level 0 returns null (root-level unsat)', () {
      // Preprocessing pinned A. No decisions made yet.
      final trail = [
        _entry(0, 0, const AtomEq('A', 1), const ClauseReason([])),
      ];
      final result =
          firstUipAnalyse(trail, const ClauseReason([AtomEq('A', 1)]));
      expect(result, isNull);
    });
  });

  group('firstUipAnalyse — single-level conflicts', () {
    test('decision alone is the UIP, learns the unit-negation', () {
      // Trail: decision A=1 at level 1.
      // Conflict: A=1 is jointly unsatisfiable. (Single-antecedent
      // conflict: the decision itself is the only at-level atom and
      // is the UIP.)
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
      ];
      final result =
          firstUipAnalyse(trail, const ClauseReason([AtomEq('A', 1)]));
      expect(result, isNotNull);
      expect(result!.uipAtom, const AtomEq('A', 1));
      expect(result.backjumpLevel, 0);
      expect(result.learnedClause, [const AtomNe('A', 1)]);
    });

    test('two-decision conflict: latest decision is UIP, both levels in clause',
        () {
      // Level 1: decide A. Level 2: decide B. Conflict on (A, B).
      // No propagation, no resolution needed.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(1, 2, const AtomEq('B', 1), const DecisionReason()),
      ];
      final result = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('A', 1), AtomEq('B', 1)]));
      expect(result, isNotNull);
      expect(result!.uipAtom, const AtomEq('B', 1));
      expect(result.backjumpLevel, 1);
      expect(result.learnedClause,
          unorderedEquals([const AtomNe('A', 1), const AtomNe('B', 1)]));
    });
  });

  group('firstUipAnalyse — resolution chains', () {
    test('one resolution step: implied atom resolves against its clause reason',
        () {
      // Level 1: decide A.
      // Level 2: decide B, then C is implied by (¬A ∨ ¬B ∨ C) →
      // ClauseReason([AtomEq('A', 1), AtomEq('B', 1)]).
      // Conflict: (B, C) at level 2 — two at-level atoms.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(1, 2, const AtomEq('B', 1), const DecisionReason()),
        _entry(2, 2, const AtomEq('C', 1),
            const ClauseReason([AtomEq('A', 1), AtomEq('B', 1)])),
      ];
      final result = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('B', 1), AtomEq('C', 1)]));
      expect(result, isNotNull);
      // After resolving C: working clause = {B, A}. UIP = B.
      expect(result!.uipAtom, const AtomEq('B', 1));
      expect(result.backjumpLevel, 1);
      expect(result.learnedClause,
          unorderedEquals([const AtomNe('A', 1), const AtomNe('B', 1)]));
    });

    test('two resolution steps: nested implied atoms collapse to a decision',
        () {
      // Level 1: decide A.
      // Level 2: decide B, then C implied by (¬B ∨ C) → reason([B]).
      //          then D implied by (¬A ∨ ¬C ∨ D) → reason([A, C]).
      // Conflict: (D, B) — both at level 2.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(1, 2, const AtomEq('B', 1), const DecisionReason()),
        _entry(
            2, 2, const AtomEq('C', 1), const ClauseReason([AtomEq('B', 1)])),
        _entry(3, 2, const AtomEq('D', 1),
            const ClauseReason([AtomEq('A', 1), AtomEq('C', 1)])),
      ];
      final result = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('D', 1), AtomEq('B', 1)]));
      expect(result, isNotNull);
      // Step 1: resolve D → {B, A, C} (count at level 2 = 2: B, C).
      // Step 2: resolve C → {B, A} (count at level 2 = 1: B).
      // UIP = B.
      expect(result!.uipAtom, const AtomEq('B', 1));
      expect(result.backjumpLevel, 1);
      expect(result.learnedClause,
          unorderedEquals([const AtomNe('A', 1), const AtomNe('B', 1)]));
    });

    test(
        'an earlier-level antecedent stays in the clause (no resolution past current level)',
        () {
      // Level 1: decide A, then B implied at level 1 by reason([A]).
      // Level 2: decide C, then D implied by reason([B, C]).
      // Conflict: (D, C) at level 2.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(
            1, 1, const AtomEq('B', 1), const ClauseReason([AtomEq('A', 1)])),
        _entry(2, 2, const AtomEq('C', 1), const DecisionReason()),
        _entry(3, 2, const AtomEq('D', 1),
            const ClauseReason([AtomEq('B', 1), AtomEq('C', 1)])),
      ];
      final result = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('D', 1), AtomEq('C', 1)]));
      expect(result, isNotNull);
      // Step 1: resolve D → {C, B}. countAtLevel = 1 (just C).
      // UIP = C. B stays at level 1, drives backjump.
      expect(result!.uipAtom, const AtomEq('C', 1));
      expect(result.backjumpLevel, 1);
      expect(result.learnedClause,
          unorderedEquals([const AtomNe('B', 1), const AtomNe('C', 1)]));
    });
  });

  group('firstUipAnalyse — opaque-reason behaviour', () {
    test('UnknownReason at the conflict level blocks resolution', () {
      // Mixed reasons: B was forced at level 2 by an UnknownReason
      // placeholder (e.g., a non-clause propagator that hasn't yet
      // shipped its M3 explain companion). The analyser cannot
      // resolve B; falls back to null since two at-level atoms
      // survive.
      final trail = [
        _entry(0, 1, const AtomEq('A', 1), const DecisionReason()),
        _entry(1, 2, const AtomEq('B', 1), const UnknownReason()),
        _entry(2, 2, const AtomEq('C', 1), const DecisionReason()),
      ];
      final result = firstUipAnalyse(
          trail, const ClauseReason([AtomEq('B', 1), AtomEq('C', 1)]));
      expect(result, isNull,
          reason: 'two at-level atoms with no resolvable reason → null');
    });
  });
}

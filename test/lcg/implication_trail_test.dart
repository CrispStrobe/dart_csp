import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('CSP.solveWithLcg implication trail capture', () {
    test('off by default: lastImplicationTrail is null without a solve',
        () async {
      // Run a non-LCG solve first to clear any previous LCG snapshot
      // left behind by other tests, then ensure CSP.solveWithLcg sets it.
      CSP.lastImplicationTrail = null;
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      await p.getSolution();
      // getSolution doesn't populate lastImplicationTrail.
      expect(CSP.lastImplicationTrail, isNull);
    });

    test('solveWithLcg populates lastImplicationTrail (success path)',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());
      expect(CSP.lastImplicationTrail, isNotNull);
      // At least the decision pin for A is on the trail.
      expect(CSP.lastImplicationTrail!.isNotEmpty, isTrue);
    });

    test('decision pins produce AtomEq with DecisionReason', () async {
      // With a singleton-domain variable, the seedAndPreprocess step
      // pins it via _setDomain with cause: null, so we get an AtomEq
      // under DecisionReason. Use a domain wider than 1 plus a
      // hard constraint so the search needs at least one decision.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A != B');
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());
      final decisionEntries = CSP.lastImplicationTrail!
          .where((e) => e.reason is DecisionReason)
          .toList();
      expect(decisionEntries, isNotEmpty);
      // Every decision should pin a singleton, hence an AtomEq.
      for (final e in decisionEntries) {
        expect(e.prunedAtom, isA<AtomEq>(),
            reason: 'decision entry should be AtomEq, got ${e.prunedAtom}');
      }
    });

    test('decision levels increase monotonically along the trail', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());
      final trail = CSP.lastImplicationTrail!;
      expect(trail, isNotEmpty);
      // Entries are appended in trail order; decision level can only
      // grow along the trail (never decrease) on a successful solve
      // because no backtrack rolled past a decision.
      var prevDl = 0;
      for (final e in trail) {
        expect(e.decisionLevel, greaterThanOrEqualTo(prevDl),
            reason: 'decision level dropped along trail: $trail');
        prevDl = e.decisionLevel;
      }
      // The final decision level matches the number of distinct
      // decision-site entries.
      final decisionCount =
          trail.where((e) => e.reason is DecisionReason).length;
      expect(trail.last.decisionLevel, decisionCount);
    });

    test('propagation prunes record AtomNe with UnknownReason in M1', () async {
      // In a 2-var problem with one all-different constraint and a
      // domain of {1, 2, 3}, pinning A to 1 propagates A != 1 into
      // B's domain — that propagation gives an AtomNe('B', 1)
      // entry with UnknownReason (until M3 wires concrete reasons).
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addAllDifferent(['A', 'B']);
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());
      final trail = CSP.lastImplicationTrail!;
      final propagationEntries =
          trail.where((e) => e.reason is UnknownReason).toList();
      expect(propagationEntries, isNotEmpty,
          reason: 'expected at least one propagation prune on the trail');
      // Every propagation entry's atom is an AtomEq (singleton survivor)
      // or AtomNe (value removed) — never an AtomLe/AtomGe in M1.
      for (final e in propagationEntries) {
        expect(e.prunedAtom is AtomNe || e.prunedAtom is AtomEq, isTrue,
            reason: 'unexpected atom shape: ${e.prunedAtom}');
      }
    });

    test('search-detected unsat leaves the trail empty (full rollback)',
        () async {
      // Three vars pairwise-different on a two-element domain: AC-3
      // can't detect unsat at preprocessing (each pair has support),
      // so the engine enters search, exhausts both root candidates,
      // and rolls back every prune. Final trail must be empty.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2])
        ..addAllDifferent(['A', 'B', 'C']);
      final sol = await p.solveWithLcg();
      expect(sol, 'FAILURE');
      expect(CSP.lastImplicationTrail, isNotNull);
      expect(CSP.lastImplicationTrail, isEmpty);
    });

    test('preprocessing-detected unsat leaves the failing chain on the trail',
        () async {
      // {A: [1], B: [1]} with A != B is wiped out by AC-3 before any
      // decision is made. The engine returns null without rolling
      // back the preprocessing trail, so M2 conflict analysis can
      // read the antecedents.
      final p = Problem()
        ..addVariables(['A', 'B'], [1])
        ..addStringConstraint('A != B');
      final sol = await p.solveWithLcg();
      expect(sol, 'FAILURE');
      expect(CSP.lastImplicationTrail, isNotNull);
      expect(CSP.lastImplicationTrail, isNotEmpty,
          reason: 'preprocessing prunes must survive on the trail for M2');
      // No decisions were made, so every entry is at level 0.
      expect(
          CSP.lastImplicationTrail!.every((e) => e.decisionLevel == 0), isTrue);
    });

    test('every entry has a trailIndex within the prune count', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());
      final trail = CSP.lastImplicationTrail!;
      // Trail indices must be non-negative and weakly increasing
      // because the trail is append-only (modulo rollback).
      var prevIdx = -1;
      for (final e in trail) {
        expect(e.trailIndex, greaterThanOrEqualTo(prevIdx),
            reason: 'trailIndex decreased: ${e.trailIndex} after $prevIdx');
        prevIdx = e.trailIndex;
      }
    });

    test('snapshot is immutable: modifying it throws', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      await p.solveWithLcg();
      final trail = CSP.lastImplicationTrail!;
      expect(
          () => trail.add(const ImplicationEntry(
                prunedAtom: AtomEq('Z', 0),
                reason: UnknownReason(),
                trailIndex: 0,
                decisionLevel: 0,
              )),
          throwsUnsupportedError);
    });
  });
}

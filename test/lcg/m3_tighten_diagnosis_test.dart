/// LCG M3-tighten diagnosis + design-validation suite.
///
/// This file is the executable specification for the M3-tighten work
/// (intermediate / trail-shape-matching atom encoding so the first-UIP
/// analyser converges on CSP-shaped reasons). It does two things:
///
///  1. **Measures the gap end-to-end.** On linear-heavy problems (magic
///     squares) every propagation conflict carries a concrete reason
///     but the analyser cannot isolate a UIP, so `learnedClauses` stays
///     0 and `lcgAnalysisFailures` equals the backtrack count. These
///     tests pin the *current* coarse-explanation behaviour; when
///     M3-tighten lands, `lcgAnalysisFailures` should drop and
///     `learnedClauses` should rise, and these expectations get
///     updated as the acceptance gate.
///
///  2. **Validates the fix direction on hand-built trails.** The root
///     cause (confirmed by tracing a real magic-square conflict) is
///     that a coarse per-prune reason references *sibling* at-conflict-
///     level prunes — so resolving one at-level atom re-introduces
///     others and the at-level count never falls to 1. The
///     hand-crafted trails below show:
///       - the coarse "sibling-referencing" shape diverging (bail);
///       - a "newest-cause" shape (each prune references the single
///         decision that forced it) converging to a unit UIP;
///       - a "real intermediate bound atom" shape (each prune
///         references one `AtomGe`/`AtomLe` bound atom that is itself
///         on the trail) converging, with the learned clause carrying
///         the negated bound — i.e. the bound atom is a real,
///         assertable literal, the property that makes the
///         intermediate-atom encoding work for linear constraints.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Build an [ImplicationEntry] whose `trailIndex` equals its position.
ImplicationEntry _e(int i, int dl, Atom atom, ImplicationReason reason) =>
    ImplicationEntry(
        prunedAtom: atom, reason: reason, trailIndex: i, decisionLevel: dl);

/// An n×n magic square: 1..n² all-different, every row / column / both
/// diagonals summing to [magic] via `addLinearEquals`. The linear sums
/// drive the dense conflicts that defeat the coarse analyser.
Problem _magic(int n, int magic) {
  final p = Problem();
  final cells = [for (var i = 0; i < n * n; i++) 'c$i'];
  p
    ..addVariables(cells, [for (var v = 1; v <= n * n; v++) v])
    ..addAllDifferent(cells);
  void sum(List<String> vs) =>
      p.addLinearEquals(vs, List<num>.filled(vs.length, 1), magic);
  for (var r = 0; r < n; r++) {
    sum([for (var c = 0; c < n; c++) 'c${r * n + c}']);
  }
  for (var c = 0; c < n; c++) {
    sum([for (var r = 0; r < n; r++) 'c${r * n + c}']);
  }
  sum([for (var i = 0; i < n; i++) 'c${i * n + i}']);
  sum([for (var i = 0; i < n; i++) 'c${i * n + (n - 1 - i)}']);
  return p;
}

void main() {
  group('M3-tighten diagnosis — end-to-end coarse-explanation gap', () {
    test('4×4 magic square: every conflict bails (no UIP isolated)', () async {
      final r = await _magic(4, 34).solveWithLcg();
      final s = CSP.lastStats!;
      expect(r, isA<Map<String, dynamic>>(),
          reason: 'the puzzle is satisfiable; LCG must still find it via '
              'chronological-backtrack fallback when learning bails');
      expect(s.backtracks, greaterThan(0));
      // The coarse linear/allDifferent explanations leave multiple
      // at-conflict-level atoms on the trail, so the analyser bails on
      // *every* conflict and learns nothing. M3-tighten's goal is to
      // flip these two expectations (failures → learning).
      expect(s.lcgAnalysisFailures, equals(s.backtracks),
          reason: 'current coarse explanations: every backtrack is an '
              'analysis failure');
      expect(s.learnedClauses, equals(0),
          reason: 'M3-tighten target: this should become > 0');
    });

    test('3×3 magic square: same gap at smaller scale', () async {
      final r = await _magic(3, 15).solveWithLcg();
      final s = CSP.lastStats!;
      expect(r, isA<Map<String, dynamic>>());
      expect(s.lcgAnalysisFailures, greaterThan(0));
      expect(s.learnedClauses, equals(0));
    });
  });

  group('M3-tighten design — first-UIP convergence on hand-built trails', () {
    test('coarse sibling-referencing reasons diverge → analyser bails', () {
      // Three values pruned at the conflict level (dl 2); each prune's
      // reason references the *other two* sibling prunes — the coarse
      // "whole-other-scope" shape the linear propagator emits today.
      // Resolving any one re-introduces another, so the at-level count
      // sticks at 2 and no single UIP survives.
      final trail = [
        _e(0, 1, const AtomEq('x', 1), const DecisionReason()),
        _e(1, 2, const AtomNe('a', 3),
            const LinearBoundReason([AtomNe('b', 3), AtomNe('c', 3)])),
        _e(2, 2, const AtomNe('b', 3),
            const LinearBoundReason([AtomNe('a', 3), AtomNe('c', 3)])),
        _e(3, 2, const AtomNe('c', 3),
            const LinearBoundReason([AtomNe('a', 3), AtomNe('b', 3)])),
      ];
      final trace = <String>[];
      final result = firstUipAnalyse(
        trail,
        const LinearBoundReason(
            [AtomNe('a', 3), AtomNe('b', 3), AtomNe('c', 3)]),
        trace: trace.add,
      );
      expect(result, isNull,
          reason: 'sibling-referencing reasons cannot converge to a UIP');
      expect(trace.last, contains('bail: no single UIP'),
          reason: 'instrumentation must report the convergence failure');
    });

    test('newest-cause reasons converge to the decision UIP', () {
      // Same three prunes, but each references only the single decision
      // (y = 5) that forced it — the "newest single cause" shape. The
      // siblings resolve away cleanly, collapsing to the decision UIP.
      final trail = [
        _e(0, 1, const AtomEq('x', 1), const DecisionReason()),
        _e(1, 2, const AtomEq('y', 5), const DecisionReason()),
        _e(2, 2, const AtomNe('a', 3),
            const LinearBoundReason([AtomEq('y', 5)])),
        _e(3, 2, const AtomNe('b', 3),
            const LinearBoundReason([AtomEq('y', 5)])),
        _e(4, 2, const AtomNe('c', 3),
            const LinearBoundReason([AtomEq('y', 5)])),
      ];
      final result = firstUipAnalyse(
        trail,
        const LinearBoundReason(
            [AtomNe('a', 3), AtomNe('b', 3), AtomNe('c', 3)]),
      );
      expect(result, isNotNull);
      expect(result!.uipAtom, const AtomEq('y', 5));
      expect(result.backjumpLevel, 0, reason: 'unit clause → backjump root');
      expect(result.learnedClause, [const AtomNe('y', 5)]);
    });

    test('real intermediate bound atom converges; clause carries the bound',
        () {
      // The intermediate-atom encoding for linear constraints: a single
      // bound atom (z ≥ 10) is established on the trail at the conflict
      // level, and each prune references *it* rather than the sibling
      // prunes. The bound atom is a real, assertable literal, so it is a
      // legitimate UIP and the learned clause carries its negation
      // (z ≤ 9). This is the property that distinguishes the linear
      // intermediate atom from a synthetic allDifferent "Hall" atom.
      final trail = [
        _e(0, 1, const AtomEq('w', 3), const DecisionReason()),
        _e(1, 2, const AtomEq('y', 5), const DecisionReason()),
        _e(2, 2, const AtomGe('z', 10),
            const LinearBoundReason([AtomEq('y', 5), AtomEq('w', 3)])),
        _e(3, 2, const AtomNe('a', 1),
            const LinearBoundReason([AtomGe('z', 10)])),
        _e(4, 2, const AtomNe('b', 1),
            const LinearBoundReason([AtomGe('z', 10)])),
        _e(5, 2, const AtomNe('c', 1),
            const LinearBoundReason([AtomGe('z', 10)])),
      ];
      final result = firstUipAnalyse(
        trail,
        const LinearBoundReason(
            [AtomNe('a', 1), AtomNe('b', 1), AtomNe('c', 1)]),
      );
      expect(result, isNotNull);
      expect(result!.uipAtom, const AtomGe('z', 10));
      expect(result.learnedClause, [const AtomLe('z', 9)],
          reason: 'AtomGe(z,10).negate() == AtomLe(z,9): the intermediate '
              'bound atom is itself a real domain literal');
    });

    test('trace instrumentation reports resolution steps with at-level count',
        () {
      // Reuse the divergent sibling-referencing trail: resolving against
      // a coarse reason re-introduces a sibling at-level atom, which the
      // trace makes visible (the real magic-square trace shows the count
      // climbing 6 → 9 this way).
      final trail = [
        _e(0, 1, const AtomEq('x', 1), const DecisionReason()),
        _e(1, 2, const AtomNe('a', 3),
            const LinearBoundReason([AtomNe('b', 3), AtomNe('c', 3)])),
        _e(2, 2, const AtomNe('b', 3),
            const LinearBoundReason([AtomNe('a', 3), AtomNe('c', 3)])),
        _e(3, 2, const AtomNe('c', 3),
            const LinearBoundReason([AtomNe('a', 3), AtomNe('b', 3)])),
      ];
      final trace = <String>[];
      firstUipAnalyse(
        trail,
        const LinearBoundReason(
            [AtomNe('a', 3), AtomNe('b', 3), AtomNe('c', 3)]),
        trace: trace.add,
      );
      expect(trace.any((l) => l.contains('resolve') && l.contains('atLevel')),
          isTrue,
          reason: 'a resolution step must be reported with the at-level count');
      expect(trace.first, contains('initial working clause'));
    });
  });
}

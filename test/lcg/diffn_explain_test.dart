/// LCG M3f tests: `_DiffNPropagator` forbidden-region explanation companion.
///
/// A coordinate value is pruned from rectangle `r` in dimension `d` when
/// some rectangle `s` mandatorily overlaps `r` in the orthogonal dimension
/// and `v` falls in `s`'s forbidden `d`-interval. Both are functions of
/// `r`'s and `s`'s coordinate **bounds**, so M3f explains the prune with
/// bound atoms (`AtomLe`/`AtomGe`, plus `AtomEq` for a pinned coordinate)
/// collapsed through one synthetic [AtomInScc] bridge — the same
/// bound-shaped shape as the cumulative companion (M3e), built on the
/// bound-atom trail emission.
///
/// Like cumulative (and unlike GAC-strong regular), the sweep is not GAC,
/// so both UNSAT and satisfiable packings search and learn. The acceptance
/// criterion pairs learning activation with a verdict-parity sweep against
/// full enumeration (an unsound clause flips a verdict or yields an
/// overlapping / wrong placement).
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Pack [n] rectangles into a [width]×[height] grid, non-overlapping.
/// Dispatched entirely through `_DiffNPropagator`.
Problem _pack(int n, int width, int height, List<int> ws, List<int> hs) {
  final p = Problem();
  final xs = [for (var i = 0; i < n; i++) 'x$i'];
  final ys = [for (var i = 0; i < n; i++) 'y$i'];
  for (var i = 0; i < n; i++) {
    p.addVariable(xs[i], [for (var v = 0; v <= width - ws[i]; v++) v]);
    p.addVariable(ys[i], [for (var v = 0; v <= height - hs[i]; v++) v]);
  }
  p.addDiffN(xs, ys, ws, hs);
  return p;
}

/// True iff no two rectangles in [sol] overlap.
bool _nonOverlapping(
    Map<String, dynamic> sol, int n, List<int> ws, List<int> hs) {
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final xi = sol['x$i'] as int, yi = sol['y$i'] as int;
      final xj = sol['x$j'] as int, yj = sol['y$j'] as int;
      final separated = xi + ws[i] <= xj ||
          xj + ws[j] <= xi ||
          yi + hs[i] <= yj ||
          yj + hs[j] <= yi;
      if (!separated) return false;
    }
  }
  return true;
}

void main() {
  group('DiffNReason', () {
    test('passes its antecedent atoms through unchanged', () {
      const atoms = [AtomLe('x0', 2), AtomInScc('h', 7)];
      const r = DiffNReason(atoms);
      expect(r.antecedents(), atoms);
      expect(r.toString(), contains('x0 <= 2'));
    });

    test('empty reason has no antecedents', () {
      expect(const DiffNReason([]).antecedents(), isEmpty);
    });
  });

  group('M3f end-to-end — diff_n learning', () {
    test('UNSAT packing proves UNSAT, is active, and learns', () async {
      // Four 3-wide rectangles can't share a 3-wide grid of height 4.
      const n = 4;
      const w = 3, h = 4;
      const ws = [3, 3, 3, 3];
      const hs = [1, 2, 1, 1];
      final plain = await _pack(n, w, h, ws, hs).getSolution();
      expect(plain, 'FAILURE', reason: 'instance must be UNSAT');
      for (var seed = 0; seed < 6; seed++) {
        final lcg = await _pack(n, w, h, ws, hs)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(lcg, 'FAILURE', reason: 'seed=$seed verdict must match plain');
        final st = CSP.lastStats!;
        expect(st.naryRevises, greaterThan(0),
            reason: 'seed=$seed diff_n propagator must prune');
        expect(st.learnedClauses, greaterThanOrEqualTo(1),
            reason: 'seed=$seed must learn from forbidden-region conflicts');
      }
    });

    test('SAT packing with search learns and returns a valid layout', () async {
      const n = 4;
      const w = 3, h = 4;
      const ws = [1, 1, 1, 3];
      const hs = [2, 3, 3, 1];
      var anyLearned = false;
      for (var seed = 0; seed < 8; seed++) {
        final r = await _pack(n, w, h, ws, hs)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(r, isA<Map<String, dynamic>>(),
            reason: 'seed=$seed must stay SAT despite learning');
        expect(_nonOverlapping(r as Map<String, dynamic>, n, ws, hs), isTrue,
            reason: 'seed=$seed returned overlapping rectangles');
        if (CSP.lastStats!.learnedClauses > 0) anyLearned = true;
      }
      expect(anyLearned, isTrue,
          reason: 'at least one decision order must exercise learning');
    });
  });

  group('M3f soundness — verdict parity vs full enumeration', () {
    test('random packings agree with enumeration', () async {
      final rng = Random(20240531);
      var satSeen = 0;
      var unsatSeen = 0;
      var learned = 0;
      for (var t = 0; t < 120; t++) {
        final n = 3 + rng.nextInt(3); // 3..5
        final w = 3 + rng.nextInt(3); // 3..5
        final h = 3 + rng.nextInt(3);
        final ws = [for (var i = 0; i < n; i++) 1 + rng.nextInt(w)];
        final hs = [for (var i = 0; i < n; i++) 1 + rng.nextInt(h)];

        final all = await _pack(n, w, h, ws, hs).getAllSolutions();
        final sat = all.isNotEmpty;
        final unique = all.length == 1;
        final canon =
            unique ? {for (final k in all.first.keys) k: all.first[k]} : null;
        if (sat) {
          satSeen++;
        } else {
          unsatSeen++;
        }

        for (var seed = 0; seed < 4; seed++) {
          final r = await _pack(n, w, h, ws, hs)
              .solveWithLcg(useVsids: true, seed: seed);
          if (CSP.lastStats!.learnedClauses > 0) learned++;
          if (sat) {
            expect(r, isA<Map<String, dynamic>>(),
                reason: 't=$t seed=$seed must stay SAT '
                    'n=$n w=$w h=$h ws=$ws hs=$hs');
            final m = r as Map<String, dynamic>;
            expect(_nonOverlapping(m, n, ws, hs), isTrue,
                reason: 't=$t seed=$seed overlapping layout');
            if (canon != null) {
              for (final k in canon.keys) {
                expect(m[k], canon[k],
                    reason: 't=$t seed=$seed unique cell $k mismatch');
              }
            }
          } else {
            expect(r, 'FAILURE',
                reason: 't=$t seed=$seed must stay UNSAT '
                    'n=$n w=$w h=$h ws=$ws hs=$hs');
          }
        }
      }
      expect(satSeen, greaterThan(0));
      expect(unsatSeen, greaterThan(0));
      expect(learned, greaterThan(0),
          reason: 'the sweep must exercise the M3f learning path');
    });
  });
}

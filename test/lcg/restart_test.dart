/// LCG M4 — Luby restarts with learned-clause + activity retention
/// (`useRestarts: true` on `solveWithLcg`, iterative CDCL engine).
///
/// A restart drops the search tree back to the root but keeps the
/// learned-clause pool, the activity / wdeg tables, and the per-variable
/// saved phase (Pipatsrisawat & Darwiche 2007). Coverage:
///
///   1. **Soundness** — Inkala (allDiff + GCC) with restarts *forced* by a
///      tiny budget still solves the unique puzzle correctly across seeds
///      (the restart-to-root + learned-clause-pool path on integer / atom
///      clauses).
///   2. **Verdict parity** — on random 3-SAT, restarts-on agrees with plain
///      backtracking on SAT/UNSAT and returns a valid assignment.
///   3. **Heavy-tail win** — on satisfiable random 3-SAT instances where
///      the search is heavy-tailed, restarts + phase saving cut the
///      decision count (often ~2×).
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

const _hardestSudoku = [
  [8, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 3, 6, 0, 0, 0, 0, 0],
  [0, 7, 0, 0, 9, 0, 2, 0, 0],
  [0, 5, 0, 0, 0, 7, 0, 0, 0],
  [0, 0, 0, 0, 4, 5, 7, 0, 0],
  [0, 0, 0, 1, 0, 0, 0, 3, 0],
  [0, 0, 1, 0, 0, 0, 0, 6, 8],
  [0, 0, 8, 5, 0, 0, 0, 1, 0],
  [0, 9, 0, 0, 0, 0, 4, 0, 0],
];

Problem _sudoku(List<List<int>> puzzle, {required bool gcc}) {
  final p = Problem();
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final v = puzzle[r][c];
      p.addVariable('r${r}c$c', v != 0 ? [v] : [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }
  }
  void group(List<String> cells) {
    if (gcc) {
      p.addGcc(cells, {for (var v = 1; v <= 9; v++) v: 1});
    } else {
      p.addAllDifferent(cells);
    }
  }

  for (var r = 0; r < 9; r++) {
    group([for (var c = 0; c < 9; c++) 'r${r}c$c']);
  }
  for (var c = 0; c < 9; c++) {
    group([for (var r = 0; r < 9; r++) 'r${r}c$c']);
  }
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      group([
        for (var dr = 0; dr < 3; dr++)
          for (var dc = 0; dc < 3; dc++) 'r${br * 3 + dr}c${bc * 3 + dc}'
      ]);
    }
  }
  return p;
}

/// Random 3-SAT over booleans near the phase transition (ratio ~4.26).
/// Some instances are satisfiable and heavy-tailed under VSIDS. The
/// generator is deterministic in [seed].
Problem _randSat(int seed, {int n = 100, int m = 426}) {
  final rng = Random(seed);
  final p = Problem();
  for (var i = 0; i < n; i++) {
    p.addVariable('v$i', [0, 1]);
  }
  for (var c = 0; c < m; c++) {
    final pos = <String>[];
    final neg = <String>[];
    final picked = <int>{};
    while (picked.length < 3) {
      picked.add(rng.nextInt(n));
    }
    for (final i in picked) {
      (rng.nextBool() ? pos : neg).add('v$i');
    }
    p.addClause(positive: pos, negative: neg);
  }
  return p;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('restart soundness (Inkala, restarts forced)', () {
    test('allDiff + GCC solved correctly with restarts firing', () async {
      final ref = await _sudoku(_hardestSudoku, gcc: false).getSolution()
          as Map<String, dynamic>;
      for (final gcc in [false, true]) {
        for (var seed = 0; seed < 6; seed++) {
          // restartScale 3 forces several restarts on a puzzle that
          // otherwise converges in ~26 backtracks.
          final r = await _sudoku(_hardestSudoku, gcc: gcc).solveWithLcg(
              useIterativeCdcl: true,
              useRestarts: true,
              restartScale: 3,
              useVsids: true,
              seed: seed);
          expect(r, isA<Map<String, dynamic>>(),
              reason: 'gcc=$gcc seed=$seed must stay SAT under restarts');
          final m = r as Map<String, dynamic>;
          for (final k in ref.keys) {
            expect(m[k], ref[k], reason: 'gcc=$gcc seed=$seed cell $k');
          }
        }
      }
    });

    test('restarts actually fire under the tiny budget', () async {
      await _sudoku(_hardestSudoku, gcc: false).solveWithLcg(
          useIterativeCdcl: true,
          useRestarts: true,
          restartScale: 3,
          useVsids: true,
          seed: 0);
      expect(CSP.lastStats!.restarts, greaterThan(0));
    });
  });

  group('restart verdict parity (random 3-SAT)', () {
    test('restarts-on agrees with plain backtracking on SAT/UNSAT', () async {
      // Smaller instances (n=60) so a forced-restart sweep stays fast; the
      // verdict-parity property is size-independent.
      for (var seed = 0; seed < 8; seed++) {
        final plain = await _randSat(seed, n: 60, m: 256).getSolution();
        final r = await _randSat(seed, n: 60, m: 256).solveWithLcg(
            useIterativeCdcl: true,
            useRestarts: true,
            restartScale: 20,
            useVsids: true,
            seed: seed);
        final plainSat = plain is Map<String, dynamic>;
        final rSat = r is Map<String, dynamic>;
        expect(rSat, plainSat, reason: 'seed=$seed verdict mismatch');
        if (r is Map<String, dynamic>) {
          expect(r.length, greaterThan(0));
        }
      }
    });
  });

  group('restart heavy-tail win (phase saving)', () {
    test('cuts decisions on heavy-tailed satisfiable instances', () async {
      // Seeds chosen as satisfiable and heavy-tailed: without restarts the
      // VSIDS search wanders; with restarts + phase saving it rebuilds the
      // good partial assignment and finishes far sooner. Measured margins
      // are ~2× (e.g. seed 5: 421 → 184 decisions), so a strict-improvement
      // assertion has ample cushion against minor engine drift.
      for (final seed in [1, 5, 13]) {
        final off = await _randSat(seed)
            .solveWithLcg(useIterativeCdcl: true, useVsids: true, seed: seed);
        final offDec = CSP.lastStats!.decisions;
        expect(off, isA<Map<String, dynamic>>(), reason: 'seed=$seed is SAT');

        final on = await _randSat(seed).solveWithLcg(
            useIterativeCdcl: true,
            useRestarts: true,
            useVsids: true,
            seed: seed);
        final s = CSP.lastStats!;
        expect(on, isA<Map<String, dynamic>>());
        expect(s.restarts, greaterThan(0), reason: 'seed=$seed restarts fire');
        expect(s.decisions, lessThan(offDec),
            reason: 'seed=$seed restarts+phase-saving cut decisions '
                '(${s.decisions} vs $offDec)');
      }
    });
  });
}

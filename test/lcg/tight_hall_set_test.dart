/// LCG tight-Hall-set tests: the alternating-path Régin / Quimper-Walsh
/// explanation for `_AllDifferentPropagator` and the capacity-aware
/// saturated-cut explanation for `_GccPropagator` (Régin 1996).
///
/// These replace the earlier conservative tightness *bails* (the
/// value-SCC-members entry-domain-union check for allDifferent; the
/// fully-assignment-covered-only case for GCC) with sound explanations
/// built by closing forward reachability in the residual digraph. Two
/// things are asserted:
///
///   1. **Recovery** — the tighter explanations learn strictly more
///      sound clauses than the bailing versions did (Inkala's hardest
///      sudoku rises from ~8 to ~25 learned clauses; the GCC encoding,
///      which previously bailed *every* Hall-set prune, now matches the
///      allDifferent encoding exactly).
///
///   2. **Soundness** — across many randomized VSIDS decision orders the
///      unique-solution puzzles are always solved correctly, and over
///      randomly generated multi-copy GCC instances `solveWithLcg`'s
///      SAT/UNSAT verdict and returned assignment always agree with full
///      enumeration. An unsound learned clause would forbid a real
///      solution (FAILURE-on-SAT or a wrong/partial assignment), so these
///      sweeps are the same known-solution methodology that root-caused
///      the earlier soundness bugs (see `LCG_PLAN.md` §M4).
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Arto Inkala's "World's Hardest Sudoku" (2010) — surfaces enough
/// allDifferent / GCC conflicts to exercise the tight Hall-set learning.
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

/// Build the 9×9 sudoku as nine + nine + nine all-distinct groups,
/// modelled either with `addAllDifferent` or with an exact-counts
/// `addGcc` (each digit exactly once — the degenerate GCC ≡ allDifferent).
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

bool _validSudoku(Map<String, dynamic> m) {
  bool perm(List<int> xs) =>
      xs.length == 9 &&
      xs.toSet().length == 9 &&
      xs.every((v) => v >= 1 && v <= 9);
  for (var r = 0; r < 9; r++) {
    if (!perm([for (var c = 0; c < 9; c++) m['r${r}c$c'] as int])) return false;
  }
  for (var c = 0; c < 9; c++) {
    if (!perm([for (var r = 0; r < 9; r++) m['r${r}c$c'] as int])) return false;
  }
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      if (!perm([
        for (var dr = 0; dr < 3; dr++)
          for (var dc = 0; dc < 3; dc++)
            m['r${br * 3 + dr}c${bc * 3 + dc}'] as int
      ])) {
        return false;
      }
    }
  }
  return true;
}

void main() {
  group('tight allDifferent — recovery', () {
    test('Inkala learns substantially more than the bailing version', () async {
      final r = await _sudoku(_hardestSudoku, gcc: false).solveWithLcg();
      expect(r, isA<Map<String, dynamic>>());
      expect(_validSudoku(r as Map<String, dynamic>), isTrue);
      // The conservative value-SCC-members tightness check learned ~8
      // clauses here; the reach-closure Hall set recovers the
      // free-vertex-slack prunes and learns markedly more.
      expect(CSP.lastStats!.learnedClauses, greaterThanOrEqualTo(20),
          reason: 'tight Hall set must recover the bailed prunes');
    });
  });

  group('tight GCC — recovery parity with allDifferent', () {
    test('exact-counts GCC learns as much as the allDifferent encoding',
        () async {
      await _sudoku(_hardestSudoku, gcc: false).solveWithLcg();
      final allDiffLearned = CSP.lastStats!.learnedClauses;

      final r = await _sudoku(_hardestSudoku, gcc: true).solveWithLcg();
      final gccLearned = CSP.lastStats!.learnedClauses;
      expect(r, isA<Map<String, dynamic>>());
      expect(_validSudoku(r as Map<String, dynamic>), isTrue);
      // GCC previously bailed *every* Hall-set prune (only the
      // fully-pinned assignment case learned). The capacity-aware cut at
      // upper == 1 reduces to the allDifferent reach, so the two encodings
      // now learn identically on this degenerate instance.
      expect(gccLearned, equals(allDiffLearned),
          reason: 'count-1 GCC cut == allDifferent reach Hall set');
      expect(gccLearned, greaterThanOrEqualTo(20));
    });
  });

  group('soundness — randomized VSIDS decision orders', () {
    test('Inkala (allDiff + GCC) solves correctly under 40 seeds', () async {
      final ref = await _sudoku(_hardestSudoku, gcc: false).getSolution()
          as Map<String, dynamic>;
      for (final useGcc in [false, true]) {
        for (var seed = 0; seed < 40; seed++) {
          final r = await _sudoku(_hardestSudoku, gcc: useGcc)
              .solveWithLcg(useVsids: true, seed: seed);
          expect(r, isA<Map<String, dynamic>>(),
              reason: 'gcc=$useGcc seed=$seed must stay SAT');
          final m = r as Map<String, dynamic>;
          expect(_validSudoku(m), isTrue, reason: 'gcc=$useGcc seed=$seed');
          // The puzzle has a unique solution: an unsound clause would
          // either exclude it (handled above) or yield a different
          // (still-valid?) assignment — guard exact equality too.
          for (final k in ref.keys) {
            expect(m[k], ref[k], reason: 'gcc=$useGcc seed=$seed cell $k');
          }
        }
      }
    });
  });

  group('soundness — multi-copy GCC vs full enumeration', () {
    test('random capacity (upper > 1) instances agree with enumeration',
        () async {
      final rng = Random(20240529);
      var instances = 0;
      var withMultiplicity = 0;
      for (var t = 0; t < 120; t++) {
        final nVals = 3 + rng.nextInt(2); // 3..4 values
        final nVars = nVals + rng.nextInt(3); // a few more vars than values
        // Random exact counts summing to nVars (forces tight packing, so
        // the capacity cut fires); track whether any count exceeds 1.
        final counts = <int, int>{};
        var remaining = nVars;
        var multi = false;
        for (var v = 1; v <= nVals; v++) {
          final slotsLeft = nVals - v;
          final c = v == nVals
              ? remaining
              : (remaining > slotsLeft
                  ? rng.nextInt(remaining - slotsLeft + 1)
                  : 0);
          counts[v] = c;
          if (c > 1) multi = true;
          remaining -= c;
        }
        if (multi) withMultiplicity++;
        // A scattering of pins to create real search.
        final pins = <int?>[
          for (var i = 0; i < nVars; i++)
            if (rng.nextInt(3) == 0) 1 + rng.nextInt(nVals) else null
        ];

        Problem build() {
          final p = Problem();
          final vars = [for (var i = 0; i < nVars; i++) 'x$i'];
          for (var i = 0; i < nVars; i++) {
            final pin = pins[i];
            p.addVariable(vars[i],
                pin != null ? [pin] : [for (var v = 1; v <= nVals; v++) v]);
          }
          p.addGcc(vars, counts);
          return p;
        }

        final all = await build().getAllSolutions();
        final keys = all
            .map((m) => [for (var i = 0; i < nVars; i++) m['x$i']].join(','))
            .toSet();
        final sat = all.isNotEmpty;
        for (var seed = 0; seed < 3; seed++) {
          instances++;
          final r = await build().solveWithLcg(useVsids: true, seed: seed);
          if (sat) {
            expect(r, isA<Map<String, dynamic>>(),
                reason: 't=$t seed=$seed counts=$counts pins=$pins');
            final m = r as Map<String, dynamic>;
            final key = [for (var i = 0; i < nVars; i++) m['x$i']].join(',');
            expect(keys.contains(key), isTrue,
                reason: 'returned non-solution t=$t seed=$seed key=$key');
          } else {
            expect(r, 'FAILURE',
                reason: 'unsat instance must stay unsat t=$t seed=$seed');
          }
        }
      }
      // Sanity: the generator actually produced capacity (upper > 1) cases.
      expect(withMultiplicity, greaterThan(0));
      expect(instances, greaterThan(0));
    });
  });
}

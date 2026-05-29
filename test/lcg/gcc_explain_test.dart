/// LCG M3c tests: `_GccPropagator` network-flow explanation companion.
///
/// The global cardinality constraint generalises allDifferent with
/// per-value multiplicity. M3c gives it the same M3-tighten treatment
/// as M3a + the `AtomInScc` bridge: each pruned value's "why" collapses
/// into a single synthetic bridge atom (assignment → `AtomEq(owner, v)`;
/// Hall set → entry-snapshot absences) so the first-UIP analyser
/// converges and learns clauses on GCC-shaped conflicts.
///
/// A GCC with every value required exactly once is equivalent to
/// allDifferent, so these tests reuse that structure (sudoku) to get a
/// backtrack-heavy instance whose conflicts the GCC propagator detects.
/// The acceptance criterion mirrors M3a: correctness + activation
/// (learnedClauses > 0 on a backtrack-heavy instance, LCG solution
/// matches plain, easy instances unaffected).
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Arto Inkala's "World's Hardest Sudoku" (2010) — enough GCC conflicts
/// under search to exercise M3c learning.
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

/// Sudoku where each row / column / box is an exact-count GCC (every
/// digit 1..9 required exactly once) — semantically allDifferent, but
/// dispatched to `_GccPropagator` so it drives the M3c path.
Problem _gccSudoku(List<List<int>> puzzle) {
  final p = Problem();
  final counts = {for (var d = 1; d <= 9; d++) d: 1};
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final v = puzzle[r][c];
      p.addVariable('r${r}c$c', v != 0 ? [v] : [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }
  }
  for (var r = 0; r < 9; r++) {
    p.addGcc([for (var c = 0; c < 9; c++) 'r${r}c$c'], counts);
  }
  for (var c = 0; c < 9; c++) {
    p.addGcc([for (var r = 0; r < 9; r++) 'r${r}c$c'], counts);
  }
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      final cells = [
        for (var dr = 0; dr < 3; dr++)
          for (var dc = 0; dc < 3; dc++) 'r${br * 3 + dr}c${bc * 3 + dc}',
      ];
      p.addGcc(cells, counts);
    }
  }
  return p;
}

void main() {
  group('GccFlowReason', () {
    test('passes its antecedent atoms through unchanged', () {
      const atoms = [AtomEq('a', 1), AtomInScc('h', 7)];
      const r = GccFlowReason(atoms);
      expect(r.antecedents(), atoms);
      expect(r.toString(), contains('a = 1'));
    });

    test('empty reason has no antecedents', () {
      expect(const GccFlowReason([]).antecedents(), isEmpty);
    });
  });

  group('M3c end-to-end — GCC sudoku (exact counts ≡ allDifferent)', () {
    test('LCG solution matches plain on the medium-difficulty path', () async {
      // A GCC instance solvable at the root: still must return the
      // correct solution under LCG.
      final viaPlain = await _gccSudoku(_hardestSudoku).getSolution();
      final plainStats = CSP.lastStats!;
      final viaLcg = await _gccSudoku(_hardestSudoku).solveWithLcg();
      expect(viaPlain, isA<Map<String, dynamic>>());
      expect(viaLcg, isA<Map<String, dynamic>>());
      expect(viaLcg, viaPlain, reason: 'LCG must find the same solution');
      // LCG must not do *more* search than plain backtracking.
      expect(
          CSP.lastStats!.backtracks, lessThanOrEqualTo(plainStats.backtracks),
          reason: 'learning must not regress the search on this instance');
    });

    test('LCG fires on the hardest sudoku — learnedClauses > 0', () async {
      final p = _gccSudoku(_hardestSudoku);
      final result = await p.solveWithLcg();
      final stats = CSP.lastStats!;
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect(m['r0c0'], 8); // pre-filled
      for (var r = 0; r < 9; r++) {
        final row = [for (var c = 0; c < 9; c++) m['r${r}c$c']];
        expect(row.toSet().length, 9, reason: 'row $r must be a permutation');
      }
      expect(stats.learnedClauses, greaterThan(0),
          reason: 'GCC-driven conflicts must now surface learned clauses '
              'via the M3c AtomInScc bridge');
      expect(stats.backjumps, greaterThan(0),
          reason: 'learning should drive at least one non-chronological '
              'backjump');
    });
  });

  group('M3c regression — non-GCC flow paths unaffected', () {
    test('pure-CNF pigeonhole-7-in-6 still cuts ≥ 5× under the M2b path',
        () async {
      Problem build() {
        final p = Problem();
        for (var pg = 0; pg < 7; pg++) {
          for (var h = 0; h < 6; h++) {
            p.addVariable('p${pg}_h$h', [0, 1]);
          }
          p.addClause(positive: [for (var h = 0; h < 6; h++) 'p${pg}_h$h']);
        }
        for (var h = 0; h < 6; h++) {
          for (var i = 0; i < 7; i++) {
            for (var j = i + 1; j < 7; j++) {
              p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
            }
          }
        }
        return p;
      }

      await build().getSolution();
      final plainDecisions = CSP.lastStats!.decisions;
      await build().solveWithLcg();
      final lcgStats = CSP.lastStats!;
      expect(lcgStats.learnedClauses, greaterThan(0));
      expect(lcgStats.decisions * 5, lessThan(plainDecisions));
    });
  });
}

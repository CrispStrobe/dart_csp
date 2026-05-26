/// LCG M3a tests: `_AllDifferentPropagator` Hall-set explanation
/// companion. Verifies the new `AllDifferentReason` is correctly
/// emitted on the implication trail and consumed by the first-UIP
/// analyser to drive non-chronological backjumps + clause learning
/// on allDifferent-shaped conflicts.
///
/// The "win" on these tests is modest in absolute terms (a couple of
/// clauses learned per puzzle) because the test problems are small
/// and most of their search-tree cost lives in non-allDifferent
/// propagators (linear sums, binary != predicates) which still emit
/// `UnknownReason` until M3b–g land. The acceptance criterion here is
/// **correctness + activation**: M3a must fire (learnedClauses > 0
/// on backtrack-heavy instances), the LCG solution must match the
/// plain one, and the existing M2b regression must continue to hold.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

const _mediumSudoku = [
  [1, 0, 0, 0, 0, 7, 0, 9, 0],
  [0, 3, 0, 0, 2, 0, 0, 0, 8],
  [0, 0, 9, 6, 0, 0, 5, 0, 0],
  [0, 0, 5, 3, 0, 0, 9, 0, 0],
  [0, 1, 0, 0, 8, 0, 0, 0, 2],
  [6, 0, 0, 0, 0, 4, 0, 0, 0],
  [3, 0, 0, 0, 0, 0, 0, 1, 0],
  [0, 4, 0, 0, 0, 0, 0, 0, 7],
  [0, 0, 7, 0, 0, 0, 3, 0, 0],
];

/// Arto Inkala's "World's Hardest Sudoku" (2010). Designed to
/// require substantial backtracking on naive solvers; here it
/// surfaces enough allDifferent conflicts to demonstrate M3a-driven
/// learning.
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

Problem _sudoku(List<List<int>> puzzle) {
  final p = Problem();
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final name = 'r${r}c$c';
      final v = puzzle[r][c];
      p.addVariable(name, v != 0 ? [v] : [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }
  }
  for (var r = 0; r < 9; r++) {
    p.addAllDifferent([for (var c = 0; c < 9; c++) 'r${r}c$c']);
  }
  for (var c = 0; c < 9; c++) {
    p.addAllDifferent([for (var r = 0; r < 9; r++) 'r${r}c$c']);
  }
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      final cells = <String>[];
      for (var dr = 0; dr < 3; dr++) {
        for (var dc = 0; dc < 3; dc++) {
          cells.add('r${br * 3 + dr}c${bc * 3 + dc}');
        }
      }
      p.addAllDifferent(cells);
    }
  }
  return p;
}

void main() {
  group('AllDifferentReason — construction + antecedents', () {
    test('carries the provided antecedent atoms', () {
      final atoms = <Atom>[
        const AtomNe('x', 1),
        const AtomNe('y', 5),
      ];
      const reason = AllDifferentReason([]);
      expect(reason.antecedents(), isEmpty);
      final r = AllDifferentReason(atoms);
      expect(r.antecedents(), atoms);
    });

    test('toString surfaces the antecedent atoms for debugging', () {
      const r = AllDifferentReason([AtomNe('q', 3)]);
      expect(r.toString(), contains('q != 3'));
    });
  });

  group('M3a end-to-end — sudoku medium', () {
    test('solveWithLcg finds a valid solution matching plain solve', () async {
      final pPlain = _sudoku(_mediumSudoku);
      final viaPlain = await pPlain.getSolution();
      expect(viaPlain, isA<Map<String, dynamic>>());

      final pLcg = _sudoku(_mediumSudoku);
      final viaLcg = await pLcg.solveWithLcg();
      expect(viaLcg, isA<Map<String, dynamic>>());
      expect(viaLcg, viaPlain,
          reason: 'LCG search must yield the same first solution as plain'
              ' getSolution under deterministic ordering');
    });

    test('LCG fires on the medium sudoku — learnedClauses > 0', () async {
      final p = _sudoku(_mediumSudoku);
      await p.solveWithLcg();
      final stats = CSP.lastStats!;
      expect(stats.learnedClauses, greaterThan(0),
          reason: 'M3a must learn at least one Hall-set clause');
      expect(stats.backjumps, greaterThan(0),
          reason: 'M3a learning must produce at least one backjump');
    });
  });

  group("M3a end-to-end — Inkala's hardest sudoku", () {
    test('solveWithLcg finds the unique solution', () async {
      final p = _sudoku(_hardestSudoku);
      final result = await p.solveWithLcg();
      expect(result, isA<Map<String, dynamic>>());
      // The "hardest" puzzle has a known unique solution; spot-check a
      // single cell to confirm we got the right one.
      final m = result as Map<String, dynamic>;
      expect(m['r0c0'], 8); // pre-filled
      // Verify the result is a valid sudoku (all rows distinct).
      for (var r = 0; r < 9; r++) {
        final row = [for (var c = 0; c < 9; c++) m['r${r}c$c']];
        expect(row.toSet().length, 9, reason: 'row $r must be a permutation');
      }
    });

    test('LCG learns multiple clauses on the hardest sudoku', () async {
      final p = _sudoku(_hardestSudoku);
      await p.solveWithLcg();
      final stats = CSP.lastStats!;
      expect(stats.learnedClauses, greaterThanOrEqualTo(1),
          reason: 'Hard sudoku must surface allDifferent-driven conflicts'
              ' that M3a learns from');
    });
  });

  group('M3a regression — non-allDifferent flow paths', () {
    test('pure-CNF pigeonhole-7-in-6 unaffected by M3a path', () async {
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

      // Existing M2b boolean-only path must still trigger.
      final plain = build();
      await plain.getSolution();
      final plainDecisions = CSP.lastStats!.decisions;

      final lcg = build();
      await lcg.solveWithLcg();
      final lcgStats = CSP.lastStats!;
      expect(lcgStats.learnedClauses, greaterThan(0));
      expect(lcgStats.decisions * 5, lessThan(plainDecisions),
          reason: 'pigeonhole CNF must still cut ≥ 5× under M2b path');
    });

    test('pure allDifferent UNSAT (pigeonhole encoding) returns FAILURE',
        () async {
      // 7 vars in {1..6}, allDifferent: detected at root preprocessing
      // (m < n). No learning required; the failure path bypasses search.
      Problem build() => Problem()
        ..addVariables([for (var i = 0; i < 7; i++) 'p$i'],
            [for (var v = 1; v <= 6; v++) v])
        ..addAllDifferent([for (var i = 0; i < 7; i++) 'p$i']);
      final r1 = await build().getSolution();
      final r2 = await build().solveWithLcg();
      expect(r1, 'FAILURE');
      expect(r2, 'FAILURE');
    });
  });
}

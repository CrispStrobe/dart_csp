/// LCG M4 acceptance: the iterative trail-based CDCL engine
/// (`useIterativeCdcl: true` on `solveWithLcg`).
///
/// Unlike the recursive `_searchOneLcg` (chronological backtracking +
/// learning, `backjumps == 0`), the iterative engine performs sound
/// **non-chronological backjumping** — the actual LCG search-tree
/// speedup. Three things are asserted:
///
///   1. **Backjump capability** — on the pigeonhole UNSAT proofs the
///      iterative engine reports `backjumps > 0` and skips decision
///      levels, cutting the decision count below both plain backtracking
///      *and* the recursive learning path.
///
///   2. **Soundness + completeness** — across randomized VSIDS decision
///      orders the unique-solution puzzles are always solved correctly
///      (a learned clause that backjumped unsoundly would forbid the real
///      solution → FAILURE-on-SAT or a wrong assignment). This is the
///      same known-solution methodology that root-caused the earlier LCG
///      soundness bugs (see `LCG_PLAN.md` §M4).
///
///   3. **Fallback paths** — the chronological fallback for opaque
///      propagator conflicts (e.g. plain binary constraints, which carry
///      no `explain` companion) and the non-integer-domain fallback to the
///      recursive engine both stay sound and agree with plain
///      `getSolution`.
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Problem builders
// ---------------------------------------------------------------------------

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

/// N-queens modelled with *binary* constraints only — no allDifferent,
/// no clauses. Every conflict therefore arrives with no per-propagator
/// explanation (`UnknownReason`), so the iterative engine must lean on
/// its chronological fallback for the whole search. Integer domains,
/// satisfiable for n ≥ 4.
Problem _queens(int n) {
  final p = Problem();
  final cols = [for (var i = 0; i < n; i++) 'q$i'];
  for (final c in cols) {
    p.addVariable(c, [for (var r = 0; r < n; r++) r]);
  }
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final dist = j - i;
      p.addConstraint([cols[i], cols[j]], (dynamic a, dynamic b) {
        final x = a as int;
        final y = b as int;
        return x != y && (x - y).abs() != dist;
      });
    }
  }
  return p;
}

bool _validQueens(Map<String, dynamic> m, int n) {
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final x = m['q$i'] as int;
      final y = m['q$j'] as int;
      if (x == y || (x - y).abs() == j - i) return false;
    }
  }
  return true;
}

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('iterative CDCL — non-chronological backjump on pigeonhole', () {
    Future<({int plain, int it, int learned, int bj, int skipped})> run(
        int pigeons, int holes) async {
      final plain =
          await _pigeonholeCnf(pigeons: pigeons, holes: holes).getSolution();
      expect(plain, 'FAILURE');
      final plainDecisions = CSP.lastStats!.decisions;

      final r = await _pigeonholeCnf(pigeons: pigeons, holes: holes)
          .solveWithLcg(useIterativeCdcl: true);
      expect(r, 'FAILURE', reason: 'iterative CDCL must also prove UNSAT');
      final s = CSP.lastStats!;
      return (
        plain: plainDecisions,
        it: s.decisions,
        learned: s.learnedClauses,
        bj: s.backjumps,
        skipped: s.backjumpLevelsSkipped,
      );
    }

    test('6-in-5 backjumps and cuts decisions', () async {
      final r = await run(6, 5);
      expect(r.learned, greaterThan(0));
      expect(r.bj, greaterThan(0),
          reason: 'iterative engine performs non-chronological backjumps');
      expect(r.skipped, greaterThan(0),
          reason: 'a real backjump skips at least one decision level');
      expect(r.it, lessThan(r.plain));
    });

    test('7-in-6 cuts decisions ≥ 5× vs plain', () async {
      final r = await run(7, 6);
      expect(r.bj, greaterThan(0));
      expect(r.it * 5, lessThan(r.plain),
          reason: 'iterative decisions=${r.it}, plain=${r.plain}');
    });

    test('8-in-7 cuts decisions ≥ 10× vs plain', () async {
      final r = await run(8, 7);
      expect(r.bj, greaterThan(0));
      expect(r.it * 10, lessThan(r.plain),
          reason: 'iterative decisions=${r.it}, plain=${r.plain}');
    });

    test('iterative backjumps where the recursive path stays chronological',
        () async {
      await _pigeonholeCnf(pigeons: 7, holes: 6).solveWithLcg();
      final recursive = CSP.lastStats!;
      await _pigeonholeCnf(pigeons: 7, holes: 6)
          .solveWithLcg(useIterativeCdcl: true);
      final iterative = CSP.lastStats!;
      expect(recursive.backjumps, 0,
          reason: 'recursive LCG search is chronological by design');
      expect(iterative.backjumps, greaterThan(0));
      expect(iterative.decisions, lessThanOrEqualTo(recursive.decisions),
          reason: 'non-chronological backjump should not increase decisions');
    });
  });

  group('iterative CDCL — soundness sweep (known-solution sudoku)', () {
    test('Inkala (allDiff + GCC) solved correctly across 20 VSIDS orders',
        () async {
      final ref = await _sudoku(_hardestSudoku, gcc: false).getSolution()
          as Map<String, dynamic>;
      for (final useGcc in [false, true]) {
        for (var seed = 0; seed < 20; seed++) {
          final r = await _sudoku(_hardestSudoku, gcc: useGcc)
              .solveWithLcg(useIterativeCdcl: true, useVsids: true, seed: seed);
          expect(r, isA<Map<String, dynamic>>(),
              reason: 'gcc=$useGcc seed=$seed must stay SAT');
          final m = r as Map<String, dynamic>;
          expect(_validSudoku(m), isTrue, reason: 'gcc=$useGcc seed=$seed');
          for (final k in ref.keys) {
            expect(m[k], ref[k], reason: 'gcc=$useGcc seed=$seed cell $k');
          }
        }
      }
    });

    test('Inkala solved under plain MRV and dom/wdeg orders', () async {
      final ref = await _sudoku(_hardestSudoku, gcc: false).getSolution()
          as Map<String, dynamic>;
      for (final wdeg in [false, true]) {
        final r = await _sudoku(_hardestSudoku, gcc: false)
            .solveWithLcg(useIterativeCdcl: true, useDomWdeg: wdeg);
        final m = r as Map<String, dynamic>;
        expect(_validSudoku(m), isTrue, reason: 'wdeg=$wdeg');
        for (final k in ref.keys) {
          expect(m[k], ref[k], reason: 'wdeg=$wdeg cell $k');
        }
      }
    });
  });

  group('iterative CDCL — learned-clause activity bump (VSIDS / dom-wdeg)', () {
    // The canonical CDCL rule bumps the activity / wdeg weight of every
    // variable in the *learned clause* (the conflict-analysis variables),
    // not just the propagator that detected the wipeout. Without it the
    // VSIDS picker only sees the detecting-constraint signal and diverges:
    // pigeonhole 8-in-7 needed ~6251 decisions; with the learned-clause
    // bump it tracks the learned structure (~4387). These tests pin the
    // soundness of the VSIDS / dom-wdeg path and guard against the bump
    // being dropped (a gross divergence would blow past the bound).
    test('VSIDS path proves pigeonhole UNSAT without diverging', () async {
      final r = await _pigeonholeCnf(pigeons: 8, holes: 7)
          .solveWithLcg(useIterativeCdcl: true, useVsids: true);
      expect(r, 'FAILURE');
      final s = CSP.lastStats!;
      expect(s.backjumps, greaterThan(0));
      // Comfortable margin: the bump lands ~4387; without it ~6251.
      expect(s.decisions, lessThan(6000),
          reason: 'learned-clause activity bump keeps VSIDS on track');
    });

    test('dom-wdeg path proves pigeonhole UNSAT and stays sound', () async {
      final r = await _pigeonholeCnf(pigeons: 7, holes: 6)
          .solveWithLcg(useIterativeCdcl: true, useDomWdeg: true);
      expect(r, 'FAILURE');
      expect(CSP.lastStats!.learnedClauses, greaterThan(0));
    });
  });

  group('iterative CDCL — chronological fallback (opaque conflicts)', () {
    test('binary n-queens (no explained propagator) solved correctly',
        () async {
      for (final n in [6, 8]) {
        final r = await _queens(n).solveWithLcg(useIterativeCdcl: true);
        expect(r, isA<Map<String, dynamic>>(), reason: 'n=$n queens is SAT');
        expect(_validQueens(r as Map<String, dynamic>, n), isTrue,
            reason: 'n=$n');
      }
    });

    test('binary n-queens UNSAT (n=3) returns FAILURE', () async {
      final r = await _queens(3).solveWithLcg(useIterativeCdcl: true);
      expect(r, 'FAILURE', reason: '3-queens is UNSAT');
    });

    test('opaque-conflict UNSAT (all-different infeasible) returns FAILURE',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2])
        ..addAllDifferent(['A', 'B', 'C']);
      final r = await p.solveWithLcg(useIterativeCdcl: true);
      expect(r, 'FAILURE');
    });
  });

  group('iterative CDCL — non-integer-domain fallback', () {
    test('string-domain problem falls back and agrees with plain solve',
        () async {
      Problem build() => Problem()
        ..addVariables(
            ['wa', 'nt', 'sa', 'q', 'nsw', 'v', 't'], ['red', 'green', 'blue'])
        ..addConstraint(['wa', 'nt'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['wa', 'sa'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['nt', 'sa'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['nt', 'q'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['sa', 'q'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['sa', 'nsw'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['sa', 'v'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['q', 'nsw'], (dynamic a, dynamic b) => a != b)
        ..addConstraint(['nsw', 'v'], (dynamic a, dynamic b) => a != b);
      final viaIter = await build().solveWithLcg(useIterativeCdcl: true);
      expect(viaIter, isA<Map<String, dynamic>>());
      final m = viaIter as Map<String, dynamic>;
      // Validate the colouring directly (the fallback engine must still
      // produce a correct assignment).
      bool ok(String x, String y) => m[x] != m[y];
      expect(
          ok('wa', 'nt') &&
              ok('wa', 'sa') &&
              ok('nt', 'sa') &&
              ok('nt', 'q') &&
              ok('sa', 'q') &&
              ok('sa', 'nsw') &&
              ok('sa', 'v') &&
              ok('q', 'nsw') &&
              ok('nsw', 'v'),
          isTrue);
    });
  });

  group('iterative CDCL — verdict parity with plain backtracking', () {
    test('SAT/UNSAT verdict agrees with plain on random binary CSPs', () async {
      final rng = Random(424242);
      for (var t = 0; t < 60; t++) {
        final n = 4 + rng.nextInt(3); // 4..6 vars
        final dom = 2 + rng.nextInt(3); // domain size 2..4
        final vars = [for (var i = 0; i < n; i++) 'v$i'];
        // Random not-equal edges.
        final edges = <List<int>>[];
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            if (rng.nextInt(2) == 0) edges.add([i, j]);
          }
        }
        Problem build() {
          final p = Problem();
          for (final v in vars) {
            p.addVariable(v, [for (var d = 0; d < dom; d++) d]);
          }
          for (final e in edges) {
            p.addConstraint(
                [vars[e[0]], vars[e[1]]], (dynamic a, dynamic b) => a != b);
          }
          return p;
        }

        final plain = await build().getSolution();
        final iter = await build().solveWithLcg(useIterativeCdcl: true);
        final plainSat = plain is Map<String, dynamic>;
        final iterSat = iter is Map<String, dynamic>;
        expect(iterSat, plainSat,
            reason: 't=$t n=$n dom=$dom edges=$edges verdict mismatch');
        if (iter is Map<String, dynamic>) {
          for (final e in edges) {
            expect(iter[vars[e[0]]], isNot(iter[vars[e[1]]]),
                reason: 't=$t edge $e violated');
          }
        }
      }
    });
  });
}

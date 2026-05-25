/// Shared problem builders for `benchmark/benchmark.dart` and the
/// matching `test/cbj_benchmarks_test.dart` correctness suite. By
/// living in `benchmark/`, the build functions stay close to the
/// benchmark runner that uses them; tests import them via a relative
/// path so a divergence shows up as a build break rather than a
/// silent drift.
library;

import 'package:dart_csp/dart_csp.dart';

const sudokuPuzzle = [
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

Future<Problem> buildMagicSquareNoClue() async {
  const cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
  final p = Problem()
    ..addVariables(cells, [1, 2, 3, 4, 5, 6, 7, 8, 9])
    ..addAllDifferent(cells)
    ..addExactSum(['A1', 'A2', 'A3'], 15)
    ..addExactSum(['B1', 'B2', 'B3'], 15)
    ..addExactSum(['C1', 'C2', 'C3'], 15)
    ..addExactSum(['A1', 'B1', 'C1'], 15)
    ..addExactSum(['A2', 'B2', 'C2'], 15)
    ..addExactSum(['A3', 'B3', 'C3'], 15)
    ..addExactSum(['A1', 'B2', 'C3'], 15)
    ..addExactSum(['A3', 'B2', 'C1'], 15);
  return p;
}

Future<Problem> buildMagicSquarePinned() async {
  const cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
  final p = Problem()..addVariable('B2', [5]);
  for (final c in cells) {
    if (c != 'B2') p.addVariable(c, [1, 2, 3, 4, 6, 7, 8, 9]);
  }
  p
    ..addAllDifferent(cells)
    ..addExactSum(['A1', 'A2', 'A3'], 15)
    ..addExactSum(['B1', 'B2', 'B3'], 15)
    ..addExactSum(['C1', 'C2', 'C3'], 15)
    ..addExactSum(['A1', 'B1', 'C1'], 15)
    ..addExactSum(['A2', 'B2', 'C2'], 15)
    ..addExactSum(['A3', 'B3', 'C3'], 15)
    ..addExactSum(['A1', 'B2', 'C3'], 15)
    ..addExactSum(['A3', 'B2', 'C1'], 15);
  return p;
}

Future<Problem> buildSudoku() async {
  final p = Problem();
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final name = 'r${r}c$c';
      final v = sudokuPuzzle[r][c];
      if (v != 0) {
        p.addVariable(name, [v]);
      } else {
        p.addVariable(name, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      }
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

Future<Problem> buildNQueens(int n) async {
  final queens = [for (var i = 0; i < n; i++) 'Q$i'];
  final p = Problem()
    ..addVariables(queens, [for (var i = 1; i <= n; i++) i])
    ..addAllDifferent(queens);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final d = (j - i).abs();
      p.addConstraint(
        [queens[i], queens[j]],
        (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
      );
    }
  }
  return p;
}

Future<Problem> buildMapColoring() async {
  final p = Problem()
    ..addVariables(
        ['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T'], ['red', 'green', 'blue'])
    ..addStringConstraints([
      'WA != SA',
      'NT != SA',
      'Q != SA',
      'NSW != SA',
      'V != SA',
      'WA != NT',
      'NT != Q',
      'Q != NSW',
      'NSW != V',
    ]);
  return p;
}

Future<Problem> buildSendMoreMoneyPredicate() async {
  final letters = ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'];
  final p = Problem();
  for (final l in letters) {
    p.addVariable(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  }
  p
    ..addAllDifferent(letters)
    ..addStringConstraint('S != 0')
    ..addStringConstraint('M != 0');
  p.addConstraint(letters, (Map<String, dynamic> a) {
    final s = a['S'] as int;
    final e = a['E'] as int;
    final n = a['N'] as int;
    final d = a['D'] as int;
    final m = a['M'] as int;
    final o = a['O'] as int;
    final r = a['R'] as int;
    final y = a['Y'] as int;
    final send = s * 1000 + e * 100 + n * 10 + d;
    final more = m * 1000 + o * 100 + r * 10 + e;
    final money = m * 10000 + o * 1000 + n * 100 + e * 10 + y;
    return send + more == money;
  });
  return p;
}

/// Pigeonhole principle as a SAT-style CNF: `pigeons` pigeons into
/// `holes` holes via one boolean indicator per (pigeon, hole) pair.
///
///   * Per pigeon: one disjunction of `holes` positive literals
///     ("this pigeon occupies at least one hole").
///   * Per hole, per unordered pair of pigeons: one binary negative
///     clause ("not both of these two pigeons in the same hole").
///
/// Infeasible whenever `pigeons > holes`. Useful as a CNF/unit-
/// propagation benchmark because the per-pigeon clauses have width
/// `holes`, the per-hole at-most-one clauses are width-2, and the
/// search has to drive substantial decision/propagation to disprove
/// satisfiability — which is exactly the workload that the
/// watched-literal scheme plus the per-variable seeding filter
/// optimize.
Future<Problem> buildPigeonholeCnf(
    {required int pigeons, required int holes}) async {
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

Future<Problem> buildSendMoreMoneyLinear() async {
  final letters = ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'];
  final p = Problem();
  for (final l in letters) {
    p.addVariable(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  }
  p
    ..addAllDifferent(letters)
    ..addStringConstraint('S != 0')
    ..addStringConstraint('M != 0')
    ..addLinearEquals(
      letters,
      [1000, 91, -90, 1, -9000, -900, 10, -1],
      0,
    );
  return p;
}

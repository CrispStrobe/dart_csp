import 'package:test/test.dart';

import '../benchmark/problems.dart';

/// "Real tests for all" — runs every benchmark scenario in
/// `benchmark/benchmark.dart` through the public solver entry point
/// with `enableConflictBackjumping: true` and validates that the
/// returned assignment actually satisfies the problem. Complements
/// `test/cbj_test.dart` (which covers the wiring, enumeration
/// equivalence, edge cases, and engagement on a hand-crafted
/// instance) by exercising CBJ on the same nine classic problems the
/// performance benchmark measures. By importing the shared
/// `benchmark/problems.dart`, the tests are guaranteed to verify the
/// exact same problem definitions the benchmark times — any
/// divergence becomes a build break rather than silent drift.
void main() {
  group('CBJ on every benchmark problem returns a valid solution', () {
    test('magic-square 3x3 (no clue)', () async {
      final p = await buildMagicSquareNoClue();
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertMagicSquare(sol as Map<String, dynamic>);
    });

    test('magic-square 3x3 (B2=5 pinned)', () async {
      final p = await buildMagicSquarePinned();
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertMagicSquare(sol as Map<String, dynamic>);
      expect(sol['B2'], 5);
    });

    test('sudoku medium-hard', () async {
      final p = await buildSudoku();
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertSudoku(sol as Map<String, dynamic>);
    });

    test('8-queens', () async {
      final p = await buildNQueens(8);
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertNQueens(sol as Map<String, dynamic>, 8);
    });

    test('12-queens', () async {
      final p = await buildNQueens(12);
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertNQueens(sol as Map<String, dynamic>, 12);
    });

    test('16-queens', () async {
      final p = await buildNQueens(16);
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertNQueens(sol as Map<String, dynamic>, 16);
    });

    test('Australia map coloring (3 colors)', () async {
      final p = await buildMapColoring();
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertMapColoring(sol as Map<String, dynamic>);
    });

    test('SEND + MORE = MONEY (predicate)', () async {
      final p = await buildSendMoreMoneyPredicate();
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertSendMoreMoney(sol as Map<String, dynamic>);
    });

    test('SEND + MORE = MONEY (linear)', () async {
      final p = await buildSendMoreMoneyLinear();
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertSendMoreMoney(sol as Map<String, dynamic>);
    });
  });

  group(
      'CBJ matches plain backtracking on benchmark scenarios with '
      'a unique solution', () {
    test('SEND + MORE = MONEY (predicate) — both find the canonical', () async {
      final plain = await (await buildSendMoreMoneyPredicate()).getSolution();
      final cbj = await (await buildSendMoreMoneyPredicate())
          .getSolution(enableConflictBackjumping: true);
      expect(plain, isA<Map<String, dynamic>>());
      expect(cbj, isA<Map<String, dynamic>>());
      _assertSendMoreMoney(plain as Map<String, dynamic>);
      _assertSendMoreMoney(cbj as Map<String, dynamic>);
      expect(cbj, plain);
    });

    test('SEND + MORE = MONEY (linear) — both find the canonical', () async {
      final plain = await (await buildSendMoreMoneyLinear()).getSolution();
      final cbj = await (await buildSendMoreMoneyLinear())
          .getSolution(enableConflictBackjumping: true);
      expect(plain, isA<Map<String, dynamic>>());
      expect(cbj, isA<Map<String, dynamic>>());
      _assertSendMoreMoney(plain as Map<String, dynamic>);
      _assertSendMoreMoney(cbj as Map<String, dynamic>);
      expect(cbj, plain);
    });

    test('sudoku — both find the same (unique) solution', () async {
      final plain = await (await buildSudoku()).getSolution();
      final cbj = await (await buildSudoku())
          .getSolution(enableConflictBackjumping: true);
      expect(plain, isA<Map<String, dynamic>>());
      expect(cbj, isA<Map<String, dynamic>>());
      // Standard sudokus have a unique solution; both solvers should
      // converge on the same assignment.
      expect(cbj, plain);
    });
  });

  group('CBJ on benchmark scenarios — enumeration sanity checks', () {
    test('8-queens enumeration count matches plain (92 solutions)', () async {
      final plainSols = await (await buildNQueens(8)).getSolutions().toList();
      final cbjSols = await (await buildNQueens(8))
          .getSolutions(enableConflictBackjumping: true)
          .toList();
      expect(plainSols.length, 92,
          reason: '8-queens has 92 distinct solutions');
      expect(cbjSols.length, plainSols.length);
    });

    test('map-coloring enumeration count matches plain', () async {
      final plainSols =
          await (await buildMapColoring()).getSolutions().toList();
      final cbjSols = await (await buildMapColoring())
          .getSolutions(enableConflictBackjumping: true)
          .toList();
      expect(cbjSols.length, plainSols.length);
    });
  });
}

// -----------------------------------------------------------------------------
// Validators.
// -----------------------------------------------------------------------------

void _assertMagicSquare(Map<String, dynamic> sol) {
  const cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
  // All-different over 1..9.
  final vals = cells.map((c) => sol[c] as int).toList();
  expect(vals.toSet().length, 9);
  for (final v in vals) {
    expect(v, allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(9)));
  }
  // Three rows, three cols, two diagonals each sum to 15.
  const lines = [
    ['A1', 'A2', 'A3'],
    ['B1', 'B2', 'B3'],
    ['C1', 'C2', 'C3'],
    ['A1', 'B1', 'C1'],
    ['A2', 'B2', 'C2'],
    ['A3', 'B3', 'C3'],
    ['A1', 'B2', 'C3'],
    ['A3', 'B2', 'C1'],
  ];
  for (final line in lines) {
    final s = line.map((c) => sol[c] as int).reduce((a, b) => a + b);
    expect(s, 15, reason: '$line sums to $s, not 15');
  }
}

void _assertSudoku(Map<String, dynamic> sol) {
  // 81 cells, each in 1..9.
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final v = sol['r${r}c$c'] as int;
      expect(v, allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(9)));
      // If the puzzle pinned a value, the solution must match.
      final pinned = sudokuPuzzle[r][c];
      if (pinned != 0) expect(v, pinned);
    }
  }
  // Rows.
  for (var r = 0; r < 9; r++) {
    final row = [for (var c = 0; c < 9; c++) sol['r${r}c$c'] as int];
    expect(row.toSet().length, 9, reason: 'row $r is not all-different');
  }
  // Columns.
  for (var c = 0; c < 9; c++) {
    final col = [for (var r = 0; r < 9; r++) sol['r${r}c$c'] as int];
    expect(col.toSet().length, 9, reason: 'col $c is not all-different');
  }
  // 3x3 boxes.
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      final box = <int>[];
      for (var dr = 0; dr < 3; dr++) {
        for (var dc = 0; dc < 3; dc++) {
          box.add(sol['r${br * 3 + dr}c${bc * 3 + dc}'] as int);
        }
      }
      expect(box.toSet().length, 9,
          reason: 'box ($br,$bc) is not all-different');
    }
  }
}

void _assertNQueens(Map<String, dynamic> sol, int n) {
  // n queens, columns are 1..n, all-different on columns and on each
  // diagonal.
  for (var i = 0; i < n; i++) {
    final ci = sol['Q$i'] as int;
    expect(ci, allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(n)));
    for (var j = i + 1; j < n; j++) {
      final cj = sol['Q$j'] as int;
      expect(ci != cj, isTrue, reason: 'queens $i and $j share column $ci');
      expect((ci - cj).abs() != j - i, isTrue,
          reason: 'queens $i and $j on same diagonal: $ci, $cj');
    }
  }
}

void _assertMapColoring(Map<String, dynamic> sol) {
  const adjacency = [
    ['WA', 'SA'],
    ['NT', 'SA'],
    ['Q', 'SA'],
    ['NSW', 'SA'],
    ['V', 'SA'],
    ['WA', 'NT'],
    ['NT', 'Q'],
    ['Q', 'NSW'],
    ['NSW', 'V'],
  ];
  for (final pair in adjacency) {
    expect(sol[pair[0]], isNot(sol[pair[1]]),
        reason: '${pair[0]} and ${pair[1]} are both ${sol[pair[0]]}');
  }
  // Tasmania has no neighbors so it can be any colour; just verify it
  // got assigned something.
  expect(sol['T'], isNotNull);
  // All assignments are one of the three colours.
  for (final region in const ['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T']) {
    expect(['red', 'green', 'blue'].contains(sol[region]), isTrue);
  }
}

void _assertSendMoreMoney(Map<String, dynamic> sol) {
  final s = sol['S'] as int;
  final e = sol['E'] as int;
  final n = sol['N'] as int;
  final d = sol['D'] as int;
  final m = sol['M'] as int;
  final o = sol['O'] as int;
  final r = sol['R'] as int;
  final y = sol['Y'] as int;
  // All-different.
  expect({s, e, n, d, m, o, r, y}.length, 8);
  // Leading digits non-zero.
  expect(s, isNot(0));
  expect(m, isNot(0));
  // Each digit in 0..9.
  for (final v in [s, e, n, d, m, o, r, y]) {
    expect(v, allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(9)));
  }
  // The equation holds.
  final send = s * 1000 + e * 100 + n * 10 + d;
  final more = m * 1000 + o * 100 + r * 10 + e;
  final money = m * 10000 + o * 1000 + n * 100 + e * 10 + y;
  expect(send + more, money, reason: '$send + $more != $money');
  // The puzzle has a unique solution.
  expect(s, 9);
  expect(e, 5);
  expect(n, 6);
  expect(d, 7);
  expect(m, 1);
  expect(o, 0);
  expect(r, 8);
  expect(y, 2);
}

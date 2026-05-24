/// Performance regression benchmarks for dart_csp.
///
/// Run with:
///
///   dart run benchmark/benchmark.dart
///
/// Prints a row per benchmark with wall-clock time and the engine
/// stats from `Problem.lastStats`. CI runs this on push to main.
library;

import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  print('--- dart_csp benchmarks ---');
  print('');
  await _bench('magic-square 3x3 (no clue)', _magicSquareNoClue);
  await _bench('magic-square 3x3 (B2=5 pinned)', _magicSquarePinned);
  await _bench('sudoku medium-hard', _sudoku);
  await _bench('8-queens', () => _nQueens(8));
  await _bench('12-queens', () => _nQueens(12));
  await _bench('16-queens', () => _nQueens(16));
  await _bench('Australia map coloring (3 colors)', _mapColoring);
  await _bench('SEND + MORE = MONEY (predicate)', _sendMoreMoney);
  await _bench('SEND + MORE = MONEY (linear)', _sendMoreMoneyLinear);
  print('');
  print('--- done ---');
}

Future<void> _bench(String label, Future<Problem> Function() build) async {
  final p = await build();
  final stopwatch = Stopwatch()..start();
  final result = await p.getSolution();
  stopwatch.stop();
  final ok = result is Map<String, dynamic>;
  final stats = p.lastStats;
  print('${label.padRight(36)}  ${ok ? 'ok' : 'NO SOLUTION'}  '
      '${stopwatch.elapsedMilliseconds.toString().padLeft(6)} ms  '
      '${stats != null ? '(decisions: ${stats.decisions}, '
          'backtracks: ${stats.backtracks}, '
          'propagations: ${stats.propagations})' : ''}');
}

Future<Problem> _magicSquareNoClue() async {
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

Future<Problem> _magicSquarePinned() async {
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

Future<Problem> _sudoku() async {
  const puzzle = [
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
  final p = Problem();
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final name = 'r${r}c$c';
      final v = puzzle[r][c];
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

Future<Problem> _nQueens(int n) async {
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

Future<Problem> _mapColoring() async {
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

Future<Problem> _sendMoreMoney() async {
  // SEND + MORE = MONEY, classic cryptarithmetic. Each letter is a
  // distinct digit, leading letters non-zero.
  final letters = ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'];
  final p = Problem();
  for (final l in letters) {
    p.addVariable(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  }
  p
    ..addAllDifferent(letters)
    ..addStringConstraint('S != 0')
    ..addStringConstraint('M != 0');
  // SEND + MORE = MONEY
  //   S*1000 + E*100 + N*10 + D
  // + M*1000 + O*100 + R*10 + E
  // = M*10000 + O*1000 + N*100 + E*10 + Y
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

Future<Problem> _sendMoreMoneyLinear() async {
  // Same problem expressed with the bounds-consistency linear
  // propagator. The 8-var equation:
  //   1000S + 100E + 10N + D + 1000M + 100O + 10R + E
  //   = 10000M + 1000O + 100N + 10E + Y
  // becomes, after rearrangement:
  //   1000S + 91E - 90N + D - 9000M - 900O + 10R - Y = 0
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

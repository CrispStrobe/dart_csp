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

/// `blocks` independent (x_i, y_i, z_i) triples over `{1..d}` with
/// `x_i == y_i`, `y_i == z_i`, `x_i != z_i`. AC-consistent but
/// SAC-infeasible: pinning any value of `x_i` forces `y_i = z_i = x_i`
/// and then `x_i != z_i` wipes the domain. The canonical
/// SAC-detects-what-AC-misses example, scaled to multiple blocks so
/// the propagation work per pinning is non-trivial.
Future<Problem> buildSacInfeasible(
    {required int blocks, int domainSize = 3}) async {
  final p = Problem();
  final values = [for (var v = 1; v <= domainSize; v++) v];
  for (var i = 0; i < blocks; i++) {
    final x = 'x$i';
    final y = 'y$i';
    final z = 'z$i';
    p
      ..addVariable(x, values)
      ..addVariable(y, values)
      ..addVariable(z, values)
      ..addStringConstraint('$x == $y')
      ..addStringConstraint('$y == $z')
      ..addStringConstraint('$x != $z');
  }
  return p;
}

/// Over-packed 2D problem: `k` rectangles of size `size × size` in a
/// `box × box` bounding region with `k * size^2 > box^2`. Always
/// infeasible by area alone; useful for measuring how quickly each
/// propagation scheme can prove UNSAT. The sweep's compulsory-part
/// reasoning catches the infeasibility shallower in search than the
/// decomposition, where each pairwise 4-ary disjunction has to be
/// driven independently before the conflict surfaces.
Future<Problem> buildDiffNOverpack({
  bool useSweep = true,
  int k = 5,
  int size = 3,
  int box = 6,
}) async {
  final widths = List<int>.filled(k, size);
  final heights = List<int>.filled(k, size);
  final p = Problem();
  final xs = <String>[];
  final ys = <String>[];
  for (var i = 0; i < k; i++) {
    final xName = 'x$i';
    final yName = 'y$i';
    p
      ..addVariable(xName, [for (var v = 0; v <= box - size; v++) v])
      ..addVariable(yName, [for (var v = 0; v <= box - size; v++) v]);
    xs.add(xName);
    ys.add(yName);
  }
  if (useSweep) {
    p.addDiffN(xs, ys, widths, heights);
    return p;
  }
  for (var i = 0; i < k; i++) {
    for (var j = i + 1; j < k; j++) {
      final xi = xs[i];
      final yi = ys[i];
      final xj = xs[j];
      final yj = ys[j];
      p.addConstraint([xi, yi, xj, yj], (Map<String, dynamic> a) {
        final axi = a[xi];
        final ayi = a[yi];
        final axj = a[xj];
        final ayj = a[yj];
        if (axi == null || ayi == null || axj == null || ayj == null) {
          return true;
        }
        final xiN = axi as int;
        final yiN = ayi as int;
        final xjN = axj as int;
        final yjN = ayj as int;
        return xiN + size <= xjN ||
            xjN + size <= xiN ||
            yiN + size <= yjN ||
            yjN + size <= yiN;
      });
    }
  }
  return p;
}

/// 2D rectangle packing problem used for the sweep-vs-decomposition
/// comparison. Places a deterministic list of `n` mixed-size
/// rectangles inside a `box × box` bounding region; the lower-left
/// `(x_i, y_i)` of each rectangle is a fresh variable with domain
/// `[0, box - len_i]`. `addDiffN` is used when [useSweep] is true (the
/// shipped sweep propagator); otherwise the constraint is decomposed
/// manually into `n(n-1)/2` 4-ary disjunction predicates — exactly the
/// shape the old `addDiffN` posted before this session.
///
/// The default size (`n = 8`, `box = 8`) is a known-feasible packing:
/// six 2×2 squares plus a 3×3 and a 2×3 strip fit inside an 8×8 area
/// with room to spare. The mixed sizes (and `widths != heights` per
/// rectangle) let the sweep's compulsory-part overlap tests trigger
/// in both dimensions, which is where the sweep pulls ahead of the
/// decomposition.
Future<Problem> buildDiffNPack({
  bool useSweep = true,
  int box = 8,
}) async {
  // Mixed widths and heights — six 2×2 squares, one 3×3, one 2×3
  // strip. Total area = 6×4 + 9 + 6 = 39 in an 8×8 = 64 area.
  const widths = [3, 2, 2, 2, 2, 2, 2, 2];
  const heights = [3, 3, 2, 2, 2, 2, 2, 2];
  final n = widths.length;
  final p = Problem();
  final xs = <String>[];
  final ys = <String>[];
  for (var i = 0; i < n; i++) {
    final wi = widths[i];
    final hi = heights[i];
    final xName = 'x$i';
    final yName = 'y$i';
    p
      ..addVariable(xName, [for (var v = 0; v <= box - wi; v++) v])
      ..addVariable(yName, [for (var v = 0; v <= box - hi; v++) v]);
    xs.add(xName);
    ys.add(yName);
  }
  if (useSweep) {
    p.addDiffN(xs, ys, widths, heights);
    return p;
  }
  // Pairwise decomposition: post one 4-ary disjunction per unordered
  // pair. Mirrors what the old `addDiffN` did before the sweep
  // propagator shipped.
  for (var i = 0; i < n; i++) {
    final wi = widths[i];
    final hi = heights[i];
    for (var j = i + 1; j < n; j++) {
      final wj = widths[j];
      final hj = heights[j];
      final xi = xs[i];
      final yi = ys[i];
      final xj = xs[j];
      final yj = ys[j];
      p.addConstraint([xi, yi, xj, yj], (Map<String, dynamic> a) {
        final axi = a[xi];
        final ayi = a[yi];
        final axj = a[xj];
        final ayj = a[yj];
        if (axi == null || ayi == null || axj == null || ayj == null) {
          return true;
        }
        final xiN = axi as int;
        final yiN = ayi as int;
        final xjN = axj as int;
        final yjN = ayj as int;
        return xiN + wi <= xjN ||
            xjN + wj <= xiN ||
            yiN + hi <= yjN ||
            yjN + hj <= yiN;
      });
    }
  }
  return p;
}

/// Conflict-explanation benchmark: a singleton MUS surrounded by [n]
/// trivially-satisfied binary constraints. The core is a 3-in-2
/// pigeonhole over `{a, b, c}` posted as a single `addAllDifferent`
/// — the only constraint contributing to UNSAT. The redundants are
/// `n` binary `addConstraint` calls over various variable pairs with
/// always-true predicates on the `{1, 2}` domain. The MUS pass should
/// drop every redundant and return the singleton `[allDifferent]`.
///
/// Scales `n` to expose deletion's O(n) work vs QuickXplain's
/// O(k · log(n / k)) work. For k = 1, QuickXplain only needs
/// `~log_2(n + 1)` `CSP.solve` calls to locate the MUS; deletion
/// needs n + 1.
Future<Problem> buildExplainSingletonMus({required int n}) async {
  final p = Problem()
    ..addVariables(['a', 'b', 'c'], [1, 2])
    ..addAllDifferent(['a', 'b', 'c']);
  const pairs = [
    ['a', 'b'],
    ['b', 'c'],
    ['a', 'c'],
  ];
  for (var i = 0; i < n; i++) {
    final vars = pairs[i % pairs.length];
    p.addConstraint(
        vars, (dynamic x, dynamic y) => (x as int) <= 2 && (y as int) <= 2);
  }
  return p;
}

/// Conflict-explanation benchmark: a 3-element MUS (triangle 3-coloring
/// with 2 colors) surrounded by [n] trivially-satisfied redundants.
/// The three `≠` edges of the triangle are the MUS; every redundant
/// is a binary `addConstraint` call with an always-true predicate.
///
/// Scales `n` to expose deletion's O(n) work vs QuickXplain's
/// O(k · log(n / k)) work. For k = 3, QuickXplain's solve count grows
/// roughly as `3 · log_2(n / 3)`; deletion grows as `n + 3 + 1`.
Future<Problem> buildExplainTriangleMus({required int n}) async {
  final p = Problem()
    ..addVariables(['a', 'b', 'c'], [1, 2])
    ..addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b)
    ..addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c)
    ..addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
  const pairs = [
    ['a', 'b'],
    ['b', 'c'],
    ['a', 'c'],
  ];
  for (var i = 0; i < n; i++) {
    final vars = pairs[i % pairs.length];
    p.addConstraint(
        vars, (dynamic x, dynamic y) => (x as int) <= 2 && (y as int) <= 2);
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

/// Bin-packing optimization: distribute [itemCount] items across
/// [binCount] bins, minimise the heaviest bin's load. Item weights
/// are deterministic (the sequence `(2*i + 3) mod 13 + 1` for i in
/// 0..itemCount-1) so the optimum is reproducible across runs but
/// not trivial to guess. Used by `bench(lns)` and the LNS test
/// suite as a "harder than n=8" instance where plain branch-and-
/// bound has to chew through a lot of leaves and LNS can keep
/// improving its incumbent quickly via partial-reassignment moves.
///
/// Encoding: each item is a single integer variable holding its bin
/// index; each bin gets an n-ary load constraint
/// `load_b == Σ_{i: item_i == b} weight[i]`. The single-int-per-item
/// shape gives LNS room to swap a handful of items between bins per
/// destroy iteration — the indicator-per-item-per-bin alternative
/// leaves the freed indicators over-constrained by their pinned
/// siblings and rarely improves.
Future<Problem> buildBinPackingMinMaxLoad({
  required int itemCount,
  required int binCount,
}) async {
  final weights = [for (var i = 0; i < itemCount; i++) (2 * i + 3) % 13 + 1];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final items = [for (var i = 0; i < itemCount; i++) 'item$i'];
  final p = Problem();
  for (final it in items) {
    p.addVariable(it, [for (var b = 0; b < binCount; b++) b]);
  }
  for (var b = 0; b < binCount; b++) {
    p.addRangeVariable('load$b', 0, total);
    p.addConstraint(
      ['load$b', ...items],
      (Map<String, dynamic> a) {
        var sum = 0;
        for (var i = 0; i < itemCount; i++) {
          if (a[items[i]] == b) sum += weights[i];
        }
        return a['load$b'] == sum;
      },
    );
  }
  p.addRangeVariable('maxLoad', 0, total);
  for (var b = 0; b < binCount; b++) {
    p.addConstraint(['maxLoad', 'load$b'],
        (dynamic ml, dynamic l) => (ml as num) >= (l as num));
  }
  return p;
}

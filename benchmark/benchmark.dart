/// Performance regression benchmarks for dart_csp.
///
/// Run with:
///
///   dart run benchmark/benchmark.dart
///
/// Prints two rows per benchmark — plain backtracking and CBJ-enabled
/// — with wall-clock time and the engine stats from
/// `Problem.lastStats`. The CBJ row additionally shows `backjumps`
/// and `backjumpLevelsSkipped` so a user deciding whether to flip the
/// `enableConflictBackjumping:` flag on a given problem can see at a
/// glance whether the engine actually has work to do under CBJ. CI
/// runs this on push to main.
library;

import 'package:dart_csp/dart_csp.dart';

import 'problems.dart';

Future<void> main() async {
  print('--- dart_csp benchmarks ---');
  print('');
  await _bench('magic-square 3x3 (no clue)', buildMagicSquareNoClue);
  await _bench('magic-square 3x3 (B2=5 pinned)', buildMagicSquarePinned);
  await _bench('sudoku medium-hard', buildSudoku);
  await _bench('8-queens', () => buildNQueens(8));
  await _bench('12-queens', () => buildNQueens(12));
  await _bench('16-queens', () => buildNQueens(16));
  await _bench('Australia map coloring (3 colors)', buildMapColoring);
  await _bench('SEND + MORE = MONEY (predicate)', buildSendMoreMoneyPredicate);
  await _bench('SEND + MORE = MONEY (linear)', buildSendMoreMoneyLinear);
  await _bench('pigeonhole CNF 7-in-6 (UNSAT)',
      () => buildPigeonholeCnf(pigeons: 7, holes: 6));
  print('');
  print('--- done ---');
}

Future<void> _bench(String label, Future<Problem> Function() build) async {
  final plain = await _run(build, cbj: false);
  final cbj = await _run(build, cbj: true);
  print(label);
  print('  ${_format('plain', plain)}');
  print('  ${_format('cbj  ', cbj)}');
}

Future<_BenchResult> _run(
  Future<Problem> Function() build, {
  required bool cbj,
}) async {
  final p = await build();
  final sw = Stopwatch()..start();
  final result = await p.getSolution(enableConflictBackjumping: cbj);
  sw.stop();
  return _BenchResult(
    ok: result is Map<String, dynamic>,
    elapsedMs: sw.elapsedMilliseconds,
    stats: p.lastStats!,
  );
}

String _format(String tag, _BenchResult r) {
  final core = 'd:${r.stats.decisions} '
      'b:${r.stats.backtracks} '
      'p:${r.stats.propagations}';
  final cbjPart = ' bj:${r.stats.backjumps}/${r.stats.backjumpLevelsSkipped}';
  return '$tag  ${(r.ok ? 'ok' : 'NO SOLUTION').padRight(11)}  '
      '${r.elapsedMs.toString().padLeft(6)} ms  $core$cbjPart';
}

class _BenchResult {
  _BenchResult(
      {required this.ok, required this.elapsedMs, required this.stats});
  final bool ok;
  final int elapsedMs;
  final SolverStats stats;
}

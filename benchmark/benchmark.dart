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

// The diff_n bench passes `useSweep: true` explicitly for visual
// symmetry with the `useSweep: false` companion call on the same
// problem; without the explicit argument, the side-by-side reads
// asymmetrically.
// ignore_for_file: avoid_redundant_argument_values

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
  print('--- consistency-level comparisons (AC vs SAC) ---');
  print('');
  await _benchConsistency(
      'SAC-only infeasibility (5 blocks of x==y, y==z, x!=z)',
      () => buildSacInfeasible(blocks: 5));
  print('');
  print('--- diff_n propagator comparisons (sweep vs decomposition) ---');
  print('');
  await _benchDiffN(
    '8 rectangles in 8x8 (find-first)',
    () => buildDiffNPack(useSweep: true),
    () => buildDiffNPack(useSweep: false),
  );
  await _benchDiffN(
    '5 3x3 in 6x6 (UNSAT by area)',
    () => buildDiffNOverpack(useSweep: true),
    () => buildDiffNOverpack(useSweep: false),
  );
  print('');
  print('--- heuristic comparisons '
      '(MRV vs dom/wdeg vs VSIDS vs IBS vs LC+dom/wdeg) ---');
  print('');
  await _benchHeuristic('magic-square 3x3 (no clue)', buildMagicSquareNoClue);
  await _benchHeuristic('12-queens', () => buildNQueens(12));
  await _benchHeuristic('16-queens', () => buildNQueens(16));
  await _benchHeuristic(
      'SEND + MORE = MONEY (linear)', buildSendMoreMoneyLinear);
  await _benchHeuristic('pigeonhole CNF 7-in-6 (UNSAT)',
      () => buildPigeonholeCnf(pigeons: 7, holes: 6));
  await _benchHeuristic('pigeonhole CNF 8-in-7 (UNSAT, harder)',
      () => buildPigeonholeCnf(pigeons: 8, holes: 7));
  print('');
  print('--- conflict-explanation comparisons '
      '(deletion vs QuickXplain) ---');
  print('');
  await _benchExplain('singleton MUS (k=1) + 10 redundants',
      () => buildExplainSingletonMus(n: 10));
  await _benchExplain('singleton MUS (k=1) + 50 redundants',
      () => buildExplainSingletonMus(n: 50));
  await _benchExplain('singleton MUS (k=1) + 200 redundants',
      () => buildExplainSingletonMus(n: 200));
  await _benchExplain('triangle MUS (k=3) + 10 redundants',
      () => buildExplainTriangleMus(n: 10));
  await _benchExplain('triangle MUS (k=3) + 50 redundants',
      () => buildExplainTriangleMus(n: 50));
  await _benchExplain('triangle MUS (k=3) + 200 redundants',
      () => buildExplainTriangleMus(n: 200));
  await _benchExplain('pigeonhole CNF 5-in-4 (k ≈ n)',
      () => buildPigeonholeCnf(pigeons: 5, holes: 4));
  print('');
  print('--- FlatZinc parse + lower + solve ---');
  print('');
  await _benchFlatZinc('4-queens (all_different + int_lin_ne diagonals)',
      _fznQueens(4));
  await _benchFlatZinc('6-queens (all_different + int_lin_ne diagonals)',
      _fznQueens(6));
  await _benchFlatZinc('SEND + MORE = MONEY (int_lin_eq cryptarithm)',
      _fznSendMoreMoney);
  await _benchFlatZinc('magic-square 3x3 (int_lin_eq lines, all_different)',
      _fznMagicSquare3);
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

/// AC vs SAC side-by-side on a single problem. Both runs use the
/// default search settings; the only knob is `consistency:`. The
/// "ok" column reads NO SOLUTION when the problem is infeasible —
/// both modes should agree on that, but SAC normally proves it at
/// preprocessing (decisions ≈ 0) where AC has to descend.
Future<void> _benchConsistency(
    String label, Future<Problem> Function() build) async {
  final ac = await _runConsistency(build, ConsistencyLevel.arcConsistency);
  final sac =
      await _runConsistency(build, ConsistencyLevel.singletonArcConsistency);
  print(label);
  print('  ${_format('ac ', ac)}');
  print('  ${_format('sac', sac)}');
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

/// Sweep vs decomposition for `addDiffN` on the same problem. Both
/// runs solve the same packing problem; the only difference is how
/// the no-overlap constraint is posted (one tagged `addDiffN` call
/// vs `n(n-1)/2` explicit 4-ary disjunctions). A 5-rep warm-up loop
/// followed by a 25-rep timed run on each side reports the median
/// wall-clock — pre-JIT cold timings on small problems are noisy and
/// not what we want to publish. The `decisions / backtracks / props`
/// columns come from the first timed rep (they're deterministic
/// across reps for the same problem).
Future<void> _benchDiffN(
  String label,
  Future<Problem> Function() buildSweep,
  Future<Problem> Function() buildDecomp,
) async {
  final sweep = await _runMedian(buildSweep);
  final decomp = await _runMedian(buildDecomp);
  print(label);
  print('  ${_formatMicros('sweep ', sweep)}');
  print('  ${_formatMicros('decomp', decomp)}');
}

Future<_BenchMedianResult> _runMedian(
  Future<Problem> Function() build, {
  int warmup = 5,
  int reps = 25,
}) async {
  for (var i = 0; i < warmup; i++) {
    final p = await build();
    await p.getSolution();
  }
  final times = <int>[];
  late SolverStats firstStats;
  var ok = false;
  for (var i = 0; i < reps; i++) {
    final p = await build();
    final sw = Stopwatch()..start();
    final result = await p.getSolution();
    sw.stop();
    times.add(sw.elapsedMicroseconds);
    if (i == 0) {
      firstStats = p.lastStats!;
      ok = result is Map<String, dynamic>;
    }
  }
  times.sort();
  return _BenchMedianResult(
    ok: ok,
    medianMicros: times[times.length ~/ 2],
    stats: firstStats,
  );
}

/// Five-way heuristic comparison on the same problem: MRV (the
/// default), dom/wdeg, VSIDS-style activity, Impact-Based Search,
/// and Last-Conflict reasoning layered on dom/wdeg (Lecoutre's
/// canonical deployment). Uses the same 5-rep warm-up + 25-rep
/// median methodology as the diff_n bench — cold timings on
/// these problems are noisy.
///
/// LC alone (without an underlying picker) reduces to MRV-with-
/// focus-on-conflict; the more interesting and benchmark-worthy
/// shape is LC+dom/wdeg per Lecoutre 2009, so that's what the
/// row reports.
Future<void> _benchHeuristic(
    String label, Future<Problem> Function() build) async {
  final mrv = await _runHeuristicMedian(build, _Heuristic.mrv);
  final dw = await _runHeuristicMedian(build, _Heuristic.domWdeg);
  final vsids = await _runHeuristicMedian(build, _Heuristic.vsids);
  final ibs = await _runHeuristicMedian(build, _Heuristic.impact);
  final lcdw = await _runHeuristicMedian(build, _Heuristic.lcDomWdeg);
  print(label);
  print('  ${_formatMicros('mrv     ', mrv)}');
  print('  ${_formatMicros('dom/wdeg', dw)}');
  print('  ${_formatMicros('vsids   ', vsids)}');
  print('  ${_formatMicros('ibs     ', ibs)}');
  print('  ${_formatMicros('lc+dwdg ', lcdw)}');
}

enum _Heuristic { mrv, domWdeg, vsids, impact, lcDomWdeg }

Future<dynamic> _solveWithHeuristic(Problem p, _Heuristic h) {
  switch (h) {
    case _Heuristic.mrv:
      return p.getSolution();
    case _Heuristic.domWdeg:
      return p.getSolutionWithDomWdeg();
    case _Heuristic.vsids:
      return p.getSolutionWithActivity();
    case _Heuristic.impact:
      return p.getSolutionWithImpact();
    case _Heuristic.lcDomWdeg:
      return p.getSolutionWithLastConflict(useDomWdeg: true);
  }
}

Future<_BenchMedianResult> _runHeuristicMedian(
  Future<Problem> Function() build,
  _Heuristic h, {
  int warmup = 5,
  int reps = 25,
}) async {
  for (var i = 0; i < warmup; i++) {
    final p = await build();
    await _solveWithHeuristic(p, h);
  }
  final times = <int>[];
  late SolverStats firstStats;
  var ok = false;
  for (var i = 0; i < reps; i++) {
    final p = await build();
    final sw = Stopwatch()..start();
    final result = await _solveWithHeuristic(p, h);
    sw.stop();
    times.add(sw.elapsedMicroseconds);
    if (i == 0) {
      firstStats = p.lastStats!;
      ok = result is Map<String, dynamic>;
    }
  }
  times.sort();
  return _BenchMedianResult(
    ok: ok,
    medianMicros: times[times.length ~/ 2],
    stats: firstStats,
  );
}

Future<_BenchResult> _runConsistency(
  Future<Problem> Function() build,
  ConsistencyLevel consistency,
) async {
  final p = await build();
  final sw = Stopwatch()..start();
  final result = await p.getSolution(consistency: consistency);
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

String _formatMicros(String tag, _BenchMedianResult r) {
  final core = 'd:${r.stats.decisions} '
      'b:${r.stats.backtracks} '
      'p:${r.stats.propagations}';
  return '$tag  ${(r.ok ? 'ok' : 'NO SOLUTION').padRight(11)}  '
      '${r.medianMicros.toString().padLeft(7)} µs  $core';
}

class _BenchResult {
  _BenchResult(
      {required this.ok, required this.elapsedMs, required this.stats});
  final bool ok;
  final int elapsedMs;
  final SolverStats stats;
}

class _BenchMedianResult {
  _BenchMedianResult(
      {required this.ok, required this.medianMicros, required this.stats});
  final bool ok;
  final int medianMicros;
  final SolverStats stats;
}

/// Deletion-based MUS vs QuickXplain side-by-side on the same problem.
/// Both passes return the same shape of `List<ConstraintRef>?`; the
/// only knob is which method is called. Uses a smaller 3-rep warm-up +
/// 9-rep median than the propagator benches because each MUS run is
/// itself many `CSP.solve` calls. The MUS size from the first timed
/// rep is reported alongside the wall-clock — different runs of the
/// same algorithm on the same problem always return the same MUS
/// (the algorithm is deterministic given fixed constraint ordering),
/// but the two algorithms may surface different locally-minimal MUSes.
Future<void> _benchExplain(
    String label, Future<Problem> Function() build) async {
  final del = await _runExplainMedian(build, deletion: true);
  final qx = await _runExplainMedian(build, deletion: false);
  print(label);
  print('  ${_formatExplain('deletion ', del)}');
  print('  ${_formatExplain('quickxpln', qx)}');
}

Future<_BenchExplainResult> _runExplainMedian(
  Future<Problem> Function() build, {
  required bool deletion,
  int warmup = 3,
  int reps = 9,
}) async {
  Future<List<ConstraintRef>?> solve(Problem p) => deletion
      ? p.findMinimalUnsatisfiableSubset()
      : p.findMinimalUnsatisfiableSubsetQuickXplain();
  for (var i = 0; i < warmup; i++) {
    final p = await build();
    await solve(p);
  }
  final times = <int>[];
  var musSize = -1;
  for (var i = 0; i < reps; i++) {
    final p = await build();
    final sw = Stopwatch()..start();
    final mus = await solve(p);
    sw.stop();
    times.add(sw.elapsedMicroseconds);
    if (i == 0) musSize = mus?.length ?? -1;
  }
  times.sort();
  return _BenchExplainResult(
    musSize: musSize,
    medianMicros: times[times.length ~/ 2],
  );
}

String _formatExplain(String tag, _BenchExplainResult r) {
  final musTag = r.musSize < 0 ? 'NO MUS' : 'mus_size=${r.musSize}';
  return '$tag  ${musTag.padRight(11)}  '
      '${r.medianMicros.toString().padLeft(8)} µs';
}

class _BenchExplainResult {
  _BenchExplainResult({required this.musSize, required this.medianMicros});
  final int musSize;
  final int medianMicros;
}

/// FlatZinc end-to-end bench: parse + lower + solve. Splits the
/// wall-clock into a "parse+lower" portion (the frontend pipeline) and
/// a "solve" portion (the engine) so a regression in either is easy to
/// attribute. Same 5-rep warm-up + 25-rep median methodology as the
/// other median-style benches.
Future<void> _benchFlatZinc(String label, String source) async {
  // Warm-up: drive the full pipeline a few times so JIT and the
  // FlatZinc constraint-handler closures all settle.
  for (var i = 0; i < 5; i++) {
    await FlatZinc.solve(source);
  }
  final parseTimes = <int>[];
  final solveTimes = <int>[];
  for (var i = 0; i < 25; i++) {
    final sw1 = Stopwatch()..start();
    final lowered = FlatZinc.build(source);
    sw1.stop();
    parseTimes.add(sw1.elapsedMicroseconds);
    final sw2 = Stopwatch()..start();
    await lowered.problem.getSolution();
    sw2.stop();
    solveTimes.add(sw2.elapsedMicroseconds);
  }
  parseTimes.sort();
  solveTimes.sort();
  final pmed = parseTimes[parseTimes.length ~/ 2];
  final smed = solveTimes[solveTimes.length ~/ 2];
  print(label);
  print('  parse+lower ${pmed.toString().padLeft(8)} µs');
  print('  solve       ${smed.toString().padLeft(8)} µs');
  print('  total       ${(pmed + smed).toString().padLeft(8)} µs');
}

// FlatZinc problem sources for the bench. Hand-written rather than
// produced via mzn2fzn so the bench has zero external dependencies and
// the constraint mix stays explicit.
String _fznQueens(int n) {
  final buf = StringBuffer();
  buf.writeln('array[1..$n] of var 1..$n: q :: output_array([1..$n]);');
  buf.writeln('constraint all_different_int(q);');
  for (var i = 1; i <= n; i++) {
    for (var j = i + 1; j <= n; j++) {
      // Diagonal exclusion: q[i] - q[j] != ±(j - i).
      buf.writeln('constraint int_lin_ne([1, -1], [q[$i], q[$j]], ${j - i});');
      buf.writeln(
          'constraint int_lin_ne([1, -1], [q[$i], q[$j]], ${-(j - i)});');
    }
  }
  buf.writeln('solve satisfy;');
  return buf.toString();
}

const _fznSendMoreMoney = '''
var 1..9: s :: output_var;
var 0..9: e :: output_var;
var 0..9: n :: output_var;
var 0..9: d :: output_var;
var 1..9: m :: output_var;
var 0..9: o :: output_var;
var 0..9: r :: output_var;
var 0..9: y :: output_var;
constraint all_different_int([s, e, n, d, m, o, r, y]);
constraint int_lin_eq(
  [1000, 100, 10, 1, 1000, 100, 10, 1, -10000, -1000, -100, -10, -1],
  [s, e, n, d, m, o, r, e, m, o, n, e, y],
  0);
solve satisfy;
''';

const _fznMagicSquare3 = '''
array[1..9] of var 1..9: m :: output_array([1..9]);
constraint all_different_int(m);
% Row sums = 15.
constraint int_lin_eq([1, 1, 1], [m[1], m[2], m[3]], 15);
constraint int_lin_eq([1, 1, 1], [m[4], m[5], m[6]], 15);
constraint int_lin_eq([1, 1, 1], [m[7], m[8], m[9]], 15);
% Column sums = 15.
constraint int_lin_eq([1, 1, 1], [m[1], m[4], m[7]], 15);
constraint int_lin_eq([1, 1, 1], [m[2], m[5], m[8]], 15);
constraint int_lin_eq([1, 1, 1], [m[3], m[6], m[9]], 15);
% Diagonals = 15.
constraint int_lin_eq([1, 1, 1], [m[1], m[5], m[9]], 15);
constraint int_lin_eq([1, 1, 1], [m[3], m[5], m[7]], 15);
solve satisfy;
''';

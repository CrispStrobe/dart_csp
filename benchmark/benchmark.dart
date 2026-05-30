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
  print('--- LNS vs plain branch-and-bound (minimize max-load) ---');
  print('');
  // Only two instance sizes here — n=12 takes ~40s per plain rep and
  // would dominate the benchmark wall-clock for the much rarer
  // "fresh numbers locally" use case. The doc/lns.md table covers the
  // n=12 case with concrete numbers that were measured separately.
  await _benchLns(
    'bin-packing 8 items / 3 bins',
    () => buildBinPackingMinMaxLoad(itemCount: 8, binCount: 3),
  );
  await _benchLns(
    'bin-packing 10 items / 3 bins',
    () => buildBinPackingMinMaxLoad(itemCount: 10, binCount: 3),
  );
  print('');
  print('--- cooperative parallel LNS '
      '(portfolio vs cooperative on the same problem) ---');
  print('');
  // Each row spawns `workerCount × (warmup + reps) = 12` isolates so
  // the wall-clock for this section is dominated by isolate spawn
  // and per-iteration LNS overhead. Same destroy policy (random,
  // fraction 0.5), seed list, and iteration budget across both flag
  // values — only `cooperative:` differs.
  await _benchCooperativeLns(
    'bin-packing 12 items / 3 bins (3 workers, budget 80, fraction 0.5)',
    () => buildBinPackingMinMaxLoad(itemCount: 12, binCount: 3),
  );
  print('');
  print('--- cumulative energetic reasoning '
      '(time-table only vs +energetic) ---');
  print('');
  // ER adds an O(n³) overload check + earliest-start / latest-completion
  // adjustments on top of the time-table profile. On tight RCPSP instances
  // the decision-count reduction more than pays back the per-propagation
  // cost: the root-overload row is detected infeasible at the root (the
  // baseline backtracks hundreds of nodes), and the in-search row cuts the
  // decision count several-fold. Both use plain backtracking so the rows
  // isolate ER from the search heuristic. The only knob is the public
  // `useEnergeticReasoning:` flag on `addCumulative`.
  await _benchCumulative(
    'RCPSP 8-task cap-2 (UNSAT) — energetic overload at root',
    () => buildCumulativeErRootOverload(useEnergeticReasoning: false),
    () => buildCumulativeErRootOverload(useEnergeticReasoning: true),
  );
  await _benchCumulative(
    'RCPSP 8-task cap-2 (UNSAT) — energetic pruning in search',
    () => buildCumulativeErInSearch(useEnergeticReasoning: false),
    () => buildCumulativeErInSearch(useEnergeticReasoning: true),
  );
  print('');
  print('--- LCG (Lazy Clause Generation) — plain vs solveWithLcg ---');
  print('');
  // The pigeonhole rows are the canonical LCG showcase: every conflict
  // flows through the boolean clause propagator, so the analyser
  // resolves cleanly to a learned clause. Expect 10-100× decision-count
  // reductions; the wall-clock win is smaller because the LCG path
  // pays per-prune implication-trail bookkeeping on every successful
  // step too. Heuristic comparison rows for the same problems live
  // above; here we isolate the LCG knob.
  //
  // The 8-queens row is the "wash" reference: every conflict flows
  // through binary != predicates that emit UnknownReason, so the
  // analyser bails and the engine falls back to chronological
  // backtrack — modulo the trail-bookkeeping overhead the two rows
  // should match on decisions and stay within noise on wall-clock.
  await _benchLcg('pigeonhole CNF 6-in-5 (UNSAT)',
      () => buildPigeonholeCnf(pigeons: 6, holes: 5));
  await _benchLcg('pigeonhole CNF 7-in-6 (UNSAT)',
      () => buildPigeonholeCnf(pigeons: 7, holes: 6));
  await _benchLcg('pigeonhole CNF 8-in-7 (UNSAT, harder)',
      () => buildPigeonholeCnf(pigeons: 8, holes: 7));
  await _benchLcg('8-queens (no boolean clauses — LCG should be a wash)',
      () => buildNQueens(8));
  print('');
  // Restart showcase: a heavy-tailed satisfiable random 3-SAT instance
  // under VSIDS. The plain iterative search wanders; restarts that retain
  // the learned-clause pool + activity + saved phase rebuild the good
  // partial assignment and finish in far fewer decisions. (Seed 5 is
  // satisfiable; UNSAT instances would instead take a small restart
  // penalty, which is why restarts are off by default.)
  await _benchLcgRestart(
      'random 3-SAT n=100 ratio 4.26 (SAT, VSIDS) — restart showcase',
      () => buildRandom3Sat(seed: 5));
  print('');
  // M3e/M3f/M3g showcase: the scheduling / packing / routing propagators
  // now have explain companions, so the engine learns clauses on their
  // conflicts (the `lcg`/`iter` rows show learned > 0) where they were
  // previously opaque (learned == 0, chronological fallback). These globals
  // decode to the wide atom encoding, so the iterative engine posts the
  // learned clause but still backtracks chronologically (bj stays 0); the
  // win is that learning fires at all. GAC-ish constraints ⇒ small
  // decision-count deltas vs the boolean pigeonhole rows.
  await _benchLcg('cumulative RCPSP 5-task cap-2 (UNSAT) — M3e time-table',
      buildCumulativeUnsat);
  await _benchLcg(
      'diff_n 4-rect packing (UNSAT) — M3f forbidden-region', buildDiffNUnsat);
  await _benchLcg(
      'circuit 5-node (UNSAT) — M3g cycle-detection', buildCircuitUnsat);
  print('');
  print('--- FlatZinc parse + lower + solve ---');
  print('');
  await _benchFlatZinc(
      '4-queens (all_different + int_lin_ne diagonals)', _fznQueens(4));
  await _benchFlatZinc(
      '6-queens (all_different + int_lin_ne diagonals)', _fznQueens(6));
  await _benchFlatZinc(
      'SEND + MORE = MONEY (int_lin_eq cryptarithm)', _fznSendMoreMoney);
  await _benchFlatZinc(
      'magic-square 3x3 (int_lin_eq lines, all_different)', _fznMagicSquare3);
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

/// Time-table-only vs time-table+energetic-reasoning on the same tight
/// RCPSP instance. Both rows use plain backtracking (no CBJ, default MRV);
/// the only difference is the public `useEnergeticReasoning:` flag, so the
/// decision / wall-clock delta is exactly what the energetic-reasoning pass
/// buys. Same 5-rep warm-up + 25-rep median methodology as the other
/// `_runMedian` sections.
Future<void> _benchCumulative(
  String label,
  Future<Problem> Function() buildTimeTable,
  Future<Problem> Function() buildEnergetic,
) async {
  final tt = await _runMedian(buildTimeTable);
  final er = await _runMedian(buildEnergetic);
  print(label);
  print('  ${_formatMicros('time-table', tt)}');
  print('  ${_formatMicros('+energetic', er)}');
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

/// LCG (Lazy Clause Generation, M2b) vs plain backtracking on the same
/// problem. Same 5-rep warm-up + 25-rep median methodology as the
/// other bench sections. LCG row additionally surfaces
/// `learnedClauses / forgottenClauses / backjumps` so a reader can
/// distinguish "LCG learned and learned a lot" from "LCG fell back to
/// chronological" at a glance.
Future<void> _benchLcg(String label, Future<Problem> Function() build) async {
  final plain = await _runMedian(build);
  final lcg = await _runLcgMedian(build);
  // Iterative engine: the non-chronological-backjump path. The decision
  // count drops on the CNF showcase rows (and matches `lcg`/`plain` on the
  // 8-queens wash). This is the make-default non-regression evidence —
  // iterative should never lose to recursive-LCG on decisions.
  final iter = await _runLcgMedian(build, useIterativeCdcl: true);
  print(label);
  print('  ${_formatMicros('plain', plain)}');
  print('  ${_formatLcgMicros('lcg  ', lcg)}');
  print('  ${_formatLcgMicros('iter ', iter)}');
}

/// Restart comparison on a heavy-tailed satisfiable instance: iterative
/// CDCL with VSIDS, restarts off vs on. Fewer reps than the showcase rows
/// because each solve is heavier. Expect the restart row to cut decisions
/// (and usually wall-clock) substantially.
Future<void> _benchLcgRestart(
    String label, Future<Problem> Function() build) async {
  final off = await _runLcgMedian(build,
      warmup: 2, reps: 5, useIterativeCdcl: true, useVsids: true, seed: 5);
  final on = await _runLcgMedian(build,
      warmup: 2,
      reps: 5,
      useIterativeCdcl: true,
      useVsids: true,
      useRestarts: true,
      seed: 5);
  print(label);
  print('  ${_formatLcgMicros('no-restart', off)}');
  print('  ${_formatLcgMicros('restart   ', on)}');
}

Future<_BenchMedianResult> _runLcgMedian(
  Future<Problem> Function() build, {
  int warmup = 5,
  int reps = 25,
  bool useIterativeCdcl = false,
  bool useRestarts = false,
  bool useVsids = false,
  int? seed,
}) async {
  Future<dynamic> solve(Problem p) => p.solveWithLcg(
        useIterativeCdcl: useIterativeCdcl,
        useRestarts: useRestarts,
        useVsids: useVsids,
        seed: seed,
      );
  for (var i = 0; i < warmup; i++) {
    final p = await build();
    await solve(p);
  }
  final times = <int>[];
  late SolverStats firstStats;
  var ok = false;
  for (var i = 0; i < reps; i++) {
    final p = await build();
    final sw = Stopwatch()..start();
    final result = await solve(p);
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

String _formatLcgMicros(String tag, _BenchMedianResult r) {
  final core = 'd:${r.stats.decisions} '
      'b:${r.stats.backtracks} '
      'p:${r.stats.propagations}';
  final lcgPart = ' learned:${r.stats.learnedClauses}'
      '/forgotten:${r.stats.forgottenClauses}'
      ' bj:${r.stats.backjumps}/${r.stats.backjumpLevelsSkipped}'
      ' rst:${r.stats.restarts}';
  return '$tag  ${(r.ok ? 'ok' : 'NO SOLUTION').padRight(11)}  '
      '${r.medianMicros.toString().padLeft(7)} µs  $core$lcgPart';
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

/// LNS vs plain branch-and-bound side-by-side on the same problem. The
/// plain run calls `Problem.minimize` (proves the optimum); the LNS
/// run calls `Problem.lnsMinimize` with a random destroy + improving
/// accept and a fixed seed (returns a near-optimum). Reports the
/// median wall-clock for both plus the LNS-specific iteration /
/// accept / reject counts from the first timed rep.
///
/// On the smaller bin-packing instance plain branch-and-bound wins
/// because LNS pays the warm-up + iteration overhead with no real
/// search to amortise it against. On the larger instance LNS wins
/// because plain B&B has to prove optimality and the search tree
/// grows superlinearly with item count.
Future<void> _benchLns(String label, Future<Problem> Function() build) async {
  final plain = await _runLnsMedianPlain(build);
  final lns = await _runLnsMedian(build);
  print(label);
  print('  ${_formatLnsPlain('plain', plain)}');
  print('  ${_formatLns('lns  ', lns)}');
}

Future<_BenchMedianResult> _runLnsMedianPlain(
  Future<Problem> Function() build, {
  int warmup = 3,
  int reps = 9,
}) async {
  for (var i = 0; i < warmup; i++) {
    final p = await build();
    await p.minimize('maxLoad');
  }
  final times = <int>[];
  late SolverStats firstStats;
  var ok = false;
  for (var i = 0; i < reps; i++) {
    final p = await build();
    final sw = Stopwatch()..start();
    final result = await p.minimize('maxLoad');
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

Future<_BenchLnsResult> _runLnsMedian(
  Future<Problem> Function() build, {
  int warmup = 3,
  int reps = 9,
  int iterationBudget = 50,
}) async {
  Future<LnsResult> solve(Problem p) => p.lnsMinimize(
        'maxLoad',
        policy: LnsPolicy.random(fraction: 0.5),
        iterationBudget: iterationBudget,
        seed: 17,
      );
  for (var i = 0; i < warmup; i++) {
    final p = await build();
    await solve(p);
  }
  final times = <int>[];
  late LnsStats firstStats;
  num? finalObj;
  for (var i = 0; i < reps; i++) {
    final p = await build();
    final sw = Stopwatch()..start();
    final result = await solve(p);
    sw.stop();
    times.add(sw.elapsedMicroseconds);
    if (i == 0) {
      firstStats = result.stats;
      finalObj = result.stats.finalObjective;
    }
  }
  times.sort();
  return _BenchLnsResult(
    finalObjective: finalObj,
    medianMicros: times[times.length ~/ 2],
    stats: firstStats,
  );
}

String _formatLnsPlain(String tag, _BenchMedianResult r) {
  final core = 'd:${r.stats.decisions} '
      'b:${r.stats.backtracks} '
      'p:${r.stats.propagations}';
  return '$tag  ${(r.ok ? 'optimum' : 'NO SOLUTION').padRight(11)}  '
      '${r.medianMicros.toString().padLeft(7)} µs  $core';
}

String _formatLns(String tag, _BenchLnsResult r) {
  final objTag =
      r.finalObjective == null ? 'NO SOLUTION' : 'obj=${r.finalObjective}';
  final core = 'it:${r.stats.iterations} '
      'acc:${r.stats.accepts} '
      'rej:${r.stats.rejects} '
      'inf:${r.stats.infeasibles}';
  return '$tag  ${objTag.padRight(11)}  '
      '${r.medianMicros.toString().padLeft(7)} µs  $core';
}

class _BenchLnsResult {
  _BenchLnsResult({
    required this.finalObjective,
    required this.medianMicros,
    required this.stats,
  });
  final num? finalObjective;
  final int medianMicros;
  final LnsStats stats;
}

/// Compares portfolio parallel LNS (workers run independently with
/// different seeds) against cooperative parallel LNS (the same
/// runner with `cooperative: true`, which broadcasts mid-run
/// incumbent improvements through the worker isolates' control
/// ports). Both runs use the same problem builder, worker count,
/// seed list, and iteration budget; the only knob is the
/// `cooperative:` flag.
///
/// Cooperative LNS is expected to converge to an equal-or-better
/// incumbent within the same wall-clock budget on workloads where
/// (a) any worker finds an improvement during the run, and (b) the
/// tightened objective domain meaningfully prunes sibling sub-
/// problems. The bin-packing instances chosen here exhibit both:
/// random destroys produce diverse incumbents, and each
/// improvement on a 3-bin load tightens what every sibling can
/// accept on its next iteration.
Future<void> _benchCooperativeLns(
    String label, Future<Problem> Function() build) async {
  final portfolio = await _runCoopLnsMedian(build, cooperative: false);
  final cooperative = await _runCoopLnsMedian(build, cooperative: true);
  print(label);
  print('  ${_formatCoopLns('portfolio  ', portfolio)}');
  print('  ${_formatCoopLns('cooperative', cooperative)}');
}

Future<_BenchCoopLnsResult> _runCoopLnsMedian(
  Future<Problem> Function() build, {
  required bool cooperative,
  int workerCount = 3,
  int warmup = 1,
  int reps = 3,
  int iterationBudget = 80,
  double destroyFraction = 0.5,
  List<int> seeds = const [1, 2, 3],
}) async {
  // `lnsMinimizeInIsolates` takes a `Problem Function()` (sync).
  // Adapt the async builder by awaiting once per rep, then handing
  // the assembled Problem to the runner via a captured closure.
  // Each rep builds a fresh Problem so per-iteration state is
  // independent. The 0.5 destroy fraction + 80-iteration budget
  // chosen so that each worker actually accepts several
  // improvements during the run — otherwise there's nothing for
  // the cooperative broadcast to share and the two flag values
  // look identical.
  Future<LnsParallelResult> solveRep() async {
    final p = await build();
    return lnsMinimizeInIsolates(
      () => p,
      'maxLoad',
      workerCount: workerCount,
      policyBuilder: () => LnsPolicy.random(fraction: destroyFraction),
      iterationBudget: iterationBudget,
      seeds: seeds,
      cooperative: cooperative,
    );
  }

  for (var i = 0; i < warmup; i++) {
    await solveRep();
  }
  final times = <int>[];
  num? finalObj;
  late LnsStats bestStats;
  for (var i = 0; i < reps; i++) {
    final sw = Stopwatch()..start();
    final result = await solveRep();
    sw.stop();
    times.add(sw.elapsedMicroseconds);
    if (i == 0) {
      bestStats = result.bestResult.stats;
      finalObj = result.bestResult.stats.finalObjective;
    } else {
      // Track the best objective seen across reps for the printed
      // value (variance across isolate runs can shift it).
      final obj = result.bestResult.stats.finalObjective;
      if (obj != null && (finalObj == null || obj < finalObj)) {
        finalObj = obj;
      }
    }
  }
  times.sort();
  return _BenchCoopLnsResult(
    finalObjective: finalObj,
    medianMicros: times[times.length ~/ 2],
    bestStats: bestStats,
    workerCount: workerCount,
  );
}

String _formatCoopLns(String tag, _BenchCoopLnsResult r) {
  final objTag =
      r.finalObjective == null ? 'NO SOLUTION' : 'obj=${r.finalObjective}';
  final core = 'workers:${r.workerCount} '
      'it:${r.bestStats.iterations} '
      'acc:${r.bestStats.accepts} '
      'rej:${r.bestStats.rejects}';
  return '$tag  ${objTag.padRight(11)}  '
      '${r.medianMicros.toString().padLeft(8)} µs  $core';
}

class _BenchCoopLnsResult {
  _BenchCoopLnsResult({
    required this.finalObjective,
    required this.medianMicros,
    required this.bestStats,
    required this.workerCount,
  });
  final num? finalObjective;
  final int medianMicros;
  final LnsStats bestStats;
  final int workerCount;
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

/// Clean-room implementation of the dart_csp solver core.
///
/// The algorithms in this file follow textbook descriptions from:
///   * Russell & Norvig, *Artificial Intelligence: A Modern Approach*
///     (3rd ed.), Chapter 6 — Constraint Satisfaction Problems.
///   * Mackworth, "Consistency in networks of relations",
///     Artificial Intelligence 8(1), 1977 — AC-3.
///   * Minton, Johnston, Philips & Laird, "Minimizing conflicts: a
///     heuristic repair method for constraint satisfaction and
///     scheduling problems", Artificial Intelligence 58, 1992 —
///     Min-Conflicts.
///
/// This file was written from scratch using only those references.
/// No prior implementation of these algorithms in this repository
/// was consulted, and no external implementation was referenced —
/// in particular, neither the upstream `PrajitR/jusCSP` project nor
/// its `csp.js`.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'lcg/analyze.dart';
import 'lcg/atom.dart';
import 'lcg/explain.dart';
import 'types.dart';

export 'lcg/analyze.dart';
export 'lcg/atom.dart';
export 'lcg/explain.dart';

/// Public solver entry points. Signatures are dictated by callers
/// inside [Problem] (see `problem.dart`); they must not change.
class CSP {
  CSP._();

  /// Holds the [SolverStats] from the most recent backtracking solve
  /// (single-solution or stream). Reset at the start of every solve.
  /// Null before any solve has been issued.
  static SolverStats? lastStats;

  /// Snapshot of the LCG implication trail from the most recent
  /// [solveWithLcg] call. Captured immediately before the engine is
  /// discarded; remains valid after the solve returns. Null when no
  /// LCG-enabled solve has run yet, or when the last solve was a
  /// non-LCG entry point.
  ///
  /// On a successful solve the trail covers every prune that survived
  /// to the solution; on an unsatisfiable solve the trail is empty
  /// (every prune was rolled back as the search tree was exhausted).
  /// Intended for tests and tooling; not part of the stable public API.
  static List<ImplicationEntry>? lastImplicationTrail;

  /// Backtracking search for one satisfying assignment.
  /// Returns a `Map<String, dynamic>` on success or the literal
  /// `'FAILURE'` if the problem has no solution.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to full arc/generalized-arc consistency. See [ConsistencyLevel].
  static Future<dynamic> solve(CspProblem csp,
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    final solution = await engine.findOne();
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    return solution ?? 'FAILURE';
  }

  /// Backtracking enumeration of every distinct satisfying
  /// assignment. The stream is lazy: each next solution is computed
  /// only when a listener pulls it.
  ///
  /// [lastStats] is populated once the stream is fully consumed (or
  /// cancelled by the listener) with the cumulative engine counters
  /// for the run.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to full arc/generalized-arc consistency. See [ConsistencyLevel].
  static Stream<Map<String, dynamic>> solveAll(CspProblem csp,
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async* {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    try {
      yield* engine.findAll();
    } finally {
      sw.stop();
      engine.stats.elapsedMicros = sw.elapsedMicroseconds;
      lastStats = engine.stats;
    }
  }

  /// Backtracking search with Lazy Clause Generation (LCG)
  /// bookkeeping enabled. **Experimental.** M1 ships the atom
  /// encoding and parallel implication trail; the return contract is
  /// identical to [solve] — same `Map<String, dynamic>` on success
  /// / `'FAILURE'` on failure, same propagation. The first-UIP
  /// learning loop and per-propagator explanation companions arrive
  /// in M2 / M3 (see `LCG_PLAN.md`).
  ///
  /// Internally this enables `_BacktrackEngine.enableLcg`, which
  /// causes every domain prune to append an [ImplicationEntry] to a
  /// trail parallel to the engine's existing domain trail. The trail
  /// is invisible to callers and pays zero cost on solves that don't
  /// use this entry point.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to full arc/generalized-arc consistency.
  static Future<dynamic> solveWithLcg(CspProblem csp,
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      int? learnedClauseCap}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        consistency: consistency,
        cancelToken: cancelToken,
        enableLcg: true,
        learnedClauseCap: learnedClauseCap);
    final sw = Stopwatch()..start();
    final solution = await engine.findOne();
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    lastImplicationTrail = engine.implicationTrailSnapshot;
    return solution ?? 'FAILURE';
  }

  /// Local-search solver (Minton et al., 1992). Returns the first
  /// repaired assignment found within [maxSteps], or `'FAILURE'`
  /// otherwise. Failure here does not entail unsatisfiability.
  ///
  /// Pass [seed] for reproducible runs (the initial random
  /// assignment and the random tie-breaking are otherwise driven
  /// by an unseeded RNG).
  ///
  /// On return, [lastStats] holds the wall-clock time and the
  /// number of local-search iterations that ran. The
  /// backtracking-specific counters (`decisions`, `backtracks`,
  /// `propagations`, ...) are `0` since local search uses none of
  /// those mechanisms.
  static Future<dynamic> solveWithMinConflicts(CspProblem csp,
      {int maxSteps = 1000, int? seed, CancellationToken? cancelToken}) async {
    _validate(csp);
    final runner =
        _MinConflictsRunner(csp, seed: seed, cancelToken: cancelToken);
    final sw = Stopwatch()..start();
    final solution = await runner.run(maxSteps);
    sw.stop();
    lastStats = SolverStats(
      iterations: runner.stepsRun,
      elapsedMicros: sw.elapsedMicroseconds,
    );
    return solution ?? 'FAILURE';
  }

  /// Backtracking search with Luby restart and randomized value
  /// ordering. On hard instances where chronological backtracking
  /// gets trapped early, restarting from the root with a different
  /// LCV tie-break order can find a solution dramatically faster.
  ///
  /// Each restart attempt has a backtrack budget of
  /// `scale × luby(i)` for attempt `i = 1, 2, ...`. The Luby sequence
  /// is `1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, …` — universal
  /// in the Luby-Sinclair-Zuckerman (1993) sense.
  ///
  /// Returns:
  ///   - a `Map<String, dynamic>` on first success;
  ///   - the literal `'FAILURE'` if some attempt completes its
  ///     budget AND was not aborted — i.e. the search exhausted the
  ///     tree, proving the problem infeasible;
  ///   - the literal `'FAILURE'` after [maxRestarts] attempts if every
  ///     attempt was budget-aborted without exhausting the tree.
  ///
  /// Pass [seed] for reproducible runs. Pass [consistency] to choose
  /// the propagation strength applied during each restart attempt.
  static Future<dynamic> solveWithRestarts(
    CspProblem csp, {
    int scale = 100,
    int? maxRestarts,
    int? seed,
    bool useDomWdeg = false,
    bool useVsids = false,
    bool useImpact = false,
    bool useLastConflict = false,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    CancellationToken? cancelToken,
    bool enableConflictBackjumping = false,
  }) async {
    _validate(csp);
    final rng = Random(seed);
    for (var i = 1;; i++) {
      if (cancelToken?.isCancelled ?? false) return 'FAILURE';
      if (maxRestarts != null && i > maxRestarts) return 'FAILURE';
      final budget = _luby(i) * scale;
      final engine = _BacktrackEngine(csp,
          random: rng,
          maxBacktracks: budget,
          useDomWdeg: useDomWdeg,
          useVsids: useVsids,
          useImpact: useImpact,
          useLastConflict: useLastConflict,
          consistency: consistency,
          cancelToken: cancelToken,
          enableConflictBackjumping: enableConflictBackjumping);
      final solution = await engine.findOne();
      if (solution != null) return solution;
      // Cancelled mid-attempt: report FAILURE; the budget-abort path
      // and the cancel-abort path both set wasAborted, so disambiguate
      // by inspecting the token.
      if (cancelToken?.isCancelled ?? false) return 'FAILURE';
      if (!engine.wasAborted) return 'FAILURE'; // tree exhausted
    }
  }

  /// Backtracking search using the dom/wdeg variable heuristic
  /// (Boussemart, Hemery, Lecoutre, Sais, 2004) instead of plain MRV.
  /// Same return convention as [solve]. Useful when MRV ties cause
  /// noisy variable picks on structured problems.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to full arc/generalized-arc consistency.
  static Future<dynamic> solveWithDomWdeg(CspProblem csp,
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        useDomWdeg: true,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    final solution = await engine.findOne();
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    return solution ?? 'FAILURE';
  }

  /// Backtracking search using a VSIDS-style per-variable activity
  /// heuristic (Moskewicz, Madigan, Zhao, Zhang, Malik 2001 — the
  /// Chaff SAT solver), adapted to CSPs. On every propagation
  /// conflict, the activity of every variable in the failing
  /// constraint's scope is bumped by a magnitude that grows
  /// multiplicatively per conflict, so recent conflicts dominate.
  /// Variable selection minimizes `dom_size / (1 + activity)`,
  /// mirroring [solveWithDomWdeg]'s `dom/wdeg` shape — pre-conflict
  /// the ratio reduces to MRV; as activity accumulates the picker
  /// gravitates toward variables that have been near recent failures.
  ///
  /// Same return convention as [solve]. Useful on SAT-style instances
  /// and on problems whose "guilty" structure shifts over the course
  /// of search (where dom/wdeg's slow, monotone weights react less
  /// quickly than VSIDS's decaying bumps).
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to full arc/generalized-arc consistency.
  static Future<dynamic> solveWithActivity(CspProblem csp,
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        useVsids: true,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    final solution = await engine.findOne();
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    return solution ?? 'FAILURE';
  }

  /// Backtracking search using Impact-Based Search (Refalo 2004 —
  /// "Impact-Based Search Strategies for Constraint Programming",
  /// CP 2004). Each `(variable, value)` decision is rated by its
  /// *impact*: the fraction of the joint search space (product of
  /// remaining domain sizes) that propagation eliminated after the
  /// pin. A failed propagation has impact 1.0 (the entire branch is
  /// gone); a propagation that pins one variable and leaves
  /// everything else untouched has impact close to 0.
  ///
  /// Variable selection minimizes `dom_size / (1 + Σ_a I(v, a))`
  /// where the sum is over values currently in `v`'s domain. This
  /// mirrors [solveWithDomWdeg]'s `dom/wdeg` and
  /// [solveWithActivity]'s `dom / (1 + activity)` shapes — before any
  /// impact is observed the score reduces to MRV; as impacts
  /// accumulate the picker gravitates toward variables whose values
  /// have been historically high-pruning.
  ///
  /// Same return convention as [solve]. Useful on instances where
  /// dom/wdeg's slow weights and VSIDS's conflict-scoped bumps both
  /// miss structure that *successful* propagation reveals — IBS
  /// learns from every decision, not just failures.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to full arc/generalized-arc consistency.
  static Future<dynamic> solveWithImpact(CspProblem csp,
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        useImpact: true,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    final solution = await engine.findOne();
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    return solution ?? 'FAILURE';
  }

  /// Backtracking search with **Last-Conflict reasoning** (Lecoutre
  /// 2009 — "Reasoning from last conflict(s) in constraint
  /// programming", Artificial Intelligence 173) layered on top of
  /// the chosen underlying picker. After every propagation failure,
  /// the engine records the variable being pinned at the failure
  /// point. The next variable picked is that recorded variable (if
  /// still unassigned) instead of whatever the underlying heuristic
  /// would have chosen — focusing the search on the conflict cause.
  ///
  /// Pass [useDomWdeg], [useVsids], or [useImpact] to choose the
  /// underlying picker (all default to false, in which case LC
  /// composes with plain MRV). When the recorded variable becomes
  /// assigned (via propagation or via the decision pin) the picker
  /// falls through to the underlying heuristic.
  ///
  /// Lecoutre's experiments show LC+dom/wdeg outperforming pure
  /// dom/wdeg on a wide range of structured benchmarks; the same
  /// composition is the canonical deployment shape here too.
  ///
  /// Same return convention as [solve]. Pass [consistency] to
  /// choose the propagation strength; defaults to full
  /// arc/generalized-arc consistency.
  static Future<dynamic> solveWithLastConflict(CspProblem csp,
      {bool useDomWdeg = false,
      bool useVsids = false,
      bool useImpact = false,
      ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        useDomWdeg: useDomWdeg,
        useVsids: useVsids,
        useImpact: useImpact,
        useLastConflict: true,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    final solution = await engine.findOne();
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    return solution ?? 'FAILURE';
  }

  /// Integrated branch-and-bound. Returns the assignment that
  /// [minimizing] (or maximizes) the value of [objVar], or `'FAILURE'`
  /// if no feasible assignment exists.
  ///
  /// Unlike the classic restart-tightening formulation, the bound is
  /// tightened *inside* the recursive search: each improving leaf
  /// becomes the new incumbent, the objective's domain is permanently
  /// pruned to strictly-improving values (and every existing trail
  /// snapshot for that variable is re-filtered in place so rollback
  /// can't reintroduce stale values), and the search continues from
  /// the same point. This avoids the per-improvement restart cost.
  ///
  /// Same SolverStats accounting as [solve]; populated into
  /// [lastStats] on completion. Pass [consistency] to choose the
  /// propagation strength applied at every node of the search.
  static Future<dynamic> solveOptimal(CspProblem csp, String objVar,
      {required bool minimizing,
      bool useDomWdeg = false,
      bool useVsids = false,
      bool useImpact = false,
      bool useLastConflict = false,
      ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    _validate(csp);
    final engine = _BacktrackEngine(csp,
        useDomWdeg: useDomWdeg,
        useVsids: useVsids,
        useImpact: useImpact,
        useLastConflict: useLastConflict,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping);
    final sw = Stopwatch()..start();
    final solution = await engine.findOptimal(objVar, minimizing: minimizing);
    sw.stop();
    engine.stats.elapsedMicros = sw.elapsedMicroseconds;
    lastStats = engine.stats;
    return solution ?? 'FAILURE';
  }
}

/// Luby sequence (Luby, Sinclair & Zuckerman, 1993). `luby(1) = 1`,
/// `luby(2) = 1`, `luby(3) = 2`, `luby(4) = 1`, ... universal restart
/// schedule.
int _luby(int i) {
  // Iterative form of the classical recursion:
  //   luby(i) = 2^(k-1)                              if i == 2^k - 1
  //   luby(i) = luby(i - 2^(k-1) + 1)                if 2^(k-1) <= i < 2^k - 1
  while (true) {
    var k = 1;
    while ((1 << k) - 1 < i) {
      k++;
    }
    if ((1 << k) - 1 == i) return 1 << (k - 1);
    i = i - (1 << (k - 1)) + 1;
  }
}

void _validate(CspProblem csp) {
  for (final entry in csp.variables.entries) {
    if (entry.value.isEmpty) {
      throw ArgumentError(
          "Variable '${entry.key}' has an empty initial domain.");
    }
  }
}

Map<String, List<NaryConstraint>> _indexNaryByVar(List<NaryConstraint> all) {
  final out = <String, List<NaryConstraint>>{};
  for (final c in all) {
    for (final v in c.vars) {
      out.putIfAbsent(v, () => <NaryConstraint>[]).add(c);
    }
  }
  return out;
}

/// One unit of work on the GAC propagation queue: re-evaluate the
/// domain of [v] with respect to n-ary constraint [c].
class _GacTask {
  _GacTask(this.v, this.c);
  final String v;
  final NaryConstraint c;

  @override
  bool operator ==(Object other) =>
      other is _GacTask && other.v == v && identical(other.c, c);

  @override
  int get hashCode => Object.hash(v, identityHashCode(c));
}

/// Maximum span (max - min + 1) for a variable to qualify as bitset-
/// backed. Above this — provided the input is still contiguous-
/// ascending `int` — we use [_IntervalRep] instead. Beyond that
/// (non-contiguous, mixed types, etc.) we fall back to [_ListRep].
const int _bitsetMaxSpan = 1024;

/// Internal domain representation used by [_BacktrackEngine] and the
/// specialized propagators. Three variants:
///
///   * [_BitsetRep]   — `Uint64List` + integer offset. Used when the
///     initial domain is a strictly-ascending list of `int`s whose
///     span fits within [_bitsetMaxSpan]. O(1) membership; O(N/64)
///     filter.
///   * [_IntervalRep] — just `(min, max)`. Used when the initial
///     domain is a contiguous-ascending `int` range with span
///     `> _bitsetMaxSpan` (scheduling-style horizons, range
///     variables). O(1) membership / length / bounds; [filter]
///     stays as [_IntervalRep] when no interior holes are created,
///     otherwise promotes to [_BitsetRep] (if the resulting span
///     fits) or [_ListRep].
///   * [_ListRep]     — wraps a `List<dynamic>`. Used for every
///     other domain (mixed types, strings, non-monotonic ints,
///     non-contiguous ints with span `> _bitsetMaxSpan`).
///
/// All operations are non-mutating: [filter] returns a new instance
/// so the original is safe to retain on the engine's trail.
abstract class _DomainRep {
  int get length;
  bool get isEmpty;
  bool get isNotEmpty;

  /// The "first" value in iteration order — for bitset reps this is
  /// the smallest integer in the set; for list reps it is the first
  /// list element. Must only be called when [isNotEmpty].
  dynamic get first;

  /// Lazy iteration. For bitset reps this yields values in ascending
  /// order (which matches the list-order of the original ascending
  /// `addVariable` input, so observable behavior is unchanged).
  Iterable<dynamic> get values;

  /// A `List<dynamic>` view. For [_ListRep] this is the underlying
  /// list itself (no allocation). For [_BitsetRep] this allocates a
  /// fresh list each call.
  List<dynamic> get asList;

  /// `true` iff [v] is in the domain. O(1) for [_BitsetRep] when
  /// `v` is an `int`; O(n) for [_ListRep].
  bool contains(dynamic v);

  /// Returns a new [_DomainRep] containing only the values for which
  /// [keep] returns true.
  _DomainRep filter(bool Function(dynamic) keep);
}

class _ListRep implements _DomainRep {
  _ListRep(this._list);
  final List<dynamic> _list;

  @override
  int get length => _list.length;
  @override
  bool get isEmpty => _list.isEmpty;
  @override
  bool get isNotEmpty => _list.isNotEmpty;
  @override
  dynamic get first => _list.first;
  @override
  Iterable<dynamic> get values => _list;
  @override
  List<dynamic> get asList => _list;
  @override
  bool contains(dynamic v) => _list.contains(v);
  @override
  _DomainRep filter(bool Function(dynamic) keep) {
    final kept = <dynamic>[
      for (final v in _list)
        if (keep(v)) v
    ];
    return _ListRep(kept);
  }
}

class _BitsetRep implements _DomainRep {
  _BitsetRep(this._bits, this._offset, this._span);

  /// Each bit corresponds to one integer in `[offset, offset + span)`;
  /// bit `i` is set iff `offset + i` is in the domain.
  final Uint64List _bits;
  final int _offset;
  final int _span;

  @override
  int get length {
    var n = 0;
    for (var w = 0; w < _bits.length; w++) {
      n += _popcount64(_bits[w]);
    }
    return n;
  }

  @override
  bool get isEmpty {
    for (var w = 0; w < _bits.length; w++) {
      if (_bits[w] != 0) return false;
    }
    return true;
  }

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  dynamic get first {
    for (var w = 0; w < _bits.length; w++) {
      final word = _bits[w];
      if (word != 0) {
        // Lowest set bit index within the word.
        return _offset + (w << 6) + _trailingZeros64(word);
      }
    }
    throw StateError('_BitsetRep.first called on empty rep');
  }

  @override
  Iterable<dynamic> get values sync* {
    for (var w = 0; w < _bits.length; w++) {
      var word = _bits[w];
      while (word != 0) {
        final tz = _trailingZeros64(word);
        yield _offset + (w << 6) + tz;
        // Clear the lowest set bit.
        word &= word - 1;
      }
    }
  }

  @override
  List<dynamic> get asList => values.toList();

  @override
  bool contains(dynamic v) {
    if (v is! int) return false;
    final i = v - _offset;
    if (i < 0 || i >= _span) return false;
    return (_bits[i >> 6] & (1 << (i & 63))) != 0;
  }

  @override
  _DomainRep filter(bool Function(dynamic) keep) {
    final out = Uint64List(_bits.length);
    for (var w = 0; w < _bits.length; w++) {
      var word = _bits[w];
      var kept = 0;
      while (word != 0) {
        final tz = _trailingZeros64(word);
        final bit = 1 << tz;
        final value = _offset + (w << 6) + tz;
        if (keep(value)) kept |= bit;
        word &= word - 1;
      }
      out[w] = kept;
    }
    return _BitsetRep(out, _offset, _span);
  }
}

/// Range-encoded domain rep. Stores just `(min, max)`; the domain is
/// every integer `v` with `min <= v <= max`. Used for contiguous-int
/// domains whose span exceeds [_bitsetMaxSpan] — i.e., the scheduling
/// horizons that would otherwise allocate an enormous `List<dynamic>`.
///
/// [filter] keeps the rep as [_IntervalRep] when the predicate keeps
/// a contiguous prefix/suffix (and possibly nothing else inside the
/// retained range). When the predicate creates *interior* holes the
/// filter promotes the result to [_BitsetRep] (if the new span fits
/// within [_bitsetMaxSpan]) or [_ListRep].
///
/// An empty rep is canonically represented with `max < min`. Both
/// [_min] and [_max] are kept as `final` so the engine's trail is
/// safe to share across decisions.
class _IntervalRep implements _DomainRep {
  _IntervalRep(this._min, this._max);

  final int _min;
  final int _max;

  @override
  int get length => _max < _min ? 0 : _max - _min + 1;

  @override
  bool get isEmpty => _max < _min;

  @override
  bool get isNotEmpty => _max >= _min;

  @override
  dynamic get first {
    if (_max < _min) {
      throw StateError('_IntervalRep.first called on empty rep');
    }
    return _min;
  }

  @override
  Iterable<dynamic> get values sync* {
    for (var v = _min; v <= _max; v++) {
      yield v;
    }
  }

  @override
  List<dynamic> get asList => [for (var v = _min; v <= _max; v++) v];

  @override
  bool contains(dynamic v) {
    if (v is! int) return false;
    return v >= _min && v <= _max;
  }

  @override
  _DomainRep filter(bool Function(dynamic) keep) {
    // Single pass: find the kept min, the kept max, and whether the
    // retained set has interior holes. `lastKept` tracks the most
    // recent kept value so a gap of `> 1` flags a hole.
    var newMin = _max + 1; // empty sentinel until first kept value
    var newMax = _min - 1;
    var holes = false;
    var lastKept = _min - 2; // < _min so first-kept never flags a hole
    for (var v = _min; v <= _max; v++) {
      if (keep(v)) {
        if (newMin > _max) newMin = v;
        if (lastKept >= _min && v - lastKept > 1) holes = true;
        newMax = v;
        lastKept = v;
      }
    }
    if (newMin > newMax) {
      // Empty. Canonical empty interval.
      return _IntervalRep(_min, _min - 1);
    }
    if (!holes) {
      return _IntervalRep(newMin, newMax);
    }
    // Promote.
    final span = newMax - newMin + 1;
    if (span <= _bitsetMaxSpan) {
      final bits = Uint64List((span + 63) >> 6);
      for (var v = newMin; v <= newMax; v++) {
        if (keep(v)) {
          final i = v - newMin;
          bits[i >> 6] |= 1 << (i & 63);
        }
      }
      return _BitsetRep(bits, newMin, span);
    }
    final list = <dynamic>[
      for (var v = newMin; v <= newMax; v++)
        if (keep(v)) v,
    ];
    return _ListRep(list);
  }
}

/// Population count for a single 64-bit word. Dart `int` is 64-bit on
/// 64-bit platforms; on the web (JS) it is double-backed but the
/// engine is unused there for this library.
int _popcount64(int x) {
  // SWAR popcount.
  x = x - ((x >> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
  return ((x * 0x0101010101010101) >> 56) & 0x7F;
}

/// Count of trailing zero bits in a non-zero 64-bit word.
int _trailingZeros64(int x) {
  // De Bruijn sequence approach; works for non-zero inputs.
  // Isolate the lowest set bit, then use SWAR popcount on (bit - 1).
  final isolated = x & -x;
  return _popcount64(isolated - 1);
}

/// Classifies an input domain for the rep dispatcher. The variants
/// correspond to the three concrete [_DomainRep] implementations.
sealed class _RepClass {
  const _RepClass();
}

class _BitsetClass extends _RepClass {
  const _BitsetClass(this.offset, this.span);
  final int offset;
  final int span;
}

class _IntervalClass extends _RepClass {
  const _IntervalClass(this.lo, this.hi);
  final int lo;
  final int hi;
}

class _ListClass extends _RepClass {
  const _ListClass();
}

/// Classify [domain] for rep dispatch. Walks the list once; in order
/// of preference:
///
///   * strictly-ascending `int` list with span `<= _bitsetMaxSpan` →
///     [_BitsetClass]
///   * contiguous-ascending `int` list with span `> _bitsetMaxSpan`
///     (i.e., a true integer range) → [_IntervalClass]
///   * everything else → [_ListClass]
///
/// Bitset dominates interval on small contiguous int domains because
/// arbitrary-predicate filters stay as bitset (no promotion); for
/// large contiguous int domains interval is the only practical
/// option since materializing a `Uint64List` larger than 1024 bits
/// per variable becomes wasteful.
_RepClass _classifyDomain(List<dynamic> domain) {
  if (domain.isEmpty) return const _ListClass();
  if (domain.first is! int) return const _ListClass();
  var prev = domain.first as int;
  var contiguous = true;
  for (var i = 1; i < domain.length; i++) {
    final v = domain[i];
    if (v is! int) return const _ListClass();
    if (v <= prev) return const _ListClass(); // not strictly ascending
    if (v != prev + 1) contiguous = false;
    prev = v;
  }
  final lo = domain.first as int;
  final hi = domain.last as int;
  final span = hi - lo + 1;
  if (span <= _bitsetMaxSpan) return _BitsetClass(lo, span);
  // Span > _bitsetMaxSpan and the input is still ascending int. The
  // interval rep needs the domain to be the full contiguous range.
  // If it's ascending-with-holes (e.g. `[0, 2, 4, ..., 2N]`), neither
  // bitset (span too big) nor interval (gaps) fits — fall back to list.
  if (!contiguous) return const _ListClass();
  return _IntervalClass(lo, hi);
}

/// Build the initial [_DomainRep] for a variable based on
/// [_classifyDomain]'s verdict.
_DomainRep _initialDomainRep(List<dynamic> domain) {
  final klass = _classifyDomain(domain);
  switch (klass) {
    case _BitsetClass(:final offset, :final span):
      final bits = Uint64List((span + 63) >> 6);
      for (final v in domain) {
        final i = (v as int) - offset;
        bits[i >> 6] |= 1 << (i & 63);
      }
      return _BitsetRep(bits, offset, span);
    case _IntervalClass(:final lo, :final hi):
      return _IntervalRep(lo, hi);
    case _ListClass():
      return _ListRep(List<dynamic>.from(domain));
  }
}

/// One entry on the engine's trail. `oldRep` is the value to restore
/// on rollback; `cause` is the constraint that produced the mutation
/// (only consulted by CBJ to compute conflict causes; null for
/// decision-site mutations).
class _TrailEntry {
  const _TrailEntry(this.varName, this.oldRep, this.cause);
  final String varName;
  final _DomainRep oldRep;
  final Object? cause;
}

/// Sealed return type for the CBJ search helpers. Plain backtracking
/// uses `Map<String, dynamic>?` directly; CBJ needs to distinguish
/// "solution found", "subtree exhausted with no jump target" (the
/// caller should try its next candidate), and "backjump past me to
/// this earlier depth" (the caller should skip its remaining
/// candidates and propagate the jump further up).
sealed class _SearchResult {
  const _SearchResult();
}

class _Solution extends _SearchResult {
  const _Solution(this.assignment);
  final Map<String, dynamic> assignment;
}

class _Exhausted extends _SearchResult {
  const _Exhausted();
}

/// Carries the jump target (`targetDepth`) and the residual conflict
/// set (`conflict`) that the receiving frame should merge into its
/// own conflict set when the jump lands there.
class _Backjump extends _SearchResult {
  const _Backjump(this.targetDepth, this.conflict);
  final int targetDepth;
  final Set<String> conflict;
}

/// Sealed return type for the LCG search helper [_searchOneLcg].
/// Mirrors [_SearchResult] but the backjump variant carries only a
/// decision-level target — no conflict set is needed because the
/// learned clause (already posted into the constraint store before
/// the signal is emitted) does the unit-prop work after re-propagation
/// at the landing frame.
sealed class _LcgResult {
  const _LcgResult();
}

class _LcgSolution extends _LcgResult {
  const _LcgSolution(this.assignment);
  final Map<String, dynamic> assignment;
}

class _LcgExhausted extends _LcgResult {
  const _LcgExhausted();
}

class _LcgBackjump extends _LcgResult {
  const _LcgBackjump(this.targetLevel);
  final int targetLevel;
}

class _BacktrackEngine {
  _BacktrackEngine(this._csp,
      {this.random,
      this.maxBacktracks,
      this.useDomWdeg = false,
      this.useVsids = false,
      this.useImpact = false,
      this.useLastConflict = false,
      this.consistency = ConsistencyLevel.arcConsistency,
      this.cancelToken,
      this.enableConflictBackjumping = false,
      this.enableLcg = false,
      int? learnedClauseCap}) {
    for (final entry in _csp.variables.entries) {
      _domains[entry.key] = _initialDomainRep(entry.value);
    }
    for (final arc in _csp.constraints) {
      _arcsFromHead.putIfAbsent(arc.head, () => <BinaryConstraint>[]).add(arc);
    }
    _csp.naryIndex ??= _indexNaryByVar(_csp.naryConstraints);
    if (learnedClauseCap != null && learnedClauseCap > 0) {
      _forgetThreshold = learnedClauseCap;
    }
  }

  /// When non-null, used to randomize LCV tie-breaks. Enables
  /// restart-style diversification.
  final Random? random;

  /// When non-null, the engine aborts (sets [wasAborted]) once it has
  /// rolled back this many leaf failures. Caller distinguishes
  /// "tree exhausted" (search returned null and not aborted) from
  /// "ran out of budget" (search returned null and aborted).
  final int? maxBacktracks;

  /// When true, use the dom/wdeg variable heuristic (Boussemart et
  /// al., 2004) instead of plain MRV. Constraints that cause domain
  /// wipeouts gain weight, biasing future variable selection toward
  /// the "guilty" parts of the problem.
  final bool useDomWdeg;

  /// When true, use a VSIDS-style (Variable State Independent
  /// Decaying Sum, Moskewicz et al. 2001) per-variable activity
  /// heuristic. On every propagation conflict, the activity of every
  /// variable in the failing constraint's scope is bumped; the bump
  /// magnitude grows multiplicatively per conflict (equivalent to
  /// uniformly decaying every score by the inverse factor — the
  /// standard MiniSat trick), so recent conflicts dominate the score.
  ///
  /// Variable selection minimizes `dom_size / (1 + activity)`,
  /// mirroring [useDomWdeg]'s `dom_size / wdeg` shape — pre-conflict
  /// the ratio reduces to MRV; as activity accumulates the picker
  /// gravitates toward variables that have been near recent failures.
  ///
  /// If both [useVsids] and [useDomWdeg] are true, VSIDS takes
  /// precedence for picking; both bump tables are still updated so
  /// the choice of heuristic is independent of which conflicts were
  /// observed.
  final bool useVsids;

  /// When true, use Impact-Based Search (Refalo 2004 — "Impact-Based
  /// Search Strategies for Constraint Programming", CP 2004). After
  /// every decision (whether propagation succeeds or fails) the
  /// engine measures the **impact** of pinning `(var, value)`: the
  /// fraction of the joint search space (product of remaining domain
  /// sizes) that disappeared. A failed propagation contributes
  /// impact 1.0 — the entire branch is eliminated; a successful one
  /// contributes `1 - exp(logP_after - logP_before)`, clamped to
  /// `[0, 1]`. Per-`(var, value)` running means are stored.
  ///
  /// Variable selection minimizes `dom_size / (1 + Σ_a I(v, a))` —
  /// MRV when no impact has been observed; biased toward
  /// high-impact variables once they are. Mirrors the picker shape
  /// of [useDomWdeg] and [useVsids].
  ///
  /// When [useImpact] is on it takes precedence over [useVsids] and
  /// [useDomWdeg] for picking; the other heuristics' bump tables
  /// continue to update so the picker choice is independent of
  /// which conflicts were observed.
  final bool useImpact;

  /// When true, layer Lecoutre's **Last-Conflict reasoning** (2009 —
  /// "Reasoning from last conflict(s) in constraint programming",
  /// Artificial Intelligence 173) on top of whichever underlying
  /// picker is active ([useImpact] / [useVsids] / [useDomWdeg] /
  /// MRV). On every propagation failure, the engine records the
  /// variable that was being pinned ([_lastConflictVar]). The next
  /// time [_pickVariable] is called, if that variable is still
  /// unassigned the picker returns it directly — focusing the
  /// search on the conflict cause — instead of consulting the
  /// underlying heuristic. When the recorded variable is assigned
  /// (via propagation or via the decision pin), the picker falls
  /// through to the underlying heuristic.
  ///
  /// LC is a wrapper, not a sibling heuristic: it modifies the
  /// picker's variable choice without changing the score functions.
  /// Lecoutre's experiments show LC+dom/wdeg outperforming pure
  /// dom/wdeg on a wide range of structured benchmarks; the same
  /// composition is the canonical deployment shape here too.
  final bool useLastConflict;

  /// Propagation strength. [ConsistencyLevel.arcConsistency] (default)
  /// runs AC-3/GAC to a fixed point after each decision;
  /// [ConsistencyLevel.forwardChecking] revises each constraint
  /// touching the just-assigned variable exactly once and does not
  /// cascade reductions to constraints further out.
  final ConsistencyLevel consistency;

  /// When true, use Prosser's conflict-directed backjumping (CBJ,
  /// 1993) instead of chronological backtracking. After exhausting
  /// all candidate values for a decision variable with a non-empty
  /// conflict set, the search jumps directly to the deepest previously
  /// assigned variable that participated in some propagation failure
  /// for the current variable (skipping intermediate decisions that
  /// couldn't matter to those failures). Sound and complete; only the
  /// jump destination differs from chronological backtracking.
  ///
  /// The conflict set is approximated coarsely: any earlier-assigned
  /// variable that shares a constraint with any variable touched by
  /// a failed propagation is treated as a candidate cause. This is
  /// sound (always a superset of the true causes) but may
  /// over-approximate, which only weakens the jump distance, never
  /// correctness.
  final bool enableConflictBackjumping;

  /// When true, the engine maintains a parallel **implication trail**
  /// of [Atom]/[ImplicationReason] pairs alongside the domain trail,
  /// for use by Lazy Clause Generation (LCG) conflict analysis. M1
  /// just populates the trail; the first-UIP loop arrives in M2.
  /// Off by default — the bookkeeping is zero-cost when this flag
  /// is false. See `LCG_PLAN.md`.
  final bool enableLcg;

  /// LCG implication trail. Populated only when [enableLcg] is true.
  /// Each entry records the atom forced by a single prune plus the
  /// reason it was forced; the list is rolled back in lockstep with
  /// [_trail].
  final List<ImplicationEntry> _implicationTrail = [];

  /// LCG: the reason for the most recent propagation failure. Set by
  /// [_propagate] at every conflict site; non-null only when the
  /// failing propagator has a per-conflict explanation (currently
  /// just the clause propagator). Read by the LCG search loop
  /// immediately after a failed [_propagate] and used as the seed
  /// reason for [firstUipAnalyse]. Reset to null at the top of every
  /// [_propagate] call so a stale value from a previous run can't
  /// leak into the next conflict.
  ImplicationReason? _lastConflictReason;

  /// LCG: monotonic id source for synthetic intermediate atoms
  /// ([AtomInScc]). Each committed Hall-set atom gets a fresh id so two
  /// never collide on the implication trail (the analyser keys atoms by
  /// equality). Reset is unnecessary — the counter only grows and ids
  /// of rolled-back atoms are simply never reused.
  int _nextSyntheticId = 0;

  /// LCG: learned clauses posted dynamically during search, in
  /// insertion order (oldest first). Used by [_forgetIfNeeded] to drop
  /// the oldest half when the pool grows past [_forgetThreshold] and
  /// by [_implicationTrailSnapshot] consumers to distinguish learned
  /// clauses from the original problem's user-posted ones.
  final List<NaryConstraint> _learnedClauses = [];

  /// LCG forget threshold. When the learned-clause pool grows past
  /// this many clauses, the oldest half are dropped. Default chosen
  /// well above what the M2b pigeonhole-CNF acceptance benchmark
  /// needs (~50-200 clauses) while still bounding memory on harder
  /// instances. Exposed for tuning via [solveWithLcg]'s
  /// `learnedClauseCap:` kwarg.
  int _forgetThreshold = 1000;

  /// Number of decision pins committed so far (entries with
  /// `cause == null` on the domain trail). The implication trail
  /// stamps each entry with this counter so M2 conflict analysis
  /// can group antecedents by decision level. Incremented on every
  /// `_setDomain`/`_setDomainRep` with a null cause, decremented on
  /// rollback. Only updated when [enableLcg] is true.
  int _decisionLevel = 0;

  /// CBJ-only: maps each currently-assigned variable to the recursion
  /// depth at which it was assigned. Used by [_conflictCauseFromTrail]
  /// to determine which variables in the touched-by-propagation set
  /// are "earlier assignments" relative to the current decision.
  /// Stack-disciplined: each [_searchOneCbj] frame inserts on entry
  /// and removes on exit via a `try` / `finally`.
  final Map<String, int> _assignedAtDepth = HashMap<String, int>();

  /// CBJ-only: written by [_searchAllCbj] / [_searchOptimalCbj] when
  /// they want to backjump past the calling frame (async generators
  /// and `Future<void>` can't return a [_SearchResult] directly).
  /// The caller checks this slot after the recursive call returns and
  /// either consumes the signal (if it lands here) or re-propagates
  /// (if it should jump further). Always `null` outside an active CBJ
  /// search.
  int? _pendingBackjumpDepth;
  Set<String>? _pendingBackjumpConflict;

  /// When non-null, observed at each search checkpoint. A cancelled
  /// token sets [_aborted] and short-circuits the remaining recursion;
  /// the search returns null and the public solve entry point
  /// surfaces `'FAILURE'` (callers distinguish cancel from
  /// unsatisfiability by inspecting the token's [CancellationToken.isCancelled]).
  final CancellationToken? cancelToken;

  /// How many decisions may pass between cooperative event-loop
  /// yields. Picked empirically: low enough that a cancellation
  /// timer scheduled for ~50 ms is observed by the engine within
  /// tens of milliseconds on real CSPs (deep nodes take ms of
  /// propagation, so a 100-decision budget yields ~10×/s on hard
  /// instances), high enough that the yield itself (one microtask
  /// hop) stays well under 1% of search wall-clock on every
  /// benchmark in `benchmark/benchmark.dart`. The token, if any, is
  /// also polled on every decision (a cheap bool compare), so a
  /// token that gets cancelled while we are between yields is
  /// observed at the next decision.
  static const int _yieldEveryDecisions = 100;
  int _decisionsAtLastYield = 0;

  int _backtrackCount = 0;
  bool _aborted = false;
  bool get wasAborted => _aborted;

  /// Integrated B&B state. Populated only by [findOptimal]; null on
  /// satisfaction-only paths.
  String? _optObjVar;
  bool _optMinimizing = true;
  num? _optBound;
  Map<String, dynamic>? _optBest;

  /// Set by [_tightenObjectiveDomain] when neither the live objective
  /// domain nor any trail snapshot of it has improving values left.
  /// Search short-circuits — no further improvement is reachable.
  bool _optProven = false;

  /// Statistics collected during this engine's run.
  final SolverStats stats = SolverStats();

  /// Per-constraint failure weights for dom/wdeg. Keyed by identity so
  /// the maps work without overriding hashCode/equals on the constraint
  /// classes. Lazily populated; absent ⇒ weight 1.
  final Map<BinaryConstraint, int> _binWeights =
      HashMap(equals: identical, hashCode: identityHashCode);
  final Map<NaryConstraint, int> _naryWeights =
      HashMap(equals: identical, hashCode: identityHashCode);

  /// Per-clause mutable state for the two-watched-literal scheme in
  /// [_ClausePropagator]. Keyed by `ClauseSpec` identity; populated
  /// lazily on first propagation of each clause.
  ///
  /// **No rollback needed.** The watched-literal invariant — both
  /// watchers point to non-falsified literals — is monotone under
  /// the engine's trail semantics: backtracking only restores
  /// previously-removed values, so a literal that was non-falsified
  /// at a deeper assignment is also non-falsified at any shallower
  /// one. Watchers picked at any depth therefore stay valid as the
  /// engine unwinds, and we can skip trailing the per-clause state
  /// entirely.
  ///
  /// Also consulted by [_propagate]'s seeding loop: after a clause
  /// has been initialized, only the two watched literals' variables
  /// can wake it (the per-variable watch-list optimization). A
  /// reduction at any other variable in the clause's scope is
  /// filtered out before the propagator is even enqueued.
  final Map<ClauseSpec, _ClauseWatchState> _clauseWatchers =
      HashMap(equals: identical, hashCode: identityHashCode);

  void _bumpWeight(Object c) {
    if (c is BinaryConstraint) {
      _binWeights[c] = (_binWeights[c] ?? 1) + 1;
    } else if (c is NaryConstraint) {
      _naryWeights[c] = (_naryWeights[c] ?? 1) + 1;
    }
  }

  /// Per-variable VSIDS activity. Lazily populated; absent ⇒ 0.0.
  final Map<String, double> _varActivity = HashMap<String, double>();

  /// Current bump magnitude. Multiplicatively grows by `1 / decay`
  /// after each conflict — equivalent to decaying every existing
  /// activity by `decay`, but O(1) per conflict instead of O(|vars|).
  /// Standard MiniSat-style implementation.
  double _activityInc = 1.0;

  /// Decay factor; bumps grow by `1 / _activityDecay` per conflict.
  /// 0.95 is the canonical SAT-solver default and is a reasonable
  /// starting point for CSPs too.
  static const double _activityDecay = 0.95;

  /// When [_activityInc] exceeds this, rescale all activities and
  /// the increment by [_activityRescaleFactor] to prevent overflow.
  static const double _activityRescaleThreshold = 1e100;
  static const double _activityRescaleFactor = 1e-100;

  /// Called at every propagation-failure site to update conflict-
  /// driven heuristic state. Delegates to [_bumpWeight] when
  /// [useDomWdeg] is on, and bumps per-variable activities for every
  /// variable in [c]'s scope when [useVsids] is on. A no-op when
  /// neither flag is set.
  void _onConflict(Object c) {
    if (useDomWdeg) _bumpWeight(c);
    if (useVsids) _bumpActivityFor(c);
  }

  void _bumpActivityFor(Object c) {
    if (c is BinaryConstraint) {
      _bumpActivityVar(c.head);
      _bumpActivityVar(c.tail);
    } else if (c is NaryConstraint) {
      for (final v in c.vars) {
        _bumpActivityVar(v);
      }
    }
    _activityInc /= _activityDecay;
    if (_activityInc > _activityRescaleThreshold) _rescaleActivities();
  }

  void _bumpActivityVar(String v) {
    _varActivity[v] = (_varActivity[v] ?? 0.0) + _activityInc;
  }

  void _rescaleActivities() {
    for (final k in _varActivity.keys) {
      _varActivity[k] = _varActivity[k]! * _activityRescaleFactor;
    }
    _activityInc *= _activityRescaleFactor;
  }

  /// Impact-Based Search: per-`(variable, value)` running-mean impact
  /// in `[0, 1]`. Lazily populated; absent ⇒ no observation yet (the
  /// picker treats this as contribution 0 to its sum).
  ///
  /// Outer map keyed by variable name; inner map keyed by domain
  /// value (`dynamic` because domains may hold ints, strings, etc.).
  /// Updated by [_recordImpact] at every decision site of the six
  /// search loops when [useImpact] is on.
  final Map<String, Map<dynamic, double>> _impactMean =
      HashMap<String, Map<dynamic, double>>();

  /// Companion counter for [_impactMean]; the running mean is updated
  /// as `m' = m + (x - m) / n` where `n` is the post-increment count.
  final Map<String, Map<dynamic, int>> _impactCount =
      HashMap<String, Map<dynamic, int>>();

  /// Sum of `log(dom_size)` over every variable. Domains of size 1
  /// contribute 0 (`log(1) = 0`), so assigned variables drop out
  /// automatically. Called twice per decision when [useImpact] is on
  /// (before pinning, after propagation); each call is O(|vars|).
  double _logProductDomains() {
    var sum = 0.0;
    for (final dom in _domains.values) {
      final n = dom.length;
      if (n > 1) sum += log(n.toDouble());
    }
    return sum;
  }

  /// Update the running mean impact for `(v, a)` with the new
  /// observation `observed`. Standard incremental-mean formula —
  /// numerically stable and O(1) per update.
  void _recordImpact(String v, dynamic a, double observed) {
    final means = _impactMean.putIfAbsent(v, HashMap.new);
    final counts = _impactCount.putIfAbsent(v, HashMap.new);
    final n = (counts[a] ?? 0) + 1;
    counts[a] = n;
    final old = means[a] ?? 0.0;
    means[a] = old + (observed - old) / n;
  }

  /// Compute the observed impact for the just-tried decision and
  /// fold it into [_impactMean] / [_impactCount]. Called once per
  /// candidate from every search loop when [useImpact] is on.
  ///
  /// * Failed propagation (`ok == false`): impact 1.0 — the entire
  ///   subtree below this `(v, a)` was eliminated.
  /// * Successful propagation: impact is
  ///   `1 - exp(logAfter - logBefore)`, clamped to `[0, 1]`. This
  ///   is Refalo's definition of impact in log space — equivalent
  ///   to `1 - P_after / P_before` but numerically robust on
  ///   problems with very large initial product-of-domain-sizes.
  void _observeImpact(String v, dynamic a, double logBefore, bool ok) {
    if (!ok) {
      _recordImpact(v, a, 1.0);
      return;
    }
    final logAfter = _logProductDomains();
    var observed = 1.0 - exp(logAfter - logBefore);
    if (observed < 0.0) observed = 0.0;
    if (observed > 1.0) observed = 1.0;
    _recordImpact(v, a, observed);
  }

  /// Last-Conflict reasoning (Lecoutre 2009): name of the variable
  /// being pinned at the most recent propagation failure. Consulted
  /// by [_pickVariable] when [useLastConflict] is on; updated by
  /// every search variant's propagation-failure path. Null when no
  /// failure has been observed yet (or when the recorded variable
  /// has since been assigned).
  String? _lastConflictVar;

  // Upper bound on the size of the Cartesian product enumerated when
  // checking GAC support for a single value. Constraints whose free
  // (non-singleton) neighborhood would exceed this are left
  // unenforced for that revision; the backtracking layer remains
  // responsible for catching any resulting infeasibility.
  static const int _gacWorkBound = 4096;

  final CspProblem _csp;
  final Map<String, _DomainRep> _domains = {};
  final Map<String, List<BinaryConstraint>> _arcsFromHead = {};

  /// Single trail of domain mutations: append-only during forward
  /// propagation, popped in reverse on backtrack. Replaces the per-
  /// recursion-level deep snapshot of the full _domains map.
  ///
  /// Each entry carries the constraint that caused the mutation
  /// (`cause`): a [BinaryConstraint] for an AC-3 revise, a
  /// [NaryConstraint] for any GAC revise or specialized propagator
  /// reduction, or `null` for a decision-site assignment (the
  /// search loop directly committing a candidate value). The cause
  /// is only consulted by [_conflictCauseFromTrail] when CBJ is
  /// enabled; off-CBJ runs don't read it at all, so the additional
  /// reference per entry is amortized to noise.
  final List<_TrailEntry> _trail = [];

  Map<String, List<NaryConstraint>> get _naryIdx => _csp.naryIndex!;

  /// Record [varName]'s current domain on the trail and overwrite it
  /// with [newDom]. Every domain mutation must go through this method
  /// (or its rep-aware sibling [_setDomainRep]) so that
  /// [_trailRollback] can undo it.
  ///
  /// Accepts a `List<dynamic>` for caller convenience (the engine's
  /// own commit-singleton / binary-revise / generic-GAC paths build
  /// kept lists); the engine wraps with a rep matching the prior
  /// rep's kind when possible:
  ///
  ///   * Bitset-backed variable: rebuilds the `Uint64List` (cheap —
  ///     bounded `_bitsetMaxSpan`).
  ///   * Interval-backed variable: if [newDom] is contiguous
  ///     ascending the result stays as `_IntervalRep(newDom.first,
  ///     newDom.last)`; otherwise it promotes to bitset (if span
  ///     fits) or list. Callers iterate `dom.values` in ascending
  ///     order, so the contiguity check is just "no gap between
  ///     successive entries."
  ///   * List-backed variable: stays as `_ListRep`.
  ///
  /// Specialized propagators that already have a fresh `_DomainRep`
  /// from `_DomainRep.filter(predicate)` should call [_setDomainRep]
  /// instead — it bypasses the list re-wrap and lets a bitset or
  /// interval reduction stay in its native form end-to-end.
  void _setDomain(String varName, List<dynamic> newDom,
      {Object? cause, ImplicationReason? reason}) {
    final old = _domains[varName]!;
    final trailIdx = _trail.length;
    _trail.add(_TrailEntry(varName, old, cause));
    if (old is _BitsetRep) {
      final bits = Uint64List(old._bits.length);
      for (final v in newDom) {
        final i = (v as int) - old._offset;
        bits[i >> 6] |= 1 << (i & 63);
      }
      _domains[varName] = _BitsetRep(bits, old._offset, old._span);
    } else if (old is _IntervalRep) {
      _domains[varName] = _intervalFromKeptList(newDom);
    } else {
      _domains[varName] = _ListRep(newDom);
    }
    if (enableLcg) {
      _recordImplications(
          varName, old, _domains[varName]!, cause, trailIdx, reason);
    }
  }

  /// Wrap [newDom] (an ascending list of ints, as produced by the
  /// engine's revise loops over an interval-backed variable) into the
  /// most natural rep: `_IntervalRep` if contiguous, `_BitsetRep` if
  /// the resulting span fits, else `_ListRep`.
  _DomainRep _intervalFromKeptList(List<dynamic> newDom) {
    if (newDom.isEmpty) {
      // Canonical empty interval; engine treats it as a wipeout
      // either way.
      return _IntervalRep(0, -1);
    }
    final first = newDom.first as int;
    final last = newDom.last as int;
    final span = last - first + 1;
    if (newDom.length == span) {
      // Contiguous: every integer in [first, last] is present.
      return _IntervalRep(first, last);
    }
    if (span <= _bitsetMaxSpan) {
      final bits = Uint64List((span + 63) >> 6);
      for (final v in newDom) {
        final i = (v as int) - first;
        bits[i >> 6] |= 1 << (i & 63);
      }
      return _BitsetRep(bits, first, span);
    }
    return _ListRep(newDom);
  }

  /// Record [varName]'s current domain on the trail and overwrite it
  /// with the already-built [newRep]. Used by the specialized
  /// propagators whose reduction is naturally a value-predicate:
  /// `_DomainRep.filter(keep)` returns a new rep of the same kind as
  /// the source (bitset → bitset, list → list) without the
  /// intermediate `List<dynamic>` allocation that [_setDomain]
  /// requires.
  void _setDomainRep(String varName, _DomainRep newRep,
      {Object? cause, ImplicationReason? reason}) {
    final old = _domains[varName]!;
    final trailIdx = _trail.length;
    _trail.add(_TrailEntry(varName, old, cause));
    _domains[varName] = newRep;
    if (enableLcg) {
      _recordImplications(varName, old, newRep, cause, trailIdx, reason);
    }
  }

  /// Append [ImplicationEntry] records for the prune that just turned
  /// [old] into [newRep] for [varName]. Called from [_setDomain] and
  /// [_setDomainRep] only when [enableLcg] is true.
  ///
  /// Strategy: if the new rep is a singleton, emit a single
  /// `AtomEq(varName, survivor)` so decision pins read cleanly during
  /// conflict analysis. Otherwise emit one `AtomNe(varName, removed)`
  /// per removed value. Bounds-style atoms (`AtomLe` / `AtomGe`) are
  /// strictly more compact for interval prunes but the value-removal
  /// shape is uniformly sound and is what M2 conflict analysis works
  /// with; M3 propagator companions will produce the tighter bounds
  /// atoms where appropriate.
  ///
  /// Non-int domain values are silently skipped — atoms are
  /// integer-only by design (`LCG_PLAN.md` §1).
  ///
  /// When [explicitReason] is non-null the caller has computed a
  /// concrete [ImplicationReason] (typically a [ClauseReason] from
  /// the clause propagator's unit-prop path); use it directly.
  /// Otherwise fall back to the M1 inference: `cause == null` →
  /// [DecisionReason]; everything else → [UnknownReason]
  /// (placeholder until M3 ships per-propagator reasons).
  void _recordImplications(String varName, _DomainRep old, _DomainRep newRep,
      Object? cause, int trailIdx, ImplicationReason? explicitReason) {
    if (cause == null) _decisionLevel++;
    final reason = explicitReason ??
        (cause == null ? const DecisionReason() : const UnknownReason());
    if (newRep.length == 1) {
      final survivor = newRep.first;
      if (survivor is int) {
        _implicationTrail.add(ImplicationEntry(
          prunedAtom: AtomEq(varName, survivor),
          reason: reason,
          trailIndex: trailIdx,
          decisionLevel: _decisionLevel,
        ));
      }
      return;
    }
    for (final v in old.values) {
      if (v is! int) return; // non-int domain: skip the whole prune.
      if (!newRep.contains(v)) {
        _implicationTrail.add(ImplicationEntry(
          prunedAtom: AtomNe(varName, v),
          reason: reason,
          trailIndex: trailIdx,
          decisionLevel: _decisionLevel,
        ));
      }
    }
  }

  /// LCG: commit a synthetic intermediate [AtomInScc] onto the
  /// implication trail (M3-tighten, `LCG_PLAN.md` §3 task 1). Unlike a
  /// real prune this performs *no* domain mutation — the atom is a
  /// resolution bridge, not a domain literal. Its [ImplicationEntry]
  /// borrows the current domain-trail length as its `trailIndex` so the
  /// rollback in [_trailRollback] pops it in lockstep with the prunes
  /// that reference it (every entry with `trailIndex >= mark` is
  /// dropped, and a synthetic committed during a propagation round
  /// always has `trailIndex >= mark` for that round). Stamped with the
  /// current [_decisionLevel] so the analyser sees it at the conflict
  /// level.
  ///
  /// [antecedents] are the Hall set's defining absences (taken from the
  /// propagation-entry snapshot, so they never reference the
  /// just-committed sibling prunes). Returns the committed atom so the
  /// caller can reference it from the per-prune / conflict reasons.
  Atom _recordSyntheticScc(String repVar, List<Atom> antecedents) {
    final atom = AtomInScc(repVar, _nextSyntheticId++);
    _implicationTrail.add(ImplicationEntry(
      prunedAtom: atom,
      reason: AllDifferentReason(antecedents),
      trailIndex: _trail.length,
      decisionLevel: _decisionLevel,
    ));
    return atom;
  }

  int _trailMark() => _trail.length;

  /// Restore every domain that was mutated since [mark] to its
  /// pre-mutation value, then truncate the trail. Pops the
  /// implication trail in lockstep when [enableLcg] is true and
  /// decrements [_decisionLevel] once per popped decision-site entry
  /// so the decision-level counter stays consistent with the trail.
  void _trailRollback(int mark) {
    while (_trail.length > mark) {
      final last = _trail.length - 1;
      final e = _trail[last];
      _trail.removeAt(last);
      _domains[e.varName] = e.oldRep;
      if (enableLcg && e.cause == null) _decisionLevel--;
    }
    if (enableLcg) {
      while (_implicationTrail.isNotEmpty &&
          _implicationTrail.last.trailIndex >= mark) {
        _implicationTrail.removeLast();
      }
    }
  }

  /// Debug-only view of the LCG implication trail. Returns an empty
  /// list when [enableLcg] is false. Exposed for tests and future
  /// LCG components within the library; not part of the public API.
  List<ImplicationEntry> get implicationTrailSnapshot =>
      List<ImplicationEntry>.unmodifiable(_implicationTrail);

  /// Debug-only view of the current decision level. `0` ≡ root-level
  /// propagation. Exposed for tests; not part of the public API.
  int get currentDecisionLevel => _decisionLevel;

  /// LCG: build the [ClauseReason] for a clause-propagator conflict
  /// site. The propagator returns null when every literal in [spec]
  /// is currently falsified — i.e. each literal's underlying variable
  /// is pinned to the value that makes the literal false. The
  /// antecedent set is exactly those `(varName, falsifyingValue)`
  /// pairs translated into `AtomEq` atoms. M2b's first-UIP analyser
  /// resolves the working clause against this list while walking the
  /// implication trail backward.
  ImplicationReason _clauseConflictReason(ClauseSpec spec) {
    final atoms = spec.atoms != null
        ? <Atom>[for (final a in spec.atoms!) a.negate()]
        : <Atom>[
            for (final lit in spec.literals)
              AtomEq(lit.varName, lit.positive ? 0 : 1),
          ];
    return ClauseReason(atoms);
  }

  /// LCG: build the [AllDifferentReason] for a constraint-level
  /// allDifferent conflict (Hopcroft-Karp matching failure, m < n
  /// pigeonhole, or a domain-wipeout post-prune). The Hall set is
  /// the entire constraint scope — the matching needed every
  /// variable, so every variable's current absences contribute. M3a
  /// per-variable Hall-set extraction is reserved for the
  /// successful-propagate prunes; for an outright conflict we don't
  /// have a partial-matching state to read the SCCs off of.
  ImplicationReason _allDifferentConflictReason(List<String> vars) {
    final atoms = <Atom>[];
    for (final hName in vars) {
      final origDom = _csp.variables[hName];
      if (origDom == null) continue;
      final curDom = _domains[hName];
      if (curDom == null) continue;
      atoms.addAll(_domainShapeAntecedents(hName, origDom, curDom));
    }
    if (atoms.isEmpty) return const AllDifferentReason([]);
    // M3-tighten: collapse the whole conflicting scope into a single
    // synthetic [AtomInScc] so the first-UIP walk resolves through one
    // bridge atom instead of getting stuck on the coarse multi-variable
    // absence list. The bridge is committed at the conflict level; its
    // antecedents are the scope absences, which the analyser then
    // resolves further toward a single UIP.
    final scc = _recordSyntheticScc(vars.isEmpty ? '?' : vars.first, atoms);
    return AllDifferentReason([scc]);
  }

  /// LCG: build the [LinearBoundReason] for a constraint-level
  /// linear-arithmetic conflict (the bounds-consistency check
  /// reported infeasibility, or a domain-wipeout post-prune). The
  /// scope is the entire constraint — every variable's bounds
  /// contributed to the residual interval the conflict was checked
  /// against. Uses the same coarse `AtomNe`-per-absent-value shape
  /// as the per-prune reason.
  ImplicationReason _linearConflictReason(List<String> vars) {
    final atoms = <Atom>[];
    for (final hName in vars) {
      final origDom = _csp.variables[hName];
      if (origDom == null) continue;
      final curDom = _domains[hName];
      if (curDom == null) continue;
      atoms.addAll(_domainShapeAntecedents(hName, origDom, curDom));
    }
    return LinearBoundReason(atoms);
  }

  /// LCG: convert [atoms] (the disjunction emitted by
  /// [firstUipAnalyse]) into a [ClauseSpec]. Picks the boolean
  /// encoding when every atom is over a `{0, 1}` variable and maps
  /// cleanly to a boolean clause literal (cheaper per-prop eval; uses
  /// the same fast path as user-posted clauses); otherwise falls back
  /// to the atom-clause encoding (sets [ClauseSpec.atoms]).
  ///
  /// `AtomEq(v, 1)` / `AtomNe(v, 0)` map to `(v, positive=true)`;
  /// `AtomEq(v, 0)` / `AtomNe(v, 1)` map to `(v, positive=false)`.
  ///
  /// Returns null when [atoms] is empty.
  ClauseSpec? _learnedClauseToSpec(List<Atom> atoms) {
    if (atoms.isEmpty) return null;
    // First pass: try the boolean encoding (preferred for perf — the
    // boolean evaluator avoids the DomainView allocation that the
    // atom path needs per literal).
    final literals = <({String varName, bool positive})>[];
    final seen = <String>{};
    var allBoolean = true;
    for (final a in atoms) {
      bool? positive;
      if (a is AtomEq) {
        if (a.value == 1) {
          positive = true;
        } else if (a.value == 0) {
          positive = false;
        }
      } else if (a is AtomNe) {
        if (a.value == 0) {
          positive = true;
        } else if (a.value == 1) {
          positive = false;
        }
      }
      if (positive == null || !_isBooleanVariable(a.varName)) {
        allBoolean = false;
        break;
      }
      final key = '${a.varName}:$positive';
      if (seen.add(key)) {
        literals.add((varName: a.varName, positive: positive));
      }
    }
    if (allBoolean) {
      if (literals.isEmpty) return null;
      return ClauseSpec(literals: literals);
    }
    // Atom-clause path: keep every atom as-is (analyser already
    // deduplicates via its working-clause Set, so we don't dedupe
    // again here).
    return ClauseSpec(literals: const [], atoms: List<Atom>.from(atoms));
  }

  /// LCG: variables whose original declared domain is exactly
  /// `{0, 1}` (or a subset). Cached lazily because the test is per-
  /// variable and runs once per learned-clause-conversion attempt.
  final Map<String, bool> _isBooleanVarCache = HashMap<String, bool>();

  bool _isBooleanVariable(String v) {
    final cached = _isBooleanVarCache[v];
    if (cached != null) return cached;
    final dom = _csp.variables[v];
    if (dom == null) return _isBooleanVarCache[v] = false;
    for (final val in dom) {
      if (val != 0 && val != 1) return _isBooleanVarCache[v] = false;
    }
    return _isBooleanVarCache[v] = true;
  }

  /// LCG: post [spec] as a new learned clause into the engine's
  /// constraint store mid-search. Builds a [NaryConstraint] tagged
  /// with [spec], appends it to [_csp.naryConstraints] and to each
  /// participating variable's entry in [_naryIdx] (creating the entry
  /// when missing). The clause is recorded in [_learnedClauses] so
  /// the forget policy can drop it later.
  ///
  /// The clause's predicate is built by [_learnedClausePredicate] —
  /// the boolean shape iterates [ClauseSpec.literals], the atom shape
  /// iterates [ClauseSpec.atoms] and evaluates each atom against the
  /// assignment. Tagged constraints normally bypass the predicate at
  /// leaves, but having it in place keeps soundness as a belt-and-
  /// braces invariant if the dispatch flag ever gets lost.
  void _postLearnedClause(ClauseSpec spec) {
    // Dedupe vars: a clause may name the same variable in multiple
    // literals (e.g., `AtomEq(x, 1) ∨ AtomNe(x, 2)` over a > 2-domain).
    // The NaryConstraint's `vars` list and the `_naryIdx` entries
    // shouldn't double-count.
    final varSeen = <String>{};
    final vars = <String>[];
    if (spec.atoms != null) {
      for (final a in spec.atoms!) {
        if (varSeen.add(a.varName)) vars.add(a.varName);
      }
    } else {
      for (final lit in spec.literals) {
        if (varSeen.add(lit.varName)) vars.add(lit.varName);
      }
    }
    final c = NaryConstraint(
      vars: vars,
      clauseSpec: spec,
      predicate: _learnedClausePredicate(spec),
    );
    _csp.naryConstraints.add(c);
    final idx = _naryIdx;
    for (final v in vars) {
      idx.putIfAbsent(v, () => <NaryConstraint>[]).add(c);
    }
    _learnedClauses.add(c);
    stats.learnedClauses++;
  }

  /// Build a partial-assignment-tolerant predicate for the learned
  /// clause defined by [spec]. Tagged constraints normally bypass the
  /// predicate at leaves, but having it in place is belt-and-braces
  /// for soundness and supports the shared `_addNary` dispatch path.
  NaryPredicate _learnedClausePredicate(ClauseSpec spec) {
    if (spec.atoms != null) {
      final atoms = spec.atoms!;
      return (assn) {
        var anyUnknown = false;
        for (final a in atoms) {
          if (!assn.containsKey(a.varName)) {
            anyUnknown = true;
            continue;
          }
          final v = assn[a.varName];
          if (v is! int) return true; // non-int domain: bail safe.
          final entailed = switch (a) {
            AtomEq(:final value) => v == value,
            AtomNe(:final value) => v != value,
            AtomLe(:final value) => v <= value,
            AtomGe(:final value) => v >= value,
            AtomInScc() => throw StateError(
                'synthetic AtomInScc must never appear in a clause literal'),
          };
          if (entailed) return true;
        }
        return anyUnknown;
      };
    }
    final literals = spec.literals;
    return (assn) {
      var anyUnknown = false;
      for (final lit in literals) {
        if (!assn.containsKey(lit.varName)) {
          anyUnknown = true;
          continue;
        }
        if ((assn[lit.varName] == 1) == lit.positive) return true;
      }
      return anyUnknown;
    };
  }

  /// LCG: drop the oldest half of [_learnedClauses] when the pool
  /// exceeds [_forgetThreshold]. Removes the dropped constraints from
  /// [_csp.naryConstraints], [_naryIdx], and the clause-watcher side-
  /// table. Called after every successful learn so the pool is
  /// bounded in steady state.
  ///
  /// Watcher state for the dropped clauses is monotone-under-trail
  /// (`_clauseWatchers` invariants), so a watcher entry pointing into
  /// a no-longer-active clause is harmless even if the clause re-
  /// appears via a different code path later — but we drop the
  /// entries anyway to keep memory tight.
  void _forgetIfNeeded() {
    if (_learnedClauses.length <= _forgetThreshold) return;
    final dropCount = _learnedClauses.length ~/ 2;
    final dropped = _learnedClauses.sublist(0, dropCount);
    _learnedClauses.removeRange(0, dropCount);
    final droppedSet =
        HashSet<NaryConstraint>(equals: identical, hashCode: identityHashCode)
          ..addAll(dropped);
    _csp.naryConstraints.removeWhere(droppedSet.contains);
    final idx = _naryIdx;
    for (final entry in idx.entries) {
      entry.value.removeWhere(droppedSet.contains);
    }
    for (final c in dropped) {
      final spec = c.clauseSpec;
      if (spec != null) _clauseWatchers.remove(spec);
    }
    stats.forgottenClauses += dropped.length;
  }

  /// Singleton-arc-consistency preprocessing pass (Debruyne &
  /// Bessière, 1997 — algorithm SAC-1). For every `(variable,
  /// value)` pair currently in some domain, tentatively pins the
  /// variable to that value, runs propagation, and prunes the value
  /// if propagation fails. Re-runs the whole pass until a fixpoint
  /// (no value pruned in an iteration).
  ///
  /// Each tentative pin is rolled back through the standard trail
  /// so domains outside the SAC prunings are unchanged on return.
  /// Returns false if any domain is wiped (the constraint is
  /// SAC-infeasible at the root); true otherwise.
  ///
  /// Counted toward `stats.propagations` /
  /// `stats.binaryRevises` / `stats.naryRevises` via the trailing
  /// `_propagate` calls — no separate SAC counters. Conflict-driven
  /// heuristics ([useDomWdeg], [useVsids]) accumulate bumps for
  /// failures observed here too, which is intentional: SAC
  /// failures are real conflicts and informing the heuristic
  /// improves later search.
  bool _enforceSac() {
    while (true) {
      var anyChange = false;
      // Snapshot the key list so a domain replacement inside the
      // loop doesn't invalidate iteration. `_domains` keys never
      // change after construction, but `.toList()` is also a
      // defensive guard.
      final varNames = _domains.keys.toList();
      for (final v in varNames) {
        final dom = _domains[v]!;
        if (dom.length <= 1) continue;
        final values = dom.values.toList();
        final keep = <dynamic>[];
        for (final val in values) {
          final mark = _trailMark();
          _setDomain(v, <dynamic>[val]);
          final ok = _propagate(<String>[v]);
          _trailRollback(mark);
          if (ok) keep.add(val);
        }
        if (keep.length < values.length) {
          if (keep.isEmpty) return false;
          _setDomain(v, keep);
          anyChange = true;
        }
      }
      if (!anyChange) break;
    }
    return true;
  }

  /// Runs the initial root propagation, then, if the user requested
  /// [ConsistencyLevel.singletonArcConsistency], the SAC pass.
  /// Returns false if either step proves the problem infeasible.
  bool _seedAndPreprocess() {
    if (!_propagate(_domains.keys)) return false;
    if (consistency == ConsistencyLevel.singletonArcConsistency) {
      if (!_enforceSac()) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> findOne() async {
    if (cancelToken?.isCancelled ?? false) {
      _aborted = true;
      return null;
    }
    if (!_seedAndPreprocess()) return null;
    if (enableLcg) {
      // LCG takes precedence over CBJ: first-UIP analysis subsumes
      // CBJ's conflict-set backjump (LCG can jump further, to the
      // second-highest decision level in the learned clause).
      final result = await _searchOneLcg(0);
      return result is _LcgSolution ? result.assignment : null;
    }
    if (enableConflictBackjumping) {
      final result = await _searchOneCbj(0, <String>{});
      return result is _Solution ? result.assignment : null;
    }
    return _searchOne();
  }

  Stream<Map<String, dynamic>> findAll() async* {
    if (cancelToken?.isCancelled ?? false) {
      _aborted = true;
      return;
    }
    if (!_seedAndPreprocess()) return;
    if (enableConflictBackjumping) {
      yield* _searchAllCbj(0, <String>{});
    } else {
      yield* _searchAll();
    }
  }

  /// Integrated branch-and-bound. Walks the full search tree once,
  /// recording each strictly-improving leaf as the incumbent and
  /// tightening the objective's domain (plus every existing trail
  /// snapshot for it) so propagation can prune future branches.
  /// Returns the final incumbent, or null if no feasible assignment
  /// was ever reached.
  Future<Map<String, dynamic>?> findOptimal(String objVar,
      {required bool minimizing}) async {
    _optObjVar = objVar;
    _optMinimizing = minimizing;
    _optBound = null;
    _optBest = null;
    _optProven = false;
    if (cancelToken?.isCancelled ?? false) {
      _aborted = true;
      return _optBest;
    }
    if (!_seedAndPreprocess()) return _optBest;
    if (enableConflictBackjumping) {
      await _searchOptimalCbj(0, <String>{});
    } else {
      await _searchOptimal();
    }
    return _optBest;
  }

  Future<Map<String, dynamic>?> _searchOne() async {
    if (_aborted) return null;
    final pick = _pickVariable();
    if (pick == null) return _readSolution();
    stats.decisions++;
    for (final candidate in _orderByLCV(pick)) {
      if (_aborted) return null;
      final mark = _trailMark();
      final logBefore = useImpact ? _logProductDomains() : 0.0;
      _setDomain(pick, <dynamic>[candidate]);
      await _checkpoint();
      final ok = _propagate(<String>[pick]);
      if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
      if (!ok && useLastConflict) _lastConflictVar = pick;
      if (ok) {
        final result = await _searchOne();
        if (result != null) return result;
      }
      _trailRollback(mark);
      _backtrackCount++;
      stats.backtracks++;
      if (maxBacktracks != null && _backtrackCount >= maxBacktracks!) {
        _aborted = true;
        return null;
      }
    }
    return null;
  }

  /// LCG search loop (M2b). Same control flow as [_searchOne] but on
  /// every propagation failure runs the first-UIP analyser, posts the
  /// resulting learned clause into the constraint store, and (when
  /// the clause's asserting decision level is strictly lower than the
  /// current frame's depth) returns a [_LcgBackjump] signal so caller
  /// frames unwind in lockstep to the landing level.
  ///
  /// The recursion depth equals the pre-pin decision level of the
  /// frame: `_searchOneLcg(d)` runs with [_decisionLevel] == d on
  /// entry; pinning a candidate inside the frame increments it to
  /// d+1, and the conflict-time analyser produces backjump targets in
  /// the same scheme. A frame at depth d consumes
  /// `_LcgBackjump(targetLevel: d)`; any signal with a strictly lower
  /// target propagates upward after the frame rolls back its own pin.
  ///
  /// Falls back to chronological backtrack (without learning) when:
  /// the analyser refuses to emit a clause (opaque reasons block
  /// resolution), the clause's atoms include a non-boolean variable,
  /// or the post-landing re-propagation fails.
  Future<_LcgResult> _searchOneLcg(int depth) async {
    if (_aborted) return const _LcgExhausted();
    final pick = _pickVariable();
    if (pick == null) return _LcgSolution(_readSolution());
    stats.decisions++;
    for (final candidate in _orderByLCV(pick)) {
      if (_aborted) return const _LcgExhausted();
      final mark = _trailMark();
      final logBefore = useImpact ? _logProductDomains() : 0.0;
      _setDomain(pick, <dynamic>[candidate]);
      await _checkpoint();
      final ok = _propagate(<String>[pick]);
      if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
      if (!ok) {
        if (useLastConflict) _lastConflictVar = pick;
        final conflictReason = _lastConflictReason;
        AnalysisResult? analysis;
        if (conflictReason != null) {
          analysis = firstUipAnalyse(_implicationTrail, conflictReason);
          // Diagnostic: a concrete conflict reason that the analyser
          // could not turn into an asserting clause. Tracks the
          // M3-tighten convergence gap (coarse explanations leaving
          // multiple at-conflict-level atoms on the trail).
          if (analysis == null) stats.lcgAnalysisFailures++;
        }
        _trailRollback(mark);
        _backtrackCount++;
        stats.backtracks++;
        if (maxBacktracks != null && _backtrackCount >= maxBacktracks!) {
          _aborted = true;
          return const _LcgExhausted();
        }
        if (analysis != null) {
          final spec = _learnedClauseToSpec(analysis.learnedClause);
          if (spec != null) {
            _postLearnedClause(spec);
            _forgetIfNeeded();
            if (analysis.backjumpLevel < depth) {
              stats.backjumps++;
              stats.backjumpLevelsSkipped += depth - analysis.backjumpLevel - 1;
              return _LcgBackjump(analysis.backjumpLevel);
            }
            // Landing here (analysis.backjumpLevel >= depth). After
            // the rollback the engine state is the depth's pre-pin
            // configuration; re-propagate so the freshly-posted clause
            // can unit-prop its asserting literal (1-UIP case) or
            // simply enter the constraint store (multi-UIP case). If
            // propagation fails outright the frame has no feasible
            // state, mirror chronological "exhausted candidates" so
            // the caller rolls back its own pin and moves on.
            if (!_propagate(_domains.keys)) {
              return const _LcgExhausted();
            }
          }
        }
        continue;
      }
      final result = await _searchOneLcg(depth + 1);
      if (result is _LcgSolution) return result;
      _trailRollback(mark);
      _backtrackCount++;
      stats.backtracks++;
      if (maxBacktracks != null && _backtrackCount >= maxBacktracks!) {
        _aborted = true;
        return const _LcgExhausted();
      }
      if (result is _LcgBackjump) {
        if (result.targetLevel < depth) return result;
        // targetLevel == depth: land here. Re-propagate so the
        // learned clause posted further down the recursion can
        // assert its UIP literal against the current state.
        if (!_propagate(_domains.keys)) {
          return const _LcgExhausted();
        }
      }
    }
    return const _LcgExhausted();
  }

  Stream<Map<String, dynamic>> _searchAll() async* {
    if (_aborted) return;
    final pick = _pickVariable();
    if (pick == null) {
      yield _readSolution();
      return;
    }
    stats.decisions++;
    for (final candidate in _orderByLCV(pick)) {
      if (_aborted) return;
      final mark = _trailMark();
      final logBefore = useImpact ? _logProductDomains() : 0.0;
      _setDomain(pick, <dynamic>[candidate]);
      await _checkpoint();
      final ok = _propagate(<String>[pick]);
      if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
      if (!ok && useLastConflict) _lastConflictVar = pick;
      if (ok) {
        yield* _searchAll();
      }
      _trailRollback(mark);
      stats.backtracks++;
    }
  }

  /// Integrated B&B search loop. Same structure as [_searchOne] but
  /// (a) at each leaf, records an improving incumbent and tightens
  /// the objective domain instead of returning, and (b) skips candidate
  /// values for the objective variable that can't beat the current
  /// bound. Short-circuits when [_optProven] is set, i.e. when the
  /// current bound is unreachable from anywhere in the remaining tree.
  Future<void> _searchOptimal() async {
    if (_optProven || _aborted) return;
    // Bound tightening from a previous leaf may have left a domain
    // empty even though propagation reported success on its way in
    // (`_reviseNary` treats a pre-existing empty domain as "no change",
    // not a wipeout). Bail before reading a corrupt leaf.
    for (final dom in _domains.values) {
      if (dom.isEmpty) return;
    }
    final pick = _pickVariable();
    if (pick == null) {
      final assn = _readSolution();
      final v = assn[_optObjVar!];
      if (v is! num) {
        // Defensive: validated upfront in [Problem._optimize], but an
        // n-ary predicate could theoretically resolve the objective
        // to a non-num via an unusual constraint.
        return;
      }
      if (_optBound == null ||
          (_optMinimizing ? v < _optBound! : v > _optBound!)) {
        _optBest = assn;
        _optBound = v;
        _tightenObjectiveDomain();
      }
      return;
    }
    stats.decisions++;
    for (final candidate in _orderByLCV(pick)) {
      if (_optProven || _aborted) return;
      if (pick == _optObjVar && _optBound != null) {
        final cv = candidate as num;
        if (_optMinimizing ? cv >= _optBound! : cv <= _optBound!) continue;
      }
      final mark = _trailMark();
      final logBefore = useImpact ? _logProductDomains() : 0.0;
      _setDomain(pick, <dynamic>[candidate]);
      await _checkpoint();
      final ok = _propagate(<String>[pick]);
      if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
      if (!ok && useLastConflict) _lastConflictVar = pick;
      if (ok) {
        await _searchOptimal();
      }
      _trailRollback(mark);
      stats.backtracks++;
    }
  }

  // ---------------------------------------------------------------------------
  // Conflict-directed backjumping (Prosser 1993).
  //
  // Three CBJ variants — `_searchOneCbj`, `_searchAllCbj`,
  // `_searchOptimalCbj` — mirror the structure of `_searchOne`,
  // `_searchAll`, `_searchOptimal` exactly, but track a per-frame
  // conflict set and, on candidate exhaustion, jump to the deepest
  // earlier-assigned variable in that set rather than returning to
  // the immediate caller.
  //
  // `_searchOneCbj` returns a [_SearchResult] directly. The streaming
  // (`_searchAllCbj`) and optimization (`_searchOptimalCbj`) variants
  // can't return a value (async generator / `Future<void>`), so they
  // write the jump signal to engine-level `_pendingBackjumpDepth` /
  // `_pendingBackjumpConflict` slots; the caller checks those after
  // the recursive call returns.
  // ---------------------------------------------------------------------------

  /// Conflict set for the failed propagation that ran since `mark`:
  /// every earlier-assigned variable (depth < current decision's
  /// depth) that participated, transitively, in the chain of
  /// revisions that ended in the wipeout.
  ///
  /// The walk uses the per-entry `cause` constraint carried on each
  /// trail entry to attribute each revision precisely (instead of
  /// pessimistically including every neighbor of every touched
  /// variable). For a revision driven by binary arc `(X, Y, pred)`,
  /// the contributor is `X` — not the entire neighborhood of `Y`.
  /// For an n-ary revision over constraint `c` that reduced
  /// `entry.varName`, the contributors are the *other* variables
  /// in `c.vars`.
  ///
  /// When a contributor isn't earlier-assigned (it's the current
  /// pick or a within-frame intermediate), the walk follows its
  /// most-recent reducing trail entry — i.e. the propagation step
  /// that brought it to its current state — and continues from
  /// there. This keeps the chain of justifications intact even
  /// when the immediate cause is a within-frame variable. The
  /// search terminates: each chain step strictly decreases the
  /// trail index, and entries are deduplicated.
  ///
  /// Sound (every true cause is included; some non-causes may be
  /// too, especially via n-ary constraints whose support search
  /// touched all free variables). Over-approximation only weakens
  /// jump distance, not correctness.
  Set<String> _conflictCauseFromTrail(int mark, String pick, int depth) {
    final cause = HashSet<String>();
    final processed = HashSet<int>();
    final pending = <int>[];
    for (var i = mark; i < _trail.length; i++) {
      if (processed.add(i)) pending.add(i);
    }

    void considerInput(int fromIdx, String w) {
      final d = _assignedAtDepth[w];
      if (d != null && d < depth) {
        cause.add(w);
        return;
      }
      // w is the current pick or a within-frame intermediate: walk
      // back to its most recent *reducing* trail entry (skipping
      // decision-site `cause: null` entries, which don't extend the
      // justification chain) and continue the walk from there.
      for (var j = fromIdx - 1; j >= 0; j--) {
        final e = _trail[j];
        if (e.varName != w) continue;
        if (e.cause == null) continue;
        if (processed.add(j)) pending.add(j);
        return;
      }
    }

    while (pending.isNotEmpty) {
      final i = pending.removeLast();
      final entry = _trail[i];
      final c = entry.cause;
      if (c == null) continue;
      if (c is BinaryConstraint) {
        considerInput(i, c.head);
      } else if (c is NaryConstraint) {
        for (final w in c.vars) {
          if (w == entry.varName) continue;
          considerInput(i, w);
        }
      }
    }
    return cause;
  }

  /// CBJ analogue of [_searchOne]. Returns [_Solution] on success,
  /// [_Exhausted] on a normal "nothing left to try" exit at the root,
  /// or [_Backjump] when the caller should skip its remaining
  /// candidates and propagate the jump further up.
  Future<_SearchResult> _searchOneCbj(int depth, Set<String> myConfSet) async {
    if (_aborted) return const _Exhausted();
    final pick = _pickVariable();
    if (pick == null) return _Solution(_readSolution());
    stats.decisions++;
    _assignedAtDepth[pick] = depth;
    try {
      for (final candidate in _orderByLCV(pick)) {
        if (_aborted) return const _Exhausted();
        final mark = _trailMark();
        final logBefore = useImpact ? _logProductDomains() : 0.0;
        _setDomain(pick, <dynamic>[candidate]);
        await _checkpoint();
        final ok = _propagate(<String>[pick]);
        if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
        if (!ok) {
          if (useLastConflict) _lastConflictVar = pick;
          myConfSet.addAll(_conflictCauseFromTrail(mark, pick, depth));
          _trailRollback(mark);
          _backtrackCount++;
          stats.backtracks++;
          if (maxBacktracks != null && _backtrackCount >= maxBacktracks!) {
            _aborted = true;
            return const _Exhausted();
          }
          continue;
        }
        final childConfSet = HashSet<String>();
        final result = await _searchOneCbj(depth + 1, childConfSet);
        if (result is _Solution) return result;
        _trailRollback(mark);
        _backtrackCount++;
        stats.backtracks++;
        if (maxBacktracks != null && _backtrackCount >= maxBacktracks!) {
          _aborted = true;
          return const _Exhausted();
        }
        if (result is _Backjump) {
          if (result.targetDepth < depth) return result;
          // Lands here.
          myConfSet.addAll(result.conflict);
          myConfSet.remove(pick);
        }
        // _Exhausted child: just try the next candidate.
      }
      if (myConfSet.isEmpty) return const _Exhausted();
      final targetDepth =
          myConfSet.map((v) => _assignedAtDepth[v]!).reduce(max);
      final target =
          myConfSet.firstWhere((v) => _assignedAtDepth[v] == targetDepth);
      stats.backjumps++;
      stats.backjumpLevelsSkipped += depth - targetDepth - 1;
      final out = HashSet<String>.of(myConfSet)..remove(target);
      return _Backjump(targetDepth, out);
    } finally {
      _assignedAtDepth.remove(pick);
    }
  }

  /// CBJ analogue of [_searchAll]. Backjump signals are conveyed via
  /// [_pendingBackjumpDepth] / [_pendingBackjumpConflict] since async
  /// generators can't return a value.
  Stream<Map<String, dynamic>> _searchAllCbj(
      int depth, Set<String> myConfSet) async* {
    if (_aborted) return;
    final pick = _pickVariable();
    if (pick == null) {
      yield _readSolution();
      return;
    }
    stats.decisions++;
    _assignedAtDepth[pick] = depth;
    try {
      for (final candidate in _orderByLCV(pick)) {
        if (_aborted) return;
        final mark = _trailMark();
        final logBefore = useImpact ? _logProductDomains() : 0.0;
        _setDomain(pick, <dynamic>[candidate]);
        await _checkpoint();
        final ok = _propagate(<String>[pick]);
        if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
        if (!ok) {
          if (useLastConflict) _lastConflictVar = pick;
          myConfSet.addAll(_conflictCauseFromTrail(mark, pick, depth));
          _trailRollback(mark);
          stats.backtracks++;
          continue;
        }
        final childConfSet = HashSet<String>();
        _pendingBackjumpDepth = null;
        _pendingBackjumpConflict = null;
        yield* _searchAllCbj(depth + 1, childConfSet);
        final pendingDepth = _pendingBackjumpDepth;
        final pendingConflict = _pendingBackjumpConflict;
        _trailRollback(mark);
        stats.backtracks++;
        if (pendingDepth != null) {
          if (pendingDepth < depth) {
            // Pass through: leave the signal in place for the caller.
            return;
          }
          myConfSet.addAll(pendingConflict!);
          myConfSet.remove(pick);
          _pendingBackjumpDepth = null;
          _pendingBackjumpConflict = null;
        }
      }
      if (myConfSet.isEmpty) return;
      final targetDepth =
          myConfSet.map((v) => _assignedAtDepth[v]!).reduce(max);
      final target =
          myConfSet.firstWhere((v) => _assignedAtDepth[v] == targetDepth);
      stats.backjumps++;
      stats.backjumpLevelsSkipped += depth - targetDepth - 1;
      _pendingBackjumpDepth = targetDepth;
      _pendingBackjumpConflict = HashSet<String>.of(myConfSet)..remove(target);
    } finally {
      _assignedAtDepth.remove(pick);
    }
  }

  /// CBJ analogue of [_searchOptimal]. Same control flow as
  /// [_searchAllCbj] for the backjump signal; same incumbent /
  /// objective-bound handling as [_searchOptimal] for the rest.
  Future<void> _searchOptimalCbj(int depth, Set<String> myConfSet) async {
    if (_optProven || _aborted) return;
    for (final dom in _domains.values) {
      if (dom.isEmpty) return;
    }
    final pick = _pickVariable();
    if (pick == null) {
      final assn = _readSolution();
      final v = assn[_optObjVar!];
      if (v is! num) return;
      if (_optBound == null ||
          (_optMinimizing ? v < _optBound! : v > _optBound!)) {
        _optBest = assn;
        _optBound = v;
        _tightenObjectiveDomain();
      }
      return;
    }
    stats.decisions++;
    _assignedAtDepth[pick] = depth;
    try {
      for (final candidate in _orderByLCV(pick)) {
        if (_optProven || _aborted) return;
        if (pick == _optObjVar && _optBound != null) {
          final cv = candidate as num;
          if (_optMinimizing ? cv >= _optBound! : cv <= _optBound!) continue;
        }
        final mark = _trailMark();
        final logBefore = useImpact ? _logProductDomains() : 0.0;
        _setDomain(pick, <dynamic>[candidate]);
        await _checkpoint();
        final ok = _propagate(<String>[pick]);
        if (useImpact) _observeImpact(pick, candidate, logBefore, ok);
        if (!ok) {
          if (useLastConflict) _lastConflictVar = pick;
          myConfSet.addAll(_conflictCauseFromTrail(mark, pick, depth));
          _trailRollback(mark);
          stats.backtracks++;
          continue;
        }
        final childConfSet = HashSet<String>();
        _pendingBackjumpDepth = null;
        _pendingBackjumpConflict = null;
        await _searchOptimalCbj(depth + 1, childConfSet);
        final pendingDepth = _pendingBackjumpDepth;
        final pendingConflict = _pendingBackjumpConflict;
        _trailRollback(mark);
        stats.backtracks++;
        if (pendingDepth != null) {
          if (pendingDepth < depth) return;
          myConfSet.addAll(pendingConflict!);
          myConfSet.remove(pick);
          _pendingBackjumpDepth = null;
          _pendingBackjumpConflict = null;
        }
      }
      if (myConfSet.isEmpty) return;
      final targetDepth =
          myConfSet.map((v) => _assignedAtDepth[v]!).reduce(max);
      final target =
          myConfSet.firstWhere((v) => _assignedAtDepth[v] == targetDepth);
      stats.backjumps++;
      stats.backjumpLevelsSkipped += depth - targetDepth - 1;
      _pendingBackjumpDepth = targetDepth;
      _pendingBackjumpConflict = HashSet<String>.of(myConfSet)..remove(target);
    } finally {
      _assignedAtDepth.remove(pick);
    }
  }

  /// After a new incumbent is recorded, permanently filter the
  /// objective variable's domain (and every existing trail snapshot
  /// for it) to values that strictly improve over [_optBound].
  /// Filtering past trail entries is what lets rollback respect the
  /// new bound without re-running propagation from scratch. If the
  /// resulting state has no improving values left anywhere — neither
  /// in the live domain nor in any trail snapshot — sets [_optProven]
  /// so the search loop exits immediately.
  void _tightenObjectiveDomain() {
    final obj = _optObjVar!;
    final bound = _optBound!;
    final minimizing = _optMinimizing;
    bool improves(dynamic c) {
      final v = c as num;
      return minimizing ? v < bound : v > bound;
    }

    _domains[obj] = _domains[obj]!.filter(improves);
    var anyNonEmpty = _domains[obj]!.isNotEmpty;
    for (var i = 0; i < _trail.length; i++) {
      final e = _trail[i];
      if (e.varName == obj) {
        final filtered = e.oldRep.filter(improves);
        _trail[i] = _TrailEntry(e.varName, filtered, e.cause);
        if (filtered.isNotEmpty) anyNonEmpty = true;
      }
    }
    if (!anyNonEmpty) _optProven = true;
  }

  String? _pickByMRV() {
    String? best;
    var bestSize = 0;
    for (final entry in _domains.entries) {
      final size = entry.value.length;
      if (size < 2) continue;
      if (best == null || size < bestSize) {
        best = entry.key;
        bestSize = size;
      }
    }
    return best;
  }

  /// dom/wdeg variable selection (Boussemart, Hemery, Lecoutre, Sais
  /// 2004). Picks the variable that minimizes the ratio of its
  /// current domain size to the sum of weights of constraints
  /// touching it with at least one other unassigned neighbor.
  /// Adaptively focuses search on the "guilty" parts of the problem.
  String? _pickByDomWdeg() {
    String? best;
    var bestRatio = double.infinity;
    for (final entry in _domains.entries) {
      final size = entry.value.length;
      if (size < 2) continue;
      final wdeg = _wdegFor(entry.key);
      // Variables with no active constraints get the worst ratio
      // (infinity) so they're picked last — there's nothing for
      // propagation to do on them anyway.
      final ratio = wdeg == 0 ? double.infinity : size / wdeg;
      if (ratio < bestRatio) {
        best = entry.key;
        bestRatio = ratio;
      }
    }
    return best;
  }

  /// Sum of weights of constraints involving [v] where at least one
  /// other variable in the constraint is still unassigned (domain
  /// size > 1). Constraints whose other variables are all decided
  /// can no longer fail in a way attributable to [v], so they are
  /// excluded from wdeg.
  int _wdegFor(String v) {
    var total = 0;
    for (final arc in (_arcsFromHead[v] ?? const <BinaryConstraint>[])) {
      if ((_domains[arc.tail]?.length ?? 0) > 1) {
        total += _binWeights[arc] ?? 1;
      }
    }
    for (final c in (_naryIdx[v] ?? const <NaryConstraint>[])) {
      var hasUnassignedNeighbor = false;
      for (final other in c.vars) {
        if (other == v) continue;
        if ((_domains[other]?.length ?? 0) > 1) {
          hasUnassignedNeighbor = true;
          break;
        }
      }
      if (hasUnassignedNeighbor) {
        total += _naryWeights[c] ?? 1;
      }
    }
    return total;
  }

  /// VSIDS-style variable selection. Picks the variable minimizing
  /// `dom_size / (1 + activity)`. Mirrors [_pickByDomWdeg] but uses
  /// per-variable activity in place of per-constraint weight. Falls
  /// back to MRV-like behavior when all activities are zero.
  String? _pickByActivity() {
    String? best;
    var bestRatio = double.infinity;
    for (final entry in _domains.entries) {
      final size = entry.value.length;
      if (size < 2) continue;
      final activity = _varActivity[entry.key] ?? 0.0;
      final ratio = size / (1.0 + activity);
      if (ratio < bestRatio) {
        best = entry.key;
        bestRatio = ratio;
      }
    }
    return best;
  }

  /// Impact-Based Search variable selection. Picks the variable
  /// minimizing `dom_size / (1 + Σ_a I(v, a))` where the sum is over
  /// values currently in `v`'s domain. Mirrors [_pickByActivity] but
  /// uses per-`(var, value)` impact in place of per-variable
  /// activity. Falls back to MRV-like behavior when no impact has
  /// been observed yet for `v`.
  String? _pickByImpact() {
    String? best;
    var bestRatio = double.infinity;
    for (final entry in _domains.entries) {
      final size = entry.value.length;
      if (size < 2) continue;
      final means = _impactMean[entry.key];
      var sumImpact = 0.0;
      if (means != null) {
        for (final v in entry.value.values) {
          final m = means[v];
          if (m != null) sumImpact += m;
        }
      }
      final ratio = size / (1.0 + sumImpact);
      if (ratio < bestRatio) {
        best = entry.key;
        bestRatio = ratio;
      }
    }
    return best;
  }

  String? _pickVariable() {
    if (useLastConflict) {
      final lc = _lastConflictVar;
      if (lc != null) {
        final dom = _domains[lc];
        if (dom != null && dom.length >= 2) return lc;
      }
    }
    if (useImpact) return _pickByImpact();
    if (useVsids) return _pickByActivity();
    if (useDomWdeg) return _pickByDomWdeg();
    return _pickByMRV();
  }

  List<dynamic> _orderByLCV(String x) {
    final dom = _domains[x]!;
    if (dom.length <= 1) return dom.asList;
    final outgoing = _arcsFromHead[x];
    final scored = <_ScoredValue>[];
    for (final v in dom.values) {
      var penalty = 0;
      if (outgoing != null) {
        for (final arc in outgoing) {
          final tailDom = _domains[arc.tail]!;
          if (tailDom.length <= 1) continue;
          for (final t in tailDom.values) {
            if (!arc.predicate(v, t)) penalty++;
          }
        }
      }
      scored.add(_ScoredValue(v, penalty));
    }
    // When randomization is enabled, shuffle first so that the
    // subsequent stable sort breaks ties in random order. This is the
    // mechanism that lets Luby restarts explore different parts of
    // the search tree on successive attempts.
    if (random != null) {
      scored.shuffle(random);
    }
    scored.sort((a, b) => a.penalty.compareTo(b.penalty));
    return [for (final s in scored) s.value];
  }

  Map<String, dynamic> _readSolution() {
    final out = <String, dynamic>{};
    for (final entry in _domains.entries) {
      out[entry.key] = entry.value.first;
    }
    return out;
  }

  Future<void> _maybeNotify() async {
    final cb = _csp.cb;
    if (cb == null) return;
    final assigned = <String, List<dynamic>>{};
    final unassigned = <String, List<dynamic>>{};
    for (final entry in _domains.entries) {
      final copy = List<dynamic>.from(entry.value.values);
      if (entry.value.length == 1) {
        assigned[entry.key] = copy;
      } else {
        unassigned[entry.key] = copy;
      }
    }
    cb(assigned, unassigned);
    if (_csp.timeStep > 0) {
      await Future<void>.delayed(Duration(milliseconds: _csp.timeStep));
    }
  }

  /// Called once per decision from each search loop. Three roles:
  ///
  ///   1. Run the optional visualization callback (delegates to
  ///      [_maybeNotify]; no-op when the user didn't register one).
  ///   2. Every [_yieldEveryDecisions] decisions, yield to the event
  ///      loop via `Future<void>.delayed(Duration.zero)` so a wrapping
  ///      `Future.timeout(...)` actually has a chance to fire and so
  ///      a [CancellationToken] set from a Timer is observed within
  ///      bounded time. This applies whether or not the caller passed
  ///      a token — it's what makes `.timeout()` work on an otherwise
  ///      CPU-bound solve.
  ///   3. After each yield, observe [cancelToken] (if any) and
  ///      short-circuit the search when cancelled.
  ///
  /// The no-callback, no-token fast path is one integer compare per
  /// decision; the yield itself amortizes to well under 1% of search
  /// wall-clock on real CSPs.
  Future<void> _checkpoint() async {
    await _maybeNotify();
    if (cancelToken?.isCancelled ?? false) {
      _aborted = true;
      return;
    }
    if (stats.decisions - _decisionsAtLastYield >= _yieldEveryDecisions) {
      _decisionsAtLastYield = stats.decisions;
      await Future<void>.delayed(Duration.zero);
      if (cancelToken?.isCancelled ?? false) _aborted = true;
    }
  }

  /// Drains a queue of pending AC-3 arcs and GAC tasks until a fixed
  /// point is reached. Returns false if any domain wiped out.
  ///
  /// When [consistency] is [ConsistencyLevel.forwardChecking], a
  /// revise that merely narrows a domain (without making it
  /// singleton) does NOT enqueue further work. A revise that
  /// *assigns* a variable — i.e. reduces its domain to size 1 — does
  /// trigger one cascading pass, so constraints from the newly-
  /// assigned variable are still revised once. This matches the
  /// textbook FC semantics: whenever a variable is assigned (whether
  /// by a decision or by deduction), revise its constraints. Without
  /// this trigger, a variable could become singleton via propagation
  /// without ever having its constraints checked against the new
  /// value, and a leaf "solution" could violate a constraint.
  bool _propagate(Iterable<String> seeds) {
    stats.propagations++;
    if (enableLcg) _lastConflictReason = null;
    final cascadeAll = consistency == ConsistencyLevel.arcConsistency;
    final binQ = Queue<BinaryConstraint>();
    final naryQ = Queue<_GacTask>();
    final inBinQ = HashSet<BinaryConstraint>(
        equals: identical, hashCode: identityHashCode);
    final inNaryQ = <_GacTask>{};

    void seedFor(String v) {
      for (final arc in (_arcsFromHead[v] ?? const <BinaryConstraint>[])) {
        if (inBinQ.add(arc)) binQ.add(arc);
      }
      for (final c in (_naryIdx[v] ?? const <NaryConstraint>[])) {
        if (c.clauseSpec != null) {
          // Per-variable watch lists for clauses (Moskewicz et al.,
          // Chaff 2001, watcher-driven scheduling). Once the
          // two-watched-literal state is initialized, a reduction at
          // a non-watched variable cannot falsify either watcher and
          // therefore cannot change the propagator's behavior —
          // skip the wake-up. The watched-literal invariant is
          // monotone under the engine's trail semantics, so a swap
          // done deeper in the search stays valid on backtrack and
          // the per-call check `v is one of the watched literals'
          // variables` is self-consistent across all depths.
          //
          // Width filter: clauses with at most two literals always
          // have all of their variables watched (one literal becomes
          // both watchers; two literals each get one). The skip
          // condition would never fire, so the check is pure
          // overhead. Skipping it matters in workloads dominated by
          // width-2 "at most one" pairwise clauses (e.g., pigeonhole
          // CNF, naive at-most-one encodings of categorical choice)
          // where the seedFor loop runs over many such clauses per
          // domain change.
          //
          // Before initialization (first encounter of this clause)
          // we always enqueue — the propagator's own initialization
          // path scans for the first two non-falsified literals.
          final spec = c.clauseSpec!;
          final litCount =
              spec.atoms != null ? spec.atoms!.length : spec.literals.length;
          if (litCount > 2) {
            final state = _clauseWatchers[spec];
            if (state != null) {
              final w1var = spec.atoms != null
                  ? spec.atoms![state.watch1].varName
                  : spec.literals[state.watch1].varName;
              final w2var = spec.atoms != null
                  ? spec.atoms![state.watch2].varName
                  : spec.literals[state.watch2].varName;
              if (w1var != v && w2var != v) continue;
            }
          }
          final task = _GacTask(c.vars.first, c);
          if (inNaryQ.add(task)) naryQ.add(task);
          continue;
        }
        if (c.allDifferent ||
            c.linearSpec != null ||
            c.regularDfa != null ||
            c.circuit ||
            c.subcircuit ||
            c.gccSpec != null ||
            c.cumulativeSpec != null ||
            c.diffNSpec != null) {
          // The specialized propagators (Régin for allDifferent,
          // bounds-consistency for linear arithmetic, partial-state
          // forward+backward for regular, cycle-detection for
          // circuit, network-flow GCC, time-table for cumulative)
          // revise every variable in the constraint in one shot, so
          // we only need a single canonical task per constraint
          // regardless of which variable triggered seeding.
          final task = _GacTask(c.vars.first, c);
          if (inNaryQ.add(task)) naryQ.add(task);
          continue;
        }
        if (c.vars.length == 1) {
          // Unary constraint: standard GAC enqueueing skips it (no
          // neighbors), so re-revise the variable itself.
          final task = _GacTask(v, c);
          if (inNaryQ.add(task)) naryQ.add(task);
          continue;
        }
        for (final other in c.vars) {
          if (other == v) continue;
          final task = _GacTask(other, c);
          if (inNaryQ.add(task)) naryQ.add(task);
        }
      }
    }

    void maybeCascade(String v) {
      if (cascadeAll || _domains[v]!.length == 1) seedFor(v);
    }

    for (final v in seeds) {
      seedFor(v);
    }

    while (binQ.isNotEmpty || naryQ.isNotEmpty) {
      if (binQ.isNotEmpty) {
        final arc = binQ.removeFirst();
        inBinQ.remove(arc);
        if (_reviseBinary(arc)) {
          stats.binaryRevises++;
          if (_domains[arc.tail]!.isEmpty) {
            _onConflict(arc);
            return false;
          }
          maybeCascade(arc.tail);
        }
      } else {
        final task = naryQ.removeFirst();
        inNaryQ.remove(task);
        if (task.c.allDifferent) {
          final changedVars = _AllDifferentPropagator(
            task.c.vars,
            _domains,
            (v, r, {reason}) =>
                _setDomainRep(v, r, cause: task.c, reason: reason),
            originalDomains: enableLcg ? _csp.variables : null,
            recordScc: enableLcg ? _recordSyntheticScc : null,
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            if (enableLcg) {
              _lastConflictReason = _allDifferentConflictReason(task.c.vars);
            }
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              if (enableLcg) {
                _lastConflictReason = _allDifferentConflictReason(task.c.vars);
              }
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.linearSpec != null) {
          final changedVars = _LinearPropagator(
            task.c.vars,
            task.c.linearSpec!,
            _domains,
            (v, r, {reason}) =>
                _setDomainRep(v, r, cause: task.c, reason: reason),
            originalDomains: enableLcg ? _csp.variables : null,
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            if (enableLcg) {
              _lastConflictReason = _linearConflictReason(task.c.vars);
            }
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              if (enableLcg) {
                _lastConflictReason = _linearConflictReason(task.c.vars);
              }
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.regularDfa != null) {
          final changedVars = _RegularPropagator(
            task.c.vars,
            task.c.regularDfa!,
            _domains,
            (v, r) => _setDomainRep(v, r, cause: task.c),
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.circuit || task.c.subcircuit) {
          final changedVars = _CircuitPropagator(
            task.c.vars,
            _domains,
            (v, r) => _setDomainRep(v, r, cause: task.c),
            subcircuit: task.c.subcircuit,
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.gccSpec != null) {
          final changedVars = _GccPropagator(
            task.c.vars,
            task.c.gccSpec!,
            _domains,
            (v, r) => _setDomainRep(v, r, cause: task.c),
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.cumulativeSpec != null) {
          final changedVars = _CumulativePropagator(
            task.c.vars,
            task.c.cumulativeSpec!,
            _domains,
            (v, r) => _setDomainRep(v, r, cause: task.c),
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.clauseSpec != null) {
          final spec = task.c.clauseSpec!;
          final changedVars = _ClausePropagator(
            spec,
            _domains,
            (v, r, {reason}) =>
                _setDomainRep(v, r, cause: task.c, reason: reason),
            _clauseWatchers,
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            if (enableLcg) _lastConflictReason = _clauseConflictReason(spec);
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              if (enableLcg) {
                _lastConflictReason = _clauseConflictReason(spec);
              }
              return false;
            }
            maybeCascade(v);
          }
        } else if (task.c.diffNSpec != null) {
          final changedVars = _DiffNPropagator(
            task.c.vars,
            task.c.diffNSpec!,
            _domains,
            (v, r) => _setDomainRep(v, r, cause: task.c),
          ).propagate();
          if (changedVars == null) {
            _onConflict(task.c);
            return false;
          }
          if (changedVars.isNotEmpty) stats.naryRevises++;
          for (final v in changedVars) {
            if (_domains[v]!.isEmpty) {
              _onConflict(task.c);
              return false;
            }
            maybeCascade(v);
          }
        } else if (_reviseNary(task.v, task.c)) {
          stats.naryRevises++;
          if (_domains[task.v]!.isEmpty) {
            _onConflict(task.c);
            return false;
          }
          maybeCascade(task.v);
        }
      }
    }
    return true;
  }

  /// AC-3 revise step. A value `t` in the tail's domain survives only
  /// if there is at least one `h` in the head's current domain that
  /// satisfies `predicate(h, t)`.
  bool _reviseBinary(BinaryConstraint arc) {
    final headDom = _domains[arc.head]!;
    final tailDom = _domains[arc.tail]!;
    final kept = <dynamic>[];
    var changed = false;
    for (final t in tailDom.values) {
      var supported = false;
      for (final h in headDom.values) {
        if (arc.predicate(h, t)) {
          supported = true;
          break;
        }
      }
      if (supported) {
        kept.add(t);
      } else {
        changed = true;
      }
    }
    if (changed) _setDomain(arc.tail, kept, cause: arc);
    return changed;
  }

  /// GAC revise step for one (variable, n-ary constraint) pair.
  /// A candidate value `v` for [variable] survives only if there
  /// exists a tuple of values for the constraint's other variables
  /// (drawn from their current domains) that, together with `v`,
  /// satisfies the predicate.
  bool _reviseNary(String variable, NaryConstraint c) {
    final dom = _domains[variable]!;
    if (dom.isEmpty) return false;
    final fixedPart = <String, dynamic>{};
    final freeVars = <String>[];
    for (final other in c.vars) {
      if (other == variable) continue;
      final od = _domains[other]!;
      if (od.length == 1) {
        fixedPart[other] = od.first;
      } else {
        freeVars.add(other);
      }
    }
    // Bail out when the free neighborhood is too big to enumerate
    // within the configured work bound.
    var workEstimate = 1;
    for (final fv in freeVars) {
      workEstimate *= _domains[fv]!.length;
      if (workEstimate > _gacWorkBound) return false;
    }
    final kept = <dynamic>[];
    var changed = false;
    for (final val in dom.values) {
      final partial = <String, dynamic>{...fixedPart, variable: val};
      if (_findSupport(c, freeVars, 0, partial)) {
        kept.add(val);
      } else {
        changed = true;
      }
    }
    if (changed) _setDomain(variable, kept, cause: c);
    return changed;
  }

  bool _findSupport(NaryConstraint c, List<String> free, int idx,
      Map<String, dynamic> partial) {
    if (idx == free.length) return c.predicate(partial);
    final v = free[idx];
    for (final val in _domains[v]!.values) {
      partial[v] = val;
      if (_findSupport(c, free, idx + 1, partial)) {
        partial.remove(v);
        return true;
      }
    }
    partial.remove(v);
    return false;
  }
}

class _ScoredValue {
  _ScoredValue(this.value, this.penalty);
  final dynamic value;
  final int penalty;
}

/// Hyper-arc-consistent propagator for the `allDifferent` constraint
/// (Régin, "A filtering algorithm for constraints of difference in
/// CSPs", AAAI 1994).
///
/// Given a set of variables that must take pairwise distinct values,
/// this prunes every value that is not part of *some* maximum matching
/// of the bipartite variable→value graph. The algorithm:
///
/// 1. Compute a maximum matching M (Hopcroft-Karp, O(E·√V)).
/// 2. If |M| < n the constraint is infeasible (pigeonhole).
/// 3. Build a directed graph: matched edges point value → variable,
///    unmatched edges point variable → value.
/// 4. An unmatched edge (var v, val x) is part of some maximum
///    matching iff v and x are in the same SCC, or x is reachable
///    from a free (unmatched) value via a directed path. Everything
///    else can be removed.
///
/// Mutates the supplied [domains] map in place. Returns the set of
/// variables whose domains were reduced, or `null` if the constraint
/// is infeasible / any resulting domain is empty.
class _AllDifferentPropagator {
  _AllDifferentPropagator(this.vars, this.domains, this.applyUpdate,
      {this.originalDomains, this.recordScc});

  final List<String> vars;
  final Map<String, _DomainRep> domains;

  /// Both records the pre-mutation domain on the engine's trail and
  /// installs the new domain. Takes a `_DomainRep` (typically the
  /// result of `_DomainRep.filter`) so a bitset-backed reduction
  /// stays in bitset form instead of round-tripping through a
  /// `List<dynamic>` and a fresh `Uint64List`.
  ///
  /// The optional [reason] kwarg carries an [ImplicationReason]
  /// (M3a: [AllDifferentReason]) for the LCG implication trail.
  /// Non-LCG callers pass null and ignore the parameter.
  final void Function(String varName, _DomainRep newDom,
      {ImplicationReason? reason}) applyUpdate;

  /// User-declared domain for each variable in [vars], used to build
  /// per-prune Hall-set explanations: the antecedents include
  /// `AtomNe(h, k)` for every Hall-set variable `h` and every value
  /// `k` declared in `h`'s domain at construction time but absent
  /// from `h`'s current domain. Null when the engine isn't running
  /// in LCG mode — in that case the propagator skips the
  /// explanation-construction work entirely.
  final Map<String, List<dynamic>>? originalDomains;

  /// LCG (M3-tighten): commits a synthetic [AtomInScc] bridge atom for a
  /// tight Hall set (with the given Hall-set absences as antecedents)
  /// and returns it, so every per-prune reason can reference the
  /// *single* bridge instead of the coarse multi-variable absence list.
  /// Non-null exactly when [originalDomains] is (both gated by the
  /// engine's `enableLcg`).
  final Atom Function(String repVar, List<Atom> antecedents)? recordScc;

  bool get _lcgEnabled => originalDomains != null && recordScc != null;

  Set<String>? propagate() {
    final n = vars.length;
    if (n == 0) return <String>{};

    // Index the union of all values occurring in the constraint's
    // variable domains.
    final valIdx = <dynamic, int>{};
    for (final v in vars) {
      for (final val in domains[v]!.values) {
        valIdx.putIfAbsent(val, () => valIdx.length);
      }
    }
    final m = valIdx.length;

    // Pigeonhole: not enough distinct values to assign each variable.
    if (m < n) return null;

    // Adjacency: variable index → list of value indices.
    final varAdj = List<List<int>>.generate(
      n,
      (i) => [for (final val in domains[vars[i]]!.values) valIdx[val]!],
    );

    // Maximum bipartite matching.
    final matchVar = List<int>.filled(n, -1);
    final matchVal = List<int>.filled(m, -1);
    if (!_hopcroftKarp(varAdj, n, m, matchVar, matchVal)) {
      return null;
    }

    // Build the directed graph used for SCC + free-reachability.
    // Node ids: 0..n-1 are variables, n..n+m-1 are values.
    final totalNodes = n + m;
    final dAdj = List<List<int>>.generate(totalNodes, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      for (final j in varAdj[i]) {
        if (matchVar[i] == j) {
          dAdj[n + j].add(i); // matched: value → variable
        } else {
          dAdj[i].add(n + j); // unmatched: variable → value
        }
      }
    }

    final sccOf = _kosarajuScc(dAdj, totalNodes);

    // Mark every node reachable from a free (unmatched) value.
    final reachable = List<bool>.filled(totalNodes, false);
    for (var j = 0; j < m; j++) {
      if (matchVal[j] == -1) {
        _dfsMark(n + j, dAdj, reachable);
      }
    }

    // For LCG explanations (M3-tighten): group variables by SCC up
    // front, and snapshot each variable's Hall-set absences from the
    // *entry* domain state (before any prune below). Snapshotting at
    // entry is load-bearing: it keeps a Hall set's defining absences
    // free of this round's sibling prunes, which is exactly the
    // circular shape that defeated the coarse explanation. The
    // per-value bridge-atom cache (`valueBridge`) lazily commits one
    // [AtomInScc] the first time any prune removes that value, so every
    // prune of the same value shares the bridge and collapses during
    // resolution. All built only when LCG is on.
    final varsInScc = _lcgEnabled ? <int, List<int>>{} : null;
    final entryAbsent = _lcgEnabled ? <String, List<Atom>>{} : null;
    final valueBridge = _lcgEnabled ? <int, Atom>{} : null;
    if (_lcgEnabled) {
      final orig = originalDomains!;
      for (var i = 0; i < n; i++) {
        varsInScc!.putIfAbsent(sccOf[i], () => <int>[]).add(i);
        final hName = vars[i];
        final origDom = orig[hName];
        if (origDom != null) {
          entryAbsent![hName] =
              _domainShapeAntecedents(hName, origDom, domains[hName]!);
        }
      }
    }

    // Prune non-vital edges from each variable's domain. The keep
    // predicate captures per-variable state (matched value index,
    // SCC id) so we hoist those reads out of the inner filter.
    final changed = <String>{};
    for (var i = 0; i < n; i++) {
      final oldDom = domains[vars[i]]!;
      final matchedJ = matchVar[i];
      final sccI = sccOf[i];
      final newDom = oldDom.filter((val) {
        final j = valIdx[val]!;
        return matchedJ == j || sccI == sccOf[n + j] || reachable[n + j];
      });
      if (newDom.length != oldDom.length) {
        if (newDom.isEmpty) return null;
        ImplicationReason? reason;
        if (_lcgEnabled) {
          reason = _buildHallSetReason(vars[i], oldDom, newDom, valIdx, sccOf,
              matchVal, varsInScc!, entryAbsent!, valueBridge!, n);
        }
        applyUpdate(vars[i], newDom, reason: reason);
        changed.add(vars[i]);
      }
    }
    return changed;
  }

  /// Build the per-prune explanation as a list of *synthetic* [AtomInScc]
  /// bridge atoms (M3-tighten), one per value removed from [prunedVar].
  /// Each bridge collapses a whole "why is this value unavailable"
  /// argument into a single resolvable atom so the first-UIP walk
  /// converges instead of drowning in a flat multi-variable absence list.
  ///
  /// Two sound explanation shapes, picked per value `v`:
  ///
  ///  * **Assignment.** If the variable matched to `v` is currently
  ///    pinned to `{v}`, that variable occupies `v`, so allDifferent
  ///    forbids it here. The antecedent is the single on-trail literal
  ///    `AtomEq(owner, v)` — the "newest cause", which the analyser
  ///    resolves straight to the decision/implication that pinned the
  ///    owner. (This is the common case the coarse Hall-set shape
  ///    mis-handled: a value matched to a pinned variable sits in a
  ///    singleton residual-graph SCC with no member variables, so the
  ///    Hall-set lookup produced an empty, unresolvable antecedent set.)
  ///
  ///  * **Régin Hall set.** Otherwise `v` is confined by a tight SCC of
  ///    variables; the antecedents are those variables' entry-snapshot
  ///    absences (sound: the tight set is implied by the absences within
  ///    it alone — `LCG_PLAN.md` "Hall-set narrow IS sound").
  ///
  /// A bridge with empty antecedents (degenerate: neither shape applies)
  /// simply can't be resolved through, so the analyser bails for that
  /// conflict — sound, no false clause, same fallback as the coarse code.
  ImplicationReason _buildHallSetReason(
    String prunedVar,
    _DomainRep oldDom,
    _DomainRep newDom,
    Map<dynamic, int> valIdx,
    List<int> sccOf,
    List<int> matchVal,
    Map<int, List<int>> varsInScc,
    Map<String, List<Atom>> entryAbsent,
    Map<int, Atom> valueBridge,
    int n,
  ) {
    final bridges = <Atom>[];
    for (final v in oldDom.values) {
      if (newDom.contains(v) || v is! int) continue;
      bridges.add(valueBridge.putIfAbsent(v, () {
        final antecedents = <Atom>[];
        // Assignment shape: value v matched to a pinned variable.
        final owner = matchVal[valIdx[v]!];
        if (owner != -1 && domains[vars[owner]]!.length == 1) {
          antecedents.add(AtomEq(vars[owner], v));
          return recordScc!(vars[owner], antecedents);
        }
        // Régin Hall-set shape: variables sharing value v's SCC.
        final scc = sccOf[n + valIdx[v]!];
        final members = varsInScc[scc];
        if (members != null) {
          for (final hi in members) {
            final abs = entryAbsent[vars[hi]];
            if (abs != null) antecedents.addAll(abs);
          }
        }
        final rep = (members != null && members.isNotEmpty)
            ? vars[members.first]
            : prunedVar;
        return recordScc!(rep, antecedents);
      }));
    }
    return AllDifferentReason(bridges);
  }
}

/// Hopcroft-Karp maximum bipartite matching.
///
/// [adj][i] is the list of value indices in variable `i`'s domain.
/// Fills [matchVar] (variable → value) and [matchVal] (value →
/// variable). Returns true iff every variable was matched.
bool _hopcroftKarp(
  List<List<int>> adj,
  int n,
  int m,
  List<int> matchVar,
  List<int> matchVal,
) {
  final dist = List<int>.filled(n, 0);
  const inf = -1;

  bool bfs() {
    final q = Queue<int>();
    var foundAug = false;
    for (var u = 0; u < n; u++) {
      if (matchVar[u] == -1) {
        dist[u] = 0;
        q.add(u);
      } else {
        dist[u] = inf;
      }
    }
    while (q.isNotEmpty) {
      final u = q.removeFirst();
      for (final v in adj[u]) {
        final pair = matchVal[v];
        if (pair == -1) {
          foundAug = true;
        } else if (dist[pair] == inf) {
          dist[pair] = dist[u] + 1;
          q.add(pair);
        }
      }
    }
    return foundAug;
  }

  bool dfs(int u) {
    for (final v in adj[u]) {
      final pair = matchVal[v];
      if (pair == -1 || (dist[pair] == dist[u] + 1 && dfs(pair))) {
        matchVar[u] = v;
        matchVal[v] = u;
        return true;
      }
    }
    dist[u] = inf;
    return false;
  }

  while (bfs()) {
    for (var u = 0; u < n; u++) {
      if (matchVar[u] == -1) dfs(u);
    }
  }
  for (var u = 0; u < n; u++) {
    if (matchVar[u] == -1) return false;
  }
  return true;
}

/// Kosaraju's two-pass strongly-connected-components algorithm.
/// Iterative — does not consume the call stack for large graphs.
List<int> _kosarajuScc(List<List<int>> adj, int n) {
  final visited = List<bool>.filled(n, false);
  final order = <int>[];

  for (var v0 = 0; v0 < n; v0++) {
    if (visited[v0]) continue;
    final stack = <(int, int)>[(v0, 0)];
    visited[v0] = true;
    while (stack.isNotEmpty) {
      final (u, i) = stack.last;
      if (i < adj[u].length) {
        stack[stack.length - 1] = (u, i + 1);
        final w = adj[u][i];
        if (!visited[w]) {
          visited[w] = true;
          stack.add((w, 0));
        }
      } else {
        order.add(u);
        stack.removeLast();
      }
    }
  }

  final radj = List<List<int>>.generate(n, (_) => <int>[]);
  for (var u = 0; u < n; u++) {
    for (final v in adj[u]) {
      radj[v].add(u);
    }
  }

  final sccOf = List<int>.filled(n, -1);
  var nextScc = 0;
  for (var i = order.length - 1; i >= 0; i--) {
    final v = order[i];
    if (sccOf[v] != -1) continue;
    final stack = <int>[v];
    sccOf[v] = nextScc;
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      for (final w in radj[u]) {
        if (sccOf[w] == -1) {
          sccOf[w] = nextScc;
          stack.add(w);
        }
      }
    }
    nextScc++;
  }
  return sccOf;
}

/// Build a list of antecedent atoms describing the current domain
/// shape of [varName]: one `AtomNe(varName, k)` per value `k`
/// declared in [origDom] but absent from [curDom].
///
/// The shape is uniform regardless of whether [curDom] is a singleton
/// — even though [_recordImplications] emits a single `AtomEq` entry
/// for prune-to-singleton, the `AtomNe` atoms here for the
/// concurrently-removed values may or may not appear on the trail.
/// The first-UIP analyser treats atoms not on the trail as
/// structural / root-level facts (they don't contribute to the
/// at-conflict-level count or break resolution). The `AtomEq`-for-
/// singleton variant would instead make every pinned variable's
/// decision atom visible at conflict level, which multiplies the
/// at-level atom count past 1 and stops the analyser from isolating
/// a UIP on coarse "whole constraint scope" explanations.
///
/// This is the coarse-but-sound explanation shape used by M3a / M3b.
/// A tighter per-prune explanation (precise Hall set or precise
/// other-variables-bound set, with atom kinds matched to the trail)
/// would unlock more learning but requires more careful construction
/// and is reserved for a follow-up refinement.
///
/// Non-int values in [origDom] are skipped (the trail's atom layer
/// is integer-only by design).
List<Atom> _domainShapeAntecedents(
    String varName, List<dynamic> origDom, _DomainRep curDom) {
  final atoms = <Atom>[];
  for (final k in origDom) {
    if (k is! int) continue;
    if (!curDom.contains(k)) {
      atoms.add(AtomNe(varName, k));
    }
  }
  return atoms;
}

/// Iterative DFS that marks every node reachable from [start] in
/// [visited]. No-op if [start] is already visited.
void _dfsMark(int start, List<List<int>> adj, List<bool> visited) {
  if (visited[start]) return;
  final stack = <int>[start];
  visited[start] = true;
  while (stack.isNotEmpty) {
    final u = stack.removeLast();
    for (final w in adj[u]) {
      if (!visited[w]) {
        visited[w] = true;
        stack.add(w);
      }
    }
  }
}

/// Bounds-consistency propagator for a linear arithmetic constraint
/// `Σ coeffs[i]·vars[i]  op  bound`.
///
/// For each variable `xⱼ` with non-zero coefficient `cⱼ`, the
/// propagator computes the interval `[Sⱼ_min, Sⱼ_max]` of the
/// partial sum `Σᵢ≠ⱼ coeffs[i]·vars[i]` from the other variables'
/// current domain mins and maxes, and keeps a value `v` of `xⱼ`
/// only if there exists some `S ∈ [Sⱼ_min, Sⱼ_max]` such that
/// `cⱼ·v + S` satisfies the comparison. This is bounds consistency,
/// not GAC — interior values inconsistent with all extreme
/// assignments are still pruned, but values inconsistent only with
/// specific *combinations* of the others' values are not.
///
/// Mutates [domains] in place via [applyUpdate]. Returns the set of
/// variables whose domains were reduced, or `null` if the constraint
/// is infeasible.
///
/// Variables in the constraint with non-numeric values in their
/// current domain are skipped (the propagator does no pruning, and
/// soundness still rides on the predicate at the leaf).
class _LinearPropagator {
  _LinearPropagator(this.vars, this.spec, this.domains, this.applyUpdate,
      {this.originalDomains});

  final List<String> vars;
  final LinearSpec spec;
  final Map<String, _DomainRep> domains;

  /// Domain-update callback with optional [reason] kwarg for the LCG
  /// implication trail (M3b: [LinearBoundReason]). Non-LCG callers
  /// pass null and the parameter is ignored.
  final void Function(String varName, _DomainRep newDom,
      {ImplicationReason? reason}) applyUpdate;

  /// User-declared domain for each variable in [vars], used to build
  /// per-prune bound explanations. Null when the engine isn't running
  /// in LCG mode — in that case the propagator skips the
  /// explanation-construction work entirely.
  final Map<String, List<dynamic>>? originalDomains;

  bool get _lcgEnabled => originalDomains != null;

  Set<String>? propagate() {
    final n = vars.length;
    if (n == 0) return <String>{};

    // Per-var current min/max. Bail out if any domain is empty or
    // contains a non-numeric value (the propagator only handles
    // numeric domains).
    final mins = List<num>.filled(n, 0);
    final maxs = List<num>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final dom = domains[vars[i]]!;
      if (dom.isEmpty) return null;
      if (dom.first is! num) return <String>{};
      var lo = dom.first as num;
      var hi = lo;
      for (final v in dom.values) {
        if (v is! num) return <String>{};
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      mins[i] = lo;
      maxs[i] = hi;
    }

    // Total interval [sMin, sMax] of Σ coeffs[i]·vars[i].
    num sMin = 0, sMax = 0;
    for (var i = 0; i < n; i++) {
      final c = spec.coeffs[i];
      if (c >= 0) {
        sMin += c * mins[i];
        sMax += c * maxs[i];
      } else {
        sMin += c * maxs[i];
        sMax += c * mins[i];
      }
    }

    // Cheap global feasibility / already-satisfied check.
    switch (spec.op) {
      case LinearOp.eq:
        if (spec.bound < sMin || spec.bound > sMax) return null;
        break;
      case LinearOp.leq:
        if (sMin > spec.bound) return null;
        if (sMax <= spec.bound) return <String>{}; // entailed
        break;
      case LinearOp.geq:
        if (sMax < spec.bound) return null;
        if (sMin >= spec.bound) return <String>{}; // entailed
        break;
    }

    final changed = <String>{};
    for (var j = 0; j < n; j++) {
      final cj = spec.coeffs[j];
      if (cj == 0) continue;

      // Interval [sjMin, sjMax] of Σᵢ≠ⱼ coeffs[i]·vars[i] — i.e.,
      // subtract j's own contribution from the total interval.
      final jLo = cj >= 0 ? cj * mins[j] : cj * maxs[j];
      final jHi = cj >= 0 ? cj * maxs[j] : cj * mins[j];
      final sjMin = sMin - jLo;
      final sjMax = sMax - jHi;

      final dom = domains[vars[j]]!;
      final newDom = dom.filter((v) {
        final cjv = cj * (v as num);
        switch (spec.op) {
          case LinearOp.eq:
            // ∃ S ∈ [sjMin, sjMax]. cj·v + S == bound
            return cjv >= spec.bound - sjMax && cjv <= spec.bound - sjMin;
          case LinearOp.leq:
            // ∃ S ∈ [sjMin, sjMax]. cj·v + S ≤ bound, i.e. with S=sjMin
            return cjv + sjMin <= spec.bound;
          case LinearOp.geq:
            // ∃ S ∈ [sjMin, sjMax]. cj·v + S ≥ bound, i.e. with S=sjMax
            return cjv + sjMax >= spec.bound;
        }
      });
      if (newDom.length != dom.length) {
        if (newDom.isEmpty) return null;
        ImplicationReason? reason;
        if (_lcgEnabled) reason = _buildBoundReason(j);
        applyUpdate(vars[j], newDom, reason: reason);
        changed.add(vars[j]);
      }
    }
    return changed;
  }

  /// Build the [LinearBoundReason] for prunes of variable `j`. The
  /// natural bounds-shaped explanation is "the other variables have
  /// bounds [lbᵢ, ubᵢ], so v must be in this range" but the dart_csp
  /// implication trail emits only `AtomEq` / `AtomNe` entries, so
  /// `AtomLe` / `AtomGe` antecedents wouldn't resolve cleanly. The
  /// coarse-but-sound shape (matching M3a) is: `AtomNe(xᵢ, k)` for
  /// every *other* variable `xᵢ` in the constraint and every value
  /// `k` declared in `xᵢ`'s original domain but absent from its
  /// current domain.
  ///
  /// A reified-bound-atom rewrite (task 2 in `LCG_PLAN.md` §3) was
  /// attempted on top of the M3-tighten `AtomInScc` work and **reverted**:
  /// emitting `AtomGe`/`AtomLe` on the trail and referencing them here
  /// *regressed* the 4×4 magic square (5 → 4 learned clauses, below the
  /// acceptance gate). Those conflicts are allDifferent-detected, and
  /// routing the linear prunes through on-trail bound atoms re-introduced
  /// non-collapsing at-conflict-level atoms during the allDifferent
  /// resolution walk. The coarse `AtomNe` shape — whose absences for a
  /// pinned variable are *off-trail* and so treated as structural facts —
  /// converges better here. See the lesson banked in `LCG_PLAN.md`.
  ImplicationReason _buildBoundReason(int j) {
    final atoms = <Atom>[];
    final orig = originalDomains!;
    for (var i = 0; i < vars.length; i++) {
      if (i == j) continue;
      final iName = vars[i];
      final iOrig = orig[iName];
      if (iOrig == null) continue;
      atoms.addAll(_domainShapeAntecedents(iName, iOrig, domains[iName]!));
    }
    return LinearBoundReason(atoms);
  }
}

/// Partial-state propagator for the `regular` constraint (Pesant
/// 2004, "A Regular Language Membership Constraint for Finite
/// Sequences of Variables").
///
/// Given a DFA and a sequence of variables, the propagator builds
/// per-position *active* DFA-state sets by:
///
/// 1. Forward sweep — `forward[i+1]` is the set of states reachable
///    from `forward[i]` by reading some value `v` in `dom(vars[i])`.
/// 2. Backward sweep — restrict each `forward[i]` to states from
///    which some path to an accepting state at position `n` exists,
///    using only values currently in each variable's domain.
///
/// A value `v` in `dom(vars[i])` is kept iff there exists an active
/// state `q` at position `i` whose transition on `v` lands in an
/// active state at position `i+1`. This is generalized arc
/// consistency for the regular constraint.
///
/// Mutates [domains] via [applyUpdate]. Returns the set of variables
/// whose domains were reduced, or `null` if the constraint is
/// infeasible.
class _RegularPropagator {
  _RegularPropagator(this.vars, this.dfa, this.domains, this.applyUpdate);

  final List<String> vars;
  final Dfa dfa;
  final Map<String, _DomainRep> domains;
  final void Function(String varName, _DomainRep newDom) applyUpdate;

  Set<String>? propagate() {
    final n = vars.length;
    // Empty sequence: only accept if the start state is accepting.
    if (n == 0) {
      return dfa.accepting.contains(dfa.start) ? <String>{} : null;
    }

    // Forward pass: forward[i] holds DFA states reachable at
    // position i via *some* assignment of vars[0..i-1] from current
    // domains.
    final forward = List<Set<int>>.generate(n + 1, (_) => <int>{});
    forward[0].add(dfa.start);
    for (var i = 0; i < n; i++) {
      final dom = domains[vars[i]]!;
      if (dom.isEmpty) return null;
      final next = forward[i + 1];
      for (final q in forward[i]) {
        final trans = dfa.transitions[q];
        if (trans == null) continue;
        for (final v in dom.values) {
          final qp = trans[v];
          if (qp != null) next.add(qp);
        }
      }
      if (next.isEmpty) return null;
    }

    // Backward pass: backward[i] holds states in forward[i] that
    // can still reach some accepting state at position n via
    // current domain values. backward[n] = forward[n] ∩ accepting.
    final backward = List<Set<int>>.generate(n + 1, (_) => <int>{});
    for (final q in forward[n]) {
      if (dfa.accepting.contains(q)) backward[n].add(q);
    }
    if (backward[n].isEmpty) return null;
    for (var i = n - 1; i >= 0; i--) {
      final dom = domains[vars[i]]!;
      final here = backward[i];
      for (final q in forward[i]) {
        final trans = dfa.transitions[q];
        if (trans == null) continue;
        for (final v in dom.values) {
          final qp = trans[v];
          if (qp != null && backward[i + 1].contains(qp)) {
            here.add(q);
            break;
          }
        }
      }
      if (here.isEmpty) return null;
    }
    // Start state must reach accepting via current domains.
    if (!backward[0].contains(dfa.start)) return null;

    // Prune each variable's domain to values supported by some
    // active state transition.
    final changed = <String>{};
    for (var i = 0; i < n; i++) {
      final oldDom = domains[vars[i]]!;
      final activeHere = backward[i];
      final activeNext = backward[i + 1];
      final newDom = oldDom.filter((v) {
        for (final q in activeHere) {
          final qp = dfa.transitions[q]?[v];
          if (qp != null && activeNext.contains(qp)) return true;
        }
        return false;
      });
      if (newDom.length != oldDom.length) {
        if (newDom.isEmpty) return null;
        applyUpdate(vars[i], newDom);
        changed.add(vars[i]);
      }
    }
    return changed;
  }
}

/// Cycle-detection propagator for the `circuit` and `subcircuit`
/// constraints.
///
/// Interprets the constraint's [vars] as the successor function of
/// a Hamiltonian cycle: `vars[i]` should hold the position visited
/// after `i`, with `vars.length` positions in total. In
/// [subcircuit] mode a self-loop `vars[i] = i` is permitted and
/// means "position `i` is not in the cycle"; the remaining
/// non-self-loop edges still have to form a single cycle (possibly
/// empty, when every position self-loops).
///
/// On each call the propagator builds the partial graph of fixed
/// successor edges (those induced by singleton-domain variables)
/// and:
///
/// 1. Rejects assignments that imply two predecessors for the same
///    node (the successor function must be a permutation, including
///    self-loops which consume their own value).
/// 2. Rejects a self-loop `vars[i] = i` in circuit mode unless
///    `n == 1`.
/// 3. Rejects a pure cycle of length `< n` formed entirely by
///    non-self-loop singleton edges — in circuit mode that's a
///    strict sub-cycle; in subcircuit mode that's only valid when
///    every non-cycle position can be skipped, in which case those
///    positions are forced to self-loop.
/// 4. For each maximal chain `h → ... → t` of non-self-loop fixed
///    edges, removes every intermediate chain node from `t`'s
///    domain (closing on an intermediate forces the chain's
///    interior to have two predecessors). In circuit mode the head
///    is also pruned unless the chain covers every position; in
///    subcircuit mode the head is pruned unless every non-chain
///    position can be skipped, and the head is forced when every
///    non-chain position is already committed to self-loop.
/// 5. For any value `v` already produced by a fixed edge (whether
///    `vars[i] = v` with `i != v` or the self-loop `vars[v] = v`),
///    removes `v` from every other variable's domain — enforces
///    successor uniqueness across the permutation including the
///    self-loop slots.
///
/// Mutates [domains] via [applyUpdate]. Returns the set of variables
/// whose domains were reduced, or `null` if the constraint is
/// infeasible.
class _CircuitPropagator {
  _CircuitPropagator(this.vars, this.domains, this.applyUpdate,
      {this.subcircuit = false});

  final List<String> vars;
  final Map<String, _DomainRep> domains;
  final void Function(String varName, _DomainRep newDom) applyUpdate;
  final bool subcircuit;

  Set<String>? propagate() {
    final n = vars.length;
    if (n == 0) return <String>{};

    // Build the singleton-edge graph. `next[i] = j` and `pred[j] = i`
    // record a fixed non-self-loop edge `i → j`; both arrays carry
    // -1 for "no fixed edge". `selfLoop[i]` records the skipped
    // positions in subcircuit mode (they participate in successor
    // uniqueness but never appear in chains or cycles).
    final next = List<int>.filled(n, -1);
    final pred = List<int>.filled(n, -1);
    final selfLoop = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      final dom = domains[vars[i]]!;
      if (dom.length == 1) {
        final v = dom.first;
        if (v is! int) return null;
        if (v < 0 || v >= n) return null;
        if (v == i) {
          if (!subcircuit && n > 1) return null; // self-loop only valid n=1
          if (pred[i] != -1) return null; // i already pointed to by some j
          selfLoop[i] = true;
        } else {
          if (pred[v] != -1) return null; // two predecessors
          if (selfLoop[v]) return null; // value v already consumed as a skip
          next[i] = v;
          pred[v] = i;
        }
      }
    }

    // Count committed-skipped (must be skipped) and committed-in-cycle
    // (cannot be skipped) positions globally. Used to tighten the
    // chain-closing decision in subcircuit mode. These counters are
    // *mutated* within this call when the propagator itself forces a
    // node to self-loop (e.g. after detecting a non-Hamiltonian pure
    // cycle), so later chain iterations see the up-to-date picture.
    var committedSkip = 0;
    var committedInCycle = 0;
    if (subcircuit) {
      for (var i = 0; i < n; i++) {
        final dom = domains[vars[i]]!;
        if (selfLoop[i]) {
          committedSkip++;
        } else if (!dom.contains(i)) {
          committedInCycle++;
        }
      }
    }

    final changed = <String>{};
    final visited = List<bool>.filled(n, false);

    // Walk the singleton graph. Each unvisited non-skipped node
    // belongs either to a chain (a path leading away from some chain
    // head whose predecessor is unfixed) or to a pure cycle (every
    // node in the cycle has a singleton predecessor edge). In circuit
    // mode a pure cycle is OK iff it visits all `n` nodes. In
    // subcircuit mode a pure cycle of length `L < n` is OK iff every
    // non-cycle position is or can be made a skip.
    for (var start = 0; start < n; start++) {
      if (visited[start]) continue;
      if (subcircuit && selfLoop[start]) {
        visited[start] = true;
        continue; // skipped position — isolated, no chain
      }

      // Walk backward from `start` until we either hit a chain head
      // (pred[head] == -1) or loop back to `start` (pure cycle).
      var head = start;
      var isPureCycle = false;
      while (pred[head] != -1) {
        final p = pred[head];
        if (p == start) {
          isPureCycle = true;
          break;
        }
        head = p;
      }

      if (isPureCycle) {
        // Collect the cycle and mark visited.
        final cycleNodes = <int>{};
        var len = 0;
        var x = start;
        do {
          visited[x] = true;
          cycleNodes.add(x);
          x = next[x];
          len++;
        } while (x != start);

        if (!subcircuit) {
          if (len != n) return null; // strict sub-cycle
          continue;
        }
        if (len == n) continue; // full Hamiltonian — done

        // Subcircuit: every non-cycle position MUST be skipped. If
        // any non-cycle position already has a fixed edge (it's in
        // another chain) or can't take its self-loop value, the
        // constraint is infeasible. Otherwise force the skip and
        // refresh the local accounting so later chain iterations
        // within this call don't read stale committed-in-cycle.
        for (var k = 0; k < n; k++) {
          if (cycleNodes.contains(k)) continue;
          if (selfLoop[k]) continue;
          if (next[k] != -1 || pred[k] != -1) return null;
          final kDom = domains[vars[k]]!;
          if (!kDom.contains(k)) return null;
          if (kDom.length > 1) {
            final newDom = kDom.filter((v) => v == k);
            applyUpdate(vars[k], newDom);
            changed.add(vars[k]);
          }
          selfLoop[k] = true;
          committedSkip++;
          visited[k] = true;
        }
        continue;
      }

      // It's a chain rooted at `head`. Walk forward.
      final chainNodes = <int>{};
      final chainOrder = <int>[];
      var tail = head;
      visited[tail] = true;
      chainNodes.add(tail);
      chainOrder.add(tail);
      while (next[tail] != -1) {
        tail = next[tail];
        visited[tail] = true;
        chainNodes.add(tail);
        chainOrder.add(tail);
      }

      final chainLen = chainNodes.length;
      final tailVar = vars[tail];
      final tailDom = domains[tailVar]!;

      if (!subcircuit) {
        if (chainLen == n) {
          // Full circuit modulo the tail's successor — force tail → head.
          if (!tailDom.contains(head)) return null;
          if (tailDom.length > 1) {
            final newDom = tailDom.filter((v) => v == head);
            applyUpdate(tailVar, newDom);
            changed.add(tailVar);
          }
        } else {
          // Prune every chain node from tail's domain — any of those
          // would close a premature sub-cycle (head closes a cycle of
          // length `chainLen`; an intermediate closes a shorter one).
          final newDom =
              tailDom.filter((v) => !(v is int && chainNodes.contains(v)));
          if (newDom.length != tailDom.length) {
            if (newDom.isEmpty) return null;
            applyUpdate(tailVar, newDom);
            changed.add(tailVar);
          }
        }
      } else {
        // Subcircuit chain handling:
        //  * Intermediate chain nodes (everything in the chain except
        //    the head and the tail itself) are never valid successors
        //    for the tail — closing there gives that intermediate two
        //    predecessors.
        //  * `tail` itself (self-loop on the tail) is invalid whenever
        //    the chain has length > 1, because tail is already the
        //    successor of `chainOrder[-2]` and can't simultaneously be
        //    skipped (skipping consumes value `tail`).
        //  * `head` is valid iff every position outside the chain can
        //    be skipped (i.e. no committed-in-cycle node is left
        //    stranded). When the chain plus committed skips already
        //    cover every position, head is the only choice and is
        //    forced.
        final intermediate = <int>{};
        for (var k = 1; k < chainOrder.length - 1; k++) {
          intermediate.add(chainOrder[k]);
        }
        // For chainLen >= 2, every chain node has a singleton
        // non-self-loop domain so it's committed-in-cycle by
        // construction. For chainLen == 1, the lone node may or may
        // not be committed-in-cycle, and "closing at head" is just a
        // self-loop — which doesn't preclude other cycles, so we
        // never prune the head in that case.
        final closesCycle = chainLen >= 2;
        final outsideMustCycle = committedInCycle - chainLen;
        final pruneTailSelf = chainLen > 1; // tail can't self-loop in a chain
        final pruneHead = closesCycle && outsideMustCycle > 0;
        final forceHead = chainLen + committedSkip == n;

        bool keep(dynamic v) {
          if (v is! int) return true;
          if (intermediate.contains(v)) return false;
          if (pruneTailSelf && v == tail) return false;
          if (pruneHead && v == head) return false;
          if (forceHead && v != head) return false;
          return true;
        }

        final newDom = tailDom.filter(keep);
        if (newDom.length != tailDom.length) {
          if (newDom.isEmpty) return null;
          applyUpdate(tailVar, newDom);
          changed.add(tailVar);
        } else if (forceHead && !tailDom.contains(head)) {
          return null;
        }
        // If a length-1 "chain" just got forced into a self-loop
        // (head == tail and forceHead pinned the value to head), the
        // local accounting must promote it to a committed skip so
        // later chain iterations and the uniqueness pass see the
        // right state.
        if (forceHead && chainLen == 1 && !selfLoop[tail]) {
          selfLoop[tail] = true;
          committedSkip++;
        }
      }
    }

    // Successor uniqueness: each value `v` already produced by a
    // fixed edge (or consumed as a skip) can be held by only that one
    // variable. Remove `v` from every other variable's domain.
    for (var v = 0; v < n; v++) {
      final p = pred[v];
      final isSkip = selfLoop[v];
      if (p == -1 && !isSkip) continue;
      final owner = isSkip ? v : p;
      for (var j = 0; j < n; j++) {
        if (j == owner) continue;
        final dom = domains[vars[j]]!;
        if (dom.length == 1) continue; // already a singleton elsewhere
        if (dom.contains(v)) {
          final newDom = dom.filter((x) => x != v);
          if (newDom.isEmpty) return null;
          applyUpdate(vars[j], newDom);
          changed.add(vars[j]);
        }
      }
    }

    return changed;
  }
}

/// Network-flow propagator for the global cardinality constraint
/// (Régin, "Generalized arc consistency for global cardinality
/// constraint", AAAI 1996).
///
/// Generalizes [_AllDifferentPropagator] to handle multiplicity: each
/// value `v` is replicated into `upper[v]` "copies" in the bipartite
/// matching graph, so up to `upper[v]` variables can be matched to it.
/// The propagator then computes the maximum matching, builds the
/// residual graph, and (when the matching distribution is consistent
/// with the lower bounds) prunes any variable→value edge that does
/// not lie on some maximum matching.
///
/// **Lower-bound handling (v1, conservative).** When the maximum
/// matching's per-value count falls outside its `[lower, upper]`
/// range for any value, the propagator returns an empty change set
/// rather than risking incorrect pruning — the leaf predicate then
/// catches actual infeasibility. This sacrifices full GAC on the
/// lower-bound side in exchange for guaranteed correctness with the
/// simpler matching formulation. Pure upper-bound GCCs (all `lower
/// == 0`) and exact-count GCCs whose maximum matching naturally
/// saturates the bounds receive the full Régin pruning.
///
/// Mutates [domains] via [applyUpdate]. Returns the set of variables
/// whose domains were reduced, or `null` if the constraint is
/// definitely infeasible (max matching cannot cover all variables,
/// or capacity is insufficient).
class _GccPropagator {
  _GccPropagator(this.vars, this.spec, this.domains, this.applyUpdate);

  final List<String> vars;
  final GccSpec spec;
  final Map<String, _DomainRep> domains;
  final void Function(String varName, _DomainRep newDom) applyUpdate;

  Set<String>? propagate() {
    final n = vars.length;
    if (n == 0) return <String>{};

    // Index every value that could plausibly be relevant: values
    // appearing in any variable's domain, plus spec values not in
    // any domain (which would force infeasibility if their lower
    // bound is positive — but we must enumerate them to detect it).
    final valIdx = <dynamic, int>{};
    final valList = <dynamic>[];
    for (final vName in vars) {
      final dom = domains[vName]!;
      if (dom.isEmpty) return null;
      for (final val in dom.values) {
        if (!valIdx.containsKey(val)) {
          valIdx[val] = valList.length;
          valList.add(val);
        }
      }
    }
    for (final specVal in spec.bounds.keys) {
      if (!valIdx.containsKey(specVal)) {
        valIdx[specVal] = valList.length;
        valList.add(specVal);
      }
    }
    final numDistinct = valList.length;

    // Resolve (lower, upper) bounds per value. Unspecified values
    // get (0, n) — unconstrained. Spec'd uppers are capped at n.
    final lower = List<int>.filled(numDistinct, 0);
    final upper = List<int>.filled(numDistinct, n);
    for (var i = 0; i < numDistinct; i++) {
      final b = spec.bounds[valList[i]];
      if (b != null) {
        lower[i] = b.min;
        upper[i] = b.max < n ? b.max : n;
      }
    }

    // Quick capacity check: must have enough total copies to cover
    // all variables.
    var totalCapacity = 0;
    for (var i = 0; i < numDistinct; i++) {
      totalCapacity += upper[i];
    }
    if (totalCapacity < n) return null;

    // Build value-copy index ranges. Copy index `copyStart[i] + k`
    // corresponds to the k-th replica of value i, for
    // `k ∈ [0, upper[i])`.
    final copyStart = List<int>.filled(numDistinct, 0);
    var totalCopies = 0;
    for (var i = 0; i < numDistinct; i++) {
      copyStart[i] = totalCopies;
      totalCopies += upper[i];
    }
    final m = totalCopies;
    final copyToVal = List<int>.filled(m, 0);
    for (var i = 0; i < numDistinct; i++) {
      for (var k = 0; k < upper[i]; k++) {
        copyToVal[copyStart[i] + k] = i;
      }
    }

    // Adjacency: variable index → list of value-copy indices.
    final varAdj = List<List<int>>.generate(n, (i) {
      final list = <int>[];
      for (final val in domains[vars[i]]!.values) {
        final vi = valIdx[val]!;
        for (var k = 0; k < upper[vi]; k++) {
          list.add(copyStart[vi] + k);
        }
      }
      return list;
    });

    // Maximum bipartite matching.
    final matchVar = List<int>.filled(n, -1);
    final matchVal = List<int>.filled(m, -1);
    if (!_hopcroftKarp(varAdj, n, m, matchVar, matchVal)) {
      return null;
    }

    // Count matched copies per value. If the distribution falls
    // outside any value's [lower, upper] window, the matching we
    // found doesn't certify the bounds. At a leaf (every variable
    // is a singleton) there is only one possible matching — the
    // assignment itself — so a bounds violation is a real
    // infeasibility and must be reported. Otherwise, fall back to
    // no pruning: a different feasible distribution might exist
    // among the multiple max matchings.
    final matchCount = List<int>.filled(numDistinct, 0);
    for (var i = 0; i < n; i++) {
      matchCount[copyToVal[matchVar[i]]]++;
    }
    var allSingleton = true;
    for (final vName in vars) {
      if (domains[vName]!.length != 1) {
        allSingleton = false;
        break;
      }
    }
    for (var i = 0; i < numDistinct; i++) {
      if (matchCount[i] < lower[i] || matchCount[i] > upper[i]) {
        if (allSingleton) return null;
        return <String>{};
      }
    }

    // Build directed residual graph used for SCC + free-copy
    // reachability. Node ids: 0..n-1 are variables, n..n+m-1 are
    // value copies.
    final totalNodes = n + m;
    final dAdj = List<List<int>>.generate(totalNodes, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      for (final j in varAdj[i]) {
        if (matchVar[i] == j) {
          dAdj[n + j].add(i); // matched: value-copy → variable
        } else {
          dAdj[i].add(n + j); // unmatched: variable → value-copy
        }
      }
    }
    final sccOf = _kosarajuScc(dAdj, totalNodes);

    // Free-value reachability: value-copies that are not currently
    // matched are "free", and any node reachable from them in the
    // residual is on some alternative max matching.
    final reachable = List<bool>.filled(totalNodes, false);
    for (var j = 0; j < m; j++) {
      if (matchVal[j] == -1) {
        _dfsMark(n + j, dAdj, reachable);
      }
    }

    // For each variable, keep value `v` iff at least one of its
    // copies is "alive" (currently matched to this var, in the same
    // SCC, or reachable from a free copy). Per-variable matched-copy
    // and SCC id are hoisted out of the inner filter.
    final changed = <String>{};
    for (var i = 0; i < n; i++) {
      final oldDom = domains[vars[i]]!;
      final matchedCp = matchVar[i];
      final sccI = sccOf[i];
      final newDom = oldDom.filter((val) {
        final vi = valIdx[val]!;
        final upperVi = upper[vi];
        final startVi = copyStart[vi];
        for (var k = 0; k < upperVi; k++) {
          final cp = startVi + k;
          final cpNode = n + cp;
          if (matchedCp == cp || sccI == sccOf[cpNode] || reachable[cpNode]) {
            return true;
          }
        }
        return false;
      });
      if (newDom.length != oldDom.length) {
        if (newDom.isEmpty) return null;
        applyUpdate(vars[i], newDom);
        changed.add(vars[i]);
      }
    }
    return changed;
  }
}

/// Time-table propagator for the cumulative resource constraint
/// (Beldiceanu & Carlsson, "A New Multi-Resource cumulatives
/// Constraint with Negative Heights", CP 2002).
///
/// Each [vars][i] is the start variable of one task; [spec] holds
/// the per-task constant durations and demands plus the resource
/// capacity. The propagator:
///
/// 1. Reads each task's earliest start `est_i = min(dom(vars[i]))`
///    and latest start `lst_i = max(dom(vars[i]))`.
/// 2. Computes its *compulsory part* — the interval `[lst_i, est_i +
///    dur_i)` the task must occupy in every feasible schedule when
///    that interval is non-empty (i.e. `lst_i < est_i + dur_i`).
/// 3. Sums the compulsory parts into a sparse usage profile
///    (`Map<int, int>` from time → demand-sum). A compulsory-part
///    pile-up that exceeds [CumulativeSpec.capacity] at any time
///    is immediate infeasibility.
/// 4. For each task `i`, prunes each candidate start `s` for which
///    *some* `t ∈ [s, s + dur_i)` would push the profile above
///    capacity once `i`'s own demand is added (and `i`'s own
///    compulsory contribution at that time, if any, removed first
///    so the task is not double-counted).
///
/// Soundness rides on the standard pruning path: when every start
/// is singleton each task's compulsory part is exactly its
/// scheduled interval, the profile equals the realized usage, and
/// any over-capacity time-step forces the single feasible candidate
/// out of some task's domain — the engine then reports
/// infeasibility from the resulting empty domain. No separate leaf
/// check is required.
///
/// Mutates [domains] via [applyUpdate]. Returns the set of
/// variables whose domains were reduced, or `null` if the
/// constraint is infeasible.
class _CumulativePropagator {
  _CumulativePropagator(this.vars, this.spec, this.domains, this.applyUpdate);

  final List<String> vars;
  final CumulativeSpec spec;
  final Map<String, _DomainRep> domains;
  final void Function(String varName, _DomainRep newDom) applyUpdate;

  Set<String>? propagate() {
    final n = vars.length;
    if (n == 0) return <String>{};

    final durations = spec.durations;
    final demands = spec.demands;
    final capacity = spec.capacity;

    // Single-task feasibility: a task whose own demand exceeds
    // capacity can never be scheduled (its compulsory contribution
    // alone violates the resource bound).
    for (var i = 0; i < n; i++) {
      if (durations[i] > 0 && demands[i] > capacity) return null;
    }

    // Per-task earliest and latest start. Walk each domain once to
    // find the bounds — for bitset and interval reps the iteration is
    // ascending so this is cheap; for list reps with non-monotonic
    // contents the full scan is necessary.
    final ests = List<int>.filled(n, 0);
    final lsts = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final dom = domains[vars[i]]!;
      if (dom.isEmpty) return null;
      final first = dom.first;
      if (first is! int) {
        // Non-integer domain: defer to the predicate at the leaf.
        return <String>{};
      }
      var lo = first;
      var hi = first;
      for (final v in dom.values) {
        if (v is! int) return <String>{};
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      ests[i] = lo;
      lsts[i] = hi;
    }

    // Compulsory-part profile. Sparse Map<int, int> keyed by time;
    // value is the sum of demands of tasks whose compulsory part
    // covers that time. Infeasible immediately if compulsory parts
    // alone exceed capacity at some time.
    final profile = <int, int>{};
    for (var i = 0; i < n; i++) {
      final dur = durations[i];
      final dem = demands[i];
      if (dur == 0 || dem == 0) continue;
      final cStart = lsts[i];
      final cEnd = ests[i] + dur;
      if (cStart >= cEnd) continue;
      for (var t = cStart; t < cEnd; t++) {
        final next = (profile[t] ?? 0) + dem;
        if (next > capacity) return null;
        profile[t] = next;
      }
    }

    // Prune each task's start domain to feasible positions.
    final changed = <String>{};
    for (var i = 0; i < n; i++) {
      final dur = durations[i];
      final dem = demands[i];
      if (dur == 0 || dem == 0) continue;
      final lstI = lsts[i];
      final cEndI = ests[i] + dur;
      final hasComp = lstI < cEndI;

      final dom = domains[vars[i]]!;
      final newDom = dom.filter((vv) {
        final s = vv as int;
        final endS = s + dur;
        for (var t = s; t < endS; t++) {
          var p = profile[t] ?? 0;
          // Remove this task's own compulsory contribution at t so
          // its demand isn't counted twice when we test placing it
          // here.
          if (hasComp && t >= lstI && t < cEndI) {
            p -= dem;
          }
          if (p + dem > capacity) return false;
        }
        return true;
      });

      if (newDom.length != dom.length) {
        if (newDom.isEmpty) return null;
        applyUpdate(vars[i], newDom);
        changed.add(vars[i]);
      }
    }
    return changed;
  }
}

/// Forbidden-region sweep propagator for the 2D rectangle non-overlap
/// global constraint (`diff_n`), following Beldiceanu & Carlsson,
/// "Sweep as a generic pruning technique applied to the non-
/// overlapping rectangles constraint" (CP 2001).
///
/// The constraint owns `2n` variables laid out as
/// `[xs..., ys...]` — the first `n` entries are the lower-left `x`
/// coordinates of the `n` rectangles, the next `n` entries are the
/// matching `y` coordinates. Per-rectangle [DiffNSpec.widths] /
/// [DiffNSpec.heights] are constants supplied in the spec.
///
/// Pruning works per rectangle, per dimension. To prune `r`'s
/// coordinate in dimension `d`, the propagator aggregates a set of
/// **forbidden intervals** induced by every other rectangle `s`:
///
///   1. Test whether `r` and `s` *must* overlap in the orthogonal
///      dimension `d'` regardless of where they end up placed. This
///      holds iff
///        `max(d'_lst[r], d'_lst[s]) < min(d'_est[r] + len_{d'}(r),`
///                                         `d'_est[s] + len_{d'}(s))`
///      — i.e. the compulsory parts of `r` and `s` in `d'` intersect.
///      (`est`/`lst` are the earliest/latest coordinate currently in
///      the variable's domain.) If they cannot mandatorily overlap in
///      `d'`, `s` cannot force `r`'s coordinate in `d`.
///   2. If they do mandatorily overlap in `d'`, then the placement
///      of `r` in `d` must avoid the half-open box of `s` in `d`.
///      The set of `d`-positions for `r` that *cannot* be separated
///      from `s` in `d` — for any value of `s`'s own `d`-coordinate —
///      is the interval
///        `[d_lst[s] - len_d(r) + 1, d_est[s] + len_d(s) - 1]`.
///      Those positions are forbidden for `r` in `d`.
///
/// The pruning filter applied to `r`'s `d`-domain rejects every value
/// inside any of the resulting forbidden intervals. If the filter
/// empties a rectangle's domain, the propagator returns `null` so the
/// engine reports infeasibility. Otherwise the filtered domain is
/// installed via [applyUpdate] and the variable is added to the
/// returned `changed` set.
///
/// **Leaf check.** Tagged constraints bypass the engine's generic
/// `_reviseNary` path, so the predicate is never invoked at leaves;
/// soundness rides on this propagator. At a leaf every variable is
/// a singleton, so each rectangle's `est == lst` in both dimensions.
/// For any overlapping pair `(r, s)` the compulsory-overlap test in
/// the orthogonal dimension is true and the forbidden interval in
/// the other dimension contains `r`'s singleton value; the filter
/// empties `r`'s domain and the propagator returns `null`. No
/// separate leaf check is needed.
///
/// **Soundness for non-integer coordinates.** The propagator assumes
/// integer domains. If any variable's domain contains a non-`int`
/// value the propagator returns an empty `changed` set so the leaf
/// predicate is responsible for catching overlaps. (`addDiffN` only
/// validates non-negative widths and heights; coordinate domains are
/// not restricted to `int`, but in practice every test in the suite
/// uses integer coordinates.)
///
/// **Complexity.** O(n²) per call to compute pairwise compulsory-
/// overlap tests; one pass over each variable's domain via
/// `_DomainRep.filter`. The two passes (x then y) are independent
/// — they share the same `est`/`lst` arrays but the second pass
/// reads `est`/`lst` *after* the first pass's updates, so the
/// algorithm gracefully picks up tightened bounds within a single
/// `propagate()` call.
class _DiffNPropagator {
  _DiffNPropagator(this.vars, this.spec, this.domains, this.applyUpdate);

  final List<String> vars;
  final DiffNSpec spec;
  final Map<String, _DomainRep> domains;
  final void Function(String varName, _DomainRep newDom) applyUpdate;

  Set<String>? propagate() {
    final widths = spec.widths;
    final heights = spec.heights;
    final n = widths.length;
    if (n == 0) return <String>{};

    // Per-rectangle earliest/latest in x and y. We walk each domain
    // once: bitset and interval reps iterate ascending so it's cheap;
    // list reps may have non-monotonic contents so the full scan is
    // necessary. If any coordinate isn't an integer, defer to the
    // predicate by returning an empty change set.
    final xEst = List<int>.filled(n, 0);
    final xLst = List<int>.filled(n, 0);
    final yEst = List<int>.filled(n, 0);
    final yLst = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final xd = domains[vars[i]]!;
      final yd = domains[vars[n + i]]!;
      if (xd.isEmpty || yd.isEmpty) return null;
      final xf = xd.first;
      final yf = yd.first;
      if (xf is! int || yf is! int) return <String>{};
      var xLo = xf, xHi = xf, yLo = yf, yHi = yf;
      for (final v in xd.values) {
        if (v is! int) return <String>{};
        if (v < xLo) xLo = v;
        if (v > xHi) xHi = v;
      }
      for (final v in yd.values) {
        if (v is! int) return <String>{};
        if (v < yLo) yLo = v;
        if (v > yHi) yHi = v;
      }
      xEst[i] = xLo;
      xLst[i] = xHi;
      yEst[i] = yLo;
      yLst[i] = yHi;
    }

    final changed = <String>{};

    // Compulsory-part overlap test in the y dimension (used when
    // pruning x). Returns true iff for every (y_r, y_s) in the joint
    // y-domain, the y-projections of r and s overlap. Equivalent to
    // saying their compulsory y-parts intersect.
    bool mandatoryYOverlap(int r, int s) {
      final hr = heights[r], hs = heights[s];
      if (hr == 0 || hs == 0) return false;
      final lo = max(yLst[r], yLst[s]);
      final hi = min(yEst[r] + hr, yEst[s] + hs);
      return lo < hi;
    }

    // Mirror in x (used when pruning y).
    bool mandatoryXOverlap(int r, int s) {
      final wr = widths[r], ws = widths[s];
      if (wr == 0 || ws == 0) return false;
      final lo = max(xLst[r], xLst[s]);
      final hi = min(xEst[r] + wr, xEst[s] + ws);
      return lo < hi;
    }

    // Pass 1: prune each rectangle's x-coordinate.
    for (var r = 0; r < n; r++) {
      final wr = widths[r];
      if (wr == 0 || heights[r] == 0) continue;
      // Collect forbidden x-intervals induced by other rectangles
      // whose y-compulsory-part overlaps r's y-compulsory-part. Each
      // forbidden interval is inclusive on both ends.
      final lo = <int>[];
      final hi = <int>[];
      for (var s = 0; s < n; s++) {
        if (s == r) continue;
        if (widths[s] == 0 || heights[s] == 0) continue;
        if (!mandatoryYOverlap(r, s)) continue;
        final fLo = xLst[s] - wr + 1;
        final fHi = xEst[s] + widths[s] - 1;
        if (fLo <= fHi) {
          lo.add(fLo);
          hi.add(fHi);
        }
      }
      if (lo.isEmpty) continue;

      final xdom = domains[vars[r]]!;
      final m = lo.length;
      final newDom = xdom.filter((vv) {
        final v = vv as int;
        for (var k = 0; k < m; k++) {
          if (v >= lo[k] && v <= hi[k]) return false;
        }
        return true;
      });
      if (newDom.length == xdom.length) continue;
      if (newDom.isEmpty) return null;
      applyUpdate(vars[r], newDom);
      changed.add(vars[r]);
      // Refresh r's x-bounds so later iterations of this same
      // propagator call (e.g. the y pass below) see the tighter
      // bounds.
      var newLo = newDom.first as int;
      var newHi = newLo;
      for (final v in newDom.values) {
        final vi = v as int;
        if (vi < newLo) newLo = vi;
        if (vi > newHi) newHi = vi;
      }
      xEst[r] = newLo;
      xLst[r] = newHi;
    }

    // Pass 2: prune each rectangle's y-coordinate. Mirror of pass 1.
    for (var r = 0; r < n; r++) {
      final hr = heights[r];
      if (hr == 0 || widths[r] == 0) continue;
      final lo = <int>[];
      final hi = <int>[];
      for (var s = 0; s < n; s++) {
        if (s == r) continue;
        if (widths[s] == 0 || heights[s] == 0) continue;
        if (!mandatoryXOverlap(r, s)) continue;
        final fLo = yLst[s] - hr + 1;
        final fHi = yEst[s] + heights[s] - 1;
        if (fLo <= fHi) {
          lo.add(fLo);
          hi.add(fHi);
        }
      }
      if (lo.isEmpty) continue;

      final ydom = domains[vars[n + r]]!;
      final m = lo.length;
      final newDom = ydom.filter((vv) {
        final v = vv as int;
        for (var k = 0; k < m; k++) {
          if (v >= lo[k] && v <= hi[k]) return false;
        }
        return true;
      });
      if (newDom.length == ydom.length) continue;
      if (newDom.isEmpty) return null;
      applyUpdate(vars[n + r], newDom);
      changed.add(vars[n + r]);
      var newLo = newDom.first as int;
      var newHi = newLo;
      for (final v in newDom.values) {
        final vi = v as int;
        if (vi < newLo) newLo = vi;
        if (vi > newHi) newHi = vi;
      }
      yEst[r] = newLo;
      yLst[r] = newHi;
    }

    return changed;
  }
}

/// Bridge between the engine's private [_DomainRep] hierarchy and the
/// public [DomainView] interface that the [Atom] hierarchy's
/// [Atom.isEntailedBy] reads from. Lazily caches `minValue` /
/// `maxValue` so repeated atom evaluations against the same domain
/// during a single propagator call don't re-scan the values.
///
/// Lives outside [_ClausePropagator] so other M3 propagator-companion
/// code paths can reuse it without dragging the propagator instance
/// along.
class _DomainViewAdapter implements DomainView {
  _DomainViewAdapter(this._rep);
  final _DomainRep _rep;
  int? _minCache;
  int? _maxCache;

  @override
  bool contains(int v) => _rep.contains(v);

  @override
  bool get isEmpty => _rep.isEmpty;

  @override
  bool get isSingleton => _rep.length == 1;

  @override
  int get minValue {
    final cached = _minCache;
    if (cached != null) return cached;
    final rep = _rep;
    if (rep is _IntervalRep) return _minCache = rep._min;
    if (rep is _BitsetRep) return _minCache = rep.first as int;
    var m = rep.values.first as int;
    for (final v in rep.values) {
      final iv = v as int;
      if (iv < m) m = iv;
    }
    return _minCache = m;
  }

  @override
  int get maxValue {
    final cached = _maxCache;
    if (cached != null) return cached;
    final rep = _rep;
    if (rep is _IntervalRep) return _maxCache = rep._max;
    var m = rep.values.first as int;
    for (final v in rep.values) {
      final iv = v as int;
      if (iv > m) m = iv;
    }
    return _maxCache = m;
  }
}

/// Per-clause state for the two-watched-literal scheme. Stored on
/// the engine in [_BacktrackEngine._clauseWatchers] and lazily
/// populated the first time each clause is propagated.
///
/// Both [watch1] and [watch2] are indices into the clause's literal
/// list and always point to non-falsified literals. When a watched
/// literal becomes falsified, the propagator scans for another non-
/// falsified literal to take over (the "swap") so the invariant
/// holds for the next call. A "false sentinel" value of `-1` marks
/// the special single-watcher case for clauses of length 1.
class _ClauseWatchState {
  _ClauseWatchState(this.watch1, this.watch2);
  int watch1;
  int watch2;
}

/// SAT-style two-watched-literal propagator for clause constraints
/// (Moskewicz, Madigan, Zhao, Zhang & Malik, "Chaff: engineering an
/// efficient SAT solver", DAC 2001).
///
/// Each literal `(varName, positive)` evaluates to one of three
/// states given the current domain of `varName` (a subset of
/// `{0, 1}`):
///
///   * **Satisfied** — only the satisfying value remains; the
///     literal is forced true and the whole clause is entailed.
///   * **Falsified** — only the falsifying value remains; the
///     literal cannot contribute to satisfying the clause.
///   * **Undetermined** — both `0` and `1` are still in the
///     variable's domain.
///
/// The propagator maintains two **watchers**, indices into the
/// literal list that always point to non-falsified literals. On
/// each call:
///
/// 1. If either watcher's literal is satisfied → clause entailed.
/// 2. Otherwise, for each watcher whose literal has become
///    falsified, scan the rest of the literals for any non-falsified
///    literal that isn't already the other watcher; swap the watcher
///    to it. This is the cheap O(1) amortized case once a clause is
///    "settled".
/// 3. If no replacement exists for a falsified watcher, the clause's
///    fate depends entirely on the other watcher:
///    * other watcher falsified → conflict (return `null`);
///    * other watcher undetermined → unit-propagate (force its
///      variable to the satisfying value);
///    * other watcher satisfied → entailed.
///
/// The watched-literal invariant is **monotone under backtrack**
/// because the engine's trail only restores previously-removed
/// values: a literal non-falsified at a deeper assignment is also
/// non-falsified at any shallower one. The propagator therefore
/// needs no trail-aware rollback for its watcher state. See
/// [_BacktrackEngine._clauseWatchers].
///
/// Pruning behavior is identical to the previous stateless single-
/// pass implementation; this is a pure perf change. Per-call work
/// drops from O(literals) to O(1) amortized once the watchers are
/// initialized, which matters for problems with many large clauses.
///
/// Mutates [domains] via [applyUpdate]. Returns the set of variables
/// whose domains were reduced, or `null` if the clause is
/// unsatisfiable. An empty clause (no literals) is always
/// unsatisfiable and returns `null` immediately.
class _ClausePropagator {
  _ClausePropagator(this.spec, this.domains, this.applyUpdate, this.watchers);

  final ClauseSpec spec;
  final Map<String, _DomainRep> domains;

  /// Domain-update callback. Optional [reason] is the
  /// [ImplicationReason] for the prune — populated by [_forceLiteral]
  /// with a [ClauseReason] carrying the antecedent atoms, so M2's
  /// first-UIP analyser can resolve back through the prune. Other
  /// propagators don't pass a reason (M3 will).
  final void Function(String varName, _DomainRep newDom,
      {ImplicationReason? reason}) applyUpdate;

  /// Per-engine side-table of watcher state, shared across calls so
  /// the watcher positions persist between propagations.
  final Map<ClauseSpec, _ClauseWatchState> watchers;

  /// 0 = falsified, 1 = undetermined, 2 = satisfied. Encoded as
  /// small ints so the inner loops compare-and-branch on a single
  /// register rather than a Dart enum value.
  static const int _falsified = 0;
  static const int _undetermined = 1;
  static const int _satisfied = 2;

  /// Number of literals in this clause, dispatching on whether
  /// [ClauseSpec.atoms] (LCG learned-clause shape) or
  /// [ClauseSpec.literals] (boolean shape) carries them.
  int get _litCount =>
      spec.atoms != null ? spec.atoms!.length : spec.literals.length;

  /// Evaluate the literal at [idx] against the current domain state.
  /// Dispatches on the [ClauseSpec] shape.
  int _evalAt(int idx) =>
      spec.atoms != null ? _evalAtAtom(idx) : _evalAtBool(idx);

  int _evalAtBool(int idx) {
    final lit = spec.literals[idx];
    final dom = domains[lit.varName]!;
    final has0 = dom.contains(0);
    final has1 = dom.contains(1);
    final hasSat = lit.positive ? has1 : has0;
    final hasFal = lit.positive ? has0 : has1;
    if (hasSat && !hasFal) return _satisfied;
    if (!hasSat && hasFal) return _falsified;
    return _undetermined;
  }

  int _evalAtAtom(int idx) {
    final atom = spec.atoms![idx];
    final dom = domains[atom.varName]!;
    if (dom.isEmpty) return _falsified;
    final view = _DomainViewAdapter(dom);
    if (atom.isEntailedBy(view)) return _satisfied;
    if (atom.negate().isEntailedBy(view)) return _falsified;
    return _undetermined;
  }

  /// First literal index that is *not* falsified and is not equal to
  /// either of [excl1] or [excl2]. `-1` if no such literal exists.
  /// Used to find a replacement for a falsified watcher.
  int _findNonFalsified(int excl1, int excl2) {
    final n = _litCount;
    for (var i = 0; i < n; i++) {
      if (i == excl1 || i == excl2) continue;
      if (_evalAt(i) != _falsified) return i;
    }
    return -1;
  }

  /// Antecedent atoms for the unit-prop at [idx]. The propagator
  /// only unit-props when every literal other than `idx` is
  /// currently falsified, so the antecedent set is exactly those
  /// other literals translated into the atom whose truth makes them
  /// false:
  ///
  ///   * Boolean clauses: a positive literal `(v, true)` falsified
  ///     ⇒ `v == 0` ⇒ `AtomEq(v, 0)`; a negative literal `(v, false)`
  ///     falsified ⇒ `v == 1` ⇒ `AtomEq(v, 1)`.
  ///   * Atom clauses: each other literal `L_i` is falsified means
  ///     `L_i.negate()` is entailed; that negation is the antecedent.
  ///
  /// The list shape (rather than a Set) preserves clause iteration
  /// order for stable first-UIP results.
  List<Atom> _antecedentsForForce(int idx) {
    final n = _litCount;
    final out = <Atom>[];
    if (spec.atoms != null) {
      final atoms = spec.atoms!;
      for (var i = 0; i < n; i++) {
        if (i == idx) continue;
        out.add(atoms[i].negate());
      }
    } else {
      for (var i = 0; i < n; i++) {
        if (i == idx) continue;
        final lit = spec.literals[i];
        out.add(AtomEq(lit.varName, lit.positive ? 0 : 1));
      }
    }
    return out;
  }

  /// Force the literal at [idx] to be entailed. Returns the variable
  /// name on actual reduction, or null if the forced state was
  /// already satisfied (no-op), or the literal string `''` if forcing
  /// would empty the domain (caller treats as conflict).
  ///
  /// For boolean clauses the forcing is a pin to the satisfying
  /// value; for atom clauses it's the per-atom-kind domain filter
  /// (`AtomEq(v, k)` → keep only `k`; `AtomNe(v, k)` → drop `k`;
  /// `AtomLe(v, k)` → keep `v <= k`; `AtomGe(v, k)` → keep `v >= k`).
  String? _forceLiteral(int idx) {
    final String varName;
    final _DomainRep oldDom;
    final _DomainRep newDom;
    if (spec.atoms != null) {
      final atom = spec.atoms![idx];
      varName = atom.varName;
      oldDom = domains[varName]!;
      newDom = _filterForAtom(oldDom, atom);
    } else {
      final lit = spec.literals[idx];
      varName = lit.varName;
      final value = lit.positive ? 1 : 0;
      oldDom = domains[varName]!;
      newDom = oldDom.filter((v) => v == value);
    }
    if (newDom.isEmpty) return ''; // sentinel for "conflict"
    if (newDom.length != oldDom.length) {
      applyUpdate(varName, newDom,
          reason: ClauseReason(_antecedentsForForce(idx)));
      return varName;
    }
    return null;
  }

  static _DomainRep _filterForAtom(_DomainRep dom, Atom atom) {
    switch (atom) {
      case AtomEq(:final value):
        return dom.filter((v) => v == value);
      case AtomNe(:final value):
        return dom.filter((v) => v != value);
      case AtomLe(:final value):
        return dom.filter((v) => (v as int) <= value);
      case AtomGe(:final value):
        return dom.filter((v) => (v as int) >= value);
      case AtomInScc():
        throw StateError(
            'synthetic AtomInScc must never appear in a clause literal');
    }
  }

  /// Initialize watcher state for a clause we haven't seen before:
  /// scan for the first two non-falsified literals. Returns the
  /// initial change-set or null on conflict; on success records the
  /// watchers so subsequent calls can short-circuit.
  Set<String>? _initialize() {
    final n = _litCount;
    // First non-falsified, with an early-exit on satisfied (clause
    // already entailed, no watcher state needed — but we still
    // populate one for the next time around).
    var first = -1;
    for (var i = 0; i < n; i++) {
      final s = _evalAt(i);
      if (s == _satisfied) {
        // Clause is entailed. Pick this and the next non-falsified
        // (or stay alone) as initial watchers — we still want valid
        // watchers in the side-table for the next call.
        first = i;
        break;
      }
      if (s != _falsified) {
        first = i;
        break;
      }
    }
    if (first < 0) {
      // Every literal falsified → conflict.
      return null;
    }
    // Look for a second non-falsified literal after `first`.
    var second = -1;
    for (var i = first + 1; i < n; i++) {
      if (_evalAt(i) != _falsified) {
        second = i;
        break;
      }
    }
    if (second < 0) {
      // Only one non-falsified literal. Two cases:
      //   - it's satisfied → entailed.
      //   - it's undetermined → unit-propagate.
      final state = _evalAt(first);
      // Record `second = first` as a degenerate watcher so the next
      // call still sees an initialized entry; subsequent calls will
      // notice the duplicate via the swap loop and treat the clause
      // as unit-propagating again if needed.
      watchers[spec] = _ClauseWatchState(first, first);
      if (state == _satisfied) return <String>{};
      final v = _forceLiteral(first);
      if (v == '') return null;
      return v == null ? <String>{} : <String>{v};
    }
    watchers[spec] = _ClauseWatchState(first, second);
    return <String>{};
  }

  Set<String>? propagate() {
    if (_litCount == 0) return null;

    // First-time setup: scan and pick initial watchers.
    final state = watchers[spec];
    if (state == null) return _initialize();

    // Special case: the watcher entry might be degenerate
    // (`watch1 == watch2`), which we populate at init when only one
    // non-falsified literal was found. On entry now, re-check whether
    // a second one has appeared (it shouldn't have — domain reductions
    // are monotone — but if it has, refresh; otherwise re-run the
    // single-watcher logic).
    if (state.watch1 == state.watch2) {
      // Try to find a second non-falsified literal now (in case the
      // engine added more clauses or revised domains between calls in
      // a way that brought one back; under normal monotone domain
      // reduction this can't happen, but we stay correct either way).
      final replacement = _findNonFalsified(state.watch1, state.watch1);
      if (replacement >= 0) {
        state.watch2 = replacement;
      } else {
        // Still only one non-falsified literal — re-evaluate it.
        final s = _evalAt(state.watch1);
        if (s == _satisfied) return <String>{};
        if (s == _falsified) return null;
        final v = _forceLiteral(state.watch1);
        if (v == '') return null;
        return v == null ? <String>{} : <String>{v};
      }
    }

    // Common case: both watchers were valid on entry. Re-check each
    // watcher; if a watcher has become falsified, try to swap it to
    // another non-falsified literal. If no swap is possible, the
    // clause's fate depends on the other watcher.
    for (var slot = 0; slot < 2; slot++) {
      final w = slot == 0 ? state.watch1 : state.watch2;
      final other = slot == 0 ? state.watch2 : state.watch1;
      final s = _evalAt(w);
      if (s == _satisfied) return <String>{};
      if (s == _falsified) {
        final repl = _findNonFalsified(w, other);
        if (repl >= 0) {
          if (slot == 0) {
            state.watch1 = repl;
          } else {
            state.watch2 = repl;
          }
        } else {
          // Cannot replace. The clause's fate depends on `other`.
          final so = _evalAt(other);
          if (so == _falsified) return null;
          if (so == _satisfied) return <String>{};
          final v = _forceLiteral(other);
          if (v == '') return null;
          return v == null ? <String>{} : <String>{v};
        }
      }
    }
    return <String>{};
  }
}

class _MinConflictsRunner {
  _MinConflictsRunner(this._csp, {int? seed, this.cancelToken})
      : _rng = Random(seed);

  final CspProblem _csp;
  final Random _rng;

  /// When non-null, observed every [_yieldEveryIterations] iterations
  /// and (on cancellation) abandons the repair loop. Aborted runs
  /// return null, which the public entry point surfaces as
  /// `'FAILURE'`.
  final CancellationToken? cancelToken;

  /// Min-conflicts yields and rechecks the token every this many
  /// iterations. Same rationale as the backtracking engine's
  /// `_yieldEveryDecisions` — keep the hot loop cheap while letting
  /// `.timeout()` actually fire and timer-based cancels be observed.
  static const int _yieldEveryIterations = 200;

  /// Number of repair iterations executed in the most recent [run].
  /// Equals the converged step count on success, or `maxSteps` on
  /// timeout. Read by [CSP.solveWithMinConflicts] when populating
  /// [CSP.lastStats].
  int stepsRun = 0;

  Future<Map<String, dynamic>?> run(int maxSteps) async {
    stepsRun = 0;
    if (cancelToken?.isCancelled ?? false) return null;
    if (_csp.variables.isEmpty) return <String, dynamic>{};

    final binaryByVar = <String, List<BinaryConstraint>>{};
    for (final arc in _csp.constraints) {
      binaryByVar.putIfAbsent(arc.head, () => <BinaryConstraint>[]).add(arc);
    }
    final naryIdx = _csp.naryIndex ?? _indexNaryByVar(_csp.naryConstraints);

    final assignment = <String, dynamic>{};
    for (final entry in _csp.variables.entries) {
      final dom = entry.value;
      assignment[entry.key] = dom[_rng.nextInt(dom.length)];
    }

    int conflictsAt(String v, dynamic candidate) {
      final saved = assignment[v];
      assignment[v] = candidate;
      var n = 0;
      for (final arc in (binaryByVar[v] ?? const <BinaryConstraint>[])) {
        if (!arc.predicate(candidate, assignment[arc.tail])) n++;
      }
      for (final c in (naryIdx[v] ?? const <NaryConstraint>[])) {
        final sub = <String, dynamic>{};
        for (final cv in c.vars) {
          sub[cv] = assignment[cv];
        }
        if (!c.predicate(sub)) n++;
      }
      assignment[v] = saved;
      return n;
    }

    for (var step = 0; step < maxSteps; step++) {
      stepsRun = step + 1;
      if (step > 0 && step % _yieldEveryIterations == 0) {
        await Future<void>.delayed(Duration.zero);
        if (cancelToken?.isCancelled ?? false) return null;
      }
      final conflicted = <String>[];
      for (final v in assignment.keys) {
        if (conflictsAt(v, assignment[v]) > 0) conflicted.add(v);
      }
      if (conflicted.isEmpty) {
        return Map<String, dynamic>.from(assignment);
      }
      final chosen = conflicted[_rng.nextInt(conflicted.length)];
      final dom = _csp.variables[chosen]!;
      var minN = -1;
      final bestVals = <dynamic>[];
      for (final candidate in dom) {
        final n = conflictsAt(chosen, candidate);
        if (minN < 0 || n < minN) {
          minN = n;
          bestVals
            ..clear()
            ..add(candidate);
        } else if (n == minN) {
          bestVals.add(candidate);
        }
      }
      assignment[chosen] = bestVals[_rng.nextInt(bestVals.length)];
    }
    return null;
  }
}

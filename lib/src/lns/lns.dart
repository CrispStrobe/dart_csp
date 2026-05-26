/// Large Neighborhood Search (LNS) orchestration. See `doc/lns.md`
/// for the design overview; `lib/src/lns/policy.dart` and
/// `lib/src/lns/accept.dart` for the policy / accept catalogues.
///
/// This file is a `part of` `problem.dart` so the [LargeNeighborhoodSearch]
/// extension can read the host [Problem]'s private constraint and
/// variable lists when building the per-iteration sub-problem.
part of '../problem.dart';

/// Per-run statistics gathered by [LargeNeighborhoodSearch.lnsMinimize]
/// or [LargeNeighborhoodSearch.lnsMaximize]. Populated as the run
/// progresses; readable on the returned [LnsResult] after the call
/// completes.
class LnsStats {
  LnsStats();

  /// Iterations that ran (including iterations whose sub-problem was
  /// infeasible or timed out). Bounded by the caller's
  /// `iterationBudget`.
  int iterations = 0;

  /// Iterations whose candidate was accepted (replaced the incumbent).
  int accepts = 0;

  /// Iterations whose candidate was strictly evaluated but rejected
  /// by the acceptance strategy. Does not include infeasible or
  /// timed-out iterations.
  int rejects = 0;

  /// Iterations whose pinned sub-problem was infeasible. Rare for
  /// well-shaped destroys but possible when the destroy fixes
  /// variables to values that are incompatible under the constraints
  /// it can't see.
  int infeasibles = 0;

  /// Iterations whose inner solve was aborted by the per-iteration
  /// time bound. Treated like an infeasible sub-problem for the
  /// purposes of the accept loop, but counted separately so callers
  /// can spot a `iterationTimeMs` that is too tight.
  int timeouts = 0;

  /// Objective of the initial feasible solution found before the LNS
  /// loop began. `null` if the host problem was infeasible (in which
  /// case the run returns with no improvement).
  num? initialObjective;

  /// Objective of the final incumbent. Equal to [initialObjective]
  /// when no candidate was accepted; better otherwise. `null` if the
  /// initial solve failed.
  num? finalObjective;

  /// Wall-clock time for the entire run in microseconds. Includes
  /// the initial feasibility solve and every inner sub-problem solve.
  int elapsedMicros = 0;

  @override
  String toString() => 'LnsStats(iterations: $iterations, accepts: $accepts, '
      'rejects: $rejects, infeasibles: $infeasibles, timeouts: $timeouts, '
      'initialObjective: $initialObjective, finalObjective: $finalObjective, '
      'elapsedMicros: $elapsedMicros)';
}

/// Result of an LNS run. [solution] is either the best [Map] found
/// (with set variables materialised back to `Set<dynamic>`) or the
/// literal `'FAILURE'` string when the host problem had no initial
/// feasible solution.
class LnsResult {
  LnsResult({required this.solution, required this.stats});

  /// The best solution found, or the literal `'FAILURE'`.
  final dynamic solution;

  /// Per-run statistics. Always populated.
  final LnsStats stats;
}

/// Large Neighborhood Search entry points. Shipped as an extension to
/// keep the [Problem] class focused and to colocate the policy /
/// accept catalogue with the orchestration. See `doc/lns.md` for the
/// design overview.
extension LargeNeighborhoodSearch on Problem {
  /// Find a near-optimal assignment minimising [objective] using
  /// Large Neighborhood Search. LNS finds an initial feasible
  /// solution, then iteratively "destroys" a subset of variables
  /// (frees them while pinning every other variable to its incumbent
  /// value), re-solves the smaller sub-problem, and replaces the
  /// incumbent when the [accept] strategy admits the candidate.
  ///
  /// Returns an [LnsResult]. `result.solution` is either the best
  /// assignment found or `'FAILURE'` if the host problem has no
  /// solution at all. `result.stats` is always populated. The best
  /// assignment is **not** guaranteed to be globally optimal — LNS
  /// is a metaheuristic, not a complete search — but with a
  /// reasonable [iterationBudget] it almost always beats plain
  /// branch-and-bound on hard instances.
  ///
  /// [policy] defaults to [LnsPolicy.random] with a 0.2 destroy
  /// fraction; [accept] defaults to [LnsAccept.improving]. Pass
  /// [iterationTimeMs] to time-bound each inner sub-problem solve;
  /// pass [totalTimeMs] to bound the entire run. Pass [seed] for a
  /// reproducible RNG.
  Future<LnsResult> lnsMinimize(
    String objective, {
    LnsPolicy? policy,
    LnsAccept? accept,
    int iterationBudget = 100,
    int? iterationTimeMs,
    int? totalTimeMs,
    int? seed,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    bool enableConflictBackjumping = false,
    CancellationToken? cancelToken,
    num? Function()? boundHint,
    void Function(num)? onIncumbent,
  }) =>
      _lns(
        objective,
        minimizing: true,
        policy: policy ?? LnsPolicy.random(),
        accept: accept ?? LnsAccept.improving(),
        iterationBudget: iterationBudget,
        iterationTimeMs: iterationTimeMs,
        totalTimeMs: totalTimeMs,
        seed: seed,
        consistency: consistency,
        enableConflictBackjumping: enableConflictBackjumping,
        cancelToken: cancelToken,
        boundHint: boundHint,
        onIncumbent: onIncumbent,
      );

  /// Symmetric to [lnsMinimize]: find a near-optimal assignment
  /// maximising [objective]. See that method for the algorithm and
  /// parameters.
  ///
  /// [boundHint] and [onIncumbent] are the cooperative-LNS plumbing
  /// hooks; see [lnsMinimize] for their semantics.
  Future<LnsResult> lnsMaximize(
    String objective, {
    LnsPolicy? policy,
    LnsAccept? accept,
    int iterationBudget = 100,
    int? iterationTimeMs,
    int? totalTimeMs,
    int? seed,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    bool enableConflictBackjumping = false,
    CancellationToken? cancelToken,
    num? Function()? boundHint,
    void Function(num)? onIncumbent,
  }) =>
      _lns(
        objective,
        minimizing: false,
        policy: policy ?? LnsPolicy.random(),
        accept: accept ?? LnsAccept.improving(),
        iterationBudget: iterationBudget,
        iterationTimeMs: iterationTimeMs,
        totalTimeMs: totalTimeMs,
        seed: seed,
        consistency: consistency,
        enableConflictBackjumping: enableConflictBackjumping,
        cancelToken: cancelToken,
        boundHint: boundHint,
        onIncumbent: onIncumbent,
      );

  // [boundHint] and [onIncumbent] are the internal plumbing used by
  // the cooperative parallel-LNS runner in `isolate_runner.dart`.
  // [boundHint] is polled each iteration; when the returned bound is
  // strictly better than the local best in the optimisation direction,
  // the iteration's sub-problem has its objective domain tightened to
  // values that beat the global bound (an empty resulting domain is
  // treated like an infeasible sub-problem and skipped). [onIncumbent]
  // is invoked on every local improvement so the orchestrator can
  // re-broadcast. Both default to null (no cooperation), which is the
  // standalone single-thread shape.
  Future<LnsResult> _lns(
    String objective, {
    required bool minimizing,
    required LnsPolicy policy,
    required LnsAccept accept,
    required int iterationBudget,
    required int? iterationTimeMs,
    required int? totalTimeMs,
    required int? seed,
    required ConsistencyLevel consistency,
    required bool enableConflictBackjumping,
    required CancellationToken? cancelToken,
    num? Function()? boundHint,
    void Function(num)? onIncumbent,
  }) async {
    if (!_variables.containsKey(objective)) {
      throw ArgumentError(
          "Cannot ${minimizing ? 'lnsMinimize' : 'lnsMaximize'} unknown "
          "variable '$objective'.");
    }
    for (final v in _variables[objective]!) {
      if (v is! num) {
        throw ArgumentError(
            "Cannot optimize variable '$objective': value is not numeric "
            '($v of type ${v.runtimeType}).');
      }
    }
    if (iterationBudget < 0) {
      throw ArgumentError('iterationBudget must be >= 0; got $iterationBudget');
    }
    if (iterationTimeMs != null && iterationTimeMs <= 0) {
      throw ArgumentError('iterationTimeMs must be > 0; got $iterationTimeMs');
    }
    if (totalTimeMs != null && totalTimeMs <= 0) {
      throw ArgumentError('totalTimeMs must be > 0; got $totalTimeMs');
    }

    final stats = LnsStats();
    final startMicros = DateTime.now().microsecondsSinceEpoch;
    final rng = seed != null ? Random(seed) : Random();

    // Step 1. Initial feasible solution. We deliberately use
    // `CSP.solve` (find any feasible) rather than `CSP.solveOptimal`
    // so the LNS loop has room to improve — proving optimality up
    // front would defeat the point. We bypass `getSolution()` so the
    // returned map keeps raw indicator-variable keys for any set
    // variables; pinning needs those. The user-facing result is
    // re-materialised on return.
    final initialCsp = CspProblem(
      variables: _variables.map((k, v) => MapEntry(k, List<dynamic>.of(v))),
      constraints: _constraints,
      naryConstraints: _naryConstraints,
    );
    final initial = await CSP.solve(
      initialCsp,
      consistency: consistency,
      cancelToken: cancelToken,
      enableConflictBackjumping: enableConflictBackjumping,
    );
    if (initial == 'FAILURE') {
      stats.elapsedMicros = DateTime.now().microsecondsSinceEpoch - startMicros;
      return LnsResult(solution: 'FAILURE', stats: stats);
    }

    var current = Map<String, dynamic>.of(initial as Map<String, dynamic>);
    var currentObj = current[objective] as num;
    var bestSolution = current;
    var bestObjective = currentObj;
    stats.initialObjective = currentObj;

    // Step 2. Build the variable-to-variable constraint adjacency once.
    final adjacency = _buildLnsConstraintAdjacency();
    final variableNames = List<String>.of(_variables.keys);

    final totalDeadlineMicros =
        totalTimeMs != null ? startMicros + totalTimeMs * 1000 : null;

    // Step 3. Main LNS loop.
    for (var iter = 0; iter < iterationBudget; iter++) {
      if (cancelToken?.isCancelled ?? false) break;
      if (totalDeadlineMicros != null &&
          DateTime.now().microsecondsSinceEpoch >= totalDeadlineMicros) {
        break;
      }
      stats.iterations++;

      final ctx = LnsContext(
        variableNames: variableNames,
        bestSolution: current,
        bestObjective: currentObj,
        iteration: iter,
        rng: rng,
        constraintAdjacency: adjacency,
      );
      final freedList = policy.select(ctx);
      final freed = freedList.toSet();

      var subCsp = _buildLnsSubproblem(current, freed);

      // Cooperative-LNS sub-problem tightening. When the parent
      // orchestrator has heard of a better global bound from another
      // worker, we pre-tighten the objective domain so this iteration
      // only considers values that beat the global best. The plain
      // single-thread shape (boundHint == null) is unchanged.
      final hint = boundHint?.call();
      if (hint != null) {
        final tighter = minimizing
            ? (hint < bestObjective ? hint : bestObjective)
            : (hint > bestObjective ? hint : bestObjective);
        final isStricter =
            minimizing ? tighter < bestObjective : tighter > bestObjective;
        if (isStricter) {
          final origDom = subCsp.variables[objective]!;
          final newDom = <dynamic>[
            for (final v in origDom)
              if (v is num && (minimizing ? v < tighter : v > tighter)) v,
          ];
          if (newDom.isEmpty) {
            // Sub-problem provably can't beat the global best.
            // Treat exactly like a structurally infeasible iteration.
            stats.infeasibles++;
            continue;
          }
          final tightenedVars = Map<String, List<dynamic>>.of(subCsp.variables);
          tightenedVars[objective] = newDom;
          subCsp = CspProblem(
            variables: tightenedVars,
            constraints: _constraints,
            naryConstraints: _naryConstraints,
          );
        }
      }

      // Per-iteration time bound: wire a fresh token that fires after
      // the iteration deadline AND propagates the caller's
      // cancellation through.
      CancellationToken? innerToken;
      Timer? iterTimer;
      var iterTimedOut = false;
      if (iterationTimeMs != null) {
        final t = CancellationToken();
        innerToken = t;
        if (cancelToken != null) {
          cancelToken.addListener(t.cancel);
        }
        iterTimer = Timer(Duration(milliseconds: iterationTimeMs), () {
          iterTimedOut = true;
          t.cancel();
        });
      } else {
        innerToken = cancelToken;
      }

      dynamic candidate;
      try {
        candidate = await CSP.solveOptimal(
          subCsp,
          objective,
          minimizing: minimizing,
          consistency: consistency,
          cancelToken: innerToken,
          enableConflictBackjumping: enableConflictBackjumping,
        );
      } finally {
        iterTimer?.cancel();
      }

      if (candidate == 'FAILURE') {
        if (iterTimedOut) {
          stats.timeouts++;
        } else if (cancelToken?.isCancelled ?? false) {
          // Caller cancelled mid-iteration; exit the loop cleanly.
          break;
        } else {
          stats.infeasibles++;
        }
        continue;
      }

      final candMap = candidate as Map<String, dynamic>;
      final candObj = candMap[objective] as num;
      final shouldAccept = accept.accept(
        candidate: candObj,
        incumbent: currentObj,
        iteration: iter,
        minimizing: minimizing,
        rng: rng,
      );
      // "Best ever" tracked separately from "current" so a simulated-
      // annealing-accepted worsening move can't lose a previously
      // found global best. For pure improving-accept the two move in
      // lock-step.
      final improvedBest =
          minimizing ? candObj < bestObjective : candObj > bestObjective;
      if (shouldAccept) {
        current = candMap;
        currentObj = candObj;
        stats.accepts++;
      } else {
        stats.rejects++;
      }
      if (improvedBest) {
        bestSolution = candMap;
        bestObjective = candObj;
        // Cooperative-LNS hook: tell the orchestrator about the new
        // local best so it can re-broadcast to other workers.
        onIncumbent?.call(candObj);
      }
      if (policy is LnsAdaptivePolicy) {
        policy.observe(
          ctx: ctx,
          accepted: shouldAccept,
          improvedBest: improvedBest,
        );
      }
    }

    stats.finalObjective = bestObjective;
    stats.elapsedMicros = DateTime.now().microsecondsSinceEpoch - startMicros;
    return LnsResult(
      solution: _materializeSets(bestSolution),
      stats: stats,
    );
  }

  /// Builds a sub-problem CSP for one LNS iteration: every variable in
  /// [freed] keeps its original domain; every other variable is
  /// pinned to its value in [incumbent]. A variable whose incumbent
  /// value is missing from its declared domain (shouldn't happen with
  /// the standard solvers but defends against future divergences)
  /// stays unpinned so the sub-problem can still be feasible.
  CspProblem _buildLnsSubproblem(
      Map<String, dynamic> incumbent, Set<String> freed) {
    final pinned = <String, List<dynamic>>{};
    for (final entry in _variables.entries) {
      if (freed.contains(entry.key)) {
        pinned[entry.key] = List<dynamic>.of(entry.value);
      } else {
        final v = incumbent[entry.key];
        if (v != null && entry.value.contains(v)) {
          pinned[entry.key] = <dynamic>[v];
        } else {
          pinned[entry.key] = List<dynamic>.of(entry.value);
        }
      }
    }
    return CspProblem(
      variables: pinned,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
    );
  }

  /// Constraint-variable adjacency graph: `adj[v]` is the set of
  /// variables that share at least one constraint with `v`. Built
  /// once at the top of an LNS run and passed through [LnsContext].
  Map<String, Set<String>> _buildLnsConstraintAdjacency() {
    final adj = <String, Set<String>>{
      for (final name in _variables.keys) name: <String>{}
    };
    for (final c in _constraints) {
      adj[c.head]?.add(c.tail);
      adj[c.tail]?.add(c.head);
    }
    for (final c in _naryConstraints) {
      final vars = c.vars;
      for (var i = 0; i < vars.length; i++) {
        for (var j = 0; j < vars.length; j++) {
          if (i != j) adj[vars[i]]?.add(vars[j]);
        }
      }
    }
    return adj;
  }
}

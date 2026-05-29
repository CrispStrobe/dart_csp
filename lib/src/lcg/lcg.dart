/// Lazy Clause Generation (LCG) entry points on [Problem]. M1 ships
/// the runner shell + the atom/implication-trail wiring; the
/// first-UIP loop and per-propagator explanation companions arrive
/// in M2 / M3. See `LCG_PLAN.md` for the milestone roadmap.
///
/// This file is `part of` `problem.dart` so the extension can read
/// the host [Problem]'s private variable / constraint lists when
/// dispatching to [CSP.solveWithLcg], and so the result goes through
/// `_wrapResult` for set-variable materialisation.
part of '../problem.dart';

/// LCG-flavoured solve entry points on [Problem]. **Experimental.**
///
/// In M1 the runner is functionally indistinguishable from
/// [Problem.getSolution] — same return contract, same answers, same
/// propagation. The visible difference is that the engine maintains
/// an implication trail of atoms during search, which M2 will consume
/// to drive first-UIP conflict-clause learning.
///
/// Callers wanting parity behaviour can switch to [solveWithLcg]
/// freely; it won't get *slower* than [Problem.getSolution] by
/// design (the trail bookkeeping is bounded by the search-tree
/// size), and benefits will arrive transparently as M2 / M3 land.
extension LcgSearch on Problem {
  /// Solve the problem with LCG bookkeeping enabled. Returns
  /// `Map<String, dynamic>` on success or `'FAILURE'` otherwise —
  /// identical contract to [getSolution].
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to [ConsistencyLevel.arcConsistency]. Pass [learnedClauseCap] to
  /// override the default forget threshold (1000); when the engine has
  /// learned more than this many clauses, the oldest half are dropped
  /// to keep memory bounded. Both M2b and earlier milestones keep the
  /// per-clause overhead bounded by the existing
  /// `_ClausePropagator`'s two-watched-literal scheme.
  ///
  /// Pass [useIterativeCdcl] to drive search with the iterative
  /// trail-based CDCL engine (sound non-chronological backjumping — the
  /// LCG search-tree speedup); it falls back to the recursive engine on
  /// any non-integer-domain problem. On by default (pass `false` for the
  /// recursive chronological-backtracking-with-learning path).
  Future<dynamic> solveWithLcg(
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool useVsids = false,
      bool useDomWdeg = false,
      bool useIterativeCdcl = true,
      bool useRestarts = false,
      int restartScale = 100,
      int? seed,
      int? learnedClauseCap,
      void Function(List<Atom> clause)? onLearnedClause,
      List<List<Atom>> Function()? importClauses}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveWithLcg(problem,
        consistency: consistency,
        cancelToken: cancelToken,
        useVsids: useVsids,
        useDomWdeg: useDomWdeg,
        useIterativeCdcl: useIterativeCdcl,
        useRestarts: useRestarts,
        restartScale: restartScale,
        seed: seed,
        learnedClauseCap: learnedClauseCap,
        onLearnedClause: onLearnedClause,
        importClauses: importClauses));
  }
}

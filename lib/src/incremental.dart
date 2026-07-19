// Assumption-based incremental solving.
//
// Interactive callers re-solve constantly as the user edits: add a
// hypothesis, solve, retract it, try another. [IncrementalSolver] gives that
// a first-class API — a base model plus a stack of retractable *assumption*
// scopes — with an exactness guarantee: assumptions are layered onto a
// `copy()` of the base at solve time, so the base is never mutated and
// `pop()` / `resetAssumptions()` retract *precisely*, with no residue.
//
// Warm-starting is layered on top: `prime()` / `solveWarm()` cache the
// nogoods the LCG engine learns, tagged with the assumptions that were
// active, and re-import the ones still valid. See the Warm-starting section
// below for what that does and does not reuse.

import 'lcg/atom.dart';
import 'problem.dart';
import 'types.dart';

/// One thing to add to the problem before solving — a named-for-debugging
/// closure that posts a constraint onto a working [Problem], plus a stable
/// [id] used to tag the clauses learned while it was active.
typedef _Assumption = ({
  int id,
  String description,
  void Function(Problem) apply,
});

/// A learned nogood together with the assumptions it may depend on.
///
/// [tags] holds the ids of the assumptions that were active in the solve
/// that produced [clause]. The clause is implied by `base ∧ tags`, so it
/// is sound to reuse in any solve whose active assumption set is a
/// *superset* of [tags] — and in particular a clause with no tags (learned
/// from the base alone) is sound everywhere.
///
/// The tagging is per-*solve*, not per-clause: a clause is tagged with
/// every assumption that was active, whether or not its derivation
/// actually used them. That over-approximates, so some reusable clauses
/// are held back — never the reverse. See `IncrementalSolver.solveWarm`
/// for why the precise version needs an engine change.
class _CachedClause {
  _CachedClause(this.clause, this.tags) : key = _keyOf(clause);

  final List<Atom> clause;
  final Set<int> tags;

  /// Canonical form used to suppress duplicates across solves.
  final String key;

  static String _keyOf(List<Atom> clause) {
    final parts = [for (final a in clause) a.toString()]..sort();
    return parts.join('|');
  }
}

/// A retractable-scope wrapper around a base [Problem] for interactive,
/// assumption-driven solving.
///
/// ```dart
/// final solver = IncrementalSolver(baseModel);
/// solver.assumeEquals('x', 3);
/// final a = await solver.solve();          // base + {x == 3}
/// solver.push();                            // open a nested scope
/// solver.assumeEquals('y', 5);
/// final b = await solver.solve();          // base + {x == 3, y == 5}
/// solver.pop();                             // retract {y == 5} exactly
/// final c = await solver.solve();          // base + {x == 3} again
/// ```
///
/// The base problem passed to the constructor is never modified; every solve
/// runs on a fresh assembly of `base.copy()` plus the currently-active
/// assumptions.
class IncrementalSolver {
  /// Wraps [base]. [base] is copied at each solve and never mutated, so it
  /// may be reused or solved on directly elsewhere.
  IncrementalSolver(this._base, {this.maxCachedClauses = 10000});

  final Problem _base;

  /// A stack of assumption scopes. Index 0 is the always-present root scope;
  /// [push] appends, [pop] removes the top (never the root).
  final List<List<_Assumption>> _scopes = [<_Assumption>[]];

  /// Source of stable per-assumption ids. Never reset — a popped scope's
  /// ids must never be reused, or a cached clause tagged with the old
  /// assumption would be wrongly considered reusable under the new one.
  int _nextId = 0;

  /// The ids of every currently-active assumption.
  Set<int> _activeIds() => {
        for (final scope in _scopes)
          for (final a in scope) a.id
      };

  List<_Assumption> get _top => _scopes.last;

  /// Number of assumption scopes currently open beyond the root (i.e. the
  /// number of [pop]s that would return to the root).
  int get depth => _scopes.length - 1;

  /// Total number of active assumptions across every open scope.
  int get assumptionCount => _scopes.fold(0, (n, scope) => n + scope.length);

  /// Human-readable descriptions of the active assumptions, root scope first.
  List<String> get assumptions => [
        for (final scope in _scopes)
          for (final a in scope) a.description
      ];

  // --- Managing scopes -----------------------------------------------------

  /// Opens a new assumption scope. Assumptions added after this go into it and
  /// are all retracted together by the matching [pop].
  void push() => _scopes.add(<_Assumption>[]);

  /// Discards the top assumption scope and everything assumed in it. Throws
  /// [StateError] if no scope has been [push]ed (the root cannot be popped;
  /// use [resetAssumptions] to clear it).
  void pop() {
    if (_scopes.length == 1) {
      throw StateError('pop() with no open scope; the root scope cannot be '
          'popped (use resetAssumptions() to clear it).');
    }
    _scopes.removeLast();
  }

  /// Removes every assumption in every scope, returning to just the base
  /// model, and collapses back to a single root scope.
  void resetAssumptions() {
    _scopes
      ..clear()
      ..add(<_Assumption>[]);
  }

  // --- Adding assumptions to the current scope -----------------------------

  /// Whether [variable] has an all-integer domain, so an assumption on it
  /// can be posted as an atom clause rather than a predicate. Atom clauses
  /// go to the two-watched-literal propagator, which both runs cheaper than
  /// a generic predicate revise (measured ~3x on a 50-variable 3-SAT base)
  /// and — the part that matters for learning — explains its propagations,
  /// so conflict analysis resolves through the assumption instead of
  /// stopping at it.
  bool _isIntVar(String variable) {
    final dom = _base.variables[variable];
    if (dom == null) return false;
    return dom.every((v) => v is int);
  }

  /// Assumes `variable == value`. Works for any domain value (numeric or
  /// not).
  void assumeEquals(String variable, dynamic value) {
    _requireVariable(variable);
    final atomic = value is int && _isIntVar(variable);
    _top.add((
      id: _nextId++,
      description: '$variable == $value',
      apply: atomic
          ? (p) => p.addAtomClause([AtomEq(variable, value)])
          : (p) => p.addConstraint<bool Function(Map<String, dynamic>)>(
              [variable], (m) => m[variable] == value),
    ));
  }

  /// Assumes `variable != value`.
  void assumeNotEquals(String variable, dynamic value) {
    _requireVariable(variable);
    final atomic = value is int && _isIntVar(variable);
    _top.add((
      id: _nextId++,
      description: '$variable != $value',
      apply: atomic
          ? (p) => p.addAtomClause([AtomNe(variable, value)])
          : (p) => p.addConstraint<bool Function(Map<String, dynamic>)>(
              [variable], (m) => m[variable] != value),
    ));
  }

  /// Assumes `variable` takes one of [values].
  void assumeInSet(String variable, Set<dynamic> values) {
    _requireVariable(variable);
    // A genuine disjunction, so this is where the atom-clause form earns
    // the most: `x in {1, 3, 7}` becomes a real three-literal clause the
    // propagator can unit-propagate, rather than an opaque predicate.
    final atomic = values.isNotEmpty &&
        values.every((v) => v is int) &&
        _isIntVar(variable);
    _top.add((
      id: _nextId++,
      description: '$variable in $values',
      apply: atomic
          ? (p) => p.addAtomClause(
              [for (final v in values) AtomEq(variable, v as int)])
          : (p) => p.addConstraint<bool Function(Map<String, dynamic>)>(
              [variable], (m) => values.contains(m[variable])),
    ));
  }

  /// Assumes an arbitrary string constraint (parsed like
  /// [Problem.addStringConstraint]).
  void assumeConstraint(String constraint) {
    _top.add((
      id: _nextId++,
      description: constraint,
      apply: (p) => p.addStringConstraint(constraint),
    ));
  }

  /// Assumes an arbitrary predicate over [variables].
  void assumePredicate(
    List<String> variables,
    bool Function(Map<String, dynamic>) predicate, {
    String? description,
  }) {
    for (final v in variables) {
      _requireVariable(v);
    }
    _top.add((
      id: _nextId++,
      description: description ?? 'predicate(${variables.join(', ')})',
      // addConstraint wants a BinaryPredicate for exactly two variables and a
      // NaryPredicate otherwise, so adapt the map predicate to the arity.
      apply: (p) {
        if (variables.length == 2) {
          final a = variables[0], b = variables[1];
          p.addConstraint<bool Function(dynamic, dynamic)>(
              variables, (va, vb) => predicate({a: va, b: vb}));
        } else {
          p.addConstraint<bool Function(Map<String, dynamic>)>(
              variables, predicate);
        }
      },
    ));
  }

  // --- Solving under the current assumptions -------------------------------

  /// Assembles `base.copy()` plus every active assumption. Exposed so callers
  /// can run any [Problem] operation (a custom heuristic, a trace, …) under
  /// the current assumptions; the returned problem is a throwaway copy.
  Problem materialize() {
    final work = _base.copy();
    for (final scope in _scopes) {
      for (final a in scope) {
        a.apply(work);
      }
    }
    return work;
  }

  /// Solves under the active assumptions. Returns a `Map<String, dynamic>`
  /// solution or `'FAILURE'` — the same contract as [Problem.getSolution].
  Future<dynamic> solve({
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    CancellationToken? cancelToken,
  }) =>
      materialize()
          .getSolution(consistency: consistency, cancelToken: cancelToken);

  /// Whether the problem is satisfiable under the active assumptions.
  Future<bool> isSatisfiable({CancellationToken? cancelToken}) async =>
      await solve(cancelToken: cancelToken) is Map;

  /// Streams every solution consistent with the active assumptions.
  Stream<Map<String, dynamic>> getSolutions({
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    CancellationToken? cancelToken,
  }) =>
      materialize()
          .getSolutions(consistency: consistency, cancelToken: cancelToken);

  /// Counts solutions consistent with the active assumptions.
  Future<int> countSolutions() => materialize().countSolutions();

  /// Minimizes [objective] under the active assumptions.
  Future<dynamic> minimize(String objective,
          {CancellationToken? cancelToken}) =>
      materialize().minimize(objective, cancelToken: cancelToken);

  /// Maximizes [objective] under the active assumptions.
  Future<dynamic> maximize(String objective,
          {CancellationToken? cancelToken}) =>
      materialize().maximize(objective, cancelToken: cancelToken);

  // --- Warm-starting -------------------------------------------------------
  //
  // Reuse across re-solves. A nogood learned by the LCG engine is implied by
  // the constraints of the problem it was learned on — so a clause learned
  // from the *base alone* is valid under any assumptions, and a clause
  // learned while assumption set `A` was active is valid under any set that
  // still contains `A`.
  //
  // The cache tags every clause with the assumptions that were active when
  // it was learned, and a later solve imports exactly those whose tags it
  // still satisfies. Priming (no assumptions) produces untagged clauses,
  // which are therefore reusable everywhere.

  final List<_CachedClause> _cache = [];

  /// Keys already in [_cache], so the same nogood is not stored twice across
  /// solves. When a duplicate arrives with a *smaller* tag set the existing
  /// entry is relaxed to it — the same clause proved under fewer assumptions
  /// is strictly more reusable.
  final Map<String, _CachedClause> _byKey = {};

  bool _primed = false;

  /// Maximum number of cached nogoods. Past this, the most heavily tagged
  /// entries are dropped first: they are the least reusable, since they
  /// require the most assumptions to still be active. Untagged (base) clauses
  /// are never evicted while any tagged one remains.
  final int maxCachedClauses;

  /// Number of cached nogoods available for warm-starting.
  int get cachedClauseCount => _cache.length;

  /// Number of cached nogoods that are reusable under *any* assumptions,
  /// i.e. those derived from the base problem alone.
  int get unconditionalClauseCount =>
      _cache.where((c) => c.tags.isEmpty).length;

  /// How many cached nogoods would be imported by a [solveWarm] right now:
  /// those whose every tag is still an active assumption. Exposed for
  /// tests and for diagnosing how much reuse a given workload actually
  /// gets — see [solveWarm] on why that is often just the untagged ones.
  int get importableClauseCount {
    final active = _activeIds();
    return _cache.where((c) => c.tags.every(active.contains)).length;
  }

  /// Discards every cached nogood. Call after mutating the base problem.
  void clearCache() {
    _cache.clear();
    _byKey.clear();
    _primed = false;
  }

  void _remember(List<Atom> clause, Set<int> tags) {
    if (clause.isEmpty) return;
    final entry = _CachedClause(List<Atom>.of(clause), tags);
    final existing = _byKey[entry.key];
    if (existing != null) {
      // Same nogood, fewer preconditions ⇒ keep the weaker precondition.
      if (tags.length < existing.tags.length) {
        existing.tags
          ..clear()
          ..addAll(tags);
      }
      return;
    }
    _byKey[entry.key] = entry;
    _cache.add(entry);
    if (_cache.length > maxCachedClauses) _evict();
  }

  void _evict() {
    // Stable sort by tag count, then drop from the back.
    _cache.sort((a, b) => a.tags.length.compareTo(b.tags.length));
    while (_cache.length > maxCachedClauses) {
      final dropped = _cache.removeLast();
      _byKey.remove(dropped.key);
    }
  }

  /// Learns the reusable base-only nogoods by solving the base problem (no
  /// assumptions) with the LCG engine. Called automatically by [solveWarm]
  /// on first use; call it explicitly to pay the priming cost up front (e.g.
  /// right after building the model, before the interactive loop).
  ///
  /// Re-priming rebuilds from scratch — do it if the base problem changed.
  Future<void> prime({
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    CancellationToken? cancelToken,
    bool useVsids = false,
    bool useDomWdeg = false,
  }) async {
    clearCache();
    await _base.solveWithLcg(
      consistency: consistency,
      cancelToken: cancelToken,
      useVsids: useVsids,
      useDomWdeg: useDomWdeg,
      onLearnedClause: (c) => _remember(c, const <int>{}),
    );
    _primed = true;
  }

  /// Solves under the active assumptions with the LCG engine,
  /// **warm-started** from the cached nogoods. [prime] is run automatically
  /// if it has not been. Returns a `Map<String, dynamic>` solution or
  /// `'FAILURE'`, the same contract as [solve].
  ///
  /// Semantics are identical to a cold solve. Every imported clause is
  /// logically implied by the constraints currently in force, so it can only
  /// prune branches that contain no solution.
  ///
  /// **What gets reused.** A clause is imported when every assumption it was
  /// learned under is still active. So priming yields clauses reusable
  /// forever; a clause learned under `{x == 3}` comes back on any later
  /// solve that still assumes `x == 3` — including deeper ones that assume
  /// more — and is correctly dropped once that assumption is popped.
  ///
  /// **How precise that is.** Tagging happens per *solve*: a clause carries
  /// every assumption that was active, not just the ones its derivation
  /// actually used. That is conservative — it holds back some clauses that
  /// would have been safe — but never unsound. Tagging per *clause* would
  /// need the assumption literals to appear in the learned clauses
  /// themselves, which in turn needs the engine to take assumptions as
  /// *decisions* rather than as posted constraints: a constraint pins its
  /// variable at decision level 0, and CDCL omits level-0 literals from
  /// learned clauses precisely because they are supposed to be permanent.
  /// See `doc/next-engine-work.md`.
  Future<dynamic> solveWarm({
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    CancellationToken? cancelToken,
    bool useVsids = false,
    bool useDomWdeg = false,
  }) async {
    if (!_primed) {
      await prime(
        consistency: consistency,
        cancelToken: cancelToken,
        useVsids: useVsids,
        useDomWdeg: useDomWdeg,
      );
    }
    final active = _activeIds();
    final importable = <List<Atom>>[
      for (final c in _cache)
        if (c.tags.every(active.contains)) c.clause,
    ];
    // Deliver the cached clauses once: the engine drains [importClauses]
    // repeatedly during search, so returning the full list every call would
    // re-add duplicates into the pool.
    var delivered = false;
    return materialize().solveWithLcg(
      consistency: consistency,
      cancelToken: cancelToken,
      useVsids: useVsids,
      useDomWdeg: useDomWdeg,
      importClauses: () {
        if (delivered) return const [];
        delivered = true;
        return importable;
      },
      onLearnedClause: (c) => _remember(c, Set<int>.of(active)),
    );
  }

  void _requireVariable(String name) {
    if (!_base.variables.containsKey(name)) {
      throw ArgumentError("No variable named '$name' in the base problem.");
    }
  }
}

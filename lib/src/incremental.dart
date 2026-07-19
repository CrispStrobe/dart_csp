// Assumption-based incremental solving.
//
// Interactive callers re-solve constantly as the user edits: add a
// hypothesis, solve, retract it, try another. [IncrementalSolver] gives that
// a first-class API — a base model plus a stack of retractable *assumption*
// scopes — with an exactness guarantee: assumptions are layered onto a
// `copy()` of the base at solve time, so the base is never mutated and
// `pop()` / `resetAssumptions()` retract *precisely*, with no residue.
//
// Scope, stated honestly. This delivers the incremental *interface* and its
// correctness, not warm-starting: each `solve` still runs the engine from
// scratch on the assembled model. Persisting engine state (trail + learned
// clauses) across solves so a re-solve reuses prior work is a deeper,
// engine-level change tracked in PLAN.md; it would make this same API faster
// without changing its semantics.

import 'problem.dart';
import 'types.dart';

/// One thing to add to the problem before solving — a named-for-debugging
/// closure that posts a constraint onto a working [Problem].
typedef _Assumption = ({String description, void Function(Problem) apply});

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
  IncrementalSolver(this._base);

  final Problem _base;

  /// A stack of assumption scopes. Index 0 is the always-present root scope;
  /// [push] appends, [pop] removes the top (never the root).
  final List<List<_Assumption>> _scopes = [<_Assumption>[]];

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

  /// Assumes `variable == value`. Works for any domain value (numeric or
  /// not).
  void assumeEquals(String variable, dynamic value) {
    _requireVariable(variable);
    _top.add((
      description: '$variable == $value',
      apply: (p) => p.addConstraint<bool Function(Map<String, dynamic>)>(
          [variable], (m) => m[variable] == value),
    ));
  }

  /// Assumes `variable != value`.
  void assumeNotEquals(String variable, dynamic value) {
    _requireVariable(variable);
    _top.add((
      description: '$variable != $value',
      apply: (p) => p.addConstraint<bool Function(Map<String, dynamic>)>(
          [variable], (m) => m[variable] != value),
    ));
  }

  /// Assumes `variable` takes one of [values].
  void assumeInSet(String variable, Set<dynamic> values) {
    _requireVariable(variable);
    _top.add((
      description: '$variable in $values',
      apply: (p) => p.addConstraint<bool Function(Map<String, dynamic>)>(
          [variable], (m) => values.contains(m[variable])),
    ));
  }

  /// Assumes an arbitrary string constraint (parsed like
  /// [Problem.addStringConstraint]).
  void assumeConstraint(String constraint) {
    _top.add((
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

  void _requireVariable(String name) {
    if (!_base.variables.containsKey(name)) {
      throw ArgumentError("No variable named '$name' in the base problem.");
    }
  }
}

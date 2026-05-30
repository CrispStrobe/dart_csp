/// Problem builder class and extensions for easy CSP construction.
library;

import 'dart:async';
import 'dart:math' show Random;

import 'builtin_constraints.dart';
import 'constraint_parser.dart';
import 'lns/accept.dart';
import 'lns/policy.dart';
import 'solver.dart';
import 'types.dart';

// Re-export the LNS public types defined in the part file below so
// callers importing dart_csp.dart see them alongside Problem.
export 'lns/accept.dart' show LnsAccept;
export 'lns/policy.dart' show LnsAdaptivePolicy, LnsContext, LnsPolicy;

part 'lcg/lcg.dart';
part 'lns/lns.dart';

/// A user-friendly wrapper class to build a constraint satisfaction problem.
///
/// This class provides a builder pattern API to add variables and constraints
/// before creating a [CspProblem] object to be solved by the [CSP] solver.
///
/// ### Usage Example
/// ```dart
/// final p = Problem();
/// const colors = ['red', 'green', 'blue'];
///
/// // 1. Add variables and their domains
/// p.addVariables(['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T'], colors);
///
/// // 2. Add constraints
/// p.addConstraint(['SA', 'WA'], (sa, wa) => sa != wa);
/// p.addConstraint(['SA', 'NT'], (sa, nt) => sa != nt);
/// // ... more constraints
///
/// // 3. Get the solution
/// final solution = await p.getSolution();
/// if (solution is Map) {
///   print("Solution found: $solution");
/// } else {
///   print("No solution found!");
/// }
///
/// // 4. Or get all solutions
/// await for (final solution in p.getSolutions()) {
///   print("Found solution: $solution");
/// }
/// ```
class Problem {
  final Map<String, List<dynamic>> _variables = {};
  final List<BinaryConstraint> _constraints = [];
  final List<NaryConstraint> _naryConstraints = [];
  int _timeStep = 1;
  CspCallback? _cb;

  /// Boolean variables that have been declared "soft" along with the
  /// weight contributed by their satisfaction. Used by
  /// [SoftConstraints.maximizeSatisfaction] to drive MaxCSP-style
  /// optimization. See `SoftConstraints`.
  final List<({String boolVar, int weight})> _softConstraints = [];

  /// Set-valued variables, keyed by user-facing name. Each entry holds
  /// the variable's universe (ordered) and the per-element internal
  /// indicator variable name. Populated by
  /// [SetVariables.addSetVariable]; consulted by [_materializeSets]
  /// on every solve entry point so the returned solution map exposes
  /// each set variable as a `Set<dynamic>` of its included elements
  /// instead of leaking the indicator variables.
  final Map<String, ({List<dynamic> universe, Map<dynamic, String> indicator})>
      _setVarUniverses = {};

  /// Replaces indicator-variable entries in a raw solver result with
  /// each set variable's materialized `Set<dynamic>`. No-op when no
  /// set variables have been declared, so the existing return shape
  /// is preserved for problems that don't use them.
  Map<String, dynamic> _materializeSets(Map<String, dynamic> raw) {
    if (_setVarUniverses.isEmpty) return raw;
    final stripped = <String>{};
    final out = <String, dynamic>{};
    for (final entry in _setVarUniverses.entries) {
      final included = <dynamic>{};
      for (final element in entry.value.universe) {
        final ind = entry.value.indicator[element]!;
        stripped.add(ind);
        if (raw[ind] == 1) included.add(element);
      }
      out[entry.key] = included;
    }
    for (final k in raw.keys) {
      if (!stripped.contains(k)) out[k] = raw[k];
    }
    return out;
  }

  /// Wraps a solver result (a `Map<String, dynamic>` or the literal
  /// `'FAILURE'` string) by materializing set variables, leaving the
  /// failure literal untouched.
  dynamic _wrapResult(dynamic result) {
    if (result is Map<String, dynamic>) return _materializeSets(result);
    return result;
  }

  /// Wraps a streaming solver result by materializing set variables on
  /// every emitted solution.
  Stream<Map<String, dynamic>> _wrapStream(
      Stream<Map<String, dynamic>> source) async* {
    await for (final sol in source) {
      yield _materializeSets(sol);
    }
  }

  /// Adds a single variable and its domain to the problem.
  ///
  /// - [name]: The name of the variable.
  /// - [domain]: A list of possible values for the variable.
  void addVariable(String name, List<dynamic> domain) {
    if (_variables.containsKey(name)) {
      throw ArgumentError("Variable '$name' already exists.");
    }
    if (domain.isEmpty) {
      throw ArgumentError("Domain for '$name' must be a non-empty list.");
    }
    _variables[name] = List.from(domain);
  }

  /// Adds multiple variables that share the same domain.
  ///
  /// - [names]: A list of variable names.
  /// - [domain]: A list of possible values for all variables.
  void addVariables(List<String> names, List<dynamic> domain) {
    for (final name in names) {
      addVariable(name, domain);
    }
  }

  /// Adds a variable whose domain is the contiguous integer range
  /// `[min, max]` (inclusive on both ends). Equivalent to
  /// `addVariable(name, [for (var i = min; i <= max; i++) i])`.
  ///
  /// For ranges with span greater than 1024 the engine uses a
  /// compact `(min, max)` domain representation that supports `O(1)`
  /// membership/length/bounds and keeps bounds-only reductions
  /// (e.g. from the linear-arithmetic propagator) in the same form
  /// without allocating per-step domain lists. This is the natural
  /// way to model scheduling-style horizons: start, duration, and
  /// end variables each over `[0, horizon]`.
  ///
  /// Throws [ArgumentError] if [name] is already added or
  /// `min > max`.
  void addRangeVariable(String name, int min, int max) {
    if (_variables.containsKey(name)) {
      throw ArgumentError("Variable '$name' already exists.");
    }
    if (min > max) {
      throw ArgumentError(
          "addRangeVariable '$name': empty range ($min > $max).");
    }
    _variables[name] = [for (var i = min; i <= max; i++) i];
  }

  /// Adds a constraint to the problem.
  ///
  /// Automatically routes to binary or n-ary constraint types based on the
  /// number of variables involved.
  ///
  /// - For **2 variables**, the [predicate] must be a [BinaryPredicate], i.e.,
  ///   `bool Function(dynamic, dynamic)`. The constraint will be added for
  ///   both directions (e.g., A->B and B->A) to ensure full consistency checks.
  /// - For **1, 3, or more variables**, the [predicate] must be an [NaryPredicate], i.e.,
  ///   `bool Function(Map<String, dynamic>)`.
  ///
  /// - [variables]: A list of variable names this constraint applies to.
  /// - [predicate]: The function that evaluates the constraint.
  /// - [label]: Optional human-readable label that surfaces on the
  ///   conflict-explanation API's [ConstraintRef.label]. For binary
  ///   constraints, the same label is attached to both directed arcs
  ///   so the forward+reverse pair shares one label.
  void addConstraint<T extends Function>(List<String> variables, T predicate,
      {String? label}) {
    if (variables.isEmpty) {
      throw ArgumentError(
          'addConstraint requires a non-empty list of variables.');
    }
    for (final v in variables) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addConstraint references variable '$v' which has not been added yet.");
      }
    }

    if (variables.length == 2) {
      if (predicate is! BinaryPredicate) {
        throw ArgumentError(
            'For 2 variables, predicate must be of type bool Function(dynamic, dynamic)');
      }
      final v1 = variables[0];
      final v2 = variables[1];
      // To ensure full arc consistency, we create directed constraints for
      // both directions from a single user-defined predicate.
      _constraints.add(BinaryConstraint(v1, v2, predicate, label: label));
      _constraints.add(BinaryConstraint(
          v2, v1, (val2, val1) => predicate(val1, val2),
          label: label));
    } else {
      if (predicate is! NaryPredicate) {
        throw ArgumentError(
            'For 1, 3, or more variables, predicate must be of type bool Function(Map<String, dynamic>)');
      }
      _naryConstraints.add(
          NaryConstraint(vars: variables, predicate: predicate, label: label));
    }
  }

  /// Sets the optional time step and callback for visualizing the search.
  ///
  /// - [timeStep]: The delay in milliseconds between solver steps.
  /// - [callback]: The function to call at each step.
  void setOptions({int? timeStep, CspCallback? callback}) {
    if (timeStep != null) _timeStep = timeStep;
    if (callback != null) _cb = callback;
  }

  /// Solves the problem and returns the first solution found.
  ///
  /// Assembles a [CspProblem] object from the added variables and constraints
  /// and passes it to the core [CSP.solve] function.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to [ConsistencyLevel.arcConsistency].
  ///
  /// Returns a [Future] that completes with:
  /// - A `Map<String, dynamic>` of variable assignments if a solution is found.
  /// - The string 'FAILURE' if no solution exists.
  Future<dynamic> getSolution(
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solve(problem,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Solves the problem and returns a stream of all solutions found.
  ///
  /// Assembles a [CspProblem] object from the added variables and constraints
  /// and uses the backtracking generator to find all valid assignments.
  ///
  /// Returns a [Stream] which emits a `Map<String, dynamic>` for each solution.
  /// If no solutions exist, the stream will be empty.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to [ConsistencyLevel.arcConsistency].
  ///
  /// ### Usage Example
  /// ```dart
  /// final p = Problem();
  /// p.addVariables(['A', 'B'], [1, 2, 3]);
  /// p.addStringConstraint('A < B');
  ///
  /// print('All solutions where A < B:');
  /// await for (final solution in p.getSolutions()) {
  ///   print(solution);
  /// }
  /// ```
  Stream<Map<String, dynamic>> getSolutions(
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      // timeStep and cb are less relevant for streaming all solutions
      // as the callback would be called too frequently
    );
    return _wrapStream(CSP.solveAll(problem,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Statistics from the most recent solve via this `Problem`. Null
  /// before any solve has run. Every solver populates these stats:
  /// backtracking entry points fill in the search counters
  /// (`decisions`, `backtracks`, ...); [getSolutions] sets them
  /// once the stream is fully consumed or cancelled;
  /// [solveWithMinConflicts] sets [SolverStats.iterations] and
  /// [SolverStats.elapsedMicros] and leaves the search counters at
  /// `0`.
  ///
  /// **Gotcha:** `lastStats` is a single static slot on [CSP], so
  /// it is shared across every `Problem` instance. A solve on one
  /// problem overwrites the stats from the most recent solve on any
  /// other. Capture `lastStats` immediately after the call that
  /// produced it if you need to compare runs.
  SolverStats? get lastStats => CSP.lastStats;

  /// Gets the number of variables in the problem
  int get variableCount => _variables.length;

  /// Gets the number of constraints in the problem
  int get constraintCount => _constraints.length + _naryConstraints.length;

  /// Removes all variables and constraints, resetting the problem
  void clear() {
    _variables.clear();
    _constraints.clear();
    _naryConstraints.clear();
  }

  /// Registers an n-ary predicate without dispatching through the
  /// 2-variable binary path. Use this when a predicate is naturally
  /// expressed as `bool Function(Map<String, dynamic>)` and would
  /// happen to fall into the 2-var case where [addConstraint] would
  /// demand a [BinaryPredicate]. Library-private helper used by the
  /// reified, logical, soft, and global-constraint extensions.
  void _addNary(List<String> vars, NaryPredicate predicate, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('_addNary requires a non-empty list of variables.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "_addNary references variable '$v' which has not been added yet.");
      }
    }
    _naryConstraints
        .add(NaryConstraint(vars: vars, predicate: predicate, label: label));
  }

  /// Creates a copy of this problem
  Problem copy() {
    final newProblem = Problem();
    newProblem._variables
        .addAll(_variables.map((k, v) => MapEntry(k, List.from(v))));
    newProblem._constraints.addAll(_constraints);
    newProblem._naryConstraints.addAll(_naryConstraints);
    newProblem._softConstraints.addAll(_softConstraints);
    newProblem._setVarUniverses.addAll(_setVarUniverses);
    newProblem._timeStep = _timeStep;
    newProblem._cb = _cb;
    return newProblem;
  }

  /// Returns the assignment that minimizes the value of [objective],
  /// or the string `'FAILURE'` if the problem has no solution at all.
  ///
  /// Branch-and-bound via iterative tightening: each time an improving
  /// solution is found, a constraint forbidding non-improving values is
  /// added on top of a fresh [copy] of the problem and the search
  /// restarts. The final returned assignment is provably optimal — no
  /// assignment with a strictly lower [objective] value satisfies the
  /// original constraints.
  ///
  /// This is the textbook "bound tightening" formulation, which re-runs
  /// the full backtracking search at each improvement. It is correct
  /// but not maximally efficient; a future integrated branch-and-bound
  /// inside the backtracking loop would avoid restart overhead.
  ///
  /// Throws [ArgumentError] if [objective] is not a registered variable
  /// or if its domain is non-numeric on a solution.
  ///
  /// Pass [consistency] to choose the propagation strength applied at
  /// every node of the search; defaults to
  /// [ConsistencyLevel.arcConsistency].
  ///
  /// Pass [useDomWdeg], [useVsids], [useImpact], or [useLastConflict]
  /// to bias variable selection during the integrated B&B search,
  /// mirroring [getSolutionWithDomWdeg] / [getSolutionWithActivity] /
  /// [getSolutionWithImpact] / [getSolutionWithLastConflict] for
  /// satisfaction problems.
  Future<dynamic> minimize(String objective,
          {bool useDomWdeg = false,
          bool useVsids = false,
          bool useImpact = false,
          bool useLastConflict = false,
          ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
          CancellationToken? cancelToken,
          bool enableConflictBackjumping = false}) =>
      _optimize(objective,
          minimizing: true,
          useDomWdeg: useDomWdeg,
          useVsids: useVsids,
          useImpact: useImpact,
          useLastConflict: useLastConflict,
          consistency: consistency,
          cancelToken: cancelToken,
          enableConflictBackjumping: enableConflictBackjumping);

  /// Returns the assignment that maximizes the value of [objective].
  /// Symmetric to [minimize]; see that method for the algorithm and
  /// caveats.
  Future<dynamic> maximize(String objective,
          {bool useDomWdeg = false,
          bool useVsids = false,
          bool useImpact = false,
          bool useLastConflict = false,
          ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
          CancellationToken? cancelToken,
          bool enableConflictBackjumping = false}) =>
      _optimize(objective,
          minimizing: false,
          useDomWdeg: useDomWdeg,
          useVsids: useVsids,
          useImpact: useImpact,
          useLastConflict: useLastConflict,
          consistency: consistency,
          cancelToken: cancelToken,
          enableConflictBackjumping: enableConflictBackjumping);

  Future<dynamic> _optimize(String objective,
      {required bool minimizing,
      required ConsistencyLevel consistency,
      bool useDomWdeg = false,
      bool useVsids = false,
      bool useImpact = false,
      bool useLastConflict = false,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    if (!_variables.containsKey(objective)) {
      throw ArgumentError(
          "Cannot ${minimizing ? 'minimize' : 'maximize'} unknown "
          "variable '$objective'.");
    }
    // Reject non-numeric domains upfront so the integrated B&B can
    // assume `value is num` at each leaf without re-checking.
    for (final v in _variables[objective]!) {
      if (v is! num) {
        throw ArgumentError(
            "Cannot optimize variable '$objective': value is not numeric "
            '($v of type ${v.runtimeType}).');
      }
    }
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveOptimal(problem, objective,
        minimizing: minimizing,
        useDomWdeg: useDomWdeg,
        useVsids: useVsids,
        useImpact: useImpact,
        useLastConflict: useLastConflict,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Solves the problem with Luby-scheduled restarts and randomized LCV
  /// tie-breaking. See [CSP.solveWithRestarts] for the algorithm.
  ///
  /// Useful on hard problem instances where chronological backtracking
  /// makes an early wrong choice and gets stuck deep in a doomed
  /// subtree; restarting from the root with a different value order
  /// often finds a solution dramatically faster.
  ///
  /// On infeasible problems, restarts complete normally and return
  /// `'FAILURE'` once the tree is exhausted. On hard but feasible
  /// problems where no attempt manages to either find a solution
  /// or exhaust the tree, [maxRestarts] (if provided) bounds total
  /// effort and the method returns `'FAILURE'` when reached.
  Future<dynamic> getSolutionWithRestarts({
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
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveWithRestarts(
      problem,
      scale: scale,
      maxRestarts: maxRestarts,
      seed: seed,
      useDomWdeg: useDomWdeg,
      useVsids: useVsids,
      useImpact: useImpact,
      useLastConflict: useLastConflict,
      consistency: consistency,
      cancelToken: cancelToken,
      enableConflictBackjumping: enableConflictBackjumping,
    ));
  }

  /// Backtracking search using the dom/wdeg variable heuristic. See
  /// [CSP.solveWithDomWdeg] for behavior; equivalent to [getSolution]
  /// but biases variable selection toward variables involved in
  /// failing constraints.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to [ConsistencyLevel.arcConsistency].
  Future<dynamic> getSolutionWithDomWdeg(
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveWithDomWdeg(problem,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Backtracking search using a VSIDS-style per-variable activity
  /// heuristic. See [CSP.solveWithActivity] for behavior; equivalent
  /// to [getSolution] but biases variable selection toward variables
  /// involved in recent propagation conflicts.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to [ConsistencyLevel.arcConsistency].
  Future<dynamic> getSolutionWithActivity(
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveWithActivity(problem,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Backtracking search using Impact-Based Search (Refalo 2004).
  /// See [CSP.solveWithImpact] for behavior; equivalent to
  /// [getSolution] but biases variable selection toward variables
  /// whose values historically prune the largest fraction of the
  /// joint search space.
  ///
  /// Pass [consistency] to choose the propagation strength; defaults
  /// to [ConsistencyLevel.arcConsistency].
  Future<dynamic> getSolutionWithImpact(
      {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveWithImpact(problem,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Backtracking search with Last-Conflict reasoning (Lecoutre 2009)
  /// layered on top of an underlying picker. See
  /// [CSP.solveWithLastConflict] for behavior. After every
  /// propagation failure, the engine records the variable being
  /// pinned and prefers it for the next decision (when still
  /// unassigned), focusing the search on the conflict cause.
  ///
  /// Pass [useDomWdeg], [useVsids], or [useImpact] to choose the
  /// underlying picker; without any of those flags LC composes
  /// with plain MRV. The canonical deployment shape from
  /// Lecoutre's experiments is `useDomWdeg: true`.
  ///
  /// Pass [consistency] to choose the propagation strength;
  /// defaults to [ConsistencyLevel.arcConsistency].
  Future<dynamic> getSolutionWithLastConflict(
      {bool useDomWdeg = false,
      bool useVsids = false,
      bool useImpact = false,
      ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
      CancellationToken? cancelToken,
      bool enableConflictBackjumping = false}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
      timeStep: _timeStep,
      cb: _cb,
    );
    return _wrapResult(await CSP.solveWithLastConflict(problem,
        useDomWdeg: useDomWdeg,
        useVsids: useVsids,
        useImpact: useImpact,
        consistency: consistency,
        cancelToken: cancelToken,
        enableConflictBackjumping: enableConflictBackjumping));
  }

  /// Solves the problem using the Min-Conflicts local search algorithm.
  ///
  /// This method is often faster for large problems but is not guaranteed to
  /// find a solution even if one exists. It's a good choice when you need
  /// *any* solution quickly, rather than a systematic search for one.
  /// It cannot find all solutions.
  ///
  /// Returns a [Future] that completes with:
  /// - A `Map<String, dynamic>` of variable assignments if a solution is found.
  /// - The string 'FAILURE' if no solution is found within [maxSteps].
  Future<dynamic> solveWithMinConflicts(
      {int maxSteps = 1000, int? seed, CancellationToken? cancelToken}) async {
    final problem = CspProblem(
      variables: _variables,
      constraints: _constraints,
      naryConstraints: _naryConstraints,
    );
    // Min-Conflicts doesn't support visualization callbacks in this implementation.
    return _wrapResult(await CSP.solveWithMinConflicts(problem,
        maxSteps: maxSteps, seed: seed, cancelToken: cancelToken));
  }

  /// Gets all variables and their current domains
  Map<String, List<dynamic>> get variables => Map.unmodifiable(_variables);
}

/// Extension methods for Problem class to make using built-in constraints easier
extension BuiltinConstraints on Problem {
  /// Add an all-different constraint
  void addAllDifferent(List<String> variables, {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, allDifferentBinary(), label: label);
      return;
    }
    // Validate variables exist (mirroring addConstraint's check).
    for (final v in variables) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addAllDifferent references variable '$v' which has not been added yet.");
      }
    }
    // Construct the n-ary constraint directly with the `allDifferent`
    // flag so the solver can dispatch to Régin's propagator.
    _naryConstraints.add(NaryConstraint(
      vars: variables,
      predicate: allDifferent(),
      allDifferent: true,
      label: label,
    ));
  }

  /// Add an all-equal constraint
  void addAllEqual(List<String> variables, {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, allEqualBinary(), label: label);
    } else {
      addConstraint(variables, allEqual(), label: label);
    }
  }

  /// Add an exact sum constraint
  void addExactSum(List<String> variables, num targetSum,
      {List<num>? multipliers, String? label}) {
    if (variables.length == 2) {
      addConstraint(
          variables, exactSumBinary(targetSum, multipliers: multipliers),
          label: label);
    } else {
      addConstraint(variables, exactSum(targetSum, multipliers: multipliers),
          label: label);
    }
  }

  /// Add a sum range constraint
  void addSumRange(List<String> variables, num minSum, num maxSum,
      {List<num>? multipliers, String? label}) {
    if (variables.length == 2) {
      addConstraint(
          variables, sumInRangeBinary(minSum, maxSum, multipliers: multipliers),
          label: label);
    } else {
      addConstraint(
          variables, sumInRange(minSum, maxSum, multipliers: multipliers),
          label: label);
    }
  }

  /// Add an exact product constraint
  void addExactProduct(List<String> variables, num targetProduct,
      {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, exactProductBinary(targetProduct), label: label);
    } else {
      addConstraint(variables, exactProduct(targetProduct), label: label);
    }
  }

  /// Add an in-set constraint (variables must take values from allowed set)
  void addInSet(List<String> variables, Set<dynamic> allowedValues,
      {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, inSetBinary(allowedValues), label: label);
    } else {
      addConstraint(variables, inSet(allowedValues), label: label);
    }
  }

  /// Add a not-in-set constraint (variables cannot take values from forbidden set)
  void addNotInSet(List<String> variables, Set<dynamic> forbiddenValues,
      {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, notInSetBinary(forbiddenValues), label: label);
    } else {
      addConstraint(variables, notInSet(forbiddenValues), label: label);
    }
  }

  /// Add an ordering constraint (variables in ascending order)
  void addAscending(List<String> variables, {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, ascendingBinary(), label: label);
    } else {
      addConstraint(variables, ascendingInOrder(variables), label: label);
    }
  }

  /// Add a strict ordering constraint (variables in strictly ascending order)
  void addStrictlyAscending(List<String> variables, {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, strictlyAscendingBinary(), label: label);
    } else {
      addConstraint(variables, strictlyAscendingInOrder(variables),
          label: label);
    }
  }

  /// Add a descending order constraint
  void addDescending(List<String> variables, {String? label}) {
    if (variables.length == 2) {
      addConstraint(variables, descendingBinary(), label: label);
    } else {
      addConstraint(variables, descendingInOrder(variables), label: label);
    }
  }

  /// Add a lexicographic ≤ symmetry-breaking constraint between two
  /// equal-length sequences of variables.
  ///
  /// Forbids assignments where `[left[0], left[1], ...]` is lex-greater
  /// than `[right[0], right[1], ...]`. This is the standard primitive
  /// for breaking row/column symmetry in puzzles and exchange symmetry
  /// between interchangeable agents: for every solution that violates
  /// the lex-ordering you'd otherwise get an equivalent dual solution
  /// where left and right are swapped, doubling the search work.
  ///
  /// Throws [ArgumentError] if the two lists differ in length or
  /// reference an unknown variable.
  void addLexLeq(List<String> left, List<String> right, {String? label}) {
    if (left.length != right.length) {
      throw ArgumentError(
          'addLexLeq requires equal-length sequences (got ${left.length} and ${right.length}).');
    }
    final all = [...left, ...right];
    for (final v in all) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addLexLeq references variable '$v' which has not been added yet.");
      }
    }
    addConstraint(all, lexLeq(left, right), label: label);
  }

  /// Strict lexicographic < variant of [addLexLeq]. Use when even
  /// equal-prefix-then-equal-rest assignments must be forbidden
  /// (e.g., to keep exactly one representative when two sequences
  /// being equal is itself a redundant case).
  void addLexLt(List<String> left, List<String> right, {String? label}) {
    if (left.length != right.length) {
      throw ArgumentError(
          'addLexLt requires equal-length sequences (got ${left.length} and ${right.length}).');
    }
    final all = [...left, ...right];
    for (final v in all) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addLexLt references variable '$v' which has not been added yet.");
      }
    }
    addConstraint(all, lexLt(left, right), label: label);
  }

  /// Add a **lexicographic chain** of [addLexLeq] (or [addLexLt] if
  /// [strict] is true) between consecutive rows in [rows]. Standard
  /// idiom for breaking row-permutation symmetry in matrix models
  /// where every row is interchangeable: posting one
  /// `lexLeq(rows[i], rows[i+1])` per consecutive pair selects a
  /// single canonical row-order representative from each
  /// permutation orbit.
  ///
  /// Lex-leq is transitive on `Comparable`, so chaining consecutive
  /// pairs is equivalent to (and cheaper than) posting all
  /// `k(k-1)/2` pairwise constraints between `k` rows. Set
  /// [strict] = `true` to forbid equal rows as well (use when
  /// duplicate rows are themselves redundant — e.g. when an
  /// `allDifferent` between rows would also hold).
  ///
  /// All rows must have the same length and reference only
  /// registered variables. Throws [ArgumentError] if [rows] has
  /// fewer than 2 entries, any two rows differ in length, or any
  /// variable is unknown.
  void addLexChain(List<List<String>> rows,
      {bool strict = false, String? label}) {
    if (rows.length < 2) {
      throw ArgumentError(
          'addLexChain requires at least 2 rows (got ${rows.length}).');
    }
    final n = rows[0].length;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].length != n) {
        throw ArgumentError(
            'addLexChain: row $i has length ${rows[i].length} but row 0 has '
            'length $n.');
      }
    }
    for (var i = 0; i + 1 < rows.length; i++) {
      if (strict) {
        addLexLt(rows[i], rows[i + 1], label: label);
      } else {
        addLexLeq(rows[i], rows[i + 1], label: label);
      }
    }
  }

  /// Add a **value-precedence** symmetry-breaking constraint over
  /// [variables] under the canonical [values] ordering.
  ///
  /// For each consecutive pair `(values[i], values[i+1])`, enforces
  /// that the first occurrence of `values[i]` in [variables] is
  /// strictly before the first occurrence of `values[i+1]` (or that
  /// `values[i+1]` is unused). Equivalently: a value from [values]
  /// may only appear in [variables] once every value listed earlier
  /// in [values] has already appeared.
  ///
  /// Standard primitive for breaking *value symmetry* — the symmetry
  /// where the labels assigned to a finite set of interchangeable
  /// alternatives (colors, agents, machine labels, bin IDs) can be
  /// permuted without changing the solution structure. Keeps exactly
  /// one representative from each permutation class of [values],
  /// reducing the search space by up to `k!` where
  /// `k = values.length`.
  ///
  /// Posts one n-ary [valuePrecedence] constraint over [variables]
  /// for each consecutive pair in [values] (so `values.length - 1`
  /// constraints total). [variables] may contain values outside of
  /// [values] — those simply aren't constrained relative to the
  /// canonical order.
  ///
  /// Throws [ArgumentError] if [values] has fewer than 2 entries
  /// (nothing to enforce), if [values] has duplicate entries, or if
  /// [variables] references an unknown variable.
  void addValuePrecedence(List<String> variables, List<dynamic> values,
      {String? label}) {
    if (values.length < 2) {
      throw ArgumentError(
          'addValuePrecedence requires at least 2 values in canonical order '
          '(got ${values.length}).');
    }
    if (values.toSet().length != values.length) {
      throw ArgumentError(
          'addValuePrecedence requires distinct values in canonical order.');
    }
    for (final v in variables) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addValuePrecedence references variable '$v' which has not been "
            'added yet.');
      }
    }
    for (var i = 0; i + 1 < values.length; i++) {
      _addNary(variables, valuePrecedence(variables, values[i], values[i + 1]),
          label: label);
    }
  }
}

/// Extension to add string constraint parsing to Problem class
extension StringConstraints on Problem {
  /// Add a constraint from a string expression
  ///
  /// Supports expressions like:
  /// - "A != B" (all different)
  /// - "A + B == 10" (exact sum)
  /// - "A * B >= 5" (minimum product)
  /// - "A + B + C == D" (variable sum)
  /// - "A in [1, 2, 3]" (set membership)
  /// - "A < B < C" (ordering)
  ///
  /// Example:
  /// ```dart
  /// final p = Problem();
  /// p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);
  /// p.addStringConstraint("A + B == C");
  /// p.addStringConstraint("A != B");
  /// ```
  void addStringConstraint(String constraintStr, {String? label}) {
    try {
      final parsed =
          ConstraintParser.parseConstraint(constraintStr, _variables);

      switch (parsed.type) {
        case ConstraintType.binary:
          addConstraint(parsed.variables, parsed.predicate as BinaryPredicate,
              label: label);
          break;
        case ConstraintType.nary:
          addConstraint(parsed.variables, parsed.predicate as NaryPredicate,
              label: label);
          break;
        case ConstraintType.variableSum:
        case ConstraintType.variableProduct:
          final varConstraint = parsed.predicate as VariableConstraint;
          addConstraint(parsed.variables, varConstraint.toPredicate(),
              label: label);
          break;
      }
    } catch (e) {
      throw ConstraintParseException(
          'Failed to parse constraint', constraintStr);
    }
  }

  /// Add multiple string constraints at once
  void addStringConstraints(List<String> constraints, {String? label}) {
    for (final constraint in constraints) {
      addStringConstraint(constraint, label: label);
    }
  }
}

/// Extension for debugging and introspection
extension ProblemDebug on Problem {
  /// Print a summary of the problem
  void printSummary() {
    print('CSP Problem Summary:');
    print('  Variables: $variableCount');
    print('  Constraints: $constraintCount');
    print('  Variables and domains:');
    for (final entry in _variables.entries) {
      print('    ${entry.key}: ${entry.value}');
    }
  }

  /// Validate the problem for common issues
  List<String> validate() {
    final issues = <String>[];

    // Check for empty domains
    for (final entry in _variables.entries) {
      if (entry.value.isEmpty) {
        issues.add('Variable ${entry.key} has empty domain');
      }
    }

    // Check if problem is over-constrained (more constraints than variables)
    if (constraintCount > variableCount * 2) {
      issues.add(
          'Problem may be over-constrained ($constraintCount constraints for $variableCount variables)');
    }

    // Check for isolated variables (variables with no constraints)
    final constrainedVariables = <String>{};
    for (final constraint in _constraints) {
      constrainedVariables.add(constraint.head);
      constrainedVariables.add(constraint.tail);
    }
    for (final constraint in _naryConstraints) {
      constrainedVariables.addAll(constraint.vars);
    }

    for (final varName in _variables.keys) {
      if (!constrainedVariables.contains(varName)) {
        issues.add('Variable $varName has no constraints (isolated)');
      }
    }

    return issues;
  }
}

/// Extension providing utilities for working with multiple solutions
extension MultipleSolutions on Problem {
  /// Get all solutions as a List (convenience method for small solution sets)
  ///
  /// Warning: This will collect all solutions in memory. For problems with
  /// many solutions, prefer using getSolutions() stream directly.
  ///
  /// Example:
  /// ```dart
  /// final solutions = await p.getAllSolutions();
  /// print('Found ${solutions.length} solutions');
  /// for (final solution in solutions) {
  ///   print(solution);
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> getAllSolutions() async {
    final solutions = <Map<String, dynamic>>[];
    await for (final solution in getSolutions()) {
      solutions.add(solution);
    }
    return solutions;
  }

  /// Count the total number of solutions without storing them
  ///
  /// This is memory-efficient for problems with many solutions.
  ///
  /// Example:
  /// ```dart
  /// final count = await p.countSolutions();
  /// print('This problem has $count solutions');
  /// ```
  Future<int> countSolutions() async {
    var count = 0;
    await for (final _ in getSolutions()) {
      count++;
    }
    return count;
  }

  /// Check if multiple solutions exist without finding them all
  ///
  /// This stops after finding the second solution, making it efficient
  /// for determining if a problem has a unique solution.
  ///
  /// Example:
  /// ```dart
  /// final hasMultiple = await p.hasMultipleSolutions();
  /// if (hasMultiple) {
  ///   print('Problem has multiple solutions');
  /// } else {
  ///   print('Problem has at most one solution');
  /// }
  /// ```
  Future<bool> hasMultipleSolutions() async {
    var count = 0;
    await for (final _ in getSolutions()) {
      count++;
      if (count >= 2) return true;
    }
    return false;
  }

  /// Get the first N solutions
  ///
  /// This stops the search after finding the specified number of solutions,
  /// making it more efficient than finding all solutions if you only need a few.
  /// This is useful when you want to see a few examples without processing all solutions.
  ///
  /// Example:
  /// ```dart
  /// final firstFive = await p.getFirstNSolutions(5);
  /// print('First 5 solutions:');
  /// for (final solution in firstFive) {
  ///   print(solution);
  /// }
  /// ```
  Future<List<Map<String, dynamic>>> getFirstNSolutions(int n) async {
    final solutions = <Map<String, dynamic>>[];
    if (n <= 0) return solutions; // Handle n=0 edge case
    await for (final solution in getSolutions()) {
      solutions.add(solution);
      if (solutions.length >= n) {
        break;
      }
    }
    return solutions;
  }
}

/// Reified constraints. A reified constraint introduces a 0/1 boolean
/// variable whose value tracks whether some underlying relation holds:
///
/// ```dart
/// p.addVariable('X', [1, 2, 3, 4, 5]);
/// p.addReifiedEquals('bX5', 'X', 5);     // bX5 ⇔ (X == 5)
/// p.addStringConstraint('bX5 == 1');     // forces X = 5
/// ```
///
/// Once a boolean variable exists, it composes naturally with the
/// existing arithmetic/comparison machinery — e.g. counting how many
/// reified constraints hold is just a string constraint over the
/// boolean variables:
///
/// ```dart
/// p.addStringConstraint('bA + bB + bC >= 2');  // at least 2 hold
/// ```
///
/// All methods auto-register [boolVar] with domain `[0, 1]` if it has
/// not already been added. They throw [ArgumentError] if [boolVar]
/// exists with a non-{0,1} domain or if a referenced data variable
/// has not been added.
extension ReifiedConstraints on Problem {
  /// Ensures [boolVar] is registered with domain [0, 1].
  void _ensureBoolVar(String boolVar) {
    if (_variables.containsKey(boolVar)) {
      final dom = _variables[boolVar]!;
      final domSet = dom.toSet();
      if (!domSet.every((v) => v == 0 || v == 1)) {
        throw ArgumentError(
            "Reified bool var '$boolVar' already has a non-{0,1} domain: $dom");
      }
      return;
    }
    addVariable(boolVar, [0, 1]);
  }

  void _requireDataVar(String name) {
    if (!_variables.containsKey(name)) {
      throw ArgumentError(
          "Reified constraint references variable '$name' which has not been added yet.");
    }
  }

  /// `b ⇔ (variable == constant)`. Forces [boolVar] to track whether
  /// [variable] equals [constant] in any satisfying assignment.
  void addReifiedEquals(String boolVar, String variable, dynamic constant,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      if (b == 1) return v == constant;
      if (b == 0) return v != constant;
      return false;
    }, label: label);
  }

  /// `b ⇔ (variable != constant)`.
  void addReifiedNotEquals(String boolVar, String variable, dynamic constant,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      if (b == 1) return v != constant;
      if (b == 0) return v == constant;
      return false;
    }, label: label);
  }

  /// `b ⇔ (variable < constant)`. Variable's domain must be numeric.
  void addReifiedLessThan(String boolVar, String variable, num constant,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      final val = v as num;
      if (b == 1) return val < constant;
      if (b == 0) return val >= constant;
      return false;
    }, label: label);
  }

  /// `b ⇔ (variable <= constant)`.
  void addReifiedLessOrEqual(String boolVar, String variable, num constant,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      final val = v as num;
      if (b == 1) return val <= constant;
      if (b == 0) return val > constant;
      return false;
    }, label: label);
  }

  /// `b ⇔ (variable > constant)`.
  void addReifiedGreaterThan(String boolVar, String variable, num constant,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      final val = v as num;
      if (b == 1) return val > constant;
      if (b == 0) return val <= constant;
      return false;
    }, label: label);
  }

  /// `b ⇔ (variable >= constant)`.
  void addReifiedGreaterOrEqual(String boolVar, String variable, num constant,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      final val = v as num;
      if (b == 1) return val >= constant;
      if (b == 0) return val < constant;
      return false;
    }, label: label);
  }

  /// `b ⇔ (variable ∈ allowedValues)`.
  void addReifiedInSet(
      String boolVar, String variable, Set<dynamic> allowedValues,
      {String? label}) {
    _requireDataVar(variable);
    _ensureBoolVar(boolVar);
    addConstraint([boolVar, variable], (dynamic b, dynamic v) {
      final inSet = allowedValues.contains(v);
      if (b == 1) return inSet;
      if (b == 0) return !inSet;
      return false;
    }, label: label);
  }

  /// `b ⇔ (left == right)` for two variables.
  void addReifiedEqualsVar(String boolVar, String left, String right,
      {String? label}) {
    _requireDataVar(left);
    _requireDataVar(right);
    _ensureBoolVar(boolVar);
    // Three-variable n-ary reification (boolVar + the two operands).
    addConstraint([boolVar, left, right], (Map<String, dynamic> a) {
      final b = a[boolVar];
      final l = a[left];
      final r = a[right];
      // If any operand is unassigned (null), the predicate is
      // conservatively satisfied; the solver re-checks on completion.
      if (l == null || r == null || b == null) return true;
      if (b == 1) return l == r;
      if (b == 0) return l != r;
      return false;
    }, label: label);
  }

  /// Generic reification: `b ⇔ predicate(assignment)` over [vars].
  /// Use when no specialized helper fits. [vars] must list every
  /// variable the predicate reads, plus [boolVar] is added at the
  /// front automatically.
  void addReified(String boolVar, List<String> vars,
      bool Function(Map<String, dynamic>) predicate,
      {String? label}) {
    for (final v in vars) {
      _requireDataVar(v);
    }
    _ensureBoolVar(boolVar);
    final allVars = [boolVar, ...vars];
    _addNary(allVars, (Map<String, dynamic> a) {
      final b = a[boolVar];
      // If any required var is unassigned, accept (defensive — the
      // predicate may need full assignment to evaluate).
      for (final v in vars) {
        if (a[v] == null) return true;
      }
      final holds = predicate(a);
      if (b == 1) return holds;
      if (b == 0) return !holds;
      return false;
    }, label: label);
  }
}

/// Logical combinators on boolean (0/1) variables. These compose with
/// [ReifiedConstraints]: reify each sub-constraint to get a boolean,
/// then combine the booleans with the helpers below.
///
/// All methods require their variable arguments to have been added
/// already and to have domains that are subsets of `{0, 1}`. They
/// throw [ArgumentError] otherwise.
extension LogicalConstraints on Problem {
  void _requireBoolVars(List<String> vars) {
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "Logical constraint references variable '$v' which has not been added yet.");
      }
      final dom = _variables[v]!.toSet();
      if (!dom.every((x) => x == 0 || x == 1)) {
        throw ArgumentError(
            "Logical constraint variable '$v' has a non-{0,1} domain: $dom");
      }
    }
  }

  /// At least [k] of the given boolean variables must be 1.
  /// `addAtLeast([b1, b2, b3], 2)` ⇔ `b1 + b2 + b3 >= 2`.
  void addAtLeast(List<String> boolVars, int k, {String? label}) {
    _requireBoolVars(boolVars);
    addConstraint(boolVars, (Map<String, dynamic> a) {
      var s = 0;
      for (final v in boolVars) {
        s += a[v] as int;
      }
      return s >= k;
    }, label: label);
  }

  /// At most [k] of the given boolean variables may be 1.
  void addAtMost(List<String> boolVars, int k, {String? label}) {
    _requireBoolVars(boolVars);
    addConstraint(boolVars, (Map<String, dynamic> a) {
      var s = 0;
      for (final v in boolVars) {
        s += a[v] as int;
      }
      return s <= k;
    }, label: label);
  }

  /// Exactly [k] of the given boolean variables must be 1.
  void addExactly(List<String> boolVars, int k, {String? label}) {
    _requireBoolVars(boolVars);
    addConstraint(boolVars, (Map<String, dynamic> a) {
      var s = 0;
      for (final v in boolVars) {
        s += a[v] as int;
      }
      return s == k;
    }, label: label);
  }

  /// Material implication: `[antecedent] = 1` forces `[consequent] = 1`.
  /// (When [antecedent] = 0, [consequent] is unconstrained.)
  void addImplies(String antecedent, String consequent, {String? label}) {
    _requireBoolVars([antecedent, consequent]);
    addConstraint(
        [antecedent, consequent], (dynamic a, dynamic c) => !(a == 1 && c == 0),
        label: label);
  }

  /// `boolVar ⇔ (b1 ∧ b2 ∧ ... ∧ bn)`. [boolVar] is auto-added with
  /// domain `[0, 1]` if it doesn't already exist.
  void addReifiedAnd(String boolVar, List<String> bools, {String? label}) {
    _requireBoolVars(bools);
    _ensureBoolVar(boolVar);
    final all = [boolVar, ...bools];
    _addNary(all, (Map<String, dynamic> a) {
      final b = a[boolVar] as int;
      var all1 = true;
      for (final v in bools) {
        if (a[v] != 1) {
          all1 = false;
          break;
        }
      }
      return b == (all1 ? 1 : 0);
    }, label: label);
  }

  /// `boolVar ⇔ (b1 ∨ b2 ∨ ... ∨ bn)`.
  void addReifiedOr(String boolVar, List<String> bools, {String? label}) {
    _requireBoolVars(bools);
    _ensureBoolVar(boolVar);
    final all = [boolVar, ...bools];
    _addNary(all, (Map<String, dynamic> a) {
      final b = a[boolVar] as int;
      var any1 = false;
      for (final v in bools) {
        if (a[v] == 1) {
          any1 = true;
          break;
        }
      }
      return b == (any1 ? 1 : 0);
    }, label: label);
  }

  /// `boolVar ⇔ ¬[otherBool]`, i.e. `boolVar = 1 - otherBool`.
  void addReifiedNot(String boolVar, String otherBool, {String? label}) {
    _requireBoolVars([otherBool]);
    _ensureBoolVar(boolVar);
    addConstraint(
        [boolVar, otherBool],
        (dynamic b, dynamic other) =>
            (b == 1 && other == 0) || (b == 0 && other == 1),
        label: label);
  }

  /// SAT-style **clause** constraint: the disjunction of the listed
  /// boolean literals must hold. [positive] lists variables that
  /// appear unnegated; [negative] lists variables that appear
  /// negated. The clause is satisfied iff at least one variable in
  /// [positive] takes value 1 OR at least one variable in [negative]
  /// takes value 0.
  ///
  /// Internally tags the n-ary constraint with a [ClauseSpec] so the
  /// engine dispatches to a textbook two-watched-literal propagator
  /// (Moskewicz et al., Chaff 2001): each clause keeps two watcher
  /// indices into its literal list that are updated lazily across
  /// propagation calls, so per-call work is O(1) amortized once the
  /// watchers are initialized. The engine's propagation queue also
  /// applies a matching per-variable seeding filter — once the
  /// watchers are set, reductions to non-watched variables don't
  /// wake the propagator. The user-visible pruning is the standard
  /// unit-propagation rule; both the watchers and the seeding filter
  /// are implementation details.
  ///
  /// Composes naturally with [ReifiedConstraints] for CNF-style
  /// modeling: reify each sub-constraint to a boolean, then express
  /// arbitrary CNF over the booleans via repeated [addClause]
  /// calls. All listed variables must already be registered and
  /// have domain ⊆ `{0, 1}`. Variables can appear in both [positive]
  /// and [negative] (which makes the clause vacuously satisfied), or
  /// appear multiple times in one list (redundant but accepted). An
  /// entirely empty clause (no literals) is the empty disjunction,
  /// which is always false — registered as a constraint that rejects
  /// every assignment.
  ///
  /// Throws [ArgumentError] if any listed variable is unknown or has
  /// a non-`{0, 1}` domain.
  void addClause({
    List<String> positive = const <String>[],
    List<String> negative = const <String>[],
    String? label,
  }) {
    final all = <String>[...positive, ...negative];
    _requireBoolVars(all);
    if (all.isEmpty) {
      // Empty disjunction is vacuously false. Need at least one
      // variable to attach the constraint to; the engine doesn't
      // support zero-arity n-ary constraints.
      if (_variables.isEmpty) {
        throw ArgumentError(
            'addClause with no literals requires at least one variable '
            'in the problem to attach the (vacuously false) constraint to.');
      }
      final anchor = _variables.keys.first;
      _naryConstraints.add(NaryConstraint(
        vars: <String>[anchor],
        predicate: (Map<String, dynamic> _) => false,
        clauseSpec: ClauseSpec(literals: const []),
        label: label,
      ));
      return;
    }
    final literals = <({String varName, bool positive})>[
      for (final v in positive) (varName: v, positive: true),
      for (final v in negative) (varName: v, positive: false),
    ];
    _naryConstraints.add(NaryConstraint(
      vars: all,
      predicate: (Map<String, dynamic> a) {
        for (final lit in literals) {
          final v = a[lit.varName];
          if (lit.positive ? v == 1 : v == 0) return true;
        }
        return false;
      },
      clauseSpec: ClauseSpec(literals: literals),
      label: label,
    ));
  }
}

/// Global constraints: predicates expressing common structured
/// relations that show up across CSP modeling. These are direct
/// generic-GAC encodings; they're correct on any problem but a real
/// production solver would ship specialized propagators (e.g. an
/// MDD-compressed table propagator, range-aware element propagation).
extension GlobalConstraints on Problem {
  /// `list[idxVar] == valueVar` — the **element** constraint.
  ///
  /// [list] is a fixed list of values, [idxVar] is the index into it
  /// (must be an integer 0..list.length-1 at solve time), and
  /// [valueVar] must equal the selected element. Use for any kind of
  /// indirection ("the cost of the chosen item is X").
  ///
  /// Throws [ArgumentError] if either variable hasn't been added.
  void addElement(String idxVar, List<dynamic> list, String valueVar,
      {String? label}) {
    if (!_variables.containsKey(idxVar)) {
      throw ArgumentError(
          "addElement: index variable '$idxVar' has not been added.");
    }
    if (!_variables.containsKey(valueVar)) {
      throw ArgumentError(
          "addElement: value variable '$valueVar' has not been added.");
    }
    addConstraint([idxVar, valueVar], (dynamic idx, dynamic val) {
      if (idx is! int) return false;
      if (idx < 0 || idx >= list.length) return false;
      return list[idx] == val;
    }, label: label);
  }

  /// **Table** constraint: the tuple `(vars[0], vars[1], ...)` must
  /// equal one of the [tuples].
  ///
  /// Useful for encoding arbitrary relations that don't have a clean
  /// closed-form predicate (e.g. compatibility matrices, lookup
  /// tables, finite-state-machine transitions).
  ///
  /// Throws [ArgumentError] if any [vars] entry is unknown, or if
  /// any tuple's length doesn't match `vars.length`.
  ///
  /// Note: the current implementation is a generic n-ary predicate
  /// that scans all tuples on each check (O(|tuples|·n) per call).
  /// For very large tables, prefer pre-filtering or a custom
  /// propagator.
  void addTable(List<String> vars, List<List<dynamic>> tuples,
      {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addTable requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addTable references variable '$v' which has not been added yet.");
      }
    }
    for (final tup in tuples) {
      if (tup.length != vars.length) {
        throw ArgumentError(
            'addTable: tuple of length ${tup.length} does not match vars length ${vars.length}.');
      }
    }
    if (tuples.isEmpty) {
      // Vacuously infeasible: no assignment satisfies the empty
      // disjunction of allowed tuples. Encode as a permanently-false
      // constraint, picking the right predicate shape for the arity.
      if (vars.length == 2) {
        addConstraint(vars, (dynamic _, dynamic __) => false, label: label);
      } else {
        addConstraint(vars, (Map<String, dynamic> _) => false, label: label);
      }
      return;
    }
    if (vars.length == 2) {
      // addConstraint demands a BinaryPredicate for arity 2.
      addConstraint(vars, (dynamic a, dynamic b) {
        for (final tup in tuples) {
          if (tup[0] == a && tup[1] == b) return true;
        }
        return false;
      }, label: label);
      return;
    }
    addConstraint(vars, (Map<String, dynamic> a) {
      for (final tup in tuples) {
        var allMatch = true;
        for (var i = 0; i < vars.length; i++) {
          if (a[vars[i]] != tup[i]) {
            allMatch = false;
            break;
          }
        }
        if (allMatch) return true;
      }
      return false;
    }, label: label);
  }

  /// `addAmong(vars, values, countVar)` — the **among** constraint.
  ///
  /// The number of [vars] whose value falls in [values] equals
  /// [countVar]. [countVar] is a registered variable; its domain
  /// typically ranges over `[0, vars.length]`. Use for "how many of
  /// these slots are X" patterns: morning shifts assigned, odd values
  /// picked, items chosen from a category, etc.
  ///
  /// For a fixed count, use [addAmongExactly] instead.
  ///
  /// Throws [ArgumentError] if [vars] is empty or any referenced
  /// variable is unknown.
  void addAmong(List<String> vars, Set<dynamic> values, String countVar,
      {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addAmong requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addAmong references variable '$v' which has not been added yet.");
      }
    }
    if (!_variables.containsKey(countVar)) {
      throw ArgumentError(
          "addAmong: count variable '$countVar' has not been added.");
    }
    _addNary([countVar, ...vars], (Map<String, dynamic> a) {
      var n = 0;
      for (final v in vars) {
        if (values.contains(a[v])) n++;
      }
      return a[countVar] == n;
    }, label: label);
  }

  /// Fixed-count variant of [addAmong]: exactly [k] of [vars] take a
  /// value in [values].
  ///
  /// Throws [ArgumentError] if [vars] is empty, any variable is
  /// unknown, or [k] is outside `[0, vars.length]`.
  void addAmongExactly(List<String> vars, Set<dynamic> values, int k,
      {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError(
          'addAmongExactly requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addAmongExactly references variable '$v' which has not been added yet.");
      }
    }
    if (k < 0 || k > vars.length) {
      throw ArgumentError(
          'addAmongExactly: k=$k must be between 0 and ${vars.length}.');
    }
    _addNary(vars, (Map<String, dynamic> a) {
      var n = 0;
      for (final v in vars) {
        if (values.contains(a[v])) n++;
      }
      return n == k;
    }, label: label);
  }

  /// `addNvalue(vars, countVar)` — the **nvalue** constraint.
  ///
  /// [countVar] equals the number of distinct values taken across
  /// [vars]. Useful for chromatic-number-style problems (minimize
  /// distinct colors used), resource-usage rationing (use at most K
  /// distinct shifts), and palette restriction.
  ///
  /// For a fixed count, use [addNvalueExactly] instead.
  ///
  /// Throws [ArgumentError] if [vars] is empty or any referenced
  /// variable is unknown.
  void addNvalue(List<String> vars, String countVar, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addNvalue requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addNvalue references variable '$v' which has not been added yet.");
      }
    }
    if (!_variables.containsKey(countVar)) {
      throw ArgumentError(
          "addNvalue: count variable '$countVar' has not been added.");
    }
    _addNary([countVar, ...vars], (Map<String, dynamic> a) {
      final s = <dynamic>{};
      for (final v in vars) {
        s.add(a[v]);
      }
      return a[countVar] == s.length;
    }, label: label);
  }

  /// Fixed-count variant of [addNvalue]: exactly [k] distinct values
  /// must appear across [vars].
  ///
  /// Throws [ArgumentError] if [vars] is empty, any variable is
  /// unknown, or [k] is outside `[1, vars.length]`.
  void addNvalueExactly(List<String> vars, int k, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError(
          'addNvalueExactly requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addNvalueExactly references variable '$v' which has not been added yet.");
      }
    }
    if (k < 1 || k > vars.length) {
      throw ArgumentError(
          'addNvalueExactly: k=$k must be between 1 and ${vars.length}.');
    }
    _addNary(vars, (Map<String, dynamic> a) {
      final s = <dynamic>{};
      for (final v in vars) {
        s.add(a[v]);
      }
      return s.length == k;
    }, label: label);
  }

  /// `addGcc(vars, counts)` — **global cardinality constraint** (exact
  /// counts form). For each `(value, count)` entry in [counts], exactly
  /// `count` of [vars] must be assigned to `value`. Values not present
  /// in [counts] are unconstrained in their occurrence count.
  ///
  /// Generalizes `allDifferent` (the case where each value-of-interest
  /// has count 1). Use for shift rosters ("morning occurs exactly 3
  /// times"), distribution problems, sudoku-like puzzles where each
  /// digit appears a fixed number of times, etc.
  ///
  /// For ranged occurrence requirements, see [addGccRanges].
  ///
  /// Throws [ArgumentError] if [vars] is empty, any variable is
  /// unknown, any count is negative, or the sum of counts exceeds
  /// [vars.length] (infeasible by pigeonhole).
  void addGcc(List<String> vars, Map<dynamic, int> counts, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addGcc requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addGcc references variable '$v' which has not been added yet.");
      }
    }
    var sumCounts = 0;
    for (final entry in counts.entries) {
      if (entry.value < 0) {
        throw ArgumentError(
            'addGcc: count for value ${entry.key} must be non-negative, got ${entry.value}.');
      }
      sumCounts += entry.value;
    }
    if (sumCounts > vars.length) {
      throw ArgumentError(
          'addGcc: sum of required counts ($sumCounts) exceeds variable count (${vars.length}).');
    }
    final gccBounds = <dynamic, ({int min, int max})>{
      for (final entry in counts.entries)
        entry.key: (min: entry.value, max: entry.value),
    };
    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: (Map<String, dynamic> a) {
        final hist = <dynamic, int>{};
        for (final v in vars) {
          final val = a[v];
          hist[val] = (hist[val] ?? 0) + 1;
        }
        for (final entry in counts.entries) {
          if ((hist[entry.key] ?? 0) != entry.value) return false;
        }
        return true;
      },
      gccSpec: GccSpec(bounds: gccBounds),
      label: label,
    ));
  }

  /// `addRegular(vars, dfa)` — the **regular** constraint.
  ///
  /// The sequence `(vars[0], vars[1], ..., vars[n-1])` must be
  /// accepted by [dfa] when read left-to-right. Each variable's
  /// assignment is the next symbol; the DFA's transition function
  /// drives the state; the sequence is accepted iff the final state
  /// is in [Dfa.accepting].
  ///
  /// Useful for sequencing rules expressible as a finite automaton:
  /// at-most-k pattern occurrences, run-length bounds, alternation
  /// requirements ("at least one rest between two night shifts"),
  /// arbitrary regular-language constraints over assignments.
  ///
  /// Throws [ArgumentError] if [vars] is empty, any variable is
  /// unknown, the DFA's start state is out of range, or any
  /// accepting state is out of range.
  void addRegular(List<String> vars, Dfa dfa, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addRegular requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addRegular references variable '$v' which has not been added yet.");
      }
    }
    if (dfa.start < 0 || dfa.start >= dfa.numStates) {
      throw ArgumentError(
          'addRegular: start state ${dfa.start} is outside [0, ${dfa.numStates}).');
    }
    for (final s in dfa.accepting) {
      if (s < 0 || s >= dfa.numStates) {
        throw ArgumentError(
            'addRegular: accepting state $s is outside [0, ${dfa.numStates}).');
      }
    }
    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: (Map<String, dynamic> a) {
        var state = dfa.start;
        for (final v in vars) {
          final next = dfa.step(state, a[v]);
          if (next == null) return false;
          state = next;
        }
        return dfa.accepting.contains(state);
      },
      regularDfa: dfa,
      label: label,
    ));
  }

  /// `addCircuit(vars)` — the **circuit** constraint.
  ///
  /// Interprets `vars[i]` as the *successor* of position `i` in a
  /// permutation of `[0, vars.length)`. The successor function must
  /// form a single Hamiltonian cycle visiting every position exactly
  /// once before returning to position 0. Use for TSP-like sequencing
  /// problems, vehicle routing, and any "single tour through every
  /// node" pattern.
  ///
  /// Each variable's domain should be a subset of integers in
  /// `[0, vars.length)`; values outside that range or non-integer
  /// values cause the constraint to fail at check time. The
  /// underlying permutation requirement (all successors distinct) is
  /// enforced by the predicate but not by a separate `allDifferent`
  /// — combine with `addAllDifferent(vars)` for stronger early
  /// pruning if the search is slow.
  ///
  /// Throws [ArgumentError] if [vars] is empty or any variable is
  /// unknown.
  void addCircuit(List<String> vars, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addCircuit requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addCircuit references variable '$v' which has not been added yet.");
      }
    }
    final n = vars.length;
    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: (Map<String, dynamic> a) {
        final next = List<int>.filled(n, -1);
        for (var i = 0; i < n; i++) {
          final v = a[vars[i]];
          if (v is! int || v < 0 || v >= n) return false;
          next[i] = v;
        }
        final visited = List<bool>.filled(n, false);
        var cur = 0;
        for (var k = 0; k < n; k++) {
          if (visited[cur]) return false;
          visited[cur] = true;
          cur = next[cur];
        }
        // Closed the loop back to 0 after visiting every position
        // exactly once.
        return cur == 0;
      },
      circuit: true,
      label: label,
    ));
  }

  /// `addSubcircuit(vars)` — the **subcircuit** constraint.
  ///
  /// Like [addCircuit], `vars[i]` is interpreted as the successor of
  /// position `i`. Unlike circuit, the self-loop `vars[i] = i` is
  /// permitted and means "position `i` is not in the cycle". The
  /// remaining (non-self-loop) edges among the positions that *are*
  /// in the cycle must still form a single cycle; an empty
  /// subcircuit (every position self-looped) is also valid. Standard
  /// CP primitive for vehicle routing with optional stops, "visit a
  /// subset of cities in one tour", and any sequencing problem where
  /// the set of visited positions is itself part of the decision.
  ///
  /// Each variable's domain should be a subset of integers in
  /// `[0, vars.length)`; values outside that range or non-integer
  /// values cause the constraint to fail at check time. The
  /// underlying permutation requirement (each value used at most
  /// once across `vars`, including the self-loop slots) is enforced
  /// both by the propagator and by the predicate at leaves;
  /// `addAllDifferent(vars)` is therefore redundant.
  ///
  /// Throws [ArgumentError] if [vars] is empty or any variable is
  /// unknown.
  void addSubcircuit(List<String> vars, {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addSubcircuit requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addSubcircuit references variable '$v' which has not been added yet.");
      }
    }
    final n = vars.length;
    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: (Map<String, dynamic> a) {
        final next = List<int>.filled(n, -1);
        for (var i = 0; i < n; i++) {
          final v = a[vars[i]];
          if (v is! int || v < 0 || v >= n) return false;
          next[i] = v;
        }
        // Permutation: each value used at most once across the
        // successor list (self-loop slot `i` is "used" by `vars[i] = i`).
        final used = List<bool>.filled(n, false);
        for (var i = 0; i < n; i++) {
          if (used[next[i]]) return false;
          used[next[i]] = true;
        }
        // Single cycle on non-self-looped positions. Find the first
        // included position and the total count of included
        // positions; if none, every position is skipped (valid empty
        // subcircuit).
        var start = -1;
        var included = 0;
        for (var i = 0; i < n; i++) {
          if (next[i] != i) {
            included++;
            if (start == -1) start = i;
          }
        }
        if (start == -1) return true;
        // Walk forward from `start`; the cycle must visit exactly
        // `included` distinct positions before returning to `start`.
        var cur = next[start];
        var count = 1;
        while (cur != start) {
          if (next[cur] == cur) return false; // landed on a skipped position
          cur = next[cur];
          count++;
          if (count > included) return false; // safety against runaway
        }
        return count == included;
      },
      subcircuit: true,
      label: label,
    ));
  }

  /// `addInverse(forward, inverse)` — the **inverse** channelling
  /// constraint.
  ///
  /// [forward] and [inverse] are equal-length variable lists of
  /// length `n`. For every `i, j` in `0..n-1`, the constraint enforces
  ///
  ///     forward[i] = j   ⇔   inverse[j] = i
  ///
  /// — i.e. the two lists represent functional inverses of each other
  /// over `0..n-1`. Standard pattern for problems that benefit from
  /// modelling the same relation in both directions: assignment
  /// problems where you want `task[i] = machine` and
  /// `machine[j] = task` simultaneously, scheduling models that
  /// channel "what is in slot t?" and "when is event e scheduled?",
  /// or any permutation problem where some constraints are easier on
  /// the forward map and others on the inverse map.
  ///
  /// Implies that both [forward] and [inverse] are (partial)
  /// permutations of `0..n-1`: if any two `forward[i] = forward[i']`
  /// for `i != i'`, the inverse cell would need to take two values at
  /// once — which the channelling constraint forbids. You therefore
  /// don't need a separate `addAllDifferent` for either list once
  /// `addInverse` is posted.
  ///
  /// All listed variables must already be registered and have integer
  /// domains. Each domain is automatically intersected with `0..n-1`
  /// at solve time via the channelling logic (out-of-range values
  /// won't satisfy the constraint and will be pruned by AC-3).
  ///
  /// Decomposes into `n²` binary constraints so AC-3 can propagate
  /// them efficiently: each pair `(i, j)` becomes
  /// `(forward[i] = j) ⇔ (inverse[j] = i)`. For very large `n` you
  /// can wrap with explicit domain restrictions to keep AC-3 work
  /// bounded.
  ///
  /// Throws [ArgumentError] if [forward] and [inverse] differ in
  /// length, the lists are empty, or any variable is unknown.
  void addInverse(List<String> forward, List<String> inverse, {String? label}) {
    if (forward.length != inverse.length) {
      throw ArgumentError(
          'addInverse: forward and inverse must have the same length '
          '(${forward.length} vs ${inverse.length}).');
    }
    if (forward.isEmpty) {
      throw ArgumentError('addInverse requires non-empty variable lists.');
    }
    for (final v in forward) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addInverse references forward variable '$v' which has not been "
            'added yet.');
      }
    }
    for (final v in inverse) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addInverse references inverse variable '$v' which has not been "
            'added yet.');
      }
    }
    final n = forward.length;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        // (forward[i] == j) ⇔ (inverse[j] == i)
        addConstraint([
          forward[i],
          inverse[j]
        ], (dynamic fv, dynamic iv) => (fv == j) == (iv == i), label: label);
      }
    }
  }

  /// `addBinPacking(items, sizes, binLoads)` — the **bin packing**
  /// constraint.
  ///
  /// Each `items[i]` is a CSP variable holding the bin assignment for
  /// item `i` (an int in `[0, binLoads.length)`). `sizes[i]` is the
  /// fixed integer size of item `i`. For each bin `b`, the constraint
  /// enforces `binLoads[b] == sum(sizes[i] for items[i] == b)`.
  ///
  /// Bin capacities are not part of this constraint — to bound a
  /// bin's total, constrain its `binLoads[b]` variable separately
  /// (e.g. `addStringConstraint('binLoad0 <= 10')` or a custom
  /// domain). To minimize total bins used, count nonzero loads via
  /// reified `binLoad_b > 0` flags and `minimize` their sum.
  ///
  /// Throws [ArgumentError] if [items] is empty, [sizes] doesn't
  /// match [items] in length, [binLoads] is empty, any variable is
  /// unknown, or any size is negative.
  void addBinPacking(List<String> items, List<int> sizes, List<String> binLoads,
      {String? label}) {
    if (items.isEmpty) {
      throw ArgumentError('addBinPacking requires a non-empty items list.');
    }
    if (sizes.length != items.length) {
      throw ArgumentError(
          'addBinPacking: sizes length (${sizes.length}) must match items '
          'length (${items.length}).');
    }
    if (binLoads.isEmpty) {
      throw ArgumentError('addBinPacking requires a non-empty binLoads list.');
    }
    for (final v in items) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addBinPacking references items variable '$v' which has not been added yet.");
      }
    }
    for (final v in binLoads) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addBinPacking references binLoads variable '$v' which has not been added yet.");
      }
    }
    for (final s in sizes) {
      if (s < 0) {
        throw ArgumentError(
            'addBinPacking: item sizes must be non-negative, got $s.');
      }
    }
    final numBins = binLoads.length;
    _addNary([...items, ...binLoads], (Map<String, dynamic> a) {
      final loads = List<int>.filled(numBins, 0);
      for (var i = 0; i < items.length; i++) {
        final b = a[items[i]];
        if (b is! int || b < 0 || b >= numBins) return false;
        loads[b] += sizes[i];
      }
      for (var b = 0; b < numBins; b++) {
        if (a[binLoads[b]] != loads[b]) return false;
      }
      return true;
    }, label: label);
  }

  /// Range variant of [addGcc]: for each `(value, (min, max))` entry,
  /// the number of [vars] assigned to `value` must lie in `[min, max]`
  /// (inclusive). Values not present in [ranges] are unconstrained.
  ///
  /// Throws [ArgumentError] if [vars] is empty, any variable is
  /// unknown, any range is malformed (`min < 0` or `max < min`), or
  /// the sum of minimums exceeds [vars.length].
  void addGccRanges(
      List<String> vars, Map<dynamic, ({int min, int max})> ranges,
      {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addGccRanges requires a non-empty variable list.');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addGccRanges references variable '$v' which has not been added yet.");
      }
    }
    var sumMin = 0;
    for (final entry in ranges.entries) {
      final r = entry.value;
      if (r.min < 0 || r.max < r.min) {
        throw ArgumentError(
            'addGccRanges: invalid range for ${entry.key}: min=${r.min}, max=${r.max}.');
      }
      sumMin += r.min;
    }
    if (sumMin > vars.length) {
      throw ArgumentError(
          'addGccRanges: sum of minimums ($sumMin) exceeds variable count (${vars.length}).');
    }
    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: (Map<String, dynamic> a) {
        final hist = <dynamic, int>{};
        for (final v in vars) {
          final val = a[v];
          hist[val] = (hist[val] ?? 0) + 1;
        }
        for (final entry in ranges.entries) {
          final cnt = hist[entry.key] ?? 0;
          if (cnt < entry.value.min || cnt > entry.value.max) return false;
        }
        return true;
      },
      gccSpec: GccSpec(bounds: Map<dynamic, ({int min, int max})>.from(ranges)),
      label: label,
    ));
  }

  /// Disjunctive / unary-resource **no-overlap** constraint. For every
  /// pair of tasks `(i, j)`, enforces
  ///   `starts[i] + durations[i] <= starts[j]`  OR
  ///   `starts[j] + durations[j] <= starts[i]`
  /// so the half-open intervals
  /// `[starts[i], starts[i] + durations[i])` do not overlap.
  ///
  /// Each task is described by a registered start variable and a
  /// **constant** duration; if you need a variable duration, model
  /// the end time as a separate variable, add the relation
  /// `start + duration == end` via [LinearConstraints.addLinearEquals],
  /// and express the no-overlap condition directly with
  /// [BuiltinConstraints]/[LogicalConstraints] primitives.
  ///
  /// Common use cases: machine scheduling (one task per machine at a
  /// time), exam timetabling (one student per room per slot), unary
  /// resource constraints in project scheduling.
  ///
  /// **Implementation note.** This helper dispatches to [addCumulative]
  /// with `capacity = 1` and every demand `= 1`, which is the exact
  /// no-overlap reduction. The cumulative time-table propagator
  /// gives strictly stronger pruning than the prior O(n²) pairwise-
  /// disjunction encoding, while the constraint semantics are
  /// unchanged.
  ///
  /// Throws [ArgumentError] if [starts] and [durations] differ in
  /// length, any start variable is unknown, or any duration is
  /// negative.
  void addNoOverlap(List<String> starts, List<int> durations, {String? label}) {
    if (starts.length != durations.length) {
      throw ArgumentError(
          'addNoOverlap: starts and durations must have the same length '
          '(${starts.length} vs ${durations.length}).');
    }
    for (final s in starts) {
      if (!_variables.containsKey(s)) {
        throw ArgumentError(
            "addNoOverlap references variable '$s' which has not been added yet.");
      }
    }
    for (var i = 0; i < durations.length; i++) {
      if (durations[i] < 0) {
        throw ArgumentError(
            'addNoOverlap: duration $i is negative (${durations[i]}).');
      }
    }
    if (starts.isEmpty) return;
    addCumulative(
      starts,
      durations,
      List<int>.filled(starts.length, 1),
      1,
      label: label,
    );
  }

  /// 2D rectangle **non-overlap** constraint (the standard
  /// `diff_n` global). Generalises [addNoOverlap] from a unary
  /// resource (1D time) to two dimensions.
  ///
  /// Each rectangle `i` is described by its lower-left corner
  /// `(xs[i], ys[i])` — both registered variables — and its
  /// **constant** size `(widths[i], heights[i])`. The constraint
  /// enforces that for every pair `(i, j)` of distinct rectangles,
  /// the half-open boxes
  ///
  ///     [xs[i], xs[i] + widths[i]) × [ys[i], ys[i] + heights[i])
  ///     [xs[j], xs[j] + widths[j]) × [ys[j], ys[j] + heights[j])
  ///
  /// have empty intersection — equivalently, at least one of the
  /// four 1D separation conditions holds:
  ///
  ///     xs[i] + widths[i] <= xs[j]   (i is left  of j)
  ///     xs[j] + widths[j] <= xs[i]   (j is left  of i)
  ///     ys[i] + heights[i] <= ys[j]  (i is below j)
  ///     ys[j] + heights[j] <= ys[i]  (j is below i)
  ///
  /// Use for rectangle packing (cutting stock, container loading),
  /// floor planning (VLSI placement, room layout), 2D scheduling
  /// (machine × time grids), and tile-placement puzzles. For 3D or
  /// higher-dimensional analogues, compose multiple instances over
  /// shared axes — there's no built-in `diff_n` for more than two
  /// dimensions.
  ///
  /// Implementation: tags the constraint with a [DiffNSpec] so the
  /// engine dispatches to a forbidden-region sweep propagator
  /// (Beldiceanu & Carlsson, "Sweep as a generic pruning technique
  /// applied to the non-overlapping rectangles constraint", CP 2001).
  /// For each rectangle and each dimension, the propagator aggregates
  /// the forbidden-position intervals induced by every other
  /// rectangle whose compulsory part in the orthogonal dimension
  /// forces an overlap, then filters the current domain in one pass.
  /// The constraint's scope spans all `2n` coordinate variables in
  /// the order `[xs..., ys...]`, so propagation runs once per change
  /// to any rectangle rather than `n(n-1)/2` times across pairwise
  /// 4-ary constraints. A belt-and-braces leaf predicate (the same
  /// pairwise disjunction the old decomposition relied on) is kept
  /// on the constraint.
  ///
  /// Zero-area rectangles (width or height = 0) are excluded from the
  /// constraint scope: they trivially do not overlap with anything,
  /// and dropping them keeps the propagator's `n` matched to the
  /// number of "real" rectangles. Variable coordinates must be
  /// numeric; the lower-left can be negative if you model an origin
  /// shift. The propagator's sweep is integer-only — non-`int`
  /// coordinates defer pruning to the leaf predicate.
  ///
  /// Throws [ArgumentError] if [xs], [ys], [widths], and [heights]
  /// disagree in length, any coordinate variable is unknown, or any
  /// width or height is negative.
  void addDiffN(
    List<String> xs,
    List<String> ys,
    List<int> widths,
    List<int> heights, {
    String? label,
  }) {
    final n = xs.length;
    if (ys.length != n || widths.length != n || heights.length != n) {
      throw ArgumentError(
          'addDiffN: xs (${xs.length}), ys (${ys.length}), widths '
          '(${widths.length}), and heights (${heights.length}) must have the '
          'same length.');
    }
    for (final v in xs) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addDiffN references x variable '$v' which has not been added yet.");
      }
    }
    for (final v in ys) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addDiffN references y variable '$v' which has not been added yet.");
      }
    }
    for (var i = 0; i < n; i++) {
      if (widths[i] < 0) {
        throw ArgumentError('addDiffN: width $i is negative (${widths[i]}).');
      }
      if (heights[i] < 0) {
        throw ArgumentError('addDiffN: height $i is negative (${heights[i]}).');
      }
    }
    if (n < 2) return;
    // Filter out zero-area rectangles before constructing the spec:
    // they trivially do not overlap with anything, so they would
    // just waste work for the propagator on every call.
    final keepXs = <String>[];
    final keepYs = <String>[];
    final keepW = <int>[];
    final keepH = <int>[];
    for (var i = 0; i < n; i++) {
      if (widths[i] == 0 || heights[i] == 0) continue;
      keepXs.add(xs[i]);
      keepYs.add(ys[i]);
      keepW.add(widths[i]);
      keepH.add(heights[i]);
    }
    final m = keepXs.length;
    if (m < 2) return;
    final spec = DiffNSpec(
      widths: List<int>.unmodifiable(keepW),
      heights: List<int>.unmodifiable(keepH),
    );
    final vars = <String>[...keepXs, ...keepYs];
    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: (Map<String, dynamic> a) {
        // Soundness predicate (used at leaves; the engine bypasses
        // generic _reviseNary for tagged constraints). Walk every
        // pair and reject if both projections overlap. Partial
        // assignments (any coordinate absent) accept.
        for (var i = 0; i < m; i++) {
          final axi = a[keepXs[i]];
          final ayi = a[keepYs[i]];
          if (axi == null || ayi == null) return true;
          for (var j = i + 1; j < m; j++) {
            final axj = a[keepXs[j]];
            final ayj = a[keepYs[j]];
            if (axj == null || ayj == null) return true;
            final xi = axi as num;
            final yi = ayi as num;
            final xj = axj as num;
            final yj = ayj as num;
            final separated = xi + keepW[i] <= xj ||
                xj + keepW[j] <= xi ||
                yi + keepH[i] <= yj ||
                yj + keepH[j] <= yi;
            if (!separated) return false;
          }
        }
        return true;
      },
      diffNSpec: spec,
      label: label,
    ));
  }

  /// **Cumulative** resource constraint. Generalizes [addNoOverlap]
  /// from a unary resource (one task at a time) to an integer-capacity
  /// resource: at every time `t`, the sum of [demands] across tasks
  /// whose half-open interval `[starts[i], starts[i] + durations[i])`
  /// covers `t` may not exceed [capacity].
  ///
  /// Use for any "renewable" resource that several tasks can share up
  /// to a bound — machine slots with multiple identical units,
  /// throughput-limited stations, parallel workers, room-with-N-seats
  /// scheduling, etc. The classical RCPSP (Resource-Constrained
  /// Project Scheduling Problem) is exactly this constraint applied
  /// to each resource type.
  ///
  /// Each entry of [starts] must be a registered variable; [durations]
  /// and [demands] are constant integer vectors aligned with [starts].
  /// Setting `capacity = 1` and every demand to `1` reduces this
  /// constraint to disjunctive (unary) no-overlap, matching
  /// [addNoOverlap]'s semantics.
  ///
  /// Internally tags the n-ary constraint with a [CumulativeSpec] so
  /// the engine dispatches to a time-table propagator: compute each
  /// task's *compulsory part* (the interval `[lst_i, est_i + dur_i)`
  /// the task must occupy in every feasible schedule when that
  /// interval is non-empty), sum the compulsory parts into a global
  /// usage profile, and prune any start value that would push the
  /// profile above [capacity] at some time.
  ///
  /// On top of the time-table profile the propagator also runs an
  /// energetic-reasoning pass (Baptiste, Le Pape & Nuijten 1999) — a
  /// stronger, still-sound overload check plus earliest-start /
  /// latest-completion adjustments. That pass is O(n³) in the task count
  /// (internally capped above a task-count bound); pass
  /// [useEnergeticReasoning] `false` to opt out of it entirely.
  ///
  /// Throws [ArgumentError] if [starts], [durations], and [demands]
  /// disagree in length, any start variable is unknown, any duration
  /// or demand is negative, or [capacity] is negative. A zero-task
  /// call is a no-op (no constraint registered).
  void addCumulative(
    List<String> starts,
    List<int> durations,
    List<int> demands,
    int capacity, {
    String? label,
    bool useEnergeticReasoning = true,
  }) {
    if (starts.length != durations.length || starts.length != demands.length) {
      throw ArgumentError('addCumulative: starts (${starts.length}), durations '
          '(${durations.length}), and demands (${demands.length}) must have '
          'the same length.');
    }
    for (final s in starts) {
      if (!_variables.containsKey(s)) {
        throw ArgumentError(
            "addCumulative references variable '$s' which has not been added yet.");
      }
    }
    for (var i = 0; i < durations.length; i++) {
      if (durations[i] < 0) {
        throw ArgumentError(
            'addCumulative: duration $i is negative (${durations[i]}).');
      }
      if (demands[i] < 0) {
        throw ArgumentError(
            'addCumulative: demand $i is negative (${demands[i]}).');
      }
    }
    if (capacity < 0) {
      throw ArgumentError(
          'addCumulative: capacity must be non-negative (got $capacity).');
    }
    if (starts.isEmpty) return;
    final spec = CumulativeSpec(
      durations: List<int>.unmodifiable(durations),
      demands: List<int>.unmodifiable(demands),
      capacity: capacity,
      useEnergeticReasoning: useEnergeticReasoning,
    );
    _naryConstraints.add(NaryConstraint(
      vars: starts,
      predicate: (Map<String, dynamic> a) {
        // Soundness predicate: tasks with zero duration or zero demand
        // contribute nothing, so skip them. For the rest, accumulate
        // per-time-step usage and reject any over-capacity step.
        final usage = <int, int>{};
        for (var i = 0; i < starts.length; i++) {
          final dur = durations[i];
          final dem = demands[i];
          if (dur == 0 || dem == 0) continue;
          final v = a[starts[i]];
          if (v is! int) return false;
          for (var t = v; t < v + dur; t++) {
            final next = (usage[t] ?? 0) + dem;
            if (next > capacity) return false;
            usage[t] = next;
          }
        }
        return true;
      },
      cumulativeSpec: spec,
      label: label,
    ));
  }
}

/// Linear arithmetic constraints with a bounds-consistency
/// propagator.
///
/// Each constraint has the shape
///   `Σ coeffs[i] · vars[i]  ∘  bound`
/// where `∘` is one of `==`, `≤`, or `≥`. The engine tags the
/// constraint with a [LinearSpec] and dispatches propagation to a
/// dedicated bounds-consistency routine that narrows each variable's
/// domain to values compatible with the interval of the partial sum
/// computed from the other variables' current mins and maxes.
/// Stronger than predicate-only encoding on arithmetic constraints
/// with many variables; weaker than full GAC.
///
/// Coefficients may be positive, negative, or zero. Domains of all
/// involved variables must be numeric (`int` or `double`) — this is
/// checked at constraint registration time.
extension LinearConstraints on Problem {
  /// `Σ coeffs[i] · vars[i] == bound`.
  void addLinearEquals(List<String> vars, List<num> coeffs, num bound,
          {String? label}) =>
      _addLinear(vars, coeffs, LinearOp.eq, bound, label: label);

  /// `Σ coeffs[i] · vars[i] <= bound`.
  void addLinearLeq(List<String> vars, List<num> coeffs, num bound,
          {String? label}) =>
      _addLinear(vars, coeffs, LinearOp.leq, bound, label: label);

  /// `Σ coeffs[i] · vars[i] >= bound`.
  void addLinearGeq(List<String> vars, List<num> coeffs, num bound,
          {String? label}) =>
      _addLinear(vars, coeffs, LinearOp.geq, bound, label: label);

  void _addLinear(List<String> vars, List<num> coeffs, LinearOp op, num bound,
      {String? label}) {
    if (vars.isEmpty) {
      throw ArgumentError('addLinear* requires a non-empty list of variables.');
    }
    if (vars.length != coeffs.length) {
      throw ArgumentError('addLinear*: vars and coeffs differ in length '
          '(${vars.length} vs ${coeffs.length}).');
    }
    for (final v in vars) {
      if (!_variables.containsKey(v)) {
        throw ArgumentError(
            "addLinear* references variable '$v' which has not been added yet.");
      }
      for (final dv in _variables[v]!) {
        if (dv is! num) {
          throw ArgumentError(
              "addLinear*: variable '$v' has non-numeric value '$dv' in its domain.");
        }
      }
    }

    // Soundness predicate: the propagator only enforces bounds
    // consistency, so the predicate still verifies the constraint
    // exactly when the engine reaches a complete assignment of these
    // variables.
    bool predicate(Map<String, dynamic> a) {
      num s = 0;
      for (var i = 0; i < vars.length; i++) {
        final v = a[vars[i]];
        if (v is! num) return true; // partial assignment — defer to leaf
        s += coeffs[i] * v;
      }
      switch (op) {
        case LinearOp.eq:
          return s == bound;
        case LinearOp.leq:
          return s <= bound;
        case LinearOp.geq:
          return s >= bound;
      }
    }

    _naryConstraints.add(NaryConstraint(
      vars: vars,
      predicate: predicate,
      linearSpec:
          LinearSpec(coeffs: List<num>.from(coeffs), op: op, bound: bound),
      label: label,
    ));
  }
}

/// Soft constraints / MaxCSP support.
///
/// A "soft" constraint is one that the solver tries to satisfy but
/// isn't required to. Each soft constraint contributes a fixed
/// non-negative weight to the objective when satisfied; failing to
/// satisfy it costs that weight. The job of
/// [maximizeSatisfaction] is then to find the feasible assignment
/// (w.r.t. all hard constraints) that maximizes the total weight
/// of satisfied soft constraints.
///
/// Internally:
/// 1. Each soft constraint is reified to a 0/1 boolean (you can
///    do this manually with `addReified*` and call [declareSoft], or
///    use [addSoftConstraint] which does both in one step).
/// 2. [maximizeSatisfaction] builds an aggregator variable equal to
///    `Σ weight_i × boolVar_i` and runs [Problem.maximize] on it.
/// 3. Because [Problem.maximize] uses iterative branch-and-bound,
///    the returned assignment is provably optimal: no other feasible
///    assignment has a higher total satisfied-weight.
extension SoftConstraints on Problem {
  /// Marks an existing 0/1 boolean variable as soft, contributing
  /// [weight] to the satisfaction objective whenever it takes value 1.
  ///
  /// Throws [ArgumentError] if [boolVar] is unknown, doesn't have
  /// domain ⊆ {0, 1}, or [weight] is negative.
  void declareSoft(String boolVar, int weight) {
    if (!_variables.containsKey(boolVar)) {
      throw ArgumentError(
          "declareSoft: variable '$boolVar' has not been added.");
    }
    final dom = _variables[boolVar]!.toSet();
    if (!dom.every((v) => v == 0 || v == 1)) {
      throw ArgumentError(
          "declareSoft: variable '$boolVar' has a non-{0,1} domain: $dom");
    }
    if (weight < 0) {
      throw ArgumentError(
          'declareSoft: weight must be non-negative, got $weight.');
    }
    _softConstraints.add((boolVar: boolVar, weight: weight));
  }

  /// One-step helper that reifies an arbitrary predicate over [vars]
  /// (creating a new auto-named boolean variable) and declares the
  /// result as a soft constraint with the given [weight].
  ///
  /// Returns the auto-generated boolean variable name so the caller
  /// can use it in further constraints.
  String addSoftConstraint(int weight, List<String> vars,
      bool Function(Map<String, dynamic>) predicate,
      {String? label}) {
    final boolName = '_soft_${_softConstraints.length}_'
        '${DateTime.now().microsecondsSinceEpoch}';
    addReified(boolName, vars, predicate, label: label);
    declareSoft(boolName, weight);
    return boolName;
  }

  /// Solves the problem maximizing the total weight of satisfied soft
  /// constraints (subject to all hard constraints).
  ///
  /// If no soft constraints have been declared, this falls back to
  /// [getSolution] (a feasibility check).
  ///
  /// Implementation: builds an aggregator variable on a [copy] of the
  /// problem equal to `Σ weight_i × boolVar_i` and runs
  /// [Problem.maximize] on it. The original problem is not mutated.
  ///
  /// Returns the optimal assignment (a `Map<String, dynamic>`) or the
  /// string `'FAILURE'` if the hard constraints alone are
  /// unsatisfiable.
  Future<dynamic> maximizeSatisfaction({CancellationToken? cancelToken}) async {
    if (_softConstraints.isEmpty) return getSolution(cancelToken: cancelToken);

    final problem = copy();
    final maxTotal = _softConstraints.fold<int>(0, (s, e) => s + e.weight);
    // Unique aggregator name to avoid colliding with user variables
    // across multiple calls.
    final totalVar = '_soft_total_${DateTime.now().microsecondsSinceEpoch}';
    problem.addVariable(totalVar, [for (var i = 0; i <= maxTotal; i++) i]);

    final boolNames = [for (final s in _softConstraints) s.boolVar];
    final weights = [for (final s in _softConstraints) s.weight];

    problem._addNary(
      [totalVar, ...boolNames],
      (Map<String, dynamic> a) {
        var sum = 0;
        for (var i = 0; i < boolNames.length; i++) {
          sum += weights[i] * (a[boolNames[i]] as int);
        }
        return a[totalVar] == sum;
      },
    );

    return problem.maximize(totalVar, cancelToken: cancelToken);
  }
}

/// Set-valued variables backed by per-element 0/1 indicator
/// variables.
///
/// A *set variable* takes its value from `2^U` for some finite
/// universe `U` declared at construction time. Internally the
/// representation is a vector of 0/1 indicator variables — one per
/// element of `U` — whose pattern of 1s names the chosen subset.
/// This lets every existing primitive (linear arithmetic for
/// cardinality, reified/logical for membership tests, plain binary
/// constraints for subset/disjoint/equality) compose with set
/// variables without any new propagator.
///
/// All solve entry points on [Problem] post-process the raw result
/// so each declared set variable appears in the returned map as a
/// `Set<dynamic>` of its included elements rather than as the raw
/// indicator variables. The internal indicator variable names
/// (prefixed `__set__`) are stripped from the map.
///
/// ```dart
/// final p = Problem()
///   ..addSetVariables(['Team', 'Bench'], universe: [
///     'alice', 'bob', 'carol', 'dave', 'erin',
///   ])
///   ..addSetCardinality('Team', 3)
///   ..addSetCardinality('Bench', 2)
///   ..addSetDisjoint('Team', 'Bench')
///   ..addRequiredInSet('Team', 'alice');
///
/// final result = await p.getSolution();
/// // result['Team'] is a Set<dynamic> of 3 names including 'alice';
/// // result['Bench'] is a Set<dynamic> of 2 names disjoint from
/// // 'Team'.
/// ```
///
/// **Universe matching.** Pairwise relations ([addSetEquals],
/// [addSubset], [addSetDisjoint]) and ternary relations
/// ([addSetUnion], [addSetIntersection], [addSetDifference])
/// reason element-by-element by looking up shared elements through
/// the universes of the involved set variables. The ternary
/// operations require all three set variables to share the **same
/// universe** (as a set); the binary operations allow universes
/// that differ — only elements present in both contribute a
/// constraint, with the asymmetric leftover handled per operation
/// (e.g. [addSubset] forces a sub-only element to be excluded from
/// the subset since `super` cannot contain it).
extension SetVariables on Problem {
  /// Names of every declared set variable, in declaration order.
  Iterable<String> get setVariableNames => _setVarUniverses.keys;

  /// Returns the universe (in declaration order) for set variable
  /// [name]. Throws [ArgumentError] if [name] is not a registered
  /// set variable.
  List<dynamic> setUniverse(String name) {
    final entry = _setVarUniverses[name];
    if (entry == null) {
      throw ArgumentError("'$name' is not a registered set variable.");
    }
    return List<dynamic>.unmodifiable(entry.universe);
  }

  /// Declares a set-valued variable [name] whose value is a subset
  /// of [universe].
  ///
  /// Internally, each element of [universe] becomes a 0/1 indicator
  /// variable with reserved internal name `__set__<name>__<i>` (i is
  /// the element's index in the universe). Solutions returned
  /// through this [Problem]'s solve entry points expose [name] as a
  /// `Set<dynamic>` of the included elements rather than the
  /// indicator variables.
  ///
  /// [required] pins each listed element into the set at declaration
  /// time (indicator domain `[1]`); [excluded] pins each out
  /// (indicator domain `[0]`); the remaining elements remain free
  /// (domain `[0, 1]`).
  ///
  /// Throws [ArgumentError] if [name] is already used (as a set or
  /// regular variable), [universe] is empty or contains duplicates,
  /// [required] or [excluded] reference an element not in
  /// [universe], or an element appears in both.
  void addSetVariable(
    String name, {
    required Iterable<dynamic> universe,
    Iterable<dynamic> required = const <dynamic>[],
    Iterable<dynamic> excluded = const <dynamic>[],
  }) {
    if (_setVarUniverses.containsKey(name)) {
      throw ArgumentError("Set variable '$name' already exists.");
    }
    if (_variables.containsKey(name)) {
      throw ArgumentError(
          "Variable '$name' already exists (cannot reuse as set variable).");
    }
    final univList = universe.toList();
    if (univList.isEmpty) {
      throw ArgumentError("Set variable '$name': universe must be non-empty.");
    }
    final univSet = <dynamic>{};
    for (final e in univList) {
      if (!univSet.add(e)) {
        throw ArgumentError(
            "Set variable '$name': duplicate element '$e' in universe.");
      }
    }
    final requiredSet = required.toSet();
    final excludedSet = excluded.toSet();
    for (final e in requiredSet) {
      if (!univSet.contains(e)) {
        throw ArgumentError(
            "Set variable '$name': required element '$e' is not in universe.");
      }
      if (excludedSet.contains(e)) {
        throw ArgumentError(
            "Set variable '$name': element '$e' is both required and excluded.");
      }
    }
    for (final e in excludedSet) {
      if (!univSet.contains(e)) {
        throw ArgumentError(
            "Set variable '$name': excluded element '$e' is not in universe.");
      }
    }
    final indicators = <dynamic, String>{};
    for (var i = 0; i < univList.length; i++) {
      final element = univList[i];
      final indName = '__set__${name}__$i';
      final List<dynamic> dom;
      if (requiredSet.contains(element)) {
        dom = <dynamic>[1];
      } else if (excludedSet.contains(element)) {
        dom = <dynamic>[0];
      } else {
        dom = <dynamic>[0, 1];
      }
      addVariable(indName, dom);
      indicators[element] = indName;
    }
    _setVarUniverses[name] = (universe: univList, indicator: indicators);
  }

  /// Declares multiple set variables sharing the same [universe] (and
  /// optionally the same [required] / [excluded] pin sets). Convenience
  /// for the common case where several sets are subsets of a common
  /// alphabet.
  void addSetVariables(
    Iterable<String> names, {
    required Iterable<dynamic> universe,
    Iterable<dynamic> required = const <dynamic>[],
    Iterable<dynamic> excluded = const <dynamic>[],
  }) {
    for (final n in names) {
      addSetVariable(n,
          universe: universe, required: required, excluded: excluded);
    }
  }

  /// Returns the internal 0/1 indicator variable for [setName] and
  /// universe [element]. Use this to compose set membership with the
  /// reified, logical, or linear constraint helpers when you need a
  /// relation that the dedicated set helpers don't express.
  ///
  /// Throws [ArgumentError] if [setName] is not a registered set
  /// variable, or [element] is not in its universe.
  String memberIndicator(String setName, dynamic element) {
    final entry = _setVarUniverses[setName];
    if (entry == null) {
      throw ArgumentError("memberIndicator: '$setName' is not a set variable.");
    }
    final name = entry.indicator[element];
    if (name == null) {
      throw ArgumentError(
          "memberIndicator: '$element' is not in the universe of '$setName'.");
    }
    return name;
  }

  /// `|setName| == k`: exactly [k] elements of the universe are in
  /// the set. Decomposes to `addLinearEquals` over the indicator
  /// variables.
  ///
  /// Throws [ArgumentError] if [setName] is unknown or [k] is
  /// outside `[0, |universe|]`.
  void addSetCardinality(String setName, int k, {String? label}) {
    final entry = _requireSetVar('addSetCardinality', setName);
    final inds = entry.indicator.values.toList();
    if (k < 0 || k > inds.length) {
      throw ArgumentError(
          'addSetCardinality: k=$k must be between 0 and ${inds.length}.');
    }
    addLinearEquals(inds, List<num>.filled(inds.length, 1), k, label: label);
  }

  /// `minCard <= |setName| <= maxCard`. Bounds-consistency linear
  /// constraints (skips a side when the bound is vacuous).
  ///
  /// Throws [ArgumentError] if [setName] is unknown or the bounds
  /// are out of range or inconsistent.
  void addSetCardinalityRange(String setName, int minCard, int maxCard,
      {String? label}) {
    final entry = _requireSetVar('addSetCardinalityRange', setName);
    final inds = entry.indicator.values.toList();
    if (minCard < 0 || maxCard < minCard || maxCard > inds.length) {
      throw ArgumentError(
          'addSetCardinalityRange: invalid bounds (min=$minCard, max=$maxCard, '
          '|U|=${inds.length}).');
    }
    final coeffs = List<num>.filled(inds.length, 1);
    if (minCard > 0) addLinearGeq(inds, coeffs, minCard, label: label);
    if (maxCard < inds.length) {
      addLinearLeq(inds, coeffs, maxCard, label: label);
    }
  }

  /// `|setName| == countVar` where [countVar] is a pre-declared
  /// integer variable. Use this when the cardinality itself is part
  /// of the objective or another constraint
  /// (e.g. `minimize(countVar)`).
  ///
  /// Throws [ArgumentError] if [setName] or [countVar] are unknown.
  void addSetCardinalityVar(String setName, String countVar, {String? label}) {
    final entry = _requireSetVar('addSetCardinalityVar', setName);
    final inds = entry.indicator.values.toList();
    if (!_variables.containsKey(countVar)) {
      throw ArgumentError(
          "addSetCardinalityVar: count variable '$countVar' has not been added.");
    }
    // Σ inds[i] - countVar == 0.
    addLinearEquals(
      [...inds, countVar],
      [...List<num>.filled(inds.length, 1), -1],
      0,
      label: label,
    );
  }

  /// Forces [element] to be a member of [setName] (pins the
  /// indicator to 1). Use when the pin happens after declaration; for
  /// pinning at declaration time, prefer the `required:` parameter
  /// on [addSetVariable].
  void addRequiredInSet(String setName, dynamic element, {String? label}) {
    final ind = memberIndicator(setName, element);
    addConstraint(<String>[ind], (Map<String, dynamic> a) => a[ind] == 1,
        label: label);
  }

  /// Forces [element] to be excluded from [setName] (pins the
  /// indicator to 0).
  void addExcludedFromSet(String setName, dynamic element, {String? label}) {
    final ind = memberIndicator(setName, element);
    addConstraint(<String>[ind], (Map<String, dynamic> a) => a[ind] == 0,
        label: label);
  }

  /// `subName ⊆ superName`. For every element `e` of [subName]'s
  /// universe: if [superName]'s universe also contains `e`, posts
  /// `sub.in.e <= super.in.e`; otherwise (e is in sub's universe
  /// only) posts `sub.in.e = 0`, since the super-set cannot contain
  /// elements outside its own universe.
  void addSubset(String subName, String superName, {String? label}) {
    final sub = _requireSetVar('addSubset', subName);
    final sup = _requireSetVar('addSubset', superName);
    for (final element in sub.universe) {
      final subInd = sub.indicator[element]!;
      final supInd = sup.indicator[element];
      if (supInd == null) {
        addConstraint(
            <String>[subInd], (Map<String, dynamic> a) => a[subInd] == 0,
            label: label);
        continue;
      }
      addConstraint(<String>[
        subInd,
        supInd
      ], (dynamic s, dynamic t) => (s as int) <= (t as int), label: label);
    }
  }

  /// `a == b`. The two universes must be set-equal (same elements,
  /// in any order). Posts `a.in.e == b.in.e` for every element.
  void addSetEquals(String a, String b, {String? label}) {
    final aSet = _requireSetVar('addSetEquals', a);
    final bSet = _requireSetVar('addSetEquals', b);
    _requireSameUniverse('addSetEquals', a, b, aSet, bSet);
    for (final element in aSet.universe) {
      final ai = aSet.indicator[element]!;
      final bi = bSet.indicator[element]!;
      addConstraint(<String>[ai, bi], (dynamic x, dynamic y) => x == y,
          label: label);
    }
  }

  /// `a ∩ b == ∅`. Posts `a.in.e + b.in.e <= 1` for every element
  /// in the intersection of the two universes. Elements present in
  /// only one universe are trivially non-conflicting and produce no
  /// constraint, so the two sets need not share a universe.
  void addSetDisjoint(String a, String b, {String? label}) {
    final aSet = _requireSetVar('addSetDisjoint', a);
    final bSet = _requireSetVar('addSetDisjoint', b);
    for (final element in aSet.universe) {
      final bi = bSet.indicator[element];
      if (bi == null) continue;
      final ai = aSet.indicator[element]!;
      addConstraint(<String>[ai, bi],
          (dynamic x, dynamic y) => !((x as int) == 1 && (y as int) == 1),
          label: label);
    }
  }

  /// `result == a ∪ b`. All three set variables must share the same
  /// universe (as a set). Posts a per-element ternary constraint
  /// `result.in.e == (a.in.e ∨ b.in.e)`.
  void addSetUnion(String a, String b, String result, {String? label}) {
    _postTernarySet('addSetUnion', a, b, result, _unionBit, label: label);
  }

  /// `result == a ∩ b`. All three set variables must share the same
  /// universe (as a set). Posts a per-element ternary constraint
  /// `result.in.e == (a.in.e ∧ b.in.e)`.
  void addSetIntersection(String a, String b, String result, {String? label}) {
    _postTernarySet('addSetIntersection', a, b, result, _intersectBit,
        label: label);
  }

  /// `result == a \ b`. All three set variables must share the same
  /// universe (as a set). Posts a per-element ternary constraint
  /// `result.in.e == (a.in.e ∧ ¬b.in.e)`.
  void addSetDifference(String a, String b, String result, {String? label}) {
    _postTernarySet('addSetDifference', a, b, result, _differenceBit,
        label: label);
  }

  // --- Private helpers ---

  static int _unionBit(int x, int y) => (x == 1 || y == 1) ? 1 : 0;
  static int _intersectBit(int x, int y) => (x == 1 && y == 1) ? 1 : 0;
  static int _differenceBit(int x, int y) => (x == 1 && y == 0) ? 1 : 0;

  void _postTernarySet(
    String op,
    String a,
    String b,
    String result,
    int Function(int x, int y) combine, {
    String? label,
  }) {
    final aSet = _requireSetVar(op, a);
    final bSet = _requireSetVar(op, b);
    final rSet = _requireSetVar(op, result);
    _requireSameUniverse(op, a, b, aSet, bSet);
    _requireSameUniverse(op, a, result, aSet, rSet);
    for (final element in rSet.universe) {
      final ai = aSet.indicator[element]!;
      final bi = bSet.indicator[element]!;
      final ri = rSet.indicator[element]!;
      addConstraint(
          <String>[ai, bi, ri],
          (Map<String, dynamic> m) =>
              (m[ri] as int) == combine(m[ai] as int, m[bi] as int),
          label: label);
    }
  }

  ({List<dynamic> universe, Map<dynamic, String> indicator}) _requireSetVar(
      String op, String name) {
    final entry = _setVarUniverses[name];
    if (entry == null) {
      throw ArgumentError("$op: set variable '$name' has not been added yet.");
    }
    return entry;
  }

  void _requireSameUniverse(
    String op,
    String aName,
    String bName,
    ({List<dynamic> universe, Map<dynamic, String> indicator}) a,
    ({List<dynamic> universe, Map<dynamic, String> indicator}) b,
  ) {
    if (a.indicator.length != b.indicator.length) {
      throw ArgumentError(
          "$op: set variables '$aName' and '$bName' have different-sized "
          'universes (${a.indicator.length} vs ${b.indicator.length}).');
    }
    for (final k in a.indicator.keys) {
      if (!b.indicator.containsKey(k)) {
        throw ArgumentError(
            "$op: element '$k' is in '$aName''s universe but not in '$bName''s.");
      }
    }
  }
}

/// Conflict-explanation API: identifies a minimal subset of the
/// posted constraints whose conjunction is still infeasible.
///
/// When [Problem.getSolution] returns the literal `'FAILURE'`, the
/// model has no solution but the failure carries no information about
/// *which* constraints conflict. For non-trivial models that's a
/// debugging nightmare. A minimal unsatisfiable subset (MUS) is a
/// classical way to surface the conflict: a subset of the posted
/// constraints that's still infeasible, and from which the removal of
/// any single constraint makes the residual problem satisfiable.
///
/// See `doc/conflict-explanation.md` for a worked example and the
/// algorithmic background.
extension ConflictExplanation on Problem {
  /// Returns a minimal unsatisfiable subset (MUS) of the currently
  /// posted constraints, or `null` if the problem is satisfiable.
  ///
  /// **Algorithm.** Deletion-based MUS (Bakker et al. 1993, Junker
  /// 2001): for each posted constraint c in posting order, tentatively
  /// remove c from the kept set and re-solve. If the residual problem
  /// is still infeasible, drop c permanently; otherwise restore c.
  /// The remaining kept set is minimal in the sense that removing any
  /// one of its constraints makes the residual problem satisfiable.
  /// It is **not** guaranteed to be the smallest unsatisfiable subset
  /// (that's NP-hard in general); rather, it is a *locally minimal*
  /// one — sometimes called a "minimal correction subset of the
  /// negation" in the literature.
  ///
  /// **Complexity.** O(n) calls to [CSP.solve] where n is the number
  /// of user-posted constraints (binary pairs counted once). Each
  /// solve runs ordinary AC-3 search from scratch — no warm-start
  /// across iterations. On models with hundreds of constraints, where
  /// each solve takes seconds, the total runtime can be measured in
  /// minutes; pass [cancelToken] to bound the work.
  ///
  /// **Return value.**
  /// - `null` if the problem has at least one solution (no
  ///   explanation needed). Callers should branch on this case before
  ///   inspecting the returned list.
  /// - A `List<ConstraintRef>` otherwise. Forward + reverse directions
  ///   of a single user-level binary `addConstraint` call share one
  ///   ref. Refs appear in posting order (binary first, then n-ary).
  ///
  /// **Cancellation.**
  /// - If the token cancels during the initial satisfiability check
  ///   (step 1), this method returns `null`. Callers should test
  ///   `cancelToken.isCancelled` to distinguish a cancelled run from
  ///   a satisfiable problem.
  /// - If the token cancels during the deletion loop (step 2), this
  ///   method returns the current kept set. The set is still
  ///   unsatisfiable (every removed constraint was dropped because
  ///   the residual remained unsat) but may not be minimal — some
  ///   constraints that would have been removed by later iterations
  ///   stay in the result.
  ///
  /// **Granularity.** Constraints surface at the granularity at which
  /// they were posted. Helpers that decompose into multiple primitives
  /// (e.g. [addInverse] posts n² binary constraints, [addLexChain]
  /// posts k-1 lex-leq constraints, set variables decompose into per-
  /// element indicator constraints) show up as the decomposed pieces.
  /// The kind label on each [ConstraintRef] reflects the actual
  /// stored constraint, not the user-facing API call.
  ///
  /// Pass [consistency] to control propagation strength during the
  /// internal solves. Stronger consistency makes each solve more
  /// expensive but can detect unsatisfiability faster on some models.
  ///
  /// ### Example
  ///
  /// ```dart
  /// final p = Problem();
  /// p.addVariables(['a', 'b', 'c'], [1, 2]);
  /// p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
  /// p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
  /// p.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
  /// final mus = await p.findMinimalUnsatisfiableSubset();
  /// // 3-coloring with 2 colors is infeasible; all 3 edges are in
  /// // the MUS — dropping any one would make a 2-coloring possible.
  /// print(mus); // [binary(a, b), binary(b, c), binary(a, c)]
  /// ```
  Future<List<ConstraintRef>?> findMinimalUnsatisfiableSubset({
    CancellationToken? cancelToken,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  }) async {
    final binPairCount = _constraints.length ~/ 2;
    final naryCount = _naryConstraints.length;

    final entries = <({ConstraintRef ref, int idx, bool isBin})>[
      for (var i = 0; i < binPairCount; i++)
        (
          ref: ConstraintRef(
            id: 'b$i',
            kind: 'binary',
            variables: List.unmodifiable(
                [_constraints[i * 2].head, _constraints[i * 2].tail]),
            label: _constraints[i * 2].label,
          ),
          idx: i,
          isBin: true,
        ),
      for (var j = 0; j < naryCount; j++)
        (
          ref: ConstraintRef(
            id: 'n$j',
            kind: _kindOfNary(_naryConstraints[j]),
            variables: List.unmodifiable(_naryConstraints[j].vars),
            label: _naryConstraints[j].label,
          ),
          idx: j,
          isBin: false,
        ),
    ];

    Future<bool> isUnsat(Set<int> keepBin, Set<int> keepNary) async {
      final csp = _explanationSubsetCsp(keepBin, keepNary);
      final r = await CSP.solve(csp,
          consistency: consistency, cancelToken: cancelToken);
      return r == 'FAILURE';
    }

    final allBin = <int>{for (var i = 0; i < binPairCount; i++) i};
    final allNary = <int>{for (var j = 0; j < naryCount; j++) j};

    // Step 1: confirm the full problem is infeasible.
    if (!await isUnsat(allBin, allNary)) return null;
    if (cancelToken?.isCancelled ?? false) return null;

    // Step 2: deletion-based MUS over user-level constraints.
    final keepBin = Set<int>.of(allBin);
    final keepNary = Set<int>.of(allNary);
    for (final entry in entries) {
      if (cancelToken?.isCancelled ?? false) break;
      if (entry.isBin) {
        keepBin.remove(entry.idx);
      } else {
        keepNary.remove(entry.idx);
      }
      if (!await isUnsat(keepBin, keepNary)) {
        if (entry.isBin) {
          keepBin.add(entry.idx);
        } else {
          keepNary.add(entry.idx);
        }
      }
    }

    return [
      for (final entry in entries)
        if (entry.isBin
            ? keepBin.contains(entry.idx)
            : keepNary.contains(entry.idx))
          entry.ref,
    ];
  }

  /// Returns a minimal unsatisfiable subset (MUS) of the currently
  /// posted constraints, or `null` if the problem is satisfiable.
  ///
  /// **Algorithm.** QuickXplain (Junker 2004 — "QuickXPlain: Preferred
  /// Explanations and Relaxations for Over-Constrained Problems",
  /// AAAI 2004). Divide-and-conquer: split the candidate set in half,
  /// recurse on each half against a growing background of "already
  /// known to be in the MUS" constraints, short-circuiting whenever
  /// the background alone is unsat. Identifies the same kind of
  /// locally-minimal subset as [findMinimalUnsatisfiableSubset] — every
  /// constraint in the returned list is load-bearing in the sense
  /// that removing it makes the residual problem satisfiable — but
  /// uses fewer solver calls on models where the MUS is small relative
  /// to the total constraint count.
  ///
  /// **Complexity.** O(k · log(n / k)) calls to [CSP.solve] where n
  /// is the number of user-posted constraints and k is the MUS size.
  /// For small k and large n this is dramatically less than the
  /// deletion-based pass's O(n). For k ≈ n (most posted constraints
  /// participate in the conflict) the two costs are comparable; on
  /// very small models the deletion pass may even be marginally
  /// cheaper because it has no recursion overhead.
  ///
  /// **Return value, granularity, and `ConstraintRef` semantics.**
  /// Identical to [findMinimalUnsatisfiableSubset]. The returned list
  /// is sorted in posting order (binary refs first, then n-ary).
  ///
  /// **Cancellation.** If the token cancels at any point — during the
  /// initial satisfiability check or anywhere in the divide-and-
  /// conquer recursion — this method returns `null`. Unlike the
  /// deletion-based pass, the QuickXplain recursion does not maintain
  /// a "current kept set" that would be sound mid-flight; partial
  /// progress is not surfacable. Callers should test
  /// `cancelToken.isCancelled` to distinguish a cancelled run from
  /// a satisfiable problem.
  ///
  /// Pass [consistency] to control propagation strength during the
  /// internal solves.
  ///
  /// ### Example
  ///
  /// ```dart
  /// final p = Problem();
  /// p.addVariables(['a', 'b', 'c'], [1, 2]);
  /// p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
  /// p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
  /// p.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
  /// final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
  /// print(mus); // [binary(a, b), binary(b, c), binary(a, c)]
  /// ```
  Future<List<ConstraintRef>?> findMinimalUnsatisfiableSubsetQuickXplain({
    CancellationToken? cancelToken,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  }) async {
    final binPairCount = _constraints.length ~/ 2;
    final naryCount = _naryConstraints.length;

    final entries = <({ConstraintRef ref, int idx, bool isBin})>[
      for (var i = 0; i < binPairCount; i++)
        (
          ref: ConstraintRef(
            id: 'b$i',
            kind: 'binary',
            variables: List.unmodifiable(
                [_constraints[i * 2].head, _constraints[i * 2].tail]),
            label: _constraints[i * 2].label,
          ),
          idx: i,
          isBin: true,
        ),
      for (var j = 0; j < naryCount; j++)
        (
          ref: ConstraintRef(
            id: 'n$j',
            kind: _kindOfNary(_naryConstraints[j]),
            variables: List.unmodifiable(_naryConstraints[j].vars),
            label: _naryConstraints[j].label,
          ),
          idx: j,
          isBin: false,
        ),
    ];

    Future<bool> isUnsat(
        List<({ConstraintRef ref, int idx, bool isBin})> subset) async {
      final keepBin = <int>{};
      final keepNary = <int>{};
      for (final e in subset) {
        if (e.isBin) {
          keepBin.add(e.idx);
        } else {
          keepNary.add(e.idx);
        }
      }
      final csp = _explanationSubsetCsp(keepBin, keepNary);
      final r = await CSP.solve(csp,
          consistency: consistency, cancelToken: cancelToken);
      return r == 'FAILURE';
    }

    // Step 1: confirm the full problem is infeasible.
    if (!await isUnsat(entries)) return null;
    if (cancelToken?.isCancelled ?? false) return null;

    // Degenerate case: unsat with no posted constraints (e.g. an empty
    // domain). The MUS is the empty set — no constraint is load-bearing
    // for the failure.
    if (entries.isEmpty) return const <ConstraintRef>[];

    // Step 2: QuickXplain (Junker 2004).
    //
    // qx(background, delta, candidates) returns a subset of `candidates`
    // such that background ∪ subset is unsat and each element of subset
    // is load-bearing for that conclusion. `delta` is the most recent
    // addition to `background`; when non-empty it lets the recursion
    // short-circuit if `background` is already unsat (the constraints
    // added in `delta` aren't needed).
    //
    // Returns null if cancellation fired during the recursion.
    Future<List<({ConstraintRef ref, int idx, bool isBin})>?> qx(
      List<({ConstraintRef ref, int idx, bool isBin})> background,
      List<({ConstraintRef ref, int idx, bool isBin})> delta,
      List<({ConstraintRef ref, int idx, bool isBin})> candidates,
    ) async {
      if (cancelToken?.isCancelled ?? false) return null;
      if (delta.isNotEmpty && await isUnsat(background)) {
        return const [];
      }
      if (cancelToken?.isCancelled ?? false) return null;
      if (candidates.length == 1) return List.of(candidates);
      final k = candidates.length ~/ 2;
      final c1 = candidates.sublist(0, k);
      final c2 = candidates.sublist(k);
      final d2 = await qx([...background, ...c1], c1, c2);
      if (d2 == null) return null;
      final d1 = await qx([...background, ...d2], d2, c1);
      if (d1 == null) return null;
      return [...d1, ...d2];
    }

    final mus = await qx(const [], const [], entries);
    if (mus == null) return null;
    return [for (final e in mus) e.ref];
  }

  CspProblem _explanationSubsetCsp(Set<int> keepBin, Set<int> keepNary) {
    final bin = <BinaryConstraint>[];
    for (final i in keepBin) {
      bin.add(_constraints[i * 2]);
      bin.add(_constraints[i * 2 + 1]);
    }
    final nary = <NaryConstraint>[
      for (final j in keepNary) _naryConstraints[j],
    ];
    return CspProblem(
      variables: _variables,
      constraints: bin,
      naryConstraints: nary,
    );
  }

  String _kindOfNary(NaryConstraint c) {
    if (c.allDifferent) return 'allDifferent';
    final ls = c.linearSpec;
    if (ls != null) {
      switch (ls.op) {
        case LinearOp.eq:
          return 'linearEquals';
        case LinearOp.leq:
          return 'linearLeq';
        case LinearOp.geq:
          return 'linearGeq';
      }
    }
    if (c.regularDfa != null) return 'regular';
    if (c.circuit) return 'circuit';
    if (c.subcircuit) return 'subcircuit';
    if (c.gccSpec != null) return 'gcc';
    if (c.cumulativeSpec != null) return 'cumulative';
    if (c.clauseSpec != null) return 'clause';
    if (c.diffNSpec != null) return 'diffN';
    return 'predicate';
  }
}

/// Persistent, assumption-driven solving over an immutable finite-domain model.
part of 'solver.dart';

/// A complete outcome or an explicit reason the query did not complete.
enum CspSolveStatus {
  satisfied,
  infeasible,
  cancelled,
  timeLimit,
  decisionLimit,
  invalidCandidate,
}

/// One query result. Counters and assignments are detached from session state.
class CspSolveResult {
  CspSolveResult({
    required this.status,
    required SolverStats stats,
    required this.reusedRoot,
    Map<String, dynamic>? solution,
    this.diagnostic,
  })  : stats = stats.snapshot(),
        solution = solution == null ? null : Map.unmodifiable(solution);

  final CspSolveStatus status;
  final Map<String, dynamic>? solution;
  final SolverStats stats;
  final bool reusedRoot;
  final String? diagnostic;

  bool get isSatisfied => status == CspSolveStatus.satisfied;
}

/// A retractable equality or inclusive numeric bound assumption.
class CspAssumption {
  const CspAssumption.equals(this.variable, this.value)
      : lower = null,
        upper = null,
        _isEquality = true;

  const CspAssumption.bounds(this.variable, {this.lower, this.upper})
      : value = null,
        _isEquality = false;

  final String variable;
  final dynamic value;
  final num? lower;
  final num? upper;
  final bool _isEquality;
}

/// A structural snapshot with stable IDs and precomputed constraint adjacency.
///
/// Sessions use plain finite-domain search; learned clauses are not shared or
/// retained under assumptions. Recompile after editing the source model.
/// Generic predicate closures and domain objects must remain immutable/pure.
class CompiledCspModel {
  factory CompiledCspModel(CspProblem source,
      {Map<String, dynamic> Function(Map<String, dynamic>)?
          transformSolution}) {
    if (source.floatVariables.isNotEmpty) {
      throw UnsupportedError('Compiled CSP sessions currently support finite '
          'domains only. Continuous candidates require residual validation.');
    }
    final variables = <String, List<dynamic>>{
      for (final entry in source.variables.entries)
        entry.key: entry.value is IntRangeDomain
            ? entry.value
            : List<dynamic>.unmodifiable(entry.value),
    };
    final constraints = List<BinaryConstraint>.unmodifiable(source.constraints);
    final nary = List<NaryConstraint>.unmodifiable(
        source.naryConstraints.map(_snapshotConstraint));
    final snapshot = CspProblem(
      variables: Map.unmodifiable(variables),
      constraints: constraints,
      naryConstraints: nary,
      timeStep: 0,
    );
    _validate(snapshot);
    final names = List<String>.unmodifiable(variables.keys);
    final ids = Map<String, int>.unmodifiable({
      for (var i = 0; i < names.length; i++) names[i]: i,
    });
    final binary = <String, List<BinaryConstraint>>{};
    final adjacency = <String, List<int>>{
      for (final name in names) name: <int>[],
    };
    void register(String name, int constraintId) {
      final bucket = adjacency[name];
      if (bucket == null) {
        throw ArgumentError('Constraint references unknown variable $name.');
      }
      if (!bucket.contains(constraintId)) bucket.add(constraintId);
    }

    for (var i = 0; i < constraints.length; i++) {
      final constraint = constraints[i];
      binary.putIfAbsent(constraint.head, () => []).add(constraint);
      register(constraint.head, i);
      register(constraint.tail, i);
    }
    for (var i = 0; i < nary.length; i++) {
      final constraint = nary[i];
      if (constraint.floatProduct || constraint.floatLinearSpec != null) {
        throw UnsupportedError('Continuous constraint tags cannot be compiled '
            'by the finite-domain session.');
      }
      for (final variable in constraint.vars) {
        register(variable, constraints.length + i);
      }
    }
    snapshot.naryIndex = Map.unmodifiable({
      for (final entry in _indexNaryByVar(nary).entries)
        entry.key: List<NaryConstraint>.unmodifiable(entry.value),
    });
    return CompiledCspModel._(
      snapshot,
      names,
      ids,
      Map.unmodifiable({
        for (final entry in adjacency.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      }),
      Map.unmodifiable({
        for (final entry in binary.entries)
          entry.key: List<BinaryConstraint>.unmodifiable(entry.value),
      }),
      transformSolution,
    );
  }

  CompiledCspModel._(this._problem, this.variableNames, this.variableIds,
      this.constraintIdsByVariable, this._binaryIndex, this._transformSolution);

  final CspProblem _problem;
  final Map<String, List<BinaryConstraint>> _binaryIndex;
  final Map<String, dynamic> Function(Map<String, dynamic>)? _transformSolution;
  final List<String> variableNames;
  final Map<String, int> variableIds;
  final Map<String, List<int>> constraintIdsByVariable;

  int get constraintCount =>
      _problem.constraints.length + _problem.naryConstraints.length;

  CspSolveSession createSession(
          {ConsistencyLevel consistency = ConsistencyLevel.arcConsistency}) =>
      CspSolveSession._(this, consistency);

  static NaryConstraint _snapshotConstraint(NaryConstraint source) {
    LinearSpec? linear(LinearSpec? spec) => spec == null
        ? null
        : LinearSpec(
            coeffs: List<num>.unmodifiable(spec.coeffs),
            op: spec.op,
            bound: spec.bound);
    final dfa = source.regularDfa;
    final cumulative = source.cumulativeSpec;
    final clause = source.clauseSpec;
    final diffN = source.diffNSpec;
    return NaryConstraint(
      vars: List<String>.unmodifiable(source.vars),
      predicate: source.predicate,
      allDifferent: source.allDifferent,
      linearSpec: linear(source.linearSpec),
      floatLinearSpec: linear(source.floatLinearSpec),
      floatProduct: source.floatProduct,
      regularDfa: dfa == null
          ? null
          : Dfa(
              numStates: dfa.numStates,
              start: dfa.start,
              accepting: Set<int>.unmodifiable(dfa.accepting),
              transitions: Map.unmodifiable({
                for (final entry in dfa.transitions.entries)
                  entry.key: Map<dynamic, int>.unmodifiable(entry.value),
              })),
      circuit: source.circuit,
      subcircuit: source.subcircuit,
      gccSpec: source.gccSpec == null
          ? null
          : GccSpec(bounds: Map.unmodifiable(source.gccSpec!.bounds)),
      cumulativeSpec: cumulative == null
          ? null
          : CumulativeSpec(
              durations: List<int>.unmodifiable(cumulative.durations),
              demands: List<int>.unmodifiable(cumulative.demands),
              capacity: cumulative.capacity,
              useEnergeticReasoning: cumulative.useEnergeticReasoning),
      clauseSpec: clause == null
          ? null
          : ClauseSpec(
              literals: List.unmodifiable(clause.literals),
              atoms: clause.atoms == null
                  ? null
                  : List<Atom>.unmodifiable(clause.atoms!)),
      diffNSpec: diffN == null
          ? null
          : DiffNSpec(
              widths: List<int>.unmodifiable(diffN.widths),
              heights: List<int>.unmodifiable(diffN.heights)),
      label: source.label,
    );
  }

  String? _validateSolution(Map<String, dynamic> solution) {
    for (final entry in _problem.variables.entries) {
      if (!solution.containsKey(entry.key) ||
          !entry.value.contains(solution[entry.key])) {
        return 'Candidate is outside the declared domain of ${entry.key}.';
      }
    }
    for (var i = 0; i < _problem.constraints.length; i++) {
      final constraint = _problem.constraints[i];
      if (!constraint.predicate(
          solution[constraint.head], solution[constraint.tail])) {
        return 'Binary constraint $i rejected the candidate.';
      }
    }
    for (var i = 0; i < _problem.naryConstraints.length; i++) {
      final constraint = _problem.naryConstraints[i];
      if (!_satisfiesCompiledConstraint(constraint, solution)) {
        return '${constraint.coarseKind} constraint $i rejected the candidate.';
      }
    }
    return null;
  }
}

/// A reusable finite-domain engine with reversible assumptions and root reuse.
///
/// One session permits one query at a time. Make independent sessions from the
/// same compiled model for concurrent callers. Bounds/equalities never mutate
/// the compiled model, and every query restores the prepared root in `finally`.
/// Deadlines are checked between propagator calls and search steps; an individual
/// user predicate or global propagator is not preemptible.
class CspSolveSession {
  CspSolveSession._(this.model, ConsistencyLevel consistency)
      : _engine = _BacktrackEngine(model._problem,
            consistency: consistency, binaryIndex: model._binaryIndex);

  final CompiledCspModel model;
  final _BacktrackEngine _engine;
  final List<List<CspAssumption>> _scopes = [<CspAssumption>[]];
  bool _busy = false;
  bool _closed = false;
  bool _rootReady = false;
  bool _rootFeasible = true;
  int _rootMark = 0;
  int _rootPreparationCount = 0;

  int get depth => _scopes.length - 1;
  int get rootPreparationCount => _rootPreparationCount;
  bool get isClosed => _closed;

  void _requireIdle() {
    if (_closed) throw StateError('This CSP session is closed.');
    if (_busy) throw StateError('A solve is already active in this session.');
  }

  void _validateAssumption(CspAssumption assumption) {
    if (!model.variableIds.containsKey(assumption.variable)) {
      throw ArgumentError('Unknown variable ${assumption.variable}.');
    }
    if (!assumption._isEquality &&
        ((assumption.lower?.isNaN ?? false) ||
            (assumption.upper?.isNaN ?? false))) {
      throw ArgumentError('Assumption bounds must not be NaN.');
    }
  }

  void push() {
    _requireIdle();
    _scopes.add(<CspAssumption>[]);
  }

  void pop() {
    _requireIdle();
    if (_scopes.length == 1) throw StateError('Cannot pop the root scope.');
    _scopes.removeLast();
  }

  void clearAssumptions() {
    _requireIdle();
    _scopes
      ..clear()
      ..add(<CspAssumption>[]);
  }

  void assumeEquals(String variable, dynamic value) {
    _requireIdle();
    final assumption = CspAssumption.equals(variable, value);
    _validateAssumption(assumption);
    _scopes.last.add(assumption);
  }

  void assumeBounds(String variable, {num? lower, num? upper}) {
    _requireIdle();
    final assumption =
        CspAssumption.bounds(variable, lower: lower, upper: upper);
    _validateAssumption(assumption);
    _scopes.last.add(assumption);
  }

  Future<CspSolveResult> solve({
    Iterable<CspAssumption> assumptions = const [],
    CancellationToken? cancelToken,
    Duration? timeLimit,
    int? maxDecisions,
  }) async {
    _requireIdle();
    if (timeLimit != null && timeLimit.isNegative) {
      throw ArgumentError.value(timeLimit, 'timeLimit', 'must be nonnegative');
    }
    if (maxDecisions != null && maxDecisions < 0) {
      throw ArgumentError.value(maxDecisions, 'maxDecisions', 'must be >= 0');
    }
    final active = [
      for (final scope in _scopes) ...scope,
      ...assumptions,
    ];
    for (final assumption in active) {
      _validateAssumption(assumption);
    }
    _busy = true;
    final reusedRoot = _rootReady;
    final watch = Stopwatch()..start();
    CspSolveStatus? interruption;
    bool stopRequested() {
      if (cancelToken?.isCancelled ?? false) {
        interruption = CspSolveStatus.cancelled;
      } else if (timeLimit != null && watch.elapsed >= timeLimit) {
        interruption = CspSolveStatus.timeLimit;
      }
      return interruption != null;
    }

    CspSolveResult result(CspSolveStatus status,
        {Map<String, dynamic>? solution, String? diagnostic}) {
      _engine.stats.elapsedMicros = watch.elapsedMicroseconds;
      return CspSolveResult(
        status: status,
        stats: _engine.stats,
        reusedRoot: reusedRoot,
        solution: solution,
        diagnostic: diagnostic,
      );
    }

    _engine
      ..stats = SolverStats()
      .._aborted = false
      .._candidateValidation = null
      .._backtrackCount = 0
      .._decisionsAtLastYield = 0
      .._queryStopRequested = stopRequested
      .._queryDecisionLimit = maxDecisions;
    try {
      if (stopRequested()) return result(interruption!);
      if (!_rootReady) {
        _rootPreparationCount++;
        final feasible = _engine._seedAndPreprocess();
        if (_engine.wasAborted || stopRequested()) {
          return result(interruption ?? CspSolveStatus.cancelled);
        }
        _rootReady = true;
        _rootFeasible = feasible;
        _rootMark = feasible ? _engine._trailMark() : 0;
      }
      if (!_rootFeasible) return result(CspSolveStatus.infeasible);

      final changed = <String>{};
      for (final assumption in active) {
        if (stopRequested()) return result(interruption!);
        final name = assumption.variable;
        final domain = _engine._domains[name]!;
        if (assumption._isEquality) {
          final declared = model._problem.variables[name]!;
          final index = declared.indexOf(assumption.value);
          if (index < 0) {
            return result(CspSolveStatus.infeasible);
          }
          // Preserve the declared value object/type (e.g. 1 == 1.0) rather
          // than introducing a foreign value into a bitset/list snapshot.
          final value = declared[index];
          if (!domain.contains(value)) return result(CspSolveStatus.infeasible);
          if (domain.length != 1) {
            _engine._setDomain(name, [value]);
            changed.add(name);
          }
        } else {
          if (_numericBoundsOf(domain) == null) {
            throw ArgumentError(
                'Numeric bounds require a numeric domain: $name');
          }
          final next = _intersectNumericBounds(
              domain,
              assumption.lower ?? double.negativeInfinity,
              assumption.upper ?? double.infinity);
          if (next.isEmpty) return result(CspSolveStatus.infeasible);
          if (next.length != domain.length) {
            _engine._setDomainRep(name, next);
            changed.add(name);
          }
        }
      }
      if (changed.isNotEmpty && !_engine._propagate(changed)) {
        return result(interruption ?? CspSolveStatus.infeasible);
      }
      final solution = await _engine._searchOne();
      if (stopRequested()) return result(interruption!);
      if (_engine.wasAborted) {
        if (_engine._candidateValidation?.accepted == false) {
          return result(CspSolveStatus.invalidCandidate,
              diagnostic: _engine._candidateValidation!.message);
        }
        return result(CspSolveStatus.decisionLimit);
      }
      if (solution == null) return result(CspSolveStatus.infeasible);
      final error = model._validateSolution(solution);
      if (error != null) {
        return result(CspSolveStatus.invalidCandidate, diagnostic: error);
      }
      if (stopRequested()) return result(interruption!);
      return result(CspSolveStatus.satisfied,
          solution: model._transformSolution?.call(solution) ?? solution);
    } finally {
      _engine._trailRollback(_rootReady && _rootFeasible ? _rootMark : 0);
      _engine
        .._queryStopRequested = null
        .._queryDecisionLimit = null;
      _busy = false;
      watch.stop();
    }
  }

  void close() {
    _requireIdle();
    _closed = true;
    _scopes.clear();
    _engine._domains.clear();
    _engine._binarySupports.clear();
    _engine._trail.clear();
    _engine._clauseWatchers.clear();
    _engine._clauseWatchIndex.clear();
    _engine._learnedClauseIdentities.clear();
    _engine._usedLearnedClauses.clear();
    _engine._allDifferentPropagators.clear();
    _engine._gccPropagators.clear();
    _engine._binaryQueue.clear();
    _engine._naryQueue.clear();
    _engine._queuedBinary.clear();
    _engine._queuedNary.clear();
  }
}

/// Evaluate tagged semantics directly: some internal predicates are placeholders
/// or capture mutable builder collections, so tags cannot rely on that fallback.
bool _satisfiesCompiledConstraint(
    NaryConstraint constraint, Map<String, dynamic> assignment) {
  final values = [for (final variable in constraint.vars) assignment[variable]];
  if (constraint.allDifferent) return values.toSet().length == values.length;
  final linear = constraint.linearSpec;
  if (linear != null) {
    num sum = 0;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value is! num || !value.isFinite) return false;
      sum += linear.coeffs[i] * value;
    }
    if (!sum.isFinite) return false;
    return switch (linear.op) {
      LinearOp.eq => sum == linear.bound,
      LinearOp.leq => sum <= linear.bound,
      LinearOp.geq => sum >= linear.bound,
    };
  }
  final dfa = constraint.regularDfa;
  if (dfa != null) {
    var state = dfa.start;
    for (final value in values) {
      final next = dfa.step(state, value);
      if (next == null) return false;
      state = next;
    }
    return dfa.accepting.contains(state);
  }
  if (constraint.circuit || constraint.subcircuit) {
    final n = values.length;
    if (values.any((value) => value is! int || value < 0 || value >= n)) {
      return false;
    }
    if (values.toSet().length != n) return false;
    final active = <int>{
      for (var i = 0; i < n; i++)
        if (!constraint.subcircuit || values[i] != i) i,
    };
    if (active.isEmpty) return constraint.subcircuit;
    final start = active.first;
    final visited = <int>{};
    var current = start;
    while (visited.add(current)) {
      if (!active.contains(current)) return false;
      current = values[current] as int;
    }
    return current == start && visited.length == active.length;
  }
  final gcc = constraint.gccSpec;
  if (gcc != null) {
    final counts = <dynamic, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    for (final entry in gcc.bounds.entries) {
      final count = counts[entry.key] ?? 0;
      if (count < entry.value.min || count > entry.value.max) return false;
    }
    return true;
  }
  final cumulative = constraint.cumulativeSpec;
  if (cumulative != null) {
    final events = <int, int>{};
    for (var i = 0; i < values.length; i++) {
      final duration = cumulative.durations[i];
      final demand = cumulative.demands[i];
      if (duration == 0 || demand == 0) continue;
      final start = values[i];
      if (start is! int) return false;
      events[start] = (events[start] ?? 0) + demand;
      final end = start + duration;
      events[end] = (events[end] ?? 0) - demand;
    }
    var load = 0;
    final times = events.keys.toList()..sort();
    for (final time in times) {
      load += events[time]!;
      if (load > cumulative.capacity) return false;
    }
    return true;
  }
  final clause = constraint.clauseSpec;
  if (clause != null) {
    if (clause.atoms != null) {
      return clause.atoms!.any((atom) {
        final value = assignment[atom.varName];
        if (value is! int) return false;
        return switch (atom) {
          AtomEq() => value == atom.value,
          AtomNe() => value != atom.value,
          AtomLe() => value <= atom.value,
          AtomGe() => value >= atom.value,
          AtomInScc() => throw UnsupportedError(
              'Synthetic explanation atoms cannot be model constraints.'),
        };
      });
    }
    return clause.literals.any(
        (literal) => assignment[literal.varName] == (literal.positive ? 1 : 0));
  }
  final diffN = constraint.diffNSpec;
  if (diffN != null) {
    final n = diffN.widths.length;
    if (values.any((value) => value is! int)) return false;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (diffN.widths[i] == 0 ||
            diffN.heights[i] == 0 ||
            diffN.widths[j] == 0 ||
            diffN.heights[j] == 0) {
          continue;
        }
        final xi = values[i] as int, xj = values[j] as int;
        final yi = values[n + i] as int, yj = values[n + j] as int;
        if (!(xi + diffN.widths[i] <= xj ||
            xj + diffN.widths[j] <= xi ||
            yi + diffN.heights[i] <= yj ||
            yj + diffN.heights[j] <= yi)) {
          return false;
        }
      }
    }
    return true;
  }
  if (constraint.floatProduct || constraint.floatLinearSpec != null) {
    throw UnsupportedError('Continuous tags require a residual validator.');
  }
  return constraint.predicate(assignment);
}

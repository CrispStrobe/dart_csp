/// Reverse watched-variable scheduling and expansion repair for clauses.
part of 'solver.dart';

class _ClauseWatchIndex {
  _ClauseWatchIndex(this.states);
  final Map<ClauseSpec, _ClauseWatchState> states;
  final Map<ClauseSpec, List<NaryConstraint>> _owners =
      HashMap(equals: identical, hashCode: identityHashCode);
  final Map<ClauseSpec, List<String>> _watched =
      HashMap(equals: identical, hashCode: identityHashCode);
  final Map<ClauseSpec, (int, int)> _positions =
      HashMap(equals: identical, hashCode: identityHashCode);
  // Keep the original adjacency order when a watch moves away and returns.
  // This avoids changing conflict selection and VSIDS/restart behavior just
  // because reverse subscriptions replaced the old static-adjacency scan.
  final Map<String, SplayTreeSet<NaryConstraint>> _byVariable = {};
  final Map<NaryConstraint, int> _order =
      HashMap(equals: identical, hashCode: identityHashCode);
  var _nextOrder = 0;
  final LinkedHashSet<NaryConstraint> pending =
      LinkedHashSet(equals: identical, hashCode: identityHashCode);

  // Normal two-watch states survive expansion. Degenerate unit states and
  // conflict states can have a non-watched literal restored by rollback;
  // index only those fragile scopes for targeted reinitialization.
  final Map<String, Set<ClauseSpec>> _repairByVariable = {};
  final Map<ClauseSpec, Set<String>> _repairScope =
      HashMap(equals: identical, hashCode: identityHashCode);

  Iterable<NaryConstraint> watching(String variable) =>
      _byVariable[variable] ?? const <NaryConstraint>[];

  SplayTreeSet<NaryConstraint> _newBucket() =>
      SplayTreeSet((a, b) => _order[a]!.compareTo(_order[b]!));

  void register(NaryConstraint constraint) {
    final spec = constraint.clauseSpec!;
    final owners = _owners.putIfAbsent(spec, () => <NaryConstraint>[]);
    if (owners.any((c) => identical(c, constraint))) return;
    owners.add(constraint);
    _order[constraint] = _nextOrder++;
    pending.add(constraint);
    // An uninitialized clause subscribes to its whole scope until the first
    // propagation establishes two watches. This preserves initialization's
    // seed-variable order without scanning static adjacency on later events.
    final subscribed = _watched.putIfAbsent(
        spec, () => constraint.vars.toSet().toList(growable: false));
    // A ClauseSpec can be shared by multiple constraint instances.
    for (final variable in subscribed) {
      _byVariable.putIfAbsent(variable, _newBucket).add(constraint);
    }
  }

  String _variable(ClauseSpec spec, int position) => spec.atoms == null
      ? spec.literals[position].varName
      : spec.atoms![position].varName;

  void synchronize(ClauseSpec spec, SolverStats stats, {required bool failed}) {
    final state = states[spec];
    final owners = _owners[spec]!;
    if (state == null) {
      // Leave unprocessed/conflicting initialization pending. A propagation
      // call can abort before the rest of its initial clause queue is visited.
      pending.addAll(owners);
      return;
    }
    final old = _watched[spec] ?? const <String>[];
    final a = _variable(spec, state.watch1), b = _variable(spec, state.watch2);
    final current = <String>[a, if (b != a) b];
    for (final variable in old) {
      if (!current.contains(variable)) {
        final bucket = _byVariable[variable]!;
        bucket.removeAll(owners);
        if (bucket.isEmpty) _byVariable.remove(variable);
      }
    }
    for (final variable in current) {
      if (!old.contains(variable)) {
        _byVariable.putIfAbsent(variable, _newBucket).addAll(owners);
      }
    }
    final previous = _positions[spec];
    if (previous != null) {
      if (previous.$1 != state.watch1) stats.clauseWatchMoves++;
      if (previous.$2 != state.watch2) stats.clauseWatchMoves++;
    }
    _watched[spec] = current;
    _positions[spec] = (state.watch1, state.watch2);
    pending.removeAll(owners);
    if (failed || state.watch1 == state.watch2) {
      if (!_repairScope.containsKey(spec)) {
        final scope = <String>{for (final owner in owners) ...owner.vars};
        _repairScope[spec] = scope;
        for (final variable in scope) {
          _repairByVariable
              .putIfAbsent(variable,
                  () => HashSet(equals: identical, hashCode: identityHashCode))
              .add(spec);
        }
      }
    } else {
      _removeRepairScope(spec);
    }
  }

  void _removeRepairScope(ClauseSpec spec) {
    final scope = _repairScope.remove(spec);
    if (scope == null) return;
    for (final variable in scope) {
      final bucket = _repairByVariable[variable]!;
      bucket.remove(spec);
      if (bucket.isEmpty) _repairByVariable.remove(variable);
    }
  }

  void onExpansion(String variable, SolverStats stats) {
    final bucket = _repairByVariable[variable];
    if (bucket == null) return;
    for (final spec in bucket.toList(growable: false)) {
      final owners = _owners[spec]!;
      for (final watched in _watched.remove(spec) ?? const <String>[]) {
        final reverse = _byVariable[watched]!;
        reverse.removeAll(owners);
        if (reverse.isEmpty) _byVariable.remove(watched);
      }
      _positions.remove(spec);
      states.remove(spec);
      _removeRepairScope(spec);
      final scope = <String>{for (final owner in owners) ...owner.vars};
      _watched[spec] = scope.toList(growable: false);
      for (final variable in scope) {
        _byVariable.putIfAbsent(variable, _newBucket).addAll(owners);
      }
      pending.addAll(owners);
      stats.clauseWatchRepairs++;
    }
  }

  void unregister(NaryConstraint constraint) {
    final spec = constraint.clauseSpec!;
    final owners = _owners[spec];
    if (owners == null) return;
    owners.removeWhere((c) => identical(c, constraint));
    pending.remove(constraint);
    for (final variable in _watched[spec] ?? const <String>[]) {
      final bucket = _byVariable[variable]!;
      bucket.remove(constraint);
      if (bucket.isEmpty) _byVariable.remove(variable);
    }
    if (owners.isEmpty) {
      _owners.remove(spec);
      _watched.remove(spec);
      _positions.remove(spec);
      states.remove(spec);
      _removeRepairScope(spec);
    }
    _order.remove(constraint);
  }

  void clear() {
    states.clear();
    _owners.clear();
    _watched.clear();
    _positions.clear();
    _byVariable.clear();
    _order.clear();
    _nextOrder = 0;
    pending.clear();
    _repairByVariable.clear();
    _repairScope.clear();
  }
}

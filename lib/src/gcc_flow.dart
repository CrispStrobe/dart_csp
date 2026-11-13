/// Compact-capacity global cardinality flow, implemented from residual paths.
part of 'solver.dart';

/// A GCC graph has one node per variable, one per distinct value, and one
/// sink. Capacities are integers on value/sink arcs, never replicated values.
///
/// The retained assignment first repairs upper-capacity feasibility and then
/// routes lower deficits along reverse alternating paths to surplus values.
/// Once feasible, an unmatched variable/value edge has support exactly when
/// it belongs to a residual cycle. SCCs therefore enforce both lower and upper
/// bounds. Backtracking only expands domains; each new contraction validates
/// the retained assignment before it can be reused.
class _GccPropagator {
  _GccPropagator(this.vars, this.spec, this.domains, this.applyUpdate,
      {this.originalDomains, this.recordScc})
      : _varAdj = List.generate(vars.length, (_) => <int>[]),
        _lastDomains = List<_DomainRep?>.filled(vars.length, null),
        _matchVar = List<int>.filled(vars.length, -1),
        _seenVar = List<bool>.filled(vars.length, false),
        _forward = List.generate(vars.length + 1, (_) => <int>[]),
        _reverse = List.generate(vars.length + 1, (_) => <int>[]);

  final List<String> vars;
  final GccSpec spec;
  final Map<String, _DomainRep> domains;
  final void Function(String varName, _DomainRep newDom,
      {ImplicationReason? reason}) applyUpdate;
  final Map<String, List<dynamic>>? originalDomains;
  final Atom Function(String repVar, List<Atom> antecedents)? recordScc;

  final Map<dynamic, int> _valueIds = <dynamic, int>{};
  final List<dynamic> _values = <dynamic>[];
  final List<int> _lower = <int>[];
  final List<int> _upper = <int>[];
  final List<List<int>> _varAdj;
  final List<List<int>> _valueAdj = <List<int>>[];
  final List<_DomainRep?> _lastDomains;
  final List<int> _matchVar;
  final List<Set<int>> _owners = <Set<int>>[];
  final List<bool> _seenVar;
  final List<bool> _seenValue = <bool>[];
  final List<int> _pathVar = <int>[];
  final List<int> _pathValue = <int>[];
  final Queue<int> _queue = Queue<int>();
  final List<List<int>> _forward;
  final List<List<int>> _reverse;
  int _totalCapacity = 0;
  bool? _integerExplanations;

  int lastFlowNodes = 0;
  int lastFlowEdges = 0;
  int lastAugmentations = 0;
  int get totalCapacity => _totalCapacity;

  bool get _lcgEnabled => originalDomains != null && recordScc != null;

  int _indexValue(dynamic value) => _valueIds.putIfAbsent(value, () {
        final index = _values.length;
        final bound = spec.bounds[value];
        final capacity = min(bound?.max ?? vars.length, vars.length);
        _values.add(value);
        _lower.add(bound?.min ?? 0);
        _upper.add(capacity);
        _totalCapacity += capacity;
        _valueAdj.add(<int>[]);
        _owners.add(<int>{});
        _seenValue.add(false);
        _pathVar.add(-1);
        _pathValue.add(-1);
        _forward.add(<int>[]);
        _reverse.add(<int>[]);
        return index;
      });

  void _assign(int variable, int value) {
    final old = _matchVar[variable];
    if (old != -1) _owners[old].remove(variable);
    _matchVar[variable] = value;
    if (value != -1) _owners[value].add(variable);
  }

  /// Find an alternating path from an unmatched variable to spare capacity.
  bool _augmentVariable(int start) {
    _seenVar.fillRange(0, _seenVar.length, false);
    _seenValue.fillRange(0, _seenValue.length, false);
    _queue
      ..clear()
      ..add(start);
    _seenVar[start] = true;
    while (_queue.isNotEmpty) {
      final variable = _queue.removeFirst();
      for (final value in _varAdj[variable]) {
        if (_seenValue[value]) continue;
        _seenValue[value] = true;
        _pathVar[value] = variable;
        if (_owners[value].length < _upper[value]) {
          var next = value;
          while (next != -1) {
            final owner = _pathVar[next];
            final previous = _matchVar[owner];
            _assign(owner, next);
            next = previous;
          }
          lastAugmentations++;
          return true;
        }
        for (final owner in _owners[value]) {
          if (!_seenVar[owner]) {
            _seenVar[owner] = true;
            _queue.add(owner);
          }
        }
      }
    }
    return false;
  }

  /// Search backwards from a deficient value until finding a donor that can
  /// lose one owner without violating its own lower bound. Flipping the path
  /// increases only the target count and decreases only the donor count.
  bool _repairLower(int target) {
    _seenValue.fillRange(0, _seenValue.length, false);
    _queue
      ..clear()
      ..add(target);
    _seenValue[target] = true;
    while (_queue.isNotEmpty) {
      final destination = _queue.removeFirst();
      for (final variable in _valueAdj[destination]) {
        final source = _matchVar[variable];
        if (source == destination || _seenValue[source]) continue;
        _seenValue[source] = true;
        _pathVar[source] = variable;
        _pathValue[source] = destination;
        if (_owners[source].length > _lower[source]) {
          var next = source;
          while (next != target) {
            final following = _pathValue[next];
            _assign(_pathVar[next], following);
            next = following;
          }
          lastAugmentations++;
          return true;
        }
        _queue.add(source);
      }
    }
    return false;
  }

  Set<String>? propagate() {
    lastFlowNodes = 0;
    lastFlowEdges = 0;
    lastAugmentations = 0;
    final n = vars.length;
    if (n == 0) return <String>{};
    for (var i = 0; i < n; i++) {
      final domain = domains[vars[i]]!;
      if (domain.isEmpty) return null;
      if (!identical(domain, _lastDomains[i])) {
        final edges = _varAdj[i]..clear();
        for (final value in domain.values) {
          edges.add(_indexValue(value));
        }
        _lastDomains[i] = domain;
        final matched = _matchVar[i];
        if (matched != -1 && !domain.contains(_values[matched])) {
          _assign(i, -1);
        }
      }
    }
    // A required value missing from every domain still needs a node so its
    // lower deficit is detected, rather than deferred until a search leaf.
    for (final value in spec.bounds.keys) {
      _indexValue(value);
    }
    final m = _values.length;
    final sink = n + m;
    lastFlowNodes = sink + 1;
    if (_totalCapacity < n) return null;
    var minimumTotal = 0;
    for (var value = 0; value < m; value++) {
      if (_lower[value] > _upper[value]) return null;
      minimumTotal += _lower[value];
      if (minimumTotal > n) return null;
      _valueAdj[value].clear();
    }
    for (var variable = 0; variable < n; variable++) {
      for (final value in _varAdj[variable]) {
        _valueAdj[value].add(variable);
      }
    }
    for (var variable = 0; variable < n; variable++) {
      if (_matchVar[variable] == -1 && !_augmentVariable(variable)) return null;
    }
    for (var value = 0; value < m; value++) {
      while (_owners[value].length < _lower[value]) {
        if (!_repairLower(value)) return null;
      }
    }

    for (var node = 0; node <= sink; node++) {
      _forward[node].clear();
      _reverse[node].clear();
    }
    void edge(int from, int to) {
      _forward[from].add(to);
      _reverse[to].add(from);
      lastFlowEdges++;
    }

    for (var variable = 0; variable < n; variable++) {
      for (final value in _varAdj[variable]) {
        if (_matchVar[variable] == value) {
          edge(n + value, variable);
        } else {
          edge(variable, n + value);
        }
      }
    }
    for (var value = 0; value < m; value++) {
      final count = _owners[value].length;
      if (count < _upper[value]) edge(n + value, sink);
      if (count > _lower[value]) edge(sink, n + value);
    }
    final scc = _kosarajuScc(_forward, sink + 1, reverse: _reverse);

    // Explanation snapshots are local to this propagation, never cached with
    // the matching. Sibling prunes cannot become antecedents of one another.
    final entryAbsent = <String, List<Atom>>{};
    final scopeAbsent = <Atom>[];
    if (_lcgEnabled) {
      _integerExplanations ??= vars.every((variable) =>
          originalDomains![variable]!.every((value) => value is int));
      if (_integerExplanations!) {
        for (final variable in vars) {
          final original = originalDomains![variable]!;
          final domain = domains[variable]!;
          entryAbsent[variable] =
              _domainShapeAntecedents(variable, original, domain);
          scopeAbsent.addAll(_regularTrailAbsences(variable, original, domain));
        }
      }
    }
    final bridges = <int, Atom>{};
    Atom? scopeBridge;
    Atom lowerBoundBridge() =>
        scopeBridge ??= recordScc!(vars.first, scopeAbsent);
    final changed = <String>{};
    for (var variable = 0; variable < n; variable++) {
      final name = vars[variable];
      final oldDomain = domains[name]!;
      final next = oldDomain.filter((value) {
        final id = _valueIds[value]!;
        return _matchVar[variable] == id || scc[variable] == scc[n + id];
      });
      if (next.length == oldDomain.length) continue;
      if (next.isEmpty) return null;
      ImplicationReason? reason;
      if (_lcgEnabled) {
        reason = _integerExplanations!
            ? _explain(variable, oldDomain, next, entryAbsent, bridges,
                lowerBoundBridge)
            : const UnknownReason();
      }
      applyUpdate(name, next, reason: reason);
      changed.add(name);
    }
    return changed;
  }

  ImplicationReason _explain(
      int variable,
      _DomainRep oldDomain,
      _DomainRep next,
      Map<String, List<Atom>> entryAbsent,
      Map<int, Atom> valueBridge,
      Atom Function() lowerBoundBridge) {
    final bridges = <Atom>[];
    final n = vars.length;
    for (final value in oldDomain.values) {
      if (next.contains(value) || value is! int) continue;
      bridges.add(valueBridge.putIfAbsent(value, () {
        final id = _valueIds[value]!;
        final owners = _owners[id];
        if (owners.length == _upper[id] &&
            owners.every((owner) => domains[vars[owner]]!.length == 1)) {
          return recordScc!(vars[variable],
              [for (final owner in owners) AtomEq(vars[owner], value)]);
        }
        final cut =
            _reachGccValueCut(id, _forward, _owners, _upper, n, variable);
        if (cut != null) {
          final (members, valueIds) = cut;
          final hallValues = {for (final id in valueIds) _values[id]};
          final antecedents = <Atom>[
            for (final member in members)
              for (final atom in entryAbsent[vars[member]]!)
                if (atom is AtomNe && !hallValues.contains(atom.value)) atom,
          ];
          final representative = members.isEmpty ? variable : members.first;
          return recordScc!(vars[representative], antecedents);
        }
        // Lower-capacity cuts can involve a complement of the upper Hall
        // set. The complete entry domain snapshot is a sound explanation
        // of every flow prune; use it until a smaller cut proof is available.
        return lowerBoundBridge();
      }));
    }
    return GccFlowReason(bridges);
  }
}

/// Extract a saturated upper-capacity Hall cut from the compact graph. Reaching
/// the sink means capacity slack (or a lower-bound cycle), so this narrower
/// explanation cannot certify the prune and the caller uses a scope snapshot.
(List<int>, List<int>)? _reachGccValueCut(int start, List<List<int>> graph,
    List<Set<int>> owners, List<int> upper, int n, int excludedVariable) {
  final sink = n + owners.length;
  final seen = <int>{n + start};
  final stack = <int>[n + start];
  final members = <int>[];
  final values = <int>[];
  var capacity = 0;
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node == sink) return null;
    if (node < n) {
      if (node == excludedVariable) return null;
      members.add(node);
    } else {
      final value = node - n;
      if (owners[value].length != upper[value]) return null;
      values.add(value);
      capacity += upper[value];
    }
    for (final next in graph[node]) {
      if (seen.add(next)) stack.add(next);
    }
  }
  return members.length == capacity ? (members, values) : null;
}

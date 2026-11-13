/// Reusable graph traversals and exact fixed-point snapshots for matching globals.
part of 'solver.dart';

/// Successful propagation is idempotent at these exact immutable domains.
///
/// Identity is deliberately stricter than equality. Restoring different domains
/// or applying another constraint invalidates the snapshot without maintaining a
/// separate revision trail. Restoring the exact remembered fixed point is safe.
/// An interrupted or failed attempt never installs it.
class _MatchingFixedPoint {
  _MatchingFixedPoint(int variables)
      : _domains = List<_DomainRep?>.filled(variables, null);

  final List<_DomainRep?> _domains;
  bool _valid = false;

  bool matches(List<String> variables, Map<String, _DomainRep> current,
      _PropagationBudget? budget) {
    if (!_valid) return false;
    for (var i = 0; i < variables.length; i++) {
      budget?.tick();
      if (!identical(_domains[i], current[variables[i]])) return false;
    }
    return true;
  }

  void invalidate() => _valid = false;

  void remember(List<String> variables, Map<String, _DomainRep> current,
      _PropagationBudget? budget) {
    for (var i = 0; i < variables.length; i++) {
      budget?.tick();
      _domains[i] = current[variables[i]];
    }
    _valid = true;
  }
}

/// Retained O(nodes) scratch space for SCC and alternating-path reachability.
///
/// Parallel integer stacks replace the previous per-edge DFS record objects.
/// Returned arrays belong to this workspace and remain valid until another
/// traversal of the same kind or capacity growth. Reachability preserves SCC
/// labels. Only the graph's node prefix is meaningful if capacity is larger.
class _MatchingGraphWorkspace {
  List<bool> _visited = <bool>[];
  List<bool> _reachable = <bool>[];
  List<int> _order = <int>[];
  List<int> _components = <int>[];
  List<int> _nodes = <int>[];
  List<int> _nextEdges = <int>[];

  int sccPasses = 0;
  int growths = 0;
  int fixedPointSkips = 0;

  void beginInvocation() {
    sccPasses = 0;
    growths = 0;
    fixedPointSkips = 0;
  }

  void _ensure(int count) {
    if (_nodes.length >= count) return;
    final capacity = max(count, _nodes.length * 2);
    _visited = List<bool>.filled(capacity, false);
    _reachable = List<bool>.filled(capacity, false);
    _order = List<int>.filled(capacity, 0);
    _components = List<int>.filled(capacity, -1);
    _nodes = List<int>.filled(capacity, 0);
    _nextEdges = List<int>.filled(capacity, 0);
    growths++;
  }

  List<int> components(List<List<int>> graph, List<List<int>> reverse,
      int count, _PropagationBudget? budget) {
    _ensure(count);
    sccPasses++;
    _visited.fillRange(0, count, false);
    _components.fillRange(0, count, -1);
    var orderLength = 0;
    for (var start = 0; start < count; start++) {
      budget?.tick();
      if (_visited[start]) continue;
      var depth = 0;
      _nodes[0] = start;
      _nextEdges[0] = 0;
      _visited[start] = true;
      while (depth >= 0) {
        budget?.tick();
        final node = _nodes[depth];
        final nextEdge = _nextEdges[depth];
        if (nextEdge < graph[node].length) {
          _nextEdges[depth] = nextEdge + 1;
          final next = graph[node][nextEdge];
          if (!_visited[next]) {
            _visited[next] = true;
            depth++;
            _nodes[depth] = next;
            _nextEdges[depth] = 0;
          }
        } else {
          _order[orderLength++] = node;
          depth--;
        }
      }
    }

    var component = 0;
    for (var i = orderLength - 1; i >= 0; i--) {
      budget?.tick();
      final start = _order[i];
      if (_components[start] != -1) continue;
      var size = 1;
      _nodes[0] = start;
      _components[start] = component;
      while (size > 0) {
        final node = _nodes[--size];
        for (final next in reverse[node]) {
          budget?.tick();
          if (_components[next] == -1) {
            _components[next] = component;
            _nodes[size++] = next;
          }
        }
      }
      component++;
    }
    return _components;
  }

  List<bool> reachesFreeValue(List<List<int>> reverse, int count,
      int valueOffset, List<int> matchValue, _PropagationBudget? budget) {
    _ensure(count);
    _reachable.fillRange(0, count, false);
    for (var value = 0; value < matchValue.length; value++) {
      budget?.tick();
      final start = valueOffset + value;
      if (matchValue[value] != -1 || _reachable[start]) continue;
      var size = 1;
      _nodes[0] = start;
      _reachable[start] = true;
      while (size > 0) {
        final node = _nodes[--size];
        for (final next in reverse[node]) {
          budget?.tick();
          if (!_reachable[next]) {
            _reachable[next] = true;
            _nodes[size++] = next;
          }
        }
      }
    }
    return _reachable;
  }
}

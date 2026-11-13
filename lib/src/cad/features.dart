/// Transactional parametric feature graph with explicit dependency revisions.
library;

import 'dart:collection';

import '../geometry/primitives.dart' show GeometryPose;
import '../geometry/solver.dart' show GeometrySolveResult;
import 'kernel.dart';
import 'placement.dart';

class CadParameters {
  CadParameters(Map<String, double> values)
      : this._(values, {for (final name in values.keys) name: 0}, 0);
  CadParameters._(
      Map<String, double> values, Map<String, int> revisions, this.revision)
      : values = Map.unmodifiable(values),
        revisions = Map.unmodifiable(revisions) {
    for (final entry in values.entries) {
      if (entry.key.isEmpty || !entry.value.isFinite) {
        throw ArgumentError(
            'Parameters need nonempty names and finite values.');
      }
    }
  }
  final Map<String, double> values;
  final Map<String, int> revisions;
  final int revision;
  double operator [](String name) {
    final value = values[name];
    if (value == null) {
      throw ArgumentError('No declared parameter named $name.');
    }
    return value;
  }

  CadParameters _select(Set<String> names) => CadParameters._(
      {for (final name in names) name: this[name]},
      {for (final name in names) name: revisions[name]!},
      revision);

  (CadParameters, Set<String>) _edit(Map<String, double> changes) {
    // A no-op edit is common during interaction. Validate before copying the
    // complete parameter maps, and capture changed values once.
    final edits = <String, double>{};
    for (final entry in changes.entries) {
      if (!values.containsKey(entry.key) || !entry.value.isFinite) {
        throw ArgumentError(
            'Edited parameters must already exist and remain finite: ${entry.key}.');
      }
      if (values[entry.key] != entry.value) edits[entry.key] = entry.value;
    }
    if (edits.isEmpty) return (this, const <String>{});
    final next = Map<String, double>.of(values)..addAll(edits);
    final nextRevisions = Map<String, int>.of(revisions);
    for (final name in edits.keys) {
      nextRevisions[name] = nextRevisions[name]! + 1;
    }
    return (
      CadParameters._(next, nextRevisions, revision + 1),
      edits.keys.toSet()
    );
  }
}

/// Immutable parameter arithmetic with declared dependency provenance.
class CadExpression {
  CadExpression.constant(double value)
      : _constant = value,
        _parameter = null,
        _operation = null,
        _left = null,
        _right = null,
        dependencies = const {} {
    if (!value.isFinite) {
      throw ArgumentError('An expression constant must be finite.');
    }
  }
  CadExpression.parameter(String name)
      : _constant = null,
        _parameter = name,
        _operation = null,
        _left = null,
        _right = null,
        dependencies = Set.unmodifiable({name});
  CadExpression._(this._operation, this._left, this._right)
      : _constant = null,
        _parameter = null,
        dependencies =
            Set.unmodifiable({..._left!.dependencies, ..._right!.dependencies});
  final double? _constant;
  final String? _parameter, _operation;
  final CadExpression? _left, _right;
  final Set<String> dependencies;
  static CadExpression _coerce(Object value) => value is CadExpression
      ? value
      : value is num
          ? CadExpression.constant(value.toDouble())
          : throw ArgumentError('Expected a parameter expression or number.');
  CadExpression operator +(Object other) =>
      CadExpression._('+', this, _coerce(other));
  CadExpression operator -(Object other) =>
      CadExpression._('-', this, _coerce(other));
  CadExpression operator *(Object other) =>
      CadExpression._('*', this, _coerce(other));
  CadExpression operator /(Object other) =>
      CadExpression._('/', this, _coerce(other));
  CadExpression operator -() => this * -1;
  double evaluate(CadParameters parameters) {
    final double value;
    if (_constant != null) {
      value = _constant!;
    } else if (_parameter != null) {
      value = parameters[_parameter!];
    } else {
      final left = _left!.evaluate(parameters),
          right = _right!.evaluate(parameters);
      value = switch (_operation) {
        '+' => left + right,
        '-' => left - right,
        '*' => left * right,
        '/' => left / right,
        _ => throw StateError('Unknown expression operation.'),
      };
    }
    if (!value.isFinite) {
      throw StateError('A parameter expression produced a non-finite value.');
    }
    return value;
  }
}

class CadHoleExpression {
  const CadHoleExpression(
      {required this.id,
      required this.centerX,
      required this.centerY,
      required this.radius});
  final String id;
  final CadExpression centerX, centerY, radius;
  Set<String> get dependencies => {
        ...centerX.dependencies,
        ...centerY.dependencies,
        ...radius.dependencies
      };
  CadCircularHole evaluate(CadParameters parameters) => CadCircularHole(
      id: id,
      centerX: centerX.evaluate(parameters),
      centerY: centerY.evaluate(parameters),
      radius: radius.evaluate(parameters));
}

/// Parameter-driven rigid placement. The default axis is world/local Z before
/// placement, and `angle` is in radians. Translation is applied after rotation.
final class CadPlacementExpression {
  factory CadPlacementExpression({
    CadExpression? x,
    CadExpression? y,
    CadExpression? z,
    CadExpression? angle,
    CadPoint3 axis = const CadPoint3(0, 0, 1),
  }) {
    final frozenAxis = CadPoint3(axis.x, axis.y, axis.z);
    // Validate the fixed axis at model construction, without evaluating any
    // parameter expressions or keeping mutable caller-owned vector subclasses.
    CadRigidTransform.axisAngle(axis: frozenAxis, angle: 0);
    return CadPlacementExpression._([
      x ?? CadExpression.constant(0),
      y ?? CadExpression.constant(0),
      z ?? CadExpression.constant(0)
    ], angle ?? CadExpression.constant(0), frozenAxis, null);
  }

  /// Quaternion expressions use scalar-first order. Zero/non-finite evaluated
  /// quaternions reject the edit; nonzero finite values are safely normalized.
  factory CadPlacementExpression.quaternion({
    required Iterable<CadExpression> quaternion,
    CadExpression? x,
    CadExpression? y,
    CadExpression? z,
  }) {
    final frozen = List<CadExpression>.unmodifiable(quaternion);
    if (frozen.length != 4) {
      throw ArgumentError('A placement quaternion needs four expressions.');
    }
    return CadPlacementExpression._([
      x ?? CadExpression.constant(0),
      y ?? CadExpression.constant(0),
      z ?? CadExpression.constant(0)
    ], null, null, frozen);
  }

  CadPlacementExpression._(List<CadExpression> translation, this._angle,
      this._axis, this._quaternion)
      : _translation = List.unmodifiable(translation),
        dependencies = Set.unmodifiable({
          for (final expression in translation) ...expression.dependencies,
          if (_angle != null) ..._angle.dependencies,
          if (_quaternion != null)
            for (final expression in _quaternion) ...expression.dependencies,
        });

  final List<CadExpression> _translation;
  final CadExpression? _angle;
  final CadPoint3? _axis;
  final List<CadExpression>? _quaternion;
  final Set<String> dependencies;

  CadRigidTransform evaluate(CadParameters parameters) {
    final position = CadPoint3(
        _translation[0].evaluate(parameters),
        _translation[1].evaluate(parameters),
        _translation[2].evaluate(parameters));
    return _quaternion != null
        ? CadRigidTransform(translation: position, quaternion: [
            for (final expression in _quaternion!)
              expression.evaluate(parameters)
          ])
        : CadRigidTransform.axisAngle(
            translation: position,
            axis: _axis!,
            angle: _angle!.evaluate(parameters));
  }
}

class CadFeatureContext {
  CadFeatureContext._(
      {required this.kernel,
      required this.parameters,
      required Object? previousOutput,
      required Map<String, Object> inputs})
      : _previousOutput = previousOutput,
        _inputs = Map.unmodifiable(inputs);
  final CadKernel kernel;

  /// Only declared parameter dependencies are visible, preventing accidental
  /// reads that the dirty propagation graph would otherwise miss.
  final CadParameters parameters;
  final Map<String, Object> _inputs;
  final Object? _previousOutput;

  /// This feature's last committed output, usable as a numerical warm start.
  /// Candidate output from a failed transaction is never supplied here.
  T? previousOutput<T extends Object>() {
    final value = _previousOutput;
    if (value == null) return null;
    if (value is! T) {
      throw StateError('Incompatible previous feature output.');
    }
    return value;
  }

  T input<T extends Object>(String featureId) {
    final value = _inputs[featureId];
    if (value is! T) {
      throw StateError(
          'Missing, undeclared, or incompatible feature input $featureId.');
    }
    return value;
  }
}

/// A pure evaluator. Custom outputs and captured data must also be immutable.
/// A geometry-solver adapter can validate a sketch and return its profile here.
class CadFeatureNode {
  CadFeatureNode(
      {required this.id,
      required this.evaluate,
      Iterable<String> dependencies = const [],
      Iterable<String> parameterDependencies = const []})
      : dependencies = List.unmodifiable(dependencies),
        parameterDependencies = Set.unmodifiable(parameterDependencies) {
    if (id.isEmpty) throw ArgumentError('A feature needs a stable ID.');
  }
  factory CadFeatureNode.rectangularProfile(
      {required String id,
      required CadExpression width,
      required CadExpression height,
      Iterable<CadHoleExpression> holes = const []}) {
    final frozenHoles = List<CadHoleExpression>.unmodifiable(holes);
    return CadFeatureNode(
        id: id,
        parameterDependencies: {
          ...width.dependencies,
          ...height.dependencies,
          for (final hole in frozenHoles) ...hole.dependencies
        },
        evaluate: (context) => CadKernelResult.success(CadRectangularProfile(
              width: width.evaluate(context.parameters),
              height: height.evaluate(context.parameters),
              holes:
                  frozenHoles.map((hole) => hole.evaluate(context.parameters)),
            )));
  }

  factory CadFeatureNode.extrude(
          {required String id,
          required String profile,
          required CadExpression depth}) =>
      CadFeatureNode(
          id: id,
          dependencies: [profile],
          parameterDependencies: depth.dependencies,
          evaluate: (context) => context.kernel.extrude(
              featureId: id,
              profile: context.input<CadPlanarProfile>(profile),
              depth: depth.evaluate(context.parameters)));
  factory CadFeatureNode.tessellate(
          {required String id,
          required String body,
          required CadExpression chordError}) =>
      CadFeatureNode(
          id: id,
          dependencies: [body],
          parameterDependencies: chordError.dependencies,
          evaluate: (context) => context.kernel.tessellate(
              context.input<CadBody>(body),
              chordError: chordError.evaluate(context.parameters)));

  /// Places a shared local body; pose-only changes do not rebuild the body or
  /// its separately held local display mesh.
  factory CadFeatureNode.instance({
    required String id,
    required String body,
    required CadPlacementExpression placement,
    double linearTolerance = 1e-7,
  }) =>
      CadFeatureNode(
          id: id,
          dependencies: [body],
          parameterDependencies: placement.dependencies,
          evaluate: (context) => CadKernelResult.success(CadBodyInstance(
              featureId: id,
              body: context.input<CadBody>(body),
              linearTolerance: linearTolerance,
              placement: placement.evaluate(context.parameters))));

  /// Connects an assembly solver's successful pose to an analytic occurrence.
  /// [geometry] must produce a [GeometrySolveResult], for example from
  /// `constrainedGeometryFeature`.
  factory CadFeatureNode.instanceFromPose({
    required String id,
    required String body,
    required String geometry,
    required GeometryPose pose,
    double linearTolerance = 1e-7,
  }) =>
      CadFeatureNode(
          id: id,
          dependencies: [body, geometry],
          evaluate: (context) => CadKernelResult.success(CadBodyInstance(
              featureId: id,
              body: context.input<CadBody>(body),
              linearTolerance: linearTolerance,
              placement: CadRigidTransform.fromGeometryPose(
                  context.input<GeometrySolveResult>(geometry), pose))));
  final String id;
  final List<String> dependencies;
  final Set<String> parameterDependencies;
  final CadKernelResult<Object> Function(CadFeatureContext context) evaluate;
}

/// A design-semantic reference, never an unstable face-list index.
class TopologyRef {
  const TopologyRef(
      {required this.featureId, required this.semanticId, required this.kind});
  final String featureId, semanticId;
  final CadTopologyKind kind;
}

// The graph's feature IDs never change. Store a committed value/revision pair
// in a fixed-shape, immutable chunked vector, and expose read-only Map views.
// A small edit copies touched chunks plus the much smaller chunk directory;
// previous states never point to a mutable candidate or an overlay chain.
const _featureChunkSize = 128;

final class _FeatureValue {
  const _FeatureValue(this.output, this.revision);
  final Object output;
  final int revision;
}

final class _FeatureStore {
  _FeatureStore(this.ids, this.indexes, List<List<_FeatureValue>> chunks)
      : _chunks = UnmodifiableListView(chunks);

  factory _FeatureStore.build(List<String> ids, Map<String, int> indexes,
      _FeatureStore? previous, Map<int, _FeatureValue> edits) {
    if (previous == null) {
      final chunks = <List<_FeatureValue>>[];
      for (var start = 0; start < ids.length; start += _featureChunkSize) {
        final end = start + _featureChunkSize < ids.length
            ? start + _featureChunkSize
            : ids.length;
        chunks.add(UnmodifiableListView([
          for (var i = start; i < end; i++) edits[i]!,
        ]));
      }
      return _FeatureStore(ids, indexes, chunks);
    }
    if (edits.isEmpty) return previous;
    final changedChunks = <int, List<_FeatureValue>>{};
    for (final entry in edits.entries) {
      final chunk = entry.key ~/ _featureChunkSize;
      final values = changedChunks.putIfAbsent(
          chunk, () => List<_FeatureValue>.of(previous._chunks[chunk]));
      values[entry.key % _featureChunkSize] = entry.value;
    }
    final chunks = List<List<_FeatureValue>>.of(previous._chunks);
    for (final entry in changedChunks.entries) {
      chunks[entry.key] = UnmodifiableListView(entry.value);
    }
    return _FeatureStore(ids, indexes, chunks);
  }
  final List<String> ids;
  final Map<String, int> indexes;
  final List<List<_FeatureValue>> _chunks;
  late final Map<String, Object> outputs = _FeatureOutputs(this);
  late final Map<String, int> revisions = _FeatureRevisions(this);

  _FeatureValue at(int index) =>
      _chunks[index ~/ _featureChunkSize][index % _featureChunkSize];
}

final class _FeatureOutputs extends UnmodifiableMapBase<String, Object> {
  _FeatureOutputs(this.store);
  final _FeatureStore store;
  @override
  Object? operator [](Object? key) {
    final index = store.indexes[key];
    return index == null ? null : store.at(index).output;
  }

  @override
  Iterable<String> get keys => store.ids;
  @override
  int get length => store.ids.length;
  @override
  bool containsKey(Object? key) => store.indexes.containsKey(key);
}

final class _FeatureRevisions extends UnmodifiableMapBase<String, int> {
  _FeatureRevisions(this.store);
  final _FeatureStore store;
  @override
  int? operator [](Object? key) {
    final index = store.indexes[key];
    return index == null ? null : store.at(index).revision;
  }

  @override
  Iterable<String> get keys => store.ids;
  @override
  int get length => store.ids.length;
  @override
  bool containsKey(Object? key) => store.indexes.containsKey(key);
}

class CadDocumentState {
  CadDocumentState._(
      {required this.parameters,
      required this.revision,
      _FeatureStore? featureStore})
      : _featureStore = featureStore,
        outputs = featureStore?.outputs ?? const {},
        featureRevisions = featureStore?.revisions ?? const {};
  final CadParameters parameters;
  final int revision;
  final _FeatureStore? _featureStore;
  final Map<String, Object> outputs;
  final Map<String, int> featureRevisions;
  T output<T extends Object>(String featureId) {
    final value = outputs[featureId];
    if (value is! T) {
      throw StateError('Missing or incompatible feature output $featureId.');
    }
    return value;
  }

  CadTopologyResolution resolve(TopologyRef reference) {
    final body = outputs[reference.featureId];
    if (body is CadBody) {
      return body.resolve(reference.kind, reference.semanticId);
    }
    if (body is CadBodyInstance) {
      return body.resolve(reference.kind, reference.semanticId);
    }
    return CadTopologyResolution(const []);
  }
}

enum CadRegenerationStatus { committed, unchanged, rejected }

/// Structural regeneration work, independent of hardware or elapsed time.
class CadRegenerationStats {
  const CadRegenerationStats({
    this.scheduledFeatures = 0,
    this.dependencyEdgesVisited = 0,
    this.stateChunksCopied = 0,
    this.stateEntriesCopied = 0,
    this.stateDirectoryEntriesCopied = 0,
  });

  /// Features selected from changed parameters and their downstream closure.
  final int scheduledFeatures;

  /// Downstream edges inspected while discovering that closure; initial full
  /// construction does not need a dirty-closure walk and reports zero.
  final int dependencyEdgesVisited;

  /// Previously committed chunks and value/revision entries copied to isolate
  /// the candidate. New entries on first construction are not counted here.
  final int stateChunksCopied, stateEntriesCopied;

  /// References in the chunk directory copied for an edited snapshot:
  /// ceil(featureCount / 128), independent of how many entries each chunk holds.
  final int stateDirectoryEntriesCopied;
}

class CadRegenerationResult {
  CadRegenerationResult(
      {required this.status,
      required this.state,
      required Iterable<String> rebuiltFeatures,
      Iterable<CadIssue> issues = const [],
      this.failedFeature,
      this.stats = const CadRegenerationStats()})
      : rebuiltFeatures = List.unmodifiable(rebuiltFeatures),
        issues = List.unmodifiable(issues);
  final CadRegenerationStatus status;

  /// The committed state; on failure this is exactly the previous state.
  final CadDocumentState state;
  final List<String> rebuiltFeatures;
  final List<CadIssue> issues;
  final String? failedFeature;
  final CadRegenerationStats stats;
  bool get isSuccess => status != CadRegenerationStatus.rejected;
}

/// Evaluates edits transactionally and retains the last valid model on error.
/// Declarations are snapshotted at construction; no caller-supplied type getter
/// is trusted to prove that a declaration's metadata is immutable.
class CadFeatureDocument {
  CadFeatureDocument(
      {required this.kernel,
      required CadParameters parameters,
      required Iterable<CadFeatureNode> features,
      Iterable<TopologyRef> requiredReferences = const []})
      : _features = List.unmodifiable(features.map((feature) => CadFeatureNode(
            id: feature.id,
            evaluate: feature.evaluate,
            dependencies: feature.dependencies,
            parameterDependencies: feature.parameterDependencies))),
        requiredReferences = List.unmodifiable(requiredReferences),
        _state = CadDocumentState._(parameters: parameters, revision: 0) {
    // Compile from private owned declarations, never an overridable public
    // getter on a CadFeatureDocument subclass.
    _order = _topologicalOrder(_features);
    _ids = List.unmodifiable(_order.map((feature) => feature.id));
    _indexes = Map.unmodifiable({
      for (var i = 0; i < _order.length; i++) _order[i].id: i,
    });
    final consumers = <String, List<int>>{};
    final downstream = List<List<int>?>.filled(_order.length, null);
    for (var i = 0; i < _order.length; i++) {
      final feature = _order[i];
      for (final name in feature.parameterDependencies) {
        if (!parameters.values.containsKey(name)) {
          throw ArgumentError(
              'Feature ${feature.id} requires missing parameter $name.');
        }
        (consumers[name] ??= []).add(i);
      }
      for (final dependency in feature.dependencies) {
        (downstream[_indexes[dependency]!] ??= []).add(i);
      }
    }
    _parameterConsumers = Map.unmodifiable({
      for (final entry in consumers.entries)
        entry.key: List<int>.unmodifiable(entry.value),
    });
    _downstream = List.unmodifiable([
      for (final values in downstream)
        if (values == null) const <int>[] else List<int>.unmodifiable(values),
    ]);
  }
  final CadKernel kernel;
  final List<CadFeatureNode> _features;
  List<CadFeatureNode> get features => _features;
  final List<TopologyRef> requiredReferences;
  late final List<CadFeatureNode> _order;
  late final List<String> _ids;
  late final Map<String, int> _indexes;
  late final Map<String, List<int>> _parameterConsumers;
  late final List<List<int>> _downstream;
  CadDocumentState _state;
  CadDocumentState get state => _state;

  CadRegenerationResult regenerate({Map<String, double> changes = const {}}) {
    final rebuilt = <String>[];
    var scheduled = 0, edgesVisited = 0;
    var chunksCopied = 0, entriesCopied = 0, directoryEntriesCopied = 0;
    CadRegenerationStats stats() => CadRegenerationStats(
        scheduledFeatures: scheduled,
        dependencyEdgesVisited: edgesVisited,
        stateChunksCopied: chunksCopied,
        stateEntriesCopied: entriesCopied,
        stateDirectoryEntriesCopied: directoryEntriesCopied);
    CadRegenerationResult reject(Iterable<CadIssue> issues,
            [String? feature]) =>
        CadRegenerationResult(
            status: CadRegenerationStatus.rejected,
            state: _state,
            rebuiltFeatures: rebuilt,
            issues: issues,
            failedFeature: feature,
            stats: stats());
    final CadParameters parameters;
    final Set<String> changed;
    try {
      final edited = _state.parameters._edit(changes);
      parameters = edited.$1;
      changed = edited.$2;
    } on Object catch (error) {
      return reject([CadIssue('invalid_parameter_edit', error.toString())]);
    }
    final previous = _state._featureStore;
    final List<int> dirty;
    if (previous == null) {
      dirty = List.generate(_order.length, (i) => i);
    } else {
      final selected = <int>{};
      final queue = <int>[];
      void select(int index) {
        if (selected.add(index)) queue.add(index);
      }

      for (final name in changed) {
        for (final index in _parameterConsumers[name] ?? const <int>[]) {
          select(index);
        }
      }
      for (var head = 0; head < queue.length; head++) {
        for (final index in _downstream[queue[head]]) {
          edgesVisited++;
          select(index);
        }
      }
      // Preserve the exact original DFS/topological order. Sparse edits sort
      // only the affected closure; broad edits use one linear pass instead.
      if (queue.length > _order.length ~/ 8) {
        dirty = [
          for (var i = 0; i < _order.length; i++)
            if (selected.contains(i)) i,
        ];
      } else {
        dirty = queue..sort();
      }
    }
    scheduled = dirty.length;
    if (dirty.isEmpty && changed.isEmpty) {
      return CadRegenerationResult(
          status: CadRegenerationStatus.unchanged,
          state: _state,
          rebuiltFeatures: const [],
          stats: stats());
    }
    final edits = <int, _FeatureValue>{};
    for (final index in dirty) {
      final feature = _order[index];
      rebuilt.add(feature.id);
      final CadKernelResult<Object> result;
      try {
        result = feature.evaluate(CadFeatureContext._(
            kernel: kernel,
            parameters: parameters._select(feature.parameterDependencies),
            previousOutput: previous?.at(index).output,
            inputs: {
              for (final dependency in feature.dependencies)
                dependency: (edits[_indexes[dependency]!] ??
                        previous!.at(_indexes[dependency]!))
                    .output,
            }));
      } on Object catch (error) {
        return reject([
          CadIssue('feature_evaluation_failed', error.toString(),
              entity: feature.id)
        ], feature.id);
      }
      if (!result.isSuccess) return reject(result.issues, feature.id);
      final value = result.value!;
      final List<CadIssue> validation;
      try {
        validation = value is CadBody
            ? kernel.validate(value)
            : value is CadBodyInstance
                ? value.validate(kernel)
                : value is CadMesh
                    ? value.validate()
                    : const <CadIssue>[];
      } on Object catch (error) {
        return reject([
          CadIssue('feature_validation_failed', error.toString(),
              entity: feature.id)
        ], feature.id);
      }
      if (validation.isNotEmpty) return reject(validation, feature.id);
      edits[index] =
          _FeatureValue(value, (previous?.at(index).revision ?? 0) + 1);
    }
    if (previous != null && edits.isNotEmpty) {
      final copied = {
        for (final index in edits.keys) index ~/ _featureChunkSize
      };
      chunksCopied = copied.length;
      entriesCopied = copied.fold(
          0, (count, index) => count + previous._chunks[index].length);
      directoryEntriesCopied = previous._chunks.length;
    }
    final candidate = CadDocumentState._(
        parameters: parameters,
        revision: _state.revision + 1,
        featureStore: _FeatureStore.build(_ids, _indexes, previous, edits));
    for (final reference in requiredReferences) {
      final resolution = candidate.resolve(reference);
      if (resolution.status != CadTopologyResolutionStatus.found) {
        return reject([
          CadIssue('topology_${resolution.status.name}',
              'The semantic reference ${reference.semanticId} is ${resolution.status.name}; no face was guessed.',
              entity: reference.featureId)
        ], reference.featureId);
      }
    }
    _state = candidate;
    return CadRegenerationResult(
        status: CadRegenerationStatus.committed,
        state: _state,
        rebuiltFeatures: rebuilt,
        stats: stats());
  }

  static List<CadFeatureNode> _topologicalOrder(List<CadFeatureNode> features) {
    final byId = <String, CadFeatureNode>{};
    for (final feature in features) {
      if (byId.containsKey(feature.id)) {
        throw ArgumentError('Duplicate feature ID ${feature.id}.');
      }
      if (feature.dependencies.toSet().length != feature.dependencies.length) {
        throw ArgumentError('Duplicate dependency on ${feature.id}.');
      }
      byId[feature.id] = feature;
    }
    final order = <CadFeatureNode>[];
    final visiting = <String>{}, visited = <String>{};
    // Explicit frames reproduce the old recursive DFS order and diagnostics
    // without consuming the process stack for a long feature history.
    final stack = <(CadFeatureNode, int)>[];
    for (final root in features) {
      if (visited.contains(root.id)) continue;
      visiting.add(root.id);
      stack.add((root, 0));
      while (stack.isNotEmpty) {
        final (feature, nextDependency) = stack.last;
        if (nextDependency == feature.dependencies.length) {
          stack.removeLast();
          visiting.remove(feature.id);
          visited.add(feature.id);
          order.add(feature);
          continue;
        }
        stack[stack.length - 1] = (feature, nextDependency + 1);
        final dependency = feature.dependencies[nextDependency];
        final node = byId[dependency];
        if (node == null) {
          throw ArgumentError('Missing feature dependency $dependency.');
        }
        if (visited.contains(node.id)) continue;
        if (!visiting.add(node.id)) {
          throw ArgumentError('Feature dependency cycle at ${node.id}.');
        }
        stack.add((node, 0));
      }
    }
    return List.unmodifiable(order);
  }
}

/// Transactional parametric feature graph with explicit dependency revisions.
library;

import 'kernel.dart';

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
    final next = Map<String, double>.of(values);
    final nextRevisions = Map<String, int>.of(revisions);
    final changed = <String>{};
    for (final entry in changes.entries) {
      if (!values.containsKey(entry.key) || !entry.value.isFinite) {
        throw ArgumentError(
            'Edited parameters must already exist and remain finite: ${entry.key}.');
      }
      if (next[entry.key] != entry.value) {
        next[entry.key] = entry.value;
        nextRevisions[entry.key] = nextRevisions[entry.key]! + 1;
        changed.add(entry.key);
      }
    }
    return changed.isEmpty
        ? (this, changed)
        : (CadParameters._(next, nextRevisions, revision + 1), changed);
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

class CadDocumentState {
  CadDocumentState._(
      {required this.parameters,
      required this.revision,
      required Map<String, Object> outputs,
      required Map<String, int> featureRevisions})
      : outputs = Map.unmodifiable(outputs),
        featureRevisions = Map.unmodifiable(featureRevisions);
  final CadParameters parameters;
  final int revision;
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
    return body is CadBody
        ? body.resolve(reference.kind, reference.semanticId)
        : CadTopologyResolution(const []);
  }
}

enum CadRegenerationStatus { committed, unchanged, rejected }

class CadRegenerationResult {
  CadRegenerationResult(
      {required this.status,
      required this.state,
      required Iterable<String> rebuiltFeatures,
      Iterable<CadIssue> issues = const [],
      this.failedFeature})
      : rebuiltFeatures = List.unmodifiable(rebuiltFeatures),
        issues = List.unmodifiable(issues);
  final CadRegenerationStatus status;

  /// The committed state; on failure this is exactly the previous state.
  final CadDocumentState state;
  final List<String> rebuiltFeatures;
  final List<CadIssue> issues;
  final String? failedFeature;
  bool get isSuccess => status != CadRegenerationStatus.rejected;
}

/// Evaluates edits transactionally and retains the last valid model on error.
class CadFeatureDocument {
  CadFeatureDocument(
      {required this.kernel,
      required CadParameters parameters,
      required Iterable<CadFeatureNode> features,
      Iterable<TopologyRef> requiredReferences = const []})
      : features = List.unmodifiable(features),
        requiredReferences = List.unmodifiable(requiredReferences),
        _state = CadDocumentState._(
            parameters: parameters,
            revision: 0,
            outputs: {},
            featureRevisions: {}) {
    _order = _topologicalOrder(this.features);
    for (final feature in this.features) {
      for (final name in feature.parameterDependencies) {
        if (!parameters.values.containsKey(name)) {
          throw ArgumentError(
              'Feature ${feature.id} requires missing parameter $name.');
        }
      }
    }
  }
  final CadKernel kernel;
  final List<CadFeatureNode> features;
  final List<TopologyRef> requiredReferences;
  late final List<CadFeatureNode> _order;
  CadDocumentState _state;
  CadDocumentState get state => _state;

  CadRegenerationResult regenerate({Map<String, double> changes = const {}}) {
    final rebuilt = <String>[];
    CadRegenerationResult reject(Iterable<CadIssue> issues,
            [String? feature]) =>
        CadRegenerationResult(
            status: CadRegenerationStatus.rejected,
            state: _state,
            rebuiltFeatures: rebuilt,
            issues: issues,
            failedFeature: feature);
    final CadParameters parameters;
    final Set<String> changed;
    try {
      final edited = _state.parameters._edit(changes);
      parameters = edited.$1;
      changed = edited.$2;
    } on Object catch (error) {
      return reject([CadIssue('invalid_parameter_edit', error.toString())]);
    }
    final outputs = Map<String, Object>.of(_state.outputs);
    final revisions = Map<String, int>.of(_state.featureRevisions);
    final dirty = <String>{};
    for (final feature in _order) {
      if (!outputs.containsKey(feature.id) ||
          feature.parameterDependencies.any(changed.contains) ||
          feature.dependencies.any(dirty.contains)) {
        dirty.add(feature.id);
      }
    }
    if (dirty.isEmpty && changed.isEmpty) {
      return CadRegenerationResult(
          status: CadRegenerationStatus.unchanged,
          state: _state,
          rebuiltFeatures: const []);
    }
    for (final feature in _order) {
      if (!dirty.contains(feature.id)) continue;
      rebuilt.add(feature.id);
      final CadKernelResult<Object> result;
      try {
        result = feature.evaluate(CadFeatureContext._(
            kernel: kernel,
            parameters: parameters._select(feature.parameterDependencies),
            previousOutput: _state.outputs[feature.id],
            inputs: {
              for (final dependency in feature.dependencies)
                dependency: outputs[dependency]!
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
      outputs[feature.id] = value;
      revisions[feature.id] = (revisions[feature.id] ?? 0) + 1;
    }
    final candidate = CadDocumentState._(
        parameters: parameters,
        revision: _state.revision + 1,
        outputs: outputs,
        featureRevisions: revisions);
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
        rebuiltFeatures: rebuilt);
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
    void visit(CadFeatureNode feature) {
      if (visited.contains(feature.id)) return;
      if (!visiting.add(feature.id)) {
        throw ArgumentError('Feature dependency cycle at ${feature.id}.');
      }
      for (final dependency in feature.dependencies) {
        final node = byId[dependency];
        if (node == null) {
          throw ArgumentError('Missing feature dependency $dependency.');
        }
        visit(node);
      }
      visiting.remove(feature.id);
      visited.add(feature.id);
      order.add(feature);
    }

    for (final feature in features) {
      visit(feature);
    }
    return List.unmodifiable(order);
  }
}

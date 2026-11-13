import 'dart:math' as math;
import 'dart:typed_data';

import 'autodiff.dart';
import 'numeric.dart';

export 'autodiff.dart' show Dual;
export 'numeric.dart';

/// Storage-to-tangent mapping for one parameter block.
abstract class GeometryManifold {
  const GeometryManifold();
  int get ambientSize;
  int get tangentSize;

  /// Write a retraction of [delta] at [base] into [out].
  void plus(Float64List base, Float64List delta, Float64List out);

  /// Row-major `ambientSize x tangentSize` derivative of plus at delta = 0.
  void plusJacobian(Float64List base, Float64List out);

  bool isValid(Float64List values) =>
      values.length == ambientSize && values.every((v) => v.isFinite);
}

class EuclideanGeometryManifold extends GeometryManifold {
  const EuclideanGeometryManifold(this.ambientSize);
  @override
  final int ambientSize;
  @override
  int get tangentSize => ambientSize;
  @override
  void plus(Float64List base, Float64List delta, Float64List out) {
    for (var i = 0; i < ambientSize; i++) {
      out[i] = base[i] + delta[i];
    }
  }

  @override
  void plusJacobian(Float64List base, Float64List out) {
    out.fillRange(0, out.length, 0);
    for (var i = 0; i < ambientSize; i++) {
      out[i * ambientSize + i] = 1;
    }
  }
}

/// Unit quaternion `[w, x, y, z]` with a three-dimensional rotation increment.
/// Retraction uses left multiplication: `exp(delta / 2) * base`.
class QuaternionGeometryManifold extends GeometryManifold {
  const QuaternionGeometryManifold();
  @override
  int get ambientSize => 4;
  @override
  int get tangentSize => 3;
  @override
  bool isValid(Float64List values) =>
      super.isValid(values) && (geometryNorm(values) - 1).abs() <= 1e-8;
  @override
  void plus(Float64List base, Float64List delta, Float64List out) {
    final angle = geometryNorm(delta);
    final factor =
        angle < 1e-8 ? 0.5 - angle * angle / 48 : math.sin(angle / 2) / angle;
    final w = math.cos(angle / 2);
    final x = delta[0] * factor;
    final y = delta[1] * factor;
    final z = delta[2] * factor;
    out[0] = w * base[0] - x * base[1] - y * base[2] - z * base[3];
    out[1] = w * base[1] + x * base[0] + y * base[3] - z * base[2];
    out[2] = w * base[2] - x * base[3] + y * base[0] + z * base[1];
    out[3] = w * base[3] + x * base[2] - y * base[1] + z * base[0];
    final length = geometryNorm(out);
    for (var i = 0; i < 4; i++) {
      out[i] /= length;
    }
  }

  @override
  void plusJacobian(Float64List base, Float64List out) {
    final w = base[0] * 0.5;
    final x = base[1] * 0.5;
    final y = base[2] * 0.5;
    final z = base[3] * 0.5;
    out.setAll(0, [-x, -y, -z, w, z, -y, -z, w, x, y, -x, w]);
  }
}

/// Cartesian product of manifolds, e.g. translation followed by a quaternion.
class ProductGeometryManifold extends GeometryManifold {
  ProductGeometryManifold(Iterable<GeometryManifold> factors)
      : factors = List<GeometryManifold>.unmodifiable(factors) {
    if (this.factors.isEmpty) throw ArgumentError('A product needs factors.');
  }
  final List<GeometryManifold> factors;
  @override
  int get ambientSize => factors.fold(0, (n, f) => n + f.ambientSize);
  @override
  int get tangentSize => factors.fold(0, (n, f) => n + f.tangentSize);
  @override
  bool isValid(Float64List values) {
    if (!super.isValid(values)) return false;
    var offset = 0;
    for (final factor in factors) {
      if (!factor.isValid(Float64List.sublistView(
          values, offset, offset + factor.ambientSize))) {
        return false;
      }
      offset += factor.ambientSize;
    }
    return true;
  }

  @override
  void plus(Float64List base, Float64List delta, Float64List out) {
    var a = 0;
    var t = 0;
    for (final factor in factors) {
      factor.plus(
          Float64List.sublistView(base, a, a + factor.ambientSize),
          Float64List.sublistView(delta, t, t + factor.tangentSize),
          Float64List.sublistView(out, a, a + factor.ambientSize));
      a += factor.ambientSize;
      t += factor.tangentSize;
    }
  }

  @override
  void plusJacobian(Float64List base, Float64List out) {
    out.fillRange(0, out.length, 0);
    var a = 0;
    var t = 0;
    for (final factor in factors) {
      final block = Float64List(factor.ambientSize * factor.tangentSize);
      factor.plusJacobian(
          Float64List.sublistView(base, a, a + factor.ambientSize), block);
      for (var row = 0; row < factor.ambientSize; row++) {
        for (var col = 0; col < factor.tangentSize; col++) {
          out[(a + row) * tangentSize + t + col] =
              block[row * factor.tangentSize + col];
        }
      }
      a += factor.ambientSize;
      t += factor.tangentSize;
    }
  }
}

/// Immutable parameter declaration. Fixed blocks can still be edited as input
/// dimensions in a session; they contribute no optimization degrees of freedom.
class GeometryParameterBlock {
  GeometryParameterBlock({
    required this.id,
    required List<double> values,
    this.fixed = false,
    List<double>? lowerBounds,
    List<double>? upperBounds,
    List<double>? scales,
    GeometryManifold? manifold,
  })  : values = List<double>.unmodifiable(values),
        manifold = manifold ?? EuclideanGeometryManifold(values.length),
        lowerBounds = List<double>.unmodifiable(lowerBounds ??
            List<double>.filled(values.length, double.negativeInfinity)),
        upperBounds = List<double>.unmodifiable(
            upperBounds ?? List<double>.filled(values.length, double.infinity)),
        scales = List<double>.unmodifiable(scales ??
            List<double>.filled(manifold?.tangentSize ?? values.length, 1)) {
    if (id.isEmpty ||
        values.isEmpty ||
        this.manifold.ambientSize != values.length ||
        this.manifold.tangentSize <= 0 ||
        this.lowerBounds.length != values.length ||
        this.upperBounds.length != values.length ||
        this.scales.length != this.manifold.tangentSize ||
        this.scales.any((v) => !v.isFinite || v <= 0)) {
      throw ArgumentError('Invalid parameter block $id.');
    }
    for (var i = 0; i < values.length; i++) {
      if (this.lowerBounds[i].isNaN ||
          this.upperBounds[i].isNaN ||
          this.lowerBounds[i] > this.upperBounds[i]) {
        throw ArgumentError('Invalid bounds for $id.');
      }
      if (this.manifold is! EuclideanGeometryManifold &&
          (this.lowerBounds[i] != double.negativeInfinity ||
              this.upperBounds[i] != double.infinity)) {
        throw ArgumentError('Coordinate bounds require a Euclidean manifold.');
      }
    }
    _validate(values);
  }
  final String id;
  final List<double> values;
  final bool fixed;
  final List<double> lowerBounds;
  final List<double> upperBounds;
  final List<double> scales;
  final GeometryManifold manifold;
  void _validate(List<double> input) {
    if (input.length != values.length ||
        !manifold.isValid(Float64List.fromList(input))) {
      throw ArgumentError('Invalid coordinates for $id.');
    }
    for (var i = 0; i < input.length; i++) {
      if (input[i] < lowerBounds[i] || input[i] > upperBounds[i]) {
        throw ArgumentError('Coordinates for $id lie outside their bounds.');
      }
    }
  }
}

typedef GeometryResidualEvaluator = void Function(List<Float64List> values,
    Float64List residuals, List<Float64List>? ambientJacobians);
typedef GeometryAutoDiffEvaluator = List<Dual> Function(
    List<List<Dual>> values);

/// Required equations with explicit parameter dependencies and physical
/// tolerances. Jacobian blocks are row-major `residualCount x ambientSize`.
/// Callbacks must not mutate parameters; changing captured inputs requires
/// [GeometrySolveSession.invalidateConstraint]. Prefer fixed parameter blocks
/// for editable dimensions, because those invalidate dependencies automatically.
class GeometryResidualBlock {
  GeometryResidualBlock({
    required this.id,
    required List<String> parameterIds,
    required this.residualCount,
    required this.evaluate,
    double tolerance = 1e-8,
    double scale = 1,
    List<double>? tolerances,
    List<double>? scales,
  })  : parameterIds = List<String>.unmodifiable(parameterIds),
        tolerances = List<double>.unmodifiable(
            tolerances ?? List<double>.filled(residualCount, tolerance)),
        scales = List<double>.unmodifiable(
            scales ?? List<double>.filled(residualCount, scale)) {
    if (id.isEmpty ||
        residualCount <= 0 ||
        this.parameterIds.toSet().length != parameterIds.length ||
        this.tolerances.length != residualCount ||
        this.scales.length != residualCount ||
        this.tolerances.any((x) => !x.isFinite || x <= 0) ||
        this.scales.any((x) => !x.isFinite || x <= 0)) {
      throw ArgumentError('Invalid residual block $id.');
    }
  }

  factory GeometryResidualBlock.autoDiff({
    required String id,
    required List<String> parameterIds,
    required int residualCount,
    required GeometryAutoDiffEvaluator evaluate,
    double tolerance = 1e-8,
    double scale = 1,
    List<double>? tolerances,
    List<double>? scales,
  }) =>
      GeometryResidualBlock(
          id: id,
          parameterIds: parameterIds,
          residualCount: residualCount,
          tolerance: tolerance,
          scale: scale,
          tolerances: tolerances,
          scales: scales,
          evaluate: (values, residuals, jacobians) {
            final dimension = jacobians == null
                ? 0
                : values.fold<int>(0, (n, p) => n + p.length);
            var index = 0;
            final dualValues = <List<Dual>>[];
            for (final block in values) {
              final dualBlock = <Dual>[];
              for (final value in block) {
                dualBlock.add(jacobians == null
                    ? Dual.constant(value)
                    : Dual.variable(value, index++, dimension));
              }
              dualValues.add(dualBlock);
            }
            final result = evaluate(dualValues);
            if (result.length != residualCount) {
              throw StateError(
                  'Residual $id returned ${result.length} components; '
                  'expected $residualCount.');
            }
            for (var row = 0; row < residualCount; row++) {
              residuals[row] = result[row].value;
              if (jacobians != null) {
                if (result[row].derivatives.length != dimension) {
                  throw StateError(
                      'Residual $id returned a mismatched Dual dimension.');
                }
                var offset = 0;
                for (var block = 0; block < values.length; block++) {
                  for (var col = 0; col < values[block].length; col++) {
                    jacobians[block][row * values[block].length + col] =
                        result[row].derivatives[offset++];
                  }
                }
              }
            }
          });

  final String id;
  final List<String> parameterIds;
  final int residualCount;
  final GeometryResidualEvaluator evaluate;
  final List<double> tolerances;
  final List<double> scales;
}

class GeometryModel {
  GeometryModel({
    required Iterable<GeometryParameterBlock> parameters,
    required Iterable<GeometryResidualBlock> constraints,
  })  : parameters = List<GeometryParameterBlock>.unmodifiable(parameters),
        constraints = List<GeometryResidualBlock>.unmodifiable(constraints);
  final List<GeometryParameterBlock> parameters;
  final List<GeometryResidualBlock> constraints;
  // Compilation builds a dependency graph rather than merely converting data.
  // ignore: use_to_and_as_if_applicable
  CompiledGeometryModel compile() => CompiledGeometryModel._(this);
}

/// Immutable dependency graph and sparse patterns shared by independent
/// sessions. Structural edits require compiling a new model.
class CompiledGeometryModel {
  CompiledGeometryModel._(GeometryModel model)
      : parameters = model.parameters,
        constraints = model.constraints {
    for (var i = 0; i < parameters.length; i++) {
      if (_parameterIndex.containsKey(parameters[i].id)) {
        throw ArgumentError('Duplicate parameter ${parameters[i].id}.');
      }
      _parameterIndex[parameters[i].id] = i;
    }
    final parents = List<int>.generate(parameters.length, (i) => i);
    int find(int i) {
      while (parents[i] != i) {
        parents[i] = parents[parents[i]];
        i = parents[i];
      }
      return i;
    }

    final dependencies = <List<int>>[];
    for (var ci = 0; ci < constraints.length; ci++) {
      final constraint = constraints[ci];
      if (_constraintIndex.containsKey(constraint.id)) {
        throw ArgumentError('Duplicate constraint ${constraint.id}.');
      }
      _constraintIndex[constraint.id] = ci;
      final dep = <int>[];
      for (final id in constraint.parameterIds) {
        final index = _parameterIndex[id];
        if (index == null) throw ArgumentError('Unknown parameter $id.');
        dep.add(index);
      }
      dependencies.add(dep);
      final active = dep.where((i) => !parameters[i].fixed).toList();
      for (var i = 1; i < active.length; i++) {
        parents[find(active[i])] = find(active[0]);
      }
    }
    final activeByRoot = <int, List<int>>{};
    for (var i = 0; i < parameters.length; i++) {
      if (!parameters[i].fixed) {
        activeByRoot.putIfAbsent(find(i), () => <int>[]).add(i);
      }
    }
    final constraintsByRoot = <int, List<int>>{};
    for (var ci = 0; ci < constraints.length; ci++) {
      final active = dependencies[ci].where((i) => !parameters[i].fixed);
      final root = active.isEmpty ? -1 : find(active.first);
      constraintsByRoot.putIfAbsent(root, () => <int>[]).add(ci);
    }
    final roots = {...activeByRoot.keys, ...constraintsByRoot.keys};
    for (final root in roots) {
      final component = _Component(
          _components.length,
          this,
          activeByRoot[root] ?? const [],
          constraintsByRoot[root] ?? const [],
          dependencies);
      _components.add(component);
      for (final pi in component.activeParameters) {
        _parameterComponents.putIfAbsent(pi, () => <int>{}).add(component.id);
      }
      for (final layout in component.layouts) {
        _constraintComponent[layout.constraint] = component.id;
        for (final pi in layout.parameters) {
          _parameterComponents.putIfAbsent(pi, () => <int>{}).add(component.id);
        }
      }
    }
  }
  final List<GeometryParameterBlock> parameters;
  final List<GeometryResidualBlock> constraints;
  final Map<String, int> _parameterIndex = {};
  final Map<String, int> _constraintIndex = {};
  final Map<int, Set<int>> _parameterComponents = {};
  final Map<int, int> _constraintComponent = {};
  final List<_Component> _components = [];
  int get componentCount => _components.length;
  int get activeTangentDimension =>
      _components.fold(0, (sum, c) => sum + c.columns);
  int get jacobianNonzeros =>
      _components.fold(0, (sum, c) => sum + c.columnIndices.length);
  GeometrySolveSession createSession(
          {Map<String, List<double>>? initialValues}) =>
      GeometrySolveSession._(this, initialValues);
}

enum GeometrySolveStatus {
  satisfied,
  iterationLimit,
  cancelled,
  deadlineExceeded,
  stalled,
  numericalFailure,
  staleRevision,
}

class GeometrySolveOptions {
  const GeometrySolveOptions({
    this.maxIterations = 100,
    this.maxLinearIterations = 1000,
    this.initialDamping = 1e-3,
    this.linearTolerance = 1e-8,
    this.gradientTolerance = 1e-14,
    this.stepTolerance = 1e-14,
    this.rankTolerance = 1e-10,
    this.rankParameterLimit = 96,
    this.rankEntryLimit = 262144,
  });
  final int maxIterations;
  final int maxLinearIterations;
  final double initialDamping;
  final double linearTolerance;
  final double gradientTolerance;
  final double stepTolerance;
  final double rankTolerance;
  final int rankParameterLimit;
  final int rankEntryLimit;
  void _validate() {
    if (maxIterations < 0 ||
        maxLinearIterations < 0 ||
        rankParameterLimit < 0 ||
        rankEntryLimit < 0 ||
        !initialDamping.isFinite ||
        initialDamping <= 0 ||
        !linearTolerance.isFinite ||
        linearTolerance <= 0 ||
        !gradientTolerance.isFinite ||
        gradientTolerance < 0 ||
        !stepTolerance.isFinite ||
        stepTolerance < 0 ||
        !rankTolerance.isFinite ||
        rankTolerance <= 0) {
      throw ArgumentError('Invalid geometric solve options.');
    }
  }
}

class GeometryComponentDiagnostics {
  GeometryComponentDiagnostics({
    required this.component,
    required this.parameterIds,
    required this.constraintIds,
    required this.tangentDimension,
    required this.equationCount,
    required this.numericalRank,
    required this.locallyDependentConstraintIds,
    required this.maxToleranceRatio,
  });
  final int component;
  final List<String> parameterIds;
  final List<String> constraintIds;
  final int tangentDimension;
  final int equationCount;

  /// Null when the component exceeds the bounded diagnostic size or its
  /// derivative is undefined. Local numerical rank is not a consistency proof.
  final int? numericalRank;

  /// Infinitesimal freedoms of the equality equations in tangent coordinates.
  /// This excludes fixed blocks but does not classify one-sided mobility at
  /// active coordinate bounds, or higher-order mobility at singularities.
  int? get localDegreesOfFreedom =>
      numericalRank == null ? null : tangentDimension - numericalRank!;
  int? get dependentEquationCount =>
      numericalRank == null ? null : equationCount - numericalRank!;

  /// Whole residual blocks dependent on other rows *at this configuration*.
  /// Singular geometry can cause local dependency without a redundant equation
  /// globally. This list is therefore not an instruction to remove constraints.
  final List<String> locallyDependentConstraintIds;
  final double maxToleranceRatio;
}

class GeometrySolveStats {
  GeometrySolveStats({
    required this.residualEvaluations,
    required this.jacobianEvaluations,
    required this.linearSolves,
    required this.linearIterations,
    required this.nonlinearIterations,
    required this.componentsSolved,
    required this.componentsReused,
    required this.jacobianNonzeros,
    required this.elapsed,
  });
  final int residualEvaluations;
  final int jacobianEvaluations;
  final int linearSolves;
  final int linearIterations;
  final int nonlinearIterations;
  final int componentsSolved;
  final int componentsReused;
  final int jacobianNonzeros;
  final Duration elapsed;
}

class GeometrySolveResult {
  GeometrySolveResult._({
    required this.status,
    required this.revision,
    required this.values,
    required this.constraintResiduals,
    required this.components,
    required this.stats,
    this.message,
  });
  final GeometrySolveStatus status;
  final int revision;

  /// Candidate coordinates. Only [isSuccess] results have satisfied all
  /// required equations; a failed candidate is never committed by the session.
  final Map<String, List<double>> values;

  /// Original, unscaled residuals. On an interrupted run this map contains only
  /// evaluated or previously validated components, not guessed zero residuals.
  final Map<String, List<double>> constraintResiduals;
  final List<GeometryComponentDiagnostics> components;
  final GeometrySolveStats stats;
  final String? message;
  bool get isSuccess => status == GeometrySolveStatus.satisfied;
  int? get localDegreesOfFreedom {
    var sum = 0;
    for (final component in components) {
      final count = component.localDegreesOfFreedom;
      if (count == null) return null;
      sum += count;
    }
    return isSuccess ? sum : null;
  }

  double get maxToleranceRatio => components.isEmpty
      ? 0
      : components.map((c) => c.maxToleranceRatio).reduce(math.max);
}

/// Persistent numeric state over a compiled graph. Values, buffers, sparse
/// patterns and independent-component validation are reused between edits.
class GeometrySolveSession {
  GeometrySolveSession._(this.model, Map<String, List<double>>? initialValues) {
    _pending = [
      for (final p in model.parameters) Float64List.fromList(p.values)
    ];
    _dirty.addAll(List<int>.generate(model.componentCount, (i) => i));
    _workspaces = [for (final c in model._components) _Workspace(c, model)];
    if (initialValues != null) {
      for (final entry in initialValues.entries) {
        setParameterValues(entry.key, entry.value);
      }
    }
  }
  final CompiledGeometryModel model;
  late List<Float64List> _pending;
  List<Float64List>? _committed;
  late final List<_Workspace> _workspaces;
  final Set<int> _dirty = {};
  final Map<int, GeometryComponentDiagnostics> _diagnostics = {};
  int _revision = 0;
  bool _running = false;
  GeometrySolveResult? _lastResult;
  int get revision => _revision;
  int get dirtyComponentCount => _dirty.length;
  GeometrySolveResult? get lastResult => _lastResult;
  Map<String, List<double>>? get committedValues =>
      _committed == null ? null : _snapshot(model, _committed!);
  Map<String, List<double>> get values =>
      _snapshot(model, _committed ?? _pending);
  Map<String, List<double>> get pendingValues => _snapshot(model, _pending);

  /// Last committed coordinates, or the initial guess before the first success.
  List<double> parameterValues(String id) {
    final pi = model._parameterIndex[id];
    if (pi == null) throw ArgumentError('Unknown parameter $id.');
    return List<double>.unmodifiable((_committed ?? _pending)[pi]);
  }

  void setParameterValues(String id, List<double> values) {
    final pi = model._parameterIndex[id];
    if (pi == null) throw ArgumentError('Unknown parameter $id.');
    model.parameters[pi]._validate(values);
    if (_sameValues(_pending[pi], values)) return;
    _pending[pi].setAll(0, values);
    _dirty.addAll(model._parameterComponents[pi] ?? const <int>{});
    _revision++;
  }

  /// Notify the session when a callback's captured input changes. Fixed input
  /// blocks are preferable because they provide automatic dependency tracking.
  void invalidateConstraint(String id) {
    final ci = model._constraintIndex[id];
    if (ci == null) throw ArgumentError('Unknown constraint $id.');
    _dirty.add(model._constraintComponent[ci]!);
    _revision++;
  }

  void markAllDirty() {
    _dirty.addAll(List<int>.generate(model.componentCount, (i) => i));
    _revision++;
  }

  /// Discard pending coordinate edits. Captured external callback state cannot
  /// be rolled back; restore that state separately and invalidate its constraints.
  void restoreLastValid() {
    if (_committed != null) {
      _pending = _copyValues(_committed!);
      markAllDirty();
    }
  }

  GeometrySolveResult solve({
    GeometrySolveOptions options = const GeometrySolveOptions(),
    GeometryLinearSolver linearSolver = const AdaptiveGeometryLinearSolver(),
    bool Function()? shouldCancel,
    Duration? timeLimit,
    int? expectedRevision,
  }) {
    final run = _begin(
        options, linearSolver, shouldCancel, timeLimit, expectedRevision);
    try {
      for (final _ in run.steps()) {/* drive the same bounded-step engine */}
      return run.result!;
    } finally {
      _running = false;
    }
  }

  /// Cooperatively yields between nonlinear iterations and component updates.
  /// A residual callback and a linear backend step are synchronous; their inner
  /// loops must be bounded or poll the supplied stop callback. Event-loop edits
  /// invalidate the captured revision and cannot be overwritten by this run.
  Future<GeometrySolveResult> solveAsync({
    GeometrySolveOptions options = const GeometrySolveOptions(),
    GeometryLinearSolver linearSolver = const AdaptiveGeometryLinearSolver(),
    bool Function()? shouldCancel,
    Duration? timeLimit,
    int? expectedRevision,
  }) async {
    final run = _begin(
        options, linearSolver, shouldCancel, timeLimit, expectedRevision);
    try {
      for (final _ in run.steps()) {
        await Future<void>.delayed(Duration.zero);
      }
      return run.result!;
    } finally {
      _running = false;
    }
  }

  _SolveRun _begin(GeometrySolveOptions options, GeometryLinearSolver backend,
      bool Function()? cancel, Duration? limit, int? expected) {
    if (_running) throw StateError('This session already has an active solve.');
    options._validate();
    if (limit != null && limit.isNegative) {
      throw ArgumentError('Negative time limit.');
    }
    _running = true;
    return _SolveRun(
        this, options, backend, cancel, limit, expected ?? revision);
  }
}

Map<String, List<double>> _snapshot(
        CompiledGeometryModel model, List<Float64List> values) =>
    Map<String, List<double>>.unmodifiable({
      for (var i = 0; i < model.parameters.length; i++)
        model.parameters[i].id: List<double>.unmodifiable(values[i]),
    });
List<Float64List> _copyValues(List<Float64List> values) =>
    [for (final p in values) Float64List.fromList(p)];
bool _sameValues(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _ResidualLayout {
  _ResidualLayout(
      this.constraint, this.parameters, this.rowOffset, this.entryOffsets);
  final int constraint;
  final List<int> parameters;
  final int rowOffset;
  final List<int> entryOffsets;
}

class _Component {
  _Component(this.id, CompiledGeometryModel model, this.activeParameters,
      List<int> constraints, List<List<int>> dependencies) {
    for (final pi in activeParameters) {
      tangentOffsets[pi] = columns;
      columns += model.parameters[pi].manifold.tangentSize;
    }
    final rowPattern = <int>[0];
    final indices = <int>[];
    for (final ci in constraints) {
      final dep = dependencies[ci];
      final local = <int>[];
      final offsets = <int>[];
      for (final pi in dep) {
        final start = tangentOffsets[pi];
        offsets.add(start == null ? -1 : local.length);
        if (start != null) {
          for (var i = 0; i < model.parameters[pi].manifold.tangentSize; i++) {
            local.add(start + i);
          }
        }
      }
      layouts.add(_ResidualLayout(ci, dep, rows, offsets));
      for (var row = 0; row < model.constraints[ci].residualCount; row++) {
        indices.addAll(local);
        rowPattern.add(indices.length);
        rows++;
      }
    }
    rowOffsets = Int32List.fromList(rowPattern);
    columnIndices = Int32List.fromList(indices);
  }
  final int id;
  final List<int> activeParameters;
  final Map<int, int> tangentOffsets = {};
  final List<_ResidualLayout> layouts = [];
  int columns = 0;
  int rows = 0;
  late final Int32List rowOffsets;
  late final Int32List columnIndices;
}

class _Workspace {
  _Workspace(this.component, CompiledGeometryModel model)
      : raw = Float64List(component.rows),
        normalized = Float64List(component.rows),
        trialRaw = Float64List(component.rows),
        trialNormalized = Float64List(component.rows),
        diagonal = Float64List(component.columns),
        gradient = Float64List(component.columns),
        actualStep = Float64List(component.columns),
        jStep = Float64List(component.rows),
        jacobian = SparseGeometryJacobian(
            rows: component.rows,
            columns: component.columns,
            rowOffsets: component.rowOffsets,
            columnIndices: component.columnIndices,
            values: Float64List(component.columnIndices.length)) {
    for (final pi in component.activeParameters) {
      final p = model.parameters[pi];
      plusJacobians[pi] =
          Float64List(p.manifold.ambientSize * p.manifold.tangentSize);
      deltas[pi] = Float64List(p.manifold.tangentSize);
      trialValues[pi] = Float64List(p.manifold.ambientSize);
    }
    for (final layout in component.layouts) {
      arguments.add([
        for (final pi in layout.parameters)
          Float64List(model.parameters[pi].manifold.ambientSize)
      ]);
      ambientJacobians.add([
        for (final pi in layout.parameters)
          Float64List(model.parameters[pi].manifold.ambientSize *
              model.constraints[layout.constraint].residualCount)
      ]);
      residualBuffers
          .add(Float64List(model.constraints[layout.constraint].residualCount));
    }
  }
  final _Component component;
  final SparseGeometryJacobian jacobian;
  final Float64List raw, normalized, trialRaw, trialNormalized;
  final Float64List diagonal, gradient, actualStep, jStep;
  final Map<int, Float64List> plusJacobians = {}, deltas = {}, trialValues = {};
  final List<List<Float64List>> arguments = [], ambientJacobians = [];
  final List<Float64List> residualBuffers = [];
  bool evaluated = false;
}

class _SolveRun {
  _SolveRun(this.session, this.options, this.backend, this.shouldCancel,
      this.timeLimit, this.revision)
      : work = _copyValues(session._pending),
        dirty = Set<int>.from(session._dirty),
        watch = Stopwatch()..start();
  final GeometrySolveSession session;
  CompiledGeometryModel get model => session.model;
  final GeometrySolveOptions options;
  final GeometryLinearSolver backend;
  final bool Function()? shouldCancel;
  final Duration? timeLimit;
  final int revision;
  final List<Float64List> work;
  final Set<int> dirty;
  final Stopwatch watch;
  final List<GeometryComponentDiagnostics> diagnostics = [];
  final Set<int> reported = {};
  GeometrySolveResult? result;
  String? evaluationError;
  int residualEvaluations = 0, jacobianEvaluations = 0, linearSolves = 0;
  int linearIterations = 0, iterations = 0, solved = 0, reused = 0;

  GeometrySolveStatus? _stopStatus() {
    if (session.revision != revision) return GeometrySolveStatus.staleRevision;
    final cancelled = shouldCancel?.call() ?? false;
    // Callbacks are user code and can themselves edit a session.
    if (session.revision != revision) return GeometrySolveStatus.staleRevision;
    if (cancelled) return GeometrySolveStatus.cancelled;
    if (timeLimit != null && watch.elapsed >= timeLimit!) {
      return GeometrySolveStatus.deadlineExceeded;
    }
    return null;
  }

  bool _stop() => _stopStatus() != null;

  Iterable<int> steps() sync* {
    var stop = _stopStatus();
    if (stop != null) {
      _finish(stop);
      return;
    }
    for (final component in model._components) {
      final ws = session._workspaces[component.id];
      stop = _stopStatus();
      if (stop != null) {
        _finish(stop);
        return;
      }
      if (!dirty.contains(component.id) &&
          session._diagnostics.containsKey(component.id)) {
        diagnostics.add(session._diagnostics[component.id]!);
        reported.add(component.id);
        reused++;
        continue;
      }
      solved++;
      if (!_evaluate(ws, work, derivatives: false)) {
        _finish(_stopStatus() ?? GeometrySolveStatus.numericalFailure,
            message: evaluationError);
        return;
      }
      reported.add(component.id);
      yield 0;
      var damping = options.initialDamping;
      var growth = 2.0;
      final trial = List<Float64List>.from(work);
      for (final pi in component.activeParameters) {
        trial[pi] = ws.trialValues[pi]!;
      }
      var failure = GeometrySolveStatus.iterationLimit;
      for (var it = 0; it < options.maxIterations && !_satisfied(ws); it++) {
        stop = _stopStatus();
        if (stop != null) {
          _finish(stop);
          return;
        }
        if (component.columns == 0) {
          failure = GeometrySolveStatus.stalled;
          break;
        }
        if (!_evaluate(ws, work, derivatives: true)) {
          _finish(_stopStatus() ?? GeometrySolveStatus.numericalFailure,
              message: evaluationError);
          return;
        }
        iterations++;
        ws.jacobian.transposeMultiply(ws.normalized, ws.gradient);
        ws.jacobian.normalDiagonal(ws.diagonal);
        var maxGradient = 0.0;
        var dampingScale = 1e-12;
        for (var i = 0; i < component.columns; i++) {
          maxGradient = math.max(maxGradient, ws.gradient[i].abs());
          dampingScale = math.max(dampingScale, ws.diagonal[i]);
        }
        // Use one isotropic metric in the explicitly scaled tangent space.
        // Per-column J'J damping gives nearly free motion to a weakly observed
        // coordinate. In underconstrained geometry that can turn a radial drag
        // into huge tangential excursions, repeatedly shrinking the trust step.
        // Parameter.scales defines the desired coordinate metric; the common
        // magnitude merely makes initial damping relative to this Jacobian.
        ws.diagonal.fillRange(0, component.columns, dampingScale);
        final cost = 0.5 * geometryDot(ws.normalized, ws.normalized);
        if (!cost.isFinite ||
            !maxGradient.isFinite ||
            ws.diagonal.any((v) => !v.isFinite)) {
          failure = GeometrySolveStatus.numericalFailure;
          break;
        }
        if (maxGradient <= options.gradientTolerance) {
          failure = GeometrySolveStatus.stalled;
          break;
        }
        linearSolves++;
        final linear = backend.solve(ws.jacobian, ws.normalized,
            damping: damping,
            diagonal: ws.diagonal,
            maxIterations: options.maxLinearIterations,
            relativeTolerance: options.linearTolerance,
            shouldStop: _stop);
        linearIterations += linear.iterations;
        stop = _stopStatus();
        if (stop != null) {
          _finish(stop);
          return;
        }
        if (linear.status != GeometryLinearStatus.converged) {
          if (linear.status == GeometryLinearStatus.cancelled) {
            _finish(GeometrySolveStatus.cancelled);
            return;
          }
          damping *= growth;
          growth *= 2;
          failure = linear.status == GeometryLinearStatus.iterationLimit
              ? GeometrySolveStatus.iterationLimit
              : GeometrySolveStatus.numericalFailure;
          if (!damping.isFinite || damping > 1e30) break;
          yield 0;
          continue;
        }
        ws.actualStep.setAll(0, linear.step);
        var validTrial = true;
        for (final pi in component.activeParameters) {
          final parameter = model.parameters[pi];
          final offset = component.tangentOffsets[pi]!;
          final delta = ws.deltas[pi]!;
          for (var j = 0; j < delta.length; j++) {
            delta[j] = linear.step[offset + j] * parameter.scales[j];
          }
          parameter.manifold.plus(work[pi], delta, trial[pi]);
          if (parameter.manifold is EuclideanGeometryManifold) {
            for (var j = 0; j < trial[pi].length; j++) {
              trial[pi][j] = trial[pi][j]
                  .clamp(parameter.lowerBounds[j], parameter.upperBounds[j])
                  .toDouble();
              ws.actualStep[offset + j] =
                  (trial[pi][j] - work[pi][j]) / parameter.scales[j];
            }
          }
          validTrial &= parameter.manifold.isValid(trial[pi]);
        }
        if (geometryNorm(ws.actualStep) <= options.stepTolerance) {
          failure = GeometrySolveStatus.stalled;
          break;
        }
        var accepted = false;
        if (validTrial &&
            _evaluate(ws, trial, derivatives: false, trial: true)) {
          final trialCost =
              0.5 * geometryDot(ws.trialNormalized, ws.trialNormalized);
          ws.jacobian.multiply(ws.actualStep, ws.jStep);
          final predicted = -geometryDot(ws.gradient, ws.actualStep) -
              0.5 * geometryDot(ws.jStep, ws.jStep);
          final ratio = predicted > 0 ? (cost - trialCost) / predicted : -1.0;
          if (trialCost.isFinite &&
              ((_satisfied(ws, trial: true)) ||
                  (trialCost < cost && ratio > 1e-4))) {
            for (final pi in component.activeParameters) {
              work[pi].setAll(0, trial[pi]);
            }
            ws.raw.setAll(0, ws.trialRaw);
            ws.normalized.setAll(0, ws.trialNormalized);
            damping *= math.max(1 / 3, 1 - math.pow(2 * ratio - 1, 3));
            damping = damping.clamp(1e-15, 1e30).toDouble();
            growth = 2;
            accepted = true;
          }
        }
        stop = _stopStatus();
        if (stop != null) {
          _finish(stop);
          return;
        }
        if (!accepted) {
          damping *= growth;
          growth *= 2;
        }
        if (!damping.isFinite || damping > 1e30) {
          failure = GeometrySolveStatus.stalled;
          break;
        }
        yield 0;
      }
      if (!_satisfied(ws)) {
        diagnostics.add(_diagnose(ws, derivativesValid: false));
        _finish(failure,
            message: 'Required equations remain outside tolerance; '
                'local nonconvergence does not prove infeasibility.');
        return;
      }
      // Undefined derivatives do not invalidate an already verified root, but
      // rank is then unavailable. Original residual acceptance remains separate.
      final derivativeValid =
          component.columns == 0 || _evaluate(ws, work, derivatives: true);
      stop = _stopStatus();
      if (stop != null) {
        _finish(stop);
        return;
      }
      if (!_satisfied(ws)) {
        _finish(GeometrySolveStatus.numericalFailure,
            message: 'Residual callback changed during evaluation.');
        return;
      }
      diagnostics.add(_diagnose(ws, derivativesValid: derivativeValid));
      yield 0;
    }
    stop = _stopStatus();
    _finish(stop ?? GeometrySolveStatus.satisfied);
  }

  bool _evaluate(_Workspace ws, List<Float64List> values,
      {required bool derivatives, bool trial = false}) {
    final raw = trial ? ws.trialRaw : ws.raw;
    final normalized = trial ? ws.trialNormalized : ws.normalized;
    evaluationError = null;
    try {
      if (derivatives) {
        for (final pi in ws.component.activeParameters) {
          model.parameters[pi].manifold
              .plusJacobian(values[pi], ws.plusJacobians[pi]!);
        }
      }
      for (var li = 0; li < ws.component.layouts.length; li++) {
        if (_stop()) return false;
        final layout = ws.component.layouts[li];
        final constraint = model.constraints[layout.constraint];
        final arguments = ws.arguments[li];
        final ambient = ws.ambientJacobians[li];
        for (var p = 0; p < arguments.length; p++) {
          arguments[p] = values[layout.parameters[p]];
          if (derivatives) ambient[p].fillRange(0, ambient[p].length, 0);
        }
        final buffer = ws.residualBuffers[li];
        buffer.fillRange(0, buffer.length, double.nan);
        constraint.evaluate(arguments, buffer, derivatives ? ambient : null);
        residualEvaluations++;
        if (derivatives) jacobianEvaluations++;
        for (var row = 0; row < constraint.residualCount; row++) {
          final globalRow = layout.rowOffset + row;
          raw[globalRow] = buffer[row];
          normalized[globalRow] = buffer[row] / constraint.scales[row];
          if (!normalized[globalRow].isFinite) {
            evaluationError = 'Non-finite residual in ${constraint.id}.';
            return false;
          }
          if (!derivatives) continue;
          for (var p = 0; p < arguments.length; p++) {
            final pi = layout.parameters[p];
            final parameter = model.parameters[pi];
            if (parameter.fixed) continue;
            final plus = ws.plusJacobians[pi]!;
            final a = parameter.manifold.ambientSize;
            final t = parameter.manifold.tangentSize;
            for (var col = 0; col < t; col++) {
              var sum = 0.0;
              for (var k = 0; k < a; k++) {
                sum += ambient[p][row * a + k] * plus[k * t + col];
              }
              final value =
                  sum * parameter.scales[col] / constraint.scales[row];
              if (!value.isFinite) {
                evaluationError = 'Non-finite Jacobian in ${constraint.id}.';
                return false;
              }
              ws.jacobian.values[ws.jacobian.rowOffsets[globalRow] +
                  layout.entryOffsets[p] +
                  col] = value;
            }
          }
        }
      }
      if (!trial) ws.evaluated = true;
      return true;
    } catch (error) {
      evaluationError = 'Residual evaluation failed: $error';
      return false;
    }
  }

  double _maxRatio(_Workspace ws, {bool trial = false}) {
    final raw = trial ? ws.trialRaw : ws.raw;
    var ratio = 0.0;
    for (final layout in ws.component.layouts) {
      final c = model.constraints[layout.constraint];
      for (var row = 0; row < c.residualCount; row++) {
        final value = raw[layout.rowOffset + row].abs() / c.tolerances[row];
        if (!value.isFinite) return double.infinity;
        ratio = math.max(ratio, value);
      }
    }
    return ratio;
  }

  bool _satisfied(_Workspace ws, {bool trial = false}) =>
      _maxRatio(ws, trial: trial) <= 1;

  GeometryComponentDiagnostics _diagnose(_Workspace ws,
      {required bool derivativesValid}) {
    final component = ws.component;
    int? rank;
    final dependentIds = <String>[];
    if (component.columns == 0 || component.rows == 0) {
      rank = 0;
    } else if (derivativesValid &&
        component.columns <= options.rankParameterLimit &&
        component.rows * component.columns <= options.rankEntryLimit) {
      final dense = ws.jacobian.toDense();
      final info = geometryRank(dense, component.rows, component.columns,
          relativeTolerance: options.rankTolerance, shouldStop: _stop);
      rank = info?.rank;
      if (rank != null && component.rows > rank) {
        final transpose = Float64List(dense.length);
        for (var row = 0; row < component.rows; row++) {
          for (var col = 0; col < component.columns; col++) {
            transpose[col * component.rows + row] =
                dense[row * component.columns + col];
          }
        }
        final rowRank = geometryRank(
            transpose, component.columns, component.rows,
            relativeTolerance: options.rankTolerance, shouldStop: _stop);
        if (rowRank != null && rowRank.rank == rank) {
          final independent = rowRank.independentColumns.toSet();
          for (final layout in component.layouts) {
            final c = model.constraints[layout.constraint];
            var allDependent = true;
            for (var row = 0; row < c.residualCount; row++) {
              allDependent &= !independent.contains(layout.rowOffset + row);
            }
            if (allDependent) dependentIds.add(c.id);
          }
        }
      }
    }
    return GeometryComponentDiagnostics(
        component: component.id,
        parameterIds: List<String>.unmodifiable(
            component.activeParameters.map((i) => model.parameters[i].id)),
        constraintIds: List<String>.unmodifiable(
            component.layouts.map((l) => model.constraints[l.constraint].id)),
        tangentDimension: component.columns,
        equationCount: component.rows,
        numericalRank: rank,
        locallyDependentConstraintIds: List<String>.unmodifiable(dependentIds),
        maxToleranceRatio: _maxRatio(ws));
  }

  void _finish(GeometrySolveStatus status, {String? message}) {
    if (session.revision != revision) {
      status = GeometrySolveStatus.staleRevision;
    }
    watch.stop();
    final residuals = <String, List<double>>{};
    for (final component in model._components) {
      if (!reported.contains(component.id)) continue;
      final ws = session._workspaces[component.id];
      for (final layout in component.layouts) {
        final c = model.constraints[layout.constraint];
        residuals[c.id] = List<double>.unmodifiable(ws.raw
            .sublist(layout.rowOffset, layout.rowOffset + c.residualCount));
      }
    }
    result = GeometrySolveResult._(
        status: status,
        revision: revision,
        values: _snapshot(model, work),
        constraintResiduals: Map.unmodifiable(residuals),
        components:
            List<GeometryComponentDiagnostics>.unmodifiable(diagnostics),
        stats: GeometrySolveStats(
            residualEvaluations: residualEvaluations,
            jacobianEvaluations: jacobianEvaluations,
            linearSolves: linearSolves,
            linearIterations: linearIterations,
            nonlinearIterations: iterations,
            componentsSolved: solved,
            componentsReused: reused,
            jacobianNonzeros: model.jacobianNonzeros,
            elapsed: watch.elapsed),
        message: message);
    // A later revision owns pending values; never overwrite it with stale work.
    if (session.revision != revision) return;
    session._lastResult = result;
    if (status == GeometrySolveStatus.satisfied) {
      session._committed = _copyValues(work);
      session._pending = _copyValues(work);
      session._dirty.removeAll(dirty);
      for (final diagnostic in diagnostics) {
        session._diagnostics[diagnostic.component] = diagnostic;
      }
    } else if (session._committed != null) {
      // Coordinate state is atomic, including fixed dimension inputs.
      session._pending = _copyValues(session._committed!);
      // Workspaces of changed components may contain a failed candidate.
      session._dirty.addAll(dirty);
    }
  }
}

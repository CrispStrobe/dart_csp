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

// Only library-created defaults may bypass the ambient-to-tangent product.
// Public Euclidean manifolds remain extensible, including callback side effects.
final class _DefaultEuclideanGeometryManifold
    extends EuclideanGeometryManifold {
  const _DefaultEuclideanGeometryManifold(super.ambientSize);
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
        manifold = manifold ?? _DefaultEuclideanGeometryManifold(values.length),
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

  /// Differentiate the expression in its active local ambient coordinates.
  /// Compiled solves treat fixed dependencies as constants. Expressions should
  /// compose the supplied [Dual] values rather than assume a derivative-vector
  /// size; direct calls to [evaluate] still return every ambient Jacobian block.
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
      _AutoDiffGeometryResidualBlock(
          id: id,
          parameterIds: parameterIds,
          residualCount: residualCount,
          tolerance: tolerance,
          scale: scale,
          tolerances: tolerances,
          scales: scales,
          expression: evaluate);

  final String id;
  final List<String> parameterIds;
  final int residualCount;
  final GeometryResidualEvaluator evaluate;
  final List<double> tolerances;
  final List<double> scales;
}

final class _AutoDiffGeometryResidualBlock extends GeometryResidualBlock {
  _AutoDiffGeometryResidualBlock({
    required super.id,
    required super.parameterIds,
    required super.residualCount,
    required this.expression,
    required super.tolerance,
    required super.scale,
    super.tolerances,
    super.scales,
  }) : super(evaluate: (values, residuals, jacobians) {
          // Direct users of evaluate still receive all ambient derivatives.
          _evaluateAutoDiff(
              id, residualCount, expression, values, residuals, jacobians);
        });

  final GeometryAutoDiffEvaluator expression;
}

void _evaluateAutoDiff(
    String id,
    int residualCount,
    GeometryAutoDiffEvaluator evaluate,
    List<Float64List> values,
    Float64List residuals,
    List<Float64List>? jacobians,
    {List<int>? activeOffsets,
    int? activeDimension}) {
  final dimension = jacobians == null
      ? 0
      : activeDimension ?? values.fold<int>(0, (n, p) => n + p.length);
  var nextOffset = 0;
  final dualValues = <List<Dual>>[];
  for (var block = 0; block < values.length; block++) {
    final offset = activeOffsets?[block] ?? nextOffset;
    dualValues.add([
      for (var col = 0; col < values[block].length; col++)
        if (jacobians == null || offset < 0)
          Dual.constant(values[block][col], dimension)
        else
          Dual.variable(values[block][col], offset + col, dimension),
    ]);
    nextOffset += values[block].length;
  }
  final result = evaluate(dualValues);
  if (result.length != residualCount) {
    throw StateError('Residual $id returned ${result.length} components; '
        'expected $residualCount.');
  }
  for (var row = 0; row < residualCount; row++) {
    residuals[row] = result[row].value;
    if (jacobians == null) continue;
    if (result[row].derivatives.length != dimension) {
      throw StateError('Residual $id returned a mismatched Dual dimension.');
    }
    var nextOffset = 0;
    for (var block = 0; block < values.length; block++) {
      final offset = activeOffsets?[block] ?? nextOffset;
      nextOffset += values[block].length;
      if (offset < 0) continue;
      for (var col = 0; col < values[block].length; col++) {
        jacobians[block][row * values[block].length + col] =
            result[row].derivatives[offset + col];
      }
    }
  }
}

class GeometryModel {
  GeometryModel({
    required Iterable<GeometryParameterBlock> parameters,
    required Iterable<GeometryResidualBlock> constraints,
  })  : parameters = List<GeometryParameterBlock>.unmodifiable(parameters),
        constraints = List<GeometryResidualBlock>.unmodifiable(constraints);
  final List<GeometryParameterBlock> parameters;
  final List<GeometryResidualBlock> constraints;

  /// Capture declaration metadata and validate it before compiling the graph.
  /// Later changes to subclass getters or caller-owned lists require a new
  /// compilation. Evaluator callbacks and custom manifolds remain shared;
  /// their captured state still requires explicit session invalidation, and
  /// manifold dimensions must stay fixed throughout the compiled model's life.
  // Compilation builds a dependency graph rather than merely converting data.
  // ignore: use_to_and_as_if_applicable
  CompiledGeometryModel compile() => CompiledGeometryModel._(this);
}

GeometryParameterBlock _captureParameter(GeometryParameterBlock parameter) =>
    GeometryParameterBlock(
      id: parameter.id,
      values: parameter.values,
      fixed: parameter.fixed,
      lowerBounds: parameter.lowerBounds,
      upperBounds: parameter.upperBounds,
      scales: parameter.scales,
      manifold: parameter.manifold,
    );

GeometryResidualBlock _captureConstraint(GeometryResidualBlock constraint) {
  // This private implementation owns immutable declaration metadata. Retain its
  // specialized active-coordinate AD dispatch as well as its public evaluator.
  if (constraint is _AutoDiffGeometryResidualBlock) return constraint;
  return GeometryResidualBlock(
    id: constraint.id,
    parameterIds: constraint.parameterIds,
    residualCount: constraint.residualCount,
    evaluate: constraint.evaluate,
    tolerances: constraint.tolerances,
    scales: constraint.scales,
  );
}

/// Immutable dependency graph and sparse patterns shared by independent
/// sessions. Structural edits require compiling a new model.
class CompiledGeometryModel {
  CompiledGeometryModel._(GeometryModel model)
      : parameters = List.unmodifiable(model.parameters.map(_captureParameter)),
        constraints =
            List.unmodifiable(model.constraints.map(_captureConstraint)) {
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

/// A soft coordinate target. Its objective is
/// `weight / 2 * sum(((value - target) / coordinateScale)^2)`.
/// Targets never become required geometric equations. Quaternion targets use
/// the equivalent quaternion sign closest to the feasible starting orientation;
/// their coordinate distance is a chord distance, not an angle in radians.
class GeometryParameterTarget {
  GeometryParameterTarget({
    required this.parameterId,
    required List<double> values,
    this.weight = 1,
    List<double>? coordinateScales,
  })  : values = List<double>.unmodifiable(values),
        coordinateScales = List<double>.unmodifiable(
            coordinateScales ?? List<double>.filled(values.length, 1)) {
    if (parameterId.isEmpty ||
        values.isEmpty ||
        values.any((v) => !v.isFinite) ||
        !weight.isFinite ||
        weight <= 0 ||
        this.coordinateScales.length != values.length ||
        this.coordinateScales.any((v) => !v.isFinite || v <= 0)) {
      throw ArgumentError('Invalid geometric preference target.');
    }
  }
  final String parameterId;
  final List<double> values;
  final double weight;
  final List<double> coordinateScales;
}

class GeometryPreferenceOptions {
  const GeometryPreferenceOptions({
    this.maxIterations = 64,
    this.maxBacktrackingSteps = 16,
    this.maxProjectionIterations = 30,
    this.maxLinearIterations = 1000,
    this.gradientTolerance = 1e-8,
    this.targetTolerance = 1e-7,
    this.projectionTolerance = 1e-10,
    this.maxTangentStep = double.infinity,
  });
  final int maxIterations;
  final int maxBacktrackingSteps;
  final int maxProjectionIterations;
  final int maxLinearIterations;
  final double gradientTolerance;
  final double targetTolerance;
  final double projectionTolerance;
  final double maxTangentStep;
  void _validate() {
    if (maxIterations < 0 ||
        maxBacktrackingSteps < 1 ||
        maxProjectionIterations < 0 ||
        maxLinearIterations < 0 ||
        !gradientTolerance.isFinite ||
        gradientTolerance <= 0 ||
        !targetTolerance.isFinite ||
        targetTolerance <= 0 ||
        !projectionTolerance.isFinite ||
        projectionTolerance <= 0 ||
        maxTangentStep.isNaN ||
        maxTangentStep <= 0) {
      throw ArgumentError('Invalid geometric preference options.');
    }
  }
}

enum GeometryPreferenceStatus {
  targetReached,
  stationary,
  noProgress,
  iterationLimit,
  cancelled,
  deadlineExceeded,
  numericalFailure,
  staleRevision,
}

class GeometryPreferenceReport {
  GeometryPreferenceReport({
    required this.status,
    required this.initialCost,
    required this.finalCost,
    required this.maxTargetError,
    required this.iterations,
    required this.acceptedSteps,
    required this.feasibilityProjections,
  });
  final GeometryPreferenceStatus status;
  final double initialCost;
  final double finalCost;

  /// Largest coordinate-scale-normalized target distance, without weights.
  final double maxTargetError;
  final int iterations;
  final int acceptedSteps;
  final int feasibilityProjections;
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
    this.autoDiffDerivativeCoordinates = 0,
    this.rankFactorizations = 0,
    this.rankReuses = 0,
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

  /// Active ambient coordinates seeded across automatic derivative evaluations.
  /// Fixed inputs and residual-only evaluations contribute no coordinates.
  final int autoDiffDerivativeCoordinates;

  /// Rank QR factorizations attempted, including transpose factorizations used
  /// to identify locally dependent residual blocks.
  final int rankFactorizations;

  /// Component diagnostics reused after an exact numerical Jacobian and rank
  /// option comparison. Residual tolerances are always checked again.
  final int rankReuses;
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
    this.preferenceReport,
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
  final GeometryPreferenceReport? preferenceReport;
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

  GeometrySolveSession._fork(GeometrySolveSession source)
      : model = source.model,
        _revision = source._revision,
        _diagnosticOptions = source._diagnosticOptions,
        _lastResult = source._lastResult {
    _pending = _copyValues(source._pending);
    _committed =
        source._committed == null ? null : _copyValues(source._committed!);
    _dirty.addAll(source._dirty);
    _diagnostics.addAll(source._diagnostics);
    _workspaces = [
      for (final workspace in source._workspaces)
        _Workspace.fork(workspace, model),
    ];
  }
  final CompiledGeometryModel model;
  late List<Float64List> _pending;
  List<Float64List>? _committed;
  late final List<_Workspace> _workspaces;
  final Set<int> _dirty = {};
  final Map<int, GeometryComponentDiagnostics> _diagnostics = {};
  GeometrySolveOptions? _diagnosticOptions;
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

  /// Create an independent candidate with the same pending and committed
  /// coordinates, dirty components, revision and retained diagnostics.
  ///
  /// Writable values and work buffers belong to the new session. Immutable
  /// compiled structure, result snapshots and exact-Jacobian rank caches are
  /// shared. Neither later edits nor failed solves can change the other session.
  /// Scratch buffers are allocated when a component first needs evaluation or
  /// a preference step; reusing a clean component does not allocate its scratch.
  /// Forking during a synchronous callback or an active asynchronous solve is
  /// rejected, because that workspace may contain a partially evaluated trial.
  ///
  /// Residual callbacks and custom manifolds remain part of the shared model;
  /// captured application state is not cloned. After changing that state, call
  /// [invalidateConstraint] or [markAllDirty] on each affected session.
  GeometrySolveSession fork() {
    if (_running) {
      throw StateError('Cannot fork a session during an active solve.');
    }
    return GeometrySolveSession._fork(this);
  }

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

  /// Satisfy all required equations, then improve optional coordinate targets
  /// within their local feasible tangent spaces. Every accepted preference
  /// step is reprojected and revalidated against the original hard tolerances.
  /// A stationary soft target may remain unmet; inspect [GeometrySolveResult.preferenceReport].
  /// Limits, cancellation and numerical failures leave the last commit intact.
  /// Numerical solve options, preference options and target definitions are
  /// captured when the run begins, including values exposed by subclasses.
  GeometrySolveResult solve({
    GeometrySolveOptions options = const GeometrySolveOptions(),
    GeometryLinearSolver linearSolver = const AdaptiveGeometryLinearSolver(),
    bool Function()? shouldCancel,
    Duration? timeLimit,
    int? expectedRevision,
    Iterable<GeometryParameterTarget> preferences = const [],
    GeometryPreferenceOptions preferenceOptions =
        const GeometryPreferenceOptions(),
  }) {
    final run = _begin(options, linearSolver, shouldCancel, timeLimit,
        expectedRevision, preferences, preferenceOptions);
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
    Iterable<GeometryParameterTarget> preferences = const [],
    GeometryPreferenceOptions preferenceOptions =
        const GeometryPreferenceOptions(),
  }) async {
    final run = _begin(options, linearSolver, shouldCancel, timeLimit,
        expectedRevision, preferences, preferenceOptions);
    try {
      for (final _ in run.steps()) {
        await Future<void>.delayed(Duration.zero);
      }
      return run.result!;
    } finally {
      _running = false;
    }
  }

  _SolveRun _begin(
      GeometrySolveOptions options,
      GeometryLinearSolver backend,
      bool Function()? cancel,
      Duration? limit,
      int? expected,
      Iterable<GeometryParameterTarget> preferences,
      GeometryPreferenceOptions preferenceOptions) {
    if (_running) throw StateError('This session already has an active solve.');
    // The public options class can be subclassed with mutable getters. Capture
    // the values both for the solve and for any retained diagnostic cache key.
    final solveOptions = GeometrySolveOptions(
      maxIterations: options.maxIterations,
      maxLinearIterations: options.maxLinearIterations,
      initialDamping: options.initialDamping,
      linearTolerance: options.linearTolerance,
      gradientTolerance: options.gradientTolerance,
      stepTolerance: options.stepTolerance,
      rankTolerance: options.rankTolerance,
      rankParameterLimit: options.rankParameterLimit,
      rankEntryLimit: options.rankEntryLimit,
    );
    solveOptions._validate();
    final capturedPreferenceOptions = GeometryPreferenceOptions(
      maxIterations: preferenceOptions.maxIterations,
      maxBacktrackingSteps: preferenceOptions.maxBacktrackingSteps,
      maxProjectionIterations: preferenceOptions.maxProjectionIterations,
      maxLinearIterations: preferenceOptions.maxLinearIterations,
      gradientTolerance: preferenceOptions.gradientTolerance,
      targetTolerance: preferenceOptions.targetTolerance,
      projectionTolerance: preferenceOptions.projectionTolerance,
      maxTangentStep: preferenceOptions.maxTangentStep,
    );
    capturedPreferenceOptions._validate();
    if (limit != null && limit.isNegative) {
      throw ArgumentError('Negative time limit.');
    }
    final targets = <_PreferenceTarget>[];
    for (final target in preferences) {
      // A caller may subclass a target with mutable getters or lists. Freeze
      // and revalidate its whole objective, not only the desired coordinates.
      final capturedTarget = GeometryParameterTarget(
        parameterId: target.parameterId,
        values: target.values,
        weight: target.weight,
        coordinateScales: target.coordinateScales,
      );
      final pi = model._parameterIndex[capturedTarget.parameterId];
      if (pi == null ||
          !model.parameters[pi].manifold
              .isValid(Float64List.fromList(capturedTarget.values))) {
        throw ArgumentError(
            'Invalid preference for ${capturedTarget.parameterId}.');
      }
      targets.add(_PreferenceTarget(pi, capturedTarget));
    }
    for (final target in targets) {
      if (!model.parameters[target.parameter].fixed) {
        _dirty.addAll(
            model._parameterComponents[target.parameter] ?? const <int>{});
      }
    }
    // Whole-component reuse must also honor changed diagnostic options. These
    // edits do not change coordinates, but the requested numerical rank may.
    final diagnosticOptions = _diagnosticOptions;
    if (diagnosticOptions != null &&
        !_sameRankOptions(diagnosticOptions, solveOptions)) {
      _dirty.addAll(List<int>.generate(model.componentCount, (i) => i));
    }
    _running = true;
    return _SolveRun(this, solveOptions, backend, cancel, limit,
        expected ?? revision, targets, capturedPreferenceOptions);
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

bool _sameRankOptions(GeometrySolveOptions a, GeometrySolveOptions b) =>
    a.rankTolerance == b.rankTolerance &&
    a.rankParameterLimit == b.rankParameterLimit &&
    a.rankEntryLimit == b.rankEntryLimit;

class _ResidualLayout {
  _ResidualLayout(
      this.constraint,
      this.parameters,
      this.rowOffset,
      this.entryOffsets,
      this.activeAmbientOffsets,
      this.activeAmbientDimension);
  final int constraint;
  final List<int> parameters;
  final int rowOffset;
  final List<int> entryOffsets;
  final List<int> activeAmbientOffsets;
  final int activeAmbientDimension;
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
      final ambientOffsets = <int>[];
      var ambientDimension = 0;
      for (final pi in dep) {
        final start = tangentOffsets[pi];
        offsets.add(start == null ? -1 : local.length);
        ambientOffsets.add(start == null ? -1 : ambientDimension);
        if (start != null) {
          ambientDimension += model.parameters[pi].manifold.ambientSize;
          for (var i = 0; i < model.parameters[pi].manifold.tangentSize; i++) {
            local.add(start + i);
          }
        }
      }
      layouts.add(_ResidualLayout(
          ci, dep, rows, offsets, ambientOffsets, ambientDimension));
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
  _Workspace(this.component, this._model)
      : raw = Float64List(component.rows),
        normalized = Float64List(component.rows);

  factory _Workspace.fork(_Workspace source, CompiledGeometryModel model) {
    // Clean components must retain their actual physical residuals, including
    // accepted nonzero residuals. Scratch belongs only to this workspace and
    // is allocated on first use, never copied or borrowed from the source.
    // _RankCache is privately owned and immutable after construction.
    final copy = _Workspace(source.component, model);
    copy.raw.setAll(0, source.raw);
    copy.normalized.setAll(0, source.normalized);
    copy.evaluated = source.evaluated;
    copy.rankCache = source.rankCache;
    return copy;
  }

  final _Component component;
  final CompiledGeometryModel _model;
  final Float64List raw, normalized;
  late final _WorkspaceScratch _scratch = _WorkspaceScratch(component, _model);
  SparseGeometryJacobian get jacobian => _scratch.jacobian;
  Float64List get trialRaw => _scratch.trialRaw;
  Float64List get trialNormalized => _scratch.trialNormalized;
  Float64List get diagonal => _scratch.diagonal;
  Float64List get gradient => _scratch.gradient;
  Float64List get actualStep => _scratch.actualStep;
  Float64List get jStep => _scratch.jStep;
  Map<int, Float64List> get plusJacobians => _scratch.plusJacobians;
  Map<int, Float64List> get deltas => _scratch.deltas;
  Map<int, Float64List> get trialValues => _scratch.trialValues;
  List<List<Float64List>> get arguments => _scratch.arguments;
  List<List<Float64List>> get ambientJacobians => _scratch.ambientJacobians;
  List<Float64List> get residualBuffers => _scratch.residualBuffers;
  _RankCache? rankCache;
  bool evaluated = false;
}

/// Writable numerical buffers needed only by evaluated components. Keeping
/// these separate lets retained clean components publish copied residuals and
/// immutable diagnostics without allocating Jacobians, argument copies or
/// trial steps. Each workspace creates its own instance, including on a fork.
class _WorkspaceScratch {
  _WorkspaceScratch(_Component component, CompiledGeometryModel model)
      : trialRaw = Float64List(component.rows),
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
      final constraint = model.constraints[layout.constraint];
      arguments.add([
        for (final pi in layout.parameters)
          Float64List(model.parameters[pi].manifold.ambientSize)
      ]);
      ambientJacobians.add([
        for (final pi in layout.parameters)
          Float64List(constraint is _AutoDiffGeometryResidualBlock &&
                  model.parameters[pi].fixed
              ? 0
              : model.parameters[pi].manifold.ambientSize *
                  constraint.residualCount)
      ]);
      residualBuffers
          .add(Float64List(model.constraints[layout.constraint].residualCount));
    }
  }

  final SparseGeometryJacobian jacobian;
  final Float64List trialRaw, trialNormalized;
  final Float64List diagonal, gradient, actualStep, jStep;
  final Map<int, Float64List> plusJacobians = {}, deltas = {}, trialValues = {};
  final List<List<Float64List>> arguments = [], ambientJacobians = [];
  final List<Float64List> residualBuffers = [];
}

/// The retained entries are bounded by the same limits as rank diagnostics.
/// Nothing is inferred from graph structure: reuse requires identical numeric
/// Jacobian entries, which already include tangent maps and residual scaling.
class _RankCache {
  _RankCache(Float64List values, GeometrySolveOptions options, this.rank,
      List<String> dependentIds)
      : values = Float64List.fromList(values),
        tolerance = options.rankTolerance,
        parameterLimit = options.rankParameterLimit,
        entryLimit = options.rankEntryLimit,
        dependentIds = List<String>.unmodifiable(dependentIds);

  final Float64List values;
  final double tolerance;
  final int parameterLimit, entryLimit, rank;
  final List<String> dependentIds;

  bool matches(Float64List candidate, GeometrySolveOptions options) =>
      tolerance == options.rankTolerance &&
      parameterLimit == options.rankParameterLimit &&
      entryLimit == options.rankEntryLimit &&
      _sameValues(values, candidate);
}

class _PreferenceTarget {
  _PreferenceTarget(this.parameter, this.definition)
      : values = Float64List.fromList(definition.values);
  final int parameter;
  final GeometryParameterTarget definition;
  final Float64List values;
}

class _PreferenceEvaluation {
  _PreferenceEvaluation(
      this.cost, this.maxError, this.gradient, this.curvature);
  final double cost, maxError, curvature;
  final Float64List gradient;
}

void _orientPreferenceTarget(
    GeometryManifold manifold, Float64List base, Float64List target) {
  if (manifold is QuaternionGeometryManifold) {
    if (geometryDot(base, target) < 0) {
      for (var i = 0; i < target.length; i++) {
        target[i] = -target[i];
      }
    }
  } else if (manifold is ProductGeometryManifold) {
    var offset = 0;
    for (final factor in manifold.factors) {
      _orientPreferenceTarget(
          factor,
          Float64List.sublistView(base, offset, offset + factor.ambientSize),
          Float64List.sublistView(target, offset, offset + factor.ambientSize));
      offset += factor.ambientSize;
    }
  }
}

class _SolveRun {
  _SolveRun(this.session, this.options, this.backend, this.shouldCancel,
      this.timeLimit, this.revision, this.targets, this.preferenceOptions)
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
  final List<_PreferenceTarget> targets;
  final GeometryPreferenceOptions preferenceOptions;
  final List<Float64List> work;
  final Set<int> dirty;
  final Stopwatch watch;
  final List<GeometryComponentDiagnostics> diagnostics = [];
  final Set<int> reported = {};
  GeometrySolveResult? result;
  String? evaluationError;
  GeometrySolveStatus? _requiredFailure;
  GeometrySolveStatus? _latchedStop;
  String? _requiredMessage;
  GeometryPreferenceReport? preferenceReport;
  double? preferenceInitialCost;
  int preferenceIterations = 0,
      preferenceAcceptedSteps = 0,
      preferenceProjections = 0;
  int residualEvaluations = 0, jacobianEvaluations = 0, linearSolves = 0;
  int linearIterations = 0, iterations = 0, solved = 0, reused = 0;
  int autoDiffDerivativeCoordinates = 0, rankFactorizations = 0, rankReuses = 0;

  GeometrySolveStatus? _stopStatus() {
    if (session.revision != revision) {
      return _latchedStop = GeometrySolveStatus.staleRevision;
    }
    if (_latchedStop != null) return _latchedStop;
    final cancelled = shouldCancel?.call() ?? false;
    // Callbacks are user code and can themselves edit a session.
    if (session.revision != revision) {
      return _latchedStop = GeometrySolveStatus.staleRevision;
    }
    if (cancelled) return _latchedStop = GeometrySolveStatus.cancelled;
    if (timeLimit != null && watch.elapsed >= timeLimit!) {
      return _latchedStop = GeometrySolveStatus.deadlineExceeded;
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
      yield* _solveRequired(ws, maxIterations: options.maxIterations);
      if (ws.evaluated) reported.add(component.id);
      if (_requiredFailure != null) {
        diagnostics.add(_diagnose(ws, derivativesValid: false));
        _finish(_requiredFailure!, message: _requiredMessage);
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
    if (targets.isNotEmpty) {
      yield* _optimizePreferences();
      if (result != null) return;
    }
    stop = _stopStatus();
    _finish(stop ?? GeometrySolveStatus.satisfied);
  }

  Iterable<int> _optimizePreferences() sync* {
    for (final target in targets) {
      _orientPreferenceTarget(model.parameters[target.parameter].manifold,
          work[target.parameter], target.values);
    }
    preferenceInitialCost = _preferenceTotals().first;
    if (!preferenceInitialCost!.isFinite) {
      _finish(GeometrySolveStatus.numericalFailure,
          message: 'Preference objective is non-finite.');
      return;
    }
    for (final component in model._components) {
      final localTargets = targets
          .where((target) =>
              component.tangentOffsets.containsKey(target.parameter))
          .toList();
      if (localTargets.isEmpty) continue;
      final ws = session._workspaces[component.id];
      final base = <int, Float64List>{
        for (final pi in component.activeParameters)
          pi: Float64List(model.parameters[pi].manifold.ambientSize)
      };
      final baseRaw = Float64List(component.rows);
      final baseNormalized = Float64List(component.rows);
      var complete = false;
      for (var iteration = 0; !complete; iteration++) {
        var stop = _stopStatus();
        if (stop != null) {
          _finish(stop);
          return;
        }
        if (!_evaluate(ws, work, derivatives: true)) {
          _finish(_stopStatus() ?? GeometrySolveStatus.numericalFailure,
              message: evaluationError);
          return;
        }
        final objective = _preferenceEvaluation(ws, localTargets);
        if (!objective.cost.isFinite ||
            !objective.curvature.isFinite ||
            objective.gradient.any((v) => !v.isFinite)) {
          _finish(GeometrySolveStatus.numericalFailure,
              message: 'Preference objective or derivative is non-finite.');
          return;
        }
        if (objective.maxError <= preferenceOptions.targetTolerance) break;
        final projection = projectGeometryNullspace(
            ws.jacobian, objective.gradient,
            denseColumnLimit: options.rankParameterLimit,
            denseEntryLimit: options.rankEntryLimit,
            maxIterations: preferenceOptions.maxLinearIterations,
            relativeTolerance: preferenceOptions.projectionTolerance,
            shouldStop: _stop);
        stop = _stopStatus();
        if (stop != null) {
          _finish(stop);
          return;
        }
        if (projection.status != GeometryLinearStatus.converged) {
          _finish(
              projection.status == GeometryLinearStatus.iterationLimit
                  ? GeometrySolveStatus.iterationLimit
                  : GeometrySolveStatus.numericalFailure,
              message: 'The preference nullspace projection did not converge.');
          return;
        }
        final gradientNorm = geometryNorm(projection.vector);
        if (gradientNorm <=
            preferenceOptions.gradientTolerance *
                math.max(1, geometryNorm(objective.gradient))) {
          break;
        }
        if (iteration >= preferenceOptions.maxIterations) {
          _finish(GeometrySolveStatus.iterationLimit,
              message: 'Preference iteration budget reached; hard constraints '
                  'remain feasible, but this transaction was not committed.');
          return;
        }
        preferenceIterations++;
        for (final pi in component.activeParameters) {
          base[pi]!.setAll(0, work[pi]);
        }
        baseRaw.setAll(0, ws.raw);
        baseNormalized.setAll(0, ws.normalized);
        void restore() {
          for (final pi in component.activeParameters) {
            work[pi].setAll(0, base[pi]!);
          }
          ws.raw.setAll(0, baseRaw);
          ws.normalized.setAll(0, baseNormalized);
        }

        final directionalCurvature = _preferenceDirectionalCurvature(
            ws, localTargets, projection.vector);
        if (!directionalCurvature.isFinite || directionalCurvature <= 0) {
          _finish(GeometrySolveStatus.numericalFailure,
              message: 'Preference directional curvature is undefined.');
          return;
        }
        // Exact minimizer of the local quadratic along projected steepest
        // descent. This avoids one tiny step per entity when one target moves
        // an entire constrained rigid cluster.
        var alpha = gradientNorm * gradientNorm / directionalCurvature;
        if (gradientNorm * alpha > preferenceOptions.maxTangentStep) {
          alpha = preferenceOptions.maxTangentStep / gradientNorm;
        }
        var accepted = false, feasibleTrial = false;
        GeometrySolveStatus? lastProjectionFailure;
        for (var trial = 0;
            trial < preferenceOptions.maxBacktrackingSteps;
            trial++) {
          restore();
          var valid = true, actualLengthSquared = 0.0;
          for (final pi in component.activeParameters) {
            final p = model.parameters[pi];
            final offset = component.tangentOffsets[pi]!;
            final delta = ws.deltas[pi]!;
            for (var col = 0; col < delta.length; col++) {
              delta[col] =
                  -alpha * projection.vector[offset + col] * p.scales[col];
            }
            p.manifold.plus(base[pi]!, delta, work[pi]);
            if (p.manifold is EuclideanGeometryManifold) {
              for (var col = 0; col < work[pi].length; col++) {
                work[pi][col] = work[pi][col]
                    .clamp(p.lowerBounds[col], p.upperBounds[col])
                    .toDouble();
                final actual = (work[pi][col] - base[pi]![col]) / p.scales[col];
                actualLengthSquared += actual * actual;
              }
            } else {
              for (var col = 0; col < delta.length; col++) {
                final actual = delta[col] / p.scales[col];
                actualLengthSquared += actual * actual;
              }
            }
            valid &= p.manifold.isValid(work[pi]);
          }
          if (valid &&
              math.sqrt(actualLengthSquared) <= options.stepTolerance) {
            restore();
            complete = true;
            break;
          }
          if (valid) {
            preferenceProjections++;
            yield* _solveRequired(ws,
                maxIterations: preferenceOptions.maxProjectionIterations);
            stop = _stopStatus();
            if (stop != null) {
              restore();
              _finish(stop);
              return;
            }
            if (_requiredFailure == null && _satisfied(ws)) {
              feasibleTrial = true;
              final candidate =
                  _preferenceEvaluation(ws, localTargets, derivatives: false);
              final sufficient =
                  objective.cost - 1e-4 * alpha * gradientNorm * gradientNorm;
              if (candidate.cost.isFinite &&
                  candidate.cost < objective.cost &&
                  (candidate.cost <= sufficient ||
                      candidate.maxError <=
                          preferenceOptions.targetTolerance)) {
                accepted = true;
                preferenceAcceptedSteps++;
                if (candidate.maxError <= preferenceOptions.targetTolerance) {
                  complete = true;
                }
                break;
              }
            } else {
              lastProjectionFailure = _requiredFailure;
            }
          } else {
            lastProjectionFailure = GeometrySolveStatus.numericalFailure;
          }
          alpha *= 0.5;
          yield 0;
        }
        if (!accepted && !complete) {
          restore();
          _finish(
              feasibleTrial
                  ? GeometrySolveStatus.stalled
                  : (lastProjectionFailure ?? GeometrySolveStatus.stalled),
              message: 'No feasible improving preference step was found; '
                  'the transaction was not committed.');
          return;
        }
        yield 0;
      }
      if (!_evaluate(ws, work, derivatives: true) || !_satisfied(ws)) {
        _finish(_stopStatus() ?? GeometrySolveStatus.numericalFailure,
            message: evaluationError ??
                'Required constraints failed final preference validation.');
        return;
      }
      final diagnostic = _diagnose(ws, derivativesValid: true);
      final index = diagnostics.indexWhere((d) => d.component == component.id);
      if (index >= 0) {
        diagnostics[index] = diagnostic;
      } else {
        diagnostics.add(diagnostic);
      }
    }
    final totals = _preferenceTotals();
    preferenceReport = _makePreferenceReport(
        totals[1] <= preferenceOptions.targetTolerance
            ? GeometryPreferenceStatus.targetReached
            : GeometryPreferenceStatus.stationary);
  }

  _PreferenceEvaluation _preferenceEvaluation(
      _Workspace ws, List<_PreferenceTarget> localTargets,
      {bool derivatives = true}) {
    final gradient = Float64List(ws.component.columns);
    final curvatureByParameter = <int, double>{};
    var cost = 0.0, maxError = 0.0;
    for (final target in localTargets) {
      final pi = target.parameter, definition = target.definition;
      final parameter = model.parameters[pi];
      final ambientSize = parameter.manifold.ambientSize;
      final tangentSize = parameter.manifold.tangentSize;
      final offset = ws.component.tangentOffsets[pi]!;
      final plus = ws.plusJacobians[pi]!;
      var squaredError = 0.0, trace = 0.0, largestDiagonal = 0.0;
      for (var row = 0; row < ambientSize; row++) {
        final scale = definition.coordinateScales[row];
        final residual = (work[pi][row] - target.values[row]) / scale;
        squaredError += residual * residual;
        if (!derivatives) continue;
        if (parameter.manifold is EuclideanGeometryManifold) {
          final derivative = parameter.scales[row] / scale;
          gradient[offset + row] += definition.weight * residual * derivative;
          largestDiagonal = math.max(
              largestDiagonal, definition.weight * derivative * derivative);
        } else {
          for (var col = 0; col < tangentSize; col++) {
            final derivative =
                plus[row * tangentSize + col] * parameter.scales[col] / scale;
            gradient[offset + col] += definition.weight * residual * derivative;
            trace += definition.weight * derivative * derivative;
          }
        }
      }
      cost += 0.5 * definition.weight * squaredError;
      maxError = math.max(maxError, math.sqrt(squaredError));
      curvatureByParameter[pi] = (curvatureByParameter[pi] ?? 0) +
          (parameter.manifold is EuclideanGeometryManifold
              ? largestDiagonal
              : trace);
    }
    final curvature = curvatureByParameter.isEmpty
        ? 1.0
        : curvatureByParameter.values.reduce(math.max);
    return _PreferenceEvaluation(cost, maxError, gradient, curvature);
  }

  List<double> _preferenceTotals() {
    var cost = 0.0, error = 0.0;
    for (final target in targets) {
      var squared = 0.0;
      for (var i = 0; i < target.values.length; i++) {
        final residual = (work[target.parameter][i] - target.values[i]) /
            target.definition.coordinateScales[i];
        squared += residual * residual;
      }
      cost += 0.5 * target.definition.weight * squared;
      error = math.max(error, math.sqrt(squared));
    }
    return [cost, error];
  }

  double _preferenceDirectionalCurvature(_Workspace ws,
      List<_PreferenceTarget> localTargets, Float64List direction) {
    var result = 0.0;
    for (final target in localTargets) {
      final p = model.parameters[target.parameter];
      final offset = ws.component.tangentOffsets[target.parameter]!;
      final plus = ws.plusJacobians[target.parameter]!;
      for (var row = 0; row < p.manifold.ambientSize; row++) {
        var derivative = 0.0;
        for (var col = 0; col < p.manifold.tangentSize; col++) {
          derivative += plus[row * p.manifold.tangentSize + col] *
              p.scales[col] *
              direction[offset + col];
        }
        derivative /= target.definition.coordinateScales[row];
        result += target.definition.weight * derivative * derivative;
      }
    }
    return result;
  }

  GeometryPreferenceReport _makePreferenceReport(
      GeometryPreferenceStatus status) {
    final totals = _preferenceTotals();
    return GeometryPreferenceReport(
        status: status,
        initialCost: preferenceInitialCost!,
        finalCost: totals[0],
        maxTargetError: totals[1],
        iterations: preferenceIterations,
        acceptedSteps: preferenceAcceptedSteps,
        feasibilityProjections: preferenceProjections);
  }

  Iterable<int> _solveRequired(_Workspace ws,
      {required int maxIterations}) sync* {
    _requiredFailure = null;
    _requiredMessage = null;
    final component = ws.component;
    GeometrySolveStatus? stop;
    if (!_evaluate(ws, work, derivatives: false)) {
      _requiredFailure = _stopStatus() ?? GeometrySolveStatus.numericalFailure;
      _requiredMessage = evaluationError;
      return;
    }
    yield 0;
    var damping = options.initialDamping;
    var growth = 2.0;
    final trial = List<Float64List>.from(work);
    for (final pi in component.activeParameters) {
      trial[pi] = ws.trialValues[pi]!;
    }
    var failure = GeometrySolveStatus.iterationLimit;
    for (var it = 0; it < maxIterations && !_satisfied(ws); it++) {
      stop = _stopStatus();
      if (stop != null) {
        _requiredFailure = stop;
        return;
      }
      if (component.columns == 0) {
        failure = GeometrySolveStatus.stalled;
        break;
      }
      if (!_evaluate(ws, work, derivatives: true)) {
        _requiredFailure =
            _stopStatus() ?? GeometrySolveStatus.numericalFailure;
        _requiredMessage = evaluationError;
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
        _requiredFailure = stop;
        return;
      }
      if (linear.status != GeometryLinearStatus.converged) {
        if (linear.status == GeometryLinearStatus.cancelled) {
          _requiredFailure = GeometrySolveStatus.cancelled;
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
      if (validTrial && _evaluate(ws, trial, derivatives: false, trial: true)) {
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
        _requiredFailure = stop;
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
      _requiredFailure = failure;
      _requiredMessage = 'Required equations remain outside tolerance; '
          'local nonconvergence does not prove infeasibility.';
    }
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
        if (constraint is _AutoDiffGeometryResidualBlock) {
          _evaluateAutoDiff(
              constraint.id,
              constraint.residualCount,
              constraint.expression,
              arguments,
              buffer,
              derivatives ? ambient : null,
              activeOffsets: layout.activeAmbientOffsets,
              activeDimension: layout.activeAmbientDimension);
          if (derivatives) {
            autoDiffDerivativeCoordinates += layout.activeAmbientDimension;
          }
        } else {
          constraint.evaluate(arguments, buffer, derivatives ? ambient : null);
        }
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
            final identity =
                parameter.manifold is _DefaultEuclideanGeometryManifold;
            for (var col = 0; col < t; col++) {
              var sum = 0.0;
              if (identity && col > 0) {
                // The first column keeps the full reduction, which rejects
                // every non-finite ambient entry before writing this row.
                // Adding to positive zero preserves signed-zero behavior.
                sum += ambient[p][row * a + col];
              } else {
                for (var k = 0; k < a; k++) {
                  sum += ambient[p][row * a + k] * plus[k * t + col];
                }
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
    final withinLimits = component.columns <= options.rankParameterLimit &&
        component.rows * component.columns <= options.rankEntryLimit;
    if (!withinLimits) ws.rankCache = null;
    if (component.columns == 0 || component.rows == 0) {
      rank = 0;
    } else if (derivativesValid && withinLimits) {
      final cached = ws.rankCache;
      if (cached != null && cached.matches(ws.jacobian.values, options)) {
        rank = cached.rank;
        dependentIds.addAll(cached.dependentIds);
        rankReuses++;
      } else {
        final dense = ws.jacobian.toDense();
        rankFactorizations++;
        final info = geometryRank(dense, component.rows, component.columns,
            relativeTolerance: options.rankTolerance, shouldStop: _stop);
        rank = info?.rank;
        var complete = rank != null;
        if (rank != null && component.rows > rank) {
          final transpose = Float64List(dense.length);
          for (var row = 0; row < component.rows; row++) {
            for (var col = 0; col < component.columns; col++) {
              transpose[col * component.rows + row] =
                  dense[row * component.columns + col];
            }
          }
          rankFactorizations++;
          final rowRank = geometryRank(
              transpose, component.columns, component.rows,
              relativeTolerance: options.rankTolerance, shouldStop: _stop);
          complete = rowRank != null && rowRank.rank == rank;
          if (complete) {
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
        // Interrupted or incomplete factorizations never establish a cache.
        if (complete) {
          ws.rankCache =
              _RankCache(ws.jacobian.values, options, rank!, dependentIds);
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
    if (preferenceInitialCost != null &&
        (preferenceReport == null || status != GeometrySolveStatus.satisfied)) {
      preferenceReport = _makePreferenceReport(switch (status) {
        GeometrySolveStatus.satisfied => GeometryPreferenceStatus.stationary,
        GeometrySolveStatus.iterationLimit =>
          GeometryPreferenceStatus.iterationLimit,
        GeometrySolveStatus.cancelled => GeometryPreferenceStatus.cancelled,
        GeometrySolveStatus.deadlineExceeded =>
          GeometryPreferenceStatus.deadlineExceeded,
        GeometrySolveStatus.stalled => GeometryPreferenceStatus.noProgress,
        GeometrySolveStatus.numericalFailure =>
          GeometryPreferenceStatus.numericalFailure,
        GeometrySolveStatus.staleRevision =>
          GeometryPreferenceStatus.staleRevision,
      });
    }
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
            autoDiffDerivativeCoordinates: autoDiffDerivativeCoordinates,
            rankFactorizations: rankFactorizations,
            rankReuses: rankReuses,
            elapsed: watch.elapsed),
        message: message,
        preferenceReport: preferenceReport);
    // A later revision owns pending values; never overwrite it with stale work.
    if (session.revision != revision) return;
    session._lastResult = result;
    if (status == GeometrySolveStatus.satisfied) {
      session._committed = _copyValues(work);
      session._pending = _copyValues(work);
      session._dirty.removeAll(dirty);
      session._diagnosticOptions = options;
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

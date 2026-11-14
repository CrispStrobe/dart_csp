/// Native benchmark experiment at the public GeometryLinearSolver extension.
/// No residual, parameter scaling, damping policy, or CAD behavior lives here.
library;

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';

typedef _CreateDart = Pointer<Void> Function(int, int, int);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _IntsNative = Pointer<Int32> Function(Pointer<Void>);
typedef _IntsDart = Pointer<Int32> Function(Pointer<Void>);
typedef _DoublesNative = Pointer<Double> Function(Pointer<Void>);
typedef _DoublesDart = Pointer<Double> Function(Pointer<Void>);
typedef _IntNative = Int32 Function(Pointer<Void>);
typedef _IntDart = int Function(Pointer<Void>);
typedef _LongDart = int Function(Pointer<Void>);
typedef _DoubleDart = double Function(Pointer<Void>);
typedef _SolveDart = int Function(Pointer<Void>, double, int, double);

final class _Api {
  _Api(DynamicLibrary library)
      : create = library.lookupFunction<
            Pointer<Void> Function(Int32, Int32, Int32),
            _CreateDart>('ds_create'),
        destroy =
            library.lookupFunction<Void Function(Pointer<Void>), _DestroyDart>(
                'ds_destroy'),
        rowOffsets =
            library.lookupFunction<_IntsNative, _IntsDart>('ds_row_offsets'),
        columnIndices =
            library.lookupFunction<_IntsNative, _IntsDart>('ds_column_indices'),
        values =
            library.lookupFunction<_DoublesNative, _DoublesDart>('ds_values'),
        residual =
            library.lookupFunction<_DoublesNative, _DoublesDart>('ds_residual'),
        diagonal =
            library.lookupFunction<_DoublesNative, _DoublesDart>('ds_diagonal'),
        step = library.lookupFunction<_DoublesNative, _DoublesDart>('ds_step'),
        prepare = library.lookupFunction<_IntNative, _IntDart>('ds_prepare'),
        solve = library.lookupFunction<
            Int32 Function(Pointer<Void>, Double, Int32, Double),
            _SolveDart>('ds_solve'),
        relativeResidual =
            library.lookupFunction<Double Function(Pointer<Void>), _DoubleDart>(
                'ds_relative_residual'),
        iterations =
            library.lookupFunction<_IntNative, _IntDart>('ds_iterations'),
        factorizations =
            library.lookupFunction<_IntNative, _IntDart>('ds_factorizations'),
        refinements =
            library.lookupFunction<_IntNative, _IntDart>('ds_refinements'),
        normalNonzeros =
            library.lookupFunction<Int64 Function(Pointer<Void>), _LongDart>(
                'ds_normal_nonzeros');

  final _CreateDart create;
  final _DestroyDart destroy;
  final _IntsDart rowOffsets, columnIndices;
  final _DoublesDart values, residual, diagonal, step;
  final _IntDart prepare, iterations, factorizations, refinements;
  final _SolveDart solve;
  final _DoubleDart relativeResidual;
  final _LongDart normalNonzeros;
}

final class _Context {
  _Context(this.api, SparseGeometryJacobian jacobian) {
    handle =
        api.create(jacobian.rows, jacobian.columns, jacobian.values.length);
    if (handle == nullptr) throw StateError('Sparse step allocation failed.');
    try {
      api
          .rowOffsets(handle)
          .asTypedList(jacobian.rows + 1)
          .setAll(0, jacobian.rowOffsets);
      api
          .columnIndices(handle)
          .asTypedList(jacobian.values.length)
          .setAll(0, jacobian.columnIndices);
      if (api.prepare(handle) != 0) {
        throw StateError('Sparse symbolic analysis failed.');
      }
      values = api.values(handle).asTypedList(jacobian.values.length);
      residual = api.residual(handle).asTypedList(jacobian.rows);
      diagonal = api.diagonal(handle).asTypedList(jacobian.columns);
      step = api.step(handle).asTypedList(jacobian.columns);
    } catch (_) {
      api.destroy(handle);
      rethrow;
    }
  }
  final _Api api;
  late final Pointer<Void> handle;
  late final Float64List values, residual, diagonal, step;
  void dispose() => api.destroy(handle);
}

/// Same dense threshold as AdaptiveGeometryLinearSolver. Only the large linear
/// solve changes, to Eigen SimplicialLDLT with AMD and a retained symbolic pattern.
final class EigenSparseGeometrySolver implements GeometryLinearSolver {
  EigenSparseGeometrySolver(String libraryPath,
      {this.denseParameterLimit = 64, this.denseEntryLimit = 262144})
      : _api = _Api(DynamicLibrary.open(libraryPath));

  final int denseParameterLimit, denseEntryLimit;
  final _Api _api;
  final _contexts = Map<SparseGeometryJacobian, _Context>.identity();
  int nativeCalls = 0, nativeFactorizations = 0, nativeRefinements = 0;
  int symbolicAnalyses = 0, denseCalls = 0, failedNativeSteps = 0;
  int maxNormalNonzeros = 0, ffiCopyBytes = 0;
  double maxVerifiedRelativeResidual = 0.0;
  double maxNativeRelativeResidual = 0.0;
  double maxConvergedRelativeResidual = 0.0;

  /// The host calls this before its timer in cold mode. Warm mode retains the
  /// workspace for each Jacobian object across nonlinear iterations and edits.
  void clear() {
    for (final context in _contexts.values) {
      context.dispose();
    }
    _contexts.clear();
  }

  void beginOperation({required bool cold}) {
    if (cold) clear();
    nativeCalls = nativeFactorizations = nativeRefinements = 0;
    symbolicAnalyses =
        denseCalls = failedNativeSteps = maxNormalNonzeros = ffiCopyBytes = 0;
    maxVerifiedRelativeResidual =
        maxNativeRelativeResidual = maxConvergedRelativeResidual = 0.0;
  }

  Map<String, Object?> metrics() => {
        'native_linear_calls': nativeCalls,
        'native_factorizations': nativeFactorizations,
        'native_refinements': nativeRefinements,
        'native_symbolic_analyses': symbolicAnalyses,
        'dense_qr_linear_calls': denseCalls,
        'failed_native_linear_steps': failedNativeSteps,
        'max_normal_matrix_nonzeros': maxNormalNonzeros,
        'ffi_copy_bytes': ffiCopyBytes,
        'max_verified_linear_relative_residual':
            maxVerifiedRelativeResidual.isFinite
                ? maxVerifiedRelativeResidual
                : null,
        'max_native_linear_relative_residual':
            maxNativeRelativeResidual.isFinite
                ? maxNativeRelativeResidual
                : null,
        'max_converged_linear_relative_residual': maxConvergedRelativeResidual,
      };

  @override
  GeometryLinearStep solve(
      SparseGeometryJacobian jacobian, Float64List residual,
      {required double damping,
      required Float64List diagonal,
      int maxIterations = 1000,
      double relativeTolerance = 1e-8,
      bool Function()? shouldStop}) {
    GeometryLinearStep failure(GeometryLinearStatus status) =>
        GeometryLinearStep(status, Float64List(jacobian.columns),
            iterations: 0, relativeResidual: double.infinity);
    if (shouldStop?.call() ?? false) {
      return failure(GeometryLinearStatus.cancelled);
    }
    if (residual.length != jacobian.rows ||
        diagonal.length != jacobian.columns ||
        !damping.isFinite ||
        damping < 0 ||
        !relativeTolerance.isFinite ||
        relativeTolerance <= 0 ||
        maxIterations < 0 ||
        jacobian.values.any((x) => !x.isFinite) ||
        residual.any((x) => !x.isFinite) ||
        diagonal.any((x) => !x.isFinite || x < 0)) {
      return failure(GeometryLinearStatus.numericalFailure);
    }
    final useDense = jacobian.columns <= denseParameterLimit &&
        (jacobian.rows + jacobian.columns) * jacobian.columns <=
            denseEntryLimit;
    if (useDense) {
      denseCalls++;
      return const DenseQrGeometrySolver().solve(jacobian, residual,
          damping: damping,
          diagonal: diagonal,
          maxIterations: maxIterations,
          relativeTolerance: relativeTolerance,
          shouldStop: shouldStop);
    }
    if (jacobian.columns == 0) {
      return GeometryLinearStep(GeometryLinearStatus.converged, Float64List(0),
          iterations: 0, relativeResidual: 0);
    }
    final context = _contexts.putIfAbsent(jacobian, () {
      final created = _Context(_api, jacobian);
      symbolicAnalyses++;
      ffiCopyBytes += 4 * (jacobian.rows + 1 + jacobian.values.length);
      return created;
    });
    context.values.setAll(0, jacobian.values);
    context.residual.setAll(0, residual);
    context.diagonal.setAll(0, diagonal);
    ffiCopyBytes +=
        8 * (jacobian.values.length + residual.length + diagonal.length);
    if (shouldStop?.call() ?? false) {
      return failure(GeometryLinearStatus.cancelled);
    }
    nativeCalls++;
    final status =
        _api.solve(context.handle, damping, maxIterations, relativeTolerance);
    final iterations = _api.iterations(context.handle);
    nativeFactorizations += _api.factorizations(context.handle);
    nativeRefinements += _api.refinements(context.handle);
    maxNormalNonzeros =
        math.max(maxNormalNonzeros, _api.normalNonzeros(context.handle));
    maxNativeRelativeResidual = math.max(
        maxNativeRelativeResidual, _api.relativeResidual(context.handle));
    if (shouldStop?.call() ?? false) {
      return GeometryLinearStep(
          GeometryLinearStatus.cancelled, Float64List(jacobian.columns),
          iterations: iterations, relativeResidual: double.infinity);
    }
    final step = Float64List.fromList(context.step);
    ffiCopyBytes += 8 * step.length;
    // Independent Dart recomputation prevents an ABI or native residual mistake
    // from falsely reporting convergence. This validation is inside solve timing.
    final relative =
        checkedNormalResidual(jacobian, residual, diagonal, damping, step);
    maxVerifiedRelativeResidual =
        math.max(maxVerifiedRelativeResidual, relative);
    final good = status == 0 &&
        step.every((x) => x.isFinite) &&
        relative.isFinite &&
        relative <= relativeTolerance;
    if (good) {
      maxConvergedRelativeResidual =
          math.max(maxConvergedRelativeResidual, relative);
    }
    if (!good) failedNativeSteps++;
    return GeometryLinearStep(
        good
            ? GeometryLinearStatus.converged
            : status == 1
                ? GeometryLinearStatus.iterationLimit
                : GeometryLinearStatus.numericalFailure,
        step,
        iterations: iterations,
        relativeResidual: relative);
  }
}

/// Mirrors the production solver's original-system residual, independently of
/// Eigen's assembled matrix and factorization status.
double checkedNormalResidual(
    SparseGeometryJacobian jacobian,
    Float64List residual,
    Float64List diagonal,
    double damping,
    Float64List step) {
  final temp = Float64List(jacobian.rows);
  final out = Float64List(jacobian.columns);
  final rhs = Float64List(jacobian.columns);
  jacobian.multiply(step, temp);
  for (var row = 0; row < temp.length; row++) {
    temp[row] += residual[row];
  }
  jacobian.transposeMultiply(temp, out);
  jacobian.transposeMultiply(residual, rhs);
  for (var i = 0; i < out.length; i++) {
    out[i] += damping * diagonal[i] * step[i];
  }
  final initial = geometryNorm(rhs);
  return initial == 0 ? geometryNorm(out) : geometryNorm(out) / initial;
}

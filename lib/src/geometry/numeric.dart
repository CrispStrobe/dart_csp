import 'dart:math' as math;
import 'dart:typed_data';

/// Overflow-resistant Euclidean norm.
double geometryNorm(List<double> values) {
  var scale = 0.0;
  var sum = 1.0;
  for (final value in values) {
    final a = value.abs();
    if (!a.isFinite) return a;
    if (a == 0) continue;
    if (scale < a) {
      final ratio = scale / a;
      sum = 1 + sum * ratio * ratio;
      scale = a;
    } else {
      final ratio = a / scale;
      sum += ratio * ratio;
    }
  }
  return scale == 0 ? 0 : scale * math.sqrt(sum);
}

double geometryDot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// A reusable compressed-row Jacobian. The pattern stays fixed across edits;
/// only [values] change. No dense normal matrix is required by the sparse path.
class SparseGeometryJacobian {
  SparseGeometryJacobian({
    required this.rows,
    required this.columns,
    required this.rowOffsets,
    required this.columnIndices,
    required this.values,
  }) {
    if (rows < 0 ||
        columns < 0 ||
        rowOffsets.length != rows + 1 ||
        columnIndices.length != values.length ||
        rowOffsets[0] != 0 ||
        rowOffsets.last != values.length) {
      throw ArgumentError('Invalid sparse Jacobian dimensions.');
    }
    for (var row = 0; row < rows; row++) {
      if (rowOffsets[row] > rowOffsets[row + 1]) {
        throw ArgumentError('Sparse row offsets must be nondecreasing.');
      }
    }
    for (final column in columnIndices) {
      if (column < 0 || column >= columns) {
        throw ArgumentError('Sparse Jacobian column out of range.');
      }
    }
  }

  final int rows;
  final int columns;
  final Int32List rowOffsets;
  final Int32List columnIndices;
  final Float64List values;

  void multiply(Float64List x, Float64List out) {
    for (var row = 0; row < rows; row++) {
      var value = 0.0;
      for (var k = rowOffsets[row]; k < rowOffsets[row + 1]; k++) {
        value += values[k] * x[columnIndices[k]];
      }
      out[row] = value;
    }
  }

  void transposeMultiply(Float64List x, Float64List out) {
    out.fillRange(0, columns, 0);
    for (var row = 0; row < rows; row++) {
      for (var k = rowOffsets[row]; k < rowOffsets[row + 1]; k++) {
        out[columnIndices[k]] += values[k] * x[row];
      }
    }
  }

  void normalDiagonal(Float64List out) {
    out.fillRange(0, columns, 0);
    for (var k = 0; k < values.length; k++) {
      out[columnIndices[k]] += values[k] * values[k];
    }
  }

  Float64List toDense() {
    final result = Float64List(rows * columns);
    for (var row = 0; row < rows; row++) {
      for (var k = rowOffsets[row]; k < rowOffsets[row + 1]; k++) {
        result[row * columns + columnIndices[k]] += values[k];
      }
    }
    return result;
  }
}

enum GeometryLinearStatus {
  converged,
  iterationLimit,
  cancelled,
  numericalFailure
}

class GeometryLinearStep {
  GeometryLinearStep(
    this.status,
    this.step, {
    required this.iterations,
    required this.relativeResidual,
  });
  final GeometryLinearStatus status;
  final Float64List step;
  final int iterations;

  /// Residual of the damped normal equation, relative to its initial residual.
  final double relativeResidual;
}

/// Backend for `(J'J + damping * diag(diagonal)) step = -J' residual`.
/// Implementations must report whether the linear solve actually converged.
// A named backend interface is intentionally extensible by platform adapters.
// ignore: one_member_abstracts
abstract class GeometryLinearSolver {
  GeometryLinearStep solve(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    int maxIterations = 1000,
    double relativeTolerance = 1e-8,
    bool Function()? shouldStop,
  });
}

/// Dense column-pivoted Householder QR of the *augmented* least-squares system.
/// Intended for small components; it never forms `J'J`.
/// [GeometryLinearSolver.solve]'s iteration budget counts QR pivot steps.
class DenseQrGeometrySolver implements GeometryLinearSolver {
  const DenseQrGeometrySolver();

  @override
  GeometryLinearStep solve(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    int maxIterations = 1000,
    double relativeTolerance = 1e-8,
    bool Function()? shouldStop,
  }) {
    final n = jacobian.columns;
    final m = jacobian.rows + n;
    final matrix = Float64List(m * n);
    final rhs = Float64List(m);
    for (var row = 0; row < jacobian.rows; row++) {
      rhs[row] = -residual[row];
      for (var k = jacobian.rowOffsets[row];
          k < jacobian.rowOffsets[row + 1];
          k++) {
        matrix[row * n + jacobian.columnIndices[k]] += jacobian.values[k];
      }
    }
    for (var col = 0; col < n; col++) {
      matrix[(jacobian.rows + col) * n + col] =
          math.sqrt(damping * diagonal[col]);
    }
    final qr = _factorQr(matrix, m, n, rhs, 1e-14, shouldStop,
        maxSteps: maxIterations);
    if (qr.cancelled) {
      return GeometryLinearStep(GeometryLinearStatus.cancelled, Float64List(n),
          iterations: qr.rank, relativeResidual: double.infinity);
    }
    if (qr.iterationLimit) {
      return GeometryLinearStep(
          GeometryLinearStatus.iterationLimit, Float64List(n),
          iterations: qr.rank, relativeResidual: double.infinity);
    }
    if (!qr.finite || qr.rank < n) {
      return GeometryLinearStep(
          GeometryLinearStatus.numericalFailure, Float64List(n),
          iterations: qr.rank, relativeResidual: double.infinity);
    }
    final ordered = Float64List(n);
    for (var i = n - 1; i >= 0; i--) {
      var value = rhs[i];
      for (var j = i + 1; j < n; j++) {
        value -= matrix[i * n + j] * ordered[j];
      }
      ordered[i] = value / matrix[i * n + i];
    }
    final step = Float64List(n);
    for (var i = 0; i < n; i++) {
      step[qr.order[i]] = ordered[i];
    }
    final relative =
        _normalResidual(jacobian, residual, diagonal, damping, step);
    return GeometryLinearStep(
      relative.isFinite && relative <= math.max(relativeTolerance, 1e-10)
          ? GeometryLinearStatus.converged
          : GeometryLinearStatus.numericalFailure,
      step,
      iterations: n,
      relativeResidual: relative,
    );
  }
}

/// Matrix-free preconditioned conjugate gradients for a damped sparse system.
/// Storage is `O(nonzeros + rows + columns)`, not `O(columns squared)`.
class SparseCgGeometrySolver implements GeometryLinearSolver {
  const SparseCgGeometrySolver();

  @override
  GeometryLinearStep solve(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    int maxIterations = 1000,
    double relativeTolerance = 1e-8,
    bool Function()? shouldStop,
  }) {
    final n = jacobian.columns;
    final x = Float64List(n);
    final r = Float64List(n);
    jacobian.transposeMultiply(residual, r);
    for (var i = 0; i < n; i++) {
      r[i] = -r[i];
    }
    final initialNorm = geometryNorm(r);
    if (!initialNorm.isFinite) {
      return GeometryLinearStep(GeometryLinearStatus.numericalFailure, x,
          iterations: 0, relativeResidual: double.infinity);
    }
    if (initialNorm == 0) {
      return GeometryLinearStep(GeometryLinearStatus.converged, x,
          iterations: 0, relativeResidual: 0);
    }
    final preconditioner = Float64List(n);
    jacobian.normalDiagonal(preconditioner);
    final z = Float64List(n);
    final p = Float64List(n);
    final ap = Float64List(n);
    final jp = Float64List(jacobian.rows);
    for (var i = 0; i < n; i++) {
      preconditioner[i] += damping * diagonal[i];
      if (!preconditioner[i].isFinite || preconditioner[i] <= 0) {
        return GeometryLinearStep(GeometryLinearStatus.numericalFailure, x,
            iterations: 0, relativeResidual: double.infinity);
      }
      z[i] = r[i] / preconditioner[i];
      p[i] = z[i];
    }
    var rz = geometryDot(r, z);
    var relative = 1.0;
    var iterations = 0;
    for (; iterations < maxIterations; iterations++) {
      if (shouldStop?.call() ?? false) {
        return GeometryLinearStep(GeometryLinearStatus.cancelled, x,
            iterations: iterations, relativeResidual: relative);
      }
      jacobian.multiply(p, jp);
      jacobian.transposeMultiply(jp, ap);
      for (var i = 0; i < n; i++) {
        ap[i] += damping * diagonal[i] * p[i];
      }
      final pap = geometryDot(p, ap);
      if (!pap.isFinite || pap <= 0 || !rz.isFinite) {
        return GeometryLinearStep(GeometryLinearStatus.numericalFailure, x,
            iterations: iterations, relativeResidual: relative);
      }
      final alpha = rz / pap;
      for (var i = 0; i < n; i++) {
        x[i] += alpha * p[i];
        r[i] -= alpha * ap[i];
      }
      relative = geometryNorm(r) / initialNorm;
      if (!relative.isFinite) {
        return GeometryLinearStep(GeometryLinearStatus.numericalFailure, x,
            iterations: iterations + 1, relativeResidual: relative);
      }
      if (relative <= relativeTolerance) {
        // Recursive CG residuals can drift; verify against the original system.
        relative = _normalResidual(jacobian, residual, diagonal, damping, x);
        if (relative <= relativeTolerance) {
          return GeometryLinearStep(GeometryLinearStatus.converged, x,
              iterations: iterations + 1, relativeResidual: relative);
        }
        // Restart using the explicitly recomputed residual.
        jacobian.multiply(x, jp);
        for (var row = 0; row < jp.length; row++) {
          jp[row] += residual[row];
        }
        jacobian.transposeMultiply(jp, r);
        for (var i = 0; i < n; i++) {
          r[i] = -r[i] - damping * diagonal[i] * x[i];
          z[i] = r[i] / preconditioner[i];
          p[i] = z[i];
        }
        rz = geometryDot(r, z);
        continue;
      }
      for (var i = 0; i < n; i++) {
        z[i] = r[i] / preconditioner[i];
      }
      final nextRz = geometryDot(r, z);
      final beta = nextRz / rz;
      for (var i = 0; i < n; i++) {
        p[i] = z[i] + beta * p[i];
      }
      rz = nextRz;
    }
    relative = _normalResidual(jacobian, residual, diagonal, damping, x);
    return GeometryLinearStep(
        relative <= relativeTolerance
            ? GeometryLinearStatus.converged
            : GeometryLinearStatus.iterationLimit,
        x,
        iterations: iterations,
        relativeResidual: relative);
  }
}

/// Dense QR below a bounded size; sparse matrix-free CG for larger components.
class AdaptiveGeometryLinearSolver implements GeometryLinearSolver {
  const AdaptiveGeometryLinearSolver(
      {this.denseParameterLimit = 64, this.denseEntryLimit = 262144});
  final int denseParameterLimit;
  final int denseEntryLimit;

  @override
  GeometryLinearStep solve(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    int maxIterations = 1000,
    double relativeTolerance = 1e-8,
    bool Function()? shouldStop,
  }) {
    final useDense = jacobian.columns <= denseParameterLimit &&
        (jacobian.rows + jacobian.columns) * jacobian.columns <=
            denseEntryLimit;
    final backend = useDense
        ? const DenseQrGeometrySolver()
        : const SparseCgGeometrySolver();
    return backend.solve(jacobian, residual,
        damping: damping,
        diagonal: diagonal,
        maxIterations: maxIterations,
        relativeTolerance: relativeTolerance,
        shouldStop: shouldStop);
  }
}

double _normalResidual(SparseGeometryJacobian j, Float64List residual,
    Float64List diagonal, double damping, Float64List x) {
  final temp = Float64List(j.rows);
  final out = Float64List(j.columns);
  final rhs = Float64List(j.columns);
  j.multiply(x, temp);
  for (var row = 0; row < temp.length; row++) {
    temp[row] += residual[row];
  }
  j.transposeMultiply(temp, out);
  j.transposeMultiply(residual, rhs);
  for (var i = 0; i < out.length; i++) {
    out[i] += damping * diagonal[i] * x[i];
  }
  final initial = geometryNorm(rhs);
  return initial == 0 ? geometryNorm(out) : geometryNorm(out) / initial;
}

class GeometryRankInfo {
  GeometryRankInfo(this.rank, this.independentColumns, this.dependentColumns,
      {this.columnNormEvaluations = 0,
      this.columnNormEntryVisits = 0,
      this.normDowndates = 0});
  final int rank;
  final List<int> independentColumns;
  final List<int> dependentColumns;

  /// Complete trailing-column norm computations in this factorization.
  /// Includes initial norms, pivot verification and numerical safety refreshes.
  final int columnNormEvaluations;

  /// Matrix entries read by complete norm computations. This excludes the
  /// separate Householder transformation work, which remains cubic in size.
  final int columnNormEntryVisits;

  /// Constant-time norm updates that avoided a complete trailing-column scan.
  final int normDowndates;
}

/// A checked projection into the Jacobian's local nullspace.
class GeometryNullspaceProjection {
  GeometryNullspaceProjection(this.status, this.vector,
      {required this.iterations,
      required this.relativeConstraintError,
      this.rank});
  final GeometryLinearStatus status;
  final Float64List vector;
  final int iterations;
  final double relativeConstraintError;
  final int? rank;
}

/// Project [vector] onto the nullspace of [jacobian]. Small components use
/// Householder QR of J transpose; large components solve the consistent
/// row-space system `J J' lambda = J vector` with matrix-free preconditioned CG.
/// Both paths verify `J projected` before reporting success.
GeometryNullspaceProjection projectGeometryNullspace(
  SparseGeometryJacobian jacobian,
  Float64List vector, {
  int denseColumnLimit = 96,
  int denseEntryLimit = 262144,
  int maxIterations = 1000,
  double relativeTolerance = 1e-10,
  bool Function()? shouldStop,
}) {
  final m = jacobian.rows, n = jacobian.columns;
  if (vector.length != n ||
      maxIterations < 0 ||
      relativeTolerance <= 0 ||
      !relativeTolerance.isFinite) {
    throw ArgumentError('Invalid nullspace projection arguments.');
  }
  if (m == 0 || n == 0) {
    return GeometryNullspaceProjection(
        GeometryLinearStatus.converged, Float64List.fromList(vector),
        iterations: 0, relativeConstraintError: 0, rank: 0);
  }
  final denominator = geometryNorm(jacobian.values) * geometryNorm(vector);
  if (!denominator.isFinite) {
    return GeometryNullspaceProjection(
        GeometryLinearStatus.numericalFailure, Float64List(n),
        iterations: 0, relativeConstraintError: double.infinity);
  }
  GeometryNullspaceProjection finish(
      Float64List projected, int iterations, GeometryLinearStatus status,
      [int? rank]) {
    final check = Float64List(m);
    jacobian.multiply(projected, check);
    final error = denominator == 0
        ? geometryNorm(check)
        : geometryNorm(check) / denominator;
    if (status == GeometryLinearStatus.converged &&
        (!error.isFinite || error > math.max(1e-12, relativeTolerance * 10))) {
      status = GeometryLinearStatus.numericalFailure;
    }
    return GeometryNullspaceProjection(status, projected,
        iterations: iterations, relativeConstraintError: error, rank: rank);
  }

  if (shouldStop?.call() ?? false) {
    return finish(
        Float64List.fromList(vector), 0, GeometryLinearStatus.cancelled);
  }
  if (n <= denseColumnLimit && m * n <= denseEntryLimit) {
    final transpose = Float64List(n * m);
    for (var row = 0; row < m; row++) {
      for (var k = jacobian.rowOffsets[row];
          k < jacobian.rowOffsets[row + 1];
          k++) {
        transpose[jacobian.columnIndices[k] * m + row] += jacobian.values[k];
      }
    }
    final qr = _factorQr(transpose, n, m, null, relativeTolerance, shouldStop,
        maxSteps: maxIterations);
    if (qr.cancelled || qr.iterationLimit || !qr.finite) {
      return finish(
          Float64List.fromList(vector),
          qr.rank,
          qr.cancelled
              ? GeometryLinearStatus.cancelled
              : qr.iterationLimit
                  ? GeometryLinearStatus.iterationLimit
                  : GeometryLinearStatus.numericalFailure);
    }
    final projected = Float64List.fromList(vector);
    void reflector(int k) {
      var normSquared = 1.0, projection = projected[k];
      for (var row = k + 1; row < n; row++) {
        final value = transpose[row * m + k];
        normSquared += value * value;
        projection += value * projected[row];
      }
      projection *= 2 / normSquared;
      projected[k] -= projection;
      for (var row = k + 1; row < n; row++) {
        projected[row] -= transpose[row * m + k] * projection;
      }
    }

    for (var k = 0; k < qr.rank; k++) {
      reflector(k);
    }
    projected.fillRange(0, qr.rank, 0);
    for (var k = qr.rank - 1; k >= 0; k--) {
      reflector(k);
    }
    return finish(projected, qr.rank, GeometryLinearStatus.converged, qr.rank);
  }

  final rhs = Float64List(m);
  jacobian.multiply(vector, rhs);
  final initial = geometryNorm(rhs);
  if (initial <= relativeTolerance * denominator) {
    return finish(
        Float64List.fromList(vector), 0, GeometryLinearStatus.converged);
  }
  final lambda = Float64List(m), residual = Float64List.fromList(rhs);
  final z = Float64List(m), p = Float64List(m), ap = Float64List(m);
  final temp = Float64List(n), diagonal = Float64List(m);
  for (var row = 0; row < m; row++) {
    var sum = 0.0;
    for (var k = jacobian.rowOffsets[row];
        k < jacobian.rowOffsets[row + 1];
        k++) {
      sum += jacobian.values[k] * jacobian.values[k];
    }
    diagonal[row] = sum == 0 ? 1 : sum;
    z[row] = residual[row] / diagonal[row];
    p[row] = z[row];
  }
  var rz = geometryDot(residual, z);
  var status = GeometryLinearStatus.iterationLimit;
  var iterations = 0;
  for (; iterations < maxIterations; iterations++) {
    if (shouldStop?.call() ?? false) {
      status = GeometryLinearStatus.cancelled;
      break;
    }
    jacobian.transposeMultiply(p, temp);
    jacobian.multiply(temp, ap);
    final pap = geometryDot(p, ap);
    if (!pap.isFinite || pap <= 0 || !rz.isFinite) {
      status = GeometryLinearStatus.numericalFailure;
      break;
    }
    final alpha = rz / pap;
    for (var row = 0; row < m; row++) {
      lambda[row] += alpha * p[row];
      residual[row] -= alpha * ap[row];
    }
    if (geometryNorm(residual) <= relativeTolerance * initial) {
      status = GeometryLinearStatus.converged;
      iterations++;
      break;
    }
    for (var row = 0; row < m; row++) {
      z[row] = residual[row] / diagonal[row];
    }
    final next = geometryDot(residual, z), beta = next / rz;
    for (var row = 0; row < m; row++) {
      p[row] = z[row] + beta * p[row];
    }
    rz = next;
  }
  jacobian.transposeMultiply(lambda, temp);
  final projected = Float64List(n);
  for (var col = 0; col < n; col++) {
    projected[col] = vector[col] - temp[col];
  }
  return finish(projected, iterations, status);
}

/// Rank and column dependencies from column-pivoted Householder QR.
/// This is a local numerical diagnostic, not a global consistency proof.
GeometryRankInfo? geometryRank(
  Float64List matrix,
  int rows,
  int columns, {
  double relativeTolerance = 1e-10,
  bool Function()? shouldStop,
}) {
  final qr = _factorQr(Float64List.fromList(matrix), rows, columns, null,
      relativeTolerance, shouldStop);
  if (qr.cancelled || !qr.finite) return null;
  return GeometryRankInfo(
      qr.rank,
      List<int>.unmodifiable(qr.order.take(qr.rank)),
      List<int>.unmodifiable(qr.order.skip(qr.rank)),
      columnNormEvaluations: qr.columnNormEvaluations,
      columnNormEntryVisits: qr.columnNormEntryVisits,
      normDowndates: qr.normDowndates);
}

class _QrResult {
  _QrResult(this.rank, this.order,
      {this.cancelled = false,
      this.finite = true,
      this.iterationLimit = false,
      this.columnNormEvaluations = 0,
      this.columnNormEntryVisits = 0,
      this.normDowndates = 0});
  final int rank;
  final Int32List order;
  final bool cancelled;
  final bool finite;
  final bool iterationLimit;
  final int columnNormEvaluations, columnNormEntryVisits, normDowndates;
}

_QrResult _factorQr(Float64List a, int m, int n, Float64List? b,
    double tolerance, bool Function()? shouldStop,
    {int? maxSteps}) {
  final order = Int32List.fromList(List<int>.generate(n, (i) => i));
  // Tiny CAD components have only a few dozen trailing entries to scan. Exact
  // pivot norms avoid two cache arrays and guarded-update bookkeeping there;
  // larger components retain the bounded-refresh path below. Both paths use
  // the same scale-safe norms, Householder transformations and stop budgets.
  final exactNorms = m <= 16 && n <= 8;
  final norms = exactNorms ? null : Float64List(n);
  final referenceNorms = exactNorms ? null : Float64List(n);
  var normEvaluations = 0, normEntryVisits = 0, normDowndates = 0;
  var threshold = 0.0;
  var rank = 0;
  _QrResult result(
          {bool cancelled = false,
          bool finite = true,
          bool iterationLimit = false}) =>
      _QrResult(rank, order,
          cancelled: cancelled,
          finite: finite,
          iterationLimit: iterationLimit,
          columnNormEvaluations: normEvaluations,
          columnNormEntryVisits: normEntryVisits,
          normDowndates: normDowndates);

  double columnNorm(int firstRow, int column) {
    normEvaluations++;
    var scale = 0.0, sum = 1.0;
    for (var row = firstRow; row < m; row++) {
      normEntryVisits++;
      final value = a[row * n + column].abs();
      if (!value.isFinite) return value;
      if (value == 0) continue;
      if (scale < value) {
        final ratio = scale / value;
        sum = 1 + sum * ratio * ratio;
        scale = value;
      } else {
        final ratio = value / scale;
        sum += ratio * ratio;
      }
    }
    return scale == 0 ? 0.0 : scale * math.sqrt(sum);
  }

  if (shouldStop?.call() ?? false) return result(cancelled: true);
  if (maxSteps != null && maxSteps <= 0 && m > 0 && n > 0) {
    return result(iterationLimit: true);
  }
  if (!exactNorms) {
    for (var col = 0; col < n; col++) {
      if (shouldStop?.call() ?? false) return result(cancelled: true);
      final norm = columnNorm(0, col);
      if (!norm.isFinite) return result(finite: false);
      norms![col] = referenceNorms![col] = norm;
    }
  }
  for (var k = 0; k < math.min(m, n); k++) {
    if (shouldStop?.call() ?? false) {
      return result(cancelled: true);
    }
    if (maxSteps != null && k >= maxSteps) {
      return result(iterationLimit: true);
    }
    var pivot = k;
    var largest = -1.0;
    for (var col = k; col < n; col++) {
      final norm = exactNorms ? columnNorm(k, col) : norms![col];
      if (!norm.isFinite) return result(finite: false);
      if (norm > largest) {
        largest = norm;
        pivot = col;
      }
    }
    // Downdates select a pivot cheaply; its reflector always uses a freshly
    // measured norm, never an accumulated estimate. A possible rank cutoff
    // refreshes every remaining column before declaring a dependent subspace.
    if (!exactNorms && k != 0) largest = columnNorm(k, pivot);
    if (!largest.isFinite) return result(finite: false);
    if (k == 0) threshold = largest * tolerance;
    if (!exactNorms && k != 0 && (largest <= threshold || largest == 0)) {
      for (var col = k; col < n; col++) {
        if (shouldStop?.call() ?? false) return result(cancelled: true);
        final norm = columnNorm(k, col);
        if (!norm.isFinite) return result(finite: false);
        norms![col] = referenceNorms![col] = norm;
        if (norm > largest) {
          largest = norm;
          pivot = col;
        }
      }
    }
    if (largest <= threshold || largest == 0) break;
    if (pivot != k) {
      for (var row = 0; row < m; row++) {
        final index = row * n;
        final value = a[index + k];
        a[index + k] = a[index + pivot];
        a[index + pivot] = value;
      }
      final index = order[k];
      order[k] = order[pivot];
      order[pivot] = index;
      if (!exactNorms) {
        final norm = norms![k], reference = referenceNorms![k];
        norms[k] = norms[pivot];
        referenceNorms[k] = referenceNorms[pivot];
        norms[pivot] = norm;
        referenceNorms[pivot] = reference;
      }
    }
    final first = a[k * n + k];
    final alpha = first >= 0 ? -largest : largest;
    final denominator = first - alpha;
    final tau = (alpha - first) / alpha;
    a[k * n + k] = alpha;
    for (var row = k + 1; row < m; row++) {
      a[row * n + k] /= denominator;
    }
    for (var col = k + 1; col < n; col++) {
      var projection = a[k * n + col];
      for (var row = k + 1; row < m; row++) {
        projection += a[row * n + k] * a[row * n + col];
      }
      projection *= tau;
      a[k * n + col] -= projection;
      for (var row = k + 1; row < m; row++) {
        a[row * n + col] -= a[row * n + k] * projection;
      }
      final previous = exactNorms ? 0.0 : norms![col];
      if (previous != 0) {
        final removed = a[k * n + col].abs() / previous;
        final remaining = math.max(0.0, (1 - removed) * (1 + removed));
        final sinceRefresh = previous / referenceNorms![col];
        // Subtracting almost equal squares loses rank information. Refresh
        // once the remaining squared norm is small relative to the last
        // explicit norm (sqrt(binary64 epsilon), about 1.49e-8). This is the
        // guarded norm-update criterion analysed in LAPACK Working Note 176.
        if (!remaining.isFinite ||
            remaining * sinceRefresh * sinceRefresh <= 1.4901161193847656e-8) {
          final norm = columnNorm(k + 1, col);
          if (!norm.isFinite) return result(finite: false);
          norms![col] = referenceNorms[col] = norm;
        } else {
          norms![col] = previous * math.sqrt(remaining);
          normDowndates++;
        }
      }
    }
    if (b != null) {
      var projection = b[k];
      for (var row = k + 1; row < m; row++) {
        projection += a[row * n + k] * b[row];
      }
      projection *= tau;
      b[k] -= projection;
      for (var row = k + 1; row < m; row++) {
        b[row] -= a[row * n + k] * projection;
      }
    }
    rank++;
  }
  return result();
}

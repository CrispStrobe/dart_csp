part of 'numeric.dart';

/// Bounded sparse LDLT of the exact damped normal equation.
///
/// Deterministic minimum-degree ordering and symbolic fill are cached for an
/// unchanged CSR pattern. Structural zero entries participate in that pattern;
/// duplicate columns are added with all of their cross terms. Only immutable
/// symbolic data is cached. Numeric factors and solve buffers belong to each
/// call, including calls reentered through [GeometryLinearSolver.solve]'s
/// cancellation callback.
///
/// [GeometryLinearSolver.solve]'s iteration budget counts one factor/solve
/// attempt and at most two additional refinement solves. No pivot jitter or
/// damping adjustment is applied. A successful step must satisfy the original
/// normal equation at the requested relative tolerance. Structural limits
/// return [GeometryLinearStatus.iterationLimit] with zero iterations; the
/// adaptive backend can instead fall back to matrix-free CG.
final class SparseLdltGeometrySolver implements GeometryLinearSolver {
  const SparseLdltGeometrySolver({
    this.maxColumns = 4096,
    this.maxFactorEntries = 262144,
    this.maxSymbolicWork = 20000000,
    this.maxNumericWork = 20000000,
    this.maxAssemblyWork = 4000000,
  });

  final int maxColumns;
  final int maxFactorEntries;

  /// Bound on structural pair visits, ordering scans and pattern materialization.
  final int maxSymbolicWork;

  /// Bound on the number of lower-triangular Schur-complement updates.
  final int maxNumericWork;

  /// Bound on the sum of squared raw CSR row lengths, before pair assembly.
  final int maxAssemblyWork;

  static final Expando<_SparseLdltShape> _patterns =
      Expando<_SparseLdltShape>('geometry sparse LDLT symbolic pattern');

  @override
  GeometryLinearStep solve(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    int maxIterations = 1000,
    double relativeTolerance = 1e-8,
    bool Function()? shouldStop,
  }) =>
      _attempt(
        jacobian,
        residual,
        damping: damping,
        diagonal: diagonal,
        maxIterations: maxIterations,
        relativeTolerance: relativeTolerance,
        shouldStop: shouldStop,
      ) ??
      GeometryLinearStep(
        GeometryLinearStatus.iterationLimit,
        Float64List(jacobian.columns),
        iterations: 0,
        relativeResidual: double.infinity,
      );

  GeometryLinearStep? _attempt(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    required int maxIterations,
    required double relativeTolerance,
    bool Function()? shouldStop,
  }) {
    final n = jacobian.columns;
    if (residual.length != jacobian.rows ||
        diagonal.length != n ||
        maxIterations < 0 ||
        !relativeTolerance.isFinite ||
        relativeTolerance <= 0 ||
        maxColumns < 0 ||
        maxFactorEntries < 0 ||
        maxSymbolicWork < 0 ||
        maxNumericWork < 0 ||
        maxAssemblyWork < 0) {
      throw ArgumentError('Invalid sparse LDLT arguments or resource limits.');
    }
    final polling = _SparseLdltPolling(shouldStop);
    var iterations = 0;
    var relative = double.infinity;
    Float64List? step;
    GeometryLinearStep finish(GeometryLinearStatus status) =>
        GeometryLinearStep(
          status,
          step ?? Float64List(n),
          iterations: iterations,
          relativeResidual: relative,
        );
    try {
      polling.check();
      if (maxIterations == 0) {
        return finish(GeometryLinearStatus.iterationLimit);
      }
      if (n > maxColumns || n > maxFactorEntries) return null;
      if (!damping.isFinite || damping < 0) {
        return finish(GeometryLinearStatus.numericalFailure);
      }
      for (final value in residual) {
        polling.tick();
        if (!value.isFinite) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
      }
      for (final value in diagonal) {
        polling.tick();
        if (!value.isFinite || value < 0) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
      }
      final offsets = jacobian.rowOffsets;
      final columns = jacobian.columnIndices;
      final values = jacobian.values;
      if (offsets.length != jacobian.rows + 1 ||
          columns.length != values.length ||
          offsets[0] != 0 ||
          offsets.last != values.length) {
        throw ArgumentError('Invalid current sparse Jacobian dimensions.');
      }
      var assemblyWork = 0;
      for (var row = 0; row < jacobian.rows; row++) {
        polling.tick();
        final first = offsets[row], end = offsets[row + 1];
        if (first < 0 || first > end || end > values.length) {
          throw ArgumentError('Invalid current sparse row offsets.');
        }
        final length = end - first;
        // Divide before multiplying so oversized rows cannot overflow a count.
        if (length != 0 &&
            length > (maxAssemblyWork - assemblyWork) ~/ length) {
          return null;
        }
        assemblyWork += length * length;
      }
      for (var k = 0; k < values.length; k++) {
        polling.tick();
        if (columns[k] < 0 || columns[k] >= n) {
          throw ArgumentError('Current sparse column index out of range.');
        }
        if (!values[k].isFinite) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
      }
      polling.check();
      final pattern = _patternFor(jacobian, assemblyWork, polling);
      if (pattern == null) return null;
      step = Float64List(n);
      final rhs = Float64List(n);
      for (var row = 0; row < jacobian.rows; row++) {
        polling.check();
        for (var k = pattern.rowOffsets[row];
            k < pattern.rowOffsets[row + 1];
            k++) {
          polling.tick();
          rhs[pattern.inverse[pattern.columnIndices[k]]] -=
              values[k] * residual[row];
        }
      }
      final initial = geometryNorm(rhs);
      if (!initial.isFinite) {
        return finish(GeometryLinearStatus.numericalFailure);
      }
      if (initial == 0) {
        relative = _normalResidual(jacobian, residual, diagonal, damping, step,
            poll: polling.tick);
        polling.check();
        return finish(
          relative.isFinite && relative <= relativeTolerance
              ? GeometryLinearStatus.converged
              : GeometryLinearStatus.numericalFailure,
        );
      }

      // This budget unit includes assembly, factorization and the first solve.
      iterations = 1;
      final factors = [
        for (final rows in pattern.rowsByColumn) Float64List(rows.length),
      ];
      for (var row = 0; row < jacobian.rows; row++) {
        polling.check();
        final first = pattern.rowOffsets[row];
        final end = pattern.rowOffsets[row + 1];
        for (var a = first; a < end; a++) {
          final i = pattern.inverse[pattern.columnIndices[a]];
          final va = values[a];
          // Visit the complete raw Cartesian product. Two entries with the
          // same column contribute both cross terms to the diagonal, even
          // when they cancel or are not adjacent in the input row.
          for (var b = first; b < end; b++) {
            polling.tick();
            final j = pattern.inverse[pattern.columnIndices[b]];
            if (i < j) continue;
            final index = pattern.indexByColumn[j][i]!;
            final updated = factors[j][index] + va * values[b];
            if (!updated.isFinite) {
              return finish(GeometryLinearStatus.numericalFailure);
            }
            factors[j][index] = updated;
          }
        }
      }
      for (var column = 0; column < n; column++) {
        polling.tick();
        final value =
            factors[column][0] + damping * diagonal[pattern.order[column]];
        if (!value.isFinite) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
        factors[column][0] = value;
      }
      final pivots = Float64List(n);
      for (var column = 0; column < n; column++) {
        polling.check();
        final rows = pattern.rowsByColumn[column];
        final factor = factors[column];
        final pivot = factor[0];
        if (!pivot.isFinite || pivot <= 0) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
        pivots[column] = pivot;
        for (var a = 1; a < rows.length; a++) {
          polling.tick();
          factor[a] /= pivot;
          if (!factor[a].isFinite) {
            return finish(GeometryLinearStatus.numericalFailure);
          }
        }
        for (var a = 1; a < rows.length; a++) {
          final target = factors[rows[a]];
          final indices = pattern.indexByColumn[rows[a]];
          final scaled = factor[a] * pivot;
          for (var b = a; b < rows.length; b++) {
            polling.tick();
            final index = indices[rows[b]]!;
            final updated = target[index] - scaled * factor[b];
            if (!updated.isFinite) {
              return finish(GeometryLinearStatus.numericalFailure);
            }
            target[index] = updated;
          }
        }
      }
      var ordered = _sparseLdltSolve(pattern, factors, pivots, rhs, polling);
      for (var column = 0; column < n; column++) {
        polling.tick();
        step[pattern.order[column]] = ordered[column];
      }
      for (var refinement = 0;; refinement++) {
        polling.check();
        // Check using J itself, independently of the assembled normal matrix.
        relative = _normalResidual(jacobian, residual, diagonal, damping, step,
            poll: polling.tick);
        polling.check();
        if (!relative.isFinite) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
        if (relative <= relativeTolerance) {
          return finish(GeometryLinearStatus.converged);
        }
        if (iterations >= maxIterations) {
          return finish(GeometryLinearStatus.iterationLimit);
        }
        if (refinement == 2) {
          return finish(GeometryLinearStatus.numericalFailure);
        }
        iterations++;
        final correction = _sparseLdltCorrection(
          jacobian,
          pattern,
          residual,
          diagonal,
          damping,
          step,
          polling,
        );
        ordered = _sparseLdltSolve(
          pattern,
          factors,
          pivots,
          correction,
          polling,
        );
        for (var column = 0; column < n; column++) {
          polling.tick();
          final original = pattern.order[column];
          step[original] += ordered[column];
          if (!step[original].isFinite) {
            return finish(GeometryLinearStatus.numericalFailure);
          }
        }
      }
    } on _SparseLdltCancelled {
      return finish(GeometryLinearStatus.cancelled);
    } on _SparseLdltNonfinite {
      return finish(GeometryLinearStatus.numericalFailure);
    }
  }

  _SparseLdltPattern? _patternFor(SparseGeometryJacobian jacobian,
      int assemblyWork, _SparseLdltPolling polling) {
    final previous = _patterns[jacobian];
    if (previous != null && previous.matches(jacobian, polling)) {
      if (previous is _SparseLdltPattern) {
        return previous.factorEntries <= maxFactorEntries &&
                previous.symbolicWork <= maxSymbolicWork &&
                previous.numericWork <= maxNumericWork &&
                previous.assemblyWork <= maxAssemblyWork
            ? previous
            : null;
      }
      if (previous is _SparseLdltDeclinedPattern &&
          previous.matchesLimits(this)) {
        return null;
      }
    }
    final pattern = _buildPattern(jacobian, assemblyWork, polling);
    // Declined fill is structural too. Retry when the pattern or any cap
    // changes, but avoid repeating bounded ordering at every nonlinear step.
    _patterns[jacobian] = pattern ?? _SparseLdltDeclinedPattern(jacobian, this);
    return pattern;
  }

  _SparseLdltPattern? _buildPattern(
    SparseGeometryJacobian jacobian,
    int assemblyWork,
    _SparseLdltPolling polling,
  ) {
    final n = jacobian.columns;
    var symbolicWork = jacobian.rows + jacobian.values.length;
    if (symbolicWork > maxSymbolicWork) return null;
    final offsets = List<int>.unmodifiable(jacobian.rowOffsets);
    final columns = List<int>.unmodifiable(jacobian.columnIndices);
    final graph = List<Set<int>>.generate(n, (_) => <int>{});
    var entries = n;
    // Each distinct original or fill edge becomes one stored factor entry.
    // Enforce that lower bound before allocating the corresponding Set nodes.
    bool addEdge(int a, int b) {
      if (a == b || graph[a].contains(b)) return true;
      if (entries >= maxFactorEntries) return false;
      entries++;
      graph[a].add(b);
      graph[b].add(a);
      return true;
    }

    for (var row = 0; row < jacobian.rows; row++) {
      polling.check();
      for (var a = offsets[row]; a < offsets[row + 1]; a++) {
        for (var b = a + 1; b < offsets[row + 1]; b++) {
          polling.tick();
          if (symbolicWork >= maxSymbolicWork) return null;
          symbolicWork++;
          if (!addEdge(columns[a], columns[b])) return null;
        }
      }
    }
    final alive = List<bool>.filled(n, true);
    final order = List<int>.filled(n, 0);
    final inverse = List<int>.filled(n, 0);
    final originalNeighbors = <List<int>>[];
    var numericWork = 0;
    for (var position = 0; position < n; position++) {
      polling.check();
      if (n > maxSymbolicWork - symbolicWork) return null;
      symbolicWork += n;
      var pivot = -1, degree = n + 1;
      // Scanning in original-index order gives stable minimum-degree ties.
      for (var candidate = 0; candidate < n; candidate++) {
        polling.tick();
        if (alive[candidate] && graph[candidate].length < degree) {
          pivot = candidate;
          degree = graph[candidate].length;
        }
      }
      final neighbors = graph[pivot].toList()..sort();
      final left = degree.isEven ? degree ~/ 2 : degree;
      final right = degree.isEven ? degree + 1 : (degree + 1) ~/ 2;
      if (left != 0 && right > (maxNumericWork - numericWork) ~/ left) {
        return null;
      }
      numericWork += left * right;
      if (degree > maxSymbolicWork - symbolicWork) return null;
      symbolicWork += degree;
      order[position] = pivot;
      inverse[pivot] = position;
      originalNeighbors.add(neighbors);
      alive[pivot] = false;
      for (var a = 0; a < neighbors.length; a++) {
        polling.tick();
        graph[neighbors[a]].remove(pivot);
        for (var b = a + 1; b < neighbors.length; b++) {
          polling.tick();
          if (symbolicWork >= maxSymbolicWork) return null;
          symbolicWork++;
          if (!addEdge(neighbors[a], neighbors[b])) return null;
        }
      }
      graph[pivot].clear();
    }
    if (entries > maxSymbolicWork - symbolicWork) return null;
    symbolicWork += entries;
    final rowsByColumn = <List<int>>[];
    final indexByColumn = <Map<int, int>>[];
    for (var column = 0; column < n; column++) {
      polling.check();
      final rows = [
        column,
        for (final neighbor in originalNeighbors[column]) inverse[neighbor],
      ]..sort();
      final indices = <int, int>{};
      for (var index = 0; index < rows.length; index++) {
        polling.tick();
        indices[rows[index]] = index;
      }
      rowsByColumn.add(List<int>.unmodifiable(rows));
      indexByColumn.add(Map<int, int>.unmodifiable(indices));
    }
    return _SparseLdltPattern(
      jacobian.rows,
      n,
      offsets,
      columns,
      List<int>.unmodifiable(order),
      List<int>.unmodifiable(inverse),
      List<List<int>>.unmodifiable(rowsByColumn),
      List<Map<int, int>>.unmodifiable(indexByColumn),
      entries,
      symbolicWork,
      numericWork,
      assemblyWork,
    );
  }
}

class _SparseLdltPattern extends _SparseLdltShape {
  _SparseLdltPattern(
    super.rows,
    super.columns,
    super.rowOffsets,
    super.columnIndices,
    this.order,
    this.inverse,
    this.rowsByColumn,
    this.indexByColumn,
    this.factorEntries,
    this.symbolicWork,
    this.numericWork,
    this.assemblyWork,
  );
  final List<int> order, inverse;
  final List<List<int>> rowsByColumn;
  final List<Map<int, int>> indexByColumn;
  final int factorEntries, symbolicWork, numericWork, assemblyWork;
}

class _SparseLdltDeclinedPattern extends _SparseLdltShape {
  _SparseLdltDeclinedPattern(
      SparseGeometryJacobian jacobian, SparseLdltGeometrySolver solver)
      : maxColumns = solver.maxColumns,
        maxFactorEntries = solver.maxFactorEntries,
        maxSymbolicWork = solver.maxSymbolicWork,
        maxNumericWork = solver.maxNumericWork,
        maxAssemblyWork = solver.maxAssemblyWork,
        super(
            jacobian.rows,
            jacobian.columns,
            List<int>.unmodifiable(jacobian.rowOffsets),
            List<int>.unmodifiable(jacobian.columnIndices));
  final int maxColumns, maxFactorEntries, maxSymbolicWork;
  final int maxNumericWork, maxAssemblyWork;

  bool matchesLimits(SparseLdltGeometrySolver solver) =>
      maxColumns == solver.maxColumns &&
      maxFactorEntries == solver.maxFactorEntries &&
      maxSymbolicWork == solver.maxSymbolicWork &&
      maxNumericWork == solver.maxNumericWork &&
      maxAssemblyWork == solver.maxAssemblyWork;
}

class _SparseLdltShape {
  _SparseLdltShape(
      this.rows, this.columns, this.rowOffsets, this.columnIndices);
  final int rows, columns;
  final List<int> rowOffsets, columnIndices;

  bool matches(SparseGeometryJacobian jacobian, _SparseLdltPolling polling) {
    if (rows != jacobian.rows ||
        columns != jacobian.columns ||
        rowOffsets.length != jacobian.rowOffsets.length ||
        columnIndices.length != jacobian.columnIndices.length) {
      return false;
    }
    for (var i = 0; i < rowOffsets.length; i++) {
      polling.tick();
      if (rowOffsets[i] != jacobian.rowOffsets[i]) return false;
    }
    for (var i = 0; i < columnIndices.length; i++) {
      polling.tick();
      if (columnIndices[i] != jacobian.columnIndices[i]) return false;
    }
    return true;
  }
}

Float64List _sparseLdltSolve(
  _SparseLdltPattern pattern,
  List<Float64List> factors,
  Float64List pivots,
  Float64List rhs,
  _SparseLdltPolling polling,
) {
  final result = Float64List.fromList(rhs);
  for (var column = 0; column < pattern.columns; column++) {
    polling.check();
    final rows = pattern.rowsByColumn[column];
    for (var i = 1; i < rows.length; i++) {
      polling.tick();
      result[rows[i]] -= factors[column][i] * result[column];
      if (!result[rows[i]].isFinite) throw const _SparseLdltNonfinite();
    }
  }
  for (var column = 0; column < pattern.columns; column++) {
    polling.tick();
    result[column] /= pivots[column];
    if (!result[column].isFinite) throw const _SparseLdltNonfinite();
  }
  for (var column = pattern.columns - 1; column >= 0; column--) {
    polling.check();
    final rows = pattern.rowsByColumn[column];
    for (var i = 1; i < rows.length; i++) {
      polling.tick();
      result[column] -= factors[column][i] * result[rows[i]];
    }
    if (!result[column].isFinite) throw const _SparseLdltNonfinite();
  }
  return result;
}

Float64List _sparseLdltCorrection(
  SparseGeometryJacobian jacobian,
  _SparseLdltPattern pattern,
  Float64List residual,
  Float64List diagonal,
  double damping,
  Float64List step,
  _SparseLdltPolling polling,
) {
  final result = Float64List(pattern.columns);
  for (var row = 0; row < pattern.rows; row++) {
    polling.check();
    final first = pattern.rowOffsets[row], end = pattern.rowOffsets[row + 1];
    var value = 0.0;
    for (var k = first; k < end; k++) {
      polling.tick();
      value += jacobian.values[k] * step[pattern.columnIndices[k]];
    }
    value += residual[row];
    if (!value.isFinite) throw const _SparseLdltNonfinite();
    for (var k = first; k < end; k++) {
      polling.tick();
      result[pattern.inverse[pattern.columnIndices[k]]] -=
          jacobian.values[k] * value;
    }
  }
  for (var column = 0; column < pattern.columns; column++) {
    polling.tick();
    final original = pattern.order[column];
    result[column] -= damping * diagonal[original] * step[original];
    if (!result[column].isFinite) throw const _SparseLdltNonfinite();
  }
  return result;
}

class _SparseLdltPolling {
  _SparseLdltPolling(this.callback);
  final bool Function()? callback;
  var _ticks = 0;
  void check() {
    if (callback?.call() ?? false) throw const _SparseLdltCancelled();
  }

  void tick() {
    if (callback != null && ++_ticks >= 256) {
      _ticks = 0;
      check();
    }
  }
}

class _SparseLdltCancelled implements Exception {
  const _SparseLdltCancelled();
}

class _SparseLdltNonfinite implements Exception {
  const _SparseLdltNonfinite();
}

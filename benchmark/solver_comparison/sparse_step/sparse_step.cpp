// Benchmark-only linear step. Geometry, normalization, LM damping, trust updates,
// diagnostics, and transactions remain in the unchanged Dart implementation.
#ifndef EIGEN_MPL2_ONLY
#define EIGEN_MPL2_ONLY
#endif
#include <Eigen/SparseCholesky>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
using Matrix = Eigen::SparseMatrix<double, Eigen::ColMajor, int>;
using Factor = Eigen::SimplicialLDLT<Matrix, Eigen::Lower, Eigen::AMDOrdering<int>>;
constexpr int converged = 0;
constexpr int iteration_limit = 1;
constexpr int numerical_failure = 3;

double norm(const std::vector<double>& x) {
  double scale = 0.0, sum = 1.0;
  for (double value : x) {
    const double a = std::abs(value);
    if (!std::isfinite(a)) return a;
    if (a == 0.0) continue;
    if (scale < a) {
      const double ratio = scale / a;
      sum = 1.0 + sum * ratio * ratio;
      scale = a;
    } else {
      const double ratio = a / scale;
      sum += ratio * ratio;
    }
  }
  return scale == 0.0 ? 0.0 : scale * std::sqrt(sum);
}

struct Contribution { int left, right, destination; };

struct Context {
  int rows, columns, nonzeros;
  std::vector<int32_t> row_offsets, column_indices;
  std::vector<double> values, residual, diagonal, step, gradient, normal_error, temp;
  std::vector<int> diagonal_offsets;
  std::vector<Contribution> contributions;
  Matrix normal;
  Factor factor;
  bool prepared = false;
  double relative_residual = std::numeric_limits<double>::infinity();
  int iterations = 0, factorizations = 0, refinements = 0;

  Context(int m, int n, int nz)
      : rows(m), columns(n), nonzeros(nz), row_offsets(m + 1), column_indices(nz),
        values(nz), residual(m), diagonal(n), step(n), gradient(n), normal_error(n),
        temp(m), diagonal_offsets(n), normal(n, n) {}

  int offset(int row, int column) const {
    const int begin = normal.outerIndexPtr()[column];
    const int end = normal.outerIndexPtr()[column + 1];
    const int* found = std::lower_bound(normal.innerIndexPtr() + begin,
                                     normal.innerIndexPtr() + end, row);
    if (found == normal.innerIndexPtr() + end || *found != row)
      throw std::runtime_error("missing normal-matrix entry");
    return static_cast<int>(found - normal.innerIndexPtr());
  }

  void prepare() {
    if (row_offsets.front() != 0 || row_offsets.back() != nonzeros)
      throw std::invalid_argument("invalid CSR endpoints");
    for (int row = 0; row < rows; ++row) {
      if (row_offsets[row] < 0 || row_offsets[row] > row_offsets[row + 1])
        throw std::invalid_argument("invalid CSR offsets");
    }
    for (int column : column_indices)
      if (column < 0 || column >= columns) throw std::invalid_argument("invalid column");

    // Structural products include zero-valued entries. The fixed pattern and its
    // symbolic factorization therefore survive numerical zero crossings and edits.
    std::vector<Eigen::Triplet<double>> entries;
    for (int column = 0; column < columns; ++column) entries.emplace_back(column, column, 1.0);
    for (int row = 0; row < rows; ++row) {
      for (int a = row_offsets[row]; a < row_offsets[row + 1]; ++a) {
        for (int b = row_offsets[row]; b < row_offsets[row + 1]; ++b) {
          if (column_indices[a] >= column_indices[b])
            entries.emplace_back(column_indices[a], column_indices[b], 1.0);
        }
      }
    }
    normal.setFromTriplets(entries.begin(), entries.end());
    normal.makeCompressed();
    for (int column = 0; column < columns; ++column)
      diagonal_offsets[column] = offset(column, column);
    for (int row = 0; row < rows; ++row) {
      for (int a = row_offsets[row]; a < row_offsets[row + 1]; ++a) {
        for (int b = row_offsets[row]; b < row_offsets[row + 1]; ++b) {
          if (column_indices[a] >= column_indices[b])
            contributions.push_back({a, b, offset(column_indices[a], column_indices[b])});
        }
      }
    }
    factor.analyzePattern(normal);
    if (factor.info() != Eigen::Success) throw std::runtime_error("symbolic analysis failed");
    prepared = true;
  }

  // Identical operation order and norm definition to numeric.dart's
  // _normalResidual: J' (J step + residual) + damping * diagonal * step.
  double verify(double damping) {
    std::fill(normal_error.begin(), normal_error.end(), 0.0);
    for (int row = 0; row < rows; ++row) {
      double value = 0.0;
      for (int k = row_offsets[row]; k < row_offsets[row + 1]; ++k)
        value += values[k] * step[column_indices[k]];
      temp[row] = value + residual[row];
      for (int k = row_offsets[row]; k < row_offsets[row + 1]; ++k)
        normal_error[column_indices[k]] += values[k] * temp[row];
    }
    for (int column = 0; column < columns; ++column)
      normal_error[column] += damping * diagonal[column] * step[column];
    const double initial = norm(gradient);
    return initial == 0.0 ? norm(normal_error) : norm(normal_error) / initial;
  }

  int solve(double damping, int max_iterations, double tolerance) {
    iterations = factorizations = refinements = 0;
    relative_residual = std::numeric_limits<double>::infinity();
    std::fill(step.begin(), step.end(), 0.0);
    if (!prepared || !std::isfinite(damping) || damping < 0.0 ||
        !std::isfinite(tolerance) || tolerance <= 0.0 || max_iterations < 0)
      return numerical_failure;
    for (double x : values) if (!std::isfinite(x)) return numerical_failure;
    for (double x : residual) if (!std::isfinite(x)) return numerical_failure;
    for (double x : diagonal) if (!std::isfinite(x) || x < 0.0) return numerical_failure;
    if (max_iterations == 0) return iteration_limit;
    std::fill(gradient.begin(), gradient.end(), 0.0);
    for (int row = 0; row < rows; ++row)
      for (int k = row_offsets[row]; k < row_offsets[row + 1]; ++k)
        gradient[column_indices[k]] += values[k] * residual[row];
    const double initial = norm(gradient);
    if (!std::isfinite(initial)) return numerical_failure;
    if (initial == 0.0) { relative_residual = 0.0; return converged; }

    std::fill(normal.valuePtr(), normal.valuePtr() + normal.nonZeros(), 0.0);
    for (const auto& term : contributions)
      normal.valuePtr()[term.destination] += values[term.left] * values[term.right];
    for (int column = 0; column < columns; ++column)
      normal.valuePtr()[diagonal_offsets[column]] += damping * diagonal[column];
    for (int k = 0; k < normal.nonZeros(); ++k)
      if (!std::isfinite(normal.valuePtr()[k])) return numerical_failure;

    ++factorizations;
    ++iterations;
    factor.factorize(normal);
    if (factor.info() != Eigen::Success || !factor.vectorD().allFinite() ||
        (factor.vectorD().array() <= 0.0).any()) return numerical_failure;
    Eigen::Map<const Eigen::VectorXd> g(gradient.data(), columns);
    Eigen::VectorXd solution = factor.solve(-g);
    if (factor.info() != Eigen::Success || !solution.allFinite()) return numerical_failure;
    std::copy(solution.data(), solution.data() + columns, step.begin());
    relative_residual = verify(damping);
    // At most two refinements of exactly the supplied system; no changed damping,
    // regularization, tolerance, or fallback method can conceal a failed solve.
    while (std::isfinite(relative_residual) && relative_residual > tolerance &&
           iterations < std::min(max_iterations, 3)) {
      Eigen::Map<const Eigen::VectorXd> error(normal_error.data(), columns);
      Eigen::VectorXd correction = factor.solve(-error);
      ++iterations;
      ++refinements;
      if (factor.info() != Eigen::Success || !correction.allFinite()) return numerical_failure;
      for (int column = 0; column < columns; ++column) step[column] += correction[column];
      relative_residual = verify(damping);
    }
    if (!std::isfinite(relative_residual)) return numerical_failure;
    if (relative_residual <= tolerance) return converged;
    return iterations >= max_iterations ? iteration_limit : numerical_failure;
  }
};
}  // namespace

extern "C" {
void* ds_create(int32_t rows, int32_t columns, int32_t nonzeros) {
  try {
    if (rows < 0 || columns <= 0 || nonzeros < 0) return nullptr;
    return new Context(rows, columns, nonzeros);
  } catch (...) { return nullptr; }
}
void ds_destroy(void* handle) { delete static_cast<Context*>(handle); }
int32_t* ds_row_offsets(void* handle) { return static_cast<Context*>(handle)->row_offsets.data(); }
int32_t* ds_column_indices(void* handle) { return static_cast<Context*>(handle)->column_indices.data(); }
double* ds_values(void* handle) { return static_cast<Context*>(handle)->values.data(); }
double* ds_residual(void* handle) { return static_cast<Context*>(handle)->residual.data(); }
double* ds_diagonal(void* handle) { return static_cast<Context*>(handle)->diagonal.data(); }
double* ds_step(void* handle) { return static_cast<Context*>(handle)->step.data(); }
int32_t ds_prepare(void* handle) {
  try { static_cast<Context*>(handle)->prepare(); return 0; }
  catch (...) { return numerical_failure; }
}
int32_t ds_solve(void* handle, double damping, int32_t max_iterations, double tolerance) {
  try { return static_cast<Context*>(handle)->solve(damping, max_iterations, tolerance); }
  catch (...) { return numerical_failure; }
}
double ds_relative_residual(void* handle) { return static_cast<Context*>(handle)->relative_residual; }
int32_t ds_iterations(void* handle) { return static_cast<Context*>(handle)->iterations; }
int32_t ds_factorizations(void* handle) { return static_cast<Context*>(handle)->factorizations; }
int32_t ds_refinements(void* handle) { return static_cast<Context*>(handle)->refinements; }
int64_t ds_normal_nonzeros(void* handle) { return static_cast<Context*>(handle)->normal.nonZeros(); }
}

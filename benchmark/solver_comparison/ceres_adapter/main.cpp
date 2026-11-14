#include <ceres/ceres.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;
using Point = std::array<double, 2>;

constexpr const char* kCeresCommit = "e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72";
constexpr const char* kEigenCommit = "3147391d946bb4b6c68edd901f2add6ac1f31f8c";
constexpr const char* kAbseilCommit = "9ac7062b1860d895fb5a8cbf58c3e9ef8f674b5f";
constexpr const char* kJsonCommit = "55f93686c01528224f448c19128836e7df245f72";
constexpr int kDenseQrCoordinateLimit = 128;

enum class Kind { Distance, Horizontal, Vertical, Coincident };

struct Constraint {
  Kind kind;
  std::size_t a;
  std::size_t b;
  double value;
};

struct Orientation {
  std::size_t a;
  std::size_t b;
  std::size_t c;
  double sign;
};

struct Fixture {
  std::string id;
  std::vector<Point> points;
  std::vector<std::size_t> fixed;
  std::vector<Constraint> constraints;
  std::vector<Orientation> orientations;
};

struct Request {
  std::string mode;
  int warmups;
  int samples;
  int max_iterations;
  double tolerance;
  Fixture fixture;
  std::vector<std::vector<double>> edits;
};

std::int64_t Nanoseconds(Clock::time_point a, Clock::time_point b) {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(b - a).count();
}

std::size_t Index(const Json& value, std::size_t count) {
  const auto index = value.get<std::int64_t>();
  if (index < 0 || static_cast<std::size_t>(index) >= count) {
    throw std::runtime_error("Point index outside fixture");
  }
  return static_cast<std::size_t>(index);
}

double Finite(const Json& value) {
  const auto number = value.get<double>();
  if (!std::isfinite(number)) throw std::runtime_error("Nonfinite input number");
  return number;
}

Request Parse(const Json& input) {
  if (input.value("schema_version", 1) != 1) {
    throw std::runtime_error("Unsupported schema_version");
  }
  Request request;
  request.mode = input.at("mode").get<std::string>();
  if (request.mode != "cold" && request.mode != "warm") {
    throw std::runtime_error("mode must be cold or warm");
  }
  request.warmups = input.value("warmups", 0);
  request.samples = input.at("samples").get<int>();
  request.max_iterations = input.value("max_iterations", 200);
  request.tolerance = Finite(input.at("tolerance"));
  if (request.warmups < 0 || request.samples < 1 ||
      request.max_iterations < 1 || request.tolerance <= 0.0) {
    throw std::runtime_error("Invalid run counts or tolerance");
  }
  const auto& fixture = input.at("fixture");
  request.fixture.id = fixture.at("id").get<std::string>();
  for (const auto& point : fixture.at("points")) {
    if (!point.is_array() || point.size() != 2) {
      throw std::runtime_error("Each point must contain x,y");
    }
    request.fixture.points.push_back({Finite(point[0]), Finite(point[1])});
  }
  const auto count = request.fixture.points.size();
  if (count == 0) throw std::runtime_error("Fixture has no points");
  for (const auto& fixed : fixture.value("fixed", Json::array())) {
    request.fixture.fixed.push_back(Index(fixed, count));
  }
  auto& fixed = request.fixture.fixed;
  std::sort(fixed.begin(), fixed.end());
  fixed.erase(std::unique(fixed.begin(), fixed.end()), fixed.end());
  for (const auto& item : fixture.at("constraints")) {
    const auto kind = item.at("kind").get<std::string>();
    Kind type;
    if (kind == "distance") type = Kind::Distance;
    else if (kind == "horizontal") type = Kind::Horizontal;
    else if (kind == "vertical") type = Kind::Vertical;
    else if (kind == "coincident") type = Kind::Coincident;
    else throw std::runtime_error("Unsupported constraint kind: " + kind);
    const double target = type == Kind::Distance ? Finite(item.at("value")) : 0.0;
    if (target < 0.0) throw std::runtime_error("Distance cannot be negative");
    request.fixture.constraints.push_back(
        {type, Index(item.at("a"), count), Index(item.at("b"), count), target});
  }
  for (const auto& item : fixture.value("orientations", Json::array())) {
    if (!item.is_array() || item.size() != 4) {
      throw std::runtime_error("Orientation must contain a,b,c,sign");
    }
    const auto sign = Finite(item[3]);
    if (sign != 1.0 && sign != -1.0) {
      throw std::runtime_error("Orientation sign must be 1 or -1");
    }
    request.fixture.orientations.push_back(
        {Index(item[0], count), Index(item[1], count), Index(item[2], count), sign});
  }
  for (const auto& edit : input.value("edits", Json::array())) {
    std::vector<double> values;
    for (const auto& value : edit.at("values")) values.push_back(Finite(value));
    if (values.size() != request.fixture.constraints.size()) {
      throw std::runtime_error("Edit must contain one value per constraint");
    }
    for (std::size_t i = 0; i < values.size(); ++i) {
      if (request.fixture.constraints[i].kind == Kind::Distance && values[i] < 0.0) {
        throw std::runtime_error("Edited distance cannot be negative");
      }
    }
    request.edits.push_back(std::move(values));
  }
  if (request.edits.empty()) {
    std::vector<double> values;
    for (const auto& constraint : request.fixture.constraints) {
      values.push_back(constraint.value);
    }
    request.edits.push_back(std::move(values));
  }
  return request;
}

// Targets point into Model::constraints, whose storage is never resized.
// Analytic derivatives avoid any Dart/FFI callback in residual evaluation.
class PairCost final : public ceres::CostFunction {
 public:
  explicit PairCost(const Constraint* constraint) : constraint_(constraint) {
    set_num_residuals(constraint_->kind == Kind::Coincident ? 2 : 1);
    mutable_parameter_block_sizes()->push_back(2);
    if (constraint_->a != constraint_->b) {
      mutable_parameter_block_sizes()->push_back(2);
    }
  }

  bool Evaluate(double const* const* parameters, double* residuals,
                double** jacobians) const override {
    const bool self = constraint_->a == constraint_->b;
    const double* a = parameters[0];
    const double* b = self ? parameters[0] : parameters[1];
    const double dx = b[0] - a[0];
    const double dy = b[1] - a[1];
    const int residual_count = num_residuals();
    if (jacobians) {
      for (std::size_t block = 0; block < parameter_block_sizes().size(); ++block) {
        if (jacobians[block]) {
          std::fill(jacobians[block], jacobians[block] + 2 * residual_count, 0.0);
        }
      }
    }
    switch (constraint_->kind) {
      case Kind::Distance: {
        const double distance = std::hypot(dx, dy);
        residuals[0] = distance - constraint_->value;
        // At zero length the distance is nondifferentiable. A zero
        // subgradient can report a stationary point; acceptance still
        // rejects it when it fails the physical distance constraint.
        if (jacobians && !self && distance > 0.0) {
          if (jacobians[0]) {
            jacobians[0][0] = -dx / distance;
            jacobians[0][1] = -dy / distance;
          }
          if (jacobians[1]) {
            jacobians[1][0] = dx / distance;
            jacobians[1][1] = dy / distance;
          }
        }
        break;
      }
      case Kind::Horizontal:
        residuals[0] = dy;
        if (jacobians && !self) {
          if (jacobians[0]) jacobians[0][1] = -1.0;
          if (jacobians[1]) jacobians[1][1] = 1.0;
        }
        break;
      case Kind::Vertical:
        residuals[0] = dx;
        if (jacobians && !self) {
          if (jacobians[0]) jacobians[0][0] = -1.0;
          if (jacobians[1]) jacobians[1][0] = 1.0;
        }
        break;
      case Kind::Coincident:
        residuals[0] = dx;
        residuals[1] = dy;
        if (jacobians && !self) {
          if (jacobians[0]) {
            jacobians[0][0] = -1.0;
            jacobians[0][3] = -1.0;
          }
          if (jacobians[1]) {
            jacobians[1][0] = 1.0;
            jacobians[1][3] = 1.0;
          }
        }
        break;
    }
    return std::isfinite(residuals[0]) &&
           (residual_count == 1 || std::isfinite(residuals[1]));
  }

 private:
  const Constraint* constraint_;
};

struct PhysicalResult {
  bool accepted;
  bool orientations_ok;
  double maximum_error;
};

struct Model {
  const Fixture& fixture;
  std::vector<Point> points;
  std::vector<Constraint> constraints;
  std::unique_ptr<ceres::Problem> problem;
  int active_coordinates;
  int equations = 0;

  explicit Model(const Fixture& input)
      : fixture(input), points(input.points), constraints(input.constraints),
        problem(std::make_unique<ceres::Problem>()),
        active_coordinates(static_cast<int>(2 * (points.size() - input.fixed.size()))) {
    for (auto& point : points) problem->AddParameterBlock(point.data(), 2);
    for (const auto index : input.fixed) {
      problem->SetParameterBlockConstant(points[index].data());
    }
    for (auto& constraint : constraints) {
      auto* cost = new PairCost(&constraint);
      equations += cost->num_residuals();
      if (constraint.a == constraint.b) {
        problem->AddResidualBlock(cost, nullptr, points[constraint.a].data());
      } else {
        problem->AddResidualBlock(cost, nullptr, points[constraint.a].data(),
                                  points[constraint.b].data());
      }
    }
  }

  void SetTargets(const std::vector<double>& values) {
    for (std::size_t i = 0; i < constraints.size(); ++i) {
      if (constraints[i].kind == Kind::Distance) constraints[i].value = values[i];
    }
  }

  // Copy elements without replacing vector storage: Ceres retains pointers.
  void SetPoints(const std::vector<Point>& seed) {
    std::copy(seed.begin(), seed.end(), points.begin());
  }

  PhysicalResult Check(double tolerance) const {
    double maximum_error = 0.0;
    for (const auto& point : points) {
      if (!std::isfinite(point[0]) || !std::isfinite(point[1])) {
        return {false, false, std::numeric_limits<double>::infinity()};
      }
    }
    for (const auto index : fixture.fixed) {
      maximum_error = std::max(maximum_error,
          std::hypot(points[index][0] - fixture.points[index][0],
                     points[index][1] - fixture.points[index][1]));
    }
    for (const auto& constraint : constraints) {
      const auto& a = points[constraint.a];
      const auto& b = points[constraint.b];
      const double dx = b[0] - a[0];
      const double dy = b[1] - a[1];
      double error = 0.0;
      switch (constraint.kind) {
        case Kind::Distance: error = std::abs(std::hypot(dx, dy) - constraint.value); break;
        case Kind::Horizontal: error = std::abs(dy); break;
        case Kind::Vertical: error = std::abs(dx); break;
        case Kind::Coincident: error = std::hypot(dx, dy); break;
      }
      if (!std::isfinite(error)) {
        return {false, false, std::numeric_limits<double>::infinity()};
      }
      maximum_error = std::max(maximum_error, error);
    }
    bool orientations_ok = true;
    for (const auto& orientation : fixture.orientations) {
      const auto& a = points[orientation.a];
      const auto& b = points[orientation.b];
      const auto& c = points[orientation.c];
      const double cross = (b[0] - a[0]) * (c[1] - a[1]) -
                           (b[1] - a[1]) * (c[0] - a[0]);
      if (!std::isfinite(cross) || cross * orientation.sign <= 0.0) {
        orientations_ok = false;
      }
    }
    return {maximum_error <= tolerance && orientations_ok, orientations_ok, maximum_error};
  }
};

class PhysicalStop final : public ceres::IterationCallback {
 public:
  PhysicalStop(const Model& model, double tolerance)
      : model_(model), tolerance_(tolerance) {}
  ceres::CallbackReturnType operator()(const ceres::IterationSummary&) override {
    ++checks;
    return model_.Check(tolerance_).accepted ? ceres::SOLVER_TERMINATE_SUCCESSFULLY
                                           : ceres::SOLVER_CONTINUE;
  }
  int checks = 0;
 private:
  const Model& model_;
  double tolerance_;
};

void Run(const Request& request) {
  std::unique_ptr<Model> model;
  std::vector<Point> last_accepted = request.fixture.points;
  bool restore_before_next = false;
  for (int index = -request.warmups; index < request.samples; ++index) {
    const auto edit_index = static_cast<std::size_t>(index + request.warmups) % request.edits.size();
    const auto& values = request.edits[edit_index];
    // Destruction of the previous cold model belongs to its lifecycle.
    // Include it in the next cold build/update interval.
    const auto begin = Clock::now();
    const bool model_reused = request.mode == "warm" && static_cast<bool>(model);
    if (!model_reused) {
      model.reset();
      model = std::make_unique<Model>(request.fixture);
    } else if (restore_before_next) {
      model->SetPoints(last_accepted);
    }
    model->SetTargets(values);
    PhysicalStop physical_stop(*model, request.tolerance);
    ceres::Solver::Options options;
    options.num_threads = 1;
    options.max_num_iterations = request.max_iterations;
    options.minimizer_type = ceres::TRUST_REGION;
    options.trust_region_strategy_type = ceres::LEVENBERG_MARQUARDT;
    options.linear_solver_type = model->active_coordinates <= kDenseQrCoordinateLimit
        ? ceres::DENSE_QR : ceres::SPARSE_NORMAL_CHOLESKY;
    options.dense_linear_algebra_library_type = ceres::EIGEN;
    options.sparse_linear_algebra_library_type = ceres::EIGEN_SPARSE;
    options.function_tolerance = 0.0;
    options.parameter_tolerance = 0.0;
    options.gradient_tolerance = 0.0;
    options.update_state_every_iteration = true;
    options.callbacks.push_back(&physical_stop);
    options.minimizer_progress_to_stdout = false;
    options.logging_type = ceres::SILENT;
    const auto solve_begin = Clock::now();
    ceres::Solver::Summary summary;
    ceres::Solve(options, model->problem.get(), &summary);
    const auto solve_end = Clock::now();
    const auto coordinates = model->points;
    const auto end = Clock::now();

    // This independent output validation and JSON serialization are untimed.
    // The native convergence callback above is necessarily timed solver work.
    const auto physical = model->Check(request.tolerance);
    if (physical.accepted) last_accepted = coordinates;
    restore_before_next = !physical.accepted;
    const bool native_success = summary.termination_type == ceres::CONVERGENCE ||
                                summary.termination_type == ceres::USER_SUCCESS;
    const Json output = {
      {"schema_version", 1}, {"engine", "ceres"}, {"engine_version", CERES_VERSION_STRING},
      {"engine_commit", kCeresCommit}, {"eigen_commit", kEigenCommit},
      {"abseil_commit", kAbseilCommit}, {"json_commit", kJsonCommit},
      {"mode", request.mode}, {"fixture_id", request.fixture.id}, {"index", index},
      {"warmup", index < 0}, {"edit_index", edit_index},
      {"build_ns", Nanoseconds(begin, solve_begin)},
      {"solve_ns", Nanoseconds(solve_begin, solve_end)},
      {"elapsed_ns", Nanoseconds(begin, end)}, {"coordinates", coordinates},
      {"reported_success", native_success},
      {"status", ceres::TerminationTypeToString(summary.termination_type)},
      {"native_usable", summary.IsSolutionUsable()}, {"accepted", physical.accepted},
      {"orientations_ok", physical.orientations_ok},
      {"maximum_physical_error", physical.maximum_error},
      {"iterations", summary.iterations.size()}, {"model_reused", model_reused},
      {"active_coordinates", model->active_coordinates}, {"equations", model->equations},
      {"linear_solver", ceres::LinearSolverTypeToString(summary.linear_solver_type_used)},
      {"linear_solver_requested", ceres::LinearSolverTypeToString(options.linear_solver_type)},
      {"max_iterations", request.max_iterations}, {"num_threads", 1},
      {"dense_qr_max_active_coordinates", kDenseQrCoordinateLimit},
      {"function_tolerance", options.function_tolerance},
      {"gradient_tolerance", options.gradient_tolerance},
      {"parameter_tolerance", options.parameter_tolerance},
      {"physical_tolerance", request.tolerance},
      {"trust_region_strategy", "LEVENBERG_MARQUARDT"},
      {"sparse_backend", "EIGEN_SPARSE"},
      {"physical_callback_checks", physical_stop.checks},
      {"termination_message", summary.message}
    };
    std::cout << output.dump() << '\n' << std::flush;
  }
}

int main(int argc, char** argv) {
  try {
    if (argc != 2) throw std::runtime_error("Usage: ceres_geometry_adapter REQUEST.json");
    std::ifstream input(argv[1]);
    if (!input) throw std::runtime_error("Cannot open request file");
    Json data;
    input >> data;
    Run(Parse(data));
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "ceres_geometry_adapter: " << error.what() << '\n';
    return 2;
  }
}

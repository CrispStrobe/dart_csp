/// Nonlinear closed-loop linkage cold/edit measurements with an independent
/// circle-intersection oracle. Run with --check-only to validate without timing
/// output. Both this file and example/nonlinear_linkage.dart must be identical
/// in paired before/after checkouts; only baseline-compatible public APIs are
/// used. The timed edits are regular configurations, not toggle stress cases.
library;

import 'dart:convert';

import 'package:dart_csp/geometry.dart';

import '../example/nonlinear_linkage.dart';

double _percentile(List<int> samples, double probability) {
  final sorted = [...samples]..sort();
  return sorted[((sorted.length - 1) * probability).ceil()].toDouble();
}

Map<String, Object> _measurement(
        List<int> samples, GeometrySolveResult result) =>
    {
      'p50': _percentile(samples, 0.5),
      'p95': _percentile(samples, 0.95),
      'samples_us': samples,
      'components_solved': result.stats.componentsSolved,
      'components_reused': result.stats.componentsReused,
      'residual_evaluations': result.stats.residualEvaluations,
      'jacobian_evaluations': result.stats.jacobianEvaluations,
      'linear_solves': result.stats.linearSolves,
      'linear_iterations': result.stats.linearIterations,
      'nonlinear_iterations': result.stats.nonlinearIterations,
      'rank_factorizations': result.stats.rankFactorizations,
      'rank_reuses': result.stats.rankReuses,
    };

void main(List<String> arguments) {
  if (arguments.any((argument) => argument != '--check-only')) {
    throw ArgumentError('Only --check-only is supported.');
  }
  final checkOnly = arguments.contains('--check-only');
  final warmups = checkOnly ? 0 : 5;
  final repetitions = checkOnly ? 1 : 25;
  final compiled = buildFourBarLinkage();
  final session = compiled.createSession();
  checkFourBarSolution(session.solve());
  final cold = <int>[], warm = <int>[];
  late GeometrySolveResult coldResult, warmResult;
  for (var i = -warmups; i < repetitions; i++) {
    final angle = i.isEven ? 0.6 : 0.9;
    void runCold() {
      final watch = Stopwatch()..start();
      final candidate = buildFourBarLinkage().createSession();
      candidate.setParameterValues('input_angle', [angle]);
      coldResult = candidate.solve();
      watch.stop();
      checkFourBarSolution(coldResult, angle: angle);
      if (i >= 0) cold.add(watch.elapsedMicroseconds);
    }

    void runWarm() {
      final watch = Stopwatch()..start();
      session.setParameterValues('input_angle', [angle]);
      warmResult = session.solve();
      watch.stop();
      checkFourBarSolution(warmResult, angle: angle);
      if (i >= 0) warm.add(watch.elapsedMicroseconds);
    }

    if (i.isEven) {
      runCold();
      runWarm();
    } else {
      runWarm();
      runCold();
    }
  }
  if (checkOnly) {
    print('Nonlinear four-bar cold/edit coordinate, branch, closure and '
        'plane checks passed.');
    return;
  }
  print(jsonEncode({
    'fixture': 'closed four-bar linkage in a tilted 3D workplane; angle edit',
    'parameter_blocks': compiled.parameters.length,
    'active_tangent_coordinates': compiled.activeTangentDimension,
    'components': compiled.componentCount,
    'jacobian_nonzeros': compiled.jacobianNonzeros,
    'warmup_pairs': warmups,
    'measured_pairs': repetitions,
    'units': 'microseconds',
    'cold_build_compile_solve': _measurement(cold, coldResult),
    'warm_edit_solve': _measurement(warm, warmResult),
    'independent_coordinate_branch_and_closure_checks': 'passed',
    'scope': 'local regular-configuration continuation on one assembly '
        'branch; no general convergence or near-toggle latency guarantee',
  }));
}

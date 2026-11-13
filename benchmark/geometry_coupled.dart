/// Coupled 3D dimensional-chain regeneration with an independent coordinate
/// oracle. Run with `dart run benchmark/geometry_coupled.dart`; `--check-only`
/// validates one cold solve and one edit without reporting timings.
///
/// Unlike independent circles, all 72 active coordinates belong to one
/// component. This exercises sparse linear solving and bounded rank diagnostics
/// on an unchanged Jacobian after a dimension edit. The harness uses the API
/// available before this optimization so identical copies can measure both
/// revisions. It is a linear dimensional fixture, not a nonlinear CAD workload.
library;

import 'dart:convert';

import 'package:dart_csp/geometry.dart';

const coupledPointCount = 24;
const coupledOrigin = [-4.0, 3.0, 1.0];
const coupledInitialPitch = [1.0, 0.25, -0.125];

CompiledGeometryModel buildCoupledChain() => GeometryModel(
      parameters: [
        GeometryParameterBlock(
            id: 'origin', values: coupledOrigin, fixed: true),
        GeometryParameterBlock(
            id: 'pitch', values: coupledInitialPitch, fixed: true),
        for (var i = 0; i < coupledPointCount; i++)
          GeometryParameterBlock(id: 'p$i', values: [
            coupledOrigin[0] + (i + 1) * 0.8 + 0.1,
            coupledOrigin[1] + (i + 1) * 0.2 - 0.15,
            coupledOrigin[2] - (i + 1) * 0.05 + 0.3,
          ]),
      ],
      constraints: [
        for (var i = 0; i < coupledPointCount; i++)
          GeometryResidualBlock.autoDiff(
            id: 'link$i',
            parameterIds: [
              if (i == 0) 'origin' else 'p${i - 1}',
              'p$i',
              'pitch',
            ],
            residualCount: 3,
            evaluate: (p) => [
              for (var coordinate = 0; coordinate < 3; coordinate++)
                p[1][coordinate] - p[0][coordinate] - p[2][coordinate],
            ],
          ),
      ],
    ).compile();

void checkCoupledChain(GeometrySolveResult result, List<double> pitch) {
  if (!result.isSuccess || result.localDegreesOfFreedom != 0) {
    throw StateError('Coupled chain failed: ${result.status} '
        '${result.message}; freedoms=${result.localDegreesOfFreedom}.');
  }
  if (result.stats.componentsSolved != 1 ||
      result.stats.componentsReused != 0) {
    throw StateError('The chain must solve one coupled component.');
  }
  for (var i = 0; i < coupledPointCount; i++) {
    final point = result.values['p$i']!;
    final previous = i == 0 ? coupledOrigin : result.values['p${i - 1}']!;
    for (var coordinate = 0; coordinate < 3; coordinate++) {
      final expected = coupledOrigin[coordinate] + (i + 1) * pitch[coordinate];
      final linkError =
          point[coordinate] - previous[coordinate] - pitch[coordinate];
      if ((point[coordinate] - expected).abs() > coupledPointCount * 1.01e-8 ||
          linkError.abs() > 1.01e-8) {
        throw StateError('Independent chain oracle failed at p$i '
            'coordinate $coordinate.');
      }
    }
  }
}

double _percentile(List<int> samples, double p) {
  final sorted = [...samples]..sort();
  return sorted[((sorted.length - 1) * p).ceil()].toDouble();
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
    };

void main(List<String> arguments) {
  if (arguments.any((arg) => arg != '--check-only')) {
    throw ArgumentError('Only --check-only is supported.');
  }
  final checkOnly = arguments.contains('--check-only');
  final warmups = checkOnly ? 0 : 5;
  final repetitions = checkOnly ? 1 : 25;
  final compiled = buildCoupledChain();
  final warmSession = compiled.createSession();
  checkCoupledChain(warmSession.solve(), coupledInitialPitch);
  final cold = <int>[], warm = <int>[];
  late GeometrySolveResult coldResult, warmResult;
  for (var i = -warmups; i < repetitions; i++) {
    final pitch = i.isEven ? [1.1, 0.3, -0.1] : [1.2, 0.2, -0.15];
    void runCold() {
      final watch = Stopwatch()..start();
      final session = buildCoupledChain().createSession();
      session.setParameterValues('pitch', pitch);
      coldResult = session.solve();
      watch.stop();
      checkCoupledChain(coldResult, pitch);
      if (i >= 0) cold.add(watch.elapsedMicroseconds);
    }

    void runWarm() {
      final watch = Stopwatch()..start();
      warmSession.setParameterValues('pitch', pitch);
      warmResult = warmSession.solve();
      watch.stop();
      checkCoupledChain(warmResult, pitch);
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
    print('Coupled chain cold/edit independent coordinate checks passed.');
    return;
  }
  print(jsonEncode({
    'fixture': '24 coupled 3D points; edit fixed XYZ pitch',
    'parameter_blocks': coupledPointCount + 2,
    'active_tangent_coordinates': compiled.activeTangentDimension,
    'components': compiled.componentCount,
    'jacobian_nonzeros': compiled.jacobianNonzeros,
    'warmup_pairs': warmups,
    'measured_pairs': repetitions,
    'units': 'microseconds',
    'cold_build_compile_solve': _measurement(cold, coldResult),
    'warm_edit_solve': _measurement(warm, warmResult),
    'independent_coordinate_and_residual_checks': 'passed',
  }));
}

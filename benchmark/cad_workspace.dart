/// Transactional CAD geometry candidate reuse with an independent coordinate
/// oracle. APIs are baseline-compatible. Times are single builds/edits;
/// physical solves are inside timers and oracle checks are outside.
library;

import 'dart:convert';

import 'package:dart_csp/cad.dart';

const _points = 24;

CadFeatureDocument _document() {
  final model = GeometryModel(parameters: [
    GeometryParameterBlock(id: 'pitch', values: [1], fixed: true),
    GeometryParameterBlock(id: 'origin', values: [0, 0, 0], fixed: true),
    for (var i = 0; i < _points; i++)
      GeometryParameterBlock(
          id: 'p$i', values: [i + 1.0, (i + 1) * .25, (i + 1) * -.125]),
  ], constraints: [
    for (var i = 0; i < _points; i++)
      GeometryResidualBlock.autoDiff(
        id: 'link$i',
        parameterIds: [if (i == 0) 'origin' else 'p${i - 1}', 'p$i', 'pitch'],
        residualCount: 3,
        evaluate: (p) => [
          p[1][0] - p[0][0] - p[2][0],
          p[1][1] - p[0][1] - p[2][0] * .25,
          p[1][2] - p[0][2] + p[2][0] * .125,
        ],
      ),
  ]).compile();
  return CadFeatureDocument(
    kernel: const ReferenceCadKernel(),
    parameters: CadParameters({'pitch': 1}),
    features: [
      constrainedGeometryFeature(
        id: 'geometry',
        model: model,
        dimensionBindings: {'pitch': CadExpression.parameter('pitch')},
      ),
    ],
  );
}

GeometrySolveResult _check(CadFeatureDocument document,
    CadRegenerationResult regeneration, double pitch) {
  if (!regeneration.isSuccess) {
    throw StateError('Regeneration rejected: ${regeneration.issues}');
  }
  final result = document.state.output<GeometrySolveResult>('geometry');
  if (!result.isSuccess ||
      result.localDegreesOfFreedom != 0 ||
      result.maxToleranceRatio > 1) {
    throw StateError('Invalid geometric candidate.');
  }
  for (var i = 0; i < _points; i++) {
    final actual = result.values['p$i']!;
    final previous = result.values[i == 0 ? 'origin' : 'p${i - 1}']!;
    for (var c = 0; c < 3; c++) {
      final factor = [1.0, .25, -.125][c];
      if ((actual[c] - (i + 1) * pitch * factor).abs() > _points * 1.01e-8 ||
          (actual[c] - previous[c] - pitch * factor).abs() > 1.01e-8) {
        throw StateError('Coordinate oracle failed for p$i/$c.');
      }
    }
  }
  return result;
}

Map<String, Object> _measurement(List<int> samples, GeometrySolveResult r) {
  final sorted = [...samples]..sort();
  return {
    'p50': sorted[sorted.length ~/ 2],
    'p95': sorted[(sorted.length * .95).ceil() - 1],
    'samples_us': samples,
    'rank_factorizations': r.stats.rankFactorizations,
    'rank_reuses': r.stats.rankReuses,
    'residual_evaluations': r.stats.residualEvaluations,
    'jacobian_evaluations': r.stats.jacobianEvaluations,
    'linear_solves': r.stats.linearSolves,
  };
}

void main(List<String> arguments) {
  if (arguments.any((a) => a != '--check-only')) {
    throw ArgumentError('Only --check-only is supported.');
  }
  final checkOnly = arguments.contains('--check-only');
  final warmups = checkOnly ? 0 : 5, samples = checkOnly ? 1 : 25;
  final retained = _document();
  _check(retained, retained.regenerate(), 1);
  final cold = <int>[], warm = <int>[];
  late GeometrySolveResult coldResult, warmResult;
  for (var i = -warmups; i < samples; i++) {
    final pitch = i.isEven ? 1.1 : 1.2;
    void runCold() {
      final watch = Stopwatch()..start();
      final document = _document();
      final regeneration = document.regenerate(changes: {'pitch': pitch});
      watch.stop();
      coldResult = _check(document, regeneration, pitch);
      if (i >= 0) cold.add(watch.elapsedMicroseconds);
    }

    void runWarm() {
      final watch = Stopwatch()..start();
      final regeneration = retained.regenerate(changes: {'pitch': pitch});
      watch.stop();
      warmResult = _check(retained, regeneration, pitch);
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
    print('Transactional CAD coordinate checks passed.');
    return;
  }
  print(jsonEncode({
    'fixture': '24-point coupled CAD geometry feature; scalar pitch edit',
    'active_coordinates': _points * 3,
    'components': 1,
    'warmup_pairs': warmups,
    'measured_pairs': samples,
    'units': 'microseconds',
    'cold_build_compile_regenerate': _measurement(cold, coldResult),
    'warm_edit_regenerate': _measurement(warm, warmResult),
    'independent_coordinate_checks': 'passed',
    'scope': 'transactional linear dimensional fixture; no solid kernel work',
  }));
}

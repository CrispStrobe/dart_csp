/// Bounded paired measurements; correctness is checked outside timed sections.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_csp/cad.dart';

import '../example/parametric_bracket.dart';

void _check(CadFeatureDocument document) {
  final state = document.state, p = state.parameters;
  final expected = (p['width'] * p['height'] -
          2 * math.pi * math.pow(p['holeDiameter'] / 2, 2)) *
      p['thickness'];
  final actual = state.output<CadBody>('plate').volume;
  if (!actual.isFinite ||
      !expected.isFinite ||
      (actual - expected).abs() > 1e-4 ||
      state.output<CadMesh>('mesh').validate().isNotEmpty ||
      !state.output<CadSolvedSketch>('sketch').geometry.isSuccess) {
    throw StateError('Independent CAD validation failed.');
  }
}

Map<String, Object> _distribution(
    List<int> samples, List<Map<String, Object>> work) {
  final values = [...samples]..sort();
  return {
    'p50': values[values.length ~/ 2],
    'p95': values[(values.length * 0.95).ceil() - 1],
    'p99': values[(values.length * 0.99).ceil() - 1],
    'samples_us': samples,
    'work_per_sample': work,
  };
}

Map<String, Object> _work(CadRegenerationResult result, int path) {
  final expected =
      path == 2 ? ['plate', 'mesh'] : ['sketch', 'profile', 'plate', 'mesh'];
  if (result.rebuiltFeatures.join(',') != expected.join(',')) {
    throw StateError('Unexpected plate rebuild closure: '
        '${result.rebuiltFeatures} versus $expected.');
  }
  final mesh = result.state.output<CadMesh>('mesh');
  final stats = path == 2
      ? null
      : result.state.output<CadSolvedSketch>('sketch').geometry.stats;
  return {
    'rebuilt_features': result.rebuiltFeatures,
    'scheduled_features': result.stats.scheduledFeatures,
    'dependency_edges_visited': result.stats.dependencyEdgesVisited,
    'state_entries_copied': result.stats.stateEntriesCopied,
    'state_directory_entries_copied': result.stats.stateDirectoryEntriesCopied,
    'vertices': mesh.vertices.length,
    'triangles': mesh.triangles.length,
    'geometry_solve_invoked': stats != null,
    'residual_evaluations': stats?.residualEvaluations ?? 0,
    'jacobian_evaluations': stats?.jacobianEvaluations ?? 0,
    'linear_solves': stats?.linearSolves ?? 0,
    'linear_iterations': stats?.linearIterations ?? 0,
    'nonlinear_iterations': stats?.nonlinearIterations ?? 0,
    'rank_factorizations': stats?.rankFactorizations ?? 0,
    'rank_reuses': stats?.rankReuses ?? 0,
  };
}

void main(List<String> arguments) {
  var warmup = 3, repeats = 25;
  for (final argument in arguments) {
    final parts = argument.split('=');
    if (parts.length != 2 ||
        (parts.first != '--samples' && parts.first != '--warmups')) {
      throw ArgumentError('Use --samples=N and/or --warmups=N.');
    }
    final count = int.tryParse(parts.last);
    if (count == null || count < (parts.first == '--samples' ? 1 : 0)) {
      throw ArgumentError('Invalid count: $argument');
    }
    if (parts.first == '--samples') {
      repeats = count;
    } else {
      warmup = count;
    }
  }
  final document = buildParametricBracket();
  if (!document.regenerate().isSuccess) {
    throw StateError('Initial CAD failure.');
  }
  final coldTimes = <int>[], profileTimes = <int>[], thicknessTimes = <int>[];
  final coldRecords = <Map<String, Object>>[],
      profileRecords = <Map<String, Object>>[],
      thicknessRecords = <Map<String, Object>>[];
  var profileWork = <String>[], thicknessWork = <String>[];
  for (var pair = 0; pair < warmup + repeats; pair++) {
    for (final path in pair.isEven ? [0, 1, 2] : [2, 1, 0]) {
      final watch = Stopwatch()..start();
      final CadFeatureDocument solved;
      final CadRegenerationResult result;
      if (path == 0) {
        solved = buildParametricBracket();
        result = solved.regenerate();
      } else {
        solved = document;
        result = document.regenerate(
            changes: path == 1
                ? {
                    'width': pair.isEven ? 110 : 100,
                    'holeSpacing': pair.isEven ? 70 : 60
                  }
                : {'thickness': pair.isEven ? 8 : 6});
      }
      watch.stop();
      if (!result.isSuccess) throw StateError('${result.issues}');
      _check(solved);
      final work = _work(result, path);
      if (path == 1) profileWork = result.rebuiltFeatures;
      if (path == 2) thicknessWork = result.rebuiltFeatures;
      if (pair >= warmup) {
        (path == 0
                ? coldTimes
                : path == 1
                    ? profileTimes
                    : thicknessTimes)
            .add(watch.elapsedMicroseconds);
        (path == 0
                ? coldRecords
                : path == 1
                    ? profileRecords
                    : thicknessRecords)
            .add(work);
      }
    }
  }
  print(jsonEncode({
    'fixture': 'constrained two-hole mounting plate',
    'warmup_pairs': warmup,
    'measured_pairs': repeats,
    'units': 'microseconds',
    'cold_build_compile_regenerate': _distribution(coldTimes, coldRecords),
    'profile_edit_regenerate': {
      ..._distribution(profileTimes, profileRecords),
      'rebuilt_features': profileWork,
    },
    'thickness_edit_regenerate': {
      ..._distribution(thicknessTimes, thicknessRecords),
      'rebuilt_features': thicknessWork,
    },
    'analytic_volume_and_mesh_checks': 'passed',
    'scope':
        'current cold vs transactional incremental paths; not an old-release comparison',
  }));
}

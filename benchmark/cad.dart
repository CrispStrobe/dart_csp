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
  if ((state.output<CadBody>('plate').volume - expected).abs() > 1e-4 ||
      state.output<CadMesh>('mesh').validate().isNotEmpty ||
      !state.output<CadSolvedSketch>('sketch').geometry.isSuccess) {
    throw StateError('Independent CAD validation failed.');
  }
}

Map<String, num> _distribution(List<int> values) {
  values.sort();
  return {
    'p50': values[values.length ~/ 2],
    'p95': values[(values.length * 0.95).ceil() - 1],
  };
}

void main() {
  const warmup = 3, repeats = 25;
  final document = buildParametricBracket();
  if (!document.regenerate().isSuccess) {
    throw StateError('Initial CAD failure.');
  }
  final coldTimes = <int>[], profileTimes = <int>[], thicknessTimes = <int>[];
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
      if (path == 1) profileWork = result.rebuiltFeatures;
      if (path == 2) thicknessWork = result.rebuiltFeatures;
      if (pair >= warmup) {
        (path == 0
                ? coldTimes
                : path == 1
                    ? profileTimes
                    : thicknessTimes)
            .add(watch.elapsedMicroseconds);
      }
    }
  }
  print(jsonEncode({
    'fixture': 'constrained two-hole mounting plate',
    'warmup_pairs': warmup,
    'measured_pairs': repeats,
    'units': 'microseconds',
    'cold_build_compile_regenerate': _distribution(coldTimes),
    'profile_edit_regenerate': {
      ..._distribution(profileTimes),
      'rebuilt_features': profileWork,
    },
    'thickness_edit_regenerate': {
      ..._distribution(thicknessTimes),
      'rebuilt_features': thicknessWork,
    },
    'analytic_volume_and_mesh_checks': 'passed',
    'scope':
        'current cold vs transactional incremental paths; not an old-release comparison',
  }));
}

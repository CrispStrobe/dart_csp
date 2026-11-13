/// Paired cold/repeated-edit measurements for the geometric solver.
///
/// Run with `dart run benchmark/geometry.dart`. Timings compare two paths in
/// this implementation; they are not claims against another CAD system. The
/// structural reuse and residual assertions are independent of wall-clock noise.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_csp/geometry.dart';

GeometryBuilder buildCircles(int count) {
  final b = GeometryBuilder();
  for (var i = 0; i < count; i++) {
    final center = b.point3('c$i', Vec3(i * 10.0, 0, 0), fixed: true);
    final radius = b.dimension('r$i', 3, lower: 0);
    final p = b.point3('p$i', Vec3(i * 10.0 + 2, 1, 0.2));
    b.pointOnCircle('circle$i', p, GeometryCircle(center, radius, Vec3.unitZ));
  }
  return b;
}

void check(GeometrySolveResult result, int count, double radius) {
  if (!result.isSuccess) {
    throw StateError(
        'Geometry benchmark failed: ${result.status} ${result.message}');
  }
  for (var i = 0; i < count; i++) {
    final p = result.values['p$i']!;
    final expected = i == 0 ? radius : 3.0;
    final dx = p[0] - i * 10.0;
    final length = math.sqrt(dx * dx + p[1] * p[1] + p[2] * p[2]);
    if ((length - expected).abs() > 1e-7 || p[2].abs() > 1e-7) {
      throw StateError('Independent geometric validation failed for p$i.');
    }
  }
}

double percentile(List<int> samples, double p) {
  final sorted = [...samples]..sort();
  return sorted[((sorted.length - 1) * p).ceil()].toDouble();
}

void main() {
  const count = 100, warmups = 3, repetitions = 25;
  final compiled = buildCircles(count).compile();
  final warmSession = compiled.createSession();
  check(warmSession.solve(), count, 3);
  final cold = <int>[], warm = <int>[];
  late GeometrySolveResult coldResult, warmResult;
  for (var i = -warmups; i < repetitions; i++) {
    final radius = i.isEven ? 3.1 : 3.2;
    // Alternate measurement order to reduce fixed-order warm-up bias.
    void runCold() {
      final watch = Stopwatch()..start();
      final session = buildCircles(count).compile().createSession();
      session.setParameterValues('r0', [radius]);
      coldResult = session.solve();
      watch.stop();
      check(coldResult, count, radius);
      if (i >= 0) cold.add(watch.elapsedMicroseconds);
    }

    void runWarm() {
      final watch = Stopwatch()..start();
      warmSession.setParameterValues('r0', [radius]);
      warmResult = warmSession.solve();
      watch.stop();
      check(warmResult, count, radius);
      if (warmResult.stats.componentsSolved != 1 ||
          warmResult.stats.componentsReused != count - 1) {
        throw StateError(
            'A local edit did not preserve independent components.');
      }
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
  print(jsonEncode({
    'fixture': '100 independent 3D circles; edit one radius',
    'parameters': count * 3,
    'warmup_pairs': warmups,
    'measured_pairs': repetitions,
    'units': 'microseconds',
    'cold_build_compile_solve': {
      'p50': percentile(cold, 0.5),
      'p95': percentile(cold, 0.95),
      'components_solved': coldResult.stats.componentsSolved,
      'linear_solves': coldResult.stats.linearSolves,
    },
    'warm_edit_solve': {
      'p50': percentile(warm, 0.5),
      'p95': percentile(warm, 0.95),
      'components_solved': warmResult.stats.componentsSolved,
      'components_reused': warmResult.stats.componentsReused,
      'linear_solves': warmResult.stats.linearSolves,
    },
    'independent_geometry_checks': 'passed',
  }));
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';

import '../benchmark/solver_comparison/dart_adapter_core.dart';

List<Float64List> _copy(List<Float64List> values) =>
    [for (final value in values) Float64List.fromList(value)];

JsonObject _triangle(String engine,
    {double scale = 1, bool wrongBranch = false, bool recovery = false}) {
  final length = math.sqrt(2) * scale;
  return {
    'schema_version': 1,
    'engine': engine,
    'mode': 'warm',
    'warmups': 0,
    'samples': recovery ? 3 : 2,
    'tolerance': 1e-7 * scale,
    'fixture': {
      'id': 'triangle',
      'points': [
        [0.0, 0.0],
        [2 * scale, 0.0],
        [1.05 * scale, (wrongBranch ? -1.05 : 1.05) * scale]
      ],
      'fixed': [0, 1],
      'constraints': [
        {'kind': 'distance', 'a': 0, 'b': 2, 'value': length},
        {'kind': 'distance', 'a': 1, 'b': 2, 'value': length},
      ],
      'orientations': [
        [0, 1, 2, 1]
      ],
    },
    'edits': [
      {
        'values': [length, length]
      },
      if (recovery)
        {
          'values': [0.1 * scale, 0.1 * scale]
        },
      if (recovery)
        {
          'values': [length, length]
        },
    ],
  };
}

List<JsonObject> _samples(JsonObject request) =>
    evaluateDartComparisonRequest(request)
        .where((row) => row['record'] != 'metadata')
        .toList();

void main() {
  test('analytic blocks match finite differences and AD, including dimensions',
      () {
    for (final kind in ComparisonConstraintKind.values) {
      final c = ComparisonConstraint(
          kind, 0, 1, kind == ComparisonConstraintKind.distance ? 3.1 : null);
      final analytic = planarComparisonResidual(
          index: 0, constraint: c, tolerance: 1e-8, analytic: true);
      final ad = planarComparisonResidual(
          index: 0, constraint: c, tolerance: 1e-8, analytic: false);
      final values = [
        Float64List.fromList([1.2, -0.7]),
        Float64List.fromList([-2.3, 4.5]),
        if (kind == ComparisonConstraintKind.distance)
          Float64List.fromList([3.1])
      ];
      final residual = Float64List(analytic.residualCount);
      final adResidual = Float64List(analytic.residualCount);
      final jacobians = [
        for (final p in values) Float64List(analytic.residualCount * p.length)
      ];
      final adJacobians = [
        for (final p in values) Float64List(analytic.residualCount * p.length)
      ];
      analytic.evaluate(values, residual, jacobians);
      ad.evaluate(values, adResidual, adJacobians);
      for (var block = 0; block < values.length; block++) {
        for (var coordinate = 0;
            coordinate < values[block].length;
            coordinate++) {
          const h = 1e-6;
          final plus = _copy(values), minus = _copy(values);
          plus[block][coordinate] += h;
          minus[block][coordinate] -= h;
          final rp = Float64List(analytic.residualCount);
          final rm = Float64List(analytic.residualCount);
          analytic.evaluate(plus, rp, null);
          analytic.evaluate(minus, rm, null);
          for (var row = 0; row < analytic.residualCount; row++) {
            final position = row * values[block].length + coordinate;
            expect(jacobians[block][position],
                closeTo((rp[row] - rm[row]) / (2 * h), 2e-8),
                reason: '$kind block $block coordinate $coordinate row $row');
            expect(jacobians[block][position],
                closeTo(adJacobians[block][position], 1e-13));
            expect(residual[row], closeTo(adResidual[row], 1e-13));
          }
        }
      }
      if (kind == ComparisonConstraintKind.distance) {
        expect(jacobians[2].single, -1);
      }
    }
  });

  test('three representations preserve physical geometry across units', () {
    for (final engine in dartComparisonEngines) {
      for (final scale in [1e-6, 1.0, 1e6]) {
        final rows = _samples(_triangle(engine, scale: scale));
        expect(rows.every((row) => row['accepted'] == true), isTrue,
            reason: '$engine scale=$scale: $rows');
        final points = rows.last['coordinates']! as List<Object?>;
        final moving = points[2]! as List<Object?>;
        expect(moving[0]! as double, closeTo(scale, scale * 5e-7));
        expect(moving[1]! as double, closeTo(scale, scale * 5e-7));
        expect(rows.first['model_reused'], isFalse);
        expect(rows.last['model_reused'], isTrue);
        expect(rows.last['active_coordinates'], engine == 'dart_3d_ad' ? 3 : 2);
      }
    }
  });

  test('AD and analytic two-dimensional results agree on a nonlinear root', () {
    final ad = _samples(_triangle('dart_2d_ad')).last;
    final analytic = _samples(_triangle('dart_2d_analytic')).last;
    final a = ad['coordinates']! as List<Object?>;
    final b = analytic['coordinates']! as List<Object?>;
    for (var i = 0; i < a.length; i++) {
      final pa = a[i]! as List<Object?>, pb = b[i]! as List<Object?>;
      for (var j = 0; j < 2; j++) {
        expect(pa[j]! as double, closeTo(pb[j]! as double, 1e-10));
      }
    }
  });

  test(
      'physical branch rejection overrides native success and resets next seed',
      () {
    for (final engine in dartComparisonEngines) {
      final rows = _samples(_triangle(engine, wrongBranch: true));
      expect(rows.first['reported_success'], isTrue);
      expect(rows.first['accepted'], isFalse);
      expect(rows.first['orientation_mismatches'], 1);
      expect(rows.last['coordinate_seed_reset'], isTrue);
      expect(rows.last['accepted'], isFalse);
    }
  });

  test(
      'failed edit retains the earlier physical seed and a later edit recovers',
      () {
    for (final engine in dartComparisonEngines) {
      final rows = _samples(_triangle(engine, recovery: true));
      expect(rows.map((row) => row['accepted']), [true, false, true],
          reason: engine);
      expect(rows.last['coordinate_seed_reset'], isTrue);
      final points = rows.last['coordinates']! as List<Object?>;
      final moving = points[2]! as List<Object?>;
      expect(moving[0]! as double, closeTo(1, 5e-7));
      expect(moving[1]! as double, closeTo(1, 5e-7));
    }
  });
}

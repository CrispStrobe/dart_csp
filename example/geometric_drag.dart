/// Soft drag targets respect all required dimensions and workplane relations.
library;

import 'dart:math' as math;

import 'package:dart_csp/geometry.dart';

void main() {
  final builder = GeometryBuilder();
  final center = builder.point3('center', Vec3.zero, fixed: true);
  final point = builder.point3('point', const Vec3(3, 0, 0));
  final radius = builder.dimension('radius', 3, lower: 1e-12);
  builder.pointOnCircle(
      'on circle', point, GeometryCircle(center, radius, Vec3.unitZ));
  final session = builder.compile().createSession();
  final result = session.solve(preferences: [
    GeometryParameterTarget(parameterId: point.id, values: [1, 4, 1]),
  ]);
  if (!result.isSuccess) {
    throw StateError('${result.status}: ${result.message}');
  }
  final value = result.values[point.id]!;
  final expected = [3 / math.sqrt(17), 12 / math.sqrt(17), 0.0];
  for (var axis = 0; axis < 3; axis++) {
    if ((value[axis] - expected[axis]).abs() > 2e-6) {
      throw StateError(
          'Drag did not find the independently known closest point.');
    }
  }
  print('Drag target [1, 4, 1] -> $value');
  print('Required radius: 3; plane: z=0; '
      'residual ratio: ${result.maxToleranceRatio}.');
  print('Preference: ${result.preferenceReport!.status}; '
      'cost ${result.preferenceReport!.initialCost} -> '
      '${result.preferenceReport!.finalCost}.');
}

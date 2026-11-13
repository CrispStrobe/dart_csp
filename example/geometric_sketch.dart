import 'package:dart_csp/geometry.dart';

void main() {
  final b = GeometryBuilder();
  final origin = b.point3('origin', Vec3.zero, fixed: true);
  final axis = b.point3('axis', Vec3.unitX, fixed: true);
  final point = b.point3('point', const Vec3(7, 2, 1));
  final length = b.dimension('length', 5, lower: 0);
  b.pointOnLine('on axis', point, GeometryLine(origin, axis));
  b.distance('distance', origin, point, length);
  final session = b.compile().createSession();
  final first = session.solve();
  if (!first.isSuccess) throw StateError('Initial solve: ${first.status}');
  print('Initial point: ${first.values[point.id]}');
  session.setParameterValues(length.id, [8]);
  final edited = session.solve();
  if (!edited.isSuccess) throw StateError('Edited solve: ${edited.status}');
  final values = edited.values[point.id]!;
  if ((values[0] - 8).abs() > 1e-7 ||
      values[1].abs() > 1e-7 ||
      values[2].abs() > 1e-7) {
    throw StateError('Independent coordinate check failed.');
  }
  print('Edited point: $values');
  print('Remaining local freedoms: ${edited.localDegreesOfFreedom}');
}

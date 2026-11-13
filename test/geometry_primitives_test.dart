import 'dart:math' as math;

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

double distance(List<double> a, List<double> b) =>
    math.sqrt(List.generate(3, (i) => (a[i] - b[i]) * (a[i] - b[i]))
        .reduce((a, b) => a + b));

void main() {
  test('point on a 3D line follows editable distance and preserves branch', () {
    final b = GeometryBuilder();
    final o = b.point3('origin', Vec3.zero, fixed: true);
    final axis = b.point3('axis', Vec3.unitX, fixed: true);
    final p = b.point3('point', const Vec3(7, 2, 1));
    final d = b.dimension('length', 5, lower: 0);
    b.pointOnLine('on axis', p, GeometryLine(o, axis));
    b.distance('dimension', o, p, d);
    final session = b.compile().createSession();
    final first = session.solve();
    expect(first.isSuccess, isTrue,
        reason: '${first.status}: ${first.message}');
    expect(first.localDegreesOfFreedom, 0);
    expect(first.values[p.id]![0], closeTo(5, 1e-7));
    expect(distance(first.values[p.id]!, [5, 0, 0]), lessThan(1e-7));
    session.setParameterValues(d.id, [8]);
    final edited = session.solve();
    expect(edited.isSuccess, isTrue,
        reason: '${edited.status}: ${edited.message}');
    expect(distance(edited.values[p.id]!, [8, 0, 0]), lessThan(1e-7));
    final unchanged = session.solve();
    expect(unchanged.stats.linearSolves, 0);
    expect(unchanged.stats.componentsSolved, 0);
  });

  test('an unconstrained point retains its initial coordinates and freedoms',
      () {
    final b = GeometryBuilder()..point3('free', const Vec3(3, -2, 8));
    final result = b.compile().createSession().solve();
    expect(result.isSuccess, isTrue);
    expect(result.values['free'], [3, -2, 8]);
    expect(result.localDegreesOfFreedom, 3);
    expect(result.stats.linearSolves, 0);
  });

  test('circle dragging restores radius and plane while retaining one freedom',
      () {
    final b = GeometryBuilder();
    final c = b.point3('center', Vec3.zero, fixed: true);
    final r = b.dimension('radius', 3, lower: 0);
    final p = b.point3('point', const Vec3(2, 1, 0.5));
    b.pointOnCircle('on circle', p, GeometryCircle(c, r, Vec3.unitZ));
    final session = b.compile().createSession();
    expect(session.solve().isSuccess, isTrue);
    session.setParameterValues(p.id, [0.5, 4, 0.1]);
    final drag = session.solve();
    expect(drag.isSuccess, isTrue, reason: '${drag.status}: ${drag.message}');
    expect(drag.localDegreesOfFreedom, 1);
    expect(distance(drag.values[p.id]!, [0, 0, 0]), closeTo(3, 1e-7));
    expect(drag.values[p.id]![2], closeTo(0, 1e-7));
    expect(drag.values[p.id]![1], greaterThan(2.9));
  });

  test('signed angle and length solve a workplane sketch in radians', () {
    final b = GeometryBuilder();
    final o = b.point3('origin', Vec3.zero, fixed: true);
    final axis = b.point3('axis', Vec3.unitX, fixed: true);
    final p = b.workplanePoint('point',
        GeometryWorkplane(origin: Vec3.zero, normal: Vec3.unitZ), 1.3, 1.3);
    final angle = b.dimension('angle', math.pi / 3);
    final length = b.dimension('length', 2, lower: 0);
    b.distance('length constraint', o, p, length);
    b.angle(
        'angle constraint', GeometryLine(o, axis), GeometryLine(o, p), angle,
        normal: Vec3.unitZ);
    final result = b.compile().createSession().solve();
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    expect(result.values[p.id]![0], closeTo(1, 1e-7));
    expect(result.values[p.id]![1], closeTo(math.sqrt(3), 1e-7));
  });

  test('line-circle tangency keeps a specified side and planar geometry', () {
    final b = GeometryBuilder();
    final a = b.point3('a', const Vec3(-5, 0, 0), fixed: true);
    final z = b.point3('b', const Vec3(5, 0, 0), fixed: true);
    final c = b.point3('center', const Vec3(1, 3, 0.5));
    final r = b.dimension('radius', 2, lower: 0);
    b.tangentLineCircle(
        'tangent', GeometryLine(a, z), GeometryCircle(c, r, Vec3.unitZ));
    final result = b.compile().createSession().solve();
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    expect(result.values[c.id]![1], closeTo(2, 1e-7));
    expect(result.values[c.id]![2], closeTo(0, 1e-7));
    expect(result.localDegreesOfFreedom, 1);
  });

  test('a rigid mate solves translation and quaternion orientation', () {
    final b = GeometryBuilder();
    final ground = b.pose('ground', fixed: true);
    final part = b.pose('part',
        translation: const Vec3(1.7, -0.1, 0.2),
        quaternion: [math.cos(0.1), 0, 0, math.sin(0.1)]);
    b.rigidMate('rigid', ground, part, offset: const Vec3(2, 0, 0));
    final result = b.compile().createSession().solve();
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    expect(distance(result.values[part.translationId]!, [2, 0, 0]),
        lessThan(1e-7));
    final q = result.values[part.rotationId]!;
    expect(q.map((v) => v * v).reduce((a, b) => a + b), closeTo(1, 1e-12));
    expect(q[0].abs(), closeTo(1, 1e-8));
    expect(result.localDegreesOfFreedom, 0);
  });

  test('a revolute mate retains one angular freedom', () {
    final b = GeometryBuilder();
    final ground = b.pose('ground', fixed: true);
    final part = b.pose('part',
        translation: const Vec3(0.1, -0.2, 0.3),
        quaternion: [math.cos(0.2), 0, 0, math.sin(0.2)]);
    b.revoluteMate(
        'hinge', ground, Vec3.zero, Vec3.unitZ, part, Vec3.zero, Vec3.unitZ);
    final result = b.compile().createSession().solve();
    expect(result.isSuccess, isTrue,
        reason: '${result.status}: ${result.message}');
    expect(distance(result.values[part.translationId]!, [0, 0, 0]),
        lessThan(1e-7));
    expect(result.localDegreesOfFreedom, 1);
    expect(result.values[part.rotationId]![3], closeTo(math.sin(0.2), 1e-8));
  });

  test(
      'degenerate geometry is reported without overwriting the last valid state',
      () {
    final b = GeometryBuilder();
    final a = b.point3('a', Vec3.zero, fixed: true);
    final z = b.point3('b', Vec3.unitX, fixed: true);
    final p = b.point3('p', const Vec3(0.5, 0.1, 0));
    b.pointOnLine('line', p, GeometryLine(a, z));
    final session = b.compile().createSession();
    expect(session.solve().isSuccess, isTrue);
    final before = session.committedValues;
    session.setParameterValues(z.id, [0, 0, 0]);
    final failed = session.solve();
    expect(failed.status, GeometrySolveStatus.numericalFailure);
    expect(session.committedValues, before);
    expect(session.parameterValues(z.id), [1, 0, 0]);
  });

  test(
      'repeated parameter references share derivatives without spurious freedom loss',
      () {
    final b = GeometryBuilder();
    final p = b.point3('p', const Vec3(3, 2, 1));
    b.coincidence('self', p, p);
    final result = b.compile().createSession().solve();
    expect(result.isSuccess, isTrue);
    expect(result.localDegreesOfFreedom, 3);
  });

  test('workplane basis is orthonormal and invalid geometry is rejected', () {
    final plane = GeometryWorkplane(
        origin: const Vec3(4, 5, 6), normal: const Vec3(1, 2, 3));
    final p = plane.point(2, -3) - plane.origin;
    expect(p.dot(plane.normal), closeTo(0, 1e-12));
    expect(plane.u.dot(plane.v), closeTo(0, 1e-12));
    expect(plane.u.length, closeTo(1, 1e-12));
    expect(() => GeometryPlane(const GeometryPoint('x'), Vec3.zero),
        throwsArgumentError);
    expect(() => GeometryBuilder(lengthTolerance: 0), throwsArgumentError);
  });
}

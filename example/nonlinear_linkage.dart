/// A closed four-bar linkage in a tilted 3D workplane.
///
/// Two assembly branches satisfy the same dimensions. The solver follows a
/// local branch from its initial guess; this example does not select a global
/// optimum or certify infeasibility. At a toggle, infinitesimal rank can report
/// a freedom even though second-order length constraints prevent motion.
library;

import 'dart:math' as math;

import 'package:dart_csp/geometry.dart';

const linkageLengthTolerance = 1e-8;
const linkageAngleTolerance = 1e-9;
const linkageInitialAngle = 0.7;
const linkageGroundLength = 4.0;
const linkageCrankLength = 2.0;
const linkageCouplerLength = 3.0;
const linkageRockerLength = 2.5;
const _origin = Vec3(7, -3, 2);
const _normal = Vec3(0.64, -0.48, 0.6);
const _u = Vec3(0.6, 0.8, 0);
const _v = Vec3(-0.48, 0.36, 0.8);

/// Six active coordinates belong to one component. Both moving points have
/// workplane equations; three link lengths and a signed crank angle close the
/// mechanism. The initial guesses are deliberately off the required geometry.
CompiledGeometryModel buildFourBarLinkage(
    {int branch = 1, bool redundantCoupler = false}) {
  if (branch != 1 && branch != -1) {
    throw ArgumentError('The circle-intersection branch must be +1 or -1.');
  }
  final builder = GeometryBuilder(lengthTolerance: linkageLengthTolerance);
  final plane = GeometryWorkplane(origin: _origin, normal: _normal, xAxis: _u);
  final a = builder.point3('a', plane.point(0, 0), fixed: true);
  final d =
      builder.point3('d', plane.point(linkageGroundLength, 0), fixed: true);
  final b = builder.point3('b', plane.point(1.7, 1.1) + _normal * 0.04);
  final c = builder.point3(
      'c',
      (branch == 1 ? plane.point(4, 2.8) : plane.point(2.1, -1.7)) -
          _normal * 0.07);
  final crank =
      builder.dimension('crank_length', linkageCrankLength, lower: 1e-6);
  final coupler =
      builder.dimension('coupler_length', linkageCouplerLength, lower: 1e-6);
  final rocker =
      builder.dimension('rocker_length', linkageRockerLength, lower: 1e-6);
  final angle = builder.dimension('input_angle', linkageInitialAngle);
  builder.pointOnPlane('b.workplane', b, GeometryPlane(a, _normal));
  builder.pointOnPlane('c.workplane', c, GeometryPlane(a, _normal));
  builder.distance('crank', a, b, crank);
  builder.distance('coupler', b, c, coupler);
  builder.distance('rocker', c, d, rocker);
  builder.angle('input', GeometryLine(a, d), GeometryLine(a, b), angle,
      normal: _normal);
  if (redundantCoupler) {
    builder.distance('coupler_duplicate', b, c, coupler);
  }
  return builder.compile();
}

/// Independent two-circle construction. This uses ordinary trigonometry and
/// known orthonormal basis coefficients, not the solver's residual/AD code or
/// workplane conversion. It supplies a checkable answer for either branch.
({Vec3 crank, Vec3 joint, double circleHeight}) fourBarOracle({
  double angle = linkageInitialAngle,
  double crankLength = linkageCrankLength,
  double couplerLength = linkageCouplerLength,
  double rockerLength = linkageRockerLength,
  int branch = 1,
}) {
  if ((branch != 1 && branch != -1) ||
      !angle.isFinite ||
      !crankLength.isFinite ||
      !couplerLength.isFinite ||
      !rockerLength.isFinite ||
      crankLength <= 0 ||
      couplerLength <= 0 ||
      rockerLength <= 0) {
    throw ArgumentError('Expected finite positive links and branch +1 or -1.');
  }
  final bx = crankLength * math.cos(angle);
  final by = crankLength * math.sin(angle);
  final dx = linkageGroundLength - bx, dy = -by;
  final separation = math.sqrt(dx * dx + dy * dy);
  if (separation == 0 ||
      separation > couplerLength + rockerLength ||
      separation < (couplerLength - rockerLength).abs()) {
    throw StateError('The independent circles have no isolated intersection.');
  }
  final along = (couplerLength * couplerLength -
          rockerLength * rockerLength +
          separation * separation) /
      (2 * separation);
  final squaredHeight = couplerLength * couplerLength - along * along;
  // The triangle inequalities above establish a real intersection. Clamping
  // handles final-bit cancellation exactly at a tangent configuration.
  final height = math.sqrt(math.max(0, squaredHeight));
  final cx = bx + along * dx / separation - branch * height * dy / separation;
  final cy = by + along * dy / separation + branch * height * dx / separation;
  return (
    crank: _world(bx, by),
    joint: _world(cx, cy),
    circleHeight: height,
  );
}

Vec3 _world(double x, double y) =>
    Vec3(7 + 0.6 * x - 0.48 * y, -3 + 0.8 * x + 0.36 * y, 2 + 0.8 * y);

double _distance(Vec3 a, Vec3 b) {
  final x = a.x - b.x, y = a.y - b.y, z = a.z - b.z;
  return math.sqrt(x * x + y * y + z * z);
}

Vec3 _point(GeometrySolveResult result, String id) {
  final value = result.values[id]!;
  return Vec3(value[0], value[1], value[2]);
}

/// Checks closure, plane membership, input angle, fixed pivots and the selected
/// analytic branch. Near toggles, physical tolerances allow larger coordinate
/// error because the circle intersection is ill-conditioned; callers must
/// explicitly choose an appropriate [coordinateTolerance] there.
void checkFourBarSolution(
  GeometrySolveResult result, {
  double angle = linkageInitialAngle,
  double crankLength = linkageCrankLength,
  double couplerLength = linkageCouplerLength,
  double rockerLength = linkageRockerLength,
  int branch = 1,
  double coordinateTolerance = 5e-7,
  int expectedFreedoms = 0,
}) {
  if (!result.isSuccess ||
      result.localDegreesOfFreedom != expectedFreedoms ||
      result.components.length != 1) {
    throw StateError('Four-bar solve failed: ${result.status}; '
        '${result.message}; freedoms=${result.localDegreesOfFreedom}.');
  }
  final expected = fourBarOracle(
      angle: angle,
      crankLength: crankLength,
      couplerLength: couplerLength,
      rockerLength: rockerLength,
      branch: branch);
  final a = _point(result, 'a'), d = _point(result, 'd');
  final b = _point(result, 'b'), c = _point(result, 'c');
  final lengths = [
    (_distance(a, b) - crankLength).abs(),
    (_distance(b, c) - couplerLength).abs(),
    (_distance(c, d) - rockerLength).abs(),
  ];
  for (final error in lengths) {
    if (error > linkageLengthTolerance * 1.05) {
      throw StateError('Independent linkage closure error: $error.');
    }
  }
  for (final point in [b, c]) {
    if ((point - _origin).dot(_normal).abs() > linkageLengthTolerance * 1.05) {
      throw StateError('A moving point left its workplane.');
    }
  }
  final delta = b - _origin;
  final measured = math.atan2(delta.dot(_v), delta.dot(_u));
  final wrappedError =
      math.atan2(math.sin(measured - angle), math.cos(measured - angle));
  if (wrappedError.abs() > linkageAngleTolerance * 1.05 ||
      _distance(a, _world(0, 0)) > 1e-12 ||
      _distance(d, _world(linkageGroundLength, 0)) > 1e-12 ||
      _distance(b, expected.crank) > coordinateTolerance ||
      _distance(c, expected.joint) > coordinateTolerance) {
    throw StateError('Independent branch/coordinate/angle check failed: '
        'crank=${_distance(b, expected.crank)}, '
        'joint=${_distance(c, expected.joint)}, angle=$wrappedError.');
  }
}

void main() {
  final session = buildFourBarLinkage().createSession();
  for (final angle in [linkageInitialAngle, 0.9, 1.2, 1.5]) {
    session.setParameterValues('input_angle', [angle]);
    final result = session.solve();
    checkFourBarSolution(result, angle: angle);
    print('angle=$angle rad; crank=${result.values['b']}; '
        'joint=${result.values['c']}; freedoms=${result.localDegreesOfFreedom}');
  }
  session.setParameterValues('coupler_length', [0.2]);
  session.setParameterValues('rocker_length', [0.2]);
  final rejected = session.solve();
  if (rejected.isSuccess ||
      session.parameterValues('coupler_length').single !=
          linkageCouplerLength) {
    throw StateError('A rejected edit overwrote the valid linkage.');
  }
  session.restoreLastValid();
  print('Rejected impossible link dimensions with ${rejected.status}; '
      'the previous committed linkage is preserved.');
}

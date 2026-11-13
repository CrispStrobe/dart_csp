/// Geometric modeling primitives over the reusable numerical solver.
library;

import 'dart:math' as math;

import 'solver.dart';

/// A vector in a model's consistent length unit (angles use radians).
final class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const zero = Vec3(0, 0, 0);
  static const unitX = Vec3(1, 0, 0);
  static const unitY = Vec3(0, 1, 0);
  static const unitZ = Vec3(0, 0, 1);

  List<double> toList() => [x, y, z];
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;
  double get length => geometryNorm([x, y, z]);
  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator *(double scale) => Vec3(x * scale, y * scale, z * scale);
  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;
  Vec3 cross(Vec3 other) => Vec3(y * other.z - z * other.y,
      z * other.x - x * other.z, x * other.y - y * other.x);

  Vec3 normalized() {
    final scale = math.max(x.abs(), math.max(y.abs(), z.abs()));
    if (!isFinite || scale == 0) {
      throw ArgumentError('A direction must be finite and nonzero.');
    }
    final sx = x / scale, sy = y / scale, sz = z / scale;
    final norm = math.sqrt(sx * sx + sy * sy + sz * sz);
    return Vec3(sx / norm, sy / norm, sz / norm);
  }

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

final class GeometryPoint {
  const GeometryPoint(this.id);
  final String id;
}

/// A scalar dimension. Fixed dimensions remain editable session inputs.
final class GeometryScalar {
  const GeometryScalar(this.id);
  final String id;
}

final class GeometryLine {
  const GeometryLine(this.start, this.end);
  final GeometryPoint start;
  final GeometryPoint end;
}

final class GeometryPlane {
  GeometryPlane(this.origin, Vec3 normal) : normal = normal.normalized();
  final GeometryPoint origin;
  final Vec3 normal;
}

final class GeometryCircle {
  GeometryCircle(this.center, this.radius, Vec3 normal)
      : normal = normal.normalized();
  final GeometryPoint center;
  final GeometryScalar radius;
  final Vec3 normal;
}

/// Translation and a scalar-first unit quaternion; six tangent freedoms.
final class GeometryPose {
  const GeometryPose(this.translationId, this.rotationId);
  final String translationId;
  final String rotationId;
}

/// A sketch basis in 3D; points retain explicit placement in their workplane.
final class GeometryWorkplane {
  GeometryWorkplane({required this.origin, required Vec3 normal, Vec3? xAxis})
      : normal = normal.normalized() {
    final candidate =
        xAxis ?? (this.normal.x.abs() < 0.8 ? Vec3.unitX : Vec3.unitY);
    u = (candidate - this.normal * candidate.dot(this.normal)).normalized();
    v = this.normal.cross(u).normalized();
  }

  final Vec3 origin;
  final Vec3 normal;
  late final Vec3 u;
  late final Vec3 v;

  Vec3 point(double x, double y) => origin + u * x + v * y;
}

/// Convenience geometry layer. All required relations are residual blocks.
///
/// The builder freezes its structure at [compile]. Coordinate or fixed-dimension
/// edits belong to the resulting session. Adding/removing entities or constraints
/// requires compiling the new structure. Directions and angles are dimensionless;
/// positions and scalar lengths must use one consistent model unit.
class GeometryBuilder {
  GeometryBuilder({this.lengthTolerance = 1e-7, this.angleTolerance = 1e-9}) {
    if (!lengthTolerance.isFinite ||
        lengthTolerance <= 0 ||
        !angleTolerance.isFinite ||
        angleTolerance <= 0) {
      throw ArgumentError('Geometry tolerances must be finite and positive.');
    }
  }

  final double lengthTolerance;
  final double angleTolerance;
  double get _vectorLengthTolerance => lengthTolerance / math.sqrt(3);
  double get _vectorAngleTolerance => angleTolerance / math.sqrt(3);
  final Map<String, GeometryParameterBlock> _parameters = {};
  final Map<String, GeometryResidualBlock> _constraints = {};

  GeometryPoint point3(String id, Vec3 initial, {bool fixed = false}) {
    if (!initial.isFinite) throw ArgumentError('A point must be finite.');
    _parameter(
        GeometryParameterBlock(id: id, values: initial.toList(), fixed: fixed));
    return GeometryPoint(id);
  }

  GeometryScalar dimension(String id, double value,
      {bool fixed = true, double? lower, double? upper}) {
    _parameter(GeometryParameterBlock(
        id: id,
        values: [value],
        fixed: fixed,
        lowerBounds: lower == null ? null : [lower],
        upperBounds: upper == null ? null : [upper]));
    return GeometryScalar(id);
  }

  GeometryPose pose(String id,
      {Vec3 translation = Vec3.zero,
      List<double> quaternion = const [1, 0, 0, 0],
      bool fixed = false}) {
    final t = '$id.translation', q = '$id.rotation';
    if (_parameters.containsKey(t) || _parameters.containsKey(q)) {
      throw ArgumentError('Pose identifiers already exist: $id.');
    }
    // Validate both declarations before changing the builder. A rejected
    // quaternion must not leave a translation block that prevents retrying.
    final translationBlock = GeometryParameterBlock(
        id: t, values: translation.toList(), fixed: fixed);
    final rotationBlock = GeometryParameterBlock(
        id: q,
        values: quaternion,
        fixed: fixed,
        manifold: const QuaternionGeometryManifold());
    _parameter(translationBlock);
    _parameter(rotationBlock);
    return GeometryPose(t, q);
  }

  GeometryPoint workplanePoint(
      String id, GeometryWorkplane plane, double x, double y,
      {bool fixed = false}) {
    final p = point3(id, plane.point(x, y), fixed: fixed);
    _add(
        '$id.workplane',
        [p.id],
        1,
        (b) => [
              (b[0][0] - plane.origin.x) * plane.normal.x +
                  (b[0][1] - plane.origin.y) * plane.normal.y +
                  (b[0][2] - plane.origin.z) * plane.normal.z,
            ],
        tolerance: lengthTolerance);
    return p;
  }

  void coincidence(String id, GeometryPoint a, GeometryPoint b) =>
      _add(id, [a.id, b.id], 3, (p) => _sub(p[0], p[1]),
          tolerance: _vectorLengthTolerance);

  /// A distance uses length residuals. For a zero-length relation, prefer
  /// [coincidence], which exposes its three independent coordinate equations.
  void distance(
          String id, GeometryPoint a, GeometryPoint b, GeometryScalar length) =>
      _add(id, [a.id, b.id, length.id], 1, (p) {
        if (p[2][0].value < 0) throw StateError('Distance is negative.');
        return [_norm(_sub(p[0], p[1])) - p[2][0]];
      }, tolerance: lengthTolerance);

  void equalLengths(String id, GeometryLine a, GeometryLine b) => _add(
      id,
      [a.start.id, a.end.id, b.start.id, b.end.id],
      1,
      (p) => [_norm(_sub(p[1], p[0])) - _norm(_sub(p[3], p[2]))],
      tolerance: lengthTolerance);

  void pointOnPlane(String id, GeometryPoint point, GeometryPlane plane) =>
      _add(id, [point.id, plane.origin.id], 1, (p) {
        final d = _sub(p[0], p[1]);
        return [_dotConstant(d, plane.normal)];
      }, tolerance: lengthTolerance);

  void pointOnLine(String id, GeometryPoint point, GeometryLine line) => _add(
      id,
      [point.id, line.start.id, line.end.id],
      3,
      (p) => _cross(_sub(p[0], p[1]), _unit(_sub(p[2], p[1]))),
      tolerance: _vectorLengthTolerance);

  void parallel(String id, GeometryLine a, GeometryLine b) => _add(
      id,
      [a.start.id, a.end.id, b.start.id, b.end.id],
      3,
      (p) => _cross(_unit(_sub(p[1], p[0])), _unit(_sub(p[3], p[2]))),
      tolerance: _vectorAngleTolerance);

  void perpendicular(String id, GeometryLine a, GeometryLine b) => _add(
      id,
      [a.start.id, a.end.id, b.start.id, b.end.id],
      1,
      (p) => [_dot(_unit(_sub(p[1], p[0])), _unit(_sub(p[3], p[2])))],
      tolerance: angleTolerance);

  /// Angle between directed lines, in radians.
  ///
  /// Without [normal], the required angle is the unsigned 3D angle in [0, pi].
  /// With [normal], both directions must be perpendicular to that normal and
  /// the signed angle follows its right-hand orientation. The signed relation
  /// includes two coplanarity equations; it does not silently project tilted
  /// lines into a plane. A zero direction or undefined angular configuration
  /// is reported as a numerical failure by the solve session.
  void angle(String id, GeometryLine a, GeometryLine b, GeometryScalar radians,
      {Vec3? normal}) {
    final axis = normal?.normalized();
    _add(id, [a.start.id, a.end.id, b.start.id, b.end.id, radians.id],
        axis == null ? 1 : 3, (p) {
      final u = _unit(_sub(p[1], p[0])), v = _unit(_sub(p[3], p[2]));
      final cross = _cross(u, v);
      final sine = axis == null ? _norm(cross) : _dotConstant(cross, axis);
      final measured = sine.atan2(_dot(u, v));
      // The angle residual wraps without changing its local derivative away
      // from the branch cut. Large changes are best applied by continuation.
      var residual = measured - p[4][0];
      if (residual.value > math.pi) residual = residual - 2 * math.pi;
      if (residual.value < -math.pi) residual = residual + 2 * math.pi;
      return [
        residual,
        if (axis != null) _dotConstant(u, axis),
        if (axis != null) _dotConstant(v, axis),
      ];
    }, tolerance: angleTolerance);
  }

  void pointOnCircle(String id, GeometryPoint point, GeometryCircle circle) =>
      _add(id, [point.id, circle.center.id, circle.radius.id], 2, (p) {
        if (p[2][0].value <= 0) {
          throw StateError('Circle radius must be positive.');
        }
        final d = _sub(p[0], p[1]);
        return [_dotConstant(d, circle.normal), _norm(d) - p[2][0]];
      }, tolerance: lengthTolerance);

  /// Tangency to a circle in its plane, with a chosen signed side (+1/-1).
  void tangentLineCircle(String id, GeometryLine line, GeometryCircle circle,
      {int side = 1}) {
    if (side != 1 && side != -1) {
      throw ArgumentError('Tangency side is +1 or -1.');
    }
    _add(
        id, [line.start.id, line.end.id, circle.center.id, circle.radius.id], 3,
        (p) {
      if (p[3][0].value <= 0) {
        throw StateError('Circle radius must be positive.');
      }
      final direction = _unit(_sub(p[1], p[0]));
      final toCenter = _sub(p[2], p[0]);
      return [
        _dotConstant(_cross(direction, toCenter), circle.normal) -
            p[3][0] * side,
        _dotConstant(_sub(p[0], p[2]), circle.normal),
        _dotConstant(_sub(p[1], p[2]), circle.normal),
      ];
    }, tolerance: lengthTolerance);
  }

  /// External circle tangency; circles must have parallel normals and one plane.
  void tangentCircles(String id, GeometryCircle a, GeometryCircle b) {
    if (a.normal.cross(b.normal).length > angleTolerance) {
      throw ArgumentError('Circle planes must have parallel normals.');
    }
    _add(id, [a.center.id, a.radius.id, b.center.id, b.radius.id], 2, (p) {
      if (p[1][0].value <= 0 || p[3][0].value <= 0) {
        throw StateError('Circle radii must be positive.');
      }
      final delta = _sub(p[2], p[0]);
      return [_dotConstant(delta, a.normal), _norm(delta) - p[1][0] - p[3][0]];
    }, tolerance: lengthTolerance);
  }

  /// A model point attached to a rigid body's local coordinates.
  void attachPoint(
          String id, GeometryPoint point, GeometryPose pose, Vec3 local) =>
      _add(id, [point.id, pose.translationId, pose.rotationId], 3,
          (p) => _sub(p[0], _world(p[1], p[2], local)),
          tolerance: _vectorLengthTolerance);

  /// Coincident local anchors remove three relative translational freedoms.
  void matePoints(String id, GeometryPose a, Vec3 anchorA, GeometryPose b,
          Vec3 anchorB) =>
      _add(
          id,
          [a.translationId, a.rotationId, b.translationId, b.rotationId],
          3,
          (p) => _sub(_world(p[0], p[1], anchorA), _world(p[2], p[3], anchorB)),
          tolerance: _vectorLengthTolerance);

  /// Align two body-local axes. Anti-parallel orientation is allowed unless
  /// [sameDirection] is true, in which case the vector difference is used.
  void mateAxes(
      String id, GeometryPose a, Vec3 axisA, GeometryPose b, Vec3 axisB,
      {bool sameDirection = false}) {
    final u = axisA.normalized(), v = axisB.normalized();
    _add(id, [a.rotationId, b.rotationId], 3, (p) {
      final wa = _rotate(p[0], u), wb = _rotate(p[1], v);
      return sameDirection ? _sub(wa, wb) : _cross(wa, wb);
    }, tolerance: _vectorAngleTolerance);
  }

  /// Revolute mate: coincident anchors plus aligned axes, leaving rotation
  /// around the joint axis free in a regular configuration.
  void revoluteMate(String id, GeometryPose a, Vec3 anchorA, Vec3 axisA,
      GeometryPose b, Vec3 anchorB, Vec3 axisB) {
    matePoints('$id.anchor', a, anchorA, b, anchorB);
    mateAxes('$id.axis', a, axisA, b, axisB, sameDirection: true);
  }

  /// A rigid mate fixes relative placement of three noncollinear local anchors.
  void rigidMate(String id, GeometryPose a, GeometryPose b,
      {Vec3 offset = Vec3.zero}) {
    matePoints('$id.origin', a, offset, b, Vec3.zero);
    matePoints('$id.x', a, offset + Vec3.unitX, b, Vec3.unitX);
    matePoints('$id.y', a, offset + Vec3.unitY, b, Vec3.unitY);
  }

  void addResidual(GeometryResidualBlock constraint) {
    if (_constraints.containsKey(constraint.id)) {
      throw ArgumentError('Duplicate geometric constraint ${constraint.id}.');
    }
    for (final id in constraint.parameterIds) {
      if (!_parameters.containsKey(id)) {
        throw ArgumentError('Unknown parameter $id.');
      }
    }
    _constraints[constraint.id] = constraint;
  }

  GeometryModel build() => GeometryModel(
      parameters: _parameters.values, constraints: _constraints.values);

  CompiledGeometryModel compile() => build().compile();

  void _parameter(GeometryParameterBlock block) {
    if (_parameters.containsKey(block.id)) {
      throw ArgumentError('Duplicate geometric parameter ${block.id}.');
    }
    _parameters[block.id] = block;
  }

  void _add(String id, List<String> parameters, int count,
      List<Dual> Function(List<List<Dual>>) evaluate,
      {required double tolerance}) {
    final unique = parameters.toSet().toList();
    final aliases = [for (final p in parameters) unique.indexOf(p)];
    addResidual(GeometryResidualBlock.autoDiff(
        id: id,
        parameterIds: unique,
        residualCount: count,
        tolerance: tolerance,
        evaluate: (values) => evaluate([for (final i in aliases) values[i]])));
  }
}

List<Dual> _sub(List<Dual> a, List<Dual> b) =>
    [for (var i = 0; i < 3; i++) a[i] - b[i]];

Dual _dot(List<Dual> a, List<Dual> b) =>
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
Dual _dotConstant(List<Dual> a, Vec3 b) => a[0] * b.x + a[1] * b.y + a[2] * b.z;

List<Dual> _cross(List<Dual> a, List<Dual> b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

Dual _norm(List<Dual> vector) => Dual.norm(vector);

List<Dual> _unit(List<Dual> vector) => Dual.normalized(vector);

List<Dual> _rotate(List<Dual> q, Vec3 local) {
  final d = q[0].derivatives.length;
  final v = [
    Dual.constant(local.x, d),
    Dual.constant(local.y, d),
    Dual.constant(local.z, d)
  ];
  final qv = [q[1], q[2], q[3]];
  final uv = _cross(qv, v), uuv = _cross(qv, _cross(qv, v));
  return [for (var i = 0; i < 3; i++) v[i] + (uv[i] * q[0] + uuv[i]) * 2];
}

List<Dual> _world(List<Dual> translation, List<Dual> quaternion, Vec3 local) {
  final rotated = _rotate(quaternion, local);
  return [for (var i = 0; i < 3; i++) translation[i] + rotated[i]];
}

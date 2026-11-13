/// Rigid part placement without rebuilding analytic bodies or display meshes.
library;

import 'dart:math' as math;

import '../continuous.dart' show Interval, IntervalRounding;
import '../geometry/primitives.dart' show GeometryPose;
import '../geometry/solver.dart' show GeometrySolveResult;
import 'kernel.dart';

/// An immutable proper rigid transform. Quaternions use scalar-first `[w, x, y, z]`
/// order; finite nonzero inputs are normalized without overflow or underflow.
/// Lengths use the model's units and angles use radians. Scaling and reflection
/// are deliberately absent so analytic radii, volume and winding are preserved.
final class CadRigidTransform {
  factory CadRigidTransform({
    CadPoint3 translation = const CadPoint3(0, 0, 0),
    List<double> quaternion = const [1, 0, 0, 0],
  }) {
    final position = CadPoint3(translation.x, translation.y, translation.z);
    final rotation = List<double>.of(quaternion);
    if (!position.isFinite ||
        rotation.length != 4 ||
        rotation.any((value) => !value.isFinite)) {
      throw ArgumentError('A rigid placement needs finite translation and '
          'four finite quaternion components.');
    }
    final scale = rotation.fold(0.0, (a, b) => math.max(a, b.abs()));
    if (scale == 0) {
      throw ArgumentError('A placement quaternion must be nonzero.');
    }
    var squared = 0.0;
    for (var i = 0; i < 4; i++) {
      rotation[i] /= scale;
      squared += rotation[i] * rotation[i];
    }
    final norm = math.sqrt(squared);
    for (var i = 0; i < 4; i++) {
      rotation[i] /= norm;
    }
    final w = rotation[0], x = rotation[1], y = rotation[2], z = rotation[3];
    return CadRigidTransform._(
        position,
        List.unmodifiable(rotation),
        List.unmodifiable([
          1 - 2 * (y * y + z * z),
          2 * (x * y - z * w),
          2 * (x * z + y * w),
          2 * (x * y + z * w),
          1 - 2 * (x * x + z * z),
          2 * (y * z - x * w),
          2 * (x * z - y * w),
          2 * (y * z + x * w),
          1 - 2 * (x * x + y * y),
        ]));
  }

  factory CadRigidTransform.axisAngle({
    required CadPoint3 axis,
    required double angle,
    CadPoint3 translation = const CadPoint3(0, 0, 0),
  }) {
    final direction = CadPoint3(axis.x, axis.y, axis.z);
    final scale = math.max(
        direction.x.abs(), math.max(direction.y.abs(), direction.z.abs()));
    if (!direction.isFinite || scale == 0 || !angle.isFinite) {
      throw ArgumentError('A rotation needs a finite nonzero axis and angle.');
    }
    final x = direction.x / scale,
        y = direction.y / scale,
        z = direction.z / scale;
    final sine = math.sin(angle / 2) / math.sqrt(x * x + y * y + z * z);
    return CadRigidTransform(
        translation: translation,
        quaternion: [math.cos(angle / 2), x * sine, y * sine, z * sine]);
  }

  /// Creates a placement only from a successful, physically checked solve.
  /// Rejected/limited numerical candidates must not position a committed solid.
  factory CadRigidTransform.fromGeometryPose(
      GeometrySolveResult geometry, GeometryPose pose) {
    if (!geometry.isSuccess) {
      throw ArgumentError('Only a satisfied geometric solve can place a part.');
    }
    final position = geometry.values[pose.translationId];
    final rotation = geometry.values[pose.rotationId];
    if (position == null || position.length != 3 || rotation == null) {
      throw ArgumentError('The solved geometry does not contain this pose.');
    }
    return CadRigidTransform(
        translation: CadPoint3(position[0], position[1], position[2]),
        quaternion: rotation);
  }

  CadRigidTransform._(this.translation, this.quaternion, this._rotation);
  final CadPoint3 translation;
  final List<double> quaternion;
  final List<double> _rotation;

  /// Rotation of a vector or surface normal, without translation.
  CadPoint3 transformDirection(CadPoint3 direction) {
    final x = direction.x, y = direction.y, z = direction.z;
    final result = CadPoint3(
        _rotation[0] * x + _rotation[1] * y + _rotation[2] * z,
        _rotation[3] * x + _rotation[4] * y + _rotation[5] * z,
        _rotation[6] * x + _rotation[7] * y + _rotation[8] * z);
    if (!result.isFinite) {
      throw StateError('A placed coordinate is not finite at this scale.');
    }
    return result;
  }

  CadPoint3 transformPoint(CadPoint3 point) {
    final result = transformDirection(point) + translation;
    if (!result.isFinite) {
      throw StateError('A placed coordinate is not finite at this scale.');
    }
    return result;
  }

  /// This transform applied after [local]: `this(local(point))`.
  CadRigidTransform compose(CadRigidTransform local) {
    final a = quaternion, b = local.quaternion;
    return CadRigidTransform(
        translation: transformPoint(local.translation),
        quaternion: [
          a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
          a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
          a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
          a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0],
        ]);
  }

  CadRigidTransform inverse() {
    final q = quaternion;
    final rotation = CadRigidTransform(quaternion: [q[0], -q[1], -q[2], -q[3]]);
    return CadRigidTransform(
        translation: rotation.transformDirection(translation.scaled(-1)),
        quaternion: rotation.quaternion);
  }

  /// A conservative world AABB. Outward rounding covers the represented
  /// rotation matrix and local bounds, including interior points near an edge.
  CadBounds transformBounds(CadBounds bounds) {
    if (!bounds.isFinite ||
        bounds.min.x > bounds.max.x ||
        bounds.min.y > bounds.max.y ||
        bounds.min.z > bounds.max.z) {
      throw ArgumentError('Local bounds must be finite and ordered.');
    }
    final axes = [
      Interval(bounds.min.x, bounds.max.x),
      Interval(bounds.min.y, bounds.max.y),
      Interval(bounds.min.z, bounds.max.z),
    ];
    final offsets = [translation.x, translation.y, translation.z];
    const rounding = IntervalRounding.outward;
    final result = <Interval>[];
    for (var row = 0; row < 3; row++) {
      var range = rounding.scale(axes[0], _rotation[row * 3]);
      for (var col = 1; col < 3; col++) {
        range = rounding.add(
            range, rounding.scale(axes[col], _rotation[row * 3 + col]));
      }
      result.add(rounding.add(range, Interval.point(offsets[row])));
    }
    final placed = CadBounds(
        CadPoint3(result[0].lo, result[1].lo, result[2].lo),
        CadPoint3(result[0].hi, result[1].hi, result[2].hi));
    if (!placed.isFinite) {
      throw StateError('Placed bounds are not finite at this scale.');
    }
    return placed;
  }

  /// Column-major affine 4x4 matrix for rendering one shared local mesh.
  /// No world-space mesh allocation is needed for a pose-only edit.
  List<double> toColumnMajorMatrix4() => List.unmodifiable([
        _rotation[0],
        _rotation[3],
        _rotation[6],
        0.0,
        _rotation[1],
        _rotation[4],
        _rotation[7],
        0.0,
        _rotation[2],
        _rotation[5],
        _rotation[8],
        0.0,
        translation.x,
        translation.y,
        translation.z,
        1.0,
      ]);

  /// Materializes a placed mesh for export. This O(vertices + triangles) path
  /// checks the source and result; ordinary rendering should use a shared local
  /// mesh and [toColumnMajorMatrix4] instead. Coordinate precision may be lost
  /// at extreme translations; a collapsed or invalid result is rejected.
  CadKernelResult<CadMesh> transformMesh(CadMesh local) {
    final sourceIssues = local.validate();
    if (sourceIssues.isNotEmpty) {
      return CadKernelResult.failure(
          CadKernelStatus.invalidTopology, sourceIssues);
    }
    final CadMesh world;
    try {
      world = CadMesh(
          vertices: local.vertices.map(transformPoint),
          triangles: local.triangles,
          chordError: local.chordError);
    } on Object catch (error) {
      return CadKernelResult.failure(CadKernelStatus.numericalFailure,
          [CadIssue('invalid_mesh_placement', error.toString())]);
    }
    final issues = world.validate();
    return issues.isEmpty
        ? CadKernelResult.success(world)
        : CadKernelResult.failure(CadKernelStatus.invalidTopology, issues);
  }
}

/// A placed occurrence of an analytic body; [body] stays in its local frame.
/// Instances share the same prototype and its separately held display mesh.
/// This represents multiple solids, not a boolean union or collision-free mate.
final class CadBodyInstance {
  CadBodyInstance({
    required this.featureId,
    required this.body,
    required this.placement,
  }) {
    if (featureId.isEmpty) {
      throw ArgumentError('A body instance needs a stable feature ID.');
    }
  }
  final String featureId;
  final CadBody body;
  final CadRigidTransform placement;
  double get volume => body.volume;
  CadBounds get bounds => placement.transformBounds(body.bounds);

  /// Resolves the prototype's design meaning in this instance's world frame.
  /// IDs remain scoped by [featureId]; missing and ambiguous meanings survive.
  CadTopologyResolution resolve(CadTopologyKind kind, String semanticId) =>
      CadTopologyResolution(body.resolve(kind, semanticId).matches.map(_place));

  /// Validates the prototype through its backend, and checks transformed
  /// extents/topology. Public/custom bodies are never granted a validation cache.
  List<CadIssue> validate(CadKernel kernel) {
    final issues = <CadIssue>[...kernel.validate(body)];
    if (issues.isNotEmpty) return List.unmodifiable(issues);
    try {
      placement.transformBounds(body.bounds);
      for (final entity in body.topology) {
        _place(entity);
      }
    } on Object catch (error) {
      issues.add(CadIssue(
          error is UnsupportedError
              ? 'unsupported_instance_geometry'
              : 'invalid_instance_placement',
          error.toString(),
          entity: featureId));
    }
    return List.unmodifiable(issues);
  }

  CadTopologyEntity _place(CadTopologyEntity entity) {
    if (entity is CadVertex) {
      return CadVertex(
          id: entity.id,
          semanticId: entity.semanticId,
          point: placement.transformPoint(entity.point));
    }
    if (entity is CadEdge) {
      final curve = entity.curve;
      final CadCurve transformed;
      if (curve is CadLineCurve) {
        transformed = CadLineCurve(placement.transformPoint(curve.start),
            placement.transformPoint(curve.end));
      } else if (curve is CadCircleCurve) {
        transformed = CadCircleCurve(
            center: placement.transformPoint(curve.center),
            radius: curve.radius,
            normal: placement.transformDirection(curve.normal));
      } else {
        throw UnsupportedError(
            'Rigid instances support line and circle edges.');
      }
      return CadEdge(
          id: entity.id,
          semanticId: entity.semanticId,
          curve: transformed,
          startVertex: entity.startVertex,
          endVertex: entity.endVertex);
    }
    if (entity is CadFace) {
      final surface = entity.surface;
      final CadSurface transformed;
      if (surface is CadPlaneSurface) {
        transformed = CadPlaneSurface(
            origin: placement.transformPoint(surface.origin),
            normal: placement.transformDirection(surface.normal));
      } else if (surface is CadCylinderSurface) {
        transformed = CadCylinderSurface(
            origin: placement.transformPoint(surface.origin),
            radius: surface.radius,
            axis: placement.transformDirection(surface.axis),
            inward: surface.inward);
      } else {
        throw UnsupportedError(
            'Rigid instances support plane and cylinder faces.');
      }
      return CadFace(
          id: entity.id,
          semanticId: entity.semanticId,
          surface: transformed,
          loops: entity.loops);
    }
    throw UnsupportedError('Unknown topology kind in a rigid instance.');
  }
}

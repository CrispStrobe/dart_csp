/// Rigid part placement without rebuilding analytic bodies or display meshes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../continuous.dart' show IntervalRounding;
import '../geometry/primitives.dart' show GeometryPose;
import '../geometry/solver.dart'
    show GeometrySolveResult, QuaternionGeometryManifold;
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
    if (!const QuaternionGeometryManifold()
        .isValid(Float64List.fromList(rotation))) {
      throw ArgumentError('Solved pose rotation must already be a unit '
          'quaternion; unconstrained coordinates cannot be renormalized.');
    }
    return CadRigidTransform(
        translation: CadPoint3(position[0], position[1], position[2]),
        quaternion: rotation);
  }

  CadRigidTransform._(this.translation, this.quaternion, this._rotation)
      : _isIdentity = _rotation[0] == 1 &&
            _rotation[4] == 1 &&
            _rotation[8] == 1 &&
            _rotation[1] == 0 &&
            _rotation[2] == 0 &&
            _rotation[3] == 0 &&
            _rotation[5] == 0 &&
            _rotation[6] == 0 &&
            _rotation[7] == 0;
  final CadPoint3 translation;
  final List<double> quaternion;
  final List<double> _rotation;
  final bool _isIdentity;

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

  // Bound the Euclidean error of materializing a transformed point. TwoSum
  // retains the actual translation rounding error rather than a world-scale
  // ulp estimate, so an exactly representable large translation is not rejected
  // merely for being far from the origin. Each product's error is bounded by
  // epsilon*abs(product) plus one subnormal. A conservative coefficient budget
  // covers quaternion normalization and rotation-matrix arithmetic as well.
  (CadPoint3, double) _checkedPoint(CadPoint3 point) {
    final x = point.x, y = point.y, z = point.z;
    if (!x.isFinite || !y.isFinite || !z.isFinite) {
      throw StateError('A source coordinate is not finite.');
    }
    const epsilon = 2.220446049250313e-16;
    final coefficientError = _isIdentity
        ? 0.0
        : IntervalRounding.nextUp(IntervalRounding.nextUp(
                IntervalRounding.nextUp(x.abs() + y.abs()) + z.abs()) *
            (64 * epsilon));
    final first = _checkedCoordinate(_rotation[0] * x, _rotation[1] * y,
        _rotation[2] * z, translation.x, coefficientError);
    final second = _checkedCoordinate(_rotation[3] * x, _rotation[4] * y,
        _rotation[5] * z, translation.y, coefficientError);
    final third = _checkedCoordinate(_rotation[6] * x, _rotation[7] * y,
        _rotation[8] * z, translation.z, coefficientError);
    final result = CadPoint3(first.$1, second.$1, third.$1);
    // L1 bounds Euclidean displacement without squaring tiny/large values.
    final error = IntervalRounding.nextUp(
        IntervalRounding.nextUp(first.$2 + second.$2) + third.$2);
    if (!result.isFinite || !error.isFinite) {
      throw StateError('Placed coordinates or error bounds are not finite.');
    }
    return (result, error);
  }

  // Keep the multiplication, TwoSum and outward-rounding order unchanged.
  // Scalar accumulations avoid temporary term/residual lists for every row.
  static (double, double) _checkedCoordinate(
      double a, double b, double c, double offset, double coefficientError) {
    const epsilon = 2.220446049250313e-16;
    final first = _sumWithError(a, b);
    final second = _sumWithError(first.$1, c);
    final third = _sumWithError(second.$1, offset);
    var error = coefficientError;
    error = IntervalRounding.nextUp(
        error + IntervalRounding.nextUp(a.abs() * epsilon + 5e-324));
    error = IntervalRounding.nextUp(
        error + IntervalRounding.nextUp(b.abs() * epsilon + 5e-324));
    error = IntervalRounding.nextUp(
        error + IntervalRounding.nextUp(c.abs() * epsilon + 5e-324));
    error = IntervalRounding.nextUp(error + first.$2.abs());
    error = IntervalRounding.nextUp(error + second.$2.abs());
    error = IntervalRounding.nextUp(error + third.$2.abs());
    return (third.$1, error);
  }

  static (double, double) _sumWithError(double a, double b) {
    final sum = a + b;
    final virtualB = sum - a;
    final virtualA = sum - virtualB;
    return (sum, (a - virtualA) + (b - virtualB));
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
    // Preserve public getter order while retaining only scalar endpoints.
    final minX = bounds.min.x, maxX = bounds.max.x;
    final minY = bounds.min.y, maxY = bounds.max.y;
    final minZ = bounds.min.z, maxZ = bounds.max.z;
    final offsetX = translation.x,
        offsetY = translation.y,
        offsetZ = translation.z;
    final x =
        _transformBoundsRow(0, minX, maxX, minY, maxY, minZ, maxZ, offsetX);
    final y =
        _transformBoundsRow(3, minX, maxX, minY, maxY, minZ, maxZ, offsetY);
    final z =
        _transformBoundsRow(6, minX, maxX, minY, maxY, minZ, maxZ, offsetZ);
    final placed =
        CadBounds(CadPoint3(x.$1, y.$1, z.$1), CadPoint3(x.$2, y.$2, z.$2));
    if (!placed.isFinite) {
      throw StateError('Placed bounds are not finite at this scale.');
    }
    return placed;
  }

  // Scalar form of scale(x), add(scale(y)), add(scale(z)), add(offset).
  // Keep each sign choice and down/up operation in the interval algebra's
  // original order; regrouping or skipping zero products changes the bounds.
  (double, double) _transformBoundsRow(int row, double minX, double maxX,
      double minY, double maxY, double minZ, double maxZ, double offset) {
    const rounding = IntervalRounding.outward;
    final a = _rotation[row];
    var lower = rounding.down((a >= 0 ? minX : maxX) * a);
    var upper = rounding.up((a >= 0 ? maxX : minX) * a);
    final b = _rotation[row + 1];
    final lowerY = rounding.down((b >= 0 ? minY : maxY) * b);
    final upperY = rounding.up((b >= 0 ? maxY : minY) * b);
    lower = rounding.down(lower + lowerY);
    upper = rounding.up(upper + upperY);
    final c = _rotation[row + 2];
    final lowerZ = rounding.down((c >= 0 ? minZ : maxZ) * c);
    final upperZ = rounding.up((c >= 0 ? maxZ : minZ) * c);
    lower = rounding.down(lower + lowerZ);
    upper = rounding.up(upper + upperZ);
    return (rounding.down(lower + offset), rounding.up(upper + offset));
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
  /// at extreme translations. [maxRoundingError] limits added point error and
  /// defaults to the source chord error. The output's chord error includes the
  /// conservative additional error; an over-budget or invalid mesh is rejected.
  CadKernelResult<CadMesh> transformMesh(CadMesh local,
      {double? maxRoundingError}) {
    final sourceIssues = local.validate();
    if (sourceIssues.isNotEmpty) {
      return CadKernelResult.failure(
          CadKernelStatus.invalidTopology, sourceIssues);
    }
    final budget = maxRoundingError ?? local.chordError;
    if (!budget.isFinite || budget <= 0) {
      return CadKernelResult.failure(CadKernelStatus.invalidInput, [
        const CadIssue('invalid_placement_error_budget',
            'Mesh placement error budget must be finite and positive.')
      ]);
    }
    final CadMesh world;
    try {
      final vertices = <CadPoint3>[];
      var addedError = 0.0;
      for (final vertex in local.vertices) {
        final checked = _checkedPoint(vertex);
        if (checked.$2 > budget) {
          return CadKernelResult.failure(CadKernelStatus.numericalFailure, [
            CadIssue('mesh_placement_precision',
                'Point rounding error ${checked.$2} exceeds the budget $budget.')
          ]);
        }
        vertices.add(checked.$1);
        addedError = math.max(addedError, checked.$2);
      }
      world = CadMesh(
          vertices: vertices,
          triangles: [
            for (final triangle in local.triangles)
              CadTriangle(triangle.a, triangle.b, triangle.c,
                  faceId: triangle.faceId)
          ],
          chordError: IntervalRounding.nextUp(local.chordError + addedError));
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
    this.linearTolerance = 1e-7,
  }) {
    if (featureId.isEmpty) {
      throw ArgumentError('A body instance needs a stable feature ID.');
    }
    if (!linearTolerance.isFinite || linearTolerance <= 0) {
      throw ArgumentError(
          'World topology tolerance must be finite and positive.');
    }
  }
  final String featureId;
  final CadBody body;
  final CadRigidTransform placement;

  /// Maximum materialization error in model units for world topology queries.
  /// Local prototype geometry remains unchanged; unresolvable queries fail.
  final double linearTolerance;
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
          point: _placePoint(entity.point));
    }
    if (entity is CadEdge) {
      final curve = entity.curve;
      final CadCurve transformed;
      if (curve is CadLineCurve) {
        final start = _placePoint(curve.start), end = _placePoint(curve.end);
        if ((end - start).length == 0) {
          throw StateError(
              'A nonzero analytic edge collapsed after placement.');
        }
        transformed = CadLineCurve(start, end);
      } else if (curve is CadCircleCurve) {
        transformed = CadCircleCurve(
            center: _placePoint(curve.center),
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
            origin: _placePoint(surface.origin),
            normal: placement.transformDirection(surface.normal));
      } else if (surface is CadCylinderSurface) {
        transformed = CadCylinderSurface(
            origin: _placePoint(surface.origin),
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
          loops: [
            for (final loop in entity.loops)
              CadBoundaryLoop([
                for (final edge in loop.edges)
                  CadOrientedEdge(edge.edgeId, reversed: edge.reversed)
              ])
          ]);
    }
    throw UnsupportedError('Unknown topology kind in a rigid instance.');
  }

  CadPoint3 _placePoint(CadPoint3 point) {
    final checked = placement._checkedPoint(point);
    if (checked.$2 > linearTolerance) {
      throw StateError('World topology point rounding error ${checked.$2} '
          'exceeds the placement tolerance $linearTolerance.');
    }
    return checked.$1;
  }
}

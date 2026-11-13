/// Geometry-kernel contracts for the parametric feature layer.
///
/// A backend must report unsupported operations explicitly. A tessellation is
/// a display/export approximation; it does not replace the analytic body.
library;

import 'dart:math' as math;

enum CadCapability {
  extrude,
  revolve,
  booleanUnion,
  booleanDifference,
  booleanIntersection,
  fillet,
  shell,
  tessellate,
  validate,
}

enum CadKernelStatus {
  success,
  invalidInput,
  unsupported,
  numericalFailure,
  invalidTopology
}

class CadIssue {
  const CadIssue(this.code, this.message, {this.entity});
  final String code;
  final String message;
  final String? entity;
  @override
  String toString() => '$code: $message';
}

class CadKernelResult<T extends Object> {
  CadKernelResult.success(T this.value)
      : status = CadKernelStatus.success,
        issues = const [];
  CadKernelResult.failure(this.status, Iterable<CadIssue> issues)
      : value = null,
        issues = List.unmodifiable(issues) {
    if (status == CadKernelStatus.success) {
      throw ArgumentError('A failed result cannot have success status.');
    }
  }
  final CadKernelStatus status;
  final T? value;
  final List<CadIssue> issues;
  bool get isSuccess => status == CadKernelStatus.success;
}

class CadPoint3 {
  const CadPoint3(this.x, this.y, this.z);
  final double x, y, z;
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;
  CadPoint3 operator +(CadPoint3 other) =>
      CadPoint3(x + other.x, y + other.y, z + other.z);
  CadPoint3 operator -(CadPoint3 other) =>
      CadPoint3(x - other.x, y - other.y, z - other.z);
  CadPoint3 scaled(double scale) => CadPoint3(x * scale, y * scale, z * scale);
  double dot(CadPoint3 other) => x * other.x + y * other.y + z * other.z;
  CadPoint3 cross(CadPoint3 other) => CadPoint3(y * other.z - z * other.y,
      z * other.x - x * other.z, x * other.y - y * other.x);
  double get length {
    final scale = math.max(x.abs(), math.max(y.abs(), z.abs()));
    if (scale == 0 || !scale.isFinite) return scale;
    final sx = x / scale, sy = y / scale, sz = z / scale;
    return scale * math.sqrt(sx * sx + sy * sy + sz * sz);
  }

  @override
  String toString() => '($x, $y, $z)';
}

class CadBounds {
  const CadBounds(this.min, this.max);
  final CadPoint3 min, max;
  bool get isFinite => min.isFinite && max.isFinite;
  bool contains(CadPoint3 point, {double tolerance = 0}) =>
      point.x >= min.x - tolerance &&
      point.x <= max.x + tolerance &&
      point.y >= min.y - tolerance &&
      point.y <= max.y + tolerance &&
      point.z >= min.z - tolerance &&
      point.z <= max.z + tolerance;
}

abstract class CadPlanarProfile {
  const CadPlanarProfile();
}

class CadCircularHole {
  const CadCircularHole(
      {required this.id,
      required this.centerX,
      required this.centerY,
      required this.radius});
  final String id;
  final double centerX, centerY, radius;
}

/// A centered XY rectangle with identified circular through-hole contours.
class CadRectangularProfile extends CadPlanarProfile {
  CadRectangularProfile(
      {required this.width,
      required this.height,
      Iterable<CadCircularHole> holes = const []})
      : holes = List.unmodifiable(holes);
  final double width, height;
  final List<CadCircularHole> holes;
  double get area =>
      width * height -
      holes.fold(0.0, (sum, hole) => sum + math.pi * hole.radius * hole.radius);
}

enum CadTopologyKind { vertex, edge, face }

abstract class CadTopologyEntity {
  const CadTopologyEntity({required this.id, required this.semanticId});

  /// Unique backend identity within this body.
  final String id;

  /// Stable design meaning. An external kernel may produce several entities
  /// with one meaning after a split, which must resolve as ambiguous.
  final String semanticId;
  CadTopologyKind get kind;
}

class CadVertex extends CadTopologyEntity {
  const CadVertex(
      {required super.id, required super.semanticId, required this.point});
  final CadPoint3 point;
  @override
  CadTopologyKind get kind => CadTopologyKind.vertex;
}

abstract class CadCurve {
  const CadCurve();
}

class CadLineCurve extends CadCurve {
  const CadLineCurve(this.start, this.end);
  final CadPoint3 start, end;
}

class CadCircleCurve extends CadCurve {
  const CadCircleCurve(
      {required this.center,
      required this.radius,
      this.normal = const CadPoint3(0, 0, 1)});
  final CadPoint3 center, normal;
  final double radius;
}

class CadEdge extends CadTopologyEntity {
  const CadEdge(
      {required super.id,
      required super.semanticId,
      required this.curve,
      this.startVertex,
      this.endVertex});
  final CadCurve curve;
  final String? startVertex, endVertex;
  @override
  CadTopologyKind get kind => CadTopologyKind.edge;
}

class CadOrientedEdge {
  const CadOrientedEdge(this.edgeId, {this.reversed = false});
  final String edgeId;
  final bool reversed;
}

class CadBoundaryLoop {
  CadBoundaryLoop(Iterable<CadOrientedEdge> edges)
      : edges = List.unmodifiable(edges);
  final List<CadOrientedEdge> edges;
}

abstract class CadSurface {
  const CadSurface();
}

class CadPlaneSurface extends CadSurface {
  const CadPlaneSurface({required this.origin, required this.normal});
  final CadPoint3 origin, normal;
}

class CadCylinderSurface extends CadSurface {
  const CadCylinderSurface(
      {required this.origin,
      required this.radius,
      this.axis = const CadPoint3(0, 0, 1),
      this.inward = false});
  final CadPoint3 origin, axis;
  final double radius;
  final bool inward;
}

class CadFace extends CadTopologyEntity {
  CadFace(
      {required super.id,
      required super.semanticId,
      required this.surface,
      required Iterable<CadBoundaryLoop> loops})
      : loops = List.unmodifiable(loops);
  final CadSurface surface;
  final List<CadBoundaryLoop> loops;
  @override
  CadTopologyKind get kind => CadTopologyKind.face;
}

enum CadTopologyResolutionStatus { found, missing, ambiguous }

class CadTopologyResolution {
  CadTopologyResolution(Iterable<CadTopologyEntity> matches)
      : matches = List.unmodifiable(matches);
  final List<CadTopologyEntity> matches;
  CadTopologyResolutionStatus get status => matches.isEmpty
      ? CadTopologyResolutionStatus.missing
      : matches.length == 1
          ? CadTopologyResolutionStatus.found
          : CadTopologyResolutionStatus.ambiguous;
  CadTopologyEntity? get entity => matches.length == 1 ? matches.single : null;
}

/// Immutable analytic boundary representation, independent of its mesh.
class CadBody {
  CadBody(
      {required this.featureId,
      required this.bounds,
      required this.volume,
      required Iterable<CadVertex> vertices,
      required Iterable<CadEdge> edges,
      required Iterable<CadFace> faces,
      this.backendData})
      : vertices = List.unmodifiable(vertices),
        edges = List.unmodifiable(edges),
        faces = List.unmodifiable(faces);
  final String featureId;
  final CadBounds bounds;
  final double volume;
  final List<CadVertex> vertices;
  final List<CadEdge> edges;
  final List<CadFace> faces;

  /// Backend-owned immutable construction record; callers must not mutate it.
  final Object? backendData;
  Iterable<CadTopologyEntity> get topology sync* {
    yield* vertices;
    yield* edges;
    yield* faces;
  }

  CadTopologyResolution resolve(CadTopologyKind kind, String semanticId) =>
      CadTopologyResolution(topology.where(
          (entity) => entity.kind == kind && entity.semanticId == semanticId));
}

class CadTriangle {
  const CadTriangle(this.a, this.b, this.c, {required this.faceId});
  final int a, b, c;
  final String faceId;
}

class CadMesh {
  CadMesh(
      {required Iterable<CadPoint3> vertices,
      required Iterable<CadTriangle> triangles,
      required this.chordError})
      : vertices = List.unmodifiable(vertices),
        triangles = List.unmodifiable(triangles);
  final List<CadPoint3> vertices;
  final List<CadTriangle> triangles;
  final double chordError;

  double get signedVolume {
    var volume = 0.0;
    for (final triangle in triangles) {
      final a = vertices[triangle.a],
          b = vertices[triangle.b],
          c = vertices[triangle.c];
      volume += a.dot(b.cross(c)) / 6;
    }
    return volume;
  }

  /// Independent combinatorial/winding checks; this does not certify absence
  /// of arbitrary triangle-triangle self-intersections from another backend.
  List<CadIssue> validate() {
    final issues = <CadIssue>[];
    if (vertices.any((point) => !point.isFinite)) {
      issues.add(const CadIssue(
          'non_finite_vertex', 'The mesh contains a non-finite vertex.'));
    }
    final edgeUse = <(int, int), (int, int)>{};
    for (final triangle in triangles) {
      final indices = [triangle.a, triangle.b, triangle.c];
      if (indices.any((index) => index < 0 || index >= vertices.length)) {
        issues.add(const CadIssue(
            'invalid_index', 'A triangle references a missing vertex.'));
        continue;
      }
      final a = vertices[triangle.a],
          b = vertices[triangle.b],
          c = vertices[triangle.c];
      if ((b - a).cross(c - a).length == 0) {
        issues.add(CadIssue('degenerate_triangle', 'A triangle has zero area.',
            entity: triangle.faceId));
      }
      for (var i = 0; i < 3; i++) {
        final from = indices[i], to = indices[(i + 1) % 3];
        final key = from < to ? (from, to) : (to, from);
        final use = edgeUse[key] ?? (0, 0);
        edgeUse[key] = (use.$1 + 1, use.$2 + (from < to ? 1 : -1));
      }
    }
    if (edgeUse.values.any((use) => use.$1 != 2 || use.$2 != 0)) {
      issues.add(const CadIssue('non_manifold_mesh',
          'Each mesh edge must be used twice with opposite directions.'));
    }
    if (issues.every((issue) => issue.code != 'invalid_index') &&
        (!signedVolume.isFinite || signedVolume <= 0)) {
      issues.add(const CadIssue('non_positive_volume',
          'The oriented mesh must enclose positive finite volume.'));
    }
    return List.unmodifiable(issues);
  }
}

enum CadBooleanOperation { union, difference, intersection }

abstract class CadKernel {
  Set<CadCapability> get capabilities;
  CadKernelResult<CadBody> extrude(
      {required String featureId,
      required CadPlanarProfile profile,
      required double depth});
  CadKernelResult<CadBody> revolve(
      {required String featureId,
      required CadPlanarProfile profile,
      required CadPoint3 axisOrigin,
      required CadPoint3 axisDirection,
      required double angle});
  CadKernelResult<CadBody> combine(
      {required String featureId,
      required CadBooleanOperation operation,
      required CadBody left,
      required CadBody right});
  CadKernelResult<CadBody> fillet(
      {required String featureId,
      required CadBody body,
      required List<String> edges,
      required double radius});
  CadKernelResult<CadBody> shell(
      {required String featureId,
      required CadBody body,
      required List<String> removedFaces,
      required double thickness});
  CadKernelResult<CadMesh> tessellate(CadBody body, {double chordError = 0.05});
  List<CadIssue> validate(CadBody body);
}

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

  /// Oriented volume, measured relative to a mesh vertex to avoid cancellation
  /// between enormous origin-based tetrahedra after a rigid translation.
  /// Compensated accumulation also preserves smaller contributions when face
  /// order mixes large positive and negative tetrahedra. Coordinates already
  /// rounded on input cannot be recovered by this calculation.
  double get signedVolume {
    if (vertices.isEmpty) return 0;
    final origin = vertices.first;
    var volume = 0.0, correction = 0.0;
    for (final triangle in triangles) {
      final a = vertices[triangle.a],
          b = vertices[triangle.b],
          c = vertices[triangle.c];
      final ax = a.x - origin.x, ay = a.y - origin.y, az = a.z - origin.z;
      final bx = b.x - origin.x, by = b.y - origin.y, bz = b.z - origin.z;
      final cx = c.x - origin.x, cy = c.y - origin.y, cz = c.z - origin.z;
      final contribution = (ax * (by * cz - bz * cy) +
              ay * (bz * cx - bx * cz) +
              az * (bx * cy - by * cx)) /
          6;
      final next = volume + contribution;
      correction += volume.abs() >= contribution.abs()
          ? (volume - next) + contribution
          : (contribution - next) + volume;
      volume = next;
    }
    return volume + correction;
  }

  /// Independent checks for a closed, oriented triangular boundary: distinct
  /// simplices, two opposite uses of each edge, and one cyclic link per vertex.
  ///
  /// Area and volume checks use doubles. Triangles whose area cannot be
  /// distinguished from rounding error, or a volume that underflows/overflows,
  /// are rejected. This is not an exact geometric predicate or a certificate
  /// against arbitrary triangle-triangle self-intersections from another backend.
  List<CadIssue> validate() {
    final issues = <CadIssue>[];
    if (!chordError.isFinite || chordError <= 0) {
      issues.add(const CadIssue('invalid_chord_error',
          'Mesh chord error must be finite and positive.'));
    }
    if (vertices.any((point) => !point.isFinite)) {
      issues.add(const CadIssue(
          'non_finite_vertex', 'The mesh contains a non-finite vertex.'));
    }
    final edgeUse = <(int, int), (int, int)>{};
    final simplices = <(int, int, int)>{};
    final vertexLinks = <int, Map<int, Set<int>>>{};
    for (final triangle in triangles) {
      final indices = [triangle.a, triangle.b, triangle.c];
      if (indices.any((index) => index < 0 || index >= vertices.length)) {
        issues.add(const CadIssue(
            'invalid_index', 'A triangle references a missing vertex.'));
        continue;
      }
      if (triangle.a == triangle.b ||
          triangle.b == triangle.c ||
          triangle.c == triangle.a) {
        issues.add(CadIssue('degenerate_triangle',
            'A triangle must reference three distinct vertices.',
            entity: triangle.faceId));
        continue;
      }
      final ordered = List<int>.of(indices)..sort();
      if (!simplices.add((ordered[0], ordered[1], ordered[2]))) {
        issues.add(CadIssue('duplicate_triangle',
            'A triangular simplex may occur only once, in either orientation.',
            entity: triangle.faceId));
        continue;
      }
      final a = vertices[triangle.a],
          b = vertices[triangle.b],
          c = vertices[triangle.c];
      if (!_hasResolvableTriangleArea(a, b, c)) {
        issues.add(CadIssue('degenerate_triangle',
            'Triangle area is zero, non-finite, or unresolved at double precision.',
            entity: triangle.faceId));
      }
      for (var i = 0; i < 3; i++) {
        final from = indices[i], to = indices[(i + 1) % 3];
        final key = from < to ? (from, to) : (to, from);
        final use = edgeUse[key] ?? (0, 0);
        edgeUse[key] = (use.$1 + 1, use.$2 + (from < to ? 1 : -1));
        // At this vertex the other two vertices form one edge of its link.
        // A closed triangular 2-manifold has exactly one cycle in this link;
        // edge incidence alone misses two closed shells pinched at a vertex.
        final other = indices[(i + 2) % 3];
        final link = vertexLinks.putIfAbsent(from, () => <int, Set<int>>{});
        link.putIfAbsent(to, () => <int>{}).add(other);
        link.putIfAbsent(other, () => <int>{}).add(to);
      }
    }
    if (edgeUse.values.any((use) => use.$1 != 2 || use.$2 != 0)) {
      issues.add(const CadIssue('non_manifold_mesh',
          'Each mesh edge must be used twice with opposite directions.'));
    }
    for (var vertex = 0; vertex < vertices.length; vertex++) {
      final link = vertexLinks[vertex];
      if (link == null) {
        issues.add(CadIssue('unused_vertex',
            'A solid boundary cannot contain an isolated vertex.',
            entity: '$vertex'));
        continue;
      }
      var isCycle = link.length >= 3 &&
          link.values.every((neighbors) => neighbors.length == 2);
      if (isCycle) {
        final seen = <int>{}, pending = <int>[link.keys.first];
        while (pending.isNotEmpty) {
          final next = pending.removeLast();
          if (seen.add(next)) pending.addAll(link[next]!);
        }
        isCycle = seen.length == link.length;
      }
      if (!isCycle) {
        issues.add(CadIssue('non_manifold_vertex',
            'Incident triangles must form a single closed fan around a vertex.',
            entity: '$vertex'));
      }
    }
    if (issues.every((issue) => issue.code != 'invalid_index')) {
      final volume = signedVolume;
      if (!volume.isFinite || volume <= 0) {
        issues.add(const CadIssue('non_positive_volume',
            'The oriented mesh must enclose positive finite volume.'));
      }
    }
    return List.unmodifiable(issues);
  }
}

bool _hasResolvableTriangleArea(CadPoint3 a, CadPoint3 b, CadPoint3 c) {
  final u = b - a, v = c - a;
  if (!u.isFinite || !v.isFinite) return false;
  final us = math.max(u.x.abs(), math.max(u.y.abs(), u.z.abs()));
  final vs = math.max(v.x.abs(), math.max(v.y.abs(), v.z.abs()));
  if (us == 0 || vs == 0) return false;
  // Scale each edge separately; squaring raw coordinates can underflow or
  // overflow even when the triangle's directional area is well represented.
  final un = CadPoint3(u.x / us, u.y / us, u.z / us);
  final vn = CadPoint3(v.x / vs, v.y / vs, v.z / vs);
  bool resolved(double p, double q) =>
      (p - q).abs() > 8 * 2.220446049250313e-16 * (p.abs() + q.abs()) + 5e-324;
  return resolved(un.y * vn.z, un.z * vn.y) ||
      resolved(un.z * vn.x, un.x * vn.z) ||
      resolved(un.x * vn.y, un.y * vn.x);
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

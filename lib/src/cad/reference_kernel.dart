/// Pure-Dart reference kernel for rectangular plates with circular holes.
///
/// Extrusion retains analytic planes and cylinders. Tessellation supports
/// holes whose X projections are disjoint, and reports unsupported otherwise.
/// General booleans, fillets, shells and revolutions require another backend.
library;

import 'dart:math' as math;

import 'kernel.dart';

class ReferenceCadKernel implements CadKernel {
  const ReferenceCadKernel();

  @override
  Set<CadCapability> get capabilities => const {
        CadCapability.extrude,
        CadCapability.tessellate,
        CadCapability.validate,
      };

  CadKernelResult<T> _failure<T extends Object>(
          CadKernelStatus status, String code, String message) =>
      CadKernelResult.failure(status, [CadIssue(code, message)]);

  @override
  CadKernelResult<CadBody> extrude(
      {required String featureId,
      required CadPlanarProfile profile,
      required double depth}) {
    if (profile is! CadRectangularProfile) {
      return _failure(CadKernelStatus.unsupported, 'profile_not_supported',
          'This backend extrudes centered rectangles with circular holes.');
    }
    // Public profile/hole classes can expose changing getters. Read their
    // scalar declarations once, then validate and construct only this owned
    // snapshot so the cached body cannot seal inconsistent analytic geometry.
    final width = profile.width, height = profile.height;
    if (!width.isFinite ||
        width <= 0 ||
        !height.isFinite ||
        height <= 0 ||
        !depth.isFinite ||
        depth <= 0) {
      return _failure(CadKernelStatus.invalidInput, 'invalid_dimensions',
          'Width, height and extrusion depth must be finite and positive.');
    }
    final captured =
        CadRectangularProfile(width: width, height: height, holes: [
      for (final hole in profile.holes)
        CadCircularHole(
            id: hole.id,
            centerX: hole.centerX,
            centerY: hole.centerY,
            radius: hole.radius)
    ]);
    final issues = _profileIssues(captured, depth);
    if (issues.isNotEmpty) {
      return CadKernelResult.failure(CadKernelStatus.invalidInput, issues);
    }
    if (featureId.isEmpty) {
      return _failure(CadKernelStatus.invalidInput, 'empty_feature_id',
          'An extrusion needs a stable feature ID.');
    }
    final volume = captured.area * depth;
    if (!volume.isFinite || volume <= 0) {
      return _failure(CadKernelStatus.numericalFailure, 'invalid_volume',
          'The analytic volume is not positive and finite at this scale.');
    }
    final halfW = captured.width / 2, halfH = captured.height / 2;
    final corners = [
      CadPoint3(-halfW, -halfH, 0),
      CadPoint3(halfW, -halfH, 0),
      CadPoint3(halfW, halfH, 0),
      CadPoint3(-halfW, halfH, 0)
    ];
    const cornerNames = ['sw', 'se', 'ne', 'nw'];
    const sideNames = ['south', 'east', 'north', 'west'];
    final vertices = <CadVertex>[];
    final edges = <CadEdge>[];
    final faces = <CadFace>[];
    for (var i = 0; i < 4; i++) {
      final point = corners[i], next = corners[(i + 1) % 4];
      final name = cornerNames[i], nextName = cornerNames[(i + 1) % 4];
      for (final top in [false, true]) {
        final level = top ? 'top' : 'bottom';
        final z = top ? depth : 0.0;
        final vertexId = 'corner.$name.$level';
        vertices.add(CadVertex(
            id: vertexId,
            semanticId: vertexId,
            point: CadPoint3(point.x, point.y, z)));
        final edgeId = 'outer.${sideNames[i]}.$level';
        edges.add(CadEdge(
            id: edgeId,
            semanticId: edgeId,
            curve: CadLineCurve(
                CadPoint3(point.x, point.y, z), CadPoint3(next.x, next.y, z)),
            startVertex: vertexId,
            endVertex: 'corner.$nextName.$level'));
      }
      final edgeId = 'corner.$name.vertical';
      edges.add(CadEdge(
          id: edgeId,
          semanticId: edgeId,
          curve: CadLineCurve(point, CadPoint3(point.x, point.y, depth)),
          startVertex: 'corner.$name.bottom',
          endVertex: 'corner.$name.top'));
      final delta = next - point;
      final length = delta.length;
      faces.add(CadFace(
          id: 'side.${sideNames[i]}',
          semanticId: 'side.${sideNames[i]}',
          surface: CadPlaneSurface(
              origin: point,
              normal: CadPoint3(delta.y / length, -delta.x / length, 0)),
          loops: [
            CadBoundaryLoop([
              CadOrientedEdge('outer.${sideNames[i]}.bottom'),
              CadOrientedEdge('corner.$nextName.vertical'),
              CadOrientedEdge('outer.${sideNames[i]}.top', reversed: true),
              CadOrientedEdge('corner.$name.vertical', reversed: true),
            ])
          ]));
    }
    final topLoops = <CadBoundaryLoop>[
      CadBoundaryLoop([
        for (final side in sideNames) CadOrientedEdge('outer.$side.top'),
      ])
    ];
    final bottomLoops = <CadBoundaryLoop>[
      CadBoundaryLoop([
        for (final side in sideNames.reversed)
          CadOrientedEdge('outer.$side.bottom', reversed: true),
      ])
    ];
    for (final hole in captured.holes) {
      for (final top in [false, true]) {
        final edgeId = 'hole.${hole.id}.${top ? 'top' : 'bottom'}';
        edges.add(CadEdge(
            id: edgeId,
            semanticId: edgeId,
            curve: CadCircleCurve(
                center: CadPoint3(hole.centerX, hole.centerY, top ? depth : 0),
                radius: hole.radius)));
      }
      topLoops.add(CadBoundaryLoop(
          [CadOrientedEdge('hole.${hole.id}.top', reversed: true)]));
      bottomLoops
          .add(CadBoundaryLoop([CadOrientedEdge('hole.${hole.id}.bottom')]));
      final faceId = 'hole.${hole.id}.wall';
      faces.add(CadFace(
          id: faceId,
          semanticId: faceId,
          surface: CadCylinderSurface(
              origin: CadPoint3(hole.centerX, hole.centerY, 0),
              radius: hole.radius,
              inward: true),
          loops: [
            CadBoundaryLoop(
                [CadOrientedEdge('hole.${hole.id}.bottom', reversed: true)]),
            CadBoundaryLoop([CadOrientedEdge('hole.${hole.id}.top')])
          ]));
    }
    faces.add(CadFace(
        id: 'top',
        semanticId: 'top',
        surface: CadPlaneSurface(
            origin: CadPoint3(0, 0, depth), normal: const CadPoint3(0, 0, 1)),
        loops: topLoops));
    faces.add(CadFace(
        id: 'bottom',
        semanticId: 'bottom',
        surface: const CadPlaneSurface(
            origin: CadPoint3(0, 0, 0), normal: CadPoint3(0, 0, -1)),
        loops: bottomLoops));
    final body = _ReferenceCadBody(
        featureId: featureId,
        bounds: CadBounds(
            CadPoint3(-halfW, -halfH, 0), CadPoint3(halfW, halfH, depth)),
        volume: volume,
        vertices: vertices,
        edges: edges,
        faces: faces,
        backendData: _ExtrusionData(captured, depth, vertices, edges, faces));
    final validation = validate(body);
    return validation.isEmpty
        ? CadKernelResult.success(body)
        : CadKernelResult.failure(CadKernelStatus.invalidTopology, validation);
  }

  List<CadIssue> _profileIssues(CadRectangularProfile profile, double depth) {
    final issues = <CadIssue>[];
    if (![profile.width, profile.height, depth]
        .every((v) => v.isFinite && v > 0)) {
      return [
        const CadIssue('invalid_dimensions',
            'Width, height and extrusion depth must be finite and positive.')
      ];
    }
    final ids = <String>{};
    for (final hole in profile.holes) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(hole.id) ||
          !ids.add(hole.id)) {
        issues.add(CadIssue(
            'invalid_hole_id', 'Hole IDs must be unique identifiers.',
            entity: hole.id));
      }
      if (![hole.centerX, hole.centerY, hole.radius].every((v) => v.isFinite) ||
          hole.radius <= 0) {
        issues.add(CadIssue(
            'invalid_hole', 'Hole centers must be finite and radii positive.',
            entity: hole.id));
        continue;
      }
      if (hole.centerX.abs() + hole.radius >= profile.width / 2 ||
          hole.centerY.abs() + hole.radius >= profile.height / 2) {
        issues.add(CadIssue('hole_outside_profile',
            'A hole must be strictly inside the outer contour.',
            entity: hole.id));
      }
    }
    for (var i = 0; i < profile.holes.length; i++) {
      for (var j = i + 1; j < profile.holes.length; j++) {
        final a = profile.holes[i], b = profile.holes[j];
        final dx = a.centerX - b.centerX, dy = a.centerY - b.centerY;
        final distance = CadPoint3(dx, dy, 0).length;
        if (!distance.isFinite || distance <= a.radius + b.radius) {
          issues.add(CadIssue(
              'overlapping_holes', 'Circular holes may not overlap or touch.',
              entity: '${a.id},${b.id}'));
        }
      }
    }
    return issues;
  }

  @override
  List<CadIssue> validate(CadBody body) {
    // Only this backend's own final body class has a deeply immutable boundary
    // assembled from concrete value objects. Public bodies and custom subclasses
    // may expose changing getters, so they must pass the complete validator on
    // every call. A custom kernel's override still runs before reaching here.
    if (body is _ReferenceCadBody && body._validation != null) {
      return body._validation!;
    }
    final issues = <CadIssue>[];
    if (!body.volume.isFinite || body.volume <= 0 || !body.bounds.isFinite) {
      issues.add(const CadIssue('invalid_body_extent',
          'Body bounds and positive volume must be finite.'));
    }
    final ids = <String>{};
    for (final entity in body.topology) {
      if (!ids.add(entity.id)) {
        issues.add(CadIssue(
            'duplicate_topology_id', 'Topology IDs must be unique.',
            entity: entity.id));
      }
    }
    final vertices = {for (final vertex in body.vertices) vertex.id: vertex};
    final edges = {for (final edge in body.edges) edge.id: edge};
    bool samePoint(CadPoint3 a, CadPoint3 b) =>
        a.x == b.x && a.y == b.y && a.z == b.z;
    for (final vertex in body.vertices) {
      if (!vertex.point.isFinite || !body.bounds.contains(vertex.point)) {
        issues.add(CadIssue('invalid_vertex',
            'A vertex is non-finite or outside the body bounds.',
            entity: vertex.id));
      }
    }
    for (final edge in body.edges) {
      final curve = edge.curve;
      if (curve is CadLineCurve) {
        final start = vertices[edge.startVertex],
            end = vertices[edge.endVertex];
        if (!curve.start.isFinite ||
            !curve.end.isFinite ||
            (curve.end - curve.start).length == 0 ||
            (start != null && !samePoint(start.point, curve.start)) ||
            (end != null && !samePoint(end.point, curve.end))) {
          issues.add(CadIssue('invalid_edge_geometry',
              'Line geometry must agree with distinct finite endpoint vertices.',
              entity: edge.id));
        }
      } else if (curve is CadCircleCurve) {
        if (!curve.center.isFinite ||
            !curve.radius.isFinite ||
            curve.radius <= 0 ||
            !curve.normal.isFinite ||
            (curve.normal.length - 1).abs() > 1e-10) {
          issues.add(CadIssue('invalid_edge_geometry',
              'A circle needs a finite center, positive radius, and unit normal.',
              entity: edge.id));
        }
      } else {
        issues.add(CadIssue('unsupported_curve',
            'This validator supports line and circle edges.',
            entity: edge.id));
      }
    }
    final edgeUse = <String, (int, int)>{};
    for (final face in body.faces) {
      final surface = face.surface;
      final validSurface = surface is CadPlaneSurface
          ? surface.origin.isFinite &&
              surface.normal.isFinite &&
              (surface.normal.length - 1).abs() <= 1e-10
          : surface is CadCylinderSurface &&
              surface.origin.isFinite &&
              surface.axis.isFinite &&
              (surface.axis.length - 1).abs() <= 1e-10 &&
              surface.radius.isFinite &&
              surface.radius > 0;
      if (!validSurface) {
        issues.add(CadIssue('invalid_surface',
            'The reference validator requires a finite plane or cylinder with unit orientation.',
            entity: face.id));
      }
      if (face.loops.isEmpty) {
        issues.add(CadIssue('unbounded_face', 'A face needs a boundary loop.',
            entity: face.id));
      }
      for (final loop in face.loops) {
        if (loop.edges.isEmpty) {
          issues.add(CadIssue('empty_loop', 'A boundary loop may not be empty.',
              entity: face.id));
        }
        for (var i = 0; i < loop.edges.length; i++) {
          final oriented = loop.edges[i];
          final edge = edges[oriented.edgeId];
          if (edge == null) {
            issues.add(CadIssue(
                'missing_edge', 'A face references a missing edge.',
                entity: oriented.edgeId));
            continue;
          }
          final use = edgeUse[edge.id] ?? (0, 0);
          edgeUse[edge.id] =
              (use.$1 + 1, use.$2 + (oriented.reversed ? -1 : 1));
          if (edge.curve is CadLineCurve) {
            if (!vertices.containsKey(edge.startVertex) ||
                !vertices.containsKey(edge.endVertex)) {
              issues.add(CadIssue(
                  'missing_vertex', 'A line edge references a missing vertex.',
                  entity: edge.id));
            }
            final next = loop.edges[(i + 1) % loop.edges.length];
            final nextEdge = edges[next.edgeId];
            final end = oriented.reversed ? edge.startVertex : edge.endVertex;
            final start =
                next.reversed ? nextEdge?.endVertex : nextEdge?.startVertex;
            if (end != start) {
              issues.add(CadIssue(
                  'open_loop', 'Boundary edges do not form a closed loop.',
                  entity: face.id));
            }
          }
        }
      }
    }
    if (body.edges.any((edge) => edgeUse[edge.id] != (2, 0))) {
      issues.add(const CadIssue('non_manifold_boundary',
          'Each boundary edge must occur in two faces with opposite orientations.'));
    }
    final data = body.backendData;
    if (data is _ExtrusionData) {
      issues.addAll(_profileIssues(data.profile, data.depth));
      issues.addAll(data.validateBoundary(body));
      final expectedVolume = data.profile.area * data.depth;
      final expectedMin =
          CadPoint3(-data.profile.width / 2, -data.profile.height / 2, 0);
      final expectedMax = CadPoint3(
          data.profile.width / 2, data.profile.height / 2, data.depth);
      if (body.volume != expectedVolume ||
          !samePoint(body.bounds.min, expectedMin) ||
          !samePoint(body.bounds.max, expectedMax)) {
        issues.add(const CadIssue('inconsistent_body_metrics',
            'Body metrics disagree with its analytic construction.'));
      }
    } else {
      issues.add(const CadIssue('unknown_construction',
          'This reference validator accepts its own extrusion construction records.'));
    }
    final result = List<CadIssue>.unmodifiable(issues);
    if (body is _ReferenceCadBody) body._validation = result;
    return result;
  }

  @override
  CadKernelResult<CadMesh> tessellate(CadBody body,
      {double chordError = 0.05}) {
    final data = body.backendData;
    if (data is! _ExtrusionData) {
      return _failure(CadKernelStatus.unsupported, 'foreign_body',
          'This backend tessellates its own analytic extrusions.');
    }
    if (!chordError.isFinite || chordError <= 0) {
      return _failure(CadKernelStatus.invalidInput, 'invalid_chord_error',
          'Chord error must be finite and positive.');
    }
    final validation = validate(body);
    if (validation.isNotEmpty) {
      return CadKernelResult.failure(
          CadKernelStatus.invalidTopology, validation);
    }
    final holes = List<CadCircularHole>.of(data.profile.holes)
      ..sort((a, b) => (a.centerX - a.radius).compareTo(b.centerX - b.radius));
    for (var i = 1; i < holes.length; i++) {
      if (holes[i - 1].centerX + holes[i - 1].radius >=
          holes[i].centerX - holes[i].radius) {
        return _failure(
            CadKernelStatus.unsupported,
            'overlapping_hole_projections',
            'Reference tessellation requires disjoint hole X projections; the analytic body remains valid.');
      }
    }
    final mesh = _MeshBuilder();
    final profile = data.profile;
    final xmin = -profile.width / 2, xmax = profile.width / 2;
    final ymin = -profile.height / 2, ymax = profile.height / 2;
    final z = data.depth;
    final outerXs = <double>[xmin];
    var left = xmin;
    double? leftSplit;
    void cap(List<CadPoint3> polygon) {
      final center = polygon.reduce((a, b) => a + b).scaled(1 / polygon.length);
      for (var i = 0; i < polygon.length; i++) {
        final a = polygon[i], b = polygon[(i + 1) % polygon.length];
        mesh.triangle(CadPoint3(center.x, center.y, z), CadPoint3(a.x, a.y, z),
            CadPoint3(b.x, b.y, z), 'top');
        mesh.triangle(center, b, a, 'bottom');
      }
    }

    void gap(double right, double? rightSplit) {
      cap([
        CadPoint3(left, ymin, 0),
        CadPoint3(right, ymin, 0),
        if (rightSplit != null) CadPoint3(right, rightSplit, 0),
        CadPoint3(right, ymax, 0),
        CadPoint3(left, ymax, 0),
        if (leftSplit != null) CadPoint3(left, leftSplit, 0)
      ]);
    }

    for (final hole in holes) {
      final delta = math.acos(1 - math.min(1.0, chordError / hole.radius));
      if (!delta.isFinite || delta == 0) {
        return _failure(CadKernelStatus.unsupported, 'tessellation_precision',
            'The requested chord error is below double precision.');
      }
      final segments = math.max(16, ((math.pi / delta).ceil() + 3) ~/ 4 * 4);
      if (segments > 4096) {
        return _failure(CadKernelStatus.unsupported, 'tessellation_budget',
            'The reference backend limits each hole to 4096 segments.');
      }
      final upper = <CadPoint3>[], lower = <CadPoint3>[];
      for (var j = 0; j <= segments ~/ 2; j++) {
        final angle = math.pi - j * 2 * math.pi / segments;
        final x = j == 0
            ? hole.centerX - hole.radius
            : j == segments ~/ 2
                ? hole.centerX + hole.radius
                : hole.centerX + hole.radius * math.cos(angle);
        final offset =
            j == 0 || j == segments ~/ 2 ? 0.0 : hole.radius * math.sin(angle);
        upper.add(CadPoint3(x, hole.centerY + offset, 0));
        lower.add(CadPoint3(x, hole.centerY - offset, 0));
      }
      gap(upper.first.x, hole.centerY);
      outerXs.addAll(upper.map((point) => point.x));
      for (var j = 0; j < upper.length - 1; j++) {
        final a = upper[j], b = upper[j + 1];
        cap([a, b, CadPoint3(b.x, ymax, 0), CadPoint3(a.x, ymax, 0)]);
        final c = lower[j], d = lower[j + 1];
        cap([CadPoint3(c.x, ymin, 0), CadPoint3(d.x, ymin, 0), d, c]);
      }
      final ring = [...upper.reversed, ...lower.skip(1).take(lower.length - 2)];
      for (var j = 0; j < ring.length; j++) {
        final a = ring[j], b = ring[(j + 1) % ring.length];
        mesh.quad(a, CadPoint3(a.x, a.y, z), CadPoint3(b.x, b.y, z), b,
            'hole.${hole.id}.wall');
      }
      left = upper.last.x;
      leftSplit = hole.centerY;
    }
    gap(xmax, null);
    outerXs.add(xmax);
    for (var i = 0; i < outerXs.length - 1; i++) {
      final a = outerXs[i], b = outerXs[i + 1];
      mesh.quad(CadPoint3(a, ymin, 0), CadPoint3(b, ymin, 0),
          CadPoint3(b, ymin, z), CadPoint3(a, ymin, z), 'side.south');
      mesh.quad(CadPoint3(b, ymax, 0), CadPoint3(a, ymax, 0),
          CadPoint3(a, ymax, z), CadPoint3(b, ymax, z), 'side.north');
    }
    mesh.quad(CadPoint3(xmin, ymax, 0), CadPoint3(xmin, ymin, 0),
        CadPoint3(xmin, ymin, z), CadPoint3(xmin, ymax, z), 'side.west');
    mesh.quad(CadPoint3(xmax, ymin, 0), CadPoint3(xmax, ymax, 0),
        CadPoint3(xmax, ymax, z), CadPoint3(xmax, ymin, z), 'side.east');
    final result = _ReferenceCadMesh(
        vertices: mesh.vertices,
        triangles: mesh.triangles,
        chordError: chordError);
    final issues = result.validate();
    return issues.isEmpty
        ? CadKernelResult.success(result)
        : CadKernelResult.failure(CadKernelStatus.invalidTopology, issues);
  }

  @override
  CadKernelResult<CadBody> revolve(
          {required String featureId,
          required CadPlanarProfile profile,
          required CadPoint3 axisOrigin,
          required CadPoint3 axisDirection,
          required double angle}) =>
      _failure(CadKernelStatus.unsupported, 'revolve_not_supported',
          'This backend does not implement revolution.');
  @override
  CadKernelResult<CadBody> combine(
          {required String featureId,
          required CadBooleanOperation operation,
          required CadBody left,
          required CadBody right}) =>
      _failure(CadKernelStatus.unsupported, 'boolean_not_supported',
          'This backend does not implement general solid booleans.');
  @override
  CadKernelResult<CadBody> fillet(
          {required String featureId,
          required CadBody body,
          required List<String> edges,
          required double radius}) =>
      _failure(CadKernelStatus.unsupported, 'fillet_not_supported',
          'This backend does not implement edge fillets.');
  @override
  CadKernelResult<CadBody> shell(
          {required String featureId,
          required CadBody body,
          required List<String> removedFaces,
          required double thickness}) =>
      _failure(CadKernelStatus.unsupported, 'shell_not_supported',
          'This backend does not implement shell offsets.');
}

/// Constructed only here from this backend's concrete immutable value objects.
/// Callers cannot manufacture this cache boundary by copying backendData.
final class _ReferenceCadBody extends CadBody {
  _ReferenceCadBody(
      {required super.featureId,
      required super.bounds,
      required super.volume,
      required super.vertices,
      required super.edges,
      required super.faces,
      required super.backendData});

  List<CadIssue>? _validation;
}

/// Reference tessellation creates all points and triangles itself; its complete
/// numerical and combinatorial validation can therefore be reused unchanged.
/// The public CadMesh class remains uncached for custom value subclasses.
final class _ReferenceCadMesh extends CadMesh {
  _ReferenceCadMesh(
      {required super.vertices,
      required super.triangles,
      required super.chordError});

  List<CadIssue>? _validation;
  double? _volume;

  @override
  double get signedVolume => _volume ??= super.signedVolume;

  @override
  List<CadIssue> validate() => _validation ??= super.validate();
}

class _ExtrusionData {
  // `profile` is the concrete, privately owned entry snapshot from extrude.
  _ExtrusionData(this.profile, this.depth, Iterable<CadVertex> vertices,
      Iterable<CadEdge> edges, Iterable<CadFace> faces)
      : vertices = Map.unmodifiable({for (final v in vertices) v.id: v}),
        edges = Map.unmodifiable({for (final e in edges) e.id: e}),
        faces = Map.unmodifiable({for (final f in faces) f.id: f});
  final CadRectangularProfile profile;
  final double depth;

  // These objects were created by extrude and are immutable. Keeping the
  // construction's actual boundary avoids both rebuilding it on each check and
  // the extrude -> validate -> extrude recursion that regeneration would cause.
  final Map<String, CadVertex> vertices;
  final Map<String, CadEdge> edges;
  final Map<String, CadFace> faces;

  /// The reference backend validates its own represented construction, not an
  /// arbitrary B-rep. Geometry and topology must agree with that construction.
  /// Semantic IDs are deliberately independent: a kernel adapter can change
  /// provenance without changing geometry, and document reference resolution
  /// must then report missing/ambiguous matches rather than guess a face.
  List<CadIssue> validateBoundary(CadBody body) {
    final issues = <CadIssue>[];
    bool sameIds<T extends CadTopologyEntity>(
            List<T> actual, Map<String, T> expected) =>
        actual.length == expected.length &&
        actual.map((entity) => entity.id).toSet().length == expected.length &&
        actual.every((entity) => expected.containsKey(entity.id));
    if (!sameIds(body.vertices, vertices) ||
        !sameIds(body.edges, edges) ||
        !sameIds(body.faces, faces)) {
      issues.add(const CadIssue(
          'inconsistent_construction_topology',
          'Boundary entities disagree with the recorded extrusion; '
              'vertices, edges, and faces cannot be omitted or added.'));
    }
    for (final vertex in body.vertices) {
      final expected = vertices[vertex.id];
      if (expected != null && !_samePoint(vertex.point, expected.point)) {
        issues.add(CadIssue('inconsistent_vertex_geometry',
            'Vertex coordinates disagree with the recorded extrusion.',
            entity: vertex.id));
      }
    }
    for (final edge in body.edges) {
      final expected = edges[edge.id];
      if (expected != null &&
          (edge.startVertex != expected.startVertex ||
              edge.endVertex != expected.endVertex ||
              !_sameCurve(edge.curve, expected.curve))) {
        issues.add(CadIssue('inconsistent_edge_geometry',
            'Edge geometry or endpoints disagree with the recorded extrusion.',
            entity: edge.id));
      }
    }
    for (final face in body.faces) {
      final expected = faces[face.id];
      if (expected == null) continue;
      if (!_sameSurface(face.surface, expected.surface)) {
        issues.add(CadIssue('inconsistent_face_geometry',
            'Face geometry disagrees with the recorded extrusion.',
            entity: face.id));
      }
      if (!_sameLoops(face.loops, expected.loops)) {
        issues.add(CadIssue('inconsistent_face_boundary',
            'Oriented boundary loops disagree with the recorded extrusion.',
            entity: face.id));
      }
    }
    return issues;
  }

  static bool _samePoint(CadPoint3 a, CadPoint3 b) =>
      a.x == b.x && a.y == b.y && a.z == b.z;

  static bool _sameCurve(CadCurve actual, CadCurve expected) {
    if (actual is CadLineCurve && expected is CadLineCurve) {
      return _samePoint(actual.start, expected.start) &&
          _samePoint(actual.end, expected.end);
    }
    return actual is CadCircleCurve &&
        expected is CadCircleCurve &&
        _samePoint(actual.center, expected.center) &&
        _samePoint(actual.normal, expected.normal) &&
        actual.radius == expected.radius;
  }

  static bool _sameSurface(CadSurface actual, CadSurface expected) {
    if (actual is CadPlaneSurface && expected is CadPlaneSurface) {
      // Origins can move within an unchanged plane. The reference extrusion's
      // plane normals are coordinate axes, so this comparison does not need a
      // scale-dependent geometric epsilon or a rounded general dot product.
      if (!_samePoint(actual.normal, expected.normal)) return false;
      return (expected.normal.x == 0 || actual.origin.x == expected.origin.x) &&
          (expected.normal.y == 0 || actual.origin.y == expected.origin.y) &&
          (expected.normal.z == 0 || actual.origin.z == expected.origin.z);
    }
    if (actual is CadCylinderSurface && expected is CadCylinderSurface) {
      // All supported cylinders are parallel to Z. Their origin can move
      // along the same axis without changing the represented surface.
      return _samePoint(actual.axis, expected.axis) &&
          actual.origin.x == expected.origin.x &&
          actual.origin.y == expected.origin.y &&
          actual.radius == expected.radius &&
          actual.inward == expected.inward;
    }
    return false;
  }

  static bool _sameLoops(
      List<CadBoundaryLoop> actual, List<CadBoundaryLoop> expected) {
    if (actual.length != expected.length) return false;
    final counts = <String, int>{};
    for (final loop in expected) {
      final key = _loopKey(loop);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    for (final loop in actual) {
      final key = _loopKey(loop), count = counts[key] ?? 0;
      if (count == 0) return false;
      counts[key] = count - 1;
    }
    return true;
  }

  static String _loopKey(CadBoundaryLoop loop) {
    if (loop.edges.isEmpty) return '';
    final edges = [
      for (final edge in loop.edges) '${edge.edgeId}:${edge.reversed ? 1 : 0}'
    ];
    var first = 0;
    for (var i = 1; i < edges.length; i++) {
      if (edges[i].compareTo(edges[first]) < 0) first = i;
    }
    return [
      for (var i = 0; i < edges.length; i++) edges[(first + i) % edges.length]
    ].join(',');
  }
}

class _MeshBuilder {
  final vertices = <CadPoint3>[];
  final triangles = <CadTriangle>[];
  final _indices = <(double, double, double), int>{};
  int vertex(CadPoint3 point) {
    // Numeric record equality also identifies -0.0 with 0.0. Avoid formatting
    // three coordinates into a temporary string for every triangle corner.
    final key = (point.x, point.y, point.z);
    return _indices.putIfAbsent(key, () {
      vertices.add(point);
      return vertices.length - 1;
    });
  }

  void triangle(CadPoint3 a, CadPoint3 b, CadPoint3 c, String face) =>
      triangles.add(CadTriangle(vertex(a), vertex(b), vertex(c), faceId: face));
  void quad(CadPoint3 a, CadPoint3 b, CadPoint3 c, CadPoint3 d, String face) {
    triangle(a, b, c, face);
    triangle(a, c, d, face);
  }
}

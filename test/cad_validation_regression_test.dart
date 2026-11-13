import 'package:dart_csp/src/cad/features.dart';
import 'package:dart_csp/src/cad/kernel.dart';
import 'package:dart_csp/src/cad/reference_kernel.dart';
import 'package:test/test.dart';

const _kernel = ReferenceCadKernel();

CadBody _plate({bool hole = false, double centerX = 0}) => _kernel
    .extrude(
        featureId: 'plate',
        depth: 2,
        profile: CadRectangularProfile(width: 20, height: 10, holes: [
          if (hole)
            CadCircularHole(
                id: 'mount', centerX: centerX, centerY: 0, radius: 1),
        ]))
    .value!;

CadBody _copyBody(CadBody body,
        {Iterable<CadVertex>? vertices,
        Iterable<CadEdge>? edges,
        Iterable<CadFace>? faces,
        Object? backendData}) =>
    CadBody(
        featureId: body.featureId,
        bounds: body.bounds,
        volume: body.volume,
        vertices: vertices ?? body.vertices,
        edges: edges ?? body.edges,
        faces: faces ?? body.faces,
        backendData: backendData ?? body.backendData);

CadFace _copyFace(CadFace face,
        {CadSurface? surface,
        Iterable<CadBoundaryLoop>? loops,
        String? semanticId}) =>
    CadFace(
        id: face.id,
        semanticId: semanticId ?? face.semanticId,
        surface: surface ?? face.surface,
        loops: loops ?? face.loops);

CadMesh _tetrahedron({double scale = 1}) => CadMesh(vertices: [
      const CadPoint3(0, 0, 0),
      CadPoint3(scale, 0, 0),
      CadPoint3(0, scale, 0),
      CadPoint3(0, 0, scale),
    ], triangles: [
      for (final t in const [
        [0, 2, 1],
        [0, 1, 3],
        [0, 3, 2],
        [1, 2, 3]
      ])
        CadTriangle(t[0], t[1], t[2], faceId: 'tetra'),
    ], chordError: 0.01);

Set<String> _codes(Iterable<CadIssue> issues) =>
    {for (final issue in issues) issue.code};

void main() {
  group('reference construction boundary integrity', () {
    test('empty topology cannot borrow a valid positive volume record', () {
      final body = _plate();
      final empty = _copyBody(body, vertices: [], edges: [], faces: []);
      expect(_codes(_kernel.validate(empty)),
          contains('inconsistent_construction_topology'));
      expect(_kernel.tessellate(empty).status, CadKernelStatus.invalidTopology);
    });

    test('removed or added entities disagree with the recorded solid', () {
      final body = _plate(hole: true);
      final altered = [
        _copyBody(body, vertices: body.vertices.skip(1)),
        _copyBody(body, edges: body.edges.skip(1)),
        _copyBody(body, faces: body.faces.skip(1)),
        _copyBody(body, vertices: [
          ...body.vertices,
          const CadVertex(
              id: 'extra', semanticId: 'extra', point: CadPoint3(0, 0, 1))
        ]),
      ];
      for (final candidate in altered) {
        expect(_codes(_kernel.validate(candidate)),
            contains('inconsistent_construction_topology'));
      }
    });

    test('a moved or reversed plane cannot keep its old boundary', () {
      final body = _plate();
      for (final surface in const [
        CadPlaneSurface(
            origin: CadPoint3(0, 0, 999), normal: CadPoint3(0, 0, 1)),
        CadPlaneSurface(
            origin: CadPoint3(0, 0, 2), normal: CadPoint3(0, 0, -1)),
      ]) {
        final changed = _copyBody(body, faces: [
          for (final face in body.faces)
            if (face.id == 'top') _copyFace(face, surface: surface) else face,
        ]);
        expect(_codes(_kernel.validate(changed)),
            contains('inconsistent_face_geometry'));
      }
    });

    test('moving a vertex and its incident curves cannot borrow old metrics',
        () {
      final body = _plate();
      const changedId = 'corner.sw.bottom';
      const moved = CadPoint3(-9, -5, 0);
      final changed = _copyBody(body, vertices: [
        for (final vertex in body.vertices)
          if (vertex.id == changedId)
            CadVertex(
                id: vertex.id, semanticId: vertex.semanticId, point: moved)
          else
            vertex,
      ], edges: [
        for (final edge in body.edges)
          CadEdge(
              id: edge.id,
              semanticId: edge.semanticId,
              startVertex: edge.startVertex,
              endVertex: edge.endVertex,
              curve: CadLineCurve(
                  edge.startVertex == changedId
                      ? moved
                      : (edge.curve as CadLineCurve).start,
                  edge.endVertex == changedId
                      ? moved
                      : (edge.curve as CadLineCurve).end)),
      ]);
      expect(
          changed.vertices
              .every((vertex) => body.bounds.contains(vertex.point)),
          isTrue);
      expect(
          _codes(_kernel.validate(changed)),
          containsAll([
            'inconsistent_vertex_geometry',
            'inconsistent_edge_geometry',
          ]));
    });

    test('cylinder radius, axis, position and material side are checked', () {
      final body = _plate(hole: true);
      for (final surface in const [
        CadCylinderSurface(origin: CadPoint3(0, 0, 0), radius: 2, inward: true),
        CadCylinderSurface(origin: CadPoint3(1, 0, 0), radius: 1, inward: true),
        CadCylinderSurface(origin: CadPoint3(0, 0, 0), radius: 1),
        CadCylinderSurface(
            origin: CadPoint3(0, 0, 0),
            radius: 1,
            axis: CadPoint3(1, 0, 0),
            inward: true),
      ]) {
        final changed = _copyBody(body, faces: [
          for (final face in body.faces)
            if (face.id == 'hole.mount.wall')
              _copyFace(face, surface: surface)
            else
              face,
        ]);
        expect(_codes(_kernel.validate(changed)),
            contains('inconsistent_face_geometry'));
      }
    });

    test('circle geometry and expected construction record must agree', () {
      final body = _plate(hole: true, centerX: -3);
      final changed = _copyBody(body, edges: [
        for (final edge in body.edges)
          if (edge.id == 'hole.mount.top')
            CadEdge(
                id: edge.id,
                semanticId: edge.semanticId,
                curve: const CadCircleCurve(
                    center: CadPoint3(-3, 0, 2), radius: 2))
          else
            edge,
      ]);
      expect(_codes(_kernel.validate(changed)),
          contains('inconsistent_edge_geometry'));
      final differentLocation = _plate(hole: true, centerX: 3);
      // Equal bounds and equal volume cannot establish equal solid geometry.
      expect(body.volume, differentLocation.volume);
      final mismatched =
          _copyBody(body, backendData: differentLocation.backendData);
      expect(
          _codes(_kernel.validate(mismatched)),
          containsAll(
              ['inconsistent_edge_geometry', 'inconsistent_face_geometry']));
    });

    test('reversing the complete shell cannot retain positive body metrics',
        () {
      final body = _plate(hole: true);
      final changed = _copyBody(body, faces: [
        for (final face in body.faces)
          _copyFace(face, loops: [
            for (final loop in face.loops)
              CadBoundaryLoop([
                for (final edge in loop.edges.reversed)
                  CadOrientedEdge(edge.edgeId, reversed: !edge.reversed)
              ])
          ]),
      ]);
      expect(_codes(_kernel.validate(changed)),
          contains('inconsistent_face_boundary'));
    });

    test(
        'geometry-equivalent origins, cycles and semantic changes remain valid',
        () {
      final body = _plate(hole: true);
      final changed = _copyBody(body,
          vertices: body.vertices.reversed,
          edges: body.edges.reversed,
          faces: [
            for (final face in body.faces.reversed)
              _copyFace(face,
                  semanticId: face.id == 'side.north' ? 'top' : face.semanticId,
                  surface: face.id == 'top'
                      ? const CadPlaneSurface(
                          origin: CadPoint3(100, -200, 2),
                          normal: CadPoint3(0, 0, 1))
                      : face.id == 'hole.mount.wall'
                          ? const CadCylinderSurface(
                              origin: CadPoint3(0, 0, 50),
                              radius: 1,
                              inward: true)
                          : face.surface,
                  loops: [
                    for (final loop in face.loops.reversed)
                      CadBoundaryLoop([...loop.edges.skip(1), loop.edges.first])
                  ]),
          ]);
      expect(_kernel.validate(changed), isEmpty);
      expect(changed.resolve(CadTopologyKind.face, 'top').status,
          CadTopologyResolutionStatus.ambiguous);
      expect(_kernel.tessellate(changed).isSuccess, isTrue);
    });

    test('a rejected body preserves committed parameters, body, and mesh', () {
      final body = _plate();
      final empty = _copyBody(body, vertices: [], edges: [], faces: []);
      final document = CadFeatureDocument(
          kernel: _kernel,
          parameters: CadParameters({'bad': 0}),
          features: [
            CadFeatureNode(
                id: 'plate',
                parameterDependencies: ['bad'],
                evaluate: (context) => CadKernelResult.success(
                    context.parameters['bad'] == 0 ? body : empty)),
            CadFeatureNode.tessellate(
                id: 'mesh',
                body: 'plate',
                chordError: CadExpression.constant(0.01)),
          ]);
      expect(document.regenerate().status, CadRegenerationStatus.committed);
      final committed = document.state;
      final failed = document.regenerate(changes: {'bad': 1});
      expect(failed.status, CadRegenerationStatus.rejected);
      expect(failed.failedFeature, 'plate');
      expect(failed.rebuiltFeatures, ['plate']);
      expect(identical(document.state, committed), isTrue);
      expect(document.state.parameters['bad'], 0);
      expect(
          identical(document.state.outputs['mesh'], committed.outputs['mesh']),
          isTrue);
    });
  });

  group('closed triangular manifold validation', () {
    test('a tetrahedron has positive independently known volume at many scales',
        () {
      for (final scale in [1e-100, 1.0, 1e100]) {
        final mesh = _tetrahedron(scale: scale);
        expect(mesh.validate(), isEmpty, reason: 'scale=$scale');
        final expected = scale * scale * scale / 6;
        expect((mesh.signedVolume / expected - 1).abs(), lessThan(1e-14));
      }
    });

    test('two closed shells pinched at one vertex are nonmanifold', () {
      final mesh = CadMesh(vertices: const [
        CadPoint3(0, 0, 0),
        CadPoint3(1, 0, 0),
        CadPoint3(0, 1, 0),
        CadPoint3(0, 0, 1),
        CadPoint3(-1, 0, 0),
        CadPoint3(0, -1, 0),
        CadPoint3(0, 0, -1),
      ], triangles: [
        for (final t in const [
          [0, 2, 1],
          [0, 1, 3],
          [0, 3, 2],
          [1, 2, 3],
          [0, 4, 5],
          [0, 6, 4],
          [0, 5, 6],
          [4, 6, 5]
        ])
          CadTriangle(t[0], t[1], t[2], faceId: 'tetra'),
      ], chordError: 0.01);
      final edgeCount = <(int, int), int>{};
      for (final face in mesh.triangles) {
        final indices = [face.a, face.b, face.c];
        for (var i = 0; i < 3; i++) {
          final a = indices[i], b = indices[(i + 1) % 3];
          final edge = a < b ? (a, b) : (b, a);
          edgeCount[edge] = (edgeCount[edge] ?? 0) + 1;
        }
      }
      expect(edgeCount.values.every((count) => count == 2), isTrue);
      expect(mesh.signedVolume, closeTo(1 / 3, 1e-15));
      final issues = mesh.validate();
      expect(_codes(issues), contains('non_manifold_vertex'));
      expect(
          issues
              .where((issue) => issue.code == 'non_manifold_vertex')
              .single
              .entity,
          '0');
      final document = CadFeatureDocument(
          kernel: _kernel,
          parameters: CadParameters({'pinch': 0}),
          features: [
            CadFeatureNode(
                id: 'mesh',
                parameterDependencies: ['pinch'],
                evaluate: (context) => CadKernelResult.success(
                    context.parameters['pinch'] == 0 ? _tetrahedron() : mesh)),
          ]);
      expect(document.regenerate().isSuccess, isTrue);
      final committed = document.state;
      expect(document.regenerate(changes: {'pinch': 1}).status,
          CadRegenerationStatus.rejected);
      expect(identical(document.state, committed), isTrue);
    });

    test('opposite copies of one simplex cannot masquerade as a closed sheet',
        () {
      final tetra = _tetrahedron();
      final mesh = CadMesh(vertices: [
        ...tetra.vertices,
        const CadPoint3(2, 0, 0),
        const CadPoint3(3, 0, 0),
        const CadPoint3(2, 1, 0)
      ], triangles: [
        ...tetra.triangles,
        const CadTriangle(4, 5, 6, faceId: 'sheet'),
        const CadTriangle(4, 6, 5, faceId: 'sheet')
      ], chordError: 0.01);
      expect(mesh.signedVolume, closeTo(1 / 6, 1e-15));
      expect(_codes(mesh.validate()), contains('duplicate_triangle'));
    });

    test('repeated, missing, collinear and isolated vertices are rejected', () {
      final tetra = _tetrahedron();
      final repeated = CadMesh(
          vertices: tetra.vertices,
          triangles: [
            ...tetra.triangles,
            const CadTriangle(0, 0, 1, faceId: 'repeated')
          ],
          chordError: 0.01);
      expect(_codes(repeated.validate()), contains('degenerate_triangle'));
      final missing = CadMesh(
          vertices: tetra.vertices,
          triangles: [
            ...tetra.triangles,
            const CadTriangle(0, 1, 10, faceId: 'missing')
          ],
          chordError: 0.01);
      expect(_codes(missing.validate()), contains('invalid_index'));
      final collinear = CadMesh(vertices: [
        ...tetra.vertices,
        const CadPoint3(2, 0, 0)
      ], triangles: [
        ...tetra.triangles,
        const CadTriangle(0, 1, 4, faceId: 'collinear')
      ], chordError: 0.01);
      expect(_codes(collinear.validate()), contains('degenerate_triangle'));
      final isolated = CadMesh(
          vertices: [...tetra.vertices, const CadPoint3(2, 2, 2)],
          triangles: tetra.triangles,
          chordError: 0.01);
      expect(_codes(isolated.validate()), contains('unused_vertex'));
    });

    test('unrepresentable volume and invalid precision metadata are rejected',
        () {
      expect(_codes(_tetrahedron(scale: 1e-150).validate()),
          contains('non_positive_volume'));
      final tetra = _tetrahedron();
      for (final error in [0.0, -1.0, double.nan, double.infinity]) {
        final mesh = CadMesh(
            vertices: tetra.vertices,
            triangles: tetra.triangles,
            chordError: error);
        expect(_codes(mesh.validate()), contains('invalid_chord_error'));
      }
    });
  });
}

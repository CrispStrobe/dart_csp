import 'dart:math' as math;

import 'package:dart_csp/src/cad/features.dart';
import 'package:dart_csp/src/cad/kernel.dart';
import 'package:dart_csp/src/cad/reference_kernel.dart';
import 'package:test/test.dart';

CadRectangularProfile _profile() =>
    CadRectangularProfile(width: 100, height: 40, holes: const [
      CadCircularHole(id: 'left', centerX: -30, centerY: 0, radius: 4),
      CadCircularHole(id: 'right', centerX: 30, centerY: 0, radius: 4),
    ]);

CadFeatureDocument _document({CadKernel kernel = const ReferenceCadKernel()}) {
  final width = CadExpression.parameter('width');
  final height = CadExpression.parameter('height');
  final spacing = CadExpression.parameter('holeSpacing');
  final radius = CadExpression.parameter('holeDiameter') / 2;
  return CadFeatureDocument(
      kernel: kernel,
      parameters: CadParameters({
        'width': 100,
        'height': 40,
        'thickness': 6,
        'holeSpacing': 60,
        'holeDiameter': 8,
        'chordError': 0.02,
        'unrelated': 1
      }),
      features: [
        CadFeatureNode.rectangularProfile(
            id: 'profile',
            width: width,
            height: height,
            holes: [
              CadHoleExpression(
                  id: 'left',
                  centerX: -spacing / 2,
                  centerY: CadExpression.constant(0),
                  radius: radius),
              CadHoleExpression(
                  id: 'right',
                  centerX: spacing / 2,
                  centerY: CadExpression.constant(0),
                  radius: radius)
            ]),
        CadFeatureNode.extrude(
            id: 'plate',
            profile: 'profile',
            depth: CadExpression.parameter('thickness')),
        CadFeatureNode.tessellate(
            id: 'mesh',
            body: 'plate',
            chordError: CadExpression.parameter('chordError')),
        CadFeatureNode(
            id: 'other',
            parameterDependencies: ['unrelated'],
            evaluate: (context) =>
                CadKernelResult.success(context.parameters['unrelated'])),
      ],
      requiredReferences: const [
        TopologyRef(
            featureId: 'plate', semanticId: 'top', kind: CadTopologyKind.face),
        TopologyRef(
            featureId: 'plate',
            semanticId: 'hole.left.wall',
            kind: CadTopologyKind.face),
      ]);
}

void _independentlyCheckClosedMesh(CadMesh mesh) {
  final incidence = <(int, int), List<(int, int)>>{};
  for (final triangle in mesh.triangles) {
    final v = [triangle.a, triangle.b, triangle.c];
    expect(v.toSet().length, 3);
    for (var i = 0; i < 3; i++) {
      final a = v[i], b = v[(i + 1) % 3];
      (incidence[a < b ? (a, b) : (b, a)] ??= []).add((a, b));
    }
  }
  for (final use in incidence.values) {
    expect(use.length, 2,
        reason: 'A watertight manifold has two triangles per edge.');
    expect(use.first.$1, use.last.$2);
    expect(use.first.$2, use.last.$1);
  }
}

void main() {
  const kernel = ReferenceCadKernel();
  group('analytic reference extrusion', () {
    test(
        'plate volume, bounds, cylinders and semantic topology match the design',
        () {
      final result =
          kernel.extrude(featureId: 'plate', profile: _profile(), depth: 6);
      expect(result.status, CadKernelStatus.success,
          reason: '${result.issues}');
      final body = result.value!;
      expect(body.volume, closeTo((100 * 40 - 2 * math.pi * 16) * 6, 1e-9));
      expect(body.bounds.min.x, -50);
      expect(body.bounds.max.y, 20);
      expect(body.bounds.max.z, 6);
      expect(body.faces.length, 8);
      expect(body.edges.length, 16);
      expect(body.vertices.length, 8);
      final hole = body.resolve(CadTopologyKind.face, 'hole.left.wall').entity!
          as CadFace;
      final cylinder = hole.surface as CadCylinderSurface;
      expect(cylinder.radius, 4);
      expect(cylinder.origin.x, -30);
      expect(cylinder.inward, isTrue);
      expect(kernel.validate(body), isEmpty);
    });

    test(
        'tessellation is closed, consistently wound and within volume tolerance',
        () {
      final body = kernel
          .extrude(featureId: 'plate', profile: _profile(), depth: 6)
          .value!;
      final result = kernel.tessellate(body, chordError: 0.02);
      expect(result.status, CadKernelStatus.success,
          reason: '${result.issues}');
      final mesh = result.value!;
      _independentlyCheckClosedMesh(mesh);
      expect(mesh.vertices.every(body.bounds.contains), isTrue);
      expect(mesh.signedVolume,
          greaterThan(body.volume)); // inscribed polygonal holes
      const conservativeError = 6 * 2 * 2 * math.pi * 4 * 0.02;
      expect(mesh.signedVolume - body.volume, lessThan(conservativeError));
      for (final triangle in mesh.triangles) {
        final a = mesh.vertices[triangle.a],
            b = mesh.vertices[triangle.b],
            c = mesh.vertices[triangle.c];
        final normal = (b - a).cross(c - a);
        if (triangle.faceId == 'top') expect(normal.z, greaterThan(0));
        if (triangle.faceId == 'bottom') expect(normal.z, lessThan(0));
        if (triangle.faceId.startsWith('hole.')) {
          final centerX = triangle.faceId.contains('left') ? -30 : 30;
          final centroid = (a + b + c).scaled(1 / 3);
          expect(normal.dot(CadPoint3(centroid.x - centerX, centroid.y, 0)),
              lessThan(0));
        }
      }
    });

    test('rectangle without holes has exact tessellated volume', () {
      final body = kernel
          .extrude(
              featureId: 'block',
              profile: CadRectangularProfile(width: 12, height: 7),
              depth: 3)
          .value!;
      final result = kernel.tessellate(body);
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      _independentlyCheckClosedMesh(result.value!);
      expect(result.value!.signedVolume, closeTo(252, 1e-10));
    });

    test('off-center holes retain watertight cap seams', () {
      final body = kernel
          .extrude(
              featureId: 'plate',
              depth: 4,
              profile:
                  CadRectangularProfile(width: 80, height: 30, holes: const [
                CadCircularHole(id: 'a', centerX: -25, centerY: -6, radius: 3),
                CadCircularHole(id: 'b', centerX: 0, centerY: 5, radius: 4),
                CadCircularHole(id: 'c', centerX: 25, centerY: -2, radius: 2),
              ]))
          .value!;
      final result = kernel.tessellate(body);
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      _independentlyCheckClosedMesh(result.value!);
    });

    test('invalid dimensions and touching/overlapping holes are rejected', () {
      for (final profile in [
        CadRectangularProfile(width: -10, height: 20),
        CadRectangularProfile(width: 20, height: 20, holes: const [
          CadCircularHole(id: 'outside', centerX: 8, centerY: 0, radius: 2)
        ]),
        CadRectangularProfile(width: 20, height: 20, holes: const [
          CadCircularHole(id: 'a', centerX: -1, centerY: 0, radius: 2),
          CadCircularHole(id: 'b', centerX: 1, centerY: 0, radius: 2)
        ]),
      ]) {
        expect(
            kernel.extrude(featureId: 'bad', profile: profile, depth: 2).status,
            CadKernelStatus.invalidInput);
      }
    });

    test('mesh subset limitation and unavailable solid operations are explicit',
        () {
      final body = kernel
          .extrude(
              featureId: 'plate',
              depth: 3,
              profile:
                  CadRectangularProfile(width: 30, height: 30, holes: const [
                CadCircularHole(id: 'a', centerX: 0, centerY: -6, radius: 2),
                CadCircularHole(id: 'b', centerX: 0, centerY: 6, radius: 2)
              ]))
          .value!;
      expect(kernel.validate(body), isEmpty);
      expect(kernel.tessellate(body).status, CadKernelStatus.unsupported);
      expect(kernel.capabilities.contains(CadCapability.fillet), isFalse);
      expect(
          kernel
              .fillet(
                  featureId: 'round',
                  body: body,
                  edges: ['outer.south.top'],
                  radius: 1)
              .status,
          CadKernelStatus.unsupported);
      expect(
          kernel
              .combine(
                  featureId: 'union',
                  operation: CadBooleanOperation.union,
                  left: body,
                  right: body)
              .status,
          CadKernelStatus.unsupported);
    });
  });

  group('transactional parametric feature graph', () {
    test('thickness edits rebuild only the extrusion and its mesh', () {
      final doc = _document();
      expect(doc.regenerate().isSuccess, isTrue);
      final previous = doc.state;
      final result = doc.regenerate(changes: {'thickness': 8});
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      expect(result.rebuiltFeatures, ['plate', 'mesh']);
      expect(
          identical(previous.outputs['profile'], doc.state.outputs['profile']),
          isTrue);
      expect(doc.state.featureRevisions['other'],
          previous.featureRevisions['other']);
      expect(doc.state.parameters.revisions['thickness'], 1);
      expect(doc.state.parameters.revisions['width'], 0);
      expect(doc.state.output<CadBody>('plate').volume,
          closeTo(previous.output<CadBody>('plate').volume * 8 / 6, 1e-9));
      expect(doc.regenerate().status, CadRegenerationStatus.unchanged);
    });

    test(
        'width and hole-spacing edits propagate downstream and retain semantic refs',
        () {
      final doc = _document();
      expect(doc.regenerate().isSuccess, isTrue);
      final result = doc.regenerate(changes: {'width': 120, 'holeSpacing': 80});
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      expect(result.rebuiltFeatures, ['profile', 'plate', 'mesh']);
      final resolution = doc.state.resolve(const TopologyRef(
          featureId: 'plate',
          semanticId: 'hole.left.wall',
          kind: CadTopologyKind.face));
      expect(resolution.status, CadTopologyResolutionStatus.found);
      expect(
          ((resolution.entity! as CadFace).surface as CadCylinderSurface)
              .origin
              .x,
          -40);
    });

    test(
        'failed dimension edits roll back parameters, topology, mesh and revisions',
        () {
      final doc = _document();
      expect(doc.regenerate().isSuccess, isTrue);
      final previous = doc.state;
      final result = doc.regenerate(changes: {'holeDiameter': 42});
      expect(result.status, CadRegenerationStatus.rejected);
      expect(result.failedFeature, 'plate');
      expect(result.issues.any((issue) => issue.code == 'hole_outside_profile'),
          isTrue);
      expect(identical(doc.state, previous), isTrue);
      expect(doc.state.parameters['holeDiameter'], 8);
      expect(doc.state.featureRevisions['profile'], 1);
      expect(doc.regenerate(changes: {'holeDiameter': 10}).isSuccess, isTrue);
    });

    test('ambiguous topology provenance fails rather than selecting a face',
        () {
      final doc = _document(kernel: const _AmbiguousTopKernel());
      expect(doc.regenerate().isSuccess, isTrue);
      final previous = doc.state;
      final result = doc.regenerate(changes: {'thickness': 8});
      expect(result.status, CadRegenerationStatus.rejected);
      expect(result.issues.single.code, 'topology_ambiguous');
      expect(identical(doc.state, previous), isTrue);
    });

    test('missing semantic topology after a valid geometry edit rolls back',
        () {
      final doc = CadFeatureDocument(
          kernel: kernel,
          parameters: CadParameters({'hole': 1}),
          features: [
            CadFeatureNode(
                id: 'profile',
                parameterDependencies: ['hole'],
                evaluate: (context) => CadKernelResult.success(
                    CadRectangularProfile(
                        width: 30,
                        height: 20,
                        holes: context.parameters['hole'] > 0
                            ? const [
                                CadCircularHole(
                                    id: 'mount',
                                    centerX: 0,
                                    centerY: 0,
                                    radius: 2)
                              ]
                            : const []))),
            CadFeatureNode.extrude(
                id: 'plate',
                profile: 'profile',
                depth: CadExpression.constant(3))
          ],
          requiredReferences: const [
            TopologyRef(
                featureId: 'plate',
                semanticId: 'hole.mount.wall',
                kind: CadTopologyKind.face)
          ]);
      expect(doc.regenerate().isSuccess, isTrue);
      final previous = doc.state;
      final result = doc.regenerate(changes: {'hole': 0});
      expect(result.status, CadRegenerationStatus.rejected);
      expect(result.issues.single.code, 'topology_missing');
      expect(identical(doc.state, previous), isTrue);
    });

    test('dependencies and snapshots prevent accidental stale-state mutation',
        () {
      final doc = _document();
      expect(doc.regenerate().isSuccess, isTrue);
      expect(() => doc.state.parameters.values['width'] = 1,
          throwsUnsupportedError);
      expect(() => doc.state.outputs.clear(), throwsUnsupportedError);
      expect(doc.regenerate(changes: {'unknown': 1}).status,
          CadRegenerationStatus.rejected);
      final bad = CadFeatureDocument(
          kernel: kernel,
          parameters: CadParameters({'x': 1}),
          features: [
            CadFeatureNode(
                id: 'bad',
                evaluate: (context) =>
                    CadKernelResult.success(context.parameters['x']))
          ]);
      expect(bad.regenerate().status, CadRegenerationStatus.rejected);
    });

    test('feature cycles and missing inputs are rejected before evaluation',
        () {
      CadFeatureNode node(String id, List<String> dependencies) =>
          CadFeatureNode(
              id: id,
              dependencies: dependencies,
              evaluate: (_) => CadKernelResult.success(0));
      expect(
          () => CadFeatureDocument(
                  kernel: kernel,
                  parameters: CadParameters({}),
                  features: [
                    node('a', ['b']),
                    node('b', ['a'])
                  ]),
          throwsArgumentError);
      expect(
          () => CadFeatureDocument(
                  kernel: kernel,
                  parameters: CadParameters({}),
                  features: [
                    node('a', ['missing'])
                  ]),
          throwsArgumentError);
    });
  });
}

// Models an external kernel whose topology history maps two valid faces to
// the same old semantic reference after an edit. The geometry is unchanged.
class _AmbiguousTopKernel extends ReferenceCadKernel {
  const _AmbiguousTopKernel();
  @override
  CadKernelResult<CadBody> extrude(
      {required String featureId,
      required CadPlanarProfile profile,
      required double depth}) {
    final result =
        super.extrude(featureId: featureId, profile: profile, depth: depth);
    if (!result.isSuccess || depth <= 6) return result;
    final body = result.value!;
    return CadKernelResult.success(CadBody(
        featureId: body.featureId,
        bounds: body.bounds,
        volume: body.volume,
        vertices: body.vertices,
        edges: body.edges,
        backendData: body.backendData,
        faces: body.faces.map((face) => face.id != 'side.north'
            ? face
            : CadFace(
                id: face.id,
                semanticId: 'top',
                surface: face.surface,
                loops: face.loops))));
  }
}

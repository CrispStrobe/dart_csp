import 'dart:math' as math;

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

import '../example/parametric_assembly.dart';

const _kernel = ReferenceCadKernel();

CadBody _plate() => _kernel
    .extrude(
        featureId: 'plate',
        profile: CadRectangularProfile(width: 12, height: 8, holes: const [
          CadCircularHole(id: 'mount', centerX: 1, centerY: -1, radius: 1),
        ]),
        depth: 3)
    .value!;

void _expectPoint(CadPoint3 actual, CadPoint3 expected,
    {double tolerance = 1e-12}) {
  expect(actual.x, closeTo(expected.x, tolerance));
  expect(actual.y, closeTo(expected.y, tolerance));
  expect(actual.z, closeTo(expected.z, tolerance));
}

class _MutablePoint extends CadPoint3 {
  _MutablePoint() : super(1, 2, 3);
  double currentX = 1;
  @override
  double get x => currentX;
}

class _CountingKernel extends ReferenceCadKernel {
  var extrusions = 0, meshes = 0, validations = 0;
  var reject = false;
  @override
  CadKernelResult<CadBody> extrude(
      {required String featureId,
      required CadPlanarProfile profile,
      required double depth}) {
    extrusions++;
    return super.extrude(featureId: featureId, profile: profile, depth: depth);
  }

  @override
  CadKernelResult<CadMesh> tessellate(CadBody body,
      {double chordError = 0.05}) {
    meshes++;
    return super.tessellate(body, chordError: chordError);
  }

  @override
  List<CadIssue> validate(CadBody body) {
    validations++;
    return [
      ...super.validate(body),
      if (reject) const CadIssue('policy_rejection', 'Application policy.'),
    ];
  }
}

CadFeatureDocument _placedDocument({
  CadKernel kernel = _kernel,
  bool quaternion = false,
}) =>
    CadFeatureDocument(
        kernel: kernel,
        parameters: CadParameters({
          'width': 12,
          'height': 8,
          'depth': 3,
          'x': 0,
          'y': 0,
          'z': 0,
          'angle': 0,
          'qw': 1,
          'qx': 0,
          'qy': 0,
          'qz': 0,
        }),
        features: [
          CadFeatureNode.rectangularProfile(
              id: 'profile',
              width: CadExpression.parameter('width'),
              height: CadExpression.parameter('height')),
          CadFeatureNode.extrude(
              id: 'plate',
              profile: 'profile',
              depth: CadExpression.parameter('depth')),
          CadFeatureNode.tessellate(
              id: 'mesh',
              body: 'plate',
              chordError: CadExpression.constant(0.01)),
          CadFeatureNode.instance(
              id: 'placed',
              body: 'plate',
              placement: quaternion
                  ? CadPlacementExpression.quaternion(
                      x: CadExpression.parameter('x'),
                      y: CadExpression.parameter('y'),
                      z: CadExpression.parameter('z'),
                      quaternion: [
                          for (final name in ['qw', 'qx', 'qy', 'qz'])
                            CadExpression.parameter(name)
                        ])
                  : CadPlacementExpression(
                      x: CadExpression.parameter('x'),
                      y: CadExpression.parameter('y'),
                      z: CadExpression.parameter('z'),
                      angle: CadExpression.parameter('angle'),
                      axis: const CadPoint3(1, 0, 0))),
        ],
        requiredReferences: const [
          TopologyRef(
              featureId: 'placed',
              semanticId: 'top',
              kind: CadTopologyKind.face),
        ]);

void main() {
  group('rigid transforms', () {
    test('quaternion normalization handles extreme finite scales', () {
      for (final scale in [1.0, 1e300, 1e-300, -1e300, -1e-300]) {
        final transform = CadRigidTransform(quaternion: [scale, 0, 0, scale]);
        _expectPoint(transform.transformDirection(const CadPoint3(1, 0, 0)),
            const CadPoint3(0, 1, 0));
        _expectPoint(transform.transformDirection(const CadPoint3(0, 0, 1)),
            const CadPoint3(0, 0, 1));
      }
      final axisAngle = CadRigidTransform.axisAngle(
          axis: const CadPoint3(0, 0, 1e308), angle: math.pi / 2);
      _expectPoint(axisAngle.transformPoint(const CadPoint3(2, 0, 0)),
          const CadPoint3(0, 2, 0));
    });

    test('captured translation/quaternion inputs cannot mutate placement', () {
      final translation = _MutablePoint();
      final quaternion = [1.0, 0.0, 0.0, 0.0];
      final transform =
          CadRigidTransform(translation: translation, quaternion: quaternion);
      translation.currentX = 100;
      quaternion[0] = 0;
      _expectPoint(transform.transformPoint(const CadPoint3(0, 0, 0)),
          const CadPoint3(1, 2, 3));
      expect(() => transform.quaternion[0] = 0, throwsUnsupportedError);
      expect(() => transform.toColumnMajorMatrix4().clear(),
          throwsUnsupportedError);
    });

    test('composition, inversion and renderer matrix agree with hand rotation',
        () {
      final world = CadRigidTransform.axisAngle(
          axis: const CadPoint3(0, 0, 1),
          angle: math.pi / 2,
          translation: const CadPoint3(10, 20, 30));
      final local = CadRigidTransform.axisAngle(
          axis: const CadPoint3(1, 0, 0),
          angle: math.pi / 2,
          translation: const CadPoint3(1, 2, 3));
      final composed = world.compose(local);
      const point = CadPoint3(2, 3, 4);
      const expected = CadPoint3(12, 23, 36);
      _expectPoint(composed.transformPoint(point), expected);
      _expectPoint(composed.inverse().transformPoint(expected), point);
      final m = composed.toColumnMajorMatrix4();
      _expectPoint(
          CadPoint3(
              m[0] * point.x + m[4] * point.y + m[8] * point.z + m[12],
              m[1] * point.x + m[5] * point.y + m[9] * point.z + m[13],
              m[2] * point.x + m[6] * point.y + m[10] * point.z + m[14]),
          expected);
    });

    test(
        'conservative bounds contain corners and interior points after rotation',
        () {
      const local = CadBounds(CadPoint3(-6, -4, 0), CadPoint3(6, 4, 3));
      final random = math.Random(741);
      for (final offset in [0.0, 1e12]) {
        final transform = CadRigidTransform.axisAngle(
            axis: const CadPoint3(1, 2, -3),
            angle: 1.17,
            translation: CadPoint3(offset, -offset, offset));
        final bounds = transform.transformBounds(local);
        final points = [
          for (final x in [-6.0, 6.0])
            for (final y in [-4.0, 4.0])
              for (final z in [0.0, 3.0]) CadPoint3(x, y, z),
          for (var i = 0; i < 200; i++)
            CadPoint3(12 * random.nextDouble() - 6, 8 * random.nextDouble() - 4,
                3 * random.nextDouble()),
        ];
        for (final point in points) {
          expect(bounds.contains(transform.transformPoint(point)), isTrue);
        }
      }
    });

    test('invalid transforms and unrepresentable bounds fail explicitly', () {
      for (final quaternion in <List<double>>[
        [0, 0, 0, 0],
        [1, 0, 0],
        [1, 0, 0, double.nan],
        [double.infinity, 0, 0, 0],
      ]) {
        expect(() => CadRigidTransform(quaternion: quaternion),
            throwsArgumentError);
      }
      expect(
          () => CadRigidTransform(
              translation: const CadPoint3(0, double.infinity, 0)),
          throwsArgumentError);
      expect(
          () => CadRigidTransform.axisAngle(
              axis: const CadPoint3(0, 0, 0), angle: 1),
          throwsArgumentError);
      expect(
          () => CadRigidTransform.axisAngle(
              axis: const CadPoint3(0, 0, 1), angle: double.nan),
          throwsArgumentError);
      expect(
          () => CadRigidTransform().transformBounds(
              const CadBounds(CadPoint3(1, 0, 0), CadPoint3(-1, 1, 1))),
          throwsArgumentError);
      expect(
          () => CadRigidTransform(translation: const CadPoint3(1e308, 0, 0))
              .transformBounds(const CadBounds(
                  CadPoint3(1e308, 0, 0), CadPoint3(1.5e308, 1, 1))),
          throwsStateError);
    });

    test(
        'world mesh export preserves winding and rejects rounded-away geometry',
        () {
      final body = _kernel
          .extrude(
              featureId: 'box',
              profile: CadRectangularProfile(width: 12, height: 8),
              depth: 4)
          .value!;
      final mesh = _kernel.tessellate(body).value!;
      final transform = CadRigidTransform.axisAngle(
          axis: const CadPoint3(1, 0, 0),
          angle: math.pi / 2,
          translation: const CadPoint3(1e12, -1e12, 1e12));
      final result = transform.transformMesh(mesh);
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      expect(result.value!.signedVolume, closeTo(12 * 8 * 4, 1e-7));
      expect(result.value!.triangles.map((t) => (t.a, t.b, t.c, t.faceId)),
          mesh.triangles.map((t) => (t.a, t.b, t.c, t.faceId)));
      final collapsed =
          CadRigidTransform(translation: const CadPoint3(1e20, 1e20, 1e20))
              .transformMesh(mesh);
      expect(collapsed.status, CadKernelStatus.invalidTopology);
      expect(collapsed.value, isNull);
      final open = CadMesh(
          vertices: mesh.vertices,
          triangles: mesh.triangles.skip(1),
          chordError: mesh.chordError);
      expect(transform.transformMesh(open).status,
          CadKernelStatus.invalidTopology);
    });
  });

  group('analytic rigid instances', () {
    test('world faces, edges, vertices and bounds preserve design semantics',
        () {
      final body = _plate();
      final instance = CadBodyInstance(
          featureId: 'upright',
          body: body,
          placement: CadRigidTransform.axisAngle(
              axis: const CadPoint3(1, 0, 0),
              angle: math.pi / 2,
              translation: const CadPoint3(10, 20, 30)));
      expect(instance.validate(_kernel), isEmpty);
      expect(identical(instance.body, body), isTrue);
      expect(instance.volume, body.volume);
      final top =
          instance.resolve(CadTopologyKind.face, 'top').entity! as CadFace;
      final plane = top.surface as CadPlaneSurface;
      _expectPoint(plane.normal, const CadPoint3(0, -1, 0));
      _expectPoint(plane.origin, const CadPoint3(10, 17, 30));
      final hole = (instance
              .resolve(CadTopologyKind.face, 'hole.mount.wall')
              .entity! as CadFace)
          .surface as CadCylinderSurface;
      _expectPoint(hole.origin, const CadPoint3(11, 20, 29));
      _expectPoint(hole.axis, const CadPoint3(0, -1, 0));
      expect(hole.radius, 1);
      expect(hole.inward, isTrue);
      final circle = (instance
              .resolve(CadTopologyKind.edge, 'hole.mount.top')
              .entity! as CadEdge)
          .curve as CadCircleCurve;
      _expectPoint(circle.center, const CadPoint3(11, 17, 29));
      _expectPoint(circle.normal, const CadPoint3(0, -1, 0));
      final corner = instance
          .resolve(CadTopologyKind.vertex, 'corner.sw.bottom')
          .entity! as CadVertex;
      _expectPoint(corner.point, const CadPoint3(4, 20, 26));
      expect(instance.bounds.contains(corner.point), isTrue);
      expect(instance.resolve(CadTopologyKind.face, 'absent').status,
          CadTopologyResolutionStatus.missing);
      expect(
          top.loops.first.edges.map((e) => (e.edgeId, e.reversed)),
          (body.resolve(CadTopologyKind.face, 'top').entity! as CadFace)
              .loops
              .first
              .edges
              .map((e) => (e.edgeId, e.reversed)));
    });

    test('ambiguous semantic meanings remain ambiguous when placed', () {
      final original = _plate();
      final ambiguous = CadBody(
          featureId: original.featureId,
          bounds: original.bounds,
          volume: original.volume,
          vertices: original.vertices,
          edges: original.edges,
          faces: [
            for (final face in original.faces)
              CadFace(
                  id: face.id,
                  semanticId: face.id == 'bottom' ? 'top' : face.semanticId,
                  surface: face.surface,
                  loops: face.loops)
          ],
          backendData: original.backendData);
      final instance = CadBodyInstance(
          featureId: 'duplicate',
          body: ambiguous,
          placement: CadRigidTransform());
      expect(instance.validate(_kernel), isEmpty);
      expect(instance.resolve(CadTopologyKind.face, 'top').status,
          CadTopologyResolutionStatus.ambiguous);
    });

    test(
        'custom kernel validation still runs for unchanged prototype instances',
        () {
      final kernel = _CountingKernel();
      final doc = _placedDocument(kernel: kernel);
      expect(doc.regenerate().isSuccess, isTrue);
      final previous = doc.state;
      final count = kernel.validations;
      kernel.reject = true;
      final result = doc.regenerate(changes: {'x': 10});
      expect(result.status, CadRegenerationStatus.rejected);
      expect(result.issues.single.code, 'policy_rejection');
      expect(kernel.validations, count + 1);
      expect(identical(doc.state, previous), isTrue);
    });
  });

  group('parametric 3D placement transactions', () {
    test('pose-only edits reuse analytic bodies and meshes without kernel work',
        () {
      final kernel = _CountingKernel();
      final doc = _placedDocument(kernel: kernel);
      expect(doc.regenerate().isSuccess, isTrue);
      final before = doc.state;
      final result = doc.regenerate(changes: {'x': 10, 'angle': math.pi / 2});
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      expect(result.rebuiltFeatures, ['placed']);
      expect(kernel.extrusions, 1);
      expect(kernel.meshes, 1);
      for (final id in ['profile', 'plate', 'mesh']) {
        expect(identical(doc.state.outputs[id], before.outputs[id]), isTrue);
        expect(doc.state.featureRevisions[id], before.featureRevisions[id]);
      }
      final top = doc.state
          .resolve(const TopologyRef(
              featureId: 'placed',
              semanticId: 'top',
              kind: CadTopologyKind.face))
          .entity! as CadFace;
      _expectPoint(
          (top.surface as CadPlaneSurface).normal, const CadPoint3(0, -1, 0));
      expect(doc.regenerate(changes: {'x': 10}).status,
          CadRegenerationStatus.unchanged);
    });

    test('shape edits replace prototypes and dependent instances together', () {
      final doc = _placedDocument();
      expect(doc.regenerate().isSuccess, isTrue);
      final before = doc.state;
      final result = doc.regenerate(changes: {'depth': 6});
      expect(result.isSuccess, isTrue);
      expect(result.rebuiltFeatures, ['plate', 'mesh', 'placed']);
      final instance = doc.state.output<CadBodyInstance>('placed');
      expect(
          identical(instance.body, doc.state.output<CadBody>('plate')), isTrue);
      expect(instance.volume, 2 * before.output<CadBody>('plate').volume);
    });

    test('invalid quaternion or shape edits preserve every committed object',
        () {
      final doc = _placedDocument(quaternion: true);
      expect(doc.regenerate().isSuccess, isTrue);
      final committed = doc.state;
      final zeroQuaternion = doc.regenerate(changes: {'qw': 0});
      expect(zeroQuaternion.status, CadRegenerationStatus.rejected);
      expect(zeroQuaternion.failedFeature, 'placed');
      expect(identical(doc.state, committed), isTrue);
      expect(doc.regenerate(changes: {'depth': -1}).status,
          CadRegenerationStatus.rejected);
      expect(identical(doc.state, committed), isTrue);
      final valid = doc.regenerate(changes: {'qw': 0, 'qz': 2});
      expect(valid.isSuccess, isTrue, reason: '${valid.issues}');
      _expectPoint(
          doc.state
              .output<CadBodyInstance>('placed')
              .placement
              .transformDirection(const CadPoint3(1, 0, 0)),
          const CadPoint3(-1, 0, 0));
    });

    test(
        'successful assembly solver poses drive placed solids and reuse meshes',
        () {
      final kernel = _CountingKernel();
      final doc = buildParametricPlateAssembly(kernel: kernel);
      expect(doc.regenerate().isSuccess, isTrue);
      final before = doc.state;
      final result = doc.regenerate(changes: {'gap': 12});
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      expect(result.rebuiltFeatures, ['assembly', 'upright']);
      expect(kernel.extrusions, 1);
      expect(kernel.meshes, 1);
      expect(identical(doc.state.outputs['plate'], before.outputs['plate']),
          isTrue);
      expect(
          identical(doc.state.outputs['mesh'], before.outputs['mesh']), isTrue);
      final upright = doc.state.output<CadBodyInstance>('upright');
      _expectPoint(upright.placement.translation, const CadPoint3(0, 27, 15),
          tolerance: 1e-7);
      _expectPoint(
          upright.placement.transformDirection(const CadPoint3(0, 0, 1)),
          const CadPoint3(0, 1, 0),
          tolerance: 1e-9);
      expect(
          doc.state.output<GeometrySolveResult>('assembly').maxToleranceRatio,
          lessThanOrEqualTo(1));
      final committed = doc.state;
      expect(doc.regenerate(changes: {'gap': -1}).status,
          CadRegenerationStatus.rejected);
      expect(identical(doc.state, committed), isTrue);
      expect(doc.regenerate(changes: {'gap': 6}).isSuccess, isTrue);
      _expectPoint(
          doc.state.output<CadBodyInstance>('upright').placement.translation,
          const CadPoint3(0, 21, 15),
          tolerance: 1e-7);
    });

    test('unchecked geometry and malformed bindings cannot place solids', () {
      final builder = GeometryBuilder();
      final pose = builder.pose('pose', fixed: true);
      final target = builder.point3('target', const Vec3(1, 0, 0), fixed: true);
      builder.attachPoint('impossible', target, pose, Vec3.zero);
      final result = builder.compile().createSession().solve();
      expect(result.isSuccess, isFalse);
      expect(() => CadRigidTransform.fromGeometryPose(result, pose),
          throwsArgumentError);
      final valid = GeometryBuilder();
      valid.pose('valid', fixed: true);
      final compiled = valid.compile();
      final solved = compiled.createSession().solve();
      expect(() => CadRigidTransform.fromGeometryPose(solved, pose),
          throwsArgumentError);
      expect(
          () => constrainedGeometryFeature(
              id: 'bad',
              model: compiled,
              dimensionBindings: {'missing': CadExpression.constant(1)}),
          throwsArgumentError);
    });

    test('failed downstream feature never seeds the next assembly candidate',
        () {
      final starts = <double>[];
      final builder = GeometryBuilder();
      final point = builder.point3('point', const Vec3(1, 0, 0));
      builder.dimension('x', 1);
      builder.addResidual(GeometryResidualBlock.autoDiff(
          id: 'position',
          parameterIds: [point.id, 'x'],
          residualCount: 3,
          evaluate: (p) {
            starts.add(p[0][0].value);
            return [p[0][0] - p[1][0], p[0][1], p[0][2]];
          }));
      final doc = CadFeatureDocument(
          kernel: _kernel,
          parameters: CadParameters({'x': 1}),
          features: [
            constrainedGeometryFeature(
                id: 'geometry',
                model: builder.compile(),
                dimensionBindings: {'x': CadExpression.parameter('x')}),
            CadFeatureNode(
                id: 'downstream',
                dependencies: ['geometry'],
                evaluate: (context) {
                  final geometry =
                      context.input<GeometrySolveResult>('geometry');
                  return geometry.values['point']![0] > 2.5
                      ? CadKernelResult.failure(CadKernelStatus.invalidInput, [
                          const CadIssue(
                              'rejected_downstream', 'Reject candidate.')
                        ])
                      : CadKernelResult.success(1);
                }),
          ]);
      expect(doc.regenerate().isSuccess, isTrue);
      final committed = doc.state;
      expect(doc.regenerate(changes: {'x': 3}).status,
          CadRegenerationStatus.rejected);
      expect(identical(doc.state, committed), isTrue);
      starts.clear();
      expect(doc.regenerate(changes: {'x': 2}).isSuccess, isTrue);
      expect(starts.first, closeTo(1, 1e-10));
      expect(
          doc.state.output<GeometrySolveResult>('geometry').values['point']![0],
          closeTo(2, 1e-7));
    });
  });
}

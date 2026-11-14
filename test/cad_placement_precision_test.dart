import 'dart:typed_data';

import 'package:dart_csp/cad.dart';
import 'package:dart_csp/dart_csp.dart' show Interval, IntervalRounding;
import 'package:test/test.dart';

const _kernel = ReferenceCadKernel();

CadBody _box() => _kernel
    .extrude(
        featureId: 'box',
        profile: CadRectangularProfile(width: 12, height: 8),
        depth: 3)
    .value!;

class _MutableBody extends CadBody {
  _MutableBody(CadBody body)
      : currentVolume = body.volume,
        super(
            featureId: body.featureId,
            bounds: body.bounds,
            volume: body.volume,
            vertices: body.vertices,
            edges: body.edges,
            faces: body.faces,
            backendData: body.backendData);
  double currentVolume;
  @override
  double get volume => currentVolume;
}

class _MutableTriangle extends CadTriangle {
  _MutableTriangle(CadTriangle source)
      : currentA = source.a,
        super(source.a, source.b, source.c, faceId: source.faceId);
  int currentA;
  @override
  int get a => currentA;
}

class _MutablePoint extends CadPoint3 {
  _MutablePoint(CadPoint3 source)
      : currentX = source.x,
        super(source.x, source.y, source.z);
  double currentX;
  @override
  double get x => currentX;
}

// The public interval algebra and exported column-major matrix provide a
// separate oracle for scalar placement bounds, including every outward step.
CadBounds _intervalBounds(CadRigidTransform transform, CadBounds local) {
  final matrix = transform.toColumnMajorMatrix4();
  final axes = [
    Interval(local.min.x, local.max.x),
    Interval(local.min.y, local.max.y),
    Interval(local.min.z, local.max.z),
  ];
  const rounding = IntervalRounding.outward;
  final result = <Interval>[];
  for (var row = 0; row < 3; row++) {
    var range = rounding.scale(axes[0], matrix[row]);
    for (var column = 1; column < 3; column++) {
      range = rounding.add(
          range, rounding.scale(axes[column], matrix[row + 4 * column]));
    }
    result.add(rounding.add(range, Interval.point(matrix[row + 12])));
  }
  return CadBounds(CadPoint3(result[0].lo, result[1].lo, result[2].lo),
      CadPoint3(result[0].hi, result[1].hi, result[2].hi));
}

List<int> _boundsWords(CadBounds bounds) {
  final bytes = ByteData(8);
  final words = <int>[];
  for (final point in [bounds.min, bounds.max]) {
    for (final coordinate in [point.x, point.y, point.z]) {
      bytes.setFloat64(0, coordinate);
      words.add(bytes.getUint32(0));
      words.add(bytes.getUint32(4));
    }
  }
  return words;
}

void main() {
  test('placement bounds match outward interval algebra bit for bit', () {
    const tiny = double.minPositive;
    const bounds = [
      CadBounds(CadPoint3(-6, -4, 0), CadPoint3(6, 4, 3)),
      CadBounds(CadPoint3(-0.0, -0.0, -0.0), CadPoint3(0, 0, 0)),
      CadBounds(CadPoint3(-tiny, 0, -tiny), CadPoint3(tiny, tiny, tiny)),
      CadBounds(CadPoint3(1e15 - 6, -1e15 - 4, 1e15),
          CadPoint3(1e15 + 6, -1e15 + 4, 1e15 + 3)),
      CadBounds(
          CadPoint3(-1e307, -2e307, -3e307), CadPoint3(4e307, 1e307, 2e307)),
      CadBounds(CadPoint3(-double.maxFinite, 0, 0),
          CadPoint3(double.maxFinite, 1, 1)),
    ];
    final transforms = [
      CadRigidTransform(),
      CadRigidTransform(quaternion: [0, 0, 0, 1]),
      CadRigidTransform(quaternion: [1, 2, -3, 4]),
      CadRigidTransform.axisAngle(
          axis: const CadPoint3(1, 2, -3),
          angle: 1.17,
          translation: const CadPoint3(1e14, -1e14, 1e14)),
    ];
    for (final transform in transforms) {
      for (final local in bounds) {
        final expected = _intervalBounds(transform, local);
        if (expected.isFinite) {
          expect(_boundsWords(transform.transformBounds(local)),
              _boundsWords(expected));
        } else {
          expect(() => transform.transformBounds(local), throwsStateError);
        }
      }
    }
  });

  test('collapsed world analytic topology is rejected and edits roll back', () {
    final body = _box();
    final instance = CadBodyInstance(
        featureId: 'far',
        body: body,
        placement:
            CadRigidTransform(translation: const CadPoint3(1e20, 1e20, 1e20)));
    expect(instance.validate(_kernel).map((issue) => issue.code),
        contains('invalid_instance_placement'));
    expect(() => instance.resolve(CadTopologyKind.edge, 'corner.sw.vertical'),
        throwsStateError);
    final doc = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'offset': 0}),
        features: [
          CadFeatureNode(
              id: 'box', evaluate: (_) => CadKernelResult.success(body)),
          CadFeatureNode.instance(
              id: 'placed',
              body: 'box',
              placement: CadPlacementExpression(
                  x: CadExpression.parameter('offset'),
                  y: CadExpression.parameter('offset'),
                  z: CadExpression.parameter('offset'))),
        ]);
    expect(doc.regenerate().isSuccess, isTrue);
    final committed = doc.state;
    final result = doc.regenerate(changes: {'offset': 1e20});
    expect(result.status, CadRegenerationStatus.rejected);
    expect(result.failedFeature, 'placed');
    expect(identical(doc.state, committed), isTrue);
  });

  test('partial rounding cannot silently change rigid depth and chord error',
      () {
    final body = _box();
    final mesh = _kernel.tessellate(body, chordError: 0.01).value!;
    final placement =
        CadRigidTransform(translation: const CadPoint3(1e16, 1e16, 1e16));
    final result = placement.transformMesh(mesh);
    expect(result.status, CadKernelStatus.numericalFailure);
    expect(result.issues.single.code, 'mesh_placement_precision');
    expect(result.value, isNull);
    final instance =
        CadBodyInstance(featureId: 'far', body: body, placement: placement);
    expect(instance.validate(_kernel), isNotEmpty);

    // An explicitly coarse export is permitted only with an honest enlarged
    // error bound. At this location depth3 rounds to4; the mesh's volume384
    // is therefore an approximation, never reported with the old0.01 error.
    final coarse = placement.transformMesh(mesh, maxRoundingError: 2);
    expect(coarse.isSuccess, isTrue, reason: '${coarse.issues}');
    expect(coarse.value!.signedVolume, closeTo(384, 1e-9));
    expect(coarse.value!.chordError, greaterThanOrEqualTo(1.01));
    expect(body.volume, 288);
  });

  test('exact integer translation retains a usable tight error budget', () {
    final body = _box();
    final mesh = _kernel.tessellate(body, chordError: 0.01).value!;
    final placement =
        CadRigidTransform(translation: const CadPoint3(1e15, -1e15, 1e15));
    final result = placement.transformMesh(mesh, maxRoundingError: 1e-7);
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    expect(result.value!.signedVolume, closeTo(288, 1e-10));
    expect(result.value!.chordError, greaterThanOrEqualTo(mesh.chordError));
    expect(result.value!.chordError, lessThan(mesh.chordError + 1e-10));
    expect(
        CadBodyInstance(featureId: 'far', body: body, placement: placement)
            .validate(_kernel),
        isEmpty);
  });

  test('half-unit translation loss straddles the export precision budget', () {
    final body = _kernel
        .extrude(
            featureId: 'half_step',
            profile: CadRectangularProfile(width: 13, height: 8),
            depth: 3)
        .value!;
    final mesh = _kernel.tessellate(body, chordError: 0.01).value!;
    // Above 2^52, doubles have unit spacing: a positive 6.5 offset rounds
    // to 6. Identity and an exact half-turn both encounter that half-unit loss.
    const offset = 4503599627370496.0;
    for (final rotation in [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 1.0],
    ]) {
      final placement = CadRigidTransform(
          translation: const CadPoint3(offset, 0, 0), quaternion: rotation);
      final rejected = placement.transformMesh(mesh, maxRoundingError: 0.49);
      expect(rejected.status, CadKernelStatus.numericalFailure);
      expect(rejected.issues.single.code, 'mesh_placement_precision');
      final accepted = placement.transformMesh(mesh, maxRoundingError: 0.51);
      expect(accepted.isSuccess, isTrue, reason: '${accepted.issues}');
      var largestError = 0.0;
      for (var i = 0; i < mesh.vertices.length; i++) {
        final expectedX =
            rotation[0] == 1 ? mesh.vertices[i].x : -mesh.vertices[i].x;
        final actualX = accepted.value!.vertices[i].x - offset;
        final error = (actualX - expectedX).abs();
        if (error > largestError) largestError = error;
      }
      expect(largestError, 0.5);
      expect(accepted.value!.chordError, greaterThanOrEqualTo(0.51));
      expect(accepted.value!.chordError, lessThan(0.511));
      expect(accepted.value!.signedVolume, closeTo(300, 1e-9));
      expect(body.volume, 312);
    }
  });

  test('rotated offset precision is bounded and relaxation is explicit', () {
    final body = _box();
    final mesh = _kernel.tessellate(body, chordError: 0.01).value!;
    const offset = CadPoint3(1e14, -1e14, 1e14);
    final placement = CadRigidTransform.axisAngle(
        axis: const CadPoint3(1, 2, 3), angle: 0.73, translation: offset);
    expect(
        CadBodyInstance(featureId: 'tight', body: body, placement: placement)
            .validate(_kernel),
        isNotEmpty);
    expect(
        CadBodyInstance(
                featureId: 'coarse',
                body: body,
                placement: placement,
                linearTolerance: 0.05)
            .validate(_kernel),
        isEmpty);
    final result = placement.transformMesh(mesh, maxRoundingError: 0.05);
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    final bound = result.value!.chordError - mesh.chordError;
    expect(bound, greaterThan(0));
    for (var i = 0; i < mesh.vertices.length; i++) {
      // Subtracting these nearby large coordinates is exact by Sterbenz's
      // lemma. Compare with the independently materialized local rotation.
      final observed = result.value!.vertices[i] - offset;
      final expected = placement.transformDirection(mesh.vertices[i]);
      expect((observed - expected).length, lessThanOrEqualTo(bound));
    }
  });

  test('invalid error budgets and nonfinite arithmetic are rejected', () {
    final body = _box(), placement = CadRigidTransform();
    final mesh = _kernel.tessellate(body).value!;
    for (final budget in [0.0, -1.0, double.nan, double.infinity]) {
      expect(placement.transformMesh(mesh, maxRoundingError: budget).status,
          CadKernelStatus.invalidInput);
      expect(
          () => CadBodyInstance(
              featureId: 'invalid',
              body: body,
              placement: placement,
              linearTolerance: budget),
          throwsArgumentError);
    }
  });

  test('custom body changes still invoke full backend validation', () {
    final body = _MutableBody(_box());
    final instance = CadBodyInstance(
        featureId: 'placed', body: body, placement: CadRigidTransform());
    expect(instance.validate(_kernel), isEmpty);
    body.currentVolume *= 2;
    expect(instance.validate(_kernel).map((issue) => issue.code),
        contains('inconsistent_body_metrics'));
  });

  test('world mesh snapshots custom point and triangle subclasses', () {
    final original = _kernel.tessellate(_box()).value!;
    final point = _MutablePoint(original.vertices.first);
    final triangle = _MutableTriangle(original.triangles.first);
    final local = CadMesh(
        vertices: [point, ...original.vertices.skip(1)],
        triangles: [triangle, ...original.triangles.skip(1)],
        chordError: original.chordError);
    final result = CadRigidTransform().transformMesh(local);
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    final expectedX = result.value!.vertices.first.x;
    final expectedA = result.value!.triangles.first.a;
    point.currentX += 100;
    triangle.currentA = -1;
    expect(result.value!.vertices.first.x, expectedX);
    expect(result.value!.triangles.first.a, expectedA);
    expect(result.value!.validate(), isEmpty);
  });

  test('pose adapter does not normalize checked non-quaternion coordinates',
      () {
    final model = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'translation', values: [0, 0, 0], fixed: true),
      GeometryParameterBlock(id: 'rotation', values: [2, 0, 0, 0], fixed: true),
    ], constraints: const []);
    final result = model.compile().createSession().solve();
    expect(result.isSuccess, isTrue);
    expect(
        () => CadRigidTransform.fromGeometryPose(
            result, const GeometryPose('translation', 'rotation')),
        throwsArgumentError);
    // Normalization remains intentional for explicit unsolved transforms.
    expect(
        CadRigidTransform(quaternion: [2, 0, 0, 0]).quaternion, [1, 0, 0, 0]);
  });
}

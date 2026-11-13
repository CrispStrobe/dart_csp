import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

const _kernel = ReferenceCadKernel();

CadBody _plate({double depth = 2, double centerY = 0}) => _kernel
    .extrude(
        featureId: 'plate',
        depth: depth,
        profile: CadRectangularProfile(width: 20, height: 10, holes: [
          CadCircularHole(id: 'mount', centerX: 0, centerY: centerY, radius: 1),
        ]))
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

class _MutablePoint extends CadPoint3 {
  _MutablePoint() : super(0, 0, 0);

  double currentX = 0;
  @override
  double get x => currentX;
}

class _MutableTriangle extends CadTriangle {
  _MutableTriangle() : super(0, 2, 1, faceId: 'tetra');

  int currentA = 0;
  @override
  int get a => currentA;
}

CadMesh _tetrahedron({CadPoint3? origin, CadTriangle? first}) => CadMesh(
      vertices: [
        origin ?? const CadPoint3(0, 0, 0),
        const CadPoint3(1, 0, 0),
        const CadPoint3(0, 1, 0),
        const CadPoint3(0, 0, 1),
      ],
      triangles: [
        first ?? const CadTriangle(0, 2, 1, faceId: 'tetra'),
        const CadTriangle(0, 1, 3, faceId: 'tetra'),
        const CadTriangle(0, 3, 2, faceId: 'tetra'),
        const CadTriangle(1, 2, 3, faceId: 'tetra'),
      ],
      chordError: 0.01,
    );

class _CustomValidator extends ReferenceCadKernel {
  var calls = 0;
  var reject = false;

  @override
  List<CadIssue> validate(CadBody body) {
    calls++;
    final base = super.validate(body);
    return [
      ...base,
      if (reject) const CadIssue('application_rejection', 'Custom policy.'),
    ];
  }
}

void main() {
  test('owned immutable bodies and meshes reuse their complete validation', () {
    final body = _plate();
    final bodyIssues = _kernel.validate(body);
    expect(bodyIssues, isEmpty);
    expect(identical(_kernel.validate(body), bodyIssues), isTrue);
    expect(() => bodyIssues.add(const CadIssue('bad', 'bad')),
        throwsUnsupportedError);

    final mesh = _kernel.tessellate(body, chordError: 0.01).value!;
    final meshIssues = mesh.validate();
    final volume = mesh.signedVolume;
    expect(meshIssues, isEmpty);
    expect(identical(mesh.validate(), meshIssues), isTrue);
    expect(mesh.signedVolume, volume);
    expect(volume, greaterThan(0));
    expect(() => meshIssues.add(const CadIssue('bad', 'bad')),
        throwsUnsupportedError);
    expect(mesh.vertices.clear, throwsUnsupportedError);
    expect(mesh.triangles.clear, throwsUnsupportedError);
  });

  test('copies cannot borrow the validation of an immutable original', () {
    final body = _plate();
    expect(_kernel.validate(body), isEmpty);
    final missingFace = CadBody(
        featureId: body.featureId,
        bounds: body.bounds,
        volume: body.volume,
        vertices: body.vertices,
        edges: body.edges,
        faces: body.faces.skip(1),
        backendData: body.backendData);
    expect(_kernel.validate(missingFace), isNotEmpty);
    expect(_kernel.tessellate(missingFace).status,
        CadKernelStatus.invalidTopology);

    final mesh = _kernel.tessellate(body).value!;
    expect(mesh.validate(), isEmpty);
    final openMesh = CadMesh(
        vertices: mesh.vertices,
        triangles: mesh.triangles.skip(1),
        chordError: mesh.chordError);
    expect(openMesh.validate(), isNotEmpty);
    expect(mesh.validate(), isEmpty);
    expect(_kernel.validate(body), isEmpty);
  });

  test('public body subclasses are revalidated after getter changes', () {
    final body = _MutableBody(_plate());
    expect(_kernel.validate(body), isEmpty);
    body.currentVolume *= 2;
    expect(_kernel.validate(body).map((issue) => issue.code),
        contains('inconsistent_body_metrics'));
    expect(_kernel.tessellate(body).status, CadKernelStatus.invalidTopology);
  });

  test('public meshes do not cache mutable point subclass data', () {
    final point = _MutablePoint();
    final mesh = _tetrahedron(origin: point);
    expect(mesh.validate(), isEmpty);
    point.currentX = double.infinity;
    expect(mesh.validate().map((issue) => issue.code),
        contains('non_finite_vertex'));
  });

  test('public meshes do not cache mutable triangle subclass data', () {
    final triangle = _MutableTriangle();
    final mesh = _tetrahedron(first: triangle);
    expect(mesh.validate(), isEmpty);
    triangle.currentA = 9;
    expect(
        mesh.validate().map((issue) => issue.code), contains('invalid_index'));
  });

  test('custom validators still run for cached reference bodies', () {
    final kernel = _CustomValidator();
    final body = kernel
        .extrude(
            featureId: 'plate',
            profile: CadRectangularProfile(width: 20, height: 10),
            depth: 2)
        .value!;
    expect(kernel.calls, 1);
    expect(kernel.validate(body), isEmpty);
    expect(kernel.calls, 2);
    kernel.reject = true;
    expect(kernel.validate(body).map((issue) => issue.code),
        contains('application_rejection'));
    expect(kernel.tessellate(body).status, CadKernelStatus.invalidTopology);
    expect(kernel.calls, 4);
  });

  test('numeric vertex keys merge negative zero without losing topology', () {
    final positive = _kernel.tessellate(_plate()).value!;
    final negative = _kernel.tessellate(_plate(centerY: -0.0)).value!;
    expect(positive.validate(), isEmpty);
    expect(negative.validate(), isEmpty);
    expect(negative.vertices.map((point) => (point.x, point.y, point.z)),
        positive.vertices.map((point) => (point.x, point.y, point.z)));
    expect(
        negative.triangles.map((triangle) =>
            (triangle.a, triangle.b, triangle.c, triangle.faceId)),
        positive.triangles.map((triangle) =>
            (triangle.a, triangle.b, triangle.c, triangle.faceId)));
  });
}

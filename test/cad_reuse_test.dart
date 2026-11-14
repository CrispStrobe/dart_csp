import 'dart:typed_data';

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

// Two portable integer fingerprints cover every coordinate bit, triangle
// index and face-ID code unit in acquisition order. These golden values were
// captured from the preceding implementation, independently of corner reuse.
(int, int, int, int) _meshFingerprint(CadMesh mesh) {
  var first = 0, second = 0;
  final bytes = ByteData(8);
  void add(int value) {
    first = (first * 31 + value) & 0x7fffffff;
    second = (second * 131 + value) & 0x7fffffff;
  }

  void integer(int value) {
    bytes.setUint32(0, value);
    for (var i = 0; i < 4; i++) {
      add(bytes.getUint8(i));
    }
  }

  integer(mesh.vertices.length);
  integer(mesh.triangles.length);
  for (final point in mesh.vertices) {
    for (final coordinate in [point.x, point.y, point.z]) {
      bytes.setFloat64(0, coordinate);
      for (var i = 0; i < 8; i++) {
        add(bytes.getUint8(i));
      }
    }
  }
  for (final triangle in mesh.triangles) {
    integer(triangle.a);
    integer(triangle.b);
    integer(triangle.c);
    integer(triangle.faceId.length);
    for (final unit in triangle.faceId.codeUnits) {
      integer(unit);
    }
  }
  return (mesh.vertices.length, mesh.triangles.length, first, second);
}

void main() {
  test('tessellation preserves complete vertex, triangle and face ordering',
      () {
    final fixtures = [
      (
        'box',
        CadRectangularProfile(width: 4, height: 6),
        2.0,
        0.03,
        (10, 16, 1438434876, 1165328956)
      ),
      (
        'offset_holes',
        CadRectangularProfile(width: 20, height: 10, holes: const [
          CadCircularHole(id: 'left', centerX: -4, centerY: -1, radius: 0.75),
          CadCircularHole(id: 'right', centerX: 4, centerY: 2, radius: 1.25),
        ]),
        2.0,
        0.01,
        (310, 624, 489170054, 1977643058)
      ),
      (
        'positive_zero',
        CadRectangularProfile(width: 4, height: 2, holes: const [
          CadCircularHole(id: 'mount', centerX: 0.0, centerY: 0.0, radius: 0.5),
        ]),
        0.5,
        0.03,
        (112, 224, 620630730, 1918679338)
      ),
      (
        'negative_zero',
        CadRectangularProfile(width: 4, height: 2, holes: const [
          CadCircularHole(
              id: 'mount', centerX: -0.0, centerY: -0.0, radius: 0.5),
        ]),
        0.5,
        0.03,
        (112, 224, 1321497034, 13210666)
      ),
    ];
    for (final (name, profile, depth, chordError, expected) in fixtures) {
      final body = _kernel
          .extrude(featureId: name, profile: profile, depth: depth)
          .value!;
      final result = _kernel.tessellate(body, chordError: chordError);
      expect(result.isSuccess, isTrue, reason: name);
      expect(_meshFingerprint(result.value!), expected, reason: name);
      expect(result.value!.validate(), isEmpty);
    }
  });

  test('tessellation retains ordered unresolved-area diagnostics', () {
    final body = _kernel
        .extrude(
            featureId: 'thin',
            profile: CadRectangularProfile(width: 1e308, height: 1e-308),
            depth: 1)
        .value!;
    final result = _kernel.tessellate(body, chordError: 0.03);
    expect(result.status, CadKernelStatus.invalidTopology);
    expect(result.value, isNull);
    expect(result.issues.map((issue) => (issue.code, issue.entity)), [
      for (var edge = 0; edge < 4; edge++) ...[
        ('degenerate_triangle', 'top'),
        ('degenerate_triangle', 'bottom'),
      ],
    ]);
  });

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

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

CadMesh _tetrahedron(CadPoint3 offset, {bool reversed = false}) => CadMesh(
      vertices: [
        offset,
        offset + const CadPoint3(1, 0, 0),
        offset + const CadPoint3(0, 1, 0),
        offset + const CadPoint3(0, 0, 1),
      ],
      triangles: [
        for (final (a, b, c) in [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)])
          if (reversed)
            CadTriangle(a, c, b, faceId: 'tetrahedron')
          else
            CadTriangle(a, b, c, faceId: 'tetrahedron'),
      ],
      chordError: 0.01,
    );

void main() {
  test('small solid volume remains correct far from the coordinate origin', () {
    for (final offset in [
      const CadPoint3(0, 0, 0),
      const CadPoint3(1e8, 1e8, 1e8),
      const CadPoint3(1e12, -1e12, 1e12),
      const CadPoint3(-1e15, 1e15, -1e15),
    ]) {
      final mesh = _tetrahedron(offset);
      expect(mesh.signedVolume, closeTo(1 / 6, 1e-15), reason: '$offset');
      expect(mesh.validate(), isEmpty, reason: '$offset');
      final reversed = _tetrahedron(offset, reversed: true);
      expect(reversed.signedVolume, closeTo(-1 / 6, 1e-15));
      expect(
        reversed.validate().map((issue) => issue.code),
        contains('non_positive_volume'),
      );
    }
  });

  test('translated reference extrusion retains independently known volume', () {
    const kernel = ReferenceCadKernel();
    final body = kernel
        .extrude(
          featureId: 'block',
          profile: CadRectangularProfile(width: 12, height: 8),
          depth: 4,
        )
        .value!;
    final local = kernel.tessellate(body).value!;
    const offset = CadPoint3(1e12, -1e12, 1e12);
    final translated = CadMesh(
      vertices: local.vertices.map((point) => point + offset),
      triangles: local.triangles.reversed,
      chordError: local.chordError,
    );
    expect(translated.signedVolume, closeTo(12 * 8 * 4, 1e-10));
    expect(translated.validate(), isEmpty);
  });

  test('compensated accumulation preserves small signed contributions', () {
    // Three oriented tetrahedra contribute +1e16, +1 and -1e16. This is an
    // arithmetic fixture, not a valid nonintersecting solid boundary. The
    // expected signed sum is independent of triangle traversal order.
    final vertices = <CadPoint3>[const CadPoint3(0, 0, 0)];
    final triangles = <CadTriangle>[];
    for (final (height, reversed) in [
      (6e16, false),
      (6.0, false),
      (6e16, true),
    ]) {
      final first = vertices.length;
      vertices.addAll([
        const CadPoint3(1, 0, 0),
        const CadPoint3(0, 1, 0),
        CadPoint3(0, 0, height),
      ]);
      for (final (a, b, c) in [
        (0, first + 1, first),
        (0, first, first + 2),
        (0, first + 2, first + 1),
        (first, first + 1, first + 2),
      ]) {
        triangles.add(
          reversed
              ? CadTriangle(a, c, b, faceId: 'sum')
              : CadTriangle(a, b, c, faceId: 'sum'),
        );
      }
    }
    final mesh = CadMesh(
      vertices: vertices,
      triangles: triangles,
      chordError: 0.01,
    );
    expect(mesh.signedVolume, 1);
    expect(
      CadMesh(
        vertices: vertices,
        triangles: triangles.reversed,
        chordError: 0.01,
      ).signedVolume,
      1,
    );
  });

  test('empty and unresolved meshes do not acquire a positive volume', () {
    final empty = CadMesh(
      vertices: const [],
      triangles: const [],
      chordError: 0.01,
    );
    expect(empty.signedVolume, 0);
    expect(
      empty.validate().map((issue) => issue.code),
      contains('non_positive_volume'),
    );
    final unresolved = _tetrahedron(const CadPoint3(1e20, 1e20, 1e20));
    expect(unresolved.signedVolume, 0);
    expect(unresolved.validate(), isNotEmpty);
  });
}

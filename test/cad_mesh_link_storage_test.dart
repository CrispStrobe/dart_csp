import 'dart:math' as math;

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

// Independent definition of a closed vertex link: build the full undirected
// graph, require degree two and visit every node with an unrestricted BFS.
// This deliberately retains all neighbors, including malformed degree > 2.
List<(String, String)> _vertexIssues(CadMesh mesh) {
  final issues = <(String, String)>[];
  for (var center = 0; center < mesh.vertices.length; center++) {
    final adjacency = <int, Set<int>>{};
    for (final triangle in mesh.triangles) {
      final corners = [triangle.a, triangle.b, triangle.c];
      if (!corners.contains(center)) continue;
      corners.remove(center);
      adjacency.putIfAbsent(corners[0], () => <int>{}).add(corners[1]);
      adjacency.putIfAbsent(corners[1], () => <int>{}).add(corners[0]);
    }
    if (adjacency.isEmpty) {
      issues.add(('unused_vertex', '$center'));
      continue;
    }
    final visited = <int>{};
    final pending = [adjacency.keys.first];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (visited.add(next)) pending.addAll(adjacency[next]!);
    }
    if (adjacency.length < 3 ||
        adjacency.values.any((neighbors) => neighbors.length != 2) ||
        visited.length != adjacency.length) {
      issues.add(('non_manifold_vertex', '$center'));
    }
  }
  return issues;
}

void main() {
  test('bounded link storage agrees with full graphs for arbitrary complexes',
      () {
    for (var seed = 0; seed < 120; seed++) {
      final random = math.Random(seed);
      final vertexCount = 3 + random.nextInt(7);
      final triples = <(int, int, int)>[
        for (var a = 0; a < vertexCount; a++)
          for (var b = a + 1; b < vertexCount; b++)
            for (var c = b + 1; c < vertexCount; c++) (a, b, c),
      ]..shuffle(random);
      final mesh = CadMesh(vertices: [
        for (var i = 0; i < vertexCount; i++)
          CadPoint3(
              random.nextDouble(), random.nextDouble(), random.nextDouble()),
      ], triangles: [
        for (final (a, b, c)
            in triples.take(random.nextInt(triples.length + 1)))
          if (random.nextBool())
            CadTriangle(a, b, c, faceId: 'soup')
          else
            CadTriangle(c, b, a, faceId: 'soup'),
      ], chordError: 0.01);
      expect(
          mesh
              .validate()
              .where((issue) =>
                  issue.code == 'unused_vertex' ||
                  issue.code == 'non_manifold_vertex')
              .map((issue) => (issue.code, issue.entity!)),
          _vertexIssues(mesh),
          reason: 'seed=$seed');
    }
  });

  test('all corner permutations identify the same duplicate simplex', () {
    const vertices = [
      CadPoint3(0, 0, 0),
      CadPoint3(1, 0, 0),
      CadPoint3(0, 1, 0),
      CadPoint3(0, 0, 1),
    ];
    const tetrahedron = [
      CadTriangle(0, 2, 1, faceId: 'base'),
      CadTriangle(0, 1, 3, faceId: 'side'),
      CadTriangle(0, 3, 2, faceId: 'side'),
      CadTriangle(1, 2, 3, faceId: 'side'),
    ];
    for (final (a, b, c) in [
      (0, 1, 2),
      (0, 2, 1),
      (1, 0, 2),
      (1, 2, 0),
      (2, 0, 1),
      (2, 1, 0),
    ]) {
      final mesh = CadMesh(
          vertices: vertices,
          triangles: [
            ...tetrahedron,
            CadTriangle(a, b, c, faceId: 'duplicate')
          ],
          chordError: 0.01);
      final issues = mesh.validate();
      expect(issues, hasLength(1));
      expect(issues.single.code, 'duplicate_triangle');
      expect(issues.single.entity, 'duplicate');
    }
  });
}

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

Problem _rectangles(List<List<num>> coordinates,
    {List<int> widths = const [1, 1], List<int> heights = const [1, 1]}) {
  final problem = Problem();
  for (var i = 0; i < widths.length; i++) {
    problem.addVariable('x$i', coordinates[i]);
    problem.addVariable('y$i', coordinates[widths.length + i]);
  }
  problem.addDiffN([for (var i = 0; i < widths.length; i++) 'x$i'],
      [for (var i = 0; i < widths.length; i++) 'y$i'], widths, heights);
  return problem;
}

bool _separate(List<num> point, List<int> widths, List<int> heights) {
  final n = widths.length;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (widths[i] == 0 ||
          widths[j] == 0 ||
          heights[i] == 0 ||
          heights[j] == 0) {
        continue;
      }
      if (!(point[i] + widths[i] <= point[j] ||
          point[j] + widths[j] <= point[i] ||
          point[n + i] + heights[i] <= point[n + j] ||
          point[n + j] + heights[j] <= point[n + i])) {
        return false;
      }
    }
  }
  return true;
}

String _key(Iterable<num> values) => values.map((x) => x.toDouble()).join(',');

Set<String> _oracle(
    List<List<num>> domains, List<int> widths, List<int> heights) {
  final found = <String>{};
  final point = List<num>.filled(domains.length, 0);
  void visit(int i) {
    if (i == domains.length) {
      if (_separate(point, widths, heights)) found.add(_key(point));
      return;
    }
    for (final value in domains[i]) {
      point[i] = value;
      visit(i + 1);
    }
  }

  visit(0);
  return found;
}

void main() {
  test('JavaScript integer-shaped infinite extents are rejected', () {
    if (!identical(1, 1.0)) return;
    final int infinite = (double.infinity as dynamic);
    final problem = Problem()..addVariables(['x0', 'x1', 'y0', 'y1'], [0.25]);
    expect(
        () =>
            problem.addDiffN(['x0', 'x1'], ['y0', 'y1'], [infinite, 1], [1, 1]),
        throwsArgumentError);
    expect(
        () =>
            problem.addDiffN(['x0', 'x1'], ['y0', 'y1'], [1, 1], [1, infinite]),
        throwsArgumentError);
  });

  test('overlapping fractional singleton rectangles are infeasible', () async {
    final problem = _rectangles([
      [0.25],
      [0.75],
      [0.125],
      [0.625],
    ]);
    expect(await problem.getSolution(), 'FAILURE');
    expect(await problem.getAllSolutions(), isEmpty);
    expect(await problem.solveWithLcg(), 'FAILURE');
    expect((await problem.compile().createSession().solve()).status,
        CspSolveStatus.infeasible);
  });

  test('touching fractional rectangles remain valid in compiled sessions',
      () async {
    final problem = _rectangles([
      [0.25],
      [1.25],
      [-0.5],
      [-0.5],
    ]);
    expect(await problem.getSolution(), isA<Map<String, dynamic>>());
    final result = await problem.compile().createSession().solve();
    expect(result.status, CspSolveStatus.satisfied);
  });

  test('search continues past overlapping candidates', () async {
    final problem = _rectangles([
      [0.25],
      [0.5, 1.25],
      [0.25],
      [0.25],
    ]);
    for (final cbj in [false, true]) {
      final solution =
          await problem.getSolution(enableConflictBackjumping: cbj);
      expect(solution, containsPair('x1', 1.25));
    }
    expect(await problem.solveWithLcg(), containsPair('x1', 1.25));
    final result = await problem.compile().createSession().solve();
    expect(result.status, CspSolveStatus.satisfied);
    expect(result.solution, containsPair('x1', 1.25));
  });

  test('mixed integer/fractional layouts agree with Cartesian-product oracle',
      () async {
    final random = Random(140314);
    for (var round = 0; round < 80; round++) {
      final n = 2 + random.nextInt(2);
      final domains = [
        for (var i = 0; i < 2 * n; i++)
          (<num>{
            for (var j = 0; j < 3; j++)
              if (random.nextBool())
                random.nextInt(5) - 2
              else
                (random.nextInt(9) - 4) / 2 + 0.25,
          }.toList()
            ..shuffle(random)),
      ];
      final widths = [for (var i = 0; i < n; i++) random.nextInt(3)];
      final heights = [for (var i = 0; i < n; i++) random.nextInt(3)];
      final expected = _oracle(domains, widths, heights);
      final problem = _rectangles(domains, widths: widths, heights: heights);
      for (final consistency in ConsistencyLevel.values) {
        final actual =
            await problem.getSolutions(consistency: consistency).toList();
        expect(
            actual
                .map((solution) => _key([
                      for (var i = 0; i < n; i++) solution['x$i'] as num,
                      for (var i = 0; i < n; i++) solution['y$i'] as num,
                    ]))
                .toSet(),
            expected,
            reason: 'round=$round consistency=$consistency');
      }
      final learned = await problem.solveWithLcg(seed: round);
      expect(learned == 'FAILURE', expected.isEmpty,
          reason: 'LCG round=$round');
      if (learned is Map<String, dynamic>) {
        expect(
            expected,
            contains(_key([
              for (var i = 0; i < n; i++) learned['x$i'] as num,
              for (var i = 0; i < n; i++) learned['y$i'] as num,
            ])));
      }
      final compiled = await problem.compile().createSession().solve();
      expect(
          compiled.status,
          expected.isEmpty
              ? CspSolveStatus.infeasible
              : CspSolveStatus.satisfied,
          reason: 'compiled round=$round');
    }
  });

  test('fractional assumptions recover after an infeasible session query',
      () async {
    final session = _rectangles([
      [0.25],
      [0.5, 1.25],
      [0.125, 1.125],
      [0.125],
    ]).compile().createSession();
    expect(
        (await session.solve(assumptions: [
          const CspAssumption.equals('x1', 0.5),
          const CspAssumption.equals('y0', 0.125),
        ]))
            .status,
        CspSolveStatus.infeasible);
    final restored = await session.solve(assumptions: [
      const CspAssumption.equals('x1', 1.25),
      const CspAssumption.equals('y0', 0.125),
    ]);
    expect(restored.status, CspSolveStatus.satisfied);
    expect(restored.reusedRoot, isTrue);
  });

  test('numeric pruning uses the original rounded endpoint comparisons',
      () async {
    // At this magnitude x + 1 == x in double arithmetic. Rewriting the
    // predicate as an open interval using subtraction could remove a value
    // that satisfies the original endpoint comparison.
    final domains = <List<num>>[
      [1e16],
      [1e16],
      [0.125],
      [0.125],
    ];
    final expected = _oracle(domains, [1, 1], [1, 1]);
    final actual = await _rectangles(domains).getAllSolutions();
    expect(actual.length, expected.length);
  });

  test('equal integer and double starts can have different rounded ends',
      () async {
    final domains = <List<num>>[
      [0.25],
      [0.25],
      [9007199254740992, 9007199254740992.0],
      [9007199254740992],
    ];
    final expected = _oracle(domains, [1, 1], [1, 1]);
    final actual = await _rectangles(domains).getAllSolutions();
    expect(actual, isNotEmpty);
    for (final solution in actual) {
      final values = [
        solution['x0'] as num,
        solution['x1'] as num,
        solution['y0'] as num,
        solution['y1'] as num,
      ];
      expect(_separate(values, [1, 1], [1, 1]), isTrue);
      expect(expected, contains(_key(values)));
    }
  });

  test('fractional peer trims a billion-coordinate integer range compactly',
      () async {
    final problem = Problem()
      ..addVariable('x0', [0.25])
      ..addRangeVariable('x1', 0, 1000000000)
      ..addVariable('y0', [0.25])
      ..addVariable('y1', [0.25])
      ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [1000000000, 1], [1, 1]);
    expect(await problem.getSolution(), 'FAILURE');
    final feasible = Problem()
      ..addVariable('x0', [0.25])
      ..addRangeVariable('x1', 0, 1000000001)
      ..addVariable('y0', [0.25])
      ..addVariable('y1', [0.25])
      ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [1000000000, 1], [1, 1]);
    expect(await feasible.getSolution(), containsPair('x1', 1000000001));
  });
}

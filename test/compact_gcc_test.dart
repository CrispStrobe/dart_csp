import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

typedef _Bounds = Map<int, ({int min, int max})>;

List<List<int>> _oracle(List<List<int>> domains, _Bounds bounds) {
  final result = <List<int>>[];
  final tuple = List<int>.filled(domains.length, 0);
  void visit(int index) {
    if (index == domains.length) {
      for (final entry in bounds.entries) {
        final count = tuple.where((value) => value == entry.key).length;
        if (count < entry.value.min || count > entry.value.max) return;
      }
      result.add(List.of(tuple));
      return;
    }
    for (final value in domains[index]) {
      tuple[index] = value;
      visit(index + 1);
    }
  }

  visit(0);
  return result;
}

Problem _build(List<List<int>> domains, _Bounds bounds) {
  final problem = Problem();
  for (var i = 0; i < domains.length; i++) {
    problem.addVariable('x$i', domains[i]);
  }
  problem
      .addGccRanges([for (var i = 0; i < domains.length; i++) 'x$i'], bounds);
  return problem;
}

String _key(Map<String, dynamic> assignment, int count) =>
    [for (var i = 0; i < count; i++) assignment['x$i']].join(',');

void main() {
  test('lower capacities force a root solution without any search', () async {
    final result = await _build([
      [0, 1],
      [0, 1],
      [0],
    ], {
      1: (min: 2, max: 2),
    }).compile().createSession().solve(maxDecisions: 0);
    expect(result.status, CspSolveStatus.satisfied);
    expect(result.solution, {'x0': 1, 'x1': 1, 'x2': 0});
    expect(result.stats.decisions, 0);
  });

  test('missing and competing minimum capacities fail at the root', () async {
    for (final problem in [
      _build([
        [0, 1],
        [0, 1],
      ], {
        2: (min: 1, max: 2),
      }),
      _build([
        [1, 2],
        [0],
      ], {
        1: (min: 1, max: 1),
        2: (min: 1, max: 1),
      }),
    ]) {
      final result =
          await problem.compile().createSession().solve(maxDecisions: 0);
      expect(result.status, CspSolveStatus.infeasible);
      expect(result.stats.decisions, 0);
    }
  });

  test('unlisted values have unrestricted multiplicity', () async {
    final solutions = await _build([
      [0, 1, 2],
      [0, 1, 2],
    ], {
      1: (min: 0, max: 0),
    }).getAllSolutions();
    expect({for (final solution in solutions) _key(solution, 2)},
        {'0,0', '0,2', '2,0', '2,2'});
  });

  test('capacities use one value node and retain repaired assignments',
      () async {
    const n = 64, values = 8;
    final session = _build([
      for (var i = 0; i < n; i++) List.generate(values, (value) => value),
    ], {
      for (var value = 0; value < values; value++)
        value: (min: 0, max: 1000000),
    }).compile().createSession();
    final initial = await session.solve(maxDecisions: 0);
    expect(initial.status, CspSolveStatus.decisionLimit);
    expect(initial.stats.gccMaxFlowNodes, n + values + 1);
    expect(initial.stats.gccMaxTotalCapacity, n * values);
    expect(initial.stats.gccMaxFlowEdges,
        lessThanOrEqualTo(n * values + 2 * values));
    expect(initial.stats.gccAugmentations, n);
    final changed = await session.solve(
        assumptions: [const CspAssumption.equals('x0', 7)], maxDecisions: 0);
    expect(changed.status, CspSolveStatus.decisionLimit);
    expect(changed.stats.gccAugmentations, lessThan(n));
    expect(changed.stats.gccMaxFlowNodes, n + values + 1);
    expect(session.rootPreparationCount, 1);
    final snapshot = changed.stats.snapshot();
    expect(SolverStats.fromMap(snapshot.toMap()).toMap(), snapshot.toMap());
  });

  test('80 lower/upper flow models match independent full enumeration',
      () async {
    final random = Random(438907);
    for (var example = 0; example < 80; example++) {
      final count = 3 + example % 2;
      final domains = [
        for (var i = 0; i < count; i++)
          [
            for (var value = -1; value < 4; value++)
              if (random.nextInt(3) != 0) value,
          ]..shuffle(random),
      ];
      for (final domain in domains) {
        if (domain.isEmpty) domain.add(random.nextInt(5) - 1);
      }
      final bounds = <int, ({int min, int max})>{};
      var minimumBudget = count;
      for (var value = -1; value < (example % 5 == 0 ? 5 : 4); value++) {
        if (random.nextInt(4) == 0) continue;
        final upper = random.nextInt(count + 2);
        final lower = random.nextInt(min(upper, minimumBudget) + 1);
        bounds[value] = (min: lower, max: upper);
        minimumBudget -= lower;
      }
      final expected = _oracle(domains, bounds);
      final expectedKeys = {
        for (final assignment in expected) assignment.join(',')
      };
      final problem = _build(domains, bounds);
      final solutions = await problem.getAllSolutions();
      expect({for (final solution in solutions) _key(solution, count)},
          expectedKeys,
          reason: 'model=$example domains=$domains bounds=$bounds');
      expect(solutions.length, expectedKeys.length);
      for (final iterative in [false, true]) {
        final result = await problem.solveWithLcg(useIterativeCdcl: iterative);
        if (expected.isEmpty) {
          expect(result, 'FAILURE', reason: 'LCG model=$example');
        } else {
          expect(expectedKeys,
              contains(_key(result as Map<String, dynamic>, count)));
        }
      }

      // Every allowed edge is independently probed after root restoration.
      // A lone GCC is GAC: an unsupported value must fail without a decision.
      final session = problem.compile().createSession();
      for (var variable = 0; variable < count; variable++) {
        for (final value in domains[variable]) {
          final supported =
              expected.any((assignment) => assignment[variable] == value);
          final result = await session.solve(assumptions: [
            CspAssumption.equals('x$variable', value),
          ], maxDecisions: 0);
          expect(
              result.status,
              supported
                  ? anyOf(
                      CspSolveStatus.satisfied, CspSolveStatus.decisionLimit)
                  : CspSolveStatus.infeasible,
              reason: 'GAC model=$example x$variable=$value bounds=$bounds');
        }
      }
      session.close();
    }
  });
}

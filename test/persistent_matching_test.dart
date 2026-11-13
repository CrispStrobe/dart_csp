import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

List<Map<String, int>> _distinctAssignments(List<List<int>> domains) {
  final results = <Map<String, int>>[];
  final assignment = <String, int>{};
  void visit(int index) {
    if (index == domains.length) {
      if (assignment.values.toSet().length == domains.length) {
        results.add(Map.of(assignment));
      }
      return;
    }
    for (final value in domains[index]) {
      assignment['x$index'] = value;
      visit(index + 1);
    }
    assignment.remove('x$index');
  }

  visit(0);
  return results;
}

void main() {
  test('retained matching repairs after conflicts and domain restoration',
      () async {
    final session = (Problem()
          ..addVariable('a', ['red', 'blue'])
          ..addVariable('b', ['blue', 'green'])
          ..addVariable('c', ['green', 'yellow'])
          ..addAllDifferent(['a', 'b', 'c']))
        .compile()
        .createSession();
    for (var repeat = 0; repeat < 8; repeat++) {
      final left = await session.solve(assumptions: [
        const CspAssumption.equals('a', 'red'),
        const CspAssumption.equals('b', 'blue'),
        const CspAssumption.equals('c', 'green'),
      ]);
      expect(left.status, CspSolveStatus.satisfied);
      final conflict = await session.solve(assumptions: [
        const CspAssumption.equals('a', 'blue'),
        const CspAssumption.equals('b', 'blue'),
      ]);
      expect(conflict.status, CspSolveStatus.infeasible);
      final right = await session.solve(assumptions: [
        const CspAssumption.equals('a', 'blue'),
        const CspAssumption.equals('b', 'green'),
        const CspAssumption.equals('c', 'yellow'),
      ]);
      expect(right.status, CspSolveStatus.satisfied);
    }
    expect(session.rootPreparationCount, 1);
  });

  test('overlapping globals retain separate matching states', () async {
    final problem = Problem()
      ..addVariables(['a', 'b', 'c', 'd'], [0, 1, 2])
      ..addAllDifferent(['a', 'b', 'c'])
      ..addAllDifferent(['b', 'c', 'd']);
    final session = problem.compile().createSession();
    for (var value = 0; value < 3; value++) {
      final result =
          await session.solve(assumptions: [CspAssumption.equals('a', value)]);
      expect(result.status, CspSolveStatus.satisfied);
      expect(result.solution!['d'], value);
      expect({'a', 'b', 'c'}.map((key) => result.solution![key]).toSet().length,
          3);
    }
    final solutions = await problem.getAllSolutions();
    expect(solutions, hasLength(6));
  });

  test('320 restored-domain edit queries match an independent oracle',
      () async {
    final random = Random(95731);
    for (var example = 0; example < 40; example++) {
      final domains = [
        for (var i = 0; i < 4; i++)
          [
            for (var value = -1; value < 4; value++)
              if (random.nextBool()) value,
          ]..shuffle(random),
      ];
      for (final domain in domains) {
        if (domain.isEmpty) domain.add(random.nextInt(5) - 1);
      }
      final problem = Problem();
      for (var i = 0; i < domains.length; i++) {
        problem.addVariable('x$i', domains[i]);
      }
      problem.addAllDifferent(['x0', 'x1', 'x2', 'x3']);
      final oracle = _distinctAssignments(domains);
      final session = problem.compile().createSession();
      for (var edit = 0; edit < 8; edit++) {
        final fixed = {
          'x${random.nextInt(4)}': random.nextInt(5) - 1,
          if (edit.isEven) 'x${random.nextInt(4)}': random.nextInt(5) - 1,
        };
        final feasible = oracle
            .where((assignment) => fixed.entries
                .every((entry) => assignment[entry.key] == entry.value))
            .toList();
        final result = await session.solve(assumptions: [
          for (final entry in fixed.entries)
            CspAssumption.equals(entry.key, entry.value),
        ]);
        expect(
            result.status,
            feasible.isEmpty
                ? CspSolveStatus.infeasible
                : CspSolveStatus.satisfied,
            reason: 'model=$example edit=$edit domains=$domains fixed=$fixed');
        if (feasible.isNotEmpty) {
          expect(
              feasible.any((assignment) => assignment.entries.every(
                  (entry) => result.solution![entry.key] == entry.value)),
              isTrue);
        }
      }
      expect(session.rootPreparationCount, 1);
      session.close();
    }
  });
}

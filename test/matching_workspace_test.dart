import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void _distinct(
    Problem problem, List<String> variables, bool gcc, Iterable<int> values) {
  if (gcc) {
    problem.addGccRanges(variables, {
      for (final value in values) value: (min: 0, max: 1),
    });
  } else {
    problem.addAllDifferent(variables);
  }
}

class _PollingToken extends CancellationToken {
  _PollingToken(this.limit);

  final int limit;
  var polls = 0;

  @override
  bool get isCancelled {
    if (++polls >= limit) cancel();
    return super.isCancelled;
  }
}

void main() {
  for (final gcc in [false, true]) {
    final label = gcc ? 'GCC' : 'allDifferent';

    test('$label analyzes a pruning fixed point only once', () async {
      final problem = Problem()
        ..addVariable('a', [0])
        ..addVariable('b', [0, 1])
        ..addVariable('c', [1, 2]);
      _distinct(problem, ['a', 'b', 'c'], gcc, [0, 1, 2]);
      final session = problem.compile().createSession();
      final result = await session.solve(maxDecisions: 0);
      expect(result.status, CspSolveStatus.satisfied);
      expect(result.solution, {'a': 0, 'b': 1, 'c': 2});
      expect(result.stats.naryRevises, 1);
      expect(result.stats.matchingSccPasses, 1);
      expect(result.stats.matchingFixedPointSkips, 1);
      expect(result.stats.matchingWorkspaceGrowths, 1);
      if (gcc) expect(result.stats.gccPropagations, 2);
      session.close();
    });

    test('$label reuses scratch but reanalyzes restored edit domains',
        () async {
      final names = [for (var i = 0; i < 6; i++) 'x$i'];
      // Preserve a non-monotonic domain order to exercise list-backed domains.
      const values = [5, 1, 3, 0, 4, 2, 7, 6];
      final problem = Problem()..addVariables(names, values);
      _distinct(problem, names, gcc, values);
      final session = problem.compile().createSession();
      final root = await session.solve(maxDecisions: 0);
      expect(root.status, CspSolveStatus.decisionLimit);
      expect(root.stats.matchingWorkspaceGrowths, 1);
      for (final value in [5, 7, 0, 5]) {
        final edit = await session.solve(
          assumptions: [CspAssumption.equals('x0', value)],
          maxDecisions: 0,
        );
        expect(edit.status, CspSolveStatus.decisionLimit);
        expect(edit.stats.matchingSccPasses, 1);
        expect(edit.stats.matchingFixedPointSkips, 1);
        expect(edit.stats.matchingWorkspaceGrowths, 0);
      }
      final conflict = await session.solve(assumptions: [
        const CspAssumption.equals('x0', 5),
        const CspAssumption.equals('x1', 5),
      ]);
      expect(conflict.status, CspSolveStatus.infeasible);
      final recovered = await session.solve(assumptions: [
        for (var i = 0; i < names.length; i++)
          CspAssumption.equals(names[i], values[i]),
      ]);
      expect(recovered.status, CspSolveStatus.satisfied);
      expect(recovered.solution,
          {for (var i = 0; i < names.length; i++) names[i]: values[i]});
      expect(recovered.stats.matchingWorkspaceGrowths, 0);
      expect(session.rootPreparationCount, 1);
      session.close();
    });

    test('$label discards interrupted SCC scratch before retrying', () async {
      final names = [for (var i = 0; i < 6; i++) 'x$i'];
      final problem = Problem();
      for (final name in names) {
        problem.addRangeVariable(name, 0, 3000);
      }
      _distinct(problem, names, gcc, Iterable.generate(3001));
      final session = problem.compile().createSession();
      // This deterministic budget reaches graph analysis, after adjacency and
      // matching construction. A partial SCC array must never become a cache.
      final stopped =
          await session.solve(cancelToken: _PollingToken(300), maxDecisions: 0);
      expect(stopped.status, CspSolveStatus.cancelled);
      expect(stopped.stats.matchingSccPasses, 1);
      expect(stopped.stats.matchingWorkspaceGrowths, 1);
      expect(stopped.stats.matchingFixedPointSkips, 0);
      final retry = await session.solve(assumptions: [
        for (var i = 0; i < names.length; i++)
          CspAssumption.equals(names[i], 2995 + i),
      ]);
      expect(retry.status, CspSolveStatus.satisfied);
      expect(retry.solution,
          {for (var i = 0; i < names.length; i++) names[i]: 2995 + i});
      expect(retry.stats.matchingWorkspaceGrowths, 1);
      expect(session.rootPreparationCount, 2);
      session.close();
    });
  }

  test('overlapping allDifferent and GCC invalidate each other exactly',
      () async {
    final problem = Problem()
      ..addVariables(['a', 'b', 'c'], [0, 1, 2])
      ..addVariable('d', [0])
      ..addVariable('e', [1])
      ..addAllDifferent(['a', 'b', 'c'])
      ..addGccRanges([
        'c',
        'd',
        'e'
      ], {
        for (var value = 0; value < 3; value++) value: (min: 0, max: 1),
      });
    final session = problem.compile().createSession();
    final root = await session.solve(maxDecisions: 0);
    expect(root.status, CspSolveStatus.decisionLimit);
    expect(root.stats.matchingSccPasses, 3);
    expect(root.stats.matchingFixedPointSkips, 2);
    expect(root.stats.matchingWorkspaceGrowths, 2);
    for (final value in [0, 1]) {
      final result = await session.solve(
          assumptions: [CspAssumption.equals('a', value)], maxDecisions: 0);
      expect(result.status, CspSolveStatus.satisfied);
      expect(result.solution,
          {'a': value, 'b': 1 - value, 'c': 2, 'd': 0, 'e': 1});
      expect(result.stats.matchingWorkspaceGrowths, 0);
    }
    session.close();
  });

  test('matching work counters survive snapshots, serialization and restarts',
      () async {
    final stats = SolverStats(
      matchingSccPasses: 11,
      matchingWorkspaceGrowths: 2,
      matchingFixedPointSkips: 7,
    );
    final snapshot = stats.snapshot();
    stats.matchingSccPasses = 99;
    expect(snapshot.matchingSccPasses, 11);
    expect(SolverStats.fromMap(snapshot.toMap()).toMap(), snapshot.toMap());
    final legacy = SolverStats.fromMap({'decisions': 3});
    expect(legacy.matchingSccPasses, 0);
    expect(legacy.matchingWorkspaceGrowths, 0);
    expect(legacy.matchingFixedPointSkips, 0);

    final problem = Problem()
      ..addVariable('a', [0])
      ..addVariable('b', [0, 1])
      ..addVariable('c', [1, 2])
      ..addAllDifferent(['a', 'b', 'c']);
    expect(await problem.getSolutionWithRestarts(seed: 1),
        {'a': 0, 'b': 1, 'c': 2});
    expect(problem.lastStats!.matchingSccPasses, 1);
    expect(problem.lastStats!.matchingWorkspaceGrowths, 1);
    expect(problem.lastStats!.matchingFixedPointSkips, 1);
  });
}

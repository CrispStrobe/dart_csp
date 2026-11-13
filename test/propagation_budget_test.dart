import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// A deterministic cooperative signal, independent of wall-clock scheduling.
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

Problem _largeGlobal(bool gcc) {
  final problem = Problem();
  for (var i = 0; i < 6; i++) {
    problem.addRangeVariable('x$i', 0, 3000);
  }
  final variables = [for (var i = 0; i < 6; i++) 'x$i'];
  if (gcc) {
    problem.addGccRanges(variables, {
      for (var value = 0; value <= 3000; value++) value: (min: 0, max: 1),
    });
  } else {
    problem.addAllDifferent(variables);
  }
  return problem;
}

List<CspAssumption> _pins(int offset) => [
      for (var i = 0; i < 6; i++) CspAssumption.equals('x$i', offset + i),
    ];

void _expectPinned(CspSolveResult result, int offset) {
  expect(result.status, CspSolveStatus.satisfied);
  expect(result.solution, {for (var i = 0; i < 6; i++) 'x$i': offset + i});
}

void main() {
  test('generic support search polls inside a long n-ary task', () async {
    var checks = 0;
    final token = CancellationToken();
    final problem = Problem()
      ..addRangeVariable('x', 0, 1000)
      ..addVariable('y', [0])
      ..addVariable('z', [0]);
    problem.addConstraint(['x', 'y', 'z'], (Map<String, dynamic> values) {
      if (++checks == 10) token.cancel();
      return true;
    });
    final session = problem.compile().createSession();
    expect((await session.solve(cancelToken: token)).status,
        CspSolveStatus.cancelled);
    expect(checks, lessThan(300));
    final retry = await session
        .solve(assumptions: [const CspAssumption.equals('x', 1000)]);
    expect(retry.solution, {'x': 1000, 'y': 0, 'z': 0});
    session.close();
  });

  for (final gcc in [false, true]) {
    final label = gcc ? 'GCC' : 'allDifferent';

    test('$label cancels within root construction and retries safely',
        () async {
      final session = _largeGlobal(gcc).compile().createSession();
      final token = _PollingToken(30);
      final stopped = await session.solve(cancelToken: token, maxDecisions: 0);
      expect(stopped.status, CspSolveStatus.cancelled);
      expect(stopped.stats.decisions, 0);
      expect(stopped.stats.backtracks, 0);
      expect(session.rootPreparationCount, 1);
      if (gcc) {
        expect(stopped.stats.gccPropagations, 1);
        // This signal fires during adjacency construction, before flow nodes
        // are counted. Merely checking between constraints would miss it.
        expect(stopped.stats.gccMaxFlowNodes, 0);
      }
      _expectPinned(await session.solve(assumptions: _pins(10)), 10);
      expect(session.rootPreparationCount, 2);
      _expectPinned(await session.solve(assumptions: _pins(2990)), 2990);
      session.close();
    });

    test('$label cancels a prepared query without poisoning restored caches',
        () async {
      final session = _largeGlobal(gcc).compile().createSession();
      expect((await session.solve(maxDecisions: 0)).status,
          CspSolveStatus.decisionLimit);
      expect(session.rootPreparationCount, 1);
      final token = _PollingToken(30);
      final stopped = await session.solve(
        assumptions: [const CspAssumption.equals('x0', 3000)],
        cancelToken: token,
        maxDecisions: 0,
      );
      expect(stopped.status, CspSolveStatus.cancelled);
      expect(stopped.reusedRoot, isTrue);
      expect(stopped.stats.backtracks, 0);
      _expectPinned(await session.solve(assumptions: _pins(0)), 0);
      _expectPinned(await session.solve(assumptions: _pins(2995)), 2995);
      expect(session.rootPreparationCount, 1);
      session.close();
    });

    test('$label interruption never becomes an LCG conflict', () async {
      for (final iterative in [false, true]) {
        final problem = _largeGlobal(gcc);
        final stopped = await problem.solveWithLcg(
          cancelToken: _PollingToken(30),
          useIterativeCdcl: iterative,
        );
        expect(stopped, 'FAILURE');
        expect(problem.lastStats!.decisions, 0);
        expect(problem.lastStats!.backtracks, 0);
        expect(problem.lastStats!.learnedClauses, 0);
      }
    });
  }
}

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

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

Problem _twoIndependentVariables() =>
    Problem()..addVariables(['x', 'y'], [0, 1]);

void _expectNoConflictWork(SolverStats stats, List<PropagationEvent> events) {
  expect(stats.backtracks, 0);
  expect(stats.backjumps, 0);
  expect(stats.learnedClauses, 0);
  expect(stats.lcgAnalysisCalls, 0);
  expect(
      events.where((event) =>
          event.kind == PropagationEventKind.backtrack ||
          event.kind == PropagationEventKind.backjump ||
          event.kind == PropagationEventKind.domainWipeout ||
          event.kind == PropagationEventKind.solution),
      isEmpty);
}

void main() {
  for (final cbj in [false, true]) {
    final label = cbj ? 'CBJ' : 'plain';
    for (final mode in ['first', 'all', 'minimize', 'maximize']) {
      test('$label $mode stops local and descendant cancellation cleanly',
          () async {
        for (final stopDepth in [0, 1]) {
          final problem = _twoIndependentVariables();
          final token = CancellationToken();
          final events = <PropagationEvent>[];
          problem.setOptions(onPropagation: (event) {
            events.add(event);
            if (event.kind == PropagationEventKind.decision &&
                event.depth == stopDepth) {
              token.cancel();
            }
          });
          switch (mode) {
            case 'first':
              final result = await problem.getSolutionDetailed(
                  cancelToken: token, enableConflictBackjumping: cbj);
              expect(result.status, MixedSolveStatus.cancelled);
              expect(result.solution, isNull);
            case 'all':
              final result = await problem
                  .getSolutions(
                      cancelToken: token, enableConflictBackjumping: cbj)
                  .toList();
              expect(result, isEmpty);
            case 'minimize':
              final result = await problem.minimize('x',
                  cancelToken: token, enableConflictBackjumping: cbj);
              expect(result, 'FAILURE');
            case 'maximize':
              final result = await problem.maximize('x',
                  cancelToken: token, enableConflictBackjumping: cbj);
              expect(result, 'FAILURE');
          }
          expect(token.isCancelled, isTrue);
          expect(problem.lastStats!.decisions, stopDepth + 1);
          _expectNoConflictWork(problem.lastStats!, events);
        }
      });
    }

    test('$label stops when cancellation arrives during propagation', () async {
      final problem = _twoIndependentVariables()
        ..addConstraint(['x', 'y'], (dynamic x, dynamic y) => x != y);
      final token = CancellationToken();
      final events = <PropagationEvent>[];
      problem.setOptions(onPropagation: (event) {
        events.add(event);
        if (event.kind == PropagationEventKind.prune) token.cancel();
      });
      final result = await problem.getSolutionDetailed(
          cancelToken: token, enableConflictBackjumping: cbj);
      expect(result.status, MixedSolveStatus.cancelled);
      expect(events.any((event) => event.kind == PropagationEventKind.prune),
          isTrue);
      _expectNoConflictWork(result.stats, events);
    });

    test('$label stops when the stream consumer cancels after a solution',
        () async {
      final problem = _twoIndependentVariables();
      final token = CancellationToken();
      final solutions = <Map<String, dynamic>>[];
      await for (final solution in problem.getSolutions(
          cancelToken: token, enableConflictBackjumping: cbj)) {
        solutions.add(solution);
        token.cancel();
      }
      expect(solutions, [
        {'x': 0, 'y': 0}
      ]);
      _expectNoConflictWork(problem.lastStats!, const []);
    });

    test('$label still counts real conflicts', () async {
      // Two colors cannot satisfy all three inequalities of an odd cycle.
      final problem = Problem()..addVariables(['x', 'y', 'z'], [0, 1]);
      for (final pair in [
        ['x', 'y'],
        ['y', 'z'],
        ['z', 'x']
      ]) {
        problem.addConstraint(pair, (dynamic x, dynamic y) => x != y);
      }
      final result =
          await problem.getSolutionDetailed(enableConflictBackjumping: cbj);
      expect(result.status, MixedSolveStatus.infeasible);
      expect(result.stats.backtracks, greaterThan(0));
    });
  }

  test('recursive LCG aborts local and descendant frames without conflict work',
      () async {
    for (final stopCheckpoint in [1, 2]) {
      final problem = _twoIndependentVariables();
      final token = CancellationToken();
      var checkpoints = 0;
      problem.setOptions(callback: (_, __) {
        if (++checkpoints == stopCheckpoint) token.cancel();
      });
      final result = await problem.solveWithLcg(
          cancelToken: token, useIterativeCdcl: false);
      expect(result, 'FAILURE');
      expect(checkpoints, stopCheckpoint);
      _expectNoConflictWork(problem.lastStats!, const []);
    }
  });

  test('SAC stops probing a symbolic range immediately after interruption',
      () async {
    final problem = Problem()..addRangeVariable('x', 0, 20000);
    final session = problem
        .compile()
        .createSession(consistency: ConsistencyLevel.singletonArcConsistency);
    final result = await session.solve(cancelToken: _PollingToken(7));
    expect(result.status, CspSolveStatus.cancelled);
    // A cancelled probe cannot be counted as a failed test for every remaining
    // value. The moderate range makes a regression fail safely on work count.
    expect(result.stats.propagations, lessThanOrEqualTo(3));
    expect(result.stats.decisions, 0);
    _expectNoConflictWork(result.stats, const []);
    session.close();
  });

  test('SAC interrupted root restores untested values before retry', () async {
    final problem = Problem()..addRangeVariable('x', 0, 4);
    final session = problem
        .compile()
        .createSession(consistency: ConsistencyLevel.singletonArcConsistency);
    final interrupted = await session.solve(cancelToken: _PollingToken(7));
    expect(interrupted.status, CspSolveStatus.cancelled);
    final retried =
        await session.solve(assumptions: [const CspAssumption.equals('x', 4)]);
    expect(retried.status, CspSolveStatus.satisfied);
    expect(retried.solution, {'x': 4});
    expect(session.rootPreparationCount, 2);
    session.close();
  });
}

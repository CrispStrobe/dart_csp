import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  test('LCG cancellation during value scoring cannot learn a false conflict',
      () async {
    for (final iterative in [false, true]) {
      final token = CancellationToken();
      var checks = 0;
      final problem = Problem()
        ..addVariables(['x', 'y'], List.generate(32, (i) => i));
      problem.addConstraint(['x', 'y'], (dynamic x, dynamic y) {
        if (++checks == 100) token.cancel();
        return true;
      });
      expect(
          await problem.solveWithLcg(
              useIterativeCdcl: iterative, cancelToken: token),
          'FAILURE');
      expect(checks, lessThan(500));
      expect(problem.lastStats!.learnedClauses, 0);
    }
  });

  test('positive binary witnesses avoid repeated predicate evaluations',
      () async {
    var checks = 0;
    final problem = Problem()
      ..addVariables(['x', 'y'], List.generate(64, (i) => i));
    problem.addConstraint(['x', 'y'], (dynamic x, dynamic y) {
      checks++;
      return x == 0 || x == y;
    });
    final session = problem.compile().createSession();
    expect(
        (await session.solve(assumptions: [const CspAssumption.equals('x', 0)]))
            .isSatisfied,
        isTrue);
    checks = 0;
    for (var query = 0; query < 5; query++) {
      final result = await session
          .solve(assumptions: [const CspAssumption.equals('x', 0)]);
      expect(result.solution!['x'], 0);
    }
    // Original semantic validation still invokes both directional predicates.
    // Checking supports afresh would require at least 64 calls per query.
    expect(checks, lessThan(20));
    expect(session.rootPreparationCount, 1);
  });

  test('binary witnesses repair after shrink and survive restored domains',
      () async {
    final random = Random(20261113);
    for (var sample = 0; sample < 60; sample++) {
      final relation = [
        for (var x = 0; x < 5; x++)
          [for (var y = 0; y < 5; y++) random.nextBool()],
      ];
      final xs = List.generate(5, (i) => i)..shuffle(random);
      final ys = List.generate(5, (i) => i)..shuffle(random);
      final problem = Problem()
        ..addVariable('x', xs)
        ..addVariable('y', ys);
      problem.addConstraint(
          ['x', 'y'], (dynamic x, dynamic y) => relation[x as int][y as int]);
      final expected = <String>{
        for (var x = 0; x < 5; x++)
          for (var y = 0; y < 5; y++)
            if (relation[x][y]) '$x,$y',
      };
      final actual = {
        for (final solution in await problem.getAllSolutions())
          '${solution['x']},${solution['y']}',
      };
      expect(actual, expected, reason: 'full enumeration $sample');
      final session = problem.compile().createSession();
      for (var query = 0; query < 8; query++) {
        final x = random.nextInt(5), y = random.nextInt(5);
        final result = await session.solve(assumptions: [
          CspAssumption.equals('x', x),
          if (query.isEven) CspAssumption.equals('y', y),
        ]);
        final feasible =
            query.isEven ? relation[x][y] : relation[x].contains(true);
        expect(result.isSatisfied, feasible,
            reason: 'model=$sample query=$query');
        if (feasible) {
          expect(result.solution!['x'], x);
          expect(relation[x][result.solution!['y'] as int], isTrue);
        }
      }
      session.close();
    }
  });

  test('null is a valid cached support rather than an absence sentinel',
      () async {
    final problem = Problem()
      ..addVariable('x', [null, 'value'])
      ..addVariable('y', ['a', 'b']);
    problem.addConstraint(
        ['x', 'y'], (dynamic x, dynamic y) => x == null || y == 'b');
    final session = problem.compile().createSession();
    for (var i = 0; i < 3; i++) {
      expect(
          (await session
                  .solve(assumptions: [const CspAssumption.equals('y', 'a')]))
              .solution!['x'],
          isNull);
      expect(
          (await session.solve(
                  assumptions: [const CspAssumption.equals('x', 'value')]))
              .solution!['y'],
          'b');
    }
  });

  test('randomized first choice stays lazy above the 32-bit random bound',
      () async {
    final problem = Problem()..addRangeVariable('x', 0, 10000000000);
    final first = await problem.getSolutionWithRestarts(
        seed: 19, maxRestarts: 1) as Map<String, dynamic>;
    final second = await problem.getSolutionWithRestarts(
        seed: 19, maxRestarts: 1) as Map<String, dynamic>;
    expect(first, second);
    expect(first['x'], inInclusiveRange(0, 10000000000));
    expect(problem.lastStats!.decisions, 1);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('cancellation within a long binary pass preserves a reusable root',
      () async {
    final token = CancellationToken();
    var checks = 0;
    final problem = Problem()
      ..addVariables(['x', 'y'], List.generate(256, (i) => i));
    problem.addConstraint(['x', 'y'], (dynamic x, dynamic y) {
      if (++checks == 10) token.cancel();
      return x != y;
    });
    final session = problem.compile().createSession();
    final cancelled = await session.solve(cancelToken: token);
    expect(cancelled.status, CspSolveStatus.cancelled);
    expect(checks, lessThan(300));
    final retry = await session.solve(assumptions: [
      const CspAssumption.equals('x', 0),
      const CspAssumption.equals('y', 1),
    ]);
    expect(retry.solution, {'x': 0, 'y': 1});
  });
}

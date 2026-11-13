import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('compiled finite-domain sessions', () {
    test('rejected candidates do not masquerade as a decision limit', () async {
      final fixed = (Problem()..addVariable('x', [double.infinity]))
          .compile()
          .createSession();
      final invalid = await fixed.solve();
      expect(invalid.status, CspSolveStatus.invalidCandidate);
      expect(invalid.stats.decisions, 0);
      expect(invalid.diagnostic, contains('not finite'));
      fixed.close();

      final session = (Problem()..addVariable('x', [double.infinity, 1]))
          .compile()
          .createSession();
      expect((await session.solve()).status, CspSolveStatus.invalidCandidate);
      final limited = await session.solve(maxDecisions: 0);
      expect(limited.status, CspSolveStatus.decisionLimit);
      expect(limited.diagnostic, isNull);
      final valid = await session
          .solve(assumptions: [const CspAssumption.equals('x', 1)]);
      expect(valid.status, CspSolveStatus.satisfied);
      expect(valid.solution, {'x': 1});
      expect(valid.diagnostic, isNull);
      expect(session.rootPreparationCount, 1);
      session.close();
    });

    test('equal numeric assumptions preserve the declared value type',
        () async {
      for (final problem in [
        Problem()..addVariable('x', [1, 2, 3]),
        Problem()..addVariable('x', [3, 1, 2]),
        Problem()..addRangeVariable('x', 0, 1000000000),
      ]) {
        final result = await problem
            .compile()
            .createSession()
            .solve(assumptions: [const CspAssumption.equals('x', 1.0)]);
        expect(result.status, CspSolveStatus.satisfied);
        expect(result.solution!['x'], isA<int>());
        expect(result.solution!['x'], 1);
      }
    });

    test('prepared root and stable indexes survive different assumptions',
        () async {
      final problem = Problem()
        ..addVariables(['x', 'y'], [1, 2, 3])
        ..addAllDifferent(['x', 'y'])
        ..addLinearEquals(['x', 'y'], [1, 1], 4);
      final compiled = problem.compile();
      expect(compiled.variableNames, ['x', 'y']);
      expect(compiled.variableIds, {'x': 0, 'y': 1});
      expect(compiled.constraintIdsByVariable['x'], isNotEmpty);
      expect(() => compiled.variableIds['z'] = 2, throwsUnsupportedError);
      final session = compiled.createSession();
      final first = await session
          .solve(assumptions: [const CspAssumption.equals('x', 1)]);
      expect(first.status, CspSolveStatus.satisfied);
      expect(first.solution, {'x': 1, 'y': 3});
      expect(first.reusedRoot, isFalse);

      final impossible = await session
          .solve(assumptions: [const CspAssumption.equals('x', 2)]);
      expect(impossible.status, CspSolveStatus.infeasible);
      expect(impossible.reusedRoot, isTrue);
      final last = await session
          .solve(assumptions: [const CspAssumption.equals('x', 3)]);
      expect(last.solution, {'x': 3, 'y': 1});
      expect(session.rootPreparationCount, 1);
      expect(first.solution, {'x': 1, 'y': 3});
      expect(() => first.solution!['x'] = 9, throwsUnsupportedError);
    });

    test('nested scopes restore equality and compact range assumptions',
        () async {
      final session = (Problem()
            ..addRangeVariable('x', 0, 1000000000)
            ..addLinearGeq(['x'], [1], 10))
          .compile()
          .createSession();
      session.assumeBounds('x', lower: 20, upper: 30);
      expect((await session.solve()).solution, {'x': 20});
      session.push();
      session.assumeEquals('x', 25);
      expect((await session.solve()).solution, {'x': 25});
      session.pop();
      expect((await session.solve()).solution, {'x': 20});
      session.clearAssumptions();
      expect((await session.solve()).solution, {'x': 10});
      expect(session.rootPreparationCount, 1);
      expect(session.pop, throwsStateError);
    });

    test('contradictory and rejected assumptions leave the root intact',
        () async {
      final session =
          (Problem()..addRangeVariable('x', 0, 5)).compile().createSession();
      expect(
          (await session.solve(assumptions: [
            const CspAssumption.bounds('x', lower: 4, upper: 2),
          ]))
              .status,
          CspSolveStatus.infeasible);
      expect(
          (await session.solve(assumptions: [
            const CspAssumption.equals('x', 1),
            const CspAssumption.equals('x', 2),
          ]))
              .status,
          CspSolveStatus.infeasible);
      await expectLater(
          session
              .solve(assumptions: [const CspAssumption.equals('unknown', 1)]),
          throwsArgumentError);
      expect((await session.solve()).solution, {'x': 0});
      expect(session.rootPreparationCount, 1);
    });

    test('builder edits require recompilation and do not alter a snapshot',
        () async {
      final problem = Problem()..addRangeVariable('x', 0, 10);
      final compiled = problem.compile();
      problem.addLinearGeq(['x'], [1], 7);
      expect((await compiled.createSession().solve()).solution, {'x': 0});
      expect(
          (await problem.compile().createSession().solve()).solution, {'x': 7});
    });

    test('declared domains and typed metadata are copied by compilation',
        () async {
      final domain = <dynamic>[1, 2, 3];
      final coefficients = <num>[1];
      final names = ['x'];
      final compiled = CompiledCspModel(CspProblem(
        variables: {'x': domain},
        naryConstraints: [
          NaryConstraint(
              vars: names,
              predicate: (_) => false, // typed semantics are authoritative
              linearSpec:
                  LinearSpec(coeffs: coefficients, op: LinearOp.eq, bound: 2)),
        ],
      ));
      domain.clear();
      coefficients[0] = 100;
      names[0] = 'changed';
      expect((await compiled.createSession().solve()).solution, {'x': 2});
    });

    test('infeasible permanent root is cached separately from query failure',
        () async {
      final session = (Problem()
            ..addVariables(['x', 'y', 'z'], [1, 2])
            ..addAllDifferent(['x', 'y', 'z']))
          .compile()
          .createSession();
      expect((await session.solve()).status, CspSolveStatus.infeasible);
      final again = await session.solve();
      expect(again.status, CspSolveStatus.infeasible);
      expect(again.reusedRoot, isTrue);
      expect(again.stats.propagations, 0);
      expect(session.rootPreparationCount, 1);
    });

    test('cancellation, deadlines, and decision limits are distinct', () async {
      final session = (Problem()..addVariables(['x', 'y'], [0, 1]))
          .compile()
          .createSession();
      final token = CancellationToken()..cancel();
      expect((await session.solve(cancelToken: token)).status,
          CspSolveStatus.cancelled);
      expect((await session.solve(timeLimit: Duration.zero)).status,
          CspSolveStatus.timeLimit);
      expect(session.rootPreparationCount, 0);
      expect((await session.solve(maxDecisions: 1)).status,
          CspSolveStatus.decisionLimit);
      final completed = await session.solve(maxDecisions: 2);
      expect(completed.status, CspSolveStatus.satisfied);
      expect(completed.solution, {'x': 0, 'y': 0});
      expect(completed.stats.decisions, 2);
      expect(session.rootPreparationCount, 1);
    });

    test('a root solution needs no decision budget', () async {
      final session =
          (Problem()..addVariable('x', [3])).compile().createSession();
      expect((await session.solve(maxDecisions: 0)).solution, {'x': 3});
    });

    test('a session rejects overlapping queries and mutations', () async {
      final session = (Problem()..addVariables(['x', 'y'], [0, 1]))
          .compile()
          .createSession();
      final pending = session.solve();
      expect(() => session.assumeEquals('x', 1), throwsStateError);
      expect(session.close, throwsStateError);
      await expectLater(session.solve(), throwsStateError);
      expect((await pending).status, CspSolveStatus.satisfied);
      session.close();
      expect(session.isClosed, isTrue);
      await expectLater(session.solve(), throwsStateError);
    });

    test('exceptions restore the query trail before the next solve', () async {
      var injectFailure = false;
      final problem = Problem()
        ..addVariables(['x', 'y'], [0, 1])
        ..addConstraint(['x', 'y'], (dynamic x, dynamic y) {
          if (injectFailure) throw StateError('controlled predicate failure');
          return x != y;
        });
      final session = problem.compile().createSession();
      expect((await session.solve()).status, CspSolveStatus.satisfied);
      injectFailure = true;
      await expectLater(
          session.solve(assumptions: [const CspAssumption.equals('x', 1)]),
          throwsStateError);
      injectFailure = false;
      expect(
          (await session
                  .solve(assumptions: [const CspAssumption.equals('x', 0)]))
              .solution,
          {'x': 0, 'y': 1});
      expect(session.rootPreparationCount, 1);
    });

    test('independent sessions can query the same compiled model concurrently',
        () async {
      final compiled = (Problem()
            ..addVariables(['x', 'y'], [1, 2, 3])
            ..addAllDifferent(['x', 'y']))
          .compile();
      final results = await Future.wait([
        for (final value in [1, 2, 3])
          compiled
              .createSession()
              .solve(assumptions: [CspAssumption.equals('x', value)]),
      ]);
      for (var i = 0; i < results.length; i++) {
        expect(results[i].status, CspSolveStatus.satisfied);
        expect(results[i].solution!['x'], i + 1);
        expect(results[i].solution!['y'], isNot(i + 1));
      }
    });

    test('40 edit queries match an independent Cartesian-product oracle',
        () async {
      final names = ['a', 'b', 'c', 'd'];
      final session = (Problem()
            ..addVariables(names, [1, 2, 3, 4, 5])
            ..addAllDifferent(names)
            ..addLinearEquals(names, [1, 1, 1, 1], 10))
          .compile()
          .createSession();
      final oracle = <List<int>>[
        for (var a = 1; a <= 5; a++)
          for (var b = 1; b <= 5; b++)
            for (var c = 1; c <= 5; c++)
              for (var d = 1; d <= 5; d++)
                if ({a, b, c, d}.length == 4 && a + b + c + d == 10)
                  [a, b, c, d],
      ];
      final random = Random(82374);
      for (var query = 0; query < 40; query++) {
        final a = random.nextInt(5) + 1;
        final upperB = random.nextInt(5) + 1;
        final expected = {
          for (final values in oracle)
            if (values[0] == a && values[1] <= upperB) values.join(','),
        };
        final result = await session.solve(assumptions: [
          CspAssumption.equals('a', a),
          CspAssumption.bounds('b', upper: upperB),
        ]);
        expect(
            result.status,
            expected.isEmpty
                ? CspSolveStatus.infeasible
                : CspSolveStatus.satisfied,
            reason: 'query=$query a=$a upperB=$upperB');
        if (expected.isNotEmpty) {
          final key =
              [for (final name in names) result.solution![name]].join(',');
          expect(expected.contains(key), isTrue);
        }
      }
      expect(session.rootPreparationCount, 1);
    });

    test('continuous models are explicitly unsupported by finite sessions', () {
      final problem = Problem()..addFloatVariable('x', 0, 1);
      expect(problem.compile, throwsUnsupportedError);
    });
  });

  group('compiled result validation uses tagged semantics', () {
    final cases = <({
      String name,
      Map<String, List<dynamic>> vars,
      NaryConstraint constraint
    })>[
      (
        name: 'allDifferent',
        vars: {
          'a': [1],
          'b': [2],
          'c': [3]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'], predicate: (_) => false, allDifferent: true),
      ),
      (
        name: 'gcc',
        vars: {
          'a': [1],
          'b': [2],
          'c': [3]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'],
            predicate: (_) => false,
            gccSpec: GccSpec(bounds: {
              1: (min: 1, max: 1),
              2: (min: 1, max: 1),
              3: (min: 1, max: 1),
            })),
      ),
      (
        name: 'regular',
        vars: {
          'a': [1],
          'b': [2],
          'c': [3]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'],
            predicate: (_) => false,
            regularDfa: Dfa(numStates: 4, start: 0, accepting: {
              3
            }, transitions: {
              0: {1: 1},
              1: {2: 2},
              2: {3: 3},
            })),
      ),
      (
        name: 'circuit',
        vars: {
          'a': [1],
          'b': [2],
          'c': [0]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'], predicate: (_) => false, circuit: true),
      ),
      (
        name: 'subcircuit',
        vars: {
          'a': [0],
          'b': [2],
          'c': [1]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'], predicate: (_) => false, subcircuit: true),
      ),
      (
        name: 'cumulative',
        vars: {
          'a': [0],
          'b': [1],
          'c': [2]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'],
            predicate: (_) => false,
            cumulativeSpec: CumulativeSpec(
                durations: [1, 1, 1], demands: [1, 1, 1], capacity: 1)),
      ),
      (
        name: 'clause',
        vars: {
          'a': [1],
          'b': [0],
          'c': [0]
        },
        constraint: NaryConstraint(
            vars: ['a', 'b', 'c'],
            predicate: (_) => false,
            clauseSpec: ClauseSpec(literals: [
              (varName: 'a', positive: true),
              (varName: 'b', positive: true),
              (varName: 'c', positive: true),
            ])),
      ),
      (
        name: 'diffN',
        vars: {
          'x0': [0],
          'x1': [1],
          'y0': [0],
          'y1': [0]
        },
        constraint: NaryConstraint(
            vars: ['x0', 'x1', 'y0', 'y1'],
            predicate: (_) => false,
            diffNSpec: DiffNSpec(widths: [1, 1], heights: [1, 1])),
      ),
    ];
    for (final example in cases) {
      test(example.name, () async {
        final compiled = CompiledCspModel(CspProblem(
            variables: example.vars, naryConstraints: [example.constraint]));
        final result = await compiled.createSession().solve();
        expect(result.status, CspSolveStatus.satisfied,
            reason: result.diagnostic);
      });
    }
  });
}

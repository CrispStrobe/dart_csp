import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.getSolutionWithActivity', () {
    test('returns a valid solution on a basic feasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithActivity();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C']}, equals({1, 2, 3}));
    });

    test('returns FAILURE on an infeasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithActivity();
      expect(result, equals('FAILURE'));
    });

    test('handles classic constraint-heavy puzzles (6-queens)', () async {
      final queens = [for (var i = 0; i < 6; i++) 'Q$i'];
      final p = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5, 6])
        ..addAllDifferent(queens);
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          final d = (j - i).abs();
          p.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      final result = await p.getSolutionWithActivity();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      final values = queens.map((q) => s[q] as int).toList();
      expect(values.toSet().length, equals(6),
          reason: 'all queens in distinct columns');
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          expect((values[i] - values[j]).abs(), isNot(equals(j - i)),
              reason: 'queens $i,$j on the same diagonal');
        }
      }
    });

    test('agrees with MRV solver on a problem with a unique answer', () async {
      final pMrv = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final viaMrv = await pMrv.getSolution();

      final pVsids = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final viaVsids = await pVsids.getSolutionWithActivity();

      expect(viaVsids, equals(viaMrv));
    });

    test('composes with forward checking', () async {
      final p = Problem()
        ..addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4])
        ..addAllDifferent(['X', 'Y', 'Z']);
      final result = await p.getSolutionWithActivity(
        consistency: ConsistencyLevel.forwardChecking,
      );
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['X'], s['Y'], s['Z']}.length, equals(3));
    });

    test('composes with conflict-directed backjumping', () async {
      final queens = [for (var i = 0; i < 5; i++) 'Q$i'];
      final p = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5])
        ..addAllDifferent(queens);
      for (var i = 0; i < 5; i++) {
        for (var j = i + 1; j < 5; j++) {
          final d = (j - i).abs();
          p.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      final result = await p.getSolutionWithActivity(
        enableConflictBackjumping: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('engages propagation: lastStats reports work done', () async {
      // 8-queens with allDifferent: guaranteed to exercise the
      // specialized propagator and the per-variable activity bumps.
      final queens = [for (var i = 0; i < 8; i++) 'Q$i'];
      final p = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5, 6, 7, 8])
        ..addAllDifferent(queens);
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
          final d = (j - i).abs();
          p.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      final result = await p.getSolutionWithActivity();
      expect(result, isA<Map<String, dynamic>>());
      expect(CSP.lastStats, isNotNull);
      // Some propagation must have happened on a problem this size.
      expect(CSP.lastStats!.naryRevises + CSP.lastStats!.binaryRevises,
          greaterThan(0));
    });

    test('zero-conflict problem reduces to MRV-like behavior', () async {
      // No propagation conflicts on this trivially-feasible instance,
      // so all activities stay at 0.0 and the picker should return a
      // valid solution without errors. Verifies the absent-key path
      // through `_varActivity[v] ?? 0.0`.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithActivity();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });
  });

  group('useVsids flag on getSolutionWithRestarts', () {
    test('composes with restarts: still finds a solution', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolutionWithRestarts(
        seed: 5,
        useVsids: true,
      );
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('infeasible + restarts + VSIDS → FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithRestarts(
        seed: 9,
        useVsids: true,
        maxRestarts: 5,
      );
      expect(result, equals('FAILURE'));
    });

    test('VSIDS + dom/wdeg both on: VSIDS takes precedence, still solves',
        () async {
      // When both heuristic flags are set, VSIDS wins the picker
      // (documented behavior). Verify nothing breaks and a solution
      // is still returned.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithRestarts(
        seed: 1,
        useVsids: true,
        useDomWdeg: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });
  });

  group('CSP.solveWithActivity (static entry point)', () {
    test('returns a valid solution on a basic feasible problem', () async {
      final csp = CspProblem(
        variables: {
          'A': [1, 2, 3],
          'B': [1, 2, 3],
        },
        constraints: [
          BinaryConstraint('A', 'B', (dynamic a, dynamic b) => a != b),
          BinaryConstraint('B', 'A', (dynamic a, dynamic b) => a != b),
        ],
      );
      final result = await CSP.solveWithActivity(csp);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });
  });
}

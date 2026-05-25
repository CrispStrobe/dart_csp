import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.getSolutionWithImpact', () {
    test('returns a valid solution on a basic feasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithImpact();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C']}, equals({1, 2, 3}));
    });

    test('returns FAILURE on an infeasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithImpact();
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
      final result = await p.getSolutionWithImpact();
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

      final pImpact = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final viaImpact = await pImpact.getSolutionWithImpact();

      expect(viaImpact, equals(viaMrv));
    });

    test('composes with forward checking', () async {
      final p = Problem()
        ..addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4])
        ..addAllDifferent(['X', 'Y', 'Z']);
      final result = await p.getSolutionWithImpact(
        consistency: ConsistencyLevel.forwardChecking,
      );
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['X'], s['Y'], s['Z']}.length, equals(3));
    });

    test('composes with singleton-arc-consistency preprocessing', () async {
      // Canonical SAC-only-detectable infeasibility: AC-consistent at
      // the root but no value of x has a consistent extension. With
      // SAC, infeasibility is proven without entering search.
      final p = Problem()
        ..addVariables(['x', 'y', 'z'], [1, 2])
        ..addStringConstraint('x == y')
        ..addStringConstraint('y == z')
        ..addStringConstraint('x != z');
      final result = await p.getSolutionWithImpact(
        consistency: ConsistencyLevel.singletonArcConsistency,
      );
      expect(result, equals('FAILURE'));
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
      final result = await p.getSolutionWithImpact(
        enableConflictBackjumping: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('engages propagation: lastStats reports work done', () async {
      // 8-queens with allDifferent: guaranteed to exercise the
      // specialized propagator and record per-decision impact.
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
      final result = await p.getSolutionWithImpact();
      expect(result, isA<Map<String, dynamic>>());
      expect(CSP.lastStats, isNotNull);
      // Some propagation must have happened on a problem this size.
      expect(CSP.lastStats!.naryRevises + CSP.lastStats!.binaryRevises,
          greaterThan(0));
    });

    test('zero-conflict problem reduces to MRV-like behavior', () async {
      // Trivially-feasible problem: every decision succeeds. Verifies
      // the success path of [_observeImpact] (no failures recorded)
      // and the absent-key fallbacks in [_pickByImpact].
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithImpact();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });

    test('decision count is positive on a non-trivial problem', () async {
      // Verifies the picker actually drives search (not just the
      // root assignment shortcut). 8-queens guarantees > 1 decision.
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
      final result = await p.getSolutionWithImpact();
      expect(result, isA<Map<String, dynamic>>());
      expect(CSP.lastStats!.decisions, greaterThan(0));
    });
  });

  group('useImpact flag on getSolutionWithRestarts', () {
    test('composes with restarts: still finds a solution', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolutionWithRestarts(
        seed: 5,
        useImpact: true,
      );
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('infeasible + restarts + impact → FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithRestarts(
        seed: 9,
        useImpact: true,
        maxRestarts: 5,
      );
      expect(result, equals('FAILURE'));
    });

    test('impact takes precedence over VSIDS and dom/wdeg', () async {
      // When all three flags are set, the picker dispatch order
      // (impact > vsids > domWdeg) routes through _pickByImpact.
      // Verify nothing breaks and a solution is still returned.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithRestarts(
        seed: 1,
        useImpact: true,
        useVsids: true,
        useDomWdeg: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });
  });

  group('CSP.solveWithImpact (static entry point)', () {
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
      final result = await CSP.solveWithImpact(csp);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });

    test('failed propagation contributes impact 1.0 — still solvable',
        () async {
      // n-queens forces many propagation failures. The impact-1.0
      // contribution path is hit; the run must still complete.
      final queens = [for (var i = 0; i < 7; i++) 'Q$i'];
      final p = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5, 6, 7])
        ..addAllDifferent(queens);
      for (var i = 0; i < 7; i++) {
        for (var j = i + 1; j < 7; j++) {
          final d = (j - i).abs();
          p.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      final result = await p.getSolutionWithImpact();
      expect(result, isA<Map<String, dynamic>>());
    });
  });

  group('Picker correctness invariants', () {
    test('IBS solves SEND + MORE = MONEY (linear encoding)', () async {
      // Classic stress-test problem — too big to fall back to plain
      // MRV, so the impact-driven picker has to do real work.
      const letters = ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'];
      final p = Problem();
      for (final l in letters) {
        p.addVariable(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      }
      p
        ..addAllDifferent(letters)
        ..addStringConstraint('S != 0')
        ..addStringConstraint('M != 0')
        ..addLinearEquals(
          letters,
          [1000, 91, -90, 1, -9000, -900, 10, -1],
          0,
        );
      final result = await p.getSolutionWithImpact();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      // Canonical solution: S=9 E=5 N=6 D=7 M=1 O=0 R=8 Y=2.
      expect(s['S'], equals(9));
      expect(s['E'], equals(5));
      expect(s['N'], equals(6));
      expect(s['D'], equals(7));
      expect(s['M'], equals(1));
      expect(s['O'], equals(0));
      expect(s['R'], equals(8));
      expect(s['Y'], equals(2));
    });
  });
}

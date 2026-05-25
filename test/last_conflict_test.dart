import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.getSolutionWithLastConflict', () {
    test('returns a valid solution on a basic feasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithLastConflict();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C']}, equals({1, 2, 3}));
    });

    test('returns FAILURE on an infeasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithLastConflict();
      expect(result, equals('FAILURE'));
    });

    test('handles classic constraint-heavy puzzles (8-queens)', () async {
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
      final result = await p.getSolutionWithLastConflict();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      final values = queens.map((q) => s[q] as int).toList();
      expect(values.toSet().length, equals(8),
          reason: 'all queens in distinct columns');
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
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

      final pLc = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final viaLc = await pLc.getSolutionWithLastConflict();

      expect(viaLc, equals(viaMrv));
    });

    test('composes with dom/wdeg as the underlying picker', () async {
      // Canonical LC deployment: LC + dom/wdeg.
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
      final result = await p.getSolutionWithLastConflict(useDomWdeg: true);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('composes with VSIDS as the underlying picker', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolutionWithLastConflict(useVsids: true);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('composes with IBS as the underlying picker', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithLastConflict(useImpact: true);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C']}, equals({1, 2, 3}));
    });

    test('composes with forward checking', () async {
      final p = Problem()
        ..addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4])
        ..addAllDifferent(['X', 'Y', 'Z']);
      final result = await p.getSolutionWithLastConflict(
        consistency: ConsistencyLevel.forwardChecking,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('composes with singleton-arc-consistency preprocessing', () async {
      final p = Problem()
        ..addVariables(['x', 'y', 'z'], [1, 2])
        ..addStringConstraint('x == y')
        ..addStringConstraint('y == z')
        ..addStringConstraint('x != z');
      final result = await p.getSolutionWithLastConflict(
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
      final result = await p.getSolutionWithLastConflict(
        enableConflictBackjumping: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('engages propagation: lastStats reports work done', () async {
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
      final result = await p.getSolutionWithLastConflict();
      expect(result, isA<Map<String, dynamic>>());
      expect(CSP.lastStats, isNotNull);
      expect(CSP.lastStats!.naryRevises + CSP.lastStats!.binaryRevises,
          greaterThan(0));
    });

    test('zero-conflict problem reduces to underlying picker', () async {
      // No propagation conflicts on this trivially-feasible problem,
      // so _lastConflictVar stays null and the picker falls through
      // to MRV — verifies the null-LC fallback path in _pickVariable.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithLastConflict();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });
  });

  group('useLastConflict flag on getSolutionWithRestarts', () {
    test('composes with restarts: still finds a solution', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolutionWithRestarts(
        seed: 5,
        useLastConflict: true,
      );
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('LC + dom/wdeg + restarts: the canonical Lecoutre combination',
        () async {
      // Lecoutre's experiments show LC+dom/wdeg outperforming pure
      // dom/wdeg on structured benchmarks; verify the composition
      // is valid here (correctness, not performance).
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
      final result = await p.getSolutionWithRestarts(
        seed: 7,
        useDomWdeg: true,
        useLastConflict: true,
      );
      expect(result, isA<Map<String, dynamic>>());
    });

    test('infeasible + LC + restarts → FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithRestarts(
        seed: 3,
        useLastConflict: true,
        maxRestarts: 5,
      );
      expect(result, equals('FAILURE'));
    });
  });

  group('CSP.solveWithLastConflict (static entry point)', () {
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
      final result = await CSP.solveWithLastConflict(csp);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });

    test('LC + IBS together: both flags set, still solves', () async {
      // Stress the picker dispatch order: LC wraps IBS, both update.
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
      final result = await p.getSolutionWithLastConflict(useImpact: true);
      expect(result, isA<Map<String, dynamic>>());
    });
  });

  group('Picker behavior: LC focuses search on the conflict variable', () {
    test('LC reduces decisions vs. MRV on a constructed conflict-prone case',
        () async {
      // A 6-queens instance is small enough to show a difference but
      // big enough to actually exercise LC's "focus on the conflict"
      // behavior. We verify only that LC's decision count is
      // *finite and reasonable* — not that it strictly beats MRV
      // (that's a benchmark question, not a correctness one). The
      // assertion is "LC doesn't blow up search relative to MRV".
      final queens = [for (var i = 0; i < 6; i++) 'Q$i'];

      final pMrv = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5, 6])
        ..addAllDifferent(queens);
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          final d = (j - i).abs();
          pMrv.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      await pMrv.getSolution();
      final mrvDecisions = CSP.lastStats!.decisions;

      final pLc = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5, 6])
        ..addAllDifferent(queens);
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          final d = (j - i).abs();
          pLc.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      await pLc.getSolutionWithLastConflict();
      final lcDecisions = CSP.lastStats!.decisions;

      // Sanity: both finished, and LC didn't multiply search by 10x.
      expect(mrvDecisions, greaterThan(0));
      expect(lcDecisions, greaterThan(0));
      expect(lcDecisions, lessThan(mrvDecisions * 10));
    });
  });
}

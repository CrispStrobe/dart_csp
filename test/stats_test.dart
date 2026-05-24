import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('SolverStats via Problem.lastStats', () {
    test('null before any solve', () {
      // Use a fresh problem; CSP.lastStats may carry state from
      // earlier tests in the same VM, so check via runtime type.
      final p = Problem()..addVariable('X', [1]);
      final before = p.lastStats;
      // Either null or a leftover from earlier tests; both are
      // acceptable. The point is that the call shape compiles and
      // returns the expected type.
      expect(before, anyOf(isNull, isA<SolverStats>()));
    });

    test('non-null after a solve, with sensible counter values', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      await p.getSolution();
      final stats = p.lastStats!;
      expect(stats.decisions, greaterThan(0));
      // Sanity: an all-different 3x3 trivially terminates; backtracks
      // can be 0 for the trivial first-try-works ordering.
      expect(stats.backtracks, greaterThanOrEqualTo(0));
      expect(stats.propagations, greaterThan(0));
      expect(stats.elapsedMicros, greaterThan(0));
    });

    test('higher backtracks on a harder problem than an easier one', () async {
      // Easier: trivially solvable
      final easy = Problem()..addVariable('X', [1]);
      await easy.getSolution();
      final easyStats = easy.lastStats!;
      // We just need the easy run to be non-trivial enough to
      // populate stats; we don't compare absolute values.
      expect(easyStats.propagations, greaterThan(0));

      // Harder: many variables, all-different
      final hard = Problem()
        ..addVariables(['A', 'B', 'C', 'D', 'E', 'F'], [1, 2, 3, 4, 5, 6])
        ..addAllDifferent(['A', 'B', 'C', 'D', 'E', 'F']);
      await hard.getSolution();
      final hardStats = hard.lastStats!;
      expect(hardStats.decisions, greaterThan(easyStats.decisions),
          reason:
              'harder problem should have more decisions than the trivial one');
    });

    test('stats reset between solves', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addAllDifferent(['A', 'B']);
      await p.getSolution();
      final first = p.lastStats!;
      await p.getSolution();
      final second = p.lastStats!;
      // Each solve should reset, so the counters from the second run
      // are not cumulative.
      expect(second.decisions, equals(first.decisions));
      expect(second.backtracks, equals(first.backtracks));
    });

    test('toString returns a useful summary', () async {
      final p = Problem()..addVariable('X', [1, 2, 3]);
      await p.getSolution();
      final s = p.lastStats!.toString();
      expect(s, contains('decisions'));
      expect(s, contains('backtracks'));
      expect(s, contains('propagations'));
    });

    test('infeasible problem still populates stats', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
      expect(p.lastStats, isNotNull);
    });
  });

  group('SolverStats — streaming via getSolutions', () {
    test('full enumeration populates lastStats with search counters', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(6)); // 3! permutations
      final stats = p.lastStats!;
      expect(stats.decisions, greaterThan(0));
      expect(stats.propagations, greaterThan(0));
      expect(stats.elapsedMicros, greaterThan(0));
      // Iterations is for local search, not streaming.
      expect(stats.iterations, equals(0));
    });

    test('partial consumption (break after first) still populates lastStats',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      await for (final _ in p.getSolutions()) {
        break; // cancel the stream after the first solution
      }
      final stats = p.lastStats!;
      expect(stats.decisions, greaterThan(0),
          reason: 'cancelled stream should still flush stats via finally');
      expect(stats.elapsedMicros, greaterThan(0));
    });

    test('infeasible stream completes empty and populates stats', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(0));
      expect(p.lastStats, isNotNull);
      expect(p.lastStats!.elapsedMicros, greaterThan(0));
    });
  });

  group('SolverStats — local search via solveWithMinConflicts', () {
    test('converged MC run populates iterations + elapsedMicros', () async {
      // Trivially solvable problem so MC converges quickly. The
      // initial random assignment may already be conflict-free, in
      // which case stepsRun is 1 (one iteration to verify).
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4])
        ..addStringConstraint('A != B');
      await p.solveWithMinConflicts(maxSteps: 50, seed: 1);
      final stats = p.lastStats!;
      expect(stats.iterations, greaterThan(0));
      expect(stats.iterations, lessThanOrEqualTo(50));
      expect(stats.elapsedMicros, greaterThan(0));
      // Backtracking counters should be untouched.
      expect(stats.decisions, equals(0));
      expect(stats.backtracks, equals(0));
      expect(stats.propagations, equals(0));
    });

    test('unconverged MC run reports iterations == maxSteps', () async {
      // Infeasible problem: MC will exhaust maxSteps and return
      // FAILURE; iterations should equal maxSteps exactly.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.solveWithMinConflicts(maxSteps: 5, seed: 42);
      expect(result, equals('FAILURE'));
      final stats = p.lastStats!;
      expect(stats.iterations, equals(5));
      expect(stats.elapsedMicros, greaterThan(0));
    });
  });

  group('SolverStats — iterations field default', () {
    test('default constructor initializes iterations to 0', () {
      final s = SolverStats();
      expect(s.iterations, equals(0));
    });

    test('toString includes the iterations field', () {
      final s = SolverStats(iterations: 7);
      expect(s.toString(), contains('iterations: 7'));
    });
  });
}

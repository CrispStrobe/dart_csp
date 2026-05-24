import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.getSolutionWithDomWdeg', () {
    test('returns a valid solution on a basic feasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolutionWithDomWdeg();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C']}, equals({1, 2, 3}));
    });

    test('returns FAILURE on an infeasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithDomWdeg();
      expect(result, equals('FAILURE'));
    });

    test('handles classic constraint-heavy puzzles', () async {
      // 4-queens with allDifferent + diagonal exclusions; same shape as
      // the existing N-queens tests but solved via dom/wdeg.
      final queens = [for (var i = 0; i < 4; i++) 'Q$i'];
      final p = Problem()
        ..addVariables(queens, [1, 2, 3, 4])
        ..addAllDifferent(queens);
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          final d = (j - i).abs();
          p.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      final result = await p.getSolutionWithDomWdeg();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      // Verify a valid 4-queens solution.
      final values = queens.map((q) => s[q] as int).toList();
      expect(values.toSet().length, equals(4),
          reason: 'all queens in distinct columns');
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect((values[i] - values[j]).abs(), isNot(equals(j - i)),
              reason: 'queens $i,$j on the same diagonal');
        }
      }
    });

    test('agrees with MRV solver on the answer (single feasible problem)',
        () async {
      // A problem with a unique feasible answer.
      final pMrv = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final viaMrv = await pMrv.getSolution();

      final pDw = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final viaDw = await pDw.getSolutionWithDomWdeg();

      expect(viaDw, equals(viaMrv));
    });
  });

  group('useDomWdeg flag on getSolutionWithRestarts', () {
    test('composes with restarts: still finds a solution', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolutionWithRestarts(
        seed: 5,
        useDomWdeg: true,
      );
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('infeasible + restarts + dom/wdeg → FAILURE', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithRestarts(
        seed: 9,
        useDomWdeg: true,
        maxRestarts: 5,
      );
      expect(result, equals('FAILURE'));
    });
  });
}

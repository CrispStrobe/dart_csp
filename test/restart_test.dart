import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.getSolutionWithRestarts', () {
    test('finds a solution on a trivially-feasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithRestarts(seed: 1);
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['A'], isNot(equals(s['B'])));
    });

    test('returns FAILURE on a clearly-infeasible problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A == B')
        ..addStringConstraint('A != B');
      final result = await p.getSolutionWithRestarts(seed: 1, maxRestarts: 5);
      expect(result, equals('FAILURE'));
    });

    test('deterministic with a fixed seed: same answer twice', () async {
      Problem build() => Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);

      final a = await build().getSolutionWithRestarts(seed: 42);
      final b = await build().getSolutionWithRestarts(seed: 42);
      expect(a, equals(b),
          reason: 'same seed should produce the same solution');
    });

    test('different seeds can produce different solutions', () async {
      // Multiple seeds tried; not all seeds are guaranteed to differ
      // (small problem with few solutions), but at least one pair
      // should.
      Problem build() => Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);

      final solutions = <String>{};
      for (var seed = 1; seed <= 20; seed++) {
        final s = await build().getSolutionWithRestarts(seed: seed);
        solutions.add(s.toString());
      }
      expect(solutions.length, greaterThan(1),
          reason:
              'restart randomization should explore distinct solutions over 20 seeds');
    });

    test('maxRestarts caps total effort on hard-feasible-looking problems',
        () async {
      // 8-queens is an easy feasible problem for restarts; the test
      // here is really just that maxRestarts doesn't accidentally
      // prevent a normal solve from succeeding.
      final p = Problem();
      final queens = [for (var i = 0; i < 8; i++) 'Q$i'];
      p.addVariables(queens, [1, 2, 3, 4, 5, 6, 7, 8]);
      p.addAllDifferent(queens);
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
          final d = (j - i).abs();
          p.addConstraint(
            [queens[i], queens[j]],
            (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d,
          );
        }
      }
      final result = await p.getSolutionWithRestarts(seed: 7, maxRestarts: 50);
      expect(result, isA<Map<String, dynamic>>());
    });

    test('solveWithRestarts on a 4x4 puzzle returns a valid Sudoku-row',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolutionWithRestarts(seed: 0);
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
    });

    test('scale parameter changes per-attempt budget (smoke test)', () async {
      // Just verify the call still works with non-default scale.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4])
        ..addStringConstraint('A != B');
      final result =
          await p.getSolutionWithRestarts(seed: 1, scale: 1, maxRestarts: 50);
      expect(result, isA<Map<String, dynamic>>());
    });
  });
}

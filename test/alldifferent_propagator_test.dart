import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// These tests target the Régin-based allDifferent propagator
/// indirectly through Problem.addAllDifferent (the public API). The
/// propagator is private to lib/src/solver.dart by design.
///
/// Correctness here means: the surfaced solutions and infeasibility
/// detection are unchanged from a naive allDifferent. The propagator
/// only prunes more aggressively — it must never reject a feasible
/// value nor accept an infeasible one.
void main() {
  group('addAllDifferent: Régin-level pruning correctness', () {
    test('Hall set: three vars all in {1,2} -> infeasible (pigeonhole)',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2])
        ..addAllDifferent(['A', 'B', 'C']);
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });

    test('Hall set inside a larger problem: pruning propagates', () async {
      // A,B,C share {1,2,3}; D,E share {1,2,3,4,5}. A,B,C are a Hall
      // set occupying {1,2,3}, so D and E must take values from {4,5}.
      final p = Problem()
        ..addVariable('A', [1, 2, 3])
        ..addVariable('B', [1, 2, 3])
        ..addVariable('C', [1, 2, 3])
        ..addVariable('D', [1, 2, 3, 4, 5])
        ..addVariable('E', [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C', 'D', 'E']);
      final solutions = await p.getAllSolutions();
      for (final s in solutions) {
        expect({s['D'], s['E']}, equals({4, 5}));
      }
      // 3! permutations of {1,2,3} for A,B,C × 2 permutations of {4,5}.
      expect(solutions, hasLength(3 * 2 * 1 * 2));
    });

    test('matching detects infeasibility: bipartite matching too small',
        () async {
      // 4 variables share only 3 distinct values across the union of
      // their domains -> no perfect matching possible.
      final p = Problem()
        ..addVariable('A', [1, 2])
        ..addVariable('B', [1, 2])
        ..addVariable('C', [2, 3])
        ..addVariable('D', [1, 3])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });

    test('enumerates exactly the n! permutations on a tight allDifferent',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final solutions = await p.getAllSolutions();
      // 4! = 24
      expect(solutions, hasLength(24));
      for (final s in solutions) {
        expect({s['A'], s['B'], s['C'], s['D']}, equals({1, 2, 3, 4}));
      }
    });

    test('value uniqueness preserved under arbitrary value types', () async {
      // The propagator must not assume values are integers.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], ['red', 'green', 'blue'])
        ..addAllDifferent(['A', 'B', 'C']);
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(6));
      for (final s in solutions) {
        expect({s['A'], s['B'], s['C']}, equals({'red', 'green', 'blue'}));
      }
    });

    test('mixed-arity: 2-var binary still works after dispatch refactor',
        () async {
      // addAllDifferent for 2 vars takes the binary fast path; make
      // sure nothing regressed.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addAllDifferent(['A', 'B']);
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(6));
      for (final s in solutions) {
        expect(s['A'], isNot(equals(s['B'])));
      }
    });
  });

  group('addAllDifferent: hard problems that hit Régin', () {
    test('3x3 magic square WITHOUT center clue', () async {
      // This is the previously-slow case that took ~100s with generic
      // GAC + the 4096 work bound. With Régin's it should be a few
      // milliseconds.
      const cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
      final p = Problem()
        ..addVariables(cells, [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addAllDifferent(cells)
        ..addExactSum(['A1', 'A2', 'A3'], 15)
        ..addExactSum(['B1', 'B2', 'B3'], 15)
        ..addExactSum(['C1', 'C2', 'C3'], 15)
        ..addExactSum(['A1', 'B1', 'C1'], 15)
        ..addExactSum(['A2', 'B2', 'C2'], 15)
        ..addExactSum(['A3', 'B3', 'C3'], 15)
        ..addExactSum(['A1', 'B2', 'C3'], 15)
        ..addExactSum(['A3', 'B2', 'C1'], 15);

      final sw = Stopwatch()..start();
      final result = await p.getSolution();
      sw.stop();

      expect(result, isA<Map<String, dynamic>>(),
          reason: 'magic square 3x3 must be solvable');
      // The propagator should comfortably solve this in well under a
      // second. We allow generous slack to avoid CI flakes but still
      // catch a regression back to seconds.
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason:
              'magic-square 3x3 (no clue) regression: ${sw.elapsedMilliseconds}ms');
    });

    test('sudoku solve uses Régin propagator on 27 allDifferents', () async {
      // A medium-hard puzzle. Tests both correctness (a real Sudoku
      // solution) and that 27 simultaneous 9-var allDifferents stay
      // tractable.
      const puzzle = [
        [1, 0, 0, 0, 0, 7, 0, 9, 0],
        [0, 3, 0, 0, 2, 0, 0, 0, 8],
        [0, 0, 9, 6, 0, 0, 5, 0, 0],
        [0, 0, 5, 3, 0, 0, 9, 0, 0],
        [0, 1, 0, 0, 8, 0, 0, 0, 2],
        [6, 0, 0, 0, 0, 4, 0, 0, 0],
        [3, 0, 0, 0, 0, 0, 0, 1, 0],
        [0, 4, 0, 0, 0, 0, 0, 0, 7],
        [0, 0, 7, 0, 0, 0, 3, 0, 0],
      ];

      final p = Problem();
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          final name = 'r${r}c$c';
          final v = puzzle[r][c];
          if (v != 0) {
            p.addVariable(name, [v]);
          } else {
            p.addVariable(name, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
          }
        }
      }
      for (var r = 0; r < 9; r++) {
        p.addAllDifferent([for (var c = 0; c < 9; c++) 'r${r}c$c']);
      }
      for (var c = 0; c < 9; c++) {
        p.addAllDifferent([for (var r = 0; r < 9; r++) 'r${r}c$c']);
      }
      for (var br = 0; br < 3; br++) {
        for (var bc = 0; bc < 3; bc++) {
          final cells = <String>[];
          for (var dr = 0; dr < 3; dr++) {
            for (var dc = 0; dc < 3; dc++) {
              cells.add('r${br * 3 + dr}c${bc * 3 + dc}');
            }
          }
          p.addAllDifferent(cells);
        }
      }

      final sw = Stopwatch()..start();
      final result = await p.getSolution();
      sw.stop();

      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;

      // Check the solution satisfies Sudoku rules.
      for (var r = 0; r < 9; r++) {
        final row = {for (var c = 0; c < 9; c++) s['r${r}c$c']};
        expect(row, equals({1, 2, 3, 4, 5, 6, 7, 8, 9}),
            reason: 'row $r not all-different');
      }
      for (var c = 0; c < 9; c++) {
        final col = {for (var r = 0; r < 9; r++) s['r${r}c$c']};
        expect(col, equals({1, 2, 3, 4, 5, 6, 7, 8, 9}),
            reason: 'col $c not all-different');
      }
      // Clues preserved.
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          if (puzzle[r][c] != 0) {
            expect(s['r${r}c$c'], equals(puzzle[r][c]));
          }
        }
      }

      // Should be well under a second; budget 2s for CI slack.
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'sudoku regression: ${sw.elapsedMilliseconds}ms');
    });
  });
}

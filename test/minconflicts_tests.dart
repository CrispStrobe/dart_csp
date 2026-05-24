import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// ====================================================================
//  Custom Validator Functions (The "Makes Sense" Checks)
// ====================================================================

// Add this helper function to the top of your test file
void printQueensBoard(Map<String, dynamic> solution) {
  final n = solution.length;
  final board = List.generate(n, (_) => List.filled(n, '.'));

  for (final entry in solution.entries) {
    // entry.key is like 'Q1', 'Q2', etc.
    final col = int.parse(entry.key.substring(1)) - 1;
    // entry.value is the row
    final row = (entry.value as int) - 1;

    if (row < n && col < n) {
      board[row][col] = 'Q';
    }
  }

  print(''); // Newline for spacing
  for (final row in board) {
    print('  ${row.join(' ')}');
  }
  print('');
}

/// Checks if a given 8-Queens solution is valid.
/// A solution is a map like {'Q1': 3, 'Q2': 5, ...}
bool isQueensSolutionValid(Map<String, dynamic> solution, int n) {
  if (solution.length != n) return false;

  final positions = <int>[];
  for (var i = 0; i < n; i++) {
    positions.add(solution['Q${i + 1}'] as int);
  }

  // Check for row and diagonal conflicts
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      // Check for same row
      if (positions[i] == positions[j]) {
        print(
            'Validation Error: Queens ${i + 1} and ${j + 1} are in the same row!');
        return false;
      }
      // Check for diagonal conflict
      if ((positions[i] - positions[j]).abs() == (i - j).abs()) {
        print(
            'Validation Error: Queens ${i + 1} and ${j + 1} are on the same diagonal!');
        return false;
      }
    }
  }
  return true;
}

/// Checks if a given Map Coloring solution is valid.
bool isMapSolutionValid(
    Map<String, dynamic> solution, Map<String, List<String>> neighbors) {
  for (final region in solution.keys) {
    final regionColor = solution[region];
    final regionNeighbors = neighbors[region] ?? [];
    for (final neighbor in regionNeighbors) {
      if (solution.containsKey(neighbor) && solution[neighbor] == regionColor) {
        print(
            'Validation Error: Adjacent regions $region and $neighbor have the same color!');
        return false;
      }
    }
  }
  return true;
}

void main() {
  group('Min-Conflicts Algorithm Tests', () {
    // Test Facet 1: Correctness on a classic, highly-constrained problem (N-Queens)
    test('solves 8-Queens and produces a valid, non-conflicting solution',
        () async {
      final p = Problem();
      const n = 8;
      final queens = List.generate(n, (i) => 'Q${i + 1}');
      final domain = List.generate(n, (i) => i + 1);
      p.addVariables(queens, domain);
      p.addAllDifferent(queens); // No queens in the same row

      // No queens on the same diagonal
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final colDiff = j - i;
          p.addConstraint(
              [queens[i], queens[j]],
              (dynamic posI, dynamic posJ) =>
                  ((posI as int) - (posJ as int)).abs() != colDiff);
        }
      }

      // Give it plenty of steps to find a solution
      final solution = await p.solveWithMinConflicts(maxSteps: 10000);

      // The algorithm is stochastic, so it might fail to find a solution in time.
      // The crucial part is that IF it returns a solution, that solution MUST be valid.
      if (solution is Map<String, dynamic>) {
        print('Min-Conflicts found an 8-Queens solution: $solution');

        // VISUALIZE THE SOLUTION!
        print('Visualized Board:');
        printQueensBoard(solution);

        expect(isQueensSolutionValid(solution, n), isTrue,
            reason: 'The returned solution must be valid.');
      } else {
        print(
            'Min-Conflicts did not find an 8-Queens solution in time, which is acceptable.');
        expect(solution, equals('FAILURE'));
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    // Test Facet 2: Correctness on a different type of problem (Map Coloring)
    test('solves Map Coloring and produces a valid, non-conflicting solution',
        () async {
      final p = Problem();
      final neighbors = {
        'WA': ['NT', 'SA'],
        'NT': ['WA', 'SA', 'Q'],
        'SA': ['WA', 'NT', 'Q', 'NSW', 'V'],
        'Q': ['NT', 'SA', 'NSW'],
        'NSW': ['Q', 'SA', 'V'],
        'V': ['SA', 'NSW'],
        'T': <String>[]
      };
      final regions = neighbors.keys.toList();
      final colors = ['red', 'green', 'blue'];
      p.addVariables(regions, colors);

      for (final region in neighbors.keys) {
        for (final neighbor in neighbors[region]!) {
          p.addStringConstraint('$region != $neighbor');
        }
      }

      final solution = await p.solveWithMinConflicts(maxSteps: 2000);

      if (solution is Map<String, dynamic>) {
        print('Min-Conflicts found a Map Coloring solution: $solution');
        expect(isMapSolutionValid(solution, neighbors), isTrue,
            reason:
                'The returned solution must not have adjacent regions with the same color.');
      } else {
        print(
            'Min-Conflicts did not find a Map Coloring solution in time, which is acceptable.');
        expect(solution, equals('FAILURE'));
      }
    });

    // Test Facet 3: Behavior on an unsolvable problem
    test('correctly returns FAILURE for an unsolvable problem', () async {
      final p = Problem();
      // Pigeonhole principle: 3 variables, but only 2 possible values.
      // An AllDifferent constraint makes it impossible.
      p.addVariables(['A', 'B', 'C'], [1, 2]);
      p.addAllDifferent(['A', 'B', 'C']);

      final solution = await p.solveWithMinConflicts();

      // For an unsolvable problem, it should never return a solution.
      // It must eventually give up and return 'FAILURE'.
      expect(solution, equals('FAILURE'));
    });

    // Test Facet 4: Respecting the maxSteps parameter
    test(
        'respects maxSteps limit and fails on a complex problem with too few steps',
        () async {
      final p = Problem();
      const n = 8;
      final queens = List.generate(n, (i) => 'Q${i + 1}');
      final domain = List.generate(n, (i) => i + 1);
      p.addVariables(queens, domain);
      p.addAllDifferent(queens);
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final colDiff = j - i;
          p.addConstraint(
              [queens[i], queens[j]],
              (dynamic posI, dynamic posJ) =>
                  ((posI as int) - (posJ as int)).abs() != colDiff);
        }
      }

      // Give it an absurdly small number of steps. The probability of solving 8-Queens
      // in 5 steps is astronomically low. We expect it to fail.
      final solution = await p.solveWithMinConflicts(maxSteps: 5);

      // This test asserts that the algorithm terminates and returns FAILURE,
      // respecting the step limit, rather than getting stuck in an infinite loop.
      expect(solution, equals('FAILURE'));
    });
  });

  group('Min-Conflicts seed parameter', () {
    Problem buildEightQueens() {
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
      return p;
    }

    test('same seed produces identical results across runs', () async {
      final a = await buildEightQueens().solveWithMinConflicts(seed: 42);
      final b = await buildEightQueens().solveWithMinConflicts(seed: 42);
      expect(a, equals(b), reason: 'fixed seed should be deterministic');
    });

    test('different seeds can produce different results', () async {
      final seen = <String>{};
      for (var s = 1; s <= 10; s++) {
        final result = await buildEightQueens().solveWithMinConflicts(seed: s);
        if (result is Map<String, dynamic>) seen.add(result.toString());
      }
      expect(seen.length, greaterThan(1),
          reason: '10 seeds should yield more than one distinct answer');
    });
  });
}

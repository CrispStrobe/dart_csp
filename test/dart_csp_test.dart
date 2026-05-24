/// Comprehensive test suite for the dart_csp library
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Basic Problem Creation', () {
    test('create empty problem', () {
      final p = Problem();
      expect(p.variableCount, equals(0));
      expect(p.constraintCount, equals(0));
    });

    test('add single variable', () {
      final p = Problem();
      p.addVariable('A', [1, 2, 3]);
      expect(p.variableCount, equals(1));
      expect(p.variables['A'], equals([1, 2, 3]));
    });

    test('add multiple variables', () {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
      expect(p.variableCount, equals(3));
      expect(p.variables.keys, containsAll(['A', 'B', 'C']));
    });

    test('reject duplicate variable names', () {
      final p = Problem();
      p.addVariable('A', [1, 2, 3]);
      expect(() => p.addVariable('A', [4, 5, 6]), throwsArgumentError);
    });

    test('reject empty domain', () {
      final p = Problem();
      expect(() => p.addVariable('A', []), throwsArgumentError);
    });
  });

  group('Binary Constraints', () {
    test('simple binary constraint', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3]);
      p.addConstraint(['A', 'B'], (dynamic a, dynamic b) => a != b);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] != s['B'], isTrue);
    });

    test('all different binary', () async {
      final p = Problem();
      p.addVariables(['X', 'Y'], [1, 2]);
      p.addAllDifferent(['X', 'Y']);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['X'] != s['Y'], isTrue);
    });
  });

  group('N-ary Constraints', () {
    test('three-variable all different', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
      p.addAllDifferent(['A', 'B', 'C']);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;

      final values = s.values.toSet();
      expect(values.length, equals(3)); // All different
    });

    test('sum constraint', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3, 4, 5]);
      p.addExactSum(['A', 'B'], 7);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] + s['B'], equals(7));
    });

    test('product constraint', () async {
      final p = Problem();
      p.addVariables(['X', 'Y'], [2, 3, 4, 5, 6]);
      p.addExactProduct(['X', 'Y'], 12);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['X'] * s['Y'], equals(12));
    });
  });

  group('String Constraints', () {
    test('simple inequality', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3]);
      p.addStringConstraint('A != B');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] != s['B'], isTrue);
    });

    test('sum equality', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3, 4, 5]);
      p.addStringConstraint('A + B == 6');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] + s['B'], equals(6));
    });

    test('variable sum constraint', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);
      p.addStringConstraint('A + B == C');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] + s['B'], equals(s['C']));
    });

    test('chained inequality', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
      p.addStringConstraint('A != B != C');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;

      final values = s.values.toSet();
      expect(values.length, equals(3)); // All different
    });

    test('ordering constraint', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3, 4, 5]);
      p.addStringConstraint('A < B');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] < s['B'], isTrue);
    });

    test('range constraint', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3, 4, 5]);
      p.addStringConstraint('5 <= A + B <= 7');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      final sum = (s['A'] as num) + (s['B'] as num);
      expect(sum >= 5 && sum <= 7, isTrue);
    });

    test('invalid constraint throws exception', () {
      final p = Problem();
      p.addVariable('A', [1, 2, 3]);
      expect(() => p.addStringConstraint('A + B == 5'),
          throwsA(isA<ConstraintParseException>()));
    });
  });

  group('Complex Problems', () {
    test('magic square 3x3', () async {
      final p = Problem();
      final cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];

      // --- OPTIMIZATION: Add a clue to prune the search space ---
      // For a 3x3 magic square, the center cell 'B2' must always be 5.
      p.addVariable('B2', [5]);

      // Define the domain for the other 8 cells.
      final otherDomain = [1, 2, 3, 4, 6, 7, 8, 9];
      for (final cell in cells) {
        if (cell != 'B2') {
          p.addVariable(cell, otherDomain);
        }
      }

      // All different constraint remains the same
      p.addAllDifferent(cells);

      // Built-in sum constraints
      // Rows
      p.addExactSum(['A1', 'A2', 'A3'], 15);
      p.addExactSum(['B1', 'B2', 'B3'], 15);
      p.addExactSum(['C1', 'C2', 'C3'], 15);

      // Columns
      p.addExactSum(['A1', 'B1', 'C1'], 15);
      p.addExactSum(['A2', 'B2', 'C2'], 15);
      p.addExactSum(['A3', 'B3', 'C3'], 15);

      // Diagonals
      p.addExactSum(['A1', 'B2', 'C3'], 15);
      p.addExactSum(['A3', 'B2', 'C1'], 15);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());

      if (solution is Map<String, dynamic>) {
        final s = solution;

        // Check all different
        final values = s.values.toSet();
        expect(values.length, equals(9));

        // Check sums
        expect(s['A1'] + s['A2'] + s['A3'], equals(15));
        expect(s['B1'] + s['B2'] + s['B3'], equals(15));
        expect(s['C1'] + s['C2'] + s['C3'], equals(15));
        expect(s['A1'] + s['B1'] + s['C1'], equals(15));
        expect(s['A2'] + s['B2'] + s['C2'], equals(15));
        expect(s['A3'] + s['B3'] + s['C3'], equals(15));
        expect(s['A1'] + s['B2'] + s['C3'], equals(15));
        expect(s['A3'] + s['B2'] + s['C1'], equals(15));
      }
    });

    test('4-queens problem', () async {
      final p = Problem();
      final queens = ['Q1', 'Q2', 'Q3', 'Q4'];
      p.addVariables(queens, [1, 2, 3, 4]);

      // No same column
      p.addAllDifferent(queens);

      // No diagonal attacks
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          final colDiff = j - i;
          p.addConstraint(
              [queens[i], queens[j]],
              (dynamic posI, dynamic posJ) =>
                  ((posI as int) - (posJ as int)).abs() != colDiff);
        }
      }

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());

      if (solution is Map<String, dynamic>) {
        final s = solution;

        // Check no same column
        final positions = s.values.toSet();
        expect(positions.length, equals(4));

        // Check no diagonal attacks
        for (var i = 0; i < 4; i++) {
          for (var j = i + 1; j < 4; j++) {
            final posI = s['Q${i + 1}'];
            final posJ = s['Q${j + 1}'];
            final rowDiff = (posI - posJ).abs();
            final colDiff = j - i;
            expect(rowDiff != colDiff, isTrue);
          }
        }
      }
    });

    test('map coloring', () async {
      final p = Problem();
      const colors = ['red', 'green', 'blue'];
      const regions = ['A', 'B', 'C', 'D'];

      p.addVariables(regions, colors);

      // Adjacent regions different colors
      p.addStringConstraints(
          ['A != B', 'A != C', 'B != C', 'B != D', 'C != D']);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());

      if (solution is Map<String, dynamic>) {
        final s = solution;
        expect(s['A'] != s['B'], isTrue);
        expect(s['A'] != s['C'], isTrue);
        expect(s['B'] != s['C'], isTrue);
        expect(s['B'] != s['D'], isTrue);
        expect(s['C'] != s['D'], isTrue);
      }
    });
  });

  group('Multiple Solutions', () {
    // A problem with 3 solutions: {A:1, B:2}, {A:1, B:3}, {A:2, B:3}
    Problem createMultiSolutionProblem() {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3]);
      p.addStringConstraint('A < B');
      return p;
    }

    // A problem with 1 solution: {A:1, B:1}
    Problem createSingleSolutionProblem() {
      final p = Problem();
      p.addVariables(['A', 'B'], [1]);
      p.addStringConstraint('A == B');
      return p;
    }

    // A problem with 0 solutions
    Problem createNoSolutionProblem() {
      final p = Problem();
      p.addVariables(['A'], [1]);
      p.addStringConstraint('A != A');
      return p;
    }

    test('getSolutions stream yields all solutions', () async {
      final p = createMultiSolutionProblem();
      final solutions = await p.getSolutions().toList();
      expect(solutions, hasLength(3));
      expect(
          solutions,
          containsAll([
            {'A': 1, 'B': 2},
            {'A': 1, 'B': 3},
            {'A': 2, 'B': 3}
          ]));
    });

    test('getAllSolutions returns a list of all solutions', () async {
      final p = createMultiSolutionProblem();
      final solutions = await p.getAllSolutions();
      expect(solutions, isA<List<Map<String, dynamic>>>());
      expect(solutions, hasLength(3));
    });

    test('countSolutions returns correct count', () async {
      expect(await createMultiSolutionProblem().countSolutions(), equals(3));
      expect(await createSingleSolutionProblem().countSolutions(), equals(1));
      expect(await createNoSolutionProblem().countSolutions(), equals(0));
    });

    test('hasMultipleSolutions is correct', () async {
      expect(await createMultiSolutionProblem().hasMultipleSolutions(), isTrue);
      expect(
          await createSingleSolutionProblem().hasMultipleSolutions(), isFalse);
      expect(await createNoSolutionProblem().hasMultipleSolutions(), isFalse);
    });

    group('getFirstNSolutions', () {
      test('gets N solutions when N < total', () async {
        final p = createMultiSolutionProblem();
        final solutions = await p.getFirstNSolutions(2);
        expect(solutions, hasLength(2));
      });

      test('gets all solutions when N > total', () async {
        final p = createMultiSolutionProblem();
        final solutions = await p.getFirstNSolutions(5);
        expect(solutions, hasLength(3));
      });

      test('gets all solutions when N == total', () async {
        final p = createMultiSolutionProblem();
        final solutions = await p.getFirstNSolutions(3);
        expect(solutions, hasLength(3));
      });

      test('gets 0 solutions when N = 0', () async {
        final p = createMultiSolutionProblem();
        final solutions = await p.getFirstNSolutions(0);
        expect(solutions, isEmpty);
      });

      test('gets 1 solution when N = 1', () async {
        final p = createMultiSolutionProblem();
        final solutions = await p.getFirstNSolutions(1);
        expect(solutions, hasLength(1));
      });

      test('works with no solutions', () async {
        final p = createNoSolutionProblem();
        final solutions = await p.getFirstNSolutions(5);
        expect(solutions, isEmpty);
      });
    });

    test('solveAllProblems convenience function', () async {
      final stream = solveAllProblems(
        variables: {
          'A': [1, 2, 3],
          'B': [1, 2, 3]
        },
        constraints: ['A < B'],
      );
      final solutions = await stream.toList();
      expect(solutions, hasLength(3));
    });

    test('countAllSolutions convenience function', () async {
      final count = await countAllSolutions(
        variables: {
          'A': [1, 2, 3],
          'B': [1, 2, 3]
        },
        constraints: ['A < B'],
      );
      expect(count, equals(3));
    });
  });

  group('Convenience Functions', () {
    test('solveAllDifferent', () async {
      final solution = await solveAllDifferent(
          variables: ['A', 'B', 'C'], domain: [1, 2, 3]);

      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      final values = s.values.toSet();
      expect(values.length, equals(3));
    });

    test('solveSumProblem', () async {
      final solution = await solveSumProblem(
          variables: ['X', 'Y'], domain: [1, 2, 3, 4, 5], targetSum: 7);

      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['X'] + s['Y'], equals(7));
    });

    test('solveProblem with string constraints', () async {
      final solution = await solveProblem(variables: {
        'A': [1, 2, 3],
        'B': [1, 2, 3]
      }, constraints: [
        'A != B',
        'A + B >= 4'
      ]);

      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] != s['B'], isTrue);
      expect(s['A'] + s['B'] >= 4, isTrue);
    });
  });

  group('Failure Cases', () {
    test('unsolvable problem returns failure', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1]);
      p.addStringConstraint('A != B');

      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });

    test('over-constrained problem', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2]);
      p.addStringConstraints(['A != B', 'A + B == 2', 'A > B']);

      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });
  });

  group('Problem Utilities', () {
    test('problem copy', () {
      final p1 = Problem();
      p1.addVariables(['A', 'B'], [1, 2, 3]);
      p1.addStringConstraint('A != B');

      final p2 = p1.copy();
      expect(p2.variableCount, equals(p1.variableCount));
      expect(p2.constraintCount, equals(p1.constraintCount));
    });

    test('problem clear', () {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3]);
      p.addStringConstraint('A != B');

      expect(p.variableCount, greaterThan(0));
      expect(p.constraintCount, greaterThan(0));

      p.clear();
      expect(p.variableCount, equals(0));
      expect(p.constraintCount, equals(0));
    });

    test('problem validation', () {
      final p = Problem();
      p.addVariable('A', [1, 2, 3]);
      // Add a variable with no constraints (isolated variable test)
      p.addVariable('Isolated', [1, 2, 3]);
      p.addStringConstraint('A != 2'); // This creates a constraint only on A

      final issues = p.validate();
      expect(issues.length, greaterThan(0));
      expect(issues.any((issue) => issue.contains('isolated')), isTrue);
    });
  });

  group('Constraint Parser Edge Cases', () {
    test('complex arithmetic expressions', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5, 6]);
      p.addStringConstraint('A * B + C == 10');

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;
      expect(s['A'] * s['B'] + s['C'], equals(10));
    });

    test('multiple constraints with same variables', () async {
      final p = Problem();
      p.addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4, 5]);
      p.addStringConstraints(
          ['X != Y', 'Y != Z', 'X + Y + Z == 10', 'X < Y', 'Y < Z']);

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final s = solution as Map<String, dynamic>;

      expect(s['X'] != s['Y'], isTrue);
      expect(s['Y'] != s['Z'], isTrue);
      expect(s['X'] + s['Y'] + s['Z'], equals(10));
      expect(s['X'] < s['Y'], isTrue);
      expect(s['Y'] < s['Z'], isTrue);
    });

    test('malformed constraint throws exception', () {
      final p = Problem();
      p.addVariable('A', [1, 2, 3]);

      expect(() => p.addStringConstraint('A +++ B'),
          throwsA(isA<ConstraintParseException>()));
    });
  });

  group('Min-Conflicts Solver', () {
    test('8-queens problem with min-conflicts', () async {
      final p = Problem();
      const n = 8;
      final queens = List.generate(n, (i) => 'Q${i + 1}');
      final domain = List.generate(n, (i) => i + 1);
      p.addVariables(queens, domain);

      // No same column
      p.addAllDifferent(queens);

      // No diagonal attacks
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final colDiff = j - i;
          p.addConstraint(
              [queens[i], queens[j]],
              (dynamic posI, dynamic posJ) =>
                  ((posI as int) - (posJ as int)).abs() != colDiff);
        }
      }

      // We give it more steps as it's a stochastic algorithm
      final solution = await p.solveWithMinConflicts(maxSteps: 5000);

      // We don't fail the test if no solution is found, as it's possible.
      // But IF a solution is returned, it MUST be valid.
      if (solution is Map<String, dynamic>) {
        final s = solution;
        print('Min-Conflicts found a solution for 8-Queens: $s');

        // Check no same column
        final positions = s.values.toSet();
        expect(positions.length, equals(n));

        // Check no diagonal attacks
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            final posI = s['Q${i + 1}'];
            final posJ = s['Q${j + 1}'];
            final rowDiff = (posI - posJ).abs();
            final colDiff = j - i;
            expect(rowDiff != colDiff, isTrue,
                reason: 'Diagonal conflict between Q${i + 1} and Q${j + 1}');
          }
        }
      } else {
        print('Min-Conflicts did not find a solution for 8-Queens in time.');
        expect(solution, equals('FAILURE'));
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}

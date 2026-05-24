/// Complete usage examples for the dart_csp library
library;

import 'package:dart_csp/dart_csp.dart';

void main() async {
  print('=== CSP Library Examples ===\n');

  await basicLambdaExample();
  await builtinConstraintsExample();
  await stringConstraintsExample();
  await variableConstraintsExample();
  await magicSquareExample();
  await nQueensExample();
  await convenienceFunctionsExample();
}

/// Basic example using lambda constraints
Future<void> basicLambdaExample() async {
  print('1. Basic Lambda Constraints - Map Coloring:');

  final p = Problem();
  const colors = ['red', 'green', 'blue'];

  // Australian map coloring problem
  p.addVariables(['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T'], colors);

  // Add constraints using lambda functions
  p.addConstraint(['SA', 'WA'], (dynamic sa, dynamic wa) => sa != wa);
  p.addConstraint(['SA', 'NT'], (dynamic sa, dynamic nt) => sa != nt);
  p.addConstraint(['SA', 'Q'], (dynamic sa, dynamic q) => sa != q);
  p.addConstraint(['SA', 'NSW'], (dynamic sa, dynamic nsw) => sa != nsw);
  p.addConstraint(['SA', 'V'], (dynamic sa, dynamic v) => sa != v);
  p.addConstraint(['WA', 'NT'], (dynamic wa, dynamic nt) => wa != nt);
  p.addConstraint(['NT', 'Q'], (dynamic nt, dynamic q) => nt != q);
  p.addConstraint(['Q', 'NSW'], (dynamic q, dynamic nsw) => q != nsw);
  p.addConstraint(['NSW', 'V'], (dynamic nsw, dynamic v) => nsw != v);

  final solution = await p.getSolution();
  print('Solution: $solution\n');
}

/// Example using built-in constraint helpers
Future<void> builtinConstraintsExample() async {
  print('2. Built-in Constraints - Sudoku Row:');

  final p = Problem();
  p.addVariables(['A', 'B', 'C'], [1, 2, 3]);

  // All different constraint using built-in helper
  p.addAllDifferent(['A', 'B', 'C']);

  final solution = await p.getSolution();
  print('Solution: $solution\n');
}

/// Example using string constraints (most convenient)
Future<void> stringConstraintsExample() async {
  print('3. String Constraints - Mixed Problem:');

  final p = Problem();
  p.addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4, 5]);

  // String constraints are parsed automatically
  p.addStringConstraints(['X != Y', 'Y != Z', 'X + Y + Z <= 10', 'X * Y >= 6']);

  final solution = await p.getSolution();
  print('Solution: $solution\n');
}

/// Example with variable constraints (one variable equals expression of others)
Future<void> variableConstraintsExample() async {
  print('4. Variable Constraints - Arithmetic Relations:');

  final p = Problem();
  p.addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

  // C = A + B and D = A * B
  p.addStringConstraints([
    'A + B == C',
    'A * B == D',
    'A < B', // Order constraint
    'C < D' // Result constraint
  ]);

  final solution = await p.getSolution();
  print('Solution: $solution\n');
}

/// 3x3 Magic Square example
Future<void> magicSquareExample() async {
  print('5. Magic Square (3x3):');

  final p = Problem();
  final cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];

  // The center of a 3x3 magic square must be 5. Pinning it (and shrinking
  // the other domains to exclude 5) prunes the search by ~20x; without this
  // clue the same problem takes ~100s instead of ~5s. The parser dispatches
  // 'X + Y + Z == 15' to the same built-in `exactSum` factory as
  // `addExactSum`, so the string form below is not slower than the helper.
  p.addVariable('B2', [5]);
  for (final cell in cells) {
    if (cell != 'B2') {
      p.addVariable(cell, [1, 2, 3, 4, 6, 7, 8, 9]);
    }
  }

  p.addAllDifferent(cells);

  // All rows, columns, and diagonals sum to 15.
  p.addStringConstraints([
    'A1 + A2 + A3 == 15',
    'B1 + B2 + B3 == 15',
    'C1 + C2 + C3 == 15',
    'A1 + B1 + C1 == 15',
    'A2 + B2 + C2 == 15',
    'A3 + B3 + C3 == 15',
    'A1 + B2 + C3 == 15',
    'A3 + B2 + C1 == 15'
  ]);

  final solution = await p.getSolution();
  if (solution is Map) {
    print('Magic Square found:');
    print('${solution['A1']} ${solution['A2']} ${solution['A3']}');
    print('${solution['B1']} ${solution['B2']} ${solution['B3']}');
    print('${solution['C1']} ${solution['C2']} ${solution['C3']}');
  } else {
    print('No solution found');
  }
  print('');
}

/// 4-Queens example
Future<void> nQueensExample() async {
  print('6. 4-Queens Problem:');

  final p = Problem();
  final queens = ['Q1', 'Q2', 'Q3', 'Q4'];
  p.addVariables(queens, [1, 2, 3, 4]);

  // No two queens in same column
  p.addAllDifferent(queens);

  // No two queens on same diagonal
  for (var i = 0; i < queens.length; i++) {
    for (var j = i + 1; j < queens.length; j++) {
      final qi = queens[i];
      final qj = queens[j];

      // No diagonal attacks: |row_i - row_j| != |col_i - col_j|
      // Since col_i = i+1 and col_j = j+1, this becomes:
      // |position_i - position_j| != |i - j|
      final colDiff = (j - i).abs();

      p.addConstraint([qi, qj], (dynamic posI, dynamic posJ) {
        final rowDiff = (posI - posJ).abs();
        return rowDiff != colDiff;
      });
    }
  }

  final solution = await p.getSolution();
  if (solution is Map) {
    print('4-Queens solution:');
    for (var row = 1; row <= 4; row++) {
      var line = '';
      for (var col = 1; col <= 4; col++) {
        final queenCol = solution['Q$row'];
        line += queenCol == col ? 'Q ' : '. ';
      }
      print(line);
    }
  } else {
    print('No solution found');
  }
  print('');
}

/// Using convenience functions
Future<void> convenienceFunctionsExample() async {
  print('7. Convenience Functions:');

  // Quick all-different problem
  print('All-different problem:');
  var solution =
      await solveAllDifferent(variables: ['A', 'B', 'C'], domain: [1, 2, 3]);
  print('Solution: $solution');

  // Quick sum problem
  print('Sum problem:');
  solution = await solveSumProblem(
      variables: ['X', 'Y'], domain: [1, 2, 3, 4, 5], targetSum: 7);
  print('Solution: $solution');

  // General string constraint problem
  print('General string constraint problem:');
  solution = await solveProblem(variables: {
    'A': [1, 2, 3, 4],
    'B': [1, 2, 3, 4],
    'C': [1, 2, 3, 4]
  }, constraints: [
    'A != B',
    'B != C',
    'A + B == C'
  ]);
  print('Solution: $solution\n');
}

/// Example showing problem debugging features
Future<void> debuggingExample() async {
  print('8. Problem Debugging:');

  final p = Problem();
  p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
  p.addStringConstraint('A != B');

  // Print problem summary
  p.printSummary();

  // Validate problem
  final issues = p.validate();
  if (issues.isEmpty) {
    print('Problem validation: ✓ No issues found');
  } else {
    print('Problem validation issues:');
    for (final issue in issues) {
      print('  - $issue');
    }
  }
  print('');
}

/// Performance comparison example
Future<void> performanceExample() async {
  print('9. Performance Comparison:');

  // Large all-different problem with different constraint types
  const n = 8;
  final domain = List.generate(n, (i) => i + 1);
  final variables = List.generate(n, (i) => 'V$i');

  // Lambda constraints
  final stopwatch1 = Stopwatch()..start();
  final p1 = Problem();
  p1.addVariables(variables, domain);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      p1.addConstraint(
          [variables[i], variables[j]], (dynamic a, dynamic b) => a != b);
    }
  }
  final solution1 = await p1.getSolution();
  stopwatch1.stop();

  // Built-in constraints
  final stopwatch2 = Stopwatch()..start();
  final p2 = Problem();
  p2.addVariables(variables, domain);
  p2.addAllDifferent(variables);
  final solution2 = await p2.getSolution();
  stopwatch2.stop();

  // String constraints
  final stopwatch3 = Stopwatch()..start();
  final p3 = Problem();
  p3.addVariables(variables, domain);
  final constraints = <String>[];
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      constraints.add('${variables[i]} != ${variables[j]}');
    }
  }
  p3.addStringConstraints(constraints);
  final solution3 = await p3.getSolution();
  stopwatch3.stop();

  print('Results for $n-variable all-different problem:');
  print('Lambda constraints:   ${stopwatch1.elapsedMilliseconds}ms');
  print('Built-in constraints: ${stopwatch2.elapsedMilliseconds}ms');
  print('String constraints:   ${stopwatch3.elapsedMilliseconds}ms');
  print(
      'All found same solution: ${solution1 == solution2 && solution2 == solution3}');
}

/// Error handling example
Future<void> errorHandlingExample() async {
  print('10. Error Handling:');

  try {
    final p = Problem();
    p.addVariable('A', [1, 2, 3]);

    // This should fail - B is not defined
    p.addStringConstraint('A + B == 5');
  } catch (e) {
    print('Caught expected error: $e');
  }

  try {
    final p = Problem();
    p.addVariable('A', []); // Empty domain should fail
  } catch (e) {
    print('Caught expected error: $e');
  }

  print('');
}

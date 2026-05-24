/// Complete examples demonstrating multiple solutions functionality
library;

import 'package:dart_csp/dart_csp.dart';

void main() async {
  print('=== Multiple Solutions Examples ===\n');

  await basicMultipleSolutionsExample();
  await convenientMethodsExample();
  await practicalApplicationsExample();
  await performanceComparisonExample();
  await runAdvancedExamples();
}

/// Basic example showing how to find all solutions
Future<void> basicMultipleSolutionsExample() async {
  print('1. Basic Multiple Solutions Example');
  print('   Problem: Find all solutions where A < B with domain [1, 2, 3]');

  final p = Problem();
  p.addVariables(['A', 'B'], [1, 2, 3]);
  p.addStringConstraint('A < B');

  print('   Solutions found:');
  await for (final solution in p.getSolutions()) {
    print('   $solution');
  }

  print('');
}

/// Example showing convenient utility methods
Future<void> convenientMethodsExample() async {
  print('2. Convenient Utility Methods');

  final p = Problem();
  p.addVariables(['X', 'Y', 'Z'], [1, 2, 3]);
  p.addStringConstraints(['X != Y', 'Y != Z', 'X != Z']);

  // Count solutions without storing them (memory efficient)
  final count = await p.countSolutions();
  print('   Total solutions for all-different on 3 variables: $count');

  // Check if multiple solutions exist
  final hasMultiple = await p.hasMultipleSolutions();
  print('   Has multiple solutions: $hasMultiple');

  // Get first few solutions
  final firstThree = await p.getFirstNSolutions(3);
  print('   First 3 solutions:');
  for (final solution in firstThree) {
    print('   $solution');
  }

  print('');
}

/// Practical applications showing real-world usage
Future<void> practicalApplicationsExample() async {
  print('3. Practical Applications');

  // Example 1: Find all ways to make change for $1 using quarters, dimes, nickels
  await makeChangeExample();

  // Example 2: Find all valid 2x2 magic squares
  await miniMagicSquareExample();

  // Example 3: Resource allocation scenarios
  await resourceAllocationExample();
}

/// Make change example - find all ways to make $1.00
Future<void> makeChangeExample() async {
  print(
      '   3a. Make Change: All ways to make \$1.00 with quarters, dimes, nickels');

  final p = Problem();
  // Q = quarters (25¢), D = dimes (10¢), N = nickels (5¢)
  p.addVariables(['Q', 'D', 'N'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20]);

  // Total must equal 100 cents
  p.addStringConstraint('25*Q + 10*D + 5*N == 100');

  final solutions = await p.getAllSolutions();
  print('       Found ${solutions.length} ways to make change:');

  for (final solution in solutions) {
    final q = solution['Q'];
    final d = solution['D'];
    final n = solution['N'];
    print('       $q quarters + $d dimes + $n nickels = \$1.00');
  }
  print('');
}

/// Find all 2x2 magic squares (where rows and columns sum to same value)
Future<void> miniMagicSquareExample() async {
  print('   3b. All 2x2 Magic Squares using numbers 1-4');

  final p = Problem();
  p.addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4]);

  // All numbers must be different
  p.addAllDifferent(['A', 'B', 'C', 'D']);

  // Magic square condition: all rows and columns sum to same value
  // Layout: A B
  //         C D
  p.addStringConstraints([
    'A + B == C + D', // Row sums equal
    'A + C == B + D', // Column sums equal
  ]);

  final solutions = await p.getAllSolutions();
  print('       Found ${solutions.length} magic squares:');

  for (final solution in solutions) {
    final a = solution['A'], b = solution['B'];
    final c = solution['C'], d = solution['D'];
    final rowSum = a + b;
    print('       $a $b   (sums: $rowSum)');
    print('       $c $d');
    print('');
  }
}

/// Resource allocation with multiple valid scenarios
Future<void> resourceAllocationExample() async {
  print(
      '   3c. Resource Allocation: All ways to distribute 10 units among 3 teams');
  print(
      '       Each team needs at least 2 units, Team A needs at least as much as Team B');

  final p = Problem();
  p.addVariables(['TeamA', 'TeamB', 'TeamC'], [2, 3, 4, 5, 6]);

  p.addStringConstraints([
    'TeamA + TeamB + TeamC == 10', // Total budget
    'TeamA >= TeamB', // Team A priority
    'TeamA >= 2', // Minimum allocations
    'TeamB >= 2',
    'TeamC >= 2',
  ]);

  final solutions = await p.getAllSolutions();
  print('       Found ${solutions.length} allocation strategies:');

  for (final solution in solutions) {
    final a = solution['TeamA'];
    final b = solution['TeamB'];
    final c = solution['TeamC'];
    print('       Team A: $a, Team B: $b, Team C: $c');
  }
  print('');
}

/// Performance comparison between single and multiple solution approaches
Future<void> performanceComparisonExample() async {
  print('4. Performance Comparison');

  final p = Problem();
  p.addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4, 5]);
  p.addStringConstraints([
    'A != B != C != D', // All different
    'A + B + C + D >= 12', // Some additional constraint
  ]);

  // Time finding first solution
  final stopwatch1 = Stopwatch()..start();
  final firstSolution = await p.getSolution();
  stopwatch1.stop();

  // Time finding all solutions
  final stopwatch2 = Stopwatch()..start();
  final allSolutions = await p.getAllSolutions();
  stopwatch2.stop();

  // Time counting solutions (memory efficient)
  final stopwatch3 = Stopwatch()..start();
  final count = await p.countSolutions();
  stopwatch3.stop();

  print(
      '   First solution: $firstSolution (${stopwatch1.elapsedMilliseconds}ms)');
  print(
      '   All solutions: ${allSolutions.length} found (${stopwatch2.elapsedMilliseconds}ms)');
  print('   Count solutions: $count (${stopwatch3.elapsedMilliseconds}ms)');
  print(
      '   Memory usage: getAllSolutions() stores all, countSolutions() uses O(1) memory');
  print('');
}

/// Advanced example: Using convenience functions from the main library
Future<void> advancedConvenienceFunctionsExample() async {
  print('5. Advanced Convenience Functions');

  // Using top-level convenience functions
  print('   5a. Using solveAllProblems() convenience function:');
  final solutions1 = <Map<String, dynamic>>[];
  await for (final solution in solveAllProblems(variables: {
    'A': [1, 2, 3],
    'B': [1, 2, 3]
  }, constraints: [
    'A < B'
  ])) {
    solutions1.add(solution);
  }
  print(
      '       Found ${solutions1.length} solutions using convenience function');

  // Count without creating Problem object
  print('   5b. Using countAllSolutions() convenience function:');
  final count = await countAllSolutions(variables: {
    'X': [1, 2, 3, 4],
    'Y': [1, 2, 3, 4]
  }, constraints: [
    'X != Y'
  ]);
  print('       Problem has $count solutions');

  // Check for uniqueness
  print('   5c. Using hasMultipleSolutions() convenience function:');
  final hasMultiple = await hasMultipleSolutions(
      variables: {
        'P': [1],
        'Q': [2]
      }, // Only one possible solution
      constraints: [
        'P < Q'
      ]);
  print('       Has multiple solutions: $hasMultiple');

  // Get first few efficiently
  print('   5d. Using getFirstNSolutions() convenience function:');
  final firstTwo = await getFirstNSolutions(n: 2, variables: {
    'A': [1, 2, 3, 4],
    'B': [1, 2, 3, 4]
  }, constraints: [
    'A > B'
  ]);
  print('       First 2 solutions: $firstTwo');

  print('');
}

/// Example showing when to use streams vs lists
Future<void> streamVsListGuidance() async {
  print('6. When to Use Streams vs Lists');

  final p = Problem();
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  p.addAllDifferent(['A', 'B', 'C']);

  print('   This problem has many solutions...');

  // Use stream when you want to process solutions one by one
  print('   ✓ Use getSolutions() stream when:');
  print('     - Processing solutions one at a time');
  print('     - Memory usage is a concern');
  print('     - You might not need all solutions');
  print('     - Early termination conditions exist');

  var processedCount = 0;
  await for (final _ in p.getSolutions()) {
    processedCount++;
    // Example: stop after processing 10 solutions
    if (processedCount >= 10) {
      print('     Processed first 10 solutions, stopping early');
      break;
    }
  }

  print('   ✓ Use getAllSolutions() list when:');
  print('     - Need to access solutions multiple times');
  print('     - Performing analysis on the complete solution set');
  print('     - Small number of expected solutions');
  print('     - Need random access to solutions');

  // Only get all solutions if the count is reasonable
  final totalCount = await p.countSolutions();
  if (totalCount <= 100) {
    await p.getAllSolutions();
    print('     Got all $totalCount solutions for analysis');
  } else {
    print('     Too many solutions ($totalCount) to collect in memory');
  }

  print('');
}

/// Complete workflow example
Future<void> completeWorkflowExample() async {
  print('7. Complete Workflow Example: Analyzing a Scheduling Problem');

  final p = Problem();
  // Schedule 3 classes in 4 time slots
  p.addVariables(['Math', 'Science', 'English'], [1, 2, 3, 4]);

  // Constraints
  p.addStringConstraints([
    'Math != Science', // Different times
    'Math != English',
    'Science != English',
    'Math < Science', // Math must be before Science
  ]);

  // Step 1: Check if problem has solutions
  final firstSolution = await p.getSolution();
  if (firstSolution == 'FAILURE') {
    print('   No solutions found!');
    return;
  }
  print('   ✓ Problem has solutions. Example: $firstSolution');

  // Step 2: Check if multiple solutions exist
  final hasMultiple = await p.hasMultipleSolutions();
  print('   ✓ Multiple solutions exist: $hasMultiple');

  // Step 3: Count total solutions
  final count = await p.countSolutions();
  print('   ✓ Total solutions available: $count');

  // Step 4: Analyze all solutions
  if (count <= 20) {
    // Only if reasonable number
    final allSolutions = await p.getAllSolutions();

    print('   ✓ All scheduling options:');
    for (var i = 0; i < allSolutions.length; i++) {
      final solution = allSolutions[i];
      print(
          '     Option ${i + 1}: Math@${solution['Math']}, Science@${solution['Science']}, English@${solution['English']}');
    }

    // Find optimal solution (e.g., minimize latest class time)
    var bestSolution = allSolutions.first;
    var minLatestTime = [
      bestSolution['Math'],
      bestSolution['Science'],
      bestSolution['English']
    ].reduce((a, b) => (a as num) > (b as num) ? a : b);

    for (final solution in allSolutions) {
      final latestTime = [
        solution['Math'],
        solution['Science'],
        solution['English']
      ].reduce((a, b) => (a as num) > (b as num) ? a : b);
      if ((latestTime as num) < (minLatestTime as num)) {
        minLatestTime = latestTime;
        bestSolution = solution;
      }
    }

    print('   ✓ Optimal solution (earliest finish): $bestSolution');
  } else {
    print('   ⚠ Too many solutions to analyze individually');
  }

  print('');
}

/// Run the advanced examples
Future<void> runAdvancedExamples() async {
  await advancedConvenienceFunctionsExample();
  await streamVsListGuidance();
  await completeWorkflowExample();
}

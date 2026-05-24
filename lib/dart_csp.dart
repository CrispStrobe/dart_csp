/// A generic library for solving Constraint Satisfaction Problems (CSPs).
///
/// This solver finds solutions by using a backtracking search algorithm enhanced
/// with forward checking (consistency enforcement) and heuristics to prune the
/// search space efficiently. It supports both binary (between two variables)
/// and n-ary (among multiple variables) constraints.
///
library dart_csp;

import 'src/problem.dart';
import 'src/types.dart';

// Built-in constraint factories
export 'src/builtin_constraints.dart';
// String constraint parsing
export 'src/constraint_parser.dart';
// Main problem builder
export 'src/problem.dart';
// CSP solver
export 'src/solver.dart';
// Core types and definitions
export 'src/types.dart';

/// Convenience function to create a new Problem instance
Problem createProblem() => Problem();

/// Convenience function to solve a problem with variables and constraints
///
/// Example:
/// ```dart
/// final solution = await solveProblem(
///   variables: {'A': [1, 2, 3], 'B': [1, 2, 3]},
///   constraints: ['A != B']
/// );
/// ```
Future<dynamic> solveProblem({
  required Map<String, List<dynamic>> variables,
  required List<String> constraints,
  int? timeStep,
  CspCallback? callback,
}) async {
  final problem = Problem();

  // Add variables
  for (final entry in variables.entries) {
    problem.addVariable(entry.key, entry.value);
  }

  // Add string constraints
  problem.addStringConstraints(constraints);

  // Set options if provided
  if (timeStep != null || callback != null) {
    problem.setOptions(timeStep: timeStep, callback: callback);
  }

  return problem.getSolution();
}

/// Convenience function to find all solutions to a problem with string constraints
///
/// Example:
/// ```dart
/// final solutions = <Map<String, dynamic>>[];
/// await for (final solution in solveAllProblems(
///   variables: {'A': [1, 2, 3], 'B': [1, 2, 3]},
///   constraints: ['A < B']
/// )) {
///   solutions.add(solution);
/// }
/// print('Found ${solutions.length} solutions');
/// ```
Stream<Map<String, dynamic>> solveAllProblems({
  required Map<String, List<dynamic>> variables,
  required List<String> constraints,
}) async* {
  final problem = Problem();

  // Add variables
  for (final entry in variables.entries) {
    problem.addVariable(entry.key, entry.value);
  }

  // Add string constraints
  problem.addStringConstraints(constraints);

  // Stream all solutions
  yield* problem.getSolutions();
}

/// Quick helper for common all-different problems
///
/// Example:
/// ```dart
/// final solution = await solveAllDifferent(
///   variables: ['A', 'B', 'C'],
///   domain: [1, 2, 3]
/// );
/// ```
Future<dynamic> solveAllDifferent({
  required List<String> variables,
  required List<dynamic> domain,
}) async {
  final problem = Problem();
  problem.addVariables(variables, domain);
  problem.addAllDifferent(variables);
  return problem.getSolution();
}

/// Quick helper for finding all solutions to all-different problems
///
/// Example:
/// ```dart
/// final solutions = <Map<String, dynamic>>[];
/// await for (final solution in solveAllDifferentMultiple(
///   variables: ['A', 'B'],
///   domain: [1, 2, 3]
/// )) {
///   solutions.add(solution);
/// }
/// ```
Stream<Map<String, dynamic>> solveAllDifferentMultiple({
  required List<String> variables,
  required List<dynamic> domain,
}) async* {
  final problem = Problem();
  problem.addVariables(variables, domain);
  problem.addAllDifferent(variables);
  yield* problem.getSolutions();
}

/// Quick helper for sum constraint problems
///
/// Example:
/// ```dart
/// final solution = await solveSumProblem(
///   variables: ['A', 'B', 'C'],
///   domain: [1, 2, 3, 4, 5],
///   targetSum: 10
/// );
/// ```
Future<dynamic> solveSumProblem({
  required List<String> variables,
  required List<dynamic> domain,
  required num targetSum,
  List<num>? multipliers,
}) async {
  final problem = Problem();
  problem.addVariables(variables, domain);
  problem.addExactSum(variables, targetSum, multipliers: multipliers);
  return problem.getSolution();
}

/// Quick helper for finding all solutions to sum constraint problems
///
/// Example:
/// ```dart
/// final solutions = <Map<String, dynamic>>[];
/// await for (final solution in solveSumProblemMultiple(
///   variables: ['X', 'Y'],
///   domain: [1, 2, 3, 4, 5],
///   targetSum: 7
/// )) {
///   solutions.add(solution);
/// }
/// ```
Stream<Map<String, dynamic>> solveSumProblemMultiple({
  required List<String> variables,
  required List<dynamic> domain,
  required num targetSum,
  List<num>? multipliers,
}) async* {
  final problem = Problem();
  problem.addVariables(variables, domain);
  problem.addExactSum(variables, targetSum, multipliers: multipliers);
  yield* problem.getSolutions();
}

/// Utility function to count solutions without storing them in memory
///
/// This is memory-efficient for problems with many solutions.
///
/// Example:
/// ```dart
/// final count = await countAllSolutions(
///   variables: {'A': [1, 2, 3, 4], 'B': [1, 2, 3, 4]},
///   constraints: ['A != B']
/// );
/// print('Problem has $count solutions');
/// ```
Future<int> countAllSolutions({
  required Map<String, List<dynamic>> variables,
  required List<String> constraints,
}) async {
  var count = 0;
  await for (final _ in solveAllProblems(
    variables: variables,
    constraints: constraints,
  )) {
    count++;
  }
  return count;
}

/// Utility function to check if a problem has multiple solutions
///
/// This is efficient as it stops after finding the second solution.
///
/// Example:
/// ```dart
/// final hasMultiple = await hasMultipleSolutions(
///   variables: {'A': [1, 2], 'B': [1, 2]},
///   constraints: ['A != B']
/// );
/// ```
Future<bool> hasMultipleSolutions({
  required Map<String, List<dynamic>> variables,
  required List<String> constraints,
}) async {
  var count = 0;
  await for (final _ in solveAllProblems(
    variables: variables,
    constraints: constraints,
  )) {
    count++;
    if (count >= 2) return true;
  }
  return false;
}

/// Utility function to get the first N solutions efficiently
///
/// Example:
/// ```dart
/// final firstThree = await getFirstNSolutions(
///   n: 3,
///   variables: {'A': [1, 2, 3, 4], 'B': [1, 2, 3, 4]},
///   constraints: ['A < B']
/// );
/// ```
Future<List<Map<String, dynamic>>> getFirstNSolutions({
  required int n,
  required Map<String, List<dynamic>> variables,
  required List<String> constraints,
}) async {
  final solutions = <Map<String, dynamic>>[];
  var count = 0;
  await for (final solution in solveAllProblems(
    variables: variables,
    constraints: constraints,
  )) {
    solutions.add(solution);
    count++;
    if (count >= n) break;
  }
  return solutions;
}

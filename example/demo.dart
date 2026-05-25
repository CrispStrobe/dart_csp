// Import the CSP library. Ensure dart_csp.dart is in the same directory.
import 'dart:math';
import 'package:dart_csp/dart_csp.dart';

/// Main entry point for the comprehensive demonstrations.
Future<void> main() async {
  print('🚀 DART CSP COMPREHENSIVE DEMO - Testing All Built-in Constraints');
  print('=' * 70);

  await runBundeslaenderColoringDemo();
  await runEightQueensDemo();
  await runManualVsBuilderDemo();
  await runSudokuDemo();

  // NeConstraint-specific demos
  await runAllDifferentEqualDemo();
  await runSumConstraintsDemo();
  await runProductConstraintsDemo();
  await runSetMembershipDemo();
  await runOrderingConstraintsDemo();
  await runMagicSquareDemo();
  await runResourceAllocationDemo();
  await runSchedulingDemo();

  print('\n${'=' * 70}');
  print('🎉 All demos completed successfully!');
}

/// Prints a formatted header to the console.
void printHeader(String title) {
  print('\n${'─' * 50}');
  print('─ $title');
  print('─' * 50);
}

/// Prints a sub-section header
void printSubHeader(String title) {
  print('\n   ► $title');
  print('   ${'─' * (title.length + 2)}');
}

// ====================================================================
// DEMO: Map Coloring (German Bundesländer)
// ====================================================================
//
// Classic AIMA-style map-coloring problem (Russell & Norvig, "AI: A
// Modern Approach", chapter on CSPs). Each region is a variable; its
// domain is the available palette; the constraint between two
// regions that share a land border is inequality. Four colors
// suffice for any planar map (Four Color Theorem, Appel & Haken
// 1976), so the palette below has four entries.
//
// The 16 German states (Bundesländer) and their pairwise land
// borders were enumerated by hand and then cross-checked against
// the Geography sections of each state's English-language
// Wikipedia article (e.g. en.wikipedia.org/wiki/Lower_Saxony,
// /Brandenburg, /Thuringia, /Mecklenburg-Vorpommern,
// /Saxony-Anhalt). Only land borders between German states are
// listed; international borders, sea coast, and inland-water-only
// adjacencies are excluded. Berlin is treated as enclaved within
// Brandenburg, Bremen as enclaved within Lower Saxony.

Future<void> runBundeslaenderColoringDemo() async {
  printHeader('Map Coloring — German Bundesländer (16 regions, 4 colors)');

  final palette = ['red', 'green', 'blue', 'yellow'];
  final regions = germanStateAdjacencies().keys.toList()..sort();

  final p = Problem();
  p.addVariables(regions, palette);

  // Walk the adjacency map once, only emitting each undirected edge in
  // a single direction so addConstraint isn't called twice per pair.
  final emitted = <String>{};
  for (final entry in germanStateAdjacencies().entries) {
    final a = entry.key;
    for (final b in entry.value) {
      final edge = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      if (emitted.add(edge)) {
        p.addConstraint([a, b], (dynamic ca, dynamic cb) => ca != cb);
      }
    }
  }

  final solution = await p.getSolution();
  printResult(solution,
      successMessage: 'Found a valid 4-coloring for all 16 Bundesländer.');

  if (solution is Map<String, dynamic>) {
    print('\n   Color assignment:');
    final byColor = <String, List<String>>{};
    for (final region in regions) {
      final color = solution[region] as String;
      byColor.putIfAbsent(color, () => <String>[]).add(region);
    }
    for (final color in palette) {
      final names = byColor[color] ?? const <String>[];
      if (names.isNotEmpty) {
        print('   $color: ${names.join(', ')}');
      }
    }
  }
}

/// Returns an undirected adjacency map of the 16 German Bundesländer.
///
/// Keys are the standard ISO 3166-2:DE region codes (e.g. `BW` for
/// Baden-Württemberg). Each value lists the regions that share a
/// land border with the key region. The map is symmetric: if `A` is
/// in `adj[B]` then `B` is in `adj[A]`.
// ISO 3166-2:DE codes used as keys / values:
//   BW Baden-Württemberg, BY Bayern, BE Berlin, BB Brandenburg,
//   HB Bremen, HH Hamburg, HE Hessen, MV Mecklenburg-Vorpommern,
//   NI Niedersachsen, NW Nordrhein-Westfalen, RP Rheinland-Pfalz,
//   SL Saarland, SN Sachsen, ST Sachsen-Anhalt,
//   SH Schleswig-Holstein, TH Thüringen.
Map<String, List<String>> germanStateAdjacencies() => {
      'BW': ['BY', 'HE', 'RP'],
      'BY': ['BW', 'HE', 'SN', 'TH'],
      'BE': ['BB'],
      'BB': ['BE', 'MV', 'NI', 'SN', 'ST'],
      'HB': ['NI'],
      'HH': ['NI', 'SH'],
      'HE': ['BW', 'BY', 'NI', 'NW', 'RP', 'TH'],
      'MV': ['BB', 'NI', 'SH'],
      'NI': ['BB', 'HB', 'HE', 'HH', 'MV', 'NW', 'SH', 'ST', 'TH'],
      'NW': ['HE', 'NI', 'RP'],
      'RP': ['BW', 'HE', 'NW', 'SL'],
      'SL': ['RP'],
      'SN': ['BB', 'BY', 'ST', 'TH'],
      'ST': ['BB', 'NI', 'SN', 'TH'],
      'SH': ['HH', 'MV', 'NI'],
      'TH': ['BY', 'HE', 'NI', 'SN', 'ST'],
    };

// ====================================================================
// DEMO: N-Queens (textbook integer-column encoding)
// ====================================================================
//
// Standard AIMA encoding: one CSP variable per board row, with the
// column the queen occupies as that variable's value. The domain of
// every row variable is the set of integer columns [0 .. N-1]. With
// this representation:
//
//   * Two queens never share a row (each row has exactly one
//     variable, which has exactly one assigned value).
//   * The same-column attack is encoded by `col_i != col_j`.
//   * The diagonal attack between rows i and j is encoded by
//     |col_i - col_j| != |i - j| (slope of the connecting line
//     would otherwise be ±1).
//
// Both attack types collapse into a single binary predicate, which
// is then posted between every pair of distinct rows.

Future<void> runEightQueensDemo() async {
  printHeader('N-Queens (8 queens, integer column encoding)');
  await placeQueens(8);
}

Future<void> placeQueens(int n) async {
  final p = Problem();
  final rows = List.generate(n, (i) => 'r$i');
  final columns = List.generate(n, (i) => i);
  p.addVariables(rows, columns);

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final rowDelta = j - i;
      p.addConstraint([rows[i], rows[j]], (dynamic colI, dynamic colJ) {
        final ci = colI as int;
        final cj = colJ as int;
        if (ci == cj) return false;
        return (ci - cj).abs() != rowDelta;
      });
    }
  }

  print('   Solving the $n-queens problem...');
  final solution = await p.getSolution();
  printResult(solution,
      successMessage: 'Placed $n queens without mutual attack.');

  if (solution is Map<String, dynamic>) {
    print('\n   Board (Q = queen, . = empty):');
    for (var r = 0; r < n; r++) {
      final col = solution['r$r'] as int;
      final cells = List<String>.generate(n, (c) => c == col ? 'Q' : '.');
      print('   ${cells.join(' ')}');
    }
  }
}

// ====================================================================
// DEMO: Manual CspProblem + BinaryConstraint vs. Problem builder
// ====================================================================
//
// The two demos below solve the same toy ordering puzzle two ways:
//
//   1. By assembling a `CspProblem` directly: building the variable
//      map and a list of `BinaryConstraint` arcs by hand, then
//      calling `CSP.solve(...)` on it. This is the lowest-level
//      public API surface.
//   2. By using the `Problem` builder, which exposes a fluent
//      `addVariable` / `addConstraint` API and reifies the
//      underlying `CspProblem` lazily inside `getSolution`.
//
// Puzzle: find three values A < B < C drawn from the integer domain
// 1..4. The chain has exactly four solutions; we ask the solver for
// the first one it returns. Note that arc consistency is directed,
// so the manual formulation must post both `(A, B, a<b)` and
// `(B, A, a<b)` to cover the `B -> A` direction. The builder takes
// a single predicate per pair and synthesises the reverse arc
// internally — that's the main ergonomic difference visible here.

Future<void> runManualVsBuilderDemo() async {
  printHeader('Manual CspProblem vs. Problem Builder (A < B < C)');

  printSubHeader('Manual: build CspProblem + BinaryConstraint arcs by hand');
  await solveAscendingChainManually();

  printSubHeader('Builder: Problem().addConstraint(...)');
  await solveAscendingChainWithBuilder();
}

Future<void> solveAscendingChainManually() async {
  bool lessThan(dynamic head, dynamic tail) => (head as int) < (tail as int);
  bool greaterThan(dynamic head, dynamic tail) => (head as int) > (tail as int);

  final csp = CspProblem(
    variables: {
      'A': [1, 2, 3, 4],
      'B': [1, 2, 3, 4],
      'C': [1, 2, 3, 4],
    },
    constraints: [
      // A < B: post both arc directions so AC-3 propagates both ways.
      BinaryConstraint('A', 'B', lessThan),
      BinaryConstraint('B', 'A', greaterThan),
      // B < C
      BinaryConstraint('B', 'C', lessThan),
      BinaryConstraint('C', 'B', greaterThan),
    ],
  );

  final solution = await CSP.solve(csp);
  printResult(solution,
      successMessage: 'Manual API produced a valid (A, B, C).');
  if (solution is Map<String, dynamic>) {
    print('   A=${solution['A']}, B=${solution['B']}, C=${solution['C']}');
  }
}

Future<void> solveAscendingChainWithBuilder() async {
  final p = Problem();
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4]);
  p.addConstraint(
      ['A', 'B'], (dynamic a, dynamic b) => (a as int) < (b as int));
  p.addConstraint(
      ['B', 'C'], (dynamic b, dynamic c) => (b as int) < (c as int));

  final solution = await p.getSolution();
  printResult(solution,
      successMessage: 'Builder API produced a valid (A, B, C).');
  if (solution is Map<String, dynamic>) {
    print('   A=${solution['A']}, B=${solution['B']}, C=${solution['C']}');
  }
}

// ====================================================================
// DEMO: Sudoku (Enhanced)
// ====================================================================

Future<void> runSudokuDemo() async {
  printHeader('Sudoku (Enhanced)');
  final puzzle = [
    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9],
  ];

  printSubHeader('Enhanced Way (Using AllDifferent Extension Methods)');
  await solveSudokuWithBuiltins(puzzle);
}

Future<void> solveSudokuWithBuiltins(List<List<int>> puzzle) async {
  final p = Problem();
  final domain = List.generate(9, (i) => i + 1);

  // Add all 81 variables
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final key = '$r-$c';
      if (puzzle[r][c] != 0) {
        p.addVariable(key, [puzzle[r][c]]);
      } else {
        p.addVariable(key, domain);
      }
    }
  }

  // Add all-different constraints using the new extension method!
  // This is much cleaner than individual binary constraints

  // Rows
  for (var r = 0; r < 9; r++) {
    final row = <String>[];
    for (var c = 0; c < 9; c++) {
      row.add('$r-$c');
    }
    p.addAllDifferent(row); // Using the new extension method!
  }

  // Columns
  for (var c = 0; c < 9; c++) {
    final col = <String>[];
    for (var r = 0; r < 9; r++) {
      col.add('$r-$c');
    }
    p.addAllDifferent(col); // Using the new extension method!
  }

  // 3x3 Blocks
  for (final br in [0, 3, 6]) {
    for (final bc in [0, 3, 6]) {
      final block = <String>[];
      for (var r = br; r < br + 3; r++) {
        for (var c = bc; c < bc + 3; c++) {
          block.add('$r-$c');
        }
      }
      p.addAllDifferent(block); // Using the new extension method!
    }
  }

  final solution = await p.getSolution();
  printResult(solution,
      successMessage: 'Sudoku solved with built-in AllDifferent!');
  if (solution is Map<String, dynamic>) printSudokuBoard(solution);
}

// ====================================================================
// DEMO 4: All Different and All Equal Constraints
// ====================================================================

Future<void> runAllDifferentEqualDemo() async {
  printHeader('All Different & All Equal Constraints Demo');

  printSubHeader('All Different Demo');
  await testAllDifferent();

  printSubHeader('All Equal Demo');
  await testAllEqual();
}

Future<void> testAllDifferent() async {
  final p = Problem();

  // Variables A, B, C must all be different
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4]);

  // Test both approaches
  print('   Using extension method: addAllDifferent()');
  p.addAllDifferent(['A', 'B', 'C']);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'All variables have different values!');

  // Test factory function approach
  final p2 = Problem();
  p2.addVariables(['X', 'Y'], [1, 2, 3]);

  print('   Using factory function: allDifferentBinary()');
  p2.addConstraint(['X', 'Y'], allDifferentBinary());

  final solution2 = await p2.getSolution();
  printResult(solution2, successMessage: 'X and Y are different!');
}

Future<void> testAllEqual() async {
  final p = Problem();

  // Variables must all have the same value
  p.addVariables(['A', 'B', 'C'], [1, 2, 3]);

  print('   Using extension method: addAllEqual()');
  p.addAllEqual(['A', 'B', 'C']);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'All variables have the same value!');
}

// ====================================================================
// DEMO 5: Sum Constraints
// ====================================================================

Future<void> runSumConstraintsDemo() async {
  printHeader('Sum Constraints Demo');

  printSubHeader('Exact Sum');
  await testExactSum();

  printSubHeader('Min/Max Sum');
  await testMinMaxSum();

  printSubHeader('Sum Range');
  await testSumRange();

  printSubHeader('Weighted Sum');
  await testWeightedSum();
}

Future<void> testExactSum() async {
  final p = Problem();

  // Find three numbers that sum to exactly 10
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5, 6]);

  print('   Finding A + B + C = 10');
  p.addExactSum(['A', 'B', 'C'], 10);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found numbers that sum to 10!');
  if (solution is Map<String, dynamic>) {
    final sum = solution['A'] + solution['B'] + solution['C'];
    print(
        '   Verification: ${solution['A']} + ${solution['B']} + ${solution['C']} = $sum');
  }
}

Future<void> testMinMaxSum() async {
  final p = Problem();

  // Variables that sum to at least 8 but at most 12
  p.addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4, 5]);

  print('   Finding X + Y + Z >= 8 and <= 12');
  p.addConstraint(['X', 'Y', 'Z'], minSum(8));
  p.addConstraint(['X', 'Y', 'Z'], maxSum(12));

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found numbers in range!');
  if (solution is Map<String, dynamic>) {
    final sum = solution['X'] + solution['Y'] + solution['Z'];
    print(
        '   Verification: ${solution['X']} + ${solution['Y']} + ${solution['Z']} = $sum');
  }
}

Future<void> testSumRange() async {
  final p = Problem();

  p.addVariables(['A', 'B'], [1, 2, 3, 4, 5, 6]);

  print('   Using sumInRange(4, 8)');
  p.addSumRange(['A', 'B'], 4, 8);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Sum is in range [4, 8]!');
  if (solution is Map<String, dynamic>) {
    final sum = solution['A'] + solution['B'];
    print('   Verification: ${solution['A']} + ${solution['B']} = $sum');
  }
}

Future<void> testWeightedSum() async {
  final p = Problem();

  // Weighted sum: 2*A + 3*B = 11
  p.addVariables(['A', 'B'], [1, 2, 3, 4]);

  print('   Finding 2*A + 3*B = 11');
  p.addExactSum(['A', 'B'], 11, multipliers: [2, 3]);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found weighted sum solution!');
  if (solution is Map<String, dynamic>) {
    final weightedSum = 2 * (solution['A'] as num) + 3 * (solution['B'] as num);
    print(
        '   Verification: 2*${solution['A']} + 3*${solution['B']} = $weightedSum');
  }
}

// ====================================================================
// DEMO 6: Product Constraints
// ====================================================================

Future<void> runProductConstraintsDemo() async {
  printHeader('Product Constraints Demo');

  printSubHeader('Exact Product');
  await testExactProduct();

  printSubHeader('Min/Max Product');
  await testMinMaxProduct();
}

Future<void> testExactProduct() async {
  final p = Problem();

  // Find numbers that multiply to exactly 12
  p.addVariables(['A', 'B'], [1, 2, 3, 4, 6, 12]);

  print('   Finding A * B = 12');
  p.addExactProduct(['A', 'B'], 12);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found numbers that multiply to 12!');
  if (solution is Map<String, dynamic>) {
    final product = solution['A'] * solution['B'];
    print('   Verification: ${solution['A']} * ${solution['B']} = $product');
  }
}

Future<void> testMinMaxProduct() async {
  final p = Problem();

  // Product between 6 and 20
  p.addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4]);

  print('   Finding X * Y * Z >= 6 and <= 20');
  p.addConstraint(['X', 'Y', 'Z'], minProduct(6));
  p.addConstraint(['X', 'Y', 'Z'], maxProduct(20));

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found product in range!');
  if (solution is Map<String, dynamic>) {
    final product = solution['X'] * solution['Y'] * solution['Z'];
    print(
        '   Verification: ${solution['X']} * ${solution['Y']} * ${solution['Z']} = $product');
  }
}

// ====================================================================
// DEMO 7: Set Membership Constraints
// ====================================================================

Future<void> runSetMembershipDemo() async {
  printHeader('Set Membership Constraints Demo');

  printSubHeader('In Set Constraint');
  await testInSet();

  printSubHeader('Not In Set Constraint');
  await testNotInSet();

  printSubHeader('Some In Set Constraint');
  await testSomeInSet();
}

Future<void> testInSet() async {
  final p = Problem();

  // Variables must be prime numbers
  p.addVariables(['A', 'B'], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

  final primes = {2, 3, 5, 7};
  print('   Variables must be prime: $primes');
  p.addInSet(['A', 'B'], primes);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found prime numbers!');
}

Future<void> testNotInSet() async {
  final p = Problem();

  // Variables cannot be even
  p.addVariables(['X', 'Y'], [1, 2, 3, 4, 5, 6]);

  final evens = {2, 4, 6};
  print('   Variables cannot be even: $evens');
  p.addNotInSet(['X', 'Y'], evens);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Found odd numbers!');
}

Future<void> testSomeInSet() async {
  final p = Problem();

  // At least 2 variables must be in the "special" set
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);

  final special = {1, 3, 5};
  print('   At least 2 variables must be from $special');
  p.addConstraint(['A', 'B', 'C'], someInSet(special, 2));

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'At least 2 are from special set!');
  if (solution is Map<String, dynamic>) {
    final inSpecial = solution.values.where(special.contains).length;
    print('   Verification: $inSpecial variables are in special set');
  }
}

// ====================================================================
// DEMO 8: Ordering Constraints
// ====================================================================

Future<void> runOrderingConstraintsDemo() async {
  printHeader('Ordering Constraints Demo');

  printSubHeader('Ascending Order');
  await testAscending();

  printSubHeader('Strictly Ascending Order');
  await testStrictlyAscending();

  printSubHeader('Descending Order');
  await testDescending();
}

Future<void> testAscending() async {
  final p = Problem();

  // Variables in non-decreasing order
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);

  print('   Variables in ascending order (A <= B <= C)');
  p.addAscending(['A', 'B', 'C']); // preserves order

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Variables are in ascending order!');
  if (solution is Map<String, dynamic>) {
    print(
        '   Verification: ${solution['A']} <= ${solution['B']} <= ${solution['C']}');
  }
}

Future<void> testStrictlyAscending() async {
  final p = Problem();

  // Variables in strictly increasing order
  p.addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4, 5]);

  print('   Variables in strictly ascending order (X < Y < Z)');
  p.addStrictlyAscending(['X', 'Y', 'Z']); // preserve order

  final solution = await p.getSolution();
  printResult(solution,
      successMessage: 'Variables are in strictly ascending order!');
  if (solution is Map<String, dynamic>) {
    print(
        '   Verification: ${solution['X']} < ${solution['Y']} < ${solution['Z']}');
  }
}

Future<void> testDescending() async {
  final p = Problem();

  // Variables in non-increasing order
  p.addVariables(['P', 'Q'], [1, 2, 3, 4]);

  print('   Variables in descending order (P >= Q)');
  p.addDescending(['P', 'Q']); // preserve order

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Variables are in descending order!');
  if (solution is Map<String, dynamic>) {
    print('   Verification: ${solution['P']} >= ${solution['Q']}');
  }
}

// ====================================================================
// DEMO 9: Magic Square
// ====================================================================

Future<void> runMagicSquareDemo() async {
  printHeader('3x3 Magic Square - One Random Clue');

  final p = Problem();
  final random = Random();

  print('   Generating one random clue to reduce search space...');

  // Generate one random clue
  final positions = ['00', '01', '02', '10', '11', '12', '20', '21', '22'];
  final randomPosition = positions[random.nextInt(positions.length)];
  final randomValue = random.nextInt(9) + 1; // 1-9

  print('   Random clue: Position $randomPosition = $randomValue');

  // Add the random clue
  p.addVariable(randomPosition, [randomValue]);

  // Add remaining variables with domain excluding the clue value
  final remainingDomain = List.generate(9, (i) => i + 1)..remove(randomValue);

  for (final pos in positions) {
    if (pos != randomPosition) {
      p.addVariable(pos, remainingDomain);
    }
  }

  print('   Setting up magic square constraints...');

  // All different (each number 1-9 appears exactly once)
  p.addAllDifferent(positions);

  // Sum constraints = 15 for all rows, columns, and diagonals

  // Rows
  p.addExactSum(['00', '01', '02'], 15); // Top row
  p.addExactSum(['10', '11', '12'], 15); // Middle row
  p.addExactSum(['20', '21', '22'], 15); // Bottom row

  // Columns
  p.addExactSum(['00', '10', '20'], 15); // Left column
  p.addExactSum(['01', '11', '21'], 15); // Middle column
  p.addExactSum(['02', '12', '22'], 15); // Right column

  // Diagonals
  p.addExactSum(['00', '11', '22'], 15); // Main diagonal
  p.addExactSum(['02', '11', '20'], 15); // Anti-diagonal

  print('   Solving magic square with random clue...');
  final solution = await p.getSolution();
  printResult(solution,
      successMessage: '3x3 Magic Square solved with one random clue!');

  if (solution is Map<String, dynamic>) {
    print('\n   Magic Square:');
    for (var r = 0; r < 3; r++) {
      final row = [solution['${r}0'], solution['${r}1'], solution['${r}2']];
      print('   ${row.join('  ')}');
    }

    // Verify sums
    print('\n   Verification:');
    // Rows
    for (var r = 0; r < 3; r++) {
      final sum = solution['${r}0'] + solution['${r}1'] + solution['${r}2'];
      print('   Row $r: $sum');
    }
    // Columns
    for (var c = 0; c < 3; c++) {
      final sum = solution['0$c'] + solution['1$c'] + solution['2$c'];
      print('   Col $c: $sum');
    }
    // Diagonals
    final diag1 = solution['00'] + solution['11'] + solution['22'];
    final diag2 = solution['02'] + solution['11'] + solution['20'];
    print('   Main diagonal: $diag1');
    print('   Anti-diagonal: $diag2');
  } else {
    print('   Note: Some random clues may make the puzzle unsolvable.');
    print('         Run again for a different random clue!');
  }
}

// ====================================================================
// DEMO 10: Resource Allocation
// ====================================================================

Future<void> runResourceAllocationDemo() async {
  printHeader('Resource Allocation Problem');

  final p = Problem();

  // Teams A, B, C get resource allocations (restricted domain for efficiency)
  p.addVariables(['TeamA', 'TeamB', 'TeamC'], [3, 4, 5, 6, 7, 8, 9, 10]);

  print('   Setting up resource allocation constraints...');

  // Total budget is exactly 20
  p.addExactSum(['TeamA', 'TeamB', 'TeamC'], 20);

  // Each team automatically gets at least 3 resources (enforced by domain)
  // Each team automatically gets at most 10 resources (enforced by domain)

  // TeamA gets at least as much as TeamB (priority constraint)
  // Create a proper BinaryPredicate function
  bool teamAPriority(dynamic a, dynamic b) => (a as num) >= (b as num);
  p.addConstraint(['TeamA', 'TeamB'], teamAPriority);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Resource allocation found!');

  if (solution is Map<String, dynamic>) {
    print('   Team A: ${solution['TeamA']} resources');
    print('   Team B: ${solution['TeamB']} resources');
    print('   Team C: ${solution['TeamC']} resources');
    print(
        '   Total: ${(solution['TeamA'] as num) + (solution['TeamB'] as num) + (solution['TeamC'] as num)} resources');
  }
}

// ====================================================================
// DEMO 11: Class Scheduling
// ====================================================================

Future<void> runSchedulingDemo() async {
  printHeader('Class Scheduling Problem');

  final p = Problem();

  // Time slots: 1=9AM, 2=10AM, 3=11AM, 4=1PM, 5=2PM
  final timeSlots = [1, 2, 3, 4, 5];

  // Classes to schedule
  p.addVariables(['Math', 'English', 'Science', 'History'], timeSlots);

  print('   Setting up scheduling constraints...');

  // All classes at different times
  p.addAllDifferent(['Math', 'English', 'Science', 'History']);

  // Math must be before lunch (slots 1-3)
  p.addInSet(['Math'], {1, 2, 3});

  // Science must be after lunch (slots 4-5)
  p.addInSet(['Science'], {4, 5});

  // English and History should be consecutive (for language block)
  p.addConstraint(
      ['English', 'History'], (dynamic e, dynamic h) => (e - h).abs() == 1);

  final solution = await p.getSolution();
  printResult(solution, successMessage: 'Class schedule found!');

  if (solution is Map<String, dynamic>) {
    final timeMap = {1: '9AM', 2: '10AM', 3: '11AM', 4: '1PM', 5: '2PM'};
    print('   Schedule:');
    solution.forEach((subject, time) {
      print('   $subject: ${timeMap[time]}');
    });
  }
}

// ====================================================================
// Helper Functions
// ====================================================================

/// Helper to get a list of 9 variable names for a row, column, or block.
List<List<String>> getSudokuUnits() {
  final units = <List<String>>[];
  // Rows and Columns
  for (var i = 0; i < 9; i++) {
    final row = <String>[];
    final col = <String>[];
    for (var j = 0; j < 9; j++) {
      row.add('$i-$j');
      col.add('$j-$i');
    }
    units.add(row);
    units.add(col);
  }
  // 3x3 Blocks
  for (final br in [0, 3, 6]) {
    for (final bc in [0, 3, 6]) {
      final block = <String>[];
      for (var r = br; r < br + 3; r++) {
        for (var c = bc; c < bc + 3; c++) {
          block.add('$r-$c');
        }
      }
      units.add(block);
    }
  }
  return units;
}

/// Prints the final result of a CSP.
void printResult(dynamic solution, {String successMessage = ''}) {
  if (solution == 'FAILURE') {
    print('   >>> Status: FAILURE ❌');
  } else {
    print('   >>> Status: SUCCESS ✅');
    if (successMessage.isNotEmpty) print('   $successMessage');
    if (solution is Map<String, dynamic> && solution.length <= 6) {
      // Print small solutions directly
      print('   Solution: $solution');
    }
  }
}

/// Prints a solved Sudoku board.
void printSudokuBoard(Map<dynamic, dynamic> solution) {
  const divider = '   |-------+-------+-------|';
  print('\n   Solved Sudoku:');
  print(divider);
  for (var r = 0; r < 9; r++) {
    var rowStr = '   | ';
    for (var c = 0; c < 9; c++) {
      rowStr += solution['$r-$c'].toString();
      rowStr += (c + 1) % 3 == 0 ? ' | ' : ' ';
    }
    print(rowStr);
    if ((r + 1) % 3 == 0) print(divider);
  }
}

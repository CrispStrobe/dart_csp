# dart_csp

[![Language: Dart](https://img.shields.io/badge/language-Dart-blue.svg)](https://dart.dev/)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen.svg)](#testing)

A powerful, general-purpose library for modeling and solving Constraint Satisfaction Problems (CSPs) in Dart. Built with intelligent backtracking search, consistency-checking algorithms, and smart heuristics to efficiently solve complex logic puzzles.

This library offers **three intuitive ways** to define constraints: **string expressions** for natural syntax, a high-level **Problem builder** for fast development, and a manual **CspProblem class** for direct control over the underlying structure.

> **Note**: An early version of the solver core in this repository was a Dart port of [csp.js](https://github.com/PrajitR/jusCSP) by Prajit Ramachandran. That code has since been replaced by a clean-room rewrite written from textbook references with no access to the upstream source. See [`NOTICE`](NOTICE) for the history.

## What is a Constraint Satisfaction Problem?

A CSP is a mathematical problem where you need to find values for variables that satisfy a set of constraints. Every CSP consists of three components:

| Component | Description | Example (Sudoku) |
|-----------|-------------|------------------|
| **Variables** | The unknowns you need to solve for | The 81 empty squares |
| **Domains** | Possible values each variable can take | Numbers 1-9 for each square |
| **Constraints** | Rules that restrict variable assignments | No repeats in rows/columns/blocks |

### Classic CSP Examples

- **Sudoku**: Variables are grid squares, domains are numbers 1-9, constraints prevent duplicates in rows/columns/blocks
- **Map Coloring**: Variables are regions, domains are colors, constraints prevent adjacent regions from having the same color  
- **N-Queens**: Variables are queen positions, domains are board squares, constraints prevent queens from attacking each other

## Features

This solver goes beyond brute-force search with the following implemented algorithms:

### Core Algorithms
- **Backtracking Search**: Intelligent depth-first search that backtracks when constraints are violated
- **AC-3 Algorithm**: Enforces arc consistency for binary constraints (two-variable rules)
- **Generalized Arc Consistency (GAC)**: Handles n-ary constraints (multi-variable rules)
- **Multiple Solution Finding**: Stream-based API to find all possible solutions efficiently

### Smart Heuristics
- **Minimum Remaining Values (MRV)**: Chooses the most constrained variable to assign next ("fail-first" principle)
- **Least Constraining Value (LCV)**: Selects values that preserve the most options for other variables

### Built-in Constraint Library
- **20+ Pre-built Constraints**: Common constraint patterns like `allDifferent()`, `exactSum()`, `ascending()`, etc.
- **Optimized Performance**: Built-in constraints are faster than equivalent lambda functions
- **Extension Methods**: Fluent API methods like `addAllDifferent()` for cleaner code

### FlatZinc frontend
- **Drop-in MiniZinc compatibility**: parse and solve `.fzn` files produced by `mzn2fzn` (or any other MiniZinc compiler).
- **CLI binary** `bin/dart_csp_fzn.dart` reads from a file path or stdin and emits the standard FlatZinc output format (`name = value;`, `----------`, `==========`), so it plugs straight into the MiniZinc solver-configuration pipeline.
- **Builtin coverage**: every primitive in the M1–M4 plan (int/bool comparisons, linear arithmetic, SAT-style clauses, `bool2int`), every standard global (`all_different`, `circuit`, `cumulative`, `disjunctive`, `diffn`, `inverse`, `regular`, `table_int`, `lex_*`, `nvalue`, `global_cardinality`, `bin_packing_load`, `value_precede_chain_int`, `array_int_element`), and every reified variant (`int_*_reif`, `int_lin_*_reif`, `bool_eq_reif`, `bool_clause_reif`).
- **Set variables**: bounded `var set of L..U` declarations and the set constraint family (`set_in`, `set_card`, `set_eq`/`set_ne`, `set_subset`/`set_superset`, `set_union`/`set_intersect`/`set_diff`/`set_symdiff`, plus `_reif` variants) map onto the [set-variable layer](#set-variables); solutions render as FlatZinc set literals.
- **Conflict explanation traces back to FlatZinc**: every lowered constraint carries a `<fzn_name>#<counter>` label so MUS output points straight at the source `.fzn`.

See [`doc/flatzinc.md`](doc/flatzinc.md) for the full reference.

### String Constraint Parsing
- **Natural Language Syntax**: Write constraints as strings like `"A + B == 10"` or `"A != B != C"`
- **Advanced Expression Support**: Complex expressions like `"5 <= A + B <= 7"` and `"A * B + C == 15"`
- **Variable Equations**: Support for `"A + B == C"` where one variable equals an expression of others
- **Set Membership**: Constraints like `"A in [1, 3, 5]"` for allowed value sets
- **Comprehensive Parser**: Handles arithmetic, comparisons, ranges, and chained operations

### Developer Features
- **Modular Architecture**: Clean separation of concerns across multiple focused modules
- **Comprehensive Test Suite**: Full test coverage with test cases covering all functionality
- **Multiple APIs**: Choose between string constraints, builder pattern, or manual construction
- **Fluent Builder API**: An intuitive Problem class to easily define your CSP
- **Rich Examples**: Complete demo showcasing all constraint types and problem-solving techniques
- **Debugging Tools**: Problem validation, summary printing, and step-by-step visualization
- **Type Safety**: Full Dart type system integration with proper error handling
- **Async Support**: Non-blocking solving with `Future`-based API

## Quick Start

### 1. Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  dart_csp: ^2.0.0
```

Then run:
```bash
dart pub get
```

### 2. Import and Use

```dart
import 'package:dart_csp/dart_csp.dart';
```

### 3. Your First Problem - Map Coloring

```dart
Future<void> main() async {
  final p = Problem();
  
  // Variables: Australian states, Domain: Colors
  p.addVariables(['WA', 'NT', 'SA', 'Q', 'NSW', 'V'], ['red', 'green', 'blue']);
  
  // Constraints using string expressions (easiest way!)
  p.addStringConstraints([
    'WA != SA',
    'NT != SA', 
    'Q != SA',
    'NSW != SA',
    'V != SA',
    'WA != NT',
    'NT != Q',
    'Q != NSW',
    'NSW != V'
  ]);
  
  // Get first solution
  final solution = await p.getSolution();
  print(solution); // {WA: red, NT: blue, SA: green, ...}
  
  // Or find all solutions
  print('All possible colorings:');
  await for (final solution in p.getSolutions()) {
    print(solution);
  }
}
```

### 4. Run the Comprehensive Demo

The library includes a complete demo showcasing all features:

```bash
dart run example/demo.dart
```

This runs several constraint satisfaction problems demonstrating:
- Sudoku Solving
- Magic Square Generation
- Resource Allocation
- Class Scheduling
- And more!

> Map-coloring and N-queens demos are currently being rewritten
> clean-room (see `REWRITE-DEMOS.md`); they'll be back in a
> follow-up commit.

## How to Use dart_csp

### Method 1: String Constraints (Recommended)

The most intuitive way - write constraints as natural expressions:

```dart
final p = Problem();

// 1. Add variables and domains
p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);

// 2. Add constraints using natural string syntax
p.addStringConstraints([
  'A != B != C',           // All different (chained)
  'A + B == 7',            // Exact sum
  'A < B < C',             // Strict ordering
  '5 <= A + B <= 8',       // Range constraint
  'A * B >= 6',            // Minimum product
  'A + B == C'             // Variable equation
]);

// 3. Solve
final solution = await p.getSolution();
```

**Supported String Constraint Syntax:**

| Pattern | Description | Example |
|---------|-------------|---------|
| **Equality/Inequality** | Variable comparisons | `"A == B"`, `"A != B"` |
| **Chained Operations** | Multiple comparisons | `"A != B != C"`, `"A < B < C"` |
| **Arithmetic Equality** | Exact sums/products | `"A + B == 10"`, `"A * B == 12"` |
| **Arithmetic Inequality** | Min/max constraints | `"A + B >= 5"`, `"A * B <= 20"` |
| **Range Constraints** | Bounded values | `"5 <= A + B <= 10"` |
| **Variable Equations** | Inter-variable relations | `"A + B == C"`, `"A * B == D"` |
| **Complex Expressions** | Mixed operations | `"2*A + 3*B == 15"`, `"A*B + C >= 10"` |
| **Set Membership** | Allowed values | `"A in [1, 3, 5]"` |
| **Single Variable** | Constant comparisons | `"A > 5"`, `"B != 3"` |

### Method 2: The Problem Builder

The Problem class provides a clean, step-by-step builder pattern with built-in constraints:

```dart
final p = Problem();

// 1. Add variables and domains
p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);

// 2. Use built-in constraints (highly optimized)
p.addAllDifferent(['A', 'B', 'C']);      // All different values
p.addExactSum(['A', 'B'], 7);            // A + B = 7
p.addAscending(['A', 'B', 'C']);         // A ≤ B ≤ C

// 3. Or define custom constraints with lambda functions
p.addConstraint(['A', 'B'], (a, b) => a * b <= 10);

// 4. Solve
final solution = await p.getSolution();
```

### Method 3: Manual CspProblem Construction

Direct access to underlying data structures for programmatic generation:

```dart
var variables = <String, List<dynamic>>{
  'A': [1, 2, 3],
  'B': [1, 2, 3, 4],
  'C': [3, 4, 5],
};

var binaryConstraints = <BinaryConstraint>[
  BinaryConstraint('A', 'B', (a, b) => a < b),
  BinaryConstraint('B', 'A', (b, a) => b > a),
];

final problem = CspProblem(
  variables: variables,
  constraints: binaryConstraints,
);

final solution = await CSP.solve(problem);
```

### Method 4: Typed Modelling DSL

A type-safe alternative that reads like arithmetic, using operator
overloading. `Model` wraps a `Problem`; `IntVar` and `LinearExpr` build
constraints without strings or lambdas.

```dart
final m = Model();
final x = m.intVar('x', 0, 10);
final y = m.intVar('y', 0, 10);

(x + y * 2).le(12);   // x + 2y <= 12   (scalar on the right: y * 2)
(x - y).eq(2);        // x - y == 2
x.ne(y);              // x != y

final sol = await m.problem.getSolution();
```

`LinearExpr` supports `+`, `-`, unary `-`, and `* scalar`; the relational
methods `eq` / `ne` / `le` / `lt` / `ge` / `gt` post a constraint (`lt` /
`gt` use integer-strict semantics). It is a thin, engine-free layer over
the existing linear-constraint helpers. `Model(existingProblem)` wraps a
problem you already built, and `m.ref('name')` references a variable added
directly on it. Note scalars must go on the right of `*` (`x * 2`, not
`2 * x` — Dart cannot dispatch the latter); use `x.scaled(2)` if you
prefer a named form.

## Built-in Constraint Library

The library provides optimized, reusable constraint functions for common patterns:

### Equality/Inequality Constraints

```dart
// All variables must have different values
p.addAllDifferent(['A', 'B', 'C', 'D']);

// All variables must have the same value  
p.addAllEqual(['X', 'Y', 'Z']);
```

### Arithmetic Constraints

```dart
// Sum constraints
p.addExactSum(['A', 'B', 'C'], 15);           // A + B + C = 15
p.addSumRange(['A', 'B'], 5, 10);             // 5 ≤ A + B ≤ 10

// Weighted sums
p.addExactSum(['A', 'B'], 20, multipliers: [3, 4]); // 3*A + 4*B = 20

// Product constraints  
p.addExactProduct(['X', 'Y'], 12);            // X * Y = 12
p.addConstraint(['A', 'B', 'C'], minProduct(8));     // A * B * C ≥ 8
```

### Set Membership Constraints

```dart
// Variables must be from allowed set
p.addInSet(['A', 'B'], {2, 3, 5, 7});        // Only prime numbers

// Variables cannot be from forbidden set
p.addNotInSet(['X', 'Y'], {2, 4, 6});        // No even numbers

// At least N variables must be from set
p.addConstraint(['A', 'B', 'C'], someInSet({1, 3, 5}, 2)); // ≥2 odd numbers
```

### Ordering Constraints

```dart
// Ordering (preserves variable sequence)
p.addAscending(['A', 'B', 'C']);             // A ≤ B ≤ C
p.addStrictlyAscending(['X', 'Y', 'Z']);     // X < Y < Z  
p.addDescending(['P', 'Q', 'R']);            // P ≥ Q ≥ R
```

### Symmetry-Breaking

Two kinds of symmetry recur in CSP modeling and dart_csp has a
primitive for each.

**Variable (or sequence) symmetry** — when two or more parts of your
problem are *interchangeable* (rows of a matrix, identical workers),
every solution has a dual obtained by swapping them. `addLexLeq` /
`addLexLt` between two equal-length variable lists keeps a single
canonical representative:

```dart
// Two interchangeable workers W1, W2 each picking two days.
// Keep only the assignment where W1's pair is lex-smaller than W2's.
p.addLexLt(['W1Day1', 'W1Day2'], ['W2Day1', 'W2Day2']);
```

Cuts the symmetric solution set exactly in half. Comparison uses
`Comparable`, so it works on `int`, `double`, `String`, etc. For
breaking row-permutation symmetry across more than two
interchangeable rows in one call, use `addLexChain(rows)` — sugar
that posts `lexLeq` between every consecutive pair (or `lexLt` with
`strict: true` to forbid equal rows).

```dart
// Three interchangeable rows. addLexChain keeps one canonical
// row-order per orbit; lex-leq is transitive on Comparable so
// the consecutive chain is equivalent to the full pairwise set.
p.addLexChain([
  ['r0a', 'r0b'],
  ['r1a', 'r1b'],
  ['r2a', 'r2b'],
]);
```

**Value symmetry** — when the labels assigned to interchangeable
alternatives (colors, agents, machine labels, bin IDs) can be
permuted without changing the solution structure, every solution has
`k!` permutations under relabeling. `addValuePrecedence` enforces a
canonical ordering: the first occurrence of each value must follow
the canonical sequence:

```dart
// Triangle K3, three interchangeable colors. Without symmetry
// breaking: 6 colorings (3! permutations of r,g,b). With:
// exactly 1 canonical representative (r,g,b).
final p = Problem()
  ..addVariables(['a', 'b', 'c'], ['r', 'g', 'b'])
  ..addAllDifferent(['a', 'b', 'c'])
  ..addValuePrecedence(['a', 'b', 'c'], ['r', 'g', 'b']);
```

Posts one n-ary precedence constraint per consecutive pair in the
canonical value list. Values outside the canonical list are
unconstrained. Reduces the search space by up to `k!` where
`k = values.length`.

### Using Factory Functions Directly

You can also use the constraint factory functions directly:

```dart
// Using factory functions with addConstraint()
p.addConstraint(['A', 'B', 'C'], allDifferent());
p.addConstraint(['X', 'Y'], exactSumBinary(10)); // For 2 variables, more efficient

// Custom combinations
p.addConstraint(['A', 'B', 'C'], (assignment) {
  // Custom logic combining multiple constraint types
  return allDifferent()(assignment) && exactSum(12)(assignment);
});
```

## Convenience Functions

For quick problem solving, use the top-level convenience functions:

```dart
// Quick all-different problem
final solution1 = await solveAllDifferent(
  variables: ['A', 'B', 'C'],
  domain: [1, 2, 3]
);

// Quick sum problem  
final solution2 = await solveSumProblem(
  variables: ['X', 'Y'],
  domain: [1, 2, 3, 4, 5],
  targetSum: 7
);

// General string constraint problem
final solution3 = await solveProblem(
  variables: {'A': [1, 2, 3, 4], 'B': [1, 2, 3, 4]},
  constraints: ['A != B', 'A + B >= 5']
);
```

## Real-World Examples

### Sudoku Solver with String Constraints

```dart
Future<void> solveSudoku(List<List<int>> puzzle) async {
  final p = Problem();
  
  // Add variables for each cell
  for (int r = 0; r < 9; r++) {
    for (int c = 0; c < 9; c++) {
      final key = '$r-$c';
      if (puzzle[r][c] != 0) {
        p.addVariable(key, [puzzle[r][c]]);  // Clue
      } else {
        p.addVariable(key, [1, 2, 3, 4, 5, 6, 7, 8, 9]);  // Empty cell
      }
    }
  }
  
  // Add all-different constraints using built-in methods
  // Rows
  for (int r = 0; r < 9; r++) {
    final row = List.generate(9, (c) => '$r-$c');
    p.addAllDifferent(row);
  }
  
  // Columns
  for (int c = 0; c < 9; c++) {
    final col = List.generate(9, (r) => '$r-$c');
    p.addAllDifferent(col);
  }
  
  // 3x3 blocks
  for (int br in [0, 3, 6]) {
    for (int bc in [0, 3, 6]) {
      final block = <String>[];
      for (int r = br; r < br + 3; r++) {
        for (int c = bc; c < bc + 3; c++) {
          block.add('$r-$c');
        }
      }
      p.addAllDifferent(block);
    }
  }
  
  final solution = await p.getSolution();
  // Print solved puzzle...
}
```

### Magic Square with String Constraints

```dart
Future<void> generateMagicSquare() async {
  final p = Problem();
  
  // 3x3 grid with numbers 1-9
  final positions = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
  p.addVariables(positions, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  
  // Each number appears exactly once
  p.addAllDifferent(positions);
  
  // All rows, columns, and diagonals sum to 15 using string constraints
  p.addStringConstraints([
    // Rows
    'A1 + A2 + A3 == 15',
    'B1 + B2 + B3 == 15', 
    'C1 + C2 + C3 == 15',
    // Columns
    'A1 + B1 + C1 == 15',
    'A2 + B2 + C2 == 15',
    'A3 + B3 + C3 == 15',
    // Diagonals
    'A1 + B2 + C3 == 15',
    'A3 + B2 + C1 == 15'
  ]);
  
  final solution = await p.getSolution();
  // Display magic square...
}
```

### Resource Allocation with Mixed Constraints

```dart
Future<void> allocateResources() async {
  final p = Problem();
  
  // Teams get 3-10 resources each  
  p.addVariables(['TeamA', 'TeamB', 'TeamC'], [3, 4, 5, 6, 7, 8, 9, 10]);
  
  // Use string constraints for clarity
  p.addStringConstraints([
    'TeamA + TeamB + TeamC == 20',  // Total budget
    'TeamA >= TeamB',               // Priority constraint
    'TeamA >= 3',                   // Minimum allocation
    'TeamB >= 3',
    'TeamC >= 3'
  ]);
  
  final solution = await p.getSolution();
  print('Team A: ${solution['TeamA']} resources');
  print('Team B: ${solution['TeamB']} resources'); 
  print('Team C: ${solution['TeamC']} resources');
}
```

## Finding Multiple Solutions

Most problems have more than one valid assignment. `dart_csp` exposes
several ways to get at them without searching the full tree twice.

```dart
// Stream solutions one at a time; break out when you've seen enough.
await for (final s in p.getSolutions()) {
  print(s);
}

// Or collect them all (only if the set fits in memory).
final all = await p.getAllSolutions();

// Just want to know how many?
final n = await p.countSolutions();

// Just want to know if the answer is unique?
final unique = !(await p.hasMultipleSolutions());

// Bounded sample — stops after N.
final firstFive = await p.getFirstNSolutions(5);
```

The top-level convenience functions (`solveAllProblems`,
`countAllSolutions`, `hasMultipleSolutions`, `getFirstNSolutions`,
`solveAllDifferentMultiple`, `solveSumProblemMultiple`) wrap the same
operations without building a `Problem` first.

See [doc/multi-solutions.md](doc/multi-solutions.md) for guidance on which
API to pick and how the underlying stream generator behaves.

## Solution Sampling & Diversity

Beyond *how many* solutions there are, you can ask for *some* — uniformly
at random, or spread out across the solution space.

```dart
// k solutions drawn uniformly at random without replacement
// (reservoir sampling; deterministic for a fixed seed).
final samples = await p.sampleSolutions(5, seed: 42);

// A single uniform sample, or null if unsatisfiable.
final one = await p.randomSolution(seed: 42);

// k solutions chosen to be as different as possible from each other
// (greedy max–min Hamming) — handy for generating distinct puzzle
// layouts or a varied set of options.
final varied = await p.diverseSolutions(5, maxPool: 1000, seed: 42);
```

These consume the enumeration stream, so cost scales with the total
solution count; `maxPool` bounds the candidate set for `diverseSolutions`.

## Min-Conflicts (Local Search) Solver

For very large problems where you only need *some* solution quickly, the
library also ships a Min-Conflicts local-search solver:

```dart
final p = Problem();
// ... set up an N-queens, scheduling, or map-coloring problem ...

final solution = await p.solveWithMinConflicts(maxSteps: 1000);
if (solution is Map<String, dynamic>) {
  print(solution);
} else {
  print('Local search gave up (FAILURE) — try more steps or a restart loop.');
}
```

Min-Conflicts is **incomplete**: it can return `'FAILURE'` even when a
solution exists (local optima). It also cannot enumerate solutions.
Default to the backtracking solver and reach for this one only when the
default isn't fast enough and you don't need uniqueness or completeness.

See [doc/min-conflicts.md](doc/min-conflicts.md) for tradeoffs, sizing
`maxSteps`, restart strategies, and current limitations.

## Optimization (Branch-and-Bound)

If your problem has more than one feasible solution, `minimize` /
`maximize` return the one that minimizes / maximizes a named numeric
variable:

```dart
// Choose three distinct values from [1..5] whose sum S is as small
// as possible.
final p = Problem()
  ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
  ..addAllDifferent(['A', 'B', 'C'])
  ..addVariable('S', [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
  ..addStringConstraint('A + B + C == S');

final best = await p.minimize('S');
// best = {A: 1, B: 2, C: 3, S: 6} (or a permutation of A,B,C)
```

Returns the optimal assignment, or `'FAILURE'` if the problem is
infeasible. Throws `ArgumentError` if the named variable doesn't exist
or its domain isn't numeric.

Implementation is **integrated branch-and-bound** inside the
backtracking engine. Each strictly-improving leaf becomes the new
incumbent and the objective's domain is permanently pruned to
values that still improve over the current bound (every existing
trail snapshot is re-filtered in place so rollback can't reintroduce
stale values). Search continues from the same point, avoiding the
per-improvement restart cost that a classic bound-tightening loop
pays. `Problem.lastStats` is populated by `minimize` / `maximize`.

### Multiple Objectives

When a problem has more than one objective, optimize them in priority
order or enumerate the trade-off frontier.

```dart
// Lexicographic: minimize cost first; among cheapest, maximize quality.
final best = await p.lexOptimize([
  Objective.minimize('cost'),
  Objective.maximize('quality'),
]);

// Pareto frontier: every non-dominated (cost, quality) trade-off.
final frontier = await p.paretoFront([
  Objective.minimize('cost'),
  Objective.maximize('quality'),
]);
```

Both run on a `copy()` and never mutate the receiver. `lexOptimize`
fixes each objective at its optimum before moving to the next;
`paretoFront` returns one solution per non-dominated objective vector
(iterations equal the frontier size).

## Large Neighborhood Search (LNS)

`Problem.lnsMinimize` / `Problem.lnsMaximize` find a *near*-optimal
solution by decomposing the optimization into a sequence of small
focused sub-solves. LNS finds an initial feasible solution, then
iteratively "destroys" a random subset of variables (frees them
while pinning every other variable to its incumbent value) and
re-solves the smaller sub-problem; improving candidates replace the
incumbent. The result is not guaranteed optimal — it's a
metaheuristic — but on hard problems LNS can be an order of
magnitude faster than plain `minimize`. See `doc/lns.md` for the
full design, the four shipped destroy policies (`random`, `window`,
`related`, `combined`) and the two acceptance strategies
(`improving`, `simulatedAnnealing`).

```dart
final result = await problem.lnsMinimize(
  'maxLoad',
  policy: LnsPolicy.random(fraction: 0.5),
  iterationBudget: 50,
  seed: 17,
);
final best = result.solution as Map<String, dynamic>;
print('best maxLoad = ${best["maxLoad"]}');
print(result.stats);
```

LNS is **experimental** (`STABILITY.md`). The surface may change
across minor versions until ALNS / late-acceptance / parallel
exploration land.

## Lazy Clause Generation (LCG, preview)

`Problem.solveWithLcg` is the entry point for the in-progress
Lazy Clause Generation feature — the conflict-driven nogood-learning
technique that gives CP-SAT, Chuffed, and similar modern solvers
orders-of-magnitude speedups on hard structured problems. **M1+M2 +
M3 complete (M3a–M3g)**: the engine learns
conflict clauses on boolean-clause-propagator failures *and* on **every**
specialised propagator — `allDifferent` / global-cardinality (`addGcc`) /
`regular` (`addRegular`) / `cumulative` (`addCumulative`) / `diff_n`
(`addDiffN`) / `circuit` (`addCircuit` / `addSubcircuit`) conflicts, posts
them
dynamically (so they prune future branches), and backtracks
**non-chronologically** by default. On the classic
pigeonhole-CNF UNSAT proofs the decision count drops by an order of
magnitude (~10× on 7-in-6, ~30× on 8-in-7). For the matching-based
propagators, a synthetic `AtomInScc` "bridge" atom (M3-tighten)
collapses each tight Hall set into one resolvable literal so the
first-UIP analyser converges, and the Hall set / GCC capacity cut is
extracted by **closing forward reachability** in the residual graph (the
alternating-path Régin / Quimper-Walsh construction, capacity-aware for
GCC): e.g. Inkala's "World's Hardest Sudoku" learns ~25 clauses, and the
exact-counts `addGcc` encoding learns identically to `addAllDifferent`.
For `regular` (M3d), a value pruned at one position is explained by the
*other* positions' value removals, collapsed through the same `AtomInScc`
bridge; because `regular` is GAC-strong, this learning surfaces on UNSAT
grids. For `cumulative` (M3e) and `diff_n` (M3f), a pruned coordinate is explained
by the compulsory-part / forbidden-region **bounds** of the tasks /
rectangles responsible — the consumers of the implication trail's bound
atoms (`AtomGe`/`AtomLe`); neither propagator is GAC, so even satisfiable
scheduling / packing instances search and learn. For `circuit` (M3g), a
prune is explained by the **fixed successor edges** (`AtomEq`) that force
it. With M3g the last propagator is explained; only conflicts flowing
through the generic binary/predicate path now fall back to chronological
backtrack. The search is **sound +
complete under any picker** — pass `useVsids:` / `useDomWdeg:` / `seed:`
to drive it under an activity/weighted-degree picker.

**Non-chronological backjumping (the default engine).** `solveWithLcg`
runs on an iterative trail-based CDCL engine (`LCG_PLAN.md` §M4) that
performs sound **non-chronological backjumping** — the real LCG
search-tree speedup. It backjumps on short boolean/CNF clauses
(pigeonhole 7-in-6 drops to ~240 decisions with 70+ real backjumps), and
posts-but-backtracks-chronologically on the wide, weak clauses that
allDifferent / GCC produce (so hard sudoku still converges fast). Opaque
conflicts and non-integer-domain problems fall back automatically. Pass
`useIterativeCdcl: false` for the original recursive
chronological-backtracking-with-learning path (still sound + complete,
without the backjump speedup).
Learned clauses are run through recursive (self-subsuming) **clause
minimisation** (Sörensson & Eén 2009) before posting, which strengthens
them and deepens the backjumps (`SolverStats.lcgMinimisedLiterals` counts
the literals removed). When `useVsids` / `useDomWdeg` is on, the engine
applies the canonical CDCL rule of bumping the activity of every variable
in the learned clause (not just the detecting constraint), so the picker
tracks the learned structure. `useRestarts: true` adds Luby restarts that
drop the search tree back to the root while retaining the learned-clause
pool, the activity tables, and the per-variable saved phase (phase
saving) — on heavy-tailed satisfiable instances this cuts decisions ~2×.
[`LCG_PLAN.md`](LCG_PLAN.md) has the full milestone roadmap.

```dart
final p = Problem()
  ..addVariable('a', [0, 1])
  ..addVariable('b', [0, 1])
  ..addVariable('c', [0, 1])
  ..addClause(positive: ['a', 'b', 'c'])
  ..addClause(negative: ['a', 'b']);
final solution = await p.solveWithLcg();
// Returns a satisfying boolean assignment; LCG bookkeeping is
// transparent — same return contract as p.getSolution().
print(CSP.lastStats!.learnedClauses);  // # clauses learned (0 on easy
                                       // SAT problems; grows on hard
                                       // UNSAT proofs)
```

The `learnedClauseCap:` kwarg (default 1000) bounds the learned-
clause pool; when it overflows the oldest half are dropped via
FIFO forget. `CSP.lastStats` carries `learnedClauses` and
`forgottenClauses` counters alongside the existing
`backjumps` / `backjumpLevelsSkipped` (which LCG bumps too).

`solveWithLcg`, the `Atom` hierarchy, the `DomainView` interface,
the `ImplicationReason` types, the `AnalysisResult` /
`firstUipAnalyse` analyser, the `learnedClauseCap:` kwarg, and the
new `SolverStats.learnedClauses` / `SolverStats.forgottenClauses`
fields are all **experimental** (`STABILITY.md`) and will evolve
as M3 lands.

## Reified Constraints (`b ⇔ C`)

A reified constraint introduces a 0/1 boolean variable whose value
tracks whether some underlying relation holds:

```dart
p.addVariable('X', [1, 2, 3, 4, 5]);
p.addReifiedEquals('bX3', 'X', 3);   // bX3 ⇔ (X == 3)
p.addStringConstraint('bX3 == 1');   // forces X = 3
```

The killer use case is **counting**: once each sub-constraint is
reified to a bool, you can use the existing arithmetic parser to
express "at least k of these hold":

```dart
p.addReifiedEquals('b1', 'X1', 1);
p.addReifiedEquals('b2', 'X2', 1);
p.addReifiedEquals('b3', 'X3', 1);
p.addStringConstraint('b1 + b2 + b3 >= 2');   // at least 2 hold
```

The full set of helpers in the `ReifiedConstraints` extension:

| Helper | Meaning |
|---|---|
| `addReifiedEquals(b, X, c)` | `b ⇔ (X == c)` |
| `addReifiedNotEquals(b, X, c)` | `b ⇔ (X != c)` |
| `addReifiedLessThan(b, X, c)` | `b ⇔ (X < c)` |
| `addReifiedLessOrEqual(b, X, c)` | `b ⇔ (X <= c)` |
| `addReifiedGreaterThan(b, X, c)` | `b ⇔ (X > c)` |
| `addReifiedGreaterOrEqual(b, X, c)` | `b ⇔ (X >= c)` |
| `addReifiedInSet(b, X, {...})` | `b ⇔ (X ∈ set)` |
| `addReifiedEqualsVar(b, X, Y)` | `b ⇔ (X == Y)` |
| `addReified(b, vars, pred)` | generic — `b ⇔ predicate(assignment)` |

`b` is auto-added with domain `[0, 1]` if you haven't already added it.

## Logical Combinators

The `LogicalConstraints` extension layers natural logical
combinations on top of boolean variables — combine with reified
constraints to express full propositional logic over your problem:

| Helper | Meaning |
|---|---|
| `addAtLeast([b1, b2, ...], k)` | at least `k` of the bools are 1 |
| `addAtMost([b1, b2, ...], k)` | at most `k` are 1 |
| `addExactly([b1, b2, ...], k)` | exactly `k` are 1 |
| `addImplies(a, c)` | `a == 1 → c == 1` |
| `addReifiedAnd(b, [...])` | `b ⇔ all are 1` |
| `addReifiedOr(b, [...])` | `b ⇔ any is 1` |
| `addReifiedNot(b, other)` | `b ⇔ ¬other` |

```dart
// "X = 1 implies Y = 1" via two reified equalities + implies.
p.addReifiedEquals('bX', 'X', 1);
p.addReifiedEquals('bY', 'Y', 1);
p.addImplies('bX', 'bY');
```

### SAT-style clauses (`addClause`)

For CNF-style modeling, `addClause(positive: [...], negative: [...])`
posts a disjunction of boolean literals — at least one positive
variable must be `1`, OR at least one negative variable must be `0`.
Tagged internally with a `ClauseSpec` so the engine dispatches to a
**unit-propagation** propagator: when every literal but one has
been falsified and none satisfied, the remaining literal is forced
to its satisfying value.

```dart
// CNF for XOR: (a ∨ b) ∧ (¬a ∨ ¬b)
final p = Problem()
  ..addVariable('a', [0, 1])
  ..addVariable('b', [0, 1])
  ..addClause(positive: ['a', 'b'])
  ..addClause(negative: ['a', 'b']);
// Solutions: (a=0, b=1) and (a=1, b=0).
```

Compose with reified equalities for CNF over data variables:

```dart
// "x == 1 ∨ y == 5"
p.addReifiedEquals('bX1', 'x', 1);
p.addReifiedEquals('bY5', 'y', 5);
p.addClause(positive: ['bX1', 'bY5']);
```

The propagator uses the classical two-watched-literal scheme
(Moskewicz et al., "Chaff", DAC 2001): each clause keeps two
watcher pointers into its literal list that are updated lazily
across propagation calls. Per-call work is `O(1)` amortized once
the watchers are initialized, instead of `O(literals)` for a
full scan.

The seeding side is matched to the watchers: once a clause's
watchers are set, the engine wakes the propagator only when one
of the two watched literals' variables is reduced. Reductions to
other variables in the clause's scope cannot falsify the watched
literals (the invariant is monotone under backtrack), so they're
filtered out before the propagator is even enqueued. Width-2
clauses (e.g., "at most one" pairwise encodings) skip this filter
— both literals are always watched, so the check could never
fire and would just be overhead. The user-visible pruning
behavior is the standard unit-propagation rule shown above; the
watchers and the seeding filter are implementation details.

## Global Constraints

The `GlobalConstraints` extension adds two structured n-ary
constraints that recur across CSP modeling:

```dart
// Element: list[idxVar] == valueVar  (lookup / indirection)
final costs = [50, 20, 70, 10, 40];
p.addElement('item', costs, 'cost');
final cheapest = await p.minimize('cost');
// → picks item index 3, cost 10

// Table: (vars[0], vars[1], ...) must equal one of the tuples
p.addTable(['color', 'size'], [
  ['red', 'small'],
  ['blue', 'large'],
]);
```

`element` for lookup tables and indirection ("the cost of the chosen
item is X"). `table` for arbitrary relations that don't have a clean
closed-form predicate — compatibility matrices, FSM transitions, etc.

### Counting Constraints: `among`, `nvalue`, `gcc`

The `GlobalConstraints` extension also covers the three classic
counting constraints, each in both a count-variable form (lets you
optimize over the count) and a fixed-`k` form.

```dart
// among: how many of vars take a value in the set?
p.addAmong(['s1', 's2', 's3'], {'morning'}, 'nMornings');
p.addAmongExactly(['s1', 's2', 's3'], {'morning'}, 2);

// nvalue: how many distinct values are used across vars?
p.addNvalue(['p1', 'p2', 'p3'], 'nColors');
final fewest = await p.minimize('nColors');   // chromatic-number-style
p.addNvalueExactly(['p1', 'p2', 'p3'], 2);

// gcc: each value must appear the specified number of times.
p.addGcc(slots, {'morning': 3, 'afternoon': 2, 'night': 1});
// or ranged:
p.addGccRanges(slots, {
  'morning': (min: 0, max: 3),
  'night':   (min: 1, max: 4),
});
```

| Helper | Meaning |
|---|---|
| `addAmong(vars, values, countVar)` | `countVar` = #vars whose value ∈ values |
| `addAmongExactly(vars, values, k)` | exactly `k` of `vars` ∈ values |
| `addNvalue(vars, countVar)` | `countVar` = number of distinct values in `vars` |
| `addNvalueExactly(vars, k)` | exactly `k` distinct values used |
| `addGcc(vars, counts)` | each `value → count` must hold exactly |
| `addGccRanges(vars, ranges)` | each `value → (min, max)` must hold inclusively |

`gcc` generalizes `allDifferent` (the case where every value of
interest has count 1). It dispatches to a Régin-style network-flow
propagator: a bipartite matching with value multiplicity finds a
feasible assignment in polynomial time, then SCC analysis on the
residual graph prunes any variable→value edge that is on no max
matching. Upper-bound constraints receive full GAC. Lower-bound
constraints receive conservative GAC: when the matching's
distribution doesn't certify the lower bounds but the leaf isn't
reached yet, the propagator declines to prune rather than risk a
false-positive infeasibility verdict — the leaf check then catches
any real violation. See [`doc/global-cardinality.md`](doc/global-cardinality.md)
for modeling patterns (shift rosters, palette restriction, chromatic
number).

### Sequencing & Packing: `circuit`, `bin_packing`

```dart
// circuit: vars[i] is the successor of position i; the successor
// function must form a single Hamiltonian cycle through every
// position. Use for TSP-like routing, single-tour sequencing.
p.addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3]);
p.addCircuit(['n0', 'n1', 'n2', 'n3']);

// bin_packing: each items[i] is the bin assignment for item i;
// binLoads[b] equals the sum of sizes of items in bin b. Constrain
// the load vars separately (with <=, ranges, or minimize) for
// capacity / balancing requirements.
p.addVariables(['it0', 'it1', 'it2', 'it3'], [0, 1]);   // 2 bins
p.addVariables(['load0', 'load1'], [0, 1, 2, ..., 10]);
p.addBinPacking(['it0', 'it1', 'it2', 'it3'],
                [4, 3, 2, 1],
                ['load0', 'load1']);
p.addStringConstraints(['load0 <= maxLoad', 'load1 <= maxLoad']);
final balanced = await p.minimize('maxLoad');
```

| Helper | Meaning |
|---|---|
| `addCircuit(vars)` | the successor function `vars[i]` forms a single Hamiltonian cycle |
| `addSubcircuit(vars)` | same as `addCircuit`, but `vars[i] = i` is allowed and means position `i` is **skipped**; the non-skipped positions still form a single cycle (or there is no cycle at all) |
| `addBinPacking(items, sizes, binLoads)` | each `binLoads[b]` equals the sum of sizes of items assigned to bin `b` |
| `addInverse(forward, inverse)` | channelling: `forward[i] = j ⇔ inverse[j] = i` for all `i, j` in `0..n-1` |
| `addDiffN(xs, ys, widths, heights)` | 2D rectangle non-overlap (`diff_n`); each rect has a registered `(x, y)` corner and constant `(w, h)` size |

`addSubcircuit` is the standard CP primitive for vehicle routing with
optional stops, "visit some subset of cities in one tour", and any
sequencing problem where the visited set itself is part of the
decision. The propagator is shared with `addCircuit`: it tracks
singleton-edge chains, rejects strict sub-cycles among non-skipped
positions, prunes intermediate chain nodes from the tail's domain,
and forces every non-cycle position to self-loop when a pure cycle
closes early. The empty subcircuit (every position skipped) is a
valid solution. Posting `addAllDifferent(vars)` alongside is
redundant — the permutation property is enforced inherently (each
value, including the self-loop slots, is used at most once).

```dart
// Decide *which* of three optional stops to visit in a single
// tour, plus the order. n=3, full domains. Either skip all three,
// pick a 2-stop tour, or take the full 3-stop loop.
final p = Problem()
  ..addVariables(['n0', 'n1', 'n2'], [0, 1, 2])
  ..addSubcircuit(['n0', 'n1', 'n2']);
// 6 valid assignments: 1 empty + 2 three-cycles + 3 (skip one,
// swap the other two).
```

### 2D Non-Overlap: `diff_n`

`addDiffN` generalises `addNoOverlap` from a unary (1D time)
resource to two dimensions: given `n` axis-aligned rectangles
described by `(xs[i], ys[i])` corners (registered variables) and
constant `(widths[i], heights[i])` sizes, enforces that no two
rectangles overlap. Standard CP primitive for rectangle packing,
floor planning, 2D scheduling, and tile-placement puzzles.

```dart
// Pack four 1×1 squares into a 2×2 grid — exactly 4! = 24 tilings.
final p = Problem();
for (var i = 0; i < 4; i++) {
  p..addVariable('x$i', [0, 1])
   ..addVariable('y$i', [0, 1]);
}
p.addDiffN(
  [for (var i = 0; i < 4; i++) 'x$i'],
  [for (var i = 0; i < 4; i++) 'y$i'],
  List<int>.filled(4, 1),
  List<int>.filled(4, 1),
);
```

Half-open box semantics: a rectangle at `(x, y)` with size
`(w, h)` occupies `[x, x+w) × [y, y+h)`, so two rectangles that
touch at an edge (`xi + wi == xj`) do **not** overlap.

Tags the constraint with a `DiffNSpec` so the engine dispatches to
a **forbidden-region sweep propagator** (Beldiceanu & Carlsson,
"Sweep as a generic pruning technique applied to the non-overlapping
rectangles constraint", CP 2001). For each rectangle and each
dimension the propagator aggregates the forbidden-position intervals
induced by every other rectangle whose compulsory part in the
orthogonal dimension forces an overlap, then filters the current
domain in a single pass. The constraint scopes all `2n` coordinate
variables in the order `[xs..., ys...]` and propagates once per
change to any rectangle — substantially less work than the
pairwise GAC support search the previous decomposition required.
Zero-area rectangles (`width == 0` or `height == 0`) are excluded
from the constraint — they never conflict with anything.

### Channelling Inverse Maps: `inverse`

`addInverse(forward, inverse)` posts the standard channelling
constraint between two equal-length variable lists. For every
`i, j ∈ 0..n-1`:

```
forward[i] = j   ⇔   inverse[j] = i
```

Use when modelling the same relation in both directions is more
natural than picking one — assignment problems where you want both
"which machine runs task i?" and "which task runs on machine j?",
scheduling models that switch between "what is in slot t?" and
"when is event e?", or any permutation where some constraints are
cleaner on the forward map and others on the inverse.

```dart
// Tasks ↔ Machines bijection. Forbid task 0 → machine 0.
final p = Problem()
  ..addVariables(['task0','task1','task2','task3'], [0,1,2,3])
  ..addVariables(['machine0','machine1','machine2','machine3'], [0,1,2,3])
  ..addInverse(['task0','task1','task2','task3'],
               ['machine0','machine1','machine2','machine3']);
// Once forbidden via the forward side, the inverse side gets
// pruned automatically:
p.addStringConstraint('task0 != 0');
```

Decomposes into `n²` binary constraints so AC-3 propagates them
effectively. The channelling implies both lists are partial
permutations of `0..n-1` — you don't need to add `addAllDifferent`
separately for either side.

`circuit` dispatches to a cycle-detection propagator that maintains
the partial chains formed by singleton-domain edges, prunes values
that would close a premature sub-cycle, and enforces successor
uniqueness (no value can be the successor of more than one
variable). Composing with `addAllDifferent` adds Régin's
hyper-arc-consistent pruning on top of the uniqueness already
enforced by the circuit propagator, giving even stronger early
filtering on hard instances. `bin_packing` has no built-in capacity
notion; constrain the `binLoads` variables (or run `minimize` over
them) to express per-bin limits and balancing objectives.

### DFA-checked Sequences: `regular`

The **regular** constraint takes a sequence of variables and a
`Dfa` (deterministic finite automaton) and accepts only sequences
the DFA accepts. Useful for any sequencing rule expressible as a
finite automaton: pattern matching, run-length bounds, at-most-k
counting, alternation requirements.

```dart
// "At most 2 morning shifts across the week."
// State = how many M seen so far; state 3 is the trap.
final dfa = Dfa(
  numStates: 4,
  start: 0,
  accepting: {0, 1, 2},
  transitions: {
    0: {'M': 1, 'A': 0, 'N': 0},
    1: {'M': 2, 'A': 1, 'N': 1},
    2: {'M': 3, 'A': 2, 'N': 2},
    3: {'M': 3, 'A': 3, 'N': 3},
  },
);

final p = Problem()
  ..addVariables(['mon', 'tue', 'wed', 'thu', 'fri'], ['M', 'A', 'N'])
  ..addRegular(['mon', 'tue', 'wed', 'thu', 'fri'], dfa);
```

The `Dfa` value type is exposed from the top-level library import.
Symbols are `dynamic` to accommodate any variable value type
(`int`, `String`, custom objects).

Some constraints can be expressed either as a `regular` DFA or with
the cardinality helpers (`addAmongExactly`, `addGcc`). Prefer the
specialized helper when one applies — it's clearer and as fast or
faster; reach for `regular` when the rule has positional structure
(adjacency, run-length, alternation) that cardinality counts can't
capture.

The engine dispatches `addRegular` to a partial-state propagator
(Pesant 2004): per-position forward + backward reachable state sets
are computed from the DFA and the current domains, and any value
whose transition lies on no accepting path is pruned. This achieves
generalized arc consistency on the regular constraint — pruning
happens during search rather than only at leaves, so DFAs that
forbid an early symbol class detect infeasibility immediately
instead of after exhaustive enumeration.

## Soft Constraints / MaxCSP

When some constraints are preferences rather than hard requirements,
declare them *soft* with a non-negative integer weight and call
`maximizeSatisfaction` to find the feasible assignment that
maximizes the total weight of satisfied soft constraints:

```dart
final p = Problem()..addVariable('X', [1, 2, 3]);
p.addReifiedEquals('b1', 'X', 1);
p.addReifiedEquals('b2', 'X', 2);
p.addReifiedEquals('b3', 'X', 3);
p.declareSoft('b1', 1);   // weight 1 if X = 1
p.declareSoft('b2', 5);   // weight 5 if X = 2  (highest)
p.declareSoft('b3', 1);   // weight 1 if X = 3

final result = await p.maximizeSatisfaction();
// → X = 2 (the weight-5 soft wins)
```

The one-step helper bundles reification:

```dart
final boolName = p.addSoftConstraint(
  10,                            // weight
  ['X', 'Y'],                    // vars the predicate reads
  (a) => (a['X'] as int) + (a['Y'] as int) == 4,
);
```

Hard constraints (added the usual way) must still hold;
`'FAILURE'` is returned if no feasible assignment exists at all.
The original problem is not mutated.

## Luby Restart Strategy

On hard instances where chronological backtracking gets stuck in an
early-doomed subtree, restarting from the root with a different value
ordering finds a solution dramatically faster. `getSolutionWithRestarts`
uses the universal Luby schedule (Luby, Sinclair & Zuckerman, 1993):

```dart
final result = await p.getSolutionWithRestarts(
  seed: 42,           // reproducibility
  scale: 100,         // backtracks per Luby unit
  maxRestarts: 50,    // cap total effort
  useDomWdeg: true,   // optional: pair with dom/wdeg
);
```

Each attempt has a `scale × luby(i)` backtrack budget. The Luby
sequence is `1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, ...` — a
provably-optimal universal restart policy. Returns `'FAILURE'` if any
attempt completes the tree without finding a solution (proves
infeasibility) or if `maxRestarts` is exhausted.

## dom/wdeg Variable Heuristic

`getSolutionWithDomWdeg()` swaps the default MRV heuristic for
**dom/wdeg** (Boussemart, Hemery, Lecoutre, Sais, 2004), which biases
variable selection toward variables touching constraints that have
recently caused failures. Often outperforms MRV on structured
industrial problems. Composes naturally with restarts via the
`useDomWdeg: true` flag on `getSolutionWithRestarts`.

## VSIDS-Style Variable Activity

`getSolutionWithActivity()` uses a **VSIDS-style** per-variable
activity heuristic (Moskewicz, Madigan, Zhao, Zhang, Malik, 2001 —
originally the Chaff SAT solver), adapted to CSPs. On every
propagation conflict, each variable in the failing constraint's scope
gets a bump; bump magnitudes grow multiplicatively per conflict, so
recent conflicts dominate the score (the standard MiniSat trick —
mathematically equivalent to uniformly decaying every existing score,
but O(1) per conflict instead of O(|vars|)).

Variable selection minimizes `dom_size / (1 + activity)`, mirroring
dom/wdeg's `dom_size / wdeg` shape — before any conflicts the ratio
reduces to MRV, and as conflicts accumulate the picker gravitates
toward variables that have been near recent failures.

```dart
final sol = await p.getSolutionWithActivity();
```

Composes with restarts (`useVsids: true` on `getSolutionWithRestarts`),
forward checking, and conflict-directed backjumping. When dom/wdeg
and VSIDS are both enabled, VSIDS wins the picker; both bump tables
are still updated. Useful complement to dom/wdeg for SAT-style
instances and for problems where the "guilty" structure shifts over
the course of search — VSIDS's decaying bumps react faster than
dom/wdeg's monotone weights.

## Impact-Based Search (IBS)

`getSolutionWithImpact()` uses **Impact-Based Search** (Refalo, 2004 —
"Impact-Based Search Strategies for Constraint Programming", CP 2004).
After every decision the engine measures the **impact** of pinning
`(variable, value)`: the fraction of the joint search space (product
of remaining domain sizes) that propagation eliminated. A failed
propagation contributes impact `1.0` (the entire branch is gone); a
successful one contributes `1 - exp(logP_after - logP_before)`,
clamped to `[0, 1]`. Per-`(var, value)` running means are stored, so
IBS learns from *every* decision — not just failures, as dom/wdeg and
VSIDS do.

Variable selection minimizes `dom_size / (1 + Σ_a I(v, a))` where the
sum is over values currently in `v`'s domain. Pre-observation this
reduces to MRV; as impacts accumulate the picker gravitates toward
variables whose values historically prune the largest fraction of the
search space.

```dart
final sol = await p.getSolutionWithImpact();
```

Composes with restarts (`useImpact: true` on `getSolutionWithRestarts`),
forward checking, SAC preprocessing, and conflict-directed
backjumping. When all of `useImpact`, `useVsids`, and `useDomWdeg` are
set, the picker dispatch order is impact → VSIDS → dom/wdeg; the
other heuristics' bump tables continue to update so the picker choice
is independent of which conflicts were observed.

IBS is the most informative of the three conflict-driven heuristics
on problems with a wide spread of per-decision pruning — its score
combines both how often a decision leads to failure (via the impact-
1.0 contribution) and how strongly successful decisions prune. The
canonical comparison surface is the same one VSIDS competes on:
structured combinatorial problems where MRV's tie-breaking is
arbitrary.

## Last-Conflict Heuristic

`getSolutionWithLastConflict()` layers **Last-Conflict reasoning**
(Lecoutre 2009 — "Reasoning from last conflict(s) in constraint
programming", Artificial Intelligence 173) on top of whichever
underlying picker you choose. After every propagation failure, the
engine records the variable being pinned at the failure point. The
next time the picker runs, if that variable is still unassigned, the
picker returns it directly — focusing search on the conflict cause —
instead of consulting the underlying heuristic. When the recorded
variable becomes assigned (via propagation or via the decision pin),
the picker falls through.

LC is a *wrapper*, not a sibling heuristic: it modifies the variable
choice without changing the score functions. Pass `useDomWdeg:`,
`useVsids:`, or `useImpact:` to choose the underlying picker. The
canonical deployment from Lecoutre's experiments is `LC + dom/wdeg`:

```dart
final sol = await p.getSolutionWithLastConflict(useDomWdeg: true);
```

Composes with restarts (`useLastConflict: true` on
`getSolutionWithRestarts`), forward checking, SAC preprocessing, and
conflict-directed backjumping. On the in-repo benchmark, LC+dom/wdeg
wins wall-clock on UNSAT pigeonhole CNF and matches dom/wdeg on
feasible n-queens — see `dart run benchmark/benchmark.dart` for the
full comparison (the "heuristic comparisons" section runs MRV /
dom/wdeg / VSIDS / IBS / LC+dom-wdeg head-to-head on five problems
with a 5-rep-warm-up + 25-rep-median harness).

## Conflict-Directed Backjumping (CBJ)

Pass `enableConflictBackjumping: true` to any backtracking solver
entry point to opt into **CBJ** (Prosser, 1993) instead of
chronological backtracking. After all candidate values for a
decision variable have failed propagation, the engine jumps directly
to the deepest *earlier* variable that participated in some
propagation failure for the current variable — skipping intermediate
decisions that couldn't have mattered to those failures.

```dart
final sol = await p.getSolution(enableConflictBackjumping: true);
print(p.lastStats!.backjumps);            // how many times the
                                          // engine jumped on a
                                          // conflict
print(p.lastStats!.backjumpLevelsSkipped); // total decision levels
                                          // skipped past chrono BT
```

CBJ is sound and complete; only the choice of backtrack target
differs from the default. Composes with [forward checking](#consistency-level),
[restarts](#luby-restart-strategy), [dom/wdeg](#domwdeg-variable-heuristic),
[VSIDS activity](#vsids-style-variable-activity), [IBS](#impact-based-search-ibs), [LC](#last-conflict-heuristic), and the optimization
solvers (`minimize`, `maximize`). Off by default
because plain chronological backtracking has zero per-decision
overhead — CBJ adds a coarse trail walk on each propagation failure
and a small set per decision frame, paying for itself only on
problems where the failure cause is genuinely far from the most
recent decision.

See [`doc/cbj.md`](doc/cbj.md) for the algorithm, the conflict-cause
approximation, the integration with each search variant, and
worked-example benchmarks showing when CBJ helps and when it
doesn't.

## Linear Arithmetic Constraints

For arithmetic constraints of the form
`Σ coeffs[i] · vars[i]  ∘  bound` (with `∘ ∈ {==, ≤, ≥}`), use the
dedicated linear API. The engine dispatches these to a
bounds-consistency propagator that computes each variable's interval
contribution and prunes values inconsistent with the constraint's
overall bounds — much stronger than predicate-only n-ary encoding,
especially when the free neighborhood exceeds the engine's GAC work
bound.

```dart
final p = Problem()
  ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
  ..addLinearEquals(['A', 'B', 'C'], [1, 1, 1], 9);     // A + B + C = 9
final s = await p.getSolution();

// Weighted equalities:
p.addLinearEquals(['X', 'Y'], [2, 3], 12);              // 2X + 3Y = 12

// Inequalities:
p.addLinearLeq(['A', 'B', 'C'], [1, 1, 1], 10);         // A + B + C ≤ 10
p.addLinearGeq(['A', 'B', 'C'], [1, 1, 1], 5);          // A + B + C ≥ 5

// Mixed-sign coefficients (works for reformulating equations):
p.addLinearEquals(['A', 'B'], [2, -1], 3);              // 2A - B = 3
```

Coefficients may be positive, negative, or zero. All involved
variables must have numeric domains; this is checked at constraint
registration time. The propagator handles bounds consistency on
integer and floating-point domains alike.

**Why it matters.** Predicate-only encodings of large arithmetic
constraints (such as the classic SEND + MORE = MONEY
cryptarithmetic) bail out of GAC support search when the free
neighborhood is too big to enumerate, so the engine effectively
falls back to pure search. The linear propagator computes interval
bounds in `O(n)` per call and prunes immediately. On the
SEND + MORE benchmark, the linear form solves in ~1 ms vs ~1.8 s
for the predicate-only encoding (~1800× speedup).

## Consistency Level

Every backtracking entry point accepts an optional
`consistency: ConsistencyLevel` parameter that selects how strongly
the engine propagates after each decision:

- `ConsistencyLevel.arcConsistency` (default) — full AC-3 on binary
  constraints and GAC on n-ary constraints. Each domain change
  requeues the constraints reachable through the changed variable
  and runs to a fixed point. Strongest pruning per decision, almost
  always a net win on structured problems.
- `ConsistencyLevel.forwardChecking` — revise each constraint
  touching the just-assigned variable once. A revise that merely
  narrows a neighbor's domain does NOT trigger further work; a
  revise that *assigns* a neighbor (reduces its domain to a
  singleton) does cascade once, so newly-deduced assignments still
  have their constraints checked. Cheapest per decision; helpful on
  problems with loose constraint graphs or where each constraint is
  already strong on its own.
- `ConsistencyLevel.singletonArcConsistency` — runs AC-3 / GAC
  during search just like `arcConsistency`, plus an extra
  **preprocessing pass** at the top of search (Debruyne & Bessière,
  1997 — algorithm SAC-1). For every `(variable, value)` pair
  currently in some domain, the engine tentatively pins the
  variable to that value, runs propagation, and prunes the value if
  any domain wipes; it repeats the whole pass until a fixpoint. SAC
  pruning is strictly stronger than AC and catches root
  infeasibility that AC alone misses (e.g. `x == y ∧ y == z ∧
  x != z` over `{1, 2, 3}` is AC-consistent but SAC-empty). More
  expensive at the root than `arcConsistency` and adds nothing to
  per-decision cost. Useful when the root domains contain a lot of
  dead-end values that survive AC but die quickly under any
  single-variable pin.

```dart
// Single solution with FC.
final p = Problem()
  ..addVariables(['A', 'B', 'C'], [1, 2, 3])
  ..addAllDifferent(['A', 'B', 'C']);
final s = await p.getSolution(
  consistency: ConsistencyLevel.forwardChecking,
);

// Composes with optimization, dom/wdeg, restarts, and the streaming API:
await p.minimize('A', consistency: ConsistencyLevel.forwardChecking);
await p.getSolutionWithDomWdeg(
  consistency: ConsistencyLevel.forwardChecking,
);
await p.getSolutionWithRestarts(
  seed: 1,
  consistency: ConsistencyLevel.forwardChecking,
);
await for (final s in p.getSolutions(
  consistency: ConsistencyLevel.forwardChecking,
)) { /* ... */ }
```

The choice is purely a propagation knob — both modes are sound and
complete; they only differ in how much pruning they do per decision.
`SolverStats.binaryRevises` / `naryRevises` let you compare the work
done by each mode on your problem.

## Conflict Explanation (MUS)

When a model is infeasible the solver returns the literal
`'FAILURE'` — sound but uninformative. For a model with dozens of
constraints, finding the conflict by inspection is a debugging
nightmare. `Problem.findMinimalUnsatisfiableSubset` (in the
`ConflictExplanation` extension) identifies a *minimal unsatisfiable
subset* (MUS): a subset of the posted constraints that's still
infeasible, and from which removing any single constraint yields a
satisfiable subproblem.

```dart
final p = Problem();
p.addVariables(['a', 'b', 'c'], [1, 2]);
p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
p.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
p.addConstraint(['a', 'b'],
    (dynamic a, dynamic b) => (a as num) < (b as num)); // redundant

final mus = await p.findMinimalUnsatisfiableSubset();
if (mus == null) {
  print('Satisfiable — no explanation needed.');
} else {
  for (final ref in mus) {
    print(ref); // binary(a, b), binary(b, c), binary(a, c)
  }
}
```

The triangle has no 2-coloring; all three inequality edges are in
the MUS. The redundant `a < b` is dropped automatically. Returns
`null` when the problem has at least one solution.

Algorithm: classic deletion-based MUS (Bakker et al. 1993, Junker
2001) — linearly probe each posted constraint, drop it permanently
if the residual stays unsat, otherwise restore. O(n) calls to
`CSP.solve` where n is the number of user-posted constraints; each
solve runs ordinary AC-3 search. Returned MUS is *locally minimal*
(no single deletion preserves infeasibility), not necessarily the
smallest unsat subset (NP-hard in general).

Pass `cancelToken:` to bound the work. Cancellation in step 1 (the
initial satisfiability check) returns `null`; cancellation in step 2
(the deletion loop) returns the current kept set — still
unsatisfiable but possibly non-minimal. Pass `consistency:` to
control propagation strength of the internal solves.

For larger models with small MUSes, the sibling
`findMinimalUnsatisfiableSubsetQuickXplain` runs the divide-and-
conquer QuickXplain algorithm (Junker 2004) instead: O(k · log(n/k))
calls to `CSP.solve` where k is the MUS size and n is the total
constraint count, vs the deletion pass's O(n). Same return shape and
same `ConstraintRef` semantics; different MUSes may surface (both
are locally minimal but not the smallest possible). QuickXplain
cancellation always returns `null` — its recursion has no sound
mid-flight kept set to surface.

```dart
final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
```

Every primary constraint helper on `Problem` accepts an optional
`label:` parameter (any `String`) that surfaces on
`ConstraintRef.label` and in `toString`. Without it, refs print as
`linearLeq(w0, w1, w2)`; with it, `linearLeq[max-load](w0, w1, w2)`.
The label is for display only — equality on `ConstraintRef` is keyed
by `id` alone — but it makes MUS output dramatically more legible on
models where the same kind of constraint appears many times:

```dart
p.addLinearLeq(['w0', 'w1', 'w2'], [1, 1, 1], 3, label: 'max-load');
p.addLinearGeq(['w0', 'w1', 'w2'], [1, 1, 1], 10, label: 'min-load');
final mus = await p.findMinimalUnsatisfiableSubset();
print(mus);
// [linearLeq[max-load](w0, w1, w2), linearGeq[min-load](w0, w1, w2)]
```

Decomposed helpers (`addInverse`, `addLexChain`, `addValuePrecedence`,
binary `addAllEqual`) propagate the label to every decomposed piece.

See [doc/conflict-explanation.md](doc/conflict-explanation.md) for
a worked example, notes on granularity / decomposition, and the
"which algorithm to call" guidance.

## UNSAT Proof / Nogood Logging

`solveWithProof` runs the LCG engine and returns both the result and a
`ProofLog` of every nogood (learned clause) the search derived.

```dart
final r = await p.solveWithProof();
if (r.result == 'FAILURE') {
  print('proved UNSAT: ${r.proof.provedUnsat}');
  print('${r.proof.length} learned nogoods');
  print(r.proof.toReadable());  // human rendering
  final drat = r.proof.toDrat(); // DRAT clause syntax, self-describing
}
```

The log carries a stable atom↔integer legend, in derivation order. It is
a *nogood-derivation log* — the learned reasoning at the core of a
refutation — not a standalone `drat-trim`-checkable proof on its own,
since the propagators' clausal encoding is generated lazily and isn't
emitted. It is distinct from the MUS core (a minimal set of *original*
constraints) and the propagation trace (per-decision events).

## Cancellation and Timeouts

Every backtracking solver and the min-conflicts runner accept an
optional `cancelToken: CancellationToken` parameter. A cancelled
token aborts the search at the next checkpoint and the entry point
returns the literal `'FAILURE'` — the same shape as an unsatisfiable
problem, so distinguish cancel from infeasibility by inspecting
`token.isCancelled` after the call.

```dart
import 'dart:async';

final token = CancellationToken();
// Cancel after a deadline; this works for any solver entry point.
Timer(Duration(seconds: 5), token.cancel);
final result = await p.getSolution(cancelToken: token);
if (result == 'FAILURE' && token.isCancelled) {
  print('Timed out.');
}
```

The engine cooperatively yields to the event loop on every ~100
decisions (and the min-conflicts runner on every ~200 iterations),
which is also what lets a wrapping `Future.timeout(...)` actually
fire on an otherwise CPU-bound solve:

```dart
try {
  await p.getSolution().timeout(Duration(seconds: 5));
} on TimeoutException {
  print('Took longer than 5 seconds.');
}
```

Both forms work without spawning an isolate — the search stays on
the main isolate but yields often enough that timers and stream
listeners get their turns. The fast path is one integer compare per
decision; the yield itself amortizes to well under 1% of search
wall-clock on every benchmark in `benchmark/benchmark.dart`. For
cases where you also want to free the main isolate's CPU budget,
see "Solving on a worker isolate" below.

When cancelling an optimization (`minimize` / `maximize`), the
result is `'FAILURE'` regardless of whether an improving incumbent
was found before the cancel. The current API doesn't expose the
last-seen incumbent; if you need it, run an enumerating
`getSolutions` and track the best yourself.

## Incremental / Assumption-Based Solving

Interactive callers re-solve constantly as the user edits. `IncrementalSolver`
wraps a base problem with a stack of retractable *assumption* scopes.

```dart
final s = IncrementalSolver(base);

s.assumeEquals('x', 3);
await s.solve();              // base + {x == 3}

s.push();                      // open a nested scope
s.assumeEquals('y', 5);
await s.solve();              // base + {x == 3, y == 5}

s.pop();                       // retract {y == 5} exactly
await s.solve();              // base + {x == 3} again
```

Assumption flavours: `assumeEquals`, `assumeNotEquals`, `assumeInSet`,
`assumeConstraint`, `assumePredicate`. Scopes: `push` / `pop` /
`resetAssumptions`. Drives `solve`, `isSatisfiable`, `getSolutions`,
`countSolutions`, `minimize`, `maximize`.

Assumptions are layered on a `copy()` of the base at solve time, so the
base problem is never mutated and retraction is exact.

**Warm-starting.** `prime()` solves the base once with the LCG engine and
caches the nogoods it learns; `solveWarm()` imports them into each
assumption-varying solve, so a re-solve reuses the base's reasoning:

```dart
final s = IncrementalSolver(base);
await s.prime();                 // learn base nogoods once
s.assumeEquals('x', 3);
await s.solveWarm();             // re-solve, warm-started
```

Semantics are identical to a cold solve (imported clauses are implied by the
base, so they only prune); on a conflict-heavy base the search shrinks
markedly (~3.4× fewer decisions in the test suite). Only base-derived
nogoods are cached, which is always sound; a propagation-solvable base
caches nothing and warm-start is a correct no-op.

## Solving on a worker isolate

Cooperative cancellation makes a CPU-bound solve responsive to
timers and `.timeout(...)`, but the search still runs on the
calling isolate — every yield is short and CPU pressure stays on
the main thread. For workloads where you want to free the main
isolate entirely (e.g. a Flutter app whose UI must stay smooth, or
a server running multiple solves), the runner in `isolate_runner.dart`
spawns the solve on a fresh worker isolate.

```dart
import 'package:dart_csp/dart_csp.dart';

// Top-level builder so the closure is sendable. The builder runs
// inside the worker, not on the caller's isolate.
Problem buildMySchedule() {
  final p = Problem();
  // ... addVariable / addConstraint / ...
  return p;
}

Future<void> main() async {
  final solution = await solveInIsolate(
    buildMySchedule,
    timeout: Duration(seconds: 30),
  );
  // CSP.lastStats has been populated with the worker's counters.
  print(solution);
}
```

Four entry points are exported alongside their in-process twins:

| In-process              | Worker-isolate           |
| ----------------------- | ------------------------ |
| `Problem.getSolution`   | `solveInIsolate`         |
| `Problem.getSolutions`  | `solveAllInIsolate`      |
| `Problem.minimize`      | `minimizeInIsolate`      |
| `Problem.maximize`      | `maximizeInIsolate`      |
| `Problem.solveWithLcg`  | `solveWithLcgInIsolates` (portfolio of N) |

All four take a `Problem Function()` builder instead of a
constructed `Problem` — predicate closures attached to a `Problem`
generally aren't sendable across an isolate boundary, but a
top-level builder closure is. The builder runs inside the worker
to construct the problem fresh there.

Common options across all four:

- `consistency:` — same `ConsistencyLevel` enum as the in-process
  solvers.
- `cancelToken:` — main-isolate `CancellationToken`; cancelling it
  forwards a cancel signal to the worker, which aborts its search
  at the next checkpoint. The returned future / stream resolves
  with `'FAILURE'` shortly after.
- `timeout:` — built-in deadline. When it fires the runner sends
  the worker a cancel signal, waits a brief grace window for the
  worker to flush, then hard-kills the isolate. Prefer this over
  wrapping `await solveInIsolate(...).timeout(...)` — the
  built-in path actually terminates the worker; a wrapping
  `.timeout()` would leave it running until natural completion.

The worker's `CSP.lastStats` is shipped back to the main isolate
on normal completion, so the documented "stats populated when the
future resolves" contract still holds. Stats are not copied when
the runner short-circuits on a pre-cancelled token or when the
hard-kill grace fires (the worker had no chance to flush).

If the builder itself throws, the exception surfaces on the main
isolate as an `IsolateRunnerException` carrying the message and a
stringified stack trace from inside the worker. The original
exception object isn't recoverable across the boundary.

The runner is not available on Dart Web — `dart:isolate` doesn't
exist there. The test file is marked `@TestOn('vm')` for the same
reason. All other dart_csp surface continues to work on every
platform Dart supports.

### Parallel LCG portfolio + cooperative clause sharing

`solveWithLcgInIsolates` runs `Problem.solveWithLcg` across
`workerCount` worker isolates as a **portfolio** — each worker gets a
distinct `seeds` entry (and defaults to `useVsids`, so the seeds actually
diversify the search). The first worker to find a solution wins and the
rest are torn down; the aggregate is `'FAILURE'` only once *every* worker
has exhausted its search, so a cancelled or timed-out worker can never be
mistaken for a genuine UNSAT proof. Same contract as `solveInIsolate`
(`Map` on success, `'FAILURE'` otherwise); the winner's `SolverStats` is
copied into `CSP.lastStats`.

```dart
final solution = await solveWithLcgInIsolates(
  buildMyProblem,
  workerCount: 4,
  shareClauses: true,   // cooperative mode (default: portfolio only)
);
```

With `shareClauses: true` the portfolio becomes **cooperative**: each
worker exports its short learned clauses (≤ `maxSharedClauseLen`, default
8 literals) to the parent, which re-broadcasts them to the siblings; every
worker imports the others' clauses into its own learned-clause pool
(`SolverStats.importedClauses` counts them). Sharing is always sound —
every worker solves the same problem, so a clause learned by one is a
valid nogood for all — and it never changes the verdict. **Experimental**,
like parallel LNS.

## Range-Domain Variables (Scheduling)

For variables whose domain is a contiguous integer range — for
example the start time of a task in a schedule, where the value can
be any minute in `[0, horizon]` — use `addRangeVariable`:

```dart
final p = Problem()
  ..addRangeVariable('start',    0, 100)   // start in [0, 100]
  ..addRangeVariable('duration', 1,   5)   // duration in [1, 5]
  ..addRangeVariable('end',      0, 100)   // end in [0, 100]
  ..addLinearEquals(['start', 'duration', 'end'], [1, 1, -1], 0);
final s = await p.minimize('end');
```

For range spans larger than 1024, the engine uses a compact `(min,
max)` domain representation internally, with `O(1)` membership /
length / bounds. Bounds-only reductions (e.g. from the linear
arithmetic propagator) stay in the same form without allocating
per-step domain lists. For smaller ranges, `addRangeVariable` is
equivalent to `addVariable(name, [for (var i = min; i <= max; i++) i])`
and the engine uses the existing bitset representation.

### Disjunctive scheduling: `addNoOverlap`

For unary-resource scheduling (one task at a time on a machine), use
`addNoOverlap(starts, durations)`. It posts, for every pair `(i, j)`,
the disjunction
`starts[i] + durations[i] <= starts[j]` OR
`starts[j] + durations[j] <= starts[i]`,
so the half-open intervals `[start, start + duration)` do not
overlap. Durations are constants; for variable durations, model the
end time as a separate variable and use the linear-arithmetic
propagator to relate them.

```dart
// Three jobs on one machine, durations 4 / 3 / 2, horizon 20.
// Minimize makespan (the latest end time).
final p = Problem()
  ..addRangeVariable('s0', 0, 20)
  ..addRangeVariable('s1', 0, 20)
  ..addRangeVariable('s2', 0, 20)
  ..addRangeVariable('mk', 0, 20)
  ..addNoOverlap(['s0', 's1', 's2'], [4, 3, 2])
  ..addLinearGeq(['mk', 's0'], [1, -1], 4)  // mk >= s0 + 4
  ..addLinearGeq(['mk', 's1'], [1, -1], 3)  // mk >= s1 + 3
  ..addLinearGeq(['mk', 's2'], [1, -1], 2); // mk >= s2 + 2
final s = await p.minimize('mk');
// mk = 9 (sum of durations — they're forced to pack tight).
```

The current `addNoOverlap` posts `O(n²)` pairwise binary
disjunctions. This is sound and compact; for stronger pruning with
arbitrary integer capacity, use [`addCumulative`](#cumulative-resource-scheduling)
(see below) — the unary case (`capacity = 1`, all demands `= 1`)
is a strictly stronger encoding of the same constraint when paired
with the time-table + energetic-reasoning propagators.

### Cumulative resource scheduling

For a renewable resource with integer capacity that several tasks
may share (machines with `K` slots, parallel workers, a shop with
`K` looms, etc.), use `addCumulative(starts, durations, demands,
capacity)`. At every time `t`, the sum of `demands[i]` across tasks
whose half-open interval `[starts[i], starts[i] + durations[i])`
covers `t` must not exceed `capacity`.

Tagged internally with a `CumulativeSpec` so the engine dispatches
to two complementary filtering passes:

1. A **time-table** propagator (Beldiceanu & Carlsson 2002 style):
   compute each task's *compulsory part* — the interval the task must
   occupy in every feasible schedule — sum the compulsory parts into a
   global usage profile, and prune any start value that would push the
   profile above `capacity` at some time.
2. An **energetic-reasoning** pass (Baptiste, Le Pape & Nuijten 1999):
   over the relevant time windows, sum every task's minimum
   intersection energy; a window whose total exceeds `capacity ×
   width` is infeasible, and the left-shift / right-shift slack bounds
   tighten earliest-start / latest-completion times that the
   time-table profile alone leaves loose. This catches energy
   conflicts in problems with slack (tight RCPSP-style schedules)
   well before the time-table would. The O(n³) pass is capped above
   64 tasks (the time-table alone — still sound — covers those); under
   LCG learning the overload **check** still runs (an over-capacity
   window is a sound, explained conflict) while the bound *adjustments*
   are skipped (their prunes have no explanation companion). Pass
   `useEnergeticReasoning: false` to `addCumulative` to opt out of the
   pass entirely.

On tight RCPSP instances energetic reasoning more than pays back its
per-propagation cost (plain backtracking, default MRV, 25-rep median —
`bench(cumulative)`):

| 8-task cap-2 (UNSAT)          | time-table only | + energetic |
| ---------------------------- | --------------- | ----------- |
| energetic overload at root   | 871 dec / 43 ms | 0 dec / 0.05 ms |
| energetic pruning in search  | 770 dec / 28 ms | 112 dec / 8.8 ms |

```dart
// Three tasks on a machine with 2 parallel slots.
// dur=2 dem=1, dur=2 dem=1, dur=2 dem=2; total resource-time = 8
// on capacity 2 ⇒ makespan lower bound 4 (the two dem=1 tasks run
// in parallel; the dem=2 task runs alone).
final p = Problem()
  ..addRangeVariable('s0', 0, 10)
  ..addRangeVariable('s1', 0, 10)
  ..addRangeVariable('s2', 0, 10)
  ..addRangeVariable('mk', 0, 10)
  ..addCumulative(
      ['s0', 's1', 's2'], [2, 2, 2], [1, 1, 2], 2)
  ..addLinearGeq(['mk', 's0'], [1, -1], 2)
  ..addLinearGeq(['mk', 's1'], [1, -1], 2)
  ..addLinearGeq(['mk', 's2'], [1, -1], 2);
final s = await p.minimize('mk');   // mk = 4
```

Composes naturally with multiple resource types: post one
`addCumulative` per resource (RCPSP-style models). Setting
`capacity = 1` and every demand to `1` reduces `addCumulative` to
disjunctive (unary) no-overlap, with stronger propagation than the
pairwise-disjunction `addNoOverlap` encoding on tight schedules.

## Set Variables

For variables that range over the *subsets* of a finite universe,
use `addSetVariable`. Internally each universe element gets a 0/1
indicator variable, and the existing primitives (linear arithmetic
for cardinality, generic n-ary for membership combinations) handle
propagation. Solutions returned through every solve entry point
expose set variables as `Set<dynamic>` of the included elements —
the internal indicators are stripped from the result map.

```dart
const roster = ['alice', 'bob', 'carol', 'dave', 'erin'];
final p = Problem()
  ..addSetVariables(['Team', 'Bench'], universe: roster)
  ..addSetCardinality('Team', 3)
  ..addSetCardinality('Bench', 2)
  ..addSetDisjoint('Team', 'Bench')
  ..addRequiredInSet('Team', 'alice');

final result = await p.getSolution() as Map<String, dynamic>;
print(result['Team']);   // Set<dynamic> of 3 names including 'alice'
print(result['Bench']);  // Set<dynamic> of 2 names, disjoint from Team
```

### Declaration

- `addSetVariable(name, {universe, required, excluded})` — declares
  one set variable. `required` pins the listed elements in, `excluded`
  pins them out at declaration time.
- `addSetVariables(names, {universe, required, excluded})` —
  convenience for declaring several set variables that share a
  universe and (optionally) pin sets.

### Cardinality

- `addSetCardinality(setName, k)` — `|setName| == k`.
- `addSetCardinalityRange(setName, minCard, maxCard)` —
  `minCard <= |setName| <= maxCard`.
- `addSetCardinalityVar(setName, countVar)` —
  `|setName| == countVar` (compose with `minimize` / `maximize` to
  drive size optimization).

### Element pins (post-declaration)

- `addRequiredInSet(setName, element)` — `element ∈ setName`.
- `addExcludedFromSet(setName, element)` — `element ∉ setName`.

### Pairwise relations

- `addSubset(subName, superName)` — `subName ⊆ superName`.
- `addSetEquals(a, b)` — `a == b` (universes must match as sets).
- `addSetDisjoint(a, b)` — `a ∩ b == ∅`.

### Ternary relations

- `addSetUnion(a, b, result)` — `result == a ∪ b`.
- `addSetIntersection(a, b, result)` — `result == a ∩ b`.
- `addSetDifference(a, b, result)` — `result == a \ b`.

All three set variables must share the same universe (as a set).

### Escape hatch: `memberIndicator`

When you need to compose set membership with the reified, logical,
linear, or arithmetic helpers, look up the underlying 0/1 indicator
variable with `memberIndicator(setName, element)`. For example,
"if X assigns the value 7 then 7 must be in S":

```dart
p.addReifiedEquals('bX7', 'X', 7);
final ind = p.memberIndicator('S', 7);
p.addConstraint([ind, 'bX7'],
    (i, b) => !(b == 1 && i == 0));  // bX7 == 1 ⇒ ind == 1
```

See [`doc/set-variables.md`](doc/set-variables.md) for the
indicator-decomposition model in full and for guidance on when the
sugar is worth using vs. modeling the indicators directly.

## Continuous / Real Variables (experimental)

The integer engine enumerates domains, so it cannot represent fractional
quantities. `ContinuousModel` is a self-contained solver over real
intervals — it prunes with bound propagation and branches by bisection
until every variable's box is narrower than a tolerance.

```dart
final m = ContinuousModel();
final x = m.addVar('x', 0, 10);
final y = m.addVar('y', 0, 10);
(x + y).eq(10);
(x - y).eq(4);

final sol = m.solve(epsilon: 1e-9);   // ContinuousSolution or null
print(sol?.midpoint);                  // {x: 7.0, y: 3.0}
```

The `FloatVar` / `FloatExpr` DSL mirrors the integer one (`+`, `-`, unary
`-`, `* scalar`; `le` / `ge` / `eq`), and **non-linear** products are
supported too — `(x * y).eq(6)`, `(x * x).eq(2)`, circle-line
intersections — lowered to interval product constraints under the hood:

```dart
final m = ContinuousModel();
final x = m.addVar('x', 0, 5);
final y = m.addVar('y', 0, 5);
(x * y).eq(6);
(x + y).eq(5);
print(m.solve(epsilon: 1e-7)?.midpoint);   // {x: 2.0, y: 3.0}
```

This is a **preview**: no integer/continuous mixing yet, and plain IEEE-754
arithmetic — a returned box is a high-precision witness, not a formally
verified enclosure. See `PLAN.md` / `doc/next-engine-work.md` for the
remaining work and `example/continuous.dart` for a runnable demo.

## Documentation

In-depth topical guides live in [`doc/`](doc/):

- [`doc/algorithms.md`](doc/algorithms.md) — Backtracking, AC-3, GAC,
  MRV/LCV, and the cooperative-yield contract that lets `.timeout()`
  fire on a CPU-bound solve.
- [`doc/cbj.md`](doc/cbj.md) — Conflict-directed backjumping: the
  algorithm, the coarse conflict-cause approximation, how to read
  `backjumps` / `backjumpLevelsSkipped`, when CBJ pays off and when
  it doesn't.
- [`doc/propagation-trace.md`](doc/propagation-trace.md) — The opt-in
  fine-grained propagation trace (`onPropagation` / `solveWithTrace`):
  the event schema, how a `prune`'s cause mirrors MUS output, the
  `maxEvents` cap, zero-overhead-when-unset, and crossing the isolate
  boundary.
- [`doc/conflict-explanation.md`](doc/conflict-explanation.md) —
  Conflict explanation via deletion-based MUS: the algorithm, how
  `ConstraintRef` granularity surfaces decomposed helpers, when MUS
  is useful (and when it's overkill), open follow-ups.
- [`doc/heuristics.md`](doc/heuristics.md) — Consolidated guide to
  the variable-ordering heuristics (MRV / dom-wdeg / VSIDS / IBS /
  LC): how each works, which to use when, picker dispatch order,
  composition rules, and a side-by-side bench snapshot.
- [`doc/cancellation.md`](doc/cancellation.md) — The unified story for
  `CancellationToken`, wrapping `Future.timeout(...)`, and the
  worker-isolate runner — when to reach for each and how they compose.
- [`doc/string-constraints.md`](doc/string-constraints.md) — Full
  grammar reference for the string parser, dispatch table to built-in
  factories, what's *not* supported.
- [`doc/multi-solutions.md`](doc/multi-solutions.md) — Decision tree for
  the streaming / counting / enumeration APIs.
- [`doc/min-conflicts.md`](doc/min-conflicts.md) — When (and when not)
  to use the local-search solver.
- [`doc/global-cardinality.md`](doc/global-cardinality.md) — `among`,
  `nvalue`, `gcc` and how to compose them for rostering, palette
  restriction, and chromatic-number-style optimization.
- [`doc/set-variables.md`](doc/set-variables.md) — Set-valued
  variables, the indicator-decomposition model, when the sugar pays
  off, and how to compose with the rest of the library.

See also [`STABILITY.md`](STABILITY.md) for the public-API
stability tiers (stable vs experimental), the semver policy that
governs each tier, and the documented gotchas (notably the
single-static-slot nature of `lastStats`).

The CI workflow also runs `dart doc .` on every build to generate
inline-API HTML to `doc/api/`.

## Testing

The library includes a comprehensive test suite covering all functionality:

```bash
# Run all tests
dart test

# Run tests with coverage
dart pub global activate coverage
dart pub global run coverage:test_with_coverage

# Run specific test groups
dart test test/dart_csp_test.dart -n "Basic Problem Creation"
dart test test/dart_csp_test.dart -n "String Constraints"

# Run a specific test file
dart test test/builtin_and_parser_test.dart
dart test test/minconflicts_tests.dart
dart test test/multisolutions_tests.dart
```

### Test Coverage

The test suite includes test cases covering:

- **Basic Problem Creation**: Variable addition, domain validation, constraint setup
- **Binary Constraints**: Two-variable relationships and consistency
- **N-ary Constraints**: Multi-variable constraints and complex relationships  
- **String Constraints**: All parsing scenarios and edge cases
- **Built-in Constraints**: Every constraint factory function and extension method
- **Complex Problems**: Magic squares, N-Queens, Sudoku, map coloring
- **Convenience Functions**: Top-level utility functions
- **Failure Cases**: Over-constrained and unsolvable problems
- **Problem Utilities**: Validation, debugging, and introspection
- **Edge Cases**: Malformed constraints, missing variables, empty domains

## Advanced Usage

### Debugging and Problem Validation

```dart
final p = Problem();
p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
p.addStringConstraint('A != B');

// Print problem summary
p.printSummary();

// Validate problem for common issues
final issues = p.validate();
if (issues.isEmpty) {
  print('Problem validation: ✓ No issues found');
} else {
  print('Problem validation issues:');
  for (final issue in issues) {
    print('  - $issue');
  }
}
```

### Visualization and Monitoring

Monitor the solver's progress with callback functions:

```dart
void visualizer(
  Map<String, List<dynamic>> assigned,
  Map<String, List<dynamic>> unassigned,
) {
  print("\n--- Solver Step ---");
  print("Assigned: $assigned");
  print("Unassigned Domains: $unassigned");
}

final p = Problem();
// ... define problem ...
p.setOptions(
  timeStep: 100, // 100ms pause between steps
  callback: visualizer,
);

final solution = await p.getSolution();
```

#### Fine-grained propagation trace

For a step-by-step replay of *propagation itself* — which arc/constraint
fired, which value left which domain, and whether the branch ended in a
solution or a dead-end — register a `PropagationObserver` instead of (or
alongside) the coarse callback above:

```dart
final trace = await p.solveWithTrace();
// trace.result    -> Map assignment, or 'FAILURE'
// trace.events    -> List<PropagationEvent> in emission order
// trace.truncated -> true if the maxEvents cap was hit

for (final e in trace.events) {
  switch (e.kind) {
    case PropagationEventKind.decision:
      print('decide ${e.variable} = ${e.value} @depth ${e.depth}');
    case PropagationEventKind.prune:
      print('prune ${e.variable}: -${e.removedValues} '
          '(${e.domainBefore} -> ${e.domainAfter}) by ${e.causeDescription}');
    case PropagationEventKind.domainWipeout:
      print('dead end: ${e.variable} emptied by ${e.causeDescription}');
    case PropagationEventKind.backtrack:
    case PropagationEventKind.backjump:
    case PropagationEventKind.solution:
      print(e);
  }
}
```

Each `prune` / `domainWipeout` carries the pruned variable, the removed
value(s), the domain `before`→`after`, and the cause as `causeKind` +
`causeLabel` + `causeScope` — the same `kind` / `label` / scope vocabulary
the [conflict-explanation MUS API](#conflict-explanation-mus) uses, so a UI
can render propagation causes exactly like conflict explanations. The
observer is **zero overhead when unset** (every emission is guarded), is
bounded by `maxEvents` (default 100000, with `trace.truncated` /
`CSP.lastTraceTruncated` flagging truncation), and emits plain-map
serializable events (`toMap` / `fromMap`) that cross the isolate boundary
via `solveInIsolateWithTrace(...)` (and `minimize` / `maximize` /
`solveAll` siblings). See
[`doc/propagation-trace.md`](doc/propagation-trace.md) for the full event
schema. The original coarse `callback` is unchanged and independent.

### Performance Optimization

1. **Use String Constraints**: Often more readable and just as fast as built-ins
2. **Use Built-in Constraints**: `addAllDifferent()` is faster than custom lambdas
3. **Restrict Domains Early**: Smaller initial domains = faster solving
4. **Strategic Constraint Ordering**: Add most constraining constraints first
5. **Consider Clues**: For puzzles, pre-fill strategic positions to reduce search space

```dart
// Performance example: Magic square with a strategic clue.
//
// For a 3x3 magic square, the center cell must be 5. Pinning B2={5} and
// excluding 5 from every other cell's domain prunes the search by ~20x:
// with the clue the problem solves in ~5s; without it, ~100s.
//
// String constraints are NOT slower than the built-in helpers here. The
// parser dispatches 'X + Y + Z == 15' to the same `exactSum(15)` factory
// as `addExactSum`, so the choice is one of style, not performance.
final p = Problem();

// Strategic clue: the center cell of a 3x3 magic square is always 5.
p.addVariable('B2', [5]);

// Remaining variables exclude the clue value.
final otherPositions = ['A1', 'A2', 'A3', 'B1', 'B3', 'C1', 'C2', 'C3'];
p.addVariables(otherPositions, [1, 2, 3, 4, 6, 7, 8, 9]);

p.addAllDifferent(['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3']);

// Rows, columns, and diagonals all sum to 15. Either form works.
p.addStringConstraints([
  'A1 + A2 + A3 == 15',
  'B1 + B2 + B3 == 15',
  'C1 + C2 + C3 == 15',
  'A1 + B1 + C1 == 15',
  'A2 + B2 + C2 == 15',
  'A3 + B3 + C3 == 15',
  'A1 + B2 + C3 == 15',
  'A3 + B2 + C1 == 15',
]);
```

### How string constraints relate to the built-in factories

When you write a recognized pattern like `'A + B + C == 15'`, the parser
dispatches it to the corresponding built-in factory (`exactSum(15)` here)
rather than a generic expression evaluator. The same applies to:

| Pattern | Dispatches to |
|---------|---------------|
| `A + B + ... == k` | `exactSum(k)` |
| `A * B * ... == k` | `exactProduct(k)` |
| `A + B + ... >= k` (/ `>`) | `minSum(k)` (k offset by 1e-3 for strict) |
| `A + B + ... <= k` (/ `<`) | `maxSum(k)` |
| `A * B * ... >= k` (/ `>`) | `minProduct(k)` |
| `A * B * ... <= k` (/ `<`) | `maxProduct(k)` |
| `k <= A + B + ... <= m` | `sumInRange(k, m)` |
| `A != B != C ...` | `allDifferent()` |
| `A < B < C ...` (/ `<=`) | `strictlyAscendingInOrder()` / `ascendingInOrder()` |
| `A in [...]` / `A not in [...]` | `inSet()` / `notInSet()` |
| `A op N` (single var vs constant) | specialized lambda |
| `A op B` (two vars, op ∈ <,<=,>,>=) | specialized binary lambda |

Anything else falls through to a generic `ExpressionEvaluator.evaluateBoolean`
on every check, which is substantially slower because it re-tokenizes the
expression for each candidate assignment. If you find a constraint that's
hot in your profile, try to phrase it so it hits one of the fast paths
above, or call the factory directly.

## API Reference

### Problem Class (Builder) - Core Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `addVariable()` | `String name`, `List<dynamic> domain` | Adds a single variable with its domain |
| `addVariables()` | `List<String> names`, `List<dynamic> domain` | Adds multiple variables sharing the same domain |
| `addConstraint()` | `List<String> vars`, `Function predicate` | Adds custom binary or n-ary constraint |
| `addStringConstraint()` | `String constraint` | Adds constraint from string expression |
| `addStringConstraints()` | `List<String> constraints` | Adds multiple string constraints |
| `setOptions()` | `int? timeStep`, `CspCallback? callback` | Sets visualization parameters |
| `getSolution()` | (none) | Builds and solves the problem |

### Problem Class - Built-in Constraint Extensions

| Method | Parameters | Description |
|--------|------------|-------------|
| `addAllDifferent()` | `List<String> variables` | All variables have different values |
| `addAllEqual()` | `List<String> variables` | All variables have the same value |
| `addExactSum()` | `List<String> vars`, `num sum`, `List<num>? multipliers` | Variables sum to exact value |
| `addSumRange()` | `List<String> vars`, `num min`, `num max`, `List<num>? multipliers` | Sum within range |
| `addExactProduct()` | `List<String> vars`, `num product` | Variables multiply to exact value |
| `addInSet()` | `List<String> vars`, `Set<dynamic> allowed` | Variables must be from allowed set |
| `addNotInSet()` | `List<String> vars`, `Set<dynamic> forbidden` | Variables cannot be from forbidden set |
| `addAscending()` | `List<String> variables` | Variables in non-decreasing order |
| `addStrictlyAscending()` | `List<String> variables` | Variables in strictly increasing order |
| `addDescending()` | `List<String> variables` | Variables in non-increasing order |

### Problem Class - Debugging Extensions

| Method | Returns | Description |
|--------|---------|-------------|
| `printSummary()` | `void` | Prints problem overview to console |
| `validate()` | `List<String>` | Returns list of potential issues |
| `copy()` | `Problem` | Creates a deep copy of the problem |
| `clear()` | `void` | Removes all variables and constraints |
| `variableCount` | `int` | Number of variables in problem |
| `constraintCount` | `int` | Number of constraints in problem |

### Built-in Constraint Factory Functions

#### Equality Constraints
- `allDifferent()` → `NaryPredicate`
- `allDifferentBinary()` → `BinaryPredicate`  
- `allEqual()` → `NaryPredicate`
- `allEqualBinary()` → `BinaryPredicate`

#### Arithmetic Constraints
- `exactSum(num target, {List<num>? multipliers})` → `NaryPredicate`
- `minSum(num minimum, {List<num>? multipliers})` → `NaryPredicate`
- `maxSum(num maximum, {List<num>? multipliers})` → `NaryPredicate`
- `sumInRange(num min, num max, {List<num>? multipliers})` → `NaryPredicate`
- `exactProduct(num target)` → `NaryPredicate`
- `minProduct(num minimum)` → `NaryPredicate`
- `maxProduct(num maximum)` → `NaryPredicate`

#### Set Membership Constraints  
- `inSet(Set<dynamic> allowed)` → `NaryPredicate`
- `notInSet(Set<dynamic> forbidden)` → `NaryPredicate`
- `someInSet(Set<dynamic> values, int minimum)` → `NaryPredicate`
- `someNotInSet(Set<dynamic> values, int minimum)` → `NaryPredicate`

#### Ordering Constraints
- `ascendingInOrder(List<String> order)` → `NaryPredicate`
- `strictlyAscendingInOrder(List<String> order)` → `NaryPredicate`
- `descendingInOrder(List<String> order)` → `NaryPredicate`

*Note: Binary versions (suffix `Binary`) are available for 2-variable optimizations.*

### Convenience Functions

| Function | Parameters | Description |
|----------|------------|-------------|
| `solveProblem()` | `Map<String, List<dynamic>> variables`, `List<String> constraints` | Solve with string constraints |
| `solveAllDifferent()` | `List<String> variables`, `List<dynamic> domain` | Quick all-different solver |  
| `solveSumProblem()` | `List<String> variables`, `List<dynamic> domain`, `num targetSum` | Quick sum constraint solver |

### CspProblem Class (Manual Construction)

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `variables` | `Map<String, List<dynamic>>` | ✅ | Variable names mapped to their domains |
| `constraints` | `List<BinaryConstraint>` | ❌ | Rules between pairs of variables |
| `naryConstraints` | `List<NaryConstraint>` | ❌ | Rules among groups of variables |
| `cb` | `CspCallback?` | ❌ | Visualization callback function |
| `timeStep` | `int` | ❌ | Delay in ms between visualization steps |

### Constraint Classes

#### BinaryConstraint
```dart
BinaryConstraint(
  String head,                           // First variable
  String tail,                           // Second variable  
  bool Function(dynamic, dynamic) predicate  // Validation function
)
```

#### NaryConstraint  
```dart
NaryConstraint({
  required List<String> vars,                        // All involved variables
  required bool Function(Map<String, dynamic>) predicate  // Validation function
})
```

### Type Definitions

```dart
typedef BinaryPredicate = bool Function(dynamic headVal, dynamic tailVal);
typedef NaryPredicate = bool Function(Map<String, dynamic> assignment);
typedef CspCallback = void Function(
  Map<String, List<dynamic>> assigned, 
  Map<String, List<dynamic>> unassigned
);
```

## Project Structure

The library is organized into focused, modular components:

```
lib/
├── dart_csp.dart                 # Main library export and convenience functions
└── src/
    ├── types.dart                # Core type definitions and interfaces  
    ├── solver.dart               # CSP solver with backtracking, AC-3, GAC
    ├── problem.dart              # Problem builder class and extensions
    ├── builtin_constraints.dart  # Optimized constraint factory functions
    └── constraint_parser.dart    # String constraint parsing engine

example/
├── demo.dart                     # Comprehensive demo of all features
├── example.dart                  # Walkthrough of the three constraint APIs
├── multi_solutions.dart          # Enumerating all / first-N solutions
├── gencw.dart                    # Arithmetic crosswords puzzle generator
└── gensq.dart                    # Arithmetic square puzzle generator

test/
├── dart_csp_test.dart            # Core solver, builder, and parser tests
├── builtin_and_parser_test.dart  # Built-in constraint factories + expression eval
├── minconflicts_tests.dart       # Min-conflicts local search solver
└── multisolutions_tests.dart     # Streaming / multi-solution enumeration

doc/
├── algorithms.md                 # Backtracking, AC-3, GAC, MRV/LCV, min-conflicts
├── string-constraints.md         # Full string-constraint grammar reference
├── multi-solutions.md            # Enumeration / streaming API guide
└── min-conflicts.md              # Local search solver guide
```

## Running the Demo

The comprehensive demo (`example/demo.dart`) showcases all library features with 11 different problems:

```bash
dart run example/demo.dart
```

### Demo Contents

1. **USA Map Coloring** - Compares old vs new constraint methods
2. **8-Queens Problem** - Classic backtracking demonstration  
3. **Sudoku Solver** - Using built-in `allDifferent` constraints
4. **All Different & Equal Constraints** - Basic constraint examples
5. **Sum Constraints** - Arithmetic constraint varieties
6. **Product Constraints** - Multiplication-based rules
7. **Set Membership** - Value inclusion/exclusion constraints
8. **Ordering Constraints** - Sequential arrangement rules
9. **Magic Square** - Complex multi-constraint problem with random clues
10. **Resource Allocation** - Real-world optimization scenario
11. **Class Scheduling** - Timetabling with multiple constraint types

Each demo includes:
- Problem setup explanation
- Constraint definition examples  
- Solution verification
- Performance timing

## Performance Tips

1. **Use String Constraints**: Natural syntax with good performance
2. **Use Built-in Constraints**: Pre-optimized functions are faster than equivalent lambdas
3. **Strategic Domain Reduction**: Limit initial domains as much as possible
4. **Constraint Ordering**: Add most restrictive constraints first
5. **Choose Appropriate Constraint Types**: Use binary constraints for 2-variable rules
6. **Consider Problem Structure**: Add strategic "clues" to reduce search space

### Performance Comparison

```dart
// Readable and fast: String constraints  
p.addStringConstraints(['A != B != C', 'A + B + C == 10']);

// Also fast: Built-in constraints
p.addAllDifferent(['A', 'B', 'C']);
p.addExactSum(['A', 'B', 'C'], 10);

// Slower but flexible: Custom lambda
p.addConstraint(['A', 'B', 'C'], (assignment) {
  final values = assignment.values.toSet();
  return values.length == assignment.length && 
         values.fold<num>(0, (sum, v) => sum + v) == 10;
});

// Fastest for 2 variables: Binary constraint
p.addConstraint(['A', 'B'], allDifferentBinary());
```

## Contributing

Contributions are welcome! Please open an issue or pull request on [the repository](https://github.com/CrispStrobe/dart_csp).

### Development Setup

1. Clone the repository
2. Install dependencies: `dart pub get`
3. Run tests: `dart test`
4. Run the demo: `dart run example/demo.dart`
5. Run a walkthrough example: `dart run example/example.dart`

## License

MIT — see [`LICENSE`](LICENSE). See [`NOTICE`](NOTICE) for a short
historical note on how the codebase reached its current MIT-clean
state.

---

*Built with ❤️ for the Dart & Flutter community*
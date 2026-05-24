# Enumerating multiple solutions

`dart_csp` exposes several ways to get more than the first solution from
a problem. They are all powered by the same backtracking generator
(`_backtrackAll` in `lib/src/solver.dart`); the API differences are about
how the results are surfaced and how much you load into memory.

## At a glance

| Method | Returns | Use when |
|--------|---------|----------|
| `Problem.getSolution()` | `Future<dynamic>` (first solution, or the string `'FAILURE'`) | You only need one answer. Cheapest. |
| `Problem.getSolutions()` | `Stream<Map<String, dynamic>>` | You want to iterate solutions as they're found, possibly stopping early. |
| `Problem.getAllSolutions()` | `Future<List<Map<String, dynamic>>>` | The full set fits in memory and you need them all at once. |
| `Problem.countSolutions()` | `Future<int>` | You only need the count, not the assignments themselves. |
| `Problem.hasMultipleSolutions()` | `Future<bool>` | "Is the answer unique?" — short-circuits after the second solution. |
| `Problem.getFirstNSolutions(n)` | `Future<List<Map<String, dynamic>>>` | Bounded sample of solutions; stops at n. |

Top-level convenience wrappers in `lib/dart_csp.dart` cover the same
operations without building a `Problem` first:

- `solveProblem({variables, constraints})` — first solution
- `solveAllProblems({variables, constraints})` — stream of all
- `countAllSolutions({variables, constraints})` — count without storing
- `hasMultipleSolutions({variables, constraints})` — uniqueness check
- `getFirstNSolutions({n, variables, constraints})` — bounded list
- `solveAllDifferent(...)`, `solveAllDifferentMultiple(...)`,
  `solveSumProblem(...)`, `solveSumProblemMultiple(...)` — shortcuts for
  common shapes

## Picking the right API

The decision tree:

```
Need just one solution?
  └─ getSolution() / solveProblem(...)

Need the count, not the values?
  └─ countSolutions() / countAllSolutions(...)

Need to know if there's more than one?
  └─ hasMultipleSolutions() — STOPS after second match

Need a bounded number?
  └─ getFirstNSolutions(n) — STOPS after n

Need all of them?
  ├─ List comfortably fits in memory?
  │    └─ getAllSolutions()
  └─ Otherwise (or you want to stream-process):
       └─ getSolutions() — Stream, never materialized in full
```

Use the streaming API whenever the solution set might be large. The
backtracker yields one solution at a time and pauses; the next solution
isn't computed until you `await` the next stream event.

## Examples

### Stream all solutions, stop on a condition

```dart
final p = Problem()
  ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
  ..addAllDifferent(['A', 'B', 'C'])
  ..addStringConstraint('A + B + C >= 9');

await for (final s in p.getSolutions()) {
  print(s);
  if (s['A'] == 4) break;  // stops the generator
}
```

Breaking out of the `await for` is enough — there's no manual cleanup;
the underlying generator is paused and discarded by the runtime.

### Count without materializing

```dart
final count = await countAllSolutions(
  variables: {'X': [1, 2, 3, 4], 'Y': [1, 2, 3, 4]},
  constraints: ['X < Y'],
);
// count == 6
```

### Uniqueness check

```dart
final unique = !await hasMultipleSolutions(
  variables: {'A': [1, 2, 3], 'B': [1, 2, 3]},
  constraints: ['A + B == 4'],
);
```

`hasMultipleSolutions` short-circuits the moment a second solution is
found, so this is cheaper than `countSolutions() == 1` on problems with
many solutions.

### Sample the first N

```dart
final firstThree = await getFirstNSolutions(
  n: 3,
  variables: {'A': [1, 2, 3, 4, 5], 'B': [1, 2, 3, 4, 5]},
  constraints: ['A < B'],
);
// 3 solutions, even though many more exist
```

### Combine with min-conflicts?

You can't — min-conflicts is a single-solution local search and does not
enumerate. If you need both speed *and* multiple solutions, run
backtracking and stream the results.

## Solution shape

Every solution is a `Map<String, dynamic>` mapping variable name to its
assigned value. Domains are preserved as the dynamic type you put in
(e.g. `int`, `String`), so cast at the use site if you need typed access.

```dart
final s = (await p.getSolution()) as Map<String, dynamic>;
final aValue = s['A'] as int;
```

Failure is always the literal string `'FAILURE'` from `getSolution()`.
The stream variants emit nothing on failure — an empty stream means "no
solutions exist", not "error".

## See also

- [algorithms.md](algorithms.md) — why MRV + AC-3/GAC is what powers
  this and why solving for "all" is usually cheaper than n × "first".
- [min-conflicts.md](min-conflicts.md) — the local-search alternative
  for the *single*-solution case.

# Min-Conflicts solver

`Problem.solveWithMinConflicts({int maxSteps = 1000})` is an alternative
to the default backtracking solver. It is a **local search** algorithm:
it starts from a random complete assignment and iteratively repairs it,
moving one variable at a time toward fewer constraint violations.

This document explains when to reach for it and what to expect.

## TL;DR

| | Backtracking (default) | Min-Conflicts |
|---|---|---|
| Entry point | `getSolution()`, `getSolutions()` | `solveWithMinConflicts(maxSteps: ...)` |
| Completeness | Complete: returns a solution iff one exists | Incomplete: may return `'FAILURE'` even when a solution exists |
| Worst case | Exponential in variables | `O(maxSteps × |vars| × |max domain|)` per run |
| Finds *all* solutions | Yes (`getSolutions()` / `getAllSolutions()`) | **No** — one run gives at most one |
| Best for | Tightly-constrained, structured problems | Loosely-constrained, large problems where a satisfying-but-not-unique answer is fine |

Use backtracking by default. Switch to min-conflicts only when (a) the
problem is too big for the default to finish in a useful time, and (b)
you only need *some* solution, not a specific one or all of them.

## The algorithm

```
current = random complete assignment of all variables
repeat maxSteps times:
    conflicted = variables that participate in any violated constraint
    if conflicted is empty:
        return current             # solution found
    var = random pick from conflicted
    val = value from var's domain that minimizes total conflicts
          (ties broken randomly)
    current[var] = val
return FAILURE                      # gave up after maxSteps
```

Two things to notice:

1. **Random restarts are not built in.** A single call runs from one
   random initial assignment for at most `maxSteps` repair steps. If you
   want random restarts, wrap the call in your own retry loop:

   ```dart
   for (var i = 0; i < 5; i++) {
     final r = await p.solveWithMinConflicts(maxSteps: 1000);
     if (r is Map<String, dynamic>) return r;
   }
   ```

2. **Local optima are real.** Min-conflicts can plateau in a region of
   the search space where every single-variable change increases the
   conflict count. It cannot escape such a state on its own — `maxSteps`
   will simply run out. Restarts help; tightening constraints helps;
   choosing backtracking for these problems helps most.

The implementation is in `lib/src/solver.dart` (`solveWithMinConflicts`,
`_getConflictedVariables`, `_countConflictsForVar`).

## When it's a good fit

- **8-queens, n-queens at large n.** A classic case where random
  initial assignments + greedy repair converges in O(n) steps for most
  starting positions. The test suite verifies this.
- **Map coloring, scheduling, assignment problems with many feasible
  answers.** Local search shines when the satisfying set is large
  relative to the search space.
- **Real-time constraints** where you'd rather have *an* answer in
  ~50ms than the optimal answer in 5s.

## When to avoid it

- **Puzzles with a unique solution** (Sudoku, magic squares, exact-cover
  problems). Local search has nothing to bias it toward the one valid
  assignment.
- **Problems where you need to enumerate solutions.** Min-conflicts
  produces at most one.
- **Problems with hard infeasibility** that you want detected. A
  `'FAILURE'` return tells you "min-conflicts gave up", not
  "no solution exists" — the two are indistinguishable to this solver.

## Limitations of the current implementation

- **No callback / `setOptions` support.** `timeStep` and the visualizer
  callback set on a `Problem` are ignored by min-conflicts. The
  algorithm runs straight through.
- **Naive tie-breaking only.** Tied values are chosen uniformly at
  random. No tabu list, no weighted heuristics, no plateau detection.
- **No automatic restart.** If you want robust convergence, wrap the
  call in your own retry loop (see snippet above).
- **Binary and n-ary constraints are honored**, but the conflict count
  for an n-ary violation increments the conflict score by 1 — not by
  the number of variables involved. This is a deliberate simplification
  and is fine in practice for the problems above.

## Choosing `maxSteps`

The default 1000 is enough for small problems (8-queens, small map
coloring). Rule of thumb for sizing it:

- Start with `maxSteps = max(1000, 10 * variables.length)`.
- If you hit `'FAILURE'` repeatedly, try 2-3× more steps before adding
  restarts — most plateaus are *not* escaped by more steps.
- If even big `maxSteps` plus restarts fail consistently, the problem
  isn't a good fit for min-conflicts. Use backtracking.

## See also

- [algorithms.md](algorithms.md) — for the default backtracking solver.
- [multi-solutions.md](multi-solutions.md) — for enumerating answers
  (which min-conflicts cannot do).

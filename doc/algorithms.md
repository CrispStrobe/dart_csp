# Algorithms

`dart_csp` ships two distinct solvers and a small set of pruning techniques.
The defaults work for most problems, so this document is mainly here for
when you want to understand *why* a search is slow, or which solver to
reach for in unusual cases.

## Solvers

| Solver | Entry point | Completeness | Best for |
|--------|-------------|--------------|----------|
| **Backtracking + AC-3/GAC** | `getSolution()`, `getSolutions()` | Complete: finds a solution iff one exists; can enumerate all | Default. Sudoku, N-queens, magic squares, scheduling, almost everything. |
| **Min-Conflicts (local search)** | `solveWithMinConflicts()` | Incomplete: may give up via `'FAILURE'` even when solutions exist | Very large, lightly-constrained problems where you need *any* solution quickly. See [min-conflicts.md](min-conflicts.md). |

The two are independent — min-conflicts does not fall back to backtracking,
and backtracking does not use local search.

## The backtracking solver

The main solver is a depth-first search through variable assignments,
augmented with consistency propagation after each tentative assignment
and two ordering heuristics.

```
backtrack(assigned, unassigned):
    if unassigned is empty:                 # solution found
        return assigned
    var = MRV(unassigned)                   # pick variable
    for value in LCV(var, ...):             # order values
        try assigning var = value
        propagated = AC-3 + GAC on the affected domains
        if any domain is now empty:
            continue                        # this value fails; try the next
        result = backtrack(assigned ∪ {var:value}, ...)
        if result != FAILURE: return result
    return FAILURE
```

`getSolutions()` (Stream) uses the same loop but yields each complete
assignment instead of returning the first.

### MRV — Minimum Remaining Values

When choosing which variable to assign next, the solver picks the one with
the *fewest* remaining values in its domain. The rationale is "fail fast":
if a path is doomed, hitting a contradiction sooner means pruning a larger
subtree.

This is also why **pinning a variable to a single value is the most
effective optimization you can apply** — that variable is always picked
first, and its propagation through AC-3/GAC shrinks neighboring domains
before search even begins. (See the magic-square example in the README:
pinning `B2 = 5` drops solve time from ~100s to ~5s.)

### LCV — Least Constraining Value

Once a variable is chosen, MRV does not decide the *order* of values to
try. LCV orders the candidate values by how few options they remove from
neighboring variables — the value that "leaves the most room" is tried
first. This is "succeed fast": when a solution exists on the current path,
LCV tends to find it without backtracking.

LCV is best-effort; it is not a guarantee and it does add per-step
overhead, but on most problems the savings from fewer dead-end recursions
outweigh that.

### AC-3 — Arc Consistency (binary constraints)

For every binary constraint `C(X, Y)`, the solver maintains the invariant:
for every value `x` left in `X`'s domain, there is at least one `y` in `Y`'s
domain such that `C(x, y)` holds. Values that lack any supporting partner
are removed.

When a domain is reduced, every binary constraint whose head is the
reduced variable is requeued, so the change propagates until either:
- a fixed point is reached (all arcs consistent), or
- some domain becomes empty (the current assignment is impossible).

Binary constraints in `dart_csp` are stored in **both directions** —
`addConstraint(['A', 'B'], pred)` registers `(A → B, pred)` and
`(B → A, λ(b,a). pred(a,b))`. This is why `constraintCount` for one such
call is 2, and why AC-3 can propagate symmetrically. (See
`test/builtin_and_parser_test.dart` for the relevant test.)

### GAC — Generalized Arc Consistency (n-ary constraints)

For constraints over 3 or more variables, AC-3's "find one supporting
partner" check generalizes to "find one supporting *tuple* of the other
variables". The current implementation does this via a small recursive DFS
inside `_hasSupport` (see `lib/src/solver.dart`).

GAC complexity grows with the product of the other variables' domain
sizes, so it can be the dominant cost on problems with wide-domain n-ary
constraints. If profiling points here, look for ways to:
- pin or shrink any one variable in the constraint (most effective),
- replace a single high-arity constraint with several lower-arity ones,
- or use binary constraints instead where the relation permits.

A pre-built `naryIndex` (variable → constraints) keeps requeue cheap.

## Solver invocation lifecycle

1. `Problem.getSolution()` builds a `CspProblem` snapshot.
2. `CSP.solve(...)` runs `_validateProblem`, builds the n-ary index, and
   calls `_backtrack({}, copyOfDomains, csp)`.
3. The backtrack closure does MRV → LCV → tentative assign → AC-3 →
   GAC → recurse, exactly as in the pseudocode above.
4. On success, the solver unwraps each variable's domain (always a
   single-element list at this point) into a plain `Map<String, dynamic>`.
5. On failure, the literal string `'FAILURE'` is returned. Check with
   `if (result is Map<String, dynamic>) { ... }` rather than truthiness.

## Async behavior

The recursive backtracker runs in a `Future`, but unconditionally
yields to the event loop on every ~100 decisions
(`_yieldEveryDecisions`). Min-conflicts yields on every ~200
iterations. These periodic yields are what let a wrapping
`Future.timeout(...)` actually fire on an otherwise CPU-bound solve.

For programmatic cancellation (deadline missed, user pressed cancel,
upstream future no longer wants the result), pass a
`CancellationToken`:

```dart
final token = CancellationToken();
Timer(Duration(seconds: 5), token.cancel);
final result = await p.getSolution(cancelToken: token);
// result == 'FAILURE' && token.isCancelled  →  cancelled
// result == 'FAILURE' && !token.isCancelled →  proven infeasible
// result is Map ...                         →  solution
```

The same `cancelToken:` parameter is accepted by every backtracking
entry point and the min-conflicts runner. The fast path (no token,
no visualization callback) is one integer compare per decision plus
the unconditional yield every ~100 decisions — under 1% of search
wall-clock on every benchmark.

For *parallel* execution (multiple solves at once on the same VM, or
a single solve that genuinely needs to run on a different OS thread),
the cooperative yield alone keeps a single solve responsive but
doesn't let two solves share a CPU. Use the worker-isolate runner
(`solveInIsolate`, `solveAllInIsolate`, `minimizeInIsolate`,
`maximizeInIsolate` in `lib/src/isolate_runner.dart`) when you need
true parallelism. The full cancellation / timeout / isolate story —
including when to pick each one — is in
[`cancellation.md`](cancellation.md).

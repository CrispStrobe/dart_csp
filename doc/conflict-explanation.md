# Conflict Explanation (Minimal Unsatisfiable Subsets)

When `Problem.getSolution` returns the literal `'FAILURE'`, the model
is infeasible — but the failure carries no information about *which*
constraints conflict. For a model with dozens of posted constraints
that's a debugging nightmare. The library's conflict-explanation pass
identifies a **minimal unsatisfiable subset (MUS)**: a subset of the
posted constraints that's still infeasible, and from which the removal
of any single constraint makes the residual subproblem satisfiable.

Call `Problem.findMinimalUnsatisfiableSubset()` (in the
`ConflictExplanation` extension) to get a MUS.

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
    print(ref);
  }
  // binary(a, b)
  // binary(b, c)
  // binary(a, c)
}
```

A 3-cycle has no 2-coloring; all three inequality edges are in the
MUS, and the redundant `a < b` is dropped. Dropping any one of the
three returned edges makes the residual problem satisfiable (it
becomes a 2-coloring of a path or a tree).

## TL;DR

| Question | Answer |
|---|---|
| How do I call it? | `await p.findMinimalUnsatisfiableSubset()`. Returns `List<ConstraintRef>?` — `null` if the problem is satisfiable, the MUS otherwise. |
| Is the MUS the *smallest* unsat subset? | No — it's *locally minimal* (no single deletion preserves infeasibility). The smallest MUS problem is NP-hard. |
| How expensive is it? | O(n) calls to `CSP.solve` where n is the number of user-posted constraints. Each solve runs ordinary AC-3 search from scratch. |
| Can I bound the work? | Yes — pass `cancelToken: CancellationToken`. Step 1 cancellation returns `null`; step 2 cancellation returns the current kept set (sound but possibly non-minimal). |
| What's the granularity? | Whatever was posted. A binary `addConstraint` shows up as one ref (forward + reverse paired). `addAllDifferent` is one ref. `addInverse` decomposes into n² binaries internally, each a separate ref. |
| What does the ref look like? | `ConstraintRef(id, kind, variables)`. Kind is one of `binary` / `predicate` / `allDifferent` / `linearEquals` / `linearLeq` / `linearGeq` / `regular` / `circuit` / `subcircuit` / `gcc` / `cumulative` / `clause` / `diffN`. |
| Is the API stable? | No — experimental. See [`STABILITY.md`](../STABILITY.md). |

## The algorithm

The pass implements **deletion-based MUS** (Bakker et al. 1993,
Junker 2001). It runs in two phases.

**Step 1 — confirm infeasibility.** Solve the full problem. If it
has a solution, return `null`. If the solve is aborted by the
cancellation token before completing, also return `null` (callers can
inspect `cancelToken.isCancelled` to disambiguate).

**Step 2 — deletion loop.** Initialize `keep` to the full set of
posted constraints. For each constraint `c` in posting order:

1. Tentatively remove `c` from `keep`.
2. Re-solve the subproblem with constraints `keep`.
3. If the residual is unsatisfiable, drop `c` permanently (it
   wasn't load-bearing).
4. If the residual is satisfiable, restore `c` (it was load-bearing
   for the unsat conclusion).

At loop end, `keep` is a MUS: every constraint in it is load-bearing
in the sense that removing *just that one* makes the residual
satisfiable. The set is not the smallest possible MUS — that's
NP-hard — but it is *locally* minimal under single-element deletion.

Forward + reverse directions of a single user-level binary
`addConstraint([v1, v2], pred)` call are added to the engine's
constraint list as two consecutive entries (`v1 → v2` and `v2 → v1`).
The MUS pass groups them into one `ConstraintRef` so the user sees
one logical binary constraint.

## When to use it

The pass is most useful when:

- A model returns `'FAILURE'` and you can't see why by reading the
  code.
- You're debugging a model that previously worked and just broke.
- A user-supplied problem (rosters, schedules, configurations) is
  reported infeasible and you need to surface *which* user
  requirements conflict.

It is overkill when:

- The model has fewer than ~5 constraints and you can read them.
- You already know the conflict and just want to localize it
  further — try just commenting out subsets manually.
- The model is expected to be infeasible (you're using `'FAILURE'`
  as a check, not as a debugging signal).

The pass is **not free**: each iteration solves the whole problem
from scratch, and the loop runs once per posted constraint. On a
500-constraint model where each solve takes 1 second, the MUS pass
takes ~8 minutes. Use `cancelToken:` to bound this.

## Granularity and decomposed helpers

ConstraintRef granularity matches what's stored after all helper
methods have run, not what the user-facing API call looks like.

| User-level call | MUS granularity |
|---|---|
| `addConstraint([v1, v2], pred)` | One `binary` ref for the pair. |
| `addConstraint([v1, v2, v3], pred)` | One `predicate` ref. |
| `addAllDifferent([v1, v2, v3])` | One `allDifferent` ref. |
| `addLinearEquals(...)` etc. | One `linearEquals` / `linearLeq` / `linearGeq` ref. |
| `addCircuit([v1, v2, v3, v4])` | One `circuit` ref. |
| `addCumulative(...)` | One `cumulative` ref. |
| `addClause(positive: [...], negative: [...])` | One `clause` ref. |
| `addDiffN(...)` | One `diffN` ref. |
| `addInverse(forward, inverse)` | n² `binary` refs (the helper decomposes). |
| `addLexChain([row1, row2, row3])` | (k-1) lex-leq refs (the helper decomposes pairwise). |
| `addSetVariable(...)`-related helpers | Multiple `predicate` / `clause` refs (the indicator decomposition). |

If MUS output points into a decomposed cluster, the cluster as a whole
is usually what the user wants to look at. A future iteration may add
per-`addX`-call labels so the MUS can group decomposed pieces back into
their originating helper.

## Cancellation semantics

Cancellation behavior depends on which step is interrupted.

**Step 1 (initial satisfiability check) cancelled.** Returns `null`.
The caller cannot tell from the return value alone whether the
problem was satisfiable or whether cancellation prevented the
algorithm from determining feasibility. Inspect
`cancelToken.isCancelled` after the call to distinguish:

```dart
final mus = await p.findMinimalUnsatisfiableSubset(cancelToken: token);
if (mus == null) {
  if (token.isCancelled) {
    // Couldn't determine feasibility within the budget.
  } else {
    // Problem is satisfiable.
  }
}
```

**Step 2 (deletion loop) cancelled.** Returns the current kept set.
This set is sound — every constraint in it is in the *current* kept
set because removing it would have made the residual satisfiable at
some earlier iteration. Constraints that haven't yet been tested are
still in the set and may or may not be load-bearing. The result is
therefore a *superset* of some MUS; it is unsat but possibly not
minimal.

## What's NOT shipped (open follow-ups)

The current pass is the smallest useful first cut. Several natural
extensions are on the roadmap but not yet implemented:

- **QuickXplain (Junker 2004).** Divide-and-conquer MUS in
  O(k log(n/k)) calls to `CSP.solve` where k is the MUS size, vs.
  the current pass's O(n). For models with hundreds of constraints
  and small MUS, this can be orders of magnitude faster.

- **Per-`addX`-call labels.** Currently each ref carries an
  auto-generated `b{i}` / `n{j}` id and a derived `kind`. Users
  cannot easily map back to which `addX` call they made (especially
  through decomposed helpers like `addInverse` or `addLexChain`). A
  future version may add an optional `label:` parameter on every
  `addX` method and surface it on the ref.

- **Explanation-aware propagators.** When a propagator prunes a
  value, the "cause" is the entire scope of the constraint. With
  per-prune explanations (a sub-cause subset of variables that
  actually justify the prune), the MUS pass could converge toward
  more refined explanations — for instance, on a sparse
  `allDifferent` over 20 variables, only the 3 or 4 variables
  actually pinned in the failure cluster need to appear in the
  explanation. This is also a building block for full LCG-style
  nogood learning.

- **`MaximalSatisfiableSubset` (MSS) companion.** Sometimes the
  user wants the *largest* satisfiable subset instead of the
  *smallest* infeasible one — e.g. "which user requirements *can*
  I satisfy together?". The current API surfaces only the MUS;
  computing the MSS directly takes a different algorithm
  (deletion-based MSS or the QuickXplain dual).

- **Multiple MUSes.** A model can have several distinct MUSes;
  this pass returns one. Enumerating all MUSes is a separate
  algorithm (MARCO is the standard reference). Useful when one
  MUS surfaces a "downstream" conflict and the user wants to see
  earlier-cause MUSes too.

## API surface

The `ConflictExplanation` extension exposes one method:

```dart
extension ConflictExplanation on Problem {
  Future<List<ConstraintRef>?> findMinimalUnsatisfiableSubset({
    CancellationToken? cancelToken,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  });
}
```

And one new public type:

```dart
class ConstraintRef {
  const ConstraintRef({
    required this.id,         // 'b0', 'b1', ..., 'n0', 'n1', ...
    required this.kind,       // 'binary' | 'allDifferent' | ...
    required this.variables,  // scope, in posting order
  });
  // Equality keyed by id; toString surfaces kind + variables.
}
```

There is **no** `CSP.findMinimalUnsatisfiableSubset(csp, ...)` static
counterpart. The MUS pass is `Problem`-only: the binary-pair
grouping (one ref per `addConstraint` call instead of two refs per
direction) needs the user-level posting information that the raw
`CspProblem` doesn't carry. If you have a `CspProblem` without an
owning `Problem`, the workaround is to rebuild a `Problem` and
re-post the constraints; MUS then operates on the rebuilt version.

See [`STABILITY.md`](../STABILITY.md) for stability classification —
the API is experimental; the algorithm and return shape may evolve.

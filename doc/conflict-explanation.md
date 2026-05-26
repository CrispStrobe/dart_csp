# Conflict Explanation (Minimal Unsatisfiable Subsets)

When `Problem.getSolution` returns the literal `'FAILURE'`, the model
is infeasible — but the failure carries no information about *which*
constraints conflict. For a model with dozens of posted constraints
that's a debugging nightmare. The library's conflict-explanation pass
identifies a **minimal unsatisfiable subset (MUS)**: a subset of the
posted constraints that's still infeasible, and from which the removal
of any single constraint makes the residual subproblem satisfiable.

Two algorithms are shipped, both in the `ConflictExplanation`
extension:

| Method | Algorithm | Complexity | Cancellation |
|---|---|---|---|
| `findMinimalUnsatisfiableSubset` | Deletion-based (Bakker et al. 1993 / Junker 2001) | O(n) calls to `CSP.solve` | Step-1 cancel → `null`; step-2 cancel → current kept set (sound, possibly non-minimal) |
| `findMinimalUnsatisfiableSubsetQuickXplain` | QuickXplain (Junker 2004) | O(k · log(n/k)) calls to `CSP.solve` (k = MUS size) | Any cancel → `null` (no sound mid-flight kept set) |

Both return `Future<List<ConstraintRef>?>` with `null` indicating
satisfiability and the same `ConstraintRef` granularity / id scheme.
They may surface *different* locally-minimal MUSes on the same
problem — both are valid (each constraint in the returned list is
load-bearing); the smallest possible MUS is NP-hard and is not the
contract of either method.

Default pick: `findMinimalUnsatisfiableSubset` for small models
(under ~50 constraints) where the O(n) factor is fine and the
mid-loop cancellation behavior is useful. Switch to
`findMinimalUnsatisfiableSubsetQuickXplain` when n is large and the
MUS is expected to be small (k ≪ n) — the log-factor savings on the
solve count can be an order of magnitude.

The `bench(explain)` section of `benchmark/benchmark.dart` confirms
the textbook crossover on a sweep of model sizes:

| Problem shape | k | n | deletion / QX ratio |
|---|---:|---:|---|
| singleton MUS + 10 redundants | 1 | 11 | 1.5× **for deletion** |
| singleton MUS + 200 redundants | 1 | 201 | 4.3× for QX |
| triangle MUS + 10 redundants | 3 | 13 | 3.6× for QX |
| triangle MUS + 200 redundants | 3 | 203 | 63× for QX |
| pigeonhole CNF 5-in-4 | 45 | 45 | 1.6× **for deletion** |

So: deletion wins by a small constant when n is tiny or when k ≈ n
(its O(n) cost matches QX with no recursion overhead); QX wins by
orders of magnitude on small-k-large-n. Run
`dart run benchmark/benchmark.dart` to see fresh numbers on your
machine.

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
| How do I call it? | `await p.findMinimalUnsatisfiableSubset()` (deletion-based) or `await p.findMinimalUnsatisfiableSubsetQuickXplain()` (divide-and-conquer). Both return `List<ConstraintRef>?` — `null` if the problem is satisfiable, the MUS otherwise. |
| Is the MUS the *smallest* unsat subset? | No — it's *locally minimal* (no single deletion preserves infeasibility). The smallest MUS problem is NP-hard. Different algorithms (or different orderings of the same algorithm) may surface different locally-minimal MUSes for the same problem. |
| How expensive is it? | Deletion: O(n) calls to `CSP.solve`. QuickXplain: O(k · log(n/k)) calls where k = MUS size. Each solve runs ordinary AC-3 search from scratch. |
| Which one should I call? | Deletion for small n (under ~50) or when the sound mid-loop cancel matters. QuickXplain for large n with expected-small k (orders-of-magnitude speedup). |
| Can I bound the work? | Yes — pass `cancelToken: CancellationToken`. Deletion: step-1 cancel returns `null`; step-2 cancel returns the current kept set (sound but possibly non-minimal). QuickXplain: any cancel returns `null`. |
| What's the granularity? | Whatever was posted. A binary `addConstraint` shows up as one ref (forward + reverse paired). `addAllDifferent` is one ref. `addInverse` decomposes into n² binaries internally, each a separate ref. |
| What does the ref look like? | `ConstraintRef(id, kind, variables)`. Kind is one of `binary` / `predicate` / `allDifferent` / `linearEquals` / `linearLeq` / `linearGeq` / `regular` / `circuit` / `subcircuit` / `gcc` / `cumulative` / `clause` / `diffN`. |
| Is the API stable? | No — experimental. See [`STABILITY.md`](../STABILITY.md). |

## The algorithms

Two algorithms are available, both producing locally-minimal MUSes
with identical `ConstraintRef` granularity. Different runs on the
same problem may surface different MUSes — every constraint in
either result is load-bearing (removing it makes the residual
satisfiable), but neither algorithm aims at the *smallest* possible
MUS (NP-hard in general).

### Deletion-based (default)

The default pass — `findMinimalUnsatisfiableSubset` — implements
**deletion-based MUS** (Bakker et al. 1993, Junker 2001). It runs in
two phases.

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

### QuickXplain (divide-and-conquer)

The sibling `findMinimalUnsatisfiableSubsetQuickXplain` implements
**QuickXplain** (Junker 2004 — *"QuickXPlain: Preferred Explanations
and Relaxations for Over-Constrained Problems"*, AAAI 2004). Same
step-1 satisfiability check, then a recursive procedure that splits
the candidate set in half and locates the MUS by alternating
recursion on each half.

Sketch of the inner recursion `qx(B, Δ, C)`:

- `B` = background (constraints already considered part of the MUS).
- `Δ` = the most recent addition to `B`, used to short-circuit.
- `C` = candidate constraints still to be tested.

```
qx(B, Δ, C):
  if Δ ≠ ∅ and B alone is unsat:  return ∅
  if |C| == 1:                    return C
  split C into halves C1, C2
  Δ2 = qx(B ∪ C1, C1, C2)
  Δ1 = qx(B ∪ Δ2, Δ2, C1)
  return Δ1 ∪ Δ2
```

The cleverness is that when `B ∪ C1` is already unsat, the recursion
on `C2` returns `∅` immediately — every constraint contributing to
the MUS is in `B ∪ C1`, so the right half doesn't need to be probed
constraint-by-constraint. The split-and-prune structure gives
**O(k · log(n / k))** calls to `CSP.solve` where n is the candidate
count and k is the MUS size. For models where k ≪ n this is
dramatically better than deletion's O(n).

For very small models or when k ≈ n, the O(n) deletion pass can
actually be marginally cheaper — QuickXplain pays a small constant-
factor overhead from the recursion. The two should be roughly
equivalent for k ≳ n / log n; QuickXplain pulls ahead as k shrinks
below that threshold.

**Cancellation.** Unlike the deletion pass, QuickXplain's recursion
does not maintain a kept-set invariant that would be sound mid-
flight: the returned subset is constructed by unioning recursive
results at the very end, and the intermediate `B` values are
candidate explanations under exploration, not committed members of
the MUS. Cancellation at any point — initial satisfiability check or
anywhere in the recursion — returns `null`. Callers should test
`cancelToken.isCancelled` to distinguish from a satisfiable problem,
exactly as for the deletion pass's step-1 cancel.

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
is usually what the user wants to look at. Use the `label:` parameter
described in the next section to group decomposed pieces back into
their originating helper call.

## Labeling constraints

Every primary `addX` helper on `Problem` accepts an optional
`label:` parameter (any `String`). When set, the label is attached to
the underlying constraint and surfaced on `ConstraintRef.label`. The
ref's `toString` includes the label as a tag between kind and scope:

```dart
final p = Problem();
p.addRangeVariable('w0', 0, 5);
p.addRangeVariable('w1', 0, 5);
p.addRangeVariable('w2', 0, 5);
p.addLinearLeq(['w0', 'w1', 'w2'], [1, 1, 1], 3, label: 'max-load');
p.addLinearGeq(['w0', 'w1', 'w2'], [1, 1, 1], 10, label: 'min-load');

final mus = await p.findMinimalUnsatisfiableSubset();
for (final ref in mus!) {
  print(ref);
  // linearLeq[max-load](w0, w1, w2)
  // linearGeq[min-load](w0, w1, w2)
}
```

Without labels you'd see `linearLeq(w0, w1, w2)` and have to map
`n0`/`n1` back to the originating helper call by hand. Labels are
strictly advisory: equality on `ConstraintRef` is still keyed by `id`
alone, so two constraints with the same label remain distinct refs
and the label has no effect on the algorithm.

### Propagation through decomposed helpers

Helpers that decompose into multiple primitives propagate the
caller's label to every decomposed piece, so a MUS that surfaces any
subset of a cluster shows them all with one consistent label:

| Helper | What gets labeled |
|---|---|
| `addInverse(forward, inverse, label: ...)` | All n² channelling binaries share the label. |
| `addLexChain([...], label: ...)` | Every pairwise lex-leq ref shares the label. |
| `addValuePrecedence(vars, values, label: ...)` | Every consecutive-value n-ary ref shares the label. |
| Binary `addAllEqual([a, b], label: ...)` | The single directed pair shares the label. |
| `addConstraint([a, b], pred, label: ...)` | Forward + reverse arcs share the label (and surface as one ref). |

When a single decomposed call produces dozens of refs (e.g.
`addInverse` over a 10-element permutation posts 100 binaries),
labelling makes the MUS output a fraction as noisy: one repeated
label string instead of 100 opaque `b{i}` ids.

### Set-variable and soft-constraint helpers

`addSetCardinality`, `addSetCardinalityRange`, `addSetCardinalityVar`,
`addRequiredInSet`, `addExcludedFromSet`, `addSubset`, `addSetEquals`,
`addSetDisjoint`, `addSetUnion`, `addSetIntersection`,
`addSetDifference`, and `addSoftConstraint` all accept `label:`. The
label propagates to every decomposed constraint they post — including
the per-element binary or ternary constraints that `addSetEquals`,
`addSubset`, `addSetUnion`, etc. emit, and the linear constraint
that the cardinality helpers emit. `addSetVariable` and
`addSetVariables` do not accept `label:` because they declare
indicator variables rather than posting constraints; pinning at
declaration time via `required:` / `excluded:` also doesn't go
through the constraint layer. To label individual pinned elements,
use `addRequiredInSet` / `addExcludedFromSet` with a label after
declaring the set variable. `declareSoft` similarly accepts no
label (it marks an existing bool var as soft rather than posting a
constraint); `addSoftConstraint` carries the label to the reified
n-ary constraint it generates.

## Cancellation semantics

Cancellation behavior differs between the two algorithms.

### Deletion-based pass

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

### QuickXplain

**Any cancellation point returns `null`.** The recursive structure
unions partial results only at the end; intermediate `B` values are
candidate explanations under exploration, not committed MUS members.
There is no sound "current kept set" to surface mid-flight, so any
cancel reduces to the same shape as a step-1 cancel for the
deletion pass: callers test `cancelToken.isCancelled` to distinguish
from a satisfiable problem. If you need the "sound but not necessarily
minimal" mid-loop semantics, use the deletion-based pass instead.

## What's NOT shipped (open follow-ups)

QuickXplain shipped — see the algorithm section above. Several
further extensions remain on the roadmap:

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

The `ConflictExplanation` extension exposes two methods:

```dart
extension ConflictExplanation on Problem {
  // Deletion-based MUS (Bakker et al. 1993, Junker 2001).
  // O(n) calls to CSP.solve. Mid-loop cancel returns the sound
  // (but possibly non-minimal) kept set.
  Future<List<ConstraintRef>?> findMinimalUnsatisfiableSubset({
    CancellationToken? cancelToken,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  });

  // QuickXplain (Junker 2004). O(k · log(n/k)) calls to CSP.solve
  // where k = MUS size. Any cancel returns null.
  Future<List<ConstraintRef>?> findMinimalUnsatisfiableSubsetQuickXplain({
    CancellationToken? cancelToken,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  });
}
```

And one public type:

```dart
class ConstraintRef {
  const ConstraintRef({
    required this.id,         // 'b0', 'b1', ..., 'n0', 'n1', ...
    required this.kind,       // 'binary' | 'allDifferent' | ...
    required this.variables,  // scope, in posting order
    this.label,               // user-supplied via addX(..., label: ...)
  });
  // Equality keyed by id (label is display-only). toString surfaces
  // 'kind[label](variables)' when label is non-null, otherwise
  // 'kind(variables)'.
}
```

Neither method has a `CSP.findMinimalUnsatisfiableSubset(csp, ...)`
static counterpart. Both passes are `Problem`-only: the binary-pair
grouping (one ref per `addConstraint` call instead of two refs per
direction) needs the user-level posting information that the raw
`CspProblem` doesn't carry. If you have a `CspProblem` without an
owning `Problem`, the workaround is to rebuild a `Problem` and
re-post the constraints; MUS then operates on the rebuilt version.

See [`STABILITY.md`](../STABILITY.md) for stability classification —
the API is experimental; the algorithm and return shape may evolve.

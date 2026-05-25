# Conflict-Directed Backjumping (CBJ)

Pass `enableConflictBackjumping: true` to any backtracking solver
entry point to swap chronological backtracking for **CBJ** (Prosser,
1993). After a decision variable runs out of candidate values, the
engine jumps directly to the *deepest earlier-assigned variable that
participated in some failure for the current variable*, rather than
returning to the immediate caller. Intermediate decisions that
couldn't have mattered to those failures are skipped.

CBJ is **sound and complete**: it returns the same solutions as
plain backtracking on every input. Only the choice of backtrack
target differs.

## TL;DR

| Question | Answer |
|---|---|
| How do I turn it on? | `enableConflictBackjumping: true` on every backtracking entry point (`getSolution`, `getSolutions`, `minimize`, `maximize`, `getSolutionWithRestarts`, `getSolutionWithDomWdeg`). Default `false`. |
| Does it find different solutions? | No — same solution set as plain BT, in possibly different order. |
| When does it pay off? | When the cause of a deep failure is genuinely far from the most recent decision (sparse constraint structure, weak propagation, intermediate "neutral" variables in the search order). |
| When doesn't it pay off? | When AC-3 + the specialized propagators catch infeasibility right at the cause-variable's assignment — most well-modelled CSPs. |
| How do I tell if it's actually doing something? | `lastStats.backjumps` (event count) and `lastStats.backjumpLevelsSkipped` (cumulative skip past chronological backtrack). |
| Does it compose with the other strategies? | Yes: forward checking, restarts, dom/wdeg, the integrated branch-and-bound. Just pass the flag alongside whatever other options you'd normally use. |
| Is the API stable? | No — experimental. See [`STABILITY.md`](../STABILITY.md). |

## The algorithm

CBJ maintains, for each decision variable `pick` being assigned at
depth `d`, a **conflict set** `conf[pick]` of earlier-assigned
variables (depth < d) that have participated in some failure for
`pick`. Each failure contributes its cause; the set accumulates
across all the candidate values tried for `pick`.

When all candidates for `pick` have failed:

- If `conf[pick]` is empty, the search returns "exhausted" to the
  caller (the same end-state as plain BT exhausting a subtree). At
  the root, an empty conflict means the problem is unsatisfiable.
- Otherwise the engine computes the target depth — the maximum depth
  in `conf[pick]` — and jumps directly there. The receiving frame
  merges `conf[pick] \ {target}` into *its* conflict set, then
  continues with its next candidate value. The intermediate frames
  between `pick` and `target` are popped without trying their
  remaining candidates (the key win versus chronological backtracking,
  which would have retried every one).

This generalizes the textbook BJ (Gaschnig 1979) by *accumulating*
the conflict information across failed candidate values rather than
resetting it per try. The result is that an earlier failure
discovered at value `v1` of `pick` can still drive the jump after
later values `v2, v3, ...` also fail; CBJ doesn't forget.

### The conflict-cause approximation

The "true" cause of a propagation failure is the minimal set of
earlier assignments whose values determined the failure. dart_csp
computes a **tight per-revision approximation** by tagging every
trail entry with the constraint that caused the domain mutation
(`_TrailEntry.cause`), then walking back through the chain of
revisions that led to the wipeout.

The algorithm: for each trail entry produced since `mark` (i.e.
since the current candidate was committed), inspect its `cause`
constraint:

- **Binary cause `(X, Y, pred)`** — only `X` (the head) contributed.
  `_reviseBinary` reduces `arc.tail` based on `arc.head`'s current
  domain, so `head` is the precise contributor.
- **N-ary cause `c`** — every other variable in `c.vars` contributed
  (the specialized propagators and the generic GAC support search
  inspect all free variables to filter the touched one).

If a contributor is *earlier-assigned* (depth `< ` the current
decision's depth), it goes straight into the conflict set. If a
contributor is the current pick or a within-frame intermediate, the
walk continues: it follows that variable back to its most-recent
*reducing* trail entry (skipping decision-site `cause: null`
entries) and processes that entry's cause in turn. This is what
keeps the chain of justifications intact when the wipeout's
immediate cause is, say, the current pick — the walk traces the
pick's value back to whatever earlier propagation forced its
domain to singleton.

The result is still an **approximation** rather than the true
minimal cause:

- Sound — every variable returned was assigned earlier and
  participated in at least one revision that touched the chain
  leading to the wipeout.
- May over-approximate via n-ary constraints (the GAC support
  search consults every free variable, so they all become
  contributors — even those whose specific value didn't matter).
- Over-approximation only weakens jump distance, never correctness.
  CBJ enumerates the same solution set as plain backtracking on
  every input.

The cost is one walk of the trail entries since the mark plus, for
each chain link, a backwards scan to find the most recent reducing
entry for the variable. Both are bounded by the trail length and
amortize cheaply against the cost of a single wasted candidate
retry.

### The recursive structure

`_searchOneCbj` returns a sealed `_SearchResult`:

```dart
sealed class _SearchResult {}
class _Solution extends _SearchResult { final Map<String, dynamic> assignment; }
class _Exhausted extends _SearchResult {}
class _Backjump extends _SearchResult {
  final int targetDepth;
  final Set<String> conflict;
}
```

The caller switches on the return:

- `_Solution`: propagate up (we found a satisfying assignment).
- `_Exhausted`: try the next candidate (no jump info; we ran out of
  options without recording a cause).
- `_Backjump(target, conflict)`:
  - if `target < my depth` → roll back our work and re-return the
    same `_Backjump` signal so the jump propagates further up;
  - if `target == my depth` → merge `conflict` into our own `conf`
    set and continue with the next candidate.

The streaming (`_searchAllCbj`) and optimization (`_searchOptimalCbj`)
variants can't return a value (one is an async generator, the other
is `Future<void>`), so they convey backjump signals through
engine-level `_pendingBackjumpDepth` / `_pendingBackjumpConflict`
slots that the parent frame checks after the recursive call
returns. The semantics are otherwise identical.

## Reading the stats

CBJ adds two `SolverStats` fields:

- **`backjumps`** — number of conflict-driven returns up the search
  stack, one per "all candidates exhausted at a depth with a
  non-empty conflict set" event. A single chronological-backtrack-
  equivalent return (target depth `= my depth - 1`) still counts as
  one backjump. Always `0` when CBJ is off; always `0` for local
  search.
- **`backjumpLevelsSkipped`** — cumulative count of decision levels
  skipped *past* chronological backtrack — i.e. the sum, over every
  backjump, of `(my depth - target depth - 1)`. A chronological-
  equivalent return contributes `0`; a backjump skipping one
  intermediate decision contributes `1`. Always `0` when CBJ is
  off.

The interesting metric for CBJ engagement is the ratio
`backjumpLevelsSkipped / backjumps`. Zero means CBJ is firing but
the topology only allows chronological-equivalent jumps. Non-zero
means CBJ is actually saving subtree exploration on this instance.

## When CBJ pays off (and when it doesn't)

CBJ's value comes entirely from *skipping subtrees that plain BT
would have explored*. Three conditions matter:

1. **Propagation must be weak enough that failures surface deep in
   the search tree.** Strong propagation (AC-3 with Régin's
   all-different, the bounds-consistency linear propagator, Hopcroft-
   Karp matching for GCC, etc.) often catches infeasibility right at
   the cause-variable's assignment, giving CBJ nothing to do.
2. **There must be "neutral" decisions between the cause and the
   failure** — intermediate variables in the search order that don't
   participate in the failing constraint. Without them, the
   conflict-set jump degenerates to chronological backtrack.
3. **The same conflict must recur over multiple failed candidate
   values.** A single isolated failure doesn't benefit from CBJ
   compared to BT; the saving comes from re-using the conflict info
   across multiple attempts.

These conditions are common in **hand-modelled CSPs with sparse
constraint graphs**, in **academic benchmarks where pathological
instances are deliberately chosen**, and in **problems where you
deliberately use weaker propagation** (e.g. `consistency:
ConsistencyLevel.forwardChecking`). They are less common in
**production CSPs that use the library's dedicated globals** — those
globals propagate aggressively enough that CBJ rarely fires.

The cost when CBJ doesn't help is small: one extra map insertion
per decision (`_assignedAtDepth[pick] = depth`), one trail walk
per propagation failure (already O(trail-since-mark)), and a small
set per decision frame. On problems with strong propagation,
`backjumps == 0` and the per-decision overhead is well under the
random noise of search wall-clock.

If you're not sure whether CBJ is worth turning on for your problem,
solve once with the flag off and once with it on, and compare
`backjumps`, `backjumpLevelsSkipped`, and wall-clock. The pigeonhole
test in `test/cbj_test.dart` is a small worked example where the
flag has measurable effect.

## Composition with other search modes

CBJ flips the *return-edge semantics* of the search tree without
touching the *forward-edge semantics* (variable picking, value
ordering, propagation), so it composes cleanly with every other
strategy in the library:

- **Consistency level** — `enableConflictBackjumping: true` with
  `consistency: ConsistencyLevel.forwardChecking` is the most useful
  combination. FC leaves failures for deeper search levels to
  discover, exactly the regime CBJ exploits.
- **Restarts** — each restart attempt runs an independent CBJ
  search; the conflict-set state is per-engine and resets on each
  restart. Composes with Luby-scheduled randomization.
- **dom/wdeg** — CBJ uses the variable picked by whichever heuristic
  is active. The dom/wdeg weight-bump on failed constraints is
  independent of the backjump target computation; both happen.
- **Optimization** — `minimize` and `maximize` (the integrated
  branch-and-bound) support CBJ via `_searchOptimalCbj`. The
  objective-bound-tightening short-circuit (`_optProven`) and the
  pre-existing-empty-domain guard at each recursion entry are both
  preserved.

The flag is rejected by `solveWithMinConflicts` simply because that
solver doesn't use backtracking at all — it's local search; CBJ has
no surface to attach to. (The parameter isn't on
`solveWithMinConflicts` at all; the type system prevents the
mistake.)

## What's not implemented

The first cut focuses on getting the backjump-and-conflict-merge
right; several research extensions are left as follow-ups:

- **Minimal-cause conflict analysis.** The current per-revision
  approximation is still pessimistic for n-ary constraints (it
  treats every other variable in scope as a contributor, even when
  only some specific values mattered). True minimal-cause analysis
  would track per-value support attribution inside each
  propagator's revise step, paying more memory and CPU for tighter
  jumps. Worth doing if a benchmark surfaces where current
  `backjumpLevelsSkipped` is visibly lower than the topology
  should allow.
- **Nogood recording / LCG (Lazy Clause Generation).** CDCL-style
  learning records the discovered conflict as a new clause and adds
  it to the constraint set, so future search avoids re-deriving the
  same conflict. This is a substantially larger project: it needs
  efficient clause storage, watch lists per learned clause,
  forgetting strategies, and a way to interact with non-binary
  constraints. The current `_ClausePropagator` machinery is the
  natural home for the storage side but nogood learning per se is
  not yet implemented.
- **CBJ on local search.** Min-conflicts has no backtracking, so the
  flag is meaningless there and is simply not exposed on the
  `solveWithMinConflicts` API.

## See also

- The README's [Conflict-Directed Backjumping (CBJ)](../README.md#conflict-directed-backjumping-cbj)
  section is the user-facing quick reference.
- [`STABILITY.md`](../STABILITY.md) classifies the
  `enableConflictBackjumping:` parameter and the two new
  `SolverStats` fields as experimental.
- [`doc/algorithms.md`](algorithms.md) covers the rest of the solver
  pipeline — MRV, LCV, AC-3, GAC, the cooperative-yield contract.
  CBJ is a return-edge variant of the backtracking loop documented
  there; everything else stays the same.
- [`test/cbj_test.dart`](../test/cbj_test.dart) for the canonical
  examples (the pigeonhole-via-pairwise instance is the smallest
  problem that visibly exercises the flag).

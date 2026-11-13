# Propagation performance checkpoints

These changes preserve constraint semantics and explanation validity. Workload
measurements state their baseline and scope; a faster fixture is not evidence
that every problem became faster.

## Retained allDifferent matching

Each engine retains one allDifferent propagator per constraint. Stable value IDs,
adjacency rows, matching arrays, breadth-first queue/distance storage and
forward/reverse residual-graph row buffers survive propagation calls. Domain
contraction removes invalid matched pairs before repairing the matching. Domain
expansion during rollback preserves existing valid pairs; lazily discovered
values extend the index. Different overlapping globals own separate state.

Strongly connected components and free-value reachability are computed from
current domains. Explanation objects remain local to the propagation that
created them. The previous Hall/pinned-owner explanation forms are preserved.
Retaining a matching does not retain a deduction under invalid assumptions.

### Exact fixed points and reusable graph traversal

allDifferent and GCC retain the exact immutable domain objects after a complete
successful propagation. If a requeued invocation sees those same objects, its
domains are already at the propagator's fixed point, so graph construction,
SCC analysis and filtering can be skipped. A different restored domain or a
change from an overlapping constraint forces normal reanalysis. A failed or
interrupted pass never establishes a new fixed point. Reasons remain local;
this cache stores no learned deductions or explanation snapshots.

SCC and free-value traversal reuse O(nodes) arrays and parallel integer stacks.
This removes per-edge DFS record allocation. Each propagator owns its workspace,
and an interrupted cache is discarded by the existing rollback path.

Three additive work counters distinguish these effects:

- `matchingSccPasses`: actual graph analyses across allDifferent and GCC.
- `matchingWorkspaceGrowths`: increases in retained traversal capacity.
- `matchingFixedPointSkips`: complete propagator invocations avoided at an
  identical known fixed point.

Eight focused regressions cover pruning fixed points, zero workspace growth
across restored queries, overlapping globals, interruption during SCC work and
counter serialization/restart aggregation. The existing complete enumeration,
LCG explanation and cancellation suites remain the correctness oracles.

`test/persistent_matching_test.dart` adds repeated conflict/restoration checks,
overlapping globals and 320 small edit queries against an independent complete
enumeration. The focused suite of 51 tests also covers existing Hall explanations
and varied Sudoku decision orders.

### Measured workload

`benchmark/matching.dart` performs 12 edits per batch, fixing half the variables
of an allDifferent model to rotating values. Two warmup batches precede seven
measured batches. Every result is independently checked for uniqueness and
assumption satisfaction. Run the same program at both commits to compare.
`--samples=25 --warmups=5` selects a larger bounded comparison. The harness
reports nearest-rank p95 and maximum separately, plus work from an additional
untimed batch. With the default seven samples p95 equals the maximum.

The baseline was `bbb1717`; the changed path retains matching state. One native
Dart 3.14.0 Linux x64 container run measured:

| Variables / values | Before median / p95 | Retained median / p95 |
|---|---:|---:|
| 32 / 36 | 22.444 / 24.822 ms | 15.249 / 21.617 ms |
| 64 / 68 | 93.577 / 125.556 ms | 49.837 / 57.485 ms |

These are local before/after batch measurements with unpinned hardware. They
measure repeated allDifferent edits through prepared sessions; they are not a
universal solver multiplier or a comparison with a different CAD solver.

## Compact capacitated GCC

GCC now uses one node per variable, one per distinct value and one sink.
Capacities live on value/sink relations; values are not duplicated once per
permitted occurrence. A retained upper-feasible assignment is repaired after
domain changes, then alternating paths repair lower deficits. Residual SCC
filtering enforces both lower and upper occurrence bounds. Unlisted values keep
their documented unrestricted counts.

The graph uses O(n+d) nodes and O(E+d) arcs, where E is the number of current
variable/value memberships. This removes capacity-copy multiplication; it still
enumerates distinct domain values. It does not make a billion-value GCC graph
constant-sized. Lower-bound deductions use conservative entry-domain reasons;
upper-capacity cut/pinned-owner explanations retain their existing forms.

`SolverStats.gccMaxFlowNodes`, `gccMaxFlowEdges`, `gccMaxTotalCapacity`,
`gccAugmentations` and `gccPropagations` expose work. A 64-variable/eight-value
fixture with huge upper bounds uses 73 nodes and at most 528 residual arcs,
regardless of the numerical upper-bound magnitudes.

Eighty seeded small models match independently enumerated full solution sets.
Every declared variable/value edge is probed after root restoration with zero
decision budget to compare propagation with oracle support. Tests include
competing/missing minima, lower-only deductions and LCG verdict parity.

The bounded `benchmark/gcc.dart` uses 12 edits per batch, two warmups and seven
measured batches. Same-program before/after native measurements were:

| Variables / values | Copy graph median / p95 | Compact graph median / p95 |
|---|---:|---:|
| 32 / 8 | 41.381 / 63.447 ms | 19.568 / 32.390 ms |
| 64 / 8 | 227.220 / 243.308 ms | 43.449 / 59.231 ms |

Hardware was unpinned. The 64-variable benchmark graph reports 73 nodes and 520
arcs. These measurements apply to the stated repeated-edit fixture.

## Reverse clause watches and learning work

Clauses now subscribe through a reverse watched-variable index separate from
ordinary n-ary adjacency. Watch moves update subscriptions. Uninitialized,
imported and expansion-invalidated clauses remain pending until propagated;
an early conflict cannot discard initialization work. Ordinary watch states
survive rollback, while fragile unit/conflict states receive targeted repair.
Forgetting removes all subscriptions and usefulness metadata.

Ordered reverse buckets preserve the prior constraint-registration and initial
seed-traversal order. This matters to heuristic behavior: the unchanged random
SAT restart fixture regressed during development when that order changed and
passed again after order preservation. Bucket updates are logarithmic; normal
traversal touches only subscribed clauses.

A structural test attaches 512 clauses to a non-watched variable. Changing it
after preparation produces zero clause subscription visits, enqueues,
propagator calls and literal checks. Tests also cover complete Boolean/integer
oracles, watch motion, repeated assumption rollback, forced forgetting and
imports outside the current seed scope.

New `SolverStats` fields record clause visits/checks/moves/repairs, actual units,
removed values, conflicts, learned uses and unused forgotten clauses. First-UIP
instrumentation records calls, time, trail entries, expanded reasons/literals,
resolution steps and learned literals. The optional `AnalysisWork` argument
preserves analysis output, verified by exact parity. The conservative learning,
forgetting and backjump policies remain unchanged; counters make future policy
experiments measurable.

## Binary supports and lazy value ordering

Each binary arc retains bounded positive support witnesses. A witness is reused
only while it is still in the supporting domain. Stale witnesses may become
valid after rollback; absence of support is never cached. The cache holds at
most 4,096 target values per arc and requires immutable values/pure predicates,
as compiled sessions already do.

Five repeated 64-value queries with a still-valid common witness require fewer
than 20 predicate calls, including original-semantic result validation, instead
of at least 64 support checks per query. Sixty independently generated binary
relations are checked by full enumeration and 480 restored-domain queries.

LCV skips assigned/uninformative neighbors and skips sorting equal scores.
Informed choices use a stable min-heap: building it is O(d), `.first` does not
sort all alternatives, and DFS extracts later choices when needed. Restart
randomization uses lazy Fisher-Yates selection for compact intervals, including
cardinalities above 2^32. The first random choice no longer materializes the
whole range. Scoring still evaluates relevant generic predicates; arbitrary
black-box constraints do not acquire algebraic bounds automatically.

## Swept cumulative scheduling

Cumulative time-table propagation now sorts compulsory-part endpoint events
into constant-load segments. At most `2*n - 1` segments replace one map entry
per occupied time tick. A segment `[a,b)` that overloads a task of duration `d`
forbids integer starts `[a-d+1,b-1]`; the task's own compulsory contribution is
removed before computing that overload. Adjacent half-open tasks may touch.
Profile storage and traversal depend on task count rather than numerical
duration. Energetic reasoning still has its existing cubic task-count bound.

Explicit domains and compact ranges with at most 4,096 values retain exact
time-table filtering. Larger compact ranges contract only their lower and upper
bounds, preserving sparse exclusions without materializing large interior
gaps. Unsupported interior starts remain in this safe superset until another
bound or a decision exposes them. This can propagate less strongly than full
enumeration; it does not remove any valid schedule. Singleton schedules are
still checked. LCG explains large bound removals with the contributing tasks'
compulsory bounds and the previous domain context, without enumerating removed
starts. Zero-duration or zero-demand tasks keep their unconstrained values;
active tasks enforce integer start semantics.

Arithmetic has an explicit portable limit. Active starts, durations, demands,
capacity, endpoint/forbidden-bound calculations, horizon differences and summed
demands must fit the exact-integer envelope `[-(2^53-1), 2^53-1]`. If energetic
reasoning is active, its maximum relevant capacity-window energy and aggregate
task energy must fit too. Preflight checks use machine integers on ordinary
inputs and exact `BigInt` checks only for large products. Values outside this
conservative envelope raise `UnsupportedError`, including nonfinite values;
they are never treated as infeasible or silently wrapped/rounded. This policy
is shared by the builder predicate and compiled validator across VM, JS and
Wasm. Rescale units or shrink the horizon to fit. Disabling energetic reasoning
is sufficient only when time-table arithmetic fits and its energy products
are the unsupported part. No arbitrary-precision scheduling backend is claimed.

`test/cumulative_sweep_test.dart` checks independent small schedule oracles,
billion-unit durations/ranges, compact interior assumptions and rollback,
noninteger/inactive task semantics, arithmetic boundaries, and deterministic
cancellation inside profile work. Existing energetic and LCG explanation
oracles remain. `benchmark/cumulative.dart` supplies identical before/after
cold fixed schedules, compact-range solves and twelve-edit prepared batches.
The default bounded durations let the old implementation finish; its
`--durations=1000000000` scaling option is for the swept implementation only.

## Cooperative propagation budgets

Long binary/LCV and generic n-ary support loops, plus allDifferent/GCC adjacency,
augmenting-path, residual-graph, explanation-cut, reachability and SCC passes,
poll cancellation and query deadlines.
Cumulative bounds/profile/filter/energy/reason work now polls the same budget.
Matching loops amortize the callback over 256 work ticks. A stop is distinct
from a contradiction: it clears a partially mutated matching/flow cache and
allows the usual domain-trail rollback. Prepared session roots remain reusable.
Neither recursive nor iterative LCG analyzes or learns from an interruption.

Seven deterministic regressions interrupt cold root construction and a prepared
query, retry different assignments after rollback, and verify both LCG search
engines retain zero false conflicts/learned clauses. The cold GCC case stops
inside adjacency construction, before the residual graph is built; checking
only between propagators would miss it. Generic support search also stops inside
one long task. Seventeen control-flow regressions cover plain/CBJ first/all/
optimal search, recursive LCG, stream-consumer cancellation and lazy SAC probes.
An interrupted probe never becomes evidence for removing an untested value;
unwinding a stopped child does not manufacture backtracks or conflict sets.

Enumeration permits only one solution awaiting public delivery acknowledgement.
This prevents JavaScript async-generator relays from exploring another leaf
before the consumer can pause or cancel. The acknowledgement is released at
the public yield site, including early subscription cancellation, before inner
stream teardown. Postprocessing uses a synchronous stream transformation.
There is no per-solution timer. Cross-runtime tests cover `take(1)`, consumer
break/errors, transformation errors, subscription cancellation and pause/resume.

These checks are cooperative. Polling inside synchronous work does not run
same-isolate timer callbacks. Explicit session deadlines check elapsed time,
while timer-driven cancellation awaits an event-loop yield. A callback that
never returns still requires isolate/worker execution for hard preemption.
There is no universal wall-clock response bound for arbitrary user code.

## Final complete-implementation sample

The final sequential sample at `689c38b` includes the later validation,
compact-range and cancellation changes. At 64 variables the allDifferent
12-edit batch measures 53.594 ms median / 147.033 ms p95; the GCC 12-edit batch
measures 15.235 / 23.317 ms with 73 flow nodes and 520 arcs. Matching tails remain
uneven. These additional samples do not replace or silently re-pair the earlier
before/after measurements. See [the validation record](performance-cad-validation.md)
and `benchmark/results/2026-11-13-final.json` for the complete scope and output.

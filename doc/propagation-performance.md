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

Strongly connected components and free-value reachability are recomputed from
current domains. Explanation objects remain local to the propagation that
created them. The previous Hall/pinned-owner explanation forms are preserved.
Retaining a matching does not retain a deduction under invalid assumptions.

`test/persistent_matching_test.dart` adds repeated conflict/restoration checks,
overlapping globals and 320 small edit queries against an independent complete
enumeration. The focused suite of 51 tests also covers existing Hall explanations
and varied Sudoku decision orders.

### Measured workload

`benchmark/matching.dart` performs 12 edits per batch, fixing half the variables
of an allDifferent model to rotating values. Two warmup batches precede seven
measured batches. Every result is independently checked for uniqueness and
assumption satisfaction. Run the same program at both commits to compare.

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

Long binary/LCV loops poll cancellation and query deadlines. Cancellation cannot
be turned into a learned conflict. These checks are cooperative; a user callback
that never returns still requires worker isolation.

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

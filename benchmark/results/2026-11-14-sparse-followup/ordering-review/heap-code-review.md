# Independent indexed-heap source review — 2026-11-14

Reviewed the imported `lib/src/geometry/sparse_ldlt.dart` delta from main
`c2603a852229897d325a8890ed418319ee8c3572` and the new
`test/geometry_sparse_ordering_test.dart`. Reviewed solver-file SHA-256:
`f3614a37f7caa3adfdea79b5f1654c0b7876a1d4f09b0c4a34ea8d6a84a45620`.
No repository file was modified and no Dart process/compiler was executed by
this review.

## Finding

No concrete correctness blocker was found in the heap algorithm, symbolic-work
accounting, cache interaction or cancellation flow. The heap preserves exact
minimum current degree with original-column index as the tie breaker. For a
pattern admitted by both revisions, unchanged pivot order also preserves the
sorted neighbor sequence, factor layout and numeric update order.

The change legitimately alters eligibility under tight symbolic-work caps: a
large low-fill pattern can now fit a cap that previously rejected its quadratic
scan. That is an intended selected-work optimization, not evidence that the
factor/numeric/assembly caps were loosened. Those caps and the numeric routines
are unchanged. Performance and crossover at 256 columns still require the
planned timings.

## Invariants checked

- Initialization assigns one entry per column and bottom-up heapifies keys
  `(degree, original index)`. Position maps are updated for both entries on
  every swap. Removal marks the dead column `-1` and repairs the replacement.
- Every surviving graph neighbor is live: prior pivot removals delete it from
  all neighbor sets. Thus `update` is not called for a removed heap entry.
- Only pivot neighbors can change degree during its removal and fill. They are
  updated once after all fill is complete. Comparisons read stored degree
  snapshots rather than partially changed graph lengths, so every individual
  decrease/increase-key operation starts from a valid heap. A degree decrease
  needs only upward repair; an increase needs only downward repair.
- Sorted neighbor lists remain identical for identical pivots, preserving the
  factor pattern and floating-point operation order. Unchanged graph members
  keep their stored degree throughout each step.
- Each `take` checks remaining allowance before charging. All callers provide
  nonnegative sizes. Heap initialization, removals, key updates and comparisons
  are charged; every swap has a charged comparison. The work counter therefore
  bounds selected structural operations, while it remains neither a byte limit
  nor a wall-time deadline.
- A heap limit exception is caught only inside `_patternFor`, turning the
  bounded structural failure into the existing negative cache keyed by shape
  and all effective caps. Positive caches still recheck recorded work against
  the current caps. Numeric/factor/assembly limits are checked as before.
- `_SparseLdltCancelled` is distinct from the new limit exception and propagates
  past `_patternFor` before cache assignment. Cancellation during a partially
  built heap therefore cannot cache an incomplete pattern. Heap/work buffers
  are local to each build, retaining reentrancy isolation.
- Below 256 columns, the live-list scan and its work accounting remain intact.
  The existing exact 34-unit four-column test and 200-column cache test are
  still meaningful. The new tests cover large subquadratic admission, a
  fill/tie-sensitive numeric cap, positive/negative cache caps and cancellation.

## Independent graph-model check

`check_ordering_model.py` compared a faithful heap translation against an
independent full-scan oracle for **1,092 graphs**: all 1,024 undirected graphs on
five vertices, 64 seeded varied-density graphs at 6/9/16/32 vertices, and
256-column empty/chain/star/cycle boundaries. Every pivot order, ordered
neighbor list, factor-entry count and numeric-work count matched. Heap and
position-map invariants were checked after every individual key update.

The lightweight Python check ran on CPU 1, separate from the parent's pinned
CPU-0 QR screen. Its result is `ordering-model-check.json`. This is algorithm
review evidence, not execution coverage of Dart and not a timing result. The
source agent's reported 57 focused native passes are separate evidence; this
review did not rerun those tests.

## Remaining validation boundary

Retain the exact candidate source before timing. Fresh source qualification and
native/portable gates are required for the changed bytes. Paired adapter audits
should verify exact coordinates/work wherever both versions retain the same
backend eligibility. Report any intentional cap-driven change separately. The
configuration guide must describe the heap-selected work above 255 columns
instead of promising `n(n+1)/2` candidate visits for every large pattern.

# Independent packed sparse storage code review

## Scope and conclusion

Reviewed the production diff from baseline
`d43a8b0fca74c6bc893d68ca6ec8190e74b423c9` to the packed-storage candidate in
`lib/src/geometry/sparse_ldlt.dart`. The reviewed candidate file has SHA-256
`21e868f8b5d531bfe4986cace0e18ce0eb686881e328ca6241ad3df2937d32cd`.
No correctness or resource-accounting defect was found in this source change.
This review is separate from compiled tests and elapsed-time measurement; it
does not establish a speedup or a measured reduction in total allocated bytes.

## Addressing and storage invariants

Each factor column retains its existing sorted row list. Its diagonal is first,
and every other row belongs to a later pivot. `columnOffsets` is the prefix sum
of those row-list lengths, with a final sentinel. The existing `entries` count
equals their total: one diagonal per column plus every distinct original/fill
edge, charged when that edge is first inserted. Removing an eliminated vertex
does not permit its edges to be inserted again.

Assembly and Schur-update maps now store absolute positions `start + index`.
All their consumers were converted to address the single numeric factor buffer
directly. Diagonal, normalization and triangular-solve accesses consistently
use the same start offset. A Schur target belongs to a later column, so source
factor entries cannot alias its target segment. A column with no off-diagonal
entries still owns its single diagonal slot. Zero-column systems return from
the zero-right-hand-side path before numeric factorization.

The numeric buffer still contains exactly `factorEntries` doubles and remains
bounded by `maxFactorEntries`. For a nonzero numeric attempt, the source now
allocates one typed factor buffer instead of one per column plus an outer list.
The cached shape adds an immutable integer-offset list of length `columns + 1`.
This is an allocation-count observation from source, not a total-memory or GC
measurement.

## Arithmetic, budgets and ownership

The diff preserves the nesting and iteration order of every assembly addition,
duplicate-column cross term, division, Schur update and triangular reduction.
All nonfinite and pivot checks are retained. The 40 textual `polling.check()` /
`polling.tick()` call sites remain in the same sequence; loop and branch review
also finds no changed cancellation cadence. Iteration accounting, symbolic
selection, factor-entry limits and numeric/assembly work limits are unchanged.

Only immutable structural offsets join the cached pattern. Factors, pivots,
right-hand sides and solve results remain local to each invocation. Nested
calls from cancellation callbacks cannot overwrite an outer numeric buffer.
Public mutable-CSR shape matching and numeric-value rereads retain their
existing behavior. No public API, backend selection threshold or convergence
criterion changes.

## Validation boundary

The focused regressions and native/portable gates are recorded separately in
the result evidence. Relevant existing tests cover duplicate CSR columns,
mutation, exact cap boundaries, cancellation, refinement, zero-column systems
and reentrancy. The new storage regressions target irregular column extents,
diagonal-only slots and repeated/nested solves. Retention requires the frozen
candidate's own completed checks and paired measurements; earlier passing
sources are not substituted for that evidence.

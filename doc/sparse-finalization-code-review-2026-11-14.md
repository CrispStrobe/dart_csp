# Sparse solver finalization: independent source review

## Scope and conclusion

Reviewed the production source and sparse regression tests at PR #9 checkpoint
`806b236726e70b856fc3ca4d1286936ccd340a3d`. Its library tree is
`eb20b0ea6dc251142e6109f04bb7fe768d967db1`, identical to measured source
`6cc191f`. The review covered [numeric.dart](../lib/src/geometry/numeric.dart),
[sparse_ldlt.dart](../lib/src/geometry/sparse_ldlt.dart), public exports, session
integration, and both sparse regression files. No `AGENTS.md` is present in the
repository tree.

No concrete correctness blocker or necessary production change was found.
This is a source review, not a claim that the reviewer reran the saved Dart
validation. Performance acceptance additionally depends on the complete paired
measurements, including adverse controls and structural-decline cases.

## Numerical behavior

- Assembly uses the supplied damping and diagonal without added pivot jitter.
  The full raw-row Cartesian product includes both duplicate diagonal cross
  terms, even for unsorted entries and cancellation.
- The factorization requires finite positive pivots. A successful factorization
  is followed by an equation-residual check using the original CSR Jacobian,
  independently of the assembled normal matrix. Up to two correction solves
  are allowed within the remaining iteration budget.
- The live-column linked list preserves deterministic minimum-degree ties in
  original-index order. Interior and first-live-column removal are correct;
  the exact-work star regression exercises both paths against an independent
  dense solution.
- Factor-entry accounting counts each original or fill edge once. The numeric
  update count is the sum of `degree * (degree + 1) / 2`; its limit check divides
  before multiplying.

## Budgets, cancellation and cache ownership

A structural refusal leaves the complete CG iteration allowance available.
Numeric direct attempts and refinement solves are charged before fallback, so
the combined direct/CG count cannot exceed the supplied allowance. Cancellation
is terminal. Polling covers symbolic analysis, assembly, factorization,
triangular solves, refinement and the final original-equation check.

Positive cache entries compare every current row offset and column index
against immutable snapshots and recheck the effective caps. Negative cache
entries also depend on the exact effective limits. Structural edits or changed
caps therefore reconsider eligibility; value-only changes reuse symbolic data
without reusing numeric factors.

Factors, right-hand sides, correction vectors and triangular-solve buffers are
call-local. Reentrant calls with stable caller-owned inputs do not share
writable numeric scratch. As the configuration guide states, caller-owned
inputs must remain stable during each synchronous invocation; changing them
between calls is supported.

## Evidence and limits

The existing tests cover independent dense-reference solutions, raw duplicates,
numeric and structural mutation, malformed current CSR arrays, all five caps,
positive and negative caches, exact work boundaries, callback reentry,
cancellation during final verification, shared direct/CG budgets, and a
257-coordinate default-session solve/edit/rejection/rollback sequence. No
additional implementation-mirroring tests were added by this review.

The default `32 * rawNNZ` cap is a work heuristic. Cold eligibility still uses
quadratic minimum-degree scanning, so a structural refusal can add latency.
The caps bound selected work counts and stored entries; they do not establish
elapsed-time or byte guarantees. The existing configuration guide accurately
states these limits. Integration must retain measured regressions and failure
outcomes alongside improvements and must distinguish Node portability from
real-browser coverage.

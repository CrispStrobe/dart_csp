# Independent review: CG reduction loop fusion

## Scope and result

Reviewed the proposed `lib/src/geometry/numeric.dart` change and the four tests
in `test/geometry_cg_test.dart` on 2026-11-14. **No correctness blocker found.**
The source change is eight inserted and four deleted lines, confined to four
dot-product reductions inside `SparseCgGeometrySolver.solve`.

Review checkout HEAD was `080e0fed0b80f9ecd88d66fc20061e468be4cce5` with the
candidate changes still uncommitted. Reviewed file SHA-256 values:

- `numeric.dart`:
  `bce973eaf51c3bac3f2aa1774366e15d88a26e96f97516402f7a30499e2f0a49`
- `geometry_cg_test.dart`:
  `d8608e1e3fbbfde615faf9ffa815eefada405b6c6a43824c1b37dd745225bc2b`

This is a source/test review. The reviewer ran no new tests, builds or
benchmarks. The implementing agent reported 83 focused tests and targeted
analysis passing; those execution results remain its separate evidence.

## Arithmetic and data dependencies

Each replaced `geometryDot` starts its accumulator at `0.0`, visits ascending
indices, and performs `sum += a[i] * b[i]`. The replacement uses the same
initial value, index order, multiplication operand order and addition sequence.
There is no changed parenthesization or reduction tree.

| Reduction | Earlier work now adjacent to its product | Dependency check |
|---|---|---|
| Initial `rz` | Validate preconditioner, assign `z[i]`, copy it to `p[i]` | `r` is unchanged; later indices cannot modify the current operands |
| `pap` | Add damping contribution to `ap[i]` | Product reads the updated typed-array element, as before; later elements are independent |
| Restart `rz` | Recompute `r[i]`, assign `z[i]` and `p[i]` | Accumulator is reset before the loop; each product reads both updated elements |
| `nextRz` | Assign `z[i]` | `r` stays fixed; every product uses the same stored value as the old following loop |

The expressions continue to read the `Float64List` elements after their
assignments. They do not substitute an unrounded expression for an array load.
All operand/output arrays involved in these fused loops are separately
allocated within the solve. Inputs `residual` and `diagonal` are read without
being written, so callers aliasing their own input buffers does not introduce a
new internal output alias.

The initial reduction can now accumulate infinity or NaN before a later
preconditioner entry fails validation. Such floating-point arithmetic does not
throw, that partial scalar is not exposed, and the same numerical-failure
result is returned. No finiteness check moved and none was added. Signed zero,
overflow and NaN propagation within a completed reduction retain the original
operand and accumulation order at the source level.

The existing true-residual verification and restart decision are unchanged.
This review supports arithmetic equivalence at the source level; execution
evidence is still required for the concrete Dart targets and compiler builds.

## Cancellation, mutation and ownership

No callback, Jacobian method call, stopping poll or observable result sits
inside any of the fused spans. The iteration-top poll stays before the matrix
products and the numerical-failure decision. Its cadence, completed-iteration
counter and retained iterate are unchanged. Zero-iteration budgets retain the
same original-system residual check and status precedence.

All new accumulators are local scalars. No scratch array is cached, returned
early in a new location, shared with a nested solve or retained by the solver.
Reentrant solves from `shouldStop` therefore preserve their existing ownership
boundaries. The reduction relocation creates no new opportunity for a callback
to observe a partially updated vector.

## Test quality and limits

The new correctness case independently assembles dense rows from mixed,
unsorted CSR input with a duplicate column, a structural zero and an empty row.
It checks a prescribed solution and the original damped normal equation with
three damping values. Its residual oracle uses its own dense matrix and norm
calculation, not the production multiplication or norm helpers.

The cancellation case exercises every iteration-top stopping position and
checks each retained iterate against the corresponding finite-budget solve.
The reentrant case nests a one-iteration solve at every poll and checks both
outer results and retained nested snapshots. The nonfinite-dot case verifies
that cancellation and a zero iteration budget still take precedence over the
later numerical-failure check. These are relevant behavioral tests rather than
copies of the new fused implementation.

One coverage limit: the new tests do not assert that a true-residual restart
actually occurs, so they should not be described as dedicated restart-branch
coverage. The restart reduction has the same simple independence and reduction
order proof as the other three sites; this is not a blocker for this patch.

## Recommendation

Proceed to the separately planned full validation and frozen comparison
against packed-source `4325386e689566a903309accd66aca3ced1159f7`. Preserve
per-process, order-stratified evidence and exact output/work comparisons.
Eliminating four extra vector traversals is a concrete implementation change;
it does not establish a universal performance improvement before measurement.

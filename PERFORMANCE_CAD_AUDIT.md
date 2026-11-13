# Latest-branch performance and 3D CAD audit

Date: 2026-11-13. Starting source: `1bb0d281654fb21eb11e7d01f25aa5fc294aafe9`.
Working branch: `audit/performance-cad-2026-11-13`.

## Baseline and preservation

The latest remote branch is `feat/performance-parametric-cad`, draft PR #3.
It includes all changes on main (`13f2b04`) and the merged web fixes in PRs #1
and #2. The earlier implementation and evidence remain intact. This audit
continues from PR #3 rather than rebuilding the older main branch.

The user authorized an audit, performance improvements, parametric 3D CAD
capability, and incremental remote checkpoints. Save this plan before source
changes; preserve each coherent implementation and its focused validation on
the remote audit branch. Do not merge or publish a release. Record failures and
unverified platform checks accurately.

## Work selected by the initial code audit

1. **Scheduling scalability and correctness.** Replace cumulative time-tick
   enumeration with an event-swept resource profile, use compact domain bounds,
   and respect cooperative cancellation/budgets. Verify against independent small
   scheduling oracles and large-duration/range regressions.
2. **Rectangle non-overlap soundness.** Check the interaction between documented
   numeric coordinates, integer-only propagation, solution acceptance, and
   compiled-session validation. Reproduce and repair skipped double-coordinate
   constraints without weakening the original predicate.
3. **Geometric numerical costs.** Investigate cold rank-factorization overhead,
   repeated Jacobian work and zero-dimensional automatic differentiation.
   Implement only changes with meaningful correctness coverage and measured or
   structural work reduction. Preserve numerical rank, physical tolerances,
   required/preference priorities, rejection and rollback.
4. **Useful 3D CAD capability.** Add rigid part placement/instances with immutable
   prototype geometry and display-mesh reuse where supported. Correct
   translation-sensitive mesh volume evaluation before relying on placed meshes.
   Keep semantic references, transactions and kernel capability limits explicit.
5. **Integrated evidence.** Run native analysis/tests and the bounded JS/Wasm
   corpus, add relevant cases to portability coverage, execute independent CAD
   examples and sequential paired benchmarks against the starting source.
   Report scope, medians, tails and limitations; no universal speedup claim.

## Acceptance boundaries

- Exact discrete solution sets must agree with independent small-model oracles.
- Large scheduling coordinates/durations must not imply time-axis enumeration.
- Numerical reuse must never hide changed inputs/options or invalid residuals.
- Pose-only CAD edits should reuse an unchanged prototype body and mesh.
- Invalid geometry/pose edits must keep the last committed state.
- A reference subset plus instances is not a general B-rep modeling kernel:
  booleans, fillets, shells and unsupported profiles remain separate work.
- Every reported benchmark states the actual source, harness, runtime and scope.

## Checkpoints

| Checkpoint | Status | Validation |
|---|---|---|
| Latest branches and PR inventory, continuation plan | Saved before implementation | Main + PR #1/#2 included; PR #3 head selected; no review comments at audit start |
| Cumulative scheduling | Pending | Independent oracle, large ranges/durations, budgets |
| Numeric rectangle soundness | Pending | Fractional-coordinate oracle and session parity |
| Geometric numerical performance | Pending | Rank/solve regression corpus and paired measurements |
| Stable mesh volume | Implemented; source checkpoint | 43 focused CAD tests pass, including four new translated-volume/orientation/compensation regressions; scoped analysis and formatting pass |
| 3D part instances | Pending | Independent transformed-coordinate checks, rollback, reuse |
| Integrated gates and report | Pending | Native + JS/Wasm, paired benchmark evidence |

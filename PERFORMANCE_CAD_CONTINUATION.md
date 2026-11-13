# Continued CSP/CAD performance work

Date: 2026-11-13. Starting source: `3b5c4c4373fa0f08d50ff5d5902714cd09cdfc92`
on `audit/performance-cad-2026-11-13`, draft PR #4. The user asked to continue
the completed audit and retain the existing authorization for incremental
remote checkpoints. Main and the earlier PR #3 source remain unchanged.

## Selected work

1. **Transactional numerical reuse.** Add a checked geometry-session fork or
   checkpoint mechanism that retains reusable diagnostics/workspace state while
   isolating mutable candidates. Connect constrained sketch/assembly features
   to their last committed numerical state. A downstream failure must never
   influence the next warm start, and distinct documents sharing feature
   declarations must remain independent.
2. **Feature graph scaling.** Compile iterative topological ordering and reverse
   dependency indexes. Traverse the affected closure rather than scanning the
   entire graph for each edit. Evaluate a bounded immutable state structure
   so old snapshots remain stable without copying every output on every edit.
3. **Tiny QR crossover.** Test a narrowly bounded exact-norm path for matrices
   where cache setup can exceed saved scans. Preserve rank, pivot budgets,
   cancellation and numerical validation. Keep the measured guarded path for
   larger matrices. Retain this optimization only if paired evidence supports it.
4. **Nonlinear CAD evidence.** Add a deterministic closed-loop mechanism corpus
   with independent geometric oracles, retained edits, near-singular cases and
   rejected/contradictory edits. Local numerical failure is not a global
   infeasibility certificate.
5. **Integrated verification and measurement.** Run focused correctness gates,
   then the full native and bounded Node JavaScript/Wasm corpus. Freeze source
   before sequential JIT/AOT paired comparisons against this starting source.
   Preserve raw measurements, regressions, runtime/harness hashes and limits.

## Boundaries

- Preserve existing public behavior and immutable historical document states.
- A fork must never alias mutable values, enabled flags, dirty sets or writable
  workspace arrays. Cached numerical state may be reused only with unchanged
  keys and exact invalidation.
- No failed candidate becomes committed session state, including downstream
  kernel/reference failures.
- Do not trade numerical soundness or required physical tolerances for timings.
- No unverified claim of general solid modeling: the production kernel adapter
  and broader solid operations remain separate work.
- Baseline browser CI was queued; local Chromium was blocked by the workspace's
  denied process-singleton socket. Neither is a passed gate.
- Save the plan before source edits and preserve each verified coherent
  implementation remotely. Do not merge or publish a release.

## Checkpoints

| Stage | Status |
|---|---|
| Current branches/PRs checked and continuation plan | Initial remote checkpoint |
| Transactional numerical reuse | Pending implementation and independent review |
| Feature graph scaling | Pending implementation and independent review |
| Tiny QR crossover | Pending correctness and paired evidence |
| Nonlinear CAD corpus | Pending independent oracle checks |
| Integrated gates and sequential measurements | Pending |


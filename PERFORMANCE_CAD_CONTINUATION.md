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
   Connect the checked mechanism to actual bar prototypes and rigid occurrences
   in a layered articulated assembly; angle edits must retain bodies and meshes.
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
| Transactional numerical reuse | Implemented; 50 focused tests pass, including 19 new fork/CAD cases; two independent reviews clear isolation and cache invariants; candidate scratch buffers remain freshly allocated |
| Feature graph scaling | Implemented; 76 focused CAD tests pass, including ten new graph cases and both declaration/document-subclass bypass regressions; 20,000-deep history and 600 independent random-DAG edit oracles |
| Tiny QR crossover | Candidate checkpoint 2ed9223 rejected by the complete paired trial: most tiny AOT rank batches regress, including 5x4 +29.6%, 8x4 +35.1%, 16x8 +36.9%; original guarded numeric implementation restored, useful oracle tests/harness retained. All 108 trial reports and 76 summary rows saved at 3d98f36. |
| Nonlinear CAD corpus | Source checkpoint 93703b1; ten tests and baseline-compatible harness checks pass, covering tilted-workplane four-bar branches, toggle rank, contradiction, cancellation and rollback |
| Integrated gates | Final source 3f042cd passes 1,756 native tests and 420 each under JavaScript/Wasm on Node; full fatal-info analysis and all 205 Dart files pass formatting. This reruns the earlier candidate gates after QR rollback and the six solid-linkage additions. |
| Articulated solid linkage example | Implemented; six focused native tests, strict analysis and executable example pass. Four two-hole bar prototypes/meshes are retained across angle edits; selective shape rebuilds and downstream rollback checked. |
| Sequential paired measurements | Complete: 108 final reports and 76 summary rows against 3b5c4c4, using retained source 3f042cd; all checks pass. The full earlier 108-report rejected QR trial remains preserved separately. |

## Final results and remote preservation

The retained changes reduce a four-feature edit in the 10,000-feature scalar
graph fixture from 4.216 to 0.020 ms AOT and from 4.714 to 0.061 ms JIT.
Cold construction costs rise 14.6% AOT and 56.2% JIT at that size; 1,000-feature
JIT cold construction also regresses substantially. The transactional CAD
geometry edit improves from 1.283 to 0.870 ms AOT, with the same physical/Jacobian
evaluation counts and one reused rank diagnostic. Direct nonlinear AOT edits
remain approximately flat. These are scoped fixture measurements, not general
solid-regeneration or frame-latency guarantees.

Independent review reconciles all 456 per-process p50/p95 pairs and 372 retained
raw-sample distributions, plus source/harness/dependency hashes and revision
ordering. The complete results, tails, cold tradeoffs and reproduction procedure
are in [doc/performance-cad-continuation.md](doc/performance-cad-continuation.md).

| Commit | Remote checkpoint |
|---|---|
| `0404e83` | Continuation plan before source changes |
| `2ed9223` | Tiny-QR experiment and independent small-shape tests/harness |
| `93703b1` | Nonlinear tilted four-bar model, oracle, tests and harness |
| `6b2a455` | Indexed feature graph and immutable chunked state |
| `f3c0ea7` | Isolated numerical forks and CAD rank-cache retention |
| `e7c567d` | Expanded portable corpus and benchmark dependency provenance |
| `b0cd755` | Private compiled graph snapshots and subclass-bypass regressions |
| `fd2ff55` | Initial integrated gates and reproducible summary tooling |
| `3d98f36` | Complete unsuccessful QR trial and its summary |
| `63cd726` | Remove slower tiny-QR dispatch; retain tests/harness |
| `3f042cd` | Articulated solid linkage and six additional regressions; final measured source |
| `4f81ed0` | Final 108-report paired comparison, 76-row summary and full validation record |

Final raw reports, validation records and documentation are saved after those
source checkpoints. All work remains on `audit/performance-cad-2026-11-13` and
draft PR #4. Main and PR #3's source branch remain unchanged. Real-browser CI is
still an independent open gate; no queued job is counted as passed, and no merge
or release is part of this continuation.


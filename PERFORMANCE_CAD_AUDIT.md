# Latest-branch performance and 3D CAD audit

Date: 2026-11-13. Starting source: `1bb0d281654fb21eb11e7d01f25aa5fc294aafe9`.
Working branch: `audit/performance-cad-2026-11-13`.

## Baseline and preservation

The latest remote source branch at audit start was
`feat/performance-parametric-cad`, draft PR #3.
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
| Cumulative scheduling | Implemented; source checkpoint | 34 existing and 12 new focused tests pass, including independent small-schedule oracles, billion-scale ranges/durations, both LCG engines, budgets and rollback; large compact ranges use sound bounds-only interior propagation |
| Numeric rectangle soundness | Implemented; source checkpoint | Nine new regressions, including 80 independent finite-domain layout oracles; fractional layouts propagate and validate in sessions; mixed extreme arithmetic uses conservative fixed-pair checks; mixed LCG reasons stay opaque |
| Scheduling arithmetic boundaries | Implemented; follow-up checkpoint | 16 cumulative sweep tests plus 34 existing scheduling tests pass; exact portable-integer envelope rejects unsupported arithmetic explicitly; independent review cleared event sweep and arithmetic guards |
| Geometric numerical performance | Implemented and measured | 89 focused geometry tests pass; guarded QR norm reuse, dense pivot budgets and empty AD storage reuse; independent rank/solve/projection checks and work counters; QR AOT medians improve 26.5%–38.5% on the measured chains |
| Stable preference inputs | Implemented; source checkpoint | 45 focused tests pass, including five mutable-input regressions; callbacks and asynchronous yields cannot change an in-flight target tolerance, weight or coordinate scale |
| Stable mesh volume | Implemented; source checkpoint | 43 focused CAD tests pass, including four new translated-volume/orientation/compensation regressions; scoped analysis and formatting pass |
| 3D part instances | Implemented, reviewed and measured | 58 focused CAD tests pass, including 15 new rigid-transform/instance/assembly regressions; executable perpendicular-plate assembly and pose-only prototype/mesh reuse; independent review cleared and current cold/edit measurements recorded |
| World placement precision | Implemented and reviewed | 66 focused CAD tests pass; eight new precision/custom-input regressions reject collapsed or dimensionally distorted placement, preserve exact large translations, and expose mesh export error allowances; included in integrated gates |
| Integrated executable validation | Passed locally | 1,702 native tests and 366 tests each under JavaScript/WebAssembly on Node; full fatal-info analysis and 193-file formatting gate pass. Local Chrome cannot start because the workspace denies its process-singleton socket. |
| Paired benchmark evidence | Complete | 84 sequential paired JIT/AOT harness reports plus 12 current assembly/scaling reports and 12 separate volume-isolation reports; every independent result check passed. AOT 3,000-unit range scheduling 113.060→0.071 ms; QR72 0.599→0.387 ms; coupled cold 1.566→1.314 ms; warm coupled flat. Standard CAD cold/profile medians regress 10.1%/8.8%; current assembly pose edits 0.084 ms with prototype/mesh reuse. No universal latency claim. |

## Remote preservation record

Every row below was saved to the remote audit branch before subsequent stages.
The original source branch and main still match the starting hashes. The draft
review is [PR #4](https://github.com/CrispStrobe/dart_csp/pull/4), based on main
and including the existing PR #3 work. The
[audit-only comparison](https://github.com/CrispStrobe/dart_csp/compare/1bb0d281654fb21eb11e7d01f25aa5fc294aafe9...audit/performance-cad-2026-11-13)
isolates this pass.

| Commit | Preserved checkpoint |
|---|---|
| `d27227c` | Audit plan before implementation |
| `8e14aa5` | Stable translated mesh volume |
| `f6a54dd` | Guarded QR norm reuse, dense budgets and empty AD storage |
| `410e405` | Swept cumulative scheduling |
| `36ee95b` | Snapshot preferences before callbacks and asynchronous work |
| `7f462bb` | Rigid instances and solved 3D assemblies |
| `d2cbaeb` | Fractional DiffN, scheduling arithmetic guards and scheduling benchmark |
| `1421144` | World-placement precision, portable regressions and benchmark tooling |
| `7d70e4f` | Strict typing adjustment and integrated gate record; measured after source |
| `60d9de0` | Main paired measurements, summary and current assembly/scaling evidence |

The final report, volume-isolation evidence and user-facing documentation are
committed after those implementation/data checkpoints. No source implementation
changed after the measured revision. See
[doc/performance-cad-audit.md](doc/performance-cad-audit.md) for the complete
findings, timings, reproduction procedure and next priorities. Local native,
Node JavaScript/Wasm, analysis and formatting gates are complete; real-browser
validation remains open. GitHub Actions was queued at final inspection, which
is not a passed gate. No merge or release was performed.

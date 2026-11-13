# Recovered CSP/CAD continuation

Date: 2026-11-13. Starting checkpoint:
`2777886a5a1da0f0b5f9d402ecca62cf788ccb3d` on
`audit/performance-cad-2026-11-13`, draft PR #4.

The user asked to continue the work, bring in all branches and PRs, and keep
pushing incremental remote checkpoints so interruption cannot lose the work.
The pasted interrupted transcript predates the remote checkpoint: the previous
continuation, articulated solids, rejected tiny-QR experiment, final benchmark
data and validation record were already saved. See
[the completed continuation](doc/performance-cad-continuation.md).

## Recovered branches and pull requests

All remote heads and PR heads were fetched into the recovery checkout.

| Source | Recovered head | Integration state |
|---|---|---|
| `main` | `13f2b04925443a75b6766c969b10aefc65978a0e` | Ancestor of the audit branch |
| `feat/performance-parametric-cad`, PR #3 | `1bb0d281654fb21eb11e7d01f25aa5fc294aafe9` | All commits included in PR #4 |
| `audit/performance-cad-2026-11-13`, PR #4 | `2777886a5a1da0f0b5f9d402ecca62cf788ccb3d` | Current integrated source, 24 commits beyond PR #3 |
| PR #1, `fix/dart2js-interval-bitset-promotion` | `9589ea1b4358db12b8baed4f256692fc5474652d` | Already merged to main as `ce10138` |
| PR #2, `ci/full-browser-suite` | `d063d6d83a5b5dccdf04569037e4f30f32263150` | Already merged to main as `b87babf` |

At recovery, the GitHub branch listing contained exactly the three active
branches above.
PR #3 and #4 have no review comments or review threads at recovery. The older
PR #3 CI run [43431946099](https://github.com/CrispStrobe/dart_csp/actions/runs/43431946099)
passed, including browser and JS/Wasm jobs. PR #4 run
[43493846267](https://github.com/CrispStrobe/dart_csp/actions/runs/43493846267)
has five successful OS/SDK jobs and remaining jobs queued at recovery;
its browser gate is still open.

## Work selected before source changes

1. Reduce the measured cold feature-graph setup cost while retaining immutable
   declaration snapshots, indexed dirty traversal, stable order and rollback.
2. Reduce eager scratch allocation when forking geometry sessions with many
   unchanged components. Writable state must remain isolated; callbacks and
   custom manifolds retain their documented invalidation contract.
3. Add realistic articulated-solid timing coverage with independent geometry,
   retained part/mesh and rollback checks, alongside the existing scalar graph
   and numerical fixtures.
4. Run focused correctness checks, static analysis and native/JS/Wasm gates on
   the integrated source; attempt the browser gate in this environment.
5. Measure paired frozen sources sequentially with matching harnesses and
   preserve full results, including regressions. Reject unsupported performance
   claims and experiments that fail their intended tradeoff.

Each coherent implementation and its evidence will be committed and pushed.
Working branches may be used for parallel tasks and folded into the existing
audit branch. Preserve prior heads and history; do not force-push, delete
branches, merge to main or publish a release as part of this continuation.

## Checkpoint log

| Stage | Status |
|---|---|
| Recovery, branch/PR inventory and plan | Saved before implementation |
| Cold graph setup | Implemented and independently reviewed; 36 focused tests pass; unconditional declaration snapshots retained |
| Lazy fork scratch allocation | Implemented and independently reviewed; 39 focused isolation/CAD/preference tests pass; first-use allocation stays in complete-operation timings |
| Articulated-solid benchmark | Five independently checked paths; per-sample kernel/solver/graph work retained; frozen baseline compatibility checked |
| Integrated correctness | Source `03c75b9`: 1,758 native tests, 422 each on Node JS/Wasm, fatal-info analysis and all 207 Dart files pass formatting |
| Paired measurements | 84 reports / 62 summary rows; 372 process percentile pairs, 8,700 raw samples and 3,900 work records independently reconciled |
| Browser gate | Baseline Chromium startup blocked by denied process-singleton socket; zero tests executed. Candidate CI run 43509092738 queued at measurement start. |

## Saved checkpoints and results

| Commit | Remote checkpoint |
|---|---|
| `7bcc4a5` | Recovery inventory and selected work before source changes |
| `5637372` | Cold graph setup, scoped snapshots and behavioral regression |
| `66bccb7` | Solid-linkage benchmark, work counters and comparison integration |
| `03c75b9` | Private lazy numerical scratch, fork regression and complete-operation benchmark; validated/measured source |
| `78ec1df` | Complete raw measurements, summary, validation/full logs and independent audit |

The audit branch contains every checkpoint. Separate remote branches retain
`perf/cad-graph-setup-2026-11-13`, `bench/cad-solid-linkage-2026-11-13` and
`perf/geometry-fork-scratch-2026-11-13`. Main, the original PR #3 branch and
the previous audit history are preserved.

The retained changes reduce 10,000-feature cold graph p50 by 19.6% AOT / 25.3%
JIT and complete 1,000-component sparse fork/edit/solve p50 by 38.2% AOT /
28.4% JIT in the paired run. Solid cold AOT regresses 9.7%, retained solid
angle edits regress in every round, and several p95 tails worsen.
These are scoped gains with explicit costs, not an overall CAD speedup.

See [the complete recovery report](doc/performance-cad-recovery.md) for all
decisions, controls, measured tradeoffs and reproduction commands. Raw reports
are compressed losslessly, and the summarizer accepts `.json.gz` directly.

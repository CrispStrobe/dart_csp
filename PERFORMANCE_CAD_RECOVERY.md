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

The GitHub branch listing contains exactly the three active branches above.
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
| Cold graph setup | Pending |
| Lazy fork scratch allocation | Pending |
| Articulated-solid benchmark | Pending |
| Integrated correctness and measured results | Pending |

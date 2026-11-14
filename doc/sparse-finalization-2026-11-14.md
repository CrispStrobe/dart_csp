# Sparse solver finalization — 2026-11-14

## Recovery boundary

This continuation starts from remote checkpoint
`806b236726e70b856fc3ca4d1286936ccd340a3d` on
`perf/dart-sparse-direct-2026-11-14` (PR #9). The retained solver source is
`6cc191f3e9a7c6642afa9af7757b26e515723018`; consolidated main remains
`135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.

The previous agent successfully preserved its entire three-round timing cohort.
The older completion and PR status text is stale: preparation, correctness
qualification, full available validation, and the 96-job timing run are already
complete and remotely recoverable. They must not be rerun merely because the
conversation was interrupted.

An independent recovery audit checked all 714 manifested files in the four
`benchmark/results/2026-11-14-sparse-completion` archives, then reran the physical
oracle against all 972 qualification/timing operations. Archive hashes, exact
member sets, source trees, raw requests and output, operation identities, job
counts, terminal manifests, and reported timing ratios agree. No audit errors
were found. See `recovered-evidence-audit.json` in that results directory.

The saved source passes formatting, fatal-info analysis, 1,862 native tests,
541 JavaScript tests, 541 WebAssembly tests, and 48 comparison-harness tests.
The 36-job correctness qualification contains 108 operations: 96 feasible
operations accepted and 12 contradictions rejected. All 864 operations in the
timing cohort were accepted. Real-browser validation remains unverified; local
Chromium previously failed before tests, and GitHub CI is still queued.

Independent source review found no correctness blocker in numerical assembly,
deterministic active-column ordering, resource caps, CSR mutation handling,
cancellation, reentrancy, or shared direct/CG iteration budgets.

## Measurements still needed

The saved 500-coordinate ladder has median time ratios of 0.043–0.126 versus
main (87–96% less time). The 500-coordinate coupled graph ranges from 0.960 to
1.089. The 100-coordinate cold ladder is slower by 37–39% in that cohort;
its warm cases are faster. These adverse observations remain preserved.

Below the direct threshold, QR/CG selection is unchanged. That fact does not
prove the observed cold regression is noise: dispatch, residual polling, and
compiler code layout can still influence timing.

1. Restore the exact Dart 3.14.0 compiler and canonical dependency lock. Prepare
   clean detached main and candidate worktrees with identical adapter bytes.
   Keep this host's evidence separate from every earlier cohort.
2. Run seven alternating paired rounds of `ladder_25_components_1` (100 free
   planar coordinates) and `laman_free_100`, using both 3D AD and 2D analytic
   engines, cold/warm modes, five warmups, and 21 measured operations per job.
   Preserve the complete cohort before drawing a conclusion.
3. Run the 2,000-coordinate coupled fallback comparison separately, preserving
   rejected or timed-out outcomes and reporting latency only for qualified
   results.
4. Run the existing small-QR, CAD plate, and CAD linkage controls in both JIT and
   AOT, with alternating revisions and one pinned benchmark process at a time.
5. Audit new raw evidence, record the integration decision and actual CI/browser
   boundary, and integrate the retained qualified source into main. Any source
   change requires the corresponding correctness gates before integration.

## Saving policy

Every coherent source, raw-evidence, or decision milestone is committed to the
existing remote PR branch with an expected-head check. Original branches and
all adverse results remain intact. The GitHub connector performs authenticated
writes because this workspace's ordinary Git transport has no push credentials.
No history rewriting or force push is used.

## Separate small-control confirmation

The same Dart 3.14.0 binary was restored (SHA-256
`6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b`).
Both clean worktrees use the same locked dependencies and identical adapters.
The new preparation and small-control cohort are under
`benchmark/results/2026-11-14-sparse-finalization/`. The two native adapter
executables are omitted from the preparation archive; their exact hashes,
source snapshots, build commands, compiler identity, and logs are preserved.

All 112 jobs completed. The independent raw audit accepted all 2,912
operations (560 warmups and 2,352 measured operations), with no timeouts,
process errors, parsing errors, or physical-oracle discrepancies. This is a
separate host cohort; no samples are pooled with the earlier timing run.

Ratios below are candidate/main, using the median of each process's percentile.

| Fixture, free planar coordinates | Engine | Mode | p50 ratio | p95 ratio |
|---|---|---|---:|---:|
| Ladder, 100 | 2D analytic | Cold | 0.977 | 0.955 |
| Ladder, 100 | 3D AD | Cold | 1.001 | 1.275 |
| Ladder, 100 | 2D analytic | Warm | 1.041 | 1.094 |
| Ladder, 100 | 3D AD | Warm | 1.007 | 1.026 |
| Coupled, 100 | 2D analytic | Cold | 0.974 | 1.011 |
| Coupled, 100 | 3D AD | Cold | 1.045 | 1.060 |
| Coupled, 100 | 2D analytic | Warm | 1.006 | 1.049 |
| Coupled, 100 | 3D AD | Warm | 1.023 | 1.034 |

The earlier 37–39% cold-ladder median slowdown is not reproduced. The largest
new median slowdown is 4.45%, for the 3D cold coupled case. The adverse 3D
cold-ladder p95 aggregate remains visible: 6.074 ms to 7.745 ms, or 27.5% higher.
Per-round paired p95 ratios tell a different story: their median is 0.971,
with two of seven candidate rounds slower and a range of 0.835–1.622. Both
statistics are retained; this does not establish a uniform tail improvement
or prove that the adverse observation is noise.

`tool/audit_paired_evidence.py` reproduces the raw-record audit and the
per-round comparisons from either directories or the saved tar archives.

## Current status

Recovery, source review, preparation, and the separate small-control
confirmation are complete. The 2,000-coordinate fallback check and JIT/AOT
small-QR/CAD controls remain. No final integration decision has yet been made.

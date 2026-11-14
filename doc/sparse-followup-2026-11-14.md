# Sparse follow-up optimization — 2026-11-14

This plan is complete. See [the final results and retention decision](sparse-followup-results-2026-11-14.md).
The qualified heap source is retained with explicit coupled/small/CAD timing
costs; the isolated QR allocation candidate is rejected. The sections below
preserve the original plan and successive checkpoints.

## Baseline and scope

The user requested further optimization after PR #9 was merged. The exact
baseline is main `c2603a852229897d325a8890ed418319ee8c3572`, containing the
qualified sparse source and complete preserved measurements. Progress is saved
on `perf/sparse-followup-2026-11-14`; the earlier branch and all its evidence
remain intact.

The first candidate targets cold symbolic ordering. The retained selector scans
every remaining column for every pivot, costing `n * (n + 1) / 2` candidate
visits even for low-fill patterns. An indexed minimum heap keyed by current
degree and original column can avoid those scans while preserving exact pivot
order. It must charge its own work to the symbolic budget, preserve cancellation,
and leave numeric assembly, fill limits, physical acceptance and shared direct/CG
iteration budgets intact. Improved structural bookkeeping can alter admission
under tight caps, so the dense-fill fallback remains a separate reliability gate.

An independent scout is also examining the small-QR/CAD tail paths. The earlier
tail observations do not establish a cause; previously rejected placement,
mesh and numerical experiments will not be silently reinstated.

## Measurement and retention rules

1. Freeze the candidate source and focused regressions before measurement.
2. Use the exact recovered Dart 3.14.0 compiler and canonical lock in clean
   detached baseline/candidate worktrees. Keep each new cohort separate from
   earlier hosts and source revisions.
3. Run focused correctness, cancellation and cap tests, then the existing
   physical qualification suite before quoting solve timings.
4. Compare cold/warm 500- and 2,000-coordinate low-fill ladders, the coupled-500
   graph, and small controls with alternating revisions and one pinned process.
   Preserve the coupled-2,000 failed or successful outcomes independently.
5. Preserve raw results during collection, independently audit all outcomes and
   timing calculations, and retain a candidate only with an explicit benefit/
   cost decision. Validate any newly retained source on native and portable
   targets before integration.

Main CI run `43604068012` was still queued at the start of this pass. The existing
Node gates remain distinct from real-browser coverage. No package release is
part of this work.

## Initial candidates

The heap candidate uses the new selector at 256 columns and above. Small direct
systems retain the existing live-column scan, including its exact budget
boundaries. All 53 existing sparse tests and four new ordering/cap/cache/
cancellation regressions pass. The new regression is included in the Node
portable and real-browser CI corpora. No measured speed claim is made yet.

A separate allocation candidate is saved at
`748febd527cda9eeb611cdf2dcba3c9c3af388ec` on
`experiment/qr-permutation-2026-11-14`. It initializes the QR identity permutation
directly in its typed buffer, removing one temporary generated integer list per
factorization. Initialization completes before the first cancellation callback;
QR arithmetic, pivoting, norm caches and budgets are unchanged. All 45 existing
small-QR/numerical regression tests and scoped analysis pass.

The allocation screen compares that isolated source against `c2603a8` using
`geometry_small_qr`, `cad` and `cad_linkage`, both JIT/AOT, three alternating
rounds, 20 warmups and 101 measured samples. Only one pinned benchmark process
runs at a time. This screen and the heap comparison remain separate experiments.

## QR allocation retention decision

Reject the isolated QR candidate. The complete screen has 36 reports, 24,240
raw samples/batches and 40 aggregate rows. Both independent audits pass, all
9,696 CAD work records satisfy their invariants and all 4,848 paired records
match. However, AOT plate cold/profile/thickness medians are +7.03%/+10.29%/
+9.61%, and p95 values are +6.18%/+28.26%/+27.81%, all worse in every paired
process. JIT cold-linkage median rises 33.92%, also in all three pairs. The
AOT rank-4x8 improvement of 12.15% does not justify those collateral costs.

The one-list source change remains on its separate experiment branch; it is
not included in the heap candidate. All raw results, favorable and adverse
tails, derived p99 descriptions, audits and the complete review are preserved
under `benchmark/results/2026-11-14-sparse-followup/qr-screen/`. The data do not
identify a cause for the timing differences or measure allocated bytes.

## Heap source checkpoint

Source `521a31f78989cf4706c8f26bb6a2c2ec2709b777` contains the isolated heap and
new regressions. The independent graph model agrees with the scan oracle on
1,092 graphs, including every undirected five-vertex graph and large-boundary
cases. This supplements compiled Dart tests; it is not timing evidence.

Frozen baseline/candidate preparation is saved with source archives, dependency
identities, compiler and AOT hashes. Formatting, fatal-info analysis, all 1,866
native tests, 545 Node JavaScript tests, 545 Node WebAssembly tests and
48 comparison-harness tests pass for these exact source bytes.
The independent audit of the fresh 36-job physical qualification passes:
all 96 feasible operations are accepted and all twelve contradictions rejected,
with no missing operations, timeouts or integrity findings. This includes
36 warmups among the 108 checked operations.

Final status: the 72-job target comparison, 48-job small controls, eight-job
dense reliability cohort and complete 36-report JIT/AOT CAD screen are saved
and independently audited. The final report records all gains, adverse
observations, unchanged convergence limits and the retention decision.

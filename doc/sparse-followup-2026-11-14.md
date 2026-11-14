# Sparse follow-up optimization — 2026-11-14

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

Current status: both source candidates have focused correctness coverage;
the isolated QR allocation screen is running while the heap source is saved
for physical qualification and its independent paired comparison.

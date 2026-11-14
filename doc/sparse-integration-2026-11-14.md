# Sparse solver integration — 2026-11-14

## Recovery checkpoint

This continuation recovered remote `f938f29c6cc41c9f73ad32e9af81be0425a37ec3`
on `perf/dart-sparse-direct-2026-11-14` (PR #9). The previous agent saved the
complete seven-round control cohort, its independent audit, and runtime/build
preparation before the interruption. Those experiments will not be repeated
merely to recover their results.

Production source remains `6cc191f3e9a7c6642afa9af7757b26e515723018`, library
tree `eb20b0ea6dc251142e6109f04bb7fe768d967db1`, test tree
`053478f4a4d7b097211c5cb8984ff3fb6dc1a901`. Both trees match the recovered
head exactly. The baseline is main
`135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.

An independent recovery check verified all 597 members of the three finalization
archives and reran the preserved raw-output audit for all 112 control jobs:
2,912 operations accepted, including 560 warmups, with no audit errors. Every
one of the 1,456 matched before/after operations has identical coordinates and
work counters. This is additional to the already archived full source gates
and 972-operation qualification/timing audit in the completion cohort.

The archived numbers correct the interrupted chat's provisional description:
seven-round cold-ladder p50 ratios are **1.0321 in 2D** and **1.0280 in 3D**
(3.2% / 2.8% slower). Their p95 ratios are 1.1863 and 0.9849 respectively.
The largest adverse control p50 is the cold coupled 2D case, +7.94%.
The earlier 37–39% cold-ladder median regression does not recur at that
magnitude, but the remaining adverse results are retained. Cohorts from
different workspaces/hosts are not pooled.

## Remaining bounded work

1. Restore the exact Dart 3.14.0 compiler and canonical dependency lock; build
   clean detached main/candidate adapters and save this preparation.
2. Run `laman_free_2000` separately: one alternating paired round, zero warmups,
   two requested operations per job, both 2D analytic and 3D AD engines,
   cold/warm lifecycles, and a 20-second process deadline. Preserve all failed
   operations and deadlines; report speed ratios only for fully qualified
   paired groups.
3. Run `geometry_small_qr`, `cad`, and `cad_linkage` through the existing
   comparison collector in JIT and AOT, three alternating rounds, five warmups
   and 25 measured samples, with one pinned process at a time.
4. Audit the new raw evidence, record a retention decision, update the stale
   handover/PR status, and complete the previously authorized integration if
   the measured controls support it. Any production change requires validation
   of those new bytes before integration.

## Validation boundary and saving

The unchanged source has preserved passing formatting/fatal-info analysis,
1,862 native tests, 541 Node JavaScript tests, 541 Node WebAssembly tests and
48 comparison-harness tests. These are recovered results, not newly rerun
full suites. Independent source review found no concrete correctness blocker.
Real-browser validation remains unverified: the archived Chromium attempts
failed before assertions. GitHub CI run `43601185378` for recovered head
`f938f29` was still queued when checked during this continuation.

Each coherent preparation, evidence, and decision milestone is saved to the
existing remote branch with an expected-head check and no history rewriting.
All original branches and adverse observations remain preserved. No release or
package publication is included.

Current status: recovery complete; remaining measurements are pending.

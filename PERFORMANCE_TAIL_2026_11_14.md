# Follow-up: retained CAD latency and cold-build allocation

## Starting boundary

The user requested continuing optimization after PR #6 and retaining the
existing incremental GitHub-save workflow. Baseline main is
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51`, library tree
`6111175debbc7a3ae99631e274f24f16b28d2f25`. All 14 prior audit/work branch
heads remain included in main. The prior main workflow `43562820655` now has
all 17 active jobs successful, including the ten-file real-browser smoke
corpus and the stable/beta/dev Linux/macOS/Windows matrix. Full-browser and
release jobs were skipped.

The independent solver-comparison branch/PR #7 is still a draft receiving
concurrent development. It is outside this pass's baseline and measurements;
do not overwrite or silently absorb its unqualified experiments. The exact
initial inventory and CI snapshot are saved in
`benchmark/results/2026-11-14-tail-inventory.json`.

## Target and acceptance

The previous pass improved targeted CAD medians but had repeated retained-angle
and assembly p95 regressions, and numerical/document cold-build costs. Profile
complete operations and inspect source allocations; retain only bounded
changes that preserve ownership snapshots, physical validation, precision,
callback isolation, cancellation and rollback. Do not reinstate the prior
rejected scratch-buffer experiments or tune VM GC flags as a library fix.

1. Inspect CAD placement/transaction and geometric compilation/session paths
   independently. Propose small isolated candidates with source evidence.
2. Expand assembly timing evidence from legacy summary-only observations to
   raw ordered samples and aligned work. Preserve identical before/after
   harnesses and independent finite geometry/volume oracles.
3. Validate each candidate with focused regressions and independent source
   review, then measure complete cold and retained operations in sequential
   paired JIT/AOT processes, alternating revision order. Preserve controls,
   adverse results, and source/toolchain/dependency identities.
4. Keep instrumentation separate from normal timing. Offline CPU/timeline or
   GC data may support attribution only to the extent actually observed;
   allocation-count and pause-time claims require corresponding evidence.
5. Freeze retained source, run full native/portable/static gates, independently
   reconcile evidence, save the complete report and handover, and integrate
   through the normal PR controls. Preserve rejected candidate history too.

## Progress

Initial branch/CI reconciliation is complete. Source investigations and
benchmark instrumentation are in progress. Implementation checkpoints,
measurements and the final retention decision will be added incrementally.

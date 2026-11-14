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

Initial branch/CI reconciliation is complete. Both candidates passed focused
semantic checks and independent source review. Their separate three-pair
JIT/AOT comparisons are saved without dropping processes, samples or controls.

- Placement validation skips discarded concrete topology wrappers and owned
  output collections, preserving all numerical checks and public getter/
  iterator calls. The isolated cohort has 36 process reports and 20 rows.
  All five JIT linkage medians and p95 aggregates improve, with every individual
  pair faster. Costs include AOT linkage cold median (+2.9%, all three pairs
  worse), AOT assembly cold median/p95 (+5.1%/+12.8%), and JIT assembly pose
  p95 (+15.4%). This candidate advances to a fresh final comparison.
- Geometry result views and cached component identities have 72 process
  reports and 30 rows. Despite some solver edit gains, broad CAD/cold costs
  and inconsistent effects do not support retention. In particular, AOT
  coupled cold p95 increases 115.4% (all three pairs worse), and AOT assembly
  cold median/p95 increases 18.1%/46.5% (p95 worse in all three pairs).
  Revert only this candidate's production changes; retain its tests, isolated
  branch, merged history and all evidence. The retained numerical solver
  exactly matches the main baseline.

The raw isolated cohorts, summaries, independent measurement-auditor outputs
and logs use `benchmark/results/2026-11-14-tail-{placement,geometry}-*` and
`2026-11-14-tail-isolated-logs.tar.gz`. Baseline and candidate source IDs,
common harness hashes and dependency-lock identities are embedded in them.
Percentages above compare medians of process p50/p95 values, not pooled
percentiles; the shared, unpinned host limits causal claims.

Assembly now exposes raw samples and aligned physical/work checks. Separate
offline operation tracing records GC/compiler overlap without a service
socket. Its eight small same-source qualification runs test the collector,
not performance. Final normal timing, instrumented diagnostics, complete
gates, independent reconciliation and integration remain to be completed.

## Recovery checkpoint (2026-11-14)

The interrupted session was recovered from remote head
`e48430a153bba4b9790314e7a0a61129941029ac` on
`perf/cad-tail-2026-11-14` / draft PR #8. Its final normal CAD/control cohorts,
operation traces and independent normal-data review are durable. No final
tail validation manifest, completed retention decision or handover was present
at that checkpoint. Main remains `b3e14fbb298c8d4f3714debbeaffaeb6d550db51`.

The fresh normal cohort confirms AOT retained linkage gains but records AOT
assembly cold p50/p95 increases of 20.6%/72.4%, with all three pairs worse.
The instrumented cohort does not resolve that normal-timing regression. Treat
placement retention as undecided, preserve every cohort, and do not treat the
rejected geometry trial or passing checks for an earlier source as final proof.

The resumed pass will examine a bounded follow-up to placement validation,
measure it against both this checkpoint and main as appropriate, and finish
the source gates and report. Keep checkpointing source, observations and
reproduction instructions to this remote branch after each meaningful stage.
PR #7 and its solver-comparison branch remain outside this work.

### Resumed source decision

The original conditional-materialization placement change is withdrawn from
the proposed production source: its prior normal assembly cold regression
remains unresolved. Its branch/history, tests and all measurements survive.
Two narrower follow-ups also remain experimental: separating validation from
materialization improves JIT linkage edits but adds AOT costs, and direct
endpoint equality improves several AOT edits but worsens JIT linkage and AOT
assembly cold operations. Their complete normal cohorts and independent
audits are saved as `2026-11-14-recovery-{split,endpoint}-*`.

The next candidate, saved independently at `47f20f6`, uses scalar endpoints
for conservative transformed bounds. It preserves the interval algebra's
sign choices and outward-rounding order while avoiding its temporary interval
wrappers and lists. Relative to main, the only production difference is this
bounds implementation; instance validation and numerical solver code match
main. All prior regression tests remain, including the new endpoint boundary
test. Bounds tests cover bitwise interval-oracle agreement and public getter
ordering/failures. A four-pair complete-operation comparison and full frozen
source gates are pending at this checkpoint.

The normal comparison runner now verifies the effective package root, frozen
source/configuration/harness identities, records exact subprocess output and
exit/timeout status, and checkpoints even failures. Its five bounded fake
process regression tests passed. Remote checkpoints continue on PR #8's branch.

The completed four-pair bounds cohort does not support retention: AOT linkage
cold and angle-edit median/p95 values worsen in all four pairs. Restore its
production file to main; keep both candidate branches, the boundary/getter
tests and all `2026-11-14-recovery-bounds-*` evidence. Unchanged plate controls
also vary and are reported as context rather than attributed to bounds code.
The next isolated trial targets byte-order conversion overhead in
`IntervalRounding.nextUp`, with bit-level equivalence tests before measurement.

### Native rounding candidate

Guarded candidate `90b4a3e` is the first resumed trial supported by consistent
target gains. In four alternating main-relative process pairs with 400 samples
per case, all four retained AOT linkage operations improve median and p95 in
every pair (aggregate median reductions 11.4–39.4%; p95 reductions 7.3–34.5%).
JIT retained linkage median reductions are 20.9–50.7%, also every pair.
Assembly pose medians improve in every pair in both modes; cold assembly pairs
remain mixed even though aggregate medians improve. Preserve plate controls
and all tails rather than claiming a uniform speedup.

The production change is confined to `lib/src/continuous.dart`. Native targets
use shared float/uint32 views for exact next-double bit access. A compile-time
`dart.library.io` guard retains the original ByteData access on current web
targets. Special-value guards, 32-bit carry/borrow and `nextDown` are unchanged.
This improves the access path; both versions already reused scratch storage.
No allocated-byte reduction is claimed. CAD placement and numerical geometry
implementations match main.

The full CAD cohort is saved as `2026-11-14-recovery-rounding-cad-*`.
Independent bit-oracle tests pass on VM, Node JS and Node Wasm. Complete native/
portable/browser gates, a portable performance guard and remaining controls
are pending at this checkpoint.

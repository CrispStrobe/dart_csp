# Follow-up: JIT coupler tails and mesh construction

## Starting boundary

The user asked to continue the optimization and retain incremental remote saves.
Start from saved PR #8 head `6602c8a889aa19acc8f782ac152d3df429e40e49`.
Production contains the guarded native rounding change only; main remains
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51`. The prior complete report and its
qualified retention decision remain in `doc/performance-tail-recovery-2026-11-14.md`.
At the opening observation the prior head's GitHub workflow is still queued.
No previous browser/platform pass is inferred. PR #7 remains outside this work.

This follow-up first repeats the recorded JIT linkage workload, then obtains
separate GC/compiler traces and evaluates a bounded mesh-construction candidate.
Normal timing remains separate from instrumentation. The original all-four-pair
coupler p99 regression is retained regardless of the next cohort's direction.

## Fresh uninstrumented JIT diagnostic

The same baseline `b3e14fb` and isolated native candidate `90b4a3e` run four fresh
alternating JIT-only pairs with 400 measured samples after 40 warmups. Harness
and fixture bytes match. This is explicitly `diagnostic_only: true`, not a full
JIT/AOT retention cohort. All eight reports, 16,000 ordered samples and aligned
work records are preserved in `benchmark/results/2026-11-14-coupler-repeat-jit-*`.
Independent sample reconstruction passes 8,274 checks and 8,000 exact paired
work comparisons without findings.

Values are medians of four process percentiles, in microseconds; no samples are
pooled or removed. Pair direction is reported independently of aggregate change.

| Operation | Median before→after | p95 before→after | p99 before→after |
|---|---:|---:|---:|
| Cold linkage | 1832.5→1828.5 (−0.2%) | 2705.5→2807 (+3.8%) | 4381.5→4551 (+3.9%) |
| Angle edit | 260.5→193 (−25.9%) | 470.5→426.5 (−9.4%) | 698→737 (+5.6%) |
| Coupler-length edit | 623→569 (−8.7%) | 901.5→917 (+1.7%) | 1382→1997 (+44.5%) |
| Placement-only edit | 156→85 (−45.5%) | 296.5→174.5 (−41.1%) | 391.5→332 (−15.2%) |
| Rejected-angle edit | 231→166 (−28.1%) | 378.5→366.5 (−3.2%) | 628→713.5 (+13.6%) |

All retained medians improve in all four pairs. Coupler p95 and p99 now split
two faster/two slower, despite adverse aggregate changes. Individual coupler
p99 pairs are 1312→1764, 1452→1356, 1198→2790 and 2291→2230 µs. Thus the new
cohort does not reproduce the earlier four-of-four adverse tail direction;
it also does not resolve the tail cost. The original +56.2% result remains valid
for its frozen cohort. No GC/compiler cause is assigned from normal timings.

## Work in progress

- Harden the offline operation collector's package/source boundaries and add
  explicitly labeled JIT-only diagnostics. Existing operation markers suffice;
  retain full GC/compiler events, including background compiler function names.
- Independently examine ordered samples, parity and neighboring operations.
  Coupler is always third in the alternating operation order; outside-timer
  recovery and physical checks can affect subsequent runtime state.
- Trial reuse of already-interned mesh corner indices and private concrete cap
  centers, preserving exact vertex/index/face order and every validation check.
  Keep the source isolated until focused correctness and complete paired native
  measurements establish whether to retain it.

Source, raw observations and adverse results will continue to be saved to the
remote PR branch and isolated experiment branches. No merge is authorized by
this checkpoint, and no final performance retention is asserted for the mesh trial.

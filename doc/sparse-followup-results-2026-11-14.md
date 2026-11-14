# Sparse ordering follow-up: results and retention — 2026-11-14

## Decision

Retain the indexed exact minimum-degree heap in source
`521a31f78989cf4706c8f26bb6a2c2ec2709b777`. Large sparse patterns avoid a full
remaining-column scan at every symbolic pivot. The new 4,096-column regression
fits a 150,000-unit symbolic budget; the previous selector alone required
8,390,656 visits for that case. Numerical validation and the 108-operation
physical qualification pass.
The strongest repeated elapsed-time result is the 2,000-coordinate cold 3D
ladder: p50 falls 9.56% and p95 falls 21.21%, with both improvements in all three
matched process pairs.

This is a selective sparse optimization with observed costs. Coupled-500 cold
medians rise 5.67% in 2D and 4.94% in 3D; its warm 3D p95 rises 22.40%. The
100-coordinate 2D cold-ladder p95 rises 49.32%. Small-QR/CAD controls include
AOT rank-16x8 p50 +15.95%, AOT plate-profile p95 +20.78%, and JIT placement-only
p95 +30.16%. All observations, including their differing paired directions,
remain in the evidence. The decision accepts these measured tradeoffs for the
bounded-work improvement and qualified low-fill target gains; it does not
claim a universal latency improvement or resolve the earlier JIT tail costs.

Reject the separate QR identity-permutation allocation experiment at
`748febd527cda9eeb611cdf2dcba3c9c3af388ec`. Its repeated CAD median regressions
outweigh its isolated QR benefit. That source remains on
`experiment/qr-permutation-2026-11-14` and is absent from the retained library.

[PR #10](https://github.com/CrispStrobe/dart_csp/pull/10) tracks integration.
All incremental commits remain on `perf/sparse-followup-2026-11-14`. The
[earlier sparse report](sparse-results-2026-11-14.md) remains a separate
experiment against its earlier baseline; none of its samples are pooled here.

## Exact source and measurement boundary

| Identity | Value |
|---|---|
| Baseline main | `c2603a852229897d325a8890ed418319ee8c3572` |
| Frozen heap candidate | `521a31f78989cf4706c8f26bb6a2c2ec2709b777` |
| Candidate library tree | `9adec7f68b8a8b919890a0b9ff7d069a650ddd62` |
| Candidate test tree | `9b576992586ad3fe8e175869883a4b5b89e439ba` |
| Dart | 3.14.0 stable |
| Dart binary SHA-256 | `6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b` |
| Dependency lock SHA-256 | `a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a` |

The sole production-file delta from this baseline is
[`lib/src/geometry/sparse_ldlt.dart`](../lib/src/geometry/sparse_ldlt.dart).
Later commits preserve evidence, review tools and documentation without changing
the qualified library or tests. For the sparse adapters, source archives,
compiler identities, dependency inputs, exact preparation commands, build logs
and executable hashes are saved.
Temporary AOT executables are omitted from the preparation archive and listed
with their exact digests in its manifest.

All timed solver processes run sequentially, pinned to CPU 0, with alternating
revision order and compilation completed before timing. Separate lightweight
evidence analysis does not execute a solver. The sparse cohorts use native AOT
adapters and the original physical oracle. The small-QR/CAD cohort separately
uses JIT and AOT, with unchanged frozen benchmark harnesses. Each cohort has its
own complete inventory and is retained independently.

## What changes

Patterns with at least 256 columns use an indexed binary heap keyed by current
degree and original column index. There is one entry per live column. A pivot's
graph removal and fill finish before affected neighbor keys are repaired.
Stored degree snapshots keep each repair independent of other graph degrees
that have changed but whose heap keys have not yet been updated.

The selector preserves exact minimum-degree choices, original-index ties,
sorted neighbor lists, factor layout and numerical update order for patterns
admitted by both revisions. The smaller-pattern live-column scan is retained.
Heap initialization, removals, updates and comparisons count against the
symbolic-work cap and poll for cancellation. Factor-entry, numeric-work and
assembly caps remain in force. A more efficient selector intentionally changes
which large patterns can fit a tight symbolic cap; the cap remains a selected
operation limit, not a byte count or wall-time guarantee.

The new regression file exercises a 4,096-column bounded solve, a fill-sensitive
original-index tie with an exact 57-update numeric boundary, fresh/negative/
positive cache cap behavior, and cancellation during ordering followed by a
successful later solve. The independent scan-oracle model matches the heap on
1,092 graphs, including all 1,024 undirected five-vertex graphs and four large
boundary patterns. This model supplements the compiled Dart tests.

See the [configuration guide](sparse-geometry-backend.md) for public options,
adaptive selection, cancellation, caching and fallback behavior.

## Validation and physical outcomes

The exact frozen source passes formatting, fatal-info analysis, **1,866 native
tests**, **545 Node JavaScript tests**, **545 Node WebAssembly tests**, and
**48 Python comparison-harness tests**. The 51-file portable corpus and the
real-browser CI list both include the new ordering regression. The focused
sparse run passes 57 tests, including the four new cases.

| Physical cohort | Jobs | Checked operations | Independently verified outcome |
|---|---:|---:|---|
| Fresh candidate qualification | 36 | 108 | 96 feasible accepted; 12 contradictions rejected |
| Large paired targets | 72 | 648 | All accepted; 324 exact coordinate/work pairs |
| Below-threshold paired controls | 48 | 432 | All accepted; 216 exact coordinate/work pairs |
| Coupled-2,000 reliability | 8 | 16 | All `iterationLimit`; 8 exact coordinate/work pairs |

These totals include warmups: 36 in qualification, 144 in targets, 96 in small
controls and none in the reliability cohort. The independent audits replay
physical acceptance from saved raw numerical output and reconcile requests,
source/preparation identities, process inventories, exit codes, terminal gates,
timing summaries and all seven recorded solver-work counters. No operations
are missing; no timeout, adapter exception or oracle disagreement is hidden.

The constructed-feasible coupled-2,000 fixture remains unqualified on both
revisions. All sixteen outcomes are recorded failures of the local solve, not
evidence of infeasibility. Every successful-solve timing ratio for that cohort
is null. The selector does not fix this existing convergence limit.

## Large target timings

Each variant/fixture/engine/lifecycle uses three processes, two warmups and seven
measured operations. Times below are milliseconds per complete build or update,
solve and extraction operation. Each value is the median of three process
percentiles; a positive percentage means slower candidate time.

| Fixture / engine / lifecycle | p50 before → after (ms) | p50 change | p95 change |
|---|---:|---:|---:|
| Ladder 500 / 2D / cold | 7.731 → 7.411 | -4.15% | +0.09% |
| Ladder 500 / 3D / cold | 18.871 → 16.411 | -13.04% | -8.88% |
| Ladder 500 / 2D / warm | 6.023 → 5.437 | -9.73% | -18.92% |
| Ladder 500 / 3D / warm | 14.069 → 13.179 | -6.33% | +9.84% |
| Ladder 2,000 / 2D / cold | 38.954 → 37.686 | -3.25% | +7.76% |
| Ladder 2,000 / 3D / cold | 104.165 → 94.209 | -9.56% | -21.21% |
| Ladder 2,000 / 2D / warm | 26.296 → 26.258 | -0.15% | -51.27% |
| Ladder 2,000 / 3D / warm | 69.632 → 68.570 | -1.52% | -1.06% |
| Coupled 500 / 2D / cold | 66.220 → 69.978 | +5.67% | +0.23% |
| Coupled 500 / 3D / cold | 100.710 → 105.683 | +4.94% | +2.80% |
| Coupled 500 / 2D / warm | 60.038 → 55.051 | -8.31% | -31.12% |
| Coupled 500 / 3D / warm | 92.581 → 96.561 | +4.30% | +22.40% |

All eight ladder aggregate medians are lower; nine of twelve medians are lower
overall. Only the cold 2,000-coordinate 3D ladder improves both p50 and p95 in
all three pairs. Cold 500-coordinate 3D p50 improves in two pairs, while its p95
improves in all three. Warm 500-coordinate 3D p95 worsens in every pair despite
its lower median in every pair. The complete paired directions and unrounded
values are in the
[target review](../benchmark/results/2026-11-14-sparse-followup/targets-521a31f-independent-review.md)
and adjacent timing-details JSON.

With seven samples, each process p95 is its largest sample; the aggregate p95
is the median of three process maxima. This is screening evidence, not a stable
tail bound. A ratio of separate process medians can differ in direction from
the majority of matched process ratios. All of those values remain available.
Equal numerical work does not identify the cause of elapsed-time differences,
and warm timing changes alone cannot be attributed to the selector.

## Small controls and collateral CAD costs

The 100-coordinate fixtures use the same three-round, two-warmup, seven-sample
design. They fall below the adaptive direct threshold, so their changes are
collateral observations rather than measured heap speedups. Five of eight
aggregate medians improve. The 2D cold ladder p95 increases
**3.478 → 5.193 ms (+49.32%)**. Its warm p50/p95 increase **5.75% / 19.84%**;
warm 3D ladder/coupled medians increase **0.90% / 0.56%**. Each adverse aggregate
row has mixed paired directions. Those qualifications do not erase the costs.
The [complete small-control review](../benchmark/results/2026-11-14-sparse-followup/small-controls-521a31f-independent-review.md)
preserves all eight rows and every process pair.

The separate small-QR/CAD comparison has **36 JIT/AOT reports**, three alternating
rounds, 20 warmups and 101 samples. Both independent audits pass: 58,278
source/measurement assertions and 1,010 process checks, with zero findings.
All **24,240 samples or batches**, **9,696 CAD work records**, and **4,848
equal paired work records** reconcile. Unlike the sparse adapters, this
collector records the harness's numerical pass checks and work counters, not
full geometry for a second physical-oracle replay. It preserves compilation/run
linkage and source, harness and dependency hashes, but does not hash its SDK or
AOT executable bytes. The stronger binary provenance in the sparse preparation
must not be attributed to this separate normal-collector cohort.

Of 40 median rows, 26 are lower, two equal and twelve higher. This count has no
application-workload weighting. AOT linkage medians are lower by 2.8–6.5%, and
JIT plate medians are lower by 6.9–11.5%. Material adverse observations include:

| Control | Observed change | Slower matched process pairs |
|---|---:|---:|
| AOT rank 16x8 p50, per 256-call batch | +15.95% | 2/3 |
| AOT rank 16x8 p95, per 256-call batch | +37.40% | 1/3 |
| AOT plate cold p95 | +43.01% | 2/3 |
| AOT plate profile p95 | +20.78% | 3/3 |
| AOT plate thickness p50 | +6.85% | 2/3 |
| JIT cold-linkage p95 | +5.97% | 3/3 |
| JIT placement-only p95 | +30.16% | 3/3 |
| JIT rank 8x4 p95, per 256-call batch | +26.83% | 3/3 |

AOT plate cold/profile/thickness p99 rises **30.50% / 17.46% / 5.25%**,
each with two slower pairs. JIT retained-angle p99 rises 67.14%, also with two
slower pairs. The complete
[40-row review](../benchmark/results/2026-11-14-sparse-followup/cad-controls/independent-review.md)
retains favorable and adverse p50/p95/p99 values and individual process results.
Plate p99 is harness-reported; QR and linkage p99 are labeled derived screening
statistics. At 101 samples each process p99 is its second-largest observation.
These measurements establish neither a stable tail bound nor allocation-byte,
GC or compiler causality. The previous pass's adverse findings remain separate
and unresolved.

## Rejected QR allocation experiment

The isolated experiment initializes the QR permutation directly in its typed
buffer, removing a temporary generated integer list. All 45 focused regression
tests pass and all work records agree, but its separate complete 36-report
screen shows AOT plate cold/profile/thickness medians **+7.03% / +10.29% /
+9.61%**, with p95 **+6.18% / +28.26% / +27.81%**, all slower in all three
paired processes. JIT cold-linkage median rises **33.92%**, also in every pair.
The AOT rank-4x8 median benefit of 12.15% does not justify those costs.

The [full rejected experiment](../benchmark/results/2026-11-14-sparse-followup/qr-screen/independent-review.md)
and its exact source branch are preserved. The retained heap source leaves
`numeric.dart` identical to baseline.

## Evidence, checkpoints and remaining boundary

All raw inputs/outputs, failures, process records, summaries, independent audits,
review scripts and validation logs are under
[`benchmark/results/2026-11-14-sparse-followup/`](../benchmark/results/2026-11-14-sparse-followup/).
The [evidence guide](../benchmark/results/2026-11-14-sparse-followup/README.md)
describes restoration and audit reproduction. The large target archive is split
into eight bounded-size files. Its manifest records the exact part order,
whole-archive digest and every member digest; the restoration helper verifies
all 372 members before writing them. Other archive manifests similarly record
complete membership and hashes. Normal-collector JSON is stored losslessly as
gzip with its uncompressed digest.

| Remote checkpoint | Preserved stage |
|---|---|
| `032ef42` | Scope and measurement plan |
| `521a31f` | Frozen heap source, focused tests and separate QR screen |
| `4b450b3` | Rejected QR audits and frozen heap preparation |
| `27f6592` | Complete native/portable gates and physical qualification |
| `74cf8bd` | Full target and small-control raw evidence |
| `b8a5aef` | Complete CAD raw screen and dense-fill reliability evidence |

This report and final audits are added after those checkpoints. The source and
test trees above remain the validation boundary.

Real-browser coverage remains unverified: the earlier local Chromium attempt
failed at startup because its process-singleton socket was denied, before any
assertions. Node JS/Wasm passes are recorded separately. At final review,
[PR CI run 43607276690](https://github.com/CrispStrobe/dart_csp/actions/runs/43607276690)
for `b8a5aef` and the frozen-source run `43605974397` were still queued, with no
conclusion. Current platform status should be read from PR #10 and subsequent
main CI. No package release is included.

Future experiments can investigate the control tails or dense coupled
convergence with their own frozen sources and cohorts. This pass leaves no
unfinished measurement or unpreserved raw cohort.

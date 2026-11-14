# Packed sparse factor storage: results and retention — 2026-11-14

> Follow-up attribution: the coupled-500 cases decline the sparse work cap
> before allocating packed factors. Both their favorable and unfavorable
> timing changes are collateral observations, not direct packed-factor
> execution effects. The original measurements below remain unchanged.
> See the [tradeoff follow-up](performance-tradeoff-followup-2026-11-14.md)
> for the stronger controls and next optimization candidate.

## Decision

Retain source `4325386e689566a903309accd66aca3ced1159f7`. Sparse LDLT now
stores all numeric factor columns in one invocation-owned typed buffer. A
2,000-column numeric attempt replaces 2,000 factor buffers and their enclosing
list with one factor buffer, while keeping the same numeric entry count and
resource caps. The cached symbolic shape adds `columns + 1` immutable offsets.
This is a source-level allocation-count improvement; total allocated bytes and
GC behavior were not measured.

Two target improvements repeat for both median and p95 in all three matched
process pairs: warm 2,000-coordinate 2D ladders improve **11.60% / 9.31%**,
and cold coupled-500 in 3D improves **7.36% / 6.71%**. The complete native and
portable correctness gates pass, and physical coordinates and solver-work
counters remain exactly equal across all 548 before/after operation pairs, including
the separate failed dense reliability control.

The decision accepts measured costs. Cold coupled-500 in 2D has aggregate median
**+9.65%**, with slower medians in all three pairs; cold 2,000-coordinate 2D ladders have median/p95
**+4.27% / +23.45%**. Below-threshold and CAD/QR controls contain further
regressions, including AOT rank-5x4 median **+86.32% per 256-call batch** and
JIT cold-linkage p95 **+4.35%**. These are retained explicitly below. Unknown
application workload weights prevent a single net-speedup claim. The existing
coupled-2,000 convergence limit remains unresolved.

The [independent code review](sparse-storage-code-review-2026-11-14.md) and
[independent retention review](sparse-storage-retention-review-2026-11-14.md)
support this selective tradeoff. No previously rejected experiment is restored,
and no package release is included.

## Exact source and behavior

| Identity | Value |
|---|---|
| Baseline main | `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9` |
| Frozen candidate | `4325386e689566a903309accd66aca3ced1159f7` |
| Candidate library tree | `35febd175893ecd82ff2b8569eded77f6717f905` |
| Candidate test tree | `ee07f871e438a0672ec2d7b088c981eac41c5b12` |
| Dart | 3.14.0 stable |
| Dart executable SHA256 | `6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b` |
| Dependency lock SHA256 | `a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a` |

The sole library delta is
[`lib/src/geometry/sparse_ldlt.dart`](../lib/src/geometry/sparse_ldlt.dart).
Cached factor-index maps now store absolute packed-buffer positions; diagonal,
normalization and triangular-solve accesses use column start offsets. Numeric
factors remain private to each solve. There is no shared numeric scratch or
new public option.

The change preserves assembly additions and duplicate-column cross terms,
division and Schur-update order, triangular reductions, nonfinite checks,
cancellation polling, structural admission, iteration budgets, CSR mutation
checks and refinement behavior. Six new regressions exercise irregular filled
columns at 19 and 257 coordinates, empty-column diagonal slots, changing warm
numeric values/damping, earlier result snapshots, and nested/cancelled solves
at every warm callback boundary. Existing zero-column and exact-cap coverage
remains in the suite.

## Validation and physical outcomes

| Gate | Result |
|---|---:|
| Repository formatting | 229 Dart files; zero changes |
| Fatal-info analysis | Clean |
| Native suite | 1,872 tests passed |
| Node JavaScript corpus | 551 tests passed |
| Node WebAssembly corpus | 551 tests passed |
| Comparison-harness Python suite | 48 tests passed |
| Performance/collector Python suite | 8 tests passed |

All 63 focused sparse tests also pass. The new regression file is included in
both the 52-file portable corpus and the browser CI selection. The seven full
gates preserve exact commands, stdout/stderr, exit codes and before/after source
hashes. Later evidence/documentation commits do not change the frozen library
or tests.

| Physical cohort | Jobs | Checked operations | Independently verified outcome |
|---|---:|---:|---|
| Candidate qualification | 36 | 108 | 96 feasible accepted; 12 contradictions rejected |
| Large paired targets | 72 | 648 | All accepted; 324 exact coordinate/work pairs |
| Below-threshold controls | 48 | 432 | All accepted; 216 exact coordinate/work pairs |
| Coupled-2,000 reliability | 8 | 16 | All `iterationLimit`; 8 exact coordinate/work pairs |

Counts include 36, 144 and 96 warmups in the first three cohorts, respectively.
Independent audits replay physical acceptance from raw coordinates and reconcile
source/build identities, requests, process inventories, complete native outputs,
terminal gates and all seven solver-work counters. There are no missing
operations, timeouts, nonzero exits, adapter exceptions or oracle disagreements.
The supplementary preparation check binds every archived tracked source file
directly to its declared Git blob.

The coupled-2,000 fixture is constructed feasible but remains unqualified on
both revisions. Every successful-solve timing ratio for that cohort is null.
Its failed-attempt timings are retained as diagnostics and are not speedups or
evidence of infeasibility.

## Large target timings

All timed solver processes run sequentially on CPU 0 after builds and correctness
gates finish; independent analysis runs separately on CPU 8. CPU affinity does
not imply exclusive ownership of the host. Each variant/fixture/engine/lifecycle
has three alternating process pairs, two warmups and seven measured operations.
Values below are medians of process percentiles, in milliseconds per complete
build/update, solve and extraction operation. Positive percentages mean slower.

| Fixture / engine / lifecycle | p50 before → after (ms) | p50 change | p95 change |
|---|---:|---:|---:|
| Ladder 500 / 2D / cold | 9.293 → 7.457 | -19.76% | -37.93% |
| Ladder 500 / 2D / warm | 5.393 → 5.308 | -1.58% | -6.03% |
| Ladder 500 / 3D / cold | 16.741 → 16.459 | -1.68% | +5.68% |
| Ladder 500 / 3D / warm | 12.589 → 12.171 | -3.32% | -0.70% |
| Ladder 2,000 / 2D / cold | 34.031 → 35.484 | +4.27% | +23.45% |
| Ladder 2,000 / 2D / warm | 26.504 → 23.428 | -11.60% | -9.31% |
| Ladder 2,000 / 3D / cold | 91.730 → 89.980 | -1.91% | -25.80% |
| Ladder 2,000 / 3D / warm | 67.512 → 66.129 | -2.05% | -3.01% |
| Coupled 500 / 2D / cold | 62.650 → 68.693 | +9.65% | +19.68% |
| Coupled 500 / 2D / warm | 57.748 → 57.648 | -0.17% | +9.20% |
| Coupled 500 / 3D / cold | 104.781 → 97.069 | -7.36% | -6.71% |
| Coupled 500 / 3D / warm | 88.446 → 86.687 | -1.99% | -19.43% |

Ten of twelve aggregate medians are lower, with no workload weighting. The two
repeatable p50/p95 gains identified above hold in every matched pair. The larger
cold 500-coordinate 2D aggregate gain holds in two pairs. Cold coupled-500 2D
median worsens in every pair. Some aggregate directions differ from the majority
of paired directions; the
[complete target review](../benchmark/results/2026-11-14-sparse-storage/targets-review.md)
and timing-details JSON retain both views and every unrounded process value.

With seven samples, each process p95 is its largest sample; the displayed
aggregate p95 is the median of three maxima. These are screening observations,
not stable tail bounds or statistical-significance claims. Equal numerical
work does not identify the cause of elapsed-time changes.

## Small controls and CAD/QR costs

The 100-coordinate fixtures use the same three-round design and fall below the
adaptive sparse-direct threshold. Their timings are collateral observations.
Five of eight aggregate medians are lower. Warm 2D ladder median/p95 increases
**25.09% / 25.65%**, each slower in two pairs; cold 2D ladder median rises
**3.48%**, slower in all three. Cold 3D ladder median/p95 rises
**5.90% / 5.73%**. Warm coupled-100 3D p95 rises **24.92%**. All eight rows
and paired directions remain in the
[small-control review](../benchmark/results/2026-11-14-sparse-storage/small-controls-review.md).

The separate QR/plate/linkage screen has **36 JIT/AOT reports**, three alternating
pairs, 20 warmups and 101 measured samples. Independent fixture, process and
source audits pass 58,278 assertions, 1,010 process checks and 53 source checks.
All **24,240 samples or batches**, **9,696 CAD work records** and **4,848 exact
paired work records** reconcile. Of 40 aggregate medians, 27 are lower, one is
equal and twelve are higher. This count is not an application-wide speedup.

All three AOT plate medians are lower. JIT linkage angle-edit and coupler-edit
medians improve **7.42% / 10.93%** in every pair. However, retained costs include:

| Control statistic | Before → after | Change | Slower / equal / faster pairs |
|---|---:|---:|---:|
| AOT rank 5x4 p50, per 256-call batch | 95 → 177 µs | +86.32% | 2 / 1 / 0 |
| AOT rank 5x4 p95, per 256-call batch | 138 → 370 µs | +168.12% | 2 / 0 / 1 |
| AOT rank 17x8 p95, per 256-call batch | 511 → 625 µs | +22.31% | 3 / 0 / 0 |
| AOT rank 4x8 p50, per 256-call batch | 163 → 164 µs | +0.61% | 3 / 0 / 0 |
| AOT rank 4x8 p95, per 256-call batch | 204 → 223 µs | +9.31% | 3 / 0 / 0 |
| JIT cold linkage p95 | 6,003 → 6,264 µs | +4.35% | 3 / 0 / 0 |
| AOT cold linkage p99 | 3,753 → 6,253 µs | +66.61% | 2 / 0 / 1 |
| AOT rejected-angle p99 | 268 → 542 µs | +102.24% | 2 / 0 / 1 |

AOT rank-5x4 p99 also rises **142.61%**, and JIT rejected-angle p99 rises
**64.23%**, both slower in two pairs. The
[complete 40-row control review](../benchmark/results/2026-11-14-sparse-storage/cad-controls/independent-review.md)
retains favorable and adverse p50/p95/p99 statistics and every pair direction.
Plate p99 is harness-reported; QR/linkage p99 is derived. At 101 samples each
process p99 is its second-largest sample, which still does not establish a
stable tail bound.

These controls preserve harness numerical checks and work counters, not complete
geometry/QR matrices for another physical replay. The collector records source,
lock, harness and package configuration hashes plus compile/run linkage, but does
not hash its SDK or generated AOT executable bytes. The stronger binary
provenance of the sparse adapter preparation is separate. Neither cohort
establishes GC/compiler causality or total allocated-byte savings.

## Remote checkpoints and reproducibility

The user requested direct incremental saves to remote `main`. Completed stages
were saved before subsequent work; all original raw observations remain intact.

| Main checkpoint | Preserved stage |
|---|---|
| `aa7604b` | Scope, candidate and measurement plan |
| `4325386` | Reviewed packed source and six regressions |
| `9b92a54` | Frozen builds, runtime/source inputs and complete qualification |
| `55cd91d` | Complete native, portable and harness validation |
| `1921b1d` | All target and small-control raw results |
| `e3ee66b` | Independent timing audits and dense reliability failures |

The subsequent completion checkpoint preserves the full CAD screen, final
retention decision and evidence verification. The qualified library and test
trees above remain unchanged. See the
[evidence and replay guide](../benchmark/results/2026-11-14-sparse-storage/README.md)
for archive membership, split-part digests and exact audit commands.

Temporary AOT executables are omitted from the persisted preparation archive;
their hashes, build logs and source/compiler inputs remain. Actual binary-byte
checks were performed while the binaries were available. Replaying those
supplementary checks requires the recorded binaries/runtime; rebuilding is a
new run, not reproduction of historical timings. Source/archive/physical audits
can inspect the retained raw evidence independently.

Local real-browser execution was not performed. Node JS/Wasm passes remain
distinct from browser coverage; inspect the latest main GitHub Actions run for
platform status. No convergence or platform claim is inferred from a queued CI
run. There is no unfinished measurement cohort in this pass.

# CSP correctness and performance audit — 2026-11-14

## Outcome and retention decision

This pass repairs retained-input ownership and integer-bound correctness,
removes range enumeration from integer-assumption classification, and reduces
temporary mesh-validation collections. It changes six production files and
adds 27 regression tests. The integration vehicle is
[PR #6](https://github.com/CrispStrobe/dart_csp/pull/6); all independent source
branches, intermediate checkpoints, measurements and reviews are retained.

The complete candidate improves all 16 measured plate/linkage median timings
across JIT and AOT, with 46 of 48 individual process-case median comparisons
faster. For a single variable with one million possible integer values, the
complete eight-operation assumption/solve batches improve by more than 99.9%
under AOT. These are fixture-specific results, not a universal solver speedup.

**There are retained performance costs.** Linkage angle-edit p95 worsens in
every paired process in both runtimes. Several cold-build and assembly controls
also regress, and the isolated mesh experiment has worse AOT plate tails.
The separate GC diagnostic shows more frequent collections and larger sums of
reported collection durations, despite smaller typical individual events.
The full tables and limitations below preserve those results without filtering.

The correctness fixes are retained because stable assumption/declaration
meaning and sound bound complements are required. The mesh change is retained
for its bounded representation and consistent typical-time improvement in
the isolated experiment (48/48 faster median comparisons), with the tail
tradeoff explicit. No claim is made that this resolves all previously observed
tail latency. The earlier rejected numerical scratch experiments remain
reverted; this pass does not reinstate them.

## Starting point, source identity and remote preservation

Before implementation, all remote branches and PR heads were fetched. All nine
existing remote work-branch heads were already ancestors of main
`5dc27dc0b297683d47e94ade2b4ca22ed530d429`. PRs #1–#5 were merged and none were
open. PR #1/#2 used squash commits `ce10138`/`b87babf`; their original head
commits therefore need not be ancestors. PR #3–#5 heads were included by
ancestry. The exact starting refs are in the
[inventory](../benchmark/results/2026-11-14-inventory.json).

| Boundary | Commit / identity |
|---|---|
| Reconciled baseline | `5dc27dc0b297683d47e94ade2b4ca22ed530d429` |
| Baseline library tree | `ef99105a9d7787925ae245cf10adbd040df1ad62` |
| Frozen validated candidate | `f575399865675a9f8f71fbc9570b4b905b6ee09d` |
| Candidate library tree | `6111175debbc7a3ae99631e274f24f16b28d2f25` |
| Candidate test tree | `1895cef8cf8470ffef4ac813e9ee780c77e4fee1` |
| Full CAD / assumption measurement checkpoint | `957e3dcd73e7cc40d5b03256ed69403cc2899ed2` |
| Controls / GC measurement checkpoint | `a5b8d189543cc5a80817d1166925b3577e7e5813` |
| Isolated mesh comparison | `6b39dbf` → `9190a8c` |

The later full-candidate measurement checkpoints have the exact same library
tree as the frozen source. Later changes add evidence, independent Python
auditors and documentation. Library, test, benchmark Dart, example and CI
source remain identical to the validated checkpoint. The isolated comparison
changes only `lib/src/cad/kernel.dart` in production; both sides already have
the profile-capture repair.

Small coherent source checkpoints were saved throughout on
`fix/incremental-assumptions-2026-11-14`,
`fix/geometry-snapshots-2026-11-14`, and `fix/cad-validation-2026-11-14`.
The combined source is on `audit/csp-performance-2026-11-14`; subsequent
measurement checkpoints are on `bench/csp-audit-evidence-2026-11-14`.
Git trees were compared after authenticated remote writes. Branch history is
preserved, with no force push, branch deletion or release.

## Correctness findings and repairs

| Area | Reproduced gap | Retained repair and boundary |
|---|---|---|
| Incremental assumptions | Mutating a caller Set or predicate scope changed an active assumption's meaning while retaining its clause-provenance identity | Snapshot the collection at posting. Preserve the Set's comparison policy on predicate dispatch. Captured element/callback state remains application-owned. |
| Compact integer domains | Posting an integer assumption scanned every range member just to determine that the domain was integral | Recognize the final `IntRangeDomain` type directly. Other domain classification retains its previous behavior. |
| LCG bound complements | At the JavaScript 2^53 precision boundary, rounding could make `v + 1 == v`, so a bound and its supposed negation overlapped | Use adjacent representable integer values when ordinary ±1 does not advance. Native unrepresentable endpoint complements throw explicitly instead of wrapping. |
| Compiled geometric declarations | Mutable public getters and lists could change tolerance, scope or layout after compilation | Capture and revalidate parameter/residual metadata. Keep the private final AD implementation and its specialized dispatch. |
| CAD document state | Caller parameter/revision maps or overridden topology-reference getters could alter retained meaning or remove obligations | Capture initial parameter values/revisions and private semantic-reference declarations. |
| Empty feature graph | The first unchanged/no-op return bypassed required-reference checks | Reject missing mandatory references before returning initial success. |
| Reference extrusion | Changing profile getters could pass validation using one radius and build analytic geometry using another | Capture profile and hole scalars once. Preserve rejection of invalid dimensions before touching the hole list. |

Concrete regressions include a residual of 1 being accepted after a callback
changed its tolerance from 1e-8 to 2, and extrusion retaining an analytic hole
radius of 100 while its accepted volume had been calculated using radius 1.
The tests also cover old-state immutability, rejected transactions, empty
graphs, scope arity, comparator/identity sets, bound involution and learning,
and all three execution runtimes.

Mesh validation replaces two temporary triangle lists with scalar indices and
general neighbor sets with two neighbor slots plus a persistent overflow flag.
It retains custom point operations, area arithmetic, validation issue order,
edge incidence, link degree/connectivity, disconnected-cycle rejection and
positive-volume checks. An independent full-neighbor graph oracle checks 120
deterministic triangle complexes; a separate duplicate-triangle regression
covers all six corner permutations.

Independent source review caught two compatibility details in early candidates:
copying with an ordinary Set constructor lost custom comparison semantics,
and reading holes too early changed invalid-dimension short-circuit behavior.
Both were corrected before the source freeze, with focused regressions and
their intermediate history preserved.

### Remaining API and scope limits

Snapshots are shallow. Mutable element objects, callback captures, evaluator
behavior and custom manifold behavior still belong to the caller. Manifold
dimensions must remain fixed. Retract/repost an assumption or recompile a graph
when its intended behavior changes; copying declaration metadata cannot freeze
arbitrary executable code.

A pre-existing `assumeInSet` limitation remains: a nonempty all-integer Set on
an integer domain posts equality atoms for its **enumerated members**. A
custom integer Set whose `contains` relation admits other representatives does
not get that relation from atomic dispatch. For example, absolute-value
equality can treat `1` and `-1` as the same member, but atomic dispatch still
posts `x == 1`. Use an explicitly snapshotted `assumePredicate` for that
membership relation. The [ownership and membership guide](incremental-assumptions.md)
gives a runnable example and describes the performance tradeoff. This is an
explicit remaining restriction, not a claim that every custom Set behavior
has been fixed.

The inclusive AtomLe/AtomGe representation also cannot express a complement
past native integer endpoints; explicit negation throws `UnsupportedError`.
Tautological endpoint constraints still solve without needing such negation.
Complements operate on integers representable by the current runtime; this
does not add arbitrary precision or recover values already rounded by JavaScript.
The reference CAD kernel remains limited to its documented supported shapes;
this audit does not add general solid boolean operations.

## Measured gains and costs

The complete candidate's AOT plate medians improve 20.0–21.7%; aggregate p95
improves 23.7–28.8%. Linkage cold-build and coupler-edit medians improve 17.3%
and 18.2%. These are fresh comparisons against the reconciled baseline, not
comparisons of numbers collected during different previous sessions.

For the million-value compact range, AOT equality / inequality / singleton-set membership
batches fall from 34,591 / 34,668 / 34,704 µs to 29 / 34 / 31 µs. Each sample
contains eight complete operations, each constructing a one-variable model and
wrapper, posting an assumption and solving. Result retention and statistics
snapshots are inside the timer; independent assertions and work aggregation
are outside it. This is one variable with a large compact domain, not a
million-variable problem. The removed range-classification scan explains the
algorithmic improvement on this fixture. These are fresh-wrapper cold solves,
not `solveWarm`/learned-clause reuse or large/multi-value membership workloads.

The following costs constrain the retention decision:

- **Linkage tails:** final retained-angle p95 increases 20.1% JIT and 9.9% AOT,
  with all three pairs worse in each runtime. JIT placement-only p95 increases
  10.8%, also in all three pairs.
- **Isolated mesh tails:** AOT plate cold/profile p95 increases 38.1% / 9.2%,
  each with two worse pairs and one better pair. Favorable combined-candidate
  plate tails do not erase this isolated result.
- **Small assumption controls:** JIT explicit-100 inequality and membership
  medians increase 7.7% / 9.8% in all three pairs; membership p95 increases
  13.0% in all three. AOT explicit-100 aggregate medians are unchanged.
- **Cold numerical/CAD controls:** AOT nonlinear cold median/p95 increases
  6.6% / 15.7%; transactional CAD workspace cold increases 7.3% / 8.6% and
  warm increases 4.4% / 9.1%. Each of those AOT measures is worse in all three
  process pairs. Snapshot/validation costs are retained for correctness;
  the combined timings do not isolate which change causes each regression.
- **Assembly and graph controls:** AOT assembly pose median/p95 increases
  4.3% / 40.5%, both worse in all three pairs. JIT 10,000-feature graph cold
  p95 increases 54.1%, with two worse pairs, despite a 3.3% median improvement.
- **Other mixed results:** JIT 1,000-value range inequality p95 increases
  42.8%; JIT nonlinear warm p95 increases 17.5%. All remaining rows, including
  flat or zero-resolution measurements, are retained below.

There are 18 normal-summary rows with a p50 or p95 regression in all three
process pairs, counting all four cohorts. They remain in the independent
review; favorable medians were not used to discard them. Even the complete
candidate's AOT plate profile p95 worsens 3.25% in one pair while its aggregate
improves. No statistical significance or latency-service-level claim is made.

## Separate GC diagnostics

These are medians of three **whole-process** values for each fixture/runtime,
collected separately with verbose GC logging. They are not the normal elapsed
timings used above or below.

| Runtime / fixture | Scavenge count before → after | Sum of reported Scavenge durations, ms | Median new-generation capacity-before, reported MB | Sum of rounded new-generation occupancy reduction, reported MB |
|---|---:|---:|---:|---:|
| JIT plate | 78 → 178 | 30.0 → 49.2 | 32 → 8 | 2,277.7 → 1,343.8 |
| JIT linkage | 555 → 935 | 165.9 → 215.9 | 32 → 8 | 12,037.4 → 7,282.6 |
| AOT plate | 79 → 199 | 29.2 → 40.8 | 32 → 8 | 2,332.6 → 1,510.8 |
| AOT linkage | 316 → 709 | 102.0 → 149.9 | 32 → 8 | 9,796.1 → 5,547.2 |

Scavenge counts and sums of reported Scavenge durations increase in all twelve
process pairs. The median reported individual event duration falls from 0.3
to 0.2 ms in every pair. These are rounded event medians; a candidate AOT
linkage event reaches 22.6 ms, so individual events are not uniformly shorter.
Capacity medians are taken across Scavenge events within each process, not
weighted by time. Each baseline process grows through capacity values
2 → 8 → 32 reported MB, while each candidate reaches 8 MB and stays there.

The rounded occupancy-reduction proxy sums printed new-generation used-before
minus used-after for Scavenge events. It includes reclaimed **and promoted**
space and does not measure allocated bytes. Its process medians decrease
35.2–43.4% across the four comparisons. The observations are consistent with
more frequent collection of a smaller new generation, but do not establish
why capacity changed or explain an individual operation's tail latency.

Events cover setup, warmups, measured operations, independent checks and JSON
serialization. Rounded event durations may describe overlapping GC phases;
their sums are not total stop-the-world pause time. No per-operation GC
attribution, allocation-byte reduction, peak-memory reduction or lower total
GC-cost claim follows. Instrumented elapsed times are preserved for inspection
but never substituted for normal timing results.

The independent parser reconciles all 9,216 GC rows (9,107 main-isolate and
109 service-isolate), with zero dropped/unparsed event rows. It also checks
24 runs, four AOT compilation records, the SDK record, 28,800 instrumented
timing samples and 14,400 exact paired work-record comparisons. All 1,095
checks pass. See the [GC audit](../benchmark/results/2026-11-14-gc-audit.json)
and [diagnostic summary](../benchmark/results/2026-11-14-cad-gc-summary.json).

## Validation and evidence limits

| Gate | Observed result |
|---|---|
| Full unfiltered native suite | 1,789 tests passed; 127 test files in the frozen discovery inventory |
| JavaScript under Node | 453 tests passed; 44 explicitly selected files |
| WebAssembly under Node | 453 tests passed; the same 44 selected files |
| Fatal-info static analysis | Passed |
| Formatting | 214 Dart files; zero changes |
| Independent validation/archive review | 323 checks passed; commands, source, dependency lock and log hashes reconcile |
| Independent normal-measurement review | 120 reports and all 86 summary rows reconcile; no findings |
| Independent GC review | 1,095 checks passed; no findings |
| Local Chromium | Blocked before tests: process-singleton socket denied; zero tests ran |

The six new regression files are included in both portable Node corpora and
the real-browser smoke job, expanding that browser job from four to ten files.
The full browser suite retains its separate scheduled/manual scope.

The previous main workflow
[43516383046](https://github.com/CrispStrobe/dart_csp/actions/runs/43516383046)
completed with all 17 active jobs successful, including its four-file browser
smoke corpus. That is baseline coverage. At final report preparation, the new
frozen-source run
[43560094716](https://github.com/CrispStrobe/dart_csp/actions/runs/43560094716)
has passed all six Windows/macOS stable/beta/dev jobs; ten Linux/browser/other
jobs remain queued. Skipped benchmark/full-browser jobs are not counted as
passing. The final integration run has its own status on PR #6/main. Passing
Node tests and prior-main browser results do not establish new-source browser
coverage.

The native expanded concurrent log does not print a complete per-file execution
manifest; 127 is the checked-in default-discovery inventory. The unfiltered
command and 1,789 successful test increments agree. Both portable commands
explicitly list all 44 files. Full commands, dependency-lock contents,
timestamps and hashes are retained in the
[validation record](../benchmark/results/2026-11-14-validation.json) and its
linked log archive.

## Measurement method and reproduction

All cohorts use Dart 3.14.0 stable on Linux x64 in a shared, unpinned container.
Fresh before/after processes run sequentially; revision order alternates by
round. There are three rounds per runtime and revision, with AOT compilation
outside measured sections. No sample or process was removed, and no cohort
was repeated to obtain more favorable numbers.

| Normal cohort | Reports | Summary rows | Sampling |
|---|---:|---:|---|
| Isolated mesh | 24 | 16 | 300 measured operations, 30 warmups per case/process |
| Complete CAD candidate | 24 | 16 | 300 measured operations, 30 warmups per case/process |
| Incremental assumptions | 12 | 18 | 51 measured batches, 10 warmups; eight complete operations per batch |
| Numerical/CAD/graph controls | 60 | 36 | Legacy fixed 25 samples/5 warmups; assembly 40/5; graph explicitly 25/5 |

Tables report the median of three per-process p50 values and, separately, the
median of three per-process p95 values. They are not pooled percentiles.
CAD's 300-sample p50 uses the upper middle sample; p95/p99 use nearest-rank
indices. The incremental harness uses the arithmetic middle for even counts
(its measured count here is odd). A zero denominator is recorded as null,
shown as “—” below. Sub-microsecond or very small values are constrained by
timer resolution.

Identical benchmark and imported-example bytes were checked before/after.
The baseline receives only the common `cad.dart` and new
`incremental_assumptions.dart` harness overlays, with no library changes.
All compared roots use dependency-lock SHA-256
`a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a`.
Source tree/diff identities, harness hashes, exact argv, timestamps, physical
oracle outcomes and counters are retained in each raw report.

The independent normal review reconstructs 67,908 exposed raw timing samples,
63,108 aligned work records, 31,554 exact paired work-record comparisons,
72 plate p99 values and 66 paired final-counter snapshots. The 24 legacy
assembly distributions expose summary percentiles without raw samples, so
those percentiles cannot be independently reconstructed. Full coordinates are
not serialized: physical oracle completion is established by the pass records
and reviewed harness control flow, not independent replay from coordinates.
Neither independent review reran the timing workloads.

To reproduce, create before/after worktrees at the identities above, restore
the recorded dependency lock in each, run `dart pub get`, and copy the two
common harness overlays into the baseline. Use the same SDK for both roots.
Set `DART` to its executable path; do not change source between paired runs.
The commands below write fresh files in a separate `repro` directory.

```bash
python3 tool/compare_performance.py --before ../dart_csp_before --after . \
  --dart "$DART" --benchmarks cad cad_linkage --rounds 3 \
  --samples 300 --warmups 30 --output repro/final-cad.json

python3 tool/compare_performance.py --before ../dart_csp_before --after . \
  --dart "$DART" --benchmarks incremental_assumptions --rounds 3 \
  --samples 51 --warmups 10 --output repro/incremental.json

python3 tool/compare_performance.py --before ../dart_csp_before --after . \
  --dart "$DART" --benchmarks geometry_nonlinear cad_workspace \
  geometry_coupled cad_instances cad_graph --rounds 3 --samples 25 \
  --warmups 5 --output repro/controls.json

python3 tool/profile_cad_gc.py --before ../dart_csp_before --after . \
  --dart "$DART" --rounds 3 --samples 300 --warmups 30 \
  --output repro/cad-gc.json.gz

python3 tool/summarize_performance.py repro/final-cad.json \
  --output repro/final-cad-summary.json
python3 tool/audit_cad_measurements.py repro/final-cad.json \
  repro/final-cad-summary.json --before ../dart_csp_before --after . \
  --output repro/final-cad-audit.json
python3 tool/audit_gc_independent.py repro/cad-gc.json.gz \
  --before ../dart_csp_before --after . --output repro/gc-audit.json
```

Use the same comparison command with the isolated before/after worktrees for
the mesh-only experiment. Use `audit_incremental_measurements.py` for the
assumption cohort after summarizing it; use `audit_cad_measurements.py` for
controls. Raw files were losslessly gzip-compressed for storage; the auditors
accept those compressed files. The evidence index links every saved dataset,
summary, audit and log archive with SHA-256 hashes.

## Complete normal measurement tables

All times below are **microseconds**. Assumption rows are per **eight-operation
batch**; all other rows are per named complete operation. “Worse pairs” shows
the number of paired processes with increased p50 / p95 out of three. Positive
changes are regressions. These tables contain all 86 rows without selection.

### Complete candidate: plate and linkage

[Raw reports](../benchmark/results/2026-11-14-final-cad-paired.json.gz) · [Summary](../benchmark/results/2026-11-14-final-cad-summary.json) · [Audit](../benchmark/results/2026-11-14-final-cad-audit.json)

#### JIT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| Plate cold build | 916 → 690 | -24.7% | 1,321 → 1,305 | -1.2% | 0 / 1 |
| Plate profile edit | 885 → 680 | -23.2% | 1,359 → 1,297 | -4.6% | 0 / 0 |
| Plate thickness edit | 753 → 544 | -27.8% | 1,097 → 861 | -21.5% | 0 / 0 |
| Linkage cold build | 2,189 → 1,795 | -18.0% | 2,970 → 2,665 | -10.3% | 0 / 0 |
| Linkage retained angle | 267 → 258 | -3.4% | 388 → 466 | +20.1% | 0 / 3 |
| Linkage coupler length | 742 → 611 | -17.7% | 1,071 → 878 | -18.0% | 0 / 0 |
| Linkage placement only | 160 → 154 | -3.7% | 222 → 246 | +10.8% | 0 / 3 |
| Linkage rejected edit | 247 → 230 | -6.9% | 491 → 357 | -27.3% | 0 / 0 |

#### AOT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| Plate cold build | 850 → 680 | -20.0% | 1,302 → 971 | -25.4% | 0 / 0 |
| Plate profile edit | 875 → 697 | -20.3% | 1,299 → 991 | -23.7% | 0 / 1 |
| Plate thickness edit | 793 → 621 | -21.7% | 1,243 → 885 | -28.8% | 0 / 0 |
| Linkage cold build | 2,089 → 1,728 | -17.3% | 2,579 → 2,205 | -14.5% | 0 / 0 |
| Linkage retained angle | 185 → 175 | -5.4% | 243 → 267 | +9.9% | 0 / 3 |
| Linkage coupler length | 669 → 547 | -18.2% | 966 → 790 | -18.2% | 0 / 0 |
| Linkage placement only | 110 → 104 | -5.5% | 151 → 145 | -4.0% | 0 / 1 |
| Linkage rejected edit | 166 → 157 | -5.4% | 228 → 207 | -9.2% | 0 / 1 |

### Complete candidate: incremental assumptions

[Raw reports](../benchmark/results/2026-11-14-incremental-paired.json.gz) · [Summary](../benchmark/results/2026-11-14-incremental-summary.json) · [Audit](../benchmark/results/2026-11-14-incremental-audit.json)

#### JIT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| `explicit_100` · `equals` | 367 → 387 | +5.4% | 692 → 696 | +0.6% | 2 / 2 |
| `explicit_100` · `not_equals` | 274 → 295 | +7.7% | 666 → 675 | +1.4% | 3 / 2 |
| `explicit_100` · `in_set` | 214 → 235 | +9.8% | 562 → 635 | +13.0% | 3 / 3 |
| `range_1000` · `equals` | 357 → 361 | +1.1% | 2,466 → 2,013 | -18.4% | 1 / 0 |
| `range_1000` · `not_equals` | 211 → 203 | -3.8% | 479 → 684 | +42.8% | 1 / 2 |
| `range_1000` · `in_set` | 190 → 175 | -7.9% | 763 → 553 | -27.5% | 0 / 0 |
| `range_1000000` · `equals` | 20,189 → 97 | -99.5% | 20,954 → 325 | -98.4% | 0 / 0 |
| `range_1000000` · `not_equals` | 20,170 → 124 | -99.4% | 21,299 → 379 | -98.2% | 0 / 0 |
| `range_1000000` · `in_set` | 20,149 → 99 | -99.5% | 23,461 → 374 | -98.4% | 0 / 0 |

#### AOT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| `explicit_100` · `equals` | 53 → 53 | +0.0% | 208 → 191 | -8.2% | 1 / 1 |
| `explicit_100` · `not_equals` | 58 → 58 | +0.0% | 123 → 121 | -1.6% | 1 / 0 |
| `explicit_100` · `in_set` | 54 → 54 | +0.0% | 113 → 117 | +3.5% | 1 / 2 |
| `range_1000` · `equals` | 172 → 140 | -18.6% | 242 → 176 | -27.3% | 0 / 0 |
| `range_1000` · `not_equals` | 179 → 149 | -16.8% | 260 → 226 | -13.1% | 0 / 0 |
| `range_1000` · `in_set` | 175 → 143 | -18.3% | 275 → 202 | -26.5% | 0 / 0 |
| `range_1000000` · `equals` | 34,591 → 29 | -99.9% | 37,097 → 96 | -99.7% | 0 / 0 |
| `range_1000000` · `not_equals` | 34,668 → 34 | -99.9% | 38,858 → 101 | -99.7% | 0 / 0 |
| `range_1000000` · `in_set` | 34,704 → 31 | -99.9% | 36,147 → 96 | -99.7% | 0 / 0 |

### Complete candidate: numerical, CAD and graph controls

[Raw reports](../benchmark/results/2026-11-14-controls-paired.json.gz) · [Summary](../benchmark/results/2026-11-14-controls-summary.json) · [Audit](../benchmark/results/2026-11-14-controls-audit.json)

#### JIT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| Nonlinear geometry cold | 690 → 696 | +0.9% | 1,681 → 1,365 | -18.8% | 2 / 1 |
| Nonlinear geometry warm | 482 → 398 | -17.4% | 841 → 988 | +17.5% | 0 / 2 |
| CAD workspace cold | 1,416 → 1,492 | +5.4% | 2,143 → 2,183 | +1.9% | 3 / 1 |
| CAD workspace warm | 740 → 667 | -9.9% | 1,364 → 1,449 | +6.2% | 1 / 2 |
| Coupled geometry cold | 1,355 → 1,388 | +2.4% | 2,276 → 1,887 | -17.1% | 3 / 2 |
| Coupled geometry warm | 679 → 588 | -13.4% | 1,782 → 1,204 | -32.4% | 1 / 2 |
| Assembly cold build | 1,445 → 1,355 | -6.2% | 3,117 → 2,694 | -13.6% | 1 / 0 |
| Assembly pose edit | 384 → 368 | -4.2% | 671 → 630 | -6.1% | 0 / 1 |
| Graph 1,000 · cold build regenerate | 919 → 971 | +5.7% | 2,579 → 2,586 | +0.3% | 3 / 2 |
| Graph 1,000 · sparse edit | 19 → 20 | +5.3% | 74 → 73 | -1.4% | 2 / 2 |
| Graph 1,000 · no op edit | 3 → 3 | +0.0% | 15 → 16 | +6.7% | 2 / 2 |
| Graph 1,000 · unused parameter edit | 5 → 5 | +0.0% | 10 → 17 | +70.0% | 1 / 1 |
| Graph 1,000 · rejected edit | 9 → 10 | +11.1% | 19 → 19 | +0.0% | 3 / 1 |
| Graph 10,000 · cold build regenerate | 8,824 → 8,530 | -3.3% | 13,916 → 21,449 | +54.1% | 1 / 2 |
| Graph 10,000 · sparse edit | 45 → 42 | -6.7% | 87 → 113 | +29.9% | 1 / 3 |
| Graph 10,000 · no op edit | 10 → 9 | -10.0% | 28 → 30 | +7.1% | 1 / 2 |
| Graph 10,000 · unused parameter edit | 12 → 10 | -16.7% | 29 → 26 | -10.3% | 1 / 1 |
| Graph 10,000 · rejected edit | 14 → 13 | -7.1% | 22 → 22 | +0.0% | 1 / 1 |

#### AOT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| Nonlinear geometry cold | 61 → 65 | +6.6% | 140 → 162 | +15.7% | 3 / 3 |
| Nonlinear geometry warm | 45 → 46 | +2.2% | 111 → 115 | +3.6% | 2 / 1 |
| CAD workspace cold | 820 → 880 | +7.3% | 962 → 1,045 | +8.6% | 3 / 3 |
| CAD workspace warm | 551 → 575 | +4.4% | 625 → 682 | +9.1% | 3 / 3 |
| Coupled geometry cold | 813 → 828 | +1.8% | 861 → 944 | +9.6% | 2 / 2 |
| Coupled geometry warm | 544 → 551 | +1.3% | 590 → 639 | +8.3% | 2 / 3 |
| Assembly cold build | 385 → 402 | +4.4% | 622 → 490 | -21.2% | 2 / 1 |
| Assembly pose edit | 46 → 48 | +4.3% | 79 → 111 | +40.5% | 3 / 3 |
| Graph 1,000 · cold build regenerate | 371 → 361 | -2.7% | 628 → 640 | +1.9% | 0 / 2 |
| Graph 1,000 · sparse edit | 4 → 4 | +0.0% | 5 → 7 | +40.0% | 0 / 2 |
| Graph 1,000 · no op edit | 0 → 0 | — | 0 → 0 | — | 0 / 0 |
| Graph 1,000 · unused parameter edit | 0 → 0 | — | 1 → 1 | +0.0% | 0 / 0 |
| Graph 1,000 · rejected edit | 1 → 1 | +0.0% | 2 → 2 | +0.0% | 0 / 0 |
| Graph 10,000 · cold build regenerate | 7,319 → 6,470 | -11.6% | 11,787 → 11,252 | -4.5% | 2 / 1 |
| Graph 10,000 · sparse edit | 12 → 12 | +0.0% | 46 → 19 | -58.7% | 1 / 1 |
| Graph 10,000 · no op edit | 2 → 2 | +0.0% | 4 → 5 | +25.0% | 1 / 2 |
| Graph 10,000 · unused parameter edit | 2 → 2 | +0.0% | 4 → 5 | +25.0% | 0 / 1 |
| Graph 10,000 · rejected edit | 3 → 3 | +0.0% | 6 → 9 | +50.0% | 1 / 1 |

### Isolated mesh candidate

[Raw reports](../benchmark/results/2026-11-14-mesh-isolated-paired.json.gz) · [Summary](../benchmark/results/2026-11-14-mesh-isolated-summary.json) · [Audit](../benchmark/results/2026-11-14-mesh-isolated-audit.json)

#### JIT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| Plate cold build | 923 → 730 | -20.9% | 1,420 → 1,327 | -6.5% | 0 / 1 |
| Plate profile edit | 903 → 668 | -26.0% | 1,399 → 1,311 | -6.3% | 0 / 0 |
| Plate thickness edit | 757 → 561 | -25.9% | 1,149 → 925 | -19.5% | 0 / 0 |
| Linkage cold build | 2,232 → 1,803 | -19.2% | 3,469 → 2,311 | -33.4% | 0 / 1 |
| Linkage retained angle | 280 → 257 | -8.2% | 452 → 465 | +2.9% | 0 / 3 |
| Linkage coupler length | 751 → 605 | -19.4% | 1,195 → 887 | -25.8% | 0 / 0 |
| Linkage placement only | 164 → 151 | -7.9% | 271 → 253 | -6.6% | 0 / 1 |
| Linkage rejected edit | 256 → 228 | -10.9% | 546 → 402 | -26.4% | 0 / 0 |

#### AOT

| Operation | p50 before → after | Δ p50 | p95 before → after | Δ p95 | Worse pairs p50 / p95 |
|---|---:|---:|---:|---:|---:|
| Plate cold build | 848 → 652 | -23.1% | 1,274 → 1,760 | +38.1% | 0 / 2 |
| Plate profile edit | 866 → 674 | -22.2% | 1,326 → 1,448 | +9.2% | 0 / 2 |
| Plate thickness edit | 787 → 598 | -24.0% | 1,216 → 1,041 | -14.4% | 0 / 1 |
| Linkage cold build | 2,057 → 1,746 | -15.1% | 2,579 → 2,136 | -17.2% | 0 / 0 |
| Linkage retained angle | 187 → 175 | -6.4% | 260 → 333 | +28.1% | 0 / 3 |
| Linkage coupler length | 659 → 549 | -16.7% | 1,002 → 864 | -13.8% | 0 / 0 |
| Linkage placement only | 112 → 102 | -8.9% | 154 → 154 | +0.0% | 0 / 2 |
| Linkage rejected edit | 166 → 156 | -6.0% | 219 → 223 | +1.8% | 0 / 3 |


## Evidence and next concrete work

- [Evidence index and checksums](../benchmark/results/2026-11-14-evidence.json)
- [Independent review of all normal cohorts](../benchmark/results/2026-11-14-independent-normal-review.json)
- [Independent validation review](../benchmark/results/2026-11-14-independent-validation-review.json)
- [GC audit](../benchmark/results/2026-11-14-gc-audit.json)
- [Current handover](../HANDOVER.md)

The next performance work should target the repeated linkage/assembly tail
costs and AOT numerical/document cold-build costs with per-operation allocation
and GC attribution. An explicit custom-membership option could address the
remaining integer-Set contract without silently replacing compact atomic
pruning with arbitrary predicate enumeration. Complete the queued browser and
Linux CI gates before making new-platform coverage claims. Any new candidate
should preserve the current source/evidence boundary and compare all affected
controls, including its adverse results.

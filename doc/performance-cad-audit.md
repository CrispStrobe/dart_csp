# Audit of the latest CSP and parametric 3D CAD branch

Date: 2026-11-13. Baseline: `1bb0d281654fb21eb11e7d01f25aa5fc294aafe9`,
the latest head of draft PR #3 at the start of this audit. The measured audit
revision is `7d70e4fc3e5f6afeb32495087d434162b95d2dd3`; its library implementation
matches the preceding `1421144` checkpoint. The later change only makes one
JavaScript regression compatible with strict static analysis and records gates.

## Outcome

The audit adds event-swept scheduling, less repeated QR norm work, corrected
fractional rectangle propagation, stable drag objectives, and an executable
parametric 3D assembly path. It builds on the existing geometric solver and
feature graph instead of treating a finite-domain CSP as a general solid kernel.

The original feature branch and main remain intact. Work is preserved in
`audit/performance-cad-2026-11-13`, with [draft PR #4](https://github.com/CrispStrobe/dart_csp/pull/4)
for review. PRs #1 and #2 were already merged into main and are included through
PR #3. The [audit-only comparison](https://github.com/CrispStrobe/dart_csp/compare/1bb0d281654fb21eb11e7d01f25aa5fc294aafe9...audit/performance-cad-2026-11-13)
isolates this pass from the earlier work. Nothing has been merged or released.

## Findings and repairs

| Finding on the starting source or during review | Consequence | Repair and regression evidence |
|---|---|---|
| Cumulative profiles visited every occupied integer time tick and every candidate-duration tick | Large durations and compact domains could require work proportional to the horizon or worse | Sorted endpoint profiles, forbidden start intervals, direct compact bounds and cooperative budget polling; billion-unit tests and independent scheduling oracles |
| `diffN` silently returned from its propagator on fractional coordinates, while tagged constraints bypassed the leaf predicate | Overlapping fractional rectangles could be emitted as valid; compiled sessions rejected valid fractional layouts | Numeric endpoint propagation and tag-aware numeric validation; 80 independent layout oracles, all consistency modes, LCG and restored sessions |
| QR recomputed every trailing column norm at every pivot | Redundant dense norm scans in cold rank diagnostics and small dense solves | Guarded norm downdates, exact pivot norms and refreshes near cancellation/rank cutoffs; independent rank, linear solve and projection oracles |
| Dense QR and dense nullspace projection ignored their iteration budget | A zero linear budget still completed a solve | Explicit QR-pivot budget enforcement and rollback tests |
| Mutable preference-option/target subclasses survived into a running solve | A callback could change tolerance to infinity and report `targetReached` with an unmet target | Snapshot and validate the complete objective before callbacks or asynchronous yields |
| Mesh volume used tetrahedra measured from the world origin | A unit tetrahedron translated to `1e8` reported about 33 million instead of `1/6` | Reference-vertex tetrahedra and compensated summation; independent translated-volume/winding regressions |
| World placement could round distinct coordinates together, or change depth 3 to 4 while still claiming chord error 0.01 | A successfully exported/committed object could have collapsed or distorted geometry | Explicit world linear tolerances, placement error bounds, checked topology materialization and honest added mesh error |
| Scheduling endpoint, demand and energetic arithmetic could overflow or round | An impossible large-coordinate schedule could be accepted | Checked portable integer envelope with explicit unsupported outcomes and exact boundary-product checks |

The unchanged baseline passed all 1,635 native tests. The new regressions and
capability coverage increase that to 1,702. The first five
fractional-layout regressions independently failed on the baseline before the
repair. Extreme integer/double and CAD precision cases found in independent
review were added before final source validation.

## Work removed and retained limits

### Cumulative scheduling

A compulsory task contributes two events. Sorting those events produces at
most `2*n - 1` time segments; storage no longer grows with duration magnitude.
An overloaded segment `[a,b)` excludes integer task starts in
`[a-duration+1,b-1]`. The task's own compulsory use is subtracted before testing
its candidates. Complete-assignment validation uses the same endpoint principle
without a time-tick map.

Explicit domains and compact ranges of at most 4,096 values receive exact
interior filtering. Larger compact ranges use sound prefix/suffix contraction:
unsupported interior starts may remain until a later bound or decision exposes
them. That is deliberately weaker propagation, not an equivalence claim about
intermediate domains. Complete feasible solution sets and returned assignments
are checked independently. Existing energetic reasoning is still enabled by
default; the timing fixture disables it to isolate the swept time-table path.

Scheduling arithmetic must remain in the portable exact-integer envelope
`[-(2^53-1), 2^53-1]`, including relevant intermediate endpoints, horizon
differences, accumulated demand and enabled energetic quantities. Some extreme
but individually feasible inputs are conservatively rejected. `UnsupportedError`
requests different units/a smaller horizon; it never means the schedule was
proved infeasible. Ordinary inputs stay on machine integers; near-boundary
products are checked with `BigInt`. See
[propagation-performance.md](propagation-performance.md) for the full contract.

### Geometric numerical work

The QR implementation retains estimated trailing-column norms. It recomputes
the selected pivot norm exactly, refreshes when subtracting nearly equal squared
norms would lose information, and refreshes all remaining columns before a rank
cutoff. The mathematical failure mode and guarded-update criterion are discussed
in [LAPACK Working Note 176](https://www.netlib.org/lapack/lawnspdf/lawn176.pdf).
This is an independent implementation; no external solver implementation was
copied or linked.

| Unit-triangular chain | Old full-rescan entry count | New complete-norm entry visits | Reduction |
|---|---:|---:|---:|
| 48 coordinates | 38,024 | 3,432 | 91.0% |
| 72 coordinates | 127,020 | 7,740 | 93.9% |
| 96 coordinates | 299,536 | 13,776 | 95.4% |

These are norm-work counters, not percentages of total solving time.
Householder transformations remain cubic. New counters describe full norm
computations, visited entries and constant-time downdates precisely. Physical
residual checks, rank tolerances and required/preference priorities are retained.
Residual-only automatic differentiation also shares empty derivative storage;
active derivative arrays still own independent mutable data.

Dense linear and projection budgets now count QR pivots. Sparse backends count
their own iterations. Numerical options, preference settings and target values,
weights and coordinate scales are captured at run start. Local convergence and
local rank remain local numerical diagnostics, not global feasibility or
optimality certificates.

### Fractional rectangle coordinates

The normal numeric path computes actual endpoint extrema and applies the
original `x + width <= otherX` comparisons. Integer bound atoms cannot explain
fractional coordinate decisions, so unsupported mixed-domain LCG reasons remain
opaque. Native integer endpoint overflow is rejected explicitly.

Beyond the conservative sweep envelope, equal-valued integer and double starts
can have different rounded ends, and mixed comparisons can themselves round.
Those cases use exact fixed-pair checks and leave remaining alternatives to
search. This preserves the original represented-number predicate, with weaker
propagation near precision limits. It is not a certificate of exact-real
geometric separation at arbitrary scale.

## Executable parametric 3D CAD

Run:

```sh
dart run example/parametric_assembly.dart
dart run benchmark/cad_instances.dart
```

The example constructs one rectangular plate with a circular through-hole and
places two instances perpendicular to each other. The geometric solver applies
axis mates and height/clearance equations to the upright pose. Both occurrences
share one analytic body and one local display mesh.

Changing `gap` rebuilds only `assembly` and `upright`. It preserves body/mesh
object identity and does not run extrusion or tessellation again. A width,
height or thickness edit follows the declared dependencies and rebuilds affected
geometry. Invalid gap and downstream failures preserve the exact last committed
document, including parameters, solved coordinates, references and outputs.

The additive experimental API provides:

- `CadRigidTransform`: immutable translation/quaternion placement, axis-angle
  construction, composition/inverse, renderer matrices and conservative bounds.
- `CadBodyInstance`: shared analytic prototypes with world-space semantic
  vertices, line/circle edges and plane/cylinder faces.
- `CadPlacementExpression` and `CadFeatureNode.instance`: parameter-driven
  placement without reconstructing a local part.
- `constrainedGeometryFeature` and `CadFeatureNode.instanceFromPose`: physically
  checked 3D solver results connected to feature transactions.
- Checked world topology and mesh materialization, with configurable error
  budgets and a returned chord-error allowance that includes placement error.

Default world linear tolerance is `1e-7` model units. Exact large translations
can remain usable, while an unrepresentable placement is rejected. A coarse
mesh export can explicitly allow more error and reports that error honestly.
Generic transform constructors normalize finite nonzero quaternions; solved-pose
conversion requires a valid unit quaternion from the geometric solver.

The executable solid subset is still **rectangular profiles with circular
through-holes, positive extrusion, and rigid occurrences/assemblies**. This
two-plate example is a multi-solid assembly, not a fused or filleted bracket.
General profiles, revolution, booleans, fillets, shells, collision checking and
production topology repair require another kernel/backend. The guide documents
the exact subset and capability boundaries: [parametric-cad.md](parametric-cad.md).

## Validation

| Gate | Result |
|---|---|
| Unmodified latest-PR baseline native suite | 1,635 passed |
| Updated full native suite | 1,702 passed |
| Expanded JavaScript / Node corpus | 366 passed |
| Expanded WebAssembly / Node corpus | 366 passed |
| Full static analysis with fatal infos | No issues |
| Formatting | All 193 Dart files pass |
| Final strict-typing-only test adjustment | Nine affected tests rerun on native, JavaScript and WebAssembly |
| Real Chromium | Blocked before tests by denied process-singleton socket; not a passed gate |
| GitHub Actions | Check draft PR #4 for current status; no queued job is counted as passed |

The full suites exercised library source `1421144`; the subsequent `7d70e4f`
changes only a test helper's static typing and the checkpoint record. Analysis
and the affected nine tests were checked again after that adjustment. Node was
v24.22.1 and Dart was 3.14.0. Browser-native integration remains a separate CI gate.

Independent review covered scheduling events and LCG reasons, arithmetic
boundaries, QR/AD, preference snapshots, and CAD transform/transaction/precision
boundaries. Additional independent probes checked 3,000 known-rank comparisons,
400 Rodrigues/inverse transforms, 3,200 transformed AABB corners, and 1,600
materialized points against an exact-rational represented-matrix error oracle.
They supplement the committed regression suite; they are not timing samples or
proofs for arbitrary third-party geometry.

## Performance measurements

### Method and evidence

The main comparison contains **84 harness reports**: seven harnesses, two source
revisions, JIT and AOT, and three fresh processes per combination. Runs were
sequential, alternating revision order each round. Before is `1bb0d28`; after is
`7d70e4f`. Both library trees were clean, and corresponding benchmark harnesses
had matching hashes. All independent result checks passed. No outliers were
removed and no main runs were substituted after inspecting their results.

The host was a shared, unpinned Linux x64 container reporting an AMD EPYC 9V74
80-Core Processor and nine available logical CPUs. Dart was 3.14.0. AOT
compilation was outside all timers. These are controlled comparisons within
this environment, not estimates for a particular user's hardware or statistical
confidence intervals.

Each displayed value is the **median of three process-reported p50 values**;
tail summaries use the median of three process-reported p95 values. They are
not pooled percentiles. Matching, GCC, cumulative and QR use 5 warmups and 25
samples per process. The existing independent-circle and CAD fixtures retain
3 warmups/25 samples; the coupled geometry fixture uses 5/25. A cold path means
fresh model construction within a running process, not process startup or
compilation. Matching, GCC and cumulative prepared rows measure **12-query
batches**; other rows measure one operation. Cumulative fixtures disable
energetic reasoning to isolate the time-table path.

Committed evidence:

- [Paired raw reports](../benchmark/results/2026-11-13-latest-audit-paired.json),
  including source/harness hashes, separate process distributions and the raw
  samples exposed by the QR/coupled harnesses. Other harnesses report
  distributions rather than retaining every individual sample.
- [Complete paired summary](../benchmark/results/2026-11-13-latest-audit-summary.json),
  with every process p50/p95, aggregate, elapsed change and ratio.
- [Current assembly and billion-duration scaling](../benchmark/results/2026-11-13-latest-audit-scaling.json):
  12 additional after-only reports.
- [Volume-only isolation](../benchmark/results/2026-11-13-cad-volume-isolation.json):
  12 separate paired reports used to investigate the standard CAD regression.

### Latest-branch comparison

All times below are milliseconds. Positive elapsed change is slower. The
range-scheduling improvements are specific to fixtures that previously visited
many time ticks; they are not general CSP speedup factors.

| Fixture | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| Matching, 32 variables (12 queries) | 9.370 → 9.034 | 8.641 → 8.952 | +3.6% |
| Matching, 64 variables (12 queries) | 29.790 → 29.247 | 44.779 → 44.972 | +0.4% |
| GCC, 32 variables (12 queries) | 5.072 → 4.870 | 4.569 → 4.632 | +1.4% |
| GCC, 64 variables (12 queries) | 10.009 → 9.953 | 15.706 → 16.212 | +3.2% |
| Cumulative, 8 fixed tasks, duration 1,000 | 0.642 → 0.178 | 0.367 → 0.015 | -95.9% |
| Cumulative, 2 range tasks, duration 1,000 | 23.990 → 0.580 | 17.421 → 0.076 | -99.6% |
| Cumulative, prepared, duration 1,000 (12 queries) | 6.926 → 1.313 | 4.905 → 0.126 | -97.4% |
| Cumulative, 8 fixed tasks, duration 3,000 | 2.621 → 0.056 | 2.877 → 0.007 | -99.8% |
| Cumulative, 2 range tasks, duration 3,000 | 132.802 → 0.323 | 113.060 → 0.071 | -99.9% |
| Cumulative, prepared, duration 3,000 (12 queries) | 36.868 → 0.712 | 24.699 → 0.126 | -99.5% |
| QR chain, 48 coordinates | 0.187 → 0.141 | 0.162 → 0.119 | -26.5% |
| QR chain, 72 coordinates | 0.601 → 0.359 | 0.599 → 0.387 | -35.4% |
| QR chain, 96 coordinates | 1.462 → 0.802 | 1.369 → 0.842 | -38.5% |
| 100 independent circles, cold | 4.206 → 3.099 | 1.879 → 1.792 | -4.6% |
| One circle edit | 0.316 → 0.271 | 0.121 → 0.119 | -1.7% |
| Coupled 24-point 3D fixture, cold | 2.208 → 1.951 | 1.566 → 1.314 | -16.1% |
| Coupled 24-point fixture, pitch edit | 0.852 → 0.840 | 0.852 → 0.852 | +0.0% |
| Existing plate CAD, cold | 2.157 → 2.272 | 1.478 → 1.628 | +10.1% |
| Existing plate CAD, profile edit | 2.268 → 2.079 | 1.516 → 1.649 | +8.8% |
| Existing plate CAD, thickness edit | 1.498 → 1.714 | 1.438 → 1.431 | -0.5% |

Scheduling has the clearest structural gain: profile storage and compulsory
load construction now depend on task endpoints, not duration magnitude. The
3,000-unit range fixture falls from 113.060 to 0.071 ms AOT (about 1,592 times
less elapsed time in this fixture). The 12-query prepared batch falls from
24.699 to 0.126 ms. Bounds-only filtering on large compact ranges is part of
this design; it remains sound but can defer interior pruning to later search.

The isolated QR chain shows 26.5% to 38.5% lower AOT medians, alongside the
91.0% to 95.4% reduction in full norm-entry visits above. Cold construction of
the coupled 24-point 3D fixture improves by 16.1% AOT; its retained pitch edit
is unchanged. The fixture has linear dimensional equations, so it is not a
proxy for all nonlinear mechanisms or 3D sketches.

Matching and GCC are effectively neutral at the scale of these runs: AOT
medians range from 0.4% to 3.6% slower, with small JIT median improvements.
The existing plate CAD cold and profile-edit medians regress by **10.1% and
8.8% AOT**. Thickness edits are approximately flat. Those regressions remain
part of the result, even though the new assembly path is substantially cheaper
when it can reuse a prototype.

Tails did not improve uniformly. Median process p95 for matching-64 JIT rises
from 42.120 to 50.163 ms; QR-72 JIT from 0.805 to 1.052 ms; independent-circle
cold JIT from 10.517 to 16.741 ms. Coupled warm-edit p95 rises from 1.807 to
2.012 ms JIT and 0.951 to 1.056 ms AOT. Standard CAD cold AOT p95 rises from
1.770 to 2.073 ms. These results do not establish a universal interactive frame
budget or guaranteed tail latency.

### Investigating the standard CAD regression

The separate isolation comparison uses the original baseline against
`8e14aa5`, whose only library change is stable, compensated mesh volume. It
retains the same CAD harness, three alternating rounds and both runtimes.

| Volume-only comparison | AOT before | AOT after | Elapsed change |
|---|---:|---:|---:|
| Fresh plate build | 1.608 ms | 1.499 ms | -6.8% |
| Profile edit | 1.670 ms | 1.563 ms | -6.4% |
| Thickness edit | 1.517 ms | 1.442 ms | -4.9% |

This does not support blaming the volume repair for the regression in the main
comparison. It also does not isolate the remaining changes from shared-host
variation. The plate sketch factors very small matrices (roughly 4 to 12 rows
and 4 to 8 columns), where norm-cache setup and extra cancellation checks can
cost more than the small number of scans saved. A bounded exact-norm path for
tiny matrices is a reasonable follow-up experiment, but this pass does not
claim that QR caused the regression or introduce an unmeasured special case.
The original slower measurements are retained unchanged.

### New assembly and large-duration capability

The new assembly benchmark runs three fresh processes per runtime, each with
5 warmup pairs and 40 measured pairs, alternating fresh-build/edit order.
Both columns use the **current** implementation; this is a cold-versus-reuse
comparison, not a speedup against a previous release.

| Two-plate assembly | JIT p50 | JIT p95 | AOT p50 | AOT p95 |
|---|---:|---:|---:|---:|
| Fresh construction and regeneration | 1.859 ms | 3.934 ms | 0.730 ms | 1.290 ms |
| Retained gap/pose edit | 0.600 ms | 0.974 ms | 0.084 ms | 0.134 ms |

The AOT retained edit is about 8.7 times cheaper than constructing that
assembly again. Across all edits of the retained document there is exactly
one extrusion and one tessellation. The rebuilt feature list is always
`['assembly', 'upright']`. Independent coordinate, normal, volume and object
identity checks pass; geometry reuse is verified, not inferred from timing.

After-only cumulative runs also exercise duration **1,000,000,000**, with the
range fixture spanning a 2,000,000,000-unit horizon. Median process p50 is
0.014 ms AOT for eight fixed tasks, 0.010 ms for the two-task range solve, and
0.127 ms for a prepared 12-query batch. These establish covered large-duration
execution without a time-tick map. They are not paired speedups; the old
implementation was not run at that horizon. The ordinary and billion-duration
fixtures have different warmup/cross-fixture effects, so their sub-millisecond
timings should not be interpreted as larger inputs being intrinsically faster.

### Reproduction

Create separate worktrees at the exact before/after revisions, run `dart pub
get` in each, and copy the after version of `benchmark/cumulative.dart`,
`benchmark/geometry_qr.dart` and their unchanged `benchmark/sampling.dart`
helper into the baseline benchmark directory. This keeps the new harnesses
identical without changing baseline library code. Run the comparison from the
after checkout, supplying absolute worktree and Dart executable paths:

```sh
python3 tool/compare_performance.py \
  --before /absolute/path/to/before \
  --after /absolute/path/to/after \
  --dart /absolute/path/to/dart \
  --benchmarks matching gcc cumulative geometry_qr geometry geometry_coupled cad \
  --rounds 3 --samples 25 --warmups 5 \
  --cumulative-durations 1000,3000 \
  --output benchmark/results/reproduced-paired.json
```

For the volume-only diagnostic, use `1bb0d28` and `8e14aa5` as the worktrees
and select `--benchmarks cad`. Use the newer comparison tool from this branch.
For current-only capability checks, run each command in three fresh processes
and also compile/run its AOT executable; compilation belongs outside timers:

```sh
dart run benchmark/cad_instances.dart
dart run benchmark/cumulative.dart --samples=25 --warmups=5 --durations=1000000000
```

For a fresh browser check on a host where Chromium can start, follow the
portable test commands and corpus in `tool/performance_cad_tests.txt` and the
existing CI workflows. A Node JavaScript or Wasm pass does not replace browser
integration.

## Next performance priorities

1. **Safe numerical workspace forks for CAD candidates.** Transactional
   constrained features currently create isolated numerical workspaces seeded
   from committed coordinates. A checked fork/checkpoint API could retain more
   Jacobian/rank storage across edits while guaranteeing rollback. Direct
   geometry sessions already retain more state than feature candidates.
2. **Scale the feature graph.** Dirty detection scans the whole DAG and copies
   output/revision maps. Reverse dependency indexes, iterative topological
   compilation and persistent/copy-on-write state would reduce costs for large
   assemblies and deep feature histories.
3. **Profile realistic coupled nonlinear CAD systems.** The existing coupled
   chain is a linear dimensional fixture. Closed-loop mechanisms, changing
   tangencies, near-singular poses, redundant/contradictory dimensions and
   realistic 3D assemblies should drive the next sparse linear algebra and
   diagnostic decisions. Do not infer a universal frame budget from one chain.
4. **Integrate a production solid kernel behind the existing contract.** A
   native/worker/Wasm adapter should provide the missing solid operations,
   stable operation provenance, healing/validation, cancellation and explicit
   tolerances. Keep constraint solving, analytic geometry and display meshes
   separate so pose edits remain cheap.

The complete plan and checkpoint sequence are in
[PERFORMANCE_CAD_AUDIT.md](../PERFORMANCE_CAD_AUDIT.md). Earlier performance claims
remain historical evidence in [performance-optimization-followup.md](performance-optimization-followup.md)
and are not relabeled as measurements from this pass.

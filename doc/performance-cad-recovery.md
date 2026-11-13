# CSP/CAD recovery and allocation follow-up

Date: 2026-11-13. Recovered baseline:
`2777886a5a1da0f0b5f9d402ecca62cf788ccb3d`. Validated and measured candidate:
`03c75b938a23fa9b7819f61b9225026cbb7223ea`.

## Recovery and integration

The interrupted chat transcript was older than the last remote checkpoint.
The previous continuation had completed its articulated solid linkage,
isolated numerical forks, indexed feature histories, tiny-QR rollback and
paired results. Those changes and their original evidence are preserved in
[the previous report](performance-cad-continuation.md).

The recovery fetched every active branch and all four PR heads. Main is an
ancestor of PR #3, and PR #3 is an ancestor of PR #4. The old PR #1 and #2 heads
are tree-identical to their squash-merged main commits. No additional source
merge or conflict resolution was necessary. This pass continues the integrated
audit branch and draft PR #4, preserving separate remote checkpoints for its
three work streams. See [the recovery plan](../PERFORMANCE_CAD_RECOVERY.md).

## Changes

### Cold feature-graph setup

The previous report measured a substantial construction cost for the indexed
graph, despite much faster retained edits. This pass reduces redundant work
without changing its dependency model:

- Leaf nodes need no DFS frame or active-path entry, while iterative traversal
  still supports deep histories and checks cycles in dependent nodes.
- A zero- or one-entry dependency list cannot contain a duplicate; only longer
  lists need a temporary duplicate-check set.
- Features without parameter dependencies share one immutable empty parameter
  scope per regeneration, with the correct candidate global revision.
- Scoped parameter maps and edited maps are freshly owned; read-only views
  retain them without a second copy. A feature context similarly owns its
  private input map, or uses the constant empty map.

All public declaration inputs are still snapshotted unconditionally. No
overridable `runtimeType` or document getter is used to bypass capture. Dirty
closure ordering, chunked historical state, rollback and structural work
counters are unchanged. A new retained-context regression checks old values,
revisions, inputs and previous outputs through successful, unused, rejected
and retried edits, including mutation rejection and scope restrictions.

### Deferred geometry-fork scratch

Each geometry workspace now separates retained physical residual/rank state
from lazily created writable numerical scratch. Forks copy their pending and
committed coordinates, dirty state and actual raw/normalized residuals. Exact
rank caches and diagnostics remain immutable shared records. A component
allocates its own Jacobian, argument copies, derivative buffers and trial
vectors when it first needs evaluation or preference work.

No writable scratch is borrowed from a parent or sibling. Clean components
can publish their validated nonzero residuals without creating scratch. The
existing failed/stale/cancelled/reentrant/preference cases remain covered; a
new regression interleaves asynchronous siblings, forks a clean descendant
twice, then edits and drags it without changing either ancestor or sibling.

This remains an allocation tradeoff. Coordinates and residual snapshots are
still copied across every fork; results and retained historical sessions still
consume memory. CAD adapters deliberately revalidate every component, so they
allocate scratch for all components they evaluate. First-use allocation now
occurs inside the solve's elapsed-time budget. Whole fork-plus-solve operations
and cold build-plus-solve controls are therefore measured, rather than claiming
a gain from moving work outside a timer.

### Articulated-solid timing coverage

`benchmark/cad_linkage.dart` uses the existing four-bar assembly of four
two-hole bar solids, four meshes and four occurrences. Its five timed paths
cover construction, retained angle edits, selective coupler-length edits,
layer-only placement changes and downstream rejection after a valid solve.
It records every raw elapsed sample with aligned per-sample graph, solver,
extrusion and tessellation counters.

Independent trigonometric/circle-intersection, pivot/axis/normal and analytic
and exported-mesh-volume checks run after timing. Exact prototype identities,
rebuilt feature sequences, historical snapshots and rollback are checked too.
Successful recovery after rejection is outside the rejection timer. The
rejected fixture has 18 features; ordinary cases have 17. This is a regular
configuration on the positive assembly branch, with layered reference solids;
it does not add collision detection or broaden the reference kernel's scope.

`benchmark/geometry_fork.dart` measures one fork, a clean fork plus solve, a
one-component fork edit plus solve, and a retained direct edit over 100 and
1,000 independent 3D components. Coordinate and residual oracles explicitly
reject non-finite values, and every measured solve records physical work.
Forks always start from the original source, while the direct control alternates
between its own prior edited states. Their displacements are not identical.

## Validation

Candidate correctness and static gates ran on clean source `03c75b9`, with
Dart 3.14.0 and Node v24.22.1. The separate baseline compatibility checks are
identified in the table:

| Gate | Result |
|---|---|
| Full native suite | 1,758 tests passed across all 121 test files |
| Portable JavaScript / Node | 422 tests passed across all 38 corpus files |
| Portable WebAssembly / Node | 422 tests passed across all 38 corpus files |
| Fatal-info static analysis | No issues found |
| Formatting | 207 Dart files checked, zero changes |
| New harnesses on recovered baseline | Both independent check-only modes pass |
| Independent review | Graph ownership/order, workspace isolation and solid benchmark evidence reviewed; no blocking findings |

Commands, source/dependency hashes, test inventories, timestamps, counts and
log hashes are retained in the
[validation record](../benchmark/results/2026-11-13-recovery-validation.json).

Chromium was attempted on the recovered baseline with the normal four-file
CI browser command. It exited before any tests ran because the environment
denied its process-singleton socket (`Operation not permitted`). Zero tests
passed in that attempt; this is an environment blockage, not a browser pass.
The previous PR #3 CI run passed its browser job, but that older source does
not validate the current changes. CI on the candidate is
[run 43509092738](https://github.com/CrispStrobe/dart_csp/actions/runs/43509092738),
queued when measurement began.

## Paired measurement method

Seven identical-hash harnesses compare recovered `2777886` with candidate
`03c75b9`, using three fresh processes per revision/runtime, JIT and AOT,
sequential execution and alternating revision order. AOT compilation is outside
timers. Both revisions have clean library trees and the same dependency lock
hash; imported example dependencies are hashed too. Correctness runs finished
before timing began. Hardware is a shared, unpinned Linux container.

The graph, fork and solid-linkage harnesses use five warmups and 25 measured
samples; the existing CAD-workspace, coupled and nonlinear fixtures retain
their documented five/25 counts, and independent circles retain three/25.
Aggregates are medians of per-process p50/p95 values, not pooled percentiles.
All samples, processes, control results and regressions are retained.

### Complete results and reconciliation

The run completed **84 reports and 62 summary rows**. The
[compressed raw reports](../benchmark/results/2026-11-13-recovery-paired.json.gz)
expand byte-for-byte to the original JSON (SHA-256
`549c9600185197cb3bcf4d0489e092bfa9090f8cc2457dd0f0b1b55da91142d2`). The
[complete summary](../benchmark/results/2026-11-13-recovery-summary.json)
contains every process p50/p95 and aggregate, including tiny/no-op cases and
controls omitted from the focused tables below. The summarizer accepts either
plain JSON or `.json.gz` inputs.

Independent reconciliation checked all **372 process p50/p95 pairs**, **372
derived aggregate values**, **348 exposed distributions containing 8,700 raw
samples**, and **3,900 aligned work records**. All 1,950 paired before/after
work records match exactly. Every report completed its physical oracle checks.
The audit also checked all revision ordering, rounds, harness/dependency hashes
and frozen library bytes. The older independent-circle harness omits raw samples
for its 24 distributions; their reported values were reconciled, but those
percentiles cannot be independently recomputed from absent samples.

See the [measurement audit](../benchmark/results/2026-11-13-recovery-measurement-audit.json)
and [full validation/benchmark logs](../benchmark/results/2026-11-13-recovery-validation-logs.tar.gz).
The audit retains its original summary hash and records the packaged summary
hash separately: only the `source` filename changed from `.json` to `.json.gz`.
All measurement rows remain identical.
No samples, processes or measured regressions were removed or rerun to improve
the result.

### Targeted graph and fork results

Values are milliseconds and medians of the three process p50s. Positive elapsed
change is slower. Cold graph construction includes initial regeneration; it
does not include process startup or AOT compilation.

| Fixture | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| 1,000-feature cold graph | 2.390 → 1.756 | 0.784 → 0.565 | −27.9% |
| 10,000-feature cold graph | 18.092 → 13.511 | 14.108 → 11.342 | −19.6% |
| 1,000-feature four-feature edit | 0.046 → 0.042 | 0.008 → 0.007 | −12.5% |
| 10,000-feature four-feature edit | 0.056 → 0.059 | 0.023 → 0.022 | −4.3% |
| 100-component fork only | 0.176 → 0.034 | 0.108 → 0.011 | −89.8% |
| 100-component clean fork + solve | 0.719 → 0.286 | 0.224 → 0.091 | −59.4% |
| 100-component fork + one-component edit + solve | 0.815 → 0.495 | 0.269 → 0.105 | −61.0% |
| 1,000-component fork only | 0.495 → 0.125 | 0.612 → 0.124 | −79.7% |
| 1,000-component clean fork + solve | 1.336 → 0.975 | 1.526 → 0.983 | −35.6% |
| 1,000-component fork + one-component edit + solve | 1.450 → 1.038 | 1.609 → 0.995 | −38.2% |
| 1,000-component retained direct edit | 0.907 → 0.920 | 0.916 → 0.879 | −4.0% |

Cold graph p50 improves in every round at both sizes and under both runtimes.
The 10,000-feature JIT aggregate improves 25.3%. Its AOT cold gain reduces the
previously observed setup burden while preserving the indexed sparse-edit
behavior. Cross-run comparisons to older reports are not substituted for this
paired baseline.

The complete 1,000-component AOT fork/edit/solve improves in every paired round
(35.6%, 50.5%, 40.0%). Its 38.2% summary reduction survives including first-use
scratch allocation and the physical solve. JIT improves 28.4% in the summary,
with two improved rounds and one effectively flat round. The direct-edit
control has no corresponding fork allocation to eliminate. Work records
confirm exactly one solved component, 999 reused components and the same
physical/Jacobian/linear work before and after the sparse fork edit.

These are scoped reductions: the graph fixture uses scalar feature outputs,
and the fork fixture has many independent components. Neither result predicts
the same gain for a fully coupled assembly or thousands of complex solids.

### Articulated solids and numerical controls

| Fixture | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| Solid linkage cold build/solve/solids/meshes | 4.712 → 4.541 | 3.497 → 3.837 | **+9.7%** |
| Solid linkage retained angle edit | 0.755 → 0.760 | 0.324 → 0.332 | **+2.5%** |
| Solid linkage selective coupler-length edit | 1.928 → 1.724 | 1.086 → 1.157 | +6.5% |
| Solid linkage placement-only layer edit | 0.380 → 0.358 | 0.189 → 0.198 | +4.8% |
| Solid linkage downstream-rejected angle edit | 0.716 → 0.741 | 0.278 → 0.279 | +0.4% |
| CAD geometry feature cold build/solve | 2.616 → 2.109 | 1.439 → 1.331 | −7.5% |
| CAD geometry feature retained pitch edit | 1.124 → 1.050 | 0.896 → 0.855 | −4.6% |
| Direct coupled 24-point cold solve | 1.908 → 2.244 | 1.668 → 1.371 | −17.8% |
| Direct coupled 24-point retained edit | 0.905 → 0.917 | 1.070 → 0.926 | −13.5% |
| Nonlinear four-bar cold solve | 0.977 → 1.034 | 0.096 → 0.096 | 0.0% |
| Nonlinear four-bar retained angle edit | 0.590 → 0.631 | 0.066 → 0.070 | +6.1% |
| Independent-circle cold solve | 4.820 → 4.462 | 2.232 → 2.148 | −3.8% |
| Independent-circle retained edit | 0.387 → 0.393 | 0.145 → 0.135 | −6.9% |

Solid cold AOT is slower in all three paired rounds. Retained solid angle
edits are also slower in every round in both runtimes, despite the much larger
gain in the independent-component fork fixture. JIT nonlinear cold solves
regress in all three rounds. These are observed costs, not evidence of a
general CAD or nonlinear speedup.

Other directions are mixed. AOT coupler edits are slower in one paired round
and slightly faster in two; direct nonlinear AOT edits improve in one round
and worsen by two/four microseconds in the others. The 17.6% JIT coupled-cold
aggregate regression also has mixed paired directions. Some apparent gains,
including JIT CAD-workspace cold construction and AOT coupled solves, are
mixed by round too. A ratio of separately aggregated medians is not a median
of paired percentage changes. The combined-source comparison cannot assign
each secondary effect to one of the two implementation changes.

Exact work checks confirm that angle edits retain all four bodies and meshes,
coupler edits rebuild only that part, layer edits do no fresh solve or kernel
work, and rejected edits preserve the committed state. Physical work remains
equal across the paired revisions. The example still models a regular layered
four-bar assembly, without collision checking, pins or bearings.

### Tail latency and timer limits

Values below are milliseconds and medians of process p95s.

| Fixture | Before | After | Elapsed change |
|---|---:|---:|---:|
| 10,000-feature cold graph, JIT | 27.248 | 29.696 | **+9.0%** |
| 10,000-feature cold graph, AOT | 20.482 | 24.373 | **+19.0%** |
| Independent-circle cold solve, AOT | 3.272 | 4.401 | **+34.5%** |
| 100-component fork/edit/solve, AOT | 0.365 | 0.504 | **+38.1%** |
| Retained solid angle edit, JIT | 1.306 | 1.593 | **+22.0%** |
| 1,000-component fork/edit/solve, AOT | 2.360 | 1.779 | −24.6% |

Independent-circle cold AOT p95 worsens in all three paired rounds. Graph cold
p95 worsens in two rounds per runtime; the third AOT round reaches 38.435 ms
after the change, despite a lower median. Even the improved 1,000-component
fork p95 is not universal: its third paired round worsens slightly.

Short 25-sample p95 estimates on shared hardware do not establish a frame or
service-level latency bound. The 1,000-feature AOT no-op median quantizes from
one microsecond to zero; it is not a literal zero-cost operation or a usable
100% speedup claim. No workload weighting was established, so these results
are not combined into an overall percentage gain.

## Retained decision and remaining work

The graph and scratch changes are retained: their intended construction and
complete candidate-fork benefits repeat, and the correctness and isolation
gates pass. The realistic solid and tail costs remain visible in this report
and the complete dataset. A further optimization pass should isolate those
costs before changing additional solver/kernel algorithms. Browser/platform CI
is still a separate gate; no release or merge to main is included here.

## Reproduction

Use Dart 3.14.0 and the same dependency resolution for both source worktrees.
The validation record includes the dependency-lock SHA-256. Put the two new
harnesses (`geometry_fork.dart` and `cad_linkage.dart`) into the recovered
baseline unchanged; their imported examples already exist there. Keep library
trees at the exact commits above. The comparison script refuses differing
harness or imported-example hashes.

```sh
python3 tool/compare_performance.py \
  --before /path/to/recovered-2777886 \
  --after /path/to/candidate-03c75b9 \
  --dart /path/to/dart-sdk/bin/dart \
  --benchmarks cad_graph geometry_fork cad_linkage cad_workspace \
    geometry_coupled geometry_nonlinear geometry \
  --rounds 3 --samples 25 --warmups 5 \
  --output /path/to/recovery-paired.json

python3 tool/summarize_performance.py \
  benchmark/results/2026-11-13-recovery-paired.json.gz \
  --output /path/to/recovery-summary.json
```

The full native, Node JS/Wasm, static and browser-attempt commands are preserved
in the validation record. The complete logs archive includes those runs and
the sequential benchmark console output. Compressed raw reports were checked
to expand to the original bytes; parsing compressed and uncompressed reports
produces identical summary rows.

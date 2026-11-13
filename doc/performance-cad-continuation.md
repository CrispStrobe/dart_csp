# Continued CAD performance and nonlinear assembly work

Date: 2026-11-13. This pass starts at `3b5c4c4373fa0f08d50ff5d5902714cd09cdfc92`,
the completed previous audit on `audit/performance-cad-2026-11-13`. The final
validated and measured source is `3f042cd61c24720cc03c27a4e52a6d9919cabce7`.
It continues
in [draft PR #4](https://github.com/CrispStrobe/dart_csp/pull/4). The
[continuation-only comparison](https://github.com/CrispStrobe/dart_csp/compare/3b5c4c4373fa0f08d50ff5d5902714cd09cdfc92...audit/performance-cad-2026-11-13)
isolates these changes from the earlier scheduling, geometry and instance work.

## Changes and their purpose

### Transactional numerical candidates

`GeometrySolveSession.fork()` captures an idle session's pending and committed
coordinates, dirty components, local revision, diagnostic options and last
result. Each branch owns its writable values and scratch arrays. Immutable
compiled structure, diagnostic/result snapshots and private rank-cache records
are shared. Neither later edits nor a failed or stale solve can overwrite the
other branch's committed state. An active synchronous/asynchronous solve cannot
be forked because its workspace may contain a partial trial.

Clean components preserve their actual validated physical residuals, including
nonzero values inside tolerance. Dirty components and preference targets evaluate
fresh numerical derivatives before consuming candidate work arrays. Rank reuse
requires the existing exact numerical Jacobian and rank-option comparison.
Callbacks and custom manifolds still belong to the shared model; application
state captured by them is not cloned and still requires explicit invalidation.

The CAD constrained sketch and geometry adapters retain a session weakly keyed
by its successful output. The next regeneration forks the session associated
with the **previous committed output**. A rejected downstream solid, validation
or topology reference therefore cannot become the next numerical seed. Sharing
one feature declaration across documents does not share their numerical history.

Every CAD candidate marks all components dirty and physically revalidates them.
This preserves the adapter's existing behavior for callback-captured application
inputs, including inputs in components not connected to the edited dimension.
Only rank/diagnostic computation is reused after fresh numerical checks.

This is not zero-allocation or copy-on-write scratch reuse. Forks allocate fresh
scratch buffers and copy coordinate/residual state. Retaining historical output
objects also retains their associated sessions. The tradeoff is deliberate:
safe candidate isolation with reusable rank state, without speculative aliasing
of mutable numerical buffers. See [geometric-solver.md](geometric-solver.md) and
[parametric-cad.md](parametric-cad.md).

### Feature graph scaling

The graph compiles parameter-consumer and reverse dependency indexes. An edit
discovers only the affected closure, then evaluates it in the original stable
dependency-first order. Explicit DFS frames replace recursion at compilation,
allowing deep feature histories without consuming the process call stack.

Committed output/revision pairs use immutable chunks of 128 entries. A small
edit copies touched chunks and the shallow chunk directory; unchanged chunks
and immutable outputs remain shared. Public outputs and revision maps retain
read-only lookup/iteration behavior. Rejected candidates preserve the exact old
document state, and retained historical states cannot observe candidate writes.

A 4,097-feature regression changes two features: two scheduled nodes, one
traversed dependency edge, 129 prior entries copied and 33 directory references
copied. The suite retains 41 historical snapshots across 40 edits, checks a
20,000-deep reverse-listed history and compares 600 randomized DAG edits with
independent full recomputation.

Independent review found two ways user subclasses could invalidate a compiled
index: spoofing `runtimeType` to bypass node copying and overriding the public
document `features` getter used by the constructor. All node declarations are
now snapshotted, and compilation uses a private backing list. Dedicated
adversarial regressions cover both cases.

Total commit cost is not constant in document size: it still copies
`ceil(N / 128)` directory references, edited parameter maps and checks required
references. Compilation also builds extra indexes and declaration snapshots.
The [feature graph guide](cad-feature-graph.md) specifies the structural counters,
ordering, immutable Map contract and remaining costs.

### Tiny dense QR experiment rejected

The first candidate used exact scale-safe trailing-column norms for matrices
with at most 16 rows and 8 columns, avoiding cache allocation and downdate work
while sharing the existing Householder implementation. The full paired trial
did not support retaining it: AOT rank batches became 29.6% slower at 5x4,
35.1% slower at 8x4 and 36.9% slower at 16x8. The 4x8 rank batch improved 5.5%,
while AOT damped solve/projection were approximately flat. JIT also regressed
on most shapes, including a 63.0% slowdown in the damped solve batch.

The dispatch is removed. `numeric.dart` is restored byte-for-byte to the
previous audit source, retaining its guarded norm reuse, numerical validation,
budgets and cancellation. This pass does not claim a tiny-QR speedup or replace
the first measurements with selected favorable repeats. The complete
[108-report candidate trial](../benchmark/results/2026-11-13-continuation-qr-candidate-paired.json)
and [76-row summary](../benchmark/results/2026-11-13-continuation-qr-candidate-summary.json)
remain preserved. Final retained changes are measured in a separate paired run.

The useful new suite remains: 174 independently known-rank cases at scales
`1e-150`, `1` and `1e150`, 16x9 and 17x8 shapes, a larger 48x48 control,
independent damped solves, redundant nullspace projections, budgets and stops.
The benchmark includes actual CAD-sized shapes; its timings are operation
**batches**, generally 256 calls, while the 48x48 control uses eight.

## Nonlinear CAD capability and evidence

`example/nonlinear_linkage.dart` constructs a closed four-bar mechanism in a
tilted 3D workplane. Two fixed pivots, three link lengths, plane equations and
an editable signed crank angle constrain two moving points in one nonlinear
component. An independent ordinary-trigonometry/two-circle-intersection oracle
checks both assembly branches, all physical link lengths, plane membership,
fixed pivots and expected coordinates.

Tests include continuation along both branches, link-length edits, an exact
toggle, near-toggle conditioning, redundant equations, impossible dimensions,
budgets, cancellation, asynchronous edits and rollback. A numerical rank loss
at the exact toggle is a local infinitesimal diagnostic; it does not establish
finite mechanism mobility. Local convergence/failure does not select a global
branch or prove general infeasibility.

The timed nonlinear cases are regular configurations on one branch. Near-toggle
and contradictory cases are correctness coverage, not a latency claim.

`example/parametric_linkage.dart` connects this geometry to four two-hole bar
prototypes, four local meshes, a fixed ground instance and three moving
instances. Angle edits rebuild exactly `linkage`, `crank`, `coupler`, `rocker`;
each retained prototype is extruded and tessellated only once. A coupler-length
edit rebuilds only its prototype/mesh among the four parts. Layer-spacing edits
reposition the three moving instances without rerunning the solve.

The six additional tests independently check both branches, actual semantic
pivot-hole centers/axes, normals, analytic and exported mesh volume, reuse,
selective rebuilds and rollback after impossible dimensions, invalid profiles
or a downstream rejection. These are layered solids with coaxial pivot axes;
pins, bearings and collision checking are not modeled. The solid linkage is
correctness/capability coverage; it has no separate latency benchmark in this
pass.

## Measurement method

Paired measurements use the exact previous-audit source and frozen continuation
source. Corresponding harnesses and imported example dependencies must have
matching hashes. Runs are sequential with alternating revision order, three
fresh processes per runtime/revision, and AOT compilation outside all timers.
Independent correctness checks remain outside timed sections in these CAD and
geometry harnesses. Original physical solver/kernel validation remains inside.

Reported aggregates are medians of process p50/p95 values, not pooled
percentiles. Raw samples are retained where the harness exposes them. No samples
or processes are removed after inspection. The host is a shared, unpinned Linux
x64 container with Dart 3.14.0; wall-clock results describe these fixtures and
do not establish a universal interactive frame budget.

`tool/compare_performance.py` records source/runtime/harness provenance and
writes each completed run incrementally. `tool/summarize_performance.py`
derives the complete per-process/aggregate table without discarding samples,
including operation-batch metadata. The new summarizer was independently
reconciled against all 240 aggregate values in the prior 40-row audit summary.

### Final paired results

The final run contains **108 reports**: nine harnesses, two revisions, JIT/AOT
and three fresh processes. The baseline is `3b5c4c4`; retained source is
`3f042cd`. Both library trees are clean. All independent checks pass and all
nine harness/three imported-example hashes match across revisions. Hardware
reports an AMD EPYC 9V74 80-Core Processor, nine available logical CPUs and a
shared unpinned Linux container.

Evidence:

- [Final paired reports](../benchmark/results/2026-11-13-continuation-paired.json).
- [Complete 76-row summary](../benchmark/results/2026-11-13-continuation-summary.json),
  including every process p50/p95, aggregate and ratio.
- [Rejected QR candidate reports](../benchmark/results/2026-11-13-continuation-qr-candidate-paired.json)
  and [summary](../benchmark/results/2026-11-13-continuation-qr-candidate-summary.json).

The graph, CAD workspace, tiny QR, larger QR, coupled geometry and nonlinear
geometry harnesses use 5 warmups/25 measured samples. Independent circles and
the existing plate CAD use 3/25; the existing two-plate instance harness uses
5/40. Cold means model construction within a process, not process startup or
AOT compilation. The tables below use milliseconds and median process p50s.
Positive elapsed change is slower.

#### Feature graph bookkeeping

These fixtures have scalar immutable outputs and a four-feature affected
branch. They measure graph scheduling/snapshot overhead, not regeneration of
10,000 complex solids.

| Fixture | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| 1,000 features: Cold construction | 0.971 → 2.424 | 0.662 → 0.706 | +6.6% |
| 1,000 features: Four-feature edit | 0.273 → 0.060 | 0.212 → 0.008 | -96.2% |
| 1,000 features: No-op edit | 0.146 → 0.014 | 0.117 → 0.001 | -99.1% |
| 1,000 features: Unused parameter edit | 0.256 → 0.014 | 0.203 → 0.001 | -99.5% |
| 1,000 features: Rejected edit | 0.161 → 0.024 | 0.120 → 0.003 | -97.5% |
| 10,000 features: Cold construction | 11.768 → 18.381 | 10.644 → 12.198 | +14.6% |
| 10,000 features: Four-feature edit | 4.714 → 0.061 | 4.216 → 0.020 | -99.5% |
| 10,000 features: No-op edit | 2.403 → 0.013 | 2.076 → 0.003 | -99.9% |
| 10,000 features: Unused parameter edit | 4.470 → 0.016 | 3.984 → 0.004 | -99.9% |
| 10,000 features: Rejected edit | 2.573 → 0.018 | 2.867 → 0.007 | -99.8% |

The 10,000-feature sparse edit improves from **4.216 to 0.020 ms AOT** (about
211 times less elapsed time) and **4.714 to 0.061 ms JIT**. Its AOT p95 summary
falls from 7.010 to 0.029 ms. The structural closure/chunk counters explain why
the edit no longer copies and scans every feature.

The setup cost is substantial and retained in the result: 10,000-feature cold
construction rises from **10.644 to 12.198 ms AOT** (+14.6%) and **11.768 to
18.381 ms JIT** (+56.2%). Cold p95 rises from 13.491 to 18.634 ms AOT and
16.111 to 33.884 ms JIT. At 1,000 features, cold JIT rises from 0.971 to
2.424 ms. The new indexes and immutable declaration/state setup favor retained,
repeatedly edited documents. For the 10,000-feature AOT fixture, one sparse
edit saves more time than the measured additional cold setup cost, but that
break-even observation belongs to this workload.

No-op and unused-parameter AOT edits reach 1–4 microseconds. Those values are
close to timer resolution; their very large ratios are not general latency
predictions. The unchanged/unused paths still have independent identity and
parameter checks outside their timers.

#### Geometry and CAD paths

| Fixture | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| CAD geometry feature, cold | 2.066 → 2.123 | 1.342 → 1.306 | -2.7% |
| CAD geometry feature, retained pitch edit | 1.456 → 1.158 | 1.283 → 0.870 | -32.2% |
| QR chain, 48 coordinates | 0.120 → 0.119 | 0.118 → 0.118 | +0.0% |
| QR chain, 72 coordinates | 0.377 → 0.363 | 0.379 → 0.381 | +0.5% |
| QR chain, 96 coordinates | 0.802 → 0.833 | 0.836 → 0.839 | +0.4% |
| Nonlinear four-bar, cold | 1.211 → 0.915 | 0.092 → 0.090 | -2.2% |
| Nonlinear four-bar, retained angle edit | 0.757 → 0.511 | 0.066 → 0.067 | +1.5% |
| Direct coupled 24-point solve, cold | 2.166 → 1.896 | 1.409 → 1.343 | -4.7% |
| Direct coupled 24-point solve, pitch edit | 0.999 → 0.877 | 0.940 → 0.870 | -7.4% |
| 100 independent circles, cold | 4.181 → 4.808 | 1.898 → 1.978 | +4.2% |
| One circle edit | 0.324 → 0.331 | 0.120 → 0.118 | -1.7% |
| Existing plate CAD, cold | 2.197 → 2.224 | 1.507 → 1.447 | -4.0% |
| Existing plate CAD, profile edit | 2.196 → 2.263 | 1.643 → 1.518 | -7.6% |
| Existing plate CAD, thickness edit | 1.575 → 1.526 | 1.371 → 1.360 | -0.8% |
| Two-plate assembly, cold | 1.939 → 1.891 | 0.700 → 0.727 | +3.9% |
| Two-plate assembly, pose edit | 0.569 → 0.512 | 0.083 → 0.080 | -3.6% |

The transactional 24-point CAD geometry feature improves its warm edit from
**1.283 to 0.870 ms AOT** (32.2%) and **1.456 to 1.158 ms JIT** (20.5%). AOT
p95 improves from 1.503 to 0.936 ms. Every measured warm after run performs
zero rank factorizations and one rank reuse, versus one factorization/no reuse
before. Both versions still perform 336 residual evaluations, 168 Jacobian
evaluations and six linear solves. This supports retained diagnostic work as
the mechanism while preserving fresh physical evaluation. The fixture has
linear dimensional equations and no solid-kernel work.

The existing plate profile edit improves 7.6% AOT but regresses 3.1% JIT.
Direct nonlinear AOT is approximately unchanged (0.066 to 0.067 ms for a warm
angle edit). Its JIT medians fall, but the final numerical algorithm is unchanged;
those observations do not establish a new nonlinear algorithmic improvement.
The new articulated four-solid example is checked separately and has no timing
claim attached to these simpler fixtures.

Tails remain mixed. The two-plate pose edit JIT median falls from 0.569 to
0.512 ms, while its p95 rises from 0.964 to 1.083 ms. Independent-circle cold
JIT p50/p95 rise from 4.181/10.449 to 4.808/12.195 ms. No universal frame or
tail-latency guarantee follows from these measurements.

#### Restored QR controls

`numeric.dart` is identical before and after. Larger QR AOT medians are nearly
flat; the small-shape controls below still vary. In JIT, the nullspace batch
rises from 0.309 to 0.392 ms despite identical numerical source, illustrating
shared-host/JIT sensitivity. These controls carry no claimed QR improvement.
Each row measures a batch, not a single factorization/solve.

| Fixture | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| rank_5x4 (256 operations) | 0.912 → 1.054 | 0.145 → 0.143 | -1.4% |
| rank_8x4 (256 operations) | 0.237 → 0.222 | 0.172 → 0.171 | -0.6% |
| rank_4x5 (256 operations) | 0.409 → 0.360 | 0.159 → 0.159 | +0.0% |
| rank_4x8 (256 operations) | 0.255 → 0.222 | 0.244 → 0.242 | -0.8% |
| rank_9x4 (256 operations) | 0.170 → 0.174 | 0.180 → 0.180 | +0.0% |
| rank_12x4 (256 operations) | 0.199 → 0.202 | 0.211 → 0.211 | +0.0% |
| rank_16x8 (256 operations) | 0.652 → 0.618 | 0.681 → 0.679 | -0.3% |
| rank_16x9 (256 operations) | 0.755 → 0.680 | 0.764 → 0.736 | -3.7% |
| rank_17x8 (256 operations) | 0.647 → 0.669 | 0.696 → 0.726 | +4.3% |
| rank_48x48 (8 operations) | 0.840 → 0.827 | 0.955 → 1.014 | +6.2% |
| damped_solve_8x4 (256 operations) | 0.408 → 0.426 | 0.297 → 0.282 | -5.1% |
| nullspace_4x8 (256 operations) | 0.309 → 0.392 | 0.281 → 0.267 | -5.0% |

Independent review reconciled all **456 process-level p50/p95 pairs** and all
summary medians/ratios. It also recomputed **372 distributions with retained
raw samples**, checked source/harness/dependency hashes, sequential revision
ordering and the diagnostic/physical-work counters. No outliers were removed.

### Reproduction

Create separate worktrees at `3b5c4c4` and `3f042cd`, and run `dart pub get` in
both. Copy these five after-version harness/dependency files into the baseline
worktree without changing its library:

- `benchmark/cad_graph.dart`
- `benchmark/cad_workspace.dart`
- `benchmark/geometry_small_qr.dart`
- `benchmark/geometry_nonlinear.dart`
- `example/nonlinear_linkage.dart`

Run the comparison from the after worktree, supplying absolute local paths:

```sh
python3 tool/compare_performance.py \
  --before /absolute/path/to/before \
  --after /absolute/path/to/after \
  --dart /absolute/path/to/dart \
  --benchmarks cad_graph cad_workspace geometry_small_qr geometry_qr \
    geometry_nonlinear geometry_coupled geometry cad cad_instances \
  --rounds 3 --samples 25 --warmups 5 \
  --output benchmark/results/reproduced-continuation.json
python3 tool/summarize_performance.py \
  benchmark/results/reproduced-continuation.json \
  --output benchmark/results/reproduced-continuation-summary.json
```

The runner checks matching imported example hashes for CAD and nonlinear
fixtures. Its explicit CAD graph default is `--cad-graph-sizes 1000,10000`.
Use `dart run example/parametric_linkage.dart` to execute the articulated solid
capability checks; that example is not one of the timed harnesses.

## Integrated verification

The final source, including removal of the unsuccessful QR dispatch and the
solid linkage example, passes all listed local integrated gates:

| Gate | Result |
|---|---|
| Full native suite, 121 test files | 1,756 tests passed |
| Portable JavaScript/Node corpus, 38 files | 420 tests passed |
| Portable WebAssembly/Node corpus, 38 files | 420 tests passed |
| Full analysis with fatal infos | No issues |
| Whole-repository formatting | 205 Dart files, zero changes |
| Nonlinear and solid-linkage examples | Executed successfully with independent checks |

The [machine-readable validation record](../benchmark/results/2026-11-13-continuation-validation.json)
contains the source, runtime, file lists, counts, log hashes and final output
lines. Dart is 3.14.0 and Node is v24.22.1. Earlier candidate-source gates
(1,750/414/414) remain part of the checkpoint history; the final gates above
were rerun after the numeric rollback and addition of the six solid tests.

Independent reviews checked session aliases and cache invalidation, CAD warm
start provenance, graph declarations and immutable snapshots, and the articulated
solid placements/dependencies/oracles. The two graph snapshot bypasses found in
review were corrected before final gates and have dedicated regressions.

Browser execution remains separate: the previous local Chromium
attempt was blocked before tests by a denied process-singleton socket, and
queued GitHub Actions jobs do not count as passed gates.

## Remaining scope

The reference solid subset remains rectangular profiles with circular holes,
positive extrusion and rigid occurrences. The mechanism example does not add
general profiles, booleans, fillets, shells, revolution, collision checking,
pins or production topology repair. A broader kernel backend is still needed.

Further performance work should be driven by these paired results: distinguish
graph setup from repeated edits, rank-cache reuse from scratch allocation,
tiny-matrix crossover from larger sparse solves, and regular nonlinear
continuation from near-singular mechanisms. Full browser latency and a larger
realistic CAD corpus remain independent validation tasks.

See [PERFORMANCE_CAD_CONTINUATION.md](../PERFORMANCE_CAD_CONTINUATION.md) for
incremental remote checkpoints and the [previous audit](performance-cad-audit.md)
for historical results. Earlier measurements are not relabeled as this pass.

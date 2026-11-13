# CAD allocation optimization after main integration

Date: 2026-11-13. Follow-up: [PR #5](https://github.com/CrispStrobe/dart_csp/pull/5).

## Outcome and source boundaries

PR #3 and PR #4 merged the complete earlier CSP/CAD work into main, preserving
history. Their merge commits are `b289538d732bdb9eb0ae55480c796fbe4c5a68db`
and `894a11d74dae312ca99578532b27cca0b51fd34f`. All five earlier work-branch
heads are ancestors of that main checkpoint; PR #1/#2 were already merged.

This pass retains two CAD allocation changes. The final comparison measures
merged main **`894a11d`** against validated source **`acc01d7`**, using identical
harnesses and imported examples. Both numerical allocation experiments were
measured, preserved in history, and removed from the retained production code.
The numerical solver and graph implementations remain byte-identical to the
merged baseline. Their final benchmark rows are controls.

| Source | Full commit | Library tree |
|---|---|---|
| Merged baseline | `894a11d74dae312ca99578532b27cca0b51fd34f` | `fd84f7592a65f5e6bc9c5f3be18a2a8619bb6b93` |
| Validated retained source | `acc01d77156559a8854b22b6c03cd10083cc36f8` | `ef99105a9d7787925ae245cf10adbd040df1ad62` |

Documentation, audit tooling and evidence commits after `acc01d7` do not alter
its library, tests, examples or benchmark harnesses. PR #5 provides the final
merge identity. All work branches and rejected trials remain reachable; no
history is rewritten.

## Retained implementation

### Checked rigid placement

`CadRigidTransform` computes identity status once from its private immutable
matrix. Checked point placement uses scalar accumulation in place of temporary
coordinate, product and residual lists. For each output coordinate, the three
products, three TwoSum steps, outward-rounded product bounds, residual-error
additions and final L1 error accumulation retain their original order. Source
coordinates are still captured once, and translation is the factory's concrete
immutable snapshot.

The precision budget and finite/overflow checks are preserved. The regression
at coordinate magnitude 2^52 verifies half-unit loss for identity and an exact
half-turn, rejection with a 0.49 budget, acceptance with a 0.51 budget and an
honest additional error bound. It also checks the independent analytic/local
volume of 312 and the representable placed-mesh volume of 300.

### Mesh vertex links

After the existing distinct-index construction and degree-two gate, each
connected component of a vertex link is a cycle. Validation now follows the
neighbor other than the previous vertex while counting visited nodes. It
accepts only after returning to the start and covering the entire link. This
removes the per-vertex traversal set and pending list; disconnected cycles at
a pinched vertex still reject. The loop is bounded by the link size.

Triangle area arithmetic, custom point operators, edge-incidence checks,
positive-volume checks and issue order are unchanged. Two regression tests
cover 40 valid bipyramid variants and 32 unequal pinched-fan variants, including
both possible starting cycles, several valences and triangle/index permutations.

Separate agent reviews checked arithmetic order, immutable snapshots, cycle
termination and the independent regression oracles. The final production diff
contains only `lib/src/cad/placement.dart` and `lib/src/cad/kernel.dart`.
The changes remove specific collection constructions; heap-memory reduction
was not measured, and the validator's asymptotic complexity is unchanged.

## Main performance result

The combined candidate improves all ten reported CAD AOT median rows. Nine of
the ten are faster in every paired process: all five solid-linkage operations,
all three plate operations and the assembly pose edit. Assembly cold
construction improves in two pairs, giving 29 faster pairs out of 30 overall.
Each percentage below compares the median of three process p50
values. Times are microseconds per complete operation.

| AOT fixture / operation | Baseline p50 (us) | Retained p50 (us) | Elapsed change | Faster pairs |
|---|---:|---:|---:|---:|
| `cad_linkage` / `cold_build_solve_solids_meshes` | 3665 | 3035 | -17.2% | 3/3 |
| `cad_linkage` / `retained_angle_edit` | 304 | 274 | -9.9% | 3/3 |
| `cad_linkage` / `selective_coupler_length_edit` | 1071 | 926 | -13.5% | 3/3 |
| `cad_linkage` / `placement_only_layer_edit` | 190 | 167 | -12.1% | 3/3 |
| `cad_linkage` / `downstream_rejected_angle_edit` | 273 | 247 | -9.5% | 3/3 |
| `cad` / `cold_build_compile_regenerate` | 1519 | 1159 | -23.7% | 3/3 |
| `cad` / `profile_edit_regenerate` | 1568 | 1199 | -23.5% | 3/3 |
| `cad` / `thickness_edit_regenerate` | 1450 | 1080 | -25.5% | 3/3 |
| `cad_instances` / `cold_build_solve_regenerate` | 672 | 630 | -6.2% | 2/3 |
| `cad_instances` / `solved_pose_edit` | 78 | 74 | -5.1% | 3/3 |

JIT plate cold/profile/thickness medians improve 15.7%/14.8%/12.5%; cold and
profile are faster in all three process pairs. JIT assembly cold construction
improves 7.0% in aggregate and every pair. JIT solid-linkage cold construction
improves 5.7% in aggregate and every pair, but some other JIT operations are
mixed or slower.

### Costs and interpretation

The retained changes do not improve every latency distribution:

- AOT plate cold/profile/thickness p95 medians worsen **1,952 to 2,487 us**,
  **1,966 to 2,186 us**, and **1,790 to 2,231 us**. All three process pairs for
  each operation have worse p95 values. Their p50 gains do not establish an
  improvement in tail latency.
- JIT linkage placement-only edits worsen from **369 to 393 us** at p50 and
  **647 to 1,150 us** at p95. JIT assembly pose p50 is **511 to 516 us**.
- JIT linkage cold/angle/coupler/rejected-edit p95 medians also worsen, despite
  some improved p50 values. All such values are retained in the complete table.
- Unchanged controls move substantially: the 100-circle AOT warm-solve median
  is **131 to 171 us**, while the 10,000-feature graph AOT cold median is
  **9,815 to 9,457 us**. These are not attributed to solver or graph changes.
  They demonstrate the limits of a shared, unpinned environment and short runs;
  the records do not establish the cause of each timing change.

Retention is based on consistent complete-operation CAD median gains and
preserved correctness, with the tail costs disclosed. The two CAD changes are
measured together, so these data cannot divide their individual contributions.
There is no universal speedup claim or production latency guarantee. A follow-up
on plate tails should profile their cause and use a latency target before
changing the algorithm further.

## Numerical trials rejected

Each stage used the same four harnesses (`geometry_fork`, `cad_workspace`,
`geometry_coupled`, `geometry_nonlinear`) in three paired JIT/AOT rounds: 48
reports and 28 summary rows per stage. Every sample and report is retained.

| Stage | Source comparison | Observation | Decision |
|---|---|---|---|
| Replace unused ambient argument buffers with a private empty placeholder | `894a11d` to `aaca896` | CAD JIT cold/retained medians worsen 21.6%/23.7%. The 11.4% aggregate coupled AOT cold gain comes from paired changes +3.9%, -33.0%, +26.9%; only one pair improves. Nonallocating controls also move. | Insufficient consistent benefit; revert production change. |
| Bind scratch/Jacobian references at their existing first-use point | `aaca896` to `01f8f86` | CAD JIT cold/retained medians worsen 14.1%/24.5%, in every corresponding pair. AOT CAD retained median worsens 2.3%. | Revert production change. |

The trials were merged into the integration history at `31b7c98`; the next
commit `acc01d7` restores `solver.dart` exactly to blob
`8c41acb7c8b4f8588a359efc714bd9ed3f4c5817` from merged main. The mixed-shape
analytic callback/fork isolation regression remains. The data support the
retention decision, not a statement that either trial is universally slower.
Their correctness reviews and 115 focused tests passed before measurement.

## Correctness and evidence integrity

| Gate on frozen `acc01d7` | Result |
|---|---|
| Entire native suite | 1,762 tests passed across 121 files |
| Node / dart2js portable corpus | 426 tests passed across 38 files |
| Node / dart2wasm portable corpus | 426 tests passed across 38 files |
| Fatal-info static analysis | Passed |
| Dart formatting | 207 files checked; 0 changes |
| Independent final source review | Only the two intended CAD production files differ; solver restored exactly |
| Independent final measurement audit | 108 reports / 72 rows; no findings |

The final audit reconciles all 432 process p50/p95 pairs, 8,700 exposed raw
samples, 3,900 aligned per-sample work records, 108 physical-oracle completion
records, alternating revision order, complete rounds, frozen source bytes,
harness hashes and imported-example hashes. Both numerical screens independently
reconcile another 96 reports, 8,400 samples and 4,800 aligned work records.
All paired physical-work records and reported numerical counters match.

Legacy `cad`, `cad_instances` and `geometry` reports expose percentiles without
raw sample arrays; their percentiles cannot be independently recomputed from
absent samples. Their counters/rebuild lists, and those of the coupled/workspace
and nonlinear harnesses, describe the last measured solve. Only `geometry_fork`
and `cad_linkage` expose aligned work records for every sample. Physical-oracle
pass flags are checked against the reviewed harness control flow; full coordinate
snapshots are not serialized for independent replay.

Real-browser validation remains open. The prior Chromium attempt was blocked
by the workspace's process-singleton socket restriction; no bypass or repeated
attempt was made. GitHub platform/browser CI was queued in the recorded snapshot.
Queued jobs are not counted as passes. The local portable checks exercise Node,
and do not substitute for real-browser/platform CI. See PR #5 and its workflow
runs for the current server-side status.

## Measurement method and reproduction

Dart 3.14.0, Linux x64, Node v24.22.1. Hardware: AMD EPYC 9V74 80-Core Processor,
nine available logical CPUs, shared and unpinned container. Correctness runs
finished before timings began. All timing processes ran sequentially; no
parallel agent tests or benchmark processes ran during measurements.

There are three fresh processes per revision and runtime. Revision order is
before/after, after/before, before/after. AOT compilation is outside measured
sections. Each report's p50/p95 stays separate; the tables use the median of the
three process percentiles, without pooling, removing samples or selecting a
favorable repeat. Zero denominators produce an undefined percentage.

| Harness | Warmups / samples per process | Timing scope |
|---|---:|---|
| `cad_linkage` | 5 / 25 | Cold build and four retained/edit/rejection operations; independent physical/reuse/rollback checks outside timing |
| `cad` | 3 / 25 | Plate cold/profile/thickness regeneration; analytic volume and mesh checks outside timing |
| `cad_instances` | 5 / 40 | Two-instance cold construction and solved pose edit |
| `cad_workspace`, `geometry_coupled`, `geometry_nonlinear` | 5 / 25 | Complete cold and retained numerical operations |
| `geometry_fork` | 5 / 25 at 100 and 1,000 components | Fork, clean solve, fork-and-edit, and retained direct edit |
| `geometry` | 3 / 25 | 100 independent circles; edit one radius |
| `cad_graph` | 5 / 25 at 1,000 and 10,000 features | Cold, sparse, no-op, unused-parameter and rejected edits |

Create separate checkouts of the exact before/after commits, install the same
Dart SDK and dependencies, then run from a checkout with the comparison tools:

```sh
python3 tool/compare_performance.py \
  --before /path/to/baseline-894a11d \
  --after /path/to/retained-acc01d7 \
  --dart /path/to/dart-sdk/bin/dart \
  --benchmarks cad_linkage cad cad_instances cad_workspace geometry_fork \
    geometry_coupled geometry_nonlinear geometry cad_graph \
  --rounds 3 --samples 25 --warmups 5 \
  --output /path/to/main-paired.json

python3 tool/summarize_performance.py \
  /path/to/main-paired.json \
  --output /path/to/main-summary.json

python3 tool/audit_cad_measurements.py \
  /path/to/main-paired.json \
  /path/to/main-summary.json \
  --before /path/to/baseline-894a11d \
  --after /path/to/retained-acc01d7 \
  --output /path/to/main-audit.json
```

The same comparison command with the four numerical harnesses reproduces the
individual screens, using `894a11d`/`aaca896` and `aaca896`/`01f8f86` respectively.
The audit reads JSON or gzip and runs no Dart timings.

## Saved evidence

- [Final raw reports, losslessly compressed](../benchmark/results/2026-11-13-main-paired.json.gz)
- [All final summaries and per-process percentiles](../benchmark/results/2026-11-13-main-summary.json)
- [Independent final measurement audit](../benchmark/results/2026-11-13-main-audit.json)
- [Validation commands, runtimes, source identity and hashes](../benchmark/results/2026-11-13-main-validation.json)
- [Full validation and benchmark logs](../benchmark/results/2026-11-13-main-validation-logs.tar.gz)
- [Placeholder trial](../benchmark/results/2026-11-13-placeholder-summary.json) and [its audit](../benchmark/results/2026-11-13-placeholder-audit.json)
- [Binding trial](../benchmark/results/2026-11-13-binding-summary.json) and [its audit](../benchmark/results/2026-11-13-binding-audit.json)
- [Independent audit implementation](../tool/audit_cad_measurements.py)

The main raw JSON SHA-256 is
`9547c2c6d36cd6b735e331c5d6ca47f8970d3469eb5a8a6b22e3d1aedb356229`.
The audit also identifies the exact compressed-file and summary hashes.
Compression was verified by byte-for-byte decompression.

The CAD scope remains the reference extrusion and articulated rigid-instance
subset. These changes introduce no new solid operations or geometric predicates.
Version 2.4.0 remains experimental and unreleased.

## Complete final table

All 72 rows are shown. Negative change means lower elapsed time. Times are
microseconds per operation; p50 and p95 columns each show baseline to retained.
The final column counts paired processes with a lower p50, without discarding
any process. Numerical and feature-graph rows are unchanged controls.

| Runtime | Harness | Measurement | p50 us (before to after) | Elapsed change | p95 us (before to after) | Faster pairs |
|---|---|---|---:|---:|---:|---:|
| JIT | `cad_linkage` | `measurements/cold_build_solve_solids_meshes` | 4770 to 4496 | -5.7% | 7570 to 7991 | 3/3 |
| JIT | `cad_linkage` | `measurements/retained_angle_edit` | 770 to 765 | -0.6% | 1551 to 1949 | 2/3 |
| JIT | `cad_linkage` | `measurements/selective_coupler_length_edit` | 1694 to 1686 | -0.5% | 2562 to 2831 | 2/3 |
| JIT | `cad_linkage` | `measurements/placement_only_layer_edit` | 369 to 393 | +6.5% | 647 to 1150 | 2/3 |
| JIT | `cad_linkage` | `measurements/downstream_rejected_angle_edit` | 773 to 693 | -10.3% | 1179 to 1364 | 2/3 |
| JIT | `cad` | `cold_build_compile_regenerate` | 2267 to 1910 | -15.7% | 4437 to 3908 | 3/3 |
| JIT | `cad` | `profile_edit_regenerate` | 2306 to 1964 | -14.8% | 5097 to 4868 | 3/3 |
| JIT | `cad` | `thickness_edit_regenerate` | 1526 to 1336 | -12.5% | 3376 to 3841 | 2/3 |
| JIT | `cad_instances` | `cold_build_solve_regenerate` | 1971 to 1834 | -7.0% | 3652 to 3472 | 3/3 |
| JIT | `cad_instances` | `solved_pose_edit` | 511 to 516 | +1.0% | 1119 to 1100 | 2/3 |
| JIT | `cad_workspace` | `cold_build_compile_regenerate` | 2006 to 2121 | +5.7% | 3687 to 3347 | 0/3 |
| JIT | `cad_workspace` | `warm_edit_regenerate` | 1020 to 1022 | +0.2% | 1991 to 2406 | 1/3 |
| JIT | `geometry_fork` | `results/components=100/fork_only` | 37 to 33 | -10.8% | 90 to 70 | 3/3 |
| JIT | `geometry_fork` | `results/components=100/clean_fork_solve` | 252 to 250 | -0.8% | 913 to 784 | 2/3 |
| JIT | `geometry_fork` | `results/components=100/sparse_fork_edit` | 469 to 365 | -22.2% | 1431 to 990 | 2/3 |
| JIT | `geometry_fork` | `results/components=100/direct_sparse_edit` | 358 to 345 | -3.6% | 1028 to 1033 | 2/3 |
| JIT | `geometry_fork` | `results/components=1000/fork_only` | 120 to 125 | +4.2% | 164 to 155 | 0/3 |
| JIT | `geometry_fork` | `results/components=1000/clean_fork_solve` | 927 to 967 | +4.3% | 1552 to 1254 | 1/3 |
| JIT | `geometry_fork` | `results/components=1000/sparse_fork_edit` | 996 to 1040 | +4.4% | 2044 to 1298 | 2/3 |
| JIT | `geometry_fork` | `results/components=1000/direct_sparse_edit` | 857 to 889 | +3.7% | 1830 to 1401 | 2/3 |
| JIT | `geometry_coupled` | `cold_build_compile_solve` | 1954 to 1896 | -3.0% | 2879 to 2815 | 2/3 |
| JIT | `geometry_coupled` | `warm_edit_solve` | 862 to 872 | +1.2% | 2076 to 1689 | 1/3 |
| JIT | `geometry_nonlinear` | `cold_build_compile_solve` | 1082 to 1045 | -3.4% | 1667 to 1533 | 2/3 |
| JIT | `geometry_nonlinear` | `warm_edit_solve` | 622 to 570 | -8.4% | 1460 to 1261 | 2/3 |
| JIT | `geometry` | `cold_build_compile_solve` | 4156 to 4241 | +2.0% | 10243 to 10892 | 1/3 |
| JIT | `geometry` | `warm_edit_solve` | 294 to 323 | +9.9% | 1120 to 1288 | 1/3 |
| JIT | `cad_graph` | `results/features=1000/cold_build_regenerate` | 1411 to 1433 | +1.6% | 2436 to 4190 | 1/3 |
| JIT | `cad_graph` | `results/features=1000/sparse_edit` | 34 to 36 | +5.9% | 109 to 102 | 2/3 |
| JIT | `cad_graph` | `results/features=1000/no_op_edit` | 8 to 8 | +0.0% | 44 to 21 | 2/3 |
| JIT | `cad_graph` | `results/features=1000/unused_parameter_edit` | 11 to 12 | +9.1% | 32 to 32 | 1/3 |
| JIT | `cad_graph` | `results/features=1000/rejected_edit` | 18 to 18 | +0.0% | 42 to 37 | 0/3 |
| JIT | `cad_graph` | `results/features=10000/cold_build_regenerate` | 11695 to 12152 | +3.9% | 20862 to 24746 | 1/3 |
| JIT | `cad_graph` | `results/features=10000/sparse_edit` | 60 to 51 | -15.0% | 134 to 111 | 2/3 |
| JIT | `cad_graph` | `results/features=10000/no_op_edit` | 13 to 12 | -7.7% | 28 to 41 | 2/3 |
| JIT | `cad_graph` | `results/features=10000/unused_parameter_edit` | 14 to 15 | +7.1% | 32 to 34 | 1/3 |
| JIT | `cad_graph` | `results/features=10000/rejected_edit` | 20 to 18 | -10.0% | 39 to 44 | 2/3 |
| AOT | `cad_linkage` | `measurements/cold_build_solve_solids_meshes` | 3665 to 3035 | -17.2% | 8625 to 3573 | 3/3 |
| AOT | `cad_linkage` | `measurements/retained_angle_edit` | 304 to 274 | -9.9% | 565 to 362 | 3/3 |
| AOT | `cad_linkage` | `measurements/selective_coupler_length_edit` | 1071 to 926 | -13.5% | 1939 to 1119 | 3/3 |
| AOT | `cad_linkage` | `measurements/placement_only_layer_edit` | 190 to 167 | -12.1% | 351 to 277 | 3/3 |
| AOT | `cad_linkage` | `measurements/downstream_rejected_angle_edit` | 273 to 247 | -9.5% | 433 to 285 | 3/3 |
| AOT | `cad` | `cold_build_compile_regenerate` | 1519 to 1159 | -23.7% | 1952 to 2487 | 3/3 |
| AOT | `cad` | `profile_edit_regenerate` | 1568 to 1199 | -23.5% | 1966 to 2186 | 3/3 |
| AOT | `cad` | `thickness_edit_regenerate` | 1450 to 1080 | -25.5% | 1790 to 2231 | 3/3 |
| AOT | `cad_instances` | `cold_build_solve_regenerate` | 672 to 630 | -6.2% | 1117 to 1135 | 2/3 |
| AOT | `cad_instances` | `solved_pose_edit` | 78 to 74 | -5.1% | 181 to 168 | 3/3 |
| AOT | `cad_workspace` | `cold_build_compile_regenerate` | 1344 to 1302 | -3.1% | 1835 to 1480 | 3/3 |
| AOT | `cad_workspace` | `warm_edit_regenerate` | 880 to 851 | -3.3% | 1168 to 1038 | 2/3 |
| AOT | `geometry_fork` | `results/components=100/fork_only` | 10 to 10 | +0.0% | 65 to 22 | 0/3 |
| AOT | `geometry_fork` | `results/components=100/clean_fork_solve` | 81 to 81 | +0.0% | 172 to 182 | 2/3 |
| AOT | `geometry_fork` | `results/components=100/sparse_fork_edit` | 95 to 99 | +4.2% | 294 to 242 | 1/3 |
| AOT | `geometry_fork` | `results/components=100/direct_sparse_edit` | 83 to 82 | -1.2% | 216 to 131 | 1/3 |
| AOT | `geometry_fork` | `results/components=1000/fork_only` | 111 to 105 | -5.4% | 184 to 160 | 2/3 |
| AOT | `geometry_fork` | `results/components=1000/clean_fork_solve` | 875 to 882 | +0.8% | 1027 to 1055 | 1/3 |
| AOT | `geometry_fork` | `results/components=1000/sparse_fork_edit` | 886 to 885 | -0.1% | 1634 to 1513 | 2/3 |
| AOT | `geometry_fork` | `results/components=1000/direct_sparse_edit` | 775 to 777 | +0.3% | 1139 to 976 | 1/3 |
| AOT | `geometry_coupled` | `cold_build_compile_solve` | 1303 to 1357 | +4.1% | 1577 to 1688 | 1/3 |
| AOT | `geometry_coupled` | `warm_edit_solve` | 848 to 872 | +2.8% | 1133 to 1032 | 1/3 |
| AOT | `geometry_nonlinear` | `cold_build_compile_solve` | 91 to 99 | +8.8% | 194 to 197 | 0/3 |
| AOT | `geometry_nonlinear` | `warm_edit_solve` | 67 to 73 | +9.0% | 190 to 202 | 0/3 |
| AOT | `geometry` | `cold_build_compile_solve` | 2142 to 2080 | -2.9% | 3849 to 6959 | 2/3 |
| AOT | `geometry` | `warm_edit_solve` | 131 to 171 | +30.5% | 251 to 250 | 0/3 |
| AOT | `cad_graph` | `results/features=1000/cold_build_regenerate` | 562 to 582 | +3.6% | 1169 to 1165 | 2/3 |
| AOT | `cad_graph` | `results/features=1000/sparse_edit` | 7 to 7 | +0.0% | 16 to 12 | 1/3 |
| AOT | `cad_graph` | `results/features=1000/no_op_edit` | 0 to 1 | undefined | 1 to 1 | 0/3 |
| AOT | `cad_graph` | `results/features=1000/unused_parameter_edit` | 1 to 1 | +0.0% | 2 to 2 | 0/3 |
| AOT | `cad_graph` | `results/features=1000/rejected_edit` | 2 to 2 | +0.0% | 4 to 4 | 0/3 |
| AOT | `cad_graph` | `results/features=10000/cold_build_regenerate` | 9815 to 9457 | -3.6% | 21305 to 21603 | 2/3 |
| AOT | `cad_graph` | `results/features=10000/sparse_edit` | 18 to 19 | +5.6% | 31 to 32 | 1/3 |
| AOT | `cad_graph` | `results/features=10000/no_op_edit` | 3 to 3 | +0.0% | 6 to 5 | 0/3 |
| AOT | `cad_graph` | `results/features=10000/unused_parameter_edit` | 4 to 3 | -25.0% | 6 to 6 | 2/3 |
| AOT | `cad_graph` | `results/features=10000/rejected_edit` | 7 to 6 | -14.3% | 12 to 9 | 2/3 |

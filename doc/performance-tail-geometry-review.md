# Independent geometry retention and CAD instrumentation review

## Recommendation

Revert the immutable-result publication optimization from production, preserving its focused ownership regressions, source checkpoint and all measurement evidence. The implementation remains semantically defensible; this recommendation rests on insufficient performance benefit for the target workloads. It does not establish that every subchange is individually slower.

The isolated source comparison is baseline `b3e14fbb298c8d4f3714debbeaffaeb6d550db51` (library tree `6111175debbc7a3ae99631e274f24f16b28d2f25`) against geometry candidate `e14bd4c91d9ca8ac676b90904fda3a056e2d6b37` (library tree `486344b2aaef9bfe13c666c04fa995c2ceab0192`). The only production delta is `lib/src/geometry/solver.dart`. Current retained root `e510f1fbc00a825283fafee2fc6bc57547ef898a` has reverted that delta: its only production difference from the baseline is `lib/src/cad/placement.dart`.

The geometry candidate replaces copies of privately owned result maps with unmodifiable views, wraps an already copied residual slice instead of copying it again, and caches immutable component identity lists. Per-parameter coordinate copies, callback buffers, declaration snapshots, numerical algorithms, tolerance/rank work and transaction handling are unchanged. The owned data is not subsequently mutated or exposed through another mutable reference. Cached ID construction does add work at component construction and retains those lists for the compiled model's lifetime; the data do not identify which subchange causes any timing result. No new solver performance claim should be inferred from expected allocation savings alone.

## Performance evidence

Six of fifteen aggregate p50 rows improve in each runtime. Every AOT linkage/assembly p50 row worsens; six of seven corresponding JIT rows worsen. The principal target, retained-angle latency, has mixed results: p50 increases 2.17% JIT and 2.48% AOT, whereas p95 falls 9.98% and 3.40%. Two of three p50 process pairs worsen in each runtime. This is not a convincing target improvement.

Two repeated AOT tail costs carry particular weight: coupled-geometry cold p95 increases 115.36%, with all three pairs worse (+129.1%, +20.1%, +75.6%); assembly cold p95 increases 46.47%, also with all three pairs worse (+184.6%, +5.2%, +45.1%). Assembly cold p50 increases 18.06%, and pose-edit p50 increases 10.42%. JIT assembly pose p50/p95 also worsen 14.94%/22.76%.

Benefits remain in the evidence. The independent-circle retained edit improves AOT p50/p95 by 30.77%/53.89%; its p50 improves in all three pairs, although the legacy harness does not expose raw samples. Nonlinear warm p50 improves in all three JIT and AOT pairs. Transactional workspace AOT warm p50 also improves in all three pairs (aggregate 3.03% lower), and cold/warm p95 aggregates decrease 23.07%/20.31%. These gains do not outweigh the target workload costs for retaining the combined candidate.

No row has all three p50 pairs slower. Many rows reverse direction between processes, including the unchanged-solve placement-only control: it reports zero new geometry work but AOT p50 increases 2.52% and JIT p95 increases 14.44%. This is useful evidence of process/heap/noise sensitivity. Shared, unpinned execution and three process pairs support a bounded retention decision, not a universal speed ranking or a causal GC explanation.

### All aggregate rows and adverse-pair counts

Times are microseconds. Changes are after/before minus one; positive means slower. Each timing cell is the median of the three process p50 or p95 values, not a percentile of pooled samples. `Worse pairs` lists p50/p95 counts out of three.

| Runtime | Fixture / operation | p50 before → after | p50 change | p95 before → after | p95 change | Worse pairs |
|---|---|---:|---:|---:|---:|---:|
| JIT | geometry / cold_build_compile_solve | 3155 → 3747 | +18.76% | 9639 → 11993 | +24.42% | 2/3; 2/3 |
| JIT | geometry / warm_edit_solve | 187 → 229 | +22.46% | 980 → 723 | -26.22% | 2/3; 1/3 |
| JIT | geometry_nonlinear / cold_build_compile_solve | 771 → 730 | -5.32% | 1533 → 1687 | +10.05% | 1/3; 2/3 |
| JIT | geometry_nonlinear / warm_edit_solve | 488 → 452 | -7.38% | 977 → 831 | -14.94% | 0/3; 0/3 |
| JIT | geometry_coupled / cold_build_compile_solve | 1457 → 1344 | -7.76% | 2221 → 2289 | +3.06% | 1/3; 1/3 |
| JIT | geometry_coupled / warm_edit_solve | 621 → 546 | -12.08% | 1697 → 1461 | -13.91% | 1/3; 1/3 |
| JIT | cad_workspace / cold_build_compile_regenerate | 1517 → 1581 | +4.22% | 2191 → 2568 | +17.21% | 2/3; 2/3 |
| JIT | cad_workspace / warm_edit_regenerate | 717 → 667 | -6.97% | 1812 → 1687 | -6.90% | 2/3; 1/3 |
| JIT | cad_linkage / cold_build_solve_solids_meshes | 1918 → 1913 | -0.26% | 2952 → 3075 | +4.17% | 2/3; 2/3 |
| JIT | cad_linkage / retained_angle_edit | 277 → 283 | +2.17% | 581 → 523 | -9.98% | 2/3; 1/3 |
| JIT | cad_linkage / selective_coupler_length_edit | 651 → 683 | +4.92% | 1000 → 1051 | +5.10% | 2/3; 2/3 |
| JIT | cad_linkage / placement_only_layer_edit | 162 → 163 | +0.62% | 270 → 309 | +14.44% | 2/3; 2/3 |
| JIT | cad_linkage / downstream_rejected_angle_edit | 243 → 250 | +2.88% | 484 → 505 | +4.34% | 2/3; 2/3 |
| JIT | cad_instances / cold_build_solve_regenerate | 728 → 747 | +2.61% | 1699 → 1669 | -1.77% | 2/3; 1/3 |
| JIT | cad_instances / solved_pose_edit | 154 → 177 | +14.94% | 413 → 507 | +22.76% | 2/3; 2/3 |
| AOT | geometry / cold_build_compile_solve | 1434 → 1553 | +8.30% | 2149 → 2877 | +33.88% | 2/3; 2/3 |
| AOT | geometry / warm_edit_solve | 91 → 63 | -30.77% | 321 → 148 | -53.89% | 0/3; 1/3 |
| AOT | geometry_nonlinear / cold_build_compile_solve | 66 → 65 | -1.52% | 239 → 146 | -38.91% | 0/3; 0/3 |
| AOT | geometry_nonlinear / warm_edit_solve | 47 → 46 | -2.13% | 128 → 133 | +3.91% | 0/3; 2/3 |
| AOT | geometry_coupled / cold_build_compile_solve | 884 → 939 | +6.22% | 1152 → 2481 | +115.36% | 2/3; 3/3 |
| AOT | geometry_coupled / warm_edit_solve | 578 → 563 | -2.60% | 775 → 854 | +10.19% | 1/3; 2/3 |
| AOT | cad_workspace / cold_build_compile_regenerate | 933 → 922 | -1.18% | 1608 → 1237 | -23.07% | 1/3; 0/3 |
| AOT | cad_workspace / warm_edit_regenerate | 627 → 608 | -3.03% | 1024 → 816 | -20.31% | 0/3; 1/3 |
| AOT | cad_linkage / cold_build_solve_solids_meshes | 1923 → 1974 | +2.65% | 3198 → 2971 | -7.10% | 2/3; 1/3 |
| AOT | cad_linkage / retained_angle_edit | 202 → 207 | +2.48% | 382 → 369 | -3.40% | 2/3; 1/3 |
| AOT | cad_linkage / selective_coupler_length_edit | 642 → 671 | +4.52% | 1104 → 1076 | -2.54% | 2/3; 1/3 |
| AOT | cad_linkage / placement_only_layer_edit | 119 → 122 | +2.52% | 208 → 193 | -7.21% | 2/3; 0/3 |
| AOT | cad_linkage / downstream_rejected_angle_edit | 185 → 188 | +1.62% | 301 → 315 | +4.65% | 2/3; 2/3 |
| AOT | cad_instances / cold_build_solve_regenerate | 360 → 425 | +18.06% | 553 → 810 | +46.47% | 2/3; 3/3 |
| AOT | cad_instances / solved_pose_edit | 48 → 53 | +10.42% | 153 → 129 | -15.69% | 2/3; 1/3 |

## Independent reconciliation

A separate short Python reconciliation imported no project summarizer or auditor and ran no timing workloads. It checked the complete alternating revision sequence, all timestamps for sequential nonoverlap, per-harness sampling flags/counts, disabled tracing/check-only flags, exposed raw distributions, exact paired work, per-process p50/p95/p99, all summary process entries, all aggregate medians and p50 ratios/percent changes. There were no discrepancies in 1,260 checks. A further 28 read-only provenance checks verified both worktree commits/library trees, locks, all recorded harness/dependency bytes and current root assembly/linkage harness bytes.

The cohort contains 72 process reports and 30 summary rows. Its 180 distributions comprise 156 with raw timing data (27,000 samples) and 24 legacy independent-circle distributions without raw data. There are 84 distributions with aligned work records (25,200 records), including 42 before/after distribution comparisons and 12,600 exact aligned record comparisons. The separate last-sample metadata comparisons also match. All 24 exposed assembly p99 values reconstruct exactly. The existing audit's input hashes and sample/work/missing-raw counts agree.

The CAD assembly/linkage paths use 300 measured samples after 30 warmups. Other geometry/control harnesses retain 25 measurements and their documented 3 or 5 warmups; the flags do not silently turn those into 300-sample cases. For even sample counts, the CAD harness defines p50 as the upper middle sorted value; p95/p99 use nearest rank. Summary medians combine the three already computed process percentile values. The absent independent-circle raw samples cannot be reconstructed, and other control work counters describe the last operation rather than every sample.

Physical correctness is supported by reviewed harness oracles and their pass records, not by replay of full coordinate data serialized into JSON. Work equality verifies the recorded operation workload; it does not measure allocation bytes, collection scheduling or all internal VM work.

## Assembly instrumentation semantics

Reviewed `benchmark/cad_instances.dart` at root `e510f1f...`, byte-identical to the cohort harness, with `example/parametric_assembly.dart`.

- Cold timing starts before the per-operation counting kernel, graph/model construction and regeneration. Retained timing covers the gap change and regeneration. Initial fixture setup, prior state/count capture, independent physical checks, work-record construction, sample retention and JSON aggregation are outside the timers.
- The two gap values (12 and 5) alternate, as do cold/edit operation order. The prior retained state is captured before each edit. Work records are appended with their corresponding elapsed sample in acquisition order; sorting only a separate copy preserves alignment.
- Rebuild closure and scheduled counts distinguish all six cold features from the two pose features. Kernel deltas assert one extrusion/tessellation for cold operations and none for edits. Body/mesh reuse is checked against the preceding state and original retained objects; fixed base identity is also checked on edits.
- Solver invocation is inferred only after requiring a new geometry result identity. Fresh result statistics describe that operation. Coordinates, normals, dimensions, finite values, analytic volume and mesh validity are checked after each timer stops.
- `--check-only` validates arguments then overrides to two pairs, zero warmups, covering both values/orders. It allocates no Stopwatch and emits JSON with `check_only: true`, zero timing placeholders and an explicit description. Normal audit rejects those placeholders. This output format differs intentionally from linkage's pass-message check-only mode.
- Timeline tracing is a compile-time opt-in, false in every ordinary cohort report. Start/finish calls are outside the elapsed measurement, and `finally` closes spans when regeneration throws. A profile span includes Stopwatch setup/stop overhead in addition to the operation; profile overlap should not be described as a perfect production-only allocation boundary.

This adds counting-kernel work to cold instrumentation and retains per-sample maps, so historical absolute times from the older harness are not interchangeable with this cohort. Both revisions execute identical harness bytes, preserving this paired comparison. Untimed checks still allocate and can influence later GC; their being outside the Stopwatch does not remove that environmental effect.

## Linkage instrumentation semantics

Reviewed `benchmark/cad_linkage.dart` at the same root, byte-identical to the cohort harness. Its diff adds only optional timeline wrapping and trace metadata around the existing operation timer boundaries.

- Cold operations include fixture construction and regeneration; retained operations include regeneration with the supplied edit. Solver and backend validation remain inside regeneration. Independent geometric/solid/export oracles, retention checks, kernel snapshots/deltas and result aggregation run after stop.
- Each successful solve edit requires a new geometry result; the placement-only operation requires the retained result and records zero new solver work. It does not repeat old statistics as current work. Exact per-part extrusion/tessellation deltas enforce selective rebuilds.
- The rejected-operation timer includes a solved candidate, downstream rejection and rollback. Candidate statistics come from the gate-captured result, not the unchanged committed state. Candidate/old-state geometry, exact rollback identity and rebuilt closure are checked before recording. Recovery happens only after the rejected record is captured, outside that timer/counter record. Reusing the old kernel-count baseline for the recovery check is harmless here because both reject and recovery assert zero solid work.
- `--check-only` performs one iteration of all five paths, recovery and old-history checks, creates no Stopwatch and prints a pass message instead of benchmark JSON. It covers one parity of each alternating edit value/order, not both. This is unchanged behavior; normal runs cover both parities.
- Timeline exception handling closes spans without swallowing operation exceptions. The metadata reports the compile-time tracing choice; all 72 normal reports have tracing disabled where supported.

No instrumentation correctness blocker was found. This was read-only source/data review: no Dart, tests, builds, profiler or timing workload was run during the parent's quiet measurement window.

## Reviewed input hashes

- `geometry-paired.json`: `4eb39d6f60ff5a2cf66b38a61e0e39f9e097bb14284e0523c89d46e02c629039`
- `geometry-summary.json`: `e2e0a6019641d1316dd2dd5580473bc1b981cf1cbeff1e28d76ca311278ed075`
- `geometry-audit.json`: `f008abddaec363bd0d2bd7ec872a72a9f675770eca815b4e747dd3fa31f66d04`

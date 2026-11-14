# Mesh candidate qualification — 2026-11-14

## Decision

Reject the mesh production candidate for this consolidation. Preserve its source
branch and merge history, keep its regression tests and all measurements, and
retain the PR #8 tessellator in `lib/src/cad/reference_kernel.dart`.

The source review found no correctness blocker, and all fresh focused tests and
benchmark physical checks passed. The complete-operation comparison does not
show a sufficiently consistent benefit for the target linkage workload. AOT
plate operations improve, but coupler edits are approximately unchanged or
slower and several control tails worsen. There is no need to rerun this cohort
in search of a more favorable result.

## Frozen source and method

- Before: PR #8 `6faf18a5b4a776755e5f47e47f520de4f1d89635`, library tree
  `a9fc347644d9d0cfdc52c460bdc222ae2678958e`.
- After: mesh candidate `199ce0ce3eb7310d2f2d6b7b2fc2735e8a1ff6f9`, library tree
  `34efd8bb98b1292469bdb52694f5067d28ae13b3`.
- The only production difference is the private reference tessellator's corner
  index reuse and top-center point reuse, introduced at `504c795`.
- Dart 3.14.0 stable, Linux x64, shared container with inherited CPU affinity.
- Four alternating fresh before/after pairs for each JIT/AOT mode, across the
  plate, linkage and assembly harnesses: 48 reports, 400 measured samples per
  operation after 40 warmups. AOT compilation is outside measured sections.
- Harnesses and example dependencies are identical. Explicit package mappings
  resolve each checkout to its own library. The runner checks committed clean
  library files, package configuration, lockfile and frozen harness bytes.
- Timing processes are sequential; other agents paused CPU-heavy work. One
  lightweight checkpoint copy/compression/commit preserved progress during the
  cohort. The shared host was not CPU-pinned or otherwise controlled.
- Every reported row uses the median of four per-process percentiles, not a
  pooled percentile. No samples or processes were removed. Pair direction is
  reported separately because an aggregate can move opposite to most pairs.

## Results and interpretation

AOT plate cold/profile/thickness medians improve 4.1%, 4.8% and 4.8%, with three
of four paired medians faster for each row. The plate cold p95 improves in all
four pairs under both runtimes. These are real observations from this cohort,
not evidence of a universal mesh or CAD speedup.

The intended coupler path has a JIT median of 554 → 551.5 µs (−0.45%, two faster
pairs) and AOT median 530 → 541 µs (+2.1%, two faster pairs). AOT coupler p95
rises 844 → 872 µs (+3.3%, three slower pairs); JIT coupler p99 rises
1,498.5 → 1,592 µs (+6.2%, split two/two). The candidate does not resolve the
separately recorded native-rounding JIT p99 issue.

Linkage angle-edit p95 worsens in every pair under both runtimes: +5.5% JIT and
+16.5% AOT. AOT rejected-angle p95 rises 20.4%, also every pair; AOT
placement-only p99 rises 36.3%, every pair. Those retained controls do not
execute tessellation during their timed operation, so these measurements do
not establish a direct cost of the edited function. They do constrain any
claim that the entire candidate improves interactive latency. Assembly pose
tails show substantial gains at the same time, further illustrating why a
single favorable control is not a causal explanation.

The full result is therefore preserved as a qualified rejected trial. The
branch remains a useful future experiment, and the semantic regressions remain
valuable with the prior tessellator.

## Complete table

Percent changes are after/before − 1; negative means less elapsed time. A faster
pair count does not count ties. Every row has four pairs.

### JIT

| Operation | Median, µs | p95, µs | p99, µs | Faster pairs: median / p95 / p99 |
|---|---:|---:|---:|---:|
| Plate cold | 737 → 697 (-5.4%) | 1,466.5 → 1,292.5 (-11.9%) | 2,092.5 → 2,029 (-3.0%) | 3/4 / 4/4 / 1/4 |
| Plate profile edit | 688 → 725.5 (+5.5%) | 1,310.5 → 1,218 (-7.1%) | 2,072.5 → 2,145.5 (+3.5%) | 2/4 / 3/4 / 2/4 |
| Plate thickness edit | 549 → 544 (-0.9%) | 940 → 942.5 (+0.3%) | 1,623 → 1,930.5 (+18.9%) | 2/4 / 2/4 / 1/4 |
| Linkage cold | 1,733.5 → 1,740.5 (+0.4%) | 2,642.5 → 2,491 (-5.7%) | 4,550.5 → 4,144 (-8.9%) | 2/4 / 3/4 / 1/4 |
| Linkage angle edit | 186.5 → 186.5 (+0.0%) | 371 → 391.5 (+5.5%) | 572 → 704 (+23.1%) | 2/4 / 0/4 / 1/4 |
| Linkage coupler edit | 554 → 551.5 (-0.5%) | 871.5 → 852 (-2.2%) | 1,498.5 → 1,592 (+6.2%) | 2/4 / 3/4 / 2/4 |
| Linkage placement edit | 83.5 → 81 (-3.0%) | 144 → 158 (+9.7%) | 297 → 283.5 (-4.5%) | 2/4 / 2/4 / 3/4 |
| Linkage rejected angle | 161 → 157 (-2.5%) | 309 → 285 (-7.8%) | 563 → 555.5 (-1.3%) | 3/4 / 3/4 / 3/4 |
| Assembly cold | 586.5 → 547 (-6.7%) | 1,362 → 1,344.5 (-1.3%) | 2,180.5 → 2,256 (+3.5%) | 3/4 / 2/4 / 2/4 |
| Assembly pose edit | 110 → 109.5 (-0.5%) | 308 → 348.5 (+13.1%) | 821.5 → 638 (-22.3%) | 3/4 / 1/4 / 3/4 |

### AOT

| Operation | Median, µs | p95, µs | p99, µs | Faster pairs: median / p95 / p99 |
|---|---:|---:|---:|---:|
| Plate cold | 715.5 → 686 (-4.1%) | 1,014.5 → 971.5 (-4.2%) | 1,323.5 → 1,152.5 (-12.9%) | 3/4 / 4/4 / 2/4 |
| Plate profile edit | 735.5 → 700 (-4.8%) | 1,016 → 965 (-5.0%) | 1,413.5 → 1,068.5 (-24.4%) | 3/4 / 3/4 / 3/4 |
| Plate thickness edit | 650 → 619 (-4.8%) | 941 → 881.5 (-6.3%) | 1,103.5 → 978.5 (-11.3%) | 3/4 / 3/4 / 2/4 |
| Linkage cold | 1,747.5 → 1,758 (+0.6%) | 2,274 → 2,379.5 (+4.6%) | 3,699.5 → 4,385.5 (+18.5%) | 2/4 / 2/4 / 2/4 |
| Linkage angle edit | 139.5 → 143 (+2.5%) | 242 → 282 (+16.5%) | 559 → 522.5 (-6.5%) | 2/4 / 0/4 / 2/4 |
| Linkage coupler edit | 530 → 541 (+2.1%) | 844 → 872 (+3.3%) | 1,633 → 1,615.5 (-1.1%) | 2/4 / 1/4 / 2/4 |
| Linkage placement edit | 65 → 67.5 (+3.8%) | 107 → 120 (+12.1%) | 201 → 274 (+36.3%) | 0/4 / 0/4 / 0/4 |
| Linkage rejected angle | 122.5 → 124.5 (+1.6%) | 183.5 → 221 (+20.4%) | 382.5 → 466.5 (+22.0%) | 2/4 / 0/4 / 1/4 |
| Assembly cold | 309 → 306.5 (-0.8%) | 557.5 → 484.5 (-13.1%) | 811.5 → 660.5 (-18.6%) | 3/4 / 3/4 / 3/4 |
| Assembly pose edit | 35 → 35.5 (+1.4%) | 96 → 52 (-45.8%) | 184 → 89 (-51.6%) | 2/4 / 4/4 / 4/4 |

## Verification

The fresh candidate `test/cad_reuse_test.dart` run passes all nine native tests,
including ordered fingerprints, exact signed-zero ownership, unresolved-area
issue ordering and custom validator/getter behavior. The three harnesses report
successful independent physical/reuse/rollback checks for every one of the 48
reports. This candidate-specific check is separate from the consolidated
source's full native and portable suites.

Independent fixture/source reconciliation passes 405,818 assertions with no
findings. It verifies 88 library-file byte comparisons (44 per revision), six
harness hashes, eight example-dependency hashes, all 160 timing distributions,
64,000 raw samples and 64,000 aligned work records. All 400 reported p50/p95/p99
values are reconciled across the independent audits; derived p99 values are
also preserved for the harnesses that omit p99 from their original summary.

Independent normal-data reconstruction passes 33,244 checks, including 32,000
exact before/after per-sample work comparisons. The subprocess audit passes
1,286 checks: all 125 saved subprocess records succeed without timeout, all 250
stdout/stderr byte hashes match, and all six compile records and 48 benchmark
records match their command/source/result chains. Source and package mappings
remain frozen through final checks.

The runner does not hash SDK/AOT executable bytes or installed dependency source
bytes; its exact command chain and project/package identities should not be
misstated as those additional provenance guarantees. The reports retain oracle
pass records and work counters rather than full geometry coordinates. No
statistical significance, allocated-byte reduction, GC attribution or latency
guarantee is established by this shared-host cohort.

## Evidence and reproduction

The evidence index is
`benchmark/results/2026-11-14-consolidation-mesh-evidence.json`. It records SHA-256
for the complete raw archive, normal summary, independent percentile/work
reconstruction, source/fixture audit, subprocess audit and execution logs.
The raw archive replaces the in-progress version in file history; the earlier
20-of-48-report checkpoint remains reachable in Git.

Use clean worktrees at the before/after commits above, run `dart pub get` in
each, and use the same Dart executable and dependency cache. The measured
command was equivalent to:

```sh
python3 tool/compare_performance.py \
  --before /path/to/before --after /path/to/after \
  --dart /path/to/dart-sdk/bin/dart \
  --benchmarks cad cad_linkage cad_instances --modes jit aot \
  --rounds 4 --samples 400 --warmups 40 --run-timeout 180 \
  --output /path/to/paired.json
```

Then run `tool/summarize_performance.py`, `tool/audit_cad_measurements.py`
(with both frozen worktree paths), `tool/audit_recovery_normal.py` and
`tool/audit_recovery_processes.py` against the complete saved cohort. The source
review and recovered interrupted trace analysis are in
`doc/consolidation-tail-review-2026-11-14.md`.

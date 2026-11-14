# Independent guarded-rounding retention assessment

## Assessment

This cohort supports **qualified retention as a native median/p95 optimization**.
The subsequent numerical controls, portable comparison and complete local
native/Node gates are recorded in [the final report](performance-tail-recovery-2026-11-14.md);
browser/platform CI remains open. It does not support an unqualified
tail-latency improvement claim. The JIT coupler p99
regression is material, repeats in all four pairs and remains unresolved. Keep
that cost explicit in the retention decision and preserve every sample; do not
attribute it to warmup, GC or noise without separate evidence.

The strongest result is the four retained AOT linkage edits: their aggregate
medians improve 11.4–39.4% and p95 improves 7.3–34.5%, with every individual pair
faster for both percentiles. All four retained JIT edit medians also improve in
every pair, by 20.9–50.7% between aggregate medians. This is substantially more
consistent target-workload evidence than the earlier rejected placement trials.

The narrow production change is the guarded `IntervalRounding.nextUp` storage
access. Baseline is main `b3e14fbb298c8d4f3714debbeaffaeb6d550db51`; candidate is
`90b4a3e1e11d3404814e51a34add4be723a3cbe5`. Every other production file, including
CAD placement, is byte-identical to main. The prior source review found no
correctness blocker and documents the independent bit-pattern oracle and the
compile-time web fallback. This timing review runs no Dart workload.

## Verification and provenance

The completed cohort contains four fresh process pairs for each of three
fixtures in both native runtimes, 400 measured samples after 40 warmups, 48
reports and 20 operation/runtime rows. Runs are sequential and revision order
alternates by round. AOT compilation occurs before benchmark execution. No
samples or process pairs were discarded.

- Project auditor: **405,818 assertions**, zero findings.
- Independent reconstruction importing no project code: **33,244 checks**,
  zero findings. All 160 distributions, 64,000 samples, 64,000 aligned work
  records and 400 explicitly reported percentile values reconcile. Derived p99
  values and every summary aggregate were recomputed from the samples.
- All **32,000 paired per-sample work records match exactly**. The fixtures'
  independent physical-oracle pass records and rebuild/reuse counters reconcile.
- Independent subprocess review: **1,286 checks**, zero findings, covering 125
  processes, 250 lossless stdout/stderr byte hashes, six compiles and all 48
  benchmark references. Every recorded process exited zero without timeout;
  timestamps are sequential; original stdout parses to the retained results;
  explicit package mappings and compile/run output identities agree.
- Independent source/configuration review: **279 checks**, zero findings.
  All 88 baseline/candidate library-file comparisons match their frozen Git
  objects and recorded hashes, as do six harness copies and eight fixture
  dependency copies. Lock/configuration digests reconcile. Identical relative
  package-configuration bytes resolve to **different worktree library roots**,
  avoiding accidental baseline/candidate aliasing. No recorded compile or
  benchmark command overrides `dart.library.io`.

Raw JSON SHA-256:
`51babdb9e112bf4611b0949064494e345e6d0fe0fe8d0d63afacc351c1077f03`.

Candidate `continuous.dart` SHA-256:
`6ae21fd6dba5fc9e4fd49017fb54ddcd270773a8dc3e14f0fc2c7ca219aa83f3`.

Both revisions' `placement.dart` SHA-256:
`782dd230d4279cdd940bedd4f0d75e359a7224ab9bd1cef36fe01c14dccb9f57`.

Audit outputs are the [project audit](../benchmark/results/2026-11-14-recovery-rounding-cad-audit.json),
[independent reconstruction](../benchmark/results/2026-11-14-recovery-rounding-cad-independent.json),
[process audit](../benchmark/results/2026-11-14-recovery-rounding-cad-process-audit.json)
and [identity audit](../benchmark/results/2026-11-14-recovery-rounding-identity-audit.json).
The separate [guarded source review](performance-tail-recovery-rounding-guard-review.md)
documents semantics. Raw timing provenance reports Dart
3.14.0 stable on Linux x64 and an AMD EPYC 9V45 shared container with inherited
CPU affinity across nine logical CPUs. Benchmark runs span
2026-11-14 09:50:20–09:53:58 UTC.

## Gains and adverse tails

AOT retained edit median and p95 improvements are directionally consistent in
all 16 corresponding pairs per percentile. Placement p99 also improves in all
four pairs (aggregate −31.4%). Coupler p99 improves in three pairs and by 37.8%
between aggregate medians. Angle and rejected-edit p99 aggregates improve 20.6%
and 37.0%, but each splits into two faster and two slower pairs; their aggregate
gains must not be described as consistent p99 improvements.

JIT retained medians improve in every pair. Coupler and placement p95 improve in
all four pairs; angle improves in three with one tie, while rejected-edit p95
improves in three and worsens 3.1% in the fourth. The main adverse result is
**JIT coupler p99: 1,735.5→2,711 microseconds, +56.2%, slower in every pair**.
The individual p99 comparisons are:

| Pair | Before μs | After μs | Change |
|---|---:|---:|---:|
| 1 | 1,716 | 1,856 | +8.2% |
| 2 | 1,925 | 2,693 | +39.9% |
| 3 | 1,717 | 2,729 | +58.9% |
| 4 | 1,754 | 2,787 | +58.9% |

Those candidate tail samples are not confined to the first measured operations.
For example, the five largest samples in pair 3 occur at zero-based measured
indices 181, 182, 356, 357 and 358; pair 4 includes indices 127, 200, 213 and 214.
[The tail-index artifact](../benchmark/results/2026-11-14-recovery-rounding-jit-tail-indices.json) preserves all eight processes' tail
positions. This observation rules out dismissing the entire result as initial
measured warmup; it identifies no compiler/GC cause. The normal cohort has no
operation-level GC or compilation attribution.

JIT linkage cold p99 also increases 8.6%, with three adverse pairs. JIT angle
p99 increases 5.8%, split two/two. JIT placement and rejected-edit p99 improve
34.8% and 33.2% in aggregate, each with three faster pairs and one slower pair.
These mixed tails should accompany the strong median/p95 headline.

## Assembly and controls

Assembly pose medians improve in every JIT and AOT pair. JIT pose p95 and p99
also improve in every pair. AOT pose p95 is mixed: the aggregate improves 4.5%,
but two pairs worsen (+52.0% and +12.9%) and two improve; its median paired
change is only −0.6%. This does not demonstrate consistent AOT pose-tail gains.

Assembly cold aggregates improve in both runtimes, except JIT p99 (+3.1%, two
faster/two slower). JIT cold p50/p95 improve in three pairs and worsen in one.
AOT cold p50 splits two/two despite its −3.7% aggregate; p95 and p99 improve in
three pairs with one regression (+27.2% and +47.3%, respectively). Unlike the
recovered wrapper-elision change, this cohort does not show a repeated assembly
cold regression, but it does not establish a uniform cold-build improvement.

The plate fixture has no body-instance/placement operations, and the reviewed
sketch/geometry/reference-kernel call paths do not execute the changed rounding
routine. Its movement is contextual control evidence. AOT plate cold/profile/
thickness medians nevertheless increase 2.5%/1.3%/2.0%, with two/three/three
adverse pairs. JIT plate profile p95 and p99 increase 3.7% and 6.8%, each split
two/two. JIT plate medians improve in three pairs but worsen together in pair 3
by 13.0%, 11.7% and 22.8%; that pair's thickness p99 increases 366.6%.

Control changes show that host/process/compiler-context variation exists; they
neither identify its cause nor cancel the target rows' regressions. Do not
subtract control changes from target changes. In particular, the repeated JIT
coupler p99 regression occurs in all four pairs, not just the third JIT pair
with unusually adverse plate controls.

## Complete operation tables

All times are microseconds. Changes compare medians of the four per-process
percentiles, never pooled samples. The harness p50 uses its upper-middle sample
convention; p95/p99 use nearest rank. Pair counts are **faster/slower/equal**.
At 400 samples per process only four observations lie above the p99 order
statistic (ignoring ties), so p99 is limited tail evidence even when its pair
direction repeats. Full paired percentages and median paired changes remain in
[the independent reconstruction](../benchmark/results/2026-11-14-recovery-rounding-cad-independent.json).

### JIT

| Operation | p50 before→after | p50 Δ; pairs | p95 before→after | p95 Δ; pairs | p99 before→after | p99 Δ; pairs |
|---|---:|---:|---:|---:|---:|---:|
| Assembly cold | 746→570.5 | −23.5%; 3/1/0 | 1716.5→1379.5 | −19.6%; 3/1/0 | 2606.5→2688.5 | +3.1%; 2/2/0 |
| Assembly pose | 152→108 | −28.9%; 4/0/0 | 449.5→363 | −19.2%; 4/0/0 | 957→748.5 | −21.8%; 4/0/0 |
| Linkage cold | 1991→1806 | −9.3%; 4/0/0 | 2963→2933.5 | −1.0%; 2/2/0 | 4419.5→4798 | +8.6%; 1/3/0 |
| Angle edit | 306.5→195 | −36.4%; 4/0/0 | 557.5→432.5 | −22.4%; 3/0/1 | 888.5→940 | +5.8%; 2/2/0 |
| Coupler edit | 717→567 | −20.9%; 4/0/0 | 1148→993 | −13.5%; 4/0/0 | 1735.5→2711 | +56.2%; 0/4/0 |
| Placement edit | 173.5→85.5 | −50.7%; 4/0/0 | 306→175.5 | −42.6%; 4/0/0 | 539.5→352 | −34.8%; 3/1/0 |
| Rejected edit | 270→166 | −38.5%; 4/0/0 | 478.5→369.5 | −22.8%; 3/1/0 | 1117→746.5 | −33.2%; 3/1/0 |
| Plate cold control | 778.5→723 | −7.1%; 3/1/0 | 1538.5→1462 | −5.0%; 2/2/0 | 2456→2101 | −14.5%; 2/2/0 |
| Plate profile control | 723→711 | −1.7%; 3/1/0 | 1328→1377.5 | +3.7%; 2/2/0 | 2030→2168.5 | +6.8%; 2/2/0 |
| Plate thickness control | 573→561.5 | −2.0%; 3/1/0 | 1072→999 | −6.8%; 3/1/0 | 1747→1693.5 | −3.1%; 2/2/0 |

### AOT

| Operation | p50 before→after | p50 Δ; pairs | p95 before→after | p95 Δ; pairs | p99 before→after | p99 Δ; pairs |
|---|---:|---:|---:|---:|---:|---:|
| Assembly cold | 356→343 | −3.7%; 2/2/0 | 600.5→568.5 | −5.3%; 3/1/0 | 914.5→737 | −19.4%; 3/1/0 |
| Assembly pose | 49→37 | −24.5%; 4/0/0 | 99.5→95 | −4.5%; 2/2/0 | 196.5→173 | −12.0%; 3/1/0 |
| Linkage cold | 1842→1730.5 | −6.1%; 3/0/1 | 2606→2403 | −7.8%; 3/1/0 | 4211.5→4213.5 | +0.05%; 3/1/0 |
| Angle edit | 192→141.5 | −26.3%; 4/0/0 | 341→268.5 | −21.3%; 4/0/0 | 618→490.5 | −20.6%; 2/2/0 |
| Coupler edit | 599→530.5 | −11.4%; 4/0/0 | 903→837 | −7.3%; 4/0/0 | 1880.5→1169.5 | −37.8%; 3/1/0 |
| Placement edit | 113→68.5 | −39.4%; 4/0/0 | 179.5→117.5 | −34.5%; 4/0/0 | 325→223 | −31.4%; 4/0/0 |
| Rejected edit | 168→124 | −26.2%; 4/0/0 | 262.5→205.5 | −21.7%; 4/0/0 | 646→407 | −37.0%; 2/2/0 |
| Plate cold control | 689.5→706.5 | +2.5%; 2/2/0 | 1008→1036.5 | +2.8%; 3/1/0 | 1733.5→1286.5 | −25.8%; 3/1/0 |
| Plate profile control | 710.5→719.5 | +1.3%; 1/3/0 | 1011→1010 | −0.10%; 3/1/0 | 1294.5→1210 | −6.5%; 3/1/0 |
| Plate thickness control | 624.5→637 | +2.0%; 1/3/0 | 927.5→946.5 | +2.0%; 2/2/0 | 1403.5→1295 | −7.7%; 3/1/0 |

## Retention boundary and remaining gates

The subsequent portable comparison, numerical controls and native/Node gates
are complete; browser/platform CI remains open. A defensible retained-change
statement is that it improves the measured native retained-edit medians and
most p95 latency, while preserving a material unresolved JIT coupler p99 cost
and mixed cold/pose tails. It cannot be reported as eliminating the original
tail-latency problem or speeding up every workload. If a release requires no
measured tail regression, that requirement is not met by this cohort.

The repeated p99 cost is a concrete subject for a focused follow-up if needed;
it does not justify deleting samples, lengthening warmups retroactively or
relabeling the affected run as diagnostic. Future evidence should supplement
this frozen cohort rather than replace it.

Four pairs in a shared container do not establish a universal ranking,
statistical significance, a latency guarantee or a causal allocation/GC claim.
Physical work equality is supported by serialized counters and independent
harness pass records; complete geometry outputs are not serialized for a
separate bitwise replay. Subprocess provenance records command/result and
source/configuration relationships, but does not hash the SDK, generated
executables or installed dependency source bytes. Current source comparison
corroborates collection metadata; it is not another execution-time capture.
The separate bit-semantics review and reported backend regressions support
correctness, not measured allocated bytes or performance on other platforms.

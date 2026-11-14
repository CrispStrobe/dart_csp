# Independent guarded-rounding numerical-control assessment

## Conclusion

The numerical-control cohort passes its data, source and physical-work audits.
It adds no observed correctness failure, but it contains substantial adverse
JIT timings and does **not** establish absence of collateral performance costs.
Retain every row alongside the native target gains. These fixtures do not
execute the changed rounding routine in their measured paths, so their movement
cannot be labeled a direct rounding speedup or slowdown without further causal
evidence. Do not adjust the target rows by subtracting control changes.

The main comparison remains main
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51` versus guarded source
`90b4a3e1e11d3404814e51a34add4be723a3cbe5`. The sole production delta is
`lib/src/continuous.dart`; all geometry, graph and placement sources match main.
This reviewer executed no Dart or timing workload.

## Acquisition and verification

The complete cohort has **48 reports, 32 rows, three fresh process pairs per
fixture/runtime, 25 samples and five warmups**. The numerical harnesses use
their source-defined counts; graph arguments explicitly select the same counts
and sizes 1,000 and 10,000. The four fixtures are nonlinear linkage geometry,
coupled geometry, a coupled CAD workspace and a scalar feature graph. Native
JIT/AOT processes run sequentially with alternating revision order; AOT
compilation is outside the measurement. No samples or runs were removed.

- Project auditor: **2,588 assertions**, zero findings.
- Independent reconstruction: **2,074 checks**, zero findings. All **192
  distributions, 4,800 samples and 384 reported p50/p95 values** reconcile.
- All **72 per-report physical-work snapshots** satisfy their fixed expected
  counters, and all **36 paired snapshots** match. Every report records its
  independent physical/value/rollback oracle as passed. There are no aligned
  per-sample work arrays in this cohort; do not claim one from these results.
- Subprocess provenance: **1,327 checks**, zero findings; **131 processes,
  262 stream hashes, eight compiles and 48 benchmark records** reconcile.
- Source/package identity: **271 checks**, zero findings; 88 library-file
  comparisons, eight harness copies and two fixture dependency copies match
  the recorded/frozen bytes. Explicit package maps resolve to different roots.

Raw JSON SHA-256:
`0feb73f8e925c6536e7f2e59b1c0fe09afe2dc27b197a6772a7221472cbcb9ea`.

## Adverse and favorable controls

All six JIT numerical median aggregates increase: nonlinear cold/warm
**+9.6%/+15.6%**, coupled cold/warm **+5.9%/+16.8%**, and workspace cold/warm
**+24.7%/+51.2%**. Nonlinear warm is slower in all three median pairs; most other
rows have one favorable pair. Coupled cold illustrates why pairing matters:
its median aggregate increases 5.9%, although two pairs improve and the median
paired change is −6.8%. Workspace warm p95 decreases 4.0% between aggregate
medians despite two slower pairs and a +39.4% median paired change.

JIT graph controls also contain repeated adverse medians: 1,000-feature cold
**+10.3%**, 10,000-feature sparse **+28.6%**, 10,000-feature no-op **+42.9%** and
10,000-feature unused-parameter **+20.0%**, all slower in three pairs. The
no-op/unused absolute changes are only 7→10 and 10→12 microseconds. The
1,000-feature sparse p95 increases 49→107 microseconds (+118.4%), with two
adverse pairs. Large relative changes near timer granularity need their
absolute times, which are preserved below.

AOT numerical results are more favorable: coupled cold/warm medians improve
7.3%/4.6% and workspace cold/warm improve 4.2%/4.9%, all faster in every pair;
their p95s also improve in every pair. Nonlinear AOT medians are close to
unchanged. Those gains remain contextual observations, because these paths do
not invoke the modified primitive. AOT graph medians are mostly unchanged or
slightly lower, but 1,000-feature cold p95 increases 9.2% with two adverse pairs
and its process maximum increases in all three pairs.

These data preserve the earlier qualified-retention conclusion for the target
native median/p95 gains, while strengthening the need to avoid a claim that
all workloads improve. They do not explain away the separate four-pair JIT
coupler p99 regression in the 400-sample target cohort.

## Complete rows

Times are microseconds; each before/after value is the median of three process
percentiles. Pair counts are **faster/slower/equal**. An em dash means a relative
change is undefined because the baseline aggregate is zero. No percentiles are
pooled. With only 25 samples per process, the derived nearest-rank p99 equals
the maximum; it is labeled **Max** below and is not a reliable p99 estimate.
The JSON includes all per-process values and individual pair percentages.

### JIT

| Operation | p50 before→after | p50 Δ; pairs | p95 before→after | p95 Δ; pairs | Max before→after | Max Δ; pairs |
|---|---:|---:|---:|---:|---:|---:|
| Nonlinear cold | 669→733 | +9.6%; 1/2/0 | 1100→1145 | +4.1%; 1/2/0 | 1604→1549 | −3.4%; 2/1/0 |
| Nonlinear warm | 397→459 | +15.6%; 0/3/0 | 909→1005 | +10.6%; 1/2/0 | 1637→2229 | +36.2%; 0/3/0 |
| Coupled cold | 1460→1546 | +5.9%; 2/1/0 | 2267→2080 | −8.2%; 2/1/0 | 2324→2450 | +5.4%; 1/2/0 |
| Coupled warm | 596→696 | +16.8%; 1/2/0 | 1634→1495 | −8.5%; 2/1/0 | 2161→1662 | −23.1%; 3/0/0 |
| Workspace cold | 1373→1712 | +24.7%; 1/2/0 | 2898→2424 | −16.4%; 2/1/0 | 3034→2697 | −11.1%; 2/1/0 |
| Workspace warm | 615→930 | +51.2%; 1/2/0 | 1935→1857 | −4.0%; 1/2/0 | 2106→2851 | +35.4%; 1/2/0 |
| Graph 1000 cold build regenerate | 939→1036 | +10.3%; 0/3/0 | 2602→3016 | +15.9%; 1/2/0 | 3815→3809 | −0.2%; 2/1/0 |
| Graph 1000 sparse edit | 22→21 | −4.5%; 2/1/0 | 49→107 | +118.4%; 1/2/0 | 116→719 | +519.8%; 1/2/0 |
| Graph 1000 no op edit | 3→4 | +33.3%; 0/2/1 | 9→14 | +55.6%; 0/3/0 | 68→41 | −39.7%; 1/2/0 |
| Graph 1000 unused parameter edit | 6→6 | +0.0%; 1/1/1 | 23→26 | +13.0%; 1/2/0 | 44→59 | +34.1%; 1/2/0 |
| Graph 1000 rejected edit | 10→10 | +0.0%; 1/1/1 | 33→26 | −21.2%; 2/1/0 | 34→47 | +38.2%; 1/2/0 |
| Graph 10000 cold build regenerate | 9233→9202 | −0.3%; 2/1/0 | 17635→15568 | −11.7%; 2/1/0 | 22888→17780 | −22.3%; 2/1/0 |
| Graph 10000 sparse edit | 35→45 | +28.6%; 0/3/0 | 72→77 | +6.9%; 0/2/1 | 98→103 | +5.1%; 0/3/0 |
| Graph 10000 no op edit | 7→10 | +42.9%; 0/3/0 | 39→24 | −38.5%; 3/0/0 | 40→60 | +50.0%; 1/2/0 |
| Graph 10000 unused parameter edit | 10→12 | +20.0%; 0/3/0 | 31→26 | −16.1%; 1/1/1 | 45→31 | −31.1%; 1/2/0 |
| Graph 10000 rejected edit | 14→16 | +14.3%; 0/2/1 | 29→29 | +0.0%; 2/1/0 | 34→51 | +50.0%; 0/3/0 |

### AOT

| Operation | p50 before→after | p50 Δ; pairs | p95 before→after | p95 Δ; pairs | Max before→after | Max Δ; pairs |
|---|---:|---:|---:|---:|---:|---:|
| Nonlinear cold | 65→64 | −1.5%; 2/0/1 | 192→162 | −15.6%; 2/1/0 | 210→210 | +0.0%; 1/1/1 |
| Nonlinear warm | 45→45 | +0.0%; 1/0/2 | 113→99 | −12.4%; 3/0/0 | 163→245 | +50.3%; 1/2/0 |
| Coupled cold | 895→830 | −7.3%; 3/0/0 | 1108→945 | −14.7%; 3/0/0 | 1238→951 | −23.2%; 3/0/0 |
| Coupled warm | 564→538 | −4.6%; 3/0/0 | 823→595 | −27.7%; 3/0/0 | 1001→626 | −37.5%; 3/0/0 |
| Workspace cold | 896→858 | −4.2%; 3/0/0 | 1183→976 | −17.5%; 3/0/0 | 1260→1025 | −18.7%; 3/0/0 |
| Workspace warm | 596→567 | −4.9%; 3/0/0 | 773→679 | −12.2%; 3/0/0 | 774→788 | +1.8%; 1/2/0 |
| Graph 1000 cold build regenerate | 362→361 | −0.3%; 2/1/0 | 568→620 | +9.2%; 1/2/0 | 857→1039 | +21.2%; 0/3/0 |
| Graph 1000 sparse edit | 4→4 | +0.0%; 0/0/3 | 7→5 | −28.6%; 1/1/1 | 7→7 | +0.0%; 1/1/1 |
| Graph 1000 no op edit | 0→0 | —; 0/0/3 | 0→1 | —; 0/2/1 | 1→1 | +0.0%; 0/1/2 |
| Graph 1000 unused parameter edit | 0→0 | —; 0/0/3 | 1→1 | +0.0%; 0/1/2 | 1→2 | +100.0%; 0/2/1 |
| Graph 1000 rejected edit | 1→1 | +0.0%; 0/0/3 | 2→2 | +0.0%; 0/1/2 | 2→3 | +50.0%; 0/2/1 |
| Graph 10000 cold build regenerate | 6112→6061 | −0.8%; 2/1/0 | 12640→12030 | −4.8%; 3/0/0 | 15355→12917 | −15.9%; 2/1/0 |
| Graph 10000 sparse edit | 12→11 | −8.3%; 2/0/1 | 24→25 | +4.2%; 2/1/0 | 44→43 | −2.3%; 2/1/0 |
| Graph 10000 no op edit | 2→2 | +0.0%; 1/0/2 | 5→5 | +0.0%; 2/1/0 | 7→6 | −14.3%; 2/0/1 |
| Graph 10000 unused parameter edit | 2→2 | +0.0%; 0/0/3 | 5→5 | +0.0%; 1/0/2 | 5→6 | +20.0%; 1/1/1 |
| Graph 10000 rejected edit | 4→4 | +0.0%; 0/0/3 | 6→6 | +0.0%; 1/0/2 | 14→7 | −50.0%; 2/1/0 |

## Reproducible evidence and limits

The [canonical summary](../benchmark/results/2026-11-14-recovery-rounding-controls-summary.json)
was independently reconstructed by
[audit_recovery_controls.py](../tool/audit_recovery_controls.py), producing the
[independent audit and pair directions](../benchmark/results/2026-11-14-recovery-rounding-controls-independent.json).
Additional evidence includes the
[project audit](../benchmark/results/2026-11-14-recovery-rounding-controls-audit.json),
[subprocess audit](../benchmark/results/2026-11-14-recovery-rounding-controls-process-audit.json)
and [source identity audit](../benchmark/results/2026-11-14-recovery-rounding-controls-identity-audit.json).
The subprocess checks are implemented in
[audit_recovery_processes.py](../tool/audit_recovery_processes.py).

The first final provenance audit falsely reported 36 sampling-argument findings:
Python's `command[-len(arguments):]` selects the whole command when `arguments`
is empty. The corrected auditor compares complete compile/run commands,
including empty argument lists for source-defined defaults; it also checks
sample/warmup declarations against explicit flags and across each fixture's
processes. The frozen benchmark inputs and timing values are unchanged. The
[original failed audit](../benchmark/results/2026-11-14-recovery-rounding-controls-process-audit-initial-failure.json)
and [correction record with successful reruns](../benchmark/results/2026-11-14-recovery-rounding-process-audit-correction.json)
preserve that audit history.

This is a short control cohort in the same shared Linux container. Five
warmups and 25 observations are not a long steady-state JIT characterization.
The measurements include process/compiler/host context; no trace identifies
its causes. Oracle pass records and fixed snapshots support expected physical
work, but complete geometry and per-sample counters are not serialized.
Native SDK/AOT executable and installed dependency source bytes are not hashed
in this collector. The source and configuration identities remain verified.

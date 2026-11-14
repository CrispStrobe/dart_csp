# Packed sparse factors: independent small-QR/CAD control review — 2026-11-14

## Scope and result

**The complete control cohort passes source, subprocess, fixture, work-parity and percentile audits.** This is a collateral-control review; retention of packed sparse factors requires the separately qualified sparse targets and source validation. No timing or solver workload was rerun for this review.

The baseline is `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9` and the candidate is `4325386e689566a903309accd66aca3ced1159f7`. Their sole library difference is `lib/src/geometry/sparse_ldlt.dart`. These small-QR, plate and linkage controls exercise other solver paths; timing differences do not establish that packed factors caused the observations. They are preserved as measured costs and benefits without discarding unfavorable processes.

Across 40 aggregate median rows, **27 are lower, 1 equal and 12 higher**. This is an unweighted descriptive count. The complete table below includes p50, p95, p99 and matched-pair directions for every row. All original processes and samples remain included; no cross-process sample pooling is used.

## Adverse observations

Every statistic that worsens in all three matched process pairs is listed here:

- AOT geometry_small_qr / rank_17x8 p95: 511 → 625 microseconds per 256-operation batch (+22.31%; slower/equal/faster pairs 3/0/0).
- AOT geometry_small_qr / rank_4x8 p95: 204 → 223 microseconds per 256-operation batch (+9.31%; slower/equal/faster pairs 3/0/0).
- JIT cad_linkage / cold_build_solve_solids_meshes p95: 6003 → 6264 microseconds (+4.35%; slower/equal/faster pairs 3/0/0).
- AOT geometry_small_qr / rank_4x8 p50: 163 → 164 microseconds per 256-operation batch (+0.61%; slower/equal/faster pairs 3/0/0).

The six largest remaining adverse aggregate changes are listed separately; their pair directions must not be replaced by the aggregate direction:

- AOT geometry_small_qr / rank_5x4 p95: 138 → 370 microseconds per 256-operation batch (+168.12%; slower/equal/faster pairs 2/0/1).
- AOT geometry_small_qr / rank_5x4 p99: 176 → 427 microseconds per 256-operation batch (+142.61%; slower/equal/faster pairs 2/0/1).
- AOT cad_linkage / downstream_rejected_angle_edit p99: 268 → 542 microseconds (+102.24%; slower/equal/faster pairs 2/0/1).
- AOT geometry_small_qr / rank_5x4 p50: 95 → 177 microseconds per 256-operation batch (+86.32%; slower/equal/faster pairs 2/1/0).
- AOT cad_linkage / cold_build_solve_solids_meshes p99: 3753 → 6253 microseconds (+66.61%; slower/equal/faster pairs 2/0/1).
- JIT cad_linkage / downstream_rejected_angle_edit p99: 973 → 1598 microseconds (+64.23%; slower/equal/faster pairs 2/0/1).

## Independent verification

The fixture/source auditor passes **58,278 assertions**, the process auditor passes **1,010 checks**, and the separate source-identity crosscheck passes **53 checks**, with zero findings. The 36 reports contain three alternating before/after rounds in each of JIT and AOT, with 20 warmups and 101 measured samples per case. All 240 distributions expose their raw timings: **24,240 samples or batches**.

All **9,696 CAD work records** satisfy the fixture invariants and all **4,848 matched before/after work records** agree exactly. All 40 aggregate rows and 36 harness-published plate p99 values reconcile to raw samples. The numerical checks run outside the timers in each harness. Their pass records and aligned work counters are serialized; the control records do not contain full numerical coordinates or QR matrices for a second independent physical replay.

The process audit reconciles 101 subprocess records, 202 original-stream digests, six compilations and all 36 benchmark links. Sources match the exact committed blobs and the two live frozen worktrees; complete library inventories, package configuration, dependency lock, harness and fixture hashes match. CPU affinity was recorded as `[0]`. Affinity does not imply exclusive ownership of that CPU.

The normal collector records the Dart version and exact compile/run command chain, but does not hash the SDK executable, AOT executable bytes or installed dependency source bytes. Stronger binary provenance from a different sparse cohort must not be attributed to this one.

## Complete non-pooled timing table

Values are microseconds. Positive percentage change means slower candidate time. S/E/F counts mean slower/equal/faster matched process values out of three. Each aggregate is the median of three per-process percentiles. QR rows time batches of 256 operations except `rank_48x48`, which times eight; CAD rows time individual complete operations.

Plate p99 values are harness-reported and independently recomputed. QR and linkage p99 values are derived screening statistics. With 101 samples, each process p99 is the second-largest observation; this small cohort does not establish a stable tail bound. `review-metrics.json` preserves all individual before/after process values, pair directions and pair percentage changes. These data do not measure allocated bytes or establish GC, compiler or other causal attribution.

### JIT

| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |
|---|---:|---:|---:|---:|---:|---:|
| geometry_small_qr / rank_5x4 | 97 → 105 (+8.25%) | 2/0/1 | 933 → 494 (-47.05%) | 1/0/2 | 6277 → 8391 (+33.68%) | 2/0/1 |
| geometry_small_qr / rank_8x4 | 113 → 113 (+0.00%) | 1/0/2 | 189 → 187 (-1.06%) | 1/0/2 | 216 → 302 (+39.81%) | 2/0/1 |
| geometry_small_qr / rank_4x5 | 102 → 96 (-5.88%) | 1/1/1 | 223 → 142 (-36.32%) | 1/0/2 | 370 → 164 (-55.68%) | 0/0/3 |
| geometry_small_qr / rank_4x8 | 139 → 140 (+0.72%) | 2/0/1 | 224 → 231 (+3.12%) | 1/0/2 | 319 → 296 (-7.21%) | 0/0/3 |
| geometry_small_qr / rank_9x4 | 112 → 114 (+1.79%) | 2/0/1 | 207 → 178 (-14.01%) | 2/0/1 | 503 → 335 (-33.40%) | 1/0/2 |
| geometry_small_qr / rank_12x4 | 129 → 134 (+3.88%) | 1/1/1 | 201 → 212 (+5.47%) | 2/0/1 | 236 → 282 (+19.49%) | 2/0/1 |
| geometry_small_qr / rank_16x8 | 411 → 398 (-3.16%) | 1/0/2 | 533 → 511 (-4.13%) | 1/0/2 | 760 → 691 (-9.08%) | 1/0/2 |
| geometry_small_qr / rank_16x9 | 459 → 464 (+1.09%) | 2/0/1 | 526 → 603 (+14.64%) | 2/0/1 | 698 → 696 (-0.29%) | 1/0/2 |
| geometry_small_qr / rank_17x8 | 419 → 417 (-0.48%) | 1/1/1 | 503 → 494 (-1.79%) | 2/0/1 | 682 → 520 (-23.75%) | 1/0/2 |
| geometry_small_qr / rank_48x48 | 578 → 565 (-2.25%) | 0/0/3 | 675 → 673 (-0.30%) | 1/0/2 | 805 → 794 (-1.37%) | 1/0/2 |
| geometry_small_qr / damped_solve_8x4 | 186 → 176 (-5.38%) | 1/0/2 | 270 → 234 (-13.33%) | 1/0/2 | 332 → 358 (+7.83%) | 2/0/1 |
| geometry_small_qr / nullspace_4x8 | 140 → 138 (-1.43%) | 1/0/2 | 242 → 198 (-18.18%) | 1/0/2 | 371 → 261 (-29.65%) | 1/0/2 |
| cad / cold_build_compile_regenerate | 931 → 946 (+1.61%) | 1/0/2 | 5289 → 5642 (+6.67%) | 1/0/2 | 7512 → 10794 (+43.69%) | 2/0/1 |
| cad / profile_edit_regenerate | 869 → 823 (-5.29%) | 1/0/2 | 5593 → 5785 (+3.43%) | 1/0/2 | 9637 → 8890 (-7.75%) | 1/0/2 |
| cad / thickness_edit_regenerate | 608 → 596 (-1.97%) | 2/0/1 | 4779 → 4988 (+4.37%) | 2/0/1 | 7519 → 7473 (-0.61%) | 1/0/2 |
| cad_linkage / cold_build_solve_solids_meshes | 2087 → 1960 (-6.09%) | 1/0/2 | 6003 → 6264 (+4.35%) | 3/0/0 | 8548 → 7836 (-8.33%) | 1/0/2 |
| cad_linkage / retained_angle_edit | 229 → 212 (-7.42%) | 0/0/3 | 696 → 854 (+22.70%) | 2/0/1 | 2686 → 2808 (+4.54%) | 2/0/1 |
| cad_linkage / selective_coupler_length_edit | 659 → 587 (-10.93%) | 0/0/3 | 2303 → 2018 (-12.38%) | 2/0/1 | 4963 → 4292 (-13.52%) | 1/0/2 |
| cad_linkage / placement_only_layer_edit | 93 → 89 (-4.30%) | 2/0/1 | 289 → 311 (+7.61%) | 2/0/1 | 1498 → 1498 (+0.00%) | 2/0/1 |
| cad_linkage / downstream_rejected_angle_edit | 208 → 188 (-9.62%) | 1/0/2 | 412 → 418 (+1.46%) | 2/0/1 | 973 → 1598 (+64.23%) | 2/0/1 |

### AOT

| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |
|---|---:|---:|---:|---:|---:|---:|
| geometry_small_qr / rank_5x4 | 95 → 177 (+86.32%) | 2/1/0 | 138 → 370 (+168.12%) | 2/0/1 | 176 → 427 (+142.61%) | 2/0/1 |
| geometry_small_qr / rank_8x4 | 120 → 115 (-4.17%) | 1/1/1 | 203 → 164 (-19.21%) | 2/0/1 | 260 → 188 (-27.69%) | 1/0/2 |
| geometry_small_qr / rank_4x5 | 109 → 108 (-0.92%) | 0/1/2 | 152 → 150 (-1.32%) | 2/0/1 | 190 → 214 (+12.63%) | 2/0/1 |
| geometry_small_qr / rank_4x8 | 163 → 164 (+0.61%) | 3/0/0 | 204 → 223 (+9.31%) | 3/0/0 | 214 → 261 (+21.96%) | 2/0/1 |
| geometry_small_qr / rank_9x4 | 123 → 122 (-0.81%) | 1/1/1 | 188 → 178 (-5.32%) | 1/0/2 | 252 → 205 (-18.65%) | 1/0/2 |
| geometry_small_qr / rank_12x4 | 144 → 140 (-2.78%) | 2/0/1 | 195 → 222 (+13.85%) | 2/0/1 | 207 → 254 (+22.71%) | 2/0/1 |
| geometry_small_qr / rank_16x8 | 429 → 408 (-4.90%) | 1/0/2 | 508 → 488 (-3.94%) | 2/0/1 | 596 → 585 (-1.85%) | 2/0/1 |
| geometry_small_qr / rank_16x9 | 481 → 486 (+1.04%) | 2/0/1 | 572 → 577 (+0.87%) | 2/0/1 | 702 → 606 (-13.68%) | 2/0/1 |
| geometry_small_qr / rank_17x8 | 448 → 478 (+6.70%) | 2/0/1 | 511 → 625 (+22.31%) | 3/0/0 | 682 → 693 (+1.61%) | 2/0/1 |
| geometry_small_qr / rank_48x48 | 608 → 585 (-3.78%) | 2/0/1 | 705 → 678 (-3.83%) | 0/0/3 | 942 → 710 (-24.63%) | 0/0/3 |
| geometry_small_qr / damped_solve_8x4 | 188 → 183 (-2.66%) | 0/0/3 | 263 → 254 (-3.42%) | 1/0/2 | 327 → 426 (+30.28%) | 1/0/2 |
| geometry_small_qr / nullspace_4x8 | 168 → 170 (+1.19%) | 2/0/1 | 212 → 207 (-2.36%) | 1/0/2 | 230 → 219 (-4.78%) | 2/0/1 |
| cad / cold_build_compile_regenerate | 697 → 691 (-0.86%) | 1/0/2 | 918 → 956 (+4.14%) | 1/0/2 | 980 → 1046 (+6.73%) | 1/0/2 |
| cad / profile_edit_regenerate | 719 → 712 (-0.97%) | 1/0/2 | 901 → 888 (-1.44%) | 0/1/2 | 1080 → 958 (-11.30%) | 0/0/3 |
| cad / thickness_edit_regenerate | 639 → 622 (-2.66%) | 0/0/3 | 809 → 793 (-1.98%) | 0/0/3 | 904 → 922 (+1.99%) | 1/0/2 |
| cad_linkage / cold_build_solve_solids_meshes | 1743 → 1702 (-2.35%) | 1/0/2 | 2388 → 2339 (-2.05%) | 1/0/2 | 3753 → 6253 (+66.61%) | 2/0/1 |
| cad_linkage / retained_angle_edit | 143 → 140 (-2.10%) | 1/0/2 | 238 → 276 (+15.97%) | 2/0/1 | 479 → 427 (-10.86%) | 1/0/2 |
| cad_linkage / selective_coupler_length_edit | 538 → 543 (+0.93%) | 2/0/1 | 711 → 805 (+13.22%) | 2/0/1 | 949 → 1003 (+5.69%) | 2/0/1 |
| cad_linkage / placement_only_layer_edit | 68 → 67 (-1.47%) | 1/1/1 | 130 → 120 (-7.69%) | 2/0/1 | 176 → 208 (+18.18%) | 2/0/1 |
| cad_linkage / downstream_rejected_angle_edit | 126 → 125 (-0.79%) | 1/0/2 | 184 → 179 (-2.72%) | 1/0/2 | 268 → 542 (+102.24%) | 2/0/1 |

## Reproduction

```sh
python3 audit_control_cohort.py raw.json summary.json \
  --expected-before d43a8b0fca74c6bc893d68ca6ec8190e74b423c9 \
  --expected-after 4325386e689566a903309accd66aca3ced1159f7 \
  --rounds 3 --samples 101 --warmups 20 \
  --before /path/to/baseline --after /path/to/candidate \
  --output independent-audit.json
python3 audit_processes.py raw.json --output process-audit.json
python3 audit_source_identity.py raw.json --repo /path/to/repo \
  --before /path/to/baseline --after /path/to/candidate \
  --output source-audit.json
python3 review_storage_controls.py .
```

These tools inspect preserved data and source bytes only. They execute no Dart workload and import no project timing summarizer. Their passing results are scoped to this control cohort and do not establish sparse-target gains, browser performance, resolution of prior tail observations, or dense coupled convergence.

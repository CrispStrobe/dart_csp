# Sparse heap candidate: independent small-QR/CAD control review — 2026-11-14

## Retention recommendation

**These controls expose no correctness or physical-work blocker to retaining the heap candidate. Recommend retention only as a qualified large-sparse optimization, contingent on the separately audited target gains and source validation, with the adverse control tails below explicitly accepted.** This control cohort alone does not demonstrate the target sparse benefit or establish a uniform speedup. Repeatable adverse tail observations remain.

The measured baseline is `c2603a852229897d325a8890ed418319ee8c3572` and heap candidate is `521a31f78989cf4706c8f26bb6a2c2ec2709b777`. The rejected QR permutation cleanup is a separate experiment and is not part of this review. The changed heap source is evaluated here through collateral small-QR, plate and linkage controls; this audit does not inspect its internal heap invariants or replace its separate sparse qualification.

Across all 40 aggregate median rows, **26 are lower, 2 equal and 12 higher**. This is a descriptive count without application-workload weighting. All AOT linkage medians are lower by 2.8–6.5%, and all JIT plate medians are lower by 6.9–11.5%. The full result includes the following adverse observations:

- AOT rank 16x8 p50 per 256-call batch: 420 to 487 microseconds (+15.95%; slower/equal/faster pairs 2/0/1).
- AOT rank 16x8 p95 per 256-call batch: 524 to 720 microseconds (+37.40%; slower/equal/faster pairs 1/0/2).
- AOT plate cold p95: 965 to 1380 microseconds (+43.01%; slower/equal/faster pairs 2/0/1).
- AOT plate profile p95: 1020 to 1232 microseconds (+20.78%; slower/equal/faster pairs 3/0/0).
- AOT plate thickness p50: 628 to 671 microseconds (+6.85%; slower/equal/faster pairs 2/0/1).
- JIT cold-linkage p95: 6081 to 6444 microseconds (+5.97%; slower/equal/faster pairs 3/0/0).
- JIT placement-only p95: 252 to 328 microseconds (+30.16%; slower/equal/faster pairs 3/0/0).
- JIT rank 8x4 p95 per 256-call batch: 164 to 208 microseconds (+26.83%; slower/equal/faster pairs 3/0/0).

Profile p95, cold-linkage p95, placement-only p95 and rank-8x4 p95 all worsen in three of three paired processes. They cannot be dismissed from their aggregate medians or from identical physical work counters. The observed distribution also includes mixed pair directions, which are retained alongside every ratio of process medians below.

## Independent verification

The fixture/source auditor passes **58,278 assertions** and the process auditor passes **1,010 checks**, with zero findings. All 36 reports honor three alternating rounds, 20 warmups and 101 measured samples in both JIT and AOT. All 240 distributions expose raw timings: **24,240 samples/batches** in total. All **9,696 CAD work records** satisfy their fixture invariants, and all **4,848 before/after sample pairs** have equal work records. All 40 summary rows and 36 published plate p99 values reconcile. Ninety library files across the two live worktrees match their recorded commits; harness and dependency-file hashes also match.

The process audit checks 101 subprocess records, 202 original stream digests, six compilations and 36 benchmark links. No raw sample, process, fixture or adverse row is excluded. Numerical checks run in the harness outside timers; this collector serializes their pass records and work counters, rather than full numerical outputs for a second physical-oracle replay.

The exact source identities, raw and summary digests, declared sampling design and performed source-byte checks are recorded in the audit JSON. No numerical workload was rerun by this review.

## Tail boundary and complete table

Values are microseconds and changes are candidate/baseline elapsed time. Positive means slower. S/E/F counts give slower/equal/faster paired process values out of three. QR rows time batches of 256 operations except rank 48x48 (eight operations); CAD rows time one operation. Each aggregate is the median of three per-process percentiles, without sample pooling.

Plate p99 values are harness-reported. QR and linkage p99 values below are derived screening statistics using the respective harness percentile convention. At 101 samples, p99 is the second-largest sample in each process; three processes do not establish a stable tail bound. The complete per-round values and changes are preserved in `review-metrics.json`. These data do not establish allocation-byte changes, GC attribution, compiler effects or a causal mechanism for any observed control difference.

### JIT

| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |
|---|---:|---:|---:|---:|---:|---:|
| geometry_small_qr / rank_5x4 | 94 → 93 (-1.06%) | 1/0/2 | 482 → 705 (+46.27%) | 2/0/1 | 6464 → 6278 (-2.88%) | 1/0/2 |
| geometry_small_qr / rank_8x4 | 113 → 109 (-3.54%) | 1/0/2 | 164 → 208 (+26.83%) | 3/0/0 | 5478 → 231 (-95.78%) | 0/0/3 |
| geometry_small_qr / rank_4x5 | 95 → 94 (-1.05%) | 1/0/2 | 152 → 130 (-14.47%) | 1/0/2 | 179 → 152 (-15.08%) | 1/0/2 |
| geometry_small_qr / rank_4x8 | 136 → 133 (-2.21%) | 1/0/2 | 203 → 167 (-17.73%) | 1/0/2 | 434 → 180 (-58.53%) | 0/0/3 |
| geometry_small_qr / rank_9x4 | 116 → 111 (-4.31%) | 1/0/2 | 174 → 141 (-18.97%) | 0/0/3 | 262 → 143 (-45.42%) | 1/0/2 |
| geometry_small_qr / rank_12x4 | 135 → 128 (-5.19%) | 1/0/2 | 199 → 178 (-10.55%) | 0/0/3 | 444 → 239 (-46.17%) | 0/0/3 |
| geometry_small_qr / rank_16x8 | 400 → 377 (-5.75%) | 1/0/2 | 533 → 424 (-20.45%) | 1/0/2 | 1151 → 463 (-59.77%) | 1/0/2 |
| geometry_small_qr / rank_16x9 | 456 → 436 (-4.39%) | 1/0/2 | 601 → 518 (-13.81%) | 1/0/2 | 791 → 632 (-20.10%) | 1/0/2 |
| geometry_small_qr / rank_17x8 | 406 → 412 (+1.48%) | 2/0/1 | 473 → 564 (+19.24%) | 2/0/1 | 484 → 778 (+60.74%) | 1/0/2 |
| geometry_small_qr / rank_48x48 | 561 → 569 (+1.43%) | 2/0/1 | 656 → 696 (+6.10%) | 2/0/1 | 743 → 862 (+16.02%) | 2/0/1 |
| geometry_small_qr / damped_solve_8x4 | 176 → 164 (-6.82%) | 0/0/3 | 218 → 210 (-3.67%) | 2/0/1 | 238 → 223 (-6.30%) | 1/0/2 |
| geometry_small_qr / nullspace_4x8 | 127 → 127 (+0.00%) | 1/2/0 | 176 → 192 (+9.09%) | 2/0/1 | 498 → 410 (-17.67%) | 2/0/1 |
| cad / cold_build_compile_regenerate | 1024 → 907 (-11.43%) | 1/0/2 | 6213 → 5716 (-8.00%) | 1/0/2 | 9629 → 11990 (+24.52%) | 2/0/1 |
| cad / profile_edit_regenerate | 923 → 817 (-11.48%) | 1/0/2 | 5468 → 5204 (-4.83%) | 0/0/3 | 9049 → 9586 (+5.93%) | 1/0/2 |
| cad / thickness_edit_regenerate | 634 → 590 (-6.94%) | 1/0/2 | 4629 → 4842 (+4.60%) | 1/0/2 | 8806 → 8878 (+0.82%) | 2/0/1 |
| cad_linkage / cold_build_solve_solids_meshes | 1925 → 1935 (+0.52%) | 2/0/1 | 6081 → 6444 (+5.97%) | 3/0/0 | 8759 → 8072 (-7.84%) | 2/0/1 |
| cad_linkage / retained_angle_edit | 216 → 221 (+2.31%) | 2/0/1 | 817 → 816 (-0.12%) | 1/0/2 | 2727 → 4558 (+67.14%) | 2/0/1 |
| cad_linkage / selective_coupler_length_edit | 627 → 614 (-2.07%) | 2/0/1 | 2764 → 2414 (-12.66%) | 1/0/2 | 4215 → 3446 (-18.24%) | 1/0/2 |
| cad_linkage / placement_only_layer_edit | 89 → 90 (+1.12%) | 1/1/1 | 252 → 328 (+30.16%) | 3/0/0 | 1426 → 1229 (-13.81%) | 1/0/2 |
| cad_linkage / downstream_rejected_angle_edit | 192 → 187 (-2.60%) | 1/0/2 | 636 → 431 (-32.23%) | 0/0/3 | 1409 → 1493 (+5.96%) | 2/0/1 |

### AOT

| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |
|---|---:|---:|---:|---:|---:|---:|
| geometry_small_qr / rank_5x4 | 96 → 96 (+0.00%) | 1/0/2 | 134 → 141 (+5.22%) | 2/0/1 | 150 → 188 (+25.33%) | 2/0/1 |
| geometry_small_qr / rank_8x4 | 115 → 113 (-1.74%) | 0/0/3 | 176 → 147 (-16.48%) | 1/0/2 | 198 → 161 (-18.69%) | 1/0/2 |
| geometry_small_qr / rank_4x5 | 107 → 108 (+0.93%) | 1/0/2 | 185 → 149 (-19.46%) | 1/0/2 | 240 → 195 (-18.75%) | 1/0/2 |
| geometry_small_qr / rank_4x8 | 162 → 161 (-0.62%) | 1/1/1 | 236 → 263 (+11.44%) | 1/0/2 | 283 → 302 (+6.71%) | 1/0/2 |
| geometry_small_qr / rank_9x4 | 120 → 121 (+0.83%) | 1/0/2 | 237 → 217 (-8.44%) | 1/0/2 | 261 → 257 (-1.53%) | 1/0/2 |
| geometry_small_qr / rank_12x4 | 146 → 137 (-6.16%) | 1/1/1 | 277 → 197 (-28.88%) | 1/0/2 | 346 → 254 (-26.59%) | 0/0/3 |
| geometry_small_qr / rank_16x8 | 420 → 487 (+15.95%) | 2/0/1 | 524 → 720 (+37.40%) | 1/0/2 | 654 → 1065 (+62.84%) | 1/0/2 |
| geometry_small_qr / rank_16x9 | 499 → 491 (-1.60%) | 1/0/2 | 677 → 673 (-0.59%) | 1/0/2 | 850 → 773 (-9.06%) | 1/0/2 |
| geometry_small_qr / rank_17x8 | 453 → 477 (+5.30%) | 1/0/2 | 608 → 832 (+36.84%) | 1/0/2 | 787 → 1233 (+56.67%) | 2/0/1 |
| geometry_small_qr / rank_48x48 | 660 → 604 (-8.48%) | 0/0/3 | 869 → 735 (-15.42%) | 0/0/3 | 1061 → 1263 (+19.04%) | 1/0/2 |
| geometry_small_qr / damped_solve_8x4 | 206 → 183 (-11.17%) | 1/0/2 | 321 → 245 (-23.68%) | 1/0/2 | 426 → 291 (-31.69%) | 1/0/2 |
| geometry_small_qr / nullspace_4x8 | 178 → 167 (-6.18%) | 1/0/2 | 267 → 252 (-5.62%) | 0/0/3 | 377 → 340 (-9.81%) | 1/0/2 |
| cad / cold_build_compile_regenerate | 700 → 705 (+0.71%) | 2/0/1 | 965 → 1380 (+43.01%) | 2/0/1 | 1105 → 1442 (+30.50%) | 2/0/1 |
| cad / profile_edit_regenerate | 718 → 723 (+0.70%) | 1/0/2 | 1020 → 1232 (+20.78%) | 3/0/0 | 1317 → 1547 (+17.46%) | 2/0/1 |
| cad / thickness_edit_regenerate | 628 → 671 (+6.85%) | 2/0/1 | 970 → 1054 (+8.66%) | 2/0/1 | 1200 → 1263 (+5.25%) | 2/0/1 |
| cad_linkage / cold_build_solve_solids_meshes | 1831 → 1726 (-5.73%) | 1/0/2 | 2435 → 2315 (-4.93%) | 0/0/3 | 5529 → 3301 (-40.30%) | 1/0/2 |
| cad_linkage / retained_angle_edit | 153 → 143 (-6.54%) | 1/0/2 | 283 → 250 (-11.66%) | 1/0/2 | 483 → 334 (-30.85%) | 0/0/3 |
| cad_linkage / selective_coupler_length_edit | 570 → 542 (-4.91%) | 1/0/2 | 884 → 772 (-12.67%) | 1/0/2 | 1493 → 999 (-33.09%) | 0/0/3 |
| cad_linkage / placement_only_layer_edit | 71 → 69 (-2.82%) | 1/0/2 | 113 → 108 (-4.42%) | 2/0/1 | 245 → 143 (-41.63%) | 1/0/2 |
| cad_linkage / downstream_rejected_angle_edit | 133 → 126 (-5.26%) | 1/0/2 | 254 → 171 (-32.68%) | 1/0/2 | 389 → 234 (-39.85%) | 1/0/2 |

## Reproduction

```sh
python3 audit_control_cohort.py raw.json summary.json \
  --expected-before c2603a852229897d325a8890ed418319ee8c3572 \
  --expected-after 521a31f78989cf4706c8f26bb6a2c2ec2709b777 \
  --rounds 3 --samples 101 --warmups 20 \
  --before /path/to/baseline --after /path/to/heap-candidate \
  --output independent-audit.json
python3 audit_processes.py raw.json --output process-audit.json
python3 review_heap_controls.py .
```

The standalone auditor uses declared source identities and sampling counts; it imports no project summarizer and executes no solver workload. Omit the optional worktree paths when only serialized evidence is available, retaining exact expected-commit checks. The audit result records which source-byte checks were performed.

Further timing repetition is not required merely to finish this control review. Any decision to integrate should name the separate target benefits and these retained control costs. This review does not qualify browser performance or the previously unresolved dense-fill convergence limit.

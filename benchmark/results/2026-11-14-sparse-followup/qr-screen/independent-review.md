# QR permutation-allocation experiment: independent review — 2026-11-14

## Decision

**Reject the candidate for integration and preserve its source and complete measurements.** The one-list source cleanup is numerically valid, but this prespecified screen does not support retaining it. AOT plate cold/profile/thickness medians are 7.03%, 10.29% and 9.61% higher, and their p95 values are 6.18%, 28.26% and 27.81% higher. Every one of those six percentile comparisons is worse in all three process pairs. JIT cold-linkage median is 33.92% higher, also worse in all three pairs. AOT QR gains, including rank 4x8 at -12.15%, do not justify these collateral observations.

The observed tails are mixed and remain fully visible: AOT plate cold/thickness p99 increases 28.83%/44.95%, each in all three pairs. The derived JIT damped-solve p99 rises 252.09%, also in all three pairs. Conversely, the derived JIT rank-4x8 p99 falls 49.93%, with all three pairs faster. These screening p99 values describe the sampled cohort and do not identify a causal mechanism.

The experiment source is `748febd527cda9eeb611cdf2dcba3c9c3af388ec`, compared with `c2603a852229897d325a8890ed418319ee8c3572`. The only production change directly initializes the QR identity permutation in `Int32List`, avoiding the explicit temporary generated list. It preserves initialization before the first cancellation callback and all QR arithmetic. This does not establish reduced allocated bytes, fewer GC events, or any cause of the observed tails. In particular, the plate thickness operation performs no geometry solve; its adverse result remains a control observation rather than proof that this QR expression causes that cost.

## Independent verification

The fixture/source auditor passes **58,278 assertions** and the process auditor passes **1,010 checks**, with zero findings. All 36 reports honor three alternating rounds, 20 warmups and 101 measured samples in both JIT and AOT. All 240 distributions expose raw timings: **24,240 samples/batches** in total. All **9,696 CAD work records** satisfy their fixture invariants, and all **4,848 before/after sample pairs** have equal work records. All 40 summary rows and 36 published plate p99 values reconcile. Ninety library files across the two live worktrees match their recorded commits; harness and dependency-file hashes also match.

The process audit checks 101 subprocess records, 202 original stream digests, six compilations and 36 benchmark links. No raw sample, process, fixture or adverse row is excluded. Numerical checks run in the harness outside timers; this collector serializes their pass records and work counters, rather than full numerical outputs for a second physical-oracle replay.

## Complete timing table

Values are microseconds and changes are candidate/baseline elapsed time. Positive means slower. S/E/F counts give slower/equal/faster paired process values out of three. QR rows time batches of 256 operations except rank 48x48 (eight operations); CAD rows time one operation. Each aggregate is the median of three per-process percentiles, without sample pooling.

Plate p99 values are harness-reported. QR and linkage p99 values below are derived screening statistics using the respective harness percentile convention. At 101 samples, p99 is the second-largest sample in each process; three processes do not establish a stable tail bound. The complete per-round values and changes are preserved in `review-metrics.json`.

### JIT

| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |
|---|---:|---:|---:|---:|---:|---:|
| geometry_small_qr / rank_5x4 | 151 → 141 (-6.62%) | 1/0/2 | 2645 → 4180 (+58.03%) | 2/0/1 | 5962 → 6604 (+10.77%) | 2/0/1 |
| geometry_small_qr / rank_8x4 | 166 → 180 (+8.43%) | 2/0/1 | 628 → 258 (-58.92%) | 1/0/2 | 3498 → 282 (-91.94%) | 1/0/2 |
| geometry_small_qr / rank_4x5 | 103 → 158 (+53.40%) | 2/0/1 | 231 → 224 (-3.03%) | 1/0/2 | 275 → 243 (-11.64%) | 1/0/2 |
| geometry_small_qr / rank_4x8 | 203 → 152 (-25.12%) | 1/0/2 | 314 → 269 (-14.33%) | 0/0/3 | 677 → 339 (-49.93%) | 0/0/3 |
| geometry_small_qr / rank_9x4 | 138 → 177 (+28.26%) | 2/0/1 | 255 → 239 (-6.27%) | 1/0/2 | 312 → 261 (-16.35%) | 1/0/2 |
| geometry_small_qr / rank_12x4 | 161 → 186 (+15.53%) | 3/0/0 | 272 → 253 (-6.99%) | 2/0/1 | 463 → 270 (-41.68%) | 0/0/3 |
| geometry_small_qr / rank_16x8 | 421 → 593 (+40.86%) | 2/0/1 | 705 → 690 (-2.13%) | 2/0/1 | 839 → 736 (-12.28%) | 1/0/2 |
| geometry_small_qr / rank_16x9 | 491 → 468 (-4.68%) | 1/0/2 | 748 → 686 (-8.29%) | 1/0/2 | 802 → 786 (-2.00%) | 1/0/2 |
| geometry_small_qr / rank_17x8 | 441 → 496 (+12.47%) | 2/0/1 | 654 → 769 (+17.58%) | 2/0/1 | 778 → 811 (+4.24%) | 2/0/1 |
| geometry_small_qr / rank_48x48 | 579 → 663 (+14.51%) | 2/0/1 | 869 → 973 (+11.97%) | 2/0/1 | 899 → 1000 (+11.23%) | 1/0/2 |
| geometry_small_qr / damped_solve_8x4 | 172 → 212 (+23.26%) | 2/0/1 | 281 → 531 (+88.97%) | 3/0/0 | 382 → 1345 (+252.09%) | 3/0/0 |
| geometry_small_qr / nullspace_4x8 | 146 → 152 (+4.11%) | 2/0/1 | 242 → 347 (+43.39%) | 2/0/1 | 378 → 2272 (+501.06%) | 2/0/1 |
| cad / cold_build_compile_regenerate | 1233 → 1206 (-2.19%) | 2/0/1 | 6390 → 6377 (-0.20%) | 2/0/1 | 8907 → 9627 (+8.08%) | 2/0/1 |
| cad / profile_edit_regenerate | 999 → 995 (-0.40%) | 2/0/1 | 6111 → 6461 (+5.73%) | 1/0/2 | 9741 → 9150 (-6.07%) | 1/0/2 |
| cad / thickness_edit_regenerate | 692 → 732 (+5.78%) | 2/0/1 | 4741 → 4947 (+4.35%) | 1/0/2 | 10135 → 8234 (-18.76%) | 1/0/2 |
| cad_linkage / cold_build_solve_solids_meshes | 1984 → 2657 (+33.92%) | 3/0/0 | 6867 → 6835 (-0.47%) | 1/0/2 | 8893 → 8711 (-2.05%) | 2/0/1 |
| cad_linkage / retained_angle_edit | 220 → 284 (+29.09%) | 2/0/1 | 1365 → 858 (-37.14%) | 1/0/2 | 4280 → 4513 (+5.44%) | 2/0/1 |
| cad_linkage / selective_coupler_length_edit | 637 → 837 (+31.40%) | 2/0/1 | 2854 → 2711 (-5.01%) | 1/0/2 | 5841 → 8998 (+54.05%) | 2/0/1 |
| cad_linkage / placement_only_layer_edit | 92 → 120 (+30.43%) | 2/0/1 | 287 → 419 (+45.99%) | 2/0/1 | 1433 → 1846 (+28.82%) | 2/0/1 |
| cad_linkage / downstream_rejected_angle_edit | 191 → 239 (+25.13%) | 2/0/1 | 528 → 707 (+33.90%) | 2/0/1 | 1395 → 1513 (+8.46%) | 2/0/1 |

### AOT

| Benchmark / case | p50 before → after (change) | p50 S/E/F | p95 before → after (change) | p95 S/E/F | p99 before → after (change) | p99 S/E/F |
|---|---:|---:|---:|---:|---:|---:|
| geometry_small_qr / rank_5x4 | 95 → 95 (+0.00%) | 1/1/1 | 209 → 167 (-20.10%) | 1/0/2 | 289 → 214 (-25.95%) | 0/0/3 |
| geometry_small_qr / rank_8x4 | 122 → 115 (-5.74%) | 1/0/2 | 235 → 194 (-17.45%) | 1/0/2 | 382 → 242 (-36.65%) | 0/0/3 |
| geometry_small_qr / rank_4x5 | 115 → 110 (-4.35%) | 2/0/1 | 231 → 172 (-25.54%) | 1/0/2 | 309 → 248 (-19.74%) | 1/0/2 |
| geometry_small_qr / rank_4x8 | 181 → 159 (-12.15%) | 0/0/3 | 286 → 224 (-21.68%) | 0/0/3 | 358 → 289 (-19.27%) | 1/0/2 |
| geometry_small_qr / rank_9x4 | 129 → 123 (-4.65%) | 0/0/3 | 194 → 199 (+2.58%) | 1/0/2 | 306 → 311 (+1.63%) | 2/0/1 |
| geometry_small_qr / rank_12x4 | 148 → 142 (-4.05%) | 0/0/3 | 228 → 228 (+0.00%) | 1/0/2 | 269 → 348 (+29.37%) | 1/0/2 |
| geometry_small_qr / rank_16x8 | 451 → 434 (-3.77%) | 0/0/3 | 578 → 524 (-9.34%) | 2/0/1 | 695 → 600 (-13.67%) | 1/0/2 |
| geometry_small_qr / rank_16x9 | 515 → 513 (-0.39%) | 2/0/1 | 694 → 738 (+6.34%) | 2/0/1 | 774 → 923 (+19.25%) | 2/0/1 |
| geometry_small_qr / rank_17x8 | 458 → 455 (-0.66%) | 1/0/2 | 637 → 511 (-19.78%) | 0/0/3 | 1100 → 591 (-46.27%) | 0/0/3 |
| geometry_small_qr / rank_48x48 | 613 → 602 (-1.79%) | 1/0/2 | 806 → 690 (-14.39%) | 0/0/3 | 887 → 865 (-2.48%) | 1/0/2 |
| geometry_small_qr / damped_solve_8x4 | 187 → 192 (+2.67%) | 2/0/1 | 248 → 262 (+5.65%) | 1/0/2 | 344 → 325 (-5.52%) | 1/0/2 |
| geometry_small_qr / nullspace_4x8 | 174 → 165 (-5.17%) | 1/0/2 | 245 → 242 (-1.22%) | 1/0/2 | 344 → 270 (-21.51%) | 1/0/2 |
| cad / cold_build_compile_regenerate | 711 → 761 (+7.03%) | 3/0/0 | 1003 → 1065 (+6.18%) | 3/0/0 | 1207 → 1555 (+28.83%) | 3/0/0 |
| cad / profile_edit_regenerate | 719 → 793 (+10.29%) | 3/0/0 | 1012 → 1298 (+28.26%) | 3/0/0 | 1169 → 1543 (+31.99%) | 2/0/1 |
| cad / thickness_edit_regenerate | 635 → 696 (+9.61%) | 3/0/0 | 917 → 1172 (+27.81%) | 3/0/0 | 1128 → 1635 (+44.95%) | 3/0/0 |
| cad_linkage / cold_build_solve_solids_meshes | 1820 → 1803 (-0.93%) | 2/0/1 | 2918 → 2922 (+0.14%) | 2/0/1 | 4346 → 3251 (-25.20%) | 0/0/3 |
| cad_linkage / retained_angle_edit | 167 → 156 (-6.59%) | 2/0/1 | 285 → 271 (-4.91%) | 2/0/1 | 404 → 304 (-24.75%) | 1/0/2 |
| cad_linkage / selective_coupler_length_edit | 599 → 592 (-1.17%) | 1/0/2 | 941 → 972 (+3.29%) | 2/0/1 | 1206 → 1346 (+11.61%) | 2/0/1 |
| cad_linkage / placement_only_layer_edit | 80 → 79 (-1.25%) | 2/0/1 | 137 → 135 (-1.46%) | 2/0/1 | 270 → 148 (-45.19%) | 1/0/2 |
| cad_linkage / downstream_rejected_angle_edit | 135 → 143 (+5.93%) | 2/0/1 | 238 → 266 (+11.76%) | 2/0/1 | 576 → 330 (-42.71%) | 1/0/2 |

## Reproduction

```sh
python3 audit_qr_screen.py raw.json summary.json \
  --expected-before c2603a852229897d325a8890ed418319ee8c3572 \
  --expected-after 748febd527cda9eeb611cdf2dcba3c9c3af388ec \
  --rounds 3 --samples 101 --warmups 20 \
  --before /path/to/baseline --after /path/to/qr-candidate \
  --output independent-audit.json
python3 tool/audit_recovery_processes.py raw.json --output process-audit.json
```

The standalone auditor uses declared source identities and sampling counts; it imports no project summarizer and executes no solver workload. Omit the optional worktree paths when only serialized evidence is available, retaining exact expected-commit checks. The audit result records which source-byte checks were performed.

No further timing run is needed merely to accept this rejection. The separate sparse-ordering experiment remains an independent candidate; this rejected QR change should not be combined with it or silently retained.

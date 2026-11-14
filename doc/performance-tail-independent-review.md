# Independent review of isolated tail candidates

This review independently reconstructs all rows and pair directions from the preserved JSON. It runs no Dart, profiler, tests, or timing workloads.

## Retention assessment

The placement candidate has the more consistent evidence for the targeted retained linkage edits. Preserve its AOT cold-build and JIT assembly costs; aggregate medians alone conceal adverse paired results in the assembly rows. The fresh final CAD cohort strengthens the AOT retained-edit result but also shows a substantial AOT assembly cold regression in every pair. Placement is a targeted candidate with a material tradeoff, not an unconditional overall improvement.

The geometry candidate has useful direct warm-solver gains, but also large coupled/assembly cold AOT p95 regressions in every pair, and mixed or adverse linkage/assembly medians. The isolated evidence supports its rejection from this tail-focused candidate. Preserve its branch, tests and all results. Placement retention remains conditional on the complete tradeoff assessment; eliminating structural allocations alone is insufficient.

A combined candidate versus baseline would not isolate the incremental benefit or cost of adding geometry to placement. These separate cohorts must not be multiplied or combined into an estimated combined speedup.

## Evidence limits

- Three fresh process pairs per runtime on a shared, unpinned host; no significance, deterministic latency or SLA claim.
- Each cohort containing the legacy geometry control has twenty-four distributions without raw samples; their p50/p95 reconcile to process reports but cannot be reconstructed from samples.
- Legacy numerical controls expose the last operation’s counters, not work aligned with every timing sample.
- Derived p99 on the 25-sample controls is the sample maximum; the 300-sample CAD cases have only three observations in the upper one percent per process.
- Physical correctness completion is established by pass records plus reviewed harness code; full coordinates are not serialized for independent replay.
- Raw files preserve parsed harness JSON, argv and process timestamps. They do not preserve lossless original stdout bytes or explicit exit-code fields; the collector records completed successful calls.
- These normal cohorts contain no allocated-byte measurement or GC/CPU attribution. Paired adverse results and unchanged-work controls remain evidence even when the aggregate median improves.

The final controls exercise numerical and graph code with no retained production changes in those implementations. Their sizeable changes are still reported, but cannot be causally attributed to placement validation. Likewise, plate-only controls do not execute rigid-instance validation. This observed context variability limits transfer of isolated percentage changes between cohorts.

## Complete results

Times are microseconds. “Pairs F/S/E” counts faster, slower and equal paired processes; “paired median” is the median of the three paired percentage changes. It is distinct from the percentage change between aggregate medians.

### Placement

Audit: **passed**, 221,459 checks; 36 reports and 20 rows. Counts: `{"aligned_work_distributions": 120, "aligned_work_records": 36000, "committed_library_files_checked": 88, "distributions": 120, "paired_counter_snapshots": 18, "paired_work_records": 18000, "raw_distributions": 120, "raw_samples": 36000, "reported_p99_values": 60}`.

| Runtime / fixture / operation | p50 before → after | Aggregate Δ / paired median Δ | p50 pairs F/S/E | p95 before → after | Aggregate Δ / paired median Δ | p95 pairs F/S/E | Derived p99 aggregate Δ; pairs F/S/E |
|---|---:|---:|---:|---:|---:|---:|---:|
| jit / cad / `cold_build_compile_regenerate` | 730 → 734 | +0.5% / +10.0% | 1/2/0 | 1554 → 1703 | +9.6% / +9.6% | 1/2/0 | +9.2%; 2/1/0 |
| jit / cad / `profile_edit_regenerate` | 655 → 668 | +2.0% / +5.2% | 0/2/1 | 1489 → 1654 | +11.1% / +11.1% | 1/2/0 | +39.3%; 2/1/0 |
| jit / cad / `thickness_edit_regenerate` | 550 → 543 | -1.3% / +4.0% | 1/2/0 | 1067 → 978 | -8.3% / -4.5% | 2/1/0 | -4.8%; 1/2/0 |
| jit / cad_linkage / `measurements/cold_build_solve_solids_meshes` | 2000 → 1961 | -1.9% / -3.6% | 3/0/0 | 4791 → 2864 | -40.2% / -34.9% | 3/0/0 | -40.2%; 2/1/0 |
| jit / cad_linkage / `measurements/retained_angle_edit` | 296 → 278 | -6.1% / -10.5% | 3/0/0 | 833 → 539 | -35.3% / -33.6% | 3/0/0 | -65.2%; 3/0/0 |
| jit / cad_linkage / `measurements/selective_coupler_length_edit` | 710 → 676 | -4.8% / -10.8% | 3/0/0 | 1795 → 1151 | -35.9% / -31.1% | 3/0/0 | -60.7%; 3/0/0 |
| jit / cad_linkage / `measurements/placement_only_layer_edit` | 173 → 157 | -9.2% / -11.0% | 3/0/0 | 455 → 250 | -45.1% / -37.0% | 3/0/0 | -29.0%; 3/0/0 |
| jit / cad_linkage / `measurements/downstream_rejected_angle_edit` | 267 → 248 | -7.1% / -10.9% | 3/0/0 | 903 → 495 | -45.2% / -40.5% | 3/0/0 | -71.4%; 3/0/0 |
| jit / cad_instances / `cold_build_solve_regenerate` | 735 → 641 | -12.8% / +8.2% | 1/2/0 | 1652 → 1600 | -3.1% / +20.1% | 1/2/0 | +1.9%; 1/2/0 |
| jit / cad_instances / `solved_pose_edit` | 155 → 144 | -7.1% / +7.5% | 1/2/0 | 442 → 510 | +15.4% / +36.8% | 1/2/0 | +54.4%; 1/2/0 |
| aot / cad / `cold_build_compile_regenerate` | 697 → 689 | -1.1% / -3.2% | 3/0/0 | 1089 → 1029 | -5.5% / -9.3% | 2/1/0 | +5.0%; 1/2/0 |
| aot / cad / `profile_edit_regenerate` | 716 → 720 | +0.6% / -4.9% | 2/1/0 | 1221 → 1053 | -13.8% / -6.8% | 2/1/0 | -1.5%; 2/1/0 |
| aot / cad / `thickness_edit_regenerate` | 626 → 630 | +0.6% / -2.7% | 2/1/0 | 981 → 927 | -5.5% / -14.7% | 2/1/0 | -8.7%; 2/1/0 |
| aot / cad_linkage / `measurements/cold_build_solve_solids_meshes` | 1778 → 1830 | +2.9% / +1.1% | 0/3/0 | 2404 → 2547 | +5.9% / -3.0% | 2/1/0 | +38.2%; 1/2/0 |
| aot / cad_linkage / `measurements/retained_angle_edit` | 185 → 177 | -4.3% / -3.9% | 3/0/0 | 316 → 278 | -12.0% / -6.0% | 3/0/0 | -31.4%; 2/1/0 |
| aot / cad_linkage / `measurements/selective_coupler_length_edit` | 571 → 552 | -3.3% / -3.2% | 3/0/0 | 895 → 801 | -10.5% / -11.0% | 3/0/0 | +42.3%; 1/2/0 |
| aot / cad_linkage / `measurements/placement_only_layer_edit` | 107 → 101 | -5.6% / -3.8% | 3/0/0 | 180 → 157 | -12.8% / -7.9% | 2/1/0 | +23.2%; 0/3/0 |
| aot / cad_linkage / `measurements/downstream_rejected_angle_edit` | 163 → 158 | -3.1% / -0.6% | 3/0/0 | 245 → 249 | +1.6% / +9.7% | 1/2/0 | +20.0%; 2/1/0 |
| aot / cad_instances / `cold_build_solve_regenerate` | 396 → 416 | +5.1% / +9.0% | 1/2/0 | 584 → 659 | +12.8% / +4.6% | 1/2/0 | +7.3%; 1/2/0 |
| aot / cad_instances / `solved_pose_edit` | 48 → 48 | +0.0% / -6.2% | 2/1/0 | 133 → 77 | -42.1% / -35.3% | 3/0/0 | -59.4%; 3/0/0 |

Consistent regressions (all three paired processes worse):

- aot cad_linkage `measurements/cold_build_solve_solids_meshes` p50: aggregate +2.9%; individual pairs +1.1%, +0.2%, +2.9%.

### Geometry

Audit: **passed**, 164,543 checks; 72 reports and 30 rows. Counts: `{"aligned_work_distributions": 84, "aligned_work_records": 25200, "committed_library_files_checked": 88, "distributions": 180, "distributions_without_raw_samples": 24, "paired_counter_snapshots": 54, "paired_work_records": 12600, "raw_distributions": 156, "raw_samples": 27000, "reported_p99_values": 24}`.

| Runtime / fixture / operation | p50 before → after | Aggregate Δ / paired median Δ | p50 pairs F/S/E | p95 before → after | Aggregate Δ / paired median Δ | p95 pairs F/S/E | Derived p99 aggregate Δ; pairs F/S/E |
|---|---:|---:|---:|---:|---:|---:|---:|
| jit / geometry / `cold_build_compile_solve` | 3155 → 3747 | +18.8% / +18.8% | 1/2/0 | 9639 → 11993 | +24.4% / +26.1% | 1/2/0 | unavailable |
| jit / geometry / `warm_edit_solve` | 187 → 229 | +22.5% / +22.5% | 1/2/0 | 980 → 723 | -26.2% / -10.4% | 2/1/0 | unavailable |
| jit / geometry_nonlinear / `cold_build_compile_solve` | 771 → 730 | -5.3% / -5.3% | 2/1/0 | 1533 → 1687 | +10.0% / +4.4% | 1/2/0 | +59.3%; 1/2/0 |
| jit / geometry_nonlinear / `warm_edit_solve` | 488 → 452 | -7.4% / -13.4% | 3/0/0 | 977 → 831 | -14.9% / -37.9% | 3/0/0 | -31.0%; 2/1/0 |
| jit / geometry_coupled / `cold_build_compile_solve` | 1457 → 1344 | -7.8% / -7.8% | 2/1/0 | 2221 → 2289 | +3.1% / -11.6% | 2/1/0 | +46.4%; 2/1/0 |
| jit / geometry_coupled / `warm_edit_solve` | 621 → 546 | -12.1% / -11.9% | 2/1/0 | 1697 → 1461 | -13.9% / -13.9% | 2/1/0 | -25.6%; 3/0/0 |
| jit / cad_workspace / `cold_build_compile_regenerate` | 1517 → 1581 | +4.2% / +10.2% | 1/2/0 | 2191 → 2568 | +17.2% / +17.2% | 1/2/0 | +38.2%; 0/3/0 |
| jit / cad_workspace / `warm_edit_regenerate` | 717 → 667 | -7.0% / +15.3% | 1/2/0 | 1812 → 1687 | -6.9% / -1.4% | 2/1/0 | +5.5%; 1/2/0 |
| jit / cad_linkage / `measurements/cold_build_solve_solids_meshes` | 1918 → 1913 | -0.3% / +1.4% | 1/2/0 | 2952 → 3075 | +4.2% / +6.6% | 1/2/0 | -2.0%; 2/1/0 |
| jit / cad_linkage / `measurements/retained_angle_edit` | 277 → 283 | +2.2% / +2.7% | 1/2/0 | 581 → 523 | -10.0% / -2.4% | 2/1/0 | -15.1%; 2/1/0 |
| jit / cad_linkage / `measurements/selective_coupler_length_edit` | 651 → 683 | +4.9% / +4.9% | 1/2/0 | 1000 → 1051 | +5.1% / +9.5% | 1/2/0 | -2.1%; 2/1/0 |
| jit / cad_linkage / `measurements/placement_only_layer_edit` | 162 → 163 | +0.6% / +0.6% | 1/2/0 | 270 → 309 | +14.4% / +14.4% | 1/2/0 | +10.5%; 2/1/0 |
| jit / cad_linkage / `measurements/downstream_rejected_angle_edit` | 243 → 250 | +2.9% / +1.7% | 1/2/0 | 484 → 505 | +4.3% / +7.6% | 1/2/0 | +39.0%; 1/2/0 |
| jit / cad_instances / `cold_build_solve_regenerate` | 728 → 747 | +2.6% / +2.2% | 1/2/0 | 1699 → 1669 | -1.8% / -1.5% | 2/1/0 | +2.2%; 0/3/0 |
| jit / cad_instances / `solved_pose_edit` | 154 → 177 | +14.9% / +11.7% | 1/2/0 | 413 → 507 | +22.8% / +22.8% | 1/2/0 | +16.1%; 0/3/0 |
| aot / geometry / `cold_build_compile_solve` | 1434 → 1553 | +8.3% / +10.9% | 1/2/0 | 2149 → 2877 | +33.9% / +33.9% | 1/2/0 | unavailable |
| aot / geometry / `warm_edit_solve` | 91 → 63 | -30.8% / -25.9% | 3/0/0 | 321 → 148 | -53.9% / -31.1% | 2/1/0 | unavailable |
| aot / geometry_nonlinear / `cold_build_compile_solve` | 66 → 65 | -1.5% / -1.5% | 2/0/1 | 239 → 146 | -38.9% / -24.0% | 3/0/0 | -2.5%; 2/1/0 |
| aot / geometry_nonlinear / `warm_edit_solve` | 47 → 46 | -2.1% / -4.3% | 3/0/0 | 128 → 133 | +3.9% / +3.9% | 1/2/0 | +47.4%; 0/3/0 |
| aot / geometry_coupled / `cold_build_compile_solve` | 884 → 939 | +6.2% / +6.2% | 1/2/0 | 1152 → 2481 | +115.4% / +75.6% | 0/3/0 | +107.7%; 0/3/0 |
| aot / geometry_coupled / `warm_edit_solve` | 578 → 563 | -2.6% / -3.7% | 2/1/0 | 775 → 854 | +10.2% / +10.2% | 1/2/0 | +151.3%; 0/3/0 |
| aot / cad_workspace / `cold_build_compile_regenerate` | 933 → 922 | -1.2% / -3.8% | 2/1/0 | 1608 → 1237 | -23.1% / -23.1% | 3/0/0 | -49.2%; 2/1/0 |
| aot / cad_workspace / `warm_edit_regenerate` | 627 → 608 | -3.0% / -5.1% | 3/0/0 | 1024 → 816 | -20.3% / -10.6% | 2/1/0 | -69.4%; 2/1/0 |
| aot / cad_linkage / `measurements/cold_build_solve_solids_meshes` | 1923 → 1974 | +2.7% / +5.2% | 1/2/0 | 3198 → 2971 | -7.1% / -1.7% | 2/1/0 | -13.1%; 2/1/0 |
| aot / cad_linkage / `measurements/retained_angle_edit` | 202 → 207 | +2.5% / +8.4% | 1/2/0 | 382 → 369 | -3.4% / -2.6% | 2/1/0 | -31.0%; 3/0/0 |
| aot / cad_linkage / `measurements/selective_coupler_length_edit` | 642 → 671 | +4.5% / +12.2% | 1/2/0 | 1104 → 1076 | -2.5% / -2.5% | 2/1/0 | +50.0%; 1/2/0 |
| aot / cad_linkage / `measurements/placement_only_layer_edit` | 119 → 122 | +2.5% / +6.7% | 1/2/0 | 208 → 193 | -7.2% / -9.6% | 3/0/0 | -49.6%; 3/0/0 |
| aot / cad_linkage / `measurements/downstream_rejected_angle_edit` | 185 → 188 | +1.6% / +7.6% | 1/2/0 | 301 → 315 | +4.7% / +7.9% | 1/2/0 | +36.1%; 2/1/0 |
| aot / cad_instances / `cold_build_solve_regenerate` | 360 → 425 | +18.1% / +10.9% | 1/2/0 | 553 → 810 | +46.5% / +45.1% | 0/3/0 | +69.0%; 0/3/0 |
| aot / cad_instances / `solved_pose_edit` | 48 → 53 | +10.4% / +10.4% | 1/2/0 | 153 → 129 | -15.7% / -1.5% | 2/1/0 | +69.3%; 1/2/0 |

Consistent regressions (all three paired processes worse):

- aot geometry_coupled `cold_build_compile_solve` p95: aggregate +115.4%; individual pairs +129.1%, +20.1%, +75.6%.
- aot cad_instances `cold_build_solve_regenerate` p95: aggregate +46.5%; individual pairs +184.6%, +5.2%, +45.1%.

### Final-cad

Audit: **passed**, 221,459 checks; 36 reports and 20 rows. Counts: `{"aligned_work_distributions": 120, "aligned_work_records": 36000, "committed_library_files_checked": 88, "distributions": 120, "paired_counter_snapshots": 18, "paired_work_records": 18000, "raw_distributions": 120, "raw_samples": 36000, "reported_p99_values": 60}`.

| Runtime / fixture / operation | p50 before → after | Aggregate Δ / paired median Δ | p50 pairs F/S/E | p95 before → after | Aggregate Δ / paired median Δ | p95 pairs F/S/E | Derived p99 aggregate Δ; pairs F/S/E |
|---|---:|---:|---:|---:|---:|---:|---:|
| jit / cad / `cold_build_compile_regenerate` | 762 → 677 | -11.2% / -10.5% | 2/1/0 | 1369 → 1511 | +10.4% / +10.4% | 1/2/0 | +21.4%; 0/3/0 |
| jit / cad / `profile_edit_regenerate` | 731 → 682 | -6.7% / -6.7% | 2/1/0 | 1312 → 1420 | +8.2% / +8.2% | 1/2/0 | +44.9%; 1/2/0 |
| jit / cad / `thickness_edit_regenerate` | 564 → 527 | -6.6% / -6.6% | 3/0/0 | 1104 → 975 | -11.7% / -11.7% | 2/1/0 | -7.7%; 2/1/0 |
| jit / cad_linkage / `measurements/cold_build_solve_solids_meshes` | 1823 → 1845 | +1.2% / +2.1% | 1/2/0 | 2557 → 2675 | +4.6% / +15.8% | 1/2/0 | +27.5%; 1/2/0 |
| jit / cad_linkage / `measurements/retained_angle_edit` | 264 → 269 | +1.9% / +1.5% | 1/2/0 | 484 → 478 | -1.2% / -6.5% | 2/1/0 | +43.0%; 1/2/0 |
| jit / cad_linkage / `measurements/selective_coupler_length_edit` | 629 → 651 | +3.5% / +3.5% | 1/2/0 | 1014 → 945 | -6.8% / -2.8% | 2/1/0 | +41.1%; 1/2/0 |
| jit / cad_linkage / `measurements/placement_only_layer_edit` | 155 → 152 | -1.9% / -1.9% | 2/0/1 | 263 → 248 | -5.7% / -17.4% | 3/0/0 | +5.5%; 2/1/0 |
| jit / cad_linkage / `measurements/downstream_rejected_angle_edit` | 237 → 232 | -2.1% / -1.7% | 2/1/0 | 387 → 432 | +11.6% / +11.9% | 1/2/0 | -17.7%; 1/2/0 |
| jit / cad_instances / `cold_build_solve_regenerate` | 584 → 622 | +6.5% / +7.2% | 1/2/0 | 1439 → 1323 | -8.1% / -11.6% | 2/1/0 | -35.7%; 3/0/0 |
| jit / cad_instances / `solved_pose_edit` | 132 → 131 | -0.8% / +1.5% | 1/2/0 | 379 → 360 | -5.0% / -6.0% | 3/0/0 | -6.1%; 3/0/0 |
| aot / cad / `cold_build_compile_regenerate` | 733 → 681 | -7.1% / -7.8% | 3/0/0 | 1018 → 917 | -9.9% / -8.1% | 3/0/0 | -22.5%; 3/0/0 |
| aot / cad / `profile_edit_regenerate` | 752 → 696 | -7.4% / -7.4% | 3/0/0 | 1030 → 916 | -11.1% / -11.1% | 3/0/0 | -21.2%; 3/0/0 |
| aot / cad / `thickness_edit_regenerate` | 663 → 617 | -6.9% / -7.8% | 3/0/0 | 935 → 837 | -10.5% / -10.5% | 3/0/0 | -11.9%; 3/0/0 |
| aot / cad_linkage / `measurements/cold_build_solve_solids_meshes` | 1811 → 1813 | +0.1% / -0.3% | 2/1/0 | 2801 → 2439 | -12.9% / +2.7% | 1/2/0 | +44.0%; 0/3/0 |
| aot / cad_linkage / `measurements/retained_angle_edit` | 186 → 174 | -6.5% / -7.0% | 3/0/0 | 322 → 263 | -18.3% / -18.3% | 3/0/0 | -6.9%; 2/1/0 |
| aot / cad_linkage / `measurements/selective_coupler_length_edit` | 575 → 547 | -4.9% / -6.3% | 3/0/0 | 965 → 727 | -24.7% / -17.3% | 3/0/0 | +14.3%; 2/1/0 |
| aot / cad_linkage / `measurements/placement_only_layer_edit` | 111 → 101 | -9.0% / -9.9% | 3/0/0 | 169 → 148 | -12.4% / -14.8% | 3/0/0 | -35.6%; 3/0/0 |
| aot / cad_linkage / `measurements/downstream_rejected_angle_edit` | 166 → 156 | -6.0% / -6.0% | 3/0/0 | 310 → 246 | -20.6% / -19.0% | 3/0/0 | +16.6%; 1/2/0 |
| aot / cad_instances / `cold_build_solve_regenerate` | 349 → 421 | +20.6% / +21.7% | 0/3/0 | 547 → 943 | +72.4% / +72.4% | 0/3/0 | +630.6%; 0/3/0 |
| aot / cad_instances / `solved_pose_edit` | 48 → 48 | +0.0% / +0.0% | 1/1/1 | 139 → 115 | -17.3% / -18.4% | 3/0/0 | +98.9%; 0/3/0 |

Consistent regressions (all three paired processes worse):

- aot cad_instances `cold_build_solve_regenerate` p50: aggregate +20.6%; individual pairs +32.4%, +6.7%, +21.7%.
- aot cad_instances `cold_build_solve_regenerate` p95: aggregate +72.4%; individual pairs +138.5%, +72.4%, +10.1%.

### Final-controls

Audit: **passed**, 2,745 checks; 60 reports and 36 rows. Counts: `{"committed_library_files_checked": 88, "distributions": 216, "distributions_without_raw_samples": 24, "paired_counter_snapshots": 48, "raw_distributions": 192, "raw_samples": 4800}`.

| Runtime / fixture / operation | p50 before → after | Aggregate Δ / paired median Δ | p50 pairs F/S/E | p95 before → after | Aggregate Δ / paired median Δ | p95 pairs F/S/E | Derived p99 aggregate Δ; pairs F/S/E |
|---|---:|---:|---:|---:|---:|---:|---:|
| jit / geometry / `cold_build_compile_solve` | 3416 → 3391 | -0.7% / -5.7% | 3/0/0 | 12577 → 11146 | -11.4% / -5.5% | 3/0/0 | unavailable |
| jit / geometry / `warm_edit_solve` | 261 → 178 | -31.8% / -32.2% | 2/1/0 | 1127 → 771 | -31.6% / -31.4% | 3/0/0 | unavailable |
| jit / geometry_nonlinear / `cold_build_compile_solve` | 694 → 709 | +2.2% / +9.9% | 1/2/0 | 1233 → 1409 | +14.3% / -0.9% | 2/1/0 | +29.1%; 0/3/0 |
| jit / geometry_nonlinear / `warm_edit_solve` | 380 → 373 | -1.8% / -1.8% | 2/1/0 | 830 → 1003 | +20.8% / +13.1% | 1/2/0 | -20.8%; 1/2/0 |
| jit / geometry_coupled / `cold_build_compile_solve` | 1631 → 2206 | +35.3% / +32.9% | 1/2/0 | 3277 → 2895 | -11.7% / -13.3% | 3/0/0 | -25.6%; 3/0/0 |
| jit / geometry_coupled / `warm_edit_solve` | 577 → 873 | +51.3% / +26.9% | 1/2/0 | 1492 → 1731 | +16.0% / -22.2% | 2/1/0 | +17.9%; 2/1/0 |
| jit / cad_workspace / `cold_build_compile_regenerate` | 1914 → 2059 | +7.6% / -3.7% | 2/1/0 | 2792 → 3336 | +19.5% / +22.2% | 1/2/0 | +16.1%; 1/2/0 |
| jit / cad_workspace / `warm_edit_regenerate` | 939 → 930 | -1.0% / -1.0% | 2/1/0 | 1572 → 2171 | +38.1% / +11.9% | 0/3/0 | +12.7%; 1/2/0 |
| jit / cad_graph / `results/features=1000/cold_build_regenerate` | 1054 → 1266 | +20.1% / +12.8% | 1/2/0 | 2414 → 5471 | +126.6% / +110.7% | 1/2/0 | +97.2%; 1/2/0 |
| jit / cad_graph / `results/features=1000/sparse_edit` | 20 → 30 | +50.0% / +30.4% | 1/2/0 | 75 → 149 | +98.7% / +98.7% | 1/2/0 | +88.1%; 1/2/0 |
| jit / cad_graph / `results/features=1000/no_op_edit` | 3 → 4 | +33.3% / +20.0% | 0/2/1 | 32 → 32 | +0.0% / +42.4% | 1/2/0 | +42.0%; 1/2/0 |
| jit / cad_graph / `results/features=1000/unused_parameter_edit` | 5 → 9 | +80.0% / +50.0% | 0/2/1 | 10 → 25 | +150.0% / +20.0% | 0/3/0 | +158.3%; 0/3/0 |
| jit / cad_graph / `results/features=1000/rejected_edit` | 10 → 16 | +60.0% / +45.5% | 1/2/0 | 18 → 49 | +172.2% / +172.2% | 1/2/0 | +169.0%; 1/2/0 |
| jit / cad_graph / `results/features=10000/cold_build_regenerate` | 8938 → 11801 | +32.0% / +32.0% | 0/3/0 | 18509 → 25007 | +35.1% / +13.6% | 0/3/0 | +24.6%; 1/2/0 |
| jit / cad_graph / `results/features=10000/sparse_edit` | 52 → 53 | +1.9% / -1.8% | 2/1/0 | 132 → 94 | -28.8% / -28.8% | 2/1/0 | -44.4%; 2/1/0 |
| jit / cad_graph / `results/features=10000/no_op_edit` | 10 → 11 | +10.0% / +10.0% | 0/2/1 | 26 → 28 | +7.7% / +33.3% | 1/2/0 | +44.8%; 1/2/0 |
| jit / cad_graph / `results/features=10000/unused_parameter_edit` | 13 → 15 | +15.4% / +16.7% | 0/3/0 | 25 → 33 | +32.0% / +43.5% | 0/3/0 | +10.0%; 1/2/0 |
| jit / cad_graph / `results/features=10000/rejected_edit` | 16 → 17 | +6.2% / +6.2% | 1/2/0 | 25 → 57 | +128.0% / +128.0% | 0/2/1 | +188.9%; 1/2/0 |
| aot / geometry / `cold_build_compile_solve` | 1356 → 1494 | +10.2% / +1.3% | 1/2/0 | 2302 → 2689 | +16.8% / -0.4% | 2/1/0 | unavailable |
| aot / geometry / `warm_edit_solve` | 85 → 88 | +3.5% / -1.2% | 2/1/0 | 189 → 146 | -22.8% / -16.6% | 3/0/0 | unavailable |
| aot / geometry_nonlinear / `cold_build_compile_solve` | 64 → 64 | +0.0% / +0.0% | 0/1/2 | 153 → 186 | +21.6% / +21.6% | 0/3/0 | +23.9%; 0/3/0 |
| aot / geometry_nonlinear / `warm_edit_solve` | 45 → 46 | +2.2% / +0.0% | 0/1/2 | 122 → 118 | -3.3% / -9.9% | 2/1/0 | +10.2%; 1/2/0 |
| aot / geometry_coupled / `cold_build_compile_solve` | 830 → 865 | +4.2% / +1.5% | 0/3/0 | 1021 → 1324 | +29.7% / +28.2% | 0/3/0 | +172.4%; 0/3/0 |
| aot / geometry_coupled / `warm_edit_solve` | 541 → 562 | +3.9% / +2.4% | 1/2/0 | 631 → 719 | +13.9% / +24.8% | 0/3/0 | +24.7%; 1/2/0 |
| aot / cad_workspace / `cold_build_compile_regenerate` | 947 → 971 | +2.5% / +1.0% | 1/2/0 | 1228 → 1266 | +3.1% / +3.1% | 1/2/0 | +26.6%; 2/1/0 |
| aot / cad_workspace / `warm_edit_regenerate` | 618 → 630 | +1.9% / +1.9% | 1/2/0 | 770 → 819 | +6.4% / +6.4% | 1/2/0 | -36.5%; 2/1/0 |
| aot / cad_graph / `results/features=1000/cold_build_regenerate` | 358 → 364 | +1.7% / +3.1% | 0/3/0 | 744 → 608 | -18.3% / +4.8% | 1/2/0 | -12.8%; 2/1/0 |
| aot / cad_graph / `results/features=1000/sparse_edit` | 4 → 4 | +0.0% / +0.0% | 0/1/2 | 6 → 5 | -16.7% / +0.0% | 1/1/1 | -46.7%; 2/1/0 |
| aot / cad_graph / `results/features=1000/no_op_edit` | 0 → 0 | n/a / n/a | 0/0/3 | 0 → 0 | n/a / +0.0% | 0/0/3 | +0.0%; 1/0/2 |
| aot / cad_graph / `results/features=1000/unused_parameter_edit` | 0 → 0 | n/a / n/a | 0/1/2 | 0 → 0 | n/a / +0.0% | 0/0/3 | +100.0%; 0/2/1 |
| aot / cad_graph / `results/features=1000/rejected_edit` | 1 → 1 | +0.0% / +0.0% | 0/1/2 | 2 → 2 | +0.0% / +0.0% | 0/1/2 | -33.3%; 1/1/1 |
| aot / cad_graph / `results/features=10000/cold_build_regenerate` | 9173 → 9592 | +4.6% / -0.9% | 2/1/0 | 17627 → 16477 | -6.5% / +14.7% | 1/2/0 | +2.2%; 1/2/0 |
| aot / cad_graph / `results/features=10000/sparse_edit` | 17 → 14 | -17.6% / -6.7% | 2/0/1 | 66 → 22 | -66.7% / -53.0% | 3/0/0 | -79.0%; 3/0/0 |
| aot / cad_graph / `results/features=10000/no_op_edit` | 3 → 2 | -33.3% / +0.0% | 1/1/1 | 6 → 7 | +16.7% / +16.7% | 1/2/0 | +11.1%; 1/2/0 |
| aot / cad_graph / `results/features=10000/unused_parameter_edit` | 3 → 3 | +0.0% / +0.0% | 0/1/2 | 7 → 5 | -28.6% / -28.6% | 2/1/0 | -44.4%; 2/1/0 |
| aot / cad_graph / `results/features=10000/rejected_edit` | 5 → 6 | +20.0% / +0.0% | 0/1/2 | 10 → 11 | +10.0% / +0.0% | 1/1/1 | +53.8%; 1/2/0 |

Consistent regressions (all three paired processes worse):

- jit cad_workspace `warm_edit_regenerate` p95: aggregate +38.1%; individual pairs +11.9%, +9.2%, +111.3%.
- jit cad_graph `results/features=1000/unused_parameter_edit` p95: aggregate +150.0%; individual pairs +150.0%, +20.0%, +11.1%.
- jit cad_graph `results/features=10000/cold_build_regenerate` p50: aggregate +32.0%; individual pairs +32.0%, +34.5%, +29.3%.
- jit cad_graph `results/features=10000/cold_build_regenerate` p95: aggregate +35.1%; individual pairs +43.0%, +13.6%, +10.3%.
- jit cad_graph `results/features=10000/unused_parameter_edit` p50: aggregate +15.4%; individual pairs +23.1%, +7.1%, +16.7%.
- jit cad_graph `results/features=10000/unused_parameter_edit` p95: aggregate +32.0%; individual pairs +73.1%, +43.5%, +12.0%.
- aot geometry_nonlinear `cold_build_compile_solve` p95: aggregate +21.6%; individual pairs +11.3%, +33.8%, +21.6%.
- aot geometry_coupled `cold_build_compile_solve` p50: aggregate +4.2%; individual pairs +1.5%, +4.8%, +1.3%.
- aot geometry_coupled `cold_build_compile_solve` p95: aggregate +29.7%; individual pairs +28.2%, +0.5%, +77.6%.
- aot geometry_coupled `warm_edit_solve` p95: aggregate +13.9%; individual pairs +2.6%, +24.8%, +217.6%.
- aot cad_graph `results/features=1000/cold_build_regenerate` p50: aggregate +1.7%; individual pairs +3.1%, +0.8%, +26.2%.


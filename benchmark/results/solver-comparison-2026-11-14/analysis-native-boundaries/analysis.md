# Saved solver benchmark analysis

This report reads saved evidence only. It does not execute solvers or reinterpret geometry using a newer oracle. Detailed job records and source manifests are in analysis.json.

## Input provenance

| Run | Suite | Source commit | Jobs present / planned | Summary file |
| --- | --- | --- | --- | --- |
| run-001 | boundaries | 695307b29384 | 108/108 | summary.json |

Input directories:

- run-001: /workspace/scratch/5f75d818d06d/dart_csp/benchmark/results/solver-comparison-2026-11-14/native-boundaries

## Completeness and physical outcomes

Accepted counts refer to the independent saved physical oracle. Native numerical success followed by physical rejection is a separate observation, not automatically an incorrect claim of hard feasibility. Missing operations and adapter exceptions receive no credit as successful rejection of contradictory inputs.

| Fixture | Engine | Mode | Complete jobs | Accepted / expected | Warmup accepted / expected | Valid rejections | Exceptions | Native success rejected | Oracle disagreements | Timeout jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ladder_15_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_15_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_16_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_17_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_23_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_24_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_29_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_30_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_31_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_74_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_75_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_76_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |

## Qualified successful-solve latency

Each value is the median of per-process accepted-sample percentiles, giving each process equal weight. It is not a percentile of pooled observations. Both columns are withheld unless every included/planned job is complete and every measured sample is accepted, without oracle disagreement or incompatible build/request conditions. Warmups are counted above but excluded from latency.

A five-sample process p95 is its largest observation under the recorded upper-order statistic method. These tables do not establish stable p99 performance.

| Fixture | Engine | Mode | Processes | Median process p50 ms | Median process p95 ms | Max finite error / tolerance | Qualification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ladder_15_components_1 | ceres | warm | 1 | 0.349511 | 0.441868 | 0.655899 | qualified |
| ladder_15_components_1 | dart_2d_ad | warm | 1 | 2.97923 | 3.01098 | 0.135828 | qualified |
| ladder_15_components_1 | dart_2d_analytic | warm | 1 | 2.99105 | 3.0609 | 0.135828 | qualified |
| ladder_15_components_1 | dart_3d_ad | warm | 1 | 3.35047 | 11.1775 | 0.135828 | qualified |
| ladder_15_components_1 | ezpz | warm | 1 | 0.048252 | 0.050475 | 2.89968e-05 | qualified |
| ladder_15_components_1 | ezpz_analysis | warm | 1 | 0.074201 | 0.079208 | 2.89968e-05 | qualified |
| ladder_15_components_1 | neoscad | warm | 1 | 1.40019 | 1.59868 | 1.55431e-08 | qualified |
| ladder_15_components_1 | solvent | warm | 1 | 0.132397 | 0.176282 | 1.55431e-08 | qualified |
| ladder_15_components_1 | solvent_replay | warm | 1 | 0.03998 | 0.11398 | 6.66134e-09 | qualified |
| ladder_16_components_1 | ceres | warm | 1 | 0.386856 | 0.467806 | 0.86851 | qualified |
| ladder_16_components_1 | dart_2d_ad | warm | 1 | 3.98001 | 4.08849 | 0.193902 | qualified |
| ladder_16_components_1 | dart_2d_analytic | warm | 1 | 3.7784 | 3.93718 | 0.193902 | qualified |
| ladder_16_components_1 | dart_3d_ad | warm | 1 | 2.46752 | 3.36575 | 0.193902 | qualified |
| ladder_16_components_1 | ezpz | warm | 1 | 0.058307 | 0.06085 | 3.04401e-05 | qualified |
| ladder_16_components_1 | ezpz_analysis | warm | 1 | 0.084566 | 0.115712 | 3.04401e-05 | qualified |
| ladder_16_components_1 | neoscad | warm | 1 | 1.48867 | 1.69794 | 1.55431e-08 | qualified |
| ladder_16_components_1 | solvent | warm | 1 | 0.155913 | 0.174349 | 1.55431e-08 | qualified |
| ladder_16_components_1 | solvent_replay | warm | 1 | 0.038126 | 0.042384 | 3.55271e-08 | qualified |
| ladder_17_components_1 | ceres | warm | 1 | 0.548698 | 0.566764 | 0.105407 | qualified |
| ladder_17_components_1 | dart_2d_ad | warm | 1 | 1.62584 | 1.85309 | 0.257942 | qualified |
| ladder_17_components_1 | dart_2d_analytic | warm | 1 | 1.30704 | 1.38351 | 0.257942 | qualified |
| ladder_17_components_1 | dart_3d_ad | warm | 1 | 2.00917 | 2.75536 | 0.257942 | qualified |
| ladder_17_components_1 | ezpz | warm | 1 | 0.052218 | 0.058958 | 3.20788e-05 | qualified |
| ladder_17_components_1 | ezpz_analysis | warm | 1 | 0.095382 | 0.104256 | 3.20788e-05 | qualified |
| ladder_17_components_1 | neoscad | warm | 1 | 1.7114 | 1.94026 | 1.55431e-08 | qualified |
| ladder_17_components_1 | solvent | warm | 1 | 0.175371 | 0.193889 | 1.55431e-08 | qualified |
| ladder_17_components_1 | solvent_replay | warm | 1 | 0.041732 | 0.046639 | 3.55271e-08 | qualified |
| ladder_23_components_1 | ceres | warm | 1 | 1.07206 | 1.11451 | 0.492199 | qualified |
| ladder_23_components_1 | dart_2d_ad | warm | 1 | 2.62471 | 2.97342 | 0.539891 | qualified |
| ladder_23_components_1 | dart_2d_analytic | warm | 1 | 2.58614 | 2.68484 | 0.539891 | qualified |
| ladder_23_components_1 | dart_3d_ad | warm | 1 | 3.17375 | 3.32334 | 0.539891 | qualified |
| ladder_23_components_1 | ezpz | warm | 1 | 0.069704 | 0.073339 | 4.66938e-05 | qualified |
| ladder_23_components_1 | ezpz_analysis | warm | 1 | 0.157705 | 0.165116 | 4.66938e-05 | qualified |
| ladder_23_components_1 | neoscad | warm | 1 | 4.6039 | 4.65498 | 1.55431e-08 | qualified |
| ladder_23_components_1 | solvent | warm | 1 | 0.388248 | 0.398844 | 3.33067e-08 | qualified |
| ladder_23_components_1 | solvent_replay | warm | 1 | 0.055293 | 0.0604 | 3.55271e-08 | qualified |
| ladder_24_components_1 | ceres | warm | 1 | 1.18136 | 1.21154 | 0.55448 | qualified |
| ladder_24_components_1 | dart_2d_ad | warm | 1 | 2.73151 | 3.31683 | 0.553611 | qualified |
| ladder_24_components_1 | dart_2d_analytic | warm | 1 | 2.71074 | 3.01777 | 0.553611 | qualified |
| ladder_24_components_1 | dart_3d_ad | warm | 1 | 3.47258 | 3.80726 | 0.553611 | qualified |
| ladder_24_components_1 | ezpz | warm | 1 | 0.071346 | 0.072428 | 5.00311e-05 | qualified |
| ladder_24_components_1 | ezpz_analysis | warm | 1 | 0.171035 | 0.196873 | 5.00311e-05 | qualified |
| ladder_24_components_1 | neoscad | warm | 1 | 5.19547 | 5.24401 | 1.9984e-08 | qualified |
| ladder_24_components_1 | solvent | warm | 1 | 0.425214 | 0.462438 | 3.33067e-08 | qualified |
| ladder_24_components_1 | solvent_replay | warm | 1 | 0.06092 | 0.074541 | 3.55271e-08 | qualified |
| ladder_25_components_1 | ceres | warm | 1 | 1.43023 | 1.46348 | 0.607861 | qualified |
| ladder_25_components_1 | dart_2d_ad | warm | 1 | 2.41135 | 3.02339 | 0.560806 | qualified |
| ladder_25_components_1 | dart_2d_analytic | warm | 1 | 2.43271 | 2.57425 | 0.560806 | qualified |
| ladder_25_components_1 | dart_3d_ad | warm | 1 | 3.82318 | 3.98824 | 0.560806 | qualified |
| ladder_25_components_1 | ezpz | warm | 1 | 0.078146 | 0.096003 | 5.36637e-05 | qualified |
| ladder_25_components_1 | ezpz_analysis | warm | 1 | 0.177634 | 0.207949 | 5.36637e-05 | qualified |
| ladder_25_components_1 | neoscad | warm | 1 | 5.83245 | 6.04461 | 1.9984e-08 | qualified |
| ladder_25_components_1 | solvent | warm | 1 | 0.724369 | 2.73778 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent_replay | warm | 1 | 0.062764 | 0.072588 | 3.55271e-08 | qualified |
| ladder_29_components_1 | ceres | warm | 1 | 1.98286 | 2.04451 | 0.724042 | qualified |
| ladder_29_components_1 | dart_2d_ad | warm | 1 | 3.07005 | 3.26077 | 0.56798 | qualified |
| ladder_29_components_1 | dart_2d_analytic | warm | 1 | 3.41952 | 3.90742 | 0.56798 | qualified |
| ladder_29_components_1 | dart_3d_ad | warm | 1 | 4.78706 | 4.87538 | 0.56798 | qualified |
| ladder_29_components_1 | ezpz | warm | 1 | 0.08692 | 0.092628 | 7.13252e-05 | qualified |
| ladder_29_components_1 | ezpz_analysis | warm | 1 | 0.24158 | 0.518041 | 7.13252e-05 | qualified |
| ladder_29_components_1 | neoscad | warm | 1 | 8.29353 | 9.01307 | 3.33067e-08 | qualified |
| ladder_29_components_1 | solvent | warm | 1 | 0.706162 | 0.732571 | 3.33067e-08 | qualified |
| ladder_29_components_1 | solvent_replay | warm | 1 | 0.072428 | 0.077856 | 3.55271e-08 | qualified |
| ladder_30_components_1 | ceres | warm | 1 | 2.16677 | 2.18488 | 0.734555 | qualified |
| ladder_30_components_1 | dart_2d_ad | warm | 1 | 3.26504 | 3.43843 | 0.68516 | qualified |
| ladder_30_components_1 | dart_2d_analytic | warm | 1 | 3.18315 | 3.47988 | 0.68516 | qualified |
| ladder_30_components_1 | dart_3d_ad | warm | 1 | 5.2298 | 5.74146 | 0.68516 | qualified |
| ladder_30_components_1 | ezpz | warm | 1 | 0.091587 | 0.092999 | 7.65854e-05 | qualified |
| ladder_30_components_1 | ezpz_analysis | warm | 1 | 0.25532 | 0.265866 | 7.65854e-05 | qualified |
| ladder_30_components_1 | neoscad | warm | 1 | 8.93534 | 10.6145 | 3.33067e-08 | qualified |
| ladder_30_components_1 | solvent | warm | 1 | 0.774583 | 0.781534 | 3.33067e-08 | qualified |
| ladder_30_components_1 | solvent_replay | warm | 1 | 0.073379 | 0.081071 | 3.55271e-08 | qualified |
| ladder_31_components_1 | ceres | warm | 1 | 2.3243 | 2.38782 | 0.739197 | qualified |
| ladder_31_components_1 | dart_2d_ad | warm | 1 | 3.5481 | 3.6975 | 0.689418 | qualified |
| ladder_31_components_1 | dart_2d_analytic | warm | 1 | 3.28347 | 4.1325 | 0.689418 | qualified |
| ladder_31_components_1 | dart_3d_ad | warm | 1 | 5.51347 | 5.77503 | 0.689418 | qualified |
| ladder_31_components_1 | ezpz | warm | 1 | 0.08776 | 0.106148 | 8.22076e-05 | qualified |
| ladder_31_components_1 | ezpz_analysis | warm | 1 | 0.262691 | 0.345534 | 8.22076e-05 | qualified |
| ladder_31_components_1 | neoscad | warm | 1 | 10.1028 | 11.0614 | 3.33067e-08 | qualified |
| ladder_31_components_1 | solvent | warm | 1 | 0.043144 | 0.058417 | 3.33067e-08 | qualified |
| ladder_31_components_1 | solvent_replay | warm | 1 | 0.076434 | 0.086529 | 3.55271e-08 | qualified |
| ladder_74_components_1 | ceres | warm | 1 | 0.556259 | 0.57768 | 0.858613 | qualified |
| ladder_74_components_1 | dart_2d_ad | warm | 1 | 28.0155 | 29.3862 | 0.317972 | qualified |
| ladder_74_components_1 | dart_2d_analytic | warm | 1 | 25.7758 | 27.1825 | 0.317972 | qualified |
| ladder_74_components_1 | dart_3d_ad | warm | 1 | 42.6875 | 62.8885 | 0.317972 | qualified |
| ladder_74_components_1 | ezpz | warm | 1 | 0.236722 | 0.342871 | 0.000824101 | qualified |
| ladder_74_components_1 | ezpz_analysis | warm | 1 | 1.70819 | 1.82203 | 0.000824101 | qualified |
| ladder_74_components_1 | neoscad | warm | 1 | 140.655 | 152.124 | 6.88338e-08 | qualified |
| ladder_74_components_1 | solvent | warm | 1 | 0.076624 | 0.152117 | 0.000101326 | qualified |
| ladder_74_components_1 | solvent_replay | warm | 1 | 0.210824 | 0.243462 | 1.39888e-07 | qualified |
| ladder_75_components_1 | ceres | warm | 1 | 0.53707 | 0.559122 | 0.811006 | qualified |
| ladder_75_components_1 | dart_2d_ad | warm | 1 | 27.1125 | 28.5387 | 0.308804 | qualified |
| ladder_75_components_1 | dart_2d_analytic | warm | 1 | 26.484 | 26.8753 | 0.308804 | qualified |
| ladder_75_components_1 | dart_3d_ad | warm | 1 | 40.8066 | 41.0132 | 0.308804 | qualified |
| ladder_75_components_1 | ezpz | warm | 1 | 0.233588 | 0.243783 | 0.00085614 | qualified |
| ladder_75_components_1 | ezpz_analysis | warm | 1 | 1.71403 | 2.26678 | 0.00085614 | qualified |
| ladder_75_components_1 | neoscad | warm | 1 | 151.797 | 162.28 | 6.88338e-08 | qualified |
| ladder_75_components_1 | solvent | warm | 1 | 0.076494 | 0.076954 | 0.000101334 | qualified |
| ladder_75_components_1 | solvent_replay | warm | 1 | 0.205236 | 0.227659 | 1.39888e-07 | qualified |
| ladder_76_components_1 | ceres | warm | 1 | 0.532543 | 0.58406 | 0.843083 | qualified |
| ladder_76_components_1 | dart_2d_ad | warm | 1 | 28.4023 | 28.7655 | 0.305655 | qualified |
| ladder_76_components_1 | dart_2d_analytic | warm | 1 | 26.9593 | 27.6221 | 0.305655 | qualified |
| ladder_76_components_1 | dart_3d_ad | warm | 1 | 42.9505 | 43.3511 | 0.305655 | qualified |
| ladder_76_components_1 | ezpz | warm | 1 | 0.250993 | 0.269882 | 0.000888962 | qualified |
| ladder_76_components_1 | ezpz_analysis | warm | 1 | 1.74478 | 1.93866 | 0.000888962 | qualified |
| ladder_76_components_1 | neoscad | warm | 1 | 150.109 | 166.212 | 6.88338e-08 | qualified |
| ladder_76_components_1 | solvent | warm | 1 | 0.077395 | 0.1008 | 0.000101343 | qualified |
| ladder_76_components_1 | solvent_replay | warm | 1 | 0.217004 | 0.272996 | 1.39888e-07 | qualified |

## Reading limits

- Native adapter measurements exclude JSON, the external checker, browser/FFI integration and the full CAD application.
- Scalar coordinates are unfixed parameters before geometric constraints, not remaining DOF.
- Different sample or warmup counts per process are retained in JSON; select a consistent confirmation cohort when making a publication claim.
- Error ratios use each request tolerance. Missing/nonfinite errors are counted separately in JSON and are not silently converted into zero.
- Full manifests, binary/source hashes, archive hashes when read, per-job checksums, exclusions and optional engine metrics are in analysis.json.

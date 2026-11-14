# Saved solver benchmark analysis

This report reads saved evidence only. It does not execute solvers or reinterpret geometry using a newer oracle. Detailed job records and source manifests are in [analysis.json.gz](analysis.json.gz).

## Input provenance

| Run | Suite | Source commit | Jobs present / planned | Summary file |
| --- | --- | --- | --- | --- |
| run-001 | confirm | 695307b29384 | 162/162 | summary.json.gz |
| run-002 | coupled | 695307b29384 | 54/54 | summary.json.gz |
| run-003 | confirm | 695307b29384 | 27/27 | summary.json.gz |
| run-004 | coupled | 695307b29384 | 27/27 | summary.json.gz |
| run-005 | confirm | 695307b29384 | 15/15 | summary.json.gz |
| run-006 | coupled | 695307b29384 | 15/15 | summary.json.gz |

Input directories:

- run-001: /workspace/scratch/9a3b101dafc7/solver_recovery/benchmark/results/solver-comparison-2026-11-14/native-confirm-small
- run-002: /workspace/scratch/9a3b101dafc7/solver_recovery/benchmark/results/solver-comparison-2026-11-14/native-confirm-coupled-small
- run-003: /workspace/scratch/9a3b101dafc7/solver_recovery/benchmark/results/solver-comparison-2026-11-14/native-confirm-large-ladder
- run-004: /workspace/scratch/9a3b101dafc7/solver_recovery/benchmark/results/solver-comparison-2026-11-14/native-confirm-large-coupled
- run-005: /workspace/scratch/9a3b101dafc7/solver_recovery/benchmark/results/solver-comparison-2026-11-14/native-confirm-xlarge-ladder
- run-006: /workspace/scratch/9a3b101dafc7/solver_recovery/benchmark/results/solver-comparison-2026-11-14/native-confirm-xlarge-coupled

## Completeness and physical outcomes

Accepted counts refer to the independent saved physical oracle. Native numerical success followed by physical rejection is a separate observation, not automatically an incorrect claim of hard feasibility. Missing operations and adapter exceptions receive no credit as successful rejection of contradictory inputs.

| Fixture | Engine | Mode | Complete jobs | Accepted / expected | Warmup accepted / expected | Valid rejections | Exceptions | Native success rejected | Oracle disagreements | Timeout jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ladder_125_components_1 | ceres | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_2d_ad | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_2d_analytic | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_3d_ad | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ezpz | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ezpz_analysis | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | neoscad | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | solvent | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | solvent_replay | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ceres | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_analytic | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_3d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz_analysis | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | neoscad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent_replay | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ceres | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_analytic | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_3d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz_analysis | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | neoscad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent_replay | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ceres | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_analytic | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_3d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz_analysis | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | neoscad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent_replay | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ceres | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_analytic | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_3d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz_analysis | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | neoscad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent_replay | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ceres | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ezpz | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ezpz_analysis | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | solvent | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | solvent_replay | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ceres | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_analytic | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_3d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz_analysis | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | neoscad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent_replay | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ceres | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_analytic | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_3d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz_analysis | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | neoscad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent_replay | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ceres | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_analytic | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_3d_ad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz_analysis | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | neoscad | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent_replay | cold | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ceres | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_analytic | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_3d_ad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz_analysis | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | neoscad | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent_replay | warm | 3/3 | 75/75 | 15/15 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ceres | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ezpz | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ezpz_analysis | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | solvent | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | solvent_replay | warm | 0/3 | 15/15 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ceres | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_2d_ad | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_2d_analytic | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_3d_ad | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ezpz | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ezpz_analysis | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | neoscad | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | solvent | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | solvent_replay | warm | 0/3 | 30/30 | —/6 | 0 | 0 | 0 | 0 | 0 |

## Qualified successful-solve latency

Each value is the median of per-process accepted-sample percentiles, giving each process equal weight. It is not a percentile of pooled observations. Both columns are withheld unless every included/planned job is complete and every measured sample is accepted, without oracle disagreement or incompatible build/request conditions. Warmups are counted above but excluded from latency.

A five-sample process p95 is its largest observation under the recorded upper-order statistic method. These tables do not establish stable p99 performance.

| Fixture | Engine | Mode | Processes | Median process p50 ms | Median process p95 ms | Max finite error / tolerance | Qualification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ladder_125_components_1 | ceres | warm | 3 | — | — | 0.744603 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | dart_2d_ad | warm | 3 | — | — | 0.983122 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | dart_2d_analytic | warm | 3 | — | — | 0.993887 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | dart_3d_ad | warm | 3 | — | — | 0.983122 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | ezpz | warm | 3 | — | — | 0.00341876 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | ezpz_analysis | warm | 3 | — | — | 0.00341876 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | neoscad | warm | 3 | — | — | 1.39888e-07 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | solvent | warm | 3 | — | — | 0.000102018 | incomplete_or_invalid_jobs |
| ladder_125_components_1 | solvent_replay | warm | 3 | — | — | 1.39888e-07 | incomplete_or_invalid_jobs |
| ladder_1_components_25 | ceres | cold | 3 | 0.628346 | 0.721204 | 0.00860516 | qualified |
| ladder_1_components_25 | dart_2d_ad | cold | 3 | 0.500204 | 0.807893 | 0.585196 | qualified |
| ladder_1_components_25 | dart_2d_analytic | cold | 3 | 0.427707 | 0.749587 | 0.585196 | qualified |
| ladder_1_components_25 | dart_3d_ad | cold | 3 | 0.923666 | 1.15082 | 0.585196 | qualified |
| ladder_1_components_25 | ezpz | cold | 3 | 0.089844 | 0.103013 | 0.000332034 | qualified |
| ladder_1_components_25 | ezpz_analysis | cold | 3 | 0.589237 | 0.619723 | 0.000332034 | qualified |
| ladder_1_components_25 | neoscad | cold | 3 | 0.133138 | 0.174029 | 2.88658e-08 | qualified |
| ladder_1_components_25 | solvent | cold | 3 | 0.521307 | 0.603418 | 0.00103213 | qualified |
| ladder_1_components_25 | solvent_replay | cold | 3 | 0.652742 | 0.755925 | 3.13083e-07 | qualified |
| ladder_1_components_25 | ceres | warm | 3 | 0.592913 | 0.661675 | 0.00385227 | qualified |
| ladder_1_components_25 | dart_2d_ad | warm | 3 | 0.361309 | 0.563168 | 0.176533 | qualified |
| ladder_1_components_25 | dart_2d_analytic | warm | 3 | 0.285526 | 0.401508 | 0.176533 | qualified |
| ladder_1_components_25 | dart_3d_ad | warm | 3 | 0.564491 | 0.641145 | 0.176533 | qualified |
| ladder_1_components_25 | ezpz | warm | 3 | 0.089834 | 0.108652 | 2.226e-05 | qualified |
| ladder_1_components_25 | ezpz_analysis | warm | 3 | 0.593213 | 0.709136 | 2.226e-05 | qualified |
| ladder_1_components_25 | neoscad | warm | 3 | 0.130865 | 0.146298 | 2.88658e-08 | qualified |
| ladder_1_components_25 | solvent | warm | 3 | 0.320267 | 0.382821 | 0.000100946 | qualified |
| ladder_1_components_25 | solvent_replay | warm | 3 | 0.065428 | 0.079849 | 2.88658e-08 | qualified |
| ladder_25_components_1 | ceres | cold | 3 | 1.33371 | 1.62442 | 0.625059 | qualified |
| ladder_25_components_1 | dart_2d_ad | cold | 3 | 2.8105 | 4.03195 | 0.961667 | qualified |
| ladder_25_components_1 | dart_2d_analytic | cold | 3 | 2.53189 | 2.831 | 0.961667 | qualified |
| ladder_25_components_1 | dart_3d_ad | cold | 3 | 4.48381 | 5.01572 | 0.961667 | qualified |
| ladder_25_components_1 | ezpz | cold | 3 | 0.0738 | 0.124005 | 0.00093584 | qualified |
| ladder_25_components_1 | ezpz_analysis | cold | 3 | 0.177083 | 0.28863 | 0.00093584 | qualified |
| ladder_25_components_1 | neoscad | cold | 3 | 6.38571 | 6.97396 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent | cold | 3 | 0.517551 | 0.60473 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent_replay | cold | 3 | 0.359124 | 0.461167 | 3.9968e-08 | qualified |
| ladder_25_components_1 | ceres | warm | 3 | 1.43083 | 1.61989 | 0.607862 | qualified |
| ladder_25_components_1 | dart_2d_ad | warm | 3 | 2.3718 | 2.58427 | 0.560966 | qualified |
| ladder_25_components_1 | dart_2d_analytic | warm | 3 | 2.17896 | 2.3597 | 0.560966 | qualified |
| ladder_25_components_1 | dart_3d_ad | warm | 3 | 3.77416 | 4.03089 | 0.560966 | qualified |
| ladder_25_components_1 | ezpz | warm | 3 | 0.07409 | 0.083554 | 5.36637e-05 | qualified |
| ladder_25_components_1 | ezpz_analysis | warm | 3 | 0.175451 | 0.222461 | 5.36637e-05 | qualified |
| ladder_25_components_1 | neoscad | warm | 3 | 5.06443 | 6.08749 | 1.9984e-08 | qualified |
| ladder_25_components_1 | solvent | warm | 3 | 0.478272 | 0.582968 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent_replay | warm | 3 | 0.056664 | 0.071586 | 3.55271e-08 | qualified |
| ladder_500_components_1 | ceres | warm | 3 | — | — | 0.707901 | incomplete_or_invalid_jobs |
| ladder_500_components_1 | ezpz | warm | 3 | — | — | 0.0134623 | incomplete_or_invalid_jobs |
| ladder_500_components_1 | ezpz_analysis | warm | 3 | — | — | 0.0134623 | incomplete_or_invalid_jobs |
| ladder_500_components_1 | solvent | warm | 3 | — | — | 0.000123201 | incomplete_or_invalid_jobs |
| ladder_500_components_1 | solvent_replay | warm | 3 | — | — | 4.06342e-07 | incomplete_or_invalid_jobs |
| ladder_5_components_1 | ceres | cold | 3 | 0.031247 | 0.032999 | 0.16016 | qualified |
| ladder_5_components_1 | dart_2d_ad | cold | 3 | 0.197034 | 0.313136 | 0.938654 | qualified |
| ladder_5_components_1 | dart_2d_analytic | cold | 3 | 0.173449 | 0.276131 | 0.938654 | qualified |
| ladder_5_components_1 | dart_3d_ad | cold | 3 | 0.433145 | 0.526284 | 0.938654 | qualified |
| ladder_5_components_1 | ezpz | cold | 3 | 0.017476 | 0.019369 | 0.000468621 | qualified |
| ladder_5_components_1 | ezpz_analysis | cold | 3 | 0.023916 | 0.02667 | 0.000468621 | qualified |
| ladder_5_components_1 | neoscad | cold | 3 | 0.060821 | 0.074761 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent | cold | 3 | 0.021131 | 0.022684 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent_replay | cold | 3 | 0.05353 | 0.07362 | 1.77636e-08 | qualified |
| ladder_5_components_1 | ceres | warm | 3 | 0.028923 | 0.029634 | 0.80638 | qualified |
| ladder_5_components_1 | dart_2d_ad | warm | 3 | 0.158907 | 0.27562 | 0.477965 | qualified |
| ladder_5_components_1 | dart_2d_analytic | warm | 3 | 0.14804 | 0.250353 | 0.477965 | qualified |
| ladder_5_components_1 | dart_3d_ad | warm | 3 | 0.402199 | 0.511212 | 0.477965 | qualified |
| ladder_5_components_1 | ezpz | warm | 3 | 0.017476 | 0.02008 | 2.24976e-05 | qualified |
| ladder_5_components_1 | ezpz_analysis | warm | 3 | 0.024016 | 0.026459 | 2.24976e-05 | qualified |
| ladder_5_components_1 | neoscad | warm | 3 | 0.061271 | 0.075091 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent | warm | 3 | 0.014281 | 0.015473 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent_replay | warm | 3 | 0.010155 | 0.010626 | 8.88178e-09 | qualified |
| laman_free_100 | ceres | cold | 3 | 2.00922 | 2.15575 | 0.299708 | qualified |
| laman_free_100 | dart_2d_ad | cold | 3 | 3.57628 | 3.78369 | 0.984891 | qualified |
| laman_free_100 | dart_2d_analytic | cold | 3 | 3.32372 | 3.53444 | 0.984891 | qualified |
| laman_free_100 | dart_3d_ad | cold | 3 | 5.65293 | 5.99128 | 0.984891 | qualified |
| laman_free_100 | ezpz | cold | 3 | 0.094401 | 0.111617 | 0.108899 | qualified |
| laman_free_100 | ezpz_analysis | cold | 3 | 0.262631 | 0.296212 | 0.108899 | qualified |
| laman_free_100 | neoscad | cold | 3 | 5.84823 | 6.13302 | 8.88178e-09 | qualified |
| laman_free_100 | solvent | cold | 3 | 0.509489 | 0.546273 | 8.88178e-09 | qualified |
| laman_free_100 | solvent_replay | cold | 3 | 8.32672 | 8.65746 | 8.88178e-09 | qualified |
| laman_free_100 | ceres | warm | 3 | 1.99207 | 2.04977 | 0.188103 | qualified |
| laman_free_100 | dart_2d_ad | warm | 3 | 3.49775 | 3.59712 | 0.913674 | qualified |
| laman_free_100 | dart_2d_analytic | warm | 3 | 3.25007 | 3.47104 | 0.913674 | qualified |
| laman_free_100 | dart_3d_ad | warm | 3 | 5.39257 | 5.88675 | 0.913674 | qualified |
| laman_free_100 | ezpz | warm | 3 | 0.09409 | 0.116003 | 0.0418338 | qualified |
| laman_free_100 | ezpz_analysis | warm | 3 | 0.26145 | 0.292035 | 0.0418338 | qualified |
| laman_free_100 | neoscad | warm | 3 | 5.43476 | 6.07927 | 1.77636e-08 | qualified |
| laman_free_100 | solvent | warm | 3 | 0.47689 | 0.581225 | 8.88178e-09 | qualified |
| laman_free_100 | solvent_replay | warm | 3 | 0.691259 | 0.720824 | 8.88178e-09 | qualified |
| laman_free_2000 | ceres | warm | 3 | — | — | 0.431442 | incomplete_or_invalid_jobs |
| laman_free_2000 | ezpz | warm | 3 | — | — | 0.676718 | incomplete_or_invalid_jobs |
| laman_free_2000 | ezpz_analysis | warm | 3 | — | — | 0.676718 | incomplete_or_invalid_jobs |
| laman_free_2000 | solvent | warm | 3 | — | — | 4.25715e-06 | incomplete_or_invalid_jobs |
| laman_free_2000 | solvent_replay | warm | 3 | — | — | 5.06289e-06 | incomplete_or_invalid_jobs |
| laman_free_500 | ceres | warm | 3 | — | — | 0.780634 | incomplete_or_invalid_jobs |
| laman_free_500 | dart_2d_ad | warm | 3 | — | — | 0.619498 | incomplete_or_invalid_jobs |
| laman_free_500 | dart_2d_analytic | warm | 3 | — | — | 0.619498 | incomplete_or_invalid_jobs |
| laman_free_500 | dart_3d_ad | warm | 3 | — | — | 0.619498 | incomplete_or_invalid_jobs |
| laman_free_500 | ezpz | warm | 3 | — | — | 0.351895 | incomplete_or_invalid_jobs |
| laman_free_500 | ezpz_analysis | warm | 3 | — | — | 0.351895 | incomplete_or_invalid_jobs |
| laman_free_500 | neoscad | warm | 3 | — | — | 1.77636e-08 | incomplete_or_invalid_jobs |
| laman_free_500 | solvent | warm | 3 | — | — | 1.77636e-08 | incomplete_or_invalid_jobs |
| laman_free_500 | solvent_replay | warm | 3 | — | — | 3.38618e-08 | incomplete_or_invalid_jobs |

## Partial or rejected results: descriptive only

These statistics retain completed observations from excluded groups. They must not be ranked as successful-solve latency. An accepted subset can be easier than the missing or rejected operations. Process timeouts are whole-job limits.

| Fixture | Engine | Mode | Observed / expected | Accepted subset processes | Available accepted p50 ms | Available accepted p95 ms | All-observation p50 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ladder_125_components_1 | ceres | warm | 30/30 | 3 | 1.03822 | 1.17803 | 1.03822 |
| ladder_125_components_1 | dart_2d_ad | warm | 30/30 | 3 | 125.857 | 148.253 | 125.857 |
| ladder_125_components_1 | dart_2d_analytic | warm | 30/30 | 3 | 124.086 | 151.181 | 124.086 |
| ladder_125_components_1 | dart_3d_ad | warm | 30/30 | 3 | 190.188 | 202.978 | 190.188 |
| ladder_125_components_1 | ezpz | warm | 30/30 | 3 | 0.446195 | 0.485803 | 0.446195 |
| ladder_125_components_1 | ezpz_analysis | warm | 30/30 | 3 | 6.59151 | 7.00973 | 6.59151 |
| ladder_125_components_1 | neoscad | warm | 30/30 | 3 | 719.166 | 768.043 | 719.166 |
| ladder_125_components_1 | solvent | warm | 30/30 | 3 | 0.127871 | 0.169172 | 0.127871 |
| ladder_125_components_1 | solvent_replay | warm | 30/30 | 3 | 0.427727 | 0.538572 | 0.427727 |
| ladder_500_components_1 | ceres | warm | 15/15 | 3 | 5.43032 | 5.77871 | 5.43032 |
| ladder_500_components_1 | ezpz | warm | 15/15 | 3 | 2.01705 | 3.84044 | 2.01705 |
| ladder_500_components_1 | ezpz_analysis | warm | 15/15 | 3 | 594.44 | 642.062 | 594.44 |
| ladder_500_components_1 | solvent | warm | 15/15 | 3 | 0.499704 | 0.558832 | 0.499704 |
| ladder_500_components_1 | solvent_replay | warm | 15/15 | 3 | 2.49972 | 2.622 | 2.49972 |
| laman_free_2000 | ceres | warm | 15/15 | 3 | 141.223 | 150.587 | 141.223 |
| laman_free_2000 | ezpz | warm | 15/15 | 3 | 7.55401 | 12.5119 | 7.55401 |
| laman_free_2000 | ezpz_analysis | warm | 15/15 | 3 | 593.442 | 640.33 | 593.442 |
| laman_free_2000 | solvent | warm | 15/15 | 3 | 632.117 | 655.937 | 632.117 |
| laman_free_2000 | solvent_replay | warm | 15/15 | 3 | 1037.6 | 1058.68 | 1037.6 |
| laman_free_500 | ceres | warm | 30/30 | 3 | 2.51846 | 2.80771 | 2.51846 |
| laman_free_500 | dart_2d_ad | warm | 30/30 | 3 | 56.5498 | 62.7218 | 56.5498 |
| laman_free_500 | dart_2d_analytic | warm | 30/30 | 3 | 54.9862 | 59.8947 | 54.9862 |
| laman_free_500 | dart_3d_ad | warm | 30/30 | 3 | 85.8424 | 87.8933 | 85.8424 |
| laman_free_500 | ezpz | warm | 30/30 | 3 | 0.818018 | 0.972128 | 0.818018 |
| laman_free_500 | ezpz_analysis | warm | 30/30 | 3 | 7.55512 | 7.67482 | 7.55512 |
| laman_free_500 | neoscad | warm | 30/30 | 3 | 681.084 | 701.629 | 681.084 |
| laman_free_500 | solvent | warm | 30/30 | 3 | 4.04726 | 4.42488 | 4.04726 |
| laman_free_500 | solvent_replay | warm | 30/30 | 3 | 7.04275 | 7.21973 | 7.04275 |

## Reading limits

- Native adapter measurements exclude JSON, the external checker, browser/FFI integration and the full CAD application.
- Scalar coordinates are unfixed parameters before geometric constraints, not remaining DOF.
- Different sample or warmup counts per process are retained in JSON; select a consistent confirmation cohort when making a publication claim.
- Error ratios use each request tolerance. Missing/nonfinite errors are counted separately in JSON and are not silently converted into zero.
- Full manifests, binary/source hashes, archive hashes when read, per-job checksums, exclusions and optional engine metrics are in analysis.json.

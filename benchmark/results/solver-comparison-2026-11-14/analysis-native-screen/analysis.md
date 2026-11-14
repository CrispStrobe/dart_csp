# Saved solver benchmark analysis

This report reads saved evidence only. It does not execute solvers or reinterpret geometry using a newer oracle. Detailed job records and source manifests are in analysis.json.

## Input provenance

| Run | Suite | Source commit | Jobs present / planned | Summary file |
| --- | --- | --- | --- | --- |
| run-001 | screen | 3c5555d90245 | 198/198 | summary.json |
| run-002 | coupled | 266a59f76dd4 | 54/54 | summary.json |
| run-003 | screen | 266a59f76dd4 | 36/36 | summary.json |

Input directories:

- run-001: /workspace/scratch/5f75d818d06d/dart_csp/benchmark/results/solver-comparison-2026-11-14/native-screen-core
- run-002: /workspace/scratch/5f75d818d06d/dart_csp/benchmark/results/solver-comparison-2026-11-14/native-screen-coupled
- run-003: /workspace/scratch/5f75d818d06d/dart_csp/benchmark/results/solver-comparison-2026-11-14/native-screen-large

## Completeness and physical outcomes

Accepted counts refer to the independent saved physical oracle. Native numerical success followed by physical rejection is a separate observation, not automatically an incorrect claim of hard feasibility. Missing operations and adapter exceptions receive no credit as successful rejection of contradictory inputs.

| Fixture | Engine | Mode | Complete jobs | Accepted / expected | Warmup accepted / expected | Valid rejections | Exceptions | Native success rejected | Oracle disagreements | Timeout jobs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| axis_rectangle | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| axis_rectangle | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| canonical_cell | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| coincidence | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| contradictory_distance | ceres | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| contradictory_distance | dart_2d_ad | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | dart_2d_analytic | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | dart_3d_ad | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | ezpz | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | ezpz_analysis | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | neoscad | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | solvent | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | solvent_replay | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | ceres | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| contradictory_distance | dart_2d_ad | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | dart_2d_analytic | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | dart_3d_ad | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | ezpz | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | ezpz_analysis | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | neoscad | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | solvent | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| contradictory_distance | solvent_replay | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ceres | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_2d_ad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_2d_analytic | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_3d_ad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ezpz | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ezpz_analysis | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | neoscad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | solvent | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | solvent_replay | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ceres | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_2d_ad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_2d_analytic | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | dart_3d_ad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ezpz | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | ezpz_analysis | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | neoscad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | solvent | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_125_components_1 | solvent_replay | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_1_components_25 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_25_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ceres | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | dart_2d_ad | cold | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | dart_2d_analytic | cold | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | dart_3d_ad | cold | 0/1 | 0/3 | 0/1 | 1 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | ezpz | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ezpz_analysis | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | neoscad | cold | 0/1 | 0/3 | 0/1 | 0 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | solvent | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | solvent_replay | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ceres | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | dart_2d_ad | warm | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | dart_2d_analytic | warm | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | dart_3d_ad | warm | 0/1 | 0/3 | 0/1 | 1 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | ezpz | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | ezpz_analysis | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | neoscad | warm | 0/1 | 0/3 | 0/1 | 0 | 0 | 0 | 0 | 1 |
| ladder_500_components_1 | solvent | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_500_components_1 | solvent_replay | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_offset_1e+06 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_redundant | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | ezpz | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | ezpz_analysis | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | solvent | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | ezpz | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | ezpz_analysis | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | solvent | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e+06 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | ceres | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | dart_2d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | dart_2d_analytic | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | dart_3d_ad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | ezpz | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | ezpz_analysis | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | neoscad | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | solvent | cold | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | solvent_replay | cold | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | ceres | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | dart_2d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | dart_2d_analytic | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | dart_3d_ad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | ezpz | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | ezpz_analysis | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | neoscad | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | solvent | warm | 1/1 | 0/5 | 0/2 | 5 | 0 | 5 | 0 | 0 |
| ladder_5_components_1_scale_1e-06 | solvent_replay | warm | 1/1 | 5/5 | 2/2 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ceres | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_ad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_analytic | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_3d_ad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz_analysis | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | neoscad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent_replay | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ceres | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_ad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_2d_analytic | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | dart_3d_ad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | ezpz_analysis | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | neoscad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_100 | solvent_replay | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ceres | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | dart_2d_ad | cold | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| laman_free_2000 | dart_2d_analytic | cold | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| laman_free_2000 | dart_3d_ad | cold | 0/1 | 0/3 | 0/1 | 1 | 0 | 0 | 0 | 1 |
| laman_free_2000 | ezpz | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ezpz_analysis | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | neoscad | cold | 0/1 | 0/3 | 0/1 | 0 | 0 | 0 | 0 | 1 |
| laman_free_2000 | solvent | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | solvent_replay | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ceres | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | dart_2d_ad | warm | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| laman_free_2000 | dart_2d_analytic | warm | 0/1 | 0/3 | 0/1 | 2 | 0 | 0 | 0 | 1 |
| laman_free_2000 | dart_3d_ad | warm | 0/1 | 0/3 | 0/1 | 1 | 0 | 0 | 0 | 1 |
| laman_free_2000 | ezpz | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | ezpz_analysis | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | neoscad | warm | 0/1 | 0/3 | 0/1 | 0 | 0 | 0 | 0 | 1 |
| laman_free_2000 | solvent | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_2000 | solvent_replay | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ceres | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_2d_ad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_2d_analytic | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_3d_ad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ezpz | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ezpz_analysis | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | neoscad | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | solvent | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | solvent_replay | cold | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ceres | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_2d_ad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_2d_analytic | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | dart_3d_ad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ezpz | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | ezpz_analysis | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | neoscad | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | solvent | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |
| laman_free_500 | solvent_replay | warm | 1/1 | 3/3 | 1/1 | 0 | 0 | 0 | 0 | 0 |

## Qualified successful-solve latency

Each value is the median of per-process accepted-sample percentiles, giving each process equal weight. It is not a percentile of pooled observations. Both columns are withheld unless every included/planned job is complete and every measured sample is accepted, without oracle disagreement or incompatible build/request conditions. Warmups are counted above but excluded from latency.

A five-sample process p95 is its largest observation under the recorded upper-order statistic method. These tables do not establish stable p99 performance.

| Fixture | Engine | Mode | Processes | Median process p50 ms | Median process p95 ms | Max finite error / tolerance | Qualification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| axis_rectangle | ceres | cold | 1 | 0.010405 | 0.011557 | 0.000185136 | qualified |
| axis_rectangle | dart_2d_ad | cold | 1 | 0.045638 | 0.092347 | 0.0389711 | qualified |
| axis_rectangle | dart_2d_analytic | cold | 1 | 0.032629 | 0.04064 | 0.0389711 | qualified |
| axis_rectangle | dart_3d_ad | cold | 1 | 0.096393 | 0.119297 | 0.0389711 | qualified |
| axis_rectangle | ezpz | cold | 1 | 0.00643 | 0.007381 | 1.11518e-05 | qualified |
| axis_rectangle | ezpz_analysis | cold | 1 | 0.007772 | 0.023796 | 1.11518e-05 | qualified |
| axis_rectangle | neoscad | cold | 1 | 0.01313 | 0.013661 | 0 | qualified |
| axis_rectangle | solvent | cold | 1 | 0.00681 | 0.007251 | 1.82574e-20 | qualified |
| axis_rectangle | solvent_replay | cold | 1 | 0.04671 | 0.109443 | 2.22045e-09 | qualified |
| axis_rectangle | ceres | warm | 1 | 0.007501 | 0.010496 | 0.0666365 | qualified |
| axis_rectangle | dart_2d_ad | warm | 1 | 0.032318 | 0.034211 | 0.00764584 | qualified |
| axis_rectangle | dart_2d_analytic | warm | 1 | 0.022404 | 0.024607 | 0.00764584 | qualified |
| axis_rectangle | dart_3d_ad | warm | 1 | 0.069443 | 0.078567 | 0.00764584 | qualified |
| axis_rectangle | ezpz | warm | 1 | 0.005088 | 0.005639 | 0.004 | qualified |
| axis_rectangle | ezpz_analysis | warm | 1 | 0.006569 | 0.022383 | 0.004 | qualified |
| axis_rectangle | neoscad | warm | 1 | 0.009595 | 0.031467 | 0 | qualified |
| axis_rectangle | solvent | warm | 1 | 0.004627 | 0.005128 | 0 | qualified |
| axis_rectangle | solvent_replay | warm | 1 | 0.00697 | 0.007391 | 2.22045e-09 | qualified |
| canonical_cell | ceres | cold | 1 | 0.00662 | 0.007702 | 0.00444187 | qualified |
| canonical_cell | dart_2d_ad | cold | 1 | 0.030716 | 0.039078 | 0.10458 | qualified |
| canonical_cell | dart_2d_analytic | cold | 1 | 0.024616 | 0.03353 | 0.10458 | qualified |
| canonical_cell | dart_3d_ad | cold | 1 | 0.061011 | 0.069063 | 0.10458 | qualified |
| canonical_cell | ezpz | cold | 1 | 0.007 | 0.007701 | 0.000332034 | qualified |
| canonical_cell | ezpz_analysis | cold | 1 | 0.008502 | 0.010256 | 0.000332034 | qualified |
| canonical_cell | neoscad | cold | 1 | 0.008543 | 0.008974 | 2.22045e-09 | qualified |
| canonical_cell | solvent | cold | 1 | 0.004627 | 0.005338 | 0 | qualified |
| canonical_cell | solvent_replay | cold | 1 | 0.012959 | 0.014491 | 2.22045e-09 | qualified |
| canonical_cell | ceres | warm | 1 | 0.005879 | 0.023154 | 0.00385227 | qualified |
| canonical_cell | dart_2d_ad | warm | 1 | 0.022093 | 0.029033 | 0.176533 | qualified |
| canonical_cell | dart_2d_analytic | warm | 1 | 0.016274 | 0.030435 | 0.176533 | qualified |
| canonical_cell | dart_3d_ad | warm | 1 | 0.037646 | 0.045177 | 0.176533 | qualified |
| canonical_cell | ezpz | warm | 1 | 0.007782 | 0.043775 | 2.226e-05 | qualified |
| canonical_cell | ezpz_analysis | warm | 1 | 0.009043 | 0.054401 | 2.226e-05 | qualified |
| canonical_cell | neoscad | warm | 1 | 0.008563 | 0.009024 | 0 | qualified |
| canonical_cell | solvent | warm | 1 | 0.002254 | 0.002504 | 0 | qualified |
| canonical_cell | solvent_replay | warm | 1 | 0.002424 | 0.003105 | 2.22045e-09 | qualified |
| coincidence | ceres | cold | 1 | 0.005307 | 0.005918 | 0.00471342 | qualified |
| coincidence | dart_2d_ad | cold | 1 | 0.011628 | 0.013971 | 0.470777 | qualified |
| coincidence | dart_2d_analytic | cold | 1 | 0.010696 | 0.011948 | 0.470777 | qualified |
| coincidence | dart_3d_ad | cold | 1 | 0.029965 | 0.031357 | 0.000417818 | qualified |
| coincidence | ezpz | cold | 1 | 0.002654 | 0.003135 | 0.00141421 | qualified |
| coincidence | ezpz_analysis | cold | 1 | 0.003275 | 0.004387 | 0.00141421 | qualified |
| coincidence | neoscad | cold | 1 | 0.005238 | 0.005489 | 0 | qualified |
| coincidence | solvent | cold | 1 | 0.002764 | 0.003635 | 0 | qualified |
| coincidence | solvent_replay | cold | 1 | 0.003665 | 0.004407 | 0 | qualified |
| coincidence | ceres | warm | 1 | 0.002023 | 0.002444 | 0.00471342 | qualified |
| coincidence | dart_2d_ad | warm | 1 | 0.001863 | 0.002363 | 0.470777 | qualified |
| coincidence | dart_2d_analytic | warm | 1 | 0.001913 | 0.002093 | 0.470777 | qualified |
| coincidence | dart_3d_ad | warm | 1 | 0.002304 | 0.002504 | 0.000417818 | qualified |
| coincidence | ezpz | warm | 1 | 0.001643 | 0.001953 | 0.00141421 | qualified |
| coincidence | ezpz_analysis | warm | 1 | 0.002414 | 0.002814 | 0.00141421 | qualified |
| coincidence | neoscad | warm | 1 | 0.001532 | 0.001643 | 0 | qualified |
| coincidence | solvent | warm | 1 | 0.00053 | 0.000631 | 0 | qualified |
| coincidence | solvent_replay | warm | 1 | 0.00049 | 0.000541 | 0 | qualified |
| contradictory_distance | ceres | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | dart_2d_ad | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | dart_2d_analytic | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | dart_3d_ad | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | ezpz | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | ezpz_analysis | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | neoscad | cold | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | solvent | cold | 1 | — | — | 1.0485e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | solvent_replay | cold | 1 | — | — | 1.0485e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | ceres | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | dart_2d_ad | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | dart_2d_analytic | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | dart_3d_ad | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | ezpz | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | ezpz_analysis | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | neoscad | warm | 1 | — | — | 1.003e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | solvent | warm | 1 | — | — | 1.0485e+06 | expected_infeasible, not_all_measured_samples_accepted |
| contradictory_distance | solvent_replay | warm | 1 | — | — | 1.0485e+06 | expected_infeasible, not_all_measured_samples_accepted |
| ladder_125_components_1 | ceres | cold | 1 | 1.1502 | 1.97265 | 0.575363 | qualified |
| ladder_125_components_1 | dart_2d_ad | cold | 1 | 93.2698 | 93.5758 | 0.998981 | qualified |
| ladder_125_components_1 | dart_2d_analytic | cold | 1 | 125.331 | 127.55 | 0.747256 | qualified |
| ladder_125_components_1 | dart_3d_ad | cold | 1 | 151.018 | 152.893 | 0.998981 | qualified |
| ladder_125_components_1 | ezpz | cold | 1 | 0.428067 | 0.451793 | 0.0244199 | qualified |
| ladder_125_components_1 | ezpz_analysis | cold | 1 | 6.66515 | 6.82314 | 0.0244199 | qualified |
| ladder_125_components_1 | neoscad | cold | 1 | 662.376 | 691.17 | 1.39888e-07 | qualified |
| ladder_125_components_1 | solvent | cold | 1 | 0.608236 | 0.655076 | 5.82867e-07 | qualified |
| ladder_125_components_1 | solvent_replay | cold | 1 | 3.62143 | 4.72351 | 2.93099e-07 | qualified |
| ladder_125_components_1 | ceres | warm | 1 | 1.04942 | 1.05641 | 0.626587 | qualified |
| ladder_125_components_1 | dart_2d_ad | warm | 1 | 123.64 | 124.051 | 0.745164 | qualified |
| ladder_125_components_1 | dart_2d_analytic | warm | 1 | 122.279 | 148.036 | 0.800081 | qualified |
| ladder_125_components_1 | dart_3d_ad | warm | 1 | 185.74 | 185.796 | 0.745164 | qualified |
| ladder_125_components_1 | ezpz | warm | 1 | 0.401228 | 0.424642 | 0.00346501 | qualified |
| ladder_125_components_1 | ezpz_analysis | warm | 1 | 6.58842 | 6.78562 | 0.00346501 | qualified |
| ladder_125_components_1 | neoscad | warm | 1 | 667.566 | 757.056 | 1.39888e-07 | qualified |
| ladder_125_components_1 | solvent | warm | 1 | 0.145467 | 0.151516 | 0.000102018 | qualified |
| ladder_125_components_1 | solvent_replay | warm | 1 | 0.398844 | 0.41657 | 1.39888e-07 | qualified |
| ladder_1_components_25 | ceres | cold | 1 | 0.63102 | 0.702316 | 0.00860516 | qualified |
| ladder_1_components_25 | dart_2d_ad | cold | 1 | 0.840582 | 0.910266 | 0.585196 | qualified |
| ladder_1_components_25 | dart_2d_analytic | cold | 1 | 0.56358 | 0.638631 | 0.585196 | qualified |
| ladder_1_components_25 | dart_3d_ad | cold | 1 | 1.44358 | 2.67772 | 0.585196 | qualified |
| ladder_1_components_25 | ezpz | cold | 1 | 0.092698 | 0.098697 | 0.000332034 | qualified |
| ladder_1_components_25 | ezpz_analysis | cold | 1 | 0.606924 | 0.630769 | 0.000332034 | qualified |
| ladder_1_components_25 | neoscad | cold | 1 | 0.146899 | 0.163464 | 2.88658e-08 | qualified |
| ladder_1_components_25 | solvent | cold | 1 | 0.529498 | 0.585873 | 0.00103213 | qualified |
| ladder_1_components_25 | solvent_replay | cold | 1 | 0.675196 | 0.710439 | 3.13083e-07 | qualified |
| ladder_1_components_25 | ceres | warm | 1 | 0.596298 | 0.646423 | 0.00385227 | qualified |
| ladder_1_components_25 | dart_2d_ad | warm | 1 | 0.513265 | 0.549128 | 0.176533 | qualified |
| ladder_1_components_25 | dart_2d_analytic | warm | 1 | 0.273558 | 0.281409 | 0.176533 | qualified |
| ladder_1_components_25 | dart_3d_ad | warm | 1 | 0.890166 | 0.955013 | 0.176533 | qualified |
| ladder_1_components_25 | ezpz | warm | 1 | 0.094291 | 0.118477 | 2.226e-05 | qualified |
| ladder_1_components_25 | ezpz_analysis | warm | 1 | 0.610559 | 0.625362 | 2.226e-05 | qualified |
| ladder_1_components_25 | neoscad | warm | 1 | 0.137735 | 0.149903 | 2.88658e-08 | qualified |
| ladder_1_components_25 | solvent | warm | 1 | 0.323983 | 0.334669 | 0.000100946 | qualified |
| ladder_1_components_25 | solvent_replay | warm | 1 | 0.070876 | 0.08056 | 2.88658e-08 | qualified |
| ladder_25_components_1 | ceres | cold | 1 | 1.46181 | 1.58389 | 0.625059 | qualified |
| ladder_25_components_1 | dart_2d_ad | cold | 1 | 3.27684 | 3.89834 | 0.961667 | qualified |
| ladder_25_components_1 | dart_2d_analytic | cold | 1 | 2.85924 | 3.31975 | 0.961667 | qualified |
| ladder_25_components_1 | dart_3d_ad | cold | 1 | 4.56699 | 4.70425 | 0.961667 | qualified |
| ladder_25_components_1 | ezpz | cold | 1 | 0.08083 | 0.105968 | 0.00093584 | qualified |
| ladder_25_components_1 | ezpz_analysis | cold | 1 | 0.186488 | 0.19502 | 0.00093584 | qualified |
| ladder_25_components_1 | neoscad | cold | 1 | 6.60779 | 6.82917 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent | cold | 1 | 0.519083 | 0.554316 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent_replay | cold | 1 | 0.377682 | 0.404041 | 3.9968e-08 | qualified |
| ladder_25_components_1 | ceres | warm | 1 | 1.56434 | 1.63865 | 0.607861 | qualified |
| ladder_25_components_1 | dart_2d_ad | warm | 1 | 2.59326 | 3.27531 | 0.560806 | qualified |
| ladder_25_components_1 | dart_2d_analytic | warm | 1 | 2.70908 | 3.49389 | 0.560806 | qualified |
| ladder_25_components_1 | dart_3d_ad | warm | 1 | 3.69478 | 3.94059 | 0.560806 | qualified |
| ladder_25_components_1 | ezpz | warm | 1 | 0.077415 | 0.128431 | 5.36637e-05 | qualified |
| ladder_25_components_1 | ezpz_analysis | warm | 1 | 0.206227 | 0.231134 | 5.36637e-05 | qualified |
| ladder_25_components_1 | neoscad | warm | 1 | 5.89211 | 5.98445 | 1.9984e-08 | qualified |
| ladder_25_components_1 | solvent | warm | 1 | 0.528938 | 0.569979 | 3.33067e-08 | qualified |
| ladder_25_components_1 | solvent_replay | warm | 1 | 0.063214 | 0.128772 | 3.55271e-08 | qualified |
| ladder_500_components_1 | ceres | cold | 1 | 5.05801 | 5.3494 | 0.570579 | qualified |
| ladder_500_components_1 | dart_2d_ad | cold | 1 | — | — | 13826.8 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | dart_2d_analytic | cold | 1 | — | — | 13607.6 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | dart_3d_ad | cold | 1 | — | — | 13826.8 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | ezpz | cold | 1 | 2.07537 | 2.12318 | 0.0901006 | qualified |
| ladder_500_components_1 | ezpz_analysis | cold | 1 | 641.862 | 645.305 | 0.0901006 | qualified |
| ladder_500_components_1 | neoscad | cold | 1 | — | — | — | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | solvent | cold | 1 | 4.60788 | 4.80801 | 0.000793642 | qualified |
| ladder_500_components_1 | solvent_replay | cold | 1 | 40.8357 | 41.5645 | 1.27676e-06 | qualified |
| ladder_500_components_1 | ceres | warm | 1 | 4.52554 | 5.3294 | 0.627944 | qualified |
| ladder_500_components_1 | dart_2d_ad | warm | 1 | — | — | 13826.8 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | dart_2d_analytic | warm | 1 | — | — | 13607.6 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | dart_3d_ad | warm | 1 | — | — | 13826.8 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | ezpz | warm | 1 | 2.07279 | 2.12032 | 0.0197689 | qualified |
| ladder_500_components_1 | ezpz_analysis | warm | 1 | 611.439 | 616.181 | 0.0197689 | qualified |
| ladder_500_components_1 | neoscad | warm | 1 | — | — | — | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| ladder_500_components_1 | solvent | warm | 1 | 0.551211 | 0.577851 | 0.000134539 | qualified |
| ladder_500_components_1 | solvent_replay | warm | 1 | 2.48852 | 2.73749 | 5.61773e-07 | qualified |
| ladder_5_components_1 | ceres | cold | 1 | 0.032388 | 0.034672 | 0.16016 | qualified |
| ladder_5_components_1 | dart_2d_ad | cold | 1 | 0.252566 | 0.377813 | 0.938654 | qualified |
| ladder_5_components_1 | dart_2d_analytic | cold | 1 | 0.236272 | 0.279125 | 0.938654 | qualified |
| ladder_5_components_1 | dart_3d_ad | cold | 1 | 0.535408 | 0.739762 | 0.938654 | qualified |
| ladder_5_components_1 | ezpz | cold | 1 | 0.019038 | 0.020911 | 0.000468621 | qualified |
| ladder_5_components_1 | ezpz_analysis | cold | 1 | 0.02624 | 0.029834 | 0.000468621 | qualified |
| ladder_5_components_1 | neoscad | cold | 1 | 0.063385 | 0.064245 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent | cold | 1 | 0.023094 | 0.024257 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent_replay | cold | 1 | 0.058758 | 0.069393 | 1.77636e-08 | qualified |
| ladder_5_components_1 | ceres | warm | 1 | 0.023445 | 0.030645 | 0.80638 | qualified |
| ladder_5_components_1 | dart_2d_ad | warm | 1 | 0.272085 | 0.466966 | 0.477965 | qualified |
| ladder_5_components_1 | dart_2d_analytic | warm | 1 | 0.176213 | 0.236172 | 0.477965 | qualified |
| ladder_5_components_1 | dart_3d_ad | warm | 1 | 0.51679 | 0.783797 | 0.477965 | qualified |
| ladder_5_components_1 | ezpz | warm | 1 | 0.02025 | 0.022834 | 2.24976e-05 | qualified |
| ladder_5_components_1 | ezpz_analysis | warm | 1 | 0.027331 | 0.030375 | 2.24976e-05 | qualified |
| ladder_5_components_1 | neoscad | warm | 1 | 0.066048 | 0.082332 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent | warm | 1 | 0.015834 | 0.016164 | 2.22045e-09 | qualified |
| ladder_5_components_1 | solvent_replay | warm | 1 | 0.011167 | 0.013069 | 6.66134e-09 | qualified |
| ladder_5_components_1_offset_1e+06 | ceres | cold | 1 | 0.032158 | 0.034601 | 0.160392 | qualified |
| ladder_5_components_1_offset_1e+06 | dart_2d_ad | cold | 1 | 0.262992 | 0.366526 | 0.938308 | qualified |
| ladder_5_components_1_offset_1e+06 | dart_2d_analytic | cold | 1 | 0.258645 | 0.361609 | 0.938308 | qualified |
| ladder_5_components_1_offset_1e+06 | dart_3d_ad | cold | 1 | 0.532834 | 0.740844 | 0.938308 | qualified |
| ladder_5_components_1_offset_1e+06 | ezpz | cold | 1 | 0.019368 | 0.021623 | 0.00116415 | qualified |
| ladder_5_components_1_offset_1e+06 | ezpz_analysis | cold | 1 | 0.02635 | 0.029775 | 0.00116415 | qualified |
| ladder_5_components_1_offset_1e+06 | neoscad | cold | 1 | 0.063435 | 0.079568 | 0.000903382 | qualified |
| ladder_5_components_1_offset_1e+06 | solvent | cold | 1 | 0.022724 | 0.024437 | 0.00186265 | qualified |
| ladder_5_components_1_offset_1e+06 | solvent_replay | cold | 1 | 0.058527 | 0.068992 | 0.00186265 | qualified |
| ladder_5_components_1_offset_1e+06 | ceres | warm | 1 | 0.022263 | 0.048813 | 0.806758 | qualified |
| ladder_5_components_1_offset_1e+06 | dart_2d_ad | warm | 1 | 0.246407 | 0.458122 | 0.478206 | qualified |
| ladder_5_components_1_offset_1e+06 | dart_2d_analytic | warm | 1 | 0.16764 | 0.205936 | 0.478206 | qualified |
| ladder_5_components_1_offset_1e+06 | dart_3d_ad | warm | 1 | 0.428288 | 0.674725 | 0.478206 | qualified |
| ladder_5_components_1_offset_1e+06 | ezpz | warm | 1 | 0.019238 | 0.021242 | 0.00100731 | qualified |
| ladder_5_components_1_offset_1e+06 | ezpz_analysis | warm | 1 | 0.025839 | 0.029083 | 0.00100731 | qualified |
| ladder_5_components_1_offset_1e+06 | neoscad | warm | 1 | 0.056063 | 0.072778 | 0.00100731 | qualified |
| ladder_5_components_1_offset_1e+06 | solvent | warm | 1 | 0.014512 | 0.054121 | 0.00100731 | qualified |
| ladder_5_components_1_offset_1e+06 | solvent_replay | warm | 1 | 0.010906 | 0.012579 | 0.00106816 | qualified |
| ladder_5_components_1_redundant | ceres | cold | 1 | 0.025368 | 0.027371 | 0.960069 | qualified |
| ladder_5_components_1_redundant | dart_2d_ad | cold | 1 | 0.260037 | 0.354988 | 0.378921 | qualified |
| ladder_5_components_1_redundant | dart_2d_analytic | cold | 1 | 0.257844 | 0.575217 | 0.378921 | qualified |
| ladder_5_components_1_redundant | dart_3d_ad | cold | 1 | 0.59769 | 0.800303 | 0.378921 | qualified |
| ladder_5_components_1_redundant | ezpz | cold | 1 | 0.018347 | 0.020821 | 0.000468621 | qualified |
| ladder_5_components_1_redundant | ezpz_analysis | cold | 1 | 0.031647 | 0.049083 | 0.000468621 | qualified |
| ladder_5_components_1_redundant | neoscad | cold | 1 | 0.078567 | 0.089513 | 2.22045e-09 | qualified |
| ladder_5_components_1_redundant | solvent | cold | 1 | 0.023935 | 0.024927 | 2.22045e-09 | qualified |
| ladder_5_components_1_redundant | solvent_replay | cold | 1 | 0.064877 | 0.075493 | 1.77636e-08 | qualified |
| ladder_5_components_1_redundant | ceres | warm | 1 | 0.030104 | 0.031497 | 0.0115332 | qualified |
| ladder_5_components_1_redundant | dart_2d_ad | warm | 1 | 0.271254 | 0.384213 | 0.043942 | qualified |
| ladder_5_components_1_redundant | dart_2d_analytic | warm | 1 | 0.219096 | 0.231935 | 0.043942 | qualified |
| ladder_5_components_1_redundant | dart_3d_ad | warm | 1 | 0.581686 | 0.711379 | 0.043942 | qualified |
| ladder_5_components_1_redundant | ezpz | warm | 1 | 0.02031 | 0.10118 | 2.24132e-05 | qualified |
| ladder_5_components_1_redundant | ezpz_analysis | warm | 1 | 0.031216 | 0.033831 | 2.24132e-05 | qualified |
| ladder_5_components_1_redundant | neoscad | warm | 1 | 0.065458 | 0.071607 | 2.22045e-09 | qualified |
| ladder_5_components_1_redundant | solvent | warm | 1 | 0.015943 | 0.016495 | 2.22045e-09 | qualified |
| ladder_5_components_1_redundant | solvent_replay | warm | 1 | 0.011457 | 0.012959 | 1.11022e-08 | qualified |
| ladder_5_components_1_scale_1e+06 | ceres | cold | 1 | 0.032578 | 0.056494 | 0.16016 | qualified |
| ladder_5_components_1_scale_1e+06 | dart_2d_ad | cold | 1 | 0.311734 | 0.413566 | 0.938654 | qualified |
| ladder_5_components_1_scale_1e+06 | dart_2d_analytic | cold | 1 | 0.269812 | 0.319736 | 0.938654 | qualified |
| ladder_5_components_1_scale_1e+06 | dart_3d_ad | cold | 1 | 0.535157 | 0.799832 | 0.938654 | qualified |
| ladder_5_components_1_scale_1e+06 | ezpz | cold | 1 | 0.018908 | 0.021172 | 0.000468623 | qualified |
| ladder_5_components_1_scale_1e+06 | ezpz_analysis | cold | 1 | 0.02701 | 0.052138 | 0.000468623 | qualified |
| ladder_5_components_1_scale_1e+06 | neoscad | cold | 1 | 0.082543 | 0.097205 | 1.16415e-09 | qualified |
| ladder_5_components_1_scale_1e+06 | solvent | cold | 1 | 0.023074 | 0.056895 | 3.49246e-09 | qualified |
| ladder_5_components_1_scale_1e+06 | solvent_replay | cold | 1 | 0.059379 | 0.075131 | 1.74623e-08 | qualified |
| ladder_5_components_1_scale_1e+06 | ceres | warm | 1 | 0.022393 | 0.029645 | 0.80638 | qualified |
| ladder_5_components_1_scale_1e+06 | dart_2d_ad | warm | 1 | 0.231635 | 0.34936 | 0.477965 | qualified |
| ladder_5_components_1_scale_1e+06 | dart_2d_analytic | warm | 1 | 0.167529 | 0.217334 | 0.477965 | qualified |
| ladder_5_components_1_scale_1e+06 | dart_3d_ad | warm | 1 | 0.433095 | 0.662497 | 0.477965 | qualified |
| ladder_5_components_1_scale_1e+06 | ezpz | warm | 1 | 0.018949 | 0.021182 | 2.24984e-05 | qualified |
| ladder_5_components_1_scale_1e+06 | ezpz_analysis | warm | 1 | 0.026119 | 0.029474 | 2.24984e-05 | qualified |
| ladder_5_components_1_scale_1e+06 | neoscad | warm | 1 | 0.077695 | 0.295921 | 2.32831e-09 | qualified |
| ladder_5_components_1_scale_1e+06 | solvent | warm | 1 | 0.015142 | 0.022253 | 3.49246e-09 | qualified |
| ladder_5_components_1_scale_1e+06 | solvent_replay | warm | 1 | 0.010937 | 0.011948 | 1.16415e-08 | qualified |
| ladder_5_components_1_scale_1e-06 | ceres | cold | 1 | 0.034481 | 0.089864 | 0.16016 | qualified |
| ladder_5_components_1_scale_1e-06 | dart_2d_ad | cold | 1 | 0.262461 | 0.458583 | 0.938654 | qualified |
| ladder_5_components_1_scale_1e-06 | dart_2d_analytic | cold | 1 | 0.226658 | 0.30893 | 0.938654 | qualified |
| ladder_5_components_1_scale_1e-06 | dart_3d_ad | cold | 1 | 0.567386 | 0.708055 | 0.938654 | qualified |
| ladder_5_components_1_scale_1e-06 | ezpz | cold | 1 | — | — | 48044.3 | not_all_measured_samples_accepted |
| ladder_5_components_1_scale_1e-06 | ezpz_analysis | cold | 1 | — | — | 48044.3 | not_all_measured_samples_accepted |
| ladder_5_components_1_scale_1e-06 | neoscad | cold | 1 | 0.077756 | 0.091927 | 4.23516e-09 | qualified |
| ladder_5_components_1_scale_1e-06 | solvent | cold | 1 | — | — | 48044.3 | not_all_measured_samples_accepted |
| ladder_5_components_1_scale_1e-06 | solvent_replay | cold | 1 | 0.059669 | 0.070745 | 1.27055e-08 | qualified |
| ladder_5_components_1_scale_1e-06 | ceres | warm | 1 | 0.022513 | 0.029965 | 0.80638 | qualified |
| ladder_5_components_1_scale_1e-06 | dart_2d_ad | warm | 1 | 0.232907 | 0.330172 | 0.477965 | qualified |
| ladder_5_components_1_scale_1e-06 | dart_2d_analytic | warm | 1 | 0.185316 | 0.204184 | 0.477965 | qualified |
| ladder_5_components_1_scale_1e-06 | dart_3d_ad | warm | 1 | 0.474046 | 0.985048 | 0.477965 | qualified |
| ladder_5_components_1_scale_1e-06 | ezpz | warm | 1 | — | — | 48044.3 | not_all_measured_samples_accepted |
| ladder_5_components_1_scale_1e-06 | ezpz_analysis | warm | 1 | — | — | 48044.3 | not_all_measured_samples_accepted |
| ladder_5_components_1_scale_1e-06 | neoscad | warm | 1 | 0.064096 | 0.08026 | 2.11758e-09 | qualified |
| ladder_5_components_1_scale_1e-06 | solvent | warm | 1 | — | — | 48044.3 | not_all_measured_samples_accepted |
| ladder_5_components_1_scale_1e-06 | solvent_replay | warm | 1 | 0.011377 | 0.01325 | 6.35275e-09 | qualified |
| laman_free_100 | ceres | cold | 1 | 2.17093 | 2.31479 | 0.299708 | qualified |
| laman_free_100 | dart_2d_ad | cold | 1 | 4.04032 | 4.59377 | 0.984891 | qualified |
| laman_free_100 | dart_2d_analytic | cold | 1 | 4.17545 | 4.18497 | 0.984891 | qualified |
| laman_free_100 | dart_3d_ad | cold | 1 | 7.48562 | 16.1873 | 0.984891 | qualified |
| laman_free_100 | ezpz | cold | 1 | 0.139318 | 0.14088 | 0.108899 | qualified |
| laman_free_100 | ezpz_analysis | cold | 1 | 0.341229 | 0.38305 | 0.108899 | qualified |
| laman_free_100 | neoscad | cold | 1 | 6.22975 | 6.52862 | 8.88178e-09 | qualified |
| laman_free_100 | solvent | cold | 1 | 0.568837 | 0.622508 | 8.88178e-09 | qualified |
| laman_free_100 | solvent_replay | cold | 1 | 11.7203 | 13.5379 | 8.88178e-09 | qualified |
| laman_free_100 | ceres | warm | 1 | 2.04564 | 2.05437 | 0.188045 | qualified |
| laman_free_100 | dart_2d_ad | warm | 1 | 4.40874 | 4.5154 | 0.908787 | qualified |
| laman_free_100 | dart_2d_analytic | warm | 1 | 4.15418 | 5.37055 | 0.908787 | qualified |
| laman_free_100 | dart_3d_ad | warm | 1 | 6.53173 | 6.95328 | 0.908787 | qualified |
| laman_free_100 | ezpz | warm | 1 | 0.137375 | 0.146839 | 0.0418338 | qualified |
| laman_free_100 | ezpz_analysis | warm | 1 | 0.361168 | 0.399274 | 0.0418338 | qualified |
| laman_free_100 | neoscad | warm | 1 | 5.45056 | 5.75069 | 8.88178e-09 | qualified |
| laman_free_100 | solvent | warm | 1 | 0.502538 | 0.573154 | 8.88178e-09 | qualified |
| laman_free_100 | solvent_replay | warm | 1 | 0.722917 | 0.807934 | 8.88178e-09 | qualified |
| laman_free_2000 | ceres | cold | 1 | 135.975 | 138.432 | 0.600458 | qualified |
| laman_free_2000 | dart_2d_ad | cold | 1 | — | — | 8.18002 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | dart_2d_analytic | cold | 1 | — | — | 8.18002 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | dart_3d_ad | cold | 1 | — | — | 8.18002 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | ezpz | cold | 1 | 14.8268 | 17.8827 | 0.203194 | qualified |
| laman_free_2000 | ezpz_analysis | cold | 1 | 638.531 | 763.808 | 0.203194 | qualified |
| laman_free_2000 | neoscad | cold | 1 | — | — | — | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | solvent | cold | 1 | 1000.51 | 1030.6 | 4.24855e-06 | qualified |
| laman_free_2000 | solvent_replay | cold | 1 | 942.399 | 1021 | 3.55188e-06 | qualified |
| laman_free_2000 | ceres | warm | 1 | 135.992 | 137.166 | 0.559493 | qualified |
| laman_free_2000 | dart_2d_ad | warm | 1 | — | — | 8.18002 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | dart_2d_analytic | warm | 1 | — | — | 8.18002 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | dart_3d_ad | warm | 1 | — | — | 8.18002 | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | ezpz | warm | 1 | 7.25126 | 7.33804 | 0.676718 | qualified |
| laman_free_2000 | ezpz_analysis | warm | 1 | 564.576 | 609.869 | 0.676718 | qualified |
| laman_free_2000 | neoscad | warm | 1 | — | — | — | incomplete_or_invalid_jobs, not_all_measured_samples_accepted |
| laman_free_2000 | solvent | warm | 1 | 615.212 | 632.235 | 4.25715e-06 | qualified |
| laman_free_2000 | solvent_replay | warm | 1 | 980.927 | 1111.56 | 5.06289e-06 | qualified |
| laman_free_500 | ceres | cold | 1 | 2.71902 | 2.88826 | 0.886928 | qualified |
| laman_free_500 | dart_2d_ad | cold | 1 | 70.5349 | 75.2706 | 0.401286 | qualified |
| laman_free_500 | dart_2d_analytic | cold | 1 | 73.3569 | 85.0032 | 0.401286 | qualified |
| laman_free_500 | dart_3d_ad | cold | 1 | 115.769 | 160.349 | 0.401286 | qualified |
| laman_free_500 | ezpz | cold | 1 | 1.1577 | 1.26313 | 0.029875 | qualified |
| laman_free_500 | ezpz_analysis | cold | 1 | 7.73943 | 8.71158 | 0.029875 | qualified |
| laman_free_500 | neoscad | cold | 1 | 676.539 | 702.972 | 1.77636e-08 | qualified |
| laman_free_500 | solvent | cold | 1 | 5.05751 | 5.20589 | 9.97258e-07 | qualified |
| laman_free_500 | solvent_replay | cold | 1 | 10.4792 | 10.5899 | 1.16573e-08 | qualified |
| laman_free_500 | ceres | warm | 1 | 2.50536 | 2.51525 | 0.813729 | qualified |
| laman_free_500 | dart_2d_ad | warm | 1 | 55.7178 | 55.998 | 0.729569 | qualified |
| laman_free_500 | dart_2d_analytic | warm | 1 | 54.9932 | 55.1752 | 0.729569 | qualified |
| laman_free_500 | dart_3d_ad | warm | 1 | 85.031 | 85.1833 | 0.729569 | qualified |
| laman_free_500 | ezpz | warm | 1 | 0.794443 | 0.842575 | 0.351895 | qualified |
| laman_free_500 | ezpz_analysis | warm | 1 | 7.34788 | 7.57027 | 0.351895 | qualified |
| laman_free_500 | neoscad | warm | 1 | 650.643 | 678.154 | 8.88178e-09 | qualified |
| laman_free_500 | solvent | warm | 1 | 3.99504 | 4.03436 | 8.88178e-09 | qualified |
| laman_free_500 | solvent_replay | warm | 1 | 7.22258 | 7.36929 | 3.38618e-08 | qualified |

## Partial or rejected results: descriptive only

These statistics retain completed observations from excluded groups. They must not be ranked as successful-solve latency. An accepted subset can be easier than the missing or rejected operations. Process timeouts are whole-job limits.

| Fixture | Engine | Mode | Observed / expected | Accepted subset processes | Available accepted p50 ms | Available accepted p95 ms | All-observation p50 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| contradictory_distance | ceres | cold | 5/5 | 0 | — | — | 0.010366 |
| contradictory_distance | dart_2d_ad | cold | 5/5 | 0 | — | — | 0.10702 |
| contradictory_distance | dart_2d_analytic | cold | 5/5 | 0 | — | — | 0.08025 |
| contradictory_distance | dart_3d_ad | cold | 5/5 | 0 | — | — | 0.217644 |
| contradictory_distance | ezpz | cold | 5/5 | 0 | — | — | 0.028672 |
| contradictory_distance | ezpz_analysis | cold | 5/5 | 0 | — | — | 0.030135 |
| contradictory_distance | neoscad | cold | 5/5 | 0 | — | — | 0.163975 |
| contradictory_distance | solvent | cold | 5/5 | 0 | — | — | 0.009404 |
| contradictory_distance | solvent_replay | cold | 5/5 | 0 | — | — | 0.02682 |
| contradictory_distance | ceres | warm | 5/5 | 0 | — | — | 0.009154 |
| contradictory_distance | dart_2d_ad | warm | 5/5 | 0 | — | — | 0.096534 |
| contradictory_distance | dart_2d_analytic | warm | 5/5 | 0 | — | — | 0.065107 |
| contradictory_distance | dart_3d_ad | warm | 5/5 | 0 | — | — | 0.176934 |
| contradictory_distance | ezpz | warm | 5/5 | 0 | — | — | 0.028923 |
| contradictory_distance | ezpz_analysis | warm | 5/5 | 0 | — | — | 0.030185 |
| contradictory_distance | neoscad | warm | 5/5 | 0 | — | — | 0.164154 |
| contradictory_distance | solvent | warm | 5/5 | 0 | — | — | 0.005598 |
| contradictory_distance | solvent_replay | warm | 5/5 | 0 | — | — | 0.011087 |
| ladder_500_components_1 | dart_2d_ad | cold | 2/3 | 0 | — | — | 4177.37 |
| ladder_500_components_1 | dart_2d_analytic | cold | 2/3 | 0 | — | — | 3921.36 |
| ladder_500_components_1 | dart_3d_ad | cold | 1/3 | 0 | — | — | 6184.11 |
| ladder_500_components_1 | neoscad | cold | 0/3 | 0 | — | — | — |
| ladder_500_components_1 | dart_2d_ad | warm | 2/3 | 0 | — | — | 3936.68 |
| ladder_500_components_1 | dart_2d_analytic | warm | 2/3 | 0 | — | — | 3951.29 |
| ladder_500_components_1 | dart_3d_ad | warm | 1/3 | 0 | — | — | 6155.75 |
| ladder_500_components_1 | neoscad | warm | 0/3 | 0 | — | — | — |
| ladder_5_components_1_scale_1e-06 | ezpz | cold | 5/5 | 0 | — | — | 0.013761 |
| ladder_5_components_1_scale_1e-06 | ezpz_analysis | cold | 5/5 | 0 | — | — | 0.050746 |
| ladder_5_components_1_scale_1e-06 | solvent | cold | 5/5 | 0 | — | — | 0.010175 |
| ladder_5_components_1_scale_1e-06 | ezpz | warm | 5/5 | 0 | — | — | 0.01353 |
| ladder_5_components_1_scale_1e-06 | ezpz_analysis | warm | 5/5 | 0 | — | — | 0.027881 |
| ladder_5_components_1_scale_1e-06 | solvent | warm | 5/5 | 0 | — | — | 0.002964 |
| laman_free_2000 | dart_2d_ad | cold | 2/3 | 0 | — | — | 4174.62 |
| laman_free_2000 | dart_2d_analytic | cold | 2/3 | 0 | — | — | 4272.01 |
| laman_free_2000 | dart_3d_ad | cold | 1/3 | 0 | — | — | 6576.18 |
| laman_free_2000 | neoscad | cold | 0/3 | 0 | — | — | — |
| laman_free_2000 | dart_2d_ad | warm | 2/3 | 0 | — | — | 4272.3 |
| laman_free_2000 | dart_2d_analytic | warm | 2/3 | 0 | — | — | 4170.67 |
| laman_free_2000 | dart_3d_ad | warm | 1/3 | 0 | — | — | 6267.17 |
| laman_free_2000 | neoscad | warm | 0/3 | 0 | — | — | — |

## Contradictory fixtures

Valid rejection means a checked emitted physical rejection without an adapter exception. It is not a mathematical infeasibility certificate.

| Fixture | Engine | Mode | Valid rejected / expected | Complete valid-rejection jobs | All jobs validly rejected |
| --- | --- | --- | --- | --- | --- |
| contradictory_distance | ceres | cold | 5/5 | 1/1 | True |
| contradictory_distance | dart_2d_ad | cold | 5/5 | 1/1 | True |
| contradictory_distance | dart_2d_analytic | cold | 5/5 | 1/1 | True |
| contradictory_distance | dart_3d_ad | cold | 5/5 | 1/1 | True |
| contradictory_distance | ezpz | cold | 5/5 | 1/1 | True |
| contradictory_distance | ezpz_analysis | cold | 5/5 | 1/1 | True |
| contradictory_distance | neoscad | cold | 5/5 | 1/1 | True |
| contradictory_distance | solvent | cold | 5/5 | 1/1 | True |
| contradictory_distance | solvent_replay | cold | 5/5 | 1/1 | True |
| contradictory_distance | ceres | warm | 5/5 | 1/1 | True |
| contradictory_distance | dart_2d_ad | warm | 5/5 | 1/1 | True |
| contradictory_distance | dart_2d_analytic | warm | 5/5 | 1/1 | True |
| contradictory_distance | dart_3d_ad | warm | 5/5 | 1/1 | True |
| contradictory_distance | ezpz | warm | 5/5 | 1/1 | True |
| contradictory_distance | ezpz_analysis | warm | 5/5 | 1/1 | True |
| contradictory_distance | neoscad | warm | 5/5 | 1/1 | True |
| contradictory_distance | solvent | warm | 5/5 | 1/1 | True |
| contradictory_distance | solvent_replay | warm | 5/5 | 1/1 | True |

## Reading limits

- Native adapter measurements exclude JSON, the external checker, browser/FFI integration and the full CAD application.
- Scalar coordinates are unfixed parameters before geometric constraints, not remaining DOF.
- Different sample or warmup counts per process are retained in JSON; select a consistent confirmation cohort when making a publication claim.
- Error ratios use each request tolerance. Missing/nonfinite errors are counted separately in JSON and are not silently converted into zero.
- Full manifests, binary/source hashes, archive hashes when read, per-job checksums, exclusions and optional engine metrics are in analysis.json.

# Recovered partial CG norm-fusion evidence

**Decision: revert the provisional candidate because the declared same-session cohort is incomplete.**

Available-evidence replay passed: **True**. The complete eight-block protocol did **not** pass; retention is not allowed. The original auditor remains unchanged and rejects the missing measurement inventory.

Five of eight blocks survive: candidate rounds 1–3 and A/A rounds 1–2. Missing: A/A round 3, candidate round 4, A/A round 4. No new measurement was collected and no replacement session was pooled.

## Recovered populations

| Population | Processes | Measured | Warmups | Raw records | Exact non-timing pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| norm | 96 | 2016 | 768 | 2784 | 1392 |
| aa | 64 | 1344 | 512 | 1856 | 928 |

Qualification is separate: 72 processes, 216 raw operations, 192 accepted, 24 expected contradictory rejections, 108 exact non-timing pairs.

## Descriptive observations only

All complete-operation p50 and p95 values below are recomputed from raw measurements. Each process pair has equal weight. Candidate strata have unequal pair counts (two versus one); A/A strata have one pair each. Four-round performance, stability and tail gates are **not evaluated** on these partial data. A/A is never subtracted and cannot excuse adverse results. These short-cohort percentiles are not population tail bounds.

### norm: rounds 1, 2, 3

| Fixture | Engine | Mode | Before / after median process p50, ms | Median paired p50 change | Ratio of median process p50 change | Round p50 changes | Round p95 changes | Before-first / after-first p50 changes (pair counts) |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |
| axis_rectangle | dart_2d_analytic | cold | 0.297840 / 0.082762 | -72.21% | -72.21% | -74.76%, +15.12%, -72.21% | -57.78%, +213.93%, -72.17% | -73.49% (2) / +15.12% (1) |
| axis_rectangle | dart_2d_analytic | warm | 0.043804 / 0.043665 | -1.76% | -0.32% | +0.62%, -2.57%, -1.76% | -30.52%, -26.74%, -63.25% | -2.57% (1) / -0.57% (2) |
| axis_rectangle | dart_3d_ad | cold | 0.123172 / 0.116361 | -6.52% | -5.53% | -13.14%, -5.05%, -6.52% | +8.22%, -2.81%, -11.29% | -5.05% (1) / -9.83% (2) |
| axis_rectangle | dart_3d_ad | warm | 0.089301 / 0.104795 | +17.35% | +17.35% | +60.26%, -12.12%, +17.35% | -23.19%, -24.30%, +49.51% | +38.80% (2) / -12.12% (1) |
| ladder_25_components_1 | dart_2d_analytic | cold | 5.219233 / 4.437920 | -14.97% | -14.97% | -14.97%, -16.07%, -14.42% | -19.90%, -13.88%, -15.15% | -16.07% (1) / -14.70% (2) |
| ladder_25_components_1 | dart_2d_analytic | warm | 4.498580 / 3.896791 | -16.11% | -13.38% | -12.73%, -17.90%, -16.11% | -14.88%, -17.31%, -32.42% | -14.42% (2) / -17.90% (1) |
| ladder_25_components_1 | dart_3d_ad | cold | 9.082506 / 7.766621 | -15.99% | -14.49% | -12.67%, -17.08%, -15.99% | -9.13%, -20.17%, -10.44% | -14.33% (2) / -17.08% (1) |
| ladder_25_components_1 | dart_3d_ad | warm | 7.694916 / 6.472492 | -15.89% | -15.89% | -11.20%, -15.89%, -17.51% | +74.41%, -59.73%, -18.11% | -15.89% (1) / -14.35% (2) |
| ladder_500_components_1 | dart_2d_analytic | cold | 62.205840 / 62.526910 | -2.07% | +0.52% | -2.83%, -2.07%, +0.60% | +0.16%, -15.72%, +16.57% | -1.11% (2) / -2.07% (1) |
| ladder_500_components_1 | dart_2d_analytic | warm | 45.020976 / 44.791289 | -0.51% | -0.51% | -0.51%, -3.91%, +2.68% | +4.38%, -30.21%, +1.50% | -3.91% (1) / +1.08% (2) |
| ladder_500_components_1 | dart_3d_ad | cold | 147.879932 / 141.724205 | -6.74% | -4.16% | -8.61%, -6.74%, -2.08% | -17.13%, -5.26%, +1.04% | -6.74% (1) / -5.35% (2) |
| ladder_500_components_1 | dart_3d_ad | warm | 123.830459 / 121.306405 | -2.53% | -2.04% | -2.53%, -8.00%, +0.53% | -4.41%, -21.21%, +9.29% | -1.00% (2) / -8.00% (1) |
| laman_free_500 | dart_2d_analytic | cold | 131.591027 / 100.506623 | -23.62% | -23.62% | -29.33%, -23.62%, -19.95% | -25.45%, -19.61%, -25.29% | -23.62% (1) / -24.64% (2) |
| laman_free_500 | dart_2d_analytic | warm | 110.041469 / 89.222710 | -19.25% | -18.92% | -19.25%, -16.87%, -20.16% | -20.77%, -25.90%, -28.84% | -19.71% (2) / -16.87% (1) |
| laman_free_500 | dart_3d_ad | cold | 201.956329 / 165.566965 | -17.91% | -18.02% | -17.91%, -19.47%, -15.03% | -18.12%, -20.58%, -24.96% | -16.47% (2) / -19.47% (1) |
| laman_free_500 | dart_3d_ad | warm | 172.102458 / 135.445804 | -21.07% | -21.30% | -21.07%, -19.06%, -21.30% | -34.02%, -16.60%, -17.39% | -19.06% (1) / -21.18% (2) |

### aa: rounds 1, 2

| Fixture | Engine | Mode | Before / after median process p50, ms | Median paired p50 change | Ratio of median process p50 change | Round p50 changes | Round p95 changes | Before-first / after-first p50 changes (pair counts) |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |
| axis_rectangle | dart_2d_analytic | cold | 0.199033 / 0.075421 | -37.47% | -62.11% | -76.85%, +1.91% | -79.71%, +19.19% | -76.85% (1) / +1.91% (1) |
| axis_rectangle | dart_2d_analytic | warm | 0.043450 / 0.044005 | +1.28% | +1.28% | +1.92%, +0.64% | +11.41%, -14.07% | +0.64% (1) / +1.92% (1) |
| axis_rectangle | dart_3d_ad | cold | 0.145996 / 0.128219 | -10.92% | -12.18% | -3.02%, -18.82% | -13.08%, -18.57% | -18.82% (1) / -3.02% (1) |
| axis_rectangle | dart_3d_ad | warm | 0.119851 / 0.112296 | -6.94% | -6.30% | -13.20%, -0.67% | +14.45%, -5.78% | -13.20% (1) / -0.67% (1) |
| ladder_25_components_1 | dart_2d_analytic | cold | 5.506308 / 5.576504 | +1.31% | +1.27% | +4.76%, -2.14% | -2.44%, -7.01% | -2.14% (1) / +4.76% (1) |
| ladder_25_components_1 | dart_2d_analytic | warm | 4.411188 / 4.444366 | +0.71% | +0.75% | -1.44%, +2.85% | -2.47%, +19.77% | -1.44% (1) / +2.85% (1) |
| ladder_25_components_1 | dart_3d_ad | cold | 9.180939 / 8.959746 | -2.32% | -2.41% | -0.11%, -4.54% | -1.63%, -9.83% | -0.11% (1) / -4.54% (1) |
| ladder_25_components_1 | dart_3d_ad | warm | 7.631461 / 7.525149 | -1.33% | -1.39% | +0.00%, -2.67% | -1.42%, -17.14% | -2.67% (1) / +0.00% (1) |
| ladder_500_components_1 | dart_2d_analytic | cold | 63.935648 / 63.055604 | -1.26% | -1.38% | -4.40%, +1.89% | +17.22%, +2.10% | -4.40% (1) / +1.89% (1) |
| ladder_500_components_1 | dart_2d_analytic | warm | 45.670571 / 47.195934 | +3.34% | +3.34% | +4.47%, +2.21% | +7.98%, -13.56% | +2.21% (1) / +4.47% (1) |
| ladder_500_components_1 | dart_3d_ad | cold | 146.115527 / 148.441890 | +1.71% | +1.59% | -1.35%, +4.76% | +6.32%, +3.98% | +4.76% (1) / -1.35% (1) |
| ladder_500_components_1 | dart_3d_ad | warm | 126.091587 / 122.175457 | -3.11% | -3.11% | -2.37%, -3.86% | -6.24%, +0.36% | -2.37% (1) / -3.86% (1) |
| laman_free_500 | dart_2d_analytic | cold | 133.169326 / 131.133042 | -1.52% | -1.53% | -1.00%, -2.04% | +16.43%, -5.15% | -2.04% (1) / -1.00% (1) |
| laman_free_500 | dart_2d_analytic | warm | 109.668438 / 109.048659 | -0.56% | -0.57% | -0.39%, -0.73% | +3.62%, +26.91% | -0.39% (1) / -0.73% (1) |
| laman_free_500 | dart_3d_ad | cold | 199.670468 / 202.017233 | +1.18% | +1.18% | +0.32%, +2.05% | +4.47%, -6.07% | +0.32% (1) / +2.05% (1) |
| laman_free_500 | dart_3d_ad | warm | 169.911962 / 172.364932 | +1.43% | +1.44% | +0.44%, +2.43% | +4.76%, +3.49% | +2.43% (1) / +0.44% (1) |


## Machine-readable evidence

`partial-audit.json.gz` contains the complete JSON report. It uses gzip with zero modification time; decompression recovers the exact report bytes. `executed-evidence-replay.py.gz` preserves the wrapper executed for this audit and matches the report’s `script_sha256`. The checksum manifest also binds the current reusable wrapper separately. Its file entries use paths relative to this audit directory.

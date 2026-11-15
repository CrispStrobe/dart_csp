# Independent audit of the resumed three blocks

Audit passed: **true**. Session: `b51b355c4f64`.

The resumed session completes `identity-round4`, `combined-round4`, and `aa-round4`. The original session `d1244c09828b` contains the other 13 blocks. The tables keep those timing observations separate. Completion and correctness counts may be added; latency distributions and process-pair summaries are not pooled across sessions.

## Verified population

| Check | Original 13 blocks | Resumed 3 blocks | Complete declared population |
| --- | ---: | ---: | ---: |
| Processes | 600 | 136 | 736 |
| Measured operations | 12,600 | 2,856 | 15,456 |
| Warmup operations | 4,800 | 1,088 | 5,888 |
| Independent accepted raw geometry records | 17,400 | 3,944 | 21,344 |
| Recomputed p50/p95 values | 1,200 | 272 | 1,472 |
| Paired non-timing comparisons | 8,700 | 1,972 | 10,672 |

All resumed pairs have identical coordinates, work counters and every other non-timing raw field. All 710 archived files restore byte-for-byte and match the local raw evidence. Source commits, frozen binary bytes, harness inputs, fixed fixture/engine/lifecycle populations, counts, process order and non-overlap all pass.

The protocol tool independently passes three disjoint selections: original CG rounds 1–4, original identity/combined/A-A rounds 1–3, and resumed identity/combined/A-A round 4. Each report explicitly has `full_protocol: false`. **A complete sixteen-block single-session experiment is not claimed.** The 16 declared blocks are complete across two sessions.

Recorded environment fingerprints match: **true**. Matching recorded settings do not establish an identical runtime session.

## Interpretation and recommendation

The additional block does not reverse the independent recommendation: retain fused CG for its demonstrated large iterative-workload benefit, with adverse cases documented; revert default-manifold contraction. The latter remains mixed and has repeated adverse workload observations. It still worsens 2D Laman 100 warm (+4.16% p50, +17.23% p95), following three adverse original-session rounds. The resumed block also worsens 3D ladder 500 warm (+11.18% p50) and 3D Laman 500 cold (+4.35% p50), while improving several other workloads.

The resumed A/A comparison is also variable: 2D axis cold is +305.24% p50, 2D Laman 100 warm +31.24%, and 2D ladder 500 warm −17.36%. These are same-executable observations, not corrections to subtract from candidate timings. They do not prove that any candidate regression is noise. There is no Laman 500 A/A sentinel.

The greater-than-5% repeated-regression flag in the original analyzer is descriptive, not a significance test or predeclared retain/revert threshold. No additional search or favorable sample selection is warranted.

## Per-case observations

The original column lists the three previously saved within-process-pair ratios separately. The resumed columns are one new pair per case, with no across-session aggregate. Changes are after/before minus one; negative values are faster.

### identity

| Fixture | Engine | Mode | Original three p50 effects | Resumed before / after p50, ms | Resumed p50 change | Resumed p95 change | First process |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| axis_rectangle | dart_2d_analytic | cold | +3.23%, +19.93%, -71.69% | 0.082882 / 0.131303 | +58.42% | -5.00% | after |
| axis_rectangle | dart_2d_analytic | warm | -41.76%, +0.86%, -25.75% | 0.049793 / 0.053509 | +7.46% | -38.58% | before |
| axis_rectangle | dart_3d_ad | cold | +52.15%, -34.13%, -8.70% | 1.358845 / 0.306422 | -77.45% | -86.00% | before |
| axis_rectangle | dart_3d_ad | warm | +35.06%, -39.12%, -26.03% | 0.144884 / 0.132095 | -8.83% | -34.77% | after |
| ladder_25_components_1 | dart_2d_analytic | cold | +7.03%, +1.16%, -4.92% | 6.031614 / 5.560508 | -7.81% | -49.04% | after |
| ladder_25_components_1 | dart_2d_analytic | warm | -13.05%, -0.21%, -1.35% | 4.374808 / 4.927544 | +12.63% | +40.22% | before |
| ladder_25_components_1 | dart_3d_ad | cold | +3.17%, +9.52%, -9.41% | 9.880636 / 10.414233 | +5.40% | +196.74% | before |
| ladder_25_components_1 | dart_3d_ad | warm | -9.36%, -12.51%, +2.16% | 8.001301 / 7.818090 | -2.29% | -7.44% | after |
| ladder_3_components_1 | dart_2d_analytic | cold | -20.83%, -11.47%, +30.05% | 0.156661 / 0.159475 | +1.80% | +11.10% | before |
| ladder_3_components_1 | dart_2d_analytic | warm | -2.53%, +137.37%, -0.99% | 0.134819 / 0.145245 | +7.73% | +35.24% | after |
| ladder_3_components_1 | dart_3d_ad | cold | +5.77%, -5.65%, +7.60% | 0.421352 / 0.424557 | +0.76% | -50.99% | after |
| ladder_3_components_1 | dart_3d_ad | warm | +2.88%, -16.89%, -19.18% | 0.258001 / 0.241407 | -6.43% | +11.68% | before |
| ladder_500_components_1 | dart_2d_analytic | cold | -6.05%, +7.22%, +23.45% | 68.259082 / 68.663803 | +0.59% | +8.21% | before |
| ladder_500_components_1 | dart_2d_analytic | warm | +0.07%, -5.29%, -2.87% | 48.182011 / 51.439263 | +6.76% | +20.76% | after |
| ladder_500_components_1 | dart_3d_ad | cold | +2.36%, -4.16%, +26.67% | 175.874742 / 157.837139 | -10.26% | -17.94% | after |
| ladder_500_components_1 | dart_3d_ad | warm | -5.75%, -8.68%, -0.83% | 130.085969 / 144.624699 | +11.18% | +4.15% | before |
| laman_free_100 | dart_2d_analytic | cold | -4.28%, -1.08%, +31.87% | 9.313316 / 7.259107 | -22.06% | +8.01% | after |
| laman_free_100 | dart_2d_analytic | warm | +32.33%, +14.26%, +10.59% | 6.841325 / 7.125755 | +4.16% | +17.23% | before |
| laman_free_100 | dart_3d_ad | cold | +1.84%, -2.15%, +27.82% | 13.563664 / 11.903864 | -12.24% | -30.94% | before |
| laman_free_100 | dart_3d_ad | warm | -5.71%, +4.28%, -18.98% | 12.249384 / 11.641447 | -4.96% | -6.97% | after |
| laman_free_500 | dart_2d_analytic | cold | -9.00%, +1.45%, -0.35% | 154.024430 / 142.432900 | -7.53% | -2.83% | before |
| laman_free_500 | dart_2d_analytic | warm | +15.63%, -0.05%, -22.45% | 142.279742 / 117.284864 | -17.57% | -17.26% | after |
| laman_free_500 | dart_3d_ad | cold | -5.89%, -3.21%, +15.96% | 224.849902 / 234.634229 | +4.35% | +11.20% | after |
| laman_free_500 | dart_3d_ad | warm | +9.29%, -1.50%, +0.36% | 226.621470 / 208.575807 | -7.96% | -12.68% | before |

### combined

| Fixture | Engine | Mode | Original three p50 effects | Resumed before / after p50, ms | Resumed p50 change | Resumed p95 change | First process |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| axis_rectangle | dart_2d_analytic | cold | -11.99%, +64.65%, -78.26% | 0.079447 / 0.402334 | +406.42% | +282.43% | after |
| axis_rectangle | dart_2d_analytic | warm | -23.87%, -3.32%, -1.77% | 0.050895 / 0.044496 | -12.57% | -82.11% | before |
| axis_rectangle | dart_3d_ad | cold | -33.67%, +11.38%, +17.40% | 0.215409 / 0.127748 | -40.70% | -23.46% | before |
| axis_rectangle | dart_3d_ad | warm | +38.95%, +28.01%, +39.29% | 0.121449 / 0.130733 | +7.64% | -42.69% | after |
| ladder_25_components_1 | dart_2d_analytic | cold | +3.14%, -4.18%, +0.04% | 5.614889 / 5.521301 | -1.67% | -0.82% | after |
| ladder_25_components_1 | dart_2d_analytic | warm | +54.11%, -4.51%, -9.59% | 5.187458 / 4.372806 | -15.70% | -15.54% | before |
| ladder_25_components_1 | dart_3d_ad | cold | -1.10%, -5.53%, -3.64% | 9.906635 / 9.149236 | -7.65% | -11.83% | before |
| ladder_25_components_1 | dart_3d_ad | warm | -10.68%, -5.86%, -5.57% | 7.903328 / 7.602914 | -3.80% | +159.73% | after |
| ladder_3_components_1 | dart_2d_analytic | cold | -11.62%, -24.45%, -12.79% | 0.197521 / 0.143342 | -27.43% | -40.30% | before |
| ladder_3_components_1 | dart_2d_analytic | warm | +8.10%, +0.23%, -0.28% | 0.126396 / 0.122080 | -3.41% | -51.11% | after |
| ladder_3_components_1 | dart_3d_ad | cold | -19.59%, -4.42%, -17.04% | 0.354574 / 0.316657 | -10.69% | -94.11% | after |
| ladder_3_components_1 | dart_3d_ad | warm | -20.34%, +22.82%, -6.67% | 0.322246 / 0.277610 | -13.85% | -30.27% | before |
| ladder_500_components_1 | dart_2d_analytic | cold | +7.13%, +15.61%, +1.45% | 70.218477 / 64.549027 | -8.07% | +13.20% | before |
| ladder_500_components_1 | dart_2d_analytic | warm | -7.03%, -2.64%, +1.03% | 48.901439 / 46.656073 | -4.59% | -10.54% | after |
| ladder_500_components_1 | dart_3d_ad | cold | +12.88%, -6.37%, -4.42% | 158.564581 / 147.565482 | -6.94% | -10.67% | after |
| ladder_500_components_1 | dart_3d_ad | warm | -4.92%, +5.92%, -2.22% | 126.175717 / 119.526358 | -5.27% | -8.63% | before |
| laman_free_100 | dart_2d_analytic | cold | +5.98%, +16.91%, -11.18% | 7.306276 / 7.214681 | -1.25% | -0.91% | after |
| laman_free_100 | dart_2d_analytic | warm | -11.07%, -5.83%, -17.34% | 7.244005 / 9.007739 | +24.35% | +463.05% | before |
| laman_free_100 | dart_3d_ad | cold | -1.35%, -11.19%, -0.19% | 12.534896 / 11.097184 | -11.47% | -5.36% | before |
| laman_free_100 | dart_3d_ad | warm | +15.90%, +13.75%, -5.69% | 12.361734 / 11.974077 | -3.14% | -1.57% | after |
| laman_free_500 | dart_2d_analytic | cold | -1.23%, -2.82%, +0.23% | 140.759248 / 155.865766 | +10.73% | +25.34% | before |
| laman_free_500 | dart_2d_analytic | warm | -9.26%, -2.02%, -8.18% | 126.453278 / 136.525288 | +7.97% | +0.57% | after |
| laman_free_500 | dart_3d_ad | cold | -7.03%, +7.20%, -12.14% | 240.385464 / 224.049966 | -6.80% | -3.01% | after |
| laman_free_500 | dart_3d_ad | warm | -3.04%, -1.71%, -1.92% | 226.665090 / 178.432094 | -21.28% | +12.09% | before |

### aa

| Fixture | Engine | Mode | Original three p50 effects | Resumed before / after p50, ms | Resumed p50 change | Resumed p95 change | First process |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| axis_rectangle | dart_2d_analytic | cold | -21.17%, +215.38%, -64.60% | 0.074410 / 0.301536 | +305.24% | +584.42% | after |
| axis_rectangle | dart_2d_analytic | warm | -0.34%, +4.88%, -15.31% | 0.045728 / 0.045367 | -0.79% | +76.05% | before |
| axis_rectangle | dart_3d_ad | cold | -8.08%, -11.83%, -15.97% | 0.115621 / 0.117233 | +1.39% | -32.79% | before |
| axis_rectangle | dart_3d_ad | warm | -12.56%, -4.77%, +29.88% | 0.093558 / 0.133658 | +42.86% | +24.89% | after |
| ladder_25_components_1 | dart_2d_analytic | cold | -5.00%, -1.02%, -7.68% | 5.869156 / 5.918308 | +0.84% | -0.78% | after |
| ladder_25_components_1 | dart_2d_analytic | warm | +1.41%, +2.20%, +7.04% | 4.644258 / 4.992882 | +7.51% | +27.70% | before |
| ladder_25_components_1 | dart_3d_ad | cold | -7.36%, +6.79%, -10.74% | 10.128976 / 9.727844 | -3.96% | +0.73% | before |
| ladder_25_components_1 | dart_3d_ad | warm | +3.17%, -9.67%, +0.63% | 8.827643 / 8.043487 | -8.88% | -49.96% | after |
| ladder_3_components_1 | dart_2d_analytic | cold | +21.95%, -2.38%, -1.74% | 0.177062 / 0.199885 | +12.89% | +4.61% | before |
| ladder_3_components_1 | dart_2d_analytic | warm | +1.38%, -49.70%, -17.39% | 0.121119 / 0.126547 | +4.48% | +16.90% | after |
| ladder_3_components_1 | dart_3d_ad | cold | -2.19%, +50.71%, +22.48% | 0.431006 / 0.331369 | -23.12% | -19.34% | after |
| ladder_3_components_1 | dart_3d_ad | warm | -15.88%, -1.24%, -1.14% | 0.237241 / 0.239333 | +0.88% | -0.16% | before |
| ladder_500_components_1 | dart_2d_analytic | cold | -6.97%, +8.56%, +19.35% | 67.222237 / 69.014833 | +2.67% | +21.74% | before |
| ladder_500_components_1 | dart_2d_analytic | warm | +0.60%, -0.61%, -3.74% | 58.631914 / 48.453442 | -17.36% | -5.22% | after |
| ladder_500_components_1 | dart_3d_ad | cold | -3.12%, +6.23%, -12.57% | 183.895654 / 165.070788 | -10.24% | -12.85% | after |
| ladder_500_components_1 | dart_3d_ad | warm | -2.52%, +1.65%, +3.91% | 140.506485 / 139.826471 | -0.48% | +31.35% | before |
| laman_free_100 | dart_2d_analytic | cold | -1.88%, -4.20%, -8.50% | 7.968234 / 7.481947 | -6.10% | +241.05% | after |
| laman_free_100 | dart_2d_analytic | warm | +8.98%, -1.19%, +4.47% | 7.322601 / 9.610128 | +31.24% | +207.88% | before |
| laman_free_100 | dart_3d_ad | cold | -11.72%, +3.35%, +0.58% | 13.920782 / 13.434574 | -3.49% | -6.88% | before |
| laman_free_100 | dart_3d_ad | warm | +10.19%, -3.36%, +5.29% | 12.276254 / 12.844783 | +4.63% | +3.85% | after |

## Reproduction

Run `audit_resumed_blocks.py` after restoring the frozen preparations and raw blocks, supplying `--repo`, `--prepared`, `--runs`, `--saved`, `--original-audit` and an empty `--out` directory. It restores each archive again, verifies the complete byte mapping, and invokes the original independent physical/percentile analyzer without executing solver binaries.

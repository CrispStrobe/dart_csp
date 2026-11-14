# Independent audit of 13 saved blocks

Original session `d1244c09828b` only. CG has four rounds; identity, combined and A/A have three. Later resumed-session evidence must remain separate.


All effects below are after/before within one process pair and one recovered host cohort. Each process has equal weight; raw operations are not pooled across processes for percentile claims. A/A observed ranges describe this run only and do not prove that any candidate effect is noise.

Audit passed: **True**. Non-timing output mismatches: **0**.

## Raw and provenance checks

- cg: 192 processes; 4032 measured operations; 1536 warmups; 5568 accepted operations. 2784 paired non-timing records compared.
- identity: 144 processes; 3024 measured operations; 1152 warmups; 4176 accepted operations. 2088 paired non-timing records compared.
- combined: 144 processes; 3024 measured operations; 1152 warmups; 4176 accepted operations. 2088 paired non-timing records compared.
- aa: 120 processes; 2520 measured operations; 960 warmups; 3480 accepted operations. 1740 paired non-timing records compared.

## Per-case effects

Median pair and median-process ratio are different summaries and both are shown. Repeated regression means more than 5% higher elapsed p50 in at least two rounds; this is a descriptive flag, not a significance test.

### cg

| Fixture | Engine | Mode | Before / after p50 (ms) | Ratio of median p50 | Median paired p50 | Recorded round p50 effects | p95 median pair | Before-first / after-first p50 | Repeated >5% | A/A p50 range |
|---|---|---|---:|---:|---:|---|---:|---|---|---|
| axis_rectangle | dart_2d_analytic | cold | 0.1011 / 0.2213 | +118.8% | +107.0% | -14.8%, +228.8%, -79.9%, +350.3% | +62.2% | -47.4% / +289.5% | 2, 4 | -64.6% to +215.4% |
| axis_rectangle | dart_2d_analytic | warm | 0.0452 / 0.0450 | -0.5% | -1.4% | -1.3%, -14.0%, -1.5%, +1.3% | +25.1% | -6.3% / -1.4% | no | -15.3% to +4.9% |
| axis_rectangle | dart_3d_ad | cold | 0.1190 / 0.1230 | +3.4% | +6.8% | +10.8%, +19.2%, -34.0%, +2.9% | +20.7% | +11.0% / -11.6% | 1, 2 | -16.0% to -8.1% |
| axis_rectangle | dart_3d_ad | warm | 0.1158 / 0.1105 | -4.6% | -2.4% | -3.3%, +35.4%, -1.6%, -31.6% | -5.6% | -2.4% / +1.9% | no | -12.6% to +29.9% |
| ladder_25_components_1 | dart_2d_analytic | cold | 6.1119 / 5.8019 | -5.1% | -6.3% | -7.0%, -1.1%, -9.1%, -5.6% | -5.1% | -8.0% / -3.3% | no | -7.7% to -1.0% |
| ladder_25_components_1 | dart_2d_analytic | warm | 5.1730 / 4.8031 | -7.2% | -4.6% | +0.7%, +2.0%, -28.5%, -10.0% | -7.4% | -4.0% / -13.9% | no | +1.4% to +7.0% |
| ladder_25_components_1 | dart_3d_ad | cold | 9.6182 / 9.9066 | +3.0% | +3.5% | +5.2%, +21.8%, -6.0%, +1.7% | +9.0% | +11.7% / -0.4% | 1, 2 | -10.7% to +6.8% |
| ladder_25_components_1 | dart_3d_ad | warm | 8.4086 / 8.3022 | -1.3% | -5.8% | -2.1%, +18.7%, -17.9%, -9.4% | -0.1% | -10.0% / +4.7% | no | -9.7% to +3.2% |
| ladder_3_components_1 | dart_2d_analytic | cold | 0.1474 / 0.1835 | +24.5% | +20.2% | +9.1%, +40.3%, +9.1%, +31.2% | +11.0% | +35.7% / +9.1% | 1, 2, 3, 4 | -2.4% to +21.9% |
| ladder_3_components_1 | dart_2d_analytic | warm | 0.1267 / 0.1265 | -0.1% | +0.0% | -0.3%, +0.3%, +5.4%, -3.4% | -12.2% | +2.6% / -1.6% | no | -49.7% to +1.4% |
| ladder_3_components_1 | dart_3d_ad | cold | 0.4104 / 0.4120 | +0.4% | +0.4% | -4.8%, +2.5%, -0.6%, +1.4% | +2.8% | -2.7% / +2.0% | no | -2.2% to +50.7% |
| ladder_3_components_1 | dart_3d_ad | warm | 0.2595 / 0.2935 | +13.1% | +0.1% | -3.2%, -3.4%, +3.3%, +28.6% | -1.4% | +12.6% / +0.1% | no | -15.9% to -1.1% |
| ladder_500_components_1 | dart_2d_analytic | cold | 73.0198 / 71.6913 | -1.8% | +0.0% | -4.3%, +7.1%, +0.9%, -0.8% | -6.7% | +3.1% / -1.7% | no | -7.0% to +19.3% |
| ladder_500_components_1 | dart_2d_analytic | warm | 59.0111 / 52.2021 | -11.5% | -11.4% | -13.2%, +0.8%, -17.3%, -9.6% | -11.7% | -15.3% / -4.4% | no | -3.7% to +0.6% |
| ladder_500_components_1 | dart_3d_ad | cold | 187.8504 / 200.4655 | +6.7% | +4.1% | +8.6%, +3.2%, +4.9%, -3.5% | -6.9% | +6.8% / -0.2% | no | -12.6% to +6.2% |
| ladder_500_components_1 | dart_3d_ad | warm | 144.3812 / 144.5529 | +0.1% | +0.4% | -7.9%, +5.9%, +0.9%, -0.2% | -39.5% | +2.9% / -3.5% | no | -2.5% to +3.9% |
| laman_free_100 | dart_2d_analytic | cold | 8.3736 / 8.4559 | +1.0% | +7.0% | +75.3%, +21.7%, -41.9%, -7.6% | -6.7% | +16.7% / +7.0% | 1, 2 | -8.5% to -1.9% |
| laman_free_100 | dart_2d_analytic | warm | 7.8950 / 7.3378 | -7.1% | -6.2% | -8.2%, -6.3%, -6.2%, +0.5% | -1.6% | -2.9% / -7.2% | no | -1.2% to +9.0% |
| laman_free_100 | dart_3d_ad | cold | 13.4383 / 12.5845 | -6.4% | -5.1% | -5.8%, +18.3%, -8.2%, -4.5% | -5.5% | +6.9% / -7.0% | no | -11.7% to +3.4% |
| laman_free_100 | dart_3d_ad | warm | 12.8593 / 14.6735 | +14.1% | +2.7% | -3.2%, -0.0%, +33.4%, +5.4% | +6.0% | +15.1% / +2.7% | 3, 4 | -3.4% to +10.2% |
| laman_free_500 | dart_2d_analytic | cold | 158.3281 / 152.6821 | -3.6% | -3.6% | -2.7%, -8.4%, -4.4%, -0.9% | +5.4% | -4.7% / -3.6% | no | not measured |
| laman_free_500 | dart_2d_analytic | warm | 124.1786 / 126.9760 | +2.3% | -0.3% | -2.6%, -4.2%, +2.0%, +6.7% | +10.4% | -0.3% / +1.3% | no | not measured |
| laman_free_500 | dart_3d_ad | cold | 260.3757 / 225.6154 | -13.4% | -10.0% | -18.2%, -7.1%, -13.0%, -3.9% | -8.7% | -15.6% / -5.5% | no | not measured |
| laman_free_500 | dart_3d_ad | warm | 207.4041 / 181.1993 | -12.6% | -11.0% | -13.6%, -13.9%, -8.4%, -7.0% | -3.7% | -10.5% / -11.0% | no | not measured |

### identity

| Fixture | Engine | Mode | Before / after p50 (ms) | Ratio of median p50 | Median paired p50 | Recorded round p50 effects | p95 median pair | Before-first / after-first p50 | Repeated >5% | A/A p50 range |
|---|---|---|---:|---:|---:|---|---:|---|---|---|
| axis_rectangle | dart_2d_analytic | cold | 0.0795 / 0.0853 | +7.3% | +3.2% | +3.2%, +19.9%, -71.7% | -5.0% | -34.2% / +19.9% | no | -64.6% to +215.4% |
| axis_rectangle | dart_2d_analytic | warm | 0.0579 / 0.0434 | -25.0% | -25.8% | -41.8%, +0.9%, -25.8% | -12.8% | +0.9% / -33.8% | no | -15.3% to +4.9% |
| axis_rectangle | dart_3d_ad | cold | 0.1841 / 0.1213 | -34.1% | -8.7% | +52.1%, -34.1%, -8.7% | -6.1% | -34.1% / +21.7% | no | -16.0% to -8.1% |
| axis_rectangle | dart_3d_ad | warm | 0.1162 / 0.0860 | -26.0% | -26.0% | +35.1%, -39.1%, -26.0% | -10.0% | +4.5% / -39.1% | no | -12.6% to +29.9% |
| ladder_25_components_1 | dart_2d_analytic | cold | 5.6966 / 6.0969 | +7.0% | +1.2% | +7.0%, +1.2%, -4.9% | -0.1% | +1.1% / +1.2% | no | -7.7% to -1.0% |
| ladder_25_components_1 | dart_2d_analytic | warm | 5.4319 / 4.7229 | -13.1% | -1.4% | -13.1%, -0.2%, -1.4% | +3.0% | -0.2% / -7.2% | no | +1.4% to +7.0% |
| ladder_25_components_1 | dart_3d_ad | cold | 9.3757 / 9.6727 | +3.2% | +3.2% | +3.2%, +9.5%, -9.4% | -9.3% | +9.5% / -3.1% | no | -10.7% to +6.8% |
| ladder_25_components_1 | dart_3d_ad | warm | 8.4056 / 7.6936 | -8.5% | -9.4% | -9.4%, -12.5%, +2.2% | -13.2% | -3.6% / -12.5% | no | -9.7% to +3.2% |
| ladder_3_components_1 | dart_2d_analytic | cold | 0.2004 / 0.1902 | -5.1% | -11.5% | -20.8%, -11.5%, +30.1% | -9.4% | -11.5% / +4.6% | no | -2.4% to +21.9% |
| ladder_3_components_1 | dart_2d_analytic | warm | 0.1255 / 0.1240 | -1.2% | -1.0% | -2.5%, +137.4%, -1.0% | -5.5% | -1.8% / +137.4% | no | -49.7% to +1.4% |
| ladder_3_components_1 | dart_3d_ad | cold | 0.3518 / 0.3551 | +0.9% | +5.8% | +5.8%, -5.7%, +7.6% | +20.1% | +6.7% / -5.7% | 1, 3 | -2.2% to +50.7% |
| ladder_3_components_1 | dart_3d_ad | warm | 0.3142 / 0.2683 | -14.6% | -16.9% | +2.9%, -16.9%, -19.2% | -24.8% | -16.9% / -8.2% | no | -15.9% to -1.1% |
| ladder_500_components_1 | dart_2d_analytic | cold | 68.0636 / 73.1319 | +7.4% | +7.2% | -6.0%, +7.2%, +23.5% | -14.9% | +7.2% / +8.7% | 2, 3 | -7.0% to +19.3% |
| ladder_500_components_1 | dart_2d_analytic | warm | 52.2165 / 52.2536 | +0.1% | -2.9% | +0.1%, -5.3%, -2.9% | +0.9% | -1.4% / -5.3% | no | -3.7% to +0.6% |
| ladder_500_components_1 | dart_3d_ad | cold | 179.5018 / 190.1474 | +5.9% | +2.4% | +2.4%, -4.2%, +26.7% | -0.1% | +14.5% / -4.2% | no | -12.6% to +6.2% |
| ladder_500_components_1 | dart_3d_ad | warm | 137.5559 / 128.7795 | -6.4% | -5.7% | -5.7%, -8.7%, -0.8% | -4.9% | -8.7% / -3.3% | no | -2.5% to +3.9% |
| laman_free_100 | dart_2d_analytic | cold | 7.1344 / 7.0575 | -1.1% | -1.1% | -4.3%, -1.1%, +31.9% | +3.0% | +13.8% / -1.1% | no | -8.5% to -1.9% |
| laman_free_100 | dart_2d_analytic | warm | 6.9295 / 8.6005 | +24.1% | +14.3% | +32.3%, +14.3%, +10.6% | +55.9% | +14.3% / +21.5% | 1, 2, 3 | -1.2% to +9.0% |
| laman_free_100 | dart_3d_ad | cold | 12.2765 / 12.5025 | +1.8% | +1.8% | +1.8%, -2.2%, +27.8% | +6.5% | -2.2% / +14.8% | no | -11.7% to +3.4% |
| laman_free_100 | dart_3d_ad | warm | 12.9966 / 12.9361 | -0.5% | -5.7% | -5.7%, +4.3%, -19.0% | +10.1% | -12.3% / +4.3% | no | -3.4% to +10.2% |
| laman_free_500 | dart_2d_analytic | cold | 166.0708 / 151.1300 | -9.0% | -0.3% | -9.0%, +1.4%, -0.3% | -21.9% | +1.4% / -4.7% | no | not measured |
| laman_free_500 | dart_2d_analytic | warm | 118.9007 / 122.7667 | +3.3% | -0.0% | +15.6%, -0.0%, -22.4% | -4.5% | -3.4% / -0.0% | no | not measured |
| laman_free_500 | dart_3d_ad | cold | 235.7454 / 221.9145 | -5.9% | -3.2% | -5.9%, -3.2%, +16.0% | +10.9% | +5.0% / -3.2% | no | not measured |
| laman_free_500 | dart_3d_ad | warm | 186.2504 / 203.5533 | +9.3% | +0.4% | +9.3%, -1.5%, +0.4% | +5.9% | -1.5% / +4.8% | no | not measured |

### combined

| Fixture | Engine | Mode | Before / after p50 (ms) | Ratio of median p50 | Median paired p50 | Recorded round p50 effects | p95 median pair | Before-first / after-first p50 | Repeated >5% | A/A p50 range |
|---|---|---|---:|---:|---:|---|---:|---|---|---|
| axis_rectangle | dart_2d_analytic | cold | 0.1040 / 0.0915 | -12.0% | -12.0% | -12.0%, +64.6%, -78.3% | -50.5% | -45.1% / +64.6% | no | -64.6% to +215.4% |
| axis_rectangle | dart_2d_analytic | warm | 0.0455 / 0.0440 | -3.3% | -3.3% | -23.9%, -3.3%, -1.8% | -9.3% | -3.3% / -12.8% | no | -15.3% to +4.9% |
| axis_rectangle | dart_3d_ad | cold | 0.1611 / 0.1354 | -15.9% | +11.4% | -33.7%, +11.4%, +17.4% | -0.3% | +11.4% / -8.1% | 2, 3 | -16.0% to -8.1% |
| axis_rectangle | dart_3d_ad | warm | 0.0906 / 0.1254 | +38.4% | +39.0% | +39.0%, +28.0%, +39.3% | -19.1% | +39.1% / +28.0% | 1, 2, 3 | -12.6% to +29.9% |
| ladder_25_components_1 | dart_2d_analytic | cold | 5.5785 / 5.5856 | +0.1% | +0.0% | +3.1%, -4.2%, +0.0% | +1.7% | +1.6% / -4.2% | no | -7.7% to -1.0% |
| ladder_25_components_1 | dart_2d_analytic | warm | 5.0627 / 4.9678 | -1.9% | -4.5% | +54.1%, -4.5%, -9.6% | -6.8% | -4.5% / +22.3% | no | +1.4% to +7.0% |
| ladder_25_components_1 | dart_3d_ad | cold | 9.5874 / 9.2383 | -3.6% | -3.6% | -1.1%, -5.5%, -3.6% | -16.9% | -5.5% / -2.4% | no | -10.7% to +6.8% |
| ladder_25_components_1 | dart_3d_ad | warm | 8.1342 / 7.6572 | -5.9% | -5.9% | -10.7%, -5.9%, -5.6% | +4.4% | -8.1% / -5.9% | no | -9.7% to +3.2% |
| ladder_3_components_1 | dart_2d_analytic | cold | 0.1773 / 0.1526 | -13.9% | -12.8% | -11.6%, -24.4%, -12.8% | -17.8% | -24.4% / -12.2% | no | -2.4% to +21.9% |
| ladder_3_components_1 | dart_2d_analytic | warm | 0.1227 / 0.1223 | -0.3% | +0.2% | +8.1%, +0.2%, -0.3% | -10.0% | +3.9% / +0.2% | no | -49.7% to +1.4% |
| ladder_3_components_1 | dart_3d_ad | cold | 0.3804 / 0.3156 | -17.0% | -17.0% | -19.6%, -4.4%, -17.0% | -4.0% | -18.3% / -4.4% | no | -2.2% to +50.7% |
| ladder_3_components_1 | dart_3d_ad | warm | 0.2602 / 0.2992 | +15.0% | -6.7% | -20.3%, +22.8%, -6.7% | -17.1% | +22.8% / -13.5% | no | -15.9% to -1.1% |
| ladder_500_components_1 | dart_2d_analytic | cold | 66.1529 / 73.1757 | +10.6% | +7.1% | +7.1%, +15.6%, +1.5% | +15.0% | +15.6% / +4.3% | 1, 2 | -7.0% to +19.3% |
| ladder_500_components_1 | dart_2d_analytic | warm | 49.5379 / 48.2298 | -2.6% | -2.6% | -7.0%, -2.6%, +1.0% | -0.1% | -3.0% / -2.6% | no | -3.7% to +0.6% |
| ladder_500_components_1 | dart_3d_ad | cold | 163.0706 / 155.2983 | -4.8% | -4.4% | +12.9%, -6.4%, -4.4% | +13.8% | +4.2% / -6.4% | no | -12.6% to +6.2% |
| ladder_500_components_1 | dart_3d_ad | warm | 129.0163 / 122.6709 | -4.9% | -2.2% | -4.9%, +5.9%, -2.2% | -8.4% | +5.9% / -3.6% | no | -2.5% to +3.9% |
| laman_free_100 | dart_2d_analytic | cold | 7.1610 / 7.3068 | +2.0% | +6.0% | +6.0%, +16.9%, -11.2% | +5.1% | -2.6% / +16.9% | 1, 2 | -8.5% to -1.9% |
| laman_free_100 | dart_2d_analytic | warm | 7.9849 / 7.1009 | -11.1% | -11.1% | -11.1%, -5.8%, -17.3% | -14.3% | -5.8% / -14.2% | no | -1.2% to +9.0% |
| laman_free_100 | dart_3d_ad | cold | 12.4908 / 12.3386 | -1.2% | -1.3% | -1.3%, -11.2%, -0.2% | -0.3% | -11.2% / -0.8% | no | -11.7% to +3.4% |
| laman_free_100 | dart_3d_ad | warm | 12.1187 / 14.0450 | +15.9% | +13.7% | +15.9%, +13.7%, -5.7% | +0.9% | +5.1% / +13.7% | 1, 2 | -3.4% to +10.2% |
| laman_free_500 | dart_2d_analytic | cold | 148.0342 / 146.4111 | -1.1% | -1.2% | -1.2%, -2.8%, +0.2% | -10.0% | -2.8% / -0.5% | no | not measured |
| laman_free_500 | dart_2d_analytic | warm | 121.2946 / 110.0668 | -9.3% | -8.2% | -9.3%, -2.0%, -8.2% | -9.7% | -8.7% / -2.0% | no | not measured |
| laman_free_500 | dart_3d_ad | cold | 234.8751 / 211.5783 | -9.9% | -7.0% | -7.0%, +7.2%, -12.1% | -11.3% | -9.6% / +7.2% | no | not measured |
| laman_free_500 | dart_3d_ad | warm | 188.3219 / 182.5949 | -3.0% | -1.9% | -3.0%, -1.7%, -1.9% | -8.0% | -1.7% / -2.5% | no | not measured |

### aa

| Fixture | Engine | Mode | Before / after p50 (ms) | Ratio of median p50 | Median paired p50 | Recorded round p50 effects | p95 median pair | Before-first / after-first p50 | Repeated >5% | A/A p50 range |
|---|---|---|---:|---:|---:|---|---:|---|---|---|
| axis_rectangle | dart_2d_analytic | cold | 0.0975 / 0.1272 | +30.4% | -21.2% | -21.2%, +215.4%, -64.6% | -30.7% | -42.9% / +215.4% | no | -64.6% to +215.4% |
| axis_rectangle | dart_2d_analytic | warm | 0.0447 / 0.0454 | +1.4% | -0.3% | -0.3%, +4.9%, -15.3% | -3.2% | +4.9% / -7.8% | no | -15.3% to +4.9% |
| axis_rectangle | dart_3d_ad | cold | 0.1403 / 0.1213 | -13.6% | -11.8% | -8.1%, -11.8%, -16.0% | -10.5% | -11.8% / -12.0% | no | -16.0% to -8.1% |
| axis_rectangle | dart_3d_ad | warm | 0.1014 / 0.1027 | +1.3% | -4.8% | -12.6%, -4.8%, +29.9% | -6.8% | +8.7% / -4.8% | no | -12.6% to +29.9% |
| ladder_25_components_1 | dart_2d_analytic | cold | 5.6519 / 5.5750 | -1.4% | -5.0% | -5.0%, -1.0%, -7.7% | -21.2% | -6.3% / -1.0% | no | -7.7% to -1.0% |
| ladder_25_components_1 | dart_2d_analytic | warm | 4.9172 / 5.0254 | +2.2% | +2.2% | +1.4%, +2.2%, +7.0% | +17.9% | +2.2% / +4.2% | no | +1.4% to +7.0% |
| ladder_25_components_1 | dart_3d_ad | cold | 10.1119 / 9.9477 | -1.6% | -7.4% | -7.4%, +6.8%, -10.7% | -12.8% | +6.8% / -9.0% | no | -10.7% to +6.8% |
| ladder_25_components_1 | dart_3d_ad | warm | 9.0310 / 8.2806 | -8.3% | +0.6% | +3.2%, -9.7%, +0.6% | +6.4% | +1.9% / -9.7% | no | -9.7% to +3.2% |
| ladder_3_components_1 | dart_2d_analytic | cold | 0.1543 / 0.1731 | +12.2% | -1.7% | +21.9%, -2.4%, -1.7% | -6.0% | -2.4% / +10.1% | no | -2.4% to +21.9% |
| ladder_3_components_1 | dart_2d_analytic | warm | 0.1669 / 0.1358 | -18.6% | -17.4% | +1.4%, -49.7%, -17.4% | -10.6% | -8.0% / -49.7% | no | -49.7% to +1.4% |
| ladder_3_components_1 | dart_3d_ad | cold | 0.3651 / 0.4767 | +30.5% | +22.5% | -2.2%, +50.7%, +22.5% | -4.5% | +10.1% / +50.7% | 2, 3 | -2.2% to +50.7% |
| ladder_3_components_1 | dart_3d_ad | warm | 0.2843 / 0.2445 | -14.0% | -1.2% | -15.9%, -1.2%, -1.1% | -18.7% | -1.2% / -8.5% | no | -15.9% to -1.1% |
| ladder_500_components_1 | dart_2d_analytic | cold | 69.0870 / 79.2041 | +14.6% | +8.6% | -7.0%, +8.6%, +19.3% | +13.3% | +8.6% / +6.2% | 2, 3 | -7.0% to +19.3% |
| ladder_500_components_1 | dart_2d_analytic | warm | 47.8278 / 48.1129 | +0.6% | -0.6% | +0.6%, -0.6%, -3.7% | +16.0% | -1.6% / -0.6% | no | -3.7% to +0.6% |
| ladder_500_components_1 | dart_3d_ad | cold | 165.9509 / 160.7804 | -3.1% | -3.1% | -3.1%, +6.2%, -12.6% | -18.3% | -7.8% / +6.2% | no | -12.6% to +6.2% |
| ladder_500_components_1 | dart_3d_ad | warm | 128.1992 / 130.3135 | +1.6% | +1.6% | -2.5%, +1.6%, +3.9% | -10.6% | +1.6% / +0.7% | no | -2.5% to +3.9% |
| laman_free_100 | dart_2d_analytic | cold | 7.3569 / 7.2186 | -1.9% | -4.2% | -1.9%, -4.2%, -8.5% | -18.6% | -5.2% / -4.2% | no | -8.5% to -1.9% |
| laman_free_100 | dart_2d_analytic | warm | 7.3932 / 7.3053 | -1.2% | +4.5% | +9.0%, -1.2%, +4.5% | +4.8% | -1.2% / +6.7% | no | -1.2% to +9.0% |
| laman_free_100 | dart_3d_ad | cold | 12.6995 / 12.5578 | -1.1% | +0.6% | -11.7%, +3.4%, +0.6% | +9.5% | +3.4% / -5.6% | no | -11.7% to +3.4% |
| laman_free_100 | dart_3d_ad | warm | 11.9155 / 12.0787 | +1.4% | +5.3% | +10.2%, -3.4%, +5.3% | -6.0% | +7.7% / -3.4% | 1, 3 | -3.4% to +10.2% |

## Limits and retention criteria

- Keep correctness and bounded-resource behavior as gates. Physical acceptance, tolerances, callback ordering, work caps, cancellation, and result ownership are not performance tuning parameters.
- Judge useful gain on the code path that executes the candidate, and report both favorable and adverse controls. A/A is a descriptive context, never a correction to subtract.
- Four process pairs provide limited replication. A gain that reverses with process order or has large control variation remains uncertain; no universal nonregression follows from this experiment.
- Preserve historical cohorts separately. This audit does not join the recovered-host timing population to an earlier workspace or runtime.
- Timing is native build/update through solve and extraction, excluding process startup, JSON serialization, and the independent oracle. Build/solve/elapsed observations and sums are in the JSON report.
- Bit-sensitive canonical JSON comparison is used for every non-timing record, including coordinates and work counters. Mismatches are retained explicitly; they are never silently excluded.

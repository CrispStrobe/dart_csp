# Independent final small-QR/CAD cross-check — 2026-11-14

## Finding

The complete prespecified cohort is internally consistent and all harness correctness checks passed. The independent process audit passed 1,010 checks, and the measurement/source cross-check passed 16,890 assertions, both without findings. No solver was rerun by these audits.

There are 36 complete benchmark processes, six AOT compilations, 240 reconstructed raw timing distributions and 6,000 measured sample timings. All 2,400 aligned CAD work records satisfy the fixture invariants; every before/after paired work series and static snapshot is identical. All 40 summary rows and both per-process and aggregate percentiles were independently reconstructed. The live before/after worktrees match the recorded 89 library files and all harness/dependency bytes.

## Interpretation for retention

This supplies the outstanding small-QR, plate and articulated-CAD control evidence. It exposes no new correctness or physical-work divergence. The cohort supports retaining the candidate for its qualified large sparse-ladder benefit, provided integration explicitly accepts the collateral timing costs below. It does not establish a uniformly faster release or a statistically stable bound on overhead.

All 12 AOT small-QR p50 aggregates are faster by 0.2–20.6%. The adverse p50 controls include AOT plate thickness (+11.16%, 636 to 707 microseconds), AOT plate profile (+6.09%, 722 to 766 microseconds), JIT rank 4x5 (+11.88% per 256-operation batch), and JIT cold articulated CAD (+6.68%, 2,681 to 2,860 microseconds).

Adverse tails remain material observations: JIT rank 4x8 p95 is 217 to 2,633 microseconds per 256-operation batch (+1,113.36%) while p50 is 142 to 138; JIT cold articulated-CAD p95 is +30.48%; AOT plate profile p95 is +20.37%. Three short fresh-process pairs are descriptive screening evidence; large JIT tails cannot be attributed to sparse arithmetic from these timings. The rank API and plate thickness edit do not execute sparse factorization. The unchanged physical work does not rule out dispatcher/compiler layout effects on other paths. No process or sample was removed and no hosts were pooled.

## Complete retained timing table

Values are medians of three process p50/p95 values. Positive changes mean slower candidate times. QR timings are batches of 256 operations except rank 48x48 (eight operations); all CAD rows time one operation.

| Runtime | Benchmark / operation | Before p50 us | After p50 us | p50 change | p95 change | Matched p50 changes by round |
|---|---|---:|---:|---:|---:|---|
| JIT | geometry_small_qr / rank_5x4 | 474 | 448 | -5.49% | -1.72% | +2.05%, +7.38%, -18.44% |
| JIT | geometry_small_qr / rank_8x4 | 111 | 112 | +0.90% | +49.88% | +123.74%, +0.90%, +0.93% |
| JIT | geometry_small_qr / rank_4x5 | 202 | 226 | +11.88% | -70.07% | +104.82%, -39.60%, -35.24% |
| JIT | geometry_small_qr / rank_4x8 | 142 | 138 | -2.82% | +1113.36% | +52.78%, -4.23%, +2.22% |
| JIT | geometry_small_qr / rank_9x4 | 118 | 110 | -6.78% | -4.24% | -3.39%, -6.78%, -0.90% |
| JIT | geometry_small_qr / rank_12x4 | 130 | 128 | -1.54% | -9.38% | -2.21%, -2.31%, +0.00% |
| JIT | geometry_small_qr / rank_16x8 | 404 | 394 | -2.48% | -27.95% | +0.24%, -4.46%, -0.25% |
| JIT | geometry_small_qr / rank_16x9 | 456 | 450 | -1.32% | +1.56% | -3.73%, -1.75%, +3.42% |
| JIT | geometry_small_qr / rank_17x8 | 404 | 401 | -0.74% | +2.21% | +0.25%, -0.74%, +0.00% |
| JIT | geometry_small_qr / rank_48x48 | 551 | 556 | +0.91% | +9.58% | +11.25%, -0.72%, +1.09% |
| JIT | geometry_small_qr / damped_solve_8x4 | 216 | 173 | -19.91% | -23.45% | -20.37%, -52.27%, -8.47% |
| JIT | geometry_small_qr / nullspace_4x8 | 348 | 146 | -58.05% | -92.76% | -71.97%, +20.69%, -8.18% |
| JIT | cad / cold_build_compile_regenerate | 1,394 | 1,213 | -12.98% | -3.95% | +32.78%, -37.61%, -6.48% |
| JIT | cad / profile_edit_regenerate | 1,370 | 1,389 | +1.39% | -13.61% | +6.80%, +1.39%, -25.97% |
| JIT | cad / thickness_edit_regenerate | 796 | 688 | -13.57% | -8.22% | +12.81%, -9.11%, -19.08% |
| JIT | cad_linkage / cold_build_solve_solids_meshes | 2,681 | 2,860 | +6.68% | +30.48% | -13.81%, -2.80%, +15.70% |
| JIT | cad_linkage / retained_angle_edit | 402 | 334 | -16.92% | -35.42% | -2.19%, -21.78%, -17.91% |
| JIT | cad_linkage / selective_coupler_length_edit | 939 | 853 | -9.16% | +12.11% | -18.14%, -8.27%, -8.20% |
| JIT | cad_linkage / placement_only_layer_edit | 146 | 138 | -5.48% | -54.47% | -10.22%, -5.48%, -10.83% |
| JIT | cad_linkage / downstream_rejected_angle_edit | 344 | 353 | +2.62% | -29.79% | -8.43%, +0.00%, +5.37% |
| AOT | geometry_small_qr / rank_5x4 | 109 | 97 | -11.01% | +10.09% | -4.63%, -12.84%, -15.65% |
| AOT | geometry_small_qr / rank_8x4 | 130 | 117 | -10.00% | -10.73% | +17.69%, -10.00%, -13.64% |
| AOT | geometry_small_qr / rank_4x5 | 124 | 109 | -12.10% | -14.04% | +0.00%, -13.49%, -12.10% |
| AOT | geometry_small_qr / rank_4x8 | 201 | 191 | -4.98% | -13.71% | -2.99%, -29.91%, +9.14% |
| AOT | geometry_small_qr / rank_9x4 | 155 | 123 | -20.65% | -33.07% | -10.97%, -22.15%, -12.95% |
| AOT | geometry_small_qr / rank_12x4 | 166 | 142 | -14.46% | -2.94% | -4.22%, -14.46%, -11.95% |
| AOT | geometry_small_qr / rank_16x8 | 437 | 429 | -1.83% | -7.47% | -7.92%, -1.83%, -4.92% |
| AOT | geometry_small_qr / rank_16x9 | 489 | 488 | -0.20% | +15.32% | -5.71%, +1.04%, -2.25% |
| AOT | geometry_small_qr / rank_17x8 | 476 | 446 | -6.30% | -10.19% | -3.99%, -4.53%, -6.30% |
| AOT | geometry_small_qr / rank_48x48 | 586 | 579 | -1.19% | -3.07% | +4.61%, -7.66%, +2.14% |
| AOT | geometry_small_qr / damped_solve_8x4 | 206 | 184 | -10.68% | -18.86% | -11.00%, -11.17%, -0.54% |
| AOT | geometry_small_qr / nullspace_4x8 | 186 | 182 | -2.15% | +17.25% | +8.60%, -4.71%, +3.70% |
| AOT | cad / cold_build_compile_regenerate | 739 | 721 | -2.44% | +2.19% | +0.73%, -2.44%, -4.14% |
| AOT | cad / profile_edit_regenerate | 722 | 766 | +6.09% | +20.37% | -5.59%, +6.09%, -3.35% |
| AOT | cad / thickness_edit_regenerate | 636 | 707 | +11.16% | +0.71% | -4.05%, +11.16%, -0.66% |
| AOT | cad_linkage / cold_build_solve_solids_meshes | 1,776 | 1,802 | +1.46% | -72.32% | -0.05%, +1.46%, -2.33% |
| AOT | cad_linkage / retained_angle_edit | 154 | 144 | -6.49% | -71.65% | -15.56%, -6.49%, +4.58% |
| AOT | cad_linkage / selective_coupler_length_edit | 583 | 554 | -4.97% | -55.25% | -16.06%, -4.97%, +1.40% |
| AOT | cad_linkage / placement_only_layer_edit | 73 | 68 | -6.85% | -66.04% | -8.86%, -6.85%, +6.56% |
| AOT | cad_linkage / downstream_rejected_angle_edit | 122 | 124 | +1.64% | -55.47% | +0.00%, +1.64%, +0.00% |

## Reproduction and boundary

Run `tool/audit_sparse_small_cad_crosscheck.py RAW SUMMARY --before BEFORE --after AFTER --output AUDIT` and repository `tool/audit_recovery_processes.py RAW --output AUDIT`. The first extends the preserved independent CAD auditor with explicit small-QR shape, batch and percentile checks; neither imports the project summarizer.

This audit validates serialized pass records and the reviewed harness control flow. Complete geometry coordinates and QR numerical results are not serialized in this collector, so physical oracles cannot be replayed here as they can in the large-solver adapter cohorts. Every result is checked by the harness outside its timer. Process records preserve exact stdout/stderr hashes, source/package mapping and compile/run linkage; the collector does not hash or retain the six temporary AOT executables. SDK identity is recorded separately in preparation.

The prior seven-round controls and rejected 2,000-coordinate dense-fill cohort remain separate, unchanged evidence. Real-browser coverage still requires its own actual CI result.

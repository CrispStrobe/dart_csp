# Independent heap target comparison review — 2026-11-14

## Evidence finding

The complete target comparison passes its independent audit with zero integrity or experiment-contract findings. Baseline is `c2603a852229897d325a8890ed418319ee8c3572`; candidate is `521a31f78989cf4706c8f26bb6a2c2ec2709b777`. The audit checks those exact committed source identities, frozen preparation/source/executable hashes, raw requests and native output, physical-oracle replay, complete sequential job inventory, terminal gates, process percentiles, aggregate ratios and exact paired coordinate/work results.

All **72 jobs** complete and all **648 requested operations** are physically accepted: **504 measured operations and 144 warmups**. Every one of the **324 before/after operation pairs** has identical coordinates and all seven recorded solver-work counters. There are no missing operations, timeouts, nonzero exits, parse errors, adapter exceptions, oracle disagreements or qualification mismatches. `independent-audit.json` records the full result. This audit ran on CPU 8 and executed no Dart workload.

## Interpretation

The target cohort supports a selective low-fill benefit. All eight ladder aggregate medians improve, and warm coupled 2D also improves; nine of twelve aggregate medians are lower. The strongest repeatable target result is the 2,000-coordinate 3D cold ladder: aggregate p50 is **104.165 → 94.209 ms (-9.56%)**, p95 is **138.350 → 109.010 ms (-21.21%)**, and both percentiles improve in all three matched process pairs. Cold 500-coordinate 3D p50 improves **13.04%**, with two faster pairs and one slower pair; all three p95 pairs improve.

The coupled controls retain adverse results: cold p50 is **+5.67% in 2D** and **+4.94% in 3D**; warm 3D is **+4.30% p50 and +22.40% p95**. Warm 500-coordinate 3D ladder p95 rises **9.84%**, with all three paired p95 values higher, even though its p50 improves in every pair. Cold 2,000-coordinate 2D ladder p95 rises **7.76%**. These observations are retained costs and are not dismissed as noise.

Several aggregate directions differ from a majority of matched pair directions. For example, cold coupled 2D aggregate p50 worsens while two individual pairs improve; warm 2,000-coordinate 3D ladder aggregate p50 improves while two pairs worsen. The ratio of separate process medians and matched process ratios describe different summaries; both are retained below. No process, fixture, operation or sample was discarded, and no prior host cohort was pooled with this one.

This is a three-pair screening cohort. With seven measured samples, `ceil((n-1)*0.95)` selects the largest sample in each process; the reported aggregate p95 is therefore the median of three process maxima. These measurements do not establish a stable tail-latency bound or causal attribution. The saved work counters establish unchanged nonlinear/numeric work, but do not count individual selector invocations or symbolic comparisons. Warm timing changes alone cannot be attributed to heap work.

Retention can be justified for its bounded-work mechanism and low-fill target benefit only with the adverse coupled/tail observations stated explicitly and the remaining planned small controls and reliability gate considered. This target cohort does not show a universal performance improvement or a fix for the prior JIT/CAD tail issues.

## Complete aggregate table

Times are milliseconds per complete build/update + solve + extraction operation. Each number is a median of three independent process percentiles. Positive change means slower candidate elapsed time. Pair counts are faster/equal/slower.

| Fixture / engine / lifecycle | Before p50 | After p50 | p50 change | Before p95 | After p95 | p95 change | p50 pairs F/E/S | p95 pairs F/E/S |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Ladder 500 / 2D analytic / cold | 7.731376 | 7.410869 | -4.15% | 9.568271 | 9.577065 | +0.09% | 3/0/0 | 1/0/2 |
| Ladder 500 / 3D AD / cold | 18.871499 | 16.410634 | -13.04% | 20.949011 | 19.089180 | -8.88% | 2/0/1 | 3/0/0 |
| Ladder 500 / 2D analytic / warm | 6.023061 | 5.437298 | -9.73% | 7.553050 | 6.124341 | -18.92% | 2/0/1 | 2/0/1 |
| Ladder 500 / 3D AD / warm | 14.069006 | 13.179121 | -6.33% | 14.682708 | 16.127742 | +9.84% | 3/0/0 | 0/0/3 |
| Ladder 2,000 / 2D analytic / cold | 38.954182 | 37.686232 | -3.25% | 48.850932 | 52.642540 | +7.76% | 2/0/1 | 1/0/2 |
| Ladder 2,000 / 3D AD / cold | 104.164662 | 94.208554 | -9.56% | 138.349823 | 109.009976 | -21.21% | 3/0/0 | 3/0/0 |
| Ladder 2,000 / 2D analytic / warm | 26.295812 | 26.257681 | -0.15% | 69.157134 | 33.698273 | -51.27% | 2/0/1 | 2/0/1 |
| Ladder 2,000 / 3D AD / warm | 69.631587 | 68.570035 | -1.52% | 76.218407 | 75.410025 | -1.06% | 1/0/2 | 1/0/2 |
| Coupled 500 / 2D analytic / cold | 66.220331 | 69.978217 | +5.67% | 80.555307 | 80.744578 | +0.23% | 2/0/1 | 2/0/1 |
| Coupled 500 / 3D AD / cold | 100.710348 | 105.683221 | +4.94% | 128.864318 | 132.474704 | +2.80% | 1/0/2 | 1/0/2 |
| Coupled 500 / 2D analytic / warm | 60.038097 | 55.050835 | -8.31% | 91.197887 | 62.818859 | -31.12% | 3/0/0 | 2/0/1 |
| Coupled 500 / 3D AD / warm | 92.581430 | 96.560648 | +4.30% | 107.410418 | 131.473141 | +22.40% | 1/0/2 | 1/0/2 |

## Every matched process pair

Changes are candidate/baseline elapsed-time percentages in round order; positive means slower. Exact before/after process values are in `timing-details.json` and raw job summaries.

| Fixture / engine / lifecycle | p50 changes, rounds 1 / 2 / 3 | p95 changes, rounds 1 / 2 / 3 |
|---|---|---|
| Ladder 500 / 2D analytic / cold | -57.07% / -2.39% / -6.06% | -71.34% / +10.17% / +20.87% |
| Ladder 500 / 3D AD / cold | -13.04% / +2.07% / -14.69% | -3.28% / -24.28% / -8.88% |
| Ladder 500 / 2D analytic / warm | +25.56% / -6.36% / -15.90% | +39.14% / -20.31% / -19.99% |
| Ladder 500 / 3D AD / warm | -1.06% / -7.88% / -7.03% | +3.49% / +17.82% / +9.84% |
| Ladder 2,000 / 2D analytic / cold | +21.99% / -33.25% / -3.25% | +13.66% / -52.14% / +7.76% |
| Ladder 2,000 / 3D AD / cold | -3.99% / -20.72% / -15.12% | -28.03% / -20.93% / -26.91% |
| Ladder 2,000 / 2D analytic / warm | +8.12% / -7.98% / -4.49% | +38.97% / -54.73% / -62.01% |
| Ladder 2,000 / 3D AD / warm | -1.52% / +4.90% / +3.06% | +5.29% / +4.20% / -11.24% |
| Coupled 500 / 2D analytic / cold | -5.32% / +12.35% / -2.59% | -26.15% / +5.78% / -8.86% |
| Coupled 500 / 3D AD / cold | +23.77% / -1.90% / +1.80% | +36.65% / -26.09% / +2.80% |
| Coupled 500 / 2D analytic / warm | -3.94% / -10.05% / -3.25% | -34.79% / +26.06% / -5.89% |
| Coupled 500 / 3D AD / warm | +4.30% / +4.25% / -1.23% | +48.37% / -15.14% / +40.68% |

## Reproduction

The preserved scripts in `../audit-tools/` execute no solver. Run the wrapper with both expected commits, the exact three fixtures, both engines/modes, three rounds, two warmups, seven samples and `--require-qualification --require-complete --require-exact-pairs`. The same audit can read the original directories or a full run archive with job directories restored; per-variant packed archives must be restored before using the generic Reader.

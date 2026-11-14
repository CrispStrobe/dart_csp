# Independent packed-factor small-control evidence review

## Evidence outcome

The independent audit passes with zero integrity/contract findings. All **48 jobs** and **432 requested operations** are complete, including 96 warmups and 336 measured operations. There are **216 exact before/after coordinate and solver-work pairs**.

Physical outcomes: 432 accepted, 0 rejected. No operations are missing, and no timeout, nonzero exit, adapter exception or oracle disagreement is hidden.

Baseline is `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`; candidate is `4325386e689566a903309accd66aca3ced1159f7`. The audit verifies exact source/preparation identities, raw requests and native output, physical-oracle replay, complete sequential job inventory, terminal gates and numerical-work parity. The separate preparation check binds archived source bytes directly to Git blobs.

## Collateral control observations

These 100-coordinate fixtures fall below the default sparse-direct threshold.
Their changed timings are collateral observations, not measured packed-factor
speedups. Five of eight aggregate medians are lower, with no workload weighting.
Warm 2D ladder p50 and p95 increase **25.09% / 25.65%**, each slower in two of
three pairs; cold 2D ladder p50 increases **3.48%**, slower in all three.
Cold 3D ladder p50/p95 increase **5.90% / 5.73%**, despite two favorable pairs.
Warm coupled-100 in 3D has p95 **+24.92%**, slower in two pairs.

Favorable observations include warm coupled-100 in 2D (p50 **-24.31%**, p95
**-15.34%**) and warm 3D ladders (p50 **-4.07%**, p95 **-7.40%**), with both
percentiles improving in all three pairs. The same unchanged numerical work
does not establish the cause of either favorable or adverse elapsed-time
differences. The complete table and individual paired directions remain below.

## Complete timing table

Times are milliseconds per complete build/update, solve and extraction operation. Each displayed value is the median of process percentiles, not a pooled percentile. Positive change means slower candidate time. Paired direction counts are faster/equal/slower.

| Fixture / engine / lifecycle | p50 before → after (ms) | p50 change | p50 pairs | p95 before → after (ms) | p95 change | p95 pairs |
|---|---:|---:|---:|---:|---:|---:|
| Ladder 100 / 2D / cold | 2.845 → 2.944 | +3.48% | 0/0/3 | 3.536 → 3.985 | +12.70% | 1/0/2 |
| Ladder 100 / 2D / warm | 2.348 → 2.937 | +25.09% | 1/0/2 | 3.051 → 3.834 | +25.65% | 1/0/2 |
| Ladder 100 / 3D / cold | 4.783 → 5.066 | +5.90% | 2/0/1 | 5.116 → 5.409 | +5.73% | 2/0/1 |
| Ladder 100 / 3D / warm | 4.415 → 4.235 | -4.07% | 3/0/0 | 4.873 → 4.513 | -7.40% | 3/0/0 |
| Coupled 100 / 2D / cold | 4.182 → 4.176 | -0.14% | 2/0/1 | 5.247 → 5.024 | -4.26% | 2/0/1 |
| Coupled 100 / 2D / warm | 4.970 → 3.762 | -24.31% | 3/0/0 | 6.078 → 5.145 | -15.34% | 3/0/0 |
| Coupled 100 / 3D / cold | 6.717 → 6.131 | -8.73% | 3/0/0 | 7.127 → 6.794 | -4.67% | 2/0/1 |
| Coupled 100 / 3D / warm | 6.875 → 6.725 | -2.18% | 2/0/1 | 7.565 → 9.450 | +24.92% | 1/0/2 |

## Interpretation limits

The design uses 3 alternating process pairs, 2 warmups and 7 measured samples per process. With seven samples, each process p95 is its largest sample and the aggregate p95 is the median of those maxima. These are screening statistics, not stable tail bounds or statistical-significance claims. Ratio-of-process-medians and the majority direction of matched pairs can differ; both are retained above.

Equal coordinate/work outcomes do not establish the cause of elapsed-time differences. The source eliminates per-column numeric factor buffers, but this cohort does not measure total allocated bytes or GC causality. No weighted overall application speedup is inferred. All adverse rows must remain part of any retention decision.

The audit and this summary execute no solver; they ran on CPU 8. Exact raw-native timing vectors, per-process before/after values and all unrounded ratios are in the adjacent timing-details JSON.

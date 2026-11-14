# Independent packed-factor target evidence review

## Evidence outcome

The independent audit passes with zero integrity/contract findings. All **72 jobs** and **648 requested operations** are complete, including 144 warmups and 504 measured operations. There are **324 exact before/after coordinate and solver-work pairs**.

Physical outcomes: 648 accepted, 0 rejected. No operations are missing, and no timeout, nonzero exit, adapter exception or oracle disagreement is hidden.

Baseline is `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`; candidate is `4325386e689566a903309accd66aca3ced1159f7`. The audit verifies exact source/preparation identities, raw requests and native output, physical-oracle replay, complete sequential job inventory, terminal gates and numerical-work parity. The separate preparation check binds archived source bytes directly to Git blobs.

## Findings for retention

Ten of twelve aggregate medians are lower; that count is unweighted across
workloads. The strongest repeated improvements are warm 2,000-coordinate 2D
ladders (p50 **-11.60%**, p95 **-9.31%**) and cold coupled-500 in 3D (p50
**-7.36%**, p95 **-6.71%**): both percentiles improve in all three matched
process pairs for each case. Cold 500-coordinate 2D ladders show a larger
aggregate p50 gain of **19.76%**, but only two of three pairs improve.

The adverse results are material. Cold coupled-500 in 2D has p50 **+9.65%**,
slower in all three pairs, and p95 **+19.68%**, slower in two. Cold
2,000-coordinate 2D ladders have p50 **+4.27%** and p95 **+23.45%**, both slower
in two pairs. Cold 500-coordinate 3D ladder p95 increases **5.68%**. Warm
coupled-500 in 2D has aggregate p95 **+9.20%**, despite two favorable matched
pairs. Warm coupled-500 in 3D shows the reverse directional discrepancy:
aggregate p95 falls **19.43%**, while two of three matched pairs are slower.
All of these observations remain part of the decision; the target cohort
supports a selective improvement, not uniformly lower latency.

## Complete timing table

Times are milliseconds per complete build/update, solve and extraction operation. Each displayed value is the median of process percentiles, not a pooled percentile. Positive change means slower candidate time. Paired direction counts are faster/equal/slower.

| Fixture / engine / lifecycle | p50 before → after (ms) | p50 change | p50 pairs | p95 before → after (ms) | p95 change | p95 pairs |
|---|---:|---:|---:|---:|---:|---:|
| Ladder 500 / 2D / cold | 9.293 → 7.457 | -19.76% | 2/0/1 | 13.880 → 8.615 | -37.93% | 2/0/1 |
| Ladder 500 / 2D / warm | 5.393 → 5.308 | -1.58% | 1/0/2 | 6.053 → 5.688 | -6.03% | 3/0/0 |
| Ladder 500 / 3D / cold | 16.741 → 16.459 | -1.68% | 2/0/1 | 18.960 → 20.037 | +5.68% | 1/0/2 |
| Ladder 500 / 3D / warm | 12.589 → 12.171 | -3.32% | 3/0/0 | 12.733 → 12.643 | -0.70% | 2/0/1 |
| Ladder 2,000 / 2D / cold | 34.031 → 35.484 | +4.27% | 1/0/2 | 41.822 → 51.628 | +23.45% | 1/0/2 |
| Ladder 2,000 / 2D / warm | 26.504 → 23.428 | -11.60% | 3/0/0 | 27.441 → 24.885 | -9.31% | 3/0/0 |
| Ladder 2,000 / 3D / cold | 91.730 → 89.980 | -1.91% | 2/0/1 | 130.641 → 96.940 | -25.80% | 3/0/0 |
| Ladder 2,000 / 3D / warm | 67.512 → 66.129 | -2.05% | 3/0/0 | 75.923 → 73.636 | -3.01% | 2/0/1 |
| Coupled 500 / 2D / cold | 62.650 → 68.693 | +9.65% | 0/0/3 | 80.529 → 96.374 | +19.68% | 1/0/2 |
| Coupled 500 / 2D / warm | 57.748 → 57.648 | -0.17% | 2/0/1 | 60.270 → 65.818 | +9.20% | 2/0/1 |
| Coupled 500 / 3D / cold | 104.781 → 97.069 | -7.36% | 3/0/0 | 117.155 → 109.298 | -6.71% | 3/0/0 |
| Coupled 500 / 3D / warm | 88.446 → 86.687 | -1.99% | 2/0/1 | 116.404 → 93.791 | -19.43% | 1/0/2 |

## Interpretation limits

The design uses 3 alternating process pairs, 2 warmups and 7 measured samples per process. With seven samples, each process p95 is its largest sample and the aggregate p95 is the median of those maxima. These are screening statistics, not stable tail bounds or statistical-significance claims. Ratio-of-process-medians and the majority direction of matched pairs can differ; both are retained above.

Equal coordinate/work outcomes do not establish the cause of elapsed-time differences. The source eliminates per-column numeric factor buffers, but this cohort does not measure total allocated bytes or GC causality. No weighted overall application speedup is inferred. All adverse rows must remain part of any retention decision.

The audit and this summary execute no solver; they ran on CPU 8. Exact raw-native timing vectors, per-process before/after values and all unrounded ratios are in the adjacent timing-details JSON.

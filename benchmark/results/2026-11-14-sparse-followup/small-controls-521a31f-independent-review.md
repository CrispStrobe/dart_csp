# Independent heap below-threshold control review — 2026-11-14

## Evidence finding

The complete control cohort passes the independent source/raw/oracle/process audit and explicit experiment contract with zero findings. It compares exact baseline `c2603a852229897d325a8890ed418319ee8c3572` against heap candidate `521a31f78989cf4706c8f26bb6a2c2ec2709b777`. All source/preparation identities, physical requests, native output, independent oracle verdicts, sequential job records, complete terminal manifests, process percentiles and aggregate ratios reconcile.

All **48 jobs** completed and all **432 operations** were accepted: **336 measured operations and 96 warmups**. Every one of the **216 matched before/after operations** has identical final coordinates and all seven saved work counters. There are zero missing operations, timeouts, nonzero exits, parse failures, adapter exceptions, acceptance disagreements or qualification mismatches. `independent-audit.json` records the checks. Computation ran on CPU 8 with no Dart workload.

## Interpretation

Five of eight aggregate medians are lower. The retained adverse controls are the 100-coordinate 2D ladder cold p95, **3.478061 → 5.193336 ms (+49.32%)**, and its warm p50, **2.305504 → 2.438122 ms (+5.75%)**, with warm p95 **2.871216 → 3.440739 ms (+19.84%)**. Warm 3D ladder/coupled medians also rise by **0.90% / 0.56%**. Every adverse aggregate row has mixed paired directions; that qualification does not erase the observed costs.

Cold 3D ladder improves in all three pairs at both p50 and p95. The largest aggregate median reduction is warm 2D coupled, **-9.41%**, with two faster pairs and one slightly slower pair. Complete values and pair directions are retained below. No sample or process was dropped and this cohort is kept separate from prior-host experiments.

These 100-coordinate fixtures are below the adaptive direct threshold; the changed heap is selected only for direct patterns with at least 256 columns. Their timing differences therefore cannot be described as a measured heap speedup. Exact work/output parity does not explain changes in wall time or exclude compiler-layout effects. No causal attribution is made.

The design has three process pairs and seven measured samples after two warmups. Each process p95 is the largest of seven samples, and the aggregate is the median of three such maxima. This is descriptive screening, not a stable tail bound or a statistical significance claim. Ratio-of-process-medians and individual matched ratios can have different directions; both are shown.

## Complete aggregate table

Times are milliseconds per build/update + solve + extraction operation. Positive changes mean slower candidate time; pair counts are faster/equal/slower.

| Fixture / engine / lifecycle | Before p50 | After p50 | p50 change | Before p95 | After p95 | p95 change | p50 pairs F/E/S | p95 pairs F/E/S |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Ladder 100 / 2D analytic / cold | 2.846820 | 2.840781 | -0.21% | 3.478061 | 5.193336 | +49.32% | 1/0/2 | 1/0/2 |
| Ladder 100 / 3D AD / cold | 4.963973 | 4.773721 | -3.83% | 7.147436 | 5.904685 | -17.39% | 3/0/0 | 3/0/0 |
| Ladder 100 / 2D analytic / warm | 2.305504 | 2.438122 | +5.75% | 2.871216 | 3.440739 | +19.84% | 2/0/1 | 1/0/2 |
| Ladder 100 / 3D AD / warm | 3.912047 | 3.947109 | +0.90% | 4.974981 | 4.860290 | -2.31% | 1/0/2 | 2/0/1 |
| Coupled 100 / 2D analytic / cold | 3.853030 | 3.677347 | -4.56% | 4.704578 | 4.679351 | -0.54% | 2/0/1 | 3/0/0 |
| Coupled 100 / 3D AD / cold | 5.833729 | 5.744918 | -1.52% | 6.343370 | 6.342408 | -0.02% | 2/0/1 | 2/0/1 |
| Coupled 100 / 2D analytic / warm | 3.873330 | 3.508877 | -9.41% | 4.470558 | 3.960790 | -11.40% | 2/0/1 | 3/0/0 |
| Coupled 100 / 3D AD / warm | 5.782224 | 5.814882 | +0.56% | 6.281888 | 6.235277 | -0.74% | 2/0/1 | 2/0/1 |

## Every matched process pair

| Fixture / engine / lifecycle | p50 changes, rounds 1 / 2 / 3 | p95 changes, rounds 1 / 2 / 3 |
|---|---|---|
| Ladder 100 / 2D analytic / cold | -4.02% / +5.19% / +17.83% | -45.87% / +9.88% / +49.32% |
| Ladder 100 / 3D AD / cold | -5.45% / -31.59% / -0.50% | -17.39% / -40.48% / -10.28% |
| Ladder 100 / 2D analytic / warm | -4.65% / -3.10% / +6.72% | -4.96% / +22.29% / +20.15% |
| Ladder 100 / 3D AD / warm | +14.52% / -2.01% / +2.63% | +65.95% / -39.32% / -2.31% |
| Coupled 100 / 2D analytic / cold | -1.58% / -53.68% / +3.28% | -0.54% / -20.08% / -0.61% |
| Coupled 100 / 3D AD / cold | -22.41% / +9.15% / -4.42% | -43.84% / -0.02% / +1.68% |
| Coupled 100 / 2D analytic / warm | -30.01% / -9.97% / +0.49% | -39.74% / -11.40% / -4.91% |
| Coupled 100 / 3D AD / warm | +3.16% / -6.85% / -0.91% | +2.82% / -17.07% / -0.70% |

The adjacent `timing-details.json` preserves exact before/after values for every process pair. Reproduction uses the preserved `../audit-tools/audit_ordering_followup.py` with these two fixtures, both engines and lifecycles, 3/2/7 sampling, and required qualification/completeness/exact-pair flags.

# Independent retention review of the saved final cohort

This review covers the immutable original session `d1244c09828b`: four CG
rounds and three rounds each of default-manifold contraction (`identity`), both
changes (`combined`), and identical-executable control (`aa`). Three missing
round-four blocks are being completed in a later session. They must be reported
as resumed-session corroboration, not silently pooled into the original host
population. No further candidate experiment or timing restart is recommended.

## Recommendation

**Retain fused CG as a scoped optimization for the large iterative solver path,
with explicit adverse small and medium workload results. Revert default-manifold
contraction because its incremental performance benefit is unsubstantiated and
its adverse workload results are repeated.** Retain the meaningful behavioral
regression tests and all raw evidence for both candidates. The resumed blocks
and final retained-source validation remain necessary completion steps.

This judgment uses the previously declared decision boundary: physical
correctness, unchanged work/coordinates, benefit on the code path being changed,
adverse workloads, process order, and bounded replication. There was no numeric
retention threshold. The analyzer's **greater-than-5% in two or more rounds**
flag is a descriptive screen, not a statistical significance test, confidence
interval, or predeclared acceptance gate. Four process pairs do not establish
general nonregression. A/A observations describe variability and cannot be
subtracted from candidate effects or used to dismiss a regression.

## Evidence quality

The independent audit passed for all 13 saved blocks. It checked the fixed
declaration as well as the manifests: six fixtures for each candidate, five
for A/A, both engines, cold and warm modes, eight warmups and 21 measured
operations per process, CPU 0 and 30-second process deadlines. Every expected
process and record was present, all physical checks passed, and process order
matched the harness parity schedule.

| Check | Verified population |
| --- | ---: |
| Solver processes | 600 |
| Measured operations | 12,600 |
| Warmup operations | 4,800 |
| Independent raw geometry checks | 17,400 |
| Recomputed process p50/p95 values | 1,200 |
| Paired comparisons of all non-timing output fields | 8,700 |
| Non-timing output mismatches | 0 |
| Exact restored evidence files | 3,130 |

Archive parts, combined archives, restored file sets and byte hashes match.
Frozen source archives match their Git commits, including library/test trees,
adapter inputs and dependency lock. Actual restored executable bytes match
their manifests; the A/A labels use identical executable and source bytes.
Solver processes and the enclosing blocks do not overlap. All saved blocks
share the recorded environment fingerprint and original session identity.

## Fused CG

The change fuses scalar products into existing vector loops. The strongest
evidence is in the large Laman fixture, which performs about 4,500 linear
iterations per solve. In the 3D engine, both cold and warm p50 improve in every
one of the four balanced rounds and in both process-order strata. The 2D cold
large Laman and 2D cold medium ladder cases also improve in all four rounds.

The following table gives both supported summaries. A ratio of medians and the
median of within-round ratios answer different descriptive questions, so neither
is silently substituted for the other.

| Workload | Median baseline / CG process p50, ms | Change in ratio of medians | Median paired p50 change | Four paired p50 changes |
| --- | ---: | ---: | ---: | --- |
| 3D Laman 500, cold | 260.376 / 225.615 | −13.35% | −10.04% | −18.2%, −7.1%, −13.0%, −3.9% |
| 3D Laman 500, warm | 207.404 / 181.199 | −12.63% | −11.02% | −13.6%, −13.9%, −8.4%, −7.0% |
| 2D Laman 500, cold | 158.328 / 152.682 | −3.57% | −3.58% | −2.7%, −8.4%, −4.4%, −0.9% |
| 2D ladder 25, cold | 6.112 / 5.802 | −5.07% | −6.27% | −7.0%, −1.1%, −9.1%, −5.6% |

For 3D Laman 500, before-first/after-first median paired effects are −15.58% /
−5.49% cold and −10.46% / −11.02% warm. The cold p95 improves in all four rounds;
the warm p95 is mixed (two improve, two regress), despite a median paired p95
change of −3.7%. A/A does not include Laman 500, so there is no corresponding
identical-executable sentinel for that fixture.

Retention entails measurable tradeoffs; the following findings must remain in
the final report:

* **2D tiny-ladder cold p50 is worse in all four rounds**, +9.1%, +40.3%, +9.1%
  and +31.2%. Median process p50 rises from 0.1474 to 0.1835 ms; the median paired
  increase is 20.15% and the ratio-of-medians increase is 24.48%. Before-first
  and after-first strata are both adverse (+35.73% and +9.09%). Its p95 is also
  worse in all four rounds. This path uses QR, so the CG loop edit is not
  directly executed, but that fact does not erase the observed executable
  regression.
* 2D axis-rectangle cold results are strongly order dependent: median paired
  −47.36% before-first versus +289.51% after-first. The overall median paired
  increase is 107.0%. A/A is also variable on that case, but does not establish
  that the candidate regression is measurement noise.
* **3D ladder 25 cold** has a +3.47% median paired p50 change (+3.00% ratio of
  medians), with mixed round effects. One p95 observation is particularly large;
  all tails remain in the raw and per-row report.
* **3D Laman 100 warm** has a +2.66% median paired p50 change and a +14.11%
  ratio-of-medians change (12.859 to 14.674 ms). Both order-stratum median ratios
  are adverse. The different summaries reflect the variable process
  distributions and must both be disclosed.
* 2D Laman 100 cold has a +7.04% median paired p50 increase, while 2D Laman 500
  warm is inconclusive (−0.30% median paired change versus +2.25% ratio of
  medians). The optimization is not a universal medium/large workload gain.

The retention rationale is the repeatable substantial reduction in complete
large iterative operations, with identical numerical outputs and work,
balanced against these explicit costs. It is not an assertion that all solver
workloads improve. Gains in the large sparse-direct ladder fixture should not
be attributed to CG fusion because that fixture does not exercise the changed
iterative loop.

## Default-manifold contraction

The incremental comparison is CG versus CG plus contraction. It does not
establish a stable intended-path improvement across the corpus. Several tiny
case improvements depend on process order. The heavy 3D Laman 500 warm effects
are +9.3%, −1.5%, and +0.4%, providing no clear benefit from this additional
specialization in those saved rounds.

The strongest repeated adverse result is **2D Laman 100 warm**: +32.3%, +14.3%,
and +10.6% p50, with both process-order strata adverse. Median process p50
rises from 6.929 to 8.600 ms, a +24.11% ratio-of-medians change; the median paired
increase is +14.26%. All three p95 observations also worsen, with a +55.9%
median paired increase. The combined endpoint introduces another repeated
adverse result in 3D axis-rectangle warm, with +39.0%, +28.0%, and +39.3% p50.
Combined results are not algebraically composable with the separate pairings
because they are different processes observed at different times.

There are favorable rows, including 3D ladder 500 warm and some small cases,
but they do not support retaining this additional candidate given the repeated
costs and the stated bounded decision rule. A final reversed-order block in
a resumed session may corroborate or conflict with these observations; it
must not replace unfavorable saved rounds or be treated as another observation
from the original session.

## Completion requirements

Finish and checkpoint the three already declared missing blocks, audit them
within their resumed-session boundary, and make the final source decision.
After reverting contraction, verify that the resulting library matches the
frozen CG endpoint and run the necessary final correctness gates with retained
regression tests. Preserve the exact measured-source and retained-source
mapping. No further timing search is needed to manufacture a cleaner headline.

All per-case values, round ratios, tails, order strata and archived input hashes
are retained in `saved-block-audit.json` and `saved-block-audit.md`.

# Independent heap dense-fill reliability review — 2026-11-14

## Finding

The complete reliability cohort is internally consistent, but the constructed-feasible 2,000-coordinate coupled fixture remains **unqualified on both revisions**. All 16 requested operations return `iterationLimit` and fail the independently replayed physical oracle. This retains the existing convergence limit; it does not establish geometric infeasibility and supplies no successful-solve speed comparison.

Baseline is `c2603a852229897d325a8890ed418319ee8c3572`; heap candidate is `521a31f78989cf4706c8f26bb6a2c2ec2709b777`. The experiment uses `laman_free_2000`, both 2D analytic and 3D AD engines, cold/warm lifecycles, one alternating round, no warmups and two requested operations per job. Each solver process has a 20-second deadline.

## Independent accounting

| Outcome | Baseline | Candidate | Total |
|---|---:|---:|---:|
| Completed jobs | 4 | 4 | 8 |
| Requested/reported/validated operations | 8 | 8 | 16 |
| Physically accepted operations | 0 | 0 | 0 |
| Feasible operations rejected with iterationLimit | 8 | 8 | 16 |
| Missing operations | 0 | 0 | 0 |
| Timed-out jobs | 0 | 0 | 0 |
| Adapter errors / oracle disagreements | 0 | 0 | 0 |

All **eight matched before/after operations** have exactly identical coordinates and all seven recorded work counters. All eight jobs complete without deadlines, nonzero exits, parse errors or missing output. The audit independently verifies frozen source/preparation hashes, exact requests and native-output preservation, physical-oracle verdicts, ordered process intervals, full requested/reported operation accounting, terminal manifests and unsuccessful-latency suppression. It reports zero evidence-integrity or experiment-contract findings.

`protocol_ok` is **true** and `qualification_passed` is **false**. All eight variant groups are unqualified. All four paired p50 ratios and all four paired p95 ratios are **null**, as are the successful-latency group medians. Failed-operation durations remain diagnostic data only.

| Engine / lifecycle | Baseline accepted / requested | Candidate accepted / requested | Exact output/work pairs | Successful latency ratios |
|---|---:|---:|---:|---|
| 2D analytic / cold | 0 / 2 | 0 / 2 | 2 / 2 | null |
| 3D AD / cold | 0 / 2 | 0 / 2 | 2 / 2 | null |
| 2D analytic / warm | 0 / 2 | 0 / 2 | 2 / 2 | null |
| 3D AD / warm | 0 / 2 | 0 / 2 | 2 / 2 | null |

## Reproduction and boundary

`independent-audit.json` is the complete report. The preserved `../audit-tools/audit_ordering_followup.py` pins both intended commits, the single fixture, both engines/lifecycles and 1/0/2 sampling, with `--require-complete --require-exact-pairs`. It deliberately omits `--require-qualification` so honest feasible rejection is retained separately from evidence corruption. The underlying reliability auditor independently recomputes the failed qualification gate rather than trusting the saved flag.

This audit ran on CPU 8 and executed no Dart solver or compiler. The faster ordering candidate has not resolved this fixture under the unchanged outer nonlinear budget. No repeated experiment or altered budget is needed merely to preserve that result.

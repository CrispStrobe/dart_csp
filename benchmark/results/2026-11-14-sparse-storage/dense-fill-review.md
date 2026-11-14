# Independent packed-factor dense coupled reliability review

## Outcome

The evidence-integrity and explicit experiment-contract audit passes with zero
findings. The constructed-feasible coupled-2,000 fixture remains **unqualified**
on both baseline `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9` and candidate
`4325386e689566a903309accd66aca3ced1159f7`.

All eight jobs completed and all sixteen requested operations returned
`iterationLimit`. None met the independent physical acceptance criterion.
There are eight exact before/after coordinate and seven-counter solver-work
pairs. No operations are missing, and there are no process timeouts, nonzero
exits, malformed outputs, adapter exceptions or oracle disagreements.

This is the existing local convergence limitation, not evidence that the
constructed-feasible geometry is infeasible. The packed factor layout does not
fix it. Every successful-solve p50/p95 comparison ratio is **null**; elapsed
values in the raw output are diagnostic failed-attempt timings only.

## Complete outcome inventory

| Engine | Lifecycle | Baseline operations | Candidate operations | Exact coordinate/work pairs |
|---|---|---:|---:|---:|
| 2D analytic | Cold | 2 × iterationLimit | 2 × iterationLimit | 2 |
| 2D analytic | Warm | 2 × iterationLimit | 2 × iterationLimit | 2 |
| 3D autodiff | Cold | 2 × iterationLimit | 2 × iterationLimit | 2 |
| 3D autodiff | Warm | 2 × iterationLimit | 2 × iterationLimit | 2 |

## Audit scope

The run uses one alternating round, no warmups and two operations per job, with
both engines and lifecycles. The preserved audit stack verifies the intended
commits, frozen source/preparation identities, raw requests and native output,
recomputed physical-oracle decisions, sequential process inventory, terminal
manifests, exact numerical-work parity and all null successful-solve ratios.
Qualification failure is retained separately from evidence consistency.

`dense-fill-audit.json` contains all per-job outcomes and failure accounting.
Replay the preserved wrapper with the exact source commits, `laman_free_2000`,
both engines/modes, one round, zero warmups, two samples and
`--require-complete --require-exact-pairs`; do not request qualification for
this deliberately separate reliability control. Expected results are
`evidence_consistent: true`, `qualification_passed: false`, zero integrity and
contract findings, and sixteen feasible-case rejections. The audit runs on
CPU 8 and executes no Dart solver.

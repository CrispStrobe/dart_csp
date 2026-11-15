# CG residual-norm experiment closure — 2026-11-15

## Decision and retained source

**Revert the provisional residual-norm fusion and retain the restart repair,
regression tests and all recovered evidence.** Five of the eight mandatory
measurement blocks were recovered from the remote branch. The current recovery
runs in a different session, and the frozen protocol forbids appending timings
from another session, replacing the cohort, or adding rounds to obtain a more
favorable result. Complete declared execution is mandatory for retention;
see the [frozen protocol](../benchmark/results/2026-11-15-cg-norm-fusion/protocol.md),
sections 5 and 6.

The source decision is saved at
[`be69d6a`](https://github.com/CrispStrobe/dart_csp/commit/be69d6a4999508fc464584baad58ccf860352121).
Only `lib/src/geometry/numeric.dart` was restored, byte for byte from baseline
`49234b3d418d6253dd7f377b54650e74e3941372`. The retained library tree is
`16214e4755dbd7df711bfd4901b126990b11ab45`, identical to baseline and main
`46288eb23f04c2a2f2210088fe568285bea6114f`. The test tree remains
`49e4ff78262ce5fd8559ef2b13fdd94164578727`.

This is an incomplete-evidence rejection. The candidate passed its correctness
gates, and the recovered primary timings are favorable. Neither fact overrides
the predeclared completion requirement. No new speedup is retained or claimed.
The previously completed CG dot-product fusion remains intact; its
[separate completed experiment](optimization-final-results-2026-11-14.md) is
not reopened.

All work remains on `perf/optimization-complete-2026-11-14` and
[draft PR #11](https://github.com/CrispStrobe/dart_csp/pull/11). Main has not been
changed and no package release is part of this closure.

## Changes that remain

The restart portability repair replaces a seed-specific speed/restart
assumption with small fixed formulas. Public decisions exercise forced restarts,
saved phase and activity, and learned-clause retention; exhaustive truth tables
check learned clauses against the original solutions. The random-SAT sweep now
checks every returned assignment against every original clause. The prior
mutation checks catch lost phase, lost activity and lost learned clauses.
See the [restart repair evidence](../benchmark/results/2026-11-15-restart-portability/README.md)
for the original failure, diagnosis, implementation and validation.

Three direct numeric contract regressions are retained after reverting the
optimization. They exercise scaled finite norms, first-nonfinite precedence,
completion of later vector writes, callback/budget behavior and finite-entry
norm overflow through the public Jacobian interface. Existing CG equation,
cancellation, ownership and manifold regressions remain. Both the restart and
new numeric files stay in per-PR browser and Node JavaScript/WebAssembly corpora.
There is no production-library difference from current main.

## Recovered measurement inventory

The last reported chat checkpoint was candidate round 2. Remote recovery found
two later completed blocks, including candidate round 3 at `9418d2`. Their
remote presence and saved metadata were independently verified before the
source decision; full raw replay followed. The recovered remote state is saved
at `1e78e3d`; its record distinguishes the new verification time from the
original measurement times.

| Original block | Saved commit | Recovery status |
| --- | --- | --- |
| Candidate round 1 | `8c711fce094a706e441c88ad83657812fa67c0df` | Exact replay passed |
| A/A round 1 | `2b5b3d10631b8b403c0015eee08c254e33b55c3f` | Exact replay passed |
| Candidate round 2 | `4af052ec1959e6d84a19df0e62c9c8d7108ac28a` | Exact replay passed |
| A/A round 2 | `7b0ac7a42d2c78b40561f3f60d8ea33886c7e35e` | Exact replay passed |
| Candidate round 3 | `9418d2284e8eb55a2e9c989fb655788c391cc0a4` | Exact replay passed |
| A/A round 3 | No recovered block | Missing |
| Candidate round 4 | No recovered block | Missing |
| A/A round 4 | No recovered block | Missing |

The original timing session is `b51b355c4f64`; recovery is `398c3b5ac39d`.
No additional solver measurements or qualification runs were executed during
recovery. The status of any output that never reached the remote branch is
unknown; it is not counted as recovered evidence.

| Population | Declared full cohort | Recovered cohort |
| --- | ---: | ---: |
| Blocks | 8 | 5 |
| Processes | 256 | 160 |
| Measured operations | 5,376 | 3,360 |
| Warmups | 2,048 | 1,280 |

## Independent evidence replay

The complete replay and independent review are saved at
[`d2f58bc`](https://github.com/CrispStrobe/dart_csp/commit/d2f58bce2e8041390651b9bde1131c2e1450a4c6).
All 1,248 archived files restore byte for byte. The audit checks preserved
source and executable identities, derived identical-executable A/A inputs,
fixture requests, declared options and process order, original session records,
nonoverlapping collection/packing, geometry and work outcomes, and raw timing
statistics. It also verifies that the candidate's original correctness evidence
was complete before timing began.

All 4,640 recovered measured/warmup records pass the independent physical
checks. All 2,320 paired non-timing records match exactly, and all 320 process
p50/p95 statistics are reproduced from raw samples. There are no recovered
coordinate/work mismatches, timeouts or invalid physical outcomes.

Untimed qualification remains separate: 72 processes and 216 operations,
including 192 accepted feasible outcomes and 24 expected contradictory
rejections. All 108 qualification pairs match outside timing. These records do
not enter the performance summaries.

The frozen full auditor remains unchanged. It exits with the expected missing
measurement-inventory error; it does not certify this as a complete experiment.
The separate recovery wrapper validates only the five available blocks and
explicitly records `retain_allowed: false`, `performance_gates_evaluated: false`
and `overall_decision: revert_incomplete_cohort`. No old decision rule or source
hash was changed to make incomplete evidence pass.

## Descriptive performance observations

The primary endpoint is complete-operation p50 for 3D warm Laman-500. The saved
candidate pairs have the following after/before ratios:

| Round | First process | p50 ratio | p50 change | p95 change |
| --- | --- | ---: | ---: | ---: |
| 1 | Candidate | 0.789322 | -21.07% | -34.02% |
| 2 | Baseline | 0.809443 | -19.06% | -16.60% |
| 3 | Candidate | 0.787007 | -21.30% | -17.39% |

The three-pair median p50 change is **-21.07%**. Separately, the ratio of median
process p50s is **-21.30%**, from 172.102458 to 135.445804 ms. Candidate-first has
two pairs, baseline-first has one; the planned balanced four-pair experiment is
not complete. The two available same-executable A/A primary pairs have a median
p50 change of **+1.43%**. They cannot establish the declared four-round stability
gate, and no A/A value is subtracted from the candidate results.

The [complete partial table](../benchmark/results/2026-11-15-cg-norm-fusion/closure/partial-audit/partial-audit.md)
retains all workloads, process-order strata and per-round p95 observations.
Adverse examples remain explicit: 3D warm `axis_rectangle` has median paired
p50 +17.35%, with opposite signs by process order and round-three p95 +49.51%;
3D warm ladder-25 has round-one p95 +74.41%; 2D cold `axis_rectangle` has
round-two p95 +213.93%. The tiny A/A controls also show large order sensitivity.
These descriptive observations do not establish causality or stable population
tails.

Every process pair has equal weight. Individual samples are not pooled as
independent replications, and sessions are not pooled. The original four-round
benefit, stability, adverse-workload and tail gates are not evaluated on the
partial cohort. The mandatory completion gate alone requires the conservative
source decision.

## Final retained-source validation

Fresh local validation is bound to source `be69d6a` and saved at
[`e6512c3`](https://github.com/CrispStrobe/dart_csp/commit/e6512c323374cc68e9949fc999680112839bb72d).
Native and JavaScript milestones were also saved independently at `62fff99`
and `1358bb2` before final validation completed.

| Gate | Result |
| --- | ---: |
| Formatting | Passed |
| Strict analysis, fatal infos | Passed |
| Focused CG/norm/restart tests | 12 passed |
| Complete native suite | 1,895 passed |
| Node JavaScript corpus | 578 passed |
| Node WebAssembly corpus | 578 passed |
| Solver comparison harness | 51 passed |
| Tooling harness | 27 passed |

There are no skipped tests, timeouts or interruptions. The exact Dart 3.14.0
SDK ZIP and executable hashes match the pinned inputs, and `pub get
--enforce-lockfile` preserves the canonical dependency lock. Source snapshots
are identical before and after all gates. The complete 23-file validation
bundle restores exactly, including logs, commands, lock, corpus and snapshots.
See the [final validation manifest](../benchmark/results/2026-11-15-cg-norm-fusion/closure/final-validation-manifest.json)
and [independent validation review](../benchmark/results/2026-11-15-cg-norm-fusion/closure/final-validation-review.json).

Fresh GitHub CI is tracked separately in
[run 43685263894](https://github.com/CrispStrobe/dart_csp/actions/runs/43685263894).
At this documentation checkpoint it is still in progress; the final-source
browser job is `132724307900`. Earlier candidate browser passes do not substitute
for a final-source browser pass. The per-PR browser job covers the targeted
corpus; the full-browser job is schedule/manual only and is skipped for this PR.

## Replay and future continuation

Run the saved recovery wrapper from the repository root using new, empty scratch
paths. It restores frozen inputs and the five original blocks, executes no
solver and does not authorize retention:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 \
  benchmark/results/2026-11-15-cg-norm-fusion/closure/evidence_replay.py \
  --repo "$PWD" \
  --workspace /ABSOLUTE/NEW/norm-replay \
  --out /ABSOLUTE/NEW/norm-replay-report
```

The machine-readable report is `partial-audit.json.gz`. Its checksum manifest
binds report files and the reusable wrapper separately; an archived executed
wrapper preserves the original replay's provenance. The frozen full auditor's
failure is saved alongside the successful available-evidence replay.

Restore final correctness evidence without rerunning tests:

```sh
python3 tool/pack_optimization_evidence.py restore \
  benchmark/results/2026-11-15-cg-norm-fusion/closure/validation-final-evidence.json \
  /ABSOLUTE/NEW/norm-final-validation
```

Read `progress.json`, this report and `HANDOVER.md` before continuing. The cohort
is closed: do not append the three missing blocks, invent their results, reuse
a new session label as if it were the original session, or reinstate the
candidate from partial timings. The candidate source and favorable/adverse
observations remain available for review without changing the declared outcome.

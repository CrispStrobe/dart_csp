# Completed CG optimization decision — 2026-11-14

## Retained source and decision

Retain the fused conjugate-gradient reductions from `ad8d237` and remove the
default-manifold contraction experiment. The source decision is saved at
`6d0c0bc4ea8f19b4b76b0be243e58f7d8b1ceec7` on
`perf/optimization-complete-2026-11-14`.

The retained library tree is `16214e4755dbd7df711bfd4901b126990b11ab45`.
It is byte-identical to both the measured CG endpoint `ad8d237` and current
main `46288eb`. CG was already provisionally on main; this work completes its
qualification and retention decision. The timings below compare it with the
packed **pre-CG baseline `080e0fe`**, not with current main.

The 15 default-manifold regression tests remain, together with the existing
four CG regressions and portable test registrations. The final test tree is
`b0fae52c00e64741ea8b0202bea28c2f2d2617e1`. Relative to current main, the final
branch adds the manifold test file, evidence, recovery/audit tooling and
documentation; it has no production-library delta. No main-branch merge or
package release is part of this continuation.

| Candidate | Decision | Reason |
| --- | --- | --- |
| Fused CG vector passes | Retain | Repeatable large iterative-case p50 gains in every original-session round and both process orders, with identical work and coordinates; explicit small/medium tradeoffs accepted |
| Default-manifold contraction | Revert | Incremental benefit remains inconsistent and repeated adverse workloads persist; correctness alone does not justify this specialization |
| Argument placeholders | Remain inactive | History and review preserved; no new evidence overturns the earlier rejection |
| QR permutation experiment | Remain inactive | Rejected experiment and its evidence preserved without restoring its source |

The [source review](../benchmark/results/2026-11-14-optimization-finish/source-review.md),
[independent retention review](../benchmark/results/2026-11-14-optimization-finish/retention-review.md)
and [machine-readable decision](../benchmark/results/2026-11-14-optimization-finish/retention-decision.json)
record the implementation and evidence mapping.

## What the retained optimization does

Four CG dot-product reductions are accumulated during existing vector passes:
initial preconditioning, matrix-vector multiplication, true-residual restart,
and subsequent preconditioning. This avoids extra traversals of solver vectors.
Each reduction retains its ascending index order, operand order, positive-zero
initialization and typed-array reads. Original-equation checks, physical
tolerances, solver selection, work budgets, cancellation polling and result
ownership remain unchanged.

The rejected experiment specialized ambient-to-tangent contraction for a
private subtype used by default Euclidean manifolds. Restoring `solver.dart`
from `46288eb` removes that specialization and its private subtype. All manifolds
again use the existing generic contraction. The tests retain coverage for
nonfinite rejection, retained backend-buffer writes, scaling and signed zero,
custom maps and callback mutation, AD, cancellation, forks and recovery.

The CG tests do not explicitly establish execution of the true-residual restart
branch. Source review verifies the same arithmetic-order argument there; this
coverage limit is retained rather than presented as a new test result.

## Recovery and exact experiment population

Recovery started at `120b617`, beyond the checkpoint in the interrupted chat.
All **42 current branch heads and ten original PR heads** were fetched and
verified as ancestors. All ten PRs were already merged. The old squash-equivalent
PR #1/#2 heads had been preserved as additional parents at `b0820ed`; no further
production merge was necessary. The exact observed refs and CI boundaries are
in [the remote audit](../benchmark/results/2026-11-14-optimization-finish/remote-ref-audit.json).

The preceding session `d1244c09828b` saved 13 blocks: CG rounds 1–4, plus
identity, combined and identical-executable A/A rounds 1–3. Session
`b51b355c4f64` completed only the three missing round-four blocks, in the
declared order. Earlier observations were neither replaced nor pooled into
the resumed timing distributions. No new cohort or favorable-sample selection
was introduced after observing results.

| Population checked independently | Original session | Resumed session | Total |
| --- | ---: | ---: | ---: |
| Declared timing blocks | 13 | 3 | **16** |
| Sequential processes | 600 | 136 | **736** |
| Measured operations | 12,600 | 2,856 | **15,456** |
| Warmup operations | 4,800 | 1,088 | **5,888** |
| Accepted raw geometry records | 17,400 | 3,944 | **21,344** |
| Recomputed process p50/p95 values | 1,200 | 272 | **1,472** |
| Equal paired non-timing records | 8,700 | 1,972 | **10,672** |
| Byte-exact restored archive members | 3,130 | 710 | **3,840** |

All physical checks passed, with **zero paired coordinate, work-counter or
other non-timing mismatches**. Archive parts, archive membership, every restored
member, executable bytes, source/dependency/adapter provenance, fixed workload
populations, process order and non-overlap were checked independently.

Three disjoint protocol selections pass: original CG rounds 1–4; original
identity/combined/A/A rounds 1–3; and resumed identity/combined/A/A round 4.
Each report correctly has `full_protocol: false`. All declared blocks are
complete **across two sessions**; a complete sixteen-block single-session
experiment is not claimed. The auditor's default remains strict. Its explicit
start-round option supports the resumed subset without changing a historical
manifest or weakening fixture, hash, session or process checks.

Both sessions use the exact saved Dart 3.14.0 AOT executables, eight warmups,
21 measured operations, CPU 0, sequential before/after processes with balanced
order, and 30-second process deadlines. The three candidate comparisons use
six fixtures, two engines, and cold/warm lifecycles. A/A uses the predeclared
first five fixtures and the same baseline executable on both sides.
Compilation, tests, restoration, packing and independent audit stay outside
timed collection. The SDK and dependency lock are hash pinned.

## CG gains and accepted costs

These are complete operation timings, covering build/update, solve and
extraction. Process startup, JSON serialization and the independent physical
oracle are outside the measured operation. The following table uses only the
four original-session CG pairs. Each p50 column is the median of four process
p50 values; it is not a percentile pooled over all raw samples. The percentage
column is the ratio of those medians. Median paired effects are also shown
because they answer a different question when process distributions vary.

| Fixture and lifecycle | Baseline / CG median process p50, ms | Ratio-of-medians change | Median paired change |
| --- | ---: | ---: | ---: |
| `laman_free_500`, 3D AD, cold | 260.376 / 225.615 | **−13.35%** | **−10.04%** |
| `laman_free_500`, 3D AD, warm | 207.404 / 181.199 | **−12.63%** | **−11.02%** |
| `ladder_25_components_1`, 2D analytic, cold | 6.112 / 5.802 | −5.07% | −6.27% |
| `ladder_3_components_1`, 2D analytic, cold | 0.1474 / 0.1835 | **+24.48%** | **+20.15%** |
| `ladder_25_components_1`, 3D AD, cold | 9.618 / 9.907 | +3.00% | +3.47% |
| `laman_free_100`, 3D AD, warm | 12.859 / 14.674 | **+14.11%** | **+2.66%** |

The 500-free-coordinate 3D coupled case improves in every round. Its cold
p50 changes are −18.2%, −7.1%, −13.0% and −3.9%; warm changes are −13.6%,
−13.9%, −8.4% and −7.0%. Both process-order strata improve. The reduction in
median process p50 is about 34.76 ms cold and 26.20 ms warm.

The small cold 2D ladder also worsens in **every** round: +9.1%, +40.3%,
+9.1% and +31.2%, an increase of about 0.0361 ms in the median process p50.
Its before-first and after-first strata both worsen, and all four p95 values
are higher. This fixture takes the QR path, but the absence of executed CG
arithmetic does not erase the measured executable regression. The retention
decision accepts this cost for the repeated large iterative-case benefit.

Other caveats matter. Small rectangle cold results are strongly order-dependent.
The 2D Laman 100 cold median paired change is adverse. The 2D Laman 500 warm
result is inconclusive. Large 3D warm p95 improves in two pairs and worsens in
two. A material single-round tail remains: 3D ladder-25 cold p95 rises from
10.694918 to 130.222576 ms in round 1 (+1117.61%); the other three changes are
+8.73%, −6.02% and +9.23%. This is an adverse observation, not a stable
twelvefold regression claim. Sparse-direct ladder results must not be attributed to an iterative-loop
optimization when that loop does not execute. The full favorable and adverse
matrix, individual rounds, tails and process-order strata are in
[the original-session report](../benchmark/results/2026-11-14-optimization-finish/saved-session-audit.md)
and its lossless JSON companion.

There is no A/A sentinel for `laman_free_500`. A/A shows substantial observed
variation on covered cases; it cannot establish that a candidate regression is
noise. No A/A correction is subtracted. Four process pairs are descriptive
evidence, not a universal performance guarantee or an application-weighted
speedup. The analyzer's repeated-greater-than-5% flag is a descriptive warning,
not a significance test or a newly imposed retention threshold.

## Why the default-manifold specialization was removed

The original-session incremental comparison is CG versus CG plus contraction,
with three pairs. For `laman_free_100`, 2D analytic warm p50 worsens by
32.3%, 14.3% and 10.6%, with both process orders adverse. Median process p50
rises from 6.929 to 8.600 ms: +24.11% by ratio of medians, or +14.26% by median
paired ratio. All three p95 observations also worsen; their median paired
increase is +55.9%.

Some 3D ladder and small-case observations improve, but several gains reverse
with process order. The intended large 3D Laman 500 warm case changes by
+9.3%, −1.5% and +0.4%, providing no consistent incremental benefit. The
combined endpoint also repeatedly worsens 3D rectangle warm p50. Separate
comparisons occur in different processes and cannot be composed algebraically.

The resumed fourth block remains a separate sensitivity check. It again slows
2D Laman 100 warm (+4.16% p50 / +17.23% p95), 3D large-ladder warm
(+11.18% p50), and 3D Laman 500 cold (+4.35% p50), while other rows improve.
These observations do not reverse the decision. See
[the resumed-session report](../benchmark/results/2026-11-14-optimization-finish/resumed-session-audit.md).

## Final-source correctness

All final-source gates passed and are saved at
`9b3c4d1c29f1d7e9cea9d821ae01d040d687a7b5`:

| Gate | Observed result |
| --- | --- |
| Formatting of the two numerical files and two retained regression files | Passed, without modifying files |
| Static analysis with `--fatal-infos` | Passed |
| Full native test suite | **1,891 passed**, no skips |
| Node JavaScript, exact 54-file portable corpus | **570 passed**, no skips |
| Node WebAssembly, the same portable corpus | **570 passed**, no skips |
| Python solver-comparison harness | **51 passed**, no skips |
| Python tooling, including archive and session-protocol regressions | **27 passed**, no skips |

The working library is verified byte-for-byte against `ad8d237`, and the
retained test tree against `545a1ab`. Source inputs did not change during the
gates. The canonical dependency lock stayed unchanged, and the Dart SDK archive,
compiler and relevant runtime identities were verified. All 28 manifested log
and input files match their saved byte counts and SHA-256 hashes.

Complete commands, timeouts, expected/observed test counts, the exact portable
corpus, source snapshots, compiler/dependency identities and logs are in
[the validation manifest](../benchmark/results/2026-11-14-optimization-finish/validation/validation-manifest.json).
The copied runner journals each gate and retains failures rather than retrying
them. These portable results execute compiled code under Node; they do not
claim a new full real-browser suite. Historical main CI is reported separately
in the remote audit.

## Durable checkpoints and replay

| Checkpoint | Preserved result |
| --- | --- |
| `2b7d01e` | Fresh ref audit, exact restored binaries, explicit session boundary and bounded audit support |
| `7ddf242` | Identity round 4 and independent audit of the saved 13 blocks |
| `ff0cb5f` | Combined round 4, including complete raw observations |
| `9904954` | Final A/A round; all 16 declared blocks saved |
| `6d0c0bc` | Final source decision, restored generic contraction and complete separate-session audits |
| `f2e9acf` | Final-source formatting, analysis and 1,891 native passes with pinned validation inputs |
| `1a3d026` | All 570 JavaScript passes on the retained source |
| `9b3c4d1` | Complete final-source native, JavaScript, WebAssembly and both harness gates |

Every checkpoint used an expected-head update, verified matching Git blob/tree
identities and a readback of the remote branch before the next timing block.
Earlier raw archives and preparation inputs remain in their original directories.
The [completion evidence directory](../benchmark/results/2026-11-14-optimization-finish/README.md)
links the final state; its machine-readable progress record names the next step
until completion.

To replay, first restore `prepared-evidence.json` from the optimization-recovery
directory with `tool/unpack_benchmark_evidence.py`. Restore the 13 original
compact archives from optimization-final and the three round-four archives
from optimization-finish with `tool/pack_optimization_evidence.py restore`, each
into a distinct `<workspace>/runs/<block-name>` directory. Preparation manifests
belong at `<workspace>/prepared-{cg,identity,combined,aa}`.

Run `audit_saved_blocks.py` with explicit `--repo`, `--prepared`, `--runs` and
`--out` arguments. `--prepared` names the common workspace parent containing
the four `prepared-*` directories. Run `audit_resumed_blocks.py` with the same roots,
`--saved` pointing to optimization-finish, and `--original-audit` pointing to
the decompressed saved-session JSON. Give the resumed auditor a fresh output
directory: it restores and verifies archive members under `--out/restored/`.
Run the protocol auditor separately for
CG rounds 1–4, the other original rounds 1–3, and resumed rounds 4–4. The last
selection uses `--cohorts identity,combined,aa --start-round 4 --rounds 1`.
The first two selections use `--saved` pointing to optimization-final; the
last uses `--saved` pointing to optimization-finish.
This verifies the recorded populations without pretending the session break
did not occur. None of these replay audits executes a solver or collects new
timings.

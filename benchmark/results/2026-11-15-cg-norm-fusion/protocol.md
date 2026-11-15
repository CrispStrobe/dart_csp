# Predeclared CG residual-norm experiment — 2026-11-15

**Adopted before timing.** The restart repair is saved at
`49234b3d418d6253dd7f377b54650e74e3941372`; focused native/JS/Wasm gates and
analysis pass. Its real-browser CI gate must pass before timed collection.
The candidate is being prepared and reviewed in isolation; no candidate timing
has run. Source and executable identities will be bound in `declaration.json`
and saved remotely before collection. The prior CG/manifold experiment remains
complete and separate. Commands below use placeholders for the frozen paths.

## 1. One source change and its exact contract

Fuse the overflow-resistant `geometryNorm(r)` reduction into the immediately
preceding CG loop that updates `x[i]` and `r[i]`. Preserve the current scaled
sum-of-squares arithmetic, ascending index order, and readback from the stored
Float64List element. Preserve the result of the first nonfinite absolute
residual while completing all remaining iterate/residual updates. Initial norm,
original-system verification/restart, all Jacobian virtual calls, work limits,
polling cadence, input/result ownership and backend choices remain unchanged.
No RHS reuse, CSR normal-product fusion, dispatch threshold or other optimization
is included in this source pair.

Current evidence justifies this target: Laman 500 records about 4,500 linear
iterations per complete operation. This change removes one column-length pass
per CG iteration. It is not an allocated-byte claim or a measured percentage
attribution from the older JIT/GC profiles.

## 2. Required behavioral regressions

Retain the existing mixed, unsorted, duplicate-column CSR original-equation
oracle in `test/geometry_cg_test.dart`, its cancellation-at-every-iterate check,
nested-solve ownership check and pre-update nonfinite-dot precedence check.
Those tests are useful and do not need to be copied or rewritten.

Add persistent public-contract cases covering the newly moved norm computation.
A one-off differential check against frozen baseline source may supplement
these cases in saved evidence; copied solver implementations will not become
permanent unit-test support. Required coverage:

1. **Finite fast path:** retain the existing independent original-equation
   oracle on a coupled, full-rank CSR system with nonuniform damping and
   multiple iterations. New norm probes compare the stored residual's public
   `geometryNorm` with the fused result for zero, subnormal, mixed-sign and
   widely separated finite values. An additional one-off compatibility sweep
   compares exact results and public method/callback traces against frozen
   pre-fusion CG across 648 declared CSR/budget/scale cases. This copied
   baseline is compatibility evidence, not an independent mathematical oracle
   or a claim that every CG branch executes.
2. **First infinity followed by NaN:** deliberately exercise a first-iteration
   update whose residual has `-Infinity` before `NaN`. The norm must report
   `Infinity`, while every step element—including those after the first bad
   residual—is updated. Expect numerical failure at completed iteration 1.
3. **First NaN followed by infinity:** reverse the first two positions. The norm
   must report `NaN`; a later infinity must not replace the first nonfinite
   result. Again all step entries must be updated before failure returns.
4. **Callback/budget precedence:** on the same adversarial setup, an iteration-top
   stop returns cancellation with iteration count 0 and untouched zero step;
   a zero iteration budget takes the existing original-system residual path.
   Reentrant callbacks must leave retained results and callback counts intact.

The persistent public-Jacobian probe retains the initial transpose output
buffer and modifies selected residual coordinates at the next public method
boundary, after the search direction is formed. A final active column still
requires an update after any injected nonfinite prefix. The tests check explicit
method order, poll count, first nonfinite result, every residual coordinate and
that final nonzero step. This exercises existing extensibility with no private
solver access and detects a premature failure return from the fused loop.

Run focused CG/numeric/sparse tests, strict analysis and formatting, then the
full native and existing Node JS/Wasm corpus. Include the new regression file
in portable and browser coverage. Obtain the repaired browser gate separately.
Any arithmetic, cancellation, virtual-call, ownership or work-bound mismatch
rejects the candidate before performance collection.

## 3. Freeze new artifacts

Record `BASELINE_SHA` (retained source after browser repair), `CANDIDATE_SHA`,
library/test trees, exact Dart 3.14.0 executable digest, canonical dependency
lock, adapter/harness/oracle hashes and the current session identifier. Both
worktrees must have committed tracked source and resolve their own package.
The baseline must contain the same benchmark adapter and dependency lock as the
candidate. No dependency upgrade is part of the experiment.

From the repository root, prepare once:

```bash
python benchmark/solver_comparison/paired_dart_backends.py prepare \
  --before BASELINE_WORKTREE \
  --after CANDIDATE_WORKTREE \
  --dart PINNED_DART_PATH \
  --build-timeout 300 \
  --out NEW_WORKSPACE/prepared-norm
```

Derive `NEW_WORKSPACE/prepared-aa` from **the exact already-built before
executable** in `prepared-norm`; copy that executable/source archive under both
labels and copy both variant records from the baseline variant, updating only
relative artifact paths. Preserve the source build provenance and declare the
derived-manifest source hash. The existing `derive_preparation` implementation
in `tool/run_optimization_completion.py` provides the established construction
pattern, but do not import/run that Actions-only driver: it is tied to old refs
and workflow environment variables. Check identical executable and source
archive hashes under the two A/A labels. Do not separately compile A/A labels.

Preserve both actual executables, source archives, manifests and build logs
remotely before qualification/timing. Previously frozen CG/manifold binaries
remain historical inputs; do not relabel them as new-source artifacts.

## 4. Untimed physical qualification

Use the existing independent physical oracle and contradictory fixture without
changing tolerances or selecting different backends:

```bash
python benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared NEW_WORKSPACE/prepared-norm \
  --purpose qualification --variants before,after \
  --suites smoke,confirm,coupled \
  --fixtures canonical_cell,axis_rectangle,coincidence,contradictory_distance,ladder_3_components_1,ladder_1_components_1_scale_1e-06,ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --start-round 0 --warmups 1 --samples 2 \
  --timeout 30 --cpu 0 \
  --out NEW_WORKSPACE/qualification
```

This is 72 processes / 216 operations, including 24 expected contradictory
rejections. Require complete jobs and exact expected physical outcomes for both
endpoints. Qualification timings do not enter performance summaries.

## 5. Minimal decision matrix and collection commands

| Fixture | Purpose |
| --- | --- |
| `laman_free_500` | Expensive CG fallback; 3D warm is the primary endpoint |
| `ladder_25_components_1` | Medium CG path and crossover tradeoffs |
| `ladder_500_components_1` | Admitted sparse-direct untouched control |
| `axis_rectangle` | Tiny QR untouched control and order sensitivity |

Use both engines and cold/warm modes for every fixture. Candidate and A/A use
the **same four-fixture matrix**, including Laman 500. There are 32 processes
per block, four rounds per comparison, eight blocks total: **256 processes,
5,376 measured operations and 2,048 warmups**. No new fixtures, rounds or retries
may be added based on the observations. If the environment is interrupted, save
the partial cohort and make a conservative decision; do not silently pool
another session or restart a favorable replacement cohort.

Freeze the block order:

`norm-r1, aa-r1, norm-r2, aa-r2, norm-r3, aa-r3, norm-r4, aa-r4`.

For zero-based `R=0,1,2,3`, the candidate block command is:

```bash
python benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared NEW_WORKSPACE/prepared-norm \
  --purpose measurement --variants before,after \
  --suites smoke,confirm,coupled \
  --fixtures axis_rectangle,ladder_25_components_1,ladder_500_components_1,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --start-round R --warmups 8 --samples 21 \
  --timeout 30 --cpu 0 \
  --out NEW_WORKSPACE/runs/norm-roundN
```

`N=R+1`. The corresponding A/A command is identical except `--prepared
NEW_WORKSPACE/prepared-aa` and `--out NEW_WORKSPACE/runs/aa-roundN`. The existing
harness alternates pair order using round/fixture/mode/engine parity; record
that complete schedule before execution and verify it independently. CPU 0 is fixed for this session; the observed allowed-affinity set is
`[0,1,2,3,4,5,6,7,8]`. The collector must fail if CPU 0 becomes unavailable.

Execute one block at a time with a 900-second outer bound. Preserve partial
output and terminate the process group on timeout. After each block, check
`protocol_ok`, `qualification_passed`, all expected job/record populations and
raw physical outcomes; pack with the established compact packer:

```bash
python tool/pack_optimization_evidence.py pack \
  NEW_WORKSPACE/runs/norm-roundN NEW_EVIDENCE_DIRECTORY norm-roundN
```

Save summary, status/session/declaration hashes, logs and all archive parts.
Verify the remote ref before starting the next block. Pause compilers, tests,
compression and heavy audits while solver processes collect timings.

## 6. Predeclared decision rule and A/A diagnostic gate

These engineering margins are frozen by this declaration **before candidate
timing**. They will not be changed in response to observations:

* Primary endpoint: **3D Laman 500 warm complete-operation p50**. Require median
  paired after/before ratio at most `0.95`, improvement in both process-order
  strata, and improvement in at least three of four individual pairs.
* Primary A/A stability gate: its median paired ratio must lie within
  `[0.95,1.05]` and each process-order stratum's median ratio within `[0.90,1.10]`.
  Failure means the benefit is not sufficiently substantiated in this bounded
  environment; reject the candidate without additional runs. This gate is
  diagnostic and does not turn an A/A range into a confidence interval.
* Reject a greater-than-5% median paired slowdown on another CG target cell
  when both order strata are also slower by more than 5%. Reject an untouched
  control's greater-than-10% median paired slowdown when both order strata
  exceed 10%. Candidate regressions are not subtracted or excused using A/A.
* Record all per-round p95 observations. Reject a target's p95 ratio exceeding
  `1.25` in at least three rounds, including both order strata. Short-cohort
  p95 estimates remain descriptive, not reliable population tail bounds.
* Correctness, raw coordinate/work equality, source identity and declared
  protocol completion are mandatory regardless of timing. If benefit remains
  uncertain, revert the candidate; retain tests and all evidence. No new
  optimization is folded into this experiment.

Report both median paired ratios and ratios of median process percentiles,
clearly labeled. Give process pairs equal weight; do not pool the 21 individual
operations across processes to claim independent replication or significance.

## 7. Reuse and audit boundary

Reuse the existing CSR/CG tests, physical corpus/oracle, paired AOT preparation
and collector, exact archive packer/restorer, percentile definitions, raw
work/coordinate comparison, and source-provenance audit functions. The reusable
raw analyzer can process the new names with `--cohorts norm,aa --rounds 4`:

```bash
python benchmark/results/2026-11-14-optimization-recovery/analyze_recovery.py \
  --repo . --runs NEW_WORKSPACE/runs \
  --cohorts norm,aa --rounds 4 --out NEW_WORKSPACE/audit
```

It must be supplemented by an independent check against this new four-fixture
declaration and frozen endpoint hashes. Do **not** weaken or repurpose
`tool/audit_optimization_protocol.py`: its exact old endpoints and 16-block
declaration protect immutable historical evidence. Similarly, the old
`run_optimization_round.py` hardcodes the former comparison names and matrix;
reuse its process-group/partial-checkpoint pattern in a separate small driver
instead of changing the old historical experiment.

Checkpoint the final explicit retain/revert decision, preserved raw observations
and final retained-source correctness evidence on the authorized branch.

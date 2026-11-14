# Packed sparse factor storage evidence

Baseline: `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`.
Frozen candidate: `4325386e689566a903309accd66aca3ced1159f7`.

Start with [the final results and retention decision](../../../doc/sparse-storage-results-2026-11-14.md).
The packed source is retained with explicit adverse target, small-control and
CAD/QR observations. The [plan](../../../doc/sparse-storage-followup-2026-11-14.md),
[code review](../../../doc/sparse-storage-code-review-2026-11-14.md) and
[retention review](../../../doc/sparse-storage-retention-review-2026-11-14.md)
record the scope and decision. All eight completed cohorts/archives are saved
incrementally to remote main; no timing cohort remains unfinished.
`validation-summary.json` indexes the seven successful validation gates and their
complete logs in `validation-4325386-evidence.json`.

## Verify preservation without running a solver

```sh
python3 benchmark/results/2026-11-14-sparse-storage/verify_evidence.py
```

The saved `archive-verification.json` passes eight archives, all 47 ordered
parts, all 919 regular members and 170 additional cross-reference checks. The
verifier also reconstructs source library/test Git trees from archived bytes,
matches complete validation logs and reported test counts, and compares the
standalone CAD summaries/scripts to their archived originals. This is a local
content-integrity check, not a claim about current GitHub branch status.

## Restore exact evidence

`*-evidence.json` manifests record exact archive membership, every member hash,
the whole archive hash and (when split) the ordered part hashes. Restore to new
directories with the existing verification helper:

```sh
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/preparation-4325386-evidence.json \
  /path/to/new/prepared
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/qualification-4325386-evidence.json \
  /path/to/new/qualification
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/audit-tools-evidence.json \
  /path/to/new/audit-tools
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/targets-4325386-evidence.json \
  /path/to/new/targets
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/small-controls-4325386-evidence.json \
  /path/to/new/small-controls
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/dense-fill-4325386-evidence.json \
  /path/to/new/dense-fill
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/cad-controls-4325386-evidence.json \
  /path/to/new/cad-controls
python3 tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-sparse-storage/validation-4325386-evidence.json \
  /path/to/new/validation
```

Each destination must be new. The helper checks the complete manifest before
writing any restored member. Split archives have no separate unsplit file;
their manifests specify the exact part order and whole-archive digest.

| Restored directory | Regular members | Role |
|---|---:|---|
| prepared | 12 | Source snapshots, compiler/build identities and successful logs |
| audit-tools | 6 | Preserved sparse physical/provenance audit stack |
| qualification | 186 | Complete correctness-only physical cohort |
| targets | 370 | Complete 72-job large-target comparison |
| small-controls | 250 | Complete 48-job below-threshold controls |
| dense-fill | 50 | Complete eight-job convergence-limit control |
| cad-controls | 19 | Full raw 36-report JIT/AOT screen and audits |
| validation | 26 | All seven correctness gates, logs and hashes |

Temporary AOT binaries are omitted from the preparation archive; their exact
hashes, successful build logs, compiler identities and frozen source/dependency
inputs remain. Saved audits verified the original binaries while present.
Rebuilding is required for new runs and does not reproduce historical timings.
The supplementary `audit-tools/check_preparation.py` actual-byte checks require
the recorded SDK and both original AOT binaries to be present; its passing
`preparation-independent-check.json` is preserved. Source-only replay cannot
repeat those binary-byte checks. The core sparse audit stack can inspect the
retained source archives and raw physical outputs without rerunning the solver.

The qualification review describes the exact 36-job inventory and how to replay
the independent audit. Qualification timings were collected concurrently with
other correctness gates and must not be treated as controlled comparisons.

The target cohort has 72 jobs / 648 operations; below-threshold controls have
48 jobs / 432 operations. Both use three alternating process pairs, two warmups
and seven measured operations per process. Raw outputs and every process remain
in their manifests and archives, including adverse timing observations. Their
comparison JSON files are summaries of their own cohorts, not pooled historical
observations. Each process p95 is its largest of seven measured samples.

## Replay the sparse physical and timing audits

From a checkout with both exact commits available, use the restored audit stack
and preparation directory. The wrapper loads its adjacent preserved scripts,
replays the physical oracle from raw numerical output, recomputes timings and
checks the requested source/cohort contract. These commands run no Dart code.
Substitute your checkout and newly restored directory for the following paths:

```sh
storage_repo=/path/to/dart_csp
storage_replay=/path/to/new
storage_before=d43a8b0fca74c6bc893d68ca6ec8190e74b423c9
storage_after=4325386e689566a903309accd66aca3ced1159f7
storage_audit=(python3 "$storage_replay/audit-tools/audit_ordering_followup.py"
  --repo "$storage_repo" --prepared "$storage_replay/prepared"
  --expected-before "$storage_before" --expected-after "$storage_after"
  --expected-engines dart_2d_analytic,dart_3d_ad --expected-modes cold,warm)

"${storage_audit[@]}" --run "$storage_replay/qualification" \
  --expected-variants after \
  --expected-fixtures canonical_cell,axis_rectangle,coincidence,contradictory_distance,ladder_3_components_1,ladder_1_components_1_scale_1e-06,ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --expected-rounds 1 --expected-warmups 1 --expected-samples 2 \
  --require-qualification --require-complete \
  --output "$storage_replay/qualification-audit.json"

"${storage_audit[@]}" --run "$storage_replay/targets" \
  --expected-fixtures ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --expected-rounds 3 --expected-warmups 2 --expected-samples 7 \
  --require-qualification --require-complete --require-exact-pairs \
  --output "$storage_replay/targets-audit.json"

"${storage_audit[@]}" --run "$storage_replay/small-controls" \
  --expected-fixtures ladder_25_components_1,laman_free_100 \
  --expected-rounds 3 --expected-warmups 2 --expected-samples 7 \
  --require-qualification --require-complete --require-exact-pairs \
  --output "$storage_replay/small-controls-audit.json"

"${storage_audit[@]}" --run "$storage_replay/dense-fill" \
  --expected-fixtures laman_free_2000 \
  --expected-rounds 1 --expected-warmups 0 --expected-samples 2 \
  --require-complete --require-exact-pairs \
  --output "$storage_replay/dense-fill-audit.json"
```

The dense control intentionally omits `--require-qualification`: all sixteen
constructed-feasible operations returned `iterationLimit`. Its evidence passes
integrity checks, but successful-solve ratios remain null. Do not relabel those
failed local solves as infeasibility or successful timing improvements.

The standalone `summarize_storage_timings.py` derives full non-pooled target,
small-control and failed-attempt timing detail from restored outputs. The
saved reviews include all individual paired directions and adverse observations.

## Replay CAD/QR controls

Restoring `cad-controls` supplies the exact uncompressed `raw.json`, all audit
scripts, summaries, command records and logs. Follow the reproduction commands
in [the control review](cad-controls/independent-review.md); optional live
worktree checks require matching source/package inputs. The source auditor
also uses the repository Git object database to compare recorded library and
harness hashes to the exact committed blobs.

The normal collector retains runtime version, source/harness/lock/configuration
hashes and compile/run linkage, but does not hash its SDK or generated AOT
executables. Its numerical harness checks and work counters are serialized;
it does not preserve full geometry or QR matrices for an additional physical
replay. These limits are separate from the stronger sparse-adapter provenance.

All 24,240 samples/batches and 4,848 paired CAD work records remain. Plate p99
is harness-reported; QR/linkage p99 is derived screening information. Neither
cohort establishes stable tail bounds, total allocated-byte savings or GC/
compiler causality. The final report explicitly accepts the retained timing
costs without claiming a universal application speedup.

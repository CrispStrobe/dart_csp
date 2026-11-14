# Sparse ordering follow-up measurement plan

Baseline is current main `c2603a852229897d325a8890ed418319ee8c3572`.
The candidate must be a new committed source revision. Compare fresh paired
processes on this host; historical `135a6ee` versus `6cc191f` timing aggregates
are context only. Keep their archives unchanged.

## Preparation and correctness

Use the existing `paired_dart_backends.py` unchanged. It snapshots every tracked
library/test/adapter file plus actual package config and lock, hashes the exact
Dart compiler and generated AOT files, checks source before/after compilation,
and freezes the Python harness. Both worktrees need identical adapter files,
pubspec and canonical lock, resolving dart_csp to their own source directories.

Use `/workspace/scratch/a4f67f49ccab/runtime/dart-sdk/bin/dart` (Dart 3.14.0),
`TMPDIR=/workspace/scratch/a4f67f49ccab/runtime/tmp`, and
`PUB_CACHE=/workspace/scratch/a4f67f49ccab/runtime/pub-cache`.
The already saved canonical lock has SHA-256
`a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a`.

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py prepare \
  --before "$ORDER_BEFORE" --after "$ORDER_AFTER" \
  --dart /workspace/scratch/a4f67f49ccab/runtime/dart-sdk/bin/dart \
  --out "$ORDER_RESULTS/prepared"

python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared "$ORDER_RESULTS/prepared" --variants after --purpose qualification \
  --suites smoke,confirm,coupled \
  --fixtures canonical_cell,axis_rectangle,coincidence,contradictory_distance,ladder_3_components_1,ladder_1_components_1_scale_1e-06,ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --warmups 1 --samples 2 --timeout 20 \
  --out "$ORDER_RESULTS/qualification"
```

This is 36 candidate jobs / 108 operations including 36 warmups. All 96 feasible
operations must be accepted and all twelve contradictions correctly rejected.
It exercises both engines, cold/warm caches, scales and 500/2,000-coordinate
target ladders. It complements focused exact-order/cap/cancellation/cache tests;
it does not replace a fresh full source validation gate after production edits.

The old four-column live-list exact-work boundary in
`geometry_sparse_ldlt_test.dart` can remain unchanged if small systems retain the
scan. The new heap path still needs its own intentional bounded-work and
deterministic-order regression. Do not weaken numerical/factor/assembly limits.

## Paired timing, only after all builds/tests stop

Use the existing default CPU pinning (`--cpu auto`, one allowed CPU) and one
collector at a time. No profiles, tests, compilers or second solver processes
should compete with timed work. The collector reverses order across rounds and
also balances fixture/mode/engine order. Separate target and small-control
cohorts provide natural durable checkpoints.

| Cohort | Fixtures | Rounds/warmups/samples | Jobs | Operations |
|---|---|---|---:|---:|
| Main target | `ladder_125_components_1`, `ladder_500_components_1`, `laman_free_500` | 3 / 2 / 7 | 72 | 648 |
| Below-threshold controls | `ladder_25_components_1`, `laman_free_100` | 3 / 2 / 7 | 48 | 432 |
| Dense-fill reliability | `laman_free_2000` | 1 / 0 / 2 | 8 | 16 |

Every row uses both revisions, 2D analytic + 3D AD, and cold + warm modes.
The ladder fixture names encode cells: 25/125/500 cells correspond to
100/500/2,000 free planar coordinates. The 2,000-coordinate dense-fill case
was unqualified on both revisions before this change; keep it outside ordinary
successful-solve ratios. Faster symbolic work can alter structural eligibility
even when pivot ordering is unchanged, so preserve new reliability outcomes.

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared "$ORDER_RESULTS/prepared" --suites confirm,coupled \
  --fixtures ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 3 --warmups 2 --samples 7 --timeout 20 \
  --out "$ORDER_RESULTS/targets"

python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared "$ORDER_RESULTS/prepared" --suites confirm,coupled \
  --fixtures ladder_25_components_1,laman_free_100 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 3 --warmups 2 --samples 7 --timeout 20 \
  --out "$ORDER_RESULTS/small-controls"

python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared "$ORDER_RESULTS/prepared" --suites coupled \
  --fixtures laman_free_2000 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --warmups 0 --samples 2 --timeout 20 \
  --out "$ORDER_RESULTS/dense-fill"
```

If the target cohort does not support retention, preserve the complete result
and decide whether to reject/adjust before spending time on further controls.
Do not silently drop a slow engine, warm case or rejected operation. If a source
adjustment follows, it needs a new frozen preparation and separate cohort.

For a retained candidate, the existing small-QR/CAD collector can also screen
collateral JIT/AOT effects with the same three fixtures and 3/5/25 design as the
completed prior pass. That is 36 reports and 6,000 samples/batches; source identity
must use current-main baseline. No claim that the new heap fixes old JIT tails
is supportable without that fresh comparison or a distinct causal diagnostic.

## Independent audit reuse

The generic preserved scripts are copied byte-for-byte into this directory:
`independent-audit-preserved.py`, `finalization_audit.py`, `reliability_audit.py`.
They do **not** pin old commits or fixture inventories. The finalization auditor
replays the archived physical oracle, checks native-output preservation,
requests, source archives and Git trees, sequential jobs, complete manifests,
per-process percentiles and published ratios. It also reports exact paired
coordinate/work parity. The reliability wrapper independently recomputes terminal
gates and keeps honest feasible rejection/timeouts distinct from integrity errors.

`audit_ordering_followup.py` adds explicit expected baseline/candidate commits,
fixture/engine/mode inventory, sample design and optional required qualification,
completeness and exact pair parity. It executes no solver. Example for targets:

```sh
python3 /path/to/ordering-evidence-tools/audit_ordering_followup.py \
  --repo /path/to/dart_csp --prepared "$ORDER_RESULTS/prepared" \
  --run "$ORDER_RESULTS/targets" \
  --expected-before c2603a852229897d325a8890ed418319ee8c3572 \
  --expected-after "$ORDER_CANDIDATE" \
  --expected-fixtures ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --expected-rounds 3 --expected-warmups 2 --expected-samples 7 \
  --require-qualification --require-complete --require-exact-pairs \
  --output "$ORDER_RESULTS/targets/independent-audit.json"
```

For candidate-only qualification add `--expected-variants after`, the nine
qualification fixtures and 1/1/2; omit `--require-exact-pairs`. For dense-fill use
1/0/2 and its single fixture; omit `--require-qualification` to preserve honest
failure. Exact pair parity is a chosen expectation for an arithmetic-preserving
ordering change; if eligibility intentionally changes, report that separately
instead of labelling numerical/work divergence an archival inconsistency.

`tool/audit_sparse_small_cad.py` from the prior pass pins the old baseline and
candidate library tree and therefore needs explicit parameterization for a new
small-control cohort. Its field/unit/percentile checks are reusable. The separate
`tool/audit_sparse_small_cad_crosscheck.py` and `tool/audit_recovery_processes.py`
already derive identities from their input rather than hardcoded source SHAs.

## Durable checkpoint policy

Save the plan/source before long measurements, then frozen preparation, completed
qualification, each complete timing cohort, and final evidence/decision. Every
job already has exact compressed request, raw stdout, checked records, stderr,
command and process metadata. Top and per-variant manifests are atomic, but a
snapshot taken during updates must be checked for cross-file consistency.

For an in-progress checkpoint, select only completed jobs listed in a captured
top manifest; copy their immutable files. Read the top manifest again and retry
if it changed, and require lane summaries/counts to agree. Preserve truthful
`running`/`in_progress` state and label the snapshot partial. The final generic
auditor deliberately requires a completed cohort; partial data is not a pass.

After a complete run, `pack_results.py RUN/before` and `RUN/after` generate
size-bounded raw archives (default 128 KiB target) and per-variant archive
manifests. Keep top manifest, analyses, comparison, preparation/source archives,
build logs, frozen harness and independent audits as well. Do not run the packer
on an active cohort or overwrite existing packed results. The generic Reader
does not descend into nested per-variant raw archives, so audit the original
directory first, or restore packed job directories before an audit replay.

Final evidence should record exact member sets, byte counts and SHA-256 digests;
verify the remote Git tree equals the staged tree after each checkpoint.
Preserve rejected source/timing observations and avoid force-pushing history.

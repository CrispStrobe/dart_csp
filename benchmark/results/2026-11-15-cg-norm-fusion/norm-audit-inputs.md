# CG norm-fusion auditor: input contract

Files prepared in scratch:

* `audit_norm_fusion.py`: full raw/protocol audit and immutable decision rules.
* `test_audit_norm_fusion.py`: 22 synthetic rule-boundary tests; no solver runs.
* `norm-audit-rule-tests.log`: passing test output.
* `norm-declaration.template.json`: template only, with explicit replacement
  fields. Replace every placeholder and checkpoint the completed declaration
  before qualification/timing. Do not use this template as run evidence.

No old experiment or old protocol tool is modified. The auditor never executes
the solver, compiler, benchmark or test suite. It does restore/parse archives,
read Git objects, and replay the independent physical oracle.

## Layout and invocation

```text
WORKSPACE/
  prepared-norm/prepared.json, before/, after/, harness/
  prepared-aa/prepared.json, before/, after/, harness/
  qualification/manifest.json, comparison.json, before/, after/
  runs/
    norm-round1/ ... aa-round4/
EVIDENCE/
  declaration.json
  recovery.json
  norm-round1-status.json
  norm-round1-summary.json
  norm-round1-evidence.json, norm-round1.payloads.tar.xz.partNNN
  ... the same for all eight blocks
```

`runs/` must contain exactly the eight measurement directories. Qualification
belongs outside it. The audit output must be a new directory.

```bash
python PATH_TO/audit_norm_fusion.py \
  --repo REPO_ROOT \
  --prepared WORKSPACE \
  --runs WORKSPACE/runs \
  --qualification WORKSPACE/qualification \
  --saved EVIDENCE \
  --declaration EVIDENCE/declaration.json \
  --validation-index PATH_TO/validation-index.json \
  --out NEW_AUDIT_OUTPUT_DIRECTORY
```

The output includes `audit.json`, a full per-row `audit.md`, and exact restored
archive files under `restored/`. Read `overall_decision`; exit code zero means
the raw experiment was audited successfully and can still mean **revert** or
**blocked_missing_correctness_evidence**. Retention requires the explicit
`overall_decision: retain` plus the normal human/source review.

## Declaration

Use `norm-declaration.template.json`. Its `protocol` and `decision_rules` fields
must exactly match the adopted protocol; the auditor rejects changed margins,
fixtures, counts or schedules. All source/build/hash placeholders must be filled.

`endpoints.baseline` and `.candidate` each contain:

```json
{
  "source_commit": "40-character Git commit",
  "library_tree": "Git lib tree",
  "test_tree": "Git test tree",
  "source_archive_sha256": "SHA-256 of exact frozen source.tar.gz",
  "executable_sha256": "SHA-256 of actual frozen dart-adapter"
}
```

`prepared_sha256.norm` and `.aa` bind the complete preparation files, including
their exact source/build provenance. A/A must reuse the same baseline source
archive and executable bytes as `prepared-norm/before`. `production_diff_sha256`
is the SHA-256 of the exact bytes from:

```bash
git diff --binary BASELINE_SHA CANDIDATE_SHA -- lib
```

Only `lib/src/geometry/numeric.dart` may differ in the production file list.
`auditor_sha256` pins the new auditor itself; `script_sha256` pins the old raw
analyzer, physical oracle, paired collector and packer. Copying the auditor to
the repository without modifying its bytes does not change its hash. Any fixes
before timing require refreshing the declaration before it is frozen.

Optionally add `runner_path` (a safe path relative to the repository) and
`runner_sha256` together to bind the new bounded block runner. If either field
is present, both are required and its exact bytes must match. The template
omits these optional fields because the new runner is prepared by the parent.

Preparation status and both build records must be successful and complete;
all build/preparation completion timestamps must precede the declaration.
Derived A/A retains the baseline build timestamps and does not require duplicate
build logs. The compact archive `saved_utc` must fall between the status record's
`completed_utc` and `packed_utc`, binding archive creation to the nonoverlap check.

`declared_utc` must precede `recovery.observed_utc`, qualification, and all timing.
`session_root` is the original `/workspace/scratch/SESSION_ID` prefix, not an
audit replay path. `cpu` may be another explicitly chosen allowed CPU if needed
before collection; every job must use that same declared value.

## Recovery/session record

After freezing the declaration, create `EVIDENCE/recovery.json` containing at
least these fields:

```json
{
  "session_id": "b51b355c4f64",
  "timing_cohort": "2026-11-15-cg-norm",
  "declaration_sha256": "SHA-256 of completed declaration.json",
  "observed_utc": "UTC timestamp after declaration and before qualification",
  "platform": "exact platform.platform() string used by collector",
  "cpu_model": "exact collector CPU model string",
  "affinity": [0, 1, 2, 3, 4, 5, 6, 7, 8]
}
```

Record the real allowed affinity; the array above is an example from this
workspace, not a value to assume. The recovery file must remain unchanged once
qualification/timing starts. Its hash is then bound into each block status.

## Per-block status

The existing bounded-runner status shape is reused, adding a declaration hash:

```json
{
  "name": "norm-round1",
  "cohort": "norm",
  "round": 1,
  "command": ["python", "ABSOLUTE_COLLECTOR_PATH", "run", "...actual option/value pairs..."],
  "environment_cohort": "2026-11-15-cg-norm",
  "session_id": "b51b355c4f64",
  "declaration_sha256": "SHA-256 of declaration.json",
  "recovery_sha256": "SHA-256 of recovery.json",
  "compact_evidence": true,
  "state": "ready_for_remote_checkpoint",
  "passed": true,
  "exit_code": 0,
  "pack_exit_code": 0,
  "groups": 16,
  "measured_operations": 672,
  "started_utc": "before collector start",
  "completed_utc": "after collector analysis ends",
  "packed_utc": "after archive creation ends"
}
```

The same shape applies to A/A and rounds 2–4. `command` must contain the real
argument list; do not serialize a shell command. The frozen collector's default
`--variants before,after` may be omitted, but every other declared option must
be explicit. Original executable/output paths and recorded timestamps must
match the saved manifests and job records. Packing intervals cannot overlap
later timed blocks. Each block is remotely checkpointed by the caller before
the next starts; this auditor checks the preserved data, not GitHub API actions.

## Source-bound external correctness evidence

The raw auditor does not itself run native, portable or browser tests. Supply
an optional normalized `validation-index.json` to authorize a final retain
recommendation while preserving existing validation-runner schemas:

```json
{
  "schema": "dart-csp-norm-validation-v1",
  "records": [
    {
      "endpoint": "candidate",
      "gate": "native",
      "passed": true,
      "exit_code": 0,
      "timed_out": false,
      "source_commit": "validated source/evidence commit",
      "library_tree": "exact candidate lib tree",
      "test_tree": "exact candidate test tree",
      "completed_utc": "UTC timestamp before first measurement block",
      "artifacts": [
        {"path": "validation/validation-manifest.json", "sha256": "actual hash"},
        {"path": "validation/native.stdout.log", "sha256": "actual hash"}
      ]
    }
  ]
}
```

Required records are candidate `format`, `analyze`, `focused`, `native`,
`dart2js`, `dart2wasm`, and `browser`, plus baseline `browser` for the repaired
baseline. The actual evidence commit may differ from the frozen source commit,
but its Git library and test trees must exactly match that endpoint. Evidence
paths are safe relative paths under the validation index's parent; put the
index at a common ancestor of all required artifacts. Browser artifacts can be
preserved CI responses/logs bound to the validated source.

Every required record must be passing, source-bound, hash-verified and completed
before measurement starts, as required by the adopted pre-timing correctness
boundary. The normalized index summarizes real saved evidence; it must not
assert gates that have not passed. With a missing/partial/invalid index, the
script still reports available raw/performance findings but never returns an
overall retain recommendation. A performance rejection remains a valid reason
to revert even when external correctness evidence is incomplete.

## Verification already performed

The synthetic tests cover the exact inclusive primary/A/A boundaries, strict
adverse and p95 boundaries, both-order requirements, three-of-four primary
improvement, A/A cancellation across orders, missing/duplicate/unbalanced
populations, invalid ratios, and protection against using A/A noise to excuse
candidate adversity. All 22 tests passed. The complete file/manifest/oracle audit
cannot be exercised end-to-end until the new frozen run data exists; no old
timing cohort has been run through this new decision rule.

# Sparse ordering follow-up: evidence replay

Start with [the final results and retention decision](../../../doc/sparse-followup-results-2026-11-14.md).
The retained heap, the separately rejected QR allocation trial, adverse controls
and unchanged dense-fill convergence limit all remain preserved here.

`final-archive-verification.json` records a successful byte/membership check of
all seven archives (894 members) and both completed normal-collector cohorts.
To repeat that storage verification without restoring files or running a solver:

```bash
python3 benchmark/results/2026-11-14-sparse-followup/verify_followup_evidence.py \
  benchmark/results/2026-11-14-sparse-followup \
  --output /path/to/new-archive-verification.json
```

This guide rechecks the saved experiment in `benchmark/results/2026-11-14-sparse-followup`. It restores exact recorded bytes and reruns Python evidence audits; it does not execute Dart, rebuild binaries, or collect new timings. Use Python 3 with its standard library and Git. Run the shell examples in Bash from the repository checkout.

The measured baseline is `c2603a852229897d325a8890ed418319ee8c3572`; the heap candidate is `521a31f78989cf4706c8f26bb6a2c2ec2709b777`. Later evidence/documentation commits are not new measured revisions.

## 1. Set paths and make the source commits available

```bash
set -euo pipefail
sparse_repo="$(git rev-parse --show-toplevel)"
sparse_evidence="$sparse_repo/benchmark/results/2026-11-14-sparse-followup"
sparse_replay="$(mktemp -d "${TMPDIR:-/tmp}/dart-csp-followup.XXXXXX")"
sparse_before=c2603a852229897d325a8890ed418319ee8c3572
sparse_after=521a31f78989cf4706c8f26bb6a2c2ec2709b777
git -C "$sparse_repo" cat-file -e "$sparse_before^{commit}"
git -C "$sparse_repo" cat-file -e "$sparse_after^{commit}"
```

The audits use the local Git object database to verify the recorded commit, root tree, library tree, and test tree. If either object is missing, fetch the saved branch and repeat the two checks:

```bash
git -C "$sparse_repo" fetch origin perf/sparse-followup-2026-11-14
```

A shallow clone may also need `git fetch --unshallow origin perf/sparse-followup-2026-11-14`. Fetching current `main` alone need not retain every experimental revision. Archived original absolute paths are provenance; replay does not require recreating those paths.

## 2. Verify and restore the archives

```bash
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/preparation-521a31f-evidence.json" "$sparse_replay/prepared"
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/audit-tools-evidence.json" "$sparse_replay/audit-tools"
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/qualification-521a31f-evidence.json" "$sparse_replay/qualification"
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/targets-521a31f-raw-evidence.json" "$sparse_replay/targets"
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/small-controls-521a31f-raw-evidence.json" "$sparse_replay/small-controls"
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/dense-fill-521a31f-raw-evidence.json" "$sparse_replay/dense-fill"
python3 "$sparse_repo/tool/unpack_benchmark_evidence.py" \
  "$sparse_evidence/validation-521a31f-evidence.json" "$sparse_replay/validation"
```

Each destination must not already exist. The tool checks `archive_bytes`, `archive_sha256`, the exact `files` membership, and every member's byte count and SHA256 before writing regular files. For the target cohort it reads the manifest's ordered `archive_parts`, verifies each part, joins `part000` through `part007`, and verifies the complete archive. There is no standalone target `.tar.xz` file to pass directly to `tar`.

| Restored directory | Expected regular files | Stored archive |
| --- | ---: | --- |
| `prepared` | 12 | `preparation-521a31f.tar.gz` |
| `audit-tools` | 5 | `audit-tools.tar.gz` |
| `qualification` | 188 | `qualification-521a31f.tar.gz` |
| `targets` | 372 | Eight parts of `targets-521a31f-raw.tar.xz` |
| `small-controls` | 251 | `small-controls-521a31f-raw.tar.xz` |
| `dense-fill` | 52 | `dense-fill-521a31f-raw.tar.xz` |
| `validation` | 14 | `validation-521a31f.tar.gz` |

The preparation archive deliberately omits both measured AOT executables. `prepared.json` and the evidence manifest retain their sizes/hashes, compilation commands, successful build logs, compiler identity, frozen source archives, dependency lock, and harness bytes. The recorded Dart compiler is 3.14.0 stable, SHA256 `6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b`; the shared lock SHA256 is `a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a`.

Replay therefore verifies the retained evidence without checking the omitted executable bytes. A new benchmark run requires rebuilding with the recorded inputs into a new preparation/output directory and reporting a new cohort; rebuilding does not reproduce the historical timings or establish binary identity automatically.

## 3. Replay the four sparse audits

Keep the four Python scripts in `audit-tools` together: the wrapper invokes `reliability_audit.py`, which invokes `finalization_audit.py`, which loads `independent-audit-preserved.py`. The wrapper pins the intended source commits, fixture inventory, engines, modes, sampling, completeness, and optional qualification/exact-pair requirements. It replays the frozen physical oracle and checks raw requests, native outputs, checked outputs, source/archive hashes, process records, work parity, percentiles, and qualification-dependent ratios.

```bash
sparse_audit=(
  python3 "$sparse_replay/audit-tools/audit_ordering_followup.py"
  --repo "$sparse_repo" --prepared "$sparse_replay/prepared"
  --expected-before "$sparse_before" --expected-after "$sparse_after"
  --expected-engines dart_2d_analytic,dart_3d_ad
  --expected-modes cold,warm
)

"${sparse_audit[@]}" \
  --run "$sparse_replay/qualification" --expected-variants after \
  --expected-fixtures canonical_cell,axis_rectangle,coincidence,contradictory_distance,ladder_3_components_1,ladder_1_components_1_scale_1e-06,ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --expected-rounds 1 --expected-warmups 1 --expected-samples 2 \
  --require-qualification --require-complete \
  --output "$sparse_replay/audits/qualification.json"

"${sparse_audit[@]}" \
  --run "$sparse_replay/targets" --expected-variants before,after \
  --expected-fixtures ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --expected-rounds 3 --expected-warmups 2 --expected-samples 7 \
  --require-qualification --require-complete --require-exact-pairs \
  --output "$sparse_replay/audits/targets.json"

"${sparse_audit[@]}" \
  --run "$sparse_replay/small-controls" --expected-variants before,after \
  --expected-fixtures ladder_25_components_1,laman_free_100 \
  --expected-rounds 3 --expected-warmups 2 --expected-samples 7 \
  --require-qualification --require-complete --require-exact-pairs \
  --output "$sparse_replay/audits/small-controls.json"

"${sparse_audit[@]}" \
  --run "$sparse_replay/dense-fill" --expected-variants before,after \
  --expected-fixtures laman_free_2000 \
  --expected-rounds 1 --expected-warmups 0 --expected-samples 2 \
  --require-complete --require-exact-pairs \
  --output "$sparse_replay/audits/dense-fill.json"
```

The qualification run has only `after` jobs, so it has no exact-pair requirement. The dense-fill run intentionally omits `--require-qualification`: its feasible fixture reached `iterationLimit` in both revisions and failed the physical oracle in all 16 operations. That retained convergence limitation must remain visible, with successful-solve ratios null.

| Cohort | Complete jobs | Validated operations, including warmups | Measured operations | Exact coordinate/work pairs | Expected qualification |
| --- | ---: | ---: | ---: | ---: | --- |
| Qualification | 36 | 108 | 72 | — | Pass: 96 feasible accepted, 12 contradictions rejected |
| Targets | 72 | 648 | 504 | 324 | Pass |
| Small controls | 48 | 432 | 336 | 216 | Pass |
| Dense fill | 8 | 16 | 16 | 8 | Fail: 16 feasible rejections |

All four commands should return exit code 0 and `evidence_consistent: true`, with empty integrity/contract findings. Qualification is a separate field. Each restored run contains a root `manifest.json`, variant manifests/summaries, and per-job `request.json.gz`, `stdout.jsonl.gz`, `checked.jsonl.gz`, `stderr.txt`, and `job.json`. `comparison.json` and the saved independent reviews retain adverse as well as favorable results. Three timing rounds with seven measured samples provide three process medians and three process maxima used as p95; they do not establish a precise population tail. Replay reports can differ in path/timestamp fields; compare findings and reconciled values rather than expecting their JSON bytes to match historical audit files.

## 4. Replay the normal CAD/small-QR controls

These controls are stored directly as `cad-controls/raw.json.gz`, `summary.json`, and companion files. They use a different report schema from the sparse paired harness and must not be passed to `audit_ordering_followup.py` or the archive unpacker. The rejected QR experiment is retained separately in `qr-screen`; it compares the same baseline against `748febd527cda9eeb611cdf2dcba3c9c3af388ec`, not the heap candidate.

Verify the flat evidence manifests and uncompressed raw digests:

```bash
python3 - "$sparse_evidence" <<'PY'
import gzip, hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for name in ('cad-controls', 'qr-screen'):
    folder = root / name
    manifest = json.loads((folder / 'evidence.json').read_text())
    for relative, expected in manifest['files'].items():
        data = (folder / relative).read_bytes()
        assert len(data) == expected['bytes'], (name, relative, 'size')
        assert hashlib.sha256(data).hexdigest() == expected['sha256'], (name, relative, 'hash')
    raw = gzip.decompress((folder / 'raw.json.gz').read_bytes())
    assert len(raw) == manifest['raw_uncompressed_bytes'], name
    assert hashlib.sha256(raw).hexdigest() == manifest['raw_uncompressed_sha256'], name
    print(name, 'verified')
PY

python3 "$sparse_evidence/qr-screen/audit_qr_screen.py" \
  "$sparse_evidence/cad-controls/raw.json.gz" \
  "$sparse_evidence/cad-controls/summary.json" \
  --expected-before "$sparse_before" --expected-after "$sparse_after" \
  --rounds 3 --samples 101 --warmups 20 \
  --output "$sparse_replay/audits/cad-controls.json"
python3 "$sparse_evidence/cad-controls/audit_processes.py" \
  "$sparse_evidence/cad-controls/raw.json.gz" \
  --output "$sparse_replay/audits/cad-controls-processes.json"

python3 "$sparse_evidence/qr-screen/audit_qr_screen.py" \
  "$sparse_evidence/qr-screen/raw.json.gz" \
  "$sparse_evidence/qr-screen/summary.json" \
  --expected-before "$sparse_before" \
  --expected-after 748febd527cda9eeb611cdf2dcba3c9c3af388ec \
  --rounds 3 --samples 101 --warmups 20 \
  --output "$sparse_replay/audits/qr-screen.json"
python3 "$sparse_evidence/cad-controls/audit_processes.py" \
  "$sparse_evidence/qr-screen/raw.json.gz" \
  --output "$sparse_replay/audits/qr-screen-processes.json"
```

`cad-controls/audit_control_cohort.py` is a byte-identical copy of the generalized `qr-screen/audit_qr_screen.py`. Both accept gzip directly and import only the standard library. Each cohort should pass with 36 reports, 40 summary rows, 240 raw distributions, 24,240 measured samples, and 101 process records; the process audit checks 202 original-stream hashes, six compilation records, and 36 matched benchmark records. Both JIT and AOT are required; no diagnostic override is used.

For the additional source-byte comparisons performed in the saved audit, supply `--before` and `--after` pointing to clean worktrees at that cohort's exact commits. Restore each worktree's untracked `pubspec.lock` from the corresponding `prepared/before/source.tar.gz` or `prepared/after/source.tar.gz`; its SHA256 is given above and is shared by the QR experiment too. The recorded benchmark harnesses are present at those commits. Without these optional paths, report/percentile/process replay still runs, but the source comparison counts are absent and `source_provenance` is empty; do not represent that replay as repeating those checks.

CAD reports retain oracle pass records and work counters, but not full geometry/QR values for an independent physical replay. QR timing samples are batches of 256 operations, except `rank_48x48`, which uses eight. The normal CAD runner's process records establish compile/run linkage, but do not hash SDK or AOT executable bytes; the stronger compiler/binary metadata in the sparse preparation must not be attributed to this separate cohort.

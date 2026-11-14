# Packed sparse factor storage evidence

Baseline: `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`.
Frozen candidate: `4325386e689566a903309accd66aca3ced1159f7`.

See [the experiment plan](../../../doc/sparse-storage-followup-2026-11-14.md)
and [independent code review](../../../doc/sparse-storage-code-review-2026-11-14.md).
This directory is saved incrementally to remote main. At this checkpoint the
source/preparation, complete independent physical qualification and all native/
portable validation are saved; timing collection and retention are still pending.
`validation-summary.json` indexes the seven successful validation gates and their
complete logs in `validation-4325386-evidence.json`.

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
```

Temporary AOT binaries are omitted from the preparation archive; their exact
hashes, successful build logs, compiler identities and frozen source/dependency
inputs remain. Saved audits verified the original binaries while present.
Rebuilding is required for new runs and does not reproduce historical timings.

The qualification review describes the exact 36-job inventory and how to replay
the independent audit. Qualification timings were collected concurrently with
other correctness gates and must not be treated as controlled comparisons.

# Optimization recovery evidence

This directory continues from `6760a4d` and contains a separate fresh process
cohort. Historical samples are preserved and audited, never pooled into the
new comparison. See `doc/optimization-recovery-2026-11-14.md` for the scope.

`remote-reconciliation.json` identifies all fetched branches and PR heads,
including the two original squash-equivalent heads. The integration preserves
rejected experiments as history and evidence without reinstating their source.

`prepared-evidence.json` manifests **all actual frozen executable bytes**, source
archives, build logs, four preparation manifests and harness copies. The pinned
compiler and lock match the previous session. Executable hashes changed because
the reconstructed build paths changed; `rebuild-manifest.json` records this.

## Restore and replay

Run these commands from the repository root, choosing a new destination:

```bash
python tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-optimization-recovery/prepared-evidence.json \
  ../replayed-optimization
```

The restorer verifies archive parts, the combined archive, exact member sets,
and every member digest before writing. It writes regular files without execute
permission; set executable permission on the restored `*/{before,after}/dart-adapter`
files before any new runtime execution. Audit replay does not execute them.

Restore each round's `*-evidence.json` into
`../replayed-optimization/runs/<cohort>-round<number>`. Preserve the original
names (`cg`, `identity`, `combined`, `aa`) and round numbers. Then replay the
independent source, raw-geometry, work, order and timing audit:

```bash
python benchmark/results/2026-11-14-optimization-recovery/analyze_recovery.py \
  --runs ../replayed-optimization/runs --out ../replayed-optimization/audit
```

The analysis reads Git objects to verify source provenance. The repository
checkout must contain the recorded commits. It recomputes physical acceptance
using the independent oracle, compares all paired non-timing fields, recomputes
percentiles, and separates before-first and after-first observations.

## New collection protocol

Four rounds each compare packed baseline to fused CG, CG to default-manifold
contraction, packed baseline to both, and the identical baseline to itself.
The first three comparisons use six fixtures, both engines and both lifecycle
modes. A/A uses the five predeclared sentinel fixtures. Each process performs
eight warmups and 21 measured operations, sequentially, with CPU affinity 0
and a 30-second deadline. This yields 15,456 planned measured operations across
736 processes, plus 5,888 warmups. These are planned counts until the final
audit confirms completion.

`tool/run_optimization_round.py` collects one block, records status immediately,
preserves complete or partial raw evidence on failure, bounds collection and
packing, and refuses to overwrite an existing block. A remote checkpoint with
matching Git blob/tree hashes and an expected-head ref update is verified
before the next timed block begins.

All source qualification, compilation and correctness tests precede timing.
Archive packing, uploads and independent audits occur between or after timed
blocks. Keep favorable and adverse measurements. A/A ranges describe observed
variation; they do not establish that an implementation regression is noise.

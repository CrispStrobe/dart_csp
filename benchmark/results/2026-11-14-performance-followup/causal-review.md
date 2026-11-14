# Independent causal review and bounded follow-up design

## Scope

This review reexamines the completed packed-factor experiment, baseline
`d43a8b0fca74c6bc893d68ca6ec8190e74b423c9` versus candidate
`4325386e689566a903309accd66aca3ced1159f7`. The later main documentation
checkpoint `994cdae` retains those source/test trees. No old raw observation or
retention decision is rewritten by this review. Analysis reads existing data
and code only; it executes no solver or benchmark and makes no production edit.
Lightweight Python analysis ran on CPU 8.

Evidence read:

- `sparse-storage-work/targets/`: requests, native stdout, checked output,
  per-job summaries and completed manifests.
- `sparse-storage-work/small-controls/`: the analogous below-threshold cohort.
- `sparse-storage-work/cad-controls/raw.json`: every original process report
  and sample vector from the JIT/AOT QR/plate/linkage controls.
- `dart_csp/doc/sparse-resume-evidence-review.md`: independently reconstructed
  structural work for the unchanged benchmark fixtures.
- `dart_csp/lib/src/geometry/numeric.dart`, `sparse_ldlt.dart`,
  `benchmark/solver_comparison/dart_adapter_core.dart`,
  `benchmark/geometry_small_qr.dart`, `benchmark/cad_linkage.dart`,
  `example/nonlinear_linkage.dart` and `example/parametric_bracket.dart`.

Those scratch paths are relative to `/workspace/scratch/f23bebb6afce/`.
The corresponding durable original evidence and reviews are under
`dart_csp/benchmark/results/2026-11-14-sparse-storage/`.

## Changed-path attribution

| Workload | Execution path | Packed numeric factor storage exercised? |
|---|---|---|
| Ladder 500 / 2,000, both representations | Admitted sparse LDLT; raw records show one linear iteration per solve | Yes |
| Coupled-500, both representations | Bounded symbolic decline, then CG | No |
| Coupled-2,000 | Bounded decline/fallback reliability control; unsuccessful local solve | No successful-solve speed ratio is defined |
| Ladder/coupled 100 | Below the 256-column sparse-direct threshold; CG | No |
| Small-QR harness | Direct rank/QR/nullspace functions | No |
| Plate/linkage CAD controls | Small dense-QR geometry; linkage has six active coordinates | No |

For coupled-500, preserved exact-degree structural reconstruction gives:

| Representation | Columns | Raw nnz | Predicted Schur updates | Adaptive work cap |
|---|---:|---:|---:|---:|
| 2D | 500 | 1,988 | 884,570 | 63,616 |
| 3D | 750 | 3,732 | 2,985,580 | 119,424 |

The `32 * rawNNZ` cap therefore declines before factor-column materialization
and numeric factor allocation. Current raw structural counters agree with that
reconstruction; representative records show seven solves / 4,508 CG iterations
in 2D and seven / 4,510 in 3D. The packed change occurs after this decline point.

Consequently both the cold coupled-500 2D **+9.65%** adverse observation and
the cold coupled-500 3D **-7.36%** favorable observation are collateral timing
differences. Neither establishes the runtime cost or benefit of executing the
packed factor buffer. This qualification applies symmetrically to all unchanged
paths; it does not delete or excuse unfavorable observations.

## Process order confounds the cold 2D sparse result

In all six process pairs for the 500- and 2,000-coordinate cold 2D ladders,
the variant run first has the slower median. The 2,000-coordinate pairs are:

| Round | Process order | Before p50 (ms) | After p50 (ms) | Candidate change |
|---|---|---:|---:|---:|
| 1 | After, before | 32.072 | 47.830 | +49.1% |
| 2 | Before, after | 41.401 | 35.484 | -14.3% |
| 3 | After, before | 34.031 | 35.207 | +3.5% |

The published aggregate +4.27% remains arithmetically correct. Three rounds
cannot separate a revision effect from this strong order association. These
records are not grounds to trim samples or declare the regression nonexistent.

The first baseline 500-coordinate cold 2D process contains two approximately
36 ms measured operations. Its process median build time is 8.302 ms versus
0.896 ms in the paired candidate, despite the packed-storage modification being
inside the later linear solve. The same process has a 13.834 ms total median;
the next baseline process has 7.293 ms. This shows a substantial disturbance
outside the changed allocation path, without identifying its cause.

Warm 2,000-coordinate 2D remains the strongest directly exercised result:
candidate process-median changes are -6.9%, -12.7% and -10.0%, spanning both
revision orders. Solve-phase medians also improve in every pair. Warm 500- and
2,000-coordinate 3D medians improve in all pairs, with smaller effects and mixed
tail behavior. These favorable observations need the same replication standards
as the unfavorable ones.

## QR and CAD distribution findings

AOT rank-5x4 process medians, in microseconds per 256-call batch, are:

| Round | Before | After |
|---|---:|---:|
| 1 | 95 | 95 |
| 2 | 95 | 208 |
| 3 | 98 | 177 |

Rank-5x4 is the first case in every QR process. The slow round-2 candidate is
not one bad first sample: its first-half and second-half medians are about
209 and 204 microseconds. The following rank-8x4 case in that process is a
normal 115 microseconds. Round 3 shows a broader, time-varying slowdown across
several cases. These are observed process/case-position effects with unresolved
causality. This particular result is AOT, so JIT compilation cannot explain it.

The unchanged QR source and unexecuted packed path do not prove identical
compiled artifacts. The normal collector retained compile/run linkage but did
not hash its generated executables. A subsequent experiment should bind all
AOT artifacts and include same-binary controls before attributing differences
to compiler layout or runtime host effects.

Candidate AOT linkage p99 events cluster across distinct operations around
iterations 84-86 in round 2 and 13-15 in round 3. Those operations are interleaved
within each iteration. This supports investigating temporal disturbances; it
does not establish GC or host scheduling as the cause. JIT linkage also has
recurring large values at similar indices across revisions. Interpret them
alongside exact per-sample work records rather than treating all samples as
independent identical observations.

## Predeclared bounded follow-up

The objective is an improvement with unchanged semantics and measurable bounds,
not a universal nonregression promise over unknown workloads. No dispatch rule
should be tuned to fixture IDs or chosen from whichever samples look favorable.

1. **Record actual path attribution in a separate diagnostic build.** Capture
   backend selection, structural-decline reason, dimensions, raw nnz, factor
   entries, predicted work, numeric-attempt count and cold/cached shape use.
   Keep instrumentation out of the timed executable. The earlier structural
   analysis is strong evidence but should be confirmed by diagnostic counters.
2. **Bind all artifacts and use A/A controls.** Preserve SDK and every generated
   AOT executable hash, including tiny QR/CAD. Run the same exact binary under
   both comparison labels using the same harness. This tests order/host effects
   without a revision change. Do not infer an experimental noise floor from
   different code paths or unrelated historical cohorts.
3. **Balance and block process order.** Use a recorded random seed with balanced
   ABBA/BAAB blocks and randomized fixture order. Four balanced blocks give
   sixteen processes per sentinel and avoid the prior two-versus-one order
   imbalance. A compact sentinel set should cover cold/warm admitted sparse,
   sparse-declined CG, below-threshold CG, first-position tiny QR and small CAD.
   Preserve all samples and unsuccessful operations.
4. **Separate startup and steady state.** Twenty tiny QR warmup batches last
   only a few milliseconds. Use a predeclared time-based warmup floor or a
   sufficiently sized fixed warmup workload, recording those observations.
   Never warm until a desired result appears. Report startup and steady-state
   evidence separately; collect JIT/GC diagnostics in separate profiling runs.
5. **Measure the changed operation and the complete operation separately.**
   An identical frozen microbenchmark should call the intended backend directly
   on general structural families, with fresh and reused symbolic shapes and
   original-equation checks outside timers. Separately retain complete geometry
   and CAD controls. Any eventual policy should depend on general measured
   structure/reuse properties, not benchmark identities.
6. **Define acceptance before collection.** Report per-process/block paired
   ratios, both order strata and uncertainty intervals, with practical margins
   chosen before seeing outcomes. Three same-direction pairs alone have a
   two-sided sign probability of 0.25 under a symmetric null, before accounting
   for many inspected rows. Do not pool operation samples across processes or
   call short-cohort p95/p99 estimates stable tail bounds.

Timed collection should pause compilation, tests, archival compression and
other substantial local work, even when that work is pinned to another CPU.
CPU affinity does not provide exclusive CPU or memory-bandwidth ownership.
Save each completed block remotely between measurement blocks. Record process
CPU time, wall time and context-switch/fault counts where available; those are
diagnostics, not automatic grounds to discard an inconvenient block.

## Separate source candidates

The planned CG loop-fusion candidate must be compared against frozen packed
source `4325386`, not silently combined with the historical d43a8b0-to-4325386
storage comparison. Its source, tests, work invariants, artifacts and paired
cohort form a new measurement boundary. Historical storage repeats should use
their own balanced cohort. Retention must state what each experiment actually
supports, including uncertain or adverse observations.

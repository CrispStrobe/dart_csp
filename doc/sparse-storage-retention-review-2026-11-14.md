# Independent packed sparse storage retention review

## Recommendation

**Retain candidate `4325386e689566a903309accd66aca3ced1159f7`, with the measured
costs explicitly accepted and preserved.** This is a selective optimization
against baseline `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`. The available
evidence does not establish a universal latency improvement or the expected
speedup of an application whose workload distribution is unknown.

The source change is small and keeps the numerical algorithm, arithmetic order,
cancellation cadence and existing factor/work caps intact. It replaces one
numeric factor buffer per column and their outer list with one invocation-owned
buffer. Numeric factor entries do not increase; the cached immutable shape adds
`columns + 1` integer offsets. The code review found no ownership, indexing or
budget defect. This allocation-count improvement is established by source;
total allocation bytes, peak memory and GC causality were not measured.

## Evidence supporting retention

The fresh physical qualification accepts all 96 feasible operations and rejects
all 12 deliberate contradictions. The target and small-control cohorts contain
648 and 432 complete operations, respectively, with 540 exact before/after
coordinate and seven-counter solver-work pairs. Independent audits find no
missing or inconsistent evidence. Archived tracked inputs also match their
declared Git blobs byte for byte.

The most persuasive target improvements repeat in all three matched processes
for both p50 and p95:

| Target | p50 change | p95 change |
|---|---:|---:|
| Warm 2,000-coordinate 2D ladder | -11.60% | -9.31% |
| Cold coupled-500 in 3D | -7.36% | -6.71% |

Ten of twelve target aggregate medians are lower, although that count is
unweighted and several rows have mixed paired directions. The complete
small-QR/CAD control screen also has no broad repeated median regression across
its CAD cases: all three AOT plate medians, four of five AOT linkage medians and
all five JIT linkage medians are lower. Its 36 reports preserve all 24,240
samples/batches and 4,848 exact paired CAD work records. These control checks
are distinct from the sparse cohort's independent physical-coordinate replay.

## Costs accepted by this recommendation

Retention does not dismiss the following adverse observations:

- Cold coupled-500 in 2D: p50 **+9.65%**, slower in all three matched pairs;
  p95 **+19.68%**, slower in two.
- Cold 2,000-coordinate 2D ladder: p50 **+4.27%** and p95 **+23.45%**, both
  slower in two pairs.
- Below-threshold warm 100-coordinate 2D ladder: p50 **+25.09%**, p95
  **+25.65%**, both slower in two pairs. These controls do not exercise the
  packed sparse factor path, so the timings are collateral observations.
- AOT QR rank-5x4: p50 **95 → 177 microseconds per 256-call batch (+86.32%)**,
  with two slower pairs and one equal; p95 **+168.12%** and p99 **+142.61%**,
  each slower in two pairs. The batch units matter, and the adverse result
  remains part of the evidence despite the unchanged QR source.
- AOT QR rank-17x8 p95 **+22.31%** and rank-4x8 p95 **+9.31%**, each slower in
  all three pairs. Rank-4x8 p50 also rises **0.61%** in all three.
- JIT cold-linkage p95 **+4.35%**, slower in all three pairs. AOT cold-linkage
  p99 rises **66.61%** and rejected-angle p99 **102.24%**, each slower in two.

The complete target, small-control and 40-row JIT/AOT control reviews retain
every favorable and adverse statistic, including cases where the aggregate
direction differs from the majority of individual paired directions. Without
application weights, these costs and benefits cannot be reduced to an honest
single net-speedup percentage.

## Remaining boundary

The constructed-feasible coupled-2,000 case still returns `iterationLimit` in
all sixteen operations across both revisions. Its eight matched coordinate/work
pairs are exact; every successful-solve timing ratio is null. Retention neither
fixes that convergence limitation nor implies geometric infeasibility.

The sparse cohorts have seven measured samples per process, making each process
p95 its maximum. The separate CAD controls have 101 samples per process, with
p99 the second-largest sample. These are descriptive screens, not stable tail
bounds. Equal work and unchanged source paths do not identify the cause of
elapsed-time changes. Prior adverse-tail findings remain unresolved.

The retained change is justified by the bounded storage simplification and
repeatable sparse target benefits, with the listed costs accepted. Applications
dominated by cold 2D coupled solves or tiny QR batches should use those retained
measurements when assessing the update; an unknown workload mix cannot be
promised a benefit. No further speculative source change or optional retesting
is needed for this decision. Browser coverage and remote CI status remain
separate validation reports.

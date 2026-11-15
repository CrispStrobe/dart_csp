# Optimization recovery and continuation — 2026-11-14

## Durable starting point

The continuation starts from remote `main` at
`46288eb23f04c2a2f2210088fe568285bea6114f`. Its production library includes
the packed sparse factors and the provisional CG vector-pass fusion from
`ad8d23704e50c1bf41412f086e66de4a87bfb21b`. The last session's subsequent
timings and confirmation work are described in the user's transcript but
are absent from this Git history. They cannot support a retention decision
until recovered or reproduced. The complete saved correctness evidence
remains in `benchmark/results/2026-11-14-performance-followup/`.

Work in this continuation is checkpointed incrementally on
`perf/cg-resume-2026-11-14`. Each completed stage includes its raw evidence,
provenance and the next action. No package release is part of this work.

## Bounded continuation

1. Recover the exact Dart 3.14.0 compiler and dependency lock from the saved
   manifest. Rebuild the two committed source snapshots outside timing.
2. Reproduce the planned four balanced rounds of physical comparisons:
   ladder 100 and 2,000, coupled 100 and 500, both representations and cold
   and warm lifecycles; eight warmups and 21 measured operations per process.
   Preserve and push complete rounds independently. Run solver processes
   sequentially with CPU affinity and per-process timeouts.
3. If meaningful adverse costs recur, use bounded identical-executable
   controls for the affected cases before judging the implementation.
   Record physical acceptance, work counters and process-order effects.
4. Make an explicit CG retention/reversion decision. If a separate small
   optimization has a stronger structural justification, investigate it in
   an isolated source checkpoint with meaningful semantic regressions,
   independent review and its own comparison. Do not combine unqualified
   mechanisms or tune solver dispatch to these fixtures.
5. Run all required correctness gates for the final source, preserve both
   favorable and adverse observations, update the handover and push the
   final conclusion and evidence before stopping.

Solver tolerances, resource caps, physical acceptance, custom-manifold
semantics, cancellation and result ownership are constraints, not tuning
variables. A bounded experiment can establish useful gains and identify
costs on tested workloads; it cannot establish universal nonregression.

## Checkpoints

- Recovery: repository and previous source checkpoint restored; runtime
  recovery and independent evidence/source reviews in progress.

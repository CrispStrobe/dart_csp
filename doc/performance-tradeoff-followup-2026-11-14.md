# Reducing the remaining performance tradeoffs — 2026-11-14

## Goal and starting point

Continue from `994cdae62463c01c26ace023b2f61ac2533bda42`, whose production
library is the packed sparse-factor implementation frozen at
`4325386e689566a903309accd66aca3ced1159f7`. Preserve that allocation improvement
and seek additional reductions in real solver work. Save the plan, source,
validation, and measured evidence incrementally to remote `main`.

This is an investigation into reducing measured costs, not a claim that one
implementation can be fastest for every input, runtime, and machine. No
fixture-specific solver dispatch, relaxed residual checks, larger resource
caps, or successful-solve claims for failed attempts are permitted.

## Correct the causal interpretation first

The preceding [packed-storage report](sparse-storage-results-2026-11-14.md)
preserves valid before/after observations. Its coupled-500 cases, however,
decline the sparse numeric-work cap before packed factors are allocated.
They execute CG fallback: approximately 4,500 linear iterations across seven
linear solves. Thus both the reported cold 2D cost and cold 3D benefit are
collateral observations, not direct evidence about executing packed storage.
Below-threshold cases and standalone QR controls also avoid packed factors.

The actual packed-path cold 2D ladder pairs have an additional confounder:
the first-running revision is slower in all six pairs across sizes 500 and
2,000. The warm 2,000-coordinate 2D improvement is more consistent across
both process orders. Preserve every original sample and report a new cohort
separately; do not erase unfavorable data or assert an unmeasured cause.

## First source candidate: CG vector-pass fusion

In `SparseCgGeometrySolver.solve`, accumulate dot products in the existing
loops that initialize preconditioned vectors, add damping, update the next
preconditioned residual, and restart from an explicit residual. This removes
two complete vector traversals per ordinary CG iteration, plus setup and
restart traversals. It adds no buffer or solver-selection threshold.

Keep each dot product's index and reduction order, stored values, stable
norms, callback boundaries, nonfinite checks, tolerance, iteration budget,
original-equation verification, and result ownership unchanged. Do not mix
this candidate with Euclidean-manifold shortcuts, nullspace changes, or
another sparse storage layout.

## Bounded evidence plan

1. Independently review the exact source delta. Run focused semantic tests,
   static analysis, and the native/portable correctness gates for retained
   source. Compare physical outcomes and solver-work counters exactly.
2. Freeze source and executable hashes before measurements. Reuse the
   existing physical-operation protocol and independent oracle. Compilation,
   tests, compression, and other substantial workloads must finish before
   timed collection; pin sequential timed processes to CPU 0.
3. Compare the CG candidate against the packed baseline on coupled-500 and
   below-threshold CG cases, with sparse ladder controls. Use an even number
   of alternating-order rounds and report per-process medians and tails,
   order-stratified effects, and every failure.
4. Revisit the historical packed-path cold/warm 2,000-coordinate 2D ladder
   using eight balanced rounds, eight warmups, and 21 measured operations
   per process. Preserve this as a follow-up cohort, not a replacement for
   the original three-round results.
5. Investigate tiny QR with the same exact executable under two labels
   (A/A), alongside a historical baseline/packed comparison. Use four
   balanced process pairs, 2,000 fixed warmup batches, and 101 measured
   batches; preserve compiler/source/executable hashes and full outputs.

Retain a candidate only with unchanged correctness and bounded-resource
semantics plus evidence of useful reduction in its intended path. Report
material or uncertain regressions candidly; finite benchmarks cannot prove
universal nonregression. Strongly order-dependent results require a control
before making a dispatch decision. No package release is part of this pass.

## Status

Plan checkpoint; implementation and new measurements are pending.

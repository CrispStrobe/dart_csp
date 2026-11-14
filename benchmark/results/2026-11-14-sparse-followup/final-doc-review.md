# Final sparse follow-up documentation review — 2026-11-14

## Finding

The final numerical claims, source boundaries, operation counts and retention rationale agree with the saved evidence. No production or numerical blocker was found. The review was read-only: no solver, compiler, test suite or new measurement was run.

Reviewed `doc/sparse-followup-results-2026-11-14.md`, the current HANDOVER section, README sparse paragraph, CHANGELOG entry, configuration guide, and follow-up plan against frozen source `521a31f78989cf4706c8f26bb6a2c2ec2709b777` and the saved audits/metrics.

## Verified

- Current library/test contents exactly match frozen trees `9adec7f68b8a8b919890a0b9ff7d069a650ddd62` and `9b576992586ad3fe8e175869883a4b5b89e439ba`. The sole production-file delta from `c2603a8` is `lib/src/geometry/sparse_ldlt.dart`; the rejected QR source is absent.
- Every large-target table value and rounded percentage matches `targets/timing-details.json`. All eight ladder medians are lower; nine of twelve target medians are lower. Only the cold 2,000-coordinate 3D ladder improves both p50 and p95 in all three pairs. Warm 500-coordinate 3D p95 worsens in all three pairs despite its lower median in every pair.
- The small-control values, 5/8 improved-median count, +49.32% cold 2D ladder p95 and mixed adverse paired directions match the saved metrics.
- All cited CAD p50/p95/p99 percentages and slower-pair counts match `cad-controls/review-metrics.json`. Its aggregate count is exactly 26 lower, two equal and twelve higher medians. The 24,240 samples/batches, 9,696 work records and 4,848 exact paired records agree with the independent audit.
- The rejected QR experiment's repeated AOT plate and JIT cold-linkage costs, and isolated rank-4x8 benefit, match its separate metrics. Its rejection remains explicit.
- Fresh validation records pass formatting, fatal-info analysis, 1,866 native tests, 545 Node JS tests, 545 Node Wasm tests and 48 comparison-harness tests. The new ordering test is present in both portable and browser CI lists. The independent model reports 1,092 checked graphs, comprising 1,024 exhaustive five-vertex, 64 seeded and four large-boundary graphs.
- Physical inventories agree: 108 qualification operations, 648 accepted target operations, 432 accepted small-control operations, and 16 failed dense-fill operations. There are 324 + 216 exact accepted before/after pairs, plus eight exact failed dense-fill pairs. Dense-fill qualification remains false and successful-latency ratios remain null.
- Recorded target, small-control, dense-fill and CAD timing intervals do not overlap; each records CPU 0 affinity. The target manifest has eight archive parts and 372 members.
- The text retains adverse outcomes, sampling limits, ratio-of-medians versus paired-direction distinctions, non-causal interpretation, and native/Node versus unverified browser coverage. Integration is described as tracked by PR #10 rather than already merged.

## Final publication recheck

All three documentation completion items identified during review are now resolved:

1. The opening explicitly says numerical validation and the 108-operation physical qualification pass. The separate dense-fill qualification remains correctly false in the report.
2. Saved executable hashes are explicitly scoped to sparse-adapter preparation. The normal small-QR/CAD collector's SDK/executable-byte limitation is stated separately.
3. The evidence README now exists, links back to the final results, and provides archive verification/restoration guidance. Every local link in the final results report resolves.

The final documentation is ready for the parent's preservation checkpoint. No additional source edit, test, timing run or numerical correction is requested by this review.

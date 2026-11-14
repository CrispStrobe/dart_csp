# Independent retained source and small-control review — 2026-11-14

## Decision

Recommend retaining the bounded sparse LDLT source at `6cc191f3e9a7c6642afa9af7757b26e515723018` and completing the authorized integration after recording the current CI boundary. The independent source review finds no correctness blocker, and the final planned small-QR/CAD cohort has complete, internally consistent evidence and unchanged paired physical/work records. This is a targeted performance tradeoff: the separately preserved large low-fill ladders improve substantially, while several small/control tails worsen. No universal speedup or absence of regressions is established.

The measured production source remains unchanged. No additional source edit or timing run is required to finish this review. The 2,000-coordinate dense-fill failure remains a documented convergence limit on both revisions; it supplies no successful-solve speed ratio.

## Source review

Compared the production delta from baseline `135a6eed93b46ad7d40d0f5288686d2cd26ddd48` and inspected `lib/src/geometry/numeric.dart`, `lib/src/geometry/sparse_ldlt.dart`, the public export, and both sparse regression files. The local recovered head and source checkpoint share library tree `eb20b0ea6dc251142e6109f04bb7fe768d967db1` and test tree `053478f4a4d7b097211c5cb8984ff3fb6dc1a901`. No `AGENTS.md` is present.

- The raw-row Cartesian-product assembly preserves duplicate-column cross terms and exact caller damping; finite positive pivots and original-CSR equation residuals guard acceptance.
- The live-column ordering list preserves original-index tie breaking, correctly removes first/interior live columns, and charges only remaining-column candidate visits.
- Cached acceptance rechecks effective caps; cached refusal depends on complete current CSR structure and effective limits. Numeric factors and solve scratch remain call-local.
- Structural decline consumes no linear iteration budget. Numeric direct work and CG share the supplied budget. Cancellation is terminal and polled through original-equation verification.
- The default cap is a selected-work heuristic. Cold symbolic analysis can still add latency, and work counts are neither elapsed-time nor byte guarantees. Caller-owned arrays must remain stable during a synchronous call.

These are read-only code findings. The already preserved formatting, analysis, native/Node validation and qualification results are not represented as rerun by this review.

## Independent control audit

`small-cad-independent-audit.json` reports **passed**, with **41,604 checks and zero findings**. The standalone `audit_sparse_small_cad.py` imports no collector, summarizer or project auditor and executes no Dart workload. It independently checks committed source/harness/dependency bytes and the live lock/package configuration, reversible raw stdout/stderr hashes, command/build linkage, sequential process intervals, fixture inventory, per-sample work, raw percentiles and paired summary arithmetic.

| Evidence | Count |
|---|---:|
| Committed library blobs checked across both revisions | 89 |
| Subprocess records / original stream hashes | 101 / 202 |
| Complete alternating benchmark reports | 36 |
| Process distributions / aggregate rows | 240 / 40 |
| Measured samples or operation batches | 6,000 |
| CAD per-sample work records checked | 2,400 |
| Exact before/after paired work records | 1,200 |
| Published percentiles recomputed | 516 |

Each runtime has three fresh process pairs per fixture, five warmups and 25 measured samples. All benchmark processes inherit CPU affinity `[0]` on the recorded AMD EPYC 9V45 host. The runtime is Dart 3.14.0 stable. No samples, process pairs, fixtures or adverse rows were dropped. Aggregate ratios divide the median candidate process percentile by the median baseline process percentile; samples from different processes or hosts are not pooled.

## Material observations

- **JIT small QR `rank_4x8` p95:** 217 to 2,633 microseconds per 256-call batch, **+1,113.4%**. Every paired process is slower at p95: +1,113.4%, +1,310.5%, +82.3%. Its aggregate p50 is 142 to 138 microseconds per batch (-2.8%). This is a retained adverse tail result; the underlying rank function is unchanged, so these data alone do not identify the cause.
- **JIT cold linkage p95:** 9,464 to 12,349 microseconds, **+30.5%**. All three pairs worsen (+3.7%, +30.5%, +43.8%). Aggregate p50 is +6.7%, with two of three individual pairs faster. The 2.885 ms p95 increase remains part of the integration tradeoff.
- **JIT selective coupler edit:** p50 improves 9.2%, with all three pairs faster; p95 worsens 12.1%, with mixed paired tail directions. JIT retained-angle and placement-only controls improve at both aggregate percentiles, with all three pairs faster.
- **AOT plate controls:** profile-edit p50 is +6.1% and p95 +20.4%; thickness-edit p50 is +11.2% and p95 +0.7%. Each median adverse row has two faster pairs and one slower pair. Ratio-of-medians and median paired ratios answer different questions, so neither direction is hidden.
- **AOT linkage controls:** aggregate retained-angle, coupler and placement medians improve 5.0–6.8%; cold and rejected-operation medians worsen 1.5–1.6%. All five aggregate p95 values improve, but individual pair directions are retained below.
- **Other small-QR tails:** JIT `rank_8x4` p95 is +49.9% (two slower pairs); AOT nullspace p95 is +17.3% (three slower pairs). These are bounded batch controls, not per-solve or browser latency claims.

## Complete control table

Changes are percent elapsed time; positive means slower. Pair counts are slower/equal/faster out of three. QR times are batches of 256 calls, except `rank_48x48`, which uses eight calls. CAD and linkage rows measure one operation. All raw process values and ratios are retained in the audit JSON.

| Runtime | Fixture / case | p50 change | p50 pairs S/E/F | p95 change | p95 pairs S/E/F |
|---|---|---:|---:|---:|---:|
| JIT | geometry_small_qr / rank_5x4 | -5.49% | 2/0/1 | -1.72% | 1/0/2 |
| JIT | geometry_small_qr / rank_8x4 | +0.90% | 3/0/0 | +49.88% | 2/0/1 |
| JIT | geometry_small_qr / rank_4x5 | +11.88% | 1/0/2 | -70.07% | 0/0/3 |
| JIT | geometry_small_qr / rank_4x8 | -2.82% | 2/0/1 | +1113.36% | 3/0/0 |
| JIT | geometry_small_qr / rank_9x4 | -6.78% | 0/0/3 | -4.24% | 1/0/2 |
| JIT | geometry_small_qr / rank_12x4 | -1.54% | 0/1/2 | -9.38% | 1/0/2 |
| JIT | geometry_small_qr / rank_16x8 | -2.48% | 1/0/2 | -27.95% | 2/0/1 |
| JIT | geometry_small_qr / rank_16x9 | -1.32% | 1/0/2 | +1.56% | 1/0/2 |
| JIT | geometry_small_qr / rank_17x8 | -0.74% | 1/1/1 | +2.21% | 2/0/1 |
| JIT | geometry_small_qr / rank_48x48 | +0.91% | 2/0/1 | +9.58% | 2/0/1 |
| JIT | geometry_small_qr / damped_solve_8x4 | -19.91% | 0/0/3 | -23.45% | 1/0/2 |
| JIT | geometry_small_qr / nullspace_4x8 | -58.05% | 1/0/2 | -92.76% | 0/0/3 |
| JIT | cad / cold_build_compile_regenerate | -12.98% | 1/0/2 | -3.95% | 2/0/1 |
| JIT | cad / profile_edit_regenerate | +1.39% | 2/0/1 | -13.61% | 0/0/3 |
| JIT | cad / thickness_edit_regenerate | -13.57% | 1/0/2 | -8.22% | 0/0/3 |
| JIT | cad_linkage / cold_build_solve_solids_meshes | +6.68% | 1/0/2 | +30.48% | 3/0/0 |
| JIT | cad_linkage / retained_angle_edit | -16.92% | 0/0/3 | -35.42% | 0/0/3 |
| JIT | cad_linkage / selective_coupler_length_edit | -9.16% | 0/0/3 | +12.11% | 2/0/1 |
| JIT | cad_linkage / placement_only_layer_edit | -5.48% | 0/0/3 | -54.47% | 0/0/3 |
| JIT | cad_linkage / downstream_rejected_angle_edit | +2.62% | 1/1/1 | -29.79% | 1/0/2 |
| AOT | geometry_small_qr / rank_5x4 | -11.01% | 0/0/3 | +10.09% | 2/0/1 |
| AOT | geometry_small_qr / rank_8x4 | -10.00% | 1/0/2 | -10.73% | 1/0/2 |
| AOT | geometry_small_qr / rank_4x5 | -12.10% | 0/1/2 | -14.04% | 1/0/2 |
| AOT | geometry_small_qr / rank_4x8 | -4.98% | 1/0/2 | -13.71% | 1/0/2 |
| AOT | geometry_small_qr / rank_9x4 | -20.65% | 0/0/3 | -33.07% | 0/0/3 |
| AOT | geometry_small_qr / rank_12x4 | -14.46% | 0/0/3 | -2.94% | 1/0/2 |
| AOT | geometry_small_qr / rank_16x8 | -1.83% | 0/0/3 | -7.47% | 0/0/3 |
| AOT | geometry_small_qr / rank_16x9 | -0.20% | 1/0/2 | +15.32% | 2/0/1 |
| AOT | geometry_small_qr / rank_17x8 | -6.30% | 0/0/3 | -10.19% | 0/0/3 |
| AOT | geometry_small_qr / rank_48x48 | -1.19% | 2/0/1 | -3.07% | 1/0/2 |
| AOT | geometry_small_qr / damped_solve_8x4 | -10.68% | 0/0/3 | -18.86% | 2/0/1 |
| AOT | geometry_small_qr / nullspace_4x8 | -2.15% | 2/0/1 | +17.25% | 3/0/0 |
| AOT | cad / cold_build_compile_regenerate | -2.44% | 1/0/2 | +2.19% | 1/0/2 |
| AOT | cad / profile_edit_regenerate | +6.09% | 1/0/2 | +20.37% | 1/0/2 |
| AOT | cad / thickness_edit_regenerate | +11.16% | 1/0/2 | +0.71% | 2/0/1 |
| AOT | cad_linkage / cold_build_solve_solids_meshes | +1.46% | 1/0/2 | -72.32% | 0/0/3 |
| AOT | cad_linkage / retained_angle_edit | -6.49% | 1/0/2 | -71.65% | 1/0/2 |
| AOT | cad_linkage / selective_coupler_length_edit | -4.97% | 1/0/2 | -55.25% | 1/0/2 |
| AOT | cad_linkage / placement_only_layer_edit | -6.85% | 1/0/2 | -66.04% | 0/0/3 |
| AOT | cad_linkage / downstream_rejected_angle_edit | +1.64% | 1/2/0 | -55.47% | 0/0/3 |

## Limits and integration boundary

Three process pairs and 25 measured samples establish this observed cohort; they do not establish statistical significance or a causal explanation. At this sample count, the plate p99 is each process maximum. CAD physical checks execute in the harness after each timer and preserve paired work, but these records do not serialize full geometry for an independent physical-oracle replay. The collector records compiler version and commands; it does not hash AOT executable bytes or installed dependency sources.

Real-browser validation is a separate unresolved boundary: the preserved Chromium attempts failed before assertions. Check current CI before describing platform/browser coverage. No library release or package publication is part of this recommendation. The prior native-rounding JIT coupler p99 issue and all earlier adverse sparse-control observations remain retained; this small-control cohort does not erase them.

## Reproduction

```sh
python3 tool/audit_sparse_small_cad.py small-cad-paired.json.gz small-cad-summary.json \
  --repo /path/to/dart_csp --check-live \
  --output small-cad-independent-audit.json
```

Omit `--check-live` when replaying an archive after the originally recorded detached worktree paths are unavailable; committed source/harness checks still require both source commits in the specified Git repository.

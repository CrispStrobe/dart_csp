# Sparse solver completion — 2026-11-14

## Recovered state

This continuation starts from the newest saved remote checkpoint,
`87cd622b0219601202bbefe0aa85c10e274f8bc0`. It contains source
`90f237f39c1fda6617d391a2efd5af2d96f75c3f` plus the frozen preparation and
36-job large-case qualification. Consolidated `main` remains
`135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.

An independent audit rechecked the saved archive hashes, source trees, raw
requests and native output, every physical-oracle verdict, operation counts,
and reported percentiles. All 36 jobs and 108 operations are complete: 96
feasible operations are accepted and 12 contradictions are rejected.

The final paired timing results and full validation logs described at the end
of the pasted handoff do not appear in any fetched remote branch. The reported
85–96% ladder improvement is therefore an unpreserved observation, not a new
accepted performance claim. Fresh results will be saved separately from the
older host's cohorts. Personal Context is unavailable; the attached handoff,
Git history and repository evidence define the recovery boundary.

## Current completion plan

1. Save each coherent source/evidence milestone to
   `perf/dart-sparse-direct-2026-11-14`, with expected-head checks and no history
   rewriting. Keep the original checkpoint branch intact.
2. Review the numerical implementation independently. Optimize the cold
   symbolic pivot scan only if exact deterministic ordering, work caps and
   cancellation semantics remain intact.
3. Save and validate the resulting source: formatting, fatal-info analysis,
   complete native tests, JavaScript and WebAssembly portability tests, and
   comparison-harness tests. Record the actual browser/CI boundary.
4. Freeze the final source and consolidated main through identical adapters,
   locked packages and the same Dart runtime. Rerun large-case correctness.
5. Run three alternating paired timing rounds after builds/tests stop. Include
   low-fill ladders, coupled graphs and below-threshold controls. Measure the
   2,000-coordinate dense-fill case separately and preserve failed outcomes.
6. Independently audit the new raw evidence, document limitations and the
   integration decision, and advance main only after the retained source has
   passed the applicable gates.

## Status

Recovery and the saved qualification audit are complete. Independent numerical
review found no concrete correctness blocker in the recovered implementation.
The candidate now walks a linked list of live columns during minimum-degree
ordering, preserving exact pivot ties while reducing cold candidate visits
from `n * n` to `n * (n + 1) / 2`. Work caps charge actual live visits and
cancellation polling remains active. A new exact-budget star regression covers
both interior and first-column removal and checks the numerical result against
an independent dense reference. All 53 focused sparse numerical/policy tests
pass. Full gates and controlled measurements are in progress; no timing
performance conclusion is accepted by this source checkpoint.

# Recover, consolidate, and optimize Dart CSP — 2026-11-14

## Request and preservation policy

The user requested recovery of interrupted work, integration of all recent
edits, pull requests and branches into a coherent `main`, a push to remote
`main`, and further optimization with incremental remote checkpoints.

This pass starts at main `b3e14fbb298c8d4f3714debbeaffaeb6d550db51`.
The working branch is `integrate/consolidate-optimize-2026-11-14`.
`benchmark/results/2026-11-14-consolidation/initial-branches.json` records all
31 remote branch heads observed before any changes. No branches or historical
results will be deleted or force-pushed. Rejected experiments will remain
reachable in ancestry without silently restoring their rejected source.

## Recovery findings and work in progress

- PRs #1–#6 are already merged. Open draft PR #7 contains additive comparison
  infrastructure through `43bb4dc21687a373b502d915a5e1567ea5ac3fb2`; its PR body
  describes older checkpoints and is no longer a complete inventory.
- Open draft PR #8 contains the retained native rounding implementation and
  recovery evidence through `6faf18a5b4a776755e5f47e47f520de4f1d89635`.
- The follow-up mesh source (`199ce0ce3eb7310d2f2d6b7b2fc2735e8a1ff6f9`) and
  operation-trace collector (`2a8db09124a1360d5132c804ef773b439a186b4c`) are
  separate branches. They require distinct review and integration decisions.
- Some comparison manifests reference raw archives that did not reach the
  remote branch before interruption. Their availability and evidential limits
  must be recorded; a summary is not a substitute for missing raw observations.
- The prior JIT coupler-length p99 regression is unresolved. Historical median
  gains must not be described as uniform tail-latency improvements.

## Execution plan

1. Save this recovery checkpoint remotely before source changes.
2. Audit branch ancestry, merge retained work, and record rejected experiments
   explicitly. Complete the comparison report from the evidence actually saved.
3. Run formatting, fatal-info analysis, native tests and relevant portable
   tests on the integrated source. Record browser/CI results separately.
4. Push the coherent integrated result to remote `main` without rewriting
   history, then implement and measure the next justified optimization.
5. Save source and result checkpoints throughout; finish with a current handover,
   reproducible commands, exact commit identities and remaining limitations.

## Consolidation decisions

All 31 initial remote branch heads are now ancestors of the integration branch.
PR #7's complete saved comparison infrastructure and PR #8's retained native
rounding implementation are integrated. The original source branches, rejected
experiments and every available result remain reachable. The six withdrawn
placement/bounds/all-target-rounding trials were merged with the reviewed retained
implementations; the already copied collector and harness changes needed only
ancestry integration. The exact classification is in
[the tail review](consolidation-tail-review-2026-11-14.md).

The mesh candidate was independently reviewed, then measured in four alternating
fresh pairs per JIT/AOT runtime: 48 reports and 64,000 measured samples. All
physical checks and matched-work checks passed. However, AOT coupler median/p95
rose 2.1%/3.3%, and angle-edit p95 worsened in every pair in both runtimes.
Plate medians improved about 4–5% under AOT. This mixed result does not qualify a
general interaction-latency improvement. The candidate source is rejected, while
its branch ancestry, portable semantic regression tests and full observations
are retained. See [all rows and provenance](consolidation-mesh-results-2026-11-14.md).

## Recovered comparison and repaired validation

The formerly missing [comparison results](geometric-solver-comparison-results.md)
now distinguish original measurements from recovery verification. Of 696 jobs in
saved summaries, 612 have full archived records. The 141 available archives match
their stored hashes; 84 declared archives were never uploaded. Those 84 jobs and
690 measured samples are explicitly summary-only. Rechecking all 8,950 available
records changes no physical acceptance verdict. The corrected confirmation view
qualifies 72 groups/216 jobs, not the original 100 groups/300 jobs.

The recovery fixes reject boolean coordinates, invalid/nonfinite physical
tolerances and malformed operation indices, including direct oracle calls.
Sparse qualification now requires constructed feasible cases to pass; agreement
between two rejection flags is insufficient. Future Ceres builds verify pinned,
clean dependency bytes and record content digests. Historical manifests are
preserved without retroactively claiming that stronger provenance. Forty-one
Python comparison tests cover the repaired harness and dependencies.

The Eigen sparse-step adapter remains an explicit native benchmark experiment.
Production remains pure Dart. The next production experiment targets the same
large linear-step bottleneck with a bounded portable sparse implementation;
its source, measurements and acceptance decision will be recorded separately.

## Validation boundary

Consolidated production library tree:
`a9fc347644d9d0cfdc52c460bdc222ae2678958e`.
Consolidated Dart test tree:
`3bc9d3b881ab7c6cdfebf995fc15db64484b7b1a`.
The only retained production change against starting main is guarded native
interval-rounding word access. CAD placement, reference tessellation and the
numerical geometry implementation match starting main at this boundary.

The first combined baseline passed 1,807 native tests and zero-change formatting.
Its 17 sparse-prototype analyzer infos were repaired; the original failure log
is preserved. The consolidated tree with the mesh regression tests passes
**1,809 native tests**, formatting and fatal-info analysis. The 41 comparison
tests and eight benchmark-runner/collector tests pass. The final 48-file corpus
passes **488 tests under Node JavaScript and 488 under Node WebAssembly**.
The complete record is in
`benchmark/results/2026-11-14-consolidation/final-consolidation-validation/`.

The actual local Chromium attempt exited before assertions because its
process-singleton socket was denied. That attempt is recorded as blocked, with
zero browser tests passed. Node compiled-code tests and older CI success are
not substituted for current real-browser coverage.

## Remote checkpoint trail

The branch is updated through GitHub's Git-data API with expected-head checks,
because this workspace's plain Git transport has read access but no push
credential. Each published tree is required to match the local Git tree SHA
exactly. The publisher preserves ordered merge parents and uses non-forced ref
updates; subsequent fetches verify the remote tree before aligning local HEAD.

| Checkpoint | Preserved work |
|---|---|
| `24ab1d9` | Initial plan and exact 31-branch inventory |
| `9325b27`, `0d132f4` | Recovered PR #8 and PR #7 histories and files |
| `1f5b1f4` | Strict physical oracle and feasible-outcome qualification |
| `4e4be21`, `c6aa76c` | Independent tail review and rejected-trial ancestry |
| `83001ff`, `e9cb980` | Dependency provenance repairs, lint fixes and baseline logs |
| `0455173` | Mesh trial checkpoint after 20 of 48 reports |
| `a784b72`, `88438af` | Recovered comparison report and mesh-history/test integration |
| `557aa35` | Expanded portable/browser regression corpora |
| `ff3b31e` | Complete mesh measurements, independent audits and rejection decision |

Later commits on the same branch contain final gates, main integration and the
next optimization. In-progress measurements are never relabeled as completed;
Git history retains both partial and complete checkpoints.

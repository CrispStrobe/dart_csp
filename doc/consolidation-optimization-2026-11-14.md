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

This document is an incremental work record, not a completed validation claim.

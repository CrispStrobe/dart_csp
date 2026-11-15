# Conservative source decision — 2026-11-15

**Revert the provisional CG residual-norm fusion.** Five of the eight declared
timing blocks were recovered from the remote branch; the status of any unpushed
original output is unknown. The predeclared protocol
requires the complete cohort and forbids adding timings from another session,
replacing the cohort, or extending the run to seek a favorable result.

The retained `lib/src/geometry/numeric.dart` is restored byte for byte from
baseline `49234b3d418d6253dd7f377b54650e74e3941372`. The retained library tree is
`16214e4755dbd7df711bfd4901b126990b11ab45`, also the library tree of main
`46288eb23f04c2a2f2210088fe568285bea6114f`. The restart portability repair,
all three new numeric contract regressions, existing CG/manifold regressions,
and browser/portable coverage remain. No public API changes are introduced.

This rejects retention because the evidence is incomplete; it does not assert
that the candidate is numerically incorrect or that its performance is slower.
The candidate's earlier passing correctness gates and all frozen inputs/raw
measurements remain immutable. Partial timing observations are reported
descriptively in `partial-audit/partial-audit.md`, without a four-round gate pass
or a new accepted speed claim.

Fresh validation of the restored library with the retained regression tests
passes: 1,895 native, 578 JavaScript, 578 WebAssembly, 12 focused and 78 Python
harness tests, with clean formatting/analysis and unchanged source inputs.
Local validation is saved at `e6512c3`; exact partial replay is saved at `d2f58bc`.
Fresh GitHub Chrome also passes all 222 targeted tests on exactly the retained
source; its log and source proof are in `ci-final/`. Run `43685263894` and
attempt 1 completed successfully at 2026-11-15 07:45:07 UTC: all 16 validation
jobs passed, including all nine OS/SDK combinations. No pending, failed or
cancelled jobs remain. The three conditional full-browser, performance and
release jobs were skipped. Terminal proof and an independent check are saved
at `c772f44` in `ci-final/final-ci.json` and companion files. The earlier queued
observation at `0fb2403` is preserved unchanged as historical evidence.
See `source-decision.json`, `recovery.json`, and
`doc/cg-norm-closure-2026-11-15.md` at the repository root. No new timing has
been collected.

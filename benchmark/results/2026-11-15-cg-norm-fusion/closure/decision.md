# Conservative source decision — 2026-11-15

**Revert the provisional CG residual-norm fusion.** The original session ended
with five of the eight declared timing blocks saved. The predeclared protocol
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
measurements remain immutable. Partial timing observations will be reported
descriptively after replay, without a four-round gate pass or a new speed claim.

Fresh validation of the restored library with the retained regression tests
passes: 1,895 native, 578 JavaScript, 578 WebAssembly, 12 focused and 78 Python
harness tests, with clean formatting/analysis and unchanged source inputs.
Local validation is saved at `e6512c3`; exact partial replay is saved at `d2f58bc`.
The fresh GitHub source-bound CI is recorded separately and remains in progress
at this checkpoint. See `source-decision.json`, `recovery.json`, and
`doc/cg-norm-closure-2026-11-15.md` at the repository root. No new timing has
been collected.

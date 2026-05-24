# Handover — clean-room rewrite of `example/demo.dart`

You are the first session in a fresh `dart_csp` repository. The repo was
just created from the post-audit state of the prior `dart_csp`
(which has been renamed and made private). Your **only** job in this
session is to write fresh, independent versions of three demo examples
so the new repository's MIT `LICENSE` is unambiguous over the demo
file too. After that's done, normal roadmap work resumes — see
`HANDOVER.md` for ongoing context.

---

## 1. Why this handover exists

A contamination audit on the prior repository found that three
sections of `example/demo.dart` were carried over from the predecessor
project (a Dart port of the unlicensed `PrajitR/jusCSP` /
`csp.js`) without being rewritten when the solver clean-room rewrite
happened. The clean-room scope at the time was `lib/src/solver.dart`
only; `example/demo.dart` slipped through.

The contaminated functions in the prior repo were:

1. **`solveMapColoringOldWay`** + `runMapColoringDemo` — was a port of
   the upstream's US map-coloring demo. Same `neq` helper identifier,
   same four-color palette, same per-state per-neighbor constraint loop.
2. **`solveNQueensOldWay`** + the `notColliding` predicate — was a port
   of the upstream's N-queens demo. Same `not_colliding` → `notColliding`
   only-camelCase rename, same unusual "one variable per row, domain =
   list of `[row, col]` lists" modeling choice (most independent
   encodings use a single `int` column per row).
3. **`getUsaNeighbors()`** — was a Dart map-literal transliteration of
   the upstream's `state_neighbors.json` file. Same 50 + DC entries in
   the same iteration order, same inclusion of empty `HI`/`AK`.

The Sudoku demo and the all-different / all-equal demo were verified
clean (different problem instances, different keying, different
identifiers) and have been carried over.

## 2. What's in this repo right now

Everything from the prior repo except the contaminated functions:

- `lib/src/solver.dart` — already clean-room (attestation block at the
  top of the file). Untouched.
- `lib/src/problem.dart`, `types.dart`, `builtin_constraints.dart`,
  `constraint_parser.dart` — clean. Untouched.
- `test/` — all 25 files, 440 cases, untouched. `dart test` should
  pass on this commit.
- `example/example.dart`, `example/gencw.dart`, `example/gensq.dart`,
  `example/multi_solutions.dart` — clean. Untouched.
- `example/demo.dart` — **the three contaminated functions and their
  callers + helper data have been removed**; the clean sections
  (Sudoku, all-different/all-equal, etc.) remain. The file currently
  does not reference the missing functions, so it should still
  compile and run.
- `README.md`, `PLAN.md`, `CHANGELOG.md`, `STABILITY.md`,
  `HANDOVER.md`, `NOTICE`, `LICENSE` — carried over. `NOTICE` may
  want a short addendum after this work (see §6).

If you find the file doesn't compile because some `main()` still
references a deleted demo function, fix that referent — that's part
of the cleanup, not new content.

## 3. What you must write

Write replacements for the three demo problems. Each must satisfy
the requirements in §4 below.

1. **A map-coloring demo.** Use a different map than the contiguous
   USA. Reasonable alternatives: Australian states/territories (the
   classic AIMA example, 7 regions including the Northern Territory
   and ACT), German Bundesländer (16 regions), Swiss cantons, the
   countries of the South American mainland (12 regions), or
   another small graph of your choosing. Whatever you pick, derive
   the adjacency list yourself from a public geographic reference
   you cite in a comment — do **not** transliterate a pre-existing
   adjacency JSON / list.

2. **An N-queens demo.** Use the textbook encoding: one variable
   per row, domain = the integer columns `[0, ..., N-1]`. The
   pairwise constraint between row `i` and row `j` rejects an
   assignment when the columns are equal *or* when the row delta
   equals the column delta (diagonal attack). This is the AIMA
   formulation; do **not** use a list-of-`[row, col]` domain.

3. **A "manual `CspProblem` + `BinaryConstraint`" demonstration.**
   The prior `*OldWay` functions existed to contrast the
   low-level `CSP.solve(CspProblem(...))` API against the
   `Problem` builder. That contrast is genuinely useful; pick one
   small problem (a 4-variable arithmetic puzzle, a tiny graph
   coloring, a `A < B < C` ordering — your choice) and show both
   the manual and the builder formulations side by side. Don't
   reuse the queens or map-coloring problem you wrote above — use a
   distinct third example so each demo stands on its own.

Each demo should print its result and a short visualization (an ASCII
board for queens, a state-to-color table for map coloring, etc.).
The existing clean demos in `example/demo.dart` are the template for
prose and output style.

## 4. Clean-room methodology — non-negotiable

These constraints exist to make the audit story for this repository
defensible:

- **Do not read**, fetch, grep, or otherwise inspect any of:
  - `https://github.com/PrajitR/jusCSP` (the upstream)
  - `https://github.com/CrispStrobe/jsCSP` (the maintainer's fork
    of the upstream)
  - `https://github.com/CrispStrobe/dartCSP` (the now-private
    predecessor; the prior `dart_csp` repo will also be renamed to
    private after this clean-room session)
  - The git history of *this* repo for the three deleted functions
    (`git log -p` or `git show` on the initial / pre-deletion commit
    is forbidden — if you need to know what was there beyond what's
    in this document, you've already overspecified your design).
- **Do reference**: textbook CSP material — AIMA chapter on CSPs,
  Mackworth's 1977 AC-3 paper, Wikipedia for textbook problem
  encodings — and the cleanly-originating non-`demo.dart` files in
  this repo (`example/example.dart` is a fine local reference for
  Dart conventions in this codebase).
- **Distinct identifiers.** Your replacement code must not use the
  identifiers `notColliding`, `not_colliding`, `neq`, `solveNQueens*`
  (the `*OldWay` / `*WithBuiltins` split), `solveMapColoring*`, or
  `getUsaNeighbors`. Pick names that fit your chosen problem and
  Dart conventions.
- **Distinct modeling.** Don't accidentally re-converge to upstream
  choices: integer-column N-queens (per §3.2) is the textbook
  encoding and reaches independently; the Australian / German /
  Swiss / South American maps avoid the US-states data entirely.
- **One coherent commit.** Land everything in a single commit
  titled `clean-room: rewrite example/demo.dart` (or similar). Body
  should explain that this closes the contamination found in the
  prior audit and that the rewrite was performed without reading
  the prior file or upstream sources. Include a "Co-Authored-By"
  trailer matching the pattern of recent commits.

## 5. Acceptance criteria

Before committing:

```bash
dart format --output=none --set-exit-if-changed .   # zero changes
dart analyze --fatal-infos                          # zero issues
dart test                                           # 440 passing
dart run example/demo.dart                          # runs to completion
```

The three demos must actually solve their problems and print results;
don't ship stubs.

## 6. After remediation

Once the demos commit lands:

- Add a short paragraph at the bottom of `NOTICE` recording that the
  clean-room scope was extended in this session to cover
  `example/demo.dart`. The existing `NOTICE` already documents the
  solver rewrite; this is an analogous note for the demo file.
- Delete this file (`REWRITE-DEMOS.md`). It's a one-shot directive;
  once the work is done it's noise.
- Resume from `HANDOVER.md` §6 ("What's left in PLAN.md, and how to
  pick"). The previously-recommended next item is the worker-isolate
  runner; nothing about this remediation session changes that.

Good luck. Don't peek.

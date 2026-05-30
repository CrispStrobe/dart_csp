# Handover — continuing work on `CrispStrobe/dart_csp`

You are picking up work on `CrispStrobe/dart_csp`, a pure-Dart
Constraint Satisfaction Problem solver. Post-clean-room-rewrite
(see `NOTICE`), MIT-licensed, 2.1.0+. Every Tier 1/2/3 item from
the original plan has shipped (the full done record now lives in
`HISTORY.md`); the remaining work lives in the **Strategic gaps**,
**Tactical wins**, and **Edge/workload-gated** sections of `PLAN.md`.

The most recent landings (in order, newest first):

- **`bench(cumulative)` energetic-reasoning perf anchor + `useEnergeticReasoning`
  opt-out.** Closes the perf-evidence gate the ER landings shipped without
  (they validated *soundness*, never *speed*). New public
  `useEnergeticReasoning` flag (default `true`) on `addCumulative` /
  `CumulativeSpec` opts out of the O(n³) ER pass — a **perf-only** knob
  (gated in `_CumulativePropagator.propagate` via `spec.useEnergeticReasoning`;
  toggling it never changes the solution set, only stats/wall-clock). A new
  `bench(cumulative)` section (helper `_benchCumulative`, builders
  `buildCumulativeErRootOverload` / `buildCumulativeErInSearch`) anchors ER on
  two tight 8-task / cap-2 UNSAT RCPSP instances under plain backtracking +
  the standard 5-warmup / 25-rep median: **overload-at-root 871 dec / 43 ms →
  0 dec / 0.05 ms**, **in-search 770 dec / 28 ms → 112 dec / 8.8 ms** (~3×
  wall-clock, ~7× decisions). README "Cumulative resource scheduling" gains
  the anchor table; STABILITY.md documents the flag. 3 new tests
  (`test/cumulative_edge_finding_test.dart`); **1092 total** (was 1089). The
  instances were found by an offline ER-on-vs-off decision-count sweep, then
  wall-clock was confirmed (ER's cubic cost is repaid on these tight
  instances — reported honestly).

- **Run the energetic-reasoning overload check under LCG (follow-up to the
  ER landing below).** The ER pass was originally gated *fully* off under
  LCG. Now the energetic **overload check** runs under LCG too — only the
  bound *adjustments* stay off under learning (their prunes have no
  explanation companion, so an opaque reason would degrade clause
  learning). `_energeticReasoning` gained a required `adjustBounds:` flag
  (`!_lcgEnabled` at the call site); the call-site gate dropped `!_lcgEnabled`
  so the pass runs whenever `n <= _erMaxTasks`. **Why it's sound + still
  learns:** an over-capacity energetic window is a sound conflict, and the
  engine already wires every cumulative `propagate()` failure to
  `_cumulativeConflictReason` — a coarse bridge over the tasks' *current*
  bound atoms, which entail the window energy. So a mid-search overload
  yields a learnable clause; a **root** overload (all domains original →
  empty reason → bail) is reported as immediate UNSAT (0 decisions) instead
  of being rediscovered by branching. **Verified:** the M3e 480-run LCG
  verdict-parity sweep vs full enumeration still passes (SAT validity +
  unique-solution exact + UNSAT parity); the M3e learning-activation test
  was re-anchored on an instance the *time-table* path drives (so it still
  guards time-table learning — ER no longer short-circuits it); a new
  root-detection regression test pins the 0-decision UNSAT on an
  energetic-window instance. Full suite green, **1089 total** (was 1087).
  *Future work unchanged: a full O(n log n) edge-finder, and an ER
  explanation that enables the bound adjustments under LCG too.*

- **Energetic-reasoning filtering for `addCumulative` (Baptiste, Le Pape &
  Nuijten 1999).** A second filtering pass added to `_CumulativePropagator`
  on top of the time-table profile. Over the Baptiste–Le Pape–Nuijten
  relevant-interval set (`O₁×O₂` endpoints) it (a) sums each task's
  *minimum-intersection* energy `MI_a = max(0, min(p_a, t2−t1,
  est_a+p_a−t1, t2−lst_a))·h_a` per window and fails when it exceeds
  `C·(t2−t1)`, and (b) tightens `est`/`lct` via the left-shift /
  right-shift adjustment `est_i ← t2 − ⌊avail/h_i⌋` (avail = window
  capacity minus *other* tasks' mandatory energy). **Why ER not a classic
  edge-finder:** ER is provably sound from first principles, whereas
  Nuijten-style edge finders use an invalid dominance rule and are
  incomplete (Mercier & Van Hentenryck 2008) — and the user explicitly
  required patent/licence-clean ideas (ER is 25+ yr old published math,
  present in Gecode/OR-Tools/Choco; implemented from the formulas, no
  solver source copied). Gated off when `_lcgEnabled` (explanations are
  time-table-shaped) and above `_erMaxTasks = 64` (cubic cost); both fall
  back to the still-sound time-table. **Verified** by a 4000-instance
  random soundness sweep (solver's full solution set == brute-force
  feasibility, 0 mismatches) plus 5 new tests
  (`test/cumulative_edge_finding_test.dart`); **1082 total** (was 1077),
  full suite green. *Future work: a full O(n log n) edge-finder, and
  making ER prunes LCG-explained (currently it carries no reason, so it's
  disabled under learning).* **Tooling note (resolved):** the garbled /
  duplicated text seen in Bash tool results during this work was traced to
  a misbehaving `PostToolUse` Bash hook (`~/.claude/hooks/annotate_output.sh`)
  that appended random first-person phrases plus a truncated stdout copy to
  every result. It was removed from `~/.claude/settings.json` (now `{}`) and
  the script neutralised to a no-op; the channel is clean again. If
  anything similar recurs, check `~/.claude/settings.json` hooks first and
  trust process exit codes / file bytes over streamed stdout.

- **FlatZinc lexicographic set order (`set_lt` / `set_le` + reified) +
  empty-universe hardening.** Follow-up to the set-of-int landing below.
  `set_lt` / `set_le` / `set_lt_reif` / `set_le_reif` implement MiniZinc's
  lexicographic set order — two sets compared as their sorted-ascending
  element lists, the shorter smaller when a prefix (`{} < {1} < {1,2} <
  {1,2,3} < {1,3} < {2} < {2,3} < {3}`). The semantics were **verified
  against the MiniZinc `test_set_lt` spec tests** (fetched via `gh`,
  since the handbook docs are admittedly fuzzy — see libminizinc issue
  #339): the order is *not* a single-bit rule, so the handler posts one
  predicate (`_compareSetsLex`) over both operands' membership bits that
  reconstructs and compares the sets; an 8-link `set_lt` chain over the
  subsets of `1..3` reproduces the spec order exactly. Empty-universe set
  vars (`var set of {}` / empty range) now raise a clear
  `UnimplementedError`. 8 new tests (36 total in
  `test/flatzinc/set_of_int_test.dart`); **1077 total** (was 1069). The
  FlatZinc set surface is now complete bar array-of-set element/lookup
  constraints. *Next per the user's plan: edge-finding cumulative
  (Vilím 2007) — see `PLAN.md` Tactical wins.*

- **FlatZinc `var set of int` + the set constraint family.** The FlatZinc
  frontend now accepts bounded set variables (`var set of L..U`,
  `var set of {…}`) and maps them onto the shipped set-variable layer (one
  0/1 indicator per universe element). Set parameters (`set of int: U =
  1..5;`), set-variable right-hand sides (literal pin `= {1,3}` /
  identifier alias `= other`), and arrays of set variables
  (`array[..] of var set of L..U`) are supported. New handlers: `set_in`
  (extended to the set-variable form alongside the existing constant-set
  form) + `set_in_reif`, `set_card` (const / var cardinality), `set_eq` /
  `set_ne` / `set_subset` / `set_superset` (all four with `_reif`
  variants), and `set_union` / `set_intersect` / `set_diff` /
  `set_symdiff`. The relations are decomposed **element-wise over the
  union of the operands' universes** via a `SetArg` abstraction +
  `Problem.memberIndicator` (so operands with differing universes compose
  — `set_union` of a `1..3` set and a `3..6` set into a `1..6` set is
  exact), reusing the existing `_postArithmetic` operand-predicate poster
  (which already dispatches static / binary / n-ary). Output renders set
  values as FlatZinc set literals (`{}` / `lo..hi` contiguous / `{a, b,
  c}`). Unbounded `var set of int` is rejected (finite universe required);
  `set_le` / `set_lt` lexicographic ordering stays unsupported. Pure
  frontend work — the set-variable layer pre-existed. Two earlier tests
  that asserted set-of-int *rejection* were updated; one
  unsupported-builtin test swapped to a float builtin. 28 new tests
  (`test/flatzinc/set_of_int_test.dart`); **1069 total** (was 1040). See
  `doc/flatzinc.md` → "Set variables" and the closed Tactical-wins entry
  in `HISTORY.md`.

- **LCG parallel portfolio + cooperative clause sharing
  (`solveWithLcgInIsolates`).** A new parallel entry point runs
  `solveWithLcg` across N worker isolates as a portfolio (distinct seeds,
  `useVsids` on by default for diversity); first SAT wins, `'FAILURE'` only
  once every worker exhausts (a cancelled worker is never read as UNSAT).
  `shareClauses: true` makes it cooperative: workers export short learned
  clauses (≤ `maxSharedClauseLen`) to the parent, which re-broadcasts to
  siblings; each worker imports them via two new `solveWithLcg` engine
  hooks — `onLearnedClause` (export, fired at both learn sites) and
  `importClauses` (drained at `_checkpoint`, posted via `_postLearnedClause`
  so they register in `_naryIdx` and fire on the next var change; the
  checkpoint `await` yields so the control listener can deliver clauses
  first). `Atom`s are sendable as-is (no serialisation). Sound — every
  worker solves the same problem — and verdict-preserving (validated SAT +
  UNSAT; 122 clauses imported into the winner on pigeonhole 7-in-6, UNSAT
  intact). New `SolverStats.importedClauses`. Built in two commits
  (portfolio runner, then sharing); 9 new tests
  (`test/isolate_runner_test.dart`); **1040 total**. **Experimental.** This
  closes the last optional LCG-polish follow-up (the other, the
  `bench(lcg)` scheduling rows, shipped just before).

- **LCG M3g — `_CircuitPropagator` explanation companion. M3 is COMPLETE;
  the LCG strategic gap is CLOSED (`[~]` → `[x]`, moved to `HISTORY.md`).**
  The circuit/subcircuit constraint, the last opaque propagator, now
  learns. New `CircuitReason`; every prune/conflict is driven by the
  current **fixed edges** (singleton-pinned successors `vars[i] = v`), so
  the antecedents are `AtomEq(vars[i], v)` atoms (the assignment shape that
  unlocked allDifferent/GCC) collapsed through one `AtomInScc` bridge: the
  chain-closing prune cites the chain's edges (`_chainReason`), the
  uniqueness prune the single owning edge, and a coarse all-fixed-edges
  bridge (`_circuitConflictReason`) covers every `return null` conflict.
  **Subcircuit-specific prunes** whose soundness depends on other nodes'
  skip-accounting (force-skip, head/forceHead) deliberately pass
  `reason: null` (opaque, sound) rather than an unsound partial reason.
  Sound across a random-circuit sweep (×4 seeds vs full enumeration, **0
  mismatches**, Hamiltonian-cycle SAT solutions, unique-exact) with **0
  analysis failures** — every backtrack converged. 5 new tests
  (`test/lcg/circuit_explain_test.dart`); **1031 total**. With this, **all
  eight specialised propagators are explained** — see the closed strategic
  gap in `HISTORY.md`. References: Caseau & Laburthe 1997; Francis &
  Stuckey 2014.

- **LCG M3f — `_DiffNPropagator` forbidden-region explanation companion.**
  The 2D non-overlap (`diff_n`) constraint now learns. New `DiffNReason`;
  per pruned rectangle coordinate the propagator witnesses the blocking
  rectangle per removed value and commits one `AtomInScc` bridge over the
  bound atoms of `r`'s *orthogonal* coordinate (half the mandatory-overlap
  test — never the pruned coordinate, avoiding circularity) and the witness
  `s`'s two coordinates (the other half + the forbidden interval), all
  trail-matching via the shared `_trailBoundAtoms` (factored out of M3e's
  `_taskBoundAtoms`). Engine wiring mirrors M3e + `_diffNConflictReason`.
  **Soundness** rests on monotonicity: tightening a domain only *grows* a
  rectangle's compulsory part and forbidden interval, so the asserted
  bounds entail the prune in any tighter state. Like cumulative the sweep
  is **not** GAC, so both UNSAT and satisfiable packings search and learn.
  Validated by a random-packing sweep × 4 seeds vs full enumeration — **0
  mismatches**, non-overlapping SAT layouts, unique-solution exact match. 5
  new tests (`test/lcg/diffn_explain_test.dart`); **1026 total**.
  `LCG_PLAN.md` §M3f marked shipped; **only M3g (circuit) remains.**
  Reference: Beldiceanu & Carlsson 2001.

- **LCG M3e — `_CumulativePropagator` time-table explanation companion.**
  The cumulative constraint now learns. New `CumulativeReason`; the
  propagator gains the M3a/M3d plumbing (`originalDomains:` + `recordScc:`
  + `reason:` kwarg) and, per pruned task, finds a witness overload time
  per removed start value, collects the *other* tasks whose compulsory
  parts cover it, and commits one `AtomInScc` bridge over their
  compulsory-part bound atoms. Engine wiring mirrors M3a +
  `_cumulativeConflictReason` (a bound-scope bridge via the new
  `_boundShapeAntecedents`). First consumer of bound-atom trail emission.
  **Trail-shape detail (the M3d lesson):** `_taskBoundAtoms` emits
  `AtomEq(start_k, s_k)` for a *pinned* contributor (what a decision /
  boolean pin records) **plus** any tightened `AtomGe`/`AtomLe` (what a
  propagation pin records) so whichever is on the trail resolves; original
  bounds are omitted (root facts). The time-table propagator is **not**
  GAC, so both UNSAT *and* satisfiable instances search and learn (unlike
  regular). Soundness validated by an 800-instance random-RCPSP sweep
  (±precedence) × 4 seeds vs full enumeration — **0 mismatches**, valid SAT
  schedules, unique-solution exact match (~75% of backtracks converge to a
  learned clause). 5 new tests (`test/lcg/cumulative_explain_test.dart`);
  **1021 total**. Reference: Vilím 2009.

- **LCG — bound-atom trail emission (M3e/M3f prerequisite).**
  `_recordImplications` now records `AtomGe(var, newMin)` when a prune
  raises a variable's min and `AtomLe(var, newMax)` when it lowers the max,
  computed in the single existing pass over the old domain, *in addition
  to* the per-removed-value `AtomNe` (emit-both, not replace). Sound (a
  bound atom is the conjunction of the value-removals it summarises, each
  entailed by the prune's reason) and **behaviour-neutral**: bound atoms
  are a distinct atom type, never collide with an existing trail atom,
  never enter a learned clause until a reason references them, and roll
  back in lockstep (they share the prune's `trailIndex`). This is the hard
  prerequisite that unblocks **M3e (cumulative)** and **M3f (diff_n)**,
  whose natural explanations are bound-shaped. Validated by the full suite
  staying green plus 2 focused trail tests (min-raise → `AtomGe`,
  max-lower → `AtomLe`); **1016 total**. `LCG_PLAN.md` §M3 marks the
  prerequisite shipped; M3e/M3f now build directly on it.

- **LCG M3d — `_RegularPropagator` explanation companion.** The `regular`
  constraint is no longer opaque to conflict analysis. New `RegularReason`;
  the propagator gains the M3a/M3c LCG plumbing (`originalDomains:` +
  `recordScc:` + a `reason:` kwarg) and commits **one synthetic `AtomInScc`
  bridge per pruned position** whose antecedents are the entry-snapshot
  value removals of the *other* positions (excluding the pruned variable
  avoids the circularity trap) — sound because layered-DFA reachability is
  monotone in the domains. Engine wiring mirrors M3a + a new
  `_regularConflictReason`. **The unlock (traced, not guessed):** the
  textbook `AtomNe`-per-absent-value shape bailed on *every* conflict —
  regular grids are *boolean*, and `_recordImplications` records a boolean
  singleton collapse as `AtomEq(var, survivor)`, **not** per-value
  `AtomNe`, so the `AtomNe` antecedents were absent from the trail and the
  analyser mis-classified them as root facts (0 at-level atoms → bail). The
  new `_regularTrailAbsences` helper emits the trail-matching `AtomEq` for
  pinned booleans (the regular analogue of allDifferent's singleton-SCC
  *assignment* unlock — and the reason the M3a "don't emit `AtomEq` in
  `_domainShapeAntecedents`" gotcha does **not** apply here). `regular` is
  GAC-strong, so satisfiable grids solve at the root with no learning;
  learning manifests on **UNSAT** grids (a 5×5 binary "exactly-k-ones" grid
  with incompatible margins learns ≥ 1 clause across 8 VSIDS orders and
  proves UNSAT). Soundness validated by a ~160-instance binary+ternary,
  SAT+UNSAT verdict-parity sweep vs full enumeration (**0 mismatches** —
  verdict parity + valid SAT assignment + unique-solution exact match). 6
  new tests (`test/lcg/regular_explain_test.dart`); **1015 total**.
  `LCG_PLAN.md` §M3d marked shipped; M3e–g remain (M3e/M3f gated on
  bound-atom trail emission). Reference: Pesant 2004; Beldiceanu et al. 2007.

- **LCG M5 polish — worked-example doc + roadmap refresh.** `doc/lcg.md`
  gained a "Worked example: learned clauses on pigeonhole 4-in-3" section
  (the real 5-clause progression with decision levels — unit clauses that
  pin variables, the width-3 first-UIP clause driving the one backjump,
  recursive contrast). `PLAN.md`'s LCG entry refreshed: all of M4 shipped +
  iterative is now the default; **M3d–g** (regular / cumulative / diff_n /
  circuit `explain` companions) is the remaining open LCG work, keeping the
  strategic gap `[~]`. Docs-only; **1009 tests** unchanged.

- **LCG M4 — iterative CDCL engine is now the DEFAULT for `solveWithLcg`.**
  `useIterativeCdcl` defaults to `true` on `CSP.solveWithLcg` /
  `Problem.solveWithLcg` (the engine constructor still defaults false so
  non-LCG paths are untouched). Backed by the `bench(lcg)` evidence
  (iterative beats recursive on wall-clock on every row). **Behaviour
  change:** `solveWithLcg()` now backjumps non-chronologically by default
  (`SolverStats.backjumps > 0` on CNF); pass `useIterativeCdcl: false` for
  the recursive fallback (still sound + complete). The recursive path stays
  tested: `pigeonhole_test.dart` (the M2b recursive acceptance suite) and
  the recursive-vs-iterative comparison in `iterative_cdcl_test.dart` now
  pin `useIterativeCdcl: false`. M4 item 1 is fully closed. **1009 tests**
  (no count change — recursive-path tests re-pinned, not removed). Docs:
  LCG_PLAN.md, CHANGELOG.md, README.md, STABILITY.md, doc/lcg.md.

- **bench(lcg) — iterative-engine + restart rows (make-default evidence).**
  `bench(lcg)` now prints three engines per row (plain / recursive `lcg` /
  iterative `iter`) plus a restart-showcase row on a heavy-tailed
  satisfiable random 3-SAT instance (new `buildRandom3Sat`). The iterative
  engine beats recursive LCG on wall-clock on *every* row (pigeonhole
  7-in-6 66ms → 23.5ms, 8-in-7 467ms → 134ms; 8-queens a wash), and the
  restart row shows ~2.3× fewer decisions / ~2.8× faster (421 dec / 168ms →
  184 dec / 60ms). This is the non-regression evidence the "make iterative
  the default" decision needs — but the flip itself (changing
  `useIterativeCdcl`'s default) is left as a deliberate maintainer call
  (it changes `solveWithLcg()` for every caller). LCG console format gained
  `rst:`. `doc/lcg.md` perf anchor refreshed (three-engine table + restart
  numbers). No new tests (benchmark-only); **1009 total**.

- **LCG M4 — Luby restarts + phase saving (iterative CDCL engine).**
  `useRestarts: true` / `restartScale` on `solveWithLcg` (iterative path):
  once the per-restart conflict budget `luby(i) * restartScale` is spent,
  the engine drops the search tree back to the root (`_backjumpTo(0)` +
  re-propagate; root wipeout ⇒ UNSAT) while *retaining* the learned-clause
  pool and the activity / wdeg tables. **Phase saving** (`_savedPhase`,
  recorded in `_trailRollback` on unassignment, preferred at decision
  time) is the companion that makes restarts pay — without it a restart
  re-derives the good partial assignment. **Measured:** heavy-tailed
  satisfiable random 3-SAT (n=100, ratio 4.26) under VSIDS, ~27% fewer
  decisions in aggregate, often ~2× (seed 5 421 → 184); UNSAT takes a
  modest hit, so off by default. Sound + complete — verdict parity with
  plain across the 3-SAT sweep, and Inkala (allDiff + GCC) solves
  correctly with restarts force-fired (24 runs). Completeness via the
  growing Luby budget. New `SolverStats.restarts`. 4 new tests
  (`test/lcg/restart_test.dart`); **1009 total**. Remaining in M4: make
  the iterative engine the default after a full-suite non-regression
  benchmark.

- **LCG M4 — VSIDS / dom-wdeg learned-clause activity bump (iterative
  CDCL path).** The iterative engine now applies the canonical CDCL rule:
  bump the activity (VSIDS) / wdeg weight (dom/wdeg) of every variable in
  the *learned clause* at post time, via `_onConflict(learned)` on the
  `NaryConstraint` that `_postLearnedClause` now returns — not just the
  detecting constraint's scope (the only prior signal, bumped in
  `_propagate`). Without it VSIDS diverged badly (pigeonhole 8-in-7 ~6251
  decisions vs MRV's 829); with it VSIDS tracks the learned structure
  (~4387, −30%; 9-in-8 41551 → 26207, −37%). Sound + complete (only the
  picker order changes; re-validated by the known-solution sweep, which
  runs `useVsids: true` × 20 + dom/wdeg). **MRV stays the default and the
  better picker** on these structured instances; the bump's real payoff is
  paired with restarts — the next M4 item, which needs a heavy-tailed
  benchmark instance to anchor (none in the suite yet; pigeonhole is UNSAT
  where restarts don't help). Recursive default path left unchanged. 2 new
  tests (`test/lcg/iterative_cdcl_test.dart`); **1005 total**.

- **LCG M4 item 1 — recursive learned-clause minimisation
  (Sörensson & Eén 2009).** `firstUipAnalyse` gained an opt-in `minimize`
  flag (wired on by the iterative CDCL engine) that runs a recursive
  (self-subsuming) minimisation pass — `_minimiseClause` in
  `lib/src/lcg/analyze.dart` — dropping every non-UIP literal that the
  conjunction of the remaining clause literals already implies through the
  implication trail. Sound because the trail is a DAG in trail order
  (antecedents strictly earlier), so the redundant set is safe to remove at
  once; the asserting UIP is preserved. New `SolverStats.lcgMinimisedLiterals`.
  **Measured win on the larger UNSAT proofs:** removing the literal pinning
  the backjump high lets the engine jump deeper — pigeonhole 10-in-9 drops
  26233 → 24873 decisions (−5%), backjump-levels-skipped 88 → 381 (4.3×);
  smaller instances keep their already-tight trajectory with leaner clauses.
  **Two follow-ups measured + banked as dead-ends** (`LCG_PLAN.md` §M4 item
  1): widening the backjump gate to (even minimised) atom clauses still
  wanders on Inkala (the asserting literal of a CSP clause is a weak
  `AtomNe`); and minimising the post-backjump re-propagation scope is a net
  loss (full-scope `_propagate(_domains.keys)` usefully re-fires the whole
  learned-clause pool against the restored domains). 8 new tests
  (`test/lcg/clause_minimise_test.dart`); **1003 total**. Remaining in M4
  item 1: make the iterative engine the default after a full-suite
  non-regression benchmark; then restart / VSIDS / dom-wdeg pairing.

- **LCG M4 item 1 — iterative trail-based CDCL engine (sound
  non-chronological backjumping).** New `useIterativeCdcl: true` knob on
  `CSP.solveWithLcg` / `Problem.solveWithLcg` switches search from the
  recursive chronological-backtracking-with-learning loop to a single-trail
  iterative CDCL engine (`_searchOneLcgIterative`): one
  decide/propagate/analyse loop with an O(1) `_backjumpTo` that rolls the
  one domain trail straight back to a learned clause's asserting level
  (decision stack rebuilt via parallel `_decisionTrailMark` /
  `_decisionVarStack`), where the clause unit-props its asserting literal.
  This is the real LCG search-tree speedup the recursive engine can't do.
  **Key lesson banked:** non-chronological backjumping only *wins* with
  short, strong clauses — CSP-propagator clauses (allDifferent / GCC tight
  Hall sets) decode to the wide atom encoding and run to *tens* of literals;
  backjumping on those made Inkala learn ~2000 weak clauses without
  converging in 120 s (recursive: ~48 backtracks). The shipped gate
  **backjumps only on short boolean/CNF clauses (`spec.atoms == null &&
  len ≤ 12`)** — pigeonhole 7-in-6 ~240 decisions / 70+ backjumps, 8-in-7
  cuts ≥ 10× — and *posts-but-backtracks-chronologically* on atom clauses
  (matching the recursive engine's systematic search, so hard sudoku still
  converges fast). Opaque conflicts (plain binary, regular, cumulative, …)
  chronological-fallback with no clause; non-integer-domain problems fall
  back to the recursive engine wholesale (the decision-atom machinery is
  integer-only). Off by default while the recursive path stays the
  validated baseline. Soundness + completeness re-validated with the
  known-solution sweep (Inkala × 20 VSIDS orders + dom/wdeg, allDiff + GCC,
  0 failures) + 60 random-binary-CSP verdict-parity checks. 11 new tests
  (`test/lcg/iterative_cdcl_test.dart`); **995 total**. `LCG_PLAN.md` §M4
  item 1 marked shipped (first slice); the remaining work (clause-quality
  pass to widen the backjump set, minimised re-propagation, making it the
  default, restart/VSIDS pairing) stays open there.

- **LCG — tight allDifferent / GCC explanation via residual
  reachability (Régin / Quimper-Walsh).** Replaced the conservative
  tightness *bails* with sound explanations built by **closing forward
  reachability** in the residual digraph. allDifferent
  (`_buildHallSetReason` + new top-level `_reachHallSet`): the
  reach-closure from a pruned value's node yields a tight Hall set
  `(H, K)` with `|H| == |K|`, recovering the **free-vertex-slack** prunes
  the old entry-domain-union check bailed (the closure grows `K` past
  `v`'s SCC to the downstream-reachable values + their owners, staying
  tight; `x_i` is provably outside the closure). GCC (`_buildGccReason` +
  new `_reachGccCut`): multi-source reach over value *copies* yields a
  **capacity-aware saturated cut** (Régin 1996) — a value set whose
  `Σ upper` equals the member count, so the members saturate every copy
  including all of `v`'s — recovering the Hall-set prunes the old
  fully-assignment-covered-only case bailed (it bailed *every* Hall-set
  prune). Both certify the Hall/cut condition explicitly and bail (sound
  chronological fallback) otherwise; soundness rests on Hall's theorem +
  the GCC graph connecting each variable to *all* copies of each domain
  value. **Recovery:** Inkala's hardest learns ~25 clauses (was ~8); the
  count-1 GCC encoding now learns *identically* to allDifferent (was: all
  Hall-set prunes bailed). **Soundness** re-validated with the
  known-solution methodology: 240 randomized-VSIDS-order Inkala/medium
  runs (allDiff + GCC) solve the unique solution with 0 failures; 30
  learning-triggering multi-copy (`upper > 1`) GCC instances + thousands
  of no-learning multi-copy runs all agree with full enumeration on
  SAT/UNSAT + assignment. `CSP.solveWithLcg` / `Problem.solveWithLcg`
  gained `useVsids` / `useDomWdeg` / `seed` knobs (sound + complete under
  any picker; the backjump *speedup* still needs the iterative engine).
  4 new tests (`test/lcg/tight_hall_set_test.dart`); **984 total**.
  `LCG_PLAN.md` §M4 item 2 closed.

- **LCG — root-caused + fixed the order-dependent "learned-but-FAILURE
  on SAT" bug.** It was **two independent bugs**, found with a
  known-solution soundness auditor swept over 320 randomized VSIDS
  decision orders (after which: 0 unsound clauses, 0 FAILUREs). **(1)
  Unsound learned clauses:** `_recordImplications` recorded a
  propagator's incidental singleton-collapse prune as one
  `AtomEq(var, survivor)` carrying that propagator's reason (which only
  justifies the values it removed, not the assignment — over-claim);
  fixed by emitting per-removed-value `AtomNe` except for decision pins
  / boolean vars. And `_buildHallSetReason` attributed prunes to
  non-tight value-SCC member sets; fixed by validating tightness
  (`|∪ entry domains| == |members|`) and bailing otherwise. **(2)
  Incomplete backjump:** a recursive backtracker cannot do CDCL-style
  non-chronological backjumps soundly (unwinding abandons intermediate
  frames' untried candidates → FAILURE on SAT); fixed by making
  `_searchOneLcg` **chronological backtracking + clause learning**
  (`_LcgBackjump` removed). Pigeonhole 7-in-6: 283 decisions / 224
  learned (vs the old incomplete backjump's 365 / 154; plain 3245) —
  *better*, and now sound + complete under any picker. Gates
  re-baselined: `backjumps`→0 on the LCG path; magic 4×4 "≥ 5 learned"
  → "≥ 1" (the prior 5 counted unsound clauses; sound value 3). 980
  tests. **GCC's `_buildGccReason` had the same latent
  non-tight-Hall-set unsoundness; now fixed conservatively** (emit
  antecedents only when every copy of the pruned value is held by a
  pinned owner, else bail). Follow-ups in `LCG_PLAN.md` §M4: an iterative
  trail-based CDCL engine to restore the backjump *speedup*, and the
  (capacity-aware) alternating-path Régin explanation to recover the
  learning both tightness bails drop.

- **LCG M3c — `_GccPropagator` network-flow explanation.** New
  `GccFlowReason`; the propagator gains the M3a/task-1 LCG plumbing
  (`originalDomains` + `recordScc` + a `reason:` kwarg). `_buildGccReason`
  commits one `AtomInScc` bridge per removed value (shared across
  siblings), handling per-value multiplicity: each matched copy
  contributes `AtomEq(owner, v)` when its owner is pinned (assignment)
  else the Régin Hall-set absences of the copy's SCC. Engine wiring +
  a `_gccConflictReason` via the shared `_scopeConflictBridge` helper
  (factored out of `_allDifferentConflictReason`). A GCC with exact
  counts (≡ allDifferent) on Inkala's hardest learns 8 clauses, cuts
  backtracks 48→42 (was 0). 5 new tests
  (`test/lcg/gcc_explain_test.dart`); 980 total. Régin 1996.

- **LCG M3-tighten task 1 — `AtomInScc` intermediate atom for
  `_AllDifferentPropagator`.** The crux of M3-tighten: a synthetic,
  non-assertable `AtomInScc` bridge (`isSynthetic == true`;
  `negate()`/`isEntailedBy()` throw) collapses each Hall set into one
  resolvable atom. `firstUipAnalyse` resolves *through* synthetic atoms
  (splits the at-level count real-vs-synthetic; never a UIP; bails if
  one can't be resolved through). The propagator commits one bridge per
  removed value with two sound shapes — `AtomEq(owner, v)` for the
  pinned-owner assignment case (the on-trail "newest cause" that fixed
  the degenerate singleton-SCC), else entry-snapshot Hall-set absences.
  Gate met: 4×4 magic 0→5 learned, 3×3 fully converges, Inkala 2→8,
  pigeonhole still ≥5×. 975 total (was 972).
  - *Reverted as measured dead-ends, documented:* M3-tighten task 2
    (linear bound atoms — regressed the 4×4 gate 5→4); M4 (VSIDS
    pairing — broke Inkala SAT→FAILURE via an order-dependent
    learned-but-FAILURE bug whose cause is still open); and a
    refuted "re-pick after landing" fix for that bug. See
    `LCG_PLAN.md` §M4 + Lessons.

- **LCG M3b — `_LinearPropagator` bound-explanation plumbing.**
  Second per-propagator `explain` companion. New
  `LinearBoundReason extends ImplicationReason`. Engine call site
  in `_propagate` threads `originalDomains:` + `reason:` through
  the propagator; new `_linearConflictReason` helper captures
  `_lastConflictReason` on linear-propagator failures. Shared
  `_domainShapeAntecedents` helper centralises the antecedent
  shape used by both M3a and M3b. **Known limitation**: the
  current coarse "AtomNe-per-absent-value" antecedent shape works
  occasionally (sudoku-medium learns 1 clause via M3a) but fails
  on dense-conflict problems (4×4 magic squares) where the
  conflict reason includes too many at-conflict-level atoms for
  the first-UIP analyser to isolate a UIP. The M3b plumbing is in
  place; a future per-prune-tight refinement (Hall-set / dependency-
  set narrowed to the single "newest cause" atom per resolution
  step) is needed for consistent activation. 7 new tests
  (`test/lcg/linear_explain_test.dart`); 966 total (was 959).
  See `doc/lcg.md`.

- **LCG M3a — `_AllDifferentPropagator` Hall-set explanation.**
  First per-propagator `explain` companion. New
  `AllDifferentReason extends ImplicationReason` lives in
  `lib/src/lcg/explain.dart`. The propagator extracts the Hall set
  off its existing Régin SCC decomposition: for prunes of variable
  `i`, the Hall set is the union of SCCs of all pruned values, and
  the antecedents are `AtomNe(h, k)` for every Hall-set variable
  `h` and every value `k` declared in `h`'s original domain but
  absent from `h`'s current domain. Sound: the Régin matching
  depends only on which values are in each variable's current
  domain. Engine plumbing: optional `originalDomains:` constructor
  param on the propagator (non-null only when `enableLcg` is true,
  zero cost when off), `reason:` kwarg on `applyUpdate`,
  `_allDifferentConflictReason` for the matching-failure /
  pigeonhole / empty-domain conflict sites. End-to-end acceptance:
  Inkala's "World's Hardest Sudoku" learns 2 clauses with 1
  non-chronological backjump skipping 1 level. 8 new tests
  (`test/lcg/all_different_explain_test.dart`); 959 total (was 951).
  See `doc/lcg.md`.

- **LCG — lazy atom encoding for `_ClausePropagator`.** Foundation
  for M3 per-propagator `explain` companions. `ClauseSpec` gains an
  optional `atoms: List<Atom>?` slot; when non-null the propagator
  dispatches to a new atom-aware eval / force / antecedents path
  (`_evalAtAtom`, `_filterForAtom`, `_antecedentsForForce` switch
  on `spec.atoms != null`). The two-watched-literal scheme is
  preserved — monotone-under-trail holds for all four atom kinds
  because rollback only grows domains. New `_DomainViewAdapter`
  bridges `_DomainRep` → `DomainView`. `_learnedClauseToSpec` now
  picks boolean encoding when every atom is over a `{0, 1}`
  variable (cheaper per-prop eval) and falls back to the atom
  encoding otherwise — M2b's "non-boolean → chronological
  backtrack" fallback is gone. M3 propagator companions can now
  post their explanations through the same watch-literal
  infrastructure. 9 new tests
  (`test/lcg/atom_clause_test.dart`); 951 total (was 942). See
  `doc/lcg.md`.

- **`bench(lcg)` perf anchor.** Closes the "perf claims need
  warm-up + median methodology" gate for M2b. New section in
  `benchmark/benchmark.dart` (helpers `_benchLcg` / `_runLcgMedian`
  / `_formatLcgMicros`) runs plain backtracking vs LCG back-to-back
  with the standard 5-warmup + 25-rep median methodology. Three
  pigeonhole-CNF showcase rows (6/7/8-in-N) plus one 8-queens
  "wash" row. The wash row anchors the non-regression claim
  (LCG's per-prune trail bookkeeping is negligible on opaque-
  conflict problems — engine falls back to chronological
  backtrack, decisions match plain exactly). `doc/lcg.md` gains a
  "Perf anchor" subsection with the indicative results table.

- **LCG M2b — engine wiring + first-UIP-driven backjump.** Closes
  the M2 pair: `Problem.solveWithLcg` now performs real conflict-
  driven nogood learning. New `_searchOneLcg` recursion mirrors
  the CBJ sealed-`_SearchResult` pattern; on every propagation
  failure the engine calls `firstUipAnalyse` (M2a), converts the
  learned atoms back into a boolean `ClauseSpec`, posts it
  dynamically into `_csp.naryConstraints` + `_naryIdx`, and
  signals a `_LcgBackjump(targetLevel)` up the search stack. The
  landing frame re-propagates so the freshly-posted clause's UIP
  literal asserts. New `_lastConflictReason` slot on the engine
  is set at the clause-propagator failure site inside
  `_propagate` and consumed by the LCG search loop. FIFO forget
  policy (default 1000, `learnedClauseCap:` kwarg) drops the
  oldest half once the pool overflows.
  `SolverStats.learnedClauses` + `forgottenClauses` are new; the
  existing `backjumps` / `backjumpLevelsSkipped` are also bumped.
  Acceptance gate: pigeonhole-CNF 7-in-6 cuts decisions ~9× vs
  plain backtracking, 8-in-7 cuts ~29× — solidly inside the
  10–100× literature target. Conflicts whose antecedents flow
  through any non-clause propagator still fall back to
  chronological backtrack — M3's per-propagator `explain`
  companions unlock those families. 6 new tests
  (`test/lcg/pigeonhole_test.dart`); 942 total (was 936). See
  `doc/lcg.md` for the combined M1+M2 behaviour write-up and
  `LCG_PLAN.md` for the M3+ roadmap.

- **`bench(cooperative-lns)` perf anchor.** Closes the
  perf-claim gate for the cooperative parallel LNS feature: new
  section in `benchmark/benchmark.dart` runs portfolio
  (`cooperative: false`) and cooperative (`cooperative: true`)
  back-to-back on the same `buildBinPackingMinMaxLoad(itemCount:
  12, binCount: 3)` problem. Default config: 3 workers, random
  destroy (fraction 0.5), 80-iteration budget, warm-up 1 + 3
  timed reps, median wall-clock. Sample run shows iso-objective
  (`obj=30`) with cooperative within ~10–20% wall-clock variance
  of portfolio — a non-regression anchor on this instance size.
  `doc/lns.md` gains a "Perf anchor" subsection with example
  output.
- **LCG M2a — first-UIP conflict analyser (pure function).**
  Second LCG slice: `ClauseReason` concrete subclass of
  `ImplicationReason` (`lib/src/lcg/explain.dart`) carries
  antecedent atoms for clause unit-props.
  `_ClausePropagator._forceLiteral` emits it via a new optional
  `reason:` named param threaded through `_setDomain` /
  `_setDomainRep` / `_recordImplications`. The first-UIP analyser
  itself lives in `lib/src/lcg/analyze.dart` as a pure function
  `firstUipAnalyse(trail, conflictReason) → AnalysisResult?` —
  walks the trail backward, resolves at-level atoms against
  their reasons, stops at the single remaining at-level atom
  (the UIP). Returns `learnedClause: List<Atom>` (disjunction
  over negations of currently-entailed atoms), `backjumpLevel`,
  and `uipAtom`. **Not yet wired into the engine** —
  `solveWithLcg` still uses chronological backtrack. M2b is the
  engine-surgery half (dynamic learned-clause posting +
  backjump). 12 new tests (`test/lcg/clause_reason_test.dart` +
  `test/lcg/analyze_test.dart`). See `doc/lcg.md`.
- **LCG M1 — atom encoding + implication trail + runner shell.**
  First slice of the Lazy Clause Generation strategic-gap pick:
  `lib/src/lcg/` (atom.dart with `Atom` sealed hierarchy + four
  subtypes, explain.dart with `ImplicationReason` /
  `ImplicationEntry` + `DecisionReason` / `UnknownReason`
  placeholders, lcg.dart as `part of '../problem.dart';` for the
  `LcgSearch` extension), plus `Problem.solveWithLcg` /
  `CSP.solveWithLcg` entry points and a `CSP.lastImplicationTrail`
  static slot mirroring `lastStats`. `_BacktrackEngine` learned an
  `enableLcg` flag (off by default; zero cost off); when on,
  `_setDomain` / `_setDomainRep` emit `ImplicationEntry` records on
  every prune (one `AtomEq` for singleton survivors, one `AtomNe`
  per removed value otherwise; non-int domains skipped). Decision
  level is auto-tracked by watching `cause: null` trail entries.
  Trail rolls back in lockstep with the domain trail in
  `_trailRollback`. **M1 is wiring + types only — `solveWithLcg`
  returns identical results to `getSolution` today.** The first-UIP
  loop arrives in M2 (on top of `_ClausePropagator`); per-
  propagator `explain` companions in M3. 30 new tests
  (`test/lcg/atom_test.dart`, `implication_trail_test.dart`,
  `solve_with_lcg_test.dart`); `LCG_PLAN.md` strategic-gap box
  stays `[ ]` until M2 closes the learning loop. See `doc/lcg.md`.
- **Cooperative parallel LNS** — `cooperative: true` flag on
  `lnsMinimizeInIsolates` / `lnsMaximizeInIsolates` enables mid-run
  incumbent broadcasting. New `['bound', num]` wire-protocol kind
  in `isolate_runner.dart`: worker → parent on every local
  improvement, parent → siblings as a re-broadcast routed through
  each session's control port (same channel as `'cancel'`). Workers
  use the broadcast bound to pre-tighten the next sub-problem's
  objective domain; iterations whose tightened domain becomes
  empty are skipped as infeasible. `Problem.lnsMinimize` /
  `lnsMaximize` learned `boundHint:` / `onIncumbent:` plumbing
  parameters (defaults: null → unchanged behaviour). 5 new tests.
  See `doc/lns.md` "Cooperative parallel LNS".
- **FlatZinc search-annotation mapping** — `int_search` /
  `bool_search` / `seq_search` annotations on `solve` directives
  now route the `varSelect` keyword to dart_csp's heuristic knobs
  (`dom_w_deg` → `useDomWdeg`; `activity_var` → `useVsids`;
  `impact` → `useImpact`); previously parsed-and-ignored. Required
  a small parser bump: `AstAnnotationCall` for nested annotation
  calls inside `seq_search([…])`. Optimisation runs (`minimize` /
  `maximize`) now also honour the hint — `CSP.solveOptimal` +
  `Problem.minimize` / `maximize` learned the four heuristic
  flags. 11 new tests; see `doc/flatzinc.md`.
- **Large Neighborhood Search (LNS)** — `lib/src/lns/` plus the
  `LargeNeighborhoodSearch` extension on `Problem`. Sequential v1
  with five destroy policies (`random`, `window`, `related`,
  `combined`, `adaptive`) and three acceptances (`improving`,
  `simulatedAnnealing`, `lateAcceptance`). Parallel runners via
  `lnsMinimizeInIsolates` / `lnsMaximizeInIsolates` in
  `isolate_runner.dart` — portfolio by default, cooperative on
  `cooperative: true`. `bench(lns)` shows ~14× speedup over plain
  `Problem.minimize` on a 12-item / 3-bin packing instance; tracks
  best-ever separately from current so SA / LAHC can't lose the
  best. `doc/lns.md` + `example/lns.dart`.
- **FlatZinc frontend (M1-M5 + post-M5 polish)** —
  `lib/src/flatzinc/` plus the `bin/dart_csp_fzn` CLI binary. Full
  pipeline from `.fzn` source to the standard FlatZinc output
  format. See `doc/flatzinc.md` for the supported subset.
- **Conflict explanation** — two MUS algorithms (deletion-based +
  QuickXplain), per-`addX`-call labels surfaced on
  `ConstraintRef.label`, and a `bench(explain)` comparison
  section. See `doc/conflict-explanation.md`.
- **Heuristic family** — dom/wdeg, VSIDS, IBS, Last-Conflict plus
  the five-way `bench(heuristic)` comparison. See
  `doc/heuristics.md`.

**Test count:** 1040 passing. **Files:** 6 `lib/src/*.dart` (plus
`lib/src/lns/`, `lib/src/lcg/`, and `lib/src/flatzinc/`); 66
`test/*_test.dart` files (incl. `test/lcg/`, now with
`tight_hall_set_test.dart` + `iterative_cdcl_test.dart` +
`clause_minimise_test.dart` + `restart_test.dart` +
`regular_explain_test.dart` + `cumulative_explain_test.dart` +
`diffn_explain_test.dart` + `circuit_explain_test.dart`, plus the
parallel-LCG portfolio + clause-sharing tests in
`isolate_runner_test.dart`); 13 `doc/*.md`
guides (incl. `doc/lcg.md`);
7 `example/*.dart` files; `benchmark/benchmark.dart` runs nine
sections (CBJ, AC-vs-SAC, diff_n, heuristics, conflict-explanation,
LNS, cooperative-LNS, LCG, FlatZinc). Three planning docs at repo
root: `LNS_PLAN.md`, `MINIZINC_PLAN.md`, `LCG_PLAN.md` (**LCG is COMPLETE
— M1–M5 + all of M3a–M3g + all of M4**: iterative trail-based CDCL engine
— the **default** for `solveWithLcg` — with sound non-chronological
backjumping, recursive clause minimisation, the VSIDS / dom-wdeg
learned-clause activity bump, Luby restarts + phase saving, bound-atom
trail emission, an `explain` companion for **every** specialised
propagator, a three-engine `bench(lcg)` (incl. M3e/f/g scheduling/packing/
routing showcase rows), the M5 worked-example doc, and a parallel LCG
portfolio with cooperative clause sharing (`solveWithLcgInIsolates`).
The LCG strategic gap — and its optional polish — is closed; see
`HISTORY.md`).

---

## Recommended next pick — **LCG is done; choose a fresh direction**

The entire LCG strategic gap is closed (M1–M5, all of M3a–M3g, all of M4)
**and its optional polish is done too** — the `bench(lcg)` scheduling rows
and the parallel portfolio + cooperative clause sharing both shipped (see
the landing entries at the top of this file and the closed entry in
`HISTORY.md`). There is no remaining LCG work. Pick from the
forward-looking `PLAN.md`:

1. **Float / real variables** (Strategic gap, multi-session) — the
   remaining big gap. A fourth `_DomainRep` (interval over `double`),
   interval-arithmetic propagators, branch-on-interval-split. The real
   design cost is the precision/soundness questions (NaN, epsilon
   equality, IEEE-754 rounding). See `PLAN.md` → Strategic gaps.
2. **Edge-finding propagator for `addCumulative`** (Vilím 2007, 1–2
   sessions) — the standard perf upgrade for tight RCPSP scheduling beyond
   the current time-table; take on if a real scheduling benchmark
   motivates it.
3. Other strategic / edge items in `PLAN.md` (the XCSP3 frontend, SAC-2,
   edge-finding cumulative, …). *(set-of-int in FlatZinc shipped — see the
   top landing entry.)*

**Banked LCG gotchas (still relevant if you touch the explanation code or
extend it):**
- The unlock for allDifferent/GCC was the degenerate singleton-SCC
  (*assignment*) case, not the textbook Hall set; for regular it was the
  trail-matching `AtomEq` for booleans; for cumulative/diff_n the
  trail-matching `AtomEq`-for-pinned + tightened-bounds shape
  (`_trailBoundAtoms`); for circuit the fixed-edge `AtomEq`. **The through
  line: match the atom shape the trail actually records, and trace the
  *real* conflict before assuming the textbook shape.**
- `firstUipAnalyse` has a `trace:` callback — use it to dump the resolution
  and confirm the at-level count before guessing (it pinned M3d's bug
  immediately).
- For a GAC-strong propagator (regular, circuit) learning surfaces mostly
  on UNSAT (SAT solves at the root); for a non-GAC one (cumulative, diff_n)
  SAT instances search and learn too. The verdict-parity-vs-enumeration
  sweep is the soundness net either way — non-negotiable.

The historical kickoff notes below are retained for context.

**M3-tighten kickoff (done — `feat(lcg)` instrumentation cycle).**
The convergence gap is now measured, not argued:

- `SolverStats.lcgAnalysisFailures` counts concrete-reason conflicts
  that produced no UIP. On the 4×4 magic square **all 7 backtracks
  are analysis failures** (`== backtracks`, `learnedClauses == 0`).
- `firstUipAnalyse` gained an optional `trace` callback. Tracing a
  real 4×4 conflict shows resolving an at-level atom against a
  coarse `LinearBoundReason` *adds* more at-level on-trail atoms
  than it removes — the count climbs 6 → 9 — so the walk diverges.
- `test/lcg/m3_tighten_diagnosis_test.dart` is an executable design
  spec: coarse sibling-referencing reasons bail; "newest-cause"
  reasons converge to a unit UIP; a "real intermediate bound atom"
  (`AtomGe`/`AtomLe` on the trail) converges with the learned clause
  carrying the negated bound.

**Two dead-ends ruled out this cycle (don't repeat — both were
implemented, measured, reverted):**

1. *Linear bound-atom encoding alone doesn't activate.* The sound
   snapshot-based linear bound-atom reasons were built end-to-end,
   but magic-square `learnedClauses` stayed 0 — the `trace` showed
   the conflicts are **allDifferent-detected**, so the linear reason
   never reaches the conflict's resolution chain. allDifferent is
   the bottleneck; start there.
2. *Per-atom trail-shape-matching regresses learning.* Emitting
   `AtomEq` for pinned variables in `_domainShapeAntecedents`
   dropped Inkala from 2 learned clauses to 0 (multiplies the
   at-conflict-level count). The fix is a single `AtomInScc`
   intermediate atom per scope, **not** reshaping per-variable
   antecedents.

See `LCG_PLAN.md` §M3-tighten (the two new "Failed shortcut"
entries + re-prioritised tasks: `AtomInScc` for allDifferent is
task 1, linear bound atoms task 2). Hard gate: Inkala must still
solve **and** still learn ≥ 2.

### What's broken today

The first-UIP analyser in `lib/src/lcg/analyze.dart` requires the
textbook convergence invariant: each resolution step removes one
at-conflict-level atom and adds at most one new at-level atom
(net change ≤ 0). Boolean clauses satisfy this trivially — a
unit-prop's reason has exactly one at-level antecedent (the most
recently falsified literal). CSP propagators like `_AllDifferent`
and `_Linear` naturally produce reasons over **multi-variable
scopes** with several at-level antecedents per prune, so the walk
doesn't converge and the analyser bails with `atLevelCount != 1`
on most CSP conflicts.

The two M3 companions shipped (M3a `AllDifferentReason`, M3b
`LinearBoundReason`) work plumbed end-to-end but the coarse
"AtomNe-per-absent-value across the Hall set" / "across the other
variables" antecedent shape only converges occasionally — sudoku
medium learns 1 clause, Inkala's "World's Hardest" learns 2,
4×4 magic squares (linear-heavy) learn 0. The acceptance tests
pass on the converging cases but the broader workload doesn't
benefit yet.

### What I tried this session, and why it broke

**Attempt 1: relax the analyser to accept multi-UIP working
clauses** (single-line change: drop the `atLevelCount != 1`
guard, accept multi-at-level clauses as non-asserting but sound
implicates). The argument is: resolution's "conjunction-is-unsat"
invariant is preserved at every step, so the final disjunction
of negations is a sound implicate regardless of convergence.

  - Net effect on Inkala's hardest: 49 decisions / 85 backtracks
    / 40 learned clauses / **`FAILURE` on a SAT problem**.
  - Net effect on pigeonhole-CNF 7-in-6 (M2b CNF acceptance): no
    regression.

**Attempt 2: widen M3a's per-prune reason from Hall-set to
whole-scope.** Reasoning: maybe the Hall-set narrow shape was
under-broad (didn't fully imply the prune), so widening to the
full constraint scope ensures `antecedents → prune` is sound.

  - Net effect: also `FAILURE` on Inkala. So the bug isn't only
    in the multi-UIP relaxation; the wider per-prune reason also
    breaks things.

Both attempts were reverted; all 966 tests pass with the
shipped code.

### What I learned (concrete starting points)

1. **Hall-set narrow IS sound.** The SCC containing a pruned
   value's matched-variable in Régin's residual graph is a tight
   Hall set: |H| = |dom_union(H)|. That property is implied by
   the absences within H alone (the Hall set's variables
   collectively cover their value set). Earlier I claimed Hall-
   set narrow was unsound — that was wrong. Don't burn time
   re-debating; trust the property.

2. **The whole-scope per-prune reason is *circular* during
   resolution.** When the prune is `AtomNe(v, k)` (multi-value
   prune that just removed `k` from `v`'s domain), the whole-
   scope reason includes `AtomNe(v, k)` itself as an antecedent
   (because `k` is currently absent from `v`). Resolving the
   prune removes `AtomNe(v, k)` from the working clause and
   immediately adds it back via the antecedents — a no-op
   step. The walk grinds through every at-level trail entry
   without making progress, and the analyser sometimes returns
   "learned clauses" that are essentially the conflict reason
   itself. That ended up missing valid solutions on Inkala
   (debugging didn't isolate the exact path).

3. **Multi-UIP + Hall-set narrow also fails Inkala.** Even though
   the theoretical soundness argument is intact, the empirical
   failure suggests an interaction I didn't fully diagnose:
   either the analyser's working-clause set has a subtle bug
   when atoms are added/removed multiple times via overlapping
   resolutions, or the engine's behaviour when the learned
   clause is non-asserting (`backjumpLevel == conflictLevel`)
   misbehaves in some path. Worth instrumenting before
   committing to a path.

4. **The textbook fix in Chuffed / OR-Tools is intermediate
   atom encoding.** Reify `≤` / `≥` / `=` literals as
   first-class boolean atoms on the trail. The propagator
   explanations then decompose into chains where each step
   carries ≤ 1 at-conflict-level antecedent (the single
   "newest cause"). This is the structural fix the textbook
   first-UIP loop assumes; without it, CSP-shaped reasons
   inherently violate the convergence invariant.

### Concrete entry points for the next session

If you're picking up M3-tighten:

1. **Don't repeat the "widen per-prune to whole-scope" or
   "relax analyser to multi-UIP" experiments** — both have been
   tried and rolled back. The shipped Hall-set-narrow + strict
   1-UIP is the best behaviour I could find without intermediate
   atom encoding. Confirm by running:
   ```
   dart test test/lcg/all_different_explain_test.dart
   dart test test/lcg/linear_explain_test.dart
   ```
   Both should show 7–8 tests passing, sudoku medium learning 1
   clause, Inkala's hardest learning 2.

2. **The right path is intermediate atom encoding.** Read
   `LCG_PLAN.md` §4 for the lazy-vs-eager encoding discussion;
   the multi-session refactor is essentially "lazy atom
   encoding for propagator-emitted intermediate atoms" extended
   to cover the SAT-CDCL convergence shape. Specifically:

   - `_AllDifferentPropagator`'s per-prune reason should
     reference a *single* intermediate atom like
     `AtomInScc(v, scc_id)` that captures "this variable is in
     this SCC." The SCC's defining absences are then chained as
     antecedents of `AtomInScc`, each carrying ≤ 1 at-level
     atom.
   - `_LinearPropagator`'s per-prune reason should reference
     `AtomLe(v, ub)` / `AtomGe(v, lb)` bound atoms — extending
     the existing trail-emission code in `_recordImplications`
     to emit `AtomLe` / `AtomGe` entries when a propagator
     tightens a bound (currently only `AtomEq` / `AtomNe`
     entries are emitted).

3. **Don't burn time on Chuffed-source reading without first
   building a minimum-viable reproducer.** Inkala's hardest is
   the smallest SAT case where my naïve fixes broke. Get the
   1-UIP convergence working on a 3-allDifferent / 3-cell-Hall
   toy problem first, then scale up. Without an end-to-end SAT
   acceptance, it's easy to ship something that looks sound but
   isn't.

4. **The `LinearBoundReason` plumbing in `_LinearPropagator` is
   already correct in structure** — its per-prune reason
   iterates over the OTHER variables (i ≠ j), so it doesn't
   have the circular-resolution issue M3a's whole-scope variant
   hit. M3-tighten for linear is mostly about emitting the
   bound atoms on the trail, not changing the propagator.

After M3-tighten lands, the remaining M3 sub-milestones (priority
order):

1. **M3c — `_GccPropagator.explain`.** Saturated-cut extraction
   from the residual flow graph. Same Régin-style shape as M3a;
   inherit M3-tighten's intermediate-atom approach. Reference:
   Régin 1996.
2. **M3d — `_RegularPropagator.explain`.** Path-based
   explanation from the per-position forward/backward reachable
   state sets. Reference: Pesant 2004 + Beldiceanu et al. 2007.
3. **M3e — `_CumulativePropagator.explain`.** Time-table prunes
   surface the overlap-contributing tasks. Reference: Vilím
   2009.
4. **M3f — `_DiffNPropagator.explain`.** Forbidden-region sweep
   reveals the compulsory-part rectangles.
5. **M3g — `_CircuitPropagator.explain`.** Sub-tour /
   cycle-detection state at the prune step.

After all of M3 the LCG profile should match Chuffed's on the
MiniZinc Challenge benchmarks. Follow-ups: M4 (restart + dom/wdeg
integration; LCG bumps weights of variables in learned clauses)
and M5 (extending `bench(lcg)` with magic-square + RCPSP +
clause-minimisation).

Smaller (one-session) follow-ups that are well-scoped and have
clear value:

- **`bench(search-annotation)` perf anchor.** Same idea for the
  FlatZinc varSelect routing: run a representative MiniZinc-shaped
  problem under each varSelect and report wall-clock. Confirms the
  routing actually helps (not just that it's wired correctly).
- **Edge-finding propagator for `addCumulative` (Vilím 2007).**
  PLAN.md tactical win; would strengthen RCPSP-style scheduling.
  Take on if a concrete scheduling workload motivates it; the
  RCPSP-style benchmark mentioned in PLAN.md should land first to
  anchor the perf claim.
- **Float / real variables.** Multi-session. A fourth `_DomainRep`
  (interval over `double`), interval-arithmetic propagators, and
  branch-on-interval-split. The precision-vs-soundness questions
  (NaN, epsilon equality, IEEE-754 rounding modes) are the real
  design cost.

Other multi-session: set-of-int variables in FlatZinc; the XCSP3
frontend (XML-based, distinct from FlatZinc); explanation-aware
propagators (would converge toward LCG anyway). The search-
annotation routing in FlatZinc could also be extended to support
per-variable-set heuristic scoping (currently the hint is global),
which would unlock `seq_search`'s sequential per-group semantics —
not a one-session item because the engine doesn't have a
variable-subset-scoped picker today.

---

## 1. Required reading (in this order)

1. **`PLAN.md`** — the forward-looking roadmap. The sections are
   **Strategic gaps** (LCG `[~]`, float variables), **Tactical
   wins** (edge-finding for cumulative), and **Edge / workload-
   gated** (SAC-2, k-dim diff_n, etc.). Shipped items now live in
   **`HISTORY.md`** — the done record (the original Tier 1/2/3 plan
   plus every shipped strategic gap and tactical win: FlatZinc, LNS,
   conflict-explanation, cooperative-LNS, IBS, Last-Conflict,
   QuickXplain, labels, …). If you're picking up LCG, read
   **`LCG_PLAN.md`** next (the scoping doc with atom encoding,
   milestones, per-propagator explanation contracts).
2. **`doc/<feature>.md`** for whichever feature you're touching.
   Topical guides: `algorithms`, `cancellation`, `cbj`,
   `conflict-explanation`, `flatzinc`, `global-cardinality`,
   `heuristics`, `lns`, `min-conflicts`, `multi-solutions`,
   `set-variables`, `string-constraints`. Each covers design
   rationale, gotchas, and references.
3. **`STABILITY.md`** — API stability tiers, semver policy, what's
   experimental, what's internal, known gotchas. LNS is currently
   experimental.
4. **`README.md`** — public API surface. Sections for every major
   feature.
5. **`CHANGELOG.md` `## Unreleased`** — recent shipping cadence,
   newest first.
6. **`lib/src/`** — six top-level files plus two subdirectories:
   - `types.dart` — public types (`CancellationToken`,
     `BinaryConstraint`, `NaryConstraint` with dispatch flags,
     `CspProblem`, `SolverStats`, `LinearSpec`, `GccSpec`,
     `CumulativeSpec`, `ClauseSpec`, `DiffNSpec`, `Dfa`,
     `ConsistencyLevel`, `ConstraintRef`).
   - `problem.dart` — `Problem` builder + every extension
     (`BuiltinConstraints`, `StringConstraints`, `ProblemDebug`,
     `MultipleSolutions`, `ReifiedConstraints`, `LogicalConstraints`,
     `GlobalConstraints`, `LinearConstraints`, `SoftConstraints`,
     `SetVariables`, `ConflictExplanation`).
     `LargeNeighborhoodSearch` lives in `lib/src/lns/lns.dart`
     via `part of '../problem.dart';`.
   - `builtin_constraints.dart` — factory functions.
   - `constraint_parser.dart` — string-constraint parser.
   - `solver.dart` — `CSP` static class, `_BacktrackEngine`, three
     `_DomainRep` impls, eight specialized propagators
     (`_AllDifferentPropagator`, `_LinearPropagator`,
     `_RegularPropagator`, `_CircuitPropagator`, `_GccPropagator`,
     `_CumulativePropagator`, `_ClausePropagator`,
     `_DiffNPropagator`), `_MinConflictsRunner`, CBJ machinery,
     conflict-driven heuristic state (`_varActivity`,
     `_impactMean`, `_lastConflictVar`).
   - `isolate_runner.dart` — worker-isolate runner. Single-solver
     entry points + parallel LNS runners.
   - `lns/policy.dart` — `LnsPolicy` + `LnsAdaptivePolicy` +
     builtin factories.
   - `lns/accept.dart` — `LnsAccept` + builtin factories.
   - `lns/lns.dart` — orchestrator (part of `problem.dart`).
   - `flatzinc/` — parser, AST, lowering, runner.
7. **`test/`** — 40 files. One file per feature area.

---

## 2. Conventions

These are enforced by every commit and partially by the test suite.

### Public API shape

- **All solver entry points return `Future<dynamic>` or
  `Stream<Map<String, dynamic>>`.** Failure is the literal string
  `'FAILURE'`, NOT null and NOT an exception. Callers gate with
  `if (result is Map<String, dynamic>) { ... }`. LNS is the
  exception — it returns `LnsResult` / `LnsParallelResult` whose
  `.solution` field can be `'FAILURE'`.
- **`Problem` is the user-facing builder; `CSP` is the static
  solver entry point.** New methods go on `Problem` first.
- **Extensions group related helpers.** New feature areas get
  their own extension.
- **Validation throws `ArgumentError`** naming the offending
  variable / argument.
- **`lastStats` is a single static slot on `CSP`.** Shared across
  every `Problem` instance.
- **Every backtracking entry point accepts three params:**
  `consistency: ConsistencyLevel`, `cancelToken: CancellationToken`,
  `enableConflictBackjumping: bool`.

### Problem-level solution post-processing

Every `Problem`-level solve entry point routes results through
`_wrapResult` / `_wrapStream`, which calls `_materializeSets`. This
is what surfaces set variables as `Set<dynamic>` and strips
indicator names. **New solve entry points MUST wrap or set
variables leak indicators.**

LNS deliberately bypasses this on its initial solve so it can pin
against raw indicator names per iteration; it materialises only at
return.

### The arity-dispatch gotcha (still hot)

`Problem.addConstraint([v1, v2], pred)` dispatches by arity:
- 2 vars → expects `BinaryPredicate`; registers both directions.
- 1 or 3+ → expects `NaryPredicate`; registers as `NaryConstraint`.

If your helper is naturally n-ary but might happen to have 2 vars,
use `Problem._addNary(vars, predicate)`. For helpers that need a
dispatch flag (`allDifferent`, `linearSpec`, etc.), construct
`NaryConstraint` directly.

### The tagged-constraint leaf-check gotcha (load-bearing)

Tagged constraints **bypass `_reviseNary`**. The soundness
predicate is NOT invoked at leaves — soundness rides on the
propagator catching every infeasible state. Each propagator must
detect a leaf state correctly. Patterns: GCC promotes a soft
fallback to hard `null` when matching is unique; cumulative relies
on the standard pruning path; clause's "all literals falsified" is
the leaf detection.

### Trail-based undo

The engine maintains an append-only trail of
`_TrailEntry { varName, oldRep, cause }`. **Every domain mutation
goes through `_setDomain` or `_setDomainRep`.** Both methods
append a trail entry. Pass `cause:` matching the relevant
constraint or CBJ loses precision.

**Engine assumption:** when `_propagate` is called, all current
domains are non-empty. `_reviseNary` treats a pre-existing empty
domain as "no change". Anyone tightening domains outside
propagation (e.g. integrated B&B) must guard at the leaf.

### Conflict-bump convention

Whenever propagation detects infeasibility, the engine calls
`_onConflict(c)`. This delegates to both the dom/wdeg bump and the
VSIDS activity bump; each guards on its own flag. New propagators
follow the existing shape — don't add parallel `if (useX)` lines.

### Per-constraint side-table convention

Stateful propagators (currently just `_ClausePropagator`) use a
side-table keyed by identity:

```dart
final Map<ClauseSpec, _ClauseWatchState> _clauseWatchers =
    HashMap(equals: identical, hashCode: identityHashCode);
```

Domain reductions are monotone under the trail, so watchers
pointing at non-falsified literals at deeper depth are also
non-falsified at shallower depth. **No trail-aware rollback
needed.** Same pattern for any new stateful propagator — verify
monotonicity first.

### Domain representation (three reps)

`_DomainRep` has three impls chosen per-variable at engine
construction:
- `_BitsetRep` — int span ≤ 1024. `Uint64List` + offset.
- `_IntervalRep` — int span > 1024 contiguous. `(min, max)`.
- `_ListRep` — everything else.

Propagators read via the rep API (`.values`, `.length`,
`.contains`, `.filter`) and write via `applyUpdate` (the engine
wires to `_setDomainRep`).

### LNS-specific conventions

- **Best-ever vs current.** Orchestrator tracks two solutions
  separately so SA / LAHC can't lose the best. `LnsResult.solution`
  is always best-ever. `LnsContext.bestObjective` is *current*
  (what the destroy works from).
- **`LnsPolicy` vs `LnsAdaptivePolicy`.** Plain policies satisfy
  `LnsPolicy` with just `select`. Stateful policies extend
  `LnsAdaptivePolicy` and add `observe` + `weights`. Orchestrator
  type-checks (`if (policy is LnsAdaptivePolicy) policy.observe(…)`).
- **`LnsPolicy.adaptive` is a static method, not a factory.** Its
  declared return type is `LnsAdaptivePolicy` so callers don't
  need a cast to invoke `.observe` / `.weights`.
- **Initial solve uses `CSP.solve`, not `solveOptimal`.** Proving
  optimality up front would leave LNS nothing to improve.
- **Parallel LNS is portfolio-style.** Each worker runs an
  independent LNS with its own seed. No mid-run sharing. The
  `policyBuilder` / `acceptBuilder` are called inside the worker
  so stateful instances are fresh per worker.

### Test conventions

- One test file per feature area: `test/<feature>_test.dart`.
- `group()` for sub-areas; descriptive names.
- Cover happy path, edge cases, validation errors.
- Solver tests include at least one classic problem (queens,
  sudoku, map coloring, RCPSP) as regression.
- For new globals: assert equivalence to an existing constraint on
  a degenerate parameter (e.g. `addGcc` with each count=1 ↔
  `addAllDifferent`).
- For new propagators: assert measurable activity
  (`p.lastStats!.naryRevises > 0`).
- For new heuristics: agreement-with-MRV on a unique-answer
  problem.
- **Capture `lastStats` immediately** when comparing across
  solves — the static slot gets overwritten.
- **Dart Set identity:** `Set<dynamic>{}` != `Set<dynamic>{}` even
  with same elements. Convert to canonical string keys.
- **Lambda parameters in `addConstraint` need explicit `dynamic`.**
  Analyzer fires `inference_failure_on_untyped_parameter`.

### Commit messages

```
<area>(<scope>): <one-line summary>

<paragraph: change + why>

<bullet list: API or behavior changes>

<test coverage summary with new total>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

`<area>` ∈ `feat`, `fix`, `solver`, `bench`, `docs`, `chore`,
`test`, `ci`. `<scope>` is the feature area.

### Per-feature acceptance gate

Before each commit:

```bash
cd ~/code/dart_csp
dart format --output=none --set-exit-if-changed .   # zero changes
dart analyze --fatal-infos                          # zero issues
dart test                                           # zero failures
```

Common lints to fix as they come up: `prefer_single_quotes`,
`avoid_redundant_argument_values`, `omit_local_variable_types`,
`unnecessary_brace_in_string_interps`, `unnecessary_lambdas`,
`prefer_expression_function_bodies`,
`inference_failure_on_untyped_parameter`.

For intentional redundant arguments (tests passing defaults for
symmetry), use a file-level
`// ignore_for_file: avoid_redundant_argument_values`.

### Per-feature documentation update

Each feature commit also updates:
- `PLAN.md` / `HISTORY.md` — when an item ships, move its entry from
  `PLAN.md` (the forward-looking roadmap) into `HISTORY.md` (the done
  record) and describe what shipped.
- `README.md` — new section for user-visible features.
- `CHANGELOG.md` — entry under `## Unreleased`.
- `STABILITY.md` — classify as stable or experimental.
- `doc/<feature>.md` — topical guide for non-trivial features.

---

## 3. Repo layout

```
dart_csp/
├── lib/
│   ├── dart_csp.dart                # top-level export + convenience funcs
│   └── src/
│       ├── types.dart               # public types
│       ├── problem.dart             # Problem + every extension
│       ├── builtin_constraints.dart # factory functions
│       ├── constraint_parser.dart   # string parser
│       ├── solver.dart              # CSP, _BacktrackEngine, propagators
│       ├── isolate_runner.dart      # worker-isolate runner + parallel LNS
│       ├── lns/
│       │   ├── policy.dart          # LnsPolicy + LnsAdaptivePolicy
│       │   ├── accept.dart          # LnsAccept
│       │   └── lns.dart             # orchestrator (part of problem.dart)
│       └── flatzinc/
│           ├── parser.dart
│           ├── ast.dart
│           ├── lowering.dart
│           └── runner.dart
├── bin/
│   └── dart_csp_fzn.dart            # CLI binary for FlatZinc
├── test/                            # 48 files, 894 tests
├── example/                         # demos
│   └── lns.dart                     # LNS walkthrough (5 scenarios)
├── benchmark/
│   ├── benchmark.dart               # seven sections
│   └── problems.dart                # shared builders
├── doc/                             # 12 topical guides
├── PLAN.md                          # forward-looking roadmap
├── HISTORY.md                       # done record (shipped items)
├── LNS_PLAN.md                      # LNS scoping doc (M1-M5)
├── MINIZINC_PLAN.md                 # FlatZinc scoping doc (M1-M5)
├── LCG_PLAN.md                      # LCG scoping doc (M1-M6)
├── STABILITY.md
├── HANDOVER.md                      # this file
├── CHANGELOG.md
├── README.md
├── NOTICE                           # licensing history (MIT, clean room)
├── LICENSE                          # MIT
└── .github/workflows/ci.yml         # CI
```

Remote: `https://github.com/CrispStrobe/dart_csp`. Default branch
`main`. CI runs format / analyze / tests / pana / examples /
benchmark on push.

---

## 4. The dispatch / extension pattern

Most features follow this structure:

1. **`types.dart`** (optional) — new dispatch flag on
   `NaryConstraint` if needed.
2. **`builtin_constraints.dart`** (optional) — new factory.
3. **`problem.dart`** — new extension `MyFeature on Problem`. Use
   `_addNary` for plain n-ary; construct `NaryConstraint` directly
   for tagged.
4. **`solver.dart`** (only if needed) — for propagation changes,
   new heuristics, or new solver entry points. New specialized
   propagator: add the class, add a dispatch branch in `seedFor`
   and `_propagate`'s n-ary branch, pass `cause: task.c` through
   `_setDomainRep`, call `_onConflict(task.c)` on every failure
   path.
5. **`test/<feature>_test.dart`** — full coverage.
6. **`README.md`** — new section.
7. **`PLAN.md`** — flip the item.
8. **`CHANGELOG.md`** — `## Unreleased` entry.
9. **`STABILITY.md`** — classify.
10. **`doc/<feature>.md`** — for non-trivial features.

---

## 5. Patterns from existing code

- **Optional flags on engine constructor.** Thread new mode
  variants (restarts, dom/wdeg, VSIDS, consistency level, CBJ)
  through `CSP.solve*` to `_BacktrackEngine(csp, …)`.
- **Count + fixed-k twin form** for counting helpers
  (`addAmong` + `addAmongExactly`, etc.). The variable form
  composes with `minimize` / `maximize`.
- **Predicate + tagged-flag pattern for globals.** Keep the
  soundness predicate; set the dispatch flag. Tagged constraints
  bypass the predicate but it stays as belt-and-braces.
- **Conservative-at-non-leaf, strict-at-leaf** for partial GAC.
  Soft fallback non-leaf; hard `null` when matching is unique at
  a leaf.
- **Decomposition-into-existing-primitives.** Set variables →
  per-element 0/1 indicators. `addInverse` → n² channelling
  binaries. `addLexChain` → k-1 consecutive lex-leq pairs. Add a
  follow-up note in PLAN.md if a specialized propagator would
  help.
- **Partial-assignment-aware predicates** (return true on
  partial). Examples: `lexLeq`, `lexLt`, `valuePrecedence`, diffn
  disjunction.
- **CBJ search structure.** Sealed `_SearchResult` with
  `_Solution` / `_Exhausted` / `_Backjump` for single-solution;
  engine-state-bag slots for streaming + optimization (async
  generators can't return a value).
- **Per-variable propagator seeding filter.** When propagator
  state lets you know which variables matter, filter wake-ups in
  `seedFor`. Width-2 carve-out for clauses — per-call overhead
  beats skip savings on narrow clauses; measure before adding a
  filter elsewhere.
- **`_onConflict(c)` for new heuristic bumps.** Single helper
  handles every conflict-driven bump (dom/wdeg, VSIDS).
- **MiniSat-style multiplicatively-grown bump.** VSIDS's
  `_activityInc` grows by `1 / decay`. Equivalent ranking, O(1)
  per conflict. Rescale at `1e100` to prevent overflow.
- **Heuristic picker fallback.** `dom / (1 + activity)` reduces
  to MRV when activity is zero. Pre-conflict ↔ MRV; post-conflict
  ↔ guilty-variable-first.
- **Worker-isolate runner.** Builder closure runs inside the
  worker (predicate closures aren't generally sendable). `_spawn`
  owns the single `ReceivePort` listener; callers plug in via
  `onMessage`. Cancellation forwards through
  `CancellationToken.addListener` to a `'cancel'` message on the
  worker's control port. Wire protocol is private.

---

## 6. Known gotchas

- **`CSP.lastStats` static slot** — overwritten by every solve.
  Capture immediately if comparing.
- **Set/identity equality** — see test conventions above.
- **Tagged-constraint leaf check** — see above.
- **Pre-existing empty domains** — `_reviseNary` treats as
  no-change. Guard if you mutate outside propagation.
- **Dart `part of` files share imports.** Parts can't add their
  own imports. `lib/src/lns/lns.dart` shares `problem.dart`'s
  imports.
- **Disk space.** This environment hit 100% disk during recent
  sessions; `dart test`'s `.dill` artifacts blow up under
  `/var/folders/.../`. If you hit `ENOSPC`, clean `~/.dart-tool`,
  `~/.dart`, `~/.dartServer`, and `/var/folders/.../dart_test*`.
  The Data volume was at 100% (now ~99%) when this handover was
  written — likely needs broader cleanup soon.

---

## 7. Open design questions

For LNS:
- **Default `iterationBudget`** — currently 100. A problem-shape
  heuristic (scale by variable count? by initial-objective?) would
  reduce the "user has to tune" friction. No data yet.
- **Cooperative-LNS bound semantics.** Currently every worker
  improvement is broadcast (parent filters by strict-improvement
  before re-broadcasting). Alternatives: threshold-only ("don't
  broadcast unless improvement > ε"); broadcast the full
  incumbent rather than just the objective. The full-incumbent
  variant trades diversity for convergence speed; no workload has
  motivated picking yet.
- **Late-acceptance + adaptive interaction.** LAHC and ALNS are
  independent today. A "stateful policy + stateful accept" hybrid
  might be worth exploring once a workload motivates it.

For FlatZinc:
- **Per-variable-set heuristic scoping.** `seq_search([…])` is
  parsed and walked, but dart_csp scopes its heuristic globally
  — every variable in the problem gets the same picker. Adding
  per-subset scoping would unlock `seq_search`'s real sequential
  semantics. Engine-level work (the picker doesn't have a
  variable-subset argument today), not a one-session item.

For the broader engine:
- **Float / real variables.** PLAN.md scopes the design space.
  Three months ago this was the top tactical add; the FlatZinc /
  LNS / conflict-explanation work moved it down. Pick this up if
  a continuous-quantities workload surfaces.
- **LCG / nogood learning.** The biggest gap. **`LCG_PLAN.md`**
  in the repo root has the full architecture (lazy atom encoding,
  first-UIP loop on `_ClausePropagator`, per-propagator
  explanation companions in priority order, M1–M6 milestones).
  Multi-session, 4–6 sessions; M1 alone is one session and lands
  the atom + implication-trail scaffold even if M2+ doesn't
  follow.

---

## 8. How to start

If you're picking up the recommended next item (M3-tighten —
intermediate atom encoding for first-UIP convergence on CSP
reasons): **read §0 "Recommended next pick" above end-to-end
first.** It documents what's been tried, what's broken, and what
specifically broke. Don't repeat experiments.

Concrete plan once you've read the debug log:

1. **Extend `_recordImplications`** (in `lib/src/solver.dart`) to
   emit `AtomLe(v, ub)` and `AtomGe(v, lb)` entries on the
   implication trail whenever a propagator tightens a bound
   (i.e., when the new domain's min strictly exceeds the old min,
   or the new max is strictly less than the old max). Today only
   `AtomEq` / `AtomNe` are emitted. The bound atoms are
   monotonically entailed under further pruning (rollback only
   grows domains → bound atoms stay non-falsified), so the
   watch-literal invariants in `_ClausePropagator` continue to
   hold.

2. **Add an `AtomInScc(varName, sccId)` intermediate atom** (or a
   similar propagator-specific shape) used by
   `_AllDifferentPropagator._buildHallSetReason`. The per-prune
   reason then becomes a chain: `prune ← AtomInScc(...) ←
   {AtomNe/AtomEq atoms forming the SCC's domain restrictions}`.
   The propagator commits `AtomInScc` entries to the trail when
   it computes the SCC decomposition, and the analyser resolves
   `prune` against `AtomInScc` first (which has ≤ 1 at-conflict-
   level antecedent — the SCC was just established at the current
   level), then resolves `AtomInScc` against its constituent
   atoms (which are at various lower levels).

3. **Verify the textbook 1-UIP convergence holds** by tracing
   the resolution on a small allDifferent UNSAT instance by
   hand and checking that the walk converges to a single
   at-level atom.

4. **Acceptance gate**: 4×4 magic-square (linear-spec sums)
   should learn ≥ 5 clauses (today: 0). Inkala's hardest sudoku
   should still find its unique solution (today: 2 clauses
   learned, SAT). Pigeonhole-CNF 7-in-6 should still cut ≥ 5×
   (today: ~9× under M2b). Run:
   ```
   dart test test/lcg/
   dart run benchmark/benchmark.dart
   ```

Don't take the shortcut of widening per-prune reasons to whole-
scope or relaxing the analyser's `atLevelCount != 1` guard —
both broke Inkala's hardest in this session (see debug log).
The structural intermediate-atom approach is what Chuffed and
OR-Tools both implement; references:
- `chuffed/engine/propagators/alldiffbc.c` — bounds-consistent
  allDifferent with explanations.
- Feydy & Stuckey 2009, "Lazy clause generation reengineered"
  — the canonical writeup of how to layer CSP propagator
  explanations on top of SAT-CDCL.

If you're picking up a perf-anchor bench section
(`bench(lcg)` or `bench(search-annotation)`): read
`benchmark/benchmark.dart`'s existing `bench(lns)` and
`bench(heuristic)` sections — they're the canonical shape for
warm-up + median methodology. The pigeonhole-CNF builder in
`benchmark/problems.dart` is what `bench(lcg)` should reuse.

If you're picking edge-finding for cumulative: read
`_CumulativePropagator` and find or build an RCPSP-style
benchmark first; without one the perf claim has no anchor.

For any other pick: scope it in a planning doc (mirror
`LNS_PLAN.md` / `MINIZINC_PLAN.md` / `LCG_PLAN.md` shape — scope,
architecture, milestones, open questions, references), commit
the doc first, then implement.

Test count to beat: **894**. Coverage philosophy: every public
helper has a test; every propagator has an activity-counter
assertion; every heuristic agrees with MRV on a unique-answer
problem.

Good luck.

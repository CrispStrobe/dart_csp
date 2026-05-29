## Unreleased

* **feat(lcg): tight allDifferent / GCC explanation via residual
  reachability (Régin / Quimper-Walsh).** Replaces the conservative
  tightness *bails* with sound explanations built by closing forward
  reachability in the residual digraph. For allDifferent
  (`_buildHallSetReason` + new `_reachHallSet`), the reach-closure from a
  pruned value's node yields a tight Hall set `(H, K)` with `|H| == |K|`
  that recovers the **free-vertex-slack** prunes the old entry-domain-
  union check bailed. For GCC (`_buildGccReason` + new `_reachGccCut`),
  multi-source reach over value *copies* yields a **capacity-aware
  saturated cut** (Régin 1996), recovering the Hall-set prunes the old
  fully-assignment-covered-only case bailed (it previously bailed *every*
  Hall-set prune). Both certify the Hall/cut condition explicitly and
  bail (sound chronological fallback) otherwise. Result: Inkala's hardest
  sudoku learns ~25 clauses (was ~8); the count-1 GCC encoding now learns
  *identically* to allDifferent. `CSP.solveWithLcg` / `Problem.solveWithLcg`
  gained `useVsids` / `useDomWdeg` / `seed` parameters (the learning loop
  is sound + complete under any picker). Soundness re-validated across 240
  randomized-VSIDS-order unique-solution runs (0 failures) and randomly
  generated multi-copy GCC instances cross-checked against full
  enumeration. 4 new tests (`test/lcg/tight_hall_set_test.dart`); 984
  total. `LCG_PLAN.md` §M4 item 2 closed; `doc/lcg.md` updated.

* **docs(chore): split the roadmap into `PLAN.md` (next) +
  `HISTORY.md` (done).** Moved every shipped strategic gap and tactical
  win, plus the original Tier 1/2/3 retrospective, out of `PLAN.md` into
  a new `HISTORY.md`. `PLAN.md` is now purely forward-looking (LCG
  `[~]`, float variables, edge-finding cumulative, the workload-gated
  list). Cross-references in `HANDOVER.md` / `README.md` / `LCG_PLAN.md`
  updated; the per-feature checklist now says "move the entry from
  `PLAN.md` to `HISTORY.md`" when an item ships. The LCG strategic-gap
  marker is `[~]` (in progress) to reflect M1–M3c shipped with the
  learning path still maturing.

* **fix(lcg): GCC explanation soundness — bail the unverified Hall-set
  shape.** `_GccPropagator._buildGccReason` had the same latent
  non-tight-Hall-set unsoundness fixed for allDifferent: it attributed a
  prune to the value-SCC's member variables' entry absences, which are
  not provably a tight Hall set under per-value capacities. Replaced with
  a conservative, *sound-by-construction* explanation: the bridge emits
  antecedents only when **every copy of the pruned value is held by a
  pinned owner** (assignment — `∧ AtomEq(owner_k, v)` then entails the
  prune); any copy that is free or trapped in an SCC bails the bridge
  (empty antecedents → the analyser can't resolve through it →
  chronological fallback). GCC-as-allDifferent on Inkala still learns
  clauses via the assignment case (`gcc_explain_test` unchanged). A
  capacity-aware *tight* Hall-set explanation (the alternating-path Régin
  construction) remains future work — `LCG_PLAN.md` §M4. Dropped the now
  -unused Hall-set entry-snapshot bookkeeping from the GCC LCG setup.

* **fix(lcg): root-cause + fix the order-dependent "learned-but-FAILURE
  on SAT" bug — it was two independent bugs (unsound clauses +
  incomplete backjump).** The recurring symptom (a non-MRV decision
  order makes `solveWithLcg` return `FAILURE` on a satisfiable problem)
  was diagnosed with a known-solution soundness auditor over 320
  randomized VSIDS decision orders on unique-solution sudokus. Both
  bugs are now fixed; the sweep shows **0 unsound clauses and 0 FAILUREs**
  (was 3/6/1/2 unsound and 13/5 FAILUREs across the configs).

  - **Bug 1 — unsound learned clauses (two sources).**
    (a) `_recordImplications` recorded a propagator prune that
    *incidentally* collapsed a domain to a singleton as a single
    `AtomEq(var, survivor)` attached to that propagator's reason — but
    the reason only justifies the values *it* removed, not the full
    assignment (the other values were removed by earlier causes), so the
    `AtomEq` over-claims and the learned clause can forbid the real
    solution. Fix: emit the singleton `AtomEq` only when the reason
    forces the exact value (a decision pin, or a boolean variable where
    `AtomEq ≡ AtomNe(other)`); for propagator prunes emit per-removed-
    value `AtomNe`, each soundly entailed by the reason.
    (b) `_AllDifferentPropagator._buildHallSetReason` attributed a prune
    to the value-SCC's member variables even when they are *not* a tight
    Hall set (their entry domains union to more values than members,
    e.g. via free-vertex slack), which does not entail the prune. Fix:
    validate tightness (`|union of members' entry domains| == |members|`)
    and emit the confining absences only; otherwise leave the bridge
    unresolvable so the analyser bails (sound — no clause, chronological
    fallback).
  - **Bug 2 — incomplete non-chronological backjump.** A recursive
    backtracker cannot soundly perform CDCL-style backjumps: unwinding
    several frames to a learned clause's asserting level abandons the
    intermediate frames' untried candidate values, and the asserting
    clause does not re-introduce them, so the search is *incomplete*.
    (Re-solving the landing frame fresh restores completeness but
    re-explores failed candidates and blows up — the previously-banked
    "re-pick" dead-end.) Fix: `_searchOneLcg` now backtracks
    **chronologically** and keeps clause learning; the posted clauses
    still prune via propagation — measurably *better* on pigeonhole
    7-in-6 (283 decisions, learns 224 clauses, vs the old incomplete
    backjump's 365 decisions / 154 clauses; plain backtrack 3245). The
    `_LcgBackjump` signal type is removed.
  - **Gate re-baselines.** `SolverStats.backjumps` is now 0 on the LCG
    path (chronological), so `backjumps > 0` acceptance assertions became
    decision-reduction / `backtracks > 0` assertions. The 4×4
    magic-square M3-tighten gate dropped from "≥ 5 learned" to "≥ 1"
    (current sound value 3): the prior 5 counted clauses built from
    non-tight Hall sets — unsound, and only harmless on the 4×4 because
    it has many solutions. Pigeonhole 7-in-6 / 8-in-7 still cut ≥ 5× /
    ≥ 10×.
  - **Not fixed (documented follow-up).** Restoring the non-chronological
    backjump *speedup* soundly needs an iterative trail-based CDCL engine
    (the recursive search can't do it); and a sound *and* tight
    allDifferent/GCC explanation for the free-vertex-slack prunes needs
    the alternating-path Régin construction. Both are scoped in
    `LCG_PLAN.md` (§M4 + §M3-tighten). MRV stays the LCG picker; the
    search is now sound + complete under *any* picker (verified VSIDS).
  - 980 tests (unchanged); gate assertions re-baselined in
    `test/lcg/{pigeonhole,all_different_explain,gcc_explain,m3_tighten_diagnosis}_test.dart`.

* **feat(lcg): M3c — `_GccPropagator` network-flow explanation
  companion.** Extends the M3-tighten `AtomInScc` bridge to the global
  cardinality constraint, so GCC-driven conflicts learn clauses instead
  of falling back to chronological backtrack.

  - **New `GccFlowReason`** (`lib/src/lcg/explain.dart`), mirroring
    `AllDifferentReason`'s shape (carries synthetic `AtomInScc` bridge
    antecedents).
  - **`_GccPropagator` per-prune reasons.** The propagator gains the
    same LCG plumbing as allDifferent (`originalDomains` + `recordScc`
    + a `reason:` kwarg on `applyUpdate`). For each value removed from a
    variable it commits one bridge per value (shared across siblings),
    handling multiplicity: each matched copy of the value contributes
    `AtomEq(owner, v)` when its owner is pinned to `v` (assignment), else
    the Régin Hall-set absences of the variables sharing that copy's SCC,
    snapshotted at propagation entry. The constraint-level conflict
    reason routes through one whole-scope bridge (shared
    `_scopeConflictBridge` helper, also used by allDifferent).
  - **Activation.** A GCC with every value required exactly once is
    equivalent to allDifferent; on Inkala's "World's Hardest Sudoku"
    expressed that way, LCG now learns 8 clauses with 3 backjumps and
    cuts backtracks 48 → 42 (was 0 learned — GCC carried no
    explanation). Easy GCC instances that solve at the root are
    unaffected (no search conflicts to learn from).
  - New `test/lcg/gcc_explain_test.dart` (5 tests); 980 total
    (was 975). Régin 1996.

* **feat(lcg): M3-tighten — `AtomInScc` intermediate atom for
  allDifferent first-UIP convergence (`LCG_PLAN.md` §3 task 1).**
  Closes the diagnosed convergence gap on allDifferent-driven
  conflicts: the analyser now learns clauses on dense CSP conflicts
  where it previously bailed on every backtrack.

  - **New synthetic `AtomInScc` atom** (`lib/src/lcg/atom.dart`).
    A non-assertable *bridge* literal (`isSynthetic == true`) that
    collapses a whole "why is this value unavailable" argument into a
    single resolvable atom. `negate()` / `isEntailedBy()` throw — a
    synthetic atom must never reach a learned clause or be evaluated
    as a clause literal. A new `Atom.isSynthetic` getter (default
    `false`) distinguishes it from the four real domain atoms.
  - **`firstUipAnalyse` resolves *through* synthetic atoms.** The
    at-conflict-level count is split into real vs synthetic; the walk
    keeps resolving while any synthetic at-level atom remains, never
    picks a synthetic as the UIP, and bails (no clause) if a synthetic
    can't be resolved through — so a synthetic literal can never leak
    into a learned clause.
  - **`_AllDifferentPropagator` emits per-value bridge reasons.** For
    each value removed from a variable it commits one `AtomInScc`
    (shared across every prune of that value, so siblings collapse),
    picking a sound shape: `AtomEq(owner, v)` when the value is held
    by a pinned variable (assignment propagation — the on-trail
    "newest cause"), else the Régin Hall-set absences snapshotted at
    propagation *entry* (so they never reference this round's sibling
    prunes — the circular shape that defeated the coarse explanation).
    The constraint-level conflict reason is routed through one
    whole-scope bridge the same way.
  - **Acceptance gate (all met).** 4×4 magic square learns ≥ 5 clauses
    (was 0, every backtrack an analysis failure); 3×3 converges on
    every conflict (0 failures); Inkala's "World's Hardest Sudoku"
    still solves and now learns 8 clauses (was 2 — no regression);
    pigeonhole-CNF still cuts ≥ 5×. New synthetic-atom design tests
    in `test/lcg/m3_tighten_diagnosis_test.dart`; its magic-square
    end-to-end expectations flipped from the coarse "bail on every
    conflict" baseline to the new learning gate. 975 tests total
    (was 972).

  Linear bound-atom encoding (`LCG_PLAN.md` §3 task 2) remains the
  secondary follow-up: it lands after task 1 so a mixed
  allDifferent+linear conflict can converge end to end.

* **feat(lcg): M3-tighten kickoff — analyser instrumentation +
  measured diagnosis + design validation.** Lands the disciplined
  first step of the M3-tighten refactor (per `HANDOVER.md`: build a
  minimum-viable reproducer and instrumentation before any engine
  surgery), without changing engine behaviour.

  - **`firstUipAnalyse` gains an optional `trace` callback** (pure,
    diagnostic-only — emits the initial working clause, every
    resolution step with its at-conflict-level count, and the
    terminal UIP/bail reason). Null on the hot path.
  - **New `SolverStats.lcgAnalysisFailures`** counts conflicts that
    carried a concrete (non-opaque) reason but where the analyser
    could not isolate a single UIP. Incremented at the `_searchOneLcg`
    fallback site; `0` for every non-LCG entry point.
  - **Measured the gap.** On the 4×4 magic square, all 7 backtracks
    are analysis failures (`lcgAnalysisFailures == backtracks`,
    `learnedClauses == 0`); the 3×3 shows the same at smaller scale.
    Tracing a real conflict confirmed the root cause: resolving an
    at-level atom against a coarse `LinearBoundReason` *adds* more
    at-conflict-level on-trail atoms than it removes (the trace shows
    the count climbing 6 → 9), so the walk never converges to a UIP.
  - **Validated the fix direction on hand-built trails** (the new
    `test/lcg/m3_tighten_diagnosis_test.dart` is an executable design
    spec): coarse sibling-referencing reasons diverge and bail; a
    "newest-cause" shape (each prune references the single decision
    that forced it) converges to a unit UIP; and a "real intermediate
    bound atom" shape (each prune references one `AtomGe`/`AtomLe`
    that is itself on the trail) converges with the learned clause
    carrying the negated bound — confirming the bound atom is a real,
    assertable literal, which is what makes the intermediate-atom
    encoding work for linear constraints.
  - 6 new tests; 972 total (was 966). No engine-behaviour change;
    all existing acceptance tests (Inkala's hardest, pigeonhole-CNF,
    sudoku-medium) unaffected.
  - **Two engine-surgery dead-ends ruled out** (implemented end-to-end,
    measured, reverted; findings banked in `LCG_PLAN.md` §M3-tighten):
    (a) the sound linear bound-atom encoding alone leaves
    `learnedClauses == 0` because the magic-square conflicts are
    **allDifferent-detected**, not linear; (b) per-atom
    trail-shape-matching (`AtomEq` for pinned vars in
    `_domainShapeAntecedents`) *reduced* learning (Inkala 2 → 0). The
    re-prioritised next increment is an `AtomInScc` intermediate atom
    for `_AllDifferentPropagator`, gated on Inkala still solving and
    still learning ≥ 2.

* **docs(lcg): M3-tighten roadmap + debug log.** Two structural-fix
  shortcuts (multi-UIP analyser relaxation, whole-scope M3a
  per-prune reason) were attempted in this cycle to lift the
  M3a/M3b coarse-antecedent limitation; both broke existing
  acceptance tests (Inkala's hardest sudoku returning `FAILURE`
  on a SAT problem) and were reverted. `HANDOVER.md` §0
  "Recommended next pick" and `LCG_PLAN.md` §3 M3-tighten now
  document what was tried, why it failed, and the structural
  intermediate-atom-encoding approach (Chuffed / OR-Tools / Feydy &
  Stuckey 2009) that the next session should take. `doc/lcg.md`
  caveat box updated with the same context.

* **LCG M3b — `_LinearPropagator` bound-explanation plumbing.**
  Second per-propagator `explain` companion. New
  `LinearBoundReason extends ImplicationReason` in
  `lib/src/lcg/explain.dart`. The propagator builds per-prune
  antecedents from the other variables' current domain absences,
  mirroring the M3a shape; the engine call site in `_propagate`
  threads the reason through `_setDomainRep` and captures
  `_lastConflictReason` on linear-propagator failures via a new
  `_linearConflictReason` helper.

  - **Shared `_domainShapeAntecedents` helper** in `solver.dart`
    centralises the coarse "AtomNe for every absent declared value"
    antecedent shape used by both M3a and M3b reason-builders.
  - **Acknowledged limitation.** The first-UIP analyser converges
    on tight per-prune antecedents but bails when the conflict
    reason includes many at-conflict-level atoms — the case for
    the coarse "whole constraint scope" reasons on dense conflict
    problems (e.g. 4×4 magic squares). M3a still learns on sudoku-
    medium (1 clause) where the conflict happens to be tractable;
    M3b's plumbing is in place but the analyser activates only
    occasionally until a future per-prune-tight refinement lands.
    The wiring is the contribution; the algorithmic refinement is
    a separate follow-up tracked alongside M3c–g.
  - 7 new tests (`test/lcg/linear_explain_test.dart`):
    `LinearBoundReason` construction, SEND+MORE=MONEY and
    magic-square-3x3 correctness via solveWithLcg, linear-UNSAT
    root detection, plus pigeonhole-CNF and sudoku-medium
    regression guards. 966 total (was 959).

* **LCG M3a — `_AllDifferentPropagator` Hall-set explanation.**
  First per-propagator `explain` companion, building on the lazy-atom-
  encoding extension. Conflicts that flow through the Régin
  allDifferent propagator now drive LCG learning instead of falling
  back to chronological backtrack.

  - **`AllDifferentReason` extends `ImplicationReason`.** Concrete
    subclass carrying the Hall-set antecedent atoms. Lives in
    `lib/src/lcg/explain.dart`. Replaces M2b's `UnknownReason`
    placeholder on the allDifferent path.
  - **`_AllDifferentPropagator.propagate` extracts the Hall set off
    the existing Régin SCC decomposition.** For prunes of variable
    `i`, the Hall set is the union of SCCs of all pruned values; the
    antecedents are `AtomNe(h, k)` for every Hall-set variable `h`
    and every value `k` declared in `h`'s domain at problem-
    construction time but absent from `h`'s current domain. The
    propagator's existing matching + SCC + reachability state is the
    full input; no extra computation beyond the per-prune `varsInScc`
    grouping (built once per call, only when LCG is on).
  - **Engine plumbing.** `_AllDifferentPropagator` learns an optional
    `originalDomains:` constructor parameter — non-null only when
    `enableLcg` is true, so non-LCG callers pay zero cost. The
    propagator's `applyUpdate` signature gains a `reason:` kwarg
    matching the clause propagator's shape. Engine call site in
    `_propagate` threads the reason through `_setDomainRep`. New
    `_allDifferentConflictReason` helper handles the matching-
    failure / pigeonhole / empty-domain conflict paths by using the
    full constraint scope as the Hall set.
  - **End-to-end acceptance.** Inkala's "World's Hardest Sudoku"
    (2010) goes from plain 32 decisions / 48 backtracks to LCG 31
    decisions / 43 backtracks with 2 learned clauses + 1
    non-chronological backjump skipping 1 level. The gain is modest
    in absolute terms because most sudoku backtracks still route
    through binary `!=` predicates that emit `UnknownReason`; M3b–g
    will accumulate per-propagator coverage so the analyser can
    resolve cleanly through more conflict types.
  - 8 new tests
    (`test/lcg/all_different_explain_test.dart`): `AllDifferentReason`
    construction, end-to-end sudoku medium + Inkala's hardest
    correctness, M2b CNF-path regression, root-detected pigeonhole-
    via-allDifferent. 959 total (was 951).

* **LCG — lazy atom encoding for `_ClausePropagator`.** Foundational
  extension that unlocks the per-propagator `explain` companions
  (M3) by letting the engine post learned clauses with non-boolean
  atom literals. M2b could only produce learned clauses when every
  atom resolved to a `{0, 1}` literal; any conflict whose
  antecedents touched a non-boolean atom fell back to chronological
  backtrack. The atom-clause shape lifts that restriction.

  - **`ClauseSpec` gains an optional `atoms: List<Atom>?` slot.**
    When non-null, the literals are interpreted as atom literals
    (each satisfied iff the atom is entailed by the variable's
    current domain). Boolean clauses (`literals:`) and atom clauses
    (`atoms:`) coexist on the same spec type; exactly one is
    non-empty. User-facing `Problem.addClause` continues to only
    produce boolean clauses — atom clauses are LCG-internal and
    surface only as learned clauses.
  - **`_ClausePropagator` learns the atom-clause dispatch.** New
    `_evalAtAtom` / `_filterForAtom` / `_antecedentsForForce` paths
    handle `AtomEq` / `AtomNe` / `AtomLe` / `AtomGe`. The two-
    watched-literal scheme is preserved: monotone-under-trail
    holds for all four atom kinds because the engine's rollback
    only grows domains, which can only make a previously non-
    falsified atom stay non-falsified.
  - **`_DomainViewAdapter`** bridges the engine's private
    `_DomainRep` hierarchy to the public `DomainView` interface
    used by `Atom.isEntailedBy`. O(1) `minValue` / `maxValue` for
    interval and bitset reps, O(n) for list — with per-call
    caching so repeated atom evals against the same domain don't
    re-scan.
  - **`_learnedClauseToSpec` dispatch.** Picks the boolean encoding
    when every atom resolves to `{0, 1}` (cheaper per-prop eval,
    same fast path as user-posted clauses); falls back to the atom
    encoding otherwise. The "non-boolean → chronological backtrack"
    fallback from M2b is gone.
  - **`_postLearnedClause` + `_learnedClausePredicate`** handle
    both shapes — atom shape evaluates each atom against the
    assignment via a switch on the atom kind. Variable scope is
    deduplicated since one variable may appear in multiple atom
    literals of the same clause.
  - 9 new tests (`test/lcg/atom_clause_test.dart`) covering each
    atom kind's eval, unit-prop, conflict detection, three-literal
    clauses, and a parity check that the boolean learned-clause
    fast path still triggers on the pigeonhole regression. 951
    total (was 942).

* **`bench(lcg)` perf anchor.** Closes the "perf claims need warm-up
  + median methodology" gate for the M2b LCG feature shipped earlier
  this cycle. New section in `benchmark/benchmark.dart` runs plain
  backtracking (`Problem.getSolution`) and LCG (`Problem.solveWithLcg`)
  back-to-back on the same problem builder with the standard
  5-warmup + 25-rep median methodology. Three pigeonhole-CNF
  showcase rows (6-in-5 / 7-in-6 / 8-in-7) demonstrate the
  decision-count reduction grows with problem size — ~3× → ~9× →
  ~29× — and one 8-queens "wash" row anchors the
  non-regression claim that LCG's per-prune trail bookkeeping is
  negligible on problems where the conflicts don't flow through the
  boolean clause propagator (engine falls back to chronological
  backtrack, decisions match plain exactly). `doc/lcg.md` gains a
  "Perf anchor" subsection with an indicative results table.

* **Lazy Clause Generation (LCG) — milestone M2b.** Closes the M2
  half-pair: the first-UIP analyser is now wired into the engine
  and `Problem.solveWithLcg` performs real conflict-driven nogood
  learning. On pigeonhole-CNF UNSAT proofs the search-tree size
  drops by an order of magnitude — 7-in-6 cuts decisions ~9× vs
  plain backtracking, 8-in-7 cuts ~29×.

  - **`_searchOneLcg` recursion** mirrors the CBJ
    sealed-`_SearchResult` pattern. On every propagation failure
    the engine calls `firstUipAnalyse`, converts the learned atoms
    back into a boolean `ClauseSpec`, posts it dynamically into
    `_csp.naryConstraints` + `_naryIdx`, and signals a
    `_LcgBackjump(targetLevel)` up the search stack. Caller frames
    roll back their own pin and either propagate the signal further
    up or consume it (when `targetLevel == depth`) and re-propagate
    so the freshly-posted clause's UIP literal can assert at the
    landing frame. Recursion depth equals the pre-pin decision
    level, so the analyser's backjump targets map directly.
  - **Boolean-clause restriction.** The analyser's learned atoms
    are converted into a `ClauseSpec` only when every atom is over
    a `{0, 1}` variable; non-boolean atoms fall back to chronological
    backtrack. Conflicts whose antecedents include any
    `UnknownReason` from a non-clause propagator also fall back —
    M3's per-propagator `explain` companions are what unlock those.
  - **Conflict-reason capture.** New `_lastConflictReason` slot on
    `_BacktrackEngine` (set at the clause-propagator failure site
    inside `_propagate`); the LCG search loop reads it immediately
    after a `_propagate` returning `false` and feeds it as the seed
    reason to `firstUipAnalyse`.
  - **FIFO forget policy.** New `_learnedClauses` list +
    `_forgetIfNeeded()` helper drops the oldest half of the pool
    when its size exceeds the configurable threshold (default
    1000). Exposed as `learnedClauseCap:` kwarg on
    `Problem.solveWithLcg` / `CSP.solveWithLcg`.
  - **`SolverStats` gains `learnedClauses` + `forgottenClauses`.**
    Both `0` for non-LCG entry points. LCG also bumps the existing
    `backjumps` / `backjumpLevelsSkipped` counters per
    non-chronological backjump.
  - **`LCG_PLAN.md` strategic-gap entry flips to `[x]` for M2b.**
    `STABILITY.md` and `README.md` updated with the new surface.
    `doc/lcg.md` documents the M1+M2 combined behaviour.
  - 6 new tests (`test/lcg/pigeonhole_test.dart` — 6-in-5 / 7-in-6 /
    8-in-7 acceptance gates plus forget-cap behaviour, non-boolean
    fallback, mixed-domain SAT). 942 total (was 936).

* **`bench(cooperative-lns)` perf anchor.** Closes the
  "perf claims need warm-up + median methodology" gate for the
  cooperative parallel LNS feature shipped earlier this cycle.
  New section in `benchmark/benchmark.dart` runs portfolio
  (`cooperative: false`) and cooperative (`cooperative: true`)
  back-to-back on the same problem builder, worker count, seed
  list, and iteration budget — only the flag differs. Default
  workload is `bin-packing 12 items / 3 bins` with 3 workers,
  random destroy (fraction 0.5), and an iteration budget of 80;
  warm-up of 1, 3 timed reps, median wall-clock per row.
  Sample run shows both modes converging to the same global
  incumbent (`obj=30`) with cooperative within ~10–20% wall-clock
  variance of portfolio — i.e. a non-regression anchor on this
  size instance. `doc/lns.md`'s "Cooperative parallel LNS"
  section now includes a perf-anchor subsection with sample
  output.

* **Lazy Clause Generation (LCG) — milestone M2a.** Builds on M1:
  the first-UIP conflict analyser ships as a pure, verified
  function over the implication trail. M2a does **not** yet wire
  the analyser into the engine — `solveWithLcg` still uses
  chronological backtracking — but the analyser is ready for
  M2b's engine surgery (dynamic learned-clause posting +
  backjump). Tested against hand-crafted trails covering
  decision-only conflicts, multi-step resolution chains,
  cross-level antecedents, and opaque-reason fallbacks.

  - **`ClauseReason`** concrete subclass of `ImplicationReason`.
    Carries the antecedent atoms for a clause unit-prop.
    `_ClausePropagator` emits it on every forced literal; the
    falsifying value of each other literal becomes an
    `AtomEq(varName, positive ? 0 : 1)` antecedent.
  - **`_setDomain` / `_setDomainRep` learn an optional `reason:`
    named param**, threaded through `_recordImplications`. When
    callers pass a concrete reason it overrides M1's
    `UnknownReason` placeholder. Only `_ClausePropagator`
    threads a reason today; M3 will plumb it through the
    specialised propagators (allDifferent, linear, etc.).
  - **`AnalysisResult` + `firstUipAnalyse`** in
    `lib/src/lcg/analyze.dart`. Walks the trail backward,
    resolving at-level atoms one at a time until a single UIP
    remains. Returns the learned clause as a list of atoms (the
    disjunction over negations of currently-entailed atoms),
    plus the backjump level and the asserting UIP. Conservatively
    returns null when the analyser hits an opaque reason
    (`UnknownReason`) at the conflict level — sound but weaker
    than full M3 coverage will deliver.
  - 12 new tests (`test/lcg/clause_reason_test.dart` +
    `test/lcg/analyze_test.dart`); 936 total (was 924).

* **Lazy Clause Generation (LCG) — milestone M1.** First slice of
  the LCG strategic-gap pick lands: atom encoding, parallel
  implication trail wired into `_BacktrackEngine`, and a
  `Problem.solveWithLcg` runner shell with the same return contract
  as `getSolution`. M1 is **wiring + types only** — the first-UIP
  conflict-clause learning loop arrives in M2, per-propagator
  explanation companions in M3. Marked experimental in
  `STABILITY.md`. See `LCG_PLAN.md` for the full milestone roadmap.

  - **New public types** under `lib/src/lcg/`:
    - `Atom` sealed hierarchy: `AtomEq`, `AtomNe`, `AtomLe`,
      `AtomGe` — four shapes covering every prune the engine
      makes. Each carries `varName + int value`, negates to its
      logical counterpart (`AtomEq.negate()` → `AtomNe`,
      `AtomLe(v).negate()` → `AtomGe(v+1)`, etc.), and exposes
      `isEntailedBy(DomainView)` for M2 conflict analysis.
    - `DomainView` — narrow public interface (`contains`,
      `minValue`, `maxValue`, `isSingleton`, `isEmpty`) so atoms
      can be tested without depending on the engine's private
      `_DomainRep`.
    - `ImplicationReason` abstract base + `UnknownReason` /
      `DecisionReason` placeholders. Per-propagator concrete
      subclasses are M3 work.
    - `ImplicationEntry` — one entry on the implication trail
      pairing `(prunedAtom, reason, trailIndex, decisionLevel)`.
  - **`_BacktrackEngine` gains an `enableLcg` flag.** Off by
    default; zero cost when off. When on, `_setDomain` /
    `_setDomainRep` append `ImplicationEntry` records to a
    parallel `_implicationTrail`; `_trailRollback` pops in
    lockstep with the domain trail; a per-engine
    `_decisionLevel` counter is maintained automatically by
    watching `cause: null` trail entries (decision pins). Non-int
    domain values are silently skipped — atoms are integer-only
    by design.
  - **`Problem.solveWithLcg`** + **`CSP.solveWithLcg`** entry
    points. Same `Future<dynamic>` contract as `getSolution`.
  - **`CSP.lastImplicationTrail`** static slot (mirrors
    `CSP.lastStats`). Populated by `solveWithLcg` for tests and
    tooling.
  - 30 new tests (`test/lcg/atom_test.dart`,
    `test/lcg/implication_trail_test.dart`,
    `test/lcg/solve_with_lcg_test.dart`); 924 total (was 894).

* **Cooperative parallel LNS.** Tactical-win extension to the
  portfolio LNS runner: `lnsMinimizeInIsolates` /
  `lnsMaximizeInIsolates` now accept `cooperative: true`, which
  wires a mid-run incumbent broadcast through the existing
  worker-isolate wire protocol. When any worker finds a new
  local best, the parent forwards the objective bound to every
  sibling via the control port; siblings use the bound to
  pre-tighten the objective domain of their next sub-problem
  and skip iterations that provably can't beat the global best.

  - **New wire-protocol kind.** Worker → parent
    `['bound', num]` reply on every local improvement; parent
    re-broadcasts to siblings via a new `['bound', num]` control
    message kind handled in the existing per-worker control
    listener.
  - **`_LnsOpts.cooperative` flag.** Default false (the existing
    portfolio shape is unchanged). When true, the worker
    installs `boundHint:` / `onIncumbent:` callbacks on its
    `lnsMinimize` / `lnsMaximize` call.
  - **`Problem.lnsMinimize` / `lnsMaximize` learn `boundHint:`
    and `onIncumbent:` params** — the cooperative-LNS plumbing
    hooks. Both default to null, in which case the LNS loop
    behaves exactly as before. When provided, `boundHint` is
    polled each iteration to tighten the sub-problem objective
    domain; `onIncumbent` is invoked on every local improvement.
  - **`LCG_PLAN.md`** ships in the repo root alongside this — the
    scoping doc for the next strategic-gap pick (lazy clause
    generation / nogood learning). Architecture, milestones, the
    eager-vs-lazy atom-encoding decision, per-propagator
    explanation contracts, and references; mirrors the
    `LNS_PLAN.md` / `MINIZINC_PLAN.md` shape.

  - 5 new tests (`test/lns/parallel_test.dart` +
    `test/lns/integration_test.dart`); 894 total (was 889).

* **FlatZinc search-annotation mapping.** Tactical-win delivery —
  the `:: int_search(...)` / `:: bool_search(...)` / `:: seq_search(...)`
  annotations on a `solve` directive now actually route through
  dart_csp's heuristic knobs instead of being parsed-and-ignored.

  - **Hint extraction.** `lib/src/flatzinc/runner.dart` reads the
    `varSelect` keyword (second arg of `int_search` / `bool_search`)
    and maps it to the matching `Problem.getSolutionWithX` /
    `Problem.minimize` / `Problem.maximize` flag: `dom_w_deg`
    (also `most_constrained`, `weighted_degree`) → `useDomWdeg`;
    `activity_var` (also `activity_var_min`, `vsids`) → `useVsids`;
    `impact` → `useImpact`. `bool_search` is treated identically to
    `int_search`. Unrecognised keywords (`input_order`, `first_fail`,
    `smallest`, etc.) silently fall back to the default MRV picker,
    matching the FlatZinc convention that solvers may ignore
    unsupported hints.

  - **`seq_search` support.** Required a parser bump:
    `lib/src/flatzinc/parser.dart` now recognises nested annotation
    calls (`identifier '(' args ')'`) as a new `AstAnnotationCall`
    expression node, so `seq_search([int_search(...), int_search(...)])`
    parses cleanly. The hint extractor walks the inner array and
    returns the first recognised `varSelect`; subsequent inner
    searches contribute only if earlier ones used unrecognised
    keywords. The hint is global (dart_csp doesn't yet scope
    heuristics to variable subsets), so `seq_search` does not yet
    drive sequential per-group search — the variable lists are
    informational and the chosen picker scores every variable in
    the model.

  - **Optimisation routing.** `CSP.solveOptimal` and
    `Problem.minimize` / `Problem.maximize` now accept the same
    `useDomWdeg` / `useVsids` / `useImpact` / `useLastConflict`
    flags the satisfaction entry points expose, threaded through to
    `_BacktrackEngine`. The FlatZinc runner forwards the extracted
    hint to the optimisation path the same way it already did for
    satisfy — so `solve :: int_search(q, dom_w_deg, ...) minimize total`
    actually runs branch-and-bound under dom/wdeg.

  - 11 new tests (`test/flatzinc/m6_polish_test.dart` +
    `test/flatzinc/parser_test.dart` +
    `test/optimization_test.dart`); 889 total (was 878). See
    `doc/flatzinc.md` for the supported subset and caveats.

* **Large Neighborhood Search (LNS).** Strategic-gap delivery —
  metaheuristic optimization that decomposes a hard `minimize` /
  `maximize` problem into a sequence of small focused sub-solves.

  - **Entry points.** `Problem.lnsMinimize` / `Problem.lnsMaximize`
    on the new `LargeNeighborhoodSearch` extension. Each finds an
    initial feasible solution via `CSP.solve` (not `solveOptimal`
    — proving optimality up front would defeat the point), then
    iteratively destroys a subset of variables (frees them while
    pinning every other variable to its incumbent value), re-solves
    the smaller sub-problem with `CSP.solveOptimal`, and replaces
    the incumbent when the acceptance strategy admits the candidate.
    Returns an `LnsResult` with the best assignment + per-run
    `LnsStats` (iterations, accepts, rejects, infeasibles, timeouts,
    initial / final objective, elapsed micros). Knobs:
    `iterationBudget` (default 100), `iterationTimeMs` /
    `totalTimeMs` (cooperative time bounds), `seed` (RNG seed for
    reproducibility), plus the usual `consistency`,
    `enableConflictBackjumping`, and `cancelToken` parameters from
    the underlying solver.

  - **Destroy policy catalogue.** Five shipped policies on
    `LnsPolicy` — `random(fraction: 0.2)` (uniformly random subset,
    Shaw 1998 textbook starting point), `window(windowSize: N)`
    (contiguous-by-declaration-order, useful on scheduling-shaped
    problems), `related(seedCount: 1, extendFraction: 0.2)` (Shaw
    1998's BFS expansion through the constraint-variable graph),
    `combined([…], weights: […])` (weighted-random pick from
    sub-policies with static weights), and
    `adaptive([…], segmentSize: 100, smoothingFactor: 0.1,
    rewardBest: 5, rewardAccepted: 1)` (Ropke & Pisinger 2006:
    per-segment reward-based re-weighting with a small positive
    weight floor so a starved sub-policy can recover). Users
    extend `LnsPolicy` for custom destroys (extends, not
    implements, so they inherit the default no-op `observe`);
    `LnsContext` exposes the variable list, incumbent, iteration
    counter, RNG, and a pre-built constraint-variable adjacency
    graph. The new `observe(ctx, accepted, improvedBest)` hook on
    `LnsPolicy` lets stateful policies see per-iteration feedback;
    default impl is a no-op for the non-adaptive policies.

  - **Acceptance catalogue.** Three shipped acceptances —
    `LnsAccept.improving()` (strict improvement only, converges to
    a local optimum), `LnsAccept.simulatedAnnealing(initialTemp,
    cooling)` (textbook cooling — accepts worsening moves with
    probability `exp(-Δ / T)` to escape local optima), and
    `LnsAccept.lateAcceptance(historySize: 100)` (Burke et al.
    2017's LAHC — accept iff candidate beats current incumbent OR
    the historical incumbent from `historySize` iterations ago;
    one hyperparameter, empirically strong on combinatorial
    optimization).

  - **Best-ever tracking.** The orchestrator tracks "current
    solution" (what the next destroy iteration runs on top of)
    and "best-ever solution" (what gets returned) separately, so
    SA-admitted and LAHC-admitted worsening moves cannot lose the
    best objective LNS observed at any point.

  - **Performance.** New `bench(lns)` section in
    `benchmark/benchmark.dart` compares LNS vs plain
    `Problem.minimize` on bin-packing min-max-load (8, 10, 12
    items / 3 bins). On the 12-item instance LNS finds the
    optimum ~14× faster than plain B&B; smaller instances narrow
    that gap (plain wins on tiny problems where the per-iteration
    overhead can't be amortised). New `buildBinPackingMinMaxLoad`
    builder in `benchmark/problems.dart`.

  - **Architecture.** `lib/src/lns/policy.dart` and
    `lib/src/lns/accept.dart` are standalone libraries holding the
    public abstract bases + builtin factories.
    `lib/src/lns/lns.dart` is a `part of '../problem.dart';` so
    the orchestration extension can read the host `Problem`'s
    private `_constraints` / `_naryConstraints` / `_variables`
    when building the per-iteration sub-problem CSP.

  - **Stability.** Experimental — `STABILITY.md` flags the
    surface as subject to change while ALNS adaptive weighting,
    late-acceptance hill-climbing, and parallel LNS (the
    Tier-2 follow-ups noted in `LNS_PLAN.md` §3 milestone M5)
    are still in flight.

  - **Parallel LNS (portfolio mode).** Top-level functions
    `lnsMinimizeInIsolates` / `lnsMaximizeInIsolates` spawn N worker
    isolates that each run an independent LNS with its own RNG seed
    and return the best result via a new `LnsParallelResult`
    (`bestResult` + `perWorker`). Policy and accept are passed as
    builder closures so stateful instances (`adaptive`,
    `lateAcceptance`) get a fresh one per worker. No mid-run
    incumbent sharing — workers race independently; cooperative
    parallel LNS is a follow-up. Cancellation and timeout propagate
    to every worker. 5 new tests in `test/lns/parallel_test.dart`.

  - **Policy API polish.** `LnsPolicy` is now a clean interface —
    users `implements LnsPolicy` with just `select`; the
    `observe` feedback hook moved to a new
    `LnsAdaptivePolicy extends LnsPolicy`. The orchestrator
    type-checks (`policy is LnsAdaptivePolicy`) to dispatch
    `observe`. `LnsPolicy.adaptive` is now a static method (not a
    factory constructor) so its declared return type is the more
    specific `LnsAdaptivePolicy` — callers inspecting `.weights` or
    calling `.observe` don't need a cast. The previously-needed
    `extends LnsPolicy` requirement for custom policies is gone.

  - **Tests.** 42 new tests across `test/lns/policy_test.dart`
    (per-policy unit coverage with seeded determinism + the
    related-destroy's component-respecting expansion + adaptive
    policy weight-shift demonstration + starved-policy floor),
    `test/lns/accept_test.dart` (improving / simulated-annealing
    behaviour at high vs low temperatures + late-acceptance
    history-vs-incumbent matrix), and
    `test/lns/integration_test.dart` (end-to-end LNS on the
    in-test bin-packing problem, lnsMaximize symmetry, seed
    reproducibility, infeasibility / cancellation / iteration-
    budget-zero edge cases). Plus `doc/lns.md` topical guide
    covering the design, the policy + accept catalogue (now
    including the adaptive mechanics section), knobs, when LNS
    won't help, what's not implemented yet, and references.
    `example/lns.dart` walks five usage scenarios end-to-end
    (default random+improving, related-destroy, SA, LAHC,
    adaptive policy bundle). PLAN.md's LNS strategic-gap entry
    flipped from `[ ]` to `[x]`. README adds a
    `## Large Neighborhood Search` section in the optimization
    band.

* **CI fixes + LNS scoping doc + `bool_lin_*`.** Two CI bugs from
  the FlatZinc frontend rollout fixed, plus the recommended-next
  scoping doc and a few more builtins:

  - **CLI test hardcoded an absolute path** that worked locally
    but broke on the GitHub Actions runners. The CLI test now
    starts the subprocess with the relative path
    `bin/dart_csp_fzn.dart` — `dart test` runs from the package
    root in every environment so this Just Works.
  - **`dart format` checked-in violations.** The CI workflow runs
    `dart format --output=none --set-exit-if-changed .` which
    failed because the FlatZinc files passed `dart analyze` but
    not the formatter. Now formatted; the lint step that was
    failing now passes.
  - **`bool_lin_eq` / `bool_lin_le` / `bool_lin_ne` /
    `bool_lin_ge`.** Same shape as `int_lin_*` but with
    bool-typed variables. The engine stores bools as 0/1 ints so
    the integer handler handles both cases verbatim — the
    dispatch entries just point at `_handleIntLin`. Useful for
    cardinality constraints (`bool_lin_eq([1, 1, 1], [p, q, r],
    2)` says exactly two of `{p, q, r}` are true).
  - **`LNS_PLAN.md`** at the repo root scoping Large Neighborhood
    Search, the recommended next strategic gap per HANDOVER §6.
    Mirrors `MINIZINC_PLAN.md` shape: scope (single-thread
    sequential LNS first), architecture sketch
    (`lib/src/lns/{policy,accept,lns}.dart`), five-milestone
    delivery plan (M1 random + improving accept; M2 window +
    related destroys; M3 simulated annealing + combined; M4
    `bench(lns)` + docs; M5 optional parallel LNS via
    `isolate_runner.dart`), destroy-policy catalogue (random /
    window / related / combined), open design questions, and
    references (Shaw 1998, Ropke-Pisinger 2006, Burke et al.
    2017, OR-Tools / Chuffed implementations).

  Test count: 834 → 836.

* **FlatZinc frontend.** Drop-in MiniZinc compatibility — parse and
  solve `.fzn` files produced by `mzn2fzn` (or any other FlatZinc
  emitter). Five-milestone delivery per `MINIZINC_PLAN.md` plus
  three polish rounds. Closes the largest remaining strategic gap
  on the PLAN.md roadmap and unlocks head-to-head benchmarking
  against every other CP solver.

  ### Surface
  - `lib/src/flatzinc/` — tokenizer + recursive-descent parser
    (`parser.dart`), sealed-class AST (`ast.dart`), name-keyed
    constraint-handler dispatch (`lowering.dart`), and the
    standard FlatZinc-output runner (`runner.dart`).
  - `bin/dart_csp_fzn.dart` — CLI binary. Reads from a `.fzn`
    file path or stdin; emits the standard FlatZinc output
    format (`name = value;`, `----------`, `==========`). Flags:
    `-a` for all solutions, `-s` for an `%%%mzn-stat` stats
    block, `-h`/`--help`. Exit codes follow Unix convention:
    0 success, 64 usage error, 65 parse / argument error, 66
    file not found, 78 unsupported FlatZinc builtin. Designed to
    plug straight into the MiniZinc solver-configuration
    pipeline via a `.msc` file.
  - `doc/flatzinc.md` — topical guide (the 11th) covering the
    supported subset, CLI usage, unsupported-builtin error
    policy, and worked examples (n-queens, MAX-SAT, conflict-
    explanation traceback). `README.md` gains a "FlatZinc
    frontend" section pointing at it.
  - `example/flatzinc.dart` — runnable demo (trivial sat,
    4-queens, SEND+MORE=MONEY, heuristic hint via search
    annotation, MUS on an infeasible model).
  - Public API: `FlatZinc.parse(source)`, `FlatZinc.build(source)`,
    `FlatZinc.solve(source, {all: false})`, plus the AST node
    classes (`FlatZincModel`, `VarDecl`, `ArrayVarDecl`,
    `ParamDecl`, `ConstraintItem`, `SolveItem`, `Annotation`),
    the `VarType` / `AstExpr` sealed hierarchies, and the
    `LoweredModel` / `OutputArray` shapes. All classified
    **experimental** in `STABILITY.md`.

  ### Supported FlatZinc subset
  - **Declarations**: scalar `var int` / `var bool` / `var L..U`
    / `var {v1, v2, ...}`; arrays of any of the above; aliased
    forms (`var int: x = y;` posts a deferred equality;
    `array[..] of var T: a = [literal, y, ...];` posts per-slot
    equalities). Parameter declarations `int:` / `bool:` /
    `array[..] of int:` substitute at lowering time.
  - **Solve directives**: `satisfy`, `minimize <var>`,
    `maximize <var>`. `:: int_search(vars, varSel, valSel,
    exploration)` annotations route through the matching
    `Problem.getSolutionWithXxx`: `dom_w_deg` /
    `most_constrained` / `weighted_degree` → dom/wdeg;
    `activity_var` / `activity_var_min` / `vsids` → VSIDS-style
    activity; `impact` → IBS; everything else falls back to MRV.
  - **Output annotations**: `:: output_var` for scalars,
    `:: output_array([1..N, 1..M, ...])` for arrays of any
    dimension — the formatter emits `array1d` / `array2d` /
    `array3d` / … based on the annotated dim count. Bool-typed
    outputs render as `true` / `false` per the FlatZinc spec
    (the engine still uses 0/1 ints; `LoweredModel.boolVars`
    tracks which output names to switch representation on).
  - **Primitives**: `int_eq` / `ne` / `lt` / `le` / `gt` / `ge`,
    `int_lin_eq` / `le` / `ne` / `ge` (with inline-constant
    folding into the bound and a duplicate-variable
    coefficient merge for canonical cryptarithm-style models),
    `bool_eq` / `not` / `or` / `and` / `xor`, `bool_clause`,
    `bool2int`.
  - **Arithmetic**: `int_abs` / `negate` / `plus` / `minus` /
    `times` / `div` / `mod` / `min` / `max` / `pow`.
    `int_plus` / `minus` route through `addLinearEquals` when
    all three operands are variables, for stronger bounds-
    consistency. `int_div` / `int_mod` use truncating semantics
    matching Dart's `~/` / `remainder` (which matches the
    FlatZinc spec) and reject divisor = 0.
  - **Global constraints**: `all_different_int` (+ `all_different`
    alias), `array_int_element` (1-based lookup; the `_bool`
    alias shares the code path), `array_var_int_element` /
    `array_var_bool_element` (variable-index into a variable
    array), `circuit` / `subcircuit` / `inverse` (1-based
    predicates, since the Dart APIs are 0-based), `count_eq`,
    `nvalue`, `global_cardinality(_closed)`, `bin_packing_load`
    (1-based), `lex_less` / `lex_lesseq`,
    `value_precede_chain_int`, `table_int` (reshapes the flat
    tuple array into rows), `disjunctive`, `cumulative`,
    `diffn`, `regular` (translates the 1-based Q/S/T/q0/F
    packaging to the 0-based `Dfa`), `set_in`,
    `array_bool_and` / `array_bool_or`,
    `array_int_minimum` / `array_int_maximum`.
  - **Reified primitives**: `int_*_reif` (dispatch by argument
    shape — constant r collapses to the non-reified case,
    possibly negated; var r with one constant operand routes
    through the specialized `addReifiedXxx` family; var r with
    two variable operands uses `addReifiedEqualsVar` for `==`
    and the generic `addReified` otherwise),
    `int_lin_eq_reif` / `le_reif` / `ne_reif` / `ge_reif`,
    `bool_eq_reif`, `bool_clause_reif`.

  ### Traceability and error policy
  - Every lowered constraint carries a label of the form
    `<fzn_name>#<counter>` (e.g. `int_lin_eq#7`,
    `all_different_int#3`), surfacing on
    `ConstraintRef.label`. MUS / conflict-explanation output
    traces back to the source `.fzn` line.
  - Parse errors are reported as `FormatException` with line,
    column, and a one-line snippet. Unsupported FlatZinc
    builtins throw `UnimplementedError` naming the constraint
    and source line. Statically infeasible constraints (e.g.
    `int_eq(5, 6)`, an out-of-range `array_int_element` index)
    post a vacuous `addClause()` so the model becomes UNSAT
    cleanly rather than silently succeeding.

  ### Benchmark + tests
  - `benchmark/benchmark.dart` gains a `bench(flatzinc)` section
    reporting parse+lower / solve / total medians (same 5-rep
    warm-up + 25-rep median methodology as the other
    median-style benches) on 4-queens, 6-queens, SEND+MORE=MONEY,
    and magic-square 3×3.
  - Test count: 690 → 834 (+144 across 9 new files in
    `test/flatzinc/`).

* **`bench(heuristic)` extended with a harder UNSAT instance.** Added
  pigeonhole CNF 8-in-7 (UNSAT) to the heuristic comparison section,
  one step up from the existing 7-in-6 entry. The gap between MRV
  and the dom/wdeg family widens as problem size grows:

  | Instance | MRV | dom/wdeg | VSIDS | IBS | LC+dom/wdeg |
  |---|---:|---:|---:|---:|---:|
  | pigeonhole CNF 7-in-6 | 89 ms | 48 ms | 49 ms | 52 ms | 44 ms |
  | pigeonhole CNF 8-in-7 | 1 061 ms | 478 ms | 555 ms | 762 ms | 565 ms |

  Confirms the heuristic family scales in the expected direction:
  dom/wdeg-based pickers maintain a ~2× wall-clock advantage over
  MRV on small UNSAT (2.0× at 7-in-6), and the gap widens to ~2.2×
  at 8-in-7 — even though both instances reach a similar number of
  decisions per ms of work. 9-in-8 and larger were tried but excluded
  (MRV took ~14 s per rep, blowing up the bench wall-clock budget).
  No code changes outside `benchmark/`. Test count unchanged at 690.

* **Label support for set-variable and soft-constraint helpers.**
  Closes the gap from the prior labels rollout: every set-variable
  constraint helper and the `addSoftConstraint` helper now accept
  an optional `label:` parameter that propagates to every decomposed
  constraint they post.

  Newly labeled helpers: `addSetCardinality`, `addSetCardinalityRange`
  (label attached to both the lower-bound and upper-bound linears
  when both fire), `addSetCardinalityVar`, `addRequiredInSet`,
  `addExcludedFromSet`, `addSubset` (every per-element binary plus
  the singleton pins for elements only in the sub-universe),
  `addSetEquals` (every per-element equality binary), `addSetDisjoint`
  (every per-element AT-MOST-ONE binary in the universe
  intersection), `addSetUnion` / `addSetIntersection` /
  `addSetDifference` (every per-element ternary), `addSoftConstraint`
  (the reified n-ary the helper generates from the user predicate).

  `addSetVariable`, `addSetVariables`, and `declareSoft` intentionally
  don't accept `label:` — they declare indicator variables or mark a
  bool var as soft rather than posting constraints, so there's
  nothing to label. To label pinned elements, use
  `addRequiredInSet` / `addExcludedFromSet` with a label after
  declaring the set variable.

  8 new tests in `test/labels_test.dart` covering
  addSetCardinality, addSetCardinalityRange, addRequiredInSet +
  addExcludedFromSet, addSetEquals (label propagates to every
  per-element binary), addSubset, addSetDisjoint, addSetUnion, and
  addSoftConstraint label propagation. 690 total tests (was 682).
  Updates `doc/conflict-explanation.md` "Labeling constraints"
  section to document the new helpers and the rationale for not
  labeling `addSetVariable` / `declareSoft`.

* **`bench(explain)` — deletion vs QuickXplain comparison.** New
  "conflict-explanation comparisons" section in
  `benchmark/benchmark.dart` runs both MUS algorithms on seven
  problems spanning the small-k-large-n / k≈n axis:

  | Problem | MUS size k | n | deletion | QuickXplain |
  |---|---:|---:|---:|---:|
  | singleton MUS + 10 redundants | 1 | 11 | 170 µs | 251 µs |
  | singleton MUS + 50 redundants | 1 | 51 | 2 477 µs | 1 510 µs |
  | singleton MUS + 200 redundants | 1 | 201 | 32 233 µs | 7 518 µs |
  | triangle MUS + 10 redundants | 3 | 13 | 621 µs | 172 µs |
  | triangle MUS + 50 redundants | 3 | 53 | 6 102 µs | 399 µs |
  | triangle MUS + 200 redundants | 3 | 203 | 86 934 µs | 1 369 µs |
  | pigeonhole CNF 5-in-4 | 45 | 45 | 10 924 µs | 17 520 µs |

  Confirms the textbook crossover: QuickXplain wins by 4× to 63× on
  small-k-large-n (its O(k · log(n / k)) advantage), and deletion
  wins by 1.6× when k ≈ n (its O(n) is comparable to QX with no
  recursion overhead). On very small n with k = 1 (n = 11) deletion
  is marginally faster — QX's small-instance recursion overhead
  doesn't amortize. New `buildExplainSingletonMus({n})` and
  `buildExplainTriangleMus({n})` problem builders in
  `benchmark/problems.dart` for the scaling sweeps; the pigeonhole
  CNF 5-in-4 case reuses the existing `buildPigeonholeCnf` builder.
  Uses a smaller 3-rep warm-up + 9-rep median than the other
  comparative benches (each MUS run is itself many `CSP.solve`
  calls).

* **Per-`addX`-call labels for conflict explanation.** Every primary
  constraint helper on `Problem` now accepts an optional `label:`
  parameter (a human-readable `String`). The label is stored on the
  underlying `BinaryConstraint` / `NaryConstraint` and surfaced on
  `ConstraintRef.label` by both MUS algorithms, so MUS output reads
  `linearLeq[max-load](w0, w1, w2)` instead of just `linearLeq(w0,
  w1, w2)`. New `label` field on `BinaryConstraint`, `NaryConstraint`,
  and `ConstraintRef`; updated `ConstraintRef.toString` to render
  `kind[label](variables)` when `label` is non-null and `kind(variables)`
  otherwise. Equality on `ConstraintRef` is still keyed by `id`
  alone; the label is for display, not deduplication.

  Helpers updated: `addConstraint` (binary + n-ary), `addAllDifferent`,
  `addAllEqual`, `addExactSum`, `addSumRange`, `addExactProduct`,
  `addInSet`, `addNotInSet`, `addAscending`, `addStrictlyAscending`,
  `addDescending`, `addLexLeq`, `addLexLt`, `addLexChain`,
  `addValuePrecedence`, `addStringConstraint`, `addStringConstraints`,
  every `addReified*`, `addAtLeast`, `addAtMost`, `addExactly`,
  `addImplies`, `addReifiedAnd`, `addReifiedOr`, `addReifiedNot`,
  `addClause`, `addElement`, `addTable`, `addAmong`, `addAmongExactly`,
  `addNvalue`, `addNvalueExactly`, `addGcc`, `addGccRanges`,
  `addRegular`, `addCircuit`, `addSubcircuit`, `addInverse`,
  `addBinPacking`, `addNoOverlap`, `addDiffN`, `addCumulative`,
  `addLinearEquals`, `addLinearLeq`, `addLinearGeq`.

  Decomposed helpers propagate the label to every piece: `addInverse`
  attaches the label to all n² channelling binaries; `addLexChain`
  attaches it to each pairwise lex-leq; `addValuePrecedence` attaches
  it to each consecutive-value n-ary; `addAllEqual` (binary form)
  attaches it to the directed pair. Forward + reverse arcs of a single
  binary `addConstraint` call share one label.

  Backwards-compatible: `label:` defaults to `null` and `ConstraintRef.label`
  is therefore `null` on every constraint posted by existing code.

  16 new tests in `test/labels_test.dart` (default null;
  `toString` with and without label; equality ignoring label; label
  propagation through `addConstraint` binary + n-ary, `addAllDifferent`,
  linear, clauses, lex chain, inverse, all-equal; forward+reverse pair
  sharing one label; both MUS algorithms surfacing the label; mixed
  labeled + unlabeled constraints). 682 total tests (was 666).
  Updated `doc/conflict-explanation.md` with a new "Labeling
  constraints" section and a `label:` column in the granularity table.

* **QuickXplain MUS (Junker 2004).** Shipped as
  `Problem.findMinimalUnsatisfiableSubsetQuickXplain({cancelToken,
  consistency})` — a sibling to the deletion-based
  `findMinimalUnsatisfiableSubset` in the same `ConflictExplanation`
  extension. Same return shape (`Future<List<ConstraintRef>?>`), same
  `ConstraintRef` granularity and id semantics, same `consistency:`
  knob; what changes is the algorithm.

  Algorithm: QuickXplain (Junker 2004 — "QuickXPlain: Preferred
  Explanations and Relaxations for Over-Constrained Problems", AAAI
  2004). Divide-and-conquer: split the candidate set in half, recurse
  on each half against a growing background of constraints already
  known to be in the MUS, short-circuiting whenever the background
  alone is unsat. Identifies the same kind of locally-minimal subset
  as the deletion pass — every constraint in the returned list is
  load-bearing in the sense that removing it makes the residual
  problem satisfiable. Different runs of QuickXplain and the deletion
  pass on the same problem may return *different* locally-minimal
  MUSes; finding the smallest MUS is NP-hard and is not what either
  algorithm aims at.

  Complexity: O(k · log(n / k)) calls to `CSP.solve` where n is the
  number of user-posted constraints and k is the MUS size. For small
  k and large n this is dramatically less than the deletion pass's
  O(n). For k ≈ n the two costs are comparable, and on very small
  models the deletion pass may even be marginally cheaper because it
  has no recursion overhead.

  Cancellation: unlike the deletion pass, the QuickXplain recursion
  does not maintain a "current kept set" that would be sound mid-
  flight. Any cancellation (initial satisfiability check or anywhere
  in the recursion) returns `null`. Callers test
  `cancelToken.isCancelled` to distinguish from a satisfiable
  problem.

  21 new tests in `test/quickxplain_test.dart` (satisfiability:
  trivial sat, empty constraints, redundant-only sat; minimal UNSAT
  detection: singleton binary, allDifferent pigeonhole, triangle
  3-coloring, redundant binary dropped, linear two-equation,
  mixed binary + n-ary, SAT clauses; minimality witness via
  reconstructed Problems; relation to deletion pass: same set on
  unique-MUS problems, valid MUS shape on multi-MUS problems;
  composition with consistency level; no mutation of originating
  Problem; pre-cancelled token; mid-recursion cancellation; binary
  forward+reverse pair as one ref; posting order; 5-cycle 2-coloring
  larger conflict). 666 total tests (was 645). Updated
  `doc/conflict-explanation.md` with the QuickXplain section, the
  "which algorithm to call" guidance, and the cancellation-semantics
  table.

* **Conflict explanation via deletion-based MUS.** Shipped as
  `Problem.findMinimalUnsatisfiableSubset({cancelToken, consistency})`
  in a new `ConflictExplanation` extension. When the model is
  infeasible, returns a `List<ConstraintRef>` identifying a minimal
  subset of the posted constraints whose conjunction is still
  unsatisfiable — removing any one of them makes the residual
  problem satisfiable. Returns `null` when the problem has at least
  one solution.

  Algorithm: classic deletion-based MUS (Bakker et al. 1993, Junker
  2001) — linearly probe each posted constraint, drop it permanently
  if the residual remains unsat, restore it otherwise. O(n) calls to
  `CSP.solve` where n is the number of user-posted constraints (a
  forward/reverse binary pair counts as one). Each solve runs ordinary
  AC-3 search from scratch.

  New public type: `ConstraintRef` (in `lib/src/types.dart`). Opaque
  reference with `id` / `kind` / `variables`. Equality is keyed by
  `id` (ids are only meaningful within the originating `Problem`).
  Kind labels: `binary`, `predicate`, `allDifferent`, `linearEquals`,
  `linearLeq`, `linearGeq`, `regular`, `circuit`, `subcircuit`,
  `gcc`, `cumulative`, `clause`, `diffN`. Forward + reverse
  directions of a single binary `addConstraint` call share one ref.

  Cancellation: if the token fires during the initial satisfiability
  check, returns `null` (callers test the token to distinguish from a
  satisfiable problem); if it fires during the deletion loop, returns
  the current kept set — still unsat but not guaranteed minimal.

  Granularity: constraints surface at the level at which they were
  posted. Helpers that internally decompose into primitives (e.g.
  `addInverse` posts n² binaries, `addLexChain` posts k-1 lex-leqs,
  set variables decompose into indicators) appear as the resulting
  pieces with the dispatch-flag-derived kind label.

  21 new tests in `test/explain_test.dart` (ConstraintRef equality
  /toString/unmodifiable variables; satisfiable returns null;
  satisfiable with empty constraint set; satisfiable with redundant
  constraints; singleton binary MUS; allDifferent pigeonhole;
  triangle 3-coloring with 2 colors; redundant binary correctly
  dropped from MUS; linear two-equation infeasibility; mixed binary
  + n-ary; SAT clauses; rebuild from MUS verifies soundness;
  minimality witness — every dropped constraint produces a
  satisfiable subset; consistency-level invariance; doesn't mutate
  the originating Problem; pre-cancelled token returns null; mid-
  loop cancellation returns sound subset; refs follow posting order
  with `b{i}` / `n{j}` ids; binary forward+reverse pair surfaces as
  one ref). 645 total tests (was 624).

* **`doc/heuristics.md` — consolidated guide for the variable-
  ordering heuristics.** Four-heuristic family (dom/wdeg / VSIDS /
  IBS / LC) plus the MRV baseline now have a single topical guide
  with a "which picker should I use" decision tree, per-heuristic
  algorithmic descriptions, the picker dispatch order, composition
  rules (what stacks with what), a side-by-side bench snapshot
  from `bench(heuristic)`, and the cost-when-off characterization.
  Material that was scattered across four README sections plus the
  bench output is now in one place; the README sections remain as
  short call-outs and the new doc is linked from the Documentation
  index. Ninth topical guide in `doc/`.

* **Last-Conflict heuristic (Lecoutre 2009).** New wrapper-style
  picker shipped as `Problem.getSolutionWithLastConflict({useDomWdeg,
  useVsids, useImpact, consistency, cancelToken,
  enableConflictBackjumping})`, `CSP.solveWithLastConflict`, and a
  `useLastConflict:` flag on `getSolutionWithRestarts`. On every
  propagation failure the engine records the variable being pinned
  (`_lastConflictVar`); the next time `_pickVariable` is called, if
  that variable is still unassigned the picker returns it directly,
  focusing the search on the conflict cause. When the recorded
  variable becomes assigned (via propagation or via the decision
  pin), the picker falls through to the configured underlying
  heuristic.

  LC is a wrapper, not a sibling heuristic: it modifies the
  variable choice without changing the score functions. The flag
  composes orthogonally with all four primary pickers (MRV /
  dom/wdeg / VSIDS / IBS) — pass the relevant `useX:` flag to
  pick the underlying heuristic. Lecoutre's experiments show
  LC+dom/wdeg outperforming pure dom/wdeg on a wide range of
  structured benchmarks; the same composition is the canonical
  deployment shape here too.

  Wired into all six search variants (`_searchOne` / `_searchAll`
  / `_searchOptimal` and their three CBJ analogues) at the
  propagation-failure path — one line per variant. SAC's tentative
  pinning loop is intentionally NOT instrumented (LC is for search,
  not preprocessing). Total cost when off: one field on the engine
  (`String? _lastConflictVar = null`) and one bool branch in
  `_pickVariable` per pick.

  Companion benchmark section: new `--- heuristic comparisons ---`
  block in `benchmark/benchmark.dart` runs MRV / dom/wdeg / VSIDS
  / IBS / LC+dom-wdeg head-to-head on five problems (magic-square
  3x3 no-clue, 12-queens, 16-queens, SEND+MORE linear, pigeonhole
  7-in-6 UNSAT) with the 5-rep-warm-up + 25-rep-median harness
  also used by `bench(diff_n)`. Local result on pigeonhole UNSAT
  (the strongest signal): LC+dom/wdeg ≈ 44 ms, dom/wdeg ≈ 48 ms,
  VSIDS ≈ 48 ms, IBS ≈ 53 ms, MRV ≈ 88 ms — every conflict-driven
  heuristic beats MRV substantially, and LC's edge over dom/wdeg
  is real but small. On feasible-and-small problems (queens,
  magic-square) the heuristics are essentially equivalent — the
  signal is in the UNSAT and large-search-tree cases.

  Coverage: 18 new tests in `test/last_conflict_test.dart`
  (basic feasible, infeasible, 8-queens regression, MRV
  agreement on a unique-answer instance, composition with
  dom/wdeg / VSIDS / IBS / FC / SAC / CBJ / restarts, propagation
  engagement, zero-conflict fallback, LC + IBS together,
  decision-count sanity vs. MRV). 624 tests across 34 files
  (was 606).

* **Impact-Based Search (Refalo 2004).** New backtracking heuristic
  shipped as `Problem.getSolutionWithImpact()`, `CSP.solveWithImpact`,
  and a `useImpact:` flag on `getSolutionWithRestarts`. After every
  decision (whether propagation succeeds or fails) the engine measures
  the **impact** of pinning `(variable, value)`: the fraction of the
  joint search space — product of remaining domain sizes — that
  propagation eliminated. A failed propagation contributes impact
  `1.0` (the entire branch below the pin is gone); a successful one
  contributes `1 - exp(logP_after - logP_before)`, clamped to
  `[0, 1]`. Per-`(var, value)` running means are maintained with a
  standard incremental-mean update (`m' = m + (x - m) / n`); no
  decay or rescaling needed because the impacts themselves are
  already bounded in `[0, 1]`.

  Variable selection minimizes `dom_size / (1 + Σ_a I(v, a))` where
  the sum is over values currently in `v`'s domain. Pre-observation
  this reduces to MRV; as impacts accumulate, the picker gravitates
  toward variables whose values have been historically high-pruning.
  Mirrors the picker shape of `dom/wdeg` and VSIDS — the third
  conflict-driven heuristic in the engine. Picker dispatch order is
  `useImpact > useVsids > useDomWdeg > MRV`; the other heuristics'
  bump tables continue to update so the picker choice is independent
  of which conflicts were observed.

  Wired into all six search variants (`_searchOne` / `_searchAll` /
  `_searchOptimal` and their three CBJ analogues). Each call site
  saves `logP_before` just before pinning the candidate, runs the
  pin + propagate + cascade as before, then calls a single
  `_observeImpact(pick, candidate, logBefore, ok)` helper that
  computes `logP_after` from the live domains and folds the
  observation into the per-pair mean. The whole hookup is two lines
  per search variant.

  IBS is more informative than dom/wdeg or VSIDS on problems with a
  wide spread of per-decision pruning: its score combines both how
  often a decision leads to failure (via the impact-1.0 contribution)
  and how strongly successful decisions prune (via the
  log-product-of-domains ratio). The canonical comparison surface is
  structured combinatorial problems where MRV's tie-breaking is
  arbitrary; on uniform-pruning problems (CNF / pigeonhole) it
  reduces to MRV-with-bumps and behaves much like VSIDS without the
  multiplicative growth.

  Composes unchanged with restarts, FC, SAC preprocessing, and CBJ.
  Coverage: 16 new tests in `test/impact_test.dart` (basic feasible,
  basic infeasible, 6-queens, 8-queens, 7-queens stress for the
  impact-1.0 path, MRV agreement on a unique-answer problem,
  composition with FC / SAC / CBJ / restarts, picker precedence
  vs. VSIDS / dom-wdeg when all three flags are on, decision-count
  positivity, propagation engagement, the canonical SEND+MORE=MONEY
  linear encoding). 606 tests across 33 files (was 590).

* **Forbidden-region sweep propagator for `addDiffN`.** The 2D
  rectangle non-overlap (`diff_n`) global, previously decomposed
  into `n(n-1)/2` 4-ary disjunction predicates, now dispatches to
  a dedicated sweep propagator (Beldiceanu & Carlsson, "Sweep as a
  generic pruning technique applied to the non-overlapping
  rectangles constraint", CP 2001). A single tagged `NaryConstraint`
  scopes all `2n` coordinate variables in the order
  `[xs..., ys...]`; the per-rectangle widths and heights live in a
  new `DiffNSpec`. Per-rectangle/per-dimension pruning aggregates
  forbidden-position intervals induced by every other rectangle
  whose compulsory part in the orthogonal dimension provably forces
  an overlap, then filters the rectangle's current domain in one
  pass. Mandatory-overlap test for `(r, s)` in dimension `d` is
  `max(d_lst[r], d_lst[s]) < min(d_est[r] + len_d(r), d_est[s] +
  len_d(s))` — i.e. the compulsory parts intersect; under that
  condition the forbidden positions of `r` in the orthogonal
  dimension `d'` are `[d'_lst[s] - len_{d'}(r) + 1, d'_est[s] +
  len_{d'}(s) - 1]`.

  Net effect: propagation runs **once** per change to any rectangle
  (instead of `n(n-1)/2` pairwise GAC support searches), and the
  per-call work catches root-level infeasibility and bound-
  tightening on packing problems the decomposition could only
  surface deep in search. The belt-and-braces leaf predicate
  (pairwise pairwise disjunction over the full assignment) is kept
  on the tagged constraint for compatibility with the engine's
  generic paths even though the propagator's leaf check is what
  catches overlap at singleton assignments.

  Zero-area rectangles (`width == 0` or `height == 0`) continue to
  be excluded from the constraint — they trivially do not overlap.
  Non-`int` coordinate domains defer pruning to the leaf predicate
  (the propagator returns an empty change set in that case).

  Coverage: 7 new tests in `test/diffn_test.dart` (propagator
  engagement, root-level x-pruning under compulsory-y overlap,
  root-level over-packing infeasibility detection, agreement with
  an explicit pairwise decomposition, `addNoOverlap` equivalence
  on the 1D y-pinned reduction, composition with
  `addAllDifferent`, mid-size 3×(2×2) packing) on top of the 18
  existing tests. 590 tests across 32 files (was 583).

* **`ConsistencyLevel.singletonArcConsistency` — SAC preprocessing.**
  New enum variant on `ConsistencyLevel` (Debruyne & Bessière 1997 —
  algorithm SAC-1). The engine still runs AC-3 / GAC during search
  but adds a preprocessing pass at the top: for every
  `(variable, value)` pair currently in some domain, it tentatively
  pins the variable, runs `_propagate`, rolls the trail back, and
  prunes the value if propagation failed. The whole pass repeats
  until no value is pruned in an iteration; on success, search
  proceeds with the SAC-tight root domains. Strictly stronger than
  AC at the root — catches infeasibility AC alone misses (e.g.
  `x == y ∧ y == z ∧ x != z` over `{1, 2, 3}`) and can collapse a
  domain to a singleton without descending search (e.g. `x == y ∧
  x + y == 4` over `{1, 2, 3}` forces `x = y = 2` at preprocessing).

  Implementation hooks into the engine via a new `_seedAndPreprocess`
  helper that the three search entry points (`findOne`, `findAll`,
  `findOptimal`) now route through; SAC is opt-in via the
  `consistency:` parameter (which is already on every public
  backtracking entry point), so all the existing composition surface
  — `useDomWdeg`, `useVsids`, `enableConflictBackjumping`, restarts,
  optimization, streaming — works unchanged. Conflict-driven
  heuristics observe SAC failures via the standard `_onConflict(c)`
  helper, so the bumps inform later search.

  Each tentative pin is rolled back through the standard trail
  mechanism so domains outside the SAC prunings are unchanged on
  return. Counted toward `stats.propagations` /
  `stats.binaryRevises` / `stats.naryRevises` via the trailing
  `_propagate` calls; no separate SAC counters were added.

  Coverage: 18 new tests in `test/sac_test.dart` covering dispatch
  defaults, the SAC-only infeasibility example, AC-equivalent
  solution enumeration, the chain-CSP decision-count reduction, root
  singleton collapsing, composition with dom/wdeg, restarts,
  minimize, maximize, CBJ, multi-round fixpoint iteration, no-prune
  preservation, the `CSP.solve` static, single-variable
  infeasibility, and 8-queens as a regression. 583 tests across
  32 files (was 565).

* **`addSubcircuit` — subcircuit constraint with optional skips.** New
  `Problem.addSubcircuit(vars)` in the `GlobalConstraints` extension.
  Variant of `addCircuit` that permits the self-loop `vars[i] = i` as
  a "skip" marker: position `i` is then not part of the cycle, while
  the non-self-loop edges among the remaining positions still have to
  form a single cycle (possibly empty when every position self-loops).
  Standard CP primitive for vehicle routing with optional stops, "visit
  some subset of nodes in one tour", and any sequencing problem where
  the visited set itself is part of the decision.

  Shares the cycle-detection propagator with `addCircuit` via a new
  `subcircuit: bool` dispatch flag on `NaryConstraint`. In subcircuit
  mode the propagator additionally tracks two global counters — the
  number of positions currently committed to skip (singleton `{i}`)
  and the number committed to be in the cycle (`i` removed from the
  domain) — and uses them to (a) remove the head value from a chain's
  tail when any outside position is forced into the cycle, (b) force
  the tail to close on the head when the chain plus the
  committed-skipped positions already cover every position, and (c)
  after a pure non-Hamiltonian cycle is detected, force every
  non-cycle position to self-loop (or fail if any can't).
  Successor uniqueness extends to skip slots, so the value `i` taken
  by a self-loop `vars[i] = i` is removed from every other variable's
  domain. The leaf-check in the propagator catches the remaining
  infeasibility cases (double predecessors, multiple disjoint cycles)
  that the tagged-constraint path bypasses in `_reviseNary`.

  Posting `addAllDifferent(vars)` alongside is redundant: the
  permutation property is enforced inherently by the propagator
  (each value, including the self-loop slots, is used at most once).

  Coverage: 19 new tests in `test/circuit_and_bin_packing_test.dart`
  covering small enumeration counts (n=1, n=2, n=3, n=4 against the
  closed-form Σ C(n,k)·(k-1)! formula), the empty-subcircuit and
  single-skip cases, sub-cycle infeasibility when remaining nodes
  can't self-loop, sub-cycle feasibility when they can, chain-head
  pruning when an outside node is forced into the cycle, chain-head
  forcing when every outside node is committed-skipped, intermediate
  node pruning from the tail domain (permutation guard), agreement
  with `addCircuit` on domains that exclude every self-loop value,
  composition with `addAllDifferent`, propagator engagement
  (`naryRevises > 0`), minimize / maximize over a visited-count
  aggregator, successor uniqueness on pinned values, and validation
  (`throwsArgumentError` on empty / unknown vars). 565 tests across
  31 files (was 546).

* **VSIDS-style variable activity heuristic.** New
  `Problem.getSolutionWithActivity()` entry point and matching
  `CSP.solveWithActivity(csp, ...)` static; a `useVsids: true` flag
  on `getSolutionWithRestarts` lets it compose with the Luby
  restart loop. Per-variable activity score lazily populated inside
  `_BacktrackEngine`; on every propagation conflict, every variable
  in the failing constraint's scope is bumped by a growing
  `_activityInc` (multiplicatively grown by `1 / decay` per conflict
  — the standard MiniSat trick; equivalent to uniformly decaying
  every existing activity by `decay` but O(1) per conflict instead
  of O(|vars|)). When `_activityInc` exceeds `1e100` the engine
  rescales every activity (and the increment itself) down by `1e-100`
  to prevent overflow.
  
  The variable picker minimizes `dom(v) / (1 + activity(v))`,
  mirroring dom/wdeg's `dom(v) / wdeg(v)` shape — pre-conflict the
  ratio reduces to MRV; as activity accumulates the picker
  gravitates toward variables that have been near recent failures.
  Useful complement to dom/wdeg on SAT-style instances and on
  problems where the "guilty" structure shifts over the course of
  search (VSIDS's decaying bumps react faster than dom/wdeg's
  monotone weights).
  
  Composes with `consistency:`, `cancelToken:`, and
  `enableConflictBackjumping:`. When both `useVsids` and
  `useDomWdeg` are set, VSIDS wins the picker; both bump tables
  are still updated independently.
  
  The wdeg / VSIDS bump-on-conflict sites in `_BacktrackEngine`
  were refactored into a single internal `_onConflict(c)` helper
  that delegates to whichever flag is on; the 16 per-call-site
  `if (useDomWdeg) _bumpWeight(...)` guards in `_propagate`
  collapsed into one call apiece. Bit-identical behavior under
  every existing test.
  
  Coverage: 12 new tests in `test/vsids_test.dart` — basic feasibility,
  unsat, 6-queens regression, 8-queens stats engagement, agreement
  with MRV on a unique-solution problem, composition with FC,
  CBJ, and restarts (including the "both flags on" case), and the
  static `CSP.solveWithActivity` entry point. 546 tests across 31
  files (was 534).

* **`addDiffN` — 2D rectangle non-overlap.** New
  `Problem.addDiffN(xs, ys, widths, heights)` in the
  `GlobalConstraints` extension. Generalises `addNoOverlap` from a
  unary (1D time) resource to two dimensions: given `n` axis-
  aligned rectangles described by `(xs[i], ys[i])` corners
  (registered variables) and constant `(widths[i], heights[i])`
  sizes, enforces that no two rectangles overlap. Standard CP
  primitive (`diff_n` in MiniZinc, `addNoOverlap2D` in OR-Tools)
  for rectangle packing, floor planning, VLSI placement, 2D
  scheduling, and tile-placement puzzles.

  Half-open box semantics: a rectangle at `(x, y)` with size
  `(w, h)` occupies `[x, x+w) × [y, y+h)`, so two rectangles that
  touch exactly at an edge do not overlap. Zero-area rectangles
  (`width == 0` or `height == 0`) are dropped from the constraint
  — they never conflict with anything.

  Decomposes into `n(n-1)/2` 4-ary disjunction predicates, one per
  unordered pair of rectangles, scoping only
  `(xs[i], ys[i], xs[j], ys[j])` so the engine's generic n-ary GAC
  support search stays cheap per call. For very large instances a
  sweep-based (Beldiceanu & Carlsson) propagator would be a
  worthwhile follow-up; the predicate version is the right
  starting point.

  Validation: throws `ArgumentError` on length mismatch among the
  four lists, on unknown variable names, or on negative widths /
  heights.

  Coverage: 18 new tests in `test/diffn_test.dart` — validation
  (5), single-rectangle edge case, semantics (2 unit rects on a
  grid, 2×2 corners, infeasible same-corner, zero-area cases,
  edge-touching half-open semantics), and integration (1D
  reduction equivalent to `addNoOverlap`, 2×2 tiling enumerating
  4! = 24 distinct placements, mixed-size 2×1 + 1×2 + 1×1 packing
  in 3×2, 2×2 square pair in a 4×2 strip with overlap-free
  verification, one-axis-separable case). 534 tests across 30
  files (was 516).

* **Doc polish: `addClause` docstring** updated to reflect the
  shipped two-watched-literal propagator and the matching
  per-variable seeding filter (was still calling the watched-
  literal optimization "a perf follow-up" from two sessions ago).

* **`addLexChain` helper for n-way row-symmetry breaking.** New
  `Problem.addLexChain(rows, {strict: false})` in the
  `BuiltinConstraints` extension. Sugar over pairwise `addLexLeq`
  (or `addLexLt` when `strict: true`) across every consecutive pair
  in [rows]. Standard idiom for breaking row-permutation symmetry
  in matrix models where every row is interchangeable: posting one
  `lexLeq` per consecutive pair keeps a single canonical row-order
  representative from each permutation orbit. Lex-leq is
  transitive on `Comparable`, so chaining consecutive pairs is
  equivalent to (and cheaper than) posting all `k(k-1)/2` pairwise
  constraints.

  Validation: throws `ArgumentError` on fewer than 2 rows or any
  row-length mismatch (unknown-variable validation reuses
  `addLexLeq` / `addLexLt`'s checks).

  Coverage: 6 new tests in `test/symmetry_breaking_test.dart`
  (validation, 3-row non-decreasing brute-force equivalence,
  strict variant forbidding equal rows, 4-row collapse to
  `C(rowVals + k - 1, k)` multiset count). 516 tests across 29
  files (was 510).

* **Channelling constraint: `addInverse`.** New
  `Problem.addInverse(forward, inverse)` in the `GlobalConstraints`
  extension. Posts the standard inverse-channelling constraint:
  for every `i, j ∈ 0..n-1` where `n = forward.length`,
  `forward[i] = j ⇔ inverse[j] = i`. Standard primitive in CP
  modelling (present in MiniZinc, OR-Tools, Choco) for assignment
  problems and scheduling where the same relation is naturally
  expressed in both directions; some constraints are cleaner on
  the forward map, others on the inverse, and the channelling
  keeps both views consistent.

  Decomposes into `n²` binary constraints so AC-3 can propagate
  effectively; pinning a value on either side immediately prunes
  the corresponding cells on the other. Implies that both lists
  are (partial) permutations of `0..n-1`, so a separate
  `addAllDifferent` is redundant once `addInverse` is posted.

  Validation: throws `ArgumentError` on mismatched lengths, empty
  lists, or unknown variable names.

  Coverage: 11 new tests in `test/global_constraints_test.dart` —
  validation, n=2 enumeration, n=3 enumeration with explicit
  channelling and bijection assertions, redundant-allDifferent
  equivalence, pinning-propagation in both directions, infeasible
  contradiction, and a practical 4×4 task-machine assignment with
  forbidden cells (brute-force-equivalent enumeration). 510 tests
  across 29 files (was 499).

* **Value-symmetry breaking helper: `addValuePrecedence`.** New
  `Problem.addValuePrecedence(variables, values)` and matching
  `valuePrecedence(variables, earlier, later)` factory in
  `lib/src/builtin_constraints.dart`. Standard primitive for
  breaking the symmetry under which interchangeable value labels
  (colors, agents, machine IDs, bin labels) can be permuted without
  changing the solution structure. Companion to the existing
  `addLexLeq` / `addLexLt` sequence-symmetry primitive.

  For each consecutive pair `(values[i], values[i+1])` in [values],
  posts an n-ary precedence predicate that enforces the first
  occurrence of `values[i]` in `variables` strictly precedes the
  first occurrence of `values[i+1]` (or that the latter is unused).
  Posting the full canonical chain breaks up to `k!` value-
  permutation symmetry where `k = values.length`. Values outside
  the canonical list are unconstrained.

  Validation: throws `ArgumentError` on fewer than 2 canonical
  values, on duplicate values, or on unknown variable names. The
  predicate handles partial assignments conservatively (returns
  true unless a violation is definitively visible).

  Coverage: 13 new tests in `test/symmetry_breaking_test.dart`
  covering factory unit tests (partial / decisive / non-violating
  cases, integer values), validation, and integration (K3 triangle
  coloring 6 → 1, 5-node path 3-color 6× shrink, partial value
  usage with brute-force agreement, unconstrained-outside-list
  semantics, composition with `addAllDifferent` collapsing
  4! → 1). 499 tests across 29 files (was 486).

* **Per-variable seeding filter for the clause propagator.** Once a
  clause's two-watched-literal state is initialized, the engine's
  propagation queue no longer wakes the propagator on reductions to
  variables that aren't currently watched. The watched-literal
  invariant is monotone under the engine's trail semantics (a swap
  done deeper in the search remains valid on backtrack), so a
  reduction to a non-watched variable cannot falsify either watcher
  and therefore cannot change the propagator's behavior — skipping
  the wake-up is sound and saves the per-task allocation, queue
  add/remove, and propagator instantiation.

  Width-2 clauses (the typical "at most one" pairwise encoding) skip
  the filter unconditionally: with two literals, both are watched,
  so the check would never fire and adding it is pure overhead. The
  filter applies to clauses with three or more literals — exactly
  the workloads where the textbook scheme pays off.

  Pure perf change; user-visible pruning is identical. Empirical
  win on pigeonhole CNF benchmarks (25-rep median):
  - 7-pigeon / 6-hole UNSAT: plain 136 → 112 ms (-18%), CBJ 44 → 37 ms (-16%).
  - 8-pigeon / 7-hole UNSAT: plain 1715 → 1367 ms (-20%), CBJ 347 → 292 ms (-16%).
  Non-clause benchmarks unchanged (the seedFor branch is a single
  `c.clauseSpec != null` field load + null check). New
  `pigeonhole CNF 7-in-6 (UNSAT)` benchmark added to
  `benchmark/benchmark.dart` (plus the matching builder in
  `benchmark/problems.dart` and a CBJ-correctness test in
  `test/cbj_benchmarks_test.dart`).

  Coverage: 2 new `test/clause_test.dart` cases for the filter —
  a wide-clause case where many non-watched variables are pinned
  (asserts the enumeration matches the brute-force count) and a
  watcher-swap-then-non-watched-change case (asserts the optimizer
  correctly re-targets wake-ups to the new watched variable after
  a swap). 486 tests across 29 files (was 483).

* **CBJ conflict-cause: per-revision provenance + chain following.**
  Replaces the original constraint-graph-neighborhood approximation
  with a tight per-revision attribution. Every trail entry now
  carries the constraint that caused the mutation
  (`_TrailEntry.cause` — a `BinaryConstraint` for AC-3 revises, a
  `NaryConstraint` for any GAC revise or specialized propagator
  reduction, `null` for decision-site assignments). The CBJ
  conflict-cause walk inspects each entry's cause directly:
  contributors for a binary revise are just the head; for an n-ary
  revise, the constraint's other variables. When a contributor is
  the current pick or a within-frame intermediate, the walk follows
  its most-recent reducing trail entry — preserving the chain of
  justifications across propagation hops.

  Same correctness guarantee as before (CBJ enumerates the same
  solution set as plain backtracking). Tighter jumps:
  `backjumpLevelsSkipped` is now non-zero on benchmark scenarios
  where the topology supports it — 16-queens with CBJ now shows
  `bj:34/1` (was `34/0` under the constraint-graph approximation),
  and uses one fewer backtrack overall (88 vs 89). The
  pigeonhole-via-pairwise test still triggers backjumps; a new
  `test/cbj_test.dart` case asserts the level-skip path on
  16-queens.

  Implementation: new file-private `_TrailEntry` class
  (`{varName, oldRep, cause}`) replaces the `MapEntry<String,
  _DomainRep>` trail; `_setDomain` and `_setDomainRep` gained an
  optional `cause:` parameter that every propagator call site now
  passes. `_conflictCauseFromTrail` rewritten as a chain walk over
  the trail with deduplication via `processed` index set.
  Decision-site assignments leave `cause: null` so they don't
  extend the justification chain (the chain extends through
  propagation entries only).

  Documentation: `doc/cbj.md`'s "The conflict-cause approximation"
  section rewritten to describe the chain-following algorithm;
  the "What's not implemented" entry on per-revision provenance
  updated to "minimal-cause conflict analysis" (an even tighter
  but more expensive next step). New total: 483 tests across 29
  files (was 482).

* **CBJ benchmark comparison + per-benchmark correctness tests.**
  `benchmark/benchmark.dart` now prints two rows per benchmark
  (plain BT and CBJ-enabled) with wall-clock, the existing stats
  counters, and the new `backjumps` / `backjumpLevelsSkipped`
  values, so users deciding whether to flip `enableConflictBackjumping:`
  on a given problem have side-by-side data. Empirical finding on
  the existing 9-benchmark suite: CBJ rarely changes the search
  tree size (AC-3 + the dedicated globals already catch failures
  at the cause-variable assignment) and the `backjumpLevelsSkipped`
  column is `0` across the board on these problems — confirming
  the `doc/cbj.md` guidance that CBJ pays off mostly on
  hand-crafted instances with sparse constraint graphs.

  Extracted the build functions from `benchmark/benchmark.dart` to
  a new `benchmark/problems.dart` so the new
  `test/cbj_benchmarks_test.dart` (14 tests) can validate CBJ on
  the exact same problem definitions the benchmark times. The
  tests cover all 9 benchmark scenarios (each with a domain-aware
  validator: magic-square sums, sudoku rows/cols/boxes, n-queens
  diagonals, map-coloring adjacency, SEND+MORE arithmetic), the
  CBJ-vs-plain solution equivalence on unique-solution problems
  (sudoku and both SEND+MORE forms), and enumeration-count parity
  on 8-queens (92) and the Australia map. New total: 482 tests
  across 29 files (was 468 across 28).

* **Conflict-directed backjumping (CBJ, Prosser 1993).** Opt-in via
  a new `enableConflictBackjumping: bool = false` parameter on every
  backtracking entry point: `Problem.getSolution`, `Problem.getSolutions`,
  `Problem.minimize`, `Problem.maximize`, `Problem.getSolutionWithRestarts`,
  `Problem.getSolutionWithDomWdeg`, and their static `CSP.solve*` twins.
  Default `false` preserves the existing chronological-backtracking
  surface. When enabled, the engine maintains a conflict set per
  decision and, on candidate exhaustion, jumps directly to the deepest
  previously-assigned variable in that set rather than returning to
  the immediate caller. Sound and complete; only the choice of
  backtrack target differs.

  The conflict cause uses a coarse trail-walk approximation (every
  earlier-assigned variable sharing a constraint with any variable
  touched by the failed propagation) — sound but not minimally tight;
  the only effect of over-approximation is a shorter jump, never an
  incorrect one. Composes with forward checking, restarts, dom/wdeg,
  and the integrated branch-and-bound.

  Two new `SolverStats` fields expose engagement: `backjumps` (count
  of conflict-driven returns up the search stack, one per "all
  candidates exhausted with non-empty conflict" event) and
  `backjumpLevelsSkipped` (cumulative decision levels skipped past
  chronological backtrack). Both are `0` when CBJ is off and for
  local search. Sealed `_SearchResult` types for the single-solution
  CBJ helper; engine-state-bag (`_pendingBackjumpDepth` /
  `_pendingBackjumpConflict`) for the streaming and optimization
  variants since async generators and `Future<void>` can't return a
  value directly.

  Documentation: new topical guide at
  [`doc/cbj.md`](doc/cbj.md) (algorithm, conflict-cause
  approximation, stats interpretation, composition, what's not yet
  implemented including per-revision conflict provenance and
  CDCL-style nogood learning); new "Conflict-Directed Backjumping
  (CBJ)" section in the README. Closes the tier-3 "conflict-directed
  backjumping / nogood learning" entry in PLAN.md as the first cut.
  Real CDCL with first-UIP nogood learning remains a future
  follow-up.

  Coverage: 13 tests in `test/cbj_test.dart` (wiring on every entry
  point, enumeration equivalence with plain BT on N-queens and map
  coloring, equivalence under optimization, composition with FC /
  restarts / dom-wdeg, edge cases including unsat / trivial-sat /
  no-constraints / single-value-domain, and a pigeonhole-via-pairwise
  instance that asserts `backjumps > 0`). Existing 455 tests
  unchanged; new total 468.

* **Doc fix:** the `CancellationToken` class doc said solvers check
  the token "every ~1000 decisions on backtracking paths and every
  ~1000 iterations on the min-conflicts path." The actual constants
  are 100 (`_yieldEveryDecisions`) and 200 (`_yieldEveryIterations`);
  every other docstring in the codebase already used the correct
  numbers. Fixed the outlier docstring.

* **New topical guide: [`doc/cancellation.md`](doc/cancellation.md).**
  Consolidates the previously-scattered story for cooperative
  cancellation (`CancellationToken`, the unconditional event-loop
  yield, the `'FAILURE'`-vs-`isCancelled` distinction), wrapping
  `Future.timeout(...)` on an in-process solve, and the worker-isolate
  runner's built-in `timeout:` vs an external `.timeout()`. Updates
  the README's Documentation index, links from `doc/algorithms.md`,
  and refreshes the algorithms guide's now-stale "isolate runner is on
  the roadmap" tail paragraph. Docs-only — no code or test changes.

* **Worker-isolate runner: `solveInIsolate`, `solveAllInIsolate`,
  `minimizeInIsolate`, `maximizeInIsolate`.** New top-level
  functions in `lib/src/isolate_runner.dart`, exported from
  `dart_csp.dart`. Each takes a `Problem Function()` builder that
  runs inside the spawned worker isolate (predicate closures on a
  constructed `Problem` are generally not sendable; a top-level
  builder is), runs the solve there, and bridges the result back
  over a `SendPort`. Closes the deferred worker-isolate half of
  the tier-3 isolate-parallelism item, flipping PLAN.md 3.1 from
  `[~]` to `[x]`.

  Cancellation: each entry point accepts the existing
  `cancelToken: CancellationToken`. Cancelling the parent token
  signals the worker via the message port; the worker's local
  `CancellationToken` is set and the solver aborts at the next
  checkpoint. To make this work without polling, the
  `CancellationToken` API gained `addListener(void Function())`
  (additive; the type was already experimental per STABILITY.md);
  the existing `cancel()` invokes listeners synchronously after
  flipping `isCancelled`, swallowing any listener exception.

  Timeouts: each entry point accepts an optional `timeout:
  Duration`. When the deadline fires the runner sends the worker
  a cancel signal, waits a 250 ms grace window for the worker to
  flush its result over the port, then hard-kills the isolate via
  `Isolate.kill()`. Prefer the built-in `timeout:` over wrapping
  `solveInIsolate(...).timeout(...)` — the wrapping form returns
  to the caller on time but leaves the worker isolate running
  until natural completion.

  Stats round-trip: the worker captures its own `CSP.lastStats`
  after the solve, ships it back over the port, and the runner
  writes it into the main isolate's `CSP.lastStats` slot before
  resolving the returned future / closing the returned stream.
  This preserves the documented "stats populated when the future
  resolves" contract. Stats are not copied on the pre-cancelled
  short-circuit path or when the hard-kill grace fires (the
  worker had no chance to flush).

  Errors: a builder that throws — or any exception inside the
  solve itself — is rewrapped as an `IsolateRunnerException`
  carrying the original message and stringified stack trace.
  The original exception object isn't reachable across the
  boundary in general.

  Coverage: 11 new tests in `test/isolate_runner_test.dart`
  (440 → 444 from the demo smoke tests in this batch's earlier
  commit, then 444 → 455 with this runner). The test file is
  marked `@TestOn('vm')` because `dart:isolate` isn't available
  on Dart Web. README has a new "Solving on a worker isolate"
  section; STABILITY.md adds a worker-isolate-runner entry under
  experimental.

* **`addNoOverlap` now dispatches to `addCumulative`.** Replaces the
  prior `O(n²)` pairwise-disjunction encoding with a single tagged
  cumulative constraint (unit demand, unit capacity), which is the
  exact no-overlap reduction. The cumulative time-table propagator
  (shipped in an earlier release) gives strictly stronger pruning
  while the constraint semantics are unchanged. `SolverStats`
  counters shift from `binaryRevises` to `naryRevises` since the
  pairwise binary constraints are gone — assertions on specific
  counter values for `addNoOverlap` workloads will need to be
  updated. Coverage: 1 new equivalence test in
  `test/interval_variables_test.dart` (439 → 440) confirming
  `addNoOverlap` and `addCumulative(capacity=1, demand=1)` enumerate
  identical solution sets on a non-trivial instance. All 6 prior
  no-overlap tests pass unchanged. Closes the
  `addNoOverlap`→`addCumulative` follow-up flagged in
  `HANDOVER.md` §6. STABILITY.md updates the `addNoOverlap` entry
  to reflect the dispatch.

* **Two-watched-literal data structure for the clause propagator
  (Moskewicz, Madigan, Zhao, Zhang & Malik, "Chaff", DAC 2001).**
  The internal `_ClausePropagator` now keeps two watcher pointers
  per clause and lazily updates them across calls, instead of
  scanning every literal on every call. Per-call work drops from
  O(literals) to O(1) amortized once watchers are initialized.
  The watcher state lives in a new per-engine side-table
  `_BacktrackEngine._clauseWatchers` keyed by `ClauseSpec`
  identity — the first piece of per-constraint mutable state the
  engine supports, and reusable for future stateful propagators.
  
  No trail-aware rollback is needed despite the per-constraint
  mutable state: domain reductions in the engine are monotone
  under the trail (backtrack only restores previously-removed
  values), so a watcher that points at a non-falsified literal
  at a deeper assignment is still non-falsified at any shallower
  one. The textbook concern about "watcher state must be undone
  on backtrack" doesn't apply here — watchers are always valid
  hints as the engine unwinds.
  
  User-visible pruning is identical to the prior single-pass
  scan; this is a pure perf change. Coverage: 4 new tests in
  `test/clause_test.dart` (16 → 20) covering rollback-after-deep-
  swap soundness, a 4-pigeon-3-hole CNF infeasibility instance,
  a 10-clause 3-SAT enumeration asserted equal to brute-force,
  and watcher-state freshness across repeated solves on the
  same `Problem`. All 16 prior clause tests pass unchanged.
  Benchmark suite shows no regression on non-clause problems
  (SEND+MORE predicate: 2238 ms → 2245 ms, within noise).
  
  Flips the tier-2 "variable types beyond enumerated int/string"
  entry from `[~]` to `[x]` in PLAN.md — the SAT-style booleans
  third of that item is now complete.

* **Cooperative cancellation + `CancellationToken`.** New
  `CancellationToken` type in `types.dart` (one method `cancel()`,
  one getter `isCancelled`) and a new `cancelToken:` optional
  parameter on every backtracking and local-search entry point —
  `CSP.solve`, `CSP.solveAll`, `CSP.solveWithDomWdeg`,
  `CSP.solveWithRestarts`, `CSP.solveOptimal`,
  `CSP.solveWithMinConflicts`, and the matching `Problem` methods
  (`getSolution`, `getSolutions`, `getSolutionWithDomWdeg`,
  `getSolutionWithRestarts`, `minimize`, `maximize`,
  `solveWithMinConflicts`, `maximizeSatisfaction`).
  A cancelled token aborts the search at the next checkpoint and the
  entry point returns the standard `'FAILURE'` literal; callers
  distinguish cancel from infeasibility by inspecting
  `token.isCancelled` after the call.
  
  The engine also unconditionally yields to the event loop on every
  `_yieldEveryDecisions = 100` decisions (and the min-conflicts
  runner on every `_yieldEveryIterations = 200` iterations).
  This cooperative yield is what lets a wrapping
  `Future.timeout(...)` actually fire on an otherwise CPU-bound
  solve, closing the documented `.timeout()` gotcha — no
  `CancellationToken` is required for `.timeout` to work, just for
  programmatic cancel. Fast path is one integer compare per
  decision; benchmark suite shows no measurable regression
  (SEND+MORE predicate encoding: 2238 ms before, 2242 ms after; all
  other benchmarks within noise).
  
  Coverage: 13 new tests in `test/cancellation_test.dart` (422 →
  435) covering the token API itself, pre-cancel short-circuit on
  every backtracking entry point + min-conflicts, mid-search Timer
  cancel for `getSolution` / `getSolutions` / `maximize` /
  `solveWithMinConflicts` / `getSolutionWithRestarts` /
  `getSolutionWithDomWdeg`, and `Future.timeout` integration on a
  CPU-bound infeasible problem. README has a new "Cancellation and
  Timeouts" section. STABILITY.md lists `CancellationToken` and the
  `cancelToken:` parameters as experimental and updates the
  `.timeout()` known-gotcha entry.
  
  Closes the user-visible half of the tier-3 isolate-parallelism
  item in PLAN.md; the worker-isolate runner half (closure
  serialization + stats round-trip) remains deferred.

* **SAT-style clause constraint with unit-propagation propagator.**
  New `Problem.addClause(positive: [...], negative: [...])` helper
  in the `LogicalConstraints` extension and a `ClauseSpec` tag on
  `NaryConstraint`. The disjunction of literals — `positive`
  variables that should be `1` OR `negative` variables that should
  be `0` — must hold. Tagged constraints dispatch to a new
  `_ClausePropagator` in `solver.dart` that does stateless single-
  pass unit propagation: if any literal is satisfied (only the
  satisfying value remains in the variable's domain), the clause
  is entailed; if every literal is falsified, the clause is a
  conflict; if exactly one literal is undetermined and none are
  satisfied, that literal's variable is forced to its satisfying
  value.

  Use for CNF-style modeling — combine with `ReifiedConstraints`
  to express arbitrary CNF over data variables (reify each
  sub-constraint to a boolean, then express the formula as a
  conjunction of `addClause` calls). The classical two-watched-
  literal optimization (maintain two watchers per clause and
  update lazily) is a perf follow-up: it would amortize the
  per-call scan to O(1) but requires per-constraint mutable
  state across propagation calls, a pattern the engine doesn't
  yet support. The user-visible pruning behavior is the same,
  so the optimization is a pure perf change.

  Validation: every listed variable must already be registered
  and have domain ⊆ `{0, 1}`. Variables can appear in both
  `positive` and `negative` (which makes the clause vacuously
  satisfied). An entirely empty clause (no literals at all) is
  the empty disjunction, registered as a always-false constraint;
  if no variables exist at all to attach it to, the helper
  throws `ArgumentError` rather than registering a no-op.

  Coverage: 16 new tests in `test/clause_test.dart` (406 → 422)
  covering validation, single-literal forcing, two-literal
  disjunction enumeration, mixed-polarity assignments,
  unit-propagation at root, all-false conflict detection,
  satisfied entailment, vacuous tautology, XOR via CNF, CNF over
  data variables via reified equalities, and a CNF-encoded
  3-coloring of K3 (6 solutions). All 406 prior tests pass
  unchanged. README has a new "SAT-style clauses" subsection
  under Logical Combinators. STABILITY.md lists `addClause` /
  `ClauseSpec` as experimental.

  Addresses the SAT-style-booleans third of the tier-2 "variable
  types beyond enumerated int/string" item by shipping the user-
  visible payload (clauses + unit propagation). The textbook
  watched-literal data structure itself — maintaining two watchers
  per clause across propagation calls — is the remaining perf
  follow-up, so the item stays `[~]` in PLAN.md.

* **Cumulative resource constraint with time-table propagator.** New
  `Problem.addCumulative(starts, durations, demands, capacity)`
  helper in the `GlobalConstraints` extension and a `CumulativeSpec`
  tag on `NaryConstraint`. Generalizes `addNoOverlap` from a unary
  resource (one task at a time) to an integer-capacity renewable
  resource: at every time `t`, the sum of `demands[i]` across tasks
  whose half-open interval `[starts[i], starts[i] + durations[i])`
  covers `t` must not exceed `capacity`. Use for RCPSP-style models
  (one `addCumulative` per resource type), machine slots with
  multiple identical units, parallel-worker scheduling, etc.

  Internal: new `_CumulativePropagator` in `solver.dart`
  implementing a time-table propagator (Beldiceanu & Carlsson 2002
  style). For each task, computes the compulsory part
  `[lst_i, est_i + dur_i)` — the interval the task must occupy in
  every feasible schedule — sums the compulsory parts into a sparse
  usage profile (`Map<int, int>` from time to demand-sum), reports
  immediate infeasibility on any compulsory-pile-up that exceeds
  capacity, and prunes every start candidate that would push the
  profile above capacity at some time once that task's own
  compulsory contribution at that time is removed (so the task is
  not double-counted). Dispatched from `_propagate` / `seedFor`
  alongside the existing specialized propagators; one canonical
  task per constraint is enqueued regardless of which start
  triggered it. Soundness rides on the standard pruning path — when
  every start is singleton each task's compulsory part is exactly
  its scheduled interval, the profile equals the realized usage,
  and any over-capacity time-step forces the lone feasible
  candidate out of some task's domain so the engine reports
  infeasibility from the resulting empty domain. No separate leaf
  check is required.

  Coverage: 17 new tests in `test/cumulative_test.dart` (389 → 406)
  covering validation errors, vacuous (zero-task) shapes,
  single-task feasibility and demand > capacity rejection, two- and
  three-task multi-task scenarios with shared capacity, an
  equivalence test against `addNoOverlap` on the unary reduction,
  multi-resource RCPSP composition, makespan minimization (3 tasks
  on cap 2, optimum makespan 4), propagator-activity stat
  assertion, and compulsory-pile-up root-infeasibility detection.
  All 389 prior tests pass unchanged. README has a new "Cumulative
  resource scheduling" subsection under the scheduling header.
  STABILITY.md lists `addCumulative` / `CumulativeSpec` as
  experimental.

  Closes the `cumulative` follow-up in the tier-2 "global constraint
  library expansion" item — the entry can now flip from `[~]` to
  `[x]`.

* **Set variables.** New `SetVariables` extension on `Problem` adds
  set-valued variables ranging over the subsets of a finite
  universe declared at construction time. Internally each universe
  element becomes a 0/1 indicator variable; the helpers decompose
  to existing primitives (linear arithmetic for cardinality,
  pairwise binary / ternary n-ary for relations) so no new
  propagator was required. Every solve entry point on `Problem`
  post-processes the raw result to expose each set variable as a
  `Set<dynamic>` of included elements and strip the indicator
  variables from the returned map.

  New API:
  - `Problem.addSetVariable(name, {universe, required, excluded})`
    and `addSetVariables(names, {universe, required, excluded})`.
  - `addSetCardinality(setName, k)`,
    `addSetCardinalityRange(setName, min, max)`,
    `addSetCardinalityVar(setName, countVar)`.
  - `addRequiredInSet(setName, element)`,
    `addExcludedFromSet(setName, element)`.
  - `addSubset(sub, super)`, `addSetEquals(a, b)`,
    `addSetDisjoint(a, b)`.
  - `addSetUnion(a, b, result)`, `addSetIntersection(a, b, result)`,
    `addSetDifference(a, b, result)`.
  - `memberIndicator(setName, element)` — escape hatch returning
    the internal 0/1 indicator name so the user can compose set
    membership with reified / logical / linear / arithmetic helpers
    for relations the dedicated set helpers don't express.
  - `setVariableNames` and `setUniverse(name)` introspection.

  Pairwise binary helpers (`addSubset`, `addSetDisjoint`) accept
  set variables with different universes — elements only in one are
  handled per operation (subset forces sub-only elements out;
  disjoint contributes no constraint). `addSetEquals` requires the
  universes to match as sets. The ternary helpers (`addSetUnion`,
  `addSetIntersection`, `addSetDifference`) require all three set
  variables to share the same universe; the general case is reachable
  via `memberIndicator`.

  `Problem.copy()` propagates the set-variable registry, so
  `SoftConstraints.maximizeSatisfaction` (which copies the problem
  internally) materializes set variables correctly through its
  branch-and-bound. The min-conflicts, restarts, dom/wdeg, and
  integrated branch-and-bound entry points are all wrapped through
  the same materialization helper.

  Coverage: 40 new tests in `test/set_variables_test.dart`
  (349 → 389) covering declaration validation (empty / duplicate /
  pin conflicts), free-universe enumeration (2^|U|), pin
  enforcement, cardinality (exact / range / variable), subset with
  symmetric and asymmetric universes, set equality / disjoint /
  union / intersection / difference, `memberIndicator` composition
  with reified equality, materialization through every solve entry
  point (`getSolution*`, `getSolutions`, `solveWithMinConflicts`,
  `minimize`, `maximize`, `maximizeSatisfaction`), an integration
  problem (team selection with required captain + disjoint bench),
  and an equivalence test asserting the same solution count as a
  hand-built indicator decomposition. All 349 prior tests pass
  unchanged. README has a new "Set Variables" section and
  `doc/set-variables.md` is the topical guide. `STABILITY.md` lists
  the new surface as experimental.

  Closes the set-variable third of the tier-2 "variable types beyond
  enumerated int/string" item. SAT-style watched-literal boolean
  variables remain as a follow-up.

* **Interval-variable domain representation + scheduling primitives.**
  New `_IntervalRep` internal domain representation — a third
  `_DomainRep` impl alongside `_BitsetRep` and `_ListRep`. Stores
  just `(min, max)` and supports `O(1)` membership / length /
  bounds. `filter(predicate)` walks the range once, returns a
  narrower `_IntervalRep` when the kept set is still contiguous,
  and promotes to `_BitsetRep` (if the new span fits) or `_ListRep`
  when the predicate creates interior holes.

  Dispatch (`_classifyDomain`): strictly-ascending `int` with span
  `≤ 1024` continues to use the bitset rep; contiguous-ascending
  `int` with span `> 1024` now uses the interval rep instead of the
  previous list-rep fallback; everything else (mixed types,
  non-contiguous int with span `> 1024`, non-monotonic) still falls
  back to list. `_setDomain(List<dynamic>)` detects contiguous
  ascending kept lists for interval-backed variables and preserves
  the `_IntervalRep` form on trail/rollback, promoting to bitset or
  list only when the kept list has internal gaps.

  New user-facing helpers:
  - `Problem.addRangeVariable(name, int min, int max)` — adds a
    variable whose domain is `[min, max]` (inclusive both ends).
    For ranges `> 1024` this is the natural way to model scheduling
    horizons without paying the `List<dynamic>` allocation cost on
    every propagation step.
  - `Problem.addNoOverlap(starts, durations)` (extension
    `GlobalConstraints`) — unary-resource scheduling. For every
    pair `(i, j)`, posts `starts[i] + durations[i] <= starts[j]` OR
    `starts[j] + durations[j] <= starts[i]`. Durations are
    constants; variable durations can be modeled separately via
    the linear propagator. Current implementation is `O(n²)`
    pairwise binary disjunctions; stronger globals (edge-finding,
    time-table for `cumulative`) remain follow-ups.

  Coverage: 15 new tests in `test/interval_variables_test.dart`
  (334 → 349) covering rep eligibility, filter promotion through
  the linear / regular / GAC paths, search singleton-commit on
  interval-rep variables, validation errors, two-task non-overlap
  enumeration (12 schedules with `addRangeVariable('a', 0, 4)` +
  `addRangeVariable('b', 0, 5)` + durations `[3, 2]`), and a
  three-task makespan-minimization (durations `[4, 3, 2]`, optimum
  makespan = 9). All 334 prior tests pass unchanged. README has a
  new "Range-Domain Variables (Scheduling)" section.

  Closes the interval-variable third of the tier-2 "variable types
  beyond enumerated int/string" item. Set variables and SAT-style
  watched-literal boolean variables remain as separate follow-ups;
  both are independent of the interval rep and can ship next.

* **Rep-aware filter for specialized propagators.** Closes the
  follow-up flagged in the bitset domain representation entry. New
  `_setDomainRep(varName, _DomainRep)` on `_BacktrackEngine`
  alongside the existing list-based `_setDomain`, plus an updated
  `applyUpdate(String, _DomainRep)` callback type on every
  specialized propagator (`_AllDifferentPropagator`,
  `_LinearPropagator`, `_RegularPropagator`, `_CircuitPropagator`,
  `_GccPropagator`).

  Each propagator's reduction loop now builds its kept set via
  `oldDom.filter(predicate)` instead of a fresh `List<dynamic>`,
  so a bitset-backed variable's reduction stays in `_BitsetRep`
  form end-to-end — the engine no longer re-bits a kept list back
  into a fresh `Uint64List` on every prune. Per-variable invariant
  state (matched value index, SCC id, matched copy in GCC) is
  hoisted out of the filter to avoid recomputing it for each
  candidate. The engine's list-based `_setDomain` remains in place
  for the internal singleton-commit / binary-revise / generic-GAC
  paths (which do not have a `_DomainRep` source).

  No public API changes; all five propagators retain their leaf
  detection and soundness contracts unchanged. The integrated
  branch-and-bound's `_tightenObjectiveDomain` already operated
  rep-natively (`.filter` on the live domain and every relevant
  trail snapshot), so it gains nothing here but stays consistent.

  Coverage: 3 new tests in `test/bitset_domain_test.dart` (13 → 16)
  exercising heavy-pruning workloads on bitset-eligible domains
  through Régin allDifferent (6-queens, 4 solutions),
  network-flow GCC (six-worker exact-count rostering, 90 distinct
  assignments), and the cycle-detection circuit propagator (5-position
  Hamiltonian enumeration, 24 cycles). Existing 331 tests pass
  unchanged. Total suite: 331 → 334.

  Perf note: the existing benchmark workload (queens, sudoku, magic
  square, SEND+MORE predicate, SEND+MORE linear) is dominated by
  generic n-ary support-finding (`_findSupport` over the Cartesian
  product of the free neighborhood) on the predicate forms, and by
  the LCV scorer on small puzzles — neither of which the rep-aware
  filter touches. Run-to-run timing variance (±200ms on the 1.5s
  SEND+MORE predicate case) is larger than any visible delta. The
  win is structural: one `List<dynamic>` and one full-rebuild
  `Uint64List` allocation removed per propagator reduction on
  bitset-backed variables, which matters most on propagator-heavy
  workloads (Régin allDifferent under heavy pruning, large GCCs,
  GAC-tight regular constraints).

* **Network-flow propagator for `addGcc` / `addGccRanges`** (Régin
  1996). New `GccSpec` value type and `gccSpec` field on
  `NaryConstraint`. The propagator generalizes the Régin
  allDifferent dispatch already in the codebase to handle
  multiplicity: each value `v` with upper bound `u` is replicated
  into `u` "copies" in the bipartite matching, Hopcroft-Karp finds
  a max matching, Kosaraju SCCs + free-copy reachability identify
  every variable→value edge that does not lie on some max matching,
  and those edges are pruned. Spec values that have been pruned
  from every variable's domain are still indexed so a `lower > 0`
  requirement on an unavailable value reports infeasibility at the
  root.

  Upper-bound constraints (the case where every spec entry has
  `min == 0`) receive full GAC. Lower-bound constraints receive
  conservative GAC: when the current matching distribution doesn't
  certify the lower bounds and the constraint isn't at a leaf, the
  propagator returns no changes rather than risking a false-positive
  infeasibility verdict; at a leaf the matching is unique and any
  bounds violation is reported as real infeasibility. The leaf check
  is what closes the soundness gap that would otherwise let
  predicate-bypassed constraint violations slip through.

  Both `addGcc(vars, counts)` (exact-count form: each `min == max
  == count`) and `addGccRanges(vars, ranges)` (`(min, max)` per
  value) now construct `NaryConstraint` directly with `gccSpec` set.
  The existing predicate still runs at leaves of constraints not
  reached by the propagator path. Closes the last documented
  deferred propagator follow-up for the global constraint library.

  Coverage: 5 new tests in `test/global_cardinality_test.dart` (31
  → 36) covering insufficient-capacity rejection at construction,
  root-infeasibility detection when a required value is gone from
  every domain (0 decisions), all-different equivalence with the
  Régin allDifferent solution set, upper-bound-only enumeration
  with measurable propagator activity, and a 60-solution
  exact-count rostering case. All 326 prior tests pass unchanged.
  Total suite: 326 → 331. README updated.

* **Cycle-detection propagator for `addCircuit`.** New `circuit`
  flag on `NaryConstraint` dispatches to a dedicated propagator that
  - builds the singleton-edge graph (variables with singleton
    domains define fixed successor edges);
  - rejects two predecessors for the same node and self-loops for
    `n > 1`;
  - walks the singleton graph: chains are kept as partial paths,
    pure cycles must visit all `n` nodes or the constraint is
    infeasible;
  - prunes every chain node from the chain's tail's domain when
    chain length `< n` (any such value would close a premature
    sub-cycle), or forces tail = head when chain length `= n`;
  - enforces successor uniqueness: any value with a known
    predecessor is removed from every other variable's domain.

  Same dispatch pattern as Régin allDifferent, bounds-consistency
  linear, and partial-state regular. Public API is unchanged; the
  existing soundness predicate still runs at leaves. Closes the
  last documented deferred propagator follow-up for the global
  constraint library.

  Also adds `_DomainRep.contains` (O(1) for `_BitsetRep` when the
  query is `int`, O(n) for `_ListRep`) since the cycle propagator
  needs efficient membership.

  Coverage: 6 new tests in `test/circuit_and_bin_packing_test.dart`
  (14 → 20) asserting sub-cycle rejection at the root (0 decisions),
  self-loop rejection, chain-tail pruning to force the only valid
  next position, successor uniqueness without `addAllDifferent`,
  measurable propagator activity, and composition with
  `addAllDifferent`. All 320 prior tests pass unchanged. Total
  suite: 320 → 326. README updated to describe the new propagator.

* **Bitset domain representation (closes Tier 1).** Internal
  `_DomainRep` abstraction with two implementations:
  - `_BitsetRep` — `Uint64List` + integer offset; O(1) membership,
    O(N/64) filter.
  - `_ListRep` — wraps `List<dynamic>` for mixed types,
    non-monotonic input, large spans, etc.

  Eligibility (decided per-variable at engine construction):
  strictly-ascending list of `int` with span `max - min + 1` ≤ 1024.
  These constraints make bitset iteration order match the user's
  input order so observable solver behavior is unchanged. All 22
  `_domains[...]` access sites in `_BacktrackEngine` plus all three
  specialized propagators (`_AllDifferentPropagator`,
  `_LinearPropagator`, `_RegularPropagator`) were updated to read
  through the new rep API. The `applyUpdate` callback signature is
  unchanged — propagators continue to hand back kept `List<dynamic>`s
  and `_setDomain` re-wraps as the appropriate rep for the variable.

  Coverage: 13 new tests in `test/bitset_domain_test.dart` covering
  eligibility branches (contiguous, sparse, negative-offset, span at
  the boundary, large allDifferent), ineligibility fallback (mixed
  types, non-monotonic, large span, doubles), and propagator
  round-trip across the trail. All 307 prior tests pass unchanged.
  Total suite: 307 → 320.

  Perf note: existing benchmarks (queens, sudoku, magic square) show
  no consistent runtime delta. The hot path is predicate calls and
  per-call work inside the specialized propagators, not raw domain
  operations. The bitset infrastructure is in place; future work
  exposing rep-aware filter operations directly to propagators (so
  they avoid the `_setDomain(List<dynamic>)` round-trip on each
  reduction) is now a pure perf change.

* **Partial-state propagator for `addRegular` (Pesant 2004).** New
  `regularDfa` field on `NaryConstraint`, dispatched the same way as
  Régin's allDifferent and the bounds-consistency linear propagator.
  `_RegularPropagator` computes per-position forward + backward
  reachable DFA-state sets from the current per-variable domains,
  then prunes any value whose transition lies on no accepting path.
  Achieves GAC on the regular constraint — infeasibility is detected
  at the root for many problems where the predicate-only encoding
  would have to exhaust the search tree.

  The public API is unchanged; `addRegular(vars, dfa)` now tags the
  constraint with the new field instead of falling through to the
  generic n-ary predicate path. Soundness still rides on the
  predicate at leaves, so the propagator is correctness-preserving
  by construction.

  Coverage: 4 new tests in `test/regular_constraint_test.dart` (16
  → 20) asserting root-infeasibility detection, singleton-forcing on
  a strict-alternation DFA (0 decisions for the unique solution),
  full enumeration on an at-most-one-occurrence DFA (9 solutions),
  and accepting-state-aware rejection. Existing 16 regular tests
  pass unchanged (the propagator only adds pruning; the constraint
  semantics are identical). README's "DFA-checked Sequences" section
  notes the partial-state pruning. Total suite: 303 → 307.

* **`SolverStats` populated for every solver.** The streaming and
  Min-Conflicts paths now populate `Problem.lastStats` /
  `CSP.lastStats`. `CSP.solveAll` wraps the engine's stream in a
  try/finally that flushes the engine's counters into `lastStats`
  when the stream completes or is cancelled. A new
  `SolverStats.iterations` field (default `0`) is set by
  `CSP.solveWithMinConflicts` to the local-search step count;
  backtracking solvers leave it at `0` and continue to use the
  existing `decisions` / `backtracks` / `propagations` /
  `binaryRevises` / `naryRevises` counters. `SolverStats.toString`
  includes the new field. Coverage: 7 new tests in
  `test/stats_test.dart` (6 → 13). Total suite: 296 → 303.

  Doc note added to `Problem.lastStats` flagging the known gotcha
  that `lastStats` is a single static slot on `CSP` and is
  overwritten by any solve on any `Problem` instance — capture it
  immediately after the call that produced it if you need to
  compare runs.

* **`STABILITY.md` — public-API stability statement.** Documents
  what's stable, what's experimental, and the semver policy that
  governs each tier. Lists the known behavioral gotchas (the
  static-slot `lastStats`, stream-stats-flush-on-completion, GAC
  bail-out work bound, no mid-solve `.timeout()`). Referenced from
  README's "Documentation" section.

* **Bounds-consistency linear arithmetic propagator.** New
  `LinearSpec` value type in `types.dart` capturing
  `Σ coeffs[i]·vars[i] ∘ bound` with `op ∈ {eq, leq, geq}`, and a
  new `linearSpec` field on `NaryConstraint`. New `LinearConstraints`
  extension on `Problem` exposing `addLinearEquals(vars, coeffs,
  bound)`, `addLinearLeq(...)`, and `addLinearGeq(...)`. Coefficients
  may be positive, negative, or zero; domains must be numeric (this
  is validated at registration time).

  The engine dispatches linear constraints to a dedicated
  `_LinearPropagator` (mirroring the Régin allDifferent pattern):
  computes the interval of the weighted partial sum from current
  per-variable domain mins/maxes, derives per-variable bounds, and
  filters each domain to values consistent with the constraint.
  Bounds consistency rather than full GAC — much stronger than
  predicate-only encoding on arithmetic constraints with many
  variables; closes the documented SEND+MORE follow-up. The
  cryptarithmetic benchmark expressed with a single linear equation
  drops from 1834 ms (predicate-only) to 1 ms (~1800× speedup).

  Coverage: 21 new tests in `test/linear_propagator_test.dart`.
  Total suite: 275 → 296. README has a new "Linear Arithmetic
  Constraints" section; `benchmark/benchmark.dart` now runs both
  the predicate-only and linear forms of SEND+MORE side-by-side.

* **Pluggable consistency level.** New `ConsistencyLevel` enum in
  `types.dart` exposing `arcConsistency` (the default; existing AC-3 +
  GAC behavior) and `forwardChecking`. FC revises each constraint
  touching the just-assigned variable exactly once and skips the
  cascade unless a revise reduces a variable to a singleton, in which
  case it cascades that newly-assigned variable's constraints once
  (textbook FC semantics — preserves soundness when propagation
  implicitly assigns a variable).

  Threaded through every backtracking entry point as an optional
  `consistency:` parameter: `CSP.solve`, `CSP.solveAll`,
  `CSP.solveWithDomWdeg`, `CSP.solveWithRestarts`, `CSP.solveOptimal`
  and the matching `Problem` methods (`getSolution`, `getSolutions`,
  `getSolutionWithDomWdeg`, `getSolutionWithRestarts`, `minimize`,
  `maximize`). Default behavior unchanged.

  Coverage: 13 new tests in `test/consistency_level_test.dart`
  asserting correctness across binary, n-ary, optimization, restarts
  and dom/wdeg paths, equivalence of FC and AC solution sets on a
  small enumeration, and a metric assertion that FC does strictly
  fewer binary revises than AC on a chain over a wide domain. Total
  suite: 262 → 275.

* **DFA-checked sequences: `addRegular` + `Dfa` type.** Closes the
  last named global constraint from the deferred list (other than
  `cumulative`, which is gated on interval-variable support). The
  new `Dfa` value type in `types.dart` captures a deterministic
  finite automaton (`numStates`, `start`, `accepting`, `transitions`)
  with `dynamic` symbol type to match arbitrary CSP variable values.
  `addRegular(vars, dfa)` enforces that the sequence
  `(vars[0], ..., vars[n-1])` is accepted by the DFA when read
  left-to-right.

  Use for any sequencing rule expressible as a finite automaton:
  run-length bounds ("no more than 2 night shifts in a row"),
  alternation requirements, exact-pattern matching, parity
  predicates. Complements the cardinality helpers — those count;
  `regular` adds positional structure.

  Coverage: 16 new tests in `test/regular_constraint_test.dart`
  covering Dfa step semantics, pattern acceptance, counting via
  state machine (equivalence check against `addAmongExactly`),
  run-length bounds, numeric-symbol parity, validation errors, and
  composition with other constraints. Total suite: 246 → 262.

* **Sequencing & packing global constraints: `addCircuit`,
  `addBinPacking`.** Two more classical globals join the
  `GlobalConstraints` extension:
  * `addCircuit(vars)` — `vars[i]` is the successor of position `i`;
    the n successors must form a single Hamiltonian cycle through
    every position. The predicate walks the successor function from
    position 0 and rejects sub-cycles or missed positions. Combine
    with `addAllDifferent` for stronger early pruning.
  * `addBinPacking(items, sizes, binLoads)` — for each bin `b`,
    `binLoads[b]` equals the sum of `sizes[i]` over items assigned
    to bin `b`. Bin capacities are expressed by constraining the
    load variables separately (`load0 <= 10`, ranges, `minimize`
    over `maxLoad`, etc.).

  Coverage: 14 new tests in `test/circuit_and_bin_packing_test.dart`
  including a tour-counting regression (n=4 → (n-1)! = 6 cycles), a
  sub-cycle rejection, an out-of-range bin id case, a size-0 edge
  case, and a balanced-packing minimization. Total suite: 232 → 246.

* **Integrated branch-and-bound for `minimize` / `maximize`.**
  `Problem._optimize` no longer restarts the search after each
  improvement. The new `_BacktrackEngine.findOptimal` walks the tree
  once, recording each strictly-improving leaf as the incumbent and
  permanently pruning the objective's domain (plus every existing
  trail snapshot) to values that still improve. An `_optProven`
  short-circuit fires when no improving value is reachable anywhere
  in the remaining tree.

  Behavior change: `Problem.lastStats` is now populated by `minimize`
  / `maximize` (the restart-tightening version overwrote it on every
  restart, leaving only the last attempt's stats observable). The
  non-numeric-objective check now fires synchronously at the start of
  `_optimize` rather than at the first leaf — same `ArgumentError`,
  surfaces earlier.

  Coverage: 10 new tests in `test/optimization_test.dart` covering
  stats population, bound-pruning interaction with `allDifferent`,
  the proven-optimum short-circuit, and the don't-mutate-original
  invariant after the engine's in-place tightening.

* **Counting global constraints: `among`, `nvalue`, `gcc`.** The
  `GlobalConstraints` extension on `Problem` gains six new helpers
  (count-variable and fixed-`k` forms of each):
  * `addAmong(vars, values, countVar)` / `addAmongExactly(vars, values, k)`
  * `addNvalue(vars, countVar)` / `addNvalueExactly(vars, k)`
  * `addGcc(vars, counts)` / `addGccRanges(vars, ranges)`

  Together they cover the three classical counting patterns from the
  CSP literature: category counts, distinct-value counts, and per-value
  cardinality (exact or ranged). `gcc` generalizes `allDifferent`;
  `nvalue` enables chromatic-number-style minimization (combine with
  `minimize`). Each helper validates eagerly at construction.

  Coverage: 31 new tests in `test/global_cardinality_test.dart`,
  including unknown-variable / out-of-range / infeasible-cardinality
  errors plus a multi-constraint rostering regression. Topical guide
  in `doc/global-cardinality.md`.

  All current implementations are generic n-ary GAC encodings — correct
  on any input but bounded by the engine's GAC work limit on very large
  `vars` lists. A network-flow-based GCC propagator (Régin 1996) for
  stronger pruning is tracked as a follow-up in `PLAN.md`.

## 2.1.0

* **Clean-room rewrite of the solver core.** `lib/src/solver.dart` was
  rewritten from textbook references (Russell & Norvig AIMA Ch. 6;
  Mackworth 1977 AC-3; Minton et al. 1992 Min-Conflicts) to remove
  derivative provenance from an upstream JavaScript project (see
  `NOTICE`). No public API changes; all existing tests pass unchanged.
* **~6× faster end-to-end.** Full test suite: 6.5s → 1.1s. Heaviest
  example (3x3 magic square in `example/example.dart`): 11.4s → 1.1s.
  Most of the win comes from replacing the AC-3/GAC list-based queue
  with a real `Queue<T>` plus identity-deduplicated pending work.
* **Min-Conflicts local search solver.** New
  `Problem.solveWithMinConflicts({maxSteps: 1000})` for very large or
  loosely-constrained problems where any feasible answer suffices.
  Implementation of Minton et al. (1992). Incomplete by design — see
  `doc/min-conflicts.md` for when to choose it over the default
  backtracking solver.
* **Topical documentation in `doc/`.** Four new guides:
  * `doc/algorithms.md` — Backtracking, AC-3, GAC, MRV, LCV, and the
    async caveat (solver is CPU-bound; `.timeout()` won't fire
    mid-search).
  * `doc/string-constraints.md` — Full parser grammar and dispatch
    table from string patterns to built-in factories.
  * `doc/multi-solutions.md` — Decision tree for the streaming /
    counting / bounded-enumeration APIs.
  * `doc/min-conflicts.md` — When to use the local search solver,
    sizing `maxSteps`, restart strategies.
* **Expanded test coverage.** 86 tests across four files, including a
  new `test/builtin_and_parser_test.dart` (42 tests) for the built-in
  constraint factories and the expression evaluator.
* **Fixed the `example/example.dart` magic-square hang.** Pinning
  `B2=5` (the only legal center for a 3x3 magic square) cuts the
  problem by ~20× without changing the API used.
* **CI hardening.** Non-stable Dart channels (`beta`, `dev`) are
  `continue-on-error` so upstream SDK breakage doesn't block PRs;
  least-privilege permissions on the test job.
* **Project moved.** This is a fresh repository
  (`CrispStrobe/dart_csp`) continuing the now-archived
  `CrispStrobe/dartCSP`. See `NOTICE` for licensing history.

## 2.0.0

* Initial stable release of the `dart_csp` library.
* Features backtracking solver with AC-3/GAC and MRV/LCV heuristics.
* Includes a powerful string-based constraint parser.
* Added ability to find all solutions and the first N solutions.

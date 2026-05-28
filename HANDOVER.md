# Handover — continuing work on `CrispStrobe/dart_csp`

You are picking up work on `CrispStrobe/dart_csp`, a pure-Dart
Constraint Satisfaction Problem solver. Post-clean-room-rewrite
(see `NOTICE`), MIT-licensed, 2.1.0+. Every Tier 1/2/3 item from
the original PLAN.md has shipped; the remaining work lives in
the **Strategic gaps**, **Tactical wins**, and **Edge/workload-
gated** sections of `PLAN.md`.

The most recent landings (in order, newest first):

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

**Test count:** 972 passing. **Files:** 6 `lib/src/*.dart` (plus
`lib/src/lns/`, `lib/src/lcg/`, and `lib/src/flatzinc/`); 57
`test/*_test.dart` files (incl. `test/lcg/`); 13 `doc/*.md` guides
(incl. `doc/lcg.md`); 7 `example/*.dart` files;
`benchmark/benchmark.dart` runs nine sections (CBJ, AC-vs-SAC,
diff_n, heuristics, conflict-explanation, LNS, cooperative-LNS,
LCG, FlatZinc). Three planning docs at repo root: `LNS_PLAN.md`,
`MINIZINC_PLAN.md`, `LCG_PLAN.md` (LCG M1 + M2a + M2b shipped;
M3 — per-propagator `explain` companions — is the next strategic
pick).

---

## Recommended next pick

LCG **M1 + M2a + M2b + lazy-atom-encoding + M3a + M3b all shipped,
and the M3-tighten kickoff (instrumentation + measured diagnosis +
design validation) landed.** Engine wiring + clause-propagator +
allDifferent + linear explanation companions are in place. **The
next strategic pick is the M3-tighten engine surgery — an
`AtomInScc` intermediate atom for `_AllDifferentPropagator` so the
first-UIP analyser converges on dense CSP conflicts.** This is a real
multi-session refactor; the kickoff below de-risked it and corrected
the priority (allDifferent, not linear — see below).

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

1. **`PLAN.md`** — the roadmap. The forward-looking sections are
   **Strategic gaps** (LCG, float variables; LNS, FlatZinc, and
   conflict-explanation flipped to `[x]`), **Tactical wins**
   (cooperative-LNS and search-annotation routing just flipped to
   `[x]`; edge-finding for cumulative still open), and
   **Edge / workload-gated** (SAC-2, k-dim diff_n, etc.). The
   "What shipped" retrospective at the bottom covers the entire
   Tier 1/2/3 history. If you're picking up LCG, read
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
- `PLAN.md` — flip `[ ]` → `[x]` and describe what shipped.
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
├── PLAN.md
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

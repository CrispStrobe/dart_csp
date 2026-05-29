# PLAN — Roadmap for `dart_csp`

This is a forward-looking roadmap. The original three-tier plan
(fundamental capability / competitive feature set / engineering
polish) has effectively shipped — the surviving items are listed
at the bottom as a compressed retrospective. The interesting
parts of this file are now the **Strategic gaps**, **Tactical
wins**, and **Edge / workload-gated** sections, which describe
what would meaningfully change what `dart_csp` is or who it
competes with.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done.

---

## Where we are

`dart_csp` is a pure-Dart CSP solver with a strong propagator
inventory (Régin allDifferent, network-flow GCC, partial-state
regular, cycle-detection circuit + subcircuit, time-table
cumulative, two-watched-literal clauses, bounds-consistency
linear, forbidden-region sweep diff_n — eight specialized
propagators total), three domain representations (list, bitset,
interval), CBJ-capable search, dom/wdeg and VSIDS variable
heuristics, Luby restarts, soft constraints, set variables,
SAC-1 preprocessing, integrated branch-and-bound, and a
worker-isolate runner.

Where it stands relative to SOTA:

* **What it can do well**: integer CSPs with moderate constraint
  density, classic globals well-represented, predictable
  benchmarks (n-queens, sudoku, magic-square, map-coloring,
  rostering, RCPSP, rectangle packing, CNF/SAT). The propagator
  inventory is competitive with mid-tier academic solvers on
  these workloads.
* **Where it falls short**: hard combinatorial instances where
  conflict-driven learning (LCG / CDCL-style) is the difference
  between minutes and hours; problems with continuous quantities
  (no float / real variables); ecosystem completeness (the
  FlatZinc frontend is shipped, but XCSP3 is not, and the
  FlatZinc CLI still trails the SOTA on `cumulative` /
  `disjunctive` propagator strength).

The Strategic gaps below address those shortcomings. The
Tactical wins are smaller, well-motivated items that close
narrower gaps each in roughly one session.

---

## Strategic gaps — high-impact, multi-session

These are the items that change what kind of solver `dart_csp`
*is*. Each one is large enough to be a deliberate project, not
an opportunistic pick.

- [ ] **Lazy Clause Generation (LCG) / nogood learning.** The
  single biggest gap. Modern CP-SAT (Google OR-Tools) is
  essentially CP + LCG; Chuffed is CP + LCG; Gecode without
  learning lags both. On hard structured instances the search-
  tree size difference between non-learning and learning solvers
  is regularly orders of magnitude — i.e. minutes vs hours, or
  solvable vs intractable. The first-UIP nogood-learning loop
  on top of the existing `_ClausePropagator` machinery is the
  natural shape: every conflict generates a learned clause
  (resolved back through the explanation graph), the clause is
  added to a learned-clause pool, and the propagation queue is
  driven by it for the remainder of the search. Forgetting,
  clause activity heuristics, restart policies, and explanations
  inside specialized propagators (allDifferent, GCC, regular,
  cumulative) are all in scope; each propagator needs an
  `explain` companion to produce the conflict clause for any
  prune it makes. Multi-session, easily 4-6 sessions of focused
  work; pick deliberately.

  **M1 (atom encoding + implication trail + runner shell),
  M2a (first-UIP analyser), and M2b (engine wiring + forget) all
  shipped.** `Problem.solveWithLcg` now performs real conflict-
  driven nogood learning: every analysable conflict is fed to
  `firstUipAnalyse`, the learned clause is posted dynamically into
  the constraint store, and (after re-propagating it) search
  backtracks chronologically. On pigeonhole-CNF UNSAT proofs the
  decision count drops by an order of magnitude (~10× on 7-in-6,
  ~30× on 8-in-7). (M2b originally backjumped non-chronologically;
  that proved incomplete in the recursive search and was replaced by
  chronological-backtracking-with-learning — sound + complete under
  any picker. See [`LCG_PLAN.md`](LCG_PLAN.md) §M4.) Strategic-gap box
  stays `[ ]` until M3 lands the per-propagator `explain`
  companions — without them, only CNF-shaped problems exercise
  the learning loop. See [`LCG_PLAN.md`](LCG_PLAN.md) for the M3+
  roadmap.

- [x] **FlatZinc frontend.** Done — `lib/src/flatzinc/` plus the
  `bin/dart_csp_fzn` CLI binary. Five-milestone delivery
  ([`MINIZINC_PLAN.md`](MINIZINC_PLAN.md)) landed in order: M1
  declarations + solve, M2 parameters + int/bool primitives,
  M3 global constraints (including circuit/subcircuit/inverse/
  array_int_element rewritten as 1-based predicates,
  cumulative/disjunctive/diffn, regular with 1-based ↔ 0-based
  DFA translation, table_int reshape, gcc, bin_packing_load,
  lex, value_precede_chain, nvalue, count_eq), M4 reified
  primitives + linear reifications, M5 CLI accepting a `.fzn`
  path or stdin and emitting the standard FlatZinc output
  format (`name = value;`, `----------`, `==========`).
  Search-annotation mapping (`int_search` / `bool_search` /
  `seq_search`) was wired up in a follow-up — see the Tactical
  wins entry. XCSP3 remains separately out of scope (XML-based,
  distinct frontend).

- [x] **Large Neighborhood Search (LNS).** Done — `lib/src/lns/`
  plus the `LargeNeighborhoodSearch` extension on `Problem`
  (`lnsMinimize` / `lnsMaximize`). Sequential single-thread
  v1: orchestration loop in `lib/src/lns/lns.dart` (a `part of`
  problem.dart), policy + accept catalogues in
  `lib/src/lns/policy.dart` and `lib/src/lns/accept.dart`. Four
  shipped destroy policies — `LnsPolicy.random` (Shaw 1998's
  textbook starting point), `LnsPolicy.window` (contiguous-by-
  declaration-order), `LnsPolicy.related` (BFS expansion through
  the constraint-variable graph, Shaw 1998), and
  `LnsPolicy.combined` (weighted-random pick from sub-policies).
  Two acceptances — `LnsAccept.improving` (strict improvement)
  and `LnsAccept.simulatedAnnealing` (textbook cooling). The
  initial feasibility solve uses `CSP.solve` (not `solveOptimal`)
  so the LNS loop has room to improve; each inner sub-problem
  pins all-but-freed variables to their incumbent values and runs
  `CSP.solveOptimal` against the smaller residual.
  `LnsContext` exposes the variable list, incumbent, iteration
  counter, RNG, and a pre-built constraint-variable adjacency
  graph for user-defined policies. `LnsResult` returns the best
  assignment + per-run `LnsStats` (iterations, accepts, rejects,
  infeasibles, timeouts, initial / final objective, elapsed
  micros). `bench(lns)` section compares LNS vs plain
  `minimize` on bin-packing min-max-load; on 12 items / 3 bins
  LNS finds the optimum ~14× faster than plain B&B. 35 new
  tests across `test/lns/policy_test.dart`,
  `test/lns/accept_test.dart`, `test/lns/integration_test.dart`.
  Tier-2 follow-ups remain: parallel LNS via `isolate_runner.dart`,
  adaptive destroy weighting (ALNS, Ropke & Pisinger 2006),
  late-acceptance hill-climbing (Burke et al. 2017); see
  [`LNS_PLAN.md`](LNS_PLAN.md) §3 milestone M5 and `doc/lns.md`.

- [ ] **Float / real variables.** Currently every variable is
  enumerated (`int`, `String`, set of indicators). Continuous
  quantities — fractional task durations, geometric placement at
  sub-integer resolution, prices, rates, probabilities — cannot
  be modelled. Implementation needs a fourth `_DomainRep`
  (interval over `double` with width / split-on-branch
  semantics), interval-arithmetic propagators for the linear /
  product / sum constraints, and a branch policy that splits an
  interval rather than enumerating values. Multi-session; the
  precision-vs-soundness questions (when is an interval "small
  enough" to count as solved? do we trust IEEE-754 here?) are
  the real design cost.

- [x] **Conflict explanation / model debugging — first cut.**
  Shipped as `Problem.findMinimalUnsatisfiableSubset()` in a new
  `ConflictExplanation` extension. Returns a `List<ConstraintRef>?`
  — `null` if the model is satisfiable, a list of refs identifying
  a minimal unsatisfiable subset otherwise. Removing any one of the
  returned constraints makes the residual problem satisfiable;
  re-posting just the returned constraints reproduces the
  infeasibility.

  Algorithm: textbook deletion-based MUS (Bakker et al. 1993,
  Junker 2001). O(n) calls to `CSP.solve` where n is the number of
  user-posted constraints. Cancellation in step 1 returns null;
  cancellation in step 2 returns the current (sound but possibly
  non-minimal) subset. New public type `ConstraintRef` with
  `id` / `kind` / `variables`; binary forward+reverse pairs share
  a ref.

  Follow-ups now shipped: QuickXplain (Junker 2004) and per-`addX`-call
  labels (`ConstraintRef.label`) — see the Tactical wins entries
  below. Still open: (a) explanation-aware propagators that return a
  sub-cause subset rather than the full constraint scope (would
  converge toward LCG-style explanations); (b) MSS / multiple MUSes
  (MARCO). See `doc/conflict-explanation.md`. 21 new tests in
  `test/explain_test.dart`. 645 total.

---

## Tactical wins — one session, well-motivated, proven value

Each of these has a clean specification, an existing implementation
slot, and a measurable before/after signal in `benchmark/`. Pick
any one if you want a clean one-session win.

- [x] **Cooperative parallel LNS.** Mid-run incumbent broadcasting
  shipped on the existing portfolio runner via a new
  `cooperative: true` flag on `lnsMinimizeInIsolates` /
  `lnsMaximizeInIsolates`. The implementation wires a
  `['bound', num]` message kind through the existing worker
  wire-protocol: worker → parent on every local improvement,
  parent → siblings as a re-broadcast routed via each session's
  control port. Workers use the broadcast bound to pre-tighten
  the objective domain of the next sub-problem; iterations whose
  tightened domain becomes empty are skipped as infeasible. The
  local incumbent / RNG / policy state stay independent per
  worker — only the objective bound crosses the channel.
  `Problem.lnsMinimize` / `lnsMaximize` learned `boundHint:` and
  `onIncumbent:` plumbing parameters; both default to null so
  non-cooperative runs are unchanged. See `doc/lns.md`'s
  "Cooperative parallel LNS" section. The companion
  `LCG_PLAN.md` scoping doc for the next strategic-gap pick
  ships alongside. 5 new tests across `test/lns/parallel_test.dart`
  and `test/lns/integration_test.dart`. 894 total (was 889).

- [x] **Search-annotation mapping in the FlatZinc frontend.** The
  `:: int_search(...)` / `:: bool_search(...)` annotation's
  `varSelect` keyword is now read by the FlatZinc runner and routed
  to the matching dart_csp heuristic — `dom_w_deg` /
  `most_constrained` / `weighted_degree` → `useDomWdeg`;
  `activity_var` / `activity_var_min` / `vsids` → `useVsids`;
  `impact` → `useImpact`. `bool_search` is treated identically to
  `int_search`. Required parser extension to accept nested
  annotation calls (new `AstAnnotationCall` expression node), which
  also unlocks `:: seq_search([int_search(...), int_search(...)])`
  — the hint extractor walks the inner array and picks the first
  recognised `varSelect`. `CSP.solveOptimal` and `Problem.minimize`
  / `Problem.maximize` learned the same heuristic flags so the
  routing applies on optimisation runs too. Caveats documented in
  `doc/flatzinc.md`: the hint is global (no per-variable-set
  scoping yet), so `seq_search` does not drive sequential per-group
  search; `valSelect` and exploration modes (`complete` / `lds`)
  are still ignored. 11 new tests across
  `test/flatzinc/m6_polish_test.dart`,
  `test/flatzinc/parser_test.dart`, and
  `test/optimization_test.dart`. 889 total (was 878).

- [x] **Impact-Based Search (Refalo 2004).** Shipped as
  `Problem.getSolutionWithImpact()` / `CSP.solveWithImpact` plus a
  `useImpact:` flag on `getSolutionWithRestarts`. Per-`(variable,
  value)` running mean of observed impact, where impact for a
  successful decision is `1 - exp(logP_after - logP_before)`
  (clamped to `[0, 1]`) and impact for a failed propagation is
  `1.0`. Picker minimizes `dom_size / (1 + Σ_a I(v, a))` — MRV
  pre-observation, IBS-biased post-observation, mirroring the
  dom/wdeg and VSIDS picker shapes. Wired into all six search
  variants (`_searchOne`/`All`/`Optimal` and their CBJ analogues)
  so IBS works with restarts, SAC preprocessing, FC, and CBJ
  unchanged. 16 new tests in `test/impact_test.dart`. 606 total.

- [x] **`bench(heuristic)` extended with harder UNSAT.** Added
  pigeonhole CNF 8-in-7 to the heuristic comparison section.
  Confirms the dom/wdeg family's advantage over MRV widens with
  problem size (2.0× at 7-in-6 → 2.2× at 8-in-7). 9-in-8 was tried
  but excluded — MRV took ~14 s per rep, too slow for routine
  benching. No code changes outside `benchmark/`.

- [x] **Label support for set-variable and soft-constraint helpers.**
  Finishes the per-`addX`-call labels rollout. Every set-variable
  constraint helper (`addSetCardinality` / `Range` / `Var`,
  `addRequiredInSet`, `addExcludedFromSet`, `addSubset`,
  `addSetEquals`, `addSetDisjoint`, `addSetUnion` /
  `Intersection` / `Difference`) and `addSoftConstraint` now accept
  an optional `label:` that propagates to every decomposed
  constraint they post. `addSetVariable`, `addSetVariables`, and
  `declareSoft` intentionally don't accept `label:` because they
  don't post constraints (they declare indicator variables or mark
  a bool var as soft). 8 new tests; 690 total (was 682). The
  conflict-explanation strategic gap is now closed at the level of
  user-facing helpers — only the deeper investigations
  (explanation-aware propagators, MSS, MARCO) remain, and all of
  those are multi-session.

- [x] **`bench(explain)` — deletion vs QuickXplain comparison.**
  New "conflict-explanation comparisons" section in
  `benchmark/benchmark.dart` runs both MUS algorithms side-by-side
  on seven problems spanning small-k-large-n (QX should win) to
  k≈n (deletion should win). New `buildExplainSingletonMus({n})`
  and `buildExplainTriangleMus({n})` builders in
  `benchmark/problems.dart` for the n = 10/50/200 scaling sweeps.
  Confirms textbook crossover: QX wins 4×–63× on small-k-large-n;
  deletion wins ~1.6× when k = n. 3-rep warm-up + 9-rep median
  methodology (MUS calls are themselves many `CSP.solve` calls).

- [x] **Per-`addX`-call labels for conflict explanation.** Shipped
  as an optional `label:` parameter on every primary constraint
  helper on `Problem` (forty-odd `addX` methods), surfaced on a new
  `ConstraintRef.label` field. The label is stored on the underlying
  `BinaryConstraint` / `NaryConstraint` and surfaced by both MUS
  algorithms in their returned `ConstraintRef`s. Decomposed helpers
  (`addInverse`, `addLexChain`, `addValuePrecedence`, binary
  `addAllEqual`) propagate the label to every decomposed piece, so a
  MUS that pulls in any subset of a cluster shows them all with one
  consistent label. `ConstraintRef.toString` now renders
  `kind[label](variables)` when the label is set and the original
  `kind(variables)` otherwise. Equality on `ConstraintRef` remains
  keyed by `id` alone. Backwards-compatible: `label:` defaults to
  null and existing user code surfaces `ConstraintRef.label` as null.
  16 new tests in `test/labels_test.dart`. 682 total (was 666).

- [x] **QuickXplain (Junker 2004).** Shipped as
  `Problem.findMinimalUnsatisfiableSubsetQuickXplain({cancelToken,
  consistency})` — a sibling to the deletion-based
  `findMinimalUnsatisfiableSubset` in the same `ConflictExplanation`
  extension. Same return shape (`Future<List<ConstraintRef>?>`),
  same granularity, same `ConstraintRef` semantics; the difference
  is the algorithm. QuickXplain runs divide-and-conquer: split the
  candidate set in half, recurse on each half against a growing
  background of "already known to be in the MUS" constraints,
  short-circuiting whenever the background alone is unsat. O(k ·
  log(n / k)) calls to `CSP.solve` where n is the total constraint
  count and k is the MUS size — dramatically less than the deletion
  pass's O(n) for small-k-large-n models, and comparable for k ≈ n.
  Cancellation semantics differ: the QX recursion does not maintain
  a "current kept set" that would be sound mid-flight, so any
  cancellation returns `null` (vs deletion's "sound but possibly
  non-minimal" mid-loop result). 21 new tests in
  `test/quickxplain_test.dart`. 666 total (was 645).

- [x] **Last-Conflict heuristic (Lecoutre 2009).** Shipped as
  `Problem.getSolutionWithLastConflict({useDomWdeg, useVsids,
  useImpact, ...})` / `CSP.solveWithLastConflict` plus a
  `useLastConflict:` flag on `getSolutionWithRestarts`. Wrapper
  semantics: on every propagation failure, the engine records
  the variable being pinned at the failure point
  (`_lastConflictVar`); the next variable picked is that recorded
  variable when still unassigned, falling through to the
  underlying picker otherwise. Wired into all six search variants
  at the propagation-failure path (one line each). Composes
  unchanged with MRV / dom/wdeg / VSIDS / IBS underneath and with
  restarts / FC / SAC / CBJ orthogonally. Companion benchmark
  section `bench(heuristic)` added: five-way head-to-head (MRV /
  dom-wdeg / VSIDS / IBS / LC+dom-wdeg) on magic-square 3x3,
  12/16-queens, SEND+MORE linear, pigeonhole 7-in-6 UNSAT with
  the 5-rep-warm-up + 25-rep-median harness. Local result on
  pigeonhole UNSAT: LC+dom/wdeg ≈ 44 ms, dom/wdeg ≈ 48 ms, VSIDS
  ≈ 48 ms, IBS ≈ 53 ms, MRV ≈ 88 ms. 18 new tests in
  `test/last_conflict_test.dart`. 624 total.

- **~~Strengthen the diff_n sweep with per-pair partial-GAC
  pruning~~ — investigated, ruled out.** `bench(diff_n)` measures
  the shipped sweep doing 2.2× more search than the prior
  decomposition on UNSAT (189 vs 85 decisions on the
  5×(3×3)-in-6×6 case). The original framing assumed the
  decomposition's `_reviseNary` tuple-iteration GAC was strictly
  stronger than the sweep's compulsory-part rule. A direct
  analysis of the 4-ary non-overlap disjunction shows otherwise:
  each disjunct is monotone in a single variable, so bounds-
  consistency (what the sweep computes via compulsory-part
  intervals) is **provably equivalent** to full GAC. The
  100-decision gap is real but comes from propagation-queue
  ordering effects (a sweep wakes once and runs over all pairs
  together; the decomposition has `n(n-1)/2` separate
  constraints whose interleaved re-wake order produces a
  different exploration sequence with the same per-pair pruning
  power). A "iterate the sweep to fixed point within a single
  `propagate()` call" attempt was tried and produced zero change
  in decision count, confirming that the engine's re-wake
  mechanism is already reaching the same fixed point. If a
  future session wants to revisit this, the angles still on the
  table are (a) probing whether `_gacWorkBound = 4096` bails out
  silently on some decomposition support search and the
  resulting weaker pruning lets MRV pick a luckier next
  variable, (b) custom variable-ordering inside the sweep that
  mimics the decomposition's interleaving, or (c) a strictly
  stronger global filter like energetic reasoning over a triple
  or quadruple of rectangles. None of these is a clean
  one-session win.

- [ ] **Edge-finding propagator for `addCumulative` (Vilím 2007).**
  Same shape as the diff_n sweep but applied to the 1D-time /
  multi-capacity case rather than 2D rectangles. Substantial
  work (1-2 sessions). The current time-table propagator is
  sound and adequate for most workloads; edge-finding is the
  standard perf upgrade for tight cumulative scheduling
  (RCPSP-like problems). Take on if a real RCPSP-style benchmark
  surfaces — otherwise the current time-table is fine.

---

## Edge / workload-gated — don't pick without specific motivation

These items are listed honestly but should NOT jump the queue
past the strategic gaps or tactical wins. Each one has a known
narrow value with no motivating workload surfaced.

- **SAC-2 / SAC-OPT.** Cache the singleton-support witness per
  value so only invalidated witnesses get re-tested on the next
  outer pass. ~1-2 hours, isolated to `_enforceSac`. Pick only
  if a workload surfaces where SAC preprocessing dominates
  wall-clock.

- **VSIDS variants** — pure-activity picker (no domain
  weighting), and bump-on-decision-conflict (in addition to the
  shipped propagation-conflict bumping). Each is a 1-2 hour add.
  Pick only if a specific workload benchmarks better with the
  variant than the shipped form.

- **k-dimensional sweep for `addDiffN`.** Extends the shipped 2D
  sweep to 3+ dimensions for 3D container loading or higher-d
  packing. Multi-day; only pick if a 3D-packing use case
  surfaces.

- **Minimal-cause conflict analysis for CBJ.** The current
  chain-following attribution is pessimistic on n-ary
  constraints; true minimal-cause would track per-value support
  attribution inside each propagator's revise step. Reality
  check: for the engine's generic GAC support search the "every
  other var contributes" approximation is essentially minimal
  (the support loop genuinely consults every other variable's
  full domain). Wins, if any, come from algorithm-specific
  attribution inside the specialized propagators. Multi-day,
  dubious payoff. See `doc/cbj.md` "What's not implemented".

- **Per-variable watch lists for the clause propagator —
  textbook full version.** Maintain an explicit inverse index
  `Map<String, Set<ClauseSpec>>`. The shipped per-variable
  seeding filter is already O(1) per clause check via the
  `_clauseWatchers` side-table; this would only save the
  `_naryIdx[v]` iteration. Probably not worth it.

- **Native FFI to OR-Tools / Choco.** Closes most strategic gaps
  overnight at the cost of becoming a different project — a
  Dart wrapper around a native solver rather than a pure-Dart
  solver. Distinct product shape; explicitly out of scope for
  this library.

---

## What shipped (compressed retrospective)

These items were the original Tier 1 / Tier 2 / Tier 3 plan.
Test counts are end-of-shipping; CHANGELOG.md has full per-feature
rationale, README has the public-API view, and `doc/<feature>.md`
covers anything with substantial design questions.

### Tier 1 — fundamental capability / perf

- [x] **Branch-and-bound optimization.** `Problem.minimize` /
  `maximize` via integrated B&B in `_BacktrackEngine.findOptimal`
  (each improving leaf permanently prunes the objective's domain;
  no per-improvement restart). 23 tests in
  `test/optimization_test.dart`.
- [x] **Régin's matching-based `allDifferent` propagator.**
  Hopcroft-Karp + Kosaraju SCC + free-value reachability.
  Pathological 3x3 magic-square (no clue): 104,520 ms → 16 ms.
  8 tests in `test/alldifferent_propagator_test.dart`.
- [x] **Trail-based undo.** Replaced per-recursion full-domain
  snapshots with an append-only trail of
  `(varName, oldRep, cause)` entries. Every mutation routes
  through `_setDomain` / `_setDomainRep`.
- [x] **Bitset domain representation.** Three reps in
  `_DomainRep`: `_BitsetRep` (`Uint64List` + offset, span ≤
  1024), `_IntervalRep` (`(min, max)` for span > 1024), and
  `_ListRep` (everything else). Propagators read via the rep API
  and write via the rep-aware `applyUpdate` callback. 16 tests
  in `test/bitset_domain_test.dart`.

### Tier 2 — standard CP feature set

- [x] **Restart strategies.** Luby sequence on
  `solveWithRestarts`. 7 tests in `test/restart_test.dart`.
- [x] **dom/wdeg variable heuristic.** Per-constraint failure
  weights, picker minimizes `dom(v) / wdeg(v)`. 6 tests in
  `test/dom_wdeg_test.dart`.
- [x] **VSIDS-style variable activity heuristic.**
  `getSolutionWithActivity` and `useVsids:` flag on the restart
  entry point. Picker minimizes `dom(v) / (1 + activity(v))`.
  12 tests in `test/vsids_test.dart`.
- [x] **Symmetry-breaking primitives.** `addLexLeq` / `addLexLt`
  (sequence lex), `addLexChain` (n-way sugar), `addValuePrecedence`
  (value-permutation symmetry). 29 tests in
  `test/symmetry_breaking_test.dart`.
- [x] **Reified constraints.** `b ⇔ C` across the equality /
  comparison / set-membership family. 17 tests in
  `test/reified_constraints_test.dart`.
- [x] **Logical combinators on boolean variables.** `addAtLeast`,
  `addAtMost`, `addExactly`, `addImplies`, reified-and/or/not.
  13 tests in `test/logical_combinators_test.dart`.
- [x] **Global constraint library.** `addElement`, `addTable`,
  `addAmong[Exactly]`, `addNvalue[Exactly]`, `addGcc` /
  `addGccRanges`, `addCircuit`, `addSubcircuit`, `addBinPacking`,
  `addRegular`, `addInverse`, `addDiffN`. Each global ships with
  a tagged dispatch flag on `NaryConstraint` and (where it pays
  off) a specialized propagator: Régin for allDifferent,
  network-flow for GCC, partial-state DFA for regular,
  cycle-detection for circuit / subcircuit, time-table for
  cumulative (via `addNoOverlap` → `addCumulative`), forbidden-
  region sweep for `addDiffN`. Coverage: 25 + 31 + 39 + 20 + 25
  tests across `global_constraints_test`,
  `global_cardinality_test`,
  `circuit_and_bin_packing_test`, `regular_constraint_test`,
  `diffn_test`.
- [x] **Soft constraints / MaxCSP.** `SoftConstraints` extension
  with `declareSoft` / `addSoftConstraint` /
  `maximizeSatisfaction` on top of B&B. 11 tests in
  `test/soft_constraints_test.dart`.
- [x] **Variable types beyond enumerated int / string.** Interval
  variables (`_IntervalRep` + `addRangeVariable` + `addNoOverlap`),
  set variables (`SetVariables` extension with `addSetVariable`
  and friends, decomposed to per-element 0/1 indicators), SAT-
  style clauses (`addClause` with two-watched-literal propagator
  + per-variable seeding filter). 16 + 40 + 22 tests across
  `interval_variables_test`, `set_variables_test`, `clause_test`.
- [x] **Bounds-consistency linear propagator.** `LinearSpec`,
  `LinearOp`, `addLinearEquals` / `addLinearLeq` / `addLinearGeq`.
  SEND+MORE expressed as a single linear equation: 1834 ms → 1 ms
  vs the predicate-only encoding. 21 tests in
  `test/linear_propagator_test.dart`.
- [x] **Cumulative resource constraint.** `addCumulative(starts,
  durations, demands, capacity)` with time-table propagator
  (Beldiceanu & Carlsson 2002). 17 tests in
  `test/cumulative_test.dart`.

### Tier 3 — engineering & ecosystem

- [x] **Isolate-based parallelism + cooperative checkpoints.**
  `solveInIsolate` / `solveAllInIsolate` / `minimizeInIsolate`
  / `maximizeInIsolate`, parent-side `CancellationToken` bridged
  via `addListener`, built-in `timeout:`. Every backtracking
  entry point also accepts `cancelToken:`. 13 + 11 tests across
  `cancellation_test`, `isolate_runner_test`.
- [x] **Conflict-directed backjumping (Prosser 1993).** Opt-in
  via `enableConflictBackjumping:` on every backtracking entry
  point. Per-revision conflict-cause attribution via
  `_TrailEntry.cause`. 13 + 15 tests across `cbj_test`,
  `cbj_benchmarks_test`.
- [x] **Pluggable consistency level.** `ConsistencyLevel.forwardChecking`,
  `arcConsistency` (default), `singletonArcConsistency` (SAC-1
  preprocessing — Debruyne & Bessière 1997). 13 + 18 tests across
  `consistency_level_test`, `sac_test`.
- [x] **Solver statistics.** `SolverStats` with `decisions`,
  `backtracks`, `propagations`, `binaryRevises`, `naryRevises`,
  `iterations`, `elapsedMicros`, `backjumps`,
  `backjumpLevelsSkipped`. 13 tests in `test/stats_test.dart`.
- [x] **Random seed control.** `seed:` on `solveWithMinConflicts`
  and `solveWithRestarts`; every randomized solver is reproducible.
- [x] **`benchmark/` directory.** Three sections —
  plain-BT-vs-CBJ on 10 classic CSPs, AC-vs-SAC on the canonical
  SAC-only infeasibility example, sweep-vs-decomposition on
  `diff_n` packing problems with the 5-rep-warm-up + 25-rep-median
  methodology. Shared problem builders in `benchmark/problems.dart`
  imported by `test/cbj_benchmarks_test.dart` so a divergence
  shows up as a test failure.
- [x] **Semver discipline + API stability statement.** `STABILITY.md`.

The original Tier 3 frontend item (MiniZinc / FlatZinc / XCSP3)
is no longer here — it moved to **Strategic gaps** because it's
multi-day work and the framing it deserves is "ecosystem
table-stakes", not "engineering polish".

---

## Cross-cutting

- Every new propagator must come with: a unit test for the
  propagator itself, an integration test through the solver,
  and a benchmark entry if it's perf-relevant.
- Every solver-level change should be runnable against the
  existing `test/` suite without regressions before it merges.
- README + relevant `doc/` topical guide updated in the same
  change as the feature.
- Perf claims need warm-up + median methodology
  (`benchmark/benchmark.dart`'s `_runMedian` is the canonical
  shape). Single-shot cold timings are misleading on
  moderately-sized problems.

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
  between minutes and hours; industrial-scale optimization where
  LNS dominates; ecosystem integration (no MiniZinc / FlatZinc /
  XCSP3 frontend means no head-to-head benchmarking against
  Choco, Gecode, OR-Tools); problems with continuous quantities
  (no float / real variables); and user-facing debuggability
  (no conflict explanation when a model is infeasible).

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

- [ ] **MiniZinc / FlatZinc / XCSP3 frontend.** Ecosystem
  table-stakes. Without a frontend, `dart_csp` cannot be
  benchmarked against any other CP solver on standard problem
  sets (MiniZinc challenge, XCSP3 competition, CSPLib). It lives
  in a walled garden. Implementation: a FlatZinc parser
  (FlatZinc is the lower-level target language MiniZinc compiles
  to, much simpler to parse), an AST, and a lowering pass to
  `Problem`. XCSP3 is XML-based, easier to parse but with a
  larger built-in constraint catalog. Multi-day (2-4 sessions);
  no algorithmic invention required.

- [ ] **Large Neighborhood Search (LNS).** What makes CP-SAT
  competitive on industrial-scale routing, scheduling, and
  assignment. The pattern: find an initial feasible solution,
  then iteratively "destroy" a subset of variables (fix the
  rest), re-solve the smaller sub-problem, accept the new
  solution if it improves the objective. Decomposes optimization
  into a sequence of small focused searches. Sits on top of the
  existing `minimize` / `maximize` engine and a destroy policy
  (random, related-tasks, time-window, etc.). Multi-day; design
  cost is in the destroy policies and the parallel-evaluation
  framework, not the inner loop.

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

- [ ] **Conflict explanation / model debugging.** When a model is
  infeasible the solver currently returns the literal `'FAILURE'`
  and nothing else. For a non-trivial model this is a debugging
  nightmare — the user has no idea which constraints conflict.
  A "minimal unsatisfiable subset" (MUS) explanation pass would
  identify a small subset of posted constraints whose conjunction
  is still infeasible. Smaller than LCG (the MUS algorithms —
  deletion-based, QuickXplain — are well-understood) but useful
  out of all proportion to its size for users with non-trivial
  models. ~1-2 sessions if scoped carefully.

---

## Tactical wins — one session, well-motivated, proven value

Each of these has a clean specification, an existing implementation
slot, and a measurable before/after signal in `benchmark/`. Pick
any one if you want a clean one-session win.

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

- [ ] **Last-Conflict heuristic (Lecoutre 2009).** Cheapest
  high-value heuristic in the literature. After any backtrack,
  the next variable picked is the one whose pin caused the
  conflict (if it's still unassigned), otherwise the heuristic
  falls back to dom/wdeg or whatever the configured picker is.
  ~50 lines on top of the existing variable picker; broadly
  improves dom/wdeg's robustness on hard instances. ~1 hour.

- [ ] **Strengthen the diff_n sweep with per-pair partial-GAC
  pruning.** `bench(diff_n)` measures the shipped sweep
  propagator taking 2.2× more search than the prior pairwise
  decomposition on UNSAT (189 vs 85 decisions). The sweep wins
  wall-clock by 2× because per-call cost is much lower, but the
  per-decision pruning is strictly weaker than the GAC support
  search the decomposition got "for free". Add a bounded per-pair
  partial-GAC check on top of the sweep's compulsory-part rule:
  for each pair `(r, s)`, additionally remove values of
  `(x_r, y_r)` that have no support in the 4-ary disjunction
  *over the current* `(x_s, y_s)` *domain*. Bound the work with
  a per-pair iteration cap so the call cost stays comparable to
  the current sweep. Belt-and-braces pairwise predicate already
  exists on the constraint; reuse it as the per-tuple test.
  ~1-2 hours; isolated to `_DiffNPropagator`. Immediate
  before/after signal in `bench(diff_n)`.

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

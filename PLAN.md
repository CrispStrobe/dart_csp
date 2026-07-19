# PLAN — Roadmap for `dart_csp`

This is a forward-looking roadmap: what's *next*. The **done** record
— the original three-tier plan plus every shipped strategic gap and
tactical win — lives in [`HISTORY.md`](HISTORY.md). The interesting
parts of this file are the **Strategic gaps**, **Tactical wins**, and
**Edge / workload-gated** sections, which describe what would
meaningfully change what `dart_csp` is or who it competes with.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done
(shipped items move to [`HISTORY.md`](HISTORY.md)).

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
SAC-1 preprocessing, integrated branch-and-bound, a worker-isolate
runner, an LNS metaheuristic layer, a FlatZinc frontend, conflict-
explanation (MUS) tooling, and an in-progress Lazy Clause Generation
(LCG) learning path. See [`HISTORY.md`](HISTORY.md) for the full
shipped inventory.

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

## Active build — ergonomics & solution-oriented features

A batch of user-facing capabilities that widen *what you can ask the
solver for* and *how pleasant it is to model*, built in order of
increasing coupling to the engine (least first). Each ships with tests
and a CHANGELOG entry; shipped ones move to [`HISTORY.md`](HISTORY.md).

- [x] **1. Typed modeling DSL (`IntVar` / `LinearExpr`).** ✅ Shipped
  (`lib/src/model_dsl.dart`, 17 tests). Operator
  overloading — `(x + 2*y).le(z)`, `x.ne(y)`, `x.eq(5)` — instead of
  string constraints or raw predicate lambdas. A thin, engine-free layer
  over the existing `Problem` API: relations lower to the existing
  `addLinearEquals/Leq/Geq` (and a linear-`ne` predicate). Biggest
  ergonomics win; self-contained.

- [x] **2. Solution sampling & diversity.** ✅ Shipped
  (`lib/src/sampling.dart`, 13 tests). `sampleSolutions(k)`
  (reservoir sampling over the enumeration stream — true uniform),
  `randomSolution()` (randomized value order — fast, non-uniform), and
  `diverseSolutions(k)` (greedy max–min Hamming). Directly powers the
  existing puzzle generators (`gencw`, `gensq`). Builds on
  `getSolutions()`; complements the shipped `countSolutions()`.

- [x] **3. Multi-objective optimization.** ✅ Shipped
  (`lib/src/multi_objective.dart`, 13 tests). `lexOptimize([...])`
  (priority-ordered objectives via staged branch-and-bound) and
  `paretoFront([...])` (non-dominated set via no-good dominance
  exclusion). Builds on `solveOptimal` + constraint posting; closes a
  real modelling gap on the scheduling/rostering workloads already
  targeted.

- [x] **4. UNSAT proof / nogood logging.** ✅ Shipped
  (`lib/src/lcg/proof.dart`, 11 tests) as `solveWithProof` + `ProofLog`,
  built on the existing `onLearnedClause` hook. Scoped honestly to a
  nogood-derivation log (not a standalone DRAT proof — the lazy clausal
  encoding is not emitted). Emit a checkable
  learned-clause/nogood proof (DRAT-style over the Boolean atom
  encoding) when the LCG engine proves UNSAT. Natural given the shipped
  clause-learning path; "certified UNSAT" credibility.

- [x] **5. Incremental / assumption-based solving.** ✅ Shipped in full.
  The retractable-assumption *interface* (`IncrementalSolver`, push/pop
  scopes, assume* flavours; 14 tests) plus **warm-starting**
  (`prime` / `solveWarm`; 6 tests) — re-solves reuse the base problem's
  learned nogoods (implied by the base, sound under any assumptions) via the
  engine's existing `onLearnedClause` / `importClauses` hooks. Measured
  ~3.4× fewer decisions on a conflict-heavy base. Only base-derived clauses
  are cached (always-sound "strategy 1"); assumption-tagged reuse (strategy
  2) remains a possible future extension. Solve under
  retractable assumptions and push/pop constraints without rebuilding
  from scratch, warm-started via retained learned clauses. Deepest
  coupling (touches the engine core) — the highest-leverage item for
  interactive downstreams that re-solve on every edit. Done last.

---

> **Executing the open engine-level work?** See
> [`doc/next-engine-work.md`](doc/next-engine-work.md) — a precise,
> step-by-step handover for float engine-integration and incremental
> warm-starting, with resolved design decisions and file anchors.

## Strategic gaps — high-impact, multi-session

These are the items that change what kind of solver `dart_csp`
*is*. Each one is large enough to be a deliberate project, not
an opportunistic pick.

> Shipped strategic gaps (FlatZinc frontend, LNS, conflict
> explanation) are recorded in [`HISTORY.md`](HISTORY.md).

- [x] **Lazy Clause Generation (LCG) / nogood learning.** ✅ **Done** —
  moved to [`HISTORY.md`](HISTORY.md). The single biggest gap is closed:
  M1–M5 shipped, the iterative trail-based CDCL engine is the default
  (sound non-chronological backjumping + clause minimisation + VSIDS/dom-wdeg
  bump + Luby restarts), and **every specialised propagator now has an
  `explain` companion** (M3a–M3g: clause, allDifferent, linear, GCC,
  regular, cumulative, diff_n, circuit), each validated by a verdict-parity
  sweep vs full enumeration. See `LCG_PLAN.md` / `doc/lcg.md`. *Only small
  optional polish remains, tracked under Tactical wins below.*

- [~] **Float / real variables.** Currently every variable in the *integer
  engine* is enumerated (`int`, `String`, set of indicators). **First slice
  shipped** as a self-contained interval solver (`lib/src/continuous.dart`,
  `ContinuousModel` / `Interval` / `FloatVar` / `FloatExpr`, 16 tests):
  linear continuous CSPs solved by HC4 bound propagation + bisection
  branch-and-prune, with an epsilon tolerance and the precision/soundness
  model made explicit (plain IEEE-754; a narrow surviving box is a witness,
  not a verified enclosure). This deliberately does **not** touch the integer
  engine.

  Non-linear propagators (`x * y`, `x²`) have since landed in the isolated
  solver via product decomposition (aux variable + interval product
  constraint; `test/continuous_nonlinear_test.dart`) — handover step A1. And
  **mixed integer + continuous modelling** now works in the isolated solver
  too (`addIntVar`: integer bounds round inward, search branches on integer
  boundaries; `test/continuous_mixed_test.dart`) — the *capability* of one
  model holding both kinds.

  **Engine integration has since landed** (handover step A2):
  `Problem.addFloatVariable` puts real-valued variables in the main engine
  via the originally-scoped fourth `_DomainRep` (interval over `double`),
  bisection branching in every search loop, and an HC4 propagator for
  linear constraints spanning both kinds — so mixed models now get the GAC
  globals and the dom/wdeg / VSIDS / restart machinery for the discrete
  part, plus branch-and-bound over a continuous objective. 27 tests,
  `doc/mixed-continuous.md`. Continuous paths are gated on the problem
  declaring a float variable, so the pure-integer engine is unchanged.

  **Products in the main engine have since landed** too:
  `Problem.addFloatProduct(p, a, b)` posts `p == a·b` (factors may be
  continuous or integer), dispatched to an HC4 product propagator that
  reuses the zero-aware `Interval.divide`. Polynomials decompose into
  products plus linear constraints, so the two solvers now have the same
  constraint expressiveness; what differs is `ContinuousModel`'s
  operator-overloading DSL versus `Problem`'s access to the integer
  engine.

  **Verified outward rounding has since landed** (handover step A3):
  `IntervalRounding.outward` — opt-in on both solvers
  (`p.floatRounding = ...`, `model.solve(rounding: ...)`) — nudges every
  computed bound one ULP in the safe direction via web-safe `nextUp` /
  `nextDown` primitives, so no prune can discard a solution and an
  exhaustive `FAILURE` is a *proven* infeasibility. It deliberately does
  not certify positive answers: that needs an interval Newton /
  Krawczyk existence test, which remains unimplemented and is the only
  continuous item still open.

---

## Tactical wins — one session, well-motivated, proven value

Each of these has a clean specification, an existing implementation
slot, and a measurable before/after signal in `benchmark/`. Pick
any one if you want a clean one-session win.

> Shipped tactical wins (cooperative LNS, FlatZinc search-annotation
> mapping, Impact-Based Search, Last-Conflict, QuickXplain, per-`addX`
> labels, the `bench(heuristic)` / `bench(explain)` extensions, and the
> ruled-out diff_n partial-GAC investigation) are recorded in
> [`HISTORY.md`](HISTORY.md).

- [x] **LCG polish (post-M3).** ✅ **Done** — both follow-ups shipped:
  (a) the `bench(lcg)` scheduling/packing/routing showcase rows (M3e/M3f/M3g
  cumulative / diff_n / circuit), and (b) Tier-2 **parallel learned-clause
  sharing** across isolates (`solveWithLcgInIsolates(shareClauses: true)` —
  workers export short learned clauses, the parent re-broadcasts, each
  worker imports the siblings' clauses; sound + verdict-preserving). See
  `CHANGELOG.md` / `doc/lcg.md`. The LCG strategic gap and its polish are
  now fully closed.

- [x] **Stronger filtering for `addCumulative`.** ✅ **Done** — shipped as
  an **energetic-reasoning** pass (Baptiste, Le Pape & Nuijten 1999)
  rather than the originally-scoped edge-finder, because ER is provably
  sound from first principles and sidesteps the known-buggy edge-finder
  dominance rules (Mercier & Van Hentenryck). It adds an overload check
  plus earliest-start / latest-completion adjustments over the
  Baptiste–Le Pape–Nuijten relevant-interval set, on top of the existing
  time-table propagator. Gated above 64 tasks. Under LCG only the overload
  **check** runs (soundly explained by the coarse `_cumulativeConflictReason`);
  the bound *adjustments* stay off under learning (their prunes have no
  explanation companion). Validated by a 4000-instance random soundness
  sweep (solver solution set == brute force, 0 mismatches) plus a 480-run
  LCG verdict-parity sweep vs full enumeration. Moved to
  [`HISTORY.md`](HISTORY.md). *A full O(n log n) edge-finder, and an ER
  explanation that enables the bound adjustments under LCG too, remain
  possible future work if ER's cubic cost ever bites on large RCPSP.*

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
- When a roadmap item ships, move its entry from this file to
  [`HISTORY.md`](HISTORY.md) so `PLAN.md` stays forward-looking.

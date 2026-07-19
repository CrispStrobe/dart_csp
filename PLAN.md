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

- [ ] **1. Typed modeling DSL (`IntVar` / `LinearExpr`).** Operator
  overloading — `(x + 2*y).le(z)`, `x.ne(y)`, `x.eq(5)` — instead of
  string constraints or raw predicate lambdas. A thin, engine-free layer
  over the existing `Problem` API: relations lower to the existing
  `addLinearEquals/Leq/Geq` (and a linear-`ne` predicate). Biggest
  ergonomics win; self-contained.

- [ ] **2. Solution sampling & diversity.** `sampleSolutions(k)`
  (reservoir sampling over the enumeration stream — true uniform),
  `randomSolution()` (randomized value order — fast, non-uniform), and
  `diverseSolutions(k)` (greedy max–min Hamming). Directly powers the
  existing puzzle generators (`gencw`, `gensq`). Builds on
  `getSolutions()`; complements the shipped `countSolutions()`.

- [ ] **3. Multi-objective optimization.** `lexOptimize([...])`
  (priority-ordered objectives via staged branch-and-bound) and
  `paretoFront([...])` (non-dominated set via no-good dominance
  exclusion). Builds on `solveOptimal` + constraint posting; closes a
  real modelling gap on the scheduling/rostering workloads already
  targeted.

- [ ] **4. UNSAT proof / nogood logging.** Emit a checkable
  learned-clause/nogood proof (DRAT-style over the Boolean atom
  encoding) when the LCG engine proves UNSAT. Natural given the shipped
  clause-learning path; "certified UNSAT" credibility.

- [ ] **5. Incremental / assumption-based solving.** Solve under
  retractable assumptions and push/pop constraints without rebuilding
  from scratch, warm-started via retained learned clauses. Deepest
  coupling (touches the engine core) — the highest-leverage item for
  interactive downstreams that re-solve on every edit. Done last.

---

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

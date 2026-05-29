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

## Strategic gaps — high-impact, multi-session

These are the items that change what kind of solver `dart_csp`
*is*. Each one is large enough to be a deliberate project, not
an opportunistic pick.

> Shipped strategic gaps (FlatZinc frontend, LNS, conflict
> explanation) are recorded in [`HISTORY.md`](HISTORY.md).

- [~] **Lazy Clause Generation (LCG) / nogood learning.** The
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

  **Shipped so far:** M1 (atom encoding + implication trail +
  runner shell), M2a (first-UIP analyser), M2b (engine wiring +
  forget), lazy atom encoding, M3a (`allDifferent` explanation),
  M3b (`linear` plumbing), M3-tighten task 1 (`AtomInScc` bridge),
  M3c (`GCC` explanation), M3d (`regular` explanation), bound-atom trail
  emission, M3e (`cumulative` explanation), M3f (`diff_n` explanation), the
  tight reach-closure Hall-set /
  capacity-cut explanations, and **all of M4**: the iterative
  trail-based CDCL engine with sound *non-chronological backjumping*
  (now the **default** for `solveWithLcg`), recursive (self-subsuming)
  clause minimisation, the canonical VSIDS / dom-wdeg learned-clause
  activity bump, and Luby restarts + phase saving with full
  learned-clause + activity retention. `bench(lcg)` compares all three
  engines (plain / recursive / iterative) plus a restart showcase. The
  search is **sound + complete under any picker**; on pigeonhole-CNF
  UNSAT proofs the iterative engine is 3–5× faster wall-clock than the
  recursive learning path (7-in-6 66ms → 23.5ms, 8-in-7 467ms → 134ms),
  and restarts + phase saving cut decisions ~2.3× on heavy-tailed
  satisfiable 3-SAT.

  **Next, in priority order (see [`LCG_PLAN.md`](LCG_PLAN.md)):**
  (1) **M3g** — the `explain` companion for the *last* opaque propagator,
  `circuit` / `subcircuit`, which today emits `UnknownReason` and so falls
  back to chronological backtracking with no clause learned. It is
  `AtomNe`/`AtomEq`-shaped (fixed successor edges) with no bound
  dependency. This is the last propagator without an explanation, and the
  only remaining reason this entry is `[~]` rather than closed.
  (2) optional M5/M6 polish: a magic-square / RCPSP `bench(lcg)` row, and
  Tier-2 parallel learned-clause sharing across isolates. This entry stays
  `[~]` until the learning path is competitive across **all** propagators
  (just M3g remains), not only the matching / clause / linear / regular /
  cumulative / diff_n families it covers today.

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

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

- [ ] **LCG polish (optional, post-M3).** The LCG strategic gap is
  closed (see `HISTORY.md`); two small follow-ups remain, neither
  load-bearing: (a) a magic-square / RCPSP `bench(lcg)` row showcasing the
  scheduling/packing learning now that M3e/M3f/M3g have landed; and (b)
  Tier-2 parallel learned-clause sharing across isolates (workers exchange
  short learned clauses, like cooperative LNS shares bounds). Pick either
  for a clean one-session win if LCG perf on a concrete workload motivates
  it.

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

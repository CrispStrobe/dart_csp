# Handover — next engine-level work

A precise, executable brief for the two open items in [`PLAN.md`](../PLAN.md):
**float/real variable engine integration** and **incremental warm-starting**.
Both are core-engine, multi-session efforts; each section below gives the
current state, resolved design decisions, exact file anchors, a step-by-step
plan, a test strategy, and the regression risks to watch.

Written after the 2.3.0 release + the experimental continuous-solver slice.
As of that point: **1223 tests green**, `dart analyze --fatal-infos` clean,
CI green across the full matrix.

## Repo conventions (apply to everything below)

- Gate before every commit: `dart format .`, `dart analyze --fatal-infos`
  (zero infos — the CI `test` job runs `--fatal-infos`), `dart test`.
- Examples are executed by CI (`.github/workflows/ci.yml` "Validate
  Examples"); any `example/*.dart` must exit 0 within 60s.
- Direct push to `main` is authorized once tests pass (see the project
  memory). Keep each feature a self-contained commit; push and confirm CI.
- When a `PLAN.md` item ships, move its entry to `HISTORY.md`; keep `PLAN.md`
  forward-looking. Add a `CHANGELOG.md` entry (under `## Unreleased` until a
  release) and a README section + `doc/<topic>.md` guide for user-facing work.
- New public API triggers a **minor** version bump; bug fixes a **patch**.
  Releasing = bump `pubspec.yaml` + rename the CHANGELOG header, push, wait
  for green CI, then push a `vX.Y.Z` tag (fires the pub.dev OIDC publish in
  `.github/workflows/publish.yml` and the GitHub release job in `ci.yml`).
  Publishing is irreversible — confirm with the user first.
- Every new propagator needs a unit test, an integration test through the
  solver, and a soundness sweep (solver solution set == brute force over a
  few thousand random small instances) — this is how the existing LCG
  propagators are validated (see `test/lcg/`).

---

## Item A — Float / real variables

### A0. Where it stands

Shipped (2.3.0-unreleased, experimental): `lib/src/continuous.dart` — a
**self-contained** interval branch-and-prune solver, deliberately *not*
wired into the integer engine. It has `Interval` (closed-real value type),
a `FloatVar`/`FloatExpr` DSL (`+ - unary- * scalar`; `le`/`ge`/`eq`), and
`ContinuousModel.solve({epsilon, maxSplits})` returning a
`ContinuousSolution` (narrow box + midpoint) or `null`. Solver =
`_propagate` (HC4 bound propagation over linear constraints to a fixpoint) +
bisection of the widest variable. Tests: `test/continuous_test.dart` (16),
example: `example/continuous.dart`.

Three sub-goals remain, in increasing difficulty. **Do them in this order** —
A1 is low-risk and self-contained; A2 is the big one; A3 is optional rigor.

### A1. Non-linear constraints in the isolated solver — ✅ DONE

Shipped: `x * y` / `x²` / polynomial systems in `ContinuousModel`
(`test/continuous_nonlinear_test.dart`, 10 tests + soundness sweep). The
implementation chose **product decomposition** over the expression-tree HC4
sketched below, because a naive tree suffers the interval *dependency
problem* (`x - x` would not cancel, weakening linear propagation and breaking
the linear tests). Instead: linear parts stay a term-map (exact); each
`FloatExpr * FloatExpr` lowers to a fresh aux variable `p` with a product
constraint `p == a·b`, revised by HC4 with zero-aware `Interval.divide`.
Search branches only decision variables; auxiliaries are determined by
propagation. The original expression-tree note is kept below for reference,
but the decomposition approach is what shipped and what A2 should lift.

**Original goal (superseded design).** Support `x * y`, `x²`, and general
polynomial constraints in `ContinuousModel`, still isolated from the integer
engine.

**Design decision (resolved).** Replace the linear-only `FloatExpr`
representation (a `Map<String,double>` of terms + constant) with an
**expression DAG** of primitive nodes (`var`, `const`, `add`, `mul`, `neg`),
and generalize `_propagate` from per-linear-constraint revision to **HC4
revise over the expression tree**: forward-evaluate each node's interval
bottom-up, then back-propagate the constraint's target interval top-down,
intersecting each child. This is the standard interval-constraint-propagation
architecture (Benhamou et al., HC4). Keep the linear path as the special
case (an `add` of `mul(const, var)` nodes) so `test/continuous_test.dart`
keeps passing unchanged.

**The one hard primitive: multiplication back-propagation.** Forward:
`[a,b]·[c,d]` = `[min(ac,ad,bc,bd), max(...)]`. Backward, given `z = x·y` with
`z ∈ Z`: `x ∈ Z / Y` and `y ∈ Z / X`, where interval division `Z / Y` must
handle `0 ∈ Y` (the quotient becomes the whole line, or splits into two
semi-infinite intervals — use the *hull* `(-∞,∞)` for the first slice to keep
it simple; note the precision loss). This is the only subtle part; get it
right with dedicated `Interval` division tests before touching the solver.

**Anchors.** `lib/src/continuous.dart`: `FloatExpr` (line ~71, the term-map
rep to replace), `_propagate` (line ~230, the linear revise loop to
generalize), `Interval` operators (line ~54; add `operator *` and a
`divide` that handles zero-containing divisors).

**Plan.**
1. Add `Interval.operator *` and `Interval divide(Interval)` with zero
   handling; unit-test both hard (including `[−1,1]/[−1,1]`, `[1,2]/[0,3]`).
2. Introduce an `_ExprNode` hierarchy; make `FloatExpr` wrap a root node.
   `+`/`-`/`*scalar` build `add`/`neg`/scalar-`mul` nodes; add `FloatExpr
   operator *(FloatExpr)` → `mul` node (the new non-linear capability).
3. Rewrite `_propagate`: for each constraint, forward-eval to a root
   interval, intersect with the target, back-propagate. Iterate to fixpoint
   (keep the existing 32-round cap + material-change check).
4. Bisection search is unchanged.

**Tests.** Add `x·y == 6 ∧ x + y == 5 → {2,3} or {3,2}`; `x² == 2 →
x ≈ 1.414`; a non-convex feasible region; keep all 16 existing tests green.
Add a soundness sweep: random small polynomial systems, check the returned
box's midpoint satisfies all constraints within `10·epsilon`.

**Risk.** Isolated module — **zero** risk to the integer engine. The only
correctness trap is interval division by a zero-containing interval; the
dedicated tests in step 1 cover it.

**Effort.** ~1 focused session.

### A2. Mixed integer/continuous in the main engine — ✅ DONE

> ✅ **Shipped.** `Problem.addFloatVariable(name, lo, hi)` +
> `setFloatEpsilon`, threaded through `CspProblem.floatVariables` /
> `.floatEpsilon`; `_FloatIntervalRep` as the fourth `_DomainRep` (with
> `isContinuous` on the interface); bisection branching via `_branchesFor`
> / `_applyBranch` in all seven search loops; `_FloatLinearPropagator`
> (HC4) dispatched on a new `NaryConstraint.floatLinearSpec` tag; and
> branch-and-bound over a continuous objective. 27 tests
> (`test/mixed_continuous_test.dart`, two soundness sweeps),
> `example/mixed_continuous.dart`, `doc/mixed-continuous.md`. The plan
> below is the record of what was built; deviations from it are noted
> inline. Products in the main engine and A3 remain open — see `PLAN.md`.
>
> **Three things worth knowing if you extend this.**
> 1. `_FloatIntervalRep.length` is *branchability*, not cardinality: `1`
>    when the box is within epsilon (which is what makes every existing
>    `length == 1` "assigned" idiom keep working), `2` otherwise. `values`
>    / `asList` / `filter` throw `UnsupportedError` on purpose, so a
>    missed gate fails loudly instead of pruning wrongly.
> 2. `_applyBranch` **intersects** a bisection half with the live domain
>    rather than installing it. The halves are computed once per decision;
>    by the time a later one is tried, `_tightenObjectiveDomain` may have
>    cut the domain. Overwriting it discards the bound and makes B&B walk
>    the entire box tree — `O(range/epsilon)` nodes instead of
>    `O(log(range/epsilon))`. There is a regression test for exactly this.
> 3. `_branchesFor` tries the **improving half first** on the objective
>    variable, for the same reason: worst-half-first finds a poor
>    incumbent and then creeps toward the optimum one epsilon-cut at a
>    time.

> **Earlier partial progress.** Mixed int/float *modelling* first worked in the isolated
> solver: `ContinuousModel.addIntVar(name, lo, hi)` adds integer decision
> variables that share the linear/product constraints (bounds round inward
> after each propagation step; the search branches them on integer
> boundaries). See `test/continuous_mixed_test.dart` (11 tests). What that
> does **not** give you is reuse of the integer *engine* — GAC globals
> (allDifferent, GCC, …) and the dom/wdeg / VSIDS / restart machinery — for
> the discrete part. That reuse is the remaining goal below.

**Goal.** Let a single `Problem` hold both enumerated and continuous
variables, so real models (scheduling with fractional durations, geometric
packing) work end-to-end through the existing search, heuristics, and
optimization — reusing the integer engine's propagators rather than
re-deriving them in the interval solver.

**The crux.** The engine represents every variable's domain as an
enumerable `List<dynamic>` (`Problem._variables: Map<String,List<dynamic>>`)
and, inside search, as a `_DomainRep` with three impls (list / bitset /
interval-over-**int**). A continuous variable has no enumerable domain — it
needs a `_FloatIntervalRep` (interval over **double**) whose "assignment" is
*splitting*, not value-picking.

**Design decisions (resolved / recommended).**
- **Add a fourth `_DomainRep`: `_FloatIntervalRep`** holding `[lo, hi]` over
  doubles. It cannot implement `values`/`asList`/`first` meaningfully
  (uncountable) — so the `_DomainRep` interface must grow a
  `bool get isContinuous` and the search must branch differently for it.
- **Branching.** Where the search picks a value for a discrete variable, a
  continuous variable instead **bisects** its interval into two child nodes
  (the A1 solver's split), and a variable is "assigned" when its width ≤
  `epsilon`. Solutions are boxes; the result map carries a representative
  double (midpoint).
- **Propagation.** Reuse the A1 expression-tree HC4 revise as a new
  propagator over any constraint that mentions a continuous variable; the
  existing integer propagators stay for all-integer constraints. A mixed
  linear constraint (`2·intVar + 1.5·floatVar ≤ 7`) runs the interval
  revise, treating the int variable's domain via its bounds.
- **Do NOT reuse the int `_IntervalRep`** — it assumes integer steps.

**Anchors.**
- `lib/src/solver.dart`: `abstract class _DomainRep` (line 607, add
  `isContinuous`), the three impls (`_ListRep` 636, `_BitsetRep` 664,
  `_IntervalRep` 762 — model the new rep's shape on these), `_classifyDomain`
  (923) + `_initialDomainRep` (952, where domains become reps — a continuous
  variable needs a different construction path since its input isn't a list),
  and the value-selection / branching loop inside `_BacktrackEngine`:
  `_pickVariable()` (the branch-variable chooser, called at solver.dart:2412,
  2470, 2607, ...) and the decision point where `_decisionLevel++` happens
  (line 1786). A continuous variable reaching `_pickVariable` must route to a
  bisection branch instead of value enumeration.
- `lib/src/problem.dart`: `_variables` (line 54) is `Map<String,List>` —
  continuous vars need a parallel `Map<String,Interval>` channel (recommended)
  or a boxed domain type. `addRangeVariable` (156) and the `CspProblem`
  construction inside `getSolution` (~309) / `_optimize` are the entry points
  to extend.
- The A1 solver (`lib/src/continuous.dart`) is the propagation/branching
  reference implementation — lift its `_propagate` and bisection into the
  engine's node loop.

**Plan (incremental, keep the suite green at each step).**
1. Land A1 first — it provides the tested interval-HC4 core to lift.
2. Add `Problem.addFloatVariable(name, lo, hi)` storing into a new
   `_floatDomains` map; thread it into `CspProblem`.
3. Add `_FloatIntervalRep` + `isContinuous` on `_DomainRep`; make every
   existing impl return `false`.
4. In the decision loop, branch continuous variables by bisection; treat
   width ≤ epsilon as assigned. Gate all of this behind "problem has ≥1 float
   var" so the pure-integer path is byte-for-byte unchanged (protect the 1223
   tests).
5. Add a mixed interval propagator for linear constraints spanning both
   kinds.
6. Extend `minimize`/`maximize` to continuous objectives (bisection toward
   the bound).

**Tests.** A dedicated `test/mixed_continuous_test.dart`; plus **run the full
existing suite after every step** — the pure-integer path must not regress.
Soundness sweeps for mixed linear models.

**Risk.** High — `_DomainRep` and the decision loop are hot, central code.
Mitigate with the "≥1 float var" gate so the integer path is untouched, and
by landing steps 2–6 as separate green commits.

**Effort.** Several sessions. This is the real strategic-gap closure.

### A3. Verified outward rounding (optional rigor)

Replace plain-double interval arithmetic with **outward-directed rounding**
so floating-point error can never discard a real solution (a returned box is
then a *proven* enclosure). Dart has no `fesetround`; emulate by nudging
results by one ULP (`nextafter` via bit manipulation on the double) after each
interval op. Scope this only if a user needs certified enclosures; the A1/A2
witness model is sufficient for most modelling. Anchor: every `Interval`
operator in `continuous.dart`.

---

## Item B — Incremental warm-starting

### B0. Where it stands

Shipped (2.3.0): `lib/src/incremental.dart` — `IncrementalSolver` gives the
retractable-assumption *interface* (push/pop scopes, `assume*` flavours) with
an exactness guarantee (assumptions layered on `base.copy()`; base never
mutated). But every `solve` rebuilds a fresh `CspProblem` and runs from
scratch — **no warm-start**. Goal: make a re-solve reuse the reasoning from
the previous solve.

> ✅ **DONE (strategy 1).** Shipped as `IncrementalSolver.prime()` +
> `solveWarm()` (`lib/src/incremental.dart`, `test/incremental_warmstart_test.dart`,
> 6 tests). Exactly the base-only-pool approach below: prime the base, cache
> its nogoods, import them into assumption-varying solves via `importClauses`
> (delivered once to avoid duplicate drains). Measured ~3.4× fewer decisions
> on a conflict-heavy 3-SAT base; SAT/UNSAT always agrees with a cold solve
> and every warm solution is validated against the base clauses. **Strategy 2
> (assumption-tagged clause reuse) is still open** — it needs the engine to
> expose the assumption literals in each learned clause. The design below is
> the record of what shipped and how to extend it.

### B1. The tractable path (reuse existing plumbing)

**Key realization.** The LCG engine already exposes both ends of clause
transfer, built for parallel clause sharing:
- **Export:** `solveWithLcg(onLearnedClause: (List<Atom> clause) {...})` —
  fires for every learned nogood (`lib/src/solver.dart:165`, consumed at
  2499 / 2646; this is what `ProofLog` already captures).
- **Import:** `solveWithLcg(importClauses: () => List<List<Atom>> )` — the
  engine drains these into its clause pool via `_drainImportedClauses`
  (`lib/src/solver.dart:3399`, using `_learnedClauseToSpec` at 2106).

So warm-starting does **not** require persisting engine state. It requires:
capture nogoods from solve N via `onLearnedClause`; feed the reusable subset
into solve N+1 via `importClauses`.

**The soundness caveat (critical — get this right).** A nogood learned
*while an assumption was active* may depend on that assumption and is only
valid under it. Reusing it after the assumption is retracted is **unsound**.
Two safe strategies, in order of preference:
1. **Base-only pool.** Learn once on the base problem with **no assumptions**
   (`IncrementalSolver` can do a "prime" solve of `base`), capture those
   nogoods — they are implied by the base constraints alone, hence valid
   under *any* assumptions — and import them into every subsequent
   assumption-varying solve. Simple and always sound.
2. **Assumption-tagged clauses.** Track which assumption literals appear in a
   learned clause; only reuse clauses that mention none of the
   currently-retracted assumptions. More reuse, more bookkeeping. Needs the
   engine to expose the assumption literals in each clause (it does not yet —
   would require threading assumption atoms through analysis).

Ship strategy 1 first; it is a clean, always-sound win.

### B2. Plan

1. Give `IncrementalSolver` an internal `ProofLog`-style clause cache. Add
   `warmStart: true` to its solve methods.
2. On first warm-start solve (or an explicit `prime()`), solve `base` alone
   via `solveWithLcg(onLearnedClause: cache.add)` and keep the nogoods.
3. On each subsequent solve, run the materialized (base + assumptions)
   problem via `solveWithLcg(importClauses: () => cache.clauses,
   onLearnedClause: cache.add)` — importing the base-derived nogoods and
   accumulating new base-only ones. **Only cache clauses from the base
   prime** for soundness under strategy 1; do not cache clauses learned once
   assumptions are present (they may be assumption-dependent) unless you
   implement strategy 2.
4. `materialize()` currently posts assumptions as predicate/string
   constraints; ensure the LCG path is used (assumptions that are unit bounds
   integrate cleanly as clauses).

**Tests.** `test/incremental_warmstart_test.dart`: assert (a) identical
solutions with and without warm-start (correctness), and (b) fewer decisions
/ learned clauses on the warm-started re-solve (`CSP.lastStats`) on a problem
hard enough that base nogoods help — e.g. a pigeonhole-CNF base with a
satisfiable assumption. **Correctness (a) is the gate; the speedup (b) is the
point but assert it loosely to avoid flakiness.**

**Risk.** Medium. The plumbing exists and is battle-tested (isolate clause
sharing). The only real hazard is the soundness caveat — strategy 1 sidesteps
it entirely. Verify with a sweep: for many random assumption sets, warm-start
and cold solve must agree on SAT/UNSAT and (for SAT) return valid solutions.

**Effort.** ~1–2 sessions.

### B3. Anchors recap

`lib/src/incremental.dart` (whole file — the wrapper to extend);
`lib/src/lcg/lcg.dart:42` (`solveWithLcg` signature with `onLearnedClause` +
`importClauses`); `lib/src/lcg/proof.dart` (`ProofLog` — reuse its clause
collection); `lib/src/solver.dart:3399` (`_drainImportedClauses`, the import
sink) and `:2106` (`_learnedClauseToSpec`, how an imported `List<Atom>`
becomes a live clause).

---

## Suggested order

1. ~~**A1** (non-linear continuous)~~ — ✅ done.
2. ~~**B1/B2** (warm-starting, strategy 1)~~ — ✅ done.
3. ~~**A2** (mixed int/float engine integration)~~ — ✅ done.
4. ~~**Products in the main engine**~~ — ✅ done.
   `Problem.addFloatProduct(p, a, b)` + `_FloatProductPropagator` behind
   a `floatProduct` tag, reusing the tested zero-aware `Interval.divide`.
   The determined-output question resolved to *two-tier branching* rather
   than skipping: product outputs are branched **last** (they are
   determined by their factors, and their intervals are typically the
   widest in the model) — **except** when the output is the objective,
   which must be branched eagerly in the improving direction or
   branch-and-bound loses its only source of guidance. That one exception
   is worth 227,607 decisions versus 21 on the rectangle-area model;
   both rules have regression tests.
5. **B strategy 2** (assumption-tagged clause reuse) — needs the engine
   to expose the assumption literals in each learned clause.
6. **A3** (verified rounding) — only on demand.

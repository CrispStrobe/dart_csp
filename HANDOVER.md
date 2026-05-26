# Handover — continuing work on `CrispStrobe/dart_csp`

You are picking up work on `CrispStrobe/dart_csp`, a pure-Dart
Constraint Satisfaction Problem solver. The library is post-clean-
room-rewrite (no derivative content); see `NOTICE`. The entire
PLAN.md tier 1 and tier 2 ship, plus most of tier 3 — only the
MiniZinc / FlatZinc / XCSP3 frontend remains. Tactical-wins
shipping has continued: Impact-Based Search (Refalo 2004) and
Last-Conflict reasoning (Lecoutre 2009) both landed in recent
sessions, with a companion five-way `bench(heuristic)`
comparison. The conflict-explanation strategic gap is now closed at the level
of user-facing helpers: two MUS algorithms (deletion-based, Bakker
et al. 1993 / Junker 2001; and QuickXplain, Junker 2004),
per-`addX`-call labels surfaced on `ConstraintRef.label` (every
primary helper + every constraint-posting set-variable helper +
`addSoftConstraint`), a `bench(explain)` section confirming the
textbook crossover (QX wins 4×–63× on small-k-large-n; deletion
wins ~1.6× when k ≈ n), and label support for set-variable and
soft-constraint helpers. The most recent landing is **a harder
UNSAT instance in `bench(heuristic)`** (pigeonhole 8-in-7) that
sharpens the dom/wdeg-vs-MRV signal (2.0× → 2.2× as size grows).
§6 has a small remaining set of items; **edge-finding for
`addCumulative` (Vilím 2007)** is the next natural pick — bigger
than the recent shipping cadence (~1-2 sessions) but well-scoped.

Your job is to pick **one** item, design it, implement it with
tests + docs, and ship it the same way every prior feature has
been shipped. Don't reinvent the conventions — the shape and
rigor of new work should match what's already in the repo.

---

## 1. Required reading (in this order)

1. **`PLAN.md`** — the roadmap. Recently restructured: the
   original three-tier plan (fundamental capability /
   competitive feature set / engineering polish) has effectively
   shipped and is now compressed into a "What shipped"
   retrospective at the bottom. The forward-looking sections are
   now **Strategic gaps** (multi-session: LCG / nogood learning,
   MiniZinc-FlatZinc-XCSP3 frontend, LNS, float variables,
   conflict explanation), **Tactical wins** (one-session items
   with proven value and an immediate benchmark signal: Impact-
   Based Search, Last-Conflict heuristic, strengthening the
   diff_n sweep, edge-finding for cumulative), and **Edge /
   workload-gated** (don't pick without specific motivation:
   SAC-2, VSIDS variants, k-dim diff_n, minimal-cause CBJ,
   per-variable watch lists full version, native FFI). The
   §6 ordering of this handover mirrors PLAN.md's ordering, so
   §6 is the entry point for picking a next item.
2. **`STABILITY.md`** — public-API stability tiers, semver policy,
   what's experimental, what's internal, and the known gotchas
   (single-static-slot `lastStats`, stream-stats-flush-on-completion,
   GAC bail-out work bound, bounded-latency `.timeout()`).
   `getSolutionWithActivity` / `CSP.solveWithActivity` and the
   `useVsids:` flag on the restart entry point are listed as part
   of the stable surface.
3. **`README.md`** — public API surface. Recently-added sections:
   "VSIDS-Style Variable Activity" (companion to dom/wdeg), "2D
   Non-Overlap (`diff_n`)" (describes the sweep propagator that
   shipped most recently), "Channelling Inverse Maps",
   "Symmetry-Breaking" (split into sequence + value subsections,
   with `addLexChain` and `addValuePrecedence`), "Conflict-Directed
   Backjumping (CBJ)", "Solving on a worker isolate",
   "Cancellation and Timeouts", "Set Variables", "Cumulative
   resource scheduling", "SAT-style clauses (`addClause`)". The
   "Sequencing & Packing" subsection covers `addCircuit`,
   `addSubcircuit`, and `addBinPacking`.
4. **`NOTICE`** — clean-room history; now MIT. Addendum lists the
   demo file as also covered by the clean-room scope.
5. **`CHANGELOG.md` "Unreleased"** — concise list of everything
   shipped since 2.1.0, newest entry first. Top of the list is
   **`bench(heuristic)` extended with pigeonhole 8-in-7** — one step
   up from the existing 7-in-6 entry; shows the dom/wdeg/MRV gap
   widening from 2.0× to 2.2× as problem size grows. Below that:
   **label support for set-variable and soft-constraint helpers** —
   the labels rollout now covers every constraint-posting
   set-variable helper plus `addSoftConstraint`. Below that:
   **`bench(explain)`** — new "conflict-explanation comparisons"
   section in `benchmark/benchmark.dart` running deletion vs
   QuickXplain side-by-side on seven problems spanning small-k-
   large-n to k≈n; confirms the textbook crossover. Below that:
   **per-`addX`-call labels for conflict explanation** — optional
   `label:` parameter on every primary constraint helper, surfaced
   on `ConstraintRef.label`. Below that: **QuickXplain MUS (Junker
   2004)** — `Problem.findMinimalUnsatisfiableSubsetQuickXplain`
   returning a `List<ConstraintRef>?`. Below that: **deletion-based
   MUS / conflict explanation** — `Problem.findMinimalUnsatisfiableSubset`
   returning a `List<ConstraintRef>?`. Below that: **Last-Conflict reasoning
   (Lecoutre 2009)**, a wrapper picker that composes with every
   primary heuristic, plus a companion `bench(heuristic)` five-way
   comparison section in `benchmark/benchmark.dart`. Below that:
   **Impact-Based Search (Refalo 2004)**, the third conflict-driven
   variable heuristic. Below that: the **forbidden-region sweep
   propagator for `addDiffN`** that superseded the prior pairwise
   decomposition, `ConsistencyLevel.singletonArcConsistency`,
   `addSubcircuit`, the VSIDS-style activity heuristic, `addDiffN`
   (decomposition-based — note the diff_n entry replaces this),
   `addLexChain`, `addInverse`, `addValuePrecedence`, and the
   per-variable clause seeding filter.
6. **`doc/`** — ten topical guides: algorithms, cancellation,
   cbj, conflict-explanation (new — deletion-based MUS, the
   ConstraintRef granularity table, open follow-ups),
   global-cardinality, heuristics (consolidated guide for the four
   conflict-driven pickers — dom/wdeg, VSIDS, IBS, LC — plus MRV
   baseline; added when the heuristic family reached four members),
   min-conflicts, multi-solutions, set-variables, string-constraints.
7. **`lib/src/`** — six source files; total ~9520 lines:
   * `types.dart` (~660 lines) — public types: `CancellationToken`,
     `BinaryConstraint`, `NaryConstraint` (with dispatch flags for
     `allDifferent`, `linearSpec`, `regularDfa`, `circuit`,
     `subcircuit`, `gccSpec`, `cumulativeSpec`, `clauseSpec`,
     `diffNSpec`), `CspProblem`, `SolverStats` (also `backjumps` /
     `backjumpLevelsSkipped`), `Dfa`, `LinearSpec`, `LinearOp`,
     `GccSpec`, `CumulativeSpec`, `ClauseSpec`, `DiffNSpec`,
     `ConsistencyLevel`, `ConstraintRef` (opaque ref returned by
     the MUS pass — equality by `id`, with `kind` and `variables`
     for human-readable output), typedefs.
   * `problem.dart` (~3290 lines) — `Problem` builder with every
     extension, including the `ConflictExplanation` extension which
     exposes two MUS algorithms (deletion-based and QuickXplain).
     Every primary constraint helper accepts an optional `label:`
     String for the conflict-explanation API. Every backtracking
     entry point accepts
     `consistency:`, `cancelToken:`, and
     `enableConflictBackjumping:` parameters; the heuristic-flavored
     entry points add the corresponding heuristic flag
     (`useDomWdeg:`, `useVsids:`, `useImpact:`, `useLastConflict:`)
     where it makes sense.
   * `builtin_constraints.dart` (~390 lines) — factory functions.
   * `constraint_parser.dart` (~858 lines) — string-constraint parser.
   * `solver.dart` (~4072 lines) — `CSP` static class,
     `_BacktrackEngine`, three `_DomainRep` impls (`_ListRep`,
     `_BitsetRep`, `_IntervalRep`), eight specialized propagators
     (`_AllDifferentPropagator`, `_LinearPropagator`,
     `_RegularPropagator`, `_CircuitPropagator` — serves both
     `circuit` and `subcircuit` via a `subcircuit: bool` flag,
     `_GccPropagator`, `_CumulativePropagator`,
     `_ClausePropagator`, `_DiffNPropagator`), the
     `_MinConflictsRunner`, `_TrailEntry` with constraint-cause
     attribution, sealed `_SearchResult` (with `_Solution`,
     `_Exhausted`, `_Backjump` variants) for CBJ, three CBJ search
     helpers (`_searchOneCbj`, `_searchAllCbj`, `_searchOptimalCbj`),
     `_checkpoint` (cooperative yield + cancellation poll), the
     `_clauseWatchers` side-table for the two-watched-literal scheme
     (also consulted by `seedFor` for the per-variable wake-up
     filter), the VSIDS bookkeeping (`_varActivity`, `_activityInc`,
     `_onConflict`, `_bumpActivityFor`, `_rescaleActivities`,
     `_pickByActivity`), the IBS bookkeeping (`_impactMean`,
     `_impactCount`, `_logProductDomains`, `_recordImpact`,
     `_observeImpact`, `_pickByImpact` — hooked into all six
     search variants at the decision site, taking precedence over
     VSIDS / dom-wdeg in `_pickVariable`), the Last-Conflict
     bookkeeping (single field `_lastConflictVar`, consulted by
     `_pickVariable` ahead of all four primary pickers; set in
     the propagation-failure path of all six search variants), and
     the SAC preprocessing pass (`_enforceSac`,
     `_seedAndPreprocess`) that the three search entry points
     (`findOne`, `findAll`, `findOptimal`) route through when
     `consistency == singletonArcConsistency`.
   * `isolate_runner.dart` (~458 lines) — `solveInIsolate`,
     `solveAllInIsolate`, `minimizeInIsolate`, `maximizeInIsolate`,
     `IsolateRunnerException`. Worker-isolate runner with builder-
     closure API, parent-side `CancellationToken` bridge via
     `addListener`, stats round-trip, and built-in `timeout:`.
8. **`test/`** — 37 files, 690 test cases. One file per feature
   area: `test/<feature>_test.dart`. The newest addition is
   `test/labels_test.dart` (24 cases — ConstraintRef.label default
   null; toString rendering with/without label; equality keyed by
   id only; label propagation through addConstraint binary +
   n-ary, addAllDifferent, linear, clauses, lex chain, addInverse
   decomposition, binary addAllEqual; forward+reverse pair sharing
   one label; both MUS algorithms surfacing labels identically;
   mixed labeled + unlabeled constraints; and the set/soft helper
   group — addSetCardinality, addSetCardinalityRange,
   addRequiredInSet + addExcludedFromSet, addSetEquals (per-element
   propagation), addSubset, addSetDisjoint, addSetUnion, and
   addSoftConstraint). Below that:
   `test/quickxplain_test.dart` (21 cases — satisfiability returns
   null on trivially sat / empty constraints / redundant-only;
   minimal UNSAT detection across binary, allDifferent, triangle,
   linear, mixed binary+n-ary, SAT clauses; minimality witness via
   reconstructed Problems; relation to deletion pass on unique-MUS
   and multi-MUS problems; SAC vs AC composition; no mutation of
   originating Problem; pre-cancelled and mid-recursion
   cancellation; binary forward+reverse pair as one ref; posting-
   order surface; 5-cycle 2-coloring larger conflict). Below that:
   `test/explain_test.dart` (21 cases — ConstraintRef equality /
   toString / unmodifiable variables; satisfiable returns null;
   empty + redundant-only satisfiable cases; singleton binary
   MUS; allDifferent pigeonhole; triangle 3-coloring with 2
   colors; redundant binary dropped from MUS; linear two-equation
   infeasibility; mixed binary + n-ary; SAT clauses; rebuild
   verifies soundness; minimality witness; consistency-level
   invariance; no mutation of the originating Problem;
   pre-cancelled + mid-loop cancellation; ref id scheme; binary
   forward+reverse pair surfaces as one ref). Below that:
   `test/last_conflict_test.dart` (18 cases — LC happy path,
   infeasibility, 8-queens regression, MRV agreement, composition
   with each primary picker (dom/wdeg, VSIDS, IBS) and with FC /
   SAC / CBJ / restarts, propagation engagement, zero-conflict
   fallback, LC + IBS together, decision-count sanity vs. MRV).
   Below that: `test/impact_test.dart` (16 cases), the "addDiffN
   sweep propagator" group (7 cases) inside
   `test/diffn_test.dart`, `test/sac_test.dart` (18 cases), the
   `addSubcircuit` group (19 cases) inside
   `test/circuit_and_bin_packing_test.dart`, and
   `test/vsids_test.dart` (12 cases).
9. **`benchmark/`** — `benchmark.dart` runs five sections:
   * **Plain BT vs CBJ** — 10 classic CSPs (n-queens scaling,
     magic-square, sudoku, map coloring, SEND+MORE both predicate
     and linear, pigeonhole CNF) side-by-side, single timed solve.
   * **Consistency-level comparisons (AC vs SAC)** — currently
     one entry on the canonical SAC-only infeasibility example.
   * **diff_n propagator comparisons (sweep vs decomposition)** —
     currently two entries (8-rectangle find-first, 5×(3×3)
     UNSAT-by-area) using a 5-rep warm-up + 25-rep median in
     microseconds. This is the canonical "perf-claim" methodology
     in this repo — single-shot cold timings on small problems
     are noisy. Mirror this shape for any future perf benchmark.
   * **Heuristic comparisons (MRV vs dom/wdeg vs VSIDS vs IBS vs
     LC+dom/wdeg)** — five-way head-to-head on six problems
     (magic-square 3x3, 12-queens, 16-queens, SEND+MORE linear,
     pigeonhole 7-in-6 UNSAT, pigeonhole 8-in-7 UNSAT). Same
     5-rep-warm-up + 25-rep-median methodology. The signal is in
     the UNSAT cases: dom/wdeg-based pickers beat MRV by 2.0× at
     7-in-6 and 2.2× at 8-in-7 (LC+dom/wdeg ≈ 565 ms vs MRV ≈
     1 061 ms). The gap widens with problem size as expected. On
     feasible-and-small problems all five are essentially
     equivalent — the heuristics matter on UNSAT and
     large-search-tree cases, not on easy n-queens instances.
   * **Conflict-explanation comparisons (deletion vs QuickXplain)** —
     seven entries spanning small-k-large-n to k≈n: singleton MUS
     + 10/50/200 redundants, triangle MUS + 10/50/200 redundants,
     pigeonhole CNF 5-in-4 (k = n = 45). Uses a smaller 3-rep
     warm-up + 9-rep median because each MUS run is itself many
     `CSP.solve` calls. Confirms the textbook crossover: QX wins
     4×–63× on small-k-large-n; deletion wins ~1.6× when k ≈ n.

   `problems.dart` holds the shared problem builders, imported by
   both the benchmark runner and `test/cbj_benchmarks_test.dart`
   (so a divergence shows up as a test failure, not a silent
   drift). Builders take an `{useSweep: bool}` style flag when
   the same problem needs two propagation shapes.

You do NOT need to read `git log` line-by-line. Commits are
well-titled (`<area>(<scope>): <one-line summary>`) so skim
`git log --oneline` to triangulate when needed.

---

## 2. Conventions you must follow

These are established by every commit and the test suite enforces
some of them. Don't deviate without a strong reason.

### Public API shape

- **All solver entry points return `Future<dynamic>` or
  `Stream<Map<String, dynamic>>`.** Failure is the literal string
  `'FAILURE'`, NOT null and NOT an exception. Callers gate with
  `if (result is Map<String, dynamic>) { ... }`.
- **`Problem` is the user-facing builder; `CSP` is the static
  solver entry point.** New methods go on `Problem` first
  (user-facing), with the heavy lifting in `CSP.*` or a private
  helper.
- **Extensions group related helpers.** Existing extensions on
  `Problem`: `BuiltinConstraints` (includes `addAllDifferent`,
  `addAllEqual`, sum/product/range, ordering, `addLexLeq`,
  `addLexLt`, `addLexChain`, `addValuePrecedence`),
  `StringConstraints`, `ProblemDebug`, `MultipleSolutions`,
  `ReifiedConstraints`, `LogicalConstraints`, `GlobalConstraints`
  (`addElement`, `addTable`, cardinality, `addCircuit`,
  `addBinPacking`, `addRegular`, `addInverse`, `addNoOverlap`,
  `addDiffN`, `addCumulative`), `LinearConstraints`,
  `SoftConstraints`, `SetVariables`. New feature areas get their
  own extension if they introduce a coherent group of methods.
- **Validation throws `ArgumentError`** with a message that names
  the offending variable/argument. Tests rely on this.
- **`lastStats` is a single static slot on `CSP`.** Shared across
  every `Problem` instance — a solve on one overwrites the most
  recent solve on any other. Tests comparing stats across two
  solves must capture `lastStats` immediately after each call.
- **Every backtracking entry point accepts the same three search-
  mode parameters**: `consistency: ConsistencyLevel`,
  `cancelToken: CancellationToken`, and
  `enableConflictBackjumping: bool`. Mirror this when adding a new
  backtracking entry point. The local-search and worker-isolate
  paths have their own conventions; check
  `solveWithMinConflicts` and `isolate_runner.dart` for those.

### Problem-level solution post-processing

Every `Problem`-level solve entry point routes its result through
`_wrapResult` (for `Future<dynamic>`) or `_wrapStream` (for
`Stream<Map<String, dynamic>>`), which calls `_materializeSets` on
each success map. This is a no-op when `_setVarUniverses` is empty
but it's the mechanism that lets `addSetVariable` surface set
variables as `Set<dynamic>` and strip indicator names. If you add a
new solve entry point on `Problem`, it MUST wrap through the same
helpers or set variables will leak their `__set__*` indicators.

### The arity-dispatch gotcha (still hot)

`Problem.addConstraint([v1, v2], pred)` dispatches by arity:

- 2 variables → expects `BinaryPredicate` (`bool Function(dynamic, dynamic)`); registers both directions for AC-3.
- 1 or 3+ variables → expects `NaryPredicate` (`bool Function(Map<String, dynamic>)`); registers as one `NaryConstraint`.

**If your helper is naturally an n-ary predicate but its variable
list might happen to be exactly 2 vars, use the private
`Problem._addNary(vars, predicate)` helper instead.** It bypasses
the binary dispatch and always registers as `NaryConstraint`.

**For helpers that need to set a dispatch flag on the
`NaryConstraint`** (`allDifferent`, `linearSpec`, `regularDfa`,
`circuit`, `gccSpec`, `cumulativeSpec`, `clauseSpec`), don't use
`_addNary` — it doesn't take spec fields. Construct the
`NaryConstraint` directly and append to `_naryConstraints`. See
`addAllDifferent`, `addRegular`, `addCircuit`, `addGcc`,
`addGccRanges`, `addCumulative`, `addClause`, the
`LinearConstraints` extension methods for examples.

### The tagged-constraint leaf-check gotcha (load-bearing)

Tagged constraints **bypass the generic `_reviseNary` path** in
the engine. This means **the constraint's soundness predicate is
NOT invoked at leaves** — soundness rides entirely on the
propagator catching every infeasible state.

Each propagator must detect a leaf state (every constraint
variable is a singleton) and report infeasibility correctly.
Patterns vary:

- The GCC propagator promotes a soft fallback to a hard `null`
  return when the matching is unique (`allSingleton`).
- The cumulative propagator relies on the standard pruning path:
  at a leaf, the profile equals the realized usage; any
  over-capacity step forces the lone feasible candidate out of
  some task's domain so the engine reports infeasibility from the
  resulting empty domain. No separate leaf check needed.
- The clause propagator's "all literals falsified" branch is the
  leaf detection — when every variable is singleton and every
  literal is false, the propagator returns `null`.

Mirror whichever pattern fits when designing a new specialized
propagator.

### Trail-based undo + the engine assumption to watch out for

The engine (`_BacktrackEngine` in `solver.dart`) maintains a
single append-only trail of `_TrailEntry { varName, oldRep, cause }`
records. **Every domain mutation must go through
`_setDomain(varName, newDom, {cause})`** (which takes a
`List<dynamic>`) or **`_setDomainRep(varName, newRep, {cause})`**
(which takes a `_DomainRep` directly). Both methods append a trail
entry, including the optional `cause` constraint (`BinaryConstraint`
for AC-3 revises; `NaryConstraint` for any GAC revise or
specialized propagator reduction; `null` for decision-site
assignments). The `cause` is only consulted by
`_conflictCauseFromTrail` when CBJ is on; off-CBJ runs ignore it.

When adding a new propagator or a new propagation path, pass
`cause:` matching the relevant constraint — otherwise CBJ's
chain-following loses precision on that path.

Backtrack is `_trailRollback(mark)` which undoes only what changed
since `mark`.

**Engine assumption** (relevant for any new search variant): when
`_propagate` is called, the engine assumes all current domains are
non-empty. `_reviseNary` treats a pre-existing empty domain as
"no change" rather than a wipeout — so anyone tightening domains
*outside* of propagation (e.g. the integrated B&B does this for
the objective variable) must either avoid creating pre-existing
empties or guard against them at the leaf. The integrated B&B
uses an `_optProven` flag and a top-of-search empty-domain guard;
mirror that pattern if you add a similar tightening mechanism.

### The conflict-bump convention (load-bearing for heuristics)

Whenever a propagation step detects infeasibility — a domain
wipeout in `_reviseBinary`, a `null` return from any specialized
propagator, an n-ary GAC revise that empties a domain — the
engine calls `_onConflict(c)` where `c` is the
`BinaryConstraint` or `NaryConstraint` whose enforcement just
failed. `_onConflict` delegates to **both** the dom/wdeg bump
(`_bumpWeight`) and the VSIDS activity bump
(`_bumpActivityFor`); each guards on its own flag, so a search
with neither heuristic on pays for nothing.

When adding a new specialized propagator, follow the existing
shape: `if (changedVars == null) { _onConflict(task.c); return
false; }` for the propagator-returned-null case, and the
mirrored `if (_domains[v]!.isEmpty) { _onConflict(task.c);
return false; }` inside the post-propagation cascade loop. Don't
add a parallel guarded `if (useVsids) ...` line — the helper
already handles both heuristics.

### Per-constraint side-table convention

Most specialized propagators are **stateless across calls** — they
reconstruct working state from scratch each `propagate()`
invocation. `_ClausePropagator` is the exception: it uses the
textbook two-watched-literal scheme and needs per-clause mutable
state. It reads/writes that state through a side-table on the
engine:

```dart
final Map<ClauseSpec, _ClauseWatchState> _clauseWatchers =
    HashMap(equals: identical, hashCode: identityHashCode);
```

**No trail-aware rollback is needed for this side-table.** Domain
reductions in the engine are monotone under the trail (backtrack
only restores previously-removed values), so a watcher pointing at
a non-falsified literal at a deeper assignment is also
non-falsified at any shallower one.

The same side-table is **also consulted by `_propagate.seedFor`**
for the per-variable wake-up filter.
Once a clause's watchers are set, the engine only enqueues the
clause when one of the two watched literals' variables is reduced.
Width-2 clauses bypass the filter (both literals always watched, so
the check would never fire and adding it would be pure overhead on
`at-most-one` pairwise workloads).

If you add another stateful propagator, follow the same pattern:
1. Add `final Map<<YourSpec>, _YourState> _yourSideTable = HashMap(equals: identical, hashCode: identityHashCode);` to `_BacktrackEngine`.
2. Pass it to your propagator's constructor at the dispatch site.
3. Verify your state is monotone under backtrack (same argument
   as watchers). If it's not, you'd need a trail entry for your
   state. None of the current propagators need this.

### Domain representation (three reps)

`_DomainRep` is an abstract class with **three** implementations,
chosen per-variable at engine construction by `_classifyDomain`:

- `_BitsetRep` — strictly-ascending list of `int` with span
  `max - min + 1` ≤ 1024. `Uint64List` + integer offset; O(1)
  membership, O(N/64) filter. **Stays bitset on filter.**
- `_IntervalRep` — contiguous-ascending `int` range with span
  `> 1024`. Stores just `(min, max)`; O(1) membership / length /
  bounds. `.filter(predicate)` stays as `_IntervalRep` when the
  kept set is still contiguous and promotes to `_BitsetRep` (if
  the new span fits) or `_ListRep` when the predicate creates
  interior holes.
- `_ListRep` — everything else (mixed types, non-monotonic int,
  non-contiguous int with span > 1024, strings, doubles).
  `List<dynamic>`; O(n) membership and filter.

Propagators read via the rep API: `.values`, `.length`, `.first`,
`.isEmpty`, `.isNotEmpty`, `.contains(v)`, `.filter(predicate)`,
`.asList`. They write via the rep-aware `applyUpdate(varName,
_DomainRep) -> void` callback (which the engine wires to
`_setDomainRep`).

### Test conventions

- One test file per feature area: `test/<feature>_test.dart`.
- Use `group()` for sub-areas; descriptive test names ("does X
  when Y", "throws on Z").
- Cover: happy path, edge cases, validation errors. For solvers,
  include at least one classic problem (queens / sudoku / map
  coloring / graph 3-coloring / RCPSP) as a regression.
- Use `await p.getAllSolutions()` (or manual stream-drain with
  `p.getSolutions()`) to verify enumeration count and per-solution
  invariants — much stronger than just checking the first
  solution.
- For new globals, write at least one test that asserts
  equivalence to an existing constraint (e.g. `addGcc` with each
  value count = 1 should enumerate the same solution set as
  `addAllDifferent`; `addCumulative` with cap=1 and all-dem=1
  should match `addNoOverlap`; `addDiffN` with all `heights=1`
  and `ys` pinned to 0 should match `addNoOverlap` on the x-axis).
- For new propagators, write at least one test asserting
  measurable propagator activity — usually
  `expect(p.lastStats!.naryRevises, greaterThan(0))` after a solve
  — so silent regressions to the predicate-only path get caught.
- For new heuristics, mirror the agreement-with-MRV test pattern
  (`test/dom_wdeg_test.dart`, `test/vsids_test.dart`) on a
  problem with a unique answer — same solution map regardless of
  picking order.
- When comparing stats across two solves, **capture `lastStats`
  immediately after each call** — the static slot gets overwritten
  by the second solve.
- **Dart Set identity-equality bites.** Two `Set<dynamic>{}` are
  not `==` even when they have the same elements. Convert to
  canonical string keys (e.g. sorted-element comma-join) — see
  `test/set_variables_test.dart`'s `key()` helper.
- **Lambda parameters in `addConstraint` need explicit `dynamic`
  type.** The analyzer's `inference_failure_on_untyped_parameter`
  warning fires otherwise. Write `(dynamic a, dynamic b) => a !=
  b` rather than `(a, b) => a != b`. Several existing tests use
  this pattern.

### Commit messages

Follow what's there. Pattern:

```
<area>(<scope>): <one-line summary>

<paragraph explaining the change and why>

<bullet points of API or behavior changes>

<test coverage summary with new total>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

`<area>` is one of: `feat`, `fix`, `solver`, `bench`, `docs`,
`chore`, `test`, `ci`, etc. `<scope>` is the feature area
(`reified`, `global`, `soft`, `engine`, `stats`, `set-vars`,
`logical`, `cbj`, `clause`, `symmetry`, `heuristic`, ...).

### Per-feature acceptance gate

Before each commit:

```bash
cd ~/code/dart_csp
dart format --output=none --set-exit-if-changed .   # zero changes
dart analyze --fatal-infos                          # zero issues
dart test                                           # zero failures
```

`dart analyze --fatal-infos` is strict — even info-level lints
fail it. Common gotchas: `prefer_single_quotes`,
`unnecessary_parenthesis`, `avoid_redundant_argument_values`,
`omit_local_variable_types` (use `const` for compile-time-known
locals), `unnecessary_brace_in_string_interps`,
`unnecessary_lambdas` (use tear-offs when possible),
`prefer_expression_function_bodies`,
`inference_failure_on_untyped_parameter` (annotate `dynamic`
explicitly on `addConstraint` lambdas),
`prefer_const_declarations`. Just fix them as they come up.

For intentional redundant arguments (e.g. tests that explicitly
pass the default value for symmetry), use a file-level
`// ignore_for_file: avoid_redundant_argument_values` near the
imports — see `test/consistency_level_test.dart`.

### README + PLAN.md + CHANGELOG + STABILITY.md per commit

Each feature commit also updates:

- **`PLAN.md`** — flip `[ ]` → `[x]` (or `[~]` if partial) and
  append a short description of what shipped, including test
  count. Be honest about scope limitations.
- **`README.md`** — add a new section (or subsection under an
  existing one) for any user-visible feature. Pattern: short
  prose intro, code example, table of methods if there are
  several.
- **`CHANGELOG.md`** — add an entry under `## Unreleased` (don't
  promote to a versioned heading; the maintainer decides when to
  cut a release).
- **`STABILITY.md`** — classify the new API as stable or
  experimental.

If the feature has non-trivial semantics or design decisions
worth documenting separately, add a `doc/<feature>.md` topical
guide and reference it from the README's "Documentation" section.

---

## 3. Repo layout

```
dart_csp/
├── lib/
│   ├── dart_csp.dart                # top-level export + convenience funcs
│   └── src/
│       ├── types.dart               # public types
│       ├── problem.dart             # Problem builder + every extension
│       ├── builtin_constraints.dart # factory functions
│       ├── constraint_parser.dart   # string parser
│       ├── solver.dart              # CSP, _BacktrackEngine, propagators,
│       │                            # min-conflicts runner, CBJ helpers,
│       │                            # VSIDS + IBS + LC bookkeeping
│       └── isolate_runner.dart      # worker-isolate runner
├── test/                            # 37 files, 690 tests
│   ├── dart_csp_test.dart
│   ├── builtin_and_parser_test.dart
│   ├── minconflicts_tests.dart
│   ├── multisolutions_tests.dart
│   ├── alldifferent_propagator_test.dart
│   ├── optimization_test.dart           # incl. integrated-B&B tests
│   ├── restart_test.dart
│   ├── dom_wdeg_test.dart
│   ├── vsids_test.dart                  # VSIDS-style activity heuristic
│   ├── impact_test.dart                 # Impact-Based Search (Refalo 2004)
│   ├── last_conflict_test.dart          # Last-Conflict reasoning (Lecoutre 2009)
│   ├── sac_test.dart                    # singleton-arc-consistency preprocessing
│   ├── symmetry_breaking_test.dart      # lex, lex chain, value precedence
│   ├── reified_constraints_test.dart
│   ├── logical_combinators_test.dart
│   ├── global_constraints_test.dart     # element, table, inverse
│   ├── global_cardinality_test.dart     # among, nvalue, gcc, GCC propagator
│   ├── circuit_and_bin_packing_test.dart # circuit propagator + bin_packing
│   ├── regular_constraint_test.dart     # regular + partial-state propagator
│   ├── diffn_test.dart                  # 2D rectangle non-overlap (diff_n)
│   ├── soft_constraints_test.dart
│   ├── stats_test.dart                  # stream + MC stats coverage
│   ├── consistency_level_test.dart      # FC ↔ AC
│   ├── linear_propagator_test.dart      # bounds-consistency linear
│   ├── bitset_domain_test.dart          # rep eligibility + correctness
│   ├── interval_variables_test.dart     # _IntervalRep + addRangeVariable + addNoOverlap
│   ├── set_variables_test.dart          # addSetVariable + helpers + materialization
│   ├── cumulative_test.dart             # addCumulative + time-table propagator
│   ├── clause_test.dart                 # addClause + unit propagation + watched-literal + seeding filter
│   ├── cancellation_test.dart           # CancellationToken + .timeout() integration
│   ├── isolate_runner_test.dart         # worker-isolate runner (@TestOn('vm'))
│   ├── demo_smoke_test.dart             # smoke test for example/demo.dart
│   ├── cbj_test.dart                    # CBJ wiring + equivalence + engagement
│   └── cbj_benchmarks_test.dart         # real tests on every benchmark scenario
├── example/                         # demo + per-API walkthroughs
├── benchmark/
│   ├── benchmark.dart               # 10 classic CSPs, plain + CBJ side-by-side
│   └── problems.dart                # shared builders (imported by tests too)
├── doc/                             # 8 topical guides
│   ├── algorithms.md
│   ├── cancellation.md
│   ├── cbj.md
│   ├── global-cardinality.md
│   ├── min-conflicts.md
│   ├── multi-solutions.md
│   ├── set-variables.md
│   └── string-constraints.md
├── PLAN.md                          # roadmap (keep current)
├── STABILITY.md                     # API stability tiers + semver policy
├── NOTICE                           # licensing history
├── HANDOVER.md                      # this file
├── CHANGELOG.md                     # version history
├── README.md                        # public docs
├── LICENSE                          # MIT
└── .github/workflows/ci.yml         # CI
```

Remote: `https://github.com/CrispStrobe/dart_csp`. Default branch
`main`. CI runs format / analyze / tests / pana / examples /
benchmark on push.

---

## 4. The dispatch / extension pattern for new features

Most prior tier-2 work follows the same structure. To add a new
constraint helper, expect to touch:

1. **`lib/src/types.dart`** (optional) — if the constraint needs a
   new dispatch flag on `NaryConstraint`, add the value type and
   the field here.
2. **`lib/src/builtin_constraints.dart`** (optional) — if your
   feature introduces a new constraint factory.
3. **`lib/src/problem.dart`** — add a new extension `MyFeature on
   Problem` near the end of the file, alongside the others. Use
   `_addNary` for n-ary predicates without dispatch flags;
   construct `NaryConstraint` directly when you need to set a flag.
4. **`lib/src/solver.dart`** (only if needed) — only touch if the
   feature requires propagation changes, new heuristics, or new
   solver entry points. For a new specialized propagator: add the
   propagator class near the other `_*Propagator` classes; add a
   dispatch branch in `seedFor` (single canonical task per
   constraint) and in `_propagate`'s n-ary task branch; **pass
   `cause: task.c` through the `_setDomainRep` wrapper** so CBJ's
   chain-following works on your propagator; on every failure
   path **call `_onConflict(task.c)`** so the dom/wdeg and VSIDS
   bumps both fire if their respective flags are on; mirror the
   shape of the existing seven. Remember the leaf-check gotcha.
5. **`test/<feature>_test.dart`** — full coverage (see test
   conventions in §2).
6. **`README.md`** — new section or subsection.
7. **`PLAN.md`** — flip the item.
8. **`CHANGELOG.md`** — `## Unreleased` entry.
9. **`STABILITY.md`** — classify the new API.
10. **`doc/<feature>.md`** (optional) — for substantial features.

---

## 5. Useful patterns from the existing code

- **Optional flags on engine constructor.** When adding solver-
  mode variants (restarts, dom/wdeg, VSIDS, consistency level,
  CBJ), thread an optional parameter through `CSP.solve*` to
  `_BacktrackEngine(csp, …)`. Don't duplicate engine logic.
- **One method per arity dispatch.** When adding a public helper
  that registers a constraint, route through `addConstraint` for
  binary fast-path when possible, fall through to `_addNary`
  (or direct `_naryConstraints.add` for tagged constraints) when
  the predicate is naturally n-ary.
- **Auto-add boolean variables.** The `ReifiedConstraints`
  extension auto-adds the result bool var with domain `[0, 1]` if
  the user hasn't already added it. Mirror this for any new helper
  that produces a derived variable.
- **Integrated branch-and-bound vs copy-on-optimize.** The
  integrated B&B does NOT copy — it runs directly on the user's
  `CspProblem` but only mutates the engine's internal `_domains`
  and `_trail`, never the user's variable map. Any new
  search-with-augmentation should follow the integrated pattern
  but preserve the "don't mutate the original" invariant tested
  by `test/optimization_test.dart`. **`Problem.copy()` propagates
  the set-variable registry** — if you add new Problem-level state
  in another extension, propagate it in `copy()` too or
  `maximizeSatisfaction` (which copies internally) will lose it.
- **Count-variable + fixed-k twin form** for new helpers that count
  something. See `addAmong` + `addAmongExactly`, `addNvalue` +
  `addNvalueExactly`, `addSetCardinality` + `addSetCardinalityVar`.
  The variable form lets users compose with `minimize`/`maximize`;
  the fixed-k form is the clean common case.
- **Predicate + tagged-flag pattern for new globals.** Keep the
  soundness predicate (for the engine's generic paths even though
  tagged constraints bypass it) AND set the dispatch flag.
  Soundness depends on the propagator's leaf-check alone for
  tagged constraints, but the predicate stays as belt and braces.
- **Conservative-at-non-leaf, strict-at-leaf pattern** for partial
  GAC. When a propagator can't prove infeasibility from its
  matching but the matching is unique at a leaf, promote the soft
  fallback to a strict `null` return. The GCC propagator
  demonstrates this — it's load-bearing for soundness.
- **Decomposition-into-existing-primitives pattern.** Used heavily
  for new helpers without dedicated propagators:
  * Set variables decompose into per-element 0/1 indicators.
  * `addInverse` decomposes into n² binary
    `(forward[i] == j) ⇔ (inverse[j] == i)` constraints.
  * `addDiffN` decomposes into n(n-1)/2 4-ary disjunction
    predicates over `(xs[i], ys[i], xs[j], ys[j])`.
  * `addLexChain` decomposes into k-1 consecutive lex-leq pairs.
  Dedicated propagation pays off enough that the time-table
  cumulative version is worth it; for "purely syntactic" features
  decomposition is the right starting point and lets you skip the
  propagator entirely. Add a follow-up note in PLAN.md / the
  helper's docstring if a specialized propagator would be a
  natural next step.
- **Partial-assignment-aware predicate pattern.** Predicates that
  may be called during n-ary GAC support search with one or more
  vars unassigned should return `true` (no violation yet) rather
  than `false`. Examples: `lexLeq`, `lexLt`, `valuePrecedence`,
  the diffn 4-ary disjunction. The engine's leaf check or later
  support searches will catch real violations once the relevant
  vars become singleton.
- **Solution post-processing on Problem.** The `_materializeSets`
  / `_wrapResult` / `_wrapStream` helpers on `Problem` rewrite
  solver-returned maps before they hit user code. New
  Problem-level features that need to expose derived values rather
  than raw internal vars should follow the same pattern.
- **CBJ search structure.** Search uses a sealed `_SearchResult`
  (`_Solution`, `_Exhausted`, `_Backjump(targetDepth, conflict)`)
  for the single-solution helper, plus engine-state-bag slots
  (`_pendingBackjumpDepth`, `_pendingBackjumpConflict`) for the
  streaming and optimization helpers (async generators and
  `Future<void>` can't return a value). If you add a CBJ-friendly
  entry point, follow whichever pattern matches your return type.
- **Per-variable propagator seeding filter** (clause propagator).
  When a propagator's internal state lets you know which variables
  "matter" for its current work, consider filtering wake-ups in
  `seedFor` rather than waking the propagator on every scope
  variable's change. The clause case needed a width-2 carve-out
  because for narrow clauses the per-call check overhead
  dominated the skip savings — measure before committing to a
  filter on similar grounds for other propagators.
- **Conflict-driven heuristic state via `_onConflict(c)`.** The
  single helper handles every flag-gated bump (dom/wdeg's
  per-constraint weight and VSIDS's per-variable activity); call
  sites in `_propagate` use one line — `_onConflict(task.c)` (or
  `_onConflict(arc)`) — at every failure path instead of N
  `if (useX) bumpX(...)` lines.
  If you add a third conflict-driven heuristic, add the bump
  method and wire it into `_onConflict`; don't add parallel
  per-site checks.
- **MiniSat-style multiplicatively-grown bump.** VSIDS's
  `_activityInc` grows by `1 / decay` per conflict instead of
  applying a per-conflict O(|vars|) decay sweep. Equivalent
  ranking, O(1) per conflict. Rescale (`_activityInc * 1e-100`
  on every variable, plus the increment itself) when the
  increment hits `1e100` to prevent overflow — mirrored for any
  similar growing-bump heuristic.
- **Heuristic picker fallback shape.** `_pickByActivity` returns
  `dom / (1 + activity)`, which reduces to plain MRV when every
  activity is zero — pre-conflict the heuristic is indistinguishable
  from MRV, post-conflict it gravitates toward "guilty" variables.
  Same `+ 1`-in-denominator trick keeps the picker well-defined
  on the absent-key path. Mirror this for any new heuristic where
  the per-variable score might start at zero.
- **Worker-isolate runner.** Builder closure runs inside the worker
  (predicate closures attached to a constructed `Problem` aren't
  generally sendable). `_spawn` owns the single `ReceivePort`
  listener; callers plug in via an `onMessage` callback. Parent-
  side cancellation forwards through `CancellationToken.addListener`
  to a `'cancel'` message on the worker's control port. Wire
  protocol (`['ready', port]`, `['result', val]`, `['stats',
  SolverStats]`, `['solution', map]`, `['done']`, `['error', msg,
  stack]`) is private to `lib/src/isolate_runner.dart`.

---

## 6. What's left in PLAN.md, and how to pick

As of this handover, every well-scoped one-session item that was
on the original PLAN.md roadmap has shipped except the
MiniZinc / FlatZinc / XCSP3 frontend (multi-day; tier 3). The
recent shipping cadence has been ~one feature per session,
landing as a feature commit immediately followed by a handover
refresh commit. The latest features (newest first):

- **`bench(heuristic)` extended with pigeonhole 8-in-7.** One
  step up from the existing 7-in-6 entry. Confirms the dom/wdeg
  family's advantage over MRV widens with problem size: MRV/dom-
  wdeg ratio 1.85× at 7-in-6 → 2.22× at 8-in-7; LC+dom/wdeg ≈
  565 ms vs MRV ≈ 1 061 ms. Same five-way comparison structure;
  no code changes outside `benchmark/`. 9-in-8 and 20-queens were
  tried but excluded — 9-in-8 took ~13 min for the row across
  reps and heuristics; 20-queens showed no signal (all five
  heuristics within 18-35 µs).

- **Label support for set-variable and soft-constraint helpers.**
  Finishes the per-`addX`-call labels rollout. Every set-variable
  constraint helper (`addSetCardinality` / `Range` / `Var`,
  `addRequiredInSet`, `addExcludedFromSet`, `addSubset`,
  `addSetEquals`, `addSetDisjoint`, `addSetUnion` /
  `Intersection` / `Difference`) and `addSoftConstraint` now accept
  an optional `label:` that propagates to every decomposed
  constraint they post. `addSetVariable`, `addSetVariables`, and
  `declareSoft` intentionally don't accept `label:` because they
  don't post constraints (they declare indicator variables or mark
  a bool var as soft). 8 new tests in `test/labels_test.dart`;
  690 total. Updates `doc/conflict-explanation.md` "Labeling
  constraints" section to document the new helpers (replaces the
  prior "What's not labeled" caveat). STABILITY.md classification
  updated to reflect the broader coverage and to mark the
  no-label-for-declarations gap as intentional rather than
  provisional. Closes the conflict-explanation strategic gap at the
  level of user-facing helpers — only the deeper investigations
  (explanation-aware propagators, MSS, MARCO) remain.

- **`bench(explain)` — deletion vs QuickXplain comparison.** New
  "conflict-explanation comparisons" section in
  `benchmark/benchmark.dart` runs both MUS algorithms side-by-side
  on seven problems spanning the small-k-large-n / k≈n axis:
  singleton MUS + 10/50/200 redundants, triangle MUS + 10/50/200
  redundants, pigeonhole CNF 5-in-4 (k = n = 45). Two new builders
  in `benchmark/problems.dart` for the scaling sweeps
  (`buildExplainSingletonMus({n})` and
  `buildExplainTriangleMus({n})`). Uses a smaller 3-rep warm-up +
  9-rep median than the other comparative benches because each
  MUS run is itself many `CSP.solve` calls. Confirms the textbook
  crossover: QX wins 4×–63× on small-k-large-n (its
  O(k · log(n / k)) advantage); deletion wins ~1.6× when k = n (its
  O(n) cost is comparable with no recursion overhead); on n = 11
  with k = 1 deletion is marginally faster — QX's small-instance
  recursion overhead doesn't amortize. No code changes outside
  `benchmark/`. Test count unchanged at 682. Updates
  `doc/conflict-explanation.md` with a bench-result table under
  the "Which algorithm to call?" guidance.

- **Per-`addX`-call labels for conflict explanation.** Shipped as
  an optional `label: String?` parameter on every primary constraint
  helper on `Problem` (forty-odd `addX` methods covering binary +
  n-ary `addConstraint`, every `addAllX` / `addLexX` / `addLinearX`,
  `addClause`, `addInverse`, every reified, atLeast/Most/Exactly,
  every global). The label is stored on the underlying
  `BinaryConstraint` / `NaryConstraint` (new `label:` field on both)
  and surfaced on a new `ConstraintRef.label` field by both MUS
  algorithms. `ConstraintRef.toString` now renders
  `kind[label](variables)` when the label is set,
  `kind(variables)` otherwise. Equality on `ConstraintRef` remains
  keyed by `id` alone — the label is for display, not deduplication.
  Decomposed helpers propagate the label to every piece: `addInverse`
  attaches it to all n² channelling binaries, `addLexChain` to each
  pairwise lex-leq, `addValuePrecedence` to each consecutive-value
  n-ary, binary `addAllEqual` to the directed pair. Forward + reverse
  arcs of a binary `addConstraint` share one label (and surface as
  one ref). Set-variable and soft-constraint helpers don't yet
  accept `label:` — scope choice for the first cut, called out as a
  follow-up in `doc/conflict-explanation.md`. Backwards-compatible:
  `label:` defaults to null. 16 new tests in `test/labels_test.dart`.
  682 total tests. Updates `doc/conflict-explanation.md` with a
  "Labeling constraints" section and a propagation-through-decomposed-
  helpers table, README with a labeled example, STABILITY.md to
  classify the new field, and PLAN.md (per-`addX` labels flipped to
  shipped, removed from the strategic-gap follow-ups list).

- **QuickXplain MUS (Junker 2004).** Shipped as
  `Problem.findMinimalUnsatisfiableSubsetQuickXplain({cancelToken,
  consistency})` in the same `ConflictExplanation` extension as the
  deletion-based pass, returning a `List<ConstraintRef>?` with the
  same shape and granularity. The algorithm is divide-and-conquer
  (Junker 2004 — AAAI): split the candidate set in half, recurse on
  each half against a growing background of "already known to be in
  the MUS" constraints, short-circuiting whenever the background
  alone is unsat. O(k · log(n / k)) calls to `CSP.solve` where n is
  the candidate count and k is the MUS size — dramatically less than
  the deletion pass's O(n) for small-k-large-n models, comparable
  for k ≈ n. Both algorithms identify locally-minimal MUSes; they
  may surface different MUSes for the same problem (smallest MUS is
  NP-hard). Cancellation semantics differ: QX's recursion has no
  sound mid-flight kept set, so any cancellation returns `null` —
  use the deletion pass when you need "sound but possibly
  non-minimal" mid-loop semantics. 21 new tests in
  `test/quickxplain_test.dart`. 666 total tests. Updates
  `doc/conflict-explanation.md` with a per-algorithm section and a
  "which algorithm to call" guidance row in the TL;DR.

- **Deletion-based MUS / conflict explanation.** Shipped as
  `Problem.findMinimalUnsatisfiableSubset({cancelToken, consistency})`
  in a new `ConflictExplanation` extension on `Problem`. Returns a
  `List<ConstraintRef>?` — `null` if the problem has a solution, the
  MUS otherwise. The MUS is *locally* minimal in the deletion sense
  (removing any one of its constraints yields a satisfiable subset)
  but not necessarily the smallest UNSAT subset (that's NP-hard).
  Algorithm: textbook deletion-based MUS (Bakker et al. 1993, Junker
  2001) — O(n) calls to `CSP.solve`. Step-1 cancellation returns
  null; step-2 cancellation returns the current kept set (sound but
  not minimal). New public type `ConstraintRef` (in `types.dart`)
  carries `id` / `kind` / `variables`; equality by id. Forward +
  reverse directions of a single user-level `addConstraint` call
  share one ref. Kind label derives from the dispatch flag on the
  underlying constraint (`binary` / `predicate` / `allDifferent` /
  `linearEquals` / `linearLeq` / `linearGeq` / `regular` / `circuit`
  / `subcircuit` / `gcc` / `cumulative` / `clause` / `diffN`).
  Granularity is "what's stored after helpers run, not what the
  user-facing call looks like" — decomposed helpers (`addInverse`,
  `addLexChain`, set variables) surface as the resulting pieces.
  21 new tests; 645 total. New topical guide
  `doc/conflict-explanation.md` (tenth) with the granularity
  table and open follow-ups.

- **Last-Conflict reasoning (Lecoutre 2009 — "Reasoning from last
  conflict(s) in constraint programming", AI 173)** — wrapper
  picker that composes with every primary heuristic (MRV /
  dom-wdeg / VSIDS / IBS). On every propagation failure, the
  engine records the variable being pinned (single field
  `_lastConflictVar`); on the next `_pickVariable` call, if that
  variable is still unassigned the picker returns it directly.
  When the recorded variable becomes assigned (via propagation or
  via decision pin), the picker falls through to the configured
  underlying picker. Public API: `getSolutionWithLastConflict
  ({useDomWdeg, useVsids, useImpact, ...})`,
  `CSP.solveWithLastConflict`, `useLastConflict:` on
  `solveWithRestarts`. Wired into all six search variants at the
  propagation-failure path (one line each). SAC intentionally
  NOT instrumented — LC is for search, not preprocessing. A new
  `bench(heuristic)` section in `benchmark/benchmark.dart` runs
  five-way head-to-head comparisons; the signal is in UNSAT and
  large-search-tree cases.

- **Impact-Based Search (Refalo 2004 — "Impact-Based Search
  Strategies for Constraint Programming", CP 2004)** — third
  conflict-driven variable heuristic, sibling to dom/wdeg and
  VSIDS. Measures the impact of each `(variable, value)` decision
  as `1 - exp(logP_after - logP_before)` (clamped to `[0, 1]`,
  with `1.0` on failed propagation), tracked as a per-pair
  running mean. Picker minimizes `dom_size / (1 + Σ_a I(v, a))` —
  MRV pre-observation, IBS-biased post-observation. Wired into
  all six search variants. Public API: `getSolutionWithImpact`,
  `CSP.solveWithImpact`, `useImpact:` on `solveWithRestarts`.
  IBS takes precedence over VSIDS / dom-wdeg in `_pickVariable`
  when set; the other heuristics' bump tables keep updating so
  the picker choice is independent of which conflicts were
  observed.

- **Forbidden-region sweep propagator for `addDiffN`** (Beldiceanu
  & Carlsson, "Sweep as a generic pruning technique applied to
  the non-overlapping rectangles constraint", CP 2001) — promoted
  the prior decomposition-based diff_n to a single tagged
  `NaryConstraint` with a `DiffNSpec` carrying widths and heights,
  dispatching to a new `_DiffNPropagator`. A companion bench
  (`bench(diff_n)`) measures the sweep vs the prior pairwise
  decomposition on a find-first and an UNSAT instance with 5-rep
  warm-up + 25-rep median methodology — the canonical perf-claim
  shape in this repo.
- **`ConsistencyLevel.singletonArcConsistency`** (Debruyne &
  Bessière 1997 SAC-1) — preprocessing pass at the top of search,
  on top of the existing `consistency:` parameter.
- **`addSubcircuit`** — variant of `addCircuit` permitting
  self-loops as "skip" markers; shares the existing
  cycle-detection propagator via a new dispatch flag.
- **VSIDS-style activity heuristic** — `getSolutionWithActivity`
  and `useVsids:` on the restart entry point.
- **Per-variable clause seeding filter** — skips clause wake-ups
  on variables whose values can't change either watcher.

A real bench finding from the most recent session: on UNSAT
diff_n problems, the **sweep is per-call cheaper but per-decision
weaker** than the prior pairwise decomposition's GAC support
search. The bench shows the sweep taking ~2.2× more search than
the decomposition (189 vs 85 decisions on the 5×(3×3)-in-6×6
UNSAT case), yet still winning wall-clock by ~2× because the
per-call cost gap dominates. This is an honest perf-vs-pruning
tradeoff worth knowing — see §6 "Strengthen diff_n sweep with
per-pair partial-GAC pruning" for the natural follow-up.

### What to pick

The categories below mirror PLAN.md's structure. PLAN.md has the
full per-item rationale; this section is the picking guide.

**Strategic gaps** — multi-session items that change what kind
of solver `dart_csp` is. Pick deliberately, not opportunistically.

- *Lazy Clause Generation / nogood learning* — the biggest
  strategic gap. The line between hobby-grade and competitive
  CP. 4-6 sessions of focused work.
- *MiniZinc / FlatZinc / XCSP3 frontend* — ecosystem table-stakes.
  No head-to-head benchmarking without it. 2-4 sessions; no
  algorithmic invention, mostly parser + lowering work.
- *Large Neighborhood Search (LNS)* — industrial-scale
  optimization. Multi-day; design cost is in the destroy policies.
- *Float / real variables* — limits applicability to discrete
  problems. Multi-session; precision-vs-soundness questions are
  the real design cost.
- *Conflict explanation follow-ups*. The first cut shipped
  (deletion-based MUS) and QuickXplain (Junker 2004) shipped in the
  next session. The remaining work is incremental — each follow-up
  is a one-session item, not a strategic gap any more:
  (a) **Per-`addX`-call labels** — optional `label:` parameter on
  every constraint helper, surfaced on `ConstraintRef.label`. Lets
  users see "max-load" or "no-double-shift" in the MUS output
  instead of `b17` / `n4`. ~1 session if scoped to the common
  helpers; (b) **MSS / maximal satisfiable subset** — the dual of
  MUS, useful when the user wants to know what they *can* satisfy.
  ~1 session; (c) **Multiple MUSes (MARCO)** — enumerate distinct
  MUSes for a model with several disjoint conflicts. Multi-session.

**Tactical wins** — one-session items with proven value and an
immediate before/after signal:
- *Edge-finding propagator for `addCumulative` (Vilím 2007)* —
  substantial but well-scoped (1-2 sessions). Take on for the
  RCPSP-style workloads where the current time-table propagator
  leaves pruning on the table. Companion `bench(cumulative)` shape
  would mirror the existing `bench(diff_n)` 5-rep warm-up + 25-rep
  median methodology.

**Investigated and ruled out** — the diff_n sweep "strengthening"
listed in earlier handovers is **not pursuable** as written.
`bench(diff_n)` shows the sweep doing 2.2× more search than the
decomposition on UNSAT (189 vs 85 decisions on the 5×(3×3)-in-6×6
case), but a direct analysis of the predicate shows bounds-
consistency (what the sweep does via compulsory-part rules) is
provably equivalent to full GAC (what the decomposition does via
`_reviseNary`'s tuple iteration) for monotone disjunctions like
the 4-ary non-overlap predicate. The 100-decision gap is real
but comes from propagation-queue ordering effects, not from a
pruning-power gap that a per-pair partial-GAC pass could close.
A failed attempt to "iterate the sweep to fixed point within a
single `propagate()` call" produced zero change in decision
count, confirming that the engine's re-wake mechanism is already
finding the same fixed point. If a future session wants to
revisit this, the next angle to investigate is the
`_gacWorkBound` interaction or the multi-constraint propagation
order — but neither has an obvious clean fix. Don't list this
under tactical wins until/unless a new angle surfaces.

**Edge / workload-gated** — don't pick without specific
motivation. PLAN.md lists each item with the reason it's gated:

- SAC-2 / SAC-OPT
- VSIDS variants (pure-activity picker, bump-on-decision)
- k-dimensional `addDiffN`
- Minimal-cause conflict analysis for CBJ
- Per-variable watch lists for the clause propagator (full
  version)
- Native FFI to OR-Tools / Choco (would close most strategic
  gaps overnight but becomes a different project)

### Picking criteria

Within a tier, the right item is the one with the best fit
between:

- **User value** — how often it gets reached for in real CSP
  modeling.
- **Self-contained scope** — doesn't pull in other unfinished
  work.
- **Size match to one session** — if you can ship it in ~1000
  LOC including tests, prefer it over a multi-day project.
- **Honest assessment of the design risk** — Tactical wins are
  all well-bounded; the Strategic gaps are not.

### Recommendation

With the conflict-explanation gap closed and the heuristic bench
extended, the next sensible pick is the **edge-finding propagator
for `addCumulative` (Vilím 2007)**. It's bigger than the recent
shipping cadence (~1-2 sessions) but well-scoped: extend
`_CumulativePropagator` with the standard edge-finding pruning
rule, gate it behind a flag (or make it the default and keep
time-table-only as a knob), and add a `bench(cumulative)` section
mirroring the existing `bench(diff_n)` 5-rep warm-up + 25-rep
median methodology. Substantial work, but the algorithm is
textbook and the propagator infrastructure already handles tagged
constraints, leaf checks, and CBJ attribution.

Other reasonable picks:
- **MiniZinc / FlatZinc frontend** is the highest-leverage
  strategic gap overall (~2-4 sessions) and the only path to
  head-to-head benchmarking against every other CP solver, but
  it's a multi-day project and shouldn't be cut up.
- **Lazy Clause Generation / nogood learning** — the single
  biggest strategic gap (4-6 sessions). Pick deliberately, not
  opportunistically.
- *Conflict-explanation deeper investigations* (explanation-aware
  propagators, MSS, MARCO) — multi-session each; pick only when a
  specific user need surfaces.

---

## 7. What NOT to do

- **Don't touch the licensing posture.** `LICENSE` is MIT, `NOTICE`
  documents the history, the clean-room status is established.
  Leave it.
- **Don't read `dartCSP-archive`.** It's the now-private
  predecessor repo. Everything you need is in this repo.
- **Don't refactor existing features for cosmetics.** If you find
  something genuinely wrong, fix it — but don't reshape working
  code without a behavioral reason.
- **Don't introduce new dependencies** without a strong reason.
  The whole library is pure Dart, zero deps, and that's a
  feature.
- **Don't change the failure-literal convention** (`'FAILURE'`) or
  the return types of existing solve entry points. Tests rely on
  these and so does the existing user surface.
- **Don't bypass `_setDomain` / `_setDomainRep`** for any domain
  mutation in the engine. The trail relies on every mutation
  routing through them. The integrated B&B's
  `_tightenObjectiveDomain` is the one exception (it modifies
  past trail entries in-place); mirror that pattern only if you
  need the same semantics.
- **Don't omit `cause:` on `_setDomain` / `_setDomainRep`** calls
  inside propagators. The trail entry's `cause` field is what CBJ
  uses to attribute conflicts; missing it leaves CBJ unable to
  follow chains through your new propagator. Decision-site calls
  in the search loops correctly omit `cause:` (defaults to null).
- **Don't bypass `_onConflict(c)`** on a new propagator's failure
  paths. Adding a flag-guarded `if (useX) bumpX(...)` next to it
  is the wrong shape — the helper exists precisely so new
  conflict-driven heuristics (or new bumps for existing ones) can
  be added in one place. If you need a third bump kind, extend
  `_onConflict` itself.
- **Don't claim a tagged constraint is sound without a leaf
  check.** Tagged constraints bypass the engine's `_reviseNary`
  path, so the predicate is never called at leaves. Every
  specialized propagator must detect leaf states and verify the
  constraint there.
- **Don't bypass `_wrapResult` / `_wrapStream`** on a new
  Problem-level solve entry point. Skipping them means set
  variables leak their internal `__set__*` indicator names into
  user-facing solution maps.
- **Don't assert across `lastStats` reads on two different
  solves** without capturing the value between them. The static
  slot is shared.
- **Don't compare `Set<dynamic>` instances with `==`** — Dart's
  default is identity equality. Tests must compare by canonical
  string keys or unordered-iterable matchers.
- **Don't expose `_TrailEntry`, `_SearchResult`, the worker-
  isolate wire protocol, `_ClauseWatchState`, or the VSIDS
  internals (`_varActivity`, `_activityInc`)** in the public API.
  They're file-private on purpose. If you need to extend
  search-result semantics, add a new variant to `_SearchResult`
  rather than changing the exported signature of
  `Problem.getSolution`.
- **Don't add CBJ support to `solveWithMinConflicts`** — local
  search has no backtracking surface to attach to. The parameter
  is intentionally not on that entry point; the type system
  prevents the mistake.
- **Don't add `useVsids` / `useDomWdeg` to
  `solveWithMinConflicts`** — same reasoning: the local-search
  runner has no decision tree for the heuristic to steer.
- **Don't wrap worker-isolate solves in `.timeout()`** unless you
  actually want the worker to keep running after the deadline.
  Use the runner's built-in `timeout:` parameter — it sends a
  cancel signal, waits a brief grace window, then hard-kills the
  isolate.
- **Don't measure perf without a JIT warm-up loop.** A prior
  session's first attempt at measuring the clause-seeding filter
  produced misleading results because the benchmark runner ran
  each problem cold once. The honest measurement used a 25-rep
  median after a 5-rep warm-up. If you ship a perf change,
  measure with `benchmark/bench_*` (warm-up + reps) or write a
  short throwaway harness that does the same.

---

## 8. Working procedure

1. Read §1's required reading.
2. Pick one item from §6.
3. Open a `TaskCreate` to track it.
4. Implement following §2 conventions.
5. After each major change, run the acceptance gate (§2):
   `dart format --output=none --set-exit-if-changed .` (zero
   changes), `dart analyze --fatal-infos` (zero issues),
   `dart test` (zero failures).
6. As part of the same change set, update `PLAN.md`, `README.md`,
   `CHANGELOG.md`, `STABILITY.md`, and (if substantial) add a
   `doc/<feature>.md`. Each one of these is part of the feature
   commit, not a separate commit.
7. Re-run the gate. Commit the feature with a message following
   the `<area>(<scope>): <one-line summary>` shape (see §2).
   Ask before `git push` — the user typically authorizes it
   per session rather than per commit.
8. Refresh `HANDOVER.md` as a separate `docs(handover): ...`
   commit on top of the feature commit. Mirror what the
   recently-shipped session's handover commit did — update the
   §6 preamble, refresh §1's source-file LOC and test counts if
   they changed materially, append the new feature to §9's
   "recent commits" list with its hash, and re-rank §6
   recommendations if your work invalidates the ordering.
9. Hand back a one- or two-sentence summary of what shipped.

If you discover a bug in the existing code while reading, surface
it in your final summary rather than fixing it inline. The
maintainer will triage.

---

## 9. Known-good baseline

At the time this handover was written, the suite passes **690
test cases across 37 files** in ~30–45 seconds (the cancellation
tests and the predicate-SEND+MORE-with-CBJ benchmark account for
most of the wall-clock). The benchmark suite runs 10 plain/CBJ
problems plus an SAC consistency comparison plus two sweep/decomp
diff_n entries plus five heuristic comparisons in ~30–60 seconds.
CI is green on `main` (`gh run list --repo CrispStrobe/dart_csp
--limit 1`). If your first `dart test` doesn't match this,
something is wrong with the environment — investigate before
adding new code.

### Recent commits worth knowing about (latest first)

- `24622c8` — `bench(heuristic)`: add pigeonhole 8-in-7 as harder
  UNSAT instance. Extends the heuristic comparison section with
  one more UNSAT problem one size up from the existing 7-in-6
  entry. Surfaces clearer signal that the dom/wdeg family's wall-
  clock advantage over MRV scales with problem size: MRV/dom-wdeg
  wall-clock ratio 1.85× at 7-in-6 → 2.22× at 8-in-7; decision-
  count ratio 3.3× → 4.3×. Same qualitative ordering of the five
  heuristics holds. 9-in-8 and 20-queens were tried but excluded:
  9-in-8 MRV took ~14 s per rep (~13 min for that one row);
  20-queens showed no meaningful per-heuristic signal (all five
  inside 18-35 µs). No code changes outside `benchmark/`; 690
  total tests unchanged.

- `a483980` — `feat(explain)`: label support for set + soft helpers.
  Closes the gap from the prior labels rollout. Every
  constraint-posting set-variable helper (`addSetCardinality` /
  `Range` / `Var`, `addRequiredInSet`, `addExcludedFromSet`,
  `addSubset`, `addSetEquals`, `addSetDisjoint`, `addSetUnion` /
  `Intersection` / `Difference`) and `addSoftConstraint` now accept
  an optional `label:` parameter that propagates to every
  decomposed constraint they post. `addSetVariable` /
  `addSetVariables` / `declareSoft` intentionally don't accept
  `label:` because they declare indicator variables or mark a bool
  var as soft rather than posting constraints (this gap is now
  documented as intentional in STABILITY.md, not provisional).
  Test infrastructure: 8 new tests added to the existing
  `test/labels_test.dart` (addSetCardinality,
  addSetCardinalityRange, addRequiredInSet + addExcludedFromSet,
  addSetEquals — including per-element label propagation, addSubset,
  addSetDisjoint, addSetUnion, addSoftConstraint). 690 total tests
  (was 682). Documentation: `doc/conflict-explanation.md` "Labeling
  constraints" section now lists the set/soft helpers and the
  rationale for declarations not accepting labels, replacing the
  prior "What's not labeled" caveat.

- `24260c7` — `bench(explain)`: deletion vs QuickXplain comparison.
  New "conflict-explanation comparisons" section in
  `benchmark/benchmark.dart` runs both MUS algorithms on seven
  problems spanning small-k-large-n to k ≈ n. Two new problem
  builders (`buildExplainSingletonMus({n})` and
  `buildExplainTriangleMus({n})`) in `benchmark/problems.dart`
  scale the redundant-constraint count to probe the algorithmic
  crossover; the pigeonhole CNF 5-in-4 case reuses the existing
  builder for k ≈ n. Uses a smaller 3-rep warm-up + 9-rep median
  (each MUS pass is itself many `CSP.solve` calls). Local results
  confirm the textbook crossover: QX wins by 4×–63× on
  small-k-large-n (its O(k · log(n / k)) advantage); deletion wins
  ~1.6× when k = n (its O(n) is comparable with no recursion
  overhead). Updates `doc/conflict-explanation.md` with a bench-
  result table under the "Which algorithm to call?" guidance. No
  code changes outside `benchmark/`; 682 total tests unchanged.

- `47beb59` — `feat(explain)`: per-`addX`-call labels for
  `ConstraintRef`. Add an optional `label:` parameter to every
  primary constraint helper on `Problem` (forty-odd `addX` methods
  covering binary + n-ary `addConstraint`, the all-different /
  all-equal / lex / value-precedence family, every reified, every
  global constraint, every linear, clauses). The label is stored on
  the underlying `BinaryConstraint` / `NaryConstraint` (new `label:`
  field on both) and surfaced on a new `ConstraintRef.label` field
  by both MUS algorithms. `ConstraintRef.toString` renders
  `kind[label](variables)` when the label is set and the original
  `kind(variables)` otherwise. Equality on `ConstraintRef` is still
  keyed by `id` alone — the label is for display, not deduplication.
  Decomposed helpers propagate the caller's label to every decomposed
  piece: `addInverse` attaches it to all n² channelling binaries,
  `addLexChain` to each pairwise lex-leq, `addValuePrecedence` to
  each consecutive-value n-ary, binary `addAllEqual` to the directed
  pair. Forward + reverse arcs of a binary `addConstraint` share one
  label and surface as one ref. Backwards-compatible: `label:`
  defaults to null, every existing call site surfaces
  `ConstraintRef.label` as null. Set-variable and soft-constraint
  helpers don't yet accept `label:` — scope choice for the first cut,
  called out as a follow-up in `doc/conflict-explanation.md` and §6
  Tactical wins. 16 new tests in `test/labels_test.dart` (defaults,
  toString rendering, equality keyed by id alone, label propagation
  through every primary helper family, decomposed-helper
  propagation, forward+reverse pair sharing one label, both MUS
  algorithms surfacing the label, mixed labeled + unlabeled). 682
  total tests (was 666). New "Labeling constraints" section in
  `doc/conflict-explanation.md` with a propagation-through-
  decomposed-helpers table; README MUS section gains a labeled
  example; STABILITY.md classification covers both label parameter
  and `ConstraintRef.label`.

- `66b1a31` — `feat(explain)`: QuickXplain MUS (Junker 2004). New
  `Problem.findMinimalUnsatisfiableSubsetQuickXplain({cancelToken,
  consistency})` in the same `ConflictExplanation` extension as the
  deletion pass, returning `List<ConstraintRef>?`. Same return
  shape, same `ConstraintRef` granularity and id scheme as the
  deletion pass; what changes is the algorithm. QuickXplain runs
  divide-and-conquer (Junker 2004 — AAAI): split the candidate set
  in half, recurse on each half against a growing background of
  "already known to be in the MUS" constraints, short-circuiting
  whenever the background alone is unsat. O(k · log(n / k)) calls
  to `CSP.solve` where n is the candidate count and k is the MUS
  size — dramatically less than the deletion pass's O(n) for
  small-k-large-n models, comparable for k ≈ n. Both algorithms
  identify locally-minimal MUSes; they may surface different MUSes
  for the same problem (smallest MUS is NP-hard). Cancellation
  semantics differ: QX's recursion has no sound mid-flight kept
  set, so any cancellation returns `null`. 21 new tests in
  `test/quickxplain_test.dart` (satisfiability, minimal UNSAT
  detection across binary / allDifferent / triangle / linear /
  mixed / clauses, minimality witness via reconstructed Problems,
  relation to deletion pass on unique-MUS and multi-MUS problems,
  consistency-level composition, no mutation of originating
  Problem, pre-cancel + mid-recursion cancel, ref ID semantics,
  5-cycle 2-coloring larger conflict). 666 total tests (was 645).
  Updates `doc/conflict-explanation.md` with a per-algorithm
  section, "which algorithm to call" guidance, and per-algorithm
  cancellation semantics; STABILITY.md classification covers both
  methods under one entry.

- `7e851d3` — `feat(explain)`: deletion-based MUS / conflict
  explanation. New `ConflictExplanation` extension on `Problem`
  with `findMinimalUnsatisfiableSubset({cancelToken, consistency})`
  returning `List<ConstraintRef>?`. Returns null if the problem is
  satisfiable; otherwise returns a locally-minimal unsatisfiable
  subset of the posted constraints — removing any one of the
  returned refs makes the residual problem satisfiable. Algorithm:
  textbook deletion-based MUS (Bakker et al. 1993, Junker 2001),
  O(n) calls to `CSP.solve`. New public type `ConstraintRef` in
  `types.dart` with `id` / `kind` / `variables`. Forward + reverse
  directions of a single user-level `addConstraint` call share one
  ref; n-ary constraints each have their own. Kind label derives
  from the underlying NaryConstraint's dispatch flag (`binary`,
  `predicate`, `allDifferent`, `linearEquals`, `linearLeq`,
  `linearGeq`, `regular`, `circuit`, `subcircuit`, `gcc`,
  `cumulative`, `clause`, `diffN`). Step-1 (initial sat check)
  cancellation returns null; step-2 (deletion loop) cancellation
  returns the current kept set — sound (still unsat) but possibly
  non-minimal. Granularity is "what's stored after helpers run":
  decomposed helpers (`addInverse`, `addLexChain`, set variables)
  surface as the resulting pieces, not the originating call.
  21 new tests in `test/explain_test.dart`. 645 total (was 624).
  New tenth topical guide `doc/conflict-explanation.md` with the
  granularity table and open follow-ups (QuickXplain, per-`addX`
  labels, explanation-aware propagators, MSS, multiple MUSes).
  Net cost when not used: none — the extension only fires when
  the user calls `findMinimalUnsatisfiableSubset`.

- `f51b0b3` — `docs(heuristics)`: consolidated guide for the
  heuristic family. New `doc/heuristics.md` (ninth topical guide)
  walks through the four conflict-driven heuristics (dom/wdeg /
  VSIDS / IBS / LC) plus the MRV baseline: which picker to use
  for which problem shape, per-heuristic algorithmic descriptions,
  picker dispatch order, composition rules, side-by-side bench
  snapshot from `bench(heuristic)`, cost-when-off
  characterization. The README's four heuristic call-outs are
  kept short; the consolidated comparative material lives in the
  new doc. Material that was previously scattered across the
  README is now in one place. No code changes; no test count
  changes.

- `84dbcc7` — `feat(heuristic)`: Last-Conflict reasoning
  (Lecoutre 2009 — "Reasoning from last conflict(s) in
  constraint programming", AI 173) + companion
  `bench(heuristic)` section. Wrapper-style picker that composes
  with each primary heuristic. On every propagation failure the
  engine records the variable being pinned (single field
  `_lastConflictVar`); on the next pick, if that variable is
  still unassigned, the picker returns it directly — focusing
  the search on the conflict cause. When the recorded variable
  becomes assigned via propagation or via decision pin, the
  picker falls through to the configured underlying picker.
  Wired into all six search variants at the propagation-failure
  path — one line each. SAC's tentative pinning loop is
  intentionally NOT instrumented (LC is for search, not
  preprocessing). Public API:
  `Problem.getSolutionWithLastConflict({useDomWdeg, useVsids,
  useImpact, ...})`, `CSP.solveWithLastConflict`,
  `useLastConflict:` flag on `getSolutionWithRestarts`.
  Companion `bench(heuristic)` section adds a five-way
  comparison (MRV / dom-wdeg / VSIDS / IBS / LC+dom-wdeg) on
  five problems (magic-square 3x3 no-clue, 12-queens, 16-queens,
  SEND+MORE linear, pigeonhole 7-in-6 UNSAT) using the
  5-rep-warm-up + 25-rep-median harness. Local pigeonhole UNSAT
  result: LC+dom/wdeg ≈ 44 ms, dom/wdeg ≈ 48 ms, VSIDS ≈ 48 ms,
  IBS ≈ 53 ms, MRV ≈ 88 ms — the signal is in UNSAT and
  large-search-tree cases. 18 new tests in
  `test/last_conflict_test.dart`. 624 total (was 606).

- `26c0b01` — `feat(heuristic)`: Impact-Based Search (Refalo
  2004 — "Impact-Based Search Strategies for Constraint
  Programming", CP 2004). Third conflict-driven variable
  heuristic, sibling to dom/wdeg and VSIDS. After every decision
  the engine measures the impact of pinning `(variable, value)`:
  `1.0` on failed propagation, `1 - exp(logP_after - logP_before)`
  clamped to `[0, 1]` on success. Per-pair running mean stored
  in `_impactMean` / `_impactCount` with an incremental-mean
  update (`m' = m + (x - m) / n`). Picker minimizes
  `dom_size / (1 + Σ_a I(v, a))` over current-domain values —
  reduces to MRV pre-observation. Hooked into all six search
  variants at the decision site (two lines per variant: save
  `_logProductDomains()` before pinning, call
  `_observeImpact(pick, candidate, logBefore, ok)` after
  `_propagate`). Public API: `Problem.getSolutionWithImpact()`,
  `CSP.solveWithImpact`, `useImpact:` flag on
  `getSolutionWithRestarts`. Composes unchanged with restarts,
  FC, SAC preprocessing, and CBJ. Picker dispatch order:
  `useImpact > useVsids > useDomWdeg > MRV`. 16 new tests in
  `test/impact_test.dart` (basic feasibility, 6/7/8-queens,
  MRV agreement on a unique-answer instance, composition with
  every other solver flag, picker precedence when all three
  conflict-driven flags are on, SEND+MORE=MONEY linear). 606
  total (was 590). Net cost when off: the `useImpact` field is a
  single `final bool`; the six search loops each pay one
  bool-branch + one zero-init for `logBefore` per candidate
  when off, which is dominated by the existing trail / propagate
  costs.

- `ab7c5cb` — `bench(diff_n)`: sweep vs decomposition side-by-side.
  New "diff_n propagator comparisons" section in
  `benchmark/benchmark.dart` with two entries (`8 rectangles in
  8x8 (find-first)` and `5 3x3 in 6x6 (UNSAT by area)`) running
  the same problem via `addDiffN` (sweep) and a manual pairwise
  decomposition; only knob is `useSweep:` on the new
  `buildDiffNPack` / `buildDiffNOverpack` builders. 5-rep warm-up
  + 25-rep median in microseconds (per HANDOVER §7 — single-shot
  cold timings are noisy on these problems). Local results: sweep
  beats decomposition by ~1.7× on find-first (identical search
  tree, pure per-call cost win) and by ~2× on UNSAT (sweep does
  2.2× more search than decomp's per-pair-GAC, but per-call cost
  is so much lower that wall-clock still improves). The "decomp
  does less search" gap is the motivation for the §6 "strengthen
  the diff_n sweep" follow-up.

- `b7074a5` — `feat(global)`: forbidden-region sweep propagator
  for `addDiffN` (Beldiceanu & Carlsson, "Sweep as a generic
  pruning technique applied to the non-overlapping rectangles
  constraint", CP 2001). The 2D rectangle non-overlap global,
  previously a decomposition into `n(n-1)/2` 4-ary disjunction
  predicates, now dispatches to a dedicated `_DiffNPropagator`
  via a new `diffNSpec` dispatch flag and `DiffNSpec` (carries
  widths and heights). A single tagged `NaryConstraint` scopes
  all `2n` coordinate variables in the order `[xs..., ys...]`;
  per-rectangle / per-dimension pruning aggregates forbidden-
  position intervals induced by every other rectangle whose
  compulsory part in the orthogonal dimension forces an overlap.
  Mandatory-overlap test for `(r, s)` in dimension `d` is
  `max(d_lst[r], d_lst[s]) < min(d_est[r] + len_d(r), d_est[s] +
  len_d(s))`; the forbidden positions of `r` in the orthogonal
  dimension `d'` are `[d'_lst[s] - len_{d'}(r) + 1, d'_est[s] +
  len_{d'}(s) - 1]`. Belt-and-braces pairwise leaf predicate
  preserved. Net effect: propagation runs once per change to any
  rectangle (instead of `n(n-1)/2` GAC support searches), and
  per-call pruning catches root-level infeasibility and bound-
  tightening on packing problems the decomposition could only
  surface deep in search. 7 new tests in `test/diffn_test.dart`
  (propagator engagement, root-level x-pruning under compulsory-y
  overlap, root-level over-packing infeasibility, agreement with
  an explicit pairwise decomposition, `addNoOverlap` equivalence
  on the 1D y-pinned reduction, composition with
  `addAllDifferent`, mid-size 3×(2×2) packing). 590 total tests
  (was 583).

- `5200888` — `bench(consistency)`: AC vs SAC side-by-side on the
  canonical SAC-only example. New "consistency-level comparisons"
  section in `benchmark/benchmark.dart` with new
  `_benchConsistency` / `_runConsistency` helpers (mirroring the
  existing plain/CBJ harness; only knob is `consistency:`). Single
  entry on `buildSacInfeasible(blocks: 5)` — the canonical
  AC-consistent / SAC-empty example. Local result: AC needs ~4 ms
  with 1 decision + 3 backtracks; SAC proves infeasibility in
  ~0 ms with 0 decisions. Adds `buildSacInfeasible` to
  `benchmark/problems.dart` so future tests can reuse it.

- `5e8da32` — `feat(consistency)`:
  `ConsistencyLevel.singletonArcConsistency` (SAC-1, Debruyne &
  Bessière 1997). New enum variant on top of `arcConsistency` /
  `forwardChecking`. Search still runs ordinary AC-3 / GAC; the
  SAC behavior is a preprocessing pass at the top of search that,
  for each `(variable, value)` pair currently in some domain,
  tentatively pins the variable, runs `_propagate`, rolls back the
  trail, and prunes the value if propagation failed. Repeats the
  whole pass until a fixpoint. Wired in through a new
  `_enforceSac()` method and a `_seedAndPreprocess()` wrapper that
  the three search entry points (`findOne`, `findAll`,
  `findOptimal`) route through. Counted toward existing stats via
  the trailing `_propagate` calls; conflict-driven heuristics
  (`useDomWdeg`, `useVsids`) observe SAC failures via the existing
  `_onConflict(c)` helper so the bumps inform later search. SAC
  composes unchanged with every other solver flag (dom/wdeg,
  VSIDS, CBJ, restarts, optimization, streaming). 18 new tests in
  `test/sac_test.dart` including the canonical
  `x == y ∧ y == z ∧ x != z` SAC-only infeasibility example (with
  a companion assertion that AC under the same problem has to
  descend into search to detect infeasibility), AC-equivalent
  enumeration check, decision-count reduction on a chain CSP, root
  singleton collapse on `x == y ∧ x + y == 4`, composition with
  every other solver flag, multi-round fixpoint iteration, the
  `CSP.solve` static, single-variable infeasibility, and 8-queens
  as a "doesn't break AC-easy problems" regression. 583 total
  tests (was 565).

- `0338d25` — `feat(global)`: `addSubcircuit` — subcircuit
  constraint with optional skips. Variant of `addCircuit` that
  permits `vars[i] = i` (a self-loop) as a "skip" marker meaning
  position `i` is not in the cycle; the non-self-loop edges among
  the remaining positions still form a single cycle (or no cycle
  at all, when every position self-loops). Shares the existing
  `_CircuitPropagator` via a new `subcircuit: bool` flag on
  `NaryConstraint`. The propagator additionally tracks
  committed-skipped and committed-in-cycle position counts to
  drive three subcircuit-specific reductions: (a) remove the
  chain's head value from the tail when an outside position is
  forced into the cycle (`chainLen ≥ 2` only — for `chainLen == 1`
  "closing at head" is just a self-loop and never conflicts with
  another cycle), (b) force the tail to the head when chain +
  committed-skipped already covers every position, (c) after a
  pure non-Hamiltonian cycle, force every non-cycle position to
  self-loop (or fail if any can't). The pureCycle subcircuit
  branch refreshes the local `selfLoop`/`committedSkip` arrays so
  later chain iterations within the same propagator call see the
  up-to-date picture (otherwise a length-1 chain at a
  just-forced-skip position would falsely prune its only value).
  Successor uniqueness extends to skip slots so the value `i`
  taken by a self-loop is removed from every other variable's
  domain. The predicate at the leaf does the standard permutation
  check plus a "single cycle on non-self-looped positions" walk
  starting from the first included position. 19 new tests in
  `test/circuit_and_bin_packing_test.dart` (n=1/n=2/n=3 small
  enumerations, n=4 against the closed-form Σ C(n,k)·(k-1)!
  formula = 21, sub-cycle feasibility/infeasibility splits,
  chain-head prune / force, intermediate prune, agreement with
  `addCircuit` on self-loop-free domains, composition with
  `addAllDifferent`, propagator engagement, minimize/maximize
  over a visited-count aggregator). 565 total tests.

- `02b7c41` — `feat(heuristic)`: VSIDS-style variable activity
  (Moskewicz, Madigan, Zhao, Zhang, Malik 2001 — the Chaff SAT
  solver), adapted to CSPs. New `Problem.getSolutionWithActivity()`,
  matching `CSP.solveWithActivity()` static, and `useVsids: true`
  flag on `getSolutionWithRestarts`. Per-variable activity bumped
  on every propagation conflict by a growing `_activityInc`
  (multiplicatively grown by `1 / decay` per conflict — the
  MiniSat trick; 1e100 rescale guard). Picker minimizes
  `dom(v) / (1 + activity(v))`, mirroring dom/wdeg's shape — pre-
  conflict the ratio reduces to MRV; as activity accumulates the
  picker gravitates toward variables that have been near recent
  failures. The 16 per-call-site `if (useDomWdeg) _bumpWeight(...)`
  guards in `_propagate` collapsed into one `_onConflict(c)` call
  apiece; the helper delegates to both bump types. When both
  flags are on, VSIDS wins picking; both bump tables update
  independently. 12 new tests; 546 total.
- `c83ef77` — `docs(handover)`: prior-session handover (this one
  supersedes it).
- `94c4be2` — `feat(global)`: `addDiffN` — 2D rectangle non-overlap
  (`diff_n`). Generalises `addNoOverlap` from a unary 1D resource
  to two dimensions. Posts `n(n-1)/2` 4-ary disjunction predicates;
  half-open box semantics so edge-touching counts as
  non-overlapping; zero-area rectangles dropped. 18 new tests.
- `a55dc21` — `feat(symmetry)`: `addLexChain` n-way lex chain
  helper. Sugar over pairwise `addLexLeq` / `addLexLt`. 6 new
  tests.
- `1d6df6f` — `feat(global)`: `addInverse` channelling constraint.
  Standard CP primitive (MiniZinc `inverse`, OR-Tools
  `AddInverseConstraint`). Decomposes to `n²` binary
  `(forward[i] == j) ⇔ (inverse[j] == i)` constraints so AC-3
  propagates effectively. 11 new tests.
- `b928269` — `feat(symmetry)`: `addValuePrecedence` for value-
  symmetry breaking. Companion to `addLexLeq`/`addLexLt`. Reduces
  search by up to `k!` where `k = values.length`. 13 new tests.
- `51e7820` — `solver(clause)`: per-variable seeding filter for
  the clause propagator. 18-20% perf win on pigeonhole CNF; bit-
  identical correctness. 2 new tests.
- `bd4ac74` — `solver(cbj)`: per-revision conflict cause + chain
  following. Tightens CBJ's conflict-cause attribution from the
  constraint-graph approximation to a per-revision chain walk.
- `54fb7d9` — `bench(cbj)`: side-by-side comparison + real tests
  for every benchmark. Extracted `benchmark/problems.dart` for
  sharing with `test/cbj_benchmarks_test.dart`.
- `e3cce21` — `solver(cbj)`: conflict-directed backjumping
  (Prosser 1993). Opt-in via `enableConflictBackjumping: bool =
  false` on every backtracking entry point.

Earlier commits (the Tier 1 / Tier 2 build-out — bitset rep,
specialized propagators, set variables, cumulative, clauses,
linear, regular, GCC, circuit, etc.) are also in `git log`. They
are stable; don't second-guess them without a behavioral reason.

Good luck.

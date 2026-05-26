# Handover — continuing work on `CrispStrobe/dart_csp`

You are picking up work on `CrispStrobe/dart_csp`, a pure-Dart
Constraint Satisfaction Problem solver. Post-clean-room-rewrite
(see `NOTICE`), MIT-licensed, 2.1.0+. Every Tier 1/2/3 item from
the original PLAN.md has shipped; the remaining work lives in
the **Strategic gaps**, **Tactical wins**, and **Edge/workload-
gated** sections of `PLAN.md`.

The most recent landings (in order, newest first):

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

**Test count:** 924 passing. **Files:** 6 `lib/src/*.dart` (plus
`lib/src/lns/`, `lib/src/lcg/`, and `lib/src/flatzinc/`); 51
`test/*_test.dart` files (incl. `test/lcg/`); 13 `doc/*.md` guides
(incl. `doc/lcg.md`); 7 `example/*.dart` files;
`benchmark/benchmark.dart` runs seven sections (CBJ, AC-vs-SAC,
diff_n, heuristics, conflict-explanation, LNS, FlatZinc). Three
planning docs at repo root: `LNS_PLAN.md`, `MINIZINC_PLAN.md`,
`LCG_PLAN.md` (LCG M1 shipped; M2 — first-UIP loop — is the next
strategic pick).

---

## Recommended next pick

LCG **M1 shipped this session** (atom encoding + implication trail
wired into the engine + `Problem.solveWithLcg` runner shell). The
biggest strategic gap is now **LCG M2 — first-UIP conflict
analysis on top of the existing `_ClausePropagator`**. That's the
milestone that actually closes the learning loop: every conflict
produces a learned clause via the textbook first-UIP walk, the
clause is added to the engine's clause pool, the engine backjumps
to the second-highest decision level in the learned clause, and
the loop repeats. Once M2 lands, pigeonhole-CNF 8-in-7 / 9-in-8
should drop 10–100× in search-tree size; that's the canonical
showcase test. Read `LCG_PLAN.md` §3 M2 + `_ClausePropagator` in
`solver.dart` end-to-end before starting. The implication trail
infrastructure M1 ships exposes `CSP.lastImplicationTrail`,
`ImplicationEntry`, and the `Atom` hierarchy — M2's analyser
consumes that trail. About one session of focused work for the
core loop, plus a second to tune forget / activity policies and
add the `bench(lcg)` perf anchor.

Smaller (one-session) follow-ups that are well-scoped and have
clear value:

- **`bench(cooperative-lns)` perf anchor.** Cooperative parallel
  LNS shipped without a perf-anchored claim — extend
  `benchmark/benchmark.dart` with a portfolio-vs-cooperative
  comparison on the bin-packing problem the existing `bench(lns)`
  uses. Standard warm-up + median methodology. Closes the
  "perf claims need warm-up + median" gate for the new feature.
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

If you're picking up the recommended next item (LCG): read
`LCG_PLAN.md` end-to-end first — it has the scope decisions
(lazy vs eager atom encoding in §4, per-propagator explanation
priority order in §3 M3a–g) made already. Then read
`_ClausePropagator` and `_BacktrackEngine` in `solver.dart`
end-to-end. Land M1 (atom encoding + implication trail + LCG
runner shell) first; it's a self-contained increment that leaves
the engine in a working state even if M2's first-UIP loop never
follows. Add `explain` to `_AllDifferentPropagator` first in
M3 — it's the most-used global and the natural test bed.

If you're picking up a perf-anchor bench section
(`bench(cooperative-lns)` or `bench(search-annotation)`): read
`benchmark/benchmark.dart`'s existing `bench(lns)` and
`bench(heuristic)` sections — they're the canonical shape for
warm-up + median methodology. Reuse the bin-packing builder in
`benchmark/problems.dart` for the cooperative-LNS comparison.

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

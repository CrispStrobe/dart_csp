# Handover — continuing work on `CrispStrobe/dart_csp`

You are picking up work on `CrispStrobe/dart_csp`, a pure-Dart
Constraint Satisfaction Problem solver. The library is post-clean-
room-rewrite (no derivative content); see `NOTICE`. The entire
PLAN.md tier 1 and tier 2 ship, plus most of tier 3. The only
substantial open work is a MiniZinc / FlatZinc / XCSP3 frontend
(multi-day, multi-session). The smaller follow-ups in §6 are good
one-session candidates.

Your job is to pick **one** item, design it, implement it with
tests + docs, and ship it the same way every prior feature has
been shipped. Don't reinvent the conventions — the shape and
rigor of new work should match what's already in the repo.

---

## 1. Required reading (in this order)

1. **`PLAN.md`** — the roadmap. Items marked `[x]` are done; `[~]`
   are partial; `[ ]` are open. As of this handover, every tier-1
   and tier-2 item is `[x]`, and two of the three tier-3 items
   (isolate parallelism, conflict-directed backjumping) are also
   `[x]`. Only the MiniZinc/FlatZinc/XCSP3 frontend remains open
   at tier 3.
2. **`STABILITY.md`** — public-API stability tiers, semver policy,
   what's experimental, what's internal, and the known gotchas
   (single-static-slot `lastStats`, stream-stats-flush-on-completion,
   GAC bail-out work bound, bounded-latency `.timeout()`).
3. **`README.md`** — public API surface. Recently-added sections:
   "2D Non-Overlap (`diff_n`)", "Channelling Inverse Maps",
   "Symmetry-Breaking" (now split into sequence + value
   subsections, with `addLexChain` and `addValuePrecedence` shown),
   "Conflict-Directed Backjumping (CBJ)", "Solving on a worker
   isolate", "Cancellation and Timeouts", "Set Variables",
   "Cumulative resource scheduling", "SAT-style clauses
   (`addClause`)".
4. **`NOTICE`** — clean-room history; now MIT. Addendum lists the
   demo file as also covered by the clean-room scope.
5. **`CHANGELOG.md` "Unreleased"** — concise list of everything
   shipped since 2.1.0. Top entries first; the most recent five
   commits were all this session (per-variable clause seeding,
   `addValuePrecedence`, `addInverse`, `addLexChain`, `addDiffN`).
6. **`doc/`** — eight topical guides: algorithms, cancellation,
   cbj, global-cardinality, min-conflicts, multi-solutions,
   set-variables, string-constraints.
7. **`lib/src/`** — six source files; total ~8130 lines:
   * `types.dart` (~530 lines) — public types: `CancellationToken`,
     `BinaryConstraint`, `NaryConstraint` (with dispatch flags for
     `allDifferent`, `linearSpec`, `regularDfa`, `circuit`,
     `gccSpec`, `cumulativeSpec`, `clauseSpec`), `CspProblem`,
     `SolverStats` (now also `backjumps` / `backjumpLevelsSkipped`),
     `Dfa`, `LinearSpec`, `LinearOp`, `GccSpec`, `CumulativeSpec`,
     `ClauseSpec`, `ConsistencyLevel`, typedefs.
   * `problem.dart` (~2685 lines) — `Problem` builder with every
     extension. Every backtracking entry point accepts
     `consistency:`, `cancelToken:`, and
     `enableConflictBackjumping:` parameters.
   * `builtin_constraints.dart` (~390 lines) — factory functions
     including the recent `valuePrecedence(...)`.
   * `constraint_parser.dart` — string-constraint parser.
   * `solver.dart` (~3210 lines) — `CSP` static class,
     `_BacktrackEngine`, three `_DomainRep` impls (`_ListRep`,
     `_BitsetRep`, `_IntervalRep`), seven specialized propagators
     (`_AllDifferentPropagator`, `_LinearPropagator`,
     `_RegularPropagator`, `_CircuitPropagator`, `_GccPropagator`,
     `_CumulativePropagator`, `_ClausePropagator`), the
     `_MinConflictsRunner`, `_TrailEntry` with constraint-cause
     attribution, sealed `_SearchResult` (with `_Solution`,
     `_Exhausted`, `_Backjump` variants) for CBJ, three CBJ search
     helpers (`_searchOneCbj`, `_searchAllCbj`, `_searchOptimalCbj`),
     `_checkpoint` (cooperative yield + cancellation poll), and
     `_clauseWatchers` side-table for the two-watched-literal
     scheme (also consulted by `seedFor` for the per-variable
     wake-up filter).
   * `isolate_runner.dart` (~458 lines) — `solveInIsolate`,
     `solveAllInIsolate`, `minimizeInIsolate`, `maximizeInIsolate`,
     `IsolateRunnerException`. Worker-isolate runner with builder-
     closure API, parent-side `CancellationToken` bridge via
     `addListener`, stats round-trip, and built-in `timeout:`.
8. **`test/`** — 30 files, 534 test cases. One file per feature
   area: `test/<feature>_test.dart`. The newest is
   `test/diffn_test.dart` (18 cases).
9. **`benchmark/`** — `benchmark.dart` (10 classic CSPs, runs
   plain BT + CBJ side-by-side; the most recently added entry is
   `pigeonhole CNF 7-in-6 (UNSAT)`); `problems.dart` (shared
   problem builders, imported by both the benchmark and
   `test/cbj_benchmarks_test.dart`).

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
for the per-variable wake-up filter (shipped this session). Once a
clause's watchers are set, the engine only enqueues the clause
when one of the two watched literals' variables is reduced —
reductions to non-watched variables can't change the propagator's
behaviour, so they're filtered out before the propagator is even
instantiated. Width-2 clauses bypass the filter (both literals
always watched, so the check would never fire and adding it would
be pure overhead on `at-most-one` pairwise workloads).

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
`logical`, `cbj`, `clause`, `symmetry`, ...).

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
│       │                            # min-conflicts runner, CBJ helpers
│       └── isolate_runner.dart      # worker-isolate runner
├── test/                            # 30 files, 534 tests
│   ├── dart_csp_test.dart
│   ├── builtin_and_parser_test.dart
│   ├── minconflicts_tests.dart
│   ├── multisolutions_tests.dart
│   ├── alldifferent_propagator_test.dart
│   ├── optimization_test.dart           # incl. integrated-B&B tests
│   ├── restart_test.dart
│   ├── dom_wdeg_test.dart
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
   chain-following works on your propagator; mirror the shape of
   the existing seven. Remember the leaf-check gotcha.
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
  mode variants (restarts, dom/wdeg, consistency level, CBJ),
  thread an optional parameter through `CSP.solve*` to
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
- **Per-variable propagator seeding filter** (clause propagator,
  shipped this session). When a propagator's internal state lets
  you know which variables "matter" for its current work,
  consider filtering wake-ups in `seedFor` rather than waking the
  propagator on every scope variable's change. The clause case
  needed a width-2 carve-out because for narrow clauses the
  per-call check overhead dominated the skip savings — measure
  before committing to a filter on similar grounds for other
  propagators.
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
on the radar at the last handover has shipped (five features in
the current session: per-variable seeding filter, value-precedence
symmetry, channelling inverse, lex chain, 2D diff_n).

### Tier 3 — substantial open item

- **MiniZinc / FlatZinc / XCSP3 frontend.** *Multi-day.* Parser +
  AST + lowering to `Problem`. Big ecosystem unlock (lets dart_csp
  ingest academic benchmarks). Not on any user's immediate
  critical path. Definitely not one-session sized. Pick
  deliberately, not opportunistically.

### Smaller follow-ups not in PLAN.md yet

These are all flagged in topical docs, in past handovers, or
identified during recent sessions; pick any one if you want a
clean one-session win.

- **VSIDS-style variable activity.** Sibling to the existing
  dom/wdeg heuristic. Per-variable activity score bumped on
  conflict with periodic decay. Variable picker chooses highest
  activity (or activity/dom). The dom/wdeg infrastructure
  (`_naryWeights`, `_bumpWeight` on conflict, `getSolutionWith
  DomWdeg`) is the natural template. New
  `Problem.getSolutionWithActivity()` entry point. PLAN.md tier 2
  notes this as a follow-up to dom/wdeg. Useful for SAT-style
  instances; less so for typical CP problems with structured
  globals. Well-bounded, ~300-500 LOC.
- **Singleton-arc consistency (SAC).** New
  `ConsistencyLevel.singletonArcConsistency` enum value.
  Preprocessing pass that, for each variable / value pair,
  tentatively assigns the value, runs AC-3, and prunes the value
  if the AC step wipes any domain. Repeat until stable.
  Standalone or as a top-of-search filter. Well-bounded, ~200-400
  LOC. Empirical value depends on the problem class; rarely beats
  the dedicated globals for typical instances.
- **Subcircuit (`addSubcircuit`).** Variant of `addCircuit`
  allowing `vars[i] = i` (a self-loop), which means position `i`
  is not in the cycle. Used in vehicle routing with optional
  stops. Needs propagator changes on top of the existing
  `_CircuitPropagator` (must allow self-loops while still
  rejecting non-trivial sub-cycles). ~400-600 LOC, tight for one
  session but doable.
- **Sweep-based propagator for `addDiffN`.** The current
  predicate-decomposition version is sound and adequate for small
  to medium instances. For large rectangle-packing benchmarks a
  dedicated sweep-based propagator (Beldiceanu & Carlsson,
  "Sweep as a generic pruning technique applied to the
  non-overlapping rectangles constraint", CP 2001) would be a
  noticeable perf win. Substantial work — comparable to the
  cumulative time-table propagator effort. Take on if a real
  use-case surfaces.
- **Minimal-cause conflict analysis for CBJ.** The current
  per-revision chain-following attribution is still pessimistic
  for n-ary constraints (treats every other variable in scope as
  a contributor, even when only some specific values mattered).
  True minimal-cause would track per-value support attribution
  inside each propagator's revise step. **Reality check from this
  session's analysis:** for the engine's *generic* GAC support
  search, the "every other var contributes" approximation is
  essentially minimal — the support loop genuinely consults every
  other variable's full domain to find support. The wins, if any,
  would come from algorithm-specific attribution inside the
  *specialized* propagators (clause, allDifferent, regular),
  where each propagator's structure tells you which vars'
  specific values were load-bearing. Multi-day, dubious payoff
  unless a specific benchmark surfaces the limitation.
  See `doc/cbj.md` "What's not implemented".
- **Nogood recording / LCG (Lazy Clause Generation).** CDCL-style
  learning records the discovered conflict as a new clause and
  adds it to the constraint set. Substantially larger than
  minimal-cause analysis — needs efficient learned-clause storage,
  watch lists per learned clause, forgetting strategies, and
  interaction with non-binary constraints. The existing
  `_ClausePropagator` machinery is the natural home for the
  storage side. Multi-session; the first stop on the way to real
  CDCL. Pick deliberately.
- **Per-variable watch lists for the clause propagator —
  textbook full version.** This session shipped the matching
  *seeding* filter on top of the existing two-watched-literal
  scheme. A more invasive optimization would maintain an explicit
  inverse index `Map<String, Set<ClauseSpec>>` of which clauses
  currently watch each variable, updated on watcher swaps. The
  current `seedFor` consults `_clauseWatchers[spec]` for each
  clause in `_naryIdx[v]` — already O(1) per clause — so this
  full inverse index would only save the `_naryIdx[v]` iteration
  overhead. Probably not worth it unless a workload surfaces
  where clause count dwarfs other constraint counts.

### Picking criteria

Choose the item that has the best fit between:

- **User value** — how often it gets reached for in real CSP
  modeling.
- **Self-contained scope** — doesn't pull in other unfinished
  work.
- **Size match to one session** — if you can ship it in ~1000
  LOC including tests, prefer it over a multi-day project.
- **Honest assessment of the design risk** — VSIDS and SAC are
  well-bounded; subcircuit and sweep-propagator are tighter;
  nogood learning is multi-session; the frontend is multi-day.

### Recommendation

If you don't have a preference, the order is roughly:

1. **VSIDS-style variable activity.** Companion to dom/wdeg; the
   infrastructure is in place; well-bounded perf-flavoured win.
2. **Subcircuit.** Useful for routing modelling; mostly extends
   the existing circuit propagator; tight but doable in one
   session.
3. **Sweep-based propagator for `addDiffN`.** Most natural perf
   follow-up to what just shipped, but substantial work — needs
   careful design.
4. **SAC.** Easy to wire as a new `ConsistencyLevel`; user value
   depends heavily on problem class.
5. **Nogood learning.** Big payoff if delivered; multi-session.
6. **MiniZinc/FlatZinc/XCSP3 frontend.** Multi-day; should be a
   deliberate project, not a one-session pick.

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
  isolate wire protocol, or the `_ClauseWatchState` side-table**
  in the public API. They're file-private on purpose. If you
  need to extend search-result semantics, add a new variant to
  `_SearchResult` rather than changing the exported signature of
  `Problem.getSolution`.
- **Don't add CBJ support to `solveWithMinConflicts`** — local
  search has no backtracking surface to attach to. The parameter
  is intentionally not on that entry point; the type system
  prevents the mistake.
- **Don't wrap worker-isolate solves in `.timeout()`** unless you
  actually want the worker to keep running after the deadline.
  Use the runner's built-in `timeout:` parameter — it sends a
  cancel signal, waits a brief grace window, then hard-kills the
  isolate.
- **Don't measure perf without a JIT warm-up loop.** This
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
5. After each major change, run the acceptance gate (§2).
6. Commit + push.
7. Update `PLAN.md`, `README.md`, `CHANGELOG.md`, `STABILITY.md`,
   and (if substantial) add a `doc/<feature>.md`.
8. Hand back a one-paragraph summary of what shipped.

If you discover a bug in the existing code while reading, surface
it in your final summary rather than fixing it inline. The
maintainer will triage.

---

## 9. Known-good baseline

At the time this handover was written, the suite passes **534
test cases across 30 files** in ~25–40 seconds (the cancellation
tests and the predicate-SEND+MORE-with-CBJ benchmark account for
most of the wall-clock). The benchmark suite runs 10 problems
with plain BT + CBJ comparison in ~5–10 seconds. CI is green on
`main` (`gh run list --repo CrispStrobe/dart_csp --limit 1`). If
your first `dart test` doesn't match this, something is wrong
with the environment — investigate before adding new code.

### Recent commits worth knowing about (latest first)

- `94c4be2` — `feat(global)`: `addDiffN` — 2D rectangle non-overlap
  (`diff_n`). Generalises `addNoOverlap` from a unary 1D resource
  to two dimensions. Posts `n(n-1)/2` 4-ary disjunction predicates;
  half-open box semantics so edge-touching counts as
  non-overlapping; zero-area rectangles dropped. Also bundles a
  doc polish on `addClause`'s stale docstring. 18 new tests
  (validation, semantics, integration including 4! = 24 tilings of
  the 2×2 grid). 534 tests total.
- `a55dc21` — `feat(symmetry)`: `addLexChain` n-way lex chain
  helper. Sugar over pairwise `addLexLeq` / `addLexLt`. 6 new
  tests; 516 tests total.
- `1d6df6f` — `feat(global)`: `addInverse` channelling constraint.
  Standard CP primitive (MiniZinc `inverse`, OR-Tools
  `AddInverseConstraint`). Decomposes to `n²` binary
  `(forward[i] == j) ⇔ (inverse[j] == i)` constraints so AC-3
  propagates effectively. Implies both lists are partial
  permutations of `0..n-1`. 11 new tests; 510 tests total.
- `b928269` — `feat(symmetry)`: `addValuePrecedence` for value-
  symmetry breaking. Companion to `addLexLeq`/`addLexLt`. For
  each consecutive pair `(values[i], values[i+1])`, posts an
  n-ary precedence predicate enforcing the first occurrence of
  `values[i]` strictly precedes the first occurrence of
  `values[i+1]`. Reduces search by up to `k!` where
  `k = values.length`. 13 new tests; 499 tests total.
- `51e7820` — `solver(clause)`: per-variable seeding filter for
  the clause propagator. Once watchers are set, the engine
  skips waking the clause on reductions to non-watched
  variables. Width-2 clauses bypass the filter (both literals
  always watched, so the check is pure overhead on
  pigeonhole-style "at most one" workloads). 18-20% perf win
  on pigeonhole CNF; correctness preserved bit-identically.
  New `pigeonhole CNF 7-in-6 (UNSAT)` benchmark entry. 2 new
  tests; 486 tests total.
- `ee98fd4` — `docs(handover)`: prior-session handover (this
  one supersedes it).
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

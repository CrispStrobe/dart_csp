# Handover — continuing PLAN.md work on `dart_csp`

You are picking up work on `CrispStrobe/dart_csp`, a pure-Dart
Constraint Satisfaction Problem solver. Fifteen shipping sessions
have closed every documented deferred propagator follow-up,
finished Tier 1 and Tier 2 in full, shipped the polish bundle
(SolverStats for every solver path, STABILITY.md), removed the
per-propagator `List<dynamic>` round-trip via a rep-aware filter
callback, and — most recently — added cooperative cancellation,
the two-watched-literal data structure for clauses, and the
`addNoOverlap → addCumulative` dispatch.

The current state of the big tiered roadmap:

- **Tier 1** — fully closed.
- **Tier 2** — fully closed. Variable-types (interval-rep, set
  variables, SAT-style clauses), global constraints (cumulative
  with time-table propagation, GCC, circuit, regular, ...), set
  variables, soft constraints / MaxCSP, and the cumulative
  resource constraint all shipped. The watched-literal data
  structure that previously kept the variable-types entry at `[~]`
  is now in.
- **Tier 3** — three substantial items still open: isolate-based
  parallelism is at `[~]` (cooperative checkpoint half shipped:
  `CancellationToken` + `_checkpoint` yields; worker-isolate
  runner deferred); CDCL-style backjumping is open; MiniZinc /
  FlatZinc / XCSP3 frontend is open.

Your job is to pick **one** of the remaining items, design it,
implement it with tests + docs, and ship it the same way every
prior feature has been shipped. You may pick which one (see §6).
The shape and rigor of the change should match what is already in
the repo; don't reinvent the conventions.

---

## 1. Required reading (in this order)

1. **`PLAN.md`** — the roadmap. Status of every item, sized and
   ranked. Items marked `[x]` are done; items marked `[~]` are
   partial; items marked `[ ]` are open. As of this handover, every
   tier-1 and tier-2 item is `[x]`. The only `[~]` is the tier-3
   isolate-parallelism entry, which sits at partial because the
   cooperative-checkpoint half shipped while the worker-isolate
   runner half is deferred.
2. **`STABILITY.md`** — public-API stability tiers, semver policy,
   what's experimental, what's internal, and the known gotchas
   (single-static-slot `lastStats`, stream-stats-flush-on-completion,
   GAC bail-out work bound, bounded-latency `.timeout()` instead of
   the prior never-fires gotcha). Read this before designing any
   change that touches the public API. The `addSetVariable` /
   `addCumulative` / `addClause` / `CancellationToken` surfaces are
   all in the experimental section.
3. **`README.md`** — public API surface. Each feature group has its
   own section. Most-recently-added sections: "Cancellation and
   Timeouts" (the `CancellationToken` API + `.timeout()`
   integration), "Set Variables", "Cumulative resource scheduling"
   (subsection under "Range-Domain Variables"), and "SAT-style
   clauses (`addClause`)" (subsection under Logical Combinators).
4. **`NOTICE`** — short history of the codebase (clean-room rewrite
   from a previously-derivative-of-csp.js predecessor; now MIT).
5. **`CHANGELOG.md` "Unreleased" entry** — concise list of
   everything shipped since 2.1.0. The most recent entries describe
   `addNoOverlap → addCumulative` dispatch, the two-watched-literal
   data structure for `_ClausePropagator`, cooperative cancellation
   + `CancellationToken`, clauses + unit propagation, cumulative +
   time-table, set variables + materialization, interval-rep +
   scheduling primitives, rep-aware filter, network-flow GCC,
   cycle-detection circuit, bitset rep, partial-state regular,
   polish bundle, bounds-consistency linear, and consistency-level
   changes.
6. **`lib/src/`** — five files; total ~6830 lines. Recent growth:
   * `types.dart` (466 lines) — public types: `CancellationToken`
     (new in this batch), `BinaryConstraint`, `NaryConstraint` (now
     with `allDifferent`, `linearSpec`, `regularDfa`, `circuit`,
     `gccSpec`, `cumulativeSpec`, `clauseSpec` dispatch flags),
     `CspProblem`, `SolverStats`, `Dfa`, `LinearSpec`, `LinearOp`,
     `GccSpec`, `CumulativeSpec`, `ClauseSpec`, `ConsistencyLevel`,
     typedefs.
   * `problem.dart` (2390 lines) — `Problem` builder (with the
     `_setVarUniverses` registry + `_materializeSets` /
     `_wrapResult` / `_wrapStream` helpers, plus
     `addRangeVariable`) + every public extension
     (`BuiltinConstraints`, `StringConstraints`, `ProblemDebug`,
     `MultipleSolutions`, `ReifiedConstraints`,
     `LogicalConstraints` — which includes `addClause`,
     `GlobalConstraints` — which includes `addNoOverlap` (now a
     dispatch to `addCumulative`) and `addCumulative`,
     `LinearConstraints`, `SoftConstraints`, and the `SetVariables`
     extension at the end of the file). Every solve entry point
     accepts an optional `cancelToken: CancellationToken`.
   * `builtin_constraints.dart` — factory functions (unchanged).
   * `constraint_parser.dart` — string-constraint parser
     (unchanged).
   * `solver.dart` (2763 lines) — `CSP` static class (every entry
     point now also takes `cancelToken:`), `_BacktrackEngine`,
     three `_DomainRep` impls (`_ListRep`, `_BitsetRep`,
     `_IntervalRep`) with `_classifyDomain` sealed-class dispatch,
     **seven** specialized propagators (`_AllDifferentPropagator`,
     `_LinearPropagator`, `_RegularPropagator`,
     `_CircuitPropagator`, `_GccPropagator`,
     `_CumulativePropagator`, `_ClausePropagator` — the last one
     is now stateful, see §2 "Per-constraint side-table" below) —
     each with a rep-aware `applyUpdate(String, _DomainRep)`
     callback, `_MinConflictsRunner` (now async; yields every 200
     iterations), Luby sequence, Hopcroft-Karp, Kosaraju SCC,
     `findOptimal` + `_searchOptimal` + `_tightenObjectiveDomain`
     for integrated branch-and-bound, plus the new `_checkpoint`
     method (called per decision; polls `cancelToken`, yields
     every 100 decisions so `.timeout()` fires) and a
     `_clauseWatchers` side-table for the watched-literal scheme.
7. **`test/`** — 25 files, 440 test cases. New work follows the
   same one-file-per-feature pattern. The most-recent additions:
   `cancellation_test.dart` (13 tests, this batch), and
   `clause_test.dart` (now 20 tests, +4 watched-literal correctness
   tests this batch).
8. **`doc/`** — six topical guides (algorithms, parser grammar,
   multi-solutions, min-conflicts, global-cardinality,
   set-variables). Any new non-trivial feature should get a
   similar guide.
9. **`benchmark/benchmark.dart`** — perf regression suite, 9
   classic CSPs (including both predicate-only and linear forms
   of SEND+MORE for side-by-side comparison), called from CI on
   push to main.

You do NOT need to read git log line-by-line. The commits are
well-titled (`<area>: <one-line summary>`) so skim
`git log --oneline` to triangulate when needed.

---

## 2. Conventions you must follow

These have been established by every commit and the test suite
enforces some of them. Don't deviate without a strong reason.

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
  `Problem`: `BuiltinConstraints`, `StringConstraints`,
  `ProblemDebug`, `MultipleSolutions`, `ReifiedConstraints`,
  `LogicalConstraints`, `GlobalConstraints`, `LinearConstraints`,
  `SoftConstraints`, `SetVariables`. New feature areas should get
  their own extension if they introduce a coherent group of
  methods.
- **Validation throws `ArgumentError`** with a message that names
  the offending variable/argument. Tests rely on this.
- **`lastStats` is a single static slot on `CSP`.** It's shared
  across every `Problem` instance — a solve on one overwrites
  the most recent solve on any other. Tests that compare stats
  across two solves must capture `lastStats` immediately after
  each call. This gotcha is documented in `Problem.lastStats`
  and in STABILITY.md.

### Problem-level solution post-processing

Every `Problem`-level solve entry point routes its result through
`_wrapResult` (for `Future<dynamic>`) or `_wrapStream` (for
`Stream<Map<String, dynamic>>`), which calls `_materializeSets` on
each success map. This is a no-op when `_setVarUniverses` is empty
but is the mechanism that lets `addSetVariable` surface set
variables as `Set<dynamic>` and strip indicator names. If you add
a new solve entry point on `Problem` (e.g., isolate-based runner),
it MUST wrap through the same helpers or set variables will leak
their indicators.

### The arity-dispatch gotcha (still hot)

`Problem.addConstraint([v1, v2], pred)` dispatches by arity:

- 2 variables → expects `BinaryPredicate` (`bool Function(dynamic, dynamic)`); registers both directions for AC-3.
- 1 or 3+ variables → expects `NaryPredicate` (`bool Function(Map<String, dynamic>)`); registers as one `NaryConstraint`.

**If your helper is naturally an n-ary predicate but its variable
list might happen to be exactly 2 vars, use the private
`Problem._addNary(vars, predicate)` helper instead.** It bypasses
the binary dispatch and always registers as `NaryConstraint`.

**For helpers that need to set a dispatch flag on the
`NaryConstraint`** (allDifferent, linearSpec, regularDfa, circuit,
gccSpec, cumulativeSpec, clauseSpec), don't use `_addNary` — it
doesn't take spec fields. Construct the `NaryConstraint` directly
and append to `_naryConstraints`. See `addAllDifferent`,
`addRegular`, `addCircuit`, `addGcc`, `addGccRanges`,
`addCumulative`, `addClause`, the `LinearConstraints` extension
methods for examples.

### The tagged-constraint leaf-check gotcha (load-bearing)

Tagged constraints (those with `allDifferent`, `linearSpec`,
`regularDfa`, `circuit`, `gccSpec`, `cumulativeSpec`, `clauseSpec`)
**bypass the generic `_reviseNary` path** in the engine. This
means **the constraint's soundness predicate is NOT invoked at
leaves** — soundness rides entirely on the propagator catching
every infeasible state.

Each propagator must therefore detect a leaf state (every
constraint variable is a singleton) and report infeasibility
correctly. Patterns vary:

- The GCC propagator promotes a soft fallback to a hard `null`
  return when the matching is unique (`allSingleton`).
- The cumulative propagator relies on the standard pruning path:
  when every start is singleton, each task's compulsory part is
  exactly its scheduled interval, the profile equals the realized
  usage, and any over-capacity step forces the lone feasible
  candidate out of some task's domain so the engine reports
  infeasibility from the resulting empty domain. No separate leaf
  check is required because the per-candidate filter already
  catches the bad case.
- The clause propagator's "all literals falsified" branch is
  exactly the leaf detection — when every variable is singleton
  and every literal is false, the propagator returns `null`.

Mirror whichever pattern fits when designing a new specialized
propagator. The choice depends on whether the propagator's normal
loop already catches the leaf case (cumulative, clause) or whether
the leaf needs an explicit check (GCC).

### Trail-based undo + the engine assumption to watch out for

The engine (`_BacktrackEngine` in `solver.dart`) maintains a single
append-only trail of `(varName, _DomainRep)` pairs. **Every domain
mutation must go through `_setDomain(varName, newDom)`** (which
takes a `List<dynamic>`) or **`_setDomainRep(varName, newRep)`**
(which takes a `_DomainRep` directly) so the mutation is recorded
on the trail. `_setDomain` wraps appropriately: a bitset-backed
variable gets a fresh `Uint64List` built from the kept values; an
interval-backed variable detects contiguous kept lists and
preserves the rep; a list-backed variable stores the list directly.
Backtrack is `_trailRollback(mark)` which undoes only what changed
since `mark`.

**Engine assumption** (relevant for any new search variant): when
`_propagate` is called, the engine assumes all current domains are
non-empty. `_reviseNary` treats a pre-existing empty domain as "no
change" rather than a wipeout — so anyone tightening domains
*outside* of propagation (e.g. the integrated B&B does this for the
objective variable) must either avoid creating pre-existing empties
or guard against them at the leaf. The integrated B&B uses an
`_optProven` flag and a top-of-search empty-domain guard; mirror
that pattern if you add a similar tightening mechanism.

The specialized propagators don't know about the trail directly —
they take an `applyUpdate(String, _DomainRep)` callback at
construction (the engine passes `_setDomainRep`). Each propagator
builds its reduction via `oldDom.filter(predicate)` so the
resulting rep is of the same kind as the source when possible
(bitset stays bitset, interval stays interval unless the predicate
creates holes). Keep this decoupling in any new propagator.

### Per-constraint side-table convention

Most specialized propagators are **stateless across calls** — they
reconstruct working state (Hopcroft-Karp matching, time-table
profile, etc.) from scratch each `propagate()` invocation. Six of
the seven specialized propagators follow this pattern.

The exception is `_ClausePropagator`, which uses the textbook
two-watched-literal scheme (Moskewicz et al., Chaff 2001) and
therefore needs per-clause mutable state across calls. It reads
and writes that state through a side-table on the engine:

```dart
final Map<ClauseSpec, _ClauseWatchState> _clauseWatchers =
    HashMap(equals: identical, hashCode: identityHashCode);
```

**No trail-aware rollback is needed for this side-table.** Domain
reductions in the engine are monotone under the trail — backtrack
only restores previously-removed values, never removes new ones —
so a watcher pointing at a non-falsified literal at a deeper
assignment is also non-falsified at any shallower one. The watcher
state stays valid as the engine unwinds. The textbook concern
about trailing watcher updates doesn't apply here.

If you add another stateful propagator, follow this pattern:
1. Add `final Map<<YourSpec>, _YourState> _yourSideTable = HashMap(equals: identical, hashCode: identityHashCode);` to `_BacktrackEngine`.
2. Pass it to your propagator's constructor at the dispatch site.
3. Verify your state is monotone under backtrack (same argument as
   watchers). If it's not — i.e. if your state could become *invalid*
   after a rollback because the rollback re-introduces conditions
   you assumed were gone — you'd need to add a separate trail entry
   for your state. None of the current propagators need this.

### Domain representation (three reps)

The engine stores domains as `Map<String, _DomainRep>` where
`_DomainRep` is an abstract class with **three** implementations,
chosen per-variable at engine construction by `_classifyDomain`
(a sealed-class dispatcher in `solver.dart`):

- `_BitsetRep` — strictly-ascending list of `int` with span
  `max - min + 1` ≤ 1024. `Uint64List` + integer offset; O(1)
  membership, O(N/64) filter. **Stays bitset on filter** (no
  promotion).
- `_IntervalRep` — contiguous-ascending `int` range with span
  `> 1024`. Stores just `(min, max)`; O(1) membership / length /
  bounds. `.filter(predicate)` stays as `_IntervalRep` when the
  kept set is still contiguous and promotes to `_BitsetRep` (if
  the new span fits) or `_ListRep` when the predicate creates
  interior holes.
- `_ListRep` — everything else (mixed types, non-monotonic int,
  non-contiguous int with span > 1024, strings, doubles).
  `List<dynamic>`; O(n) membership and filter.

Propagators read via the rep API: `.values` (iteration),
`.length`, `.first`, `.isEmpty`, `.isNotEmpty`, `.contains(v)`,
`.filter(predicate)`, `.asList`. They write via the rep-aware
`applyUpdate(varName, _DomainRep) -> void` callback.

### Test conventions

- One test file per feature area: `test/<feature>_test.dart`.
- Use `group()` for sub-areas; descriptive test names ("does X when
  Y", "throws on Z").
- Cover: happy path, edge cases, validation errors. For solvers,
  include at least one classic problem (queens / sudoku / map
  coloring / graph 3-coloring / RCPSP) as a regression.
- Use `await p.getAllSolutions()` (or manual stream-drain with
  `p.getSolutions()`) to verify enumeration count and per-solution
  invariants — much stronger than just checking the first solution.
- For new globals, write at least one test that asserts equivalence
  to an existing constraint (e.g. `addGcc` with each value count =
  1 should enumerate the same solution set as `addAllDifferent`;
  `addCumulative` with cap=1 and all-dem=1 should match
  `addNoOverlap`; an `addClause` set should reduce to known SAT
  examples like XOR or 3-coloring). These tests catch semantic
  drift.
- For new propagators, write at least one test asserting
  measurable propagator activity — usually
  `expect(p.lastStats!.naryRevises, greaterThan(0))` after a solve
  — so silent regressions to the predicate-only path get caught.
- When comparing stats across two solves, **capture `lastStats`
  immediately after each call** — the static slot gets overwritten
  by the second solve. The linear-propagator metric test had this
  bug initially and the partial-state regular test exercises the
  pattern.
- **Dart Set identity-equality bites.** Two `Set<dynamic>{}` are
  not `==` even when they have the same elements. For comparing
  set-of-set results, convert to canonical string keys (e.g.
  sorted-element comma-join) — see
  `test/set_variables_test.dart`'s `key()` helper for the
  pattern.

### Commit messages

Follow what's there. Pattern:

```
<area>(<scope>): <one-line summary>

<paragraph explaining the change and why>

<bullet points of API or behavior changes>

<test coverage summary with new total>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

`<area>` is one of: `feat`, `fix`, `solver`, `docs`, `chore`,
`test`, `ci`, etc. `<scope>` is the feature area (`reified`,
`global`, `soft`, `engine`, `stats`, `set-vars`, `logical`, ...).

### Per-feature acceptance gate

Before each commit:

```bash
cd ~/code/dart_csp
dart format --output=none --set-exit-if-changed .   # zero changes
dart analyze --fatal-infos                          # zero issues
dart test                                           # zero failures
```

`dart analyze --fatal-infos` is strict — even info-level lints fail
it. Common gotchas: `prefer_single_quotes`,
`unnecessary_parenthesis`, `avoid_redundant_argument_values`,
`omit_local_variable_types`, `unnecessary_brace_in_string_interps`,
`unnecessary_lambdas` (use tear-offs when possible),
`prefer_expression_function_bodies`. Just fix them as they come
up.

For intentional redundant arguments (e.g. tests that explicitly
pass the default value for symmetry with the non-default variant),
use a file-level `// ignore_for_file: avoid_redundant_argument_values`
near the imports — see `test/consistency_level_test.dart` for the
pattern.

### README + PLAN.md + CHANGELOG + STABILITY.md per commit

Each feature commit also updates:

- **`PLAN.md`** — flip the item from `[ ]` to `[x]` (or `[~]` if
  partial) and append a short description of what shipped,
  including test count. Be honest about scope limitations (the
  GCC entry notes the conservative lower-bound GAC; the bitset
  entry notes there's no perf delta on existing benchmarks; the
  isolate-parallelism entry now notes the worker-isolate runner is
  deferred even though the cancellation half shipped).
- **`README.md`** — add a new section (or subsection under an
  existing one) for any user-visible feature. Pattern: short prose
  intro, code example, table of methods if there are several.
  Existing sections are the template.
- **`CHANGELOG.md`** — add an entry under `## Unreleased` (don't
  promote to a versioned heading; the maintainer decides when to
  cut a release).
- **`STABILITY.md`** — classify the new API as stable or
  experimental.

If the feature has non-trivial semantics or design decisions
worth documenting separately, add a `doc/<feature>.md` topical
guide and reference it from the README's "Documentation" section.
The most recent example is `doc/set-variables.md`.

---

## 3. Repo layout

```
dart_csp/
├── lib/
│   ├── dart_csp.dart                # top-level export + convenience funcs
│   └── src/
│       ├── types.dart               # public types: CancellationToken,
│       │                            # SolverStats, Dfa, LinearSpec,
│       │                            # LinearOp, GccSpec,
│       │                            # CumulativeSpec, ClauseSpec,
│       │                            # ConsistencyLevel, typedefs
│       ├── problem.dart             # Problem builder + every extension
│       │                            # (incl. SetVariables) + set-var
│       │                            # registry + materialization helpers;
│       │                            # every solve entry point accepts
│       │                            # cancelToken: CancellationToken
│       ├── builtin_constraints.dart # factory functions
│       ├── constraint_parser.dart   # string parser
│       └── solver.dart              # CSP, _BacktrackEngine (with
│                                    # _checkpoint + _clauseWatchers),
│                                    # 7 specialized propagators
├── test/                            # 25 files, 440 tests
│   ├── dart_csp_test.dart
│   ├── builtin_and_parser_test.dart
│   ├── minconflicts_tests.dart
│   ├── multisolutions_tests.dart
│   ├── alldifferent_propagator_test.dart
│   ├── optimization_test.dart       # incl. integrated-B&B tests
│   ├── restart_test.dart
│   ├── dom_wdeg_test.dart
│   ├── symmetry_breaking_test.dart
│   ├── reified_constraints_test.dart
│   ├── logical_combinators_test.dart
│   ├── global_constraints_test.dart       # element, table
│   ├── global_cardinality_test.dart       # among, nvalue, gcc, GCC propagator
│   ├── circuit_and_bin_packing_test.dart  # circuit propagator + bin_packing
│   ├── regular_constraint_test.dart       # regular + partial-state propagator
│   ├── soft_constraints_test.dart
│   ├── stats_test.dart                    # stream + MC stats coverage
│   ├── consistency_level_test.dart        # FC ↔ AC
│   ├── linear_propagator_test.dart        # bounds-consistency linear
│   ├── bitset_domain_test.dart            # rep eligibility + correctness
│   ├── interval_variables_test.dart       # _IntervalRep + addRangeVariable + addNoOverlap (now → cumulative)
│   ├── set_variables_test.dart            # addSetVariable + helpers + materialization
│   ├── cumulative_test.dart               # addCumulative + time-table propagator
│   ├── clause_test.dart                   # addClause + unit propagation + watched-literal correctness
│   └── cancellation_test.dart             # CancellationToken + .timeout() integration
├── example/                         # demo + per-API walkthroughs
├── benchmark/benchmark.dart         # CI-run perf regression (9 benches)
├── doc/                             # topical deep-dive guides (6 files)
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

## 4. The dispatch / extension pattern, for new features

Most prior tier-2 work follows the same structure. To add a new
constraint helper, expect to touch:

1. **`lib/src/types.dart`** (optional) — if the constraint needs a
   new dispatch flag on `NaryConstraint` (e.g. `gccSpec`,
   `regularDfa`, `cumulativeSpec`, `clauseSpec`), add the value
   type and the field here.
2. **`lib/src/builtin_constraints.dart`** (optional) — if your
   feature introduces a new constraint factory, add it here.
3. **`lib/src/problem.dart`** — add a new extension `MyFeature on
   Problem` near the end of the file, alongside the others. Use
   `_addNary` for n-ary predicates without dispatch flags;
   construct `NaryConstraint` directly when you need to set a
   flag.
4. **`lib/src/solver.dart`** (only if needed) — only touch if the
   feature requires propagation changes, new heuristics, or new
   solver entry points. For a new specialized propagator: add the
   propagator class near the other `_*Propagator` classes; add a
   dispatch branch in `seedFor` (single canonical task per
   constraint) and in `_propagate`'s n-ary task branch; mirror
   the shape of the existing seven propagators. Remember the
   leaf-check gotcha.
5. **`test/<feature>_test.dart`** — full coverage (see test
   conventions in §2).
6. **`README.md`** — new section or subsection.
7. **`PLAN.md`** — flip the item.
8. **`CHANGELOG.md`** — `## Unreleased` entry.
9. **`STABILITY.md`** — classify the new API as stable or
   experimental.
10. **`doc/<feature>.md`** (optional) — for substantial features.

---

## 5. Useful patterns from the existing code

- **Optional flags on engine constructor.** When adding solver-mode
  variants (restarts, dom/wdeg, consistency level), thread an
  optional parameter through `CSP.solve*` to `_BacktrackEngine(csp, …)`.
  Don't duplicate engine logic.
- **One method per arity dispatch.** When adding a public helper
  that registers a constraint, route through `addConstraint` for
  binary fast-path when possible, fall through to `_addNary`
  (or direct `_naryConstraints.add` for tagged constraints) when
  the predicate is naturally n-ary.
- **Auto-add boolean variables.** The `ReifiedConstraints` extension
  auto-adds the result bool var with domain `[0, 1]` if the user
  hasn't already added it. Mirror this for any new helper that
  produces a derived variable.
- **Copy on optimization.** Historical: `Problem._optimize` used to
  operate on `copy()`. The integrated B&B does NOT copy — it
  runs directly on the user's `CspProblem` but only mutates the
  engine's internal `_domains` and `_trail`, never the user's
  variable map. Any new search-with-augmentation should follow
  the integrated pattern (avoid copy overhead) but be careful to
  preserve the "don't mutate the original" invariant tested by
  `test/optimization_test.dart`. **`Problem.copy()` propagates
  the set-variable registry** — if you add new Problem-level
  state in another extension, propagate it in `copy()` too or
  `maximizeSatisfaction` (which copies internally) will lose it.
- **Count-variable + fixed-k twin form** for new helpers that count
  something. See `addAmong` + `addAmongExactly`, `addNvalue` +
  `addNvalueExactly`, `addSetCardinality` + `addSetCardinalityVar`.
  The variable form lets users compose with `minimize`/`maximize`;
  the fixed-k form is the clean common case.
- **Predicate + tagged-flag pattern for new globals.** The current
  norm is: keep the soundness predicate (for the engine's generic
  paths even though tagged constraints bypass it), AND set the
  dispatch flag. Soundness depends on the propagator's leaf-check
  alone for tagged constraints, but the predicate stays as belt
  and braces. Every specialized propagator follows this pattern.
- **Conservative-at-non-leaf, strict-at-leaf pattern** for partial
  GAC. When a propagator can't prove infeasibility from its
  matching but the matching is unique at a leaf, promote the soft
  fallback to a strict `null` return. The GCC propagator
  demonstrates this — it's load-bearing for soundness.
- **Decomposition-into-existing-primitives pattern.** The set
  variables work uses this: each set var decomposes into per-
  element 0/1 indicator vars, and the set helpers compose
  pairwise binary or ternary n-ary constraints over those
  indicators. Cumulative-style new globals could in principle
  use a similar approach, but the time-table propagator pays off
  enough that dedicated propagation is worth it; for "purely
  syntactic" features (e.g. union of constraints) the
  decomposition approach is the right starting point and lets
  you skip the propagator entirely.
- **Solution post-processing on Problem.** The `_materializeSets`
  / `_wrapResult` / `_wrapStream` helpers on `Problem` rewrite
  solver-returned maps before they hit user code. New
  Problem-level features that need to expose derived values
  rather than raw internal vars should follow the same pattern.

---

## 6. What's left in PLAN.md, and how to pick

As of this handover, every well-scoped one-session item is
shipped. The remaining open work is the three Tier 3 substantial
items. Read carefully before picking — and seriously consider
whether your session has the runway for the choice you make.

### Tier 3 — substantial items

- **Worker-isolate runner** — *Large, well-bounded now.* The
  cooperative-checkpoint half of the original "isolate parallelism"
  item shipped in this batch (`CancellationToken` + `_checkpoint`
  yields + bounded-latency `.timeout()`), so the entry sits at
  `[~]`. What's left is the worker-isolate runner itself:
  * **New entry point**:
    `CSP.solveInIsolate(Problem Function() build, {CancellationToken? cancelToken, ConsistencyLevel consistency})`
    that takes a builder closure (not a constructed `Problem` —
    closures captured in predicates aren't `Isolate.run`-sendable
    in general). The builder runs *inside* the worker isolate to
    construct the problem fresh there.
  * **Mirror methods on `Problem`** are awkward since `Problem`
    instances themselves can't cross the boundary. The cleanest
    surface might be top-level convenience functions like
    `solveProblemInIsolate(build:, timeout:, ...)` rather than
    instance methods.
  * **Stats round-trip.** `CSP.lastStats` is a static slot in the
    main isolate. The worker fills its own `lastStats`; on
    completion, send the stats over the port and write them into
    the main isolate's slot before resolving the returned Future.
    This preserves the "stats are populated by the time the future
    resolves" invariant.
  * **Cancellation across isolates.** `CancellationToken` is a
    plain Dart object; the simplest thing is to spawn a token
    *inside* the worker and bridge the parent-side token by
    sending a "cancel" message over a SendPort when the parent
    token is cancelled. The cancellation tests for this would need
    to use `Isolate.kill` for hard timeouts only as a fallback.
  * **Testing.** Verifying real cancellation/timeout under
    isolates is similar to what's in `cancellation_test.dart`
    today; allow longer wall-clock bounds because spawning an
    isolate has measurable startup cost.

  Realistic scope: ~400–600 LOC including tests + docs, but the
  design problems are now well-understood (the cancellation work
  this session demystified most of them). One dedicated session
  should be enough.

- **Conflict-directed backjumping / nogood learning** —
  *Large, algorithm-heavy*. Real CDCL is a major project. A first
  cut could be conflict-set tracking + backjumping to the latest
  decision in the conflict set (~300 LOC); full LCG/nogood
  recording is much more. The implementation requires deep
  familiarity with `_BacktrackEngine`'s decision tracking and the
  trail.

- **MiniZinc / FlatZinc / XCSP3 frontend** — *Multi-day*. Adds a
  parser for one of the standard CP modeling languages. Big
  ecosystem unlock (lets dart_csp ingest academic benchmarks);
  not on any user's immediate critical path. Definitely not
  one-session sized.

### Smaller possibilities (not in PLAN.md yet)

- **Per-variable watch lists for the clause propagator.** The
  current implementation wakes the propagator whenever *any*
  variable in the clause changes; a per-variable watch list would
  only wake clauses whose currently-watched literal is on the
  changed variable. Would change `naryRevises` counters but not
  pruning. Probably a few hundred LOC.
- **A doc/cancellation.md topical guide.** The README has the
  user-facing summary and the algorithms doc has the async
  paragraph; a topical guide with worked timeout examples and the
  cancel-vs-infeasibility discussion would fit the pattern.
- **Larger `LinearSpec` integer ranges.** The bounds-consistency
  linear propagator computes sums as `num`; rounding for doubles
  becomes a concern at extreme ranges. Audit if you take on a
  problem domain that needs it. Likely small in scope but the
  test surface is broad.

### Picking criteria

Choose the item that has the best fit between:

- **User value** — how often it gets reached for in real CSP
  modeling.
- **Self-contained scope** — doesn't pull in other unfinished
  work.
- **Size match to one session** — if you can ship it in ~1000
  LOC including tests, prefer it over a multi-day project.
- **Honest assessment of the design risk** — the worker-isolate
  runner is now substantially de-risked thanks to the
  cancellation work in this batch; CDCL still needs deep engine
  familiarity; a frontend is multi-session.

### Recommendation

If you don't have a preference, the highest-value remaining item
is the **worker-isolate runner**. It closes the tier-3
isolate-parallelism entry, lets users genuinely parallelise solves
across cores (the cooperative yield from this batch helps single-
isolate responsiveness but doesn't help throughput), and the
design problems are now well-understood. Plan on a dedicated
session for it.

If you don't have a preference, the recommendations are (in
order):

1. **Cooperative yield + cancellation token** (the smaller
   scope cut of isolate-based parallelism). ~150 LOC, closes
   the documented `.timeout()` gotcha, lays groundwork for
   the full worker-isolate runner without committing to its
   API design. Highest user value of the remaining items.
2. **Watched-literal data structure for clauses.** Flips the
   tier-2 variable-types entry to `[x]`. Pure perf win;
   requires a small engine infrastructure change (per-
   constraint side-table with trail-aware rollback) that
   would also unblock future stateful propagators.
3. **`addNoOverlap` → `addCumulative` dispatch.** Small but
   real cleanup; closes a flagged follow-up. Could be
   bundled with another feature in the same commit to amortize
   docs overhead.
4. **Full worker-isolate runner** (the larger scope of
   isolate-based parallelism). Substantial but cleanly
   bounded once the builder-function API is committed to. Best
   tackled as a dedicated session after the cooperative-yield
   piece is in.
5. **CDCL backjumping** — Algorithm-heavy; pick only if you're
   prepared for an engine-internals deep dive and a longer
   session.
6. **MiniZinc/FlatZinc/XCSP3 frontend** — Multi-session;
   should be a deliberate project, not a one-session pick.

---

## 7. What NOT to do

- **Don't touch the licensing posture.** `LICENSE` is MIT,
  `NOTICE` documents the history, the clean-room status is
  established. Leave it.
- **Don't read `dartCSP-archive`.** It's the now-private predecessor
  repo. Everything you need is in this repo.
- **Don't refactor existing features for cosmetics.** If you find
  something genuinely wrong, fix it — but don't reshape working
  code without a behavioral reason.
- **Don't introduce new dependencies** without a strong reason. The
  whole library is pure Dart, zero deps, and that's a feature.
- **Don't change the failure-literal convention** (`'FAILURE'`) or
  the return types of existing solve entry points. Tests rely on
  these and so does the existing user surface. (Isolate-based work
  will add *new* entry points alongside the existing ones, not
  change them.)
- **Don't bypass `_setDomain` / `_setDomainRep`** for any domain
  mutation in the engine. The trail relies on every mutation
  routing through them. The integrated B&B's
  `_tightenObjectiveDomain` is the one exception (it modifies
  past trail entries in-place, not through `_setDomain`); mirror
  that pattern only if you need the same semantics.
- **Don't claim a tagged constraint is sound without a leaf check.**
  Tagged constraints bypass the engine's `_reviseNary` path, so
  the predicate is never called at leaves. Every specialized
  propagator must detect leaf states (all constraint vars
  singleton) and verify the constraint there — either via an
  explicit `allSingleton` check (GCC pattern) or by ensuring the
  normal propagation loop already catches the leaf case
  (cumulative, clause pattern).
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

At the time this handover was written, the suite passes **440 test
cases across 25 files** in ~30 seconds (the cancellation tests
account for most of the wall-clock since they spin up hard CPU-
bound problems and wait for cancel timers). The benchmark suite
runs 9 problems (including both SEND+MORE forms) in ~2 seconds.
CI is green on `main`
(`gh run list --repo CrispStrobe/dart_csp --limit 1`). If your
first `dart test` doesn't match this, something is wrong with the
environment — investigate before adding new code.

Recent commits worth knowing about (latest first):

- `31afbef` — `addNoOverlap` now dispatches to `addCumulative`
  (closes the flagged follow-up; strictly stronger pruning,
  same semantics)
- `e50e55e` — two-watched-literal data structure for
  `_ClausePropagator` (Chaff 2001; per-engine `_clauseWatchers`
  side-table; first stateful propagator)
- `c3aef07` — cooperative cancellation + `CancellationToken`
  (engine yields every 100 decisions, `.timeout()` now fires)
- `7a05fe5` — SAT-style clause constraint + unit-propagation
  propagator (`addClause`, `ClauseSpec`)
- `0f375c2` — cumulative resource constraint + time-table
  propagator (`addCumulative`, `CumulativeSpec`)
- `95c9c49` — set variables via per-element indicator
  decomposition (`addSetVariable` + 10 set helpers + solution
  materialization)
- `1b32c63` — interval-rep domain + `addRangeVariable` /
  `addNoOverlap` (scheduling primitives)
- `bf90b27` — rep-aware filter callback for specialized
  propagators (perf, closes a follow-up flagged in the bitset
  commit)
- `f9934a1` — Régin network-flow GCC propagator
- `f4a777e` — cycle-detection circuit propagator
- `22132bd` — bitset domain representation (closes Tier 1)
- `fe842f0` — partial-state regular propagator (Pesant 2004)

Good luck.

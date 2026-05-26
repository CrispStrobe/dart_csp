# API Stability

This document records which parts of the `dart_csp` public API are
stable and which are experimental, and explains the versioning
policy that governs how they may change.

The current published version is **2.x**. The goals of this policy
are (a) to let users depend on the core solver without surprise
breakage and (b) to give the library room to evolve in places where
the right design is still being explored.

---

## Versioning policy

`dart_csp` follows [semver](https://semver.org/) on the surface
listed below as **stable**:

- **Patch release** (`2.1.0` → `2.1.1`): bug fixes, performance
  improvements, internal refactors, documentation. No behavioral
  changes to stable APIs. Stronger pruning from a propagator is a
  patch — it can change `SolverStats` counters without breaking
  callers.
- **Minor release** (`2.1.0` → `2.2.0`): additive changes —
  new constraint helpers, new optional parameters with defaults
  that preserve old behavior, new extension methods, new types in
  a non-breaking way (added fields with sensible defaults, new
  enum variants where switches are not exhaustive on the user
  side).
- **Major release** (`2.x.y` → `3.0.0`): breaking changes to the
  stable surface. Renames, removed methods, changed return types,
  changed default values that alter behavior, new required
  parameters. A major release is preceded by a deprecation period
  on the prior minor where applicable.

Changes to **experimental** APIs do not follow semver. They may
change shape or be removed in any release (including patch), though
they will appear in the CHANGELOG.

---

## What's stable

Everything in this list has been in the library for at least one
minor release, has full test coverage, and is governed by the
semver rules above.

### Problem builder

- `Problem` class and its constructor.
- `addVariable`, `addVariables`.
- `addConstraint` (the arity-dispatching public method).
- `addStringConstraint`, `addStringConstraints` and the full
  grammar accepted by the parser.
- `clear`, `copy`, `variableCount`, `constraintCount`, `variables`,
  `setOptions`.

### Solving

- `getSolution`, `getSolutions`.
- `getSolutionWithDomWdeg`, `getSolutionWithActivity`,
  `getSolutionWithImpact`, `getSolutionWithLastConflict`,
  `getSolutionWithRestarts` (the `useDomWdeg:`, `useVsids:`,
  `useImpact:`, and `useLastConflict:` flags on the restart entry
  point — and the `useDomWdeg:` / `useVsids:` / `useImpact:` flags
  on `getSolutionWithLastConflict` — are part of the stable
  surface).
- `minimize`, `maximize`.
- `solveWithMinConflicts` (including `maxSteps`, `seed`).
- The static `CSP` mirrors: `CSP.solve`, `CSP.solveAll`,
  `CSP.solveWithDomWdeg`, `CSP.solveWithActivity`,
  `CSP.solveWithImpact`, `CSP.solveWithLastConflict`,
  `CSP.solveWithRestarts`, `CSP.solveWithMinConflicts`,
  `CSP.solveOptimal`.
- The failure literal `'FAILURE'` as the return-shape for "no
  solution found". This will not change to `null` or an exception.

### Constraint helpers

- The `BuiltinConstraints` extension (`addAllDifferent`,
  `addAllEqual`, `addExactSum`, `addSumRange`, `addExactProduct`,
  `addInSet`, `addNotInSet`, `addAscending`,
  `addStrictlyAscending`, `addDescending`, `addLexLeq`,
  `addLexLt`, `addLexChain`, `addValuePrecedence`).
- The `ReifiedConstraints` extension and its full method set.
- The `LogicalConstraints` extension and its full method set.
- The `GlobalConstraints` extension: `addElement`, `addTable`,
  `addAmong`, `addAmongExactly`, `addNvalue`, `addNvalueExactly`,
  `addGcc`, `addGccRanges`, `addCircuit`, `addSubcircuit`,
  `addBinPacking`, `addRegular`, `addInverse`, `addDiffN`.
- The `SoftConstraints` extension (`declareSoft`,
  `addSoftConstraint`, `maximizeSatisfaction`).
- All built-in factory functions exported from
  `builtin_constraints.dart`.

### Types

- `BinaryConstraint`, `NaryConstraint`, `CspProblem`,
  `BinaryPredicate`, `NaryPredicate`, `CspCallback`.
- `Dfa` (value type backing `addRegular`).
- `SolverStats` fields: `decisions`, `backtracks`, `propagations`,
  `binaryRevises`, `naryRevises`, `iterations`, `elapsedMicros`.
  Additional fields may be added in a minor release; existing
  fields will not be removed or change semantic in a minor.

---

## What's experimental

These APIs work and are tested, but their shape may still change
based on usage feedback.

- **`ConsistencyLevel` enum** (`ConsistencyLevel.forwardChecking`,
  `ConsistencyLevel.arcConsistency`,
  `ConsistencyLevel.singletonArcConsistency`) and the `consistency:`
  parameter threaded through `CSP.solve*` and `Problem.getSolution*`
  / `Problem.minimize` / `Problem.maximize`. The forward-checking
  semantics (cascade only on a newly-singleton domain) are a
  considered choice. `singletonArcConsistency` is SAC-1 (Debruyne &
  Bessière 1997) — AC during search plus a tentative-pin
  preprocessing pass at the top of search — and is the first of a
  possible family of singleton-consistency variants; the value name
  is unlikely to change but additional levels (e.g. path
  consistency, stronger SAC variants, restricted SAC) may be added,
  which could affect callers that exhaustively switch on it.
- **`LinearSpec`, `LinearOp`, and the `LinearConstraints` extension**
  (`addLinearEquals`, `addLinearLeq`, `addLinearGeq`). Recently
  added; the propagator implements bounds consistency and the
  numeric-domain validation may evolve (e.g. opening the API to
  rational or interval-valued coefficients).
- **`NaryConstraint.allDifferent`, `NaryConstraint.linearSpec`, and
  `NaryConstraint.subcircuit` fields.** These are dispatch flags
  consumed by the solver. End users typically should not construct
  `NaryConstraint` directly; use the extension helpers instead. The
  `subcircuit` flag in particular shares the cycle-detection
  propagator with `circuit` and may be unified or renamed in a future
  release.
- **Stronger propagators** in general. Régin allDifferent, bounds-
  consistency linear, partial-state regular (future), cycle-
  detection circuit (future) all may strengthen or change which
  values they prune. Calling `lastStats.binaryRevises` or
  `naryRevises` to derive behavioral assertions on specific
  problems is **not** covered by semver.

- **`Problem.addRangeVariable` and `Problem.addNoOverlap`.**
  Range-domain variables (a contiguous integer range as a domain)
  and the unary-resource no-overlap helper. `addNoOverlap` now
  dispatches to [addCumulative] with unit demand and unit capacity,
  so it benefits from the time-table propagator (compulsory-part
  profile + per-candidate pruning) instead of the older `O(n²)`
  pairwise-disjunction encoding. The constraint semantics are
  identical; only propagation strength and `SolverStats` counters
  change. A future stronger propagator (edge-finding, Vilím 2007
  style) may further strengthen pruning without changing semantics.
  The `(min, max)` internal rep is private; the public surface is
  just the two helpers and the existing solve entry points, which
  work transparently with range-domain variables.

- **`Problem.addCumulative` and `CumulativeSpec`.** Integer-capacity
  resource scheduling primitive. The current implementation
  dispatches to a time-table propagator (Beldiceanu & Carlsson
  2002 style) — compulsory-part profile + per-candidate pruning
  with self-contribution removed. The constraint semantics will
  not change, but a stronger edge-finding-style propagator
  (Vilím 2007) may replace or augment the time-table version in a
  future release, which would change `SolverStats` counters and
  wall-clock timings.

- **`Problem.addDiffN` and `DiffNSpec`.** 2D rectangle non-overlap
  (`diff_n`). The current implementation dispatches to a forbidden-
  region sweep propagator (Beldiceanu & Carlsson, CP 2001) — for
  each rectangle and each dimension, aggregate forbidden-position
  intervals induced by other rectangles whose compulsory part in
  the orthogonal dimension forces an overlap, and filter the
  domain in one pass. The constraint semantics are unchanged from
  the previous decomposition-based release; only propagation
  strength and `SolverStats` counters change. A future
  stronger algorithm (true sweep across all rectangles, sweep
  augmented with k-dimensional sweep, or higher-arity globals like
  `cumulative_in_dim`) may replace or augment the current
  implementation, which would change counters and wall-clock
  timings without changing what solutions are produced.

- **`Problem.addClause` and `ClauseSpec`.** SAT-style clause
  constraint over boolean variables. The propagator is the
  textbook two-watched-literal scheme (Moskewicz et al., Chaff
  2001): per-call work is O(1) amortized once the watchers are
  initialized, and the user-visible pruning behavior matches a
  full single-pass unit-propagation scan. The engine's
  propagation queue applies a matching per-variable seeding
  filter: once watchers are initialized, the propagator is only
  woken when one of the two watched literals' variables is
  reduced. Width-2 clauses bypass the filter (both literals are
  always watched, so the check would never fire). Pruning is
  unchanged; counters that observe propagator-call frequency
  (none are currently exposed by `SolverStats`) would reflect
  the reduction.

- **The `SetVariables` extension** (`addSetVariable`,
  `addSetVariables`, the `addSetCardinality*` family,
  `addRequiredInSet`, `addExcludedFromSet`, `addSubset`,
  `addSetEquals`, `addSetDisjoint`, `addSetUnion`,
  `addSetIntersection`, `addSetDifference`, `memberIndicator`,
  `setVariableNames`, `setUniverse`) and the post-processing that
  materializes set variables in every solve entry point on
  `Problem`. The current implementation is a thin sugar layer over
  per-element 0/1 indicator variables; future versions may add a
  dedicated set-domain rep (`(required, possible)` bitsets) and
  specialized propagators (e.g. card(A ∪ B) reasoning). Doing so
  would not change the surface API or the materialized solution
  shape (`Set<dynamic>` of included elements), but could materially
  change `SolverStats` counters and the names exposed under
  `Problem.variables` (which currently surfaces the internal
  `__set__*` indicators — those names are reserved and should not
  be relied upon).

- **`CancellationToken` and the `cancelToken:` parameter** on every
  backtracking and local-search entry point (`CSP.solve*` and the
  matching `Problem` methods including `maximizeSatisfaction`). The
  token API itself (`cancel()`, `isCancelled`, `addListener`) is
  minimal and unlikely to change shape, but two surrounding details
  may evolve: (a) the cancel-result convention (currently always
  `'FAILURE'`, with no incumbent surfaced from cancelled
  optimizations) may grow a richer return type that distinguishes
  cancel from infeasibility and exposes a best-so-far; (b) the
  yield cadence (currently 100 decisions / 200 min-conflicts
  iterations, hard-coded) may become tunable per-solve. The
  cooperative yield itself is part of the engine and applies even
  without a token — which is what makes `.timeout(...)` work —
  and that behavior is expected to remain.

- **Conflict-directed backjumping** — the
  `enableConflictBackjumping: bool = false` parameter on every
  backtracking entry point (`CSP.solve*` and the matching `Problem`
  methods) and the two new `SolverStats` fields `backjumps` /
  `backjumpLevelsSkipped`. The flag itself (opt-in, default off,
  preserves chronological backtracking when unset) is unlikely to
  change shape. Two areas may evolve: (a) the **conflict-cause
  attribution** is currently the per-revision chain-following
  version (each trail entry tags its cause constraint; the conflict
  walk follows the chain of revisions back to earlier-assigned
  contributors); a future refinement to minimal-cause analysis
  (tracking per-value support attribution inside each propagator)
  would tighten the conflict sets further and change
  `backjumpLevelsSkipped` on the same inputs without changing the
  solution set; (b) the **stats counter semantics** could be
  augmented (e.g. separate per-search-mode counters, or counting
  only "real" multi-level jumps versus chronological-equivalent
  returns). The solution-equivalence guarantee (CBJ enumerates the
  same set as plain BT) is part of the contract and is not expected
  to change.

- **Conflict explanation** — the `ConflictExplanation` extension's
  `Problem.findMinimalUnsatisfiableSubset({cancelToken, consistency})`
  (deletion-based, Bakker et al. 1993 / Junker 2001) and
  `Problem.findMinimalUnsatisfiableSubsetQuickXplain({cancelToken,
  consistency})` (QuickXplain, Junker 2004), plus the accompanying
  `ConstraintRef` value type and the `label:` parameter on every
  primary constraint helper. Both MUS methods return the same shape
  (`Future<List<ConstraintRef>?>`) with the same `ConstraintRef`
  semantics; what differs is the algorithm and the cancellation
  contract (deletion's mid-loop cancel returns the sound-but-non-
  minimal kept set; QuickXplain's recursion has no sound mid-flight
  result and returns `null` on any cancel). The two algorithms may
  surface different locally-minimal MUSes for the same problem —
  both are valid; finding the smallest MUS is NP-hard and is not the
  contract. The return type may grow to surface additional structure
  (e.g. a richer `Explanation` wrapper with both the MUS and a
  satisfiable maximal subset). `ConstraintRef.id` is a stable
  identifier within one `Problem` instance for the lifetime of that
  instance, but the `b{i}` / `n{j}` id scheme is not part of the
  contract — callers should treat ids as opaque strings. The `kind`
  label vocabulary may grow as new dispatch flags are added (e.g. a
  future `lcg-clause`); existing labels will not be renamed in a
  minor release. The `label:` parameter on each `addX` helper and the
  resulting `ConstraintRef.label` field are display-only (equality on
  refs is still by `id` alone); the rendering format
  `kind[label](variables)` produced by `ConstraintRef.toString` is
  stable. Coverage spans every primary constraint helper plus every
  constraint-posting set-variable helper and `addSoftConstraint`;
  `addSetVariable` / `addSetVariables` / `declareSoft` don't accept
  `label:` because they don't post constraints (they declare
  indicator variables or mark a bool var as soft), and that gap is
  intentional, not provisional. Constructing `ConstraintRef`
  directly is not part of the stable API — only the refs returned
  from the MUS pass.

- **Worker-isolate runner** (`solveInIsolate`, `solveAllInIsolate`,
  `minimizeInIsolate`, `maximizeInIsolate`, and the accompanying
  `IsolateRunnerException` type). Top-level functions in
  `lib/src/isolate_runner.dart`, exported from `dart_csp.dart`.
  Each takes a `Problem Function()` builder that runs inside the
  spawned worker. The current builder-closure API is a considered
  choice (predicate closures attached to a constructed `Problem`
  are generally not sendable), but two areas may evolve:
  (a) the wire protocol between parent and worker is currently a
  small `List`-based message set (`['ready', port]`, `['result',
  value]`, `['stats', SolverStats]`, `['solution', map]`,
  `['done']`, `['error', msg, stack]`) — internal, not part of the
  public API, but anyone reaching into `lib/src/isolate_runner.dart`
  should treat it as private; (b) the hard-kill grace window
  (currently 250 ms after a timeout-induced cancel) and the use of
  `Isolate.kill()` without a priority argument may become tunable
  for callers that need stricter time bounds. The runner is not
  available on Dart Web (no `dart:isolate`); the test file is
  marked `@TestOn('vm')` for the same reason.

- **FlatZinc frontend** (`FlatZinc.parse`, `FlatZinc.build`,
  `FlatZinc.solve`, the AST node classes — `FlatZincModel`,
  `VarDecl`, `ArrayVarDecl`, `ParamDecl`, `ConstraintItem`,
  `SolveItem`, `Annotation` — and the `VarType` / `AstExpr`
  sealed hierarchies, plus the `LoweredModel` / `OutputArray`
  shapes returned by `FlatZinc.build` / the `lower` function).
  Also experimental: the `bin/dart_csp_fzn` CLI binary, including
  its exit-code mapping (0 success, 64 usage error, 65 parse /
  argument error, 66 file not found, 78 unsupported FlatZinc
  builtin) and the `%%%mzn-stat` output emitted under `-s`.
  Frontend may extend to cover more FlatZinc builtins (variable-
  duration cumulative, set-of-int variables, float variables);
  parser error messages may change; output-formatter rendering
  of bool variables (currently as 0/1, may shift to true/false
  when the lowering pass plumbs the declared type through). The
  CLI's option set (`-a`, `-s`) is unlikely to remove options
  but is likely to grow (e.g. `-f` for free search, `-n N` for
  a solution-count cap, an `--mzn-stat` toggle separating
  human-readable and machine-readable stats output).

---

## What's internal

Everything in `lib/src/*` whose name starts with an underscore is
private. The library's `lib/dart_csp.dart` entry point exports the
public symbols. Reaching into `package:dart_csp/src/...` or
relying on the unexported helper functions (e.g. internal
propagators, Hopcroft-Karp matching) is unsupported and may break
in any release.

Performance characteristics — wall-clock times, decision counts,
backtrack counts — are not part of the API. The library aims for
broad improvements over time and may regress on individual problems
when a propagator becomes stronger in general but unlucky in
specific. Benchmark in your own setting if performance matters to
your application.

---

## Known gotchas

These are documented behaviors that may surprise users but are not
considered bugs.

- **`lastStats` is a single static slot on `CSP`.** A solve on any
  `Problem` instance overwrites the stats from the most recent
  solve on any other instance. Capture `lastStats` immediately
  after the call that produced it if you need to compare runs.
- **`getSolutions()` stats are populated when the stream
  completes** — either by being fully consumed or cancelled. If
  the returned `Stream` is never listened to, `lastStats` is not
  updated.
- **GAC bails out on large free neighborhoods.** For n-ary
  constraints registered through `addConstraint` (i.e. without a
  specialized propagator), the engine skips support enumeration
  when the product of the other variables' domain sizes exceeds an
  internal work bound (currently 4096). This protects worst-case
  cost but reduces pruning. For arithmetic constraints, prefer the
  `LinearConstraints` extension; for set-membership constraints,
  prefer `addInSet` / `addNotInSet`.
- **`.timeout()` on solve futures interrupts the search but with
  bounded latency.** As of the cancellation work in the most recent
  release, the engine yields to the event loop on every ~100
  decisions (and the min-conflicts runner on every ~200 iterations).
  This is what lets a wrapping `Future.timeout(...)` actually fire
  and a `CancellationToken` set from a `Timer` actually be observed.
  The latency between a cancel/timeout deadline and the engine
  reacting is bounded by the time to do ~100 decisions (or ~200
  min-conflicts iterations) — typically tens of milliseconds on
  real CSPs, but can stretch into the low seconds on pathological
  instances where each individual node does heavy propagation. A
  worker-isolate runner is on the roadmap for cases where main-
  isolate execution itself is the problem (e.g. multiple concurrent
  solves on the same VM).

---

## Versioning of this file

This document itself is part of the package and is updated
alongside any change that affects what's stable. The CHANGELOG
records each such update.

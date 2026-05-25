## Unreleased

* **VSIDS-style variable activity heuristic.** New
  `Problem.getSolutionWithActivity()` entry point and matching
  `CSP.solveWithActivity(csp, ...)` static; a `useVsids: true` flag
  on `getSolutionWithRestarts` lets it compose with the Luby
  restart loop. Per-variable activity score lazily populated inside
  `_BacktrackEngine`; on every propagation conflict, every variable
  in the failing constraint's scope is bumped by a growing
  `_activityInc` (multiplicatively grown by `1 / decay` per conflict
  — the standard MiniSat trick; equivalent to uniformly decaying
  every existing activity by `decay` but O(1) per conflict instead
  of O(|vars|)). When `_activityInc` exceeds `1e100` the engine
  rescales every activity (and the increment itself) down by `1e-100`
  to prevent overflow.
  
  The variable picker minimizes `dom(v) / (1 + activity(v))`,
  mirroring dom/wdeg's `dom(v) / wdeg(v)` shape — pre-conflict the
  ratio reduces to MRV; as activity accumulates the picker
  gravitates toward variables that have been near recent failures.
  Useful complement to dom/wdeg on SAT-style instances and on
  problems where the "guilty" structure shifts over the course of
  search (VSIDS's decaying bumps react faster than dom/wdeg's
  monotone weights).
  
  Composes with `consistency:`, `cancelToken:`, and
  `enableConflictBackjumping:`. When both `useVsids` and
  `useDomWdeg` are set, VSIDS wins the picker; both bump tables
  are still updated independently.
  
  The wdeg / VSIDS bump-on-conflict sites in `_BacktrackEngine`
  were refactored into a single internal `_onConflict(c)` helper
  that delegates to whichever flag is on; the 16 per-call-site
  `if (useDomWdeg) _bumpWeight(...)` guards in `_propagate`
  collapsed into one call apiece. Bit-identical behavior under
  every existing test.
  
  Coverage: 12 new tests in `test/vsids_test.dart` — basic feasibility,
  unsat, 6-queens regression, 8-queens stats engagement, agreement
  with MRV on a unique-solution problem, composition with FC,
  CBJ, and restarts (including the "both flags on" case), and the
  static `CSP.solveWithActivity` entry point. 546 tests across 31
  files (was 534).

* **`addDiffN` — 2D rectangle non-overlap.** New
  `Problem.addDiffN(xs, ys, widths, heights)` in the
  `GlobalConstraints` extension. Generalises `addNoOverlap` from a
  unary (1D time) resource to two dimensions: given `n` axis-
  aligned rectangles described by `(xs[i], ys[i])` corners
  (registered variables) and constant `(widths[i], heights[i])`
  sizes, enforces that no two rectangles overlap. Standard CP
  primitive (`diff_n` in MiniZinc, `addNoOverlap2D` in OR-Tools)
  for rectangle packing, floor planning, VLSI placement, 2D
  scheduling, and tile-placement puzzles.

  Half-open box semantics: a rectangle at `(x, y)` with size
  `(w, h)` occupies `[x, x+w) × [y, y+h)`, so two rectangles that
  touch exactly at an edge do not overlap. Zero-area rectangles
  (`width == 0` or `height == 0`) are dropped from the constraint
  — they never conflict with anything.

  Decomposes into `n(n-1)/2` 4-ary disjunction predicates, one per
  unordered pair of rectangles, scoping only
  `(xs[i], ys[i], xs[j], ys[j])` so the engine's generic n-ary GAC
  support search stays cheap per call. For very large instances a
  sweep-based (Beldiceanu & Carlsson) propagator would be a
  worthwhile follow-up; the predicate version is the right
  starting point.

  Validation: throws `ArgumentError` on length mismatch among the
  four lists, on unknown variable names, or on negative widths /
  heights.

  Coverage: 18 new tests in `test/diffn_test.dart` — validation
  (5), single-rectangle edge case, semantics (2 unit rects on a
  grid, 2×2 corners, infeasible same-corner, zero-area cases,
  edge-touching half-open semantics), and integration (1D
  reduction equivalent to `addNoOverlap`, 2×2 tiling enumerating
  4! = 24 distinct placements, mixed-size 2×1 + 1×2 + 1×1 packing
  in 3×2, 2×2 square pair in a 4×2 strip with overlap-free
  verification, one-axis-separable case). 534 tests across 30
  files (was 516).

* **Doc polish: `addClause` docstring** updated to reflect the
  shipped two-watched-literal propagator and the matching
  per-variable seeding filter (was still calling the watched-
  literal optimization "a perf follow-up" from two sessions ago).

* **`addLexChain` helper for n-way row-symmetry breaking.** New
  `Problem.addLexChain(rows, {strict: false})` in the
  `BuiltinConstraints` extension. Sugar over pairwise `addLexLeq`
  (or `addLexLt` when `strict: true`) across every consecutive pair
  in [rows]. Standard idiom for breaking row-permutation symmetry
  in matrix models where every row is interchangeable: posting one
  `lexLeq` per consecutive pair keeps a single canonical row-order
  representative from each permutation orbit. Lex-leq is
  transitive on `Comparable`, so chaining consecutive pairs is
  equivalent to (and cheaper than) posting all `k(k-1)/2` pairwise
  constraints.

  Validation: throws `ArgumentError` on fewer than 2 rows or any
  row-length mismatch (unknown-variable validation reuses
  `addLexLeq` / `addLexLt`'s checks).

  Coverage: 6 new tests in `test/symmetry_breaking_test.dart`
  (validation, 3-row non-decreasing brute-force equivalence,
  strict variant forbidding equal rows, 4-row collapse to
  `C(rowVals + k - 1, k)` multiset count). 516 tests across 29
  files (was 510).

* **Channelling constraint: `addInverse`.** New
  `Problem.addInverse(forward, inverse)` in the `GlobalConstraints`
  extension. Posts the standard inverse-channelling constraint:
  for every `i, j ∈ 0..n-1` where `n = forward.length`,
  `forward[i] = j ⇔ inverse[j] = i`. Standard primitive in CP
  modelling (present in MiniZinc, OR-Tools, Choco) for assignment
  problems and scheduling where the same relation is naturally
  expressed in both directions; some constraints are cleaner on
  the forward map, others on the inverse, and the channelling
  keeps both views consistent.

  Decomposes into `n²` binary constraints so AC-3 can propagate
  effectively; pinning a value on either side immediately prunes
  the corresponding cells on the other. Implies that both lists
  are (partial) permutations of `0..n-1`, so a separate
  `addAllDifferent` is redundant once `addInverse` is posted.

  Validation: throws `ArgumentError` on mismatched lengths, empty
  lists, or unknown variable names.

  Coverage: 11 new tests in `test/global_constraints_test.dart` —
  validation, n=2 enumeration, n=3 enumeration with explicit
  channelling and bijection assertions, redundant-allDifferent
  equivalence, pinning-propagation in both directions, infeasible
  contradiction, and a practical 4×4 task-machine assignment with
  forbidden cells (brute-force-equivalent enumeration). 510 tests
  across 29 files (was 499).

* **Value-symmetry breaking helper: `addValuePrecedence`.** New
  `Problem.addValuePrecedence(variables, values)` and matching
  `valuePrecedence(variables, earlier, later)` factory in
  `lib/src/builtin_constraints.dart`. Standard primitive for
  breaking the symmetry under which interchangeable value labels
  (colors, agents, machine IDs, bin labels) can be permuted without
  changing the solution structure. Companion to the existing
  `addLexLeq` / `addLexLt` sequence-symmetry primitive.

  For each consecutive pair `(values[i], values[i+1])` in [values],
  posts an n-ary precedence predicate that enforces the first
  occurrence of `values[i]` in `variables` strictly precedes the
  first occurrence of `values[i+1]` (or that the latter is unused).
  Posting the full canonical chain breaks up to `k!` value-
  permutation symmetry where `k = values.length`. Values outside
  the canonical list are unconstrained.

  Validation: throws `ArgumentError` on fewer than 2 canonical
  values, on duplicate values, or on unknown variable names. The
  predicate handles partial assignments conservatively (returns
  true unless a violation is definitively visible).

  Coverage: 13 new tests in `test/symmetry_breaking_test.dart`
  covering factory unit tests (partial / decisive / non-violating
  cases, integer values), validation, and integration (K3 triangle
  coloring 6 → 1, 5-node path 3-color 6× shrink, partial value
  usage with brute-force agreement, unconstrained-outside-list
  semantics, composition with `addAllDifferent` collapsing
  4! → 1). 499 tests across 29 files (was 486).

* **Per-variable seeding filter for the clause propagator.** Once a
  clause's two-watched-literal state is initialized, the engine's
  propagation queue no longer wakes the propagator on reductions to
  variables that aren't currently watched. The watched-literal
  invariant is monotone under the engine's trail semantics (a swap
  done deeper in the search remains valid on backtrack), so a
  reduction to a non-watched variable cannot falsify either watcher
  and therefore cannot change the propagator's behavior — skipping
  the wake-up is sound and saves the per-task allocation, queue
  add/remove, and propagator instantiation.

  Width-2 clauses (the typical "at most one" pairwise encoding) skip
  the filter unconditionally: with two literals, both are watched,
  so the check would never fire and adding it is pure overhead. The
  filter applies to clauses with three or more literals — exactly
  the workloads where the textbook scheme pays off.

  Pure perf change; user-visible pruning is identical. Empirical
  win on pigeonhole CNF benchmarks (25-rep median):
  - 7-pigeon / 6-hole UNSAT: plain 136 → 112 ms (-18%), CBJ 44 → 37 ms (-16%).
  - 8-pigeon / 7-hole UNSAT: plain 1715 → 1367 ms (-20%), CBJ 347 → 292 ms (-16%).
  Non-clause benchmarks unchanged (the seedFor branch is a single
  `c.clauseSpec != null` field load + null check). New
  `pigeonhole CNF 7-in-6 (UNSAT)` benchmark added to
  `benchmark/benchmark.dart` (plus the matching builder in
  `benchmark/problems.dart` and a CBJ-correctness test in
  `test/cbj_benchmarks_test.dart`).

  Coverage: 2 new `test/clause_test.dart` cases for the filter —
  a wide-clause case where many non-watched variables are pinned
  (asserts the enumeration matches the brute-force count) and a
  watcher-swap-then-non-watched-change case (asserts the optimizer
  correctly re-targets wake-ups to the new watched variable after
  a swap). 486 tests across 29 files (was 483).

* **CBJ conflict-cause: per-revision provenance + chain following.**
  Replaces the original constraint-graph-neighborhood approximation
  with a tight per-revision attribution. Every trail entry now
  carries the constraint that caused the mutation
  (`_TrailEntry.cause` — a `BinaryConstraint` for AC-3 revises, a
  `NaryConstraint` for any GAC revise or specialized propagator
  reduction, `null` for decision-site assignments). The CBJ
  conflict-cause walk inspects each entry's cause directly:
  contributors for a binary revise are just the head; for an n-ary
  revise, the constraint's other variables. When a contributor is
  the current pick or a within-frame intermediate, the walk follows
  its most-recent reducing trail entry — preserving the chain of
  justifications across propagation hops.

  Same correctness guarantee as before (CBJ enumerates the same
  solution set as plain backtracking). Tighter jumps:
  `backjumpLevelsSkipped` is now non-zero on benchmark scenarios
  where the topology supports it — 16-queens with CBJ now shows
  `bj:34/1` (was `34/0` under the constraint-graph approximation),
  and uses one fewer backtrack overall (88 vs 89). The
  pigeonhole-via-pairwise test still triggers backjumps; a new
  `test/cbj_test.dart` case asserts the level-skip path on
  16-queens.

  Implementation: new file-private `_TrailEntry` class
  (`{varName, oldRep, cause}`) replaces the `MapEntry<String,
  _DomainRep>` trail; `_setDomain` and `_setDomainRep` gained an
  optional `cause:` parameter that every propagator call site now
  passes. `_conflictCauseFromTrail` rewritten as a chain walk over
  the trail with deduplication via `processed` index set.
  Decision-site assignments leave `cause: null` so they don't
  extend the justification chain (the chain extends through
  propagation entries only).

  Documentation: `doc/cbj.md`'s "The conflict-cause approximation"
  section rewritten to describe the chain-following algorithm;
  the "What's not implemented" entry on per-revision provenance
  updated to "minimal-cause conflict analysis" (an even tighter
  but more expensive next step). New total: 483 tests across 29
  files (was 482).

* **CBJ benchmark comparison + per-benchmark correctness tests.**
  `benchmark/benchmark.dart` now prints two rows per benchmark
  (plain BT and CBJ-enabled) with wall-clock, the existing stats
  counters, and the new `backjumps` / `backjumpLevelsSkipped`
  values, so users deciding whether to flip `enableConflictBackjumping:`
  on a given problem have side-by-side data. Empirical finding on
  the existing 9-benchmark suite: CBJ rarely changes the search
  tree size (AC-3 + the dedicated globals already catch failures
  at the cause-variable assignment) and the `backjumpLevelsSkipped`
  column is `0` across the board on these problems — confirming
  the `doc/cbj.md` guidance that CBJ pays off mostly on
  hand-crafted instances with sparse constraint graphs.

  Extracted the build functions from `benchmark/benchmark.dart` to
  a new `benchmark/problems.dart` so the new
  `test/cbj_benchmarks_test.dart` (14 tests) can validate CBJ on
  the exact same problem definitions the benchmark times. The
  tests cover all 9 benchmark scenarios (each with a domain-aware
  validator: magic-square sums, sudoku rows/cols/boxes, n-queens
  diagonals, map-coloring adjacency, SEND+MORE arithmetic), the
  CBJ-vs-plain solution equivalence on unique-solution problems
  (sudoku and both SEND+MORE forms), and enumeration-count parity
  on 8-queens (92) and the Australia map. New total: 482 tests
  across 29 files (was 468 across 28).

* **Conflict-directed backjumping (CBJ, Prosser 1993).** Opt-in via
  a new `enableConflictBackjumping: bool = false` parameter on every
  backtracking entry point: `Problem.getSolution`, `Problem.getSolutions`,
  `Problem.minimize`, `Problem.maximize`, `Problem.getSolutionWithRestarts`,
  `Problem.getSolutionWithDomWdeg`, and their static `CSP.solve*` twins.
  Default `false` preserves the existing chronological-backtracking
  surface. When enabled, the engine maintains a conflict set per
  decision and, on candidate exhaustion, jumps directly to the deepest
  previously-assigned variable in that set rather than returning to
  the immediate caller. Sound and complete; only the choice of
  backtrack target differs.

  The conflict cause uses a coarse trail-walk approximation (every
  earlier-assigned variable sharing a constraint with any variable
  touched by the failed propagation) — sound but not minimally tight;
  the only effect of over-approximation is a shorter jump, never an
  incorrect one. Composes with forward checking, restarts, dom/wdeg,
  and the integrated branch-and-bound.

  Two new `SolverStats` fields expose engagement: `backjumps` (count
  of conflict-driven returns up the search stack, one per "all
  candidates exhausted with non-empty conflict" event) and
  `backjumpLevelsSkipped` (cumulative decision levels skipped past
  chronological backtrack). Both are `0` when CBJ is off and for
  local search. Sealed `_SearchResult` types for the single-solution
  CBJ helper; engine-state-bag (`_pendingBackjumpDepth` /
  `_pendingBackjumpConflict`) for the streaming and optimization
  variants since async generators and `Future<void>` can't return a
  value directly.

  Documentation: new topical guide at
  [`doc/cbj.md`](doc/cbj.md) (algorithm, conflict-cause
  approximation, stats interpretation, composition, what's not yet
  implemented including per-revision conflict provenance and
  CDCL-style nogood learning); new "Conflict-Directed Backjumping
  (CBJ)" section in the README. Closes the tier-3 "conflict-directed
  backjumping / nogood learning" entry in PLAN.md as the first cut.
  Real CDCL with first-UIP nogood learning remains a future
  follow-up.

  Coverage: 13 tests in `test/cbj_test.dart` (wiring on every entry
  point, enumeration equivalence with plain BT on N-queens and map
  coloring, equivalence under optimization, composition with FC /
  restarts / dom-wdeg, edge cases including unsat / trivial-sat /
  no-constraints / single-value-domain, and a pigeonhole-via-pairwise
  instance that asserts `backjumps > 0`). Existing 455 tests
  unchanged; new total 468.

* **Doc fix:** the `CancellationToken` class doc said solvers check
  the token "every ~1000 decisions on backtracking paths and every
  ~1000 iterations on the min-conflicts path." The actual constants
  are 100 (`_yieldEveryDecisions`) and 200 (`_yieldEveryIterations`);
  every other docstring in the codebase already used the correct
  numbers. Fixed the outlier docstring.

* **New topical guide: [`doc/cancellation.md`](doc/cancellation.md).**
  Consolidates the previously-scattered story for cooperative
  cancellation (`CancellationToken`, the unconditional event-loop
  yield, the `'FAILURE'`-vs-`isCancelled` distinction), wrapping
  `Future.timeout(...)` on an in-process solve, and the worker-isolate
  runner's built-in `timeout:` vs an external `.timeout()`. Updates
  the README's Documentation index, links from `doc/algorithms.md`,
  and refreshes the algorithms guide's now-stale "isolate runner is on
  the roadmap" tail paragraph. Docs-only — no code or test changes.

* **Worker-isolate runner: `solveInIsolate`, `solveAllInIsolate`,
  `minimizeInIsolate`, `maximizeInIsolate`.** New top-level
  functions in `lib/src/isolate_runner.dart`, exported from
  `dart_csp.dart`. Each takes a `Problem Function()` builder that
  runs inside the spawned worker isolate (predicate closures on a
  constructed `Problem` are generally not sendable; a top-level
  builder is), runs the solve there, and bridges the result back
  over a `SendPort`. Closes the deferred worker-isolate half of
  the tier-3 isolate-parallelism item, flipping PLAN.md 3.1 from
  `[~]` to `[x]`.

  Cancellation: each entry point accepts the existing
  `cancelToken: CancellationToken`. Cancelling the parent token
  signals the worker via the message port; the worker's local
  `CancellationToken` is set and the solver aborts at the next
  checkpoint. To make this work without polling, the
  `CancellationToken` API gained `addListener(void Function())`
  (additive; the type was already experimental per STABILITY.md);
  the existing `cancel()` invokes listeners synchronously after
  flipping `isCancelled`, swallowing any listener exception.

  Timeouts: each entry point accepts an optional `timeout:
  Duration`. When the deadline fires the runner sends the worker
  a cancel signal, waits a 250 ms grace window for the worker to
  flush its result over the port, then hard-kills the isolate via
  `Isolate.kill()`. Prefer the built-in `timeout:` over wrapping
  `solveInIsolate(...).timeout(...)` — the wrapping form returns
  to the caller on time but leaves the worker isolate running
  until natural completion.

  Stats round-trip: the worker captures its own `CSP.lastStats`
  after the solve, ships it back over the port, and the runner
  writes it into the main isolate's `CSP.lastStats` slot before
  resolving the returned future / closing the returned stream.
  This preserves the documented "stats populated when the future
  resolves" contract. Stats are not copied on the pre-cancelled
  short-circuit path or when the hard-kill grace fires (the
  worker had no chance to flush).

  Errors: a builder that throws — or any exception inside the
  solve itself — is rewrapped as an `IsolateRunnerException`
  carrying the original message and stringified stack trace.
  The original exception object isn't reachable across the
  boundary in general.

  Coverage: 11 new tests in `test/isolate_runner_test.dart`
  (440 → 444 from the demo smoke tests in this batch's earlier
  commit, then 444 → 455 with this runner). The test file is
  marked `@TestOn('vm')` because `dart:isolate` isn't available
  on Dart Web. README has a new "Solving on a worker isolate"
  section; STABILITY.md adds a worker-isolate-runner entry under
  experimental.

* **`addNoOverlap` now dispatches to `addCumulative`.** Replaces the
  prior `O(n²)` pairwise-disjunction encoding with a single tagged
  cumulative constraint (unit demand, unit capacity), which is the
  exact no-overlap reduction. The cumulative time-table propagator
  (shipped in an earlier release) gives strictly stronger pruning
  while the constraint semantics are unchanged. `SolverStats`
  counters shift from `binaryRevises` to `naryRevises` since the
  pairwise binary constraints are gone — assertions on specific
  counter values for `addNoOverlap` workloads will need to be
  updated. Coverage: 1 new equivalence test in
  `test/interval_variables_test.dart` (439 → 440) confirming
  `addNoOverlap` and `addCumulative(capacity=1, demand=1)` enumerate
  identical solution sets on a non-trivial instance. All 6 prior
  no-overlap tests pass unchanged. Closes the
  `addNoOverlap`→`addCumulative` follow-up flagged in
  `HANDOVER.md` §6. STABILITY.md updates the `addNoOverlap` entry
  to reflect the dispatch.

* **Two-watched-literal data structure for the clause propagator
  (Moskewicz, Madigan, Zhao, Zhang & Malik, "Chaff", DAC 2001).**
  The internal `_ClausePropagator` now keeps two watcher pointers
  per clause and lazily updates them across calls, instead of
  scanning every literal on every call. Per-call work drops from
  O(literals) to O(1) amortized once watchers are initialized.
  The watcher state lives in a new per-engine side-table
  `_BacktrackEngine._clauseWatchers` keyed by `ClauseSpec`
  identity — the first piece of per-constraint mutable state the
  engine supports, and reusable for future stateful propagators.
  
  No trail-aware rollback is needed despite the per-constraint
  mutable state: domain reductions in the engine are monotone
  under the trail (backtrack only restores previously-removed
  values), so a watcher that points at a non-falsified literal
  at a deeper assignment is still non-falsified at any shallower
  one. The textbook concern about "watcher state must be undone
  on backtrack" doesn't apply here — watchers are always valid
  hints as the engine unwinds.
  
  User-visible pruning is identical to the prior single-pass
  scan; this is a pure perf change. Coverage: 4 new tests in
  `test/clause_test.dart` (16 → 20) covering rollback-after-deep-
  swap soundness, a 4-pigeon-3-hole CNF infeasibility instance,
  a 10-clause 3-SAT enumeration asserted equal to brute-force,
  and watcher-state freshness across repeated solves on the
  same `Problem`. All 16 prior clause tests pass unchanged.
  Benchmark suite shows no regression on non-clause problems
  (SEND+MORE predicate: 2238 ms → 2245 ms, within noise).
  
  Flips the tier-2 "variable types beyond enumerated int/string"
  entry from `[~]` to `[x]` in PLAN.md — the SAT-style booleans
  third of that item is now complete.

* **Cooperative cancellation + `CancellationToken`.** New
  `CancellationToken` type in `types.dart` (one method `cancel()`,
  one getter `isCancelled`) and a new `cancelToken:` optional
  parameter on every backtracking and local-search entry point —
  `CSP.solve`, `CSP.solveAll`, `CSP.solveWithDomWdeg`,
  `CSP.solveWithRestarts`, `CSP.solveOptimal`,
  `CSP.solveWithMinConflicts`, and the matching `Problem` methods
  (`getSolution`, `getSolutions`, `getSolutionWithDomWdeg`,
  `getSolutionWithRestarts`, `minimize`, `maximize`,
  `solveWithMinConflicts`, `maximizeSatisfaction`).
  A cancelled token aborts the search at the next checkpoint and the
  entry point returns the standard `'FAILURE'` literal; callers
  distinguish cancel from infeasibility by inspecting
  `token.isCancelled` after the call.
  
  The engine also unconditionally yields to the event loop on every
  `_yieldEveryDecisions = 100` decisions (and the min-conflicts
  runner on every `_yieldEveryIterations = 200` iterations).
  This cooperative yield is what lets a wrapping
  `Future.timeout(...)` actually fire on an otherwise CPU-bound
  solve, closing the documented `.timeout()` gotcha — no
  `CancellationToken` is required for `.timeout` to work, just for
  programmatic cancel. Fast path is one integer compare per
  decision; benchmark suite shows no measurable regression
  (SEND+MORE predicate encoding: 2238 ms before, 2242 ms after; all
  other benchmarks within noise).
  
  Coverage: 13 new tests in `test/cancellation_test.dart` (422 →
  435) covering the token API itself, pre-cancel short-circuit on
  every backtracking entry point + min-conflicts, mid-search Timer
  cancel for `getSolution` / `getSolutions` / `maximize` /
  `solveWithMinConflicts` / `getSolutionWithRestarts` /
  `getSolutionWithDomWdeg`, and `Future.timeout` integration on a
  CPU-bound infeasible problem. README has a new "Cancellation and
  Timeouts" section. STABILITY.md lists `CancellationToken` and the
  `cancelToken:` parameters as experimental and updates the
  `.timeout()` known-gotcha entry.
  
  Closes the user-visible half of the tier-3 isolate-parallelism
  item in PLAN.md; the worker-isolate runner half (closure
  serialization + stats round-trip) remains deferred.

* **SAT-style clause constraint with unit-propagation propagator.**
  New `Problem.addClause(positive: [...], negative: [...])` helper
  in the `LogicalConstraints` extension and a `ClauseSpec` tag on
  `NaryConstraint`. The disjunction of literals — `positive`
  variables that should be `1` OR `negative` variables that should
  be `0` — must hold. Tagged constraints dispatch to a new
  `_ClausePropagator` in `solver.dart` that does stateless single-
  pass unit propagation: if any literal is satisfied (only the
  satisfying value remains in the variable's domain), the clause
  is entailed; if every literal is falsified, the clause is a
  conflict; if exactly one literal is undetermined and none are
  satisfied, that literal's variable is forced to its satisfying
  value.

  Use for CNF-style modeling — combine with `ReifiedConstraints`
  to express arbitrary CNF over data variables (reify each
  sub-constraint to a boolean, then express the formula as a
  conjunction of `addClause` calls). The classical two-watched-
  literal optimization (maintain two watchers per clause and
  update lazily) is a perf follow-up: it would amortize the
  per-call scan to O(1) but requires per-constraint mutable
  state across propagation calls, a pattern the engine doesn't
  yet support. The user-visible pruning behavior is the same,
  so the optimization is a pure perf change.

  Validation: every listed variable must already be registered
  and have domain ⊆ `{0, 1}`. Variables can appear in both
  `positive` and `negative` (which makes the clause vacuously
  satisfied). An entirely empty clause (no literals at all) is
  the empty disjunction, registered as a always-false constraint;
  if no variables exist at all to attach it to, the helper
  throws `ArgumentError` rather than registering a no-op.

  Coverage: 16 new tests in `test/clause_test.dart` (406 → 422)
  covering validation, single-literal forcing, two-literal
  disjunction enumeration, mixed-polarity assignments,
  unit-propagation at root, all-false conflict detection,
  satisfied entailment, vacuous tautology, XOR via CNF, CNF over
  data variables via reified equalities, and a CNF-encoded
  3-coloring of K3 (6 solutions). All 406 prior tests pass
  unchanged. README has a new "SAT-style clauses" subsection
  under Logical Combinators. STABILITY.md lists `addClause` /
  `ClauseSpec` as experimental.

  Addresses the SAT-style-booleans third of the tier-2 "variable
  types beyond enumerated int/string" item by shipping the user-
  visible payload (clauses + unit propagation). The textbook
  watched-literal data structure itself — maintaining two watchers
  per clause across propagation calls — is the remaining perf
  follow-up, so the item stays `[~]` in PLAN.md.

* **Cumulative resource constraint with time-table propagator.** New
  `Problem.addCumulative(starts, durations, demands, capacity)`
  helper in the `GlobalConstraints` extension and a `CumulativeSpec`
  tag on `NaryConstraint`. Generalizes `addNoOverlap` from a unary
  resource (one task at a time) to an integer-capacity renewable
  resource: at every time `t`, the sum of `demands[i]` across tasks
  whose half-open interval `[starts[i], starts[i] + durations[i])`
  covers `t` must not exceed `capacity`. Use for RCPSP-style models
  (one `addCumulative` per resource type), machine slots with
  multiple identical units, parallel-worker scheduling, etc.

  Internal: new `_CumulativePropagator` in `solver.dart`
  implementing a time-table propagator (Beldiceanu & Carlsson 2002
  style). For each task, computes the compulsory part
  `[lst_i, est_i + dur_i)` — the interval the task must occupy in
  every feasible schedule — sums the compulsory parts into a sparse
  usage profile (`Map<int, int>` from time to demand-sum), reports
  immediate infeasibility on any compulsory-pile-up that exceeds
  capacity, and prunes every start candidate that would push the
  profile above capacity at some time once that task's own
  compulsory contribution at that time is removed (so the task is
  not double-counted). Dispatched from `_propagate` / `seedFor`
  alongside the existing specialized propagators; one canonical
  task per constraint is enqueued regardless of which start
  triggered it. Soundness rides on the standard pruning path — when
  every start is singleton each task's compulsory part is exactly
  its scheduled interval, the profile equals the realized usage,
  and any over-capacity time-step forces the lone feasible
  candidate out of some task's domain so the engine reports
  infeasibility from the resulting empty domain. No separate leaf
  check is required.

  Coverage: 17 new tests in `test/cumulative_test.dart` (389 → 406)
  covering validation errors, vacuous (zero-task) shapes,
  single-task feasibility and demand > capacity rejection, two- and
  three-task multi-task scenarios with shared capacity, an
  equivalence test against `addNoOverlap` on the unary reduction,
  multi-resource RCPSP composition, makespan minimization (3 tasks
  on cap 2, optimum makespan 4), propagator-activity stat
  assertion, and compulsory-pile-up root-infeasibility detection.
  All 389 prior tests pass unchanged. README has a new "Cumulative
  resource scheduling" subsection under the scheduling header.
  STABILITY.md lists `addCumulative` / `CumulativeSpec` as
  experimental.

  Closes the `cumulative` follow-up in the tier-2 "global constraint
  library expansion" item — the entry can now flip from `[~]` to
  `[x]`.

* **Set variables.** New `SetVariables` extension on `Problem` adds
  set-valued variables ranging over the subsets of a finite
  universe declared at construction time. Internally each universe
  element becomes a 0/1 indicator variable; the helpers decompose
  to existing primitives (linear arithmetic for cardinality,
  pairwise binary / ternary n-ary for relations) so no new
  propagator was required. Every solve entry point on `Problem`
  post-processes the raw result to expose each set variable as a
  `Set<dynamic>` of included elements and strip the indicator
  variables from the returned map.

  New API:
  - `Problem.addSetVariable(name, {universe, required, excluded})`
    and `addSetVariables(names, {universe, required, excluded})`.
  - `addSetCardinality(setName, k)`,
    `addSetCardinalityRange(setName, min, max)`,
    `addSetCardinalityVar(setName, countVar)`.
  - `addRequiredInSet(setName, element)`,
    `addExcludedFromSet(setName, element)`.
  - `addSubset(sub, super)`, `addSetEquals(a, b)`,
    `addSetDisjoint(a, b)`.
  - `addSetUnion(a, b, result)`, `addSetIntersection(a, b, result)`,
    `addSetDifference(a, b, result)`.
  - `memberIndicator(setName, element)` — escape hatch returning
    the internal 0/1 indicator name so the user can compose set
    membership with reified / logical / linear / arithmetic helpers
    for relations the dedicated set helpers don't express.
  - `setVariableNames` and `setUniverse(name)` introspection.

  Pairwise binary helpers (`addSubset`, `addSetDisjoint`) accept
  set variables with different universes — elements only in one are
  handled per operation (subset forces sub-only elements out;
  disjoint contributes no constraint). `addSetEquals` requires the
  universes to match as sets. The ternary helpers (`addSetUnion`,
  `addSetIntersection`, `addSetDifference`) require all three set
  variables to share the same universe; the general case is reachable
  via `memberIndicator`.

  `Problem.copy()` propagates the set-variable registry, so
  `SoftConstraints.maximizeSatisfaction` (which copies the problem
  internally) materializes set variables correctly through its
  branch-and-bound. The min-conflicts, restarts, dom/wdeg, and
  integrated branch-and-bound entry points are all wrapped through
  the same materialization helper.

  Coverage: 40 new tests in `test/set_variables_test.dart`
  (349 → 389) covering declaration validation (empty / duplicate /
  pin conflicts), free-universe enumeration (2^|U|), pin
  enforcement, cardinality (exact / range / variable), subset with
  symmetric and asymmetric universes, set equality / disjoint /
  union / intersection / difference, `memberIndicator` composition
  with reified equality, materialization through every solve entry
  point (`getSolution*`, `getSolutions`, `solveWithMinConflicts`,
  `minimize`, `maximize`, `maximizeSatisfaction`), an integration
  problem (team selection with required captain + disjoint bench),
  and an equivalence test asserting the same solution count as a
  hand-built indicator decomposition. All 349 prior tests pass
  unchanged. README has a new "Set Variables" section and
  `doc/set-variables.md` is the topical guide. `STABILITY.md` lists
  the new surface as experimental.

  Closes the set-variable third of the tier-2 "variable types beyond
  enumerated int/string" item. SAT-style watched-literal boolean
  variables remain as a follow-up.

* **Interval-variable domain representation + scheduling primitives.**
  New `_IntervalRep` internal domain representation — a third
  `_DomainRep` impl alongside `_BitsetRep` and `_ListRep`. Stores
  just `(min, max)` and supports `O(1)` membership / length /
  bounds. `filter(predicate)` walks the range once, returns a
  narrower `_IntervalRep` when the kept set is still contiguous,
  and promotes to `_BitsetRep` (if the new span fits) or `_ListRep`
  when the predicate creates interior holes.

  Dispatch (`_classifyDomain`): strictly-ascending `int` with span
  `≤ 1024` continues to use the bitset rep; contiguous-ascending
  `int` with span `> 1024` now uses the interval rep instead of the
  previous list-rep fallback; everything else (mixed types,
  non-contiguous int with span `> 1024`, non-monotonic) still falls
  back to list. `_setDomain(List<dynamic>)` detects contiguous
  ascending kept lists for interval-backed variables and preserves
  the `_IntervalRep` form on trail/rollback, promoting to bitset or
  list only when the kept list has internal gaps.

  New user-facing helpers:
  - `Problem.addRangeVariable(name, int min, int max)` — adds a
    variable whose domain is `[min, max]` (inclusive both ends).
    For ranges `> 1024` this is the natural way to model scheduling
    horizons without paying the `List<dynamic>` allocation cost on
    every propagation step.
  - `Problem.addNoOverlap(starts, durations)` (extension
    `GlobalConstraints`) — unary-resource scheduling. For every
    pair `(i, j)`, posts `starts[i] + durations[i] <= starts[j]` OR
    `starts[j] + durations[j] <= starts[i]`. Durations are
    constants; variable durations can be modeled separately via
    the linear propagator. Current implementation is `O(n²)`
    pairwise binary disjunctions; stronger globals (edge-finding,
    time-table for `cumulative`) remain follow-ups.

  Coverage: 15 new tests in `test/interval_variables_test.dart`
  (334 → 349) covering rep eligibility, filter promotion through
  the linear / regular / GAC paths, search singleton-commit on
  interval-rep variables, validation errors, two-task non-overlap
  enumeration (12 schedules with `addRangeVariable('a', 0, 4)` +
  `addRangeVariable('b', 0, 5)` + durations `[3, 2]`), and a
  three-task makespan-minimization (durations `[4, 3, 2]`, optimum
  makespan = 9). All 334 prior tests pass unchanged. README has a
  new "Range-Domain Variables (Scheduling)" section.

  Closes the interval-variable third of the tier-2 "variable types
  beyond enumerated int/string" item. Set variables and SAT-style
  watched-literal boolean variables remain as separate follow-ups;
  both are independent of the interval rep and can ship next.

* **Rep-aware filter for specialized propagators.** Closes the
  follow-up flagged in the bitset domain representation entry. New
  `_setDomainRep(varName, _DomainRep)` on `_BacktrackEngine`
  alongside the existing list-based `_setDomain`, plus an updated
  `applyUpdate(String, _DomainRep)` callback type on every
  specialized propagator (`_AllDifferentPropagator`,
  `_LinearPropagator`, `_RegularPropagator`, `_CircuitPropagator`,
  `_GccPropagator`).

  Each propagator's reduction loop now builds its kept set via
  `oldDom.filter(predicate)` instead of a fresh `List<dynamic>`,
  so a bitset-backed variable's reduction stays in `_BitsetRep`
  form end-to-end — the engine no longer re-bits a kept list back
  into a fresh `Uint64List` on every prune. Per-variable invariant
  state (matched value index, SCC id, matched copy in GCC) is
  hoisted out of the filter to avoid recomputing it for each
  candidate. The engine's list-based `_setDomain` remains in place
  for the internal singleton-commit / binary-revise / generic-GAC
  paths (which do not have a `_DomainRep` source).

  No public API changes; all five propagators retain their leaf
  detection and soundness contracts unchanged. The integrated
  branch-and-bound's `_tightenObjectiveDomain` already operated
  rep-natively (`.filter` on the live domain and every relevant
  trail snapshot), so it gains nothing here but stays consistent.

  Coverage: 3 new tests in `test/bitset_domain_test.dart` (13 → 16)
  exercising heavy-pruning workloads on bitset-eligible domains
  through Régin allDifferent (6-queens, 4 solutions),
  network-flow GCC (six-worker exact-count rostering, 90 distinct
  assignments), and the cycle-detection circuit propagator (5-position
  Hamiltonian enumeration, 24 cycles). Existing 331 tests pass
  unchanged. Total suite: 331 → 334.

  Perf note: the existing benchmark workload (queens, sudoku, magic
  square, SEND+MORE predicate, SEND+MORE linear) is dominated by
  generic n-ary support-finding (`_findSupport` over the Cartesian
  product of the free neighborhood) on the predicate forms, and by
  the LCV scorer on small puzzles — neither of which the rep-aware
  filter touches. Run-to-run timing variance (±200ms on the 1.5s
  SEND+MORE predicate case) is larger than any visible delta. The
  win is structural: one `List<dynamic>` and one full-rebuild
  `Uint64List` allocation removed per propagator reduction on
  bitset-backed variables, which matters most on propagator-heavy
  workloads (Régin allDifferent under heavy pruning, large GCCs,
  GAC-tight regular constraints).

* **Network-flow propagator for `addGcc` / `addGccRanges`** (Régin
  1996). New `GccSpec` value type and `gccSpec` field on
  `NaryConstraint`. The propagator generalizes the Régin
  allDifferent dispatch already in the codebase to handle
  multiplicity: each value `v` with upper bound `u` is replicated
  into `u` "copies" in the bipartite matching, Hopcroft-Karp finds
  a max matching, Kosaraju SCCs + free-copy reachability identify
  every variable→value edge that does not lie on some max matching,
  and those edges are pruned. Spec values that have been pruned
  from every variable's domain are still indexed so a `lower > 0`
  requirement on an unavailable value reports infeasibility at the
  root.

  Upper-bound constraints (the case where every spec entry has
  `min == 0`) receive full GAC. Lower-bound constraints receive
  conservative GAC: when the current matching distribution doesn't
  certify the lower bounds and the constraint isn't at a leaf, the
  propagator returns no changes rather than risking a false-positive
  infeasibility verdict; at a leaf the matching is unique and any
  bounds violation is reported as real infeasibility. The leaf check
  is what closes the soundness gap that would otherwise let
  predicate-bypassed constraint violations slip through.

  Both `addGcc(vars, counts)` (exact-count form: each `min == max
  == count`) and `addGccRanges(vars, ranges)` (`(min, max)` per
  value) now construct `NaryConstraint` directly with `gccSpec` set.
  The existing predicate still runs at leaves of constraints not
  reached by the propagator path. Closes the last documented
  deferred propagator follow-up for the global constraint library.

  Coverage: 5 new tests in `test/global_cardinality_test.dart` (31
  → 36) covering insufficient-capacity rejection at construction,
  root-infeasibility detection when a required value is gone from
  every domain (0 decisions), all-different equivalence with the
  Régin allDifferent solution set, upper-bound-only enumeration
  with measurable propagator activity, and a 60-solution
  exact-count rostering case. All 326 prior tests pass unchanged.
  Total suite: 326 → 331. README updated.

* **Cycle-detection propagator for `addCircuit`.** New `circuit`
  flag on `NaryConstraint` dispatches to a dedicated propagator that
  - builds the singleton-edge graph (variables with singleton
    domains define fixed successor edges);
  - rejects two predecessors for the same node and self-loops for
    `n > 1`;
  - walks the singleton graph: chains are kept as partial paths,
    pure cycles must visit all `n` nodes or the constraint is
    infeasible;
  - prunes every chain node from the chain's tail's domain when
    chain length `< n` (any such value would close a premature
    sub-cycle), or forces tail = head when chain length `= n`;
  - enforces successor uniqueness: any value with a known
    predecessor is removed from every other variable's domain.

  Same dispatch pattern as Régin allDifferent, bounds-consistency
  linear, and partial-state regular. Public API is unchanged; the
  existing soundness predicate still runs at leaves. Closes the
  last documented deferred propagator follow-up for the global
  constraint library.

  Also adds `_DomainRep.contains` (O(1) for `_BitsetRep` when the
  query is `int`, O(n) for `_ListRep`) since the cycle propagator
  needs efficient membership.

  Coverage: 6 new tests in `test/circuit_and_bin_packing_test.dart`
  (14 → 20) asserting sub-cycle rejection at the root (0 decisions),
  self-loop rejection, chain-tail pruning to force the only valid
  next position, successor uniqueness without `addAllDifferent`,
  measurable propagator activity, and composition with
  `addAllDifferent`. All 320 prior tests pass unchanged. Total
  suite: 320 → 326. README updated to describe the new propagator.

* **Bitset domain representation (closes Tier 1).** Internal
  `_DomainRep` abstraction with two implementations:
  - `_BitsetRep` — `Uint64List` + integer offset; O(1) membership,
    O(N/64) filter.
  - `_ListRep` — wraps `List<dynamic>` for mixed types,
    non-monotonic input, large spans, etc.

  Eligibility (decided per-variable at engine construction):
  strictly-ascending list of `int` with span `max - min + 1` ≤ 1024.
  These constraints make bitset iteration order match the user's
  input order so observable solver behavior is unchanged. All 22
  `_domains[...]` access sites in `_BacktrackEngine` plus all three
  specialized propagators (`_AllDifferentPropagator`,
  `_LinearPropagator`, `_RegularPropagator`) were updated to read
  through the new rep API. The `applyUpdate` callback signature is
  unchanged — propagators continue to hand back kept `List<dynamic>`s
  and `_setDomain` re-wraps as the appropriate rep for the variable.

  Coverage: 13 new tests in `test/bitset_domain_test.dart` covering
  eligibility branches (contiguous, sparse, negative-offset, span at
  the boundary, large allDifferent), ineligibility fallback (mixed
  types, non-monotonic, large span, doubles), and propagator
  round-trip across the trail. All 307 prior tests pass unchanged.
  Total suite: 307 → 320.

  Perf note: existing benchmarks (queens, sudoku, magic square) show
  no consistent runtime delta. The hot path is predicate calls and
  per-call work inside the specialized propagators, not raw domain
  operations. The bitset infrastructure is in place; future work
  exposing rep-aware filter operations directly to propagators (so
  they avoid the `_setDomain(List<dynamic>)` round-trip on each
  reduction) is now a pure perf change.

* **Partial-state propagator for `addRegular` (Pesant 2004).** New
  `regularDfa` field on `NaryConstraint`, dispatched the same way as
  Régin's allDifferent and the bounds-consistency linear propagator.
  `_RegularPropagator` computes per-position forward + backward
  reachable DFA-state sets from the current per-variable domains,
  then prunes any value whose transition lies on no accepting path.
  Achieves GAC on the regular constraint — infeasibility is detected
  at the root for many problems where the predicate-only encoding
  would have to exhaust the search tree.

  The public API is unchanged; `addRegular(vars, dfa)` now tags the
  constraint with the new field instead of falling through to the
  generic n-ary predicate path. Soundness still rides on the
  predicate at leaves, so the propagator is correctness-preserving
  by construction.

  Coverage: 4 new tests in `test/regular_constraint_test.dart` (16
  → 20) asserting root-infeasibility detection, singleton-forcing on
  a strict-alternation DFA (0 decisions for the unique solution),
  full enumeration on an at-most-one-occurrence DFA (9 solutions),
  and accepting-state-aware rejection. Existing 16 regular tests
  pass unchanged (the propagator only adds pruning; the constraint
  semantics are identical). README's "DFA-checked Sequences" section
  notes the partial-state pruning. Total suite: 303 → 307.

* **`SolverStats` populated for every solver.** The streaming and
  Min-Conflicts paths now populate `Problem.lastStats` /
  `CSP.lastStats`. `CSP.solveAll` wraps the engine's stream in a
  try/finally that flushes the engine's counters into `lastStats`
  when the stream completes or is cancelled. A new
  `SolverStats.iterations` field (default `0`) is set by
  `CSP.solveWithMinConflicts` to the local-search step count;
  backtracking solvers leave it at `0` and continue to use the
  existing `decisions` / `backtracks` / `propagations` /
  `binaryRevises` / `naryRevises` counters. `SolverStats.toString`
  includes the new field. Coverage: 7 new tests in
  `test/stats_test.dart` (6 → 13). Total suite: 296 → 303.

  Doc note added to `Problem.lastStats` flagging the known gotcha
  that `lastStats` is a single static slot on `CSP` and is
  overwritten by any solve on any `Problem` instance — capture it
  immediately after the call that produced it if you need to
  compare runs.

* **`STABILITY.md` — public-API stability statement.** Documents
  what's stable, what's experimental, and the semver policy that
  governs each tier. Lists the known behavioral gotchas (the
  static-slot `lastStats`, stream-stats-flush-on-completion, GAC
  bail-out work bound, no mid-solve `.timeout()`). Referenced from
  README's "Documentation" section.

* **Bounds-consistency linear arithmetic propagator.** New
  `LinearSpec` value type in `types.dart` capturing
  `Σ coeffs[i]·vars[i] ∘ bound` with `op ∈ {eq, leq, geq}`, and a
  new `linearSpec` field on `NaryConstraint`. New `LinearConstraints`
  extension on `Problem` exposing `addLinearEquals(vars, coeffs,
  bound)`, `addLinearLeq(...)`, and `addLinearGeq(...)`. Coefficients
  may be positive, negative, or zero; domains must be numeric (this
  is validated at registration time).

  The engine dispatches linear constraints to a dedicated
  `_LinearPropagator` (mirroring the Régin allDifferent pattern):
  computes the interval of the weighted partial sum from current
  per-variable domain mins/maxes, derives per-variable bounds, and
  filters each domain to values consistent with the constraint.
  Bounds consistency rather than full GAC — much stronger than
  predicate-only encoding on arithmetic constraints with many
  variables; closes the documented SEND+MORE follow-up. The
  cryptarithmetic benchmark expressed with a single linear equation
  drops from 1834 ms (predicate-only) to 1 ms (~1800× speedup).

  Coverage: 21 new tests in `test/linear_propagator_test.dart`.
  Total suite: 275 → 296. README has a new "Linear Arithmetic
  Constraints" section; `benchmark/benchmark.dart` now runs both
  the predicate-only and linear forms of SEND+MORE side-by-side.

* **Pluggable consistency level.** New `ConsistencyLevel` enum in
  `types.dart` exposing `arcConsistency` (the default; existing AC-3 +
  GAC behavior) and `forwardChecking`. FC revises each constraint
  touching the just-assigned variable exactly once and skips the
  cascade unless a revise reduces a variable to a singleton, in which
  case it cascades that newly-assigned variable's constraints once
  (textbook FC semantics — preserves soundness when propagation
  implicitly assigns a variable).

  Threaded through every backtracking entry point as an optional
  `consistency:` parameter: `CSP.solve`, `CSP.solveAll`,
  `CSP.solveWithDomWdeg`, `CSP.solveWithRestarts`, `CSP.solveOptimal`
  and the matching `Problem` methods (`getSolution`, `getSolutions`,
  `getSolutionWithDomWdeg`, `getSolutionWithRestarts`, `minimize`,
  `maximize`). Default behavior unchanged.

  Coverage: 13 new tests in `test/consistency_level_test.dart`
  asserting correctness across binary, n-ary, optimization, restarts
  and dom/wdeg paths, equivalence of FC and AC solution sets on a
  small enumeration, and a metric assertion that FC does strictly
  fewer binary revises than AC on a chain over a wide domain. Total
  suite: 262 → 275.

* **DFA-checked sequences: `addRegular` + `Dfa` type.** Closes the
  last named global constraint from the deferred list (other than
  `cumulative`, which is gated on interval-variable support). The
  new `Dfa` value type in `types.dart` captures a deterministic
  finite automaton (`numStates`, `start`, `accepting`, `transitions`)
  with `dynamic` symbol type to match arbitrary CSP variable values.
  `addRegular(vars, dfa)` enforces that the sequence
  `(vars[0], ..., vars[n-1])` is accepted by the DFA when read
  left-to-right.

  Use for any sequencing rule expressible as a finite automaton:
  run-length bounds ("no more than 2 night shifts in a row"),
  alternation requirements, exact-pattern matching, parity
  predicates. Complements the cardinality helpers — those count;
  `regular` adds positional structure.

  Coverage: 16 new tests in `test/regular_constraint_test.dart`
  covering Dfa step semantics, pattern acceptance, counting via
  state machine (equivalence check against `addAmongExactly`),
  run-length bounds, numeric-symbol parity, validation errors, and
  composition with other constraints. Total suite: 246 → 262.

* **Sequencing & packing global constraints: `addCircuit`,
  `addBinPacking`.** Two more classical globals join the
  `GlobalConstraints` extension:
  * `addCircuit(vars)` — `vars[i]` is the successor of position `i`;
    the n successors must form a single Hamiltonian cycle through
    every position. The predicate walks the successor function from
    position 0 and rejects sub-cycles or missed positions. Combine
    with `addAllDifferent` for stronger early pruning.
  * `addBinPacking(items, sizes, binLoads)` — for each bin `b`,
    `binLoads[b]` equals the sum of `sizes[i]` over items assigned
    to bin `b`. Bin capacities are expressed by constraining the
    load variables separately (`load0 <= 10`, ranges, `minimize`
    over `maxLoad`, etc.).

  Coverage: 14 new tests in `test/circuit_and_bin_packing_test.dart`
  including a tour-counting regression (n=4 → (n-1)! = 6 cycles), a
  sub-cycle rejection, an out-of-range bin id case, a size-0 edge
  case, and a balanced-packing minimization. Total suite: 232 → 246.

* **Integrated branch-and-bound for `minimize` / `maximize`.**
  `Problem._optimize` no longer restarts the search after each
  improvement. The new `_BacktrackEngine.findOptimal` walks the tree
  once, recording each strictly-improving leaf as the incumbent and
  permanently pruning the objective's domain (plus every existing
  trail snapshot) to values that still improve. An `_optProven`
  short-circuit fires when no improving value is reachable anywhere
  in the remaining tree.

  Behavior change: `Problem.lastStats` is now populated by `minimize`
  / `maximize` (the restart-tightening version overwrote it on every
  restart, leaving only the last attempt's stats observable). The
  non-numeric-objective check now fires synchronously at the start of
  `_optimize` rather than at the first leaf — same `ArgumentError`,
  surfaces earlier.

  Coverage: 10 new tests in `test/optimization_test.dart` covering
  stats population, bound-pruning interaction with `allDifferent`,
  the proven-optimum short-circuit, and the don't-mutate-original
  invariant after the engine's in-place tightening.

* **Counting global constraints: `among`, `nvalue`, `gcc`.** The
  `GlobalConstraints` extension on `Problem` gains six new helpers
  (count-variable and fixed-`k` forms of each):
  * `addAmong(vars, values, countVar)` / `addAmongExactly(vars, values, k)`
  * `addNvalue(vars, countVar)` / `addNvalueExactly(vars, k)`
  * `addGcc(vars, counts)` / `addGccRanges(vars, ranges)`

  Together they cover the three classical counting patterns from the
  CSP literature: category counts, distinct-value counts, and per-value
  cardinality (exact or ranged). `gcc` generalizes `allDifferent`;
  `nvalue` enables chromatic-number-style minimization (combine with
  `minimize`). Each helper validates eagerly at construction.

  Coverage: 31 new tests in `test/global_cardinality_test.dart`,
  including unknown-variable / out-of-range / infeasible-cardinality
  errors plus a multi-constraint rostering regression. Topical guide
  in `doc/global-cardinality.md`.

  All current implementations are generic n-ary GAC encodings — correct
  on any input but bounded by the engine's GAC work limit on very large
  `vars` lists. A network-flow-based GCC propagator (Régin 1996) for
  stronger pruning is tracked as a follow-up in `PLAN.md`.

## 2.1.0

* **Clean-room rewrite of the solver core.** `lib/src/solver.dart` was
  rewritten from textbook references (Russell & Norvig AIMA Ch. 6;
  Mackworth 1977 AC-3; Minton et al. 1992 Min-Conflicts) to remove
  derivative provenance from an upstream JavaScript project (see
  `NOTICE`). No public API changes; all existing tests pass unchanged.
* **~6× faster end-to-end.** Full test suite: 6.5s → 1.1s. Heaviest
  example (3x3 magic square in `example/example.dart`): 11.4s → 1.1s.
  Most of the win comes from replacing the AC-3/GAC list-based queue
  with a real `Queue<T>` plus identity-deduplicated pending work.
* **Min-Conflicts local search solver.** New
  `Problem.solveWithMinConflicts({maxSteps: 1000})` for very large or
  loosely-constrained problems where any feasible answer suffices.
  Implementation of Minton et al. (1992). Incomplete by design — see
  `doc/min-conflicts.md` for when to choose it over the default
  backtracking solver.
* **Topical documentation in `doc/`.** Four new guides:
  * `doc/algorithms.md` — Backtracking, AC-3, GAC, MRV, LCV, and the
    async caveat (solver is CPU-bound; `.timeout()` won't fire
    mid-search).
  * `doc/string-constraints.md` — Full parser grammar and dispatch
    table from string patterns to built-in factories.
  * `doc/multi-solutions.md` — Decision tree for the streaming /
    counting / bounded-enumeration APIs.
  * `doc/min-conflicts.md` — When to use the local search solver,
    sizing `maxSteps`, restart strategies.
* **Expanded test coverage.** 86 tests across four files, including a
  new `test/builtin_and_parser_test.dart` (42 tests) for the built-in
  constraint factories and the expression evaluator.
* **Fixed the `example/example.dart` magic-square hang.** Pinning
  `B2=5` (the only legal center for a 3x3 magic square) cuts the
  problem by ~20× without changing the API used.
* **CI hardening.** Non-stable Dart channels (`beta`, `dev`) are
  `continue-on-error` so upstream SDK breakage doesn't block PRs;
  least-privilege permissions on the test job.
* **Project moved.** This is a fresh repository
  (`CrispStrobe/dart_csp`) continuing the now-archived
  `CrispStrobe/dartCSP`. See `NOTICE` for licensing history.

## 2.0.0

* Initial stable release of the `dart_csp` library.
* Features backtracking solver with AC-3/GAC and MRV/LCV heuristics.
* Includes a powerful string-based constraint parser.
* Added ability to find all solutions and the first N solutions.

# PLAN — Toward a production-grade `dart_csp`

This is a working roadmap. Items are ordered by impact-per-effort, not
chronologically. Tier-1 items materially change what the library can do
or how fast it does it; tier-2 items make it competitive on standard
benchmarks; tier-3 items polish it as an engineering artifact.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done.

## Tier 1 — fundamental capability / perf

- [x] **Branch-and-bound optimization (COP).** `Problem.minimize` and
  `Problem.maximize` added. Now implemented as **integrated
  branch-and-bound** in the backtracking engine
  (`_BacktrackEngine.findOptimal`): each strictly-improving leaf
  becomes the new incumbent and the objective's domain is permanently
  pruned to improving values (every existing trail snapshot is
  re-filtered in place so rollback can't reintroduce stale values).
  Search continues from the same point, avoiding per-improvement
  restart cost. `_optProven` short-circuits when no improving value
  is reachable from anywhere in the remaining tree. `lastStats` is
  now populated for `minimize`/`maximize` (the restart-tightening
  version overwrote it on every restart). Coverage: 13 baseline
  tests + 10 integration-specific tests in
  `test/optimization_test.dart`.
- [x] **Régin's matching-based `allDifferent` propagator.** Implemented
  in `lib/src/solver.dart` as `_AllDifferentPropagator`: Hopcroft-Karp
  matching + Kosaraju SCC + free-value reachability. Dispatched via the
  new `NaryConstraint.allDifferent` flag set by `addAllDifferent` for
  3+ variables. Measured wins on previously-pathological inputs:
  3x3 magic square with no center clue: 104,520 ms → 16 ms (~6500×).
  Sudoku (medium-hard, 27 simultaneous 9-var allDifferents): 19 ms.
  Coverage: 8 tests in `test/alldifferent_propagator_test.dart`
  including a Sudoku regression and a Hall-set pruning case.
- [x] **Trail-based undo.** Replaced the per-recursion full-domain
  snapshot in `_BacktrackEngine` with an append-only trail of
  `(varName, oldDomain)` entries. Every mutation routes through
  `_setDomain` (binary AC-3 revise, generic GAC revise, the
  allDifferent propagator, and the tentative assignment). Backtrack
  is `_trailRollback(mark)` which undoes only what changed. All 107
  tests still pass.
- [x] **Bitset domain representation.** Internal `_DomainRep`
  abstraction in `solver.dart` with two implementations:
  `_BitsetRep` (a `Uint64List` + integer offset; O(1) membership,
  O(N/64) filter) and `_ListRep` (wraps `List<dynamic>` for mixed
  types, non-monotonic input, large spans, etc.). Eligibility check
  at engine construction: a variable's initial domain qualifies for
  bitset only if it is a strictly-ascending list of `int` whose
  span (`max - min + 1`) is at most 1024 — these constraints
  guarantee bitset iteration order matches the user's input order
  so observable solver behavior is unchanged.

  All 22 `_domains[...]` access sites in the engine and the three
  specialized propagators (`_AllDifferentPropagator`,
  `_LinearPropagator`, `_RegularPropagator`) were updated to read
  via the `_DomainRep` API (`.values`, `.length`, `.first`,
  `.isEmpty`, `.filter`, `.asList`). The `applyUpdate` callback
  signature stays `(String, List<dynamic>) -> void` — propagators
  hand back kept lists, and `_setDomain` re-wraps as the appropriate
  rep (bitset-backed vars get a fresh `Uint64List` built from the
  kept values; list-backed vars store the list directly).

  Coverage: 13 new tests in `test/bitset_domain_test.dart` covering
  bitset-eligible cases (contiguous/sparse/negative-offset
  ascending int domains, span at the boundary, large allDifferent
  on int domain) and ineligible fallback cases (mixed types,
  non-monotonic int, span > 1024, double-valued domains), plus
  propagator round-trip tests across the trail (linear, regular,
  integrated B&B). All 307 prior tests pass unchanged. Total
  suite: 307 → 320.

  Perf observation: the existing benchmarks (queens, sudoku, magic
  square) show no consistent runtime delta — the workload is
  dominated by predicate calls and per-call work inside the
  specialized propagators (Régin matching, linear bounds, regular
  reachability), not by raw domain operations. The bitset rep is
  most relevant when future work exposes rep-aware filter
  operations directly to propagators, avoiding the
  `_setDomain(List<dynamic>)` round-trip on each domain reduction.
  The infrastructure is in place; that follow-up is now a pure
  perf change.

  **Rep-aware propagator filter shipped.** The follow-up referenced
  above is now in place: a parallel `_setDomainRep(varName, _DomainRep)`
  on the engine, plus an `applyUpdate(String, _DomainRep)` callback
  on every specialized propagator (`_AllDifferentPropagator`,
  `_LinearPropagator`, `_RegularPropagator`, `_CircuitPropagator`,
  `_GccPropagator`). Each propagator now builds its reduction via
  `oldDom.filter(predicate)` rather than a `List<dynamic>` of kept
  values, so a bitset-backed domain stays in bitset form end-to-end
  with no intermediate `Uint64List` rebuild. The engine's
  list-based `_setDomain` stays for the internal commit-singleton /
  binary-revise / generic-GAC paths. Coverage: 3 new tests in
  `test/bitset_domain_test.dart` exercising Régin allDifferent,
  network-flow GCC, and cycle-detection circuit pruning on bitset-
  eligible domains. The existing benchmark suite continues to show
  run-to-run noise dominate any measurable change (SEND+MORE
  predicate ~1.5s ±200ms either side of the baseline) because that
  workload spends most of its time in the generic n-ary support-
  finder rather than the specialized-propagator filter; the win is
  structural — one allocation removed per propagator reduction —
  and the new tests guarantee correctness on the rep-preserving
  path.

## Tier 2 — standard CP feature set

- [x] **Restart strategies.** `CSP.solveWithRestarts` and
  `Problem.getSolutionWithRestarts` added. Implements the Luby
  sequence (Luby, Sinclair & Zuckerman, 1993) with `scale × luby(i)`
  backtrack budget per attempt. `_BacktrackEngine` gained optional
  `Random` and `maxBacktracks` fields; LCV ties are shuffled when
  `random != null` so successive attempts explore different
  trees. Distinguishes tree-exhausted (`'FAILURE'`) from
  budget-aborted via `wasAborted`. Seeded runs are reproducible.
  Coverage: 7 tests in `test/restart_test.dart`.
- [x] **dom/wdeg variable heuristic.** Implemented as opt-in via
  `Problem.getSolutionWithDomWdeg()` and `useDomWdeg: true` on
  `Problem.getSolutionWithRestarts(...)`. Per-constraint failure
  weights stored in identity-hashed maps inside `_BacktrackEngine`,
  bumped whenever a propagation step causes a domain wipeout.
  Variable selection picks min `dom(v) / wdeg(v)` where wdeg(v) is
  the sum of weights of constraints touching `v` with ≥ 1 other
  unassigned variable. MRV remains the default. Coverage: 6 tests
  in `test/dom_wdeg_test.dart`. VSIDS-style activity is a separate
  follow-up.
- [x] **Symmetry-breaking primitives — sequence lex and value
  precedence.** `addLexLeq` / `addLexLt` and the matching
  `lexLeq` / `lexLt` factories implement the standard sequence-
  symmetry primitive: lex-ordering between two equal-length variable
  lists keeps a single canonical representative of every
  interchangeable-row / interchangeable-worker pair. *Value-symmetry
  breaking shipped*: new `addValuePrecedence(variables, values)`
  helper on `Problem` and matching `valuePrecedence(variables,
  earlier, later)` factory in `lib/src/builtin_constraints.dart`.
  For each consecutive pair `(values[i], values[i+1])`, posts an
  n-ary precedence predicate over `variables` that enforces the
  first occurrence of `values[i]` strictly precedes the first
  occurrence of `values[i+1]` (or the latter is unused). Posting the
  full canonical chain breaks `k!` value-permutation symmetry under
  the listed values. Values outside the list are unconstrained.
  Coverage: 23 tests in `test/symmetry_breaking_test.dart` (10
  pre-existing + 13 new: factory unit tests including partial-
  assignment behavior, validation, and integration scenarios — K3
  triangle coloring collapsing 6→1, 5-node path graph 3-color
  shrinking by 3!, partial value usage with brute-force agreement,
  unconstrained-outside-list semantics, and composition with
  `addAllDifferent` collapsing 4! → 1).
- [x] **Reified constraints.** `b ⇔ C` exposed via a new
  `ReifiedConstraints` extension on `Problem`. Methods:
  `addReifiedEquals`, `addReifiedNotEquals`, `addReifiedLessThan`,
  `addReifiedLessOrEqual`, `addReifiedGreaterThan`,
  `addReifiedGreaterOrEqual`, `addReifiedInSet`,
  `addReifiedEqualsVar`, and generic `addReified(boolVar, vars,
  predicate)`. Boolean variable is a 0/1 integer (auto-added if
  absent); composes naturally with existing arithmetic constraints
  for counting (`'b1 + b2 + b3 >= 2'`). Coverage: 17 tests in
  `test/reified_constraints_test.dart`.
- [x] **Logical combinators on boolean variables.** New
  `LogicalConstraints` extension on `Problem` adds: `addAtLeast`,
  `addAtMost`, `addExactly` (cardinality), `addImplies` (material
  implication), and `addReifiedAnd` / `addReifiedOr` /
  `addReifiedNot` for composing reified bools. Together with
  reified constraints they cover all natural ways to express
  "and / or / not / implies" between sub-constraints. Coverage:
  13 tests in `test/logical_combinators_test.dart`.
- [x] **Global constraint library expansion.** Nine new constraints
  shipped in the `GlobalConstraints` extension:
  * `addElement(idxVar, list, valueVar)` — `list[idxVar] == valueVar`
    (indirection / lookup tables).
  * `addTable(vars, tuples)` — `(vars) ∈ tuples` (arbitrary relations,
    compatibility matrices, FSM transitions). 2-var case routed through
    the binary fast path; 3+ uses generic n-ary GAC.
  * `addAmong(vars, values, countVar)` and `addAmongExactly(vars, values,
    k)` — `countVar` or constant `k` = number of `vars` whose value is
    in `values`. For category-counting ("how many morning shifts").
  * `addNvalue(vars, countVar)` and `addNvalueExactly(vars, k)` —
    `countVar` or `k` = number of distinct values across `vars`. Enables
    chromatic-number-style minimization (`addNvalue` + `minimize`).
  * `addGcc(vars, counts)` and `addGccRanges(vars, ranges)` — for each
    `value → count` (or `(min, max)`) entry, that value must occur the
    specified number of times among `vars`. Generalizes `allDifferent`;
    use for shift rosters, distribution problems, sudoku-like puzzles.
  * `addCircuit(vars)` — `vars[i]` interpreted as successor of position
    i must form a single Hamiltonian cycle. TSP-like routing,
    single-tour sequencing.
  * `addBinPacking(items, sizes, binLoads)` — each `binLoads[b]` equals
    the sum of `sizes[i]` over items assigned to bin `b`. Capacity /
    balancing comes from constraining `binLoads` separately.
  * `addRegular(vars, dfa)` — the sequence `(vars[0], ..., vars[n-1])`
    must be accepted by the given `Dfa` (states, start, accepting,
    transitions). For sequencing rules with positional structure
    (run-length bounds, alternation, exact-pattern matching) that the
    cardinality helpers can't express. New public `Dfa` value type in
    `types.dart`.
  * `addInverse(forward, inverse)` — channelling: for every i, j in
    0..n-1, `forward[i] = j ⇔ inverse[j] = i`. Standard primitive in
    CP modelling for assignment problems and scheduling where the
    same relation is naturally expressed in both directions; one
    side's pin propagates to the other. Decomposes into `n²` binary
    constraints so AC-3 propagates effectively. Implies both lists
    are partial permutations of `0..n-1`.
  Coverage: 25 tests in `test/global_constraints_test.dart` (element,
  table, inverse) + 31 tests in `test/global_cardinality_test.dart`
  (among, nvalue, gcc) + 20 tests in
  `test/circuit_and_bin_packing_test.dart` + 20 tests in
  `test/regular_constraint_test.dart`.
  Topical guide in `doc/global-cardinality.md`.
  **Partial-state propagator for `addRegular` shipped** (Pesant
  2004): new `regularDfa` field on `NaryConstraint`, dispatched the
  same way as Régin's allDifferent and the linear propagator;
  forward + backward DFA reachability per position prunes any value
  whose transition lies on no accepting path. Achieves GAC on the
  regular constraint — infeasibility is detected at the root for
  many problems where the predicate-only encoding would exhaust the
  search.
  **Cycle-detection propagator for `addCircuit` shipped**: new
  `circuit` flag on `NaryConstraint` dispatches to a propagator that
  builds the singleton-edge graph at each call, detects strict
  sub-cycles, prunes chain-internal nodes from each chain's tail
  (preventing premature closure), forces tail = head when the chain
  reaches the full Hamiltonian length, and enforces successor
  uniqueness (any value with a known predecessor is removed from
  every other variable's domain). Sub-cycles are now detected at the
  root for many problems where the predicate-only encoding would
  have to descend.
  **Network-flow propagator for `addGcc` / `addGccRanges` shipped**
  (Régin 1996): new `gccSpec` field on `NaryConstraint`. The
  propagator builds a bipartite matching with value multiplicity (a
  value with upper bound `u` is replicated into `u` copies in the
  matching graph), runs Hopcroft-Karp, and uses Kosaraju SCCs plus
  free-copy reachability to prune any variable→value edge not on
  some max matching. Spec values absent from every variable's
  domain are still indexed so a `lower > 0` requirement on a
  no-longer-available value reports infeasibility at the root.
  Upper-bound constraints get full GAC; lower-bound constraints get
  conservative GAC (the propagator returns no changes when the
  current matching's distribution doesn't certify the lower bounds,
  except at a leaf where the matching is unique and any bounds
  violation is reported as real infeasibility).
  **Time-table propagator for `addCumulative` shipped** (Beldiceanu
  & Carlsson 2002 style): new `cumulativeSpec` field on
  `NaryConstraint` with `CumulativeSpec(durations, demands,
  capacity)`. Generalizes `addNoOverlap` from unary resource to
  integer-capacity renewable resource — at every time `t`, the sum
  of `demands[i]` across tasks whose half-open interval
  `[starts[i], starts[i] + durations[i])` covers `t` must not
  exceed `capacity`. The propagator computes each task's compulsory
  part `[lst_i, est_i + dur_i)`, accumulates them into a sparse
  usage profile, rejects compulsory-pile-up that exceeds capacity,
  and prunes any start candidate that would push the profile above
  capacity at some time. Closes the last `cumulative` follow-up
  noted above. Coverage: 17 tests in `test/cumulative_test.dart`.
- [x] **Soft constraints / MaxCSP.** New `SoftConstraints` extension
  with `declareSoft(boolVar, weight)`, `addSoftConstraint(weight,
  vars, predicate)` (one-step reify+declare), and
  `maximizeSatisfaction()`. Implementation: each soft constraint
  contributes `weight × boolVar` to a fresh aggregator variable
  installed on a `copy()` of the problem; the existing
  branch-and-bound (`maximize`) returns a provably-optimal
  assignment. Hard constraints still required; original problem
  not mutated. Coverage: 11 tests in
  `test/soft_constraints_test.dart`.
- [x] **Variable types beyond enumerated int/string.** *Interval
  variables shipped*: a third `_DomainRep` implementation
  (`_IntervalRep`) for contiguous-integer ranges with span larger
  than the bitset cutoff, plus user-facing `Problem.addRangeVariable`
  and `Problem.addNoOverlap` helpers. The interval rep stores just
  `(min, max)` and supports `O(1)` membership / length / bounds;
  `filter` keeps the rep as `_IntervalRep` when the predicate keeps
  a contiguous slice, otherwise promotes to bitset (if the new span
  fits) or list. `_setDomain(List<dynamic>)` detects contiguous
  ascending kept lists when the prior rep was `_IntervalRep` and
  preserves the form for trail/rollback. `addNoOverlap(starts,
  durations)` originally posted O(n²) pairwise disjunctions; it
  now dispatches to `addCumulative` with unit demand and unit
  capacity, picking up the time-table propagator for free
  (semantics unchanged, pruning strictly stronger). Coverage: 16
  tests in `test/interval_variables_test.dart` (15 pre-existing +
  1 equivalence test confirming `addNoOverlap` and
  `addCumulative(capacity=1, demand=1)` enumerate identical
  solution sets).
  *Set variables shipped*: new `SetVariables` extension on
  `Problem` (`addSetVariable`, `addSetVariables`,
  `addSetCardinality` / `Range` / `Var`, `addRequiredInSet`,
  `addExcludedFromSet`, `addSubset`, `addSetEquals`,
  `addSetDisjoint`, `addSetUnion`, `addSetIntersection`,
  `addSetDifference`, `memberIndicator` escape hatch). Decomposes
  every set variable into one 0/1 indicator variable per universe
  element; helpers become bounds-consistency linear (for
  cardinality), pairwise binary (for subset / equality / disjoint),
  or ternary n-ary (for union / intersection / difference). Every
  solve entry point on `Problem` post-processes the raw result so
  set variables appear as `Set<dynamic>` of included elements and
  the internal indicators are stripped from the map. The
  pre-existing `copy()` is updated to propagate the registry so
  `maximizeSatisfaction`'s internal-copy branch-and-bound
  materializes set variables correctly. Coverage: 40 tests in
  `test/set_variables_test.dart` covering declaration validation,
  power-set enumeration, pin enforcement, cardinality (exact /
  range / variable), subset with symmetric and asymmetric
  universes, equality / disjoint / union / intersection /
  difference, `memberIndicator` composition with reified equality,
  materialization through every solve entry point, a team-selection
  integration problem, and an equivalence test against a hand-built
  indicator decomposition. Total suite: 349 → 389. README has a new
  "Set Variables" section and `doc/set-variables.md` is the topical
  guide.
  *SAT-style clause constraint shipped in two steps*: first
  the user-visible unit-propagation payload, then the textbook
  two-watched-literal data structure that closes the item.
  New `ClauseSpec` value type, `clauseSpec` field on
  `NaryConstraint`, `addClause(positive:, negative:)` helper on
  `Problem` in the `LogicalConstraints` extension.
  The internal `_ClausePropagator` now maintains two per-clause
  watchers across propagation calls (Moskewicz et al., Chaff 2001):
  on each call it re-checks the two watched literals and, if one
  has become falsified, scans for another non-falsified literal to
  swap in; unit-propagation fires only when no replacement exists.
  Per-call work drops from O(literals) to O(1) amortized once
  watchers are initialized. The watcher state lives in a new
  per-engine side-table `_clauseWatchers` keyed by `ClauseSpec`
  identity (the engine infrastructure piece that previously
  blocked this — reusable for future stateful propagators). No
  trail-aware rollback needed: domain reductions are monotone
  under the engine's trail (rollback only restores values), so
  a watcher pointing at a non-falsified literal stays valid as
  the engine unwinds. The user-visible pruning behavior is
  identical to the prior single-pass scan, so this is a pure perf
  change. Coverage: 20 tests in `test/clause_test.dart` (16
  pre-existing + 4 new for rollback-after-deep-swap, pigeon-hole
  CNF infeasibility, brute-force-equivalent enumeration of a
  10-clause 3-SAT instance, and watcher-state freshness across
  repeated solves on the same `Problem`).
  *Per-variable seeding filter shipped*: the engine's `seedFor`
  loop now consults `_clauseWatchers[spec]` when scheduling a
  clause for propagation. If the spec is already initialized and
  the triggering variable is not one of the two watched literals'
  variables, the wake-up is skipped — the watched-literal
  invariant guarantees the propagator's behavior cannot change.
  Width-2 clauses (e.g., "at most one" pairwise encodings) skip
  the filter unconditionally because both literals are always
  watched, so the check is pure overhead on that hot path.
  Empirical 25-rep median wins on pigeonhole CNF: 7-in-6 plain
  136→112 ms (-18%) and CBJ 44→37 ms (-16%); 8-in-7 plain
  1715→1367 ms (-20%) and CBJ 347→292 ms (-16%). New
  `pigeonhole CNF 7-in-6 (UNSAT)` entry in
  `benchmark/benchmark.dart`, builder in `benchmark/problems.dart`,
  and matching CBJ-correctness test in
  `test/cbj_benchmarks_test.dart`. 22 tests in
  `test/clause_test.dart` (20 pre-existing + 2 new — a
  many-literal-clause pinning case and a watcher-swap-then-non-
  watched-change case).

## Tier 3 — engineering & ecosystem

- [x] **Isolate-based parallelism + cooperative checkpoints.** Both
  halves shipped. *Cooperative checkpoints*: every backtracking
  solver and the min-conflicts runner accept an optional
  `cancelToken: CancellationToken` parameter. The engine polls the
  token on every decision (cheap bool compare) and yields to the
  event loop on every ~100 decisions (`_yieldEveryDecisions`) — the
  yield is what lets a wrapping `Future.timeout(...)` actually fire,
  closing the documented `.timeout()` gotcha. Cancelled solves
  return the standard `'FAILURE'` literal; callers distinguish
  cancel from infeasibility by inspecting `token.isCancelled`.
  Coverage: 13 tests in `test/cancellation_test.dart`. Benchmark
  suite shows no measurable regression (SEND+MORE predicate-
  encoding: 2238 ms before, 2242 ms after; all other benchmarks
  within noise).
  *Worker-isolate runner*: four new top-level entry points in
  `lib/src/isolate_runner.dart` — `solveInIsolate`,
  `solveAllInIsolate`, `minimizeInIsolate`, `maximizeInIsolate`.
  Each takes a `Problem Function()` builder (closures attached to
  constructed `Problem` instances generally aren't sendable; a
  top-level builder is), spawns a worker isolate, runs the solve
  there, and bridges cancellation + stats back to the parent.
  `CSP.lastStats` is round-tripped over the message port on normal
  completion so the documented "stats populated when the future
  resolves" contract still holds. `CancellationToken` gained an
  `addListener(void Function())` method (additive; experimental
  surface) so the runner can forward parent-side cancel signals to
  the worker without polling. The runner exposes its own
  `timeout:` parameter that bridges to a worker-cancel + 250ms
  grace + `Isolate.kill()`, which actually terminates the worker
  (an external wrapping `.timeout()` would leave it running).
  Coverage: 11 tests in `test/isolate_runner_test.dart` (one-shot
  solve, infeasibility, stats round-trip, pre-cancelled token,
  mid-search Timer-driven bridged cancel, built-in timeout,
  builder-throws → `IsolateRunnerException`, streaming all
  solutions, listener-cancel teardown, minimize, maximize).
- [x] **Better propagation queue.** Done in 2.1.0 as part of the
  clean-room rewrite. `_propagate` (in `solver.dart`) uses
  `Queue<BinaryConstraint>` + `Queue<_GacTask>` with `removeFirst()`
  (O(1)) instead of the previous `List.removeAt(0)` (O(n)), plus
  identity-hashed `HashSet`s tracking what's already enqueued to
  avoid duplicate work. This was the largest single contributor to
  the 2.1.0 "~6× faster end-to-end" win.
- [x] **Solver statistics.** New `SolverStats` type in `types.dart`
  with `decisions`, `backtracks`, `propagations`, `binaryRevises`,
  `naryRevises`, `iterations`, and `elapsedMicros` fields. Engine
  populates them during the run; public entry points wrap the solve
  in a `Stopwatch` and expose the latest stats via `CSP.lastStats`
  and `Problem.lastStats`. All solvers now populate stats:
  backtracking paths fill in the search counters; streaming
  (`getSolutions`) flushes them via a try/finally when the stream
  completes or is cancelled; `solveWithMinConflicts` populates the
  new `iterations` field plus `elapsedMicros`. Coverage: 13 tests
  in `test/stats_test.dart` (was 6).
- [x] **Conflict-directed backjumping (Prosser 1993).** First-cut CBJ
  shipped across every backtracking entry point (`getSolution` /
  `getSolutions` / `minimize` / `maximize` / `solveWithRestarts` /
  `solveWithDomWdeg` and the corresponding `CSP.solve*` statics) via
  a new `enableConflictBackjumping: bool = false` parameter. Default
  off; opt-in preserves the existing chronological-backtracking
  surface. Conflict cause uses the coarse trail-walk approximation
  (every earlier-assigned variable sharing a constraint with any
  variable touched by the failed propagation) — sound but not
  optimally tight; the only effect of over-approximation is a
  shorter jump, never an incorrect one. Backjump target is the
  deepest variable in the accumulated conflict set; on root-level
  exhaustion with empty conflict, the engine returns FAILURE as
  usual. New `SolverStats.backjumps` and `backjumpLevelsSkipped`
  counters expose engagement. Sealed `_SearchResult` types for the
  single-solution CBJ helper; engine-state-bag for the streaming /
  optimization CBJ helpers (async generators / `Future<void>` can't
  return a value). Real CDCL with first-UIP nogood learning is a
  much larger follow-up (see `doc/cbj.md` "What's not implemented").
  Coverage: 13 tests in `test/cbj_test.dart` (wiring, enumeration
  equivalence with plain BT, composition with FC / restarts /
  dom-wdeg / optimization, edge cases, and a pigeonhole instance
  that asserts `backjumps > 0`).
- [x] **Random seed control.** `solveWithMinConflicts` now takes an
  optional `seed:` parameter and threads it through to the
  `_MinConflictsRunner`. Combined with the previously-added `seed`
  on `solveWithRestarts`, every randomized solver in the library is
  now reproducible. Coverage: 2 tests in `test/minconflicts_tests.dart`
  (deterministic-with-fixed-seed and cross-seed-diversity).
- [x] **`benchmark/` directory.** Added `benchmark/benchmark.dart`
  covering 8 classic CSPs: magic square 3x3 (no-clue and pinned),
  sudoku medium-hard, N-queens (8, 12, 16), Australia map coloring,
  SEND+MORE=MONEY cryptarithmetic. Outputs per-bench wall-clock and
  the new SolverStats counters. Entire suite runs in ~1.7s on a
  laptop; integrated with the existing CI benchmark step. Future
  follow-ups: Sudoku-17, golomb ruler, langford; tracking of
  baseline numbers for regression detection.
- [x] **Bounds-consistency linear propagator.** New `LinearSpec` value
  type in `types.dart`, `LinearOp` enum (`eq`/`leq`/`geq`), and a
  `linearSpec` field on `NaryConstraint`. New `LinearConstraints`
  extension on `Problem` with `addLinearEquals`, `addLinearLeq`,
  `addLinearGeq`, each taking `(vars, coeffs, bound)`. Coefficients
  may be positive, negative, or zero; domains must be numeric.
  Specialized `_LinearPropagator` in `solver.dart` dispatched the
  same way as Régin's allDifferent: computes the interval of the
  weighted partial sum from current domain mins/maxes, derives
  per-variable bounds, and filters each domain to values consistent
  with those bounds (bounds consistency, not GAC). Closes the
  SEND+MORE follow-up: the cryptarithmetic benchmark expressed with
  a single linear equation drops from 1834 ms (predicate-only
  encoding, GAC bails on 7-var free neighborhood) to 1 ms with the
  propagator (~1800× speedup, 1 decision vs 75). Coverage: 21 tests
  in `test/linear_propagator_test.dart` covering positive/negative/
  mixed-sign/zero coefficients, equality and both inequality forms,
  validation errors, single-var case, SEND+MORE rewritten with
  linear constraints, root-infeasibility detection (FC-style
  metric), and composition with allDifferent and minimize. README
  has a new "Linear Arithmetic Constraints" section. The benchmark
  now runs both the predicate-only and linear forms of SEND+MORE
  side-by-side.
- [x] **Pluggable consistency level.** New `ConsistencyLevel` enum in
  `types.dart` with `arcConsistency` (default; existing AC-3 + GAC
  behavior) and `forwardChecking` (revise each constraint touching the
  just-assigned variable once; cascade only when a revise produces a
  newly-singleton variable, matching textbook FC semantics). Threaded
  through `_BacktrackEngine` and every backtracking entry point:
  `CSP.solve`, `CSP.solveAll`, `CSP.solveWithDomWdeg`,
  `CSP.solveWithRestarts`, `CSP.solveOptimal`, and the matching
  `Problem` methods (`getSolution`, `getSolutions`,
  `getSolutionWithDomWdeg`, `getSolutionWithRestarts`, `minimize`,
  `maximize`). Composes naturally with optimization, restarts, and
  dom/wdeg. Coverage: 13 tests in `test/consistency_level_test.dart`,
  including a metric assertion that FC does strictly fewer binary
  revises than AC on a chain over a wide domain. SAC (singleton-arc
  consistency) is a separate follow-up. README has a new
  "Consistency Level" section.
- [ ] **MiniZinc / FlatZinc / XCSP3 frontend.** Interop with the
  standard CP modeling languages so the solver can ingest existing
  benchmarks and models.
- [x] **Semver discipline + API stability statement.** Added
  `STABILITY.md` documenting the public-API stability tiers, the
  versioning policy (when patch / minor / major bumps happen), the
  explicit list of stable APIs (Problem builder, solvers,
  constraint helpers, types), the list of experimental APIs
  (`ConsistencyLevel`, `LinearConstraints`, the dispatch flags on
  `NaryConstraint`, stronger propagators), what's internal (the
  `lib/src/*` underscore-prefixed members, performance
  characteristics), and the documented gotchas (single-static-slot
  `lastStats`, stream-stats-flush-on-completion, GAC bail-out work
  bound, no mid-solve `.timeout()`). Referenced from README's
  "Documentation" section.

## Closed follow-ups

- ~~**Integrated branch-and-bound** — replace the restart-tightening
  loop in `Problem._optimize` with bound-update inside the recursive
  search.~~ Done. See the COP entry in tier 1.

## Out of scope (for now)

- **Native FFI to OR-Tools / Choco.** Closes most tier-1 gaps overnight
  at the cost of native deps. Distinct project shape; not what this
  pure-Dart library is for.
- **Lazy clause generation (LCG).** Massive engineering project. Add
  only after the rest of the stack is mature and there's a concrete
  problem class that needs it.

## Cross-cutting

- Every new propagator must come with: a unit test for the propagator
  itself, an integration test through the solver, and a benchmark entry
  if it's perf-relevant.
- Every solver-level change should be runnable against the existing
  `test/` suite without regressions before it merges.
- README + relevant `doc/` topical guide updated in the same change as
  the feature.

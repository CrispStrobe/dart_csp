# Compiled finite-domain solve sessions

`Problem.compile()` creates an immutable snapshot of domains, built-in
constraint metadata, stable variable IDs and constraint adjacency. A
`CspSolveSession` owns one mutable engine, its trail, propagation queues and
prepared root state. Repeated queries apply assumptions directly to that trail
and roll back to the root in `finally`, including on cancellation or exceptions.

```dart
final problem = Problem()
  ..addRangeVariable('x', 0, 1000000000)
  ..addRangeVariable('y', 0, 1000000000)
  ..addLinearEquals(['x', 'y'], [1, 1], 100);
final compiled = problem.compile();
final session = compiled.createSession();

final first = await session.solve(
  assumptions: [const CspAssumption.equals('x', 30)],
);
assert(first.status == CspSolveStatus.satisfied);
assert(first.solution!['y'] == 70);

session.push();
session.assumeBounds('x', lower: 50, upper: 60);
final second = await session.solve();
session.pop();
final third = await session.solve(
  assumptions: [const CspAssumption.equals('x', 10)],
  timeLimit: const Duration(milliseconds: 100),
  maxDecisions: 1000,
);
print(session.rootPreparationCount); // 1 after ordinary completed queries
print(third.reusedRoot); // true
session.close();
```

## Scope and invalidation

The compiled model snapshots the builder. Subsequent source-domain or constraint
edits require another `compile()` call; they do not alter an existing model.
Built-in metadata collections are copied. Custom domain objects and arbitrary
predicate closures remain caller-owned and must be immutable/pure. If a closure
changes its meaning, compile a new model rather than querying cached root state.

The initial API uses **finite-domain plain backtracking**. It rejects continuous
variables/tags and does not retain learned clauses under assumptions. It is
separate from the older `IncrementalSolver`, whose compatibility behavior is
unchanged. Geometric parameter edits use `GeometrySolveSession`.

`push`, `pop`, `assumeEquals`, `assumeBounds` and `clearAssumptions` maintain scoped
assumptions. The `solve(assumptions: ...)` argument adds assumptions for that query
only. Contradictory assumptions produce an infeasible query and do not poison
later queries. A session permits one active query; use separate sessions from
the same compiled model for concurrent callers. Editing a busy/closed session
throws instead of racing its search state.

The `Problem.compile()` path preserves normal Problem-level postprocessing,
including set-valued outputs and hidden auxiliary-variable filtering. Direct
`CompiledCspModel(CspProblem(...))` works with raw low-level assignments.

## Results, budgets and validation

`CspSolveResult` has a detached solution map and stats snapshot. Status is one of
`satisfied`, `infeasible`, `cancelled`, `timeLimit`, `decisionLimit` or
`invalidCandidate`. Limits and cancellation are not reported as infeasibility.
Original-candidate rejection, including a nonfinite numeric value, returns
`invalidCandidate` with a diagnostic even when no decision budget was supplied.
Each query resets candidate diagnostics, so a rejected query cannot mislabel a
later limited or satisfied query.

Successful assignments are checked against the original declared domains and
constraint semantics. Tagged globals are validated from their metadata rather
than relying on internal placeholder predicates. The validator covers
allDifferent, linear relations, regular automata, circuits/subcircuits, GCC,
cumulative resources, clauses and non-overlapping rectangles; ordinary predicates
are evaluated directly.

Deadlines and cancellation are polled between search/propagation steps. A user
callback or one global-propagator invocation is not forcibly preemptible. This is
cooperative execution, not a hard real-time guarantee. Root preparation is kept
only when it finishes; an interrupted preparation is rolled back and retried.

## Reuse evidence

`benchmark/compiled.dart` compares the current one-shot path with prepared
sessions on the same model. Each batch makes 20 equality edits to one variable
alongside a fixed constraint set. It uses two warmup batches and seven paired
measured batches, alternating order, and checks every returned assignment.
Compile-plus-first-solve timing is printed separately. Hardware was not pinned.

One Dart 3.14.0 native JIT container sample:

| Fixed variables | Fresh 20-query median / p95 | Reused 20-query median / p95 | Root preparations |
|---|---:|---:|---:|
| 64 | 9.440 / 15.100 ms | 2.434 / 3.053 ms | 1 |
| 512 | 15.558 / 24.893 ms | 3.859 / 7.381 ms | 1 |

This fixture measures root/index reuse when permanent constraints are unchanged.
It is not a release-to-release comparison or a speed guarantee for arbitrary
search-heavy models. Twenty-two new tests cover query isolation, scopes, model
snapshots, tagged semantics, compact assumptions, cancellation, exception cleanup,
sets and independent sessions. Forty edit queries are compared against an
independent Cartesian-product oracle.

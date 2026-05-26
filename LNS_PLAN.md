# Large Neighborhood Search (LNS) — implementation plan

A focused plan for the next session(s) to bring LNS into
`dart_csp`. This doc exists so a fresh session can pick the work
up cold: scope, architecture, milestones, destroy-policy
catalogue, and the open design questions are all here.

**Estimated effort:** 2-4 sessions. LNS is mechanically simple
(it's a wrapper around the existing `minimize` / `maximize`
engine) but the design surface — destroy policies, acceptance,
restarts, parallelism — has real choices to make.

---

## 1. Scope decision: single-thread, sequential LNS first

`dart_csp` should ship single-threaded sequential LNS first
(later: parallel exploration via the existing
`lib/src/isolate_runner.dart`).

- LNS decomposes a hard optimization problem into a sequence of
  small focused searches. Each iteration "destroys" a subset of
  variables (frees them) while fixing the rest to their current
  best values, then re-solves the smaller sub-problem. Improving
  solutions are accepted; non-improving solutions are discarded.
- The whole loop sits on top of the existing
  `Problem.minimize` / `Problem.maximize` engine. No solver
  internals need to change — LNS is an orchestration layer
  above the search.
- The design surface is in the **destroy policies** (which
  variables to free this iteration) and the **acceptance /
  restart logic** (what counts as progress, when to give up
  on a destroy strategy, how to mix multiple destroys).
- Parallel LNS (multi-worker exploration sharing a best-known
  incumbent) is a Tier-2 extension. The `isolate_runner.dart`
  worker isolate machinery already exists; wiring it up is a
  separate session once sequential LNS is stable.

**Out of scope for v1:** parallel exploration, learned-no-good
sharing between iterations (that's LCG territory), per-policy
adaptive bandit weighting (Adaptive LNS — Ropke & Pisinger
2006). All three can be added later; v1 nails the sequential
core.

---

## 2. Architecture sketch

```
lib/src/lns/
├── policy.dart      # DestroyPolicy abstract class + library of impls
├── accept.dart      # Acceptance strategy (improving-only, simulated
│                    # annealing, late-acceptance, ...)
└── lns.dart         # Top-level: Problem.lnsMinimize / lnsMaximize entry
                     # points; orchestration loop
```

`lib/dart_csp.dart` re-exports `LnsPolicy`, the builtin policies,
and the `lnsMinimize` / `lnsMaximize` extensions so callers can
do:

```dart
final result = await problem.lnsMinimize(
  'cost',
  policy: LnsPolicy.random(fraction: 0.3),
  iterationBudget: 200,
);
```

### Destroy policy shape

```dart
abstract class LnsPolicy {
  /// Return the variable names to FREE this iteration. Everything
  /// else gets pinned to its current best value. May read the
  /// current best solution + the iteration counter + rng to make
  /// the decision.
  List<String> select(LnsContext ctx);
}

class LnsContext {
  final Problem problem;
  final Map<String, dynamic> bestSolution;
  final num bestObjective;
  final int iteration;
  final Random rng;
}
```

Standard policies (start with these in v1):

- **`LnsPolicy.random({double fraction})`** — pick a random
  fraction of variables uniformly. The textbook starting point.
  Default fraction 0.2-0.3 (Shaw 1998 used 0.15-0.4).
- **`LnsPolicy.window({int windowSize})`** — pick a contiguous
  window of variables (by declaration order). Cheap, but useful
  on scheduling problems where adjacent variables share
  constraints.
- **`LnsPolicy.related({int seedCount, double extendFraction})`**
  — pick `seedCount` random variables, then extend the set with
  variables that share a constraint with any seed (Shaw's
  "related" heuristic, 1998). Requires building a constraint-
  variable graph from the Problem.
- **`LnsPolicy.combined(List<LnsPolicy>, {List<double>? weights})`**
  — round-robin or weighted-random pick from a list. Lays the
  groundwork for ALNS later by making "multiple destroys" a
  first-class concept.

### Acceptance strategy

```dart
abstract class LnsAccept {
  bool accept(num candidate, num incumbent, LnsContext ctx);
}
```

- **`LnsAccept.improving()`** — accept only strict improvements.
  The textbook default; converges to a local optimum.
- **`LnsAccept.simulatedAnnealing({double initialTemp, double cooling})`**
  — accept worsening moves with probability `exp(-Δ/T)`; T cools
  over iterations. Helps escape plateaus on hard problems.
- **`LnsAccept.lateAcceptance({int historySize})`** — Burke
  et al. 2017's "Late Acceptance Hill Climbing". Compare each
  candidate to the objective from `historySize` iterations ago
  rather than the current incumbent. Empirically strong on
  combinatorial optimization.

v1 ships `improving` and `simulatedAnnealing`. Late-acceptance
is a Tier-2 extension.

### Orchestration loop

```
1. Find an initial feasible solution via the existing
   getSolution(). If none → return FAILURE.
2. Set incumbent = initial; bestObjective = initial[objective].
3. For iter in 0..iterationBudget:
   a. freed = policy.select(ctx)
   b. fixed = problem.copy(); for v not in freed: pin v to incumbent[v]
   c. candidate = fixed.minimize(objective, ...) [time-bounded]
   d. if candidate == FAILURE: continue (sub-problem infeasible
      under the fixed pins — rare but possible)
   e. if accept(candidate[objective], bestObjective, ctx):
        incumbent = candidate; bestObjective = candidate[objective]
4. Return incumbent.
```

Time bound per iteration uses the existing
`CancellationToken` machinery — wrap the inner solve in a
timer that cancels after `iterationTimeMs` milliseconds, then
treat the cancelled-failure case like an infeasible sub-problem.

---

## 3. Milestones

Each milestone is a self-contained, testable increment. Land them
in order.

### M1 — Random policy + improving-only accept + sequential loop

- `lib/src/lns/policy.dart` with `LnsPolicy` abstract base and
  `LnsPolicy.random` implementation.
- `lib/src/lns/accept.dart` with `LnsAccept.improving`.
- `lib/src/lns/lns.dart` exposing `lnsMinimize` / `lnsMaximize`
  as `Problem` extensions. Orchestration loop calling the
  existing `Problem.copy()` + pinning + `minimize`.
- Integration with `CancellationToken` for per-iteration
  time-bounding via the existing cancellation infra.
- Unit tests over a small TSP-like problem and a small bin-
  packing problem: verify that LNS produces an assignment at
  least as good as the initial solution, and that the
  iteration counter / accept counter / reject counter are
  reported via a new `LnsStats` struct.

### M2 — Window + related destroy policies

- Add `LnsPolicy.window` (contiguous variable window).
- Add `LnsPolicy.related` (Shaw 1998): compute a constraint-
  variable graph at construction time, then extend a seed set
  through it. The graph build is straightforward — the
  `Problem` has direct access to `_constraints` /
  `_naryConstraints` and their variable lists.
- Tests: scheduling-shaped problem (n-job single-machine
  weighted-completion) showing `window` outperforming `random`
  on time-ordered variables; routing-shaped problem (TSP)
  showing `related` recovering the cluster structure that
  `random` would miss.

### M3 — Simulated annealing acceptance + combined policy

- `LnsAccept.simulatedAnnealing` with the textbook cooling
  schedule.
- `LnsPolicy.combined` for mixing multiple destroys per run.
- Tests: a problem where pure-improving LNS gets stuck at a
  local optimum and simulated-annealing escapes it.

### M4 — `bench(lns)` + docs

- New `bench(lns)` section in `benchmark/benchmark.dart`
  comparing the LNS-driven optimization to the existing
  `minimize` / `maximize` on a handful of hard problems.
  Expect LNS to win on the larger instances; the small
  instances should be a wash or slight loss (warm-up + restart
  overhead).
- `doc/lns.md` topical guide covering the policy + acceptance
  catalogue, the `iterationBudget` / `iterationTimeMs` knobs,
  how the inner solve interacts with the existing heuristic
  flags, and a worked example.
- README + STABILITY classification (LNS surface is
  experimental).
- PLAN.md: flip the LNS strategic-gap entry from `[ ]` to `[x]`.

### M5 (optional) — Parallel LNS via `isolate_runner.dart`

- Worker isolates each run an LNS loop on the same problem with
  a different RNG seed (or a different policy).
- Workers exchange incumbents via the existing message-port
  protocol; the orchestrator broadcasts the best-known
  objective so each worker can prune.
- Tests: timing comparison single-thread vs N-worker on a hard
  problem.

This milestone is genuinely Tier-2 — ship M1-M4 first, evaluate
real-world feel, then decide whether the parallelism is worth
the design cost.

---

## 4. Open design questions

These are decisions worth making explicitly during M1, before
the interface gets large enough that changes hurt.

- **Where do `lnsMinimize` / `lnsMaximize` live in the public
  API?** Options: (a) new entry points on `Problem`, (b) a free
  function taking a `Problem`, (c) a `LnsRunner` class wrapping
  a `Problem`. Probably (a) for consistency with
  `Problem.minimize` and the streaming entry points. Document
  in `STABILITY.md` as experimental.
- **`iterationBudget` vs `iterationTimeMs` vs both?** Both, with
  `iterationBudget` as the default cap and `iterationTimeMs`
  optional. Allow `totalTimeMs` as an overall budget too — a
  user typically thinks in wall-clock terms ("optimize for 30
  seconds, take the best you find").
- **What does `getSolution` / `getSolutions` look like during
  LNS?** Each inner solve mutates `CSP.lastStats` (the
  static-slot gotcha). LNS should snapshot per-iteration stats
  into the new `LnsStats` and clear the static slot at the end.
- **RNG seed.** Pass through the same way the existing
  `solveWithRestarts` does (optional `seed:`). Default to a
  fixed seed for reproducibility; document the random
  fallback.
- **Initial solution heuristic.** v1 uses the default
  `getSolution()`. A flag to pick a different heuristic (e.g.
  `getSolutionWithDomWdeg()`) would be useful — wire it through
  as `initialSolveOptions:` once the parameter list grows past
  the simple-helper threshold.
- **Best-objective tracking under floats.** The existing
  `minimize` returns the objective as a `num`. If we ever wire
  up float variables (separate PLAN.md item), LNS needs to
  cope with `double` objectives carefully (NaN handling,
  epsilon-comparison). Defer until floats land.

---

## 5. Test plan

### Unit tests

`test/lns/policy_test.dart` — each builtin policy returns the
right number of variables; respects the rng seed for
reproducibility; the `related` policy expands a seed through
the constraint graph.

`test/lns/accept_test.dart` — improving accept rejects strict
worsening; simulated annealing accepts worsening with
probability that cools over iterations (assert via a fixed
seed).

### Integration tests

`test/lns/integration_test.dart` — run LNS on a few problems
where the optimum is known. Assert that LNS finds the optimum
within a reasonable iteration budget, and that the per-iteration
`LnsStats` are sane (iterations ≤ budget, accepts ≤ iterations,
final objective ≤ initial objective for minimize).

### Performance bench

`benchmark/benchmark.dart` gains a `bench(lns)` section
comparing LNS vs plain branch-and-bound on:

- A larger TSP (30 cities) where LNS should outperform.
- A larger bin-packing (50 items) where LNS should outperform.
- A small problem (e.g. magic-square) where LNS should be a
  wash or slight loss vs plain solve (the warm-up + iteration
  overhead dominates).

---

## 6. References

- [Shaw, P. (1998). "Using Constraint Programming and Local
  Search Methods to Solve Vehicle Routing Problems."](https://www.researchgate.net/publication/220944906)
  The original LNS paper; introduces the "related" destroy
  heuristic.
- [Ropke, S. & Pisinger, D. (2006). "An Adaptive Large
  Neighborhood Search Heuristic for the Pickup and Delivery
  Problem with Time Windows."](https://transp-or.epfl.ch/courses/OptimizationAndSimulation2012/papers/Ropke2006.pdf)
  ALNS — adaptive bandit weights over multiple destroys.
- [Burke, E. K. et al. (2017). "The Late Acceptance Hill-
  Climbing Heuristic."](https://www.sciencedirect.com/science/article/pii/S0377221717304174)
  The late-acceptance acceptance criterion.
- [Pisinger, D. & Ropke, S. (2010). "Large Neighborhood Search,"
  in Handbook of Metaheuristics, 2nd ed.](https://link.springer.com/chapter/10.1007/978-1-4419-1665-5_13)
  Standard reference text covering the full design surface.
- [OR-Tools LNS implementation](https://github.com/google/or-tools/tree/main/ortools/sat)
  — battle-tested precedent; the destroy-policy split here
  mirrors theirs.
- [Chuffed LNS](https://github.com/chuffed/chuffed) — same.

The OR-Tools and Chuffed implementations have been through many
rounds of MiniZinc Challenge competition. Both are open-source
and can be consulted for the corner cases the LNS literature
doesn't fully nail down.

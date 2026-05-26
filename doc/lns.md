# Large Neighborhood Search (LNS)

For hard optimization problems where plain `Problem.minimize` /
`Problem.maximize` proves the optimum but takes too long, **Large
Neighborhood Search** finds a near-optimal solution dramatically
faster by decomposing the search into a sequence of small, focused
sub-solves. The library ships LNS as
`Problem.lnsMinimize` / `Problem.lnsMaximize` (extension on
`Problem`), sitting on top of the existing
branch-and-bound engine.

## TL;DR

| Question | Answer |
|---|---|
| When do I reach for LNS over `minimize`? | When plain branch-and-bound is too slow to prove optimality and a near-optimal answer in seconds is more useful than the optimum in minutes. |
| Does LNS find the optimum? | Not guaranteed. It's a metaheuristic. It often *finds* the optimum but doesn't *prove* it. |
| Default destroy policy? | `LnsPolicy.random(fraction: 0.2)` (textbook). |
| Default acceptance? | `LnsAccept.improving()` (strict improvement only). |
| Default budget? | 100 iterations, no per-iteration timeout, no overall timeout. |

Quick example:

```dart
final p = Problem();
// ... build a model with an integer 'maxLoad' objective variable ...
final result = await p.lnsMinimize(
  'maxLoad',
  policy: LnsPolicy.random(fraction: 0.5),
  iterationBudget: 50,
  seed: 17,
);
final best = result.solution as Map<String, dynamic>;
print('best maxLoad = ${best["maxLoad"]}');
print(result.stats);
// LnsStats(iterations: 50, accepts: 3, rejects: 47, infeasibles: 0,
//          timeouts: 0, initialObjective: 89, finalObjective: 30, …)
```

## Algorithm

1. **Initial solve.** Find any feasible solution with `CSP.solve` (not
   `CSP.solveOptimal` — proving optimality up-front would defeat the
   point). Bail out with `'FAILURE'` if the host problem is
   infeasible.
2. **Destroy + repair loop.** For each iteration up to
   `iterationBudget`:
   1. The **destroy policy** picks a subset of variables to *free*
      this iteration.
   2. Every other variable is **pinned** to its value in the current
      incumbent. The pinned variables aren't removed from the model
      — they just have a single-value domain — so all the original
      constraints still propagate.
   3. The library runs `CSP.solveOptimal` on the sub-problem,
      time-bounded by `iterationTimeMs` if supplied.
   4. The **acceptance strategy** decides whether the candidate
      replaces the incumbent.
3. **Return** the best incumbent and per-run [`LnsStats`].

The loop exits early on overall-timeout (`totalTimeMs`) or
caller-side cancellation (`cancelToken`).

## Destroy policies

All five builtin policies live on `LnsPolicy` as factory
constructors. Subclass `LnsPolicy` for problem-specific destroys —
the `LnsContext` exposes everything you need (variable list,
incumbent, iteration counter, RNG, and a pre-built constraint-
variable adjacency graph).

| Policy | What it frees | Best for |
|---|---|---|
| `LnsPolicy.random(fraction: 0.2)` | Uniformly random fraction of all variables | Default; works on everything |
| `LnsPolicy.window(windowSize: N)` | Contiguous window of N variables in declaration order | Scheduling problems where neighbouring variables share constraints |
| `LnsPolicy.related(seedCount: 1, extendFraction: 0.2)` | Seed + BFS expansion through the constraint-variable graph (Shaw 1998) | Routing / clustering problems with structured constraint locality |
| `LnsPolicy.combined([…], weights: […])` | Weighted-random pick from sub-policies each iteration | Mixing destroys with static weights |
| `LnsPolicy.adaptive([…], segmentSize: 100, smoothingFactor: 0.1, …)` | Weighted pick from sub-policies, re-weighting per segment based on observed reward (Ropke & Pisinger 2006) | Mixing destroys when you don't know upfront which one suits the problem |

The `fraction` / `windowSize` / `extendFraction` knobs default to
the textbook values from Shaw 1998 (0.15-0.4). Larger destroys give
the inner solve more room to improve but cost more per iteration —
LNS is a budget-vs-quality tradeoff at its core.

### Adaptive policy mechanics

`LnsPolicy.adaptive` is **stateful**: it owns a per-sub-policy
weight vector that updates each `segmentSize` iterations based on
observed reward. After every iteration the LNS orchestrator calls
`policy.observe(...)` with two flags:

- `accepted` — the acceptance strategy admitted the candidate
- `improvedBest` — the candidate strictly improved the global best

Score per iteration is `rewardBest` if `improvedBest`,
`rewardAccepted` if `accepted` (but not best), and zero otherwise.
At each segment boundary every sub-policy's weight is updated to
`(1 - smoothingFactor) × old_weight + smoothingFactor × avg_score`
and segment counters reset. A small positive floor prevents a
starved policy from being permanently locked out. Inspect the
adapted weights after a run by casting to the impl type:

```dart
final policy = LnsPolicy.adaptive([…]);
final result = await problem.lnsMinimize('cost', policy: policy);
final weights = (policy as dynamic).weights as List<double>;
print(weights); // sub-policy selection mass after the run
```

## Acceptance strategies

| Strategy | Behaviour |
|---|---|
| `LnsAccept.improving()` | Strict improvement only. Converges to a local optimum. |
| `LnsAccept.simulatedAnnealing(initialTemp: 1.0, cooling: 0.995)` | Improvements always accepted; worsening moves accepted with probability `exp(-Δ / T)`, where `T = initialTemp × cooling^iteration`. Escapes local optima at the cost of running longer for the same final quality. |
| `LnsAccept.lateAcceptance(historySize: 100)` | Burke et al. 2017's LAHC: accept iff the candidate beats either the current incumbent OR the historical incumbent from `historySize` iterations ago. One hyperparameter, empirically strong on combinatorial optimization. Stateful — one instance per run. |

### Best-ever vs current

The orchestrator tracks "current solution" (what the next destroy
runs on top of) and "best-ever solution" (what gets returned)
separately. Improving-only acceptance keeps them in lock-step, but
simulated annealing and late-acceptance can both temporarily move
"current" to a worse solution. The `LnsResult.solution` is always
the best objective LNS observed at any point.

## Performance: how big is the win?

The `bench(lns)` section of `benchmark/benchmark.dart` compares
LNS against plain `Problem.minimize` on bin-packing with min-max
load — distribute `n` items of fixed weights across `k` bins and
minimise the heaviest bin's load. Plain B&B proves optimality and
gets exponentially expensive as `n` grows; LNS reaches the same
(or near-) optimum in a small fraction of the time:

| Instance | Plain median | LNS median (random/0.5, 50 iters) | Speedup | LNS objective vs optimum |
|---|---|---|---|---|
| 8 items / 3 bins | ≈ 390 ms | ≈ 140 ms | ≈ 3× | 17 / 17 (optimal) |
| 10 items / 3 bins | ≈ 2.8 s | ≈ 600 ms | ≈ 5× | 23 / 22 (1 off) |
| 12 items / 3 bins | ≈ 40 s | ≈ 2.8 s | ≈ 14× | 30 / 30 (optimal) |

(Local M-series numbers; run `dart run benchmark/benchmark.dart`
for fresh figures on your machine.) The shape is what to expect of
LNS: small instances are a wash or slight loss (the warm-up + per-
iteration overhead doesn't get amortised), but the gap grows
super-linearly as the instance size — and the plain proof-of-
optimality cost — increases.

## Knobs

- **`iterationBudget`** (default `100`). Hard cap on iterations.
- **`iterationTimeMs`** (default `null`). Per-iteration deadline.
  Iterations whose inner solve exceeds this are counted as timeouts
  in `LnsStats.timeouts` and don't update the incumbent.
- **`totalTimeMs`** (default `null`). Overall wall-clock cap. Cut
  earlier than the iteration budget if reached.
- **`seed`** (default `null`). RNG seed for reproducibility. With a
  fixed seed the run is deterministic across machines (modulo
  scheduler-dependent timing of the per-iteration deadline).
- **`consistency`** (default `ConsistencyLevel.arcConsistency`).
  Applied to every inner solve. SAC preprocessing inside LNS is
  rarely worth the per-iteration cost — leave at AC unless the
  inner sub-problems happen to have a lot of SAC-only infeasibility.
- **`cancelToken`** (default `null`). Cooperative cancellation.
  Fires between iterations and through the inner solve.

## When LNS *won't* help

- **Small problems.** Warm-up + per-iteration overhead can swamp
  any per-iteration gains. The benchmark above shows this on the
  n=8 case where the LNS-vs-plain ratio is barely 3×.
- **Problems where the initial feasible solution is already
  optimal.** LNS spends every iteration rediscovering the same
  incumbent and rejecting it. Spot this in `LnsStats` as
  `accepts: 0` with no `infeasibles`.
- **Problems with no good destroy structure.** If the model has
  uniform connectivity (every variable touches every constraint)
  the destroy policies are all roughly equivalent and LNS
  degenerates to "random restart with extra steps". Mostly true
  of completely-symmetric problems.

## Parallel LNS (portfolio mode)

`lnsMinimizeInIsolates` / `lnsMaximizeInIsolates` (top-level
functions from `dart_csp.dart`, not extensions on `Problem`) run N
independent LNS workers in parallel. Each worker uses its own RNG
seed; the parent returns an `LnsParallelResult` carrying the best
result and every worker's individual result.

```dart
final result = await lnsMinimizeInIsolates(
  buildMyProblem,     // top-level / sendable Problem Function()
  'cost',
  workerCount: 4,
  policyBuilder: () => LnsPolicy.random(fraction: 0.5),
  iterationBudget: 200,
  seeds: [0, 1, 2, 3],
  timeout: Duration(seconds: 30),
);
print('best = ${result.bestResult.stats.finalObjective}');
for (final r in result.perWorker) {
  print('  worker: ${r.stats.finalObjective}');
}
```

Note `policyBuilder` and `acceptBuilder` — these are called inside
each worker so stateful policies (`adaptive`, `lateAcceptance`)
get a fresh instance per worker. The `build` closure must be
sendable across the isolate boundary (top-level / static functions
or closures over sendable values only).

The default is **portfolio LNS**: workers don't share incumbents
mid-run. For problems with many local optima the speedup from
independent restarts is already substantial.

### Cooperative parallel LNS

Pass `cooperative: true` to enable mid-run incumbent broadcasting:

```dart
final result = await lnsMinimizeInIsolates(
  buildMyProblem,
  'cost',
  workerCount: 4,
  iterationBudget: 200,
  cooperative: true,
);
```

In cooperative mode, whenever any worker finds a new local best, the
parent forwards the objective value to every sibling worker via the
existing control port (the same channel used to deliver cancellation
signals). Each sibling uses the new bound to pre-tighten the
objective domain of its **next** iteration's sub-problem — any
iteration whose tightened objective domain becomes empty is skipped
as infeasible. The local incumbent, RNG, and policy state stay
independent per worker; only the objective bound (a single `num`)
crosses the channel.

The cooperation lets workers prune each other's searches:

- A worker stuck on a plateau no longer explores sub-problems that
  provably can't beat the global best.
- A worker that lucky-finds a strong incumbent broadcasts it; every
  other worker immediately stops considering inferior candidates.

The broadcast overhead is negligible (small message, processed on
the worker's event-loop microtasks), so `cooperative: true` is
strictly an improvement on hard instances and at most a wash on
easy ones where the workers all converge before any broadcast can
help.

#### Perf anchor

`benchmark/benchmark.dart` runs a `bench(cooperative-lns)` section
comparing portfolio (`cooperative: false`) and cooperative
(`cooperative: true`) on the same problem builder, worker count,
iteration budget, and seed list — only the flag differs. Sample
run on `bin-packing 12 items / 3 bins (3 workers, budget 80,
fraction 0.5)`:

```
bin-packing 12 items / 3 bins (3 workers, budget 80, fraction 0.5)
  portfolio    obj=30   ~1.0–1.4 s  workers:3 it:80 acc:8
  cooperative  obj=30   ~1.0–1.2 s  workers:3 it:80 acc:8
```

Both modes converge to the same global incumbent (`obj=30`). Wall-
clock variance across isolate runs is ~10-20% so the per-rep gap
between portfolio and cooperative is noisy on this workload; the
benchmark is a *non-regression* anchor first, with the actual win
showing up on instances where some workers find improvements much
earlier than others — exactly the workloads cooperation is
designed for. Run it locally with `dart run benchmark/benchmark.dart`
for fresh numbers.

## What's not implemented (yet)

- **Learned-no-good sharing between iterations.** That's LCG
  territory — would require explanation-aware propagators, which
  is the next strategic gap (see PLAN.md and LCG_PLAN.md).

## References

- Shaw, P. (1998). *Using Constraint Programming and Local Search
  Methods to Solve Vehicle Routing Problems.* Introduces LNS and
  the "related" destroy heuristic.
- Ropke, S. & Pisinger, D. (2006). *An Adaptive Large Neighborhood
  Search Heuristic for the Pickup and Delivery Problem with Time
  Windows.* ALNS: adaptive bandit weights over multiple destroys.
- Pisinger, D. & Ropke, S. (2010). *Large Neighborhood Search*, in
  *Handbook of Metaheuristics*, 2nd ed. The standard reference
  text covering the full design surface.
- The OR-Tools (`ortools/sat`) and Chuffed source trees are open-
  source precedents that have been through many rounds of MiniZinc
  Challenge competition; the destroy / accept split here mirrors
  theirs.

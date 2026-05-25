# Variable Ordering Heuristics

`dart_csp` ships **four** variable-ordering heuristics on top of
the default MRV picker, plus one wrapper that composes with any of
them. They differ in what they look at, how they update their
internal state, and where they shine. This guide consolidates the
material that's split across four README sections and walks
through the choice.

| Heuristic | Entry point | Score | Updates on | Picker shape |
|---|---|---|---|---|
| **MRV** (default) | `getSolution()` | `dom_size` | nothing — static | minimize `dom_size` |
| **dom/wdeg** (Boussemart et al. 2004) | `getSolutionWithDomWdeg()` | `dom_size / wdeg` | propagation conflict (bump per-constraint weight) | minimize `dom_size / wdeg` |
| **VSIDS** (Moskewicz et al. 2001) | `getSolutionWithActivity()` | `dom_size / (1 + activity)` | propagation conflict (bump per-variable activity, decay multiplicatively) | minimize `dom_size / (1 + activity)` |
| **IBS** (Refalo 2004) | `getSolutionWithImpact()` | `dom_size / (1 + Σ impact)` | every decision (running mean of pruning fraction) | minimize `dom_size / (1 + Σ_a I(v, a))` |
| **LC** (Lecoutre 2009) | `getSolutionWithLastConflict()` | — wrapper — | propagation conflict (record variable being pinned) | first try `_lastConflictVar`, fall through to configured picker |

All four pickers reduce to MRV pre-observation (when no conflict
or successful pruning has been seen yet), so on easy problems they
behave identically. The differences appear on structured /
combinatorial / UNSAT instances where the choice of variable to
branch on actually matters.

## TL;DR — which one should I use?

| Situation | Reach for |
|---|---|
| You don't know what to use | **MRV** (the default) — try the others if MRV is slow |
| Sudoku, n-queens, magic-square, anything that solves in < 1s | **MRV** — no point adding overhead |
| Hard structured CSP (rostering, graph coloring, scheduling) | **dom/wdeg** — proven on these workloads |
| SAT-like / CNF / pigeonhole | **VSIDS** or **LC + dom/wdeg** — they earn their keep on UNSAT |
| You have time to experiment | Try **dom/wdeg + LC** first; fall back to **IBS** if it doesn't help |
| You want a single "smart default" | **dom/wdeg + LC** — Lecoutre's experiments support this combination |

The honest answer is: **MRV is fine for most problems.** The other
heuristics matter when search reaches the millions-of-decisions
scale. Below 1000 decisions, the per-pick overhead of a smarter
heuristic can outweigh the gain.

## The four heuristics

### MRV (Minimum Remaining Values)

The default. Picks the variable with the smallest current domain.
No state, no updates, no flags — just `_pickByMRV()`. Originated in
Haralick & Elliott (1980); textbook fail-first principle.

Cost: a single linear pass over the domain table per pick. The
absolute baseline.

### dom/wdeg (Boussemart, Hemery, Lecoutre, Sais, 2004)

Per-constraint weight `wdeg(c)`, initialized to 1. On every
propagation conflict in constraint `c`, increment `wdeg(c)`.
Variable score `wdeg(v) = Σ wdeg(c)` over constraints `c` that
still have at least one unassigned other variable in their scope.
Picker minimizes `dom_size(v) / wdeg(v)`.

Effect: variables touching constraints that have recently failed
get a higher score and are picked sooner. Persists across the
whole search (no decay).

Shines on: structured industrial benchmarks where the failures
are localized to a few "hard" constraints — rostering, graph
coloring, RCPSP.

### VSIDS (Moskewicz, Madigan, Zhao, Zhang, Malik, 2001)

Per-variable activity (`_varActivity`), initialized to 0. On every
propagation conflict, bump every variable in the failing
constraint's scope by `_activityInc`, which grows multiplicatively
by `1 / decay` per conflict (`decay = 0.95`). This is the standard
MiniSat trick — equivalent to uniformly decaying every existing
score by `decay`, but O(1) per conflict instead of O(|vars|).
Rescale (`_activityInc * 1e-100`) when the increment hits `1e100`.

Picker minimizes `dom_size(v) / (1 + activity(v))`. Same shape as
dom/wdeg, but VSIDS's bumps decay where dom/wdeg's are monotone,
so VSIDS reacts faster to a changing "guilty" subset of variables.

Shines on: SAT-style / CNF instances where the conflict structure
shifts over the course of search.

### IBS (Refalo, 2004)

Per-`(variable, value)` running mean of **impact**: the fraction
of the joint search space (product of remaining domain sizes)
that propagation eliminated after pinning `(v, a)`. Failed
propagation contributes impact 1.0; successful propagation
contributes `1 - exp(logP_after - logP_before)`, clamped to
`[0, 1]`. Updated with the standard incremental-mean formula on
every decision (success or failure).

Picker minimizes `dom_size(v) / (1 + Σ_a I(v, a))` where the sum
is over values currently in `v`'s domain.

Shines on: problems with a wide spread of per-decision pruning —
IBS learns from successful propagation too, unlike dom/wdeg and
VSIDS which only learn from failures. On uniform-pruning workloads
(CNF / pigeonhole) it reduces to MRV-with-bumps and behaves much
like VSIDS without the multiplicative growth.

### LC (Lecoutre, 2009) — wrapper

Not a primary picker. On every propagation failure, record the
variable being pinned (`_lastConflictVar`). On the next call to
`_pickVariable`, if that variable is still unassigned, return it
directly — focusing the search on the conflict cause. When the
recorded variable becomes assigned (via propagation or via the
decision pin), fall through to the configured underlying picker.

The cheapest high-value heuristic in the literature: ~50 lines of
code on top of the existing picker. Lecoutre's experiments show
LC + dom/wdeg outperforming pure dom/wdeg on a wide range of
structured benchmarks.

LC pairs naturally with any of the four primary pickers. The
canonical deployment shape is `LC + dom/wdeg`:

```dart
final sol = await p.getSolutionWithLastConflict(useDomWdeg: true);
```

## Composition rules

### Picker dispatch order

`_pickVariable` consults the heuristics in this fixed order, using
the first applicable one:

1. **LC** — if `useLastConflict` is on and `_lastConflictVar` is
   still unassigned, return it.
2. **IBS** — if `useImpact` is on.
3. **VSIDS** — if `useVsids` is on.
4. **dom/wdeg** — if `useDomWdeg` is on.
5. **MRV** — fallback.

This means LC always wraps the *primary* picker — there is no
"LC alone" mode (you can pass no underlying flags, which gives
LC + MRV). Among the primary pickers, the one set with the
highest precedence wins.

### What stacks with what

| Primary picker | LC compatible? | Restart compatible? | CBJ compatible? | FC/SAC compatible? |
|---|---|---|---|---|
| MRV | ✓ | ✓ | ✓ | ✓ |
| dom/wdeg | ✓ | ✓ | ✓ | ✓ |
| VSIDS | ✓ | ✓ | ✓ | ✓ |
| IBS | ✓ | ✓ | ✓ | ✓ |

Every combination is supported. The bump tables for dom/wdeg and
VSIDS keep updating regardless of which picker is active for the
choice, so the choice of primary picker is independent of *which
conflicts the engine observed*.

### What does NOT compose

- **Local search** (`solveWithMinConflicts`) ignores every
  heuristic flag. The min-conflicts runner has no backtracking
  surface for the heuristics to steer.
- **B&B optimization** (`minimize` / `maximize`) on `Problem`
  currently uses MRV unconditionally. The flags exist on the
  search variants but the optimization entry points don't expose
  them. (See `_searchOptimal` in `solver.dart` if you want to
  thread them through.)

## Benchmark snapshot

`benchmark/benchmark.dart` has a `bench(heuristic)` section that
runs all five (MRV, dom/wdeg, VSIDS, IBS, LC+dom/wdeg) on the
same set of problems with the standard 5-rep warm-up + 25-rep
median methodology. The honest summary:

| Problem | MRV | dom/wdeg | VSIDS | IBS | LC+dom/wdeg |
|---|---:|---:|---:|---:|---:|
| magic-square 3×3 (no clue) | ~1.3 ms | ~2.1 ms | ~1.5 ms | ~1.5 ms | ~1.9 ms |
| 12-queens | ~3.9 ms | ~4.0 ms | ~3.9 ms | ~3.9 ms | ~3.9 ms |
| 16-queens | ~22 ms | ~20 ms | ~19 ms | ~19 ms | ~22 ms |
| SEND+MORE=MONEY (linear) | ~0.4 ms | ~0.3 ms | ~0.3 ms | ~0.3 ms | ~0.3 ms |
| pigeonhole 7-in-6 (UNSAT) | ~88 ms | ~48 ms | ~48 ms | ~53 ms | ~44 ms |

(Local results; numbers vary across hardware. The relative
ordering is the load-bearing part.)

Read the table this way:

- **On small / easy problems** (magic-square, queens up to 16,
  SEND+MORE linear): all five are roughly equivalent. The
  per-pick overhead of dom/wdeg and LC+dom/wdeg can even be a
  slight tax on the smallest problems. **Don't reach for a
  heuristic on these.**
- **On UNSAT pigeonhole**: every conflict-driven heuristic beats
  MRV by ~2×. LC+dom/wdeg wins, just barely, with the fewest
  decisions (~966 vs MRV's ~3245). This is where the heuristics
  earn their keep.

The general lesson: **the harder and more UNSAT-ish the problem,
the more the heuristic matters.** If your problem solves in <1
second under MRV, there's almost certainly no point switching.
If it doesn't terminate under MRV at all, try `dom/wdeg + LC`
first.

## Cost when off

Every heuristic guards its work behind its `useX` flag. The
fixed overhead when all heuristics are off:

- **MRV**: zero — it's the fallback.
- **dom/wdeg**: zero — `_bumpWeight` is only called by
  `_onConflict`, which is itself only called by failure paths
  the heuristics may listen to. When all flags are off,
  `_onConflict` does nothing.
- **VSIDS**: same as dom/wdeg.
- **IBS**: each search loop checks `useImpact` before calling
  `_logProductDomains()` (one O(|vars|) loop per decision) and
  `_observeImpact`. When off, these are skipped. The cost is one
  bool branch and one zero-init for `logBefore` per candidate.
- **LC**: one bool branch in `_pickVariable` per pick. The
  `_lastConflictVar` field itself is a `String?` initialized to
  null — no per-pick allocation.

In other words: **turning a heuristic on is the only way to pay
its cost.** You can leave all four off and the engine runs as
fast as it would with no heuristics implemented at all.

## API stability

All four primary pickers and LC are part of the stable surface.
See [`STABILITY.md`](../STABILITY.md):

- `getSolutionWithDomWdeg`, `getSolutionWithActivity`,
  `getSolutionWithImpact`, `getSolutionWithLastConflict`,
  `getSolutionWithRestarts` (with `useDomWdeg:` / `useVsids:` /
  `useImpact:` / `useLastConflict:` flags).
- Static `CSP.solveWith*` mirrors.

## Further reading

- Boussemart, Hemery, Lecoutre, Sais. "Boosting systematic search
  by weighting constraints." ECAI 2004.
- Moskewicz, Madigan, Zhao, Zhang, Malik. "Chaff: engineering an
  efficient SAT solver." DAC 2001.
- Refalo. "Impact-Based Search Strategies for Constraint
  Programming." CP 2004.
- Lecoutre, Saïs, Tabary, Vidal. "Reasoning from last conflict(s)
  in constraint programming." Artificial Intelligence 173, 2009.

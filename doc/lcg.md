# Lazy Clause Generation (LCG)

`Problem.solveWithLcg` is dart_csp's entry point for **Lazy Clause
Generation** — the conflict-driven nogood-learning technique that
gives modern solvers like CP-SAT (OR-Tools) and Chuffed
orders-of-magnitude speedups over non-learning solvers on hard
structured problems. LCG is dart_csp's biggest open strategic gap;
the implementation is split into six milestones (M1–M6) tracked in
[`LCG_PLAN.md`](../LCG_PLAN.md) at the repo root.

This guide documents the **M1** surface — atom encoding plus an
implication trail wired into the engine — and explains what to
expect from `solveWithLcg` today versus once M2 / M3 land.

---

## What LCG does (and why it matters)

A traditional CP backtracker, on conflict, rolls back to the most
recent decision and tries a different value. The information about
*why* the conflict happened is discarded — the same dead-end may
be revisited deeper in the tree under a different prefix.

LCG turns each conflict into a **learned clause**: a logical
disjunction over atoms `(variable, op, value)` that says "this
combination of choices cannot all hold." Learned clauses are added
to a pool consulted by the engine on every subsequent decision, so
the dead-end is never revisited. On problems whose search tree
would otherwise be exponential in problem size, learning typically
replaces the exponential with a polynomial — minutes vs hours, or
solvable vs intractable.

The textbook reference is Marques-Silva & Sakallah 1996 (the first-
UIP loop, GRASP) and Eén & Sörensson 2003 (MiniSat). For CP
specifically, Ohrimenko, Stuckey & Codish 2009 ("Propagation via
lazy clause generation") and Feydy & Stuckey 2009 ("Lazy clause
generation reengineered") are the foundational papers — both
introduce the lazy-atom encoding dart_csp's plan adopts.

---

## What M1 ships

**M1 is wiring + types only.** The user-facing surface looks like
this:

```dart
final p = Problem()
  ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
  ..addAllDifferent(['A', 'B', 'C', 'D']);
final solution = await p.solveWithLcg();
```

In M1, `solveWithLcg` is functionally indistinguishable from
`getSolution` — same return contract (`Map<String, dynamic>` on
success or the literal `'FAILURE'`), same propagation, same answer.
The visible difference is that the engine maintains an *implication
trail* of `Atom` / `ImplicationReason` pairs during the search,
captured in `CSP.lastImplicationTrail` after the call returns.

That trail is the substrate the M2 first-UIP loop will read. M1
exists so M2 can land without engine surgery — the bookkeeping is
already in place.

### Atom encoding

Four shapes cover every prune the existing engine produces:

| Atom        | Meaning                       |
|-------------|-------------------------------|
| `AtomEq`    | `x = v` — pinned to exactly v |
| `AtomNe`    | `x ≠ v` — value v removed     |
| `AtomLe`    | `x ≤ v` — upper-bound prune   |
| `AtomGe`    | `x ≥ v` — lower-bound prune   |

Atoms negate logically (`AtomEq(x, v).negate()` → `AtomNe(x, v)`,
`AtomLe(x, v).negate()` → `AtomGe(x, v+1)`) and can be checked
against a `DomainView` via `isEntailedBy` — the narrow public
interface dart_csp's engine reps implement.

Domains over non-integer values (string-valued map-colouring, etc.)
are silently skipped on the implication trail; atoms are integer-
only by design. This is the scope decision in `LCG_PLAN.md` §1.

### Implication trail

Each domain mutation appends `ImplicationEntry` records to the
trail, one per pruned value (or a single `AtomEq` when the new
domain is a singleton):

```dart
class ImplicationEntry {
  final Atom prunedAtom;          // what was forced
  final ImplicationReason reason; // why
  final int trailIndex;           // matching position on engine's domain trail
  final int decisionLevel;        // # of decisions before this prune
}
```

For M1 the `reason` is always one of:
- `DecisionReason()` — the entry was a free decision pin
  (search-loop `_setDomain(v, [chosenValue], cause: null)`).
- `UnknownReason()` — a propagation prune. Concrete per-propagator
  subclasses arrive in M3 (`AllDifferentReason`, `LinearBoundReason`,
  `GccFlowReason`, …); until then the trail is opaque past
  decisions, which is why M2's conflict analysis can't yet learn
  anything beyond the decision atoms themselves.

The trail rolls back in lockstep with the engine's domain trail.
After a successful solve the trail covers every prune that survived
to the solution; after a search-detected unsat solve it is empty;
after a preprocessing-detected unsat (AC-3 wipeout before search
begins) it carries the failing antecedent chain so M2 can run
conflict analysis on it.

---

## API surface

All types live under `package:dart_csp/dart_csp.dart` (re-exported
from `lib/src/lcg/`):

- **`Problem.solveWithLcg({consistency, cancelToken})`** — runner
  entry point. Same shape as `getSolution`.
- **`CSP.solveWithLcg(...)`** — the static used by the extension
  above; available for callers building their own `CspProblem`.
- **`CSP.lastImplicationTrail`** — read-only snapshot of the most
  recent run's implication trail. Null after a non-LCG solve.
  Intended for tests and tooling.
- **`Atom`** sealed hierarchy: `AtomEq`, `AtomNe`, `AtomLe`,
  `AtomGe` (`varName`, `value`, `negate()`, `isEntailedBy`).
- **`DomainView`** — `contains(int)`, `minValue`, `maxValue`,
  `isSingleton`, `isEmpty`.
- **`ImplicationReason`** abstract base + `DecisionReason` /
  `UnknownReason` M1 placeholders.
- **`ImplicationEntry`** record type.

All of the above are **experimental** (`STABILITY.md`) — surface
will evolve as M2 / M3 land.

---

## What's next

- **M2** lands the first-UIP conflict-analysis loop on the existing
  `_ClausePropagator`, learned-clause storage, and forget /
  activity policies. Pigeonhole-CNF 8-in-7 / 9-in-8 are the
  classic showcase: search-tree size drops 10–100× once the loop
  closes.
- **M3** adds per-propagator `explain` companions (allDifferent,
  linear, GCC, regular, cumulative, diff_n, circuit). Each is a
  self-contained landing — large structured CSPs see a step
  improvement after `_AllDifferentPropagator.explain` alone.
- **M4** wires LCG into restart + dom/wdeg + VSIDS state so
  learned clauses bump the picker correctly.
- **M5** ships `bench(lcg)`, this doc gets a worked-example
  section, and optional Sörensson–Eén clause minimisation lands.
- **M6** (optional, Tier-2) — parallel learned-clause sharing.

See [`LCG_PLAN.md`](../LCG_PLAN.md) for the full architecture,
open design questions, and references.

---

## References

- Marques-Silva, J. P. & Sakallah, K. A. (1996). "GRASP: A search
  algorithm for propositional satisfiability." DAC 1996.
- Eén, N. & Sörensson, N. (2003). "An extensible SAT-solver." SAT
  2003.
- Ohrimenko, O., Stuckey, P. J. & Codish, M. (2009). "Propagation
  via lazy clause generation." *Constraints* 14.
- Feydy, T. & Stuckey, P. J. (2009). "Lazy clause generation
  reengineered." CP 2009.
- [Chuffed solver source](https://github.com/chuffed/chuffed) —
  battle-tested reference implementation; per-propagator `explain`
  methods are good models for the dart_csp M3 work.

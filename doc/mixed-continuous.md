# Mixed integer / continuous models

`dart_csp` enumerates domains, which is what makes its propagator
inventory work — and what makes continuous quantities (prices, rates,
fractional durations, geometric placement) impossible to express
directly. `Problem.addFloatVariable` closes that gap: a real-valued
variable that lives in the *same* `Problem` as the enumerated ones,
solved by the *same* engine, so the rest of your model keeps its
globals, heuristics, and branch-and-bound.

```dart
final p = Problem();
p.addRangeVariable('units', 0, 20);        // enumerated
p.addFloatVariable('price', 0.0, 100.0);   // continuous
p.addLinearLeq(['units', 'price'], [2, 1.5], 40);  // spans both

final sol = await p.getSolution() as Map<String, dynamic>;
// {units: 12, price: 10.000000317891438}
```

See [`example/mixed_continuous.dart`](../example/mixed_continuous.dart)
for a runnable version of this and two more models.

> Not to be confused with `ContinuousModel` (see the README's
> *Continuous variables* section and
> [`example/continuous.dart`](../example/continuous.dart)), the
> standalone interval solver. That one is self-contained and supports
> products (`x * y`, `x²`); this one is the main engine and supports the
> integer propagators. Pick by which half of your model matters more —
> see [Which one do I want?](#which-one-do-i-want) below.

## What you can write

**Declaring.** `addFloatVariable(name, lo, hi)` — both bounds must be
finite, and the name must not already be taken by either channel.

**Constraining.** Only the linear constraints accept a continuous
variable in their scope:

- `addLinearEquals(vars, coeffs, bound)`
- `addLinearLeq(vars, coeffs, bound)`
- `addLinearGeq(vars, coeffs, bound)`

Coefficients and bounds may be any `num`, so `[2, 1.5]` and `40` are
both fine. A scope mixing kinds is the interesting case and is fully
supported: `2·units + 1.5·price ≤ 40` prunes `price` from `units` **and**
`units` from `price`.

Every other constraint — the globals, string constraints, arbitrary
predicates — enumerates values, so it rejects a continuous variable at
posting time with a message saying so. Those constraints keep working
normally on the enumerated part of the model.

A variable may not appear twice in one linear constraint that mentions a
continuous variable. Interval arithmetic treats each occurrence as an
independent quantity — the classic *dependency problem*, under which
`x - x ≤ -1` would look satisfiable — so the terms must be combined into
a single coefficient. This is checked at posting time.

**Precision.** `setFloatEpsilon(eps)` (default `1e-6`) sets the target
box width. The search bisects each continuous variable until its
interval is at most that wide and reports the **midpoint**.

**Optimizing.** `minimize` / `maximize` accept a continuous objective.
The reported optimum is optimal to within `floatEpsilon` — the same
tolerance the reported value itself carries.

## How it works

A continuous variable gets a fourth domain representation inside the
engine, an interval `[lo, hi]` over doubles, alongside the existing
list / bitset / integer-interval reps. Three things follow from that:

**Branching is bisection, not value selection.** Where the search pins
an enumerated variable to a value, it splits a continuous variable's
interval into two halves and tries each. A continuous variable counts as
*assigned* once its interval is at most `floatEpsilon` wide. Enumerated
variables are always branched first: that lets the integer propagators
prune against a fully determined combinatorial structure before the
search starts splitting reals.

**Propagation is HC4 bound reasoning.** A linear constraint mentioning a
continuous variable is dispatched to an interval propagator instead of
the integer bounds-consistency one. It isolates each term, derives the
interval that term's variable must lie in from the others' current
bounds, and intersects. Continuous variables are narrowed directly;
integer variables are filtered to the values inside the derived
interval — which is where integrality comes from for free. `3k == 1.0`
has no solution because the derived bound for `k` is `[1/3, 1/3]` and no
integer survives it.

**Learning and the enumerative preprocessors sit this one out.** LCG
atoms are integer-only by design, so a continuous prune records nothing
on the implication trail; conflict analysis simply never sees these
variables. Singleton-arc-consistency preprocessing skips them too (it
pins one value at a time). Both still apply in full to the enumerated
part of the model. Mixed problems take the recursive search path rather
than the iterative CDCL one, whose value-exclusion backtrack has no
meaning on an interval.

Everything above is gated on the problem declaring at least one
continuous variable. A pure-integer solve runs exactly the code it ran
before this feature existed.

## What a solution means

A returned box is a **high-precision witness, not a proof**, in two
distinct senses — both worth understanding before you rely on a number.

**The reported value is a midpoint, so equalities hold only to within
the box.** Propagation guarantees the *box* is consistent: every
constraint is satisfiable somewhere inside it. The midpoint is a point
in that box, not necessarily the exact solution. For a constraint
`Σ cᵢ·xᵢ == b`, the residual at the midpoint can be as large as
`Σ|cᵢ|·ε/2`. So compare against a tolerance scaled to your coefficients,
not against `0` — and tighten `setFloatEpsilon` if you need more digits.
(Where propagation pins a variable exactly, as in the `x + y == 10`
example above, you do get the exact value; that is a property of the
model, not a guarantee.)

**Arithmetic is plain IEEE-754, not outward-directed rounding.** Nothing
here guarantees that a box the search *discarded* contained no solution:
a rounding error in the wrong direction could in principle prune a
sliver holding the only answer. If you need certified enclosures, that
is the outward-rounding item in [`PLAN.md`](../PLAN.md).

Two more honest edges:

- **Bisection halves share their split point** (`[lo, m]` and `[m, hi]`).
  Closed halves cannot drop a solution sitting exactly at `m`, which an
  open split could. The cost is that `getSolutions()` may report a
  boundary solution twice.
- **`getSolutions()` over continuous variables enumerates boxes**, of
  which there are `O(range / epsilon)` per variable. It is correct but
  rarely what you want; prefer `getSolution()` or `minimize` /
  `maximize`.

## Which one do I want?

| | `ContinuousModel` | `Problem` + `addFloatVariable` |
|---|---|---|
| Products (`x * y`, `x²`) | yes | no — linear only |
| allDifferent, GCC, cumulative, … | no | yes, on the enumerated part |
| dom/wdeg, VSIDS, restarts, LCG | no | yes, on the enumerated part |
| Optimization | no | yes (`minimize` / `maximize`) |
| Integer variables | yes (`addIntVar`) | yes, the whole enumerated engine |

Rule of thumb: if the hard part of your model is the *arithmetic*, use
`ContinuousModel`. If the hard part is the *combinatorics* and the reals
are along for the ride, use `Problem`.

Lifting product constraints into the main engine is the remaining piece;
it needs the auxiliary-variable decomposition `ContinuousModel` already
uses, expressed as a second interval propagator.

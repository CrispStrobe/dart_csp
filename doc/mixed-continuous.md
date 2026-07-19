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
> standalone interval solver. Both support linear constraints and
> products; the difference is that `ContinuousModel` gives you an
> operator-overloading DSL over pure arithmetic, while this one gives you
> the integer engine alongside. See
> [Which one do I want?](#which-one-do-i-want) below.

## What you can write

**Declaring.** `addFloatVariable(name, lo, hi)` — both bounds must be
finite, and the name must not already be taken by either channel.

**Constraining.** Two constraint families accept a continuous variable
in their scope. First, the linear ones:

- `addLinearEquals(vars, coeffs, bound)`
- `addLinearLeq(vars, coeffs, bound)`
- `addLinearGeq(vars, coeffs, bound)`

Coefficients and bounds may be any `num`, so `[2, 1.5]` and `40` are
both fine. A scope mixing kinds is the interesting case and is fully
supported: `2·units + 1.5·price ≤ 40` prunes `price` from `units` **and**
`units` from `price`.

Second, the product relation:

- `addFloatProduct(product, a, b)` — posts `product == a * b`

`product` must be a continuous variable; `a` and `b` may each be
continuous or enumerated-numeric, so `n * price` and `x * x` both work.
This is the primitive for **non-linear** models: polynomials are built by
decomposition, introducing a variable per product and combining them
linearly.

```dart
// x² + y² == 25 and x + y == 7  =>  (3, 4) or (4, 3)
for (final v in ['x', 'y']) p.addFloatVariable(v, 0, 10);
p.addFloatVariable('x2', 0, 100);
p.addFloatVariable('y2', 0, 100);
p.addFloatProduct('x2', 'x', 'x');
p.addFloatProduct('y2', 'y', 'y');
p.addLinearEquals(['x2', 'y2'], [1, 1], 25);
p.addLinearEquals(['x', 'y'], [1, 1], 7);
```

Give a product variable a wide enough interval — its declared bounds are
a constraint like any other, so a `product` over `[0, 50]` quietly rules
out part of the space when its factors reach 10 each.

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

Among the continuous variables, the widest interval is split first —
with two exceptions that both matter a great deal in practice:

- A variable that is the **output of a product** is branched *last*. It
  is a function of its factors, so once they are narrow propagation
  determines it; and its interval is typically far the widest (the
  product of two `[0, 100]` ranges spans `[0, 10000]`), so a plain
  widest-first rule would split it every time and burn depth computing
  what propagation was about to hand over.
- Unless it is the **objective**, which is always branched eagerly and
  in the improving direction. Branch-and-bound converges by splitting
  the objective toward its bound; demoting it leaves the bound with no
  guidance. On the rectangle-area model in the tests that distinction is
  227,607 decisions versus 21.

**Propagation is HC4 bound reasoning.** A linear constraint mentioning a
continuous variable is dispatched to an interval propagator instead of
the integer bounds-consistency one. It isolates each term, derives the
interval that term's variable must lie in from the others' current
bounds, and intersects. Continuous variables are narrowed directly;
integer variables are filtered to the values inside the derived
interval — which is where integrality comes from for free. `3k == 1.0`
has no solution because the derived bound for `k` is `[1/3, 1/3]` and no
integer survives it.

A product `p == a·b` revises the same way in both directions: forward
`p ← p ∩ (a·b)`, backward `a ← a ∩ (p/b)` and `b ← b ∩ (p/a)`. Interval
division is the subtle part — when the divisor straddles zero the exact
quotient is a pair of semi-infinite rays, and the sound single-interval
answer is their hull `(-∞, ∞)`, i.e. **no tightening at all until the
divisor moves off zero**. That is the main reason a product model can
search harder than its size suggests: a factor whose domain spans zero
gives the backward step nothing to work with until bisection separates
the signs.

Product propagation is **sound but not complete**: it never discards a
solution, but a surviving box need not contain one. `x * x` is the
standard example — the two occurrences are treated as independent
quantities (the interval *dependency problem*), so `x ∈ [-2, 2]` gives
`x² ∈ [-4, 4]` rather than `[0, 4]`. The cost is pruning strength on wide
boxes only; at a leaf the factors are narrow and the product interval is
tight again.

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

**Arithmetic is plain IEEE-754 by default.** Nothing in the default
mode guarantees that a box the search *discarded* contained no solution:
a rounding error in the wrong direction could in principle prune a
sliver holding the only answer. Set the rounding mode to fix that:

```dart
p.floatRounding = IntervalRounding.outward;
```

Every computed bound is then nudged one ULP in the safe direction (one
ULP suffices — a single IEEE operation errs by at most half of one), so
**no prune can discard a solution**. The payoff is in the negative
answer: an exhaustive search that reports `'FAILURE'` under `outward`
has *proven* there is no solution, rather than merely having failed to
find one. Dart has no `fesetround`, so this is emulated by stepping the
bit pattern; the primitives are `IntervalRounding.nextUp` / `nextDown`
and they are exposed and tested in their own right.

It does **not** certify a positive answer. Interval propagation is sound
but not complete under either mode — a box can survive every constraint
without containing a solution — so a returned box remains a witness.
Certifying that a solution exists inside a box needs an additional
existence test (an interval Newton / Krawczyk step), which this library
does not do.

The cost is a little width and a little speed; measured decision counts
are unchanged on the models in the test suite. `ContinuousModel.solve`
takes the same mode as a `rounding:` argument.

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
| Linear constraints | yes | yes |
| Products (`x * y`, `x²`) | yes, via an expression DSL | yes, via `addFloatProduct` |
| allDifferent, GCC, cumulative, … | no | yes, on the enumerated part |
| dom/wdeg, VSIDS, restarts, LCG | no | yes, on the enumerated part |
| Optimization | no | yes (`minimize` / `maximize`) |
| Integer variables | yes (`addIntVar`) | yes, the whole enumerated engine |

The capability gap is now mostly about *ergonomics*: `ContinuousModel`
has an operator-overloading DSL where `(x * y).eq(6)` introduces the
auxiliary variable for you, while `Problem` asks you to name it and post
the product yourself. In exchange you get the rest of the engine.

Rule of thumb: if your model is pure arithmetic and you want it to read
like arithmetic, use `ContinuousModel`. If there is real combinatorial
structure — globals, optimization, a discrete skeleton — use `Problem`.

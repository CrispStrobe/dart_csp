# Global cardinality constraints: `among`, `nvalue`, `gcc`

The `GlobalConstraints` extension on `Problem` ships three classical
counting constraints in addition to [`element`](../README.md#global-constraints)
and `table`. They all answer questions of the form *"how many of these
variables ... ?"* but at slightly different scopes:

| Constraint | Question |
|---|---|
| `among(vars, values)` | how many `vars` are assigned a value in `values`? |
| `nvalue(vars)` | how many *distinct* values are used across `vars`? |
| `gcc(vars, ...)` | for each interesting value, how many `vars` take it? |

Each comes in a **count-variable form** (the count is itself a CSP
variable, so you can optimize over it) and a **fixed-`k` form** for
the common case where the count is a constant.

## TL;DR — pick the right one

| You want to say... | Use |
|---|---|
| "exactly 3 of these slots are morning shifts" | `addAmongExactly(slots, {'morning'}, 3)` |
| "the count of morning shifts is the variable `nMornings`" | `addAmong(slots, {'morning'}, 'nMornings')` |
| "minimize the number of distinct colors used" | `addNvalue(vars, 'nColors')` + `p.minimize('nColors')` |
| "use exactly 2 distinct colors" | `addNvalueExactly(vars, 2)` |
| "each digit 1..9 must appear exactly once" | `addGcc(vars, {1: 1, 2: 1, ..., 9: 1})` (or just `addAllDifferent`) |
| "morning appears 3 times, night appears 1 time" | `addGcc(slots, {'morning': 3, 'night': 1})` |
| "morning appears 0–3 times, night at least 1" | `addGccRanges(slots, {'morning': (min: 0, max: 3), 'night': (min: 1, max: vars.length)})` |

## The constraints

### `among`

Count of vars whose assignment falls in a fixed value set.

```dart
// Count-variable form: the count is a registered CSP variable.
p.addVariable('nMornings', [0, 1, 2, 3, 4, 5]);
p.addAmong(['mon', 'tue', 'wed', 'thu', 'fri'], {'morning'}, 'nMornings');

// Fixed-k form: count must equal a constant.
p.addAmongExactly(['mon', 'tue', 'wed', 'thu', 'fri'], {'morning'}, 2);
```

Special cases:
- `k = 0` forces every var **outside** `values`.
- `k = vars.length` forces every var **inside** `values`.
- An empty `values` set means the count is trivially 0.

### `nvalue`

Count of distinct values across `vars`.

```dart
p.addVariable('nColors', [1, 2, 3]);
p.addNvalue(['region1', 'region2', 'region3'], 'nColors');
final fewest = await p.minimize('nColors');   // chromatic-number-style
```

Special cases:
- `nvalue = 1` forces all vars equal (collapses to `allEqual`).
- `nvalue = vars.length` forces all vars distinct (equivalent to
  `allDifferent`, but without Régin's specialized propagator — prefer
  `addAllDifferent` if that's all you need).

### `gcc` — global cardinality

For each value of interest, the number of `vars` assigned to it must
match an exact count or fall in a range.

```dart
// Exact: morning appears 3 times, afternoon 2, night 1.
p.addGcc(slots, {'morning': 3, 'afternoon': 2, 'night': 1});

// Ranges: morning 0–3 times, night at least 1.
p.addGccRanges(slots, {
  'morning': (min: 0, max: 3),
  'night':   (min: 1, max: slots.length),
});
```

Values not appearing as keys in the map are **unconstrained** —
they can occur any number of times.

`gcc` generalizes `allDifferent`: requiring every value-of-interest
to have count exactly 1 is the all-different relation. In practice
prefer `addAllDifferent` for that case because it dispatches to
Régin's hyper-arc-consistent propagator; the generic `gcc` predicate
here doesn't.

## Composition

The three constraints compose freely with each other and with the
rest of the library. A small rostering example:

```dart
const days = ['mon', 'tue', 'wed', 'thu', 'fri'];
final p = Problem()
  ..addVariables(days, ['M', 'A', 'N'])
  ..addVariable('nShifts', [2, 3])
  // No shift may run more than 3 days in a row this week.
  ..addGccRanges(days, {
    'M': (min: 0, max: 3),
    'A': (min: 0, max: 3),
    'N': (min: 0, max: 3),
  })
  // Exactly two mornings.
  ..addAmongExactly(days, {'M'}, 2)
  // Track how many distinct shifts the week uses.
  ..addNvalue(days, 'nShifts');

final result = await p.minimize('nShifts');
```

## Propagation caveat

All four counting predicates above are **generic n-ary GAC**
encodings: the engine prunes a value from a domain only if no support
tuple exists for it among the remaining domains. The engine's GAC
revision bails out when the Cartesian product of free neighbors would
exceed an internal work bound (`_gacWorkBound`, currently 4096); for
very large `vars` lists this means propagation may not fire and the
constraint is checked only at leaf assignments.

The constraints are still *correct* — no spurious solution can sneak
past the leaf check — but they may not prune as aggressively as a
dedicated propagator would. A specialized GCC propagator (network-flow
based, à la Régin 1996) is a follow-up tracked in `PLAN.md`.

In practice:
- For up to ~10–12 variables with small domains, propagation fires
  normally and pruning is effective.
- For larger problems, prefer to model around the constraint (add
  `allDifferent` where applicable, decompose the rostering into
  per-day windows) rather than rely on this generic encoding for
  early filtering.

## API summary

| Helper | Arity | Notes |
|---|---|---|
| `addAmong(vars, values, countVar)` | n + 1 | `countVar` auto-checked existence; domain must cover possible counts |
| `addAmongExactly(vars, values, k)` | n | `k` must be in `[0, vars.length]` |
| `addNvalue(vars, countVar)` | n + 1 | `countVar` domain typically `[1, vars.length]` |
| `addNvalueExactly(vars, k)` | n | `k` must be in `[1, vars.length]` |
| `addGcc(vars, counts)` | n | each count ≥ 0; sum of counts ≤ vars.length |
| `addGccRanges(vars, ranges)` | n | each `(min, max)` valid; sum of mins ≤ vars.length |

All helpers throw `ArgumentError` at construction time when an
argument is malformed (unknown variable, out-of-range `k`, negative
count, infeasible cardinality sum, etc.).

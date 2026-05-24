# Set variables

A *set variable* is a variable whose value is a finite subset of a
fixed universe `U`. The `SetVariables` extension on `Problem` adds
declaration plus a small library of operations (cardinality, subset,
disjoint, union, intersection, difference) that reads as ordinary set
algebra and decomposes internally to operations on the existing
arithmetic / logical infrastructure.

## TL;DR — pick the right helper

| You want to say... | Use |
|---|---|
| "S is some subset of {a, b, c, d, e}" | `addSetVariable('S', universe: ['a', ..., 'e'])` |
| "S has exactly 3 elements" | `addSetCardinality('S', 3)` |
| "S has between 2 and 4 elements" | `addSetCardinalityRange('S', 2, 4)` |
| "k = |S|, minimize k" | `addSetCardinalityVar('S', 'k') + minimize('k')` |
| "S must contain element x" | `addRequiredInSet('S', x)` |
| "S must not contain element x" | `addExcludedFromSet('S', x)` |
| "A ⊆ B" | `addSubset('A', 'B')` |
| "A = B" | `addSetEquals('A', 'B')` |
| "A ∩ B = ∅" | `addSetDisjoint('A', 'B')` |
| "C = A ∪ B" | `addSetUnion('A', 'B', 'C')` |
| "C = A ∩ B" | `addSetIntersection('A', 'B', 'C')` |
| "C = A \ B" | `addSetDifference('A', 'B', 'C')` |
| "if X = v then v ∈ S" (custom composition) | `memberIndicator('S', v)` |

## The indicator decomposition model

Every set variable is internally a vector of 0/1 *indicator variables*
— one per universe element. The pattern of 1s and 0s names the
chosen subset:

```
universe = [1, 2, 3, 4, 5]
S = {2, 4}   ⇔   [0, 1, 0, 1, 0]
S = ∅        ⇔   [0, 0, 0, 0, 0]
S = U        ⇔   [1, 1, 1, 1, 1]
```

The indicator variables are registered under reserved internal names
of the form `__set__<setName>__<i>` (i = element's position in the
universe). Solutions returned from every solve entry point on the
declaring `Problem` post-process the raw result so each set variable
appears as a `Set<dynamic>` of included elements and the indicator
variables are stripped from the map.

This decomposition pays off because:

- **Cardinality is bounds-consistent linear.** `|S| = k` becomes
  `addLinearEquals(indicators, [1, 1, ..., 1], k)`, dispatched to the
  bounds-consistency linear propagator.
- **Subset / equality / disjoint are pairwise binary.** Each
  element contributes a single `BinaryConstraint` between the two
  indicator variables, registered for both directions so AC-3 prunes
  symmetrically.
- **Union / intersection / difference are ternary.** Each universe
  element contributes one 3-variable n-ary constraint over the two
  inputs and the output indicator, all of which have domain `{0, 1}`
  — the search tree is shallow per element.

Because the model is pure decomposition, every set-variable solve
composes naturally with `minimize`/`maximize`, restarts, dom/wdeg,
`solveWithMinConflicts`, and the soft-constraint /
`maximizeSatisfaction` machinery.

## When to use the sugar vs. model indicators directly

The sugar pays off when:

- The mental model is "this is a set". Reading
  `addSetDisjoint('Team', 'Bench')` is much clearer than reading
  five pairwise binary constraints over indicator names.
- Solutions need to be set-valued. `result['Team'] is Set<dynamic>`
  is what most downstream code wants; the post-processing is free.
- You're going to do *several* set operations. Each one of the
  pairwise / ternary helpers is identical to what you'd hand-write
  but consistent in error reporting and validation.

The sugar does *not* pay off (and you should model indicators
directly) when:

- The element type doesn't fit `Map<dynamic, ...>` lookup ergonomics
  (e.g. complex objects whose `==`/`hashCode` are unreliable).
- You want a single set variable but everything else is integer-
  typed and you'd rather see a plain `int` per-element field in the
  solution.
- You need a relation between sets that none of the built-in
  helpers express. `memberIndicator(setName, element)` is the
  escape hatch: it returns the name of the underlying indicator
  variable, which you can then thread into `addReified*`,
  `addLinear*`, or arbitrary `addConstraint` predicates.

## Universe matching rules

- **Pairwise binary helpers** (`addSubset`, `addSetDisjoint`) iterate
  the universe of the **left** argument. Elements not in the right
  argument's universe are handled per operation:
  - `addSubset(A, B)`: an element in `A`'s universe but not in `B`'s
    is forced out of `A` (it cannot be in any subset of `B`).
  - `addSetDisjoint(A, B)`: an element in only one universe is
    trivially non-conflicting and contributes no constraint.

- **`addSetEquals(a, b)`** requires the two universes to be **equal
  as sets** (same elements, any order). It is an `ArgumentError`
  otherwise.

- **Ternary helpers** (`addSetUnion`, `addSetIntersection`,
  `addSetDifference`) require **all three** set variables to share
  the same universe (as a set). If you genuinely need different
  universes for the inputs and the output, decompose manually using
  `memberIndicator` plus pairwise constraints.

For the common case of "several sets over a shared alphabet", use
`addSetVariables(['A', 'B', 'C'], universe: ...)` to declare them
together with the same `universe` reference.

## Worked example: team selection

```dart
const roster = ['alice', 'bob', 'carol', 'dave', 'erin'];

final p = Problem()
  // Two set variables sharing the roster as universe.
  ..addSetVariables(['Team', 'Bench'], universe: roster)
  // Exact sizes — `Team ∪ Bench == roster` then follows since
  // 3 + 2 = 5 and they're disjoint.
  ..addSetCardinality('Team', 3)
  ..addSetCardinality('Bench', 2)
  ..addSetDisjoint('Team', 'Bench')
  // Captain must be on the team.
  ..addRequiredInSet('Team', 'alice');

await for (final sol in p.getSolutions()) {
  print('Team: ${sol['Team']}, Bench: ${sol['Bench']}');
}
// Six solutions: 'alice' is in Team; pick 2 of the other 4 to join
// her; the remaining 2 fill the bench.
```

## Composing with `minimize` / `maximize`

To optimize over set size, declare a count variable and link it to
the set's cardinality:

```dart
final p = Problem()
  ..addSetVariable('S', universe: [1, 2, 3, 4, 5])
  ..addVariable('k', [0, 1, 2, 3, 4, 5])
  ..addSetCardinalityVar('S', 'k')
  ..addRequiredInSet('S', 2);

final sol = await p.minimize('k');
// sol['k'] == 1; sol['S'] == {2}
```

## What's not (yet) implemented

- **A specialized set-domain rep** (a single `(required, possible)`
  pair of bitsets stored as one `_DomainRep` variant) is on the
  PLAN as a follow-up if benchmarks ever surface a problem class
  where the per-element decomposition is the bottleneck. The current
  decomposition piggy-backs on the bitset rep used for every
  indicator's `[0, 1]` domain, so memory cost is already small.
- **`union`/`intersection`/`difference` with mixed universes** —
  for now require all three vars to share a universe. Manual
  decomposition via `memberIndicator` covers the general case.

## See also

- [`STABILITY.md`](../STABILITY.md) classifies the set-variable
  surface as experimental.
- The reified / logical / linear / soft-constraint docs are the
  composition partners when you need behaviors the dedicated set
  helpers don't express.

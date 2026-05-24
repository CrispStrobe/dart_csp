# String constraint grammar

`Problem.addStringConstraint(str)` parses a string into a constraint. The
parser tries a series of patterns in order and dispatches to a specialized
built-in factory when it can. Anything it doesn't recognize falls through
to a generic expression evaluator.

This document is the reference for what the parser accepts and how it
behaves. See [algorithms.md](algorithms.md) for what the solver does with
the result.

## Tokens

- **Variables** are alphanumeric identifiers (`A`, `Q1`, `team_a`) that
  match an earlier `addVariable(name, ...)`. Variable matching is
  whole-word and longest-match-first, so `A` and `A1` don't collide.
- **Numbers** are integer or decimal literals (`5`, `-3`, `2.5`).
- **Reserved words** (case-insensitive): `in`, `not`, `and`, `or`.

## Operators

| Kind | Operators |
|------|-----------|
| Comparison | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Arithmetic | `+`, `-`, `*`, `/` |
| Range bracket | `<=`, `<` (only as the upper-bound operator) |

Precedence is the usual one: `*` and `/` bind tighter than `+` and `-`.
There are no parentheses — if you need them, you've outgrown the string
parser; use a custom predicate via `addConstraint`.

Division by zero is silently skipped (`a / 0` evaluates as `a` rather
than throwing). This is a deliberate guard inside the evaluator; don't
rely on it for correctness.

## Recognized patterns and what they dispatch to

The parser tries these in this order; the first match wins.

| Pattern | Example | Dispatches to |
|---------|---------|---------------|
| Range bracket | `'5 <= A + B <= 10'`, `'0 <= X + Y + Z < 7'` | `sumInRange(min, max)` (strict upper uses `max - 0.001`) |
| Chained inequality | `'A != B != C'` | `allDifferent()` |
| Binary comparison | `'A < B'`, `'A == B'` | specialized `BinaryPredicate` (`<`, `<=`, `>`, `>=`, `==`, `!=`) |
| Chained ordering | `'A < B < C'`, `'A <= B <= C'` | `strictlyAscendingInOrder()` / `ascendingInOrder()` |
| Variable vs. constant | `'A > 5'`, `'B != 3'` (one variable) | specialized lambda |
| Variable equation | `'A + B == C'`, `'A * B == C'` | `VariableSumConstraint` / `VariableProductConstraint` |
| Sum/product == constant | `'A + B + C == 15'`, `'A * B == 12'` | `exactSum(k)` / `exactProduct(k)` |
| Sum/product inequality | `'A + B >= 5'`, `'A * B <= 20'` | `minSum/maxSum/minProduct/maxProduct` (strict operators offset by 1e-3) |
| Set membership | `'A in [1, 3, 5]'`, `'A not in [2, 4]'` | `inSet(...)` / `notInSet(...)` |
| Anything else | `'2*A + 3*B + C >= 15'` | `ExpressionEvaluator.evaluateBoolean` (generic) |

**Performance note.** A pattern in the table above dispatches to a
constraint that just runs a small arithmetic check on each candidate. A
"generic" fallthrough re-tokenizes and re-parses the expression for every
candidate assignment — measurably slower in tight loops. If a hot
constraint isn't matching a fast path, restructure it (e.g. move one
term to the other side so the left becomes a recognized sum/product) or
write it directly with `addConstraint`.

## Set syntax

`'A in [...]'` and `'A not in [...]'` accept a comma-separated list of
values inside the brackets. Values are parsed as numbers if possible,
otherwise as strings (with surrounding quotes stripped). Whitespace
around commas is ignored.

```dart
p.addStringConstraint('A in [2, 4, 6]');           // numeric
p.addStringConstraint("A in ['red', 'green']");    // string
p.addStringConstraint('A not in [0]');             // exclude one value
```

The regex demands a single variable on the left side of `in`/`not in`.
For multi-variable membership, use `addInSet(['A', 'B'], {...})` or
`addConstraint(vars, inSet(...))` directly.

## Range syntax

`'low <= EXPR <= high'` and `'low <= EXPR < high'` are accepted; the
lower comparator must be `<=`. Both bounds must be literal numbers, not
variables. The expression must contain `+` (the parser detects sum-style
ranges only).

```dart
p.addStringConstraint('5 <= A + B <= 10');  // 5 ≤ A+B ≤ 10
p.addStringConstraint('0 <= X + Y < 7');    // 0 ≤ X+Y < 7  (uses 6.999)
```

## What is *not* supported

These will throw `ConstraintParseException` or silently degrade to the
generic evaluator. If you need them, use `addConstraint` with a custom
predicate:

- Parentheses inside expressions: `(A + B) * C`
- Boolean connectives between sub-constraints: `(A < B) and (B < C)`
- Negation of a sub-constraint: `not (A == B)`
- `if/then/else`, `==>`, `iff`
- Variables on both sides of `in`: `A in [B, C, D]`

## Error handling

`addStringConstraint` wraps parse failures in `ConstraintParseException`,
which carries the offending `constraint` string and a human-readable
`message`. The `toString()` returns
`'ConstraintParseException: <message> in "<constraint>"'`. Reference an
undefined variable and you'll see exactly that.

```dart
final p = Problem()..addVariable('A', [1, 2, 3]);
try {
  p.addStringConstraint('A + Z == 5');  // Z not defined
} on ConstraintParseException catch (e) {
  print(e.message);     // "Variable \"Z\" is not defined"
  print(e.constraint);  // "A + Z == 5"
}
```

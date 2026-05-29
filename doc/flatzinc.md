# FlatZinc frontend

`dart_csp` ships with a built-in FlatZinc parser, lowering pass, and
solver runner. The frontend takes a `.fzn` source string (or file)
and either returns a solved `Problem` instance you can drive
programmatically or prints the standard FlatZinc output format
directly.

FlatZinc is the lower-level target language that MiniZinc compiles
to. Almost every CP solver integrates at the FlatZinc level — Choco,
Gecode, Chuffed, OR-Tools, JaCoP — so once you have a `.mzn` model
you can compile it once with `mzn2fzn` and drive `dart_csp` with the
result.

This guide covers the supported FlatZinc subset, the CLI binary, the
error policy, and a worked example.

---

## Quick start

```dart
import 'package:dart_csp/dart_csp.dart';

final output = await FlatZinc.solve('''
array[1..4] of var 1..4: q :: output_array([1..4]);
constraint all_different_int(q);
constraint int_lin_ne([1, -1], [q[1], q[2]], 1);
constraint int_lin_ne([1, -1], [q[1], q[2]], -1);
constraint int_lin_ne([1, -1], [q[1], q[3]], 2);
constraint int_lin_ne([1, -1], [q[1], q[3]], -2);
constraint int_lin_ne([1, -1], [q[2], q[3]], 1);
constraint int_lin_ne([1, -1], [q[2], q[3]], -1);
constraint int_lin_ne([1, -1], [q[1], q[4]], 3);
constraint int_lin_ne([1, -1], [q[1], q[4]], -3);
constraint int_lin_ne([1, -1], [q[2], q[4]], 2);
constraint int_lin_ne([1, -1], [q[2], q[4]], -2);
constraint int_lin_ne([1, -1], [q[3], q[4]], 1);
constraint int_lin_ne([1, -1], [q[3], q[4]], -1);
solve satisfy;
''');
print(output);
// q = array1d(1..4, [2, 4, 1, 3]);
// ----------
```

`FlatZinc.solve(source)` returns the first solution in the standard
FlatZinc format. Pass `all: true` to enumerate every solution; the
output stream ends with `==========` once the search is proven
exhaustive, or with `=====UNSATISFIABLE=====` if no solution exists.

`FlatZinc.build(source)` stops after lowering and returns a
`LoweredModel` carrying the constructed `Problem`, the parameter
map, the output annotations, and the `SolveItem`. Use this when you
want to drive the solver yourself (e.g. with custom heuristics).

---

## CLI binary

```bash
# Solve a file:
dart run dart_csp:dart_csp_fzn model.fzn

# Solve via stdin:
mzn2fzn --no-output-ozn -O- model.mzn | dart run dart_csp:dart_csp_fzn

# All solutions + stats:
dart run dart_csp:dart_csp_fzn -a -s model.fzn
```

| Flag | Meaning |
|------|---------|
| `-a`, `--all-solutions` | Enumerate every solution (satisfaction only) |
| `-s`, `--statistics`    | Append a `%%%mzn-stat` block after the result |
| `-h`, `--help`          | Print usage and exit |

Exit codes follow Unix convention: `0` success, `64` usage error,
`65` parse or argument error, `66` file not found, `78` unsupported
FlatZinc builtin.

To use `dart_csp` as a MiniZinc solver, write an `.msc` file pointing
at the compiled CLI binary and place it in `~/.minizinc/solvers/`.
The full `mzn2fzn` → `dart_csp` pipeline works without further glue
because the runner emits the standard FlatZinc output format.

---

## Supported FlatZinc subset

### Variable declarations

| Form | Notes |
|---|---|
| `var int: x;` | Materialized as a bounded `±1_000_000` integer domain |
| `var L..U: x;` | Range domain (uses compact `(min, max)` rep for large ranges) |
| `var bool: b;` | Domain `[0, 1]` (booleans are 0/1 ints at the engine level) |
| `var {v1, v2, ...}: x;` | Explicit enumerated integer domain |
| `var set of L..U: S;` | Set variable over universe `L..U`, mapped onto the set-variable layer |
| `var set of {v1, ...}: S;` | Set variable over an explicit universe |
| `array[1..N] of var T: a;` | Each slot becomes a scalar `a[i]` for `i in 1..N` |
| `array[1..N] of var set of L..U: a;` | Each slot becomes a set variable `a[i]` over the shared universe |
| `array[1..N] of var T: a = [e1, e2, ...];` | Aliased — each slot gets a singleton (literal) or alias equality (identifier) |

A `var set of ...` declaration may carry a right-hand side: `= {1, 3}`
(or a range) pins the set to a fixed value, and `= other` aliases it to
another set variable (posted as a `set_eq`). Set **parameters** —
`set of int: U = 1..5;` / `set of int: U = {1, 3, 5};` — are stored and
resolved wherever a set argument is expected.

**Not yet supported**: `var float`, **unbounded** `var set of int`
(a set variable needs a finite universe — use a bounded form such as
`var set of 1..10`), aliased arrays of set variables, multi-dimensional
array declarations. These produce a `FormatException` from the parser or
an unsupported-builtin / unimplemented error from the lowering pass.

#### Set variables

A `var set of ...` declaration is lowered onto the shipped
[set-variable layer](set-variables.md): each universe element becomes a
0/1 membership indicator, and the set constraints below are posted
element-wise via the indicators (so they compose with differing
universes — e.g. `set_union` of a `1..3` set and a `3..6` set into a
`1..6` set). Solutions render the set as a FlatZinc set literal: `{}` for
the empty set, `lo..hi` for a contiguous run, and `{a, b, c}` otherwise.

### Parameter declarations

```
int: n = 5;
bool: flag = true;
array[1..3] of int: coef = [2, 3, 5];
```

Parameters are substituted at lowering time. Wherever a constraint
expects an integer constant or an int-array constant, you can pass a
parameter identifier — it's resolved transparently.

### Solve directive

```
solve satisfy;
solve minimize x;
solve maximize x;
solve :: int_search([x, y, z], input_order, indomain_min, complete) satisfy;
solve :: int_search(q, dom_w_deg, indomain_min, complete) minimize total;
solve :: seq_search([
  int_search([x], dom_w_deg, indomain_min, complete),
  int_search([y], input_order, indomain_min, complete)
]) satisfy;
```

Search annotations on `solve` directives are honoured for both
satisfaction and optimisation runs. The frontend reads the `varSelect`
keyword from the first `int_search` / `bool_search` annotation (or the
first recognised inner search inside a `seq_search([...])` block) and
routes the solve through the matching dart_csp heuristic:

| `varSelect`                                              | dart_csp picker                |
|----------------------------------------------------------|--------------------------------|
| `dom_w_deg`, `most_constrained`, `weighted_degree`       | `getSolutionWithDomWdeg`       |
| `activity_var`, `activity_var_min`, `vsids`              | `getSolutionWithActivity` (VSIDS) |
| `impact`                                                 | `getSolutionWithImpact` (IBS)  |
| `input_order`, `first_fail`, `smallest`, anything else   | default MRV                    |

For `solve minimize` / `solve maximize`, the same hint is forwarded
to `Problem.minimize` / `Problem.maximize` via the corresponding
`useDomWdeg` / `useVsids` / `useImpact` flag.

Caveats:

- The hint applies **globally** — dart_csp doesn't yet support
  per-variable-subset heuristic scoping, so the variable list passed
  to `int_search` is informational; the chosen picker scores every
  variable in the model.
- `seq_search` is parsed and walked, but the engine itself does not
  search the variable groups sequentially. The first recognised inner
  `varSelect` wins; subsequent groups contribute their `varSelect`
  only if earlier groups all used unrecognised keywords.
- `valSelect` (`indomain_min`, `indomain_max`, …) and the exploration
  mode (`complete`, `lds`, …) are still parsed and ignored — dart_csp
  uses its built-in least-constraining-value tie break.
- Unrecognised `varSelect` keywords silently fall back to MRV rather
  than failing the solve, matching the FlatZinc convention that
  solvers may ignore unsupported hints.

### Output annotations

| Form | Effect |
|---|---|
| `:: output_var` (on a `var` declaration) | Variable shows up in the output as `name = value;` |
| `:: output_array([1..N, 1..M, ...])` (on an array declaration) | Array shows up as `name = array1d(1..N, [v1, v2, ...]);` |

If a model has no `output_*` annotations the runner falls back to
emitting every variable, which is the right behaviour for
hand-written `.fzn` snippets used in tests.

### Constraints

`dart_csp` ships handlers for every FlatZinc builtin in the M1–M4
delivery plan (see [`MINIZINC_PLAN.md`](../MINIZINC_PLAN.md) at the
repo root for the milestone breakdown).

**Primitives** (M2):

- `int_eq`, `int_ne`, `int_lt`, `int_le`, `int_gt`, `int_ge`
- `int_lin_eq`, `int_lin_le`, `int_lin_ne`, `int_lin_ge`
- `bool_eq`, `bool_not`, `bool_or`, `bool_and`, `bool_xor`
- `bool_clause`, `bool2int`

**Global constraints** (M3):

- `all_different_int` (and `all_different` alias)
- `array_int_element`, `array_bool_element`
- `circuit`, `subcircuit`
- `inverse`
- `count_eq`, `nvalue`, `global_cardinality`,
  `global_cardinality_closed`
- `bin_packing_load`
- `lex_less`, `lex_lesseq`
- `value_precede_chain_int`
- `table_int`, `table_bool`
- `disjunctive`, `cumulative`, `diffn`
- `regular`

**Reified primitives** (M4):

- `int_eq_reif`, `int_ne_reif`, `int_lt_reif`, `int_le_reif`,
  `int_gt_reif`, `int_ge_reif`
- `int_lin_eq_reif`, `int_lin_le_reif`, `int_lin_ne_reif`,
  `int_lin_ge_reif`
- `bool_eq_reif`, `bool_clause_reif`

**Set constraints** (over `var set of ...` variables, set parameters,
and set literals — see [Set variables](#set-variables) above):

- `set_in`, `set_in_reif`
- `set_card` (constant or variable cardinality)
- `set_eq`, `set_ne`, `set_eq_reif`, `set_ne_reif`
- `set_subset`, `set_superset`, `set_subset_reif`, `set_superset_reif`
- `set_union`, `set_intersect`, `set_diff`, `set_symdiff`

`set_in` accepts both the constant-set form (`set_in(x, 1..5)`, posted
as a domain restriction) and the set-variable form (`set_in(x, S)`).
The lexicographic set orderings `set_le` / `set_lt` are **not** mapped
and produce an unsupported-builtin error.

### Argument constants in vars positions

Some FlatZinc encoders inline literals where you'd expect a variable
identifier — e.g. `int_lin_eq([1, 1, 1], [x, 5, y], 10)`. The
lowering pass folds those literals into the bound (here, `10 - 1*5`
becomes the new RHS over just `x` and `y`) so you don't pay for an
extra singleton variable.

### Index conventions

FlatZinc uses 1-based indexing throughout. The lowering pass keeps
the 1-based convention in any user-visible name (`a[1]`, `a[2]`, ...
in the variable map; the MUS / conflict-explanation output retains
the FlatZinc identifier verbatim). For the four constraints whose
Dart-side API is 0-based — `circuit`, `subcircuit`, `inverse`,
`array_int_element` — the FlatZinc handler posts a direct n-ary
predicate that interprets the 1-based domain conventions inline
rather than synthesising offset variables.

---

## Unsupported-builtin error policy

A FlatZinc constraint that the lowering pass doesn't recognize
produces an `UnimplementedError` whose message includes the builtin
name and the source line. The CLI binary translates this into exit
code `78` (`EX_CONFIG`).

```
$ dart run dart_csp:dart_csp_fzn unsupported.fzn
dart_csp_fzn: FlatZinc constraint 'int_pow' is not yet supported by
this lowering pass (parsed from line 3). See MINIZINC_PLAN.md for
the constraint roadmap (M3+ adds globals; M4 adds reified variants).
```

Parse errors (tokenizer or grammar errors) produce a
`FormatException` with line, column, and a one-line snippet. The
CLI binary translates this into exit code `65` (`EX_DATAERR`).

---

## Worked example: MAX-SAT

```dart
final out = await FlatZinc.solve('''
% Maximize the number of satisfied clauses across four 2-SAT clauses.
var bool: p :: output_var;
var bool: q :: output_var;
var bool: r :: output_var;

% Per-clause indicators.
var bool: s1;
var bool: s2;
var bool: s3;
var bool: s4;
var 0..4: total :: output_var;

constraint bool_clause_reif([p, q], [], s1);   % p ∨ q
constraint bool_clause_reif([r], [p], s2);     % ¬p ∨ r
constraint bool_clause_reif([q, r], [], s3);   % q ∨ r
constraint bool_clause_reif([], [q], s4);      % ¬q

constraint int_lin_eq([1, 1, 1, 1, -1],
                      [s1, s2, s3, s4, total], 0);
solve maximize total;
''');
print(out);
// p = 1; q = 0; r = 1; total = 4;
// ==========
```

The reified clause indicators turn each disjunction into a boolean
variable. Their sum is the number of satisfied clauses, which the
solver maximizes via branch-and-bound.

---

## Conflict explanation on FlatZinc problems

Every constraint posted during lowering carries a label of the form
`<fzn_name>#<counter>` (e.g. `int_lin_eq#42`,
`all_different_int#3`). The label appears on
`ConstraintRef.label` and is rendered by the MUS / conflict-
explanation pass, so an explanation pulled from a FlatZinc-derived
problem traces directly back to the FlatZinc source:

```dart
final lowered = FlatZinc.build(source);
final mus = await lowered.problem.findMinimalUnsatisfiableSubset();
for (final ref in mus!) {
  print(ref); // e.g. linearEquals[int_lin_eq#7](x, y, z)
}
```

See [`conflict-explanation.md`](conflict-explanation.md) for the
full MUS / QuickXplain API.

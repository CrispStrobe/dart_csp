# MiniZinc / FlatZinc frontend — implementation plan

A focused plan for the next session(s) to bring a FlatZinc frontend
into `dart_csp`. This doc exists so a fresh session can pick the
work up cold: scope, architecture, milestones, and the open design
questions are all here.

**Estimated effort:** 2-4 sessions. Pick deliberately, not
opportunistically — this is the highest-leverage strategic gap on
the PLAN.md roadmap and unlocks head-to-head benchmarking against
every other CP solver, but it is not a single-session item.

---

## 1. Scope decision: FlatZinc first

`dart_csp` should target **FlatZinc** as the frontend language, not
MiniZinc directly.

- FlatZinc is the low-level target language that MiniZinc compiles
  to. Its grammar is small, its semantics are first-order, and the
  set of builtin constraints is finite and well-documented.
- Almost every other CP solver integrates at the FlatZinc level
  (Choco, Gecode, Chuffed, OR-Tools, JaCoP). MiniZinc users compile
  to `.fzn` once and feed the result to whichever solver they're
  benchmarking.
- The MiniZinc compiler (`mzn2fzn`) is the standard way to produce
  FlatZinc from MiniZinc source; it handles type checking, predicate
  expansion, and decomposition of high-level constructs. Users who
  already have `.mzn` models pay zero additional cost to drive
  `dart_csp` once FlatZinc support lands.
- The MiniZinc tool also drives the standard MiniZinc Challenge
  benchmarking infrastructure: a solver that accepts FlatZinc and
  emits the standard output format can be wrapped as a MiniZinc
  solver configuration (`.msc`) without further work.

**Out of scope for v1:** XCSP3 (different format, XML-based — would
be a separate frontend), MiniZinc parsing (the MiniZinc compiler is
the right tool for `.mzn` → `.fzn`).

---

## 2. Architecture sketch

```
lib/src/flatzinc/
├── ast.dart        # AST node definitions
├── parser.dart     # Tokenizer + parser → AST
├── lowering.dart   # AST → Problem builder calls
└── runner.dart     # Top-level: file path or string → Problem
                    # + output-formatter for solution maps

bin/
└── dart_csp_fzn.dart   # CLI: reads stdin or a .fzn file,
                        # runs the solver, prints the standard
                        # FlatZinc output format
```

`lib/dart_csp.dart` re-exports the FlatZinc runner so callers can
do `final problem = await FlatZinc.parse(source);` directly.

### Parser shape

Hand-rolled recursive-descent parser keeps the dependency footprint
zero (matches the rest of the library). FlatZinc's grammar is small
enough that a parser generator would be overkill, and pure-Dart
purity is part of the library's identity.

```
ParseResult = (variables, parameters, constraints, solveItem)
```

### Lowering pass

Pure function: `Problem fromAst(ParseResult ast)`. Walks the AST,
emits one `Problem.addX` call per FlatZinc constraint. Uses the
`label:` parameter that shipped this cycle to carry the FlatZinc
constraint name and any user-visible identifier — so a MUS pass on
a FlatZinc-derived problem produces refs like
`allDifferent[all_different_int#3](x[0], x[1], x[2])`.

### Output formatter

FlatZinc's standard output format is:

```
x = 3;
y = 7;
arr = array1d(1..3, [1, 2, 3]);
----------
==========
```

`----------` after each solution; `==========` to mark
exhaustive search complete. Implemented in `runner.dart`; works
with both `getSolution` (single solution) and `getSolutions`
(stream) entry points.

---

## 3. FlatZinc subset for v1

### Variable declarations

| FlatZinc construct | Dart mapping |
|---|---|
| `var int: x;` | `addVariable('x', /* large int domain */)` |
| `var 1..10: x;` | `addRangeVariable('x', 1, 10)` |
| `var bool: b;` | `addVariable('b', [0, 1])` |
| `var {1, 3, 5}: x;` | `addVariable('x', [1, 3, 5])` |
| `array[1..N] of var int: a;` | `addVariables(['a[1]'..'a[N]'], ...)` |

**Out of scope for v1:** `var set of int`, `var float`. Both can be
added later — set-var support already exists in the library and the
mapping is mechanical; float requires the float-variable strategic
gap from PLAN.md and is multi-session in its own right.

### Parameter (non-variable) declarations

`int: n = 5;` and similar are stored in a parameter map and
substituted at lowering time. Parameter arrays
(`array[1..3] of int: a = [1, 2, 3];`) are similar.

### Constraints

The FlatZinc spec defines ~100 builtin constraints. The
[FlatZinc 2.x reference](https://docs.minizinc.dev/en/stable/fzn-spec.html)
groups them by argument type. v1 targets the most-used:

| FlatZinc builtin | Dart mapping |
|---|---|
| `int_lin_eq(coeffs, vars, c)` | `addLinearEquals(vars, coeffs, c)` |
| `int_lin_le(coeffs, vars, c)` | `addLinearLeq(vars, coeffs, c)` |
| `int_lin_ne(coeffs, vars, c)` | `addConstraint(vars, predicate)` (negated linear) |
| `int_eq(a, b)`, `int_ne`, `int_lt`, `int_le` | `addConstraint([a, b], pred)` |
| `bool_eq`, `bool_or`, `bool_and`, `bool_xor` | reified helpers |
| `bool_clause(positive, negative)` | `addClause(positive: ..., negative: ...)` |
| `bool2int(b, x)` | `addConstraint([b, x], (a, b) => a == b)` |
| `array_int_element(idx, arr, value)` | `addElement(idx, arr, value)` |
| `all_different_int(vars)` | `addAllDifferent(vars)` |
| `circuit(vars)` | `addCircuit(vars)` |
| `subcircuit(vars)` | `addSubcircuit(vars)` |
| `cumulative(starts, durs, dems, cap)` | `addCumulative(starts, durs, dems, cap)` |
| `disjunctive(starts, durs)` | `addNoOverlap(starts, durs)` |
| `diffn(xs, ys, ws, hs)` | `addDiffN(xs, ys, ws, hs)` |
| `inverse(forward, inverse)` | `addInverse(forward, inverse)` |
| `regular(vars, q, s, d, q0, F)` | `addRegular(vars, dfa)` |
| `count_eq(vars, value, k)` | `addAmongExactly(vars, {value}, k)` |
| `nvalue(n, vars)` | `addNvalue(vars, n)` |
| `global_cardinality(vars, cover, counts)` | `addGcc(vars, ...)` |
| `bin_packing_load(loads, items, sizes)` | `addBinPacking(items, sizes, loads)` |
| `lex_lesseq(a, b)` | `addLexLeq(a, b)` |
| `lex_less(a, b)` | `addLexLt(a, b)` |
| `value_precede_chain_int(c, vars)` | `addValuePrecedence(vars, c)` |
| `table_int(vars, t)` | `addTable(vars, tuples)` |

**Reified constraints.** Most FlatZinc int/bool constraints have
`_reif` variants (e.g., `int_eq_reif(a, b, r)`). These map to the
`addReified*` family on `Problem`. The reified mapping is
mechanical but doubles the constraint dispatch surface — plan for
this in the lowering pass.

**Annotations** (`:: defines_var(x)`, `:: var_is_introduced`,
`:: output_var`, `:: output_array(...)`) drive which variables
appear in the output, and influence the solver-side variable order.
For v1, parse annotations but only act on `output_var` /
`output_array` (drives the output formatter). Treat the rest as
hints we may use in a later iteration.

### Solve directives

```
solve satisfy;                              // → getSolution
solve minimize x;                           // → minimize('x')
solve maximize x;                           // → maximize('x')
solve :: int_search(...) satisfy;           // annotation; ignored in v1
```

Search annotations (`int_search(vars, varSelect, valSelect, ...)`)
are FlatZinc's way to control variable/value ordering. v1 parses
and ignores them; later iterations can map them to the existing
heuristic flags (`useDomWdeg:`, `useVsids:`, `useImpact:`,
`useLastConflict:`) plus a value-ordering knob (not currently
exposed).

### Output formatter

Walks the variable map produced by the solve entry point, emits
`name = value;` for each `:: output_var`-annotated variable and
`name = array1d(...);` for each `:: output_array(...)` array.
Followed by the standard FlatZinc separators (`----------` per
solution; `==========` at end).

---

## 4. Milestones

Each milestone is a self-contained, testable increment. Land them
in order.

### M1 — Tokenizer + AST shell + `solve satisfy` end-to-end

- Tokenize FlatZinc source into a stream of tokens.
- Parse a minimal subset: `var int: x;`, `var 1..N: x;`,
  `array[...] of var int: a;`, plus `solve satisfy;`. No
  constraints yet.
- AST nodes: `VarDecl`, `ArrayVarDecl`, `SolveItem`.
- Lowering walks the AST and calls `Problem.addVariable` /
  `addRangeVariable` / `addVariables`.
- Output formatter emits `var = value;` for every variable.
- End-to-end test: a trivial `.fzn` file declaring three vars and
  asking for a solution parses, solves, and prints the expected
  output.

### M2 — Parameters + integer/boolean primitive constraints

- Parse `int: n = 5;` / `bool: b = true;` parameter declarations
  and parameter arrays.
- Parse and lower `int_eq`, `int_ne`, `int_lt`, `int_le`,
  `int_lin_eq`, `int_lin_le`, `int_lin_ne`, `bool_clause`,
  `bool_eq`, `bool_or`, `bool_and`, `bool_not`.
- AST nodes: `ConstraintItem` with name + argument list.
- Lowering dispatches by constraint name to a handler table
  (`Map<String, void Function(LoweringContext, List<AstArg>)>`).
- Test fixture: small CNF-style problems and small linear
  arithmetic problems.

### M3 — Global constraints

- Parse and lower `all_different_int`, `circuit`, `subcircuit`,
  `cumulative`, `disjunctive`, `diffn`, `inverse`,
  `array_int_element`, `regular`, `count_eq`, `nvalue`,
  `global_cardinality`, `bin_packing_load`, `lex_lesseq`,
  `lex_less`, `value_precede_chain_int`, `table_int`.
- One handler entry per builtin; the handler table grows but stays
  flat (no inheritance).
- Test fixture: small instances of each global (n-queens,
  pigeonhole, single-machine scheduling) drawn from MiniZinc
  Challenge or the `tutorial.minizinc.org` examples.

### M4 — Optimization + reified constraints

- Parse and lower `solve minimize <var>;` / `solve maximize
  <var>;` via the existing `Problem.minimize` / `maximize` entry
  points.
- Parse and lower the `_reif` variants of every primitive (and
  selected globals where the spec defines reifications).
- Reified mapping uses the existing `addReified*` family. New
  AST argument type for the reification boolean.
- Test fixture: a small MAX-SAT instance and a small soft-CSP
  instance (e.g., maximum-clique on a tiny graph).

### M5 — CLI + standard FlatZinc output + regression tests

- `bin/dart_csp_fzn.dart`: command-line wrapper that reads a `.fzn`
  file path or stdin, parses, solves, and prints output in the
  standard FlatZinc format.
- Output annotations: `:: output_var`, `:: output_array(...)`
  drive which variables are surfaced and how arrays are formatted
  (`array1d(1..N, [v1, v2, ...])`).
- Standard separators: `----------` after each solution,
  `==========` once exhaustive search is complete.
- Regression tests: drive a handful of MiniZinc Challenge problems
  through `mzn2fzn` (if installed on the test runner) and assert
  the produced solution is valid per the original `.mzn` model.

---

## 5. Open design questions

These are decisions worth making explicitly during M1 / M2, before
the parser gets large enough that changes hurt.

- **AST shape: discriminated record types or class hierarchy?**
  Records get verbose for nested AST nodes; a sealed class hierarchy
  matches the style of `_SearchResult` in `solver.dart`. Probably
  go with sealed classes for consistency.
- **Error reporting: lexer/parser error format.** FlatZinc files
  are machine-generated, so most errors will be "internal" (the
  user is debugging their `.mzn` source via the generated `.fzn`).
  Decision: parser errors include line + column and a short snippet,
  but no fancy ANSI styling. Just throw `ArgumentError` with a
  detailed message, matching the rest of the library's error
  convention.
- **Memory footprint of parsed AST on large models.** MiniZinc
  challenge instances regularly have 10 000+ constraints in the
  FlatZinc form. Naive AST representation costs ~100 bytes per
  constraint; 10 000 constraints = ~1 MB AST. Acceptable. If profiling
  later shows this is a problem, the lowering pass can stream
  constraints from the parser instead of materializing the full AST
  first.
- **Variable-name namespacing for FlatZinc array elements.**
  FlatZinc arrays of variables use names like `x_1`, `x_2`, ... in
  the source but the lowered Problem uses our own naming. Decision:
  preserve FlatZinc names verbatim (with `[i]` suffixed for array
  elements rendered for the output formatter only, not stored
  internally — internal name is the literal FlatZinc identifier).
  This keeps MUS labels and debug output legible against the
  original `.fzn` file.
- **`label:` use during lowering.** Every lowered constraint should
  carry a label derived from the FlatZinc constraint name plus a
  per-occurrence counter (e.g. `int_lin_eq#42`). This makes MUS
  output trivially traceable back to the source `.fzn` line. Could
  be even better with line-number information preserved from the
  parser.
- **Bool ↔ int dispatch.** FlatZinc's `bool2int(b, x)` and
  similar mean the same physical 0/1 variable can be touched by
  both bool and int constraints. The existing `Problem` already
  handles this (bool vars have domain `[0, 1]` and accept int
  arithmetic). No special handling needed.
- **Reification reverse-direction.** `int_eq_reif(a, b, r)` means
  `r ⇔ (a == b)`. The existing `addReifiedEquals(r, a, constant)`
  expects a constant, not a variable. The variable-variable form is
  `addReifiedEqualsVar(r, a, b)`. Lowering needs to choose the right
  one based on argument types.

---

## 6. Test plan

### Unit tests

`test/flatzinc/parser_test.dart` — tokenization + AST construction.
`test/flatzinc/lowering_test.dart` — AST → Problem mapping for each
constraint type. `test/flatzinc/output_test.dart` — solution map →
FlatZinc output formatting.

### Integration tests

`test/flatzinc/integration_test.dart` — end-to-end on hand-written
`.fzn` snippets representing each constraint family. Fixture files
live in `test/flatzinc/fixtures/`.

### Regression tests against MiniZinc Challenge

`test/flatzinc/challenge_test.dart` (skip if `mzn2fzn` is not in
`$PATH`) — drive a curated subset of the MiniZinc Challenge problems
through `mzn2fzn`, solve via dart_csp, and assert each returned
solution satisfies the original `.mzn` model's constraints. Start
with one problem per constraint family covered in M3.

### Performance bench

`benchmark/benchmark.dart` gains a `bench(flatzinc)` section running
a small set of FlatZinc problems with wall-clock-only reporting.
Mirror the existing 5-rep warm-up + 25-rep median shape. Use this
to track regressions in the parser + lowering pipeline as more
constraints are added.

---

## 7. Documentation deliverables

When the frontend ships:

- New topical guide `doc/flatzinc.md` (11th guide) covering: how to
  use the frontend, the supported FlatZinc subset, the
  unimplemented-builtin error policy, and a worked example.
- README section "FlatZinc frontend" with the `bin/dart_csp_fzn.dart`
  invocation and a short `.fzn` example.
- `STABILITY.md` classification of the new public API
  (`FlatZinc.parse`, `FlatZinc.solve`, the CLI binary).
- `PLAN.md`: flip the "MiniZinc / FlatZinc / XCSP3 frontend"
  strategic gap from `[ ]` to `[x]` (with a note that XCSP3
  remains separately-out-of-scope).
- `CHANGELOG.md` entry under "Unreleased".

---

## 8. References

- [FlatZinc 2.x spec](https://docs.minizinc.dev/en/stable/fzn-spec.html)
- [MiniZinc 2.x docs (overview)](https://docs.minizinc.dev/en/stable/)
- [Standard library of FlatZinc builtins](https://www.minizinc.org/doc-2.7.6/en/lib-flatzinc.html)
- [MiniZinc Challenge problem set](https://www.minizinc.org/challenge.html)
- [Choco's FlatZinc parser](https://github.com/chocoteam/choco-parsers)
  — useful reference for the constraint-mapping table
- [Chuffed's FlatZinc parser](https://github.com/chuffed/chuffed) —
  same

The Choco and Chuffed parsers in particular have been through many
rounds of MiniZinc Challenge battle-testing. Both are MIT-licensed
and can be consulted for the corner cases that the FlatZinc spec
doesn't fully nail down.

# Fuzzing dart_csp's reader surfaces

Every entry point here consumes untrusted text: FlatZinc source, or a
constraint string. The contract each one is held to is:

> Parsing arbitrary input may **reject**, but must never crash with an
> unexpected exception type, and must never hang.

`tool/fuzz/targets.dart` encodes that contract per target as an `isClean`
allow-list. Anything thrown that is not on the list is an *escape* — a
contract violation — and the fuzzer minimizes it to a small reproducer.

Built on [covfuzz](https://github.com/CrispStrobe/covfuzz).

## Running it

Blind mutation — fast, no setup, what CI runs:

```bash
dart run tool/fuzz/fuzz_blind.dart                    # all targets
dart run tool/fuzz/fuzz_blind.dart flatzinc-lower     # one target
dart run tool/fuzz/fuzz_blind.dart --budget-ms 60000  # longer run
```

Coverage-guided — ~150 execs/sec, evolves a corpus toward paths behind
preconditions that blind mutation rarely satisfies. Needs the VM service:

```bash
dart run --enable-vm-service=0 --no-pause-isolates-on-exit \
  tool/fuzz/covfuzz_target.dart flatzinc-lower
```

The corpus persists in `.fuzz-corpus/<target>/` and reloads on the next run,
so coverage accumulates across sessions. Crashes land in
`.fuzz-crashes/<target>/`. Both are gitignored.

The seed is fixed, so a CI failure reproduces locally with the same command.

## Targets

| Target | Entry point | Clean rejections |
| --- | --- | --- |
| `flatzinc-parse` | `parseFlatZinc` | `FormatException` |
| `flatzinc-lower` | `lower(parseFlatZinc(…))` | `FormatException`, `UnimplementedError`, `StateError`, `ArgumentError` |
| `constraint-parse` | `ConstraintParser.parseConstraint` | `ConstraintParseException`, `ArgumentError` |
| `eval-numeric` | `ExpressionEvaluator.evaluateNumeric` | `ArgumentError`, `FormatException` |
| `eval-boolean` | `ExpressionEvaluator.evaluateBoolean` | `ArgumentError`, `FormatException` |

`flatzinc-lower` allows `ArgumentError` because `bin/dart_csp_fzn.dart`
deliberately maps it to exit 65 alongside `FormatException` — it is a designed
rejection channel for malformed constraints, not a leak. `RangeError` and
`StackOverflowError` are on no allow-list; those would be real defects.

## Interpreting the exit code

| Code | Meaning | Gated in CI |
| --- | --- | --- |
| 0 | Clean | — |
| 1 | Escape: a non-allow-listed exception | **yes** |
| 2 | SLOW: >5ms/iter or a single parse over 200ms | no (`--allow-slow`) |

SLOW is not gated because it is an absolute threshold on a JIT runtime: the
first input to reach a cold path pays compilation cost. One shape measured
~500ms on first execution against a ~2ms steady state. It is still worth
reading — it is what surfaced the quadratic tokenizer below — but confirm any
hit with a scaling measurement (time at n, 2n, 4n; a ratio near 4 per doubling
is quadratic, near 2 is linear) before treating it as a defect.

## Stressor sizing

`stressors` are one-shot structural inputs appended after the random pass, for
shapes random mutation rarely produces — deep nesting, extreme declared
bounds, long operator chains.

They are deliberately kept to the low tens of KB. Large enough to exercise the
caps (nesting still exceeds the parser's 2000-frame limit; declared domains
still exceed the lowering limit), small enough that linear handling stays under
the 200ms SLOW threshold. Earlier revisions used 100–400KB inputs, which made
every target report SLOW purely because the input was enormous — the signal
was lost. If you add a stressor, keep it in that range.

## What this found

Three defects on the first run, all reachable from small inputs:

1. **Unbounded domain materialization.** `Problem.addRangeVariable` expands a
   range into an explicit element list, so a declared width is also an
   allocation size. `var 1..999999999999999999: x;` — 40 bytes — asked for a
   10^18 element list and never returned. The same held for array lengths and
   `set of L..U` universes. Now capped, rejected as `FormatException`.
   (Note: `addRangeVariable`'s doc comment claims it works "without allocating
   per-step domain lists". It does allocate. The cap is a containment fix at
   the FlatZinc boundary; making the representation interval-based would be
   the deeper fix.)

2. **Quadratic tokenizer.** `ExpressionEvaluator` accumulated tokens with
   `currentToken += char`, reallocating the whole token each character. An
   expression with no top-level operator is a single token, so `((((1))))`
   was O(n²): 32KB took ~90ms, and 400KB did not finish in four minutes.
   Rewritten to slice by index — the same input now takes milliseconds.

3. **Redeclaration leaked the builder's error type.** A model naming the same
   variable twice surfaced `Problem.addVariable`'s `ArgumentError`, losing the
   line number and making user error look internal. Now a `FormatException`
   naming the line.

Regression tests for all three are in `test/flatzinc/resource_limits_test.dart`.

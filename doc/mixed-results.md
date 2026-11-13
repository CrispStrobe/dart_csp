# Original-equation checks in the main mixed solver

`Problem.getSolutionDetailed()` and `CSP.solveDetailed()` report whether a
returned point actually satisfies the original mixed model. All legacy main
engine solve paths also validate a candidate before emitting it: ordinary and
conflict-directed search, both LCG search variants, streams and optimization.

```dart
final model = Model();
model.problem.floatRounding = IntervalRounding.outward;
final x = model.realVar('x', -1e-7, 1e-7);
final y = model.realVar('y', -1e-7, 1e-7);
(x * y * 1e14).eq(1);

final result = await model.problem.getSolutionDetailed();
print(result.status); // candidateRejected at the default box width
print(result.candidate); // {x: 0.0, y: 0.0}
print(result.maxNormalizedViolation); // greater than 1
```

The model is feasible: `x=y=1e-7` satisfies it numerically. Its midpoint does not.
Previously independently small auxiliary boxes allowed the main engine to return
the zero point. The DSL now records immutable generated linear/product
definitions in dependency order. Validation recomputes those definitions from
the original decisions and then evaluates the original constraints. A small
hidden product error cannot bypass a later large multiplier.

## Tolerances and status

`Problem.floatValidation` accepts `MixedValidationOptions`:

```dart
problem.floatValidation = MixedValidationOptions(
  defaultTolerance: const MixedTolerance(absolute: 1e-8, relative: 1e-10),
  byLabel: {
    'length-mm': const MixedTolerance(absolute: 1e-6, relative: 0),
    'angle-rad': const MixedTolerance(absolute: 1e-9, relative: 0),
  },
);
```

Each numeric relation permits
`absolute + relative * max(abs(lhs), abs(rhs))`. Without explicit settings both
tolerances default to `floatEpsilon` for compatibility; physical models should
choose tolerances appropriate to their units. Declared variable domains remain
hard limits. The search's box-width target is separate from residual acceptance.

| Detailed status | Meaning |
|---|---|
| `satisfied` | Returned point passes original-equation checks |
| `infeasible` | Finite-domain search exhausted all assignments |
| `searchExhausted` | Interval search exhausted under its arithmetic; no mathematical certificate |
| `candidateRejected` | A terminal midpoint failed required residuals |
| `precisionLimit` | Rejected point and an interval cannot be split to its requested width |
| `numericalFailure` | Invalid/non-finite candidate evaluation |
| `cancelled` / `searchLimit` | Search stopped without a complete verdict |

A representably stagnant interval may still return a numerically satisfied
point; `precisionLimited` records its unmet box-width target. A rejected point
is neither an infeasibility proof nor a reason to learn a conflict. It does not
become an optimization incumbent or a solution event. Restarts stop on that
unresolved outcome instead of repeating the same rejected box indefinitely.

The current interval engine stops at a rejected terminal midpoint. It does not
add numerical polishing or further refinement automatically. Request a tighter
box target if appropriate, or use `GeometrySolveSession` for local geometric
solving. Numerical satisfaction does not prove exact-real existence, uniqueness
or global infeasibility. Continuous detailed outcomes never set
`certifiedInfeasible`.

## Compatibility and diagnostics

Existing APIs still return a solution map or `'FAILURE'`, and streams emit only
validated points. `lastMixedValidation` exposes diagnostics after a legacy
solve, but this static diagnostic slot can be overwritten by another solve.
The detailed result owns per-call status, candidate, residuals and stats and is
the appropriate interface for concurrent work. `Problem` postprocessing still
strips generated variables and materializes sets.

`Problem.copy()` and all main-engine construction paths retain provenance and
tolerances. Generated DSL names cannot collide with user variables. Direct
`CSP.solveWithMinConflicts` rejects continuous inputs just as the Problem wrapper
does. Finite-domain MUS/QuickXplain APIs reject continuous inputs and consume
detailed finite-domain statuses internally, so an unresolved numerical witness
cannot produce a false UNSAT explanation.

Thirty-one new regressions cover amplified expressions, nested provenance,
physical tolerance overrides, representable limits, non-finite values, copy,
all return paths and proof-API boundaries. They passed with 177 existing
continuous/DSL/optimization/QuickXplain tests before the consolidated checkpoint.

# Detailed continuous results

`ContinuousModel.solveDetailed()` makes the termination reason and numerical
quality visible. The legacy `solve()` convenience method remains available and
returns a solution only when its returned coordinates pass residual validation;
other outcomes remain `null` for compatibility. Use the detailed method whenever
a limit, cancellation, or numerical failure must be distinguished from exclusion.

```dart
final model = ContinuousModel();
final x = model.addVar('x', 0, 4);
(x * x).eq(2);
final result = model.solveDetailed();
print(result.status);
print(result.solution?.midpoint);
print(result.residuals);
```

Residual checks recompute derived auxiliary expressions from the decision
coordinates in construction order. They do not accept small auxiliary equation
errors independently when those errors can be amplified by a later expression.
Absolute and relative residual tolerances are separate from box-width epsilon.
A numerically satisfied result is not an interval existence certificate.

The detailed method exposes distinct statuses for satisfied results, unvalidated
candidates, infeasible search, split limits, representable precision limits,
cancellation, and numerical failures. Inspect the enum and result diagnostics
for the exact contract. `certifiedInfeasible` is currently false even under
outward arithmetic: further auditing of expression folding and all search
boundaries is required before certifying an end-to-end proof.

The synchronous solver supports an explicit cancellation predicate and deadline.
It does not claim that event-loop timers can interrupt synchronous Dart work;
use a worker for that execution model. The geometric session work will provide
the separate interactive numerical path described in the implementation plan.

## Correctness repairs in this checkpoint

Automatically introduced expression domains are constructed conservatively;
midpoints avoid overflow; bisection detects representable endpoint stagnation;
squares use a nonnegative forward range; and generated auxiliary names cannot
silently overwrite caller variables. The regressions also cover a feasible
large-cancellation expression and impossible negative squares.

The main `Problem` mixed engine still returns its established map/string result
shape. The standalone detailed residual contract must not be assumed to have
been retrofitted onto every main-engine entry point yet.

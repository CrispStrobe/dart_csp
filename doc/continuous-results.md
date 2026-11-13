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

The main `Problem` mixed engine has its own
[original-equation result contract](mixed-results.md). Legacy main-engine calls
keep their map/string shape but validate witnesses before emission. Use
`getSolutionDetailed()` for per-call status, residuals and unresolved outcomes.

## Event-driven contractor work

The model caches a compiled variable-to-contractor dependency graph. Structural
edits invalidate it. Each solve reuses indexed queue/deduplication buffers and
linear prefix/suffix bounds. Root propagation visits all contractors; splitting
one variable wakes its dependants. Unfinished work is carried into both children
if the conservative per-node work cap is reached. Linear contraction performs
O(k) term work per pass rather than recomputing all other terms for each variable.

`result.stats` exposes structural revision/reuse, contractor and term visits,
queue work, narrowing, search domain copies, work-cap hits and per-constraint
evaluation counts. This cache reuses model structure; it does not reuse the
previous solution or turn interval search into the geometric numerical solver.
Search branch maps and global split-variable selection remain.

Focused tests check 60 seeded systems against analytic linear solutions. With
80 disconnected fixed constraints and another component split more than ten
times, every disconnected constraint is evaluated once. Increasing a fixed
linear row from 100 to 400 terms increases recorded term visits by at most 4.1×.
These are measured work bounds, not a wall-clock speedup claim. Cancellation is
also checked within long linear passes.

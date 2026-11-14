# Bounded sparse geometry linear solving

`SparseLdltGeometrySolver` adds a pure-Dart direct linear step for larger sparse
geometry components. It preserves the existing nonlinear solver, physical
acceptance checks, session commits and rollback behavior. The default adaptive
backend tries it for components with at least 256 active tangent coordinates,
subject to explicit structural limits and an additional default numeric-work
cap of 32 Schur updates per raw CSR entry.

The original direct implementation was saved at source checkpoint
[`b22bb671e505ad818c46f1a69772973ead436dd4`](https://github.com/CrispStrobe/dart_csp/commit/b22bb671e505ad818c46f1a69772973ead436dd4),
library tree `960b3b699628ade1e6b5b61cecae6037f50391f4`. The continuation adds
the automatic fill-cost cap described below. Its implementation is in
[`numeric.dart`](../lib/src/geometry/numeric.dart) and
[`sparse_ldlt.dart`](../lib/src/geometry/sparse_ldlt.dart), exported through
`package:dart_csp/geometry.dart`. See [the continuation report](sparse-resume-2026-11-14.md)
for the current validation and measurement boundary. This configuration guide
does not imply that every eligible system is faster.

## Default selection

An ordinary `GeometrySolveSession.solve()` uses
`const AdaptiveGeometryLinearSolver()`. Selection applies separately to each
connected numerical component. Here, `n` is the number of active tangent
coordinates and `m` is the number of scalar Jacobian rows; neither is the total
number of CAD features or parameter objects in the document.

| Condition, in selection order | Backend |
|---|---|
| `n <= 64` and `(m + n) * n <= 262144` | Column-pivoted dense QR of the augmented least-squares system |
| Dense QR is ineligible and `n < 256` | Matrix-free preconditioned conjugate gradients (CG) |
| Dense QR is ineligible and `n >= 256` | Bounded sparse LDLT attempt, additionally capped at `32 * rawNNZ` Schur updates, with CG fallback when appropriate |

The dense entry limit still applies to components with 64 or fewer columns.
A sparse input can produce substantial factor fill, so reaching 256 columns
does not guarantee that the direct attempt is eligible. Large connected graphs
with dense fill may use CG under the default caps. Many independent small
components can continue to use QR even when their total coordinate count is
large.

`rawNNZ` means the length of the CSR values array, including structural zeros
and duplicate entries. The effective numeric-work cap is the smaller of the
direct solver's `maxNumericWork` and
`sparseNumericWorkPerNonzero * rawNNZ`. The default multiplier is 32. This
heuristic keeps low-fill patterns eligible while declining patterns whose
factorization work greatly exceeds a sparse matrix pass. Eligibility still
performs bounded symbolic work, so a cold decline is not free.

Set `sparseNumericWorkPerNonzero: null` to use only the direct solver's explicit
limits. A zero multiplier permits only patterns needing zero Schur updates;
negative values throw `ArgumentError`. Multiplication saturates at the hard
numeric cap without overflowing native or JavaScript integer arithmetic.

## Configure a session

Use the existing `linearSolver` argument on `solve` or `solveAsync`. This example
changes the direct-selection threshold and gives the direct attempt smaller
resource limits while retaining adaptive fallback:

```dart
import 'package:dart_csp/geometry.dart';

GeometrySolveResult solveWithinLimits(GeometrySolveSession session) {
  return session.solve(
    linearSolver: const AdaptiveGeometryLinearSolver(
      denseParameterLimit: 64,
      denseEntryLimit: 262144,
      sparseParameterThreshold: 512,
      sparseNumericWorkPerNonzero: 16,
      sparseDirectSolver: SparseLdltGeometrySolver(
        maxColumns: 2048,
        maxFactorEntries: 131072,
        maxSymbolicWork: 10000000,
        maxNumericWork: 10000000,
        maxAssemblyWork: 2000000,
      ),
    ),
    options: const GeometrySolveOptions(
      maxLinearIterations: 1000,
      linearTolerance: 1e-8,
    ),
  );
}
```

Choose limits from the shapes and responsiveness requirements of the
application. Increasing a cap permits more work and storage; it does not
establish a speed advantage or improve the conditioning of an equation.
`sparseParameterThreshold` controls when the adaptive backend considers a direct
attempt. The adaptive multiplier applies even to a caller-supplied
`sparseDirectSolver`, unless explicitly set to null. Passing a backend directly
gives more direct control and does not apply the adaptive multiplier:

```dart
// Use CG for every component handled by this session solve.
final cgResult = session.solve(
  linearSolver: const SparseCgGeometrySolver(),
);

// Use bounded LDLT directly. This choice has no automatic CG fallback.
final directResult = session.solve(
  linearSolver: const SparseLdltGeometrySolver(),
);
```

The examples above assume an existing `GeometrySolveSession`. Inspect each
result's `isSuccess` and `status`; an unsuccessful candidate is not committed.
The outer nonlinear solver can retry a rejected linear step with different
damping, according to its existing algorithm and nonlinear iteration budget.

## Equation and numerical checks

For the Jacobian `J`, residual vector `r`, caller-provided diagonal vector `d`
and damping scalar `lambda`, the linear backend solves

\[
\left(J^T J + \lambda\,\operatorname{diag}(d)\right)s = -J^T r.
\]

The direct backend assembles this exact normal equation in sparse lower-triangle
storage, permutes it with deterministic minimum-degree ordering, and factors it
as `L D L^T`. Equal-degree choices use the original column index to break ties.
The diagonal damping contribution uses the supplied `lambda` and `d` exactly;
the direct backend does not add pivot jitter or change the requested damping.
Every pivot must be finite and strictly positive.

CSR rows may contain unsorted columns, duplicate columns and numerical zeros.
All raw entries contribute to the structural pattern. Numeric assembly visits
the full Cartesian product of each raw row and stores the lower triangle. For
example, two entries `a` and `b` in the same column contribute
`a*a + a*b + b*a + b*b` to the diagonal, including cancellations. A value changing
through zero does not change the symbolic graph.

Forming normal equations can amplify conditioning problems: for an undamped,
full-column-rank matrix, the 2-norm condition number of `J^T J` is the square of
that of `J`. Damping affects the actual system, but a successful factorization
alone is insufficient evidence that the returned step solves it accurately.
The backend therefore recomputes the equation error from the original CSR
Jacobian, independently of the assembled factor storage:

\[
\eta =
\frac{\left\|J^T(Js+r)+\lambda\operatorname{diag}(d)s\right\|_2}
{\left\|J^T r\right\|_2}.
\]

When the denominator is zero, the check uses the absolute error norm instead.
Both norms must be finite, and `eta` must satisfy the requested
`relativeTolerance`. Up to two correction solves can refine the step when the
first explicit check fails and the budget permits. The reported
`GeometryLinearStep.relativeResidual` is this checked equation residual.

A small linear equation residual is not a forward-error guarantee for an
ill-conditioned step. The nonlinear session separately checks the original
physical residual tolerances before it commits geometry. Neither convergence
nor failure of this local numerical procedure is a global feasibility or
mobility certificate.

## Structural resource limits

All limits are nonnegative integers. They bound selected structural operations
and stored entries; they are not byte limits or elapsed-time deadlines.

| Setting | Default | What it bounds |
|---|---:|---|
| `maxColumns` | 4,096 | Active scalar columns in one direct attempt |
| `maxFactorEntries` | 262,144 | Diagonal entries plus unique original/fill edges stored in the lower-triangular factor pattern |
| `maxSymbolicWork` | 20,000,000 | Structural input work, raw-row pair visits, deterministic ordering scans, neighbor/fill visits and pattern materialization |
| `maxNumericWork` | 20,000,000 | Lower-triangular Schur-complement update count implied by the filled pattern |
| `maxAssemblyWork` | 4,000,000 | Sum of squared **raw** CSR row lengths, including duplicates and zero-valued entries |

Assembly eligibility is checked before any Cartesian-product assembly. Factor
storage is bounded while constructing the original adjacency and during fill,
before adding the corresponding Set entries. Symbolic and numeric work limits
are also checked before performing the work they permit. This prevents a short
wide row from materializing an oversized normal graph before the factor-entry
limit is noticed.

The exact minimum-degree implementation uses a deterministic scan of the
remaining candidates, with its scan work included in the symbolic cap. It is
bounded, but it is not a promise that every sparse graph will factor cheaply.
Particularly fill-heavy components can exceed the caps even when their column
count fits `maxColumns`.

## Budgets, cancellation and fallback

The linear `maxIterations` budget counts different units for the different
algorithms:

| Backend | One budget unit |
|---|---|
| Dense QR | One QR pivot step |
| CG | One iterative update |
| Sparse LDLT | One assembly/factorization/initial-solve attempt, or one subsequent refinement solve |

A sparse direct attempt therefore uses at most three units: one initial attempt
and at most two refinements. A positive budget can return zero iterations for
an already-zero right-hand side. A zero supplied budget returns
`iterationLimit` before factorization. Structural ineligibility also consumes
zero linear iteration units, although the bounded eligibility analysis itself
can require work.

In adaptive mode, a structural decline leaves the complete CG budget available.
A numeric attempt that fails after consuming units leaves only the remainder
for CG. The returned iteration count includes both attempts and cannot exceed
the supplied budget. CG starts its own solve; the unsuccessful direct step is
not used as its initial iterate. A cancellation result is terminal and never
triggers fallback. Invalid numerical input detected before a numeric attempt is
also returned directly as `numericalFailure`.

Direct calls expose `shouldStop`; session calls expose `shouldCancel` and
`timeLimit`, which feed the backend's stop callback. The direct implementation
polls during structural analysis, assembly, factorization, triangular solves,
refinement and original-equation verification. Cancellation remains cooperative:
it does not preempt arbitrary application callbacks. The session continues to
preserve its last committed state on cancellation, limits or failure.

For callers working directly with a CSR Jacobian:

```dart
import 'dart:typed_data';
import 'package:dart_csp/geometry.dart';

GeometryLinearStep solveLinearStep(
  SparseGeometryJacobian jacobian,
  Float64List residual,
  Float64List diagonal, {
  required double damping,
  bool Function()? shouldStop,
}) {
  return const SparseLdltGeometrySolver().solve(
    jacobian,
    residual,
    damping: damping,
    diagonal: diagonal,
    maxIterations: 3,
    relativeTolerance: 1e-8,
    shouldStop: shouldStop,
  );
}
```

## Cache ownership and invalidation

Symbolic caches are associated with each `SparseGeometryJacobian` object through
an `Expando`. Cached data includes immutable copies of every CSR row offset and
column index, the permutation, the filled column pattern and its index maps.
The complete CSR snapshots are compared before reuse, so changing an existing
array in place invalidates the old pattern just as replacing the structure
would. A different Jacobian object has its own association.

Only symbolic data is retained. Values, residuals, damping and diagonal metrics
are read afresh, and numeric factors, right-hand sides, correction vectors and
triangular-solve buffers belong to each call. Reentrant backend calls therefore
do not share writable numeric scratch. Keep caller-owned inputs stable during
each synchronous solve; changing numeric values between calls is supported.

Accepted patterns are reused only when their recorded entry/work requirements
fit the current caps. An expensive structural refusal is cached with the same
full CSR snapshots and the exact five effective cap settings, avoiding repeated ordering
and fill attempts at every nonlinear iteration. Changing any of those settings
or the CSR structure retries eligibility. The effective numeric cap includes
the adaptive multiplier, so changing that policy cannot reuse an incompatible
acceptance or refusal. Value-only edits retain a structural
refusal because they do not change the graph. Cheap preflight refusals are not
cached by copying a structure that already exceeds the selected input-work
limit.

This symbolic caching does not change compiled declaration snapshots, session
fork isolation, retained rank checks, or the application's ownership of residual
callback state. See [the parametric CAD guide](parametric-cad.md) for the wider
transactional boundary.

## Reading failure and measurement results

A direct structural refusal returns `GeometryLinearStatus.iterationLimit` with
zero iterations and no accepted step. Singular/nonpositive pivots, arithmetic
overflow, non-finite norms, or an explicit residual that remains too large can
produce `numericalFailure` or an exhausted iteration budget. Invalid vector
lengths, invalid current CSR structure, negative budgets/caps and invalid
tolerances reject the invocation with `ArgumentError`.

These outcomes describe the linear attempt, not the feasibility of the CAD
model. Adaptive fallback and the nonlinear solver's existing damping policy can
still find an acceptable subsequent step. Inspect the final session result and
physical residuals before using candidate coordinates.

The independent regressions cover raw duplicates/cancellation, structural
mutation, all five caps after caching, negative-cache retries, callback
reentrancy, shared direct/CG budgets, and a default-session solve/edit/rejection/
rollback sequence. Benchmark conclusions must additionally report completeness,
physical acceptance, source identity, tail behavior and any fallback cases.
The default cap limits deliberately leave some large dense-fill components on
CG. No guaranteed speedup, universal large-sketch convergence or interactive
latency bound follows from the backend's presence.

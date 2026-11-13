# Persistent geometric solving

Import `package:dart_csp/geometry.dart` (or the main library). This numerical path
solves required geometric equations near an existing configuration. The discrete
CSP remains available for combinatorial choices; interval solving retains its
separate bounds/search contract.

```dart
final b = GeometryBuilder();
final origin = b.point3('origin', Vec3.zero, fixed: true);
final axis = b.point3('axis', Vec3.unitX, fixed: true);
final point = b.point3('point', const Vec3(7, 2, 1));
final length = b.dimension('length', 5, lower: 0);
b.pointOnLine('on axis', point, GeometryLine(origin, axis));
b.distance('distance', origin, point, length);

final compiled = b.compile();
final session = compiled.createSession();
final first = session.solve();
if (!first.isSuccess) throw StateError(first.message ?? '${first.status}');
session.setParameterValues(length.id, [8]);
final edited = session.solve();
print(edited.values[point.id]); // approximately [8, 0, 0]
print(edited.localDegreesOfFreedom); // 0 at a regular solution
```

## Data and reuse

`GeometryParameterBlock` declares fixed/free values, bounds, tangent-coordinate
scales and a manifold. Fixed blocks are editable input dimensions; they do not
add optimization freedoms or connect otherwise independent free components.
`GeometryResidualBlock` declares exactly which blocks it depends on and emits
signed residual components. Analytic callbacks supply ambient Jacobian blocks;
`autoDiff` seeds derivatives only for coordinates local to that residual block.

Compilation snapshots the graph, builds connected components and sparse Jacobian
patterns, and removes fixed coordinates from the active solve. Each session owns
mutable coordinates and retained component workspaces. An unchanged component
reuses its validated state. Structural changes require a new compile; input
edits use `setParameterValues`. Captured callback inputs require explicit
`invalidateConstraint`; fixed input blocks are preferable.

## Numerical behavior

The solver uses controlled Levenberg-Marquardt steps. Small blocks use augmented
column-pivoted Householder QR; large blocks use preconditioned conjugate gradients
on the damped normal equations without assembling a dense global matrix. A
backend interface permits replacement. The sparse normal-equation path retains
normal-equation conditioning limits, so convergence and the original damped
system residual are checked explicitly.

Damping is isotropic in explicitly scaled tangent coordinates. Per-column
damping can accidentally allow excessive motion in weakly observed directions;
a regression covers radial circle dragging across units 1e-9, 1 and 1e9.

Objective scales affect numerical conditioning. They never weaken each required
equation's declared physical tolerance. A successful result reevaluates every
affected required constraint; an unsuccessful result is not committed. Local
nonconvergence, stalled steps and iteration limits do not prove infeasibility.

The builder uses one consistent length unit and radians. Three-component point
relations divide their component tolerance by sqrt(3), bounding the Euclidean
violation by the declared length tolerance. Zero-distance point relations should
use `coincidence` to expose all three equations. Degenerate lines or invalid
circle radii produce explicit evaluation failures rather than NaN success.

Norms and their automatic derivatives use scaled arithmetic, so very small
nonzero distances cannot pass a zero target merely because squaring underflows.
Direction normalization also avoids reciprocal-overflow intermediates.
`Dual.atan2` rejects the undefined origin and scales coordinate and derivative
pairs independently. These checks improve floating-point behavior; they do not
turn local numerical convergence into a global existence proof.

## Geometry and poses

`GeometryBuilder` supplies points, scalar dimensions, lines, planes, circles,
workplanes and rigid poses, plus coincidence, point incidence, distance, equal
length, parallel/perpendicular/signed-angle, circle tangency and assembly mates.
Quaternion poses use scalar-first `[w,x,y,z]` storage and three-dimensional local
rotation updates. `revoluteMate` leaves its joint-axis rotation free in a regular
grounded assembly. `rigidMate` constrains three noncollinear local anchors.

A signed angle with a supplied normal is a planar direction constraint: both
line directions must be perpendicular to the normal as well as meet the signed
angle. It does not constrain the locations of the lines to the same plane.
Pose construction validates both translation and quaternion blocks before
inserting either, so an invalid pose can be corrected and retried with its ID.

Coordinate edits choose the seed for a required-feasibility projection. Use
explicit preferences for dragging toward a desired coordinate while preserving
dimensions. Branch choice follows local continuation; very large changes can
cross basins and should be subdivided when branch continuity is essential.

## Required constraints and soft drag targets

```dart
final dragged = session.solve(
  preferences: [
    GeometryParameterTarget(
      parameterId: 'point',
      values: [1, 4, 1],
    ),
  ],
  preferenceOptions: const GeometryPreferenceOptions(maxIterations: 64),
);
print(dragged.preferenceReport?.status);
```

The solver establishes required feasibility first. It projects each affected
component's preference gradient into the hard Jacobian's nullspace, takes a
manifold-aware step, restores required feasibility and accepts the trial only if
every original required constraint passes and preference cost improves. A large
preference weight cannot purchase a violation of a required dimension.

Small components use QR projection; larger ones use checked matrix-free row-space
CG. Bounds and quaternion/product-manifold retractions remain active. Targets
have positive weights and coordinate scales with objective
`weight / 2 * sum(((value - target) / scale)^2)`. Quaternion targets choose the
equivalent sign closest to the feasible starting rotation; their objective is
quaternion chord distance, not an angle in radians.

`preferenceReport` exposes initial/final cost, maximum normalized target error,
iterations, accepted steps and feasibility projections. A fixed or unreachable
target can return hard geometry satisfied with preference `stationary` and a
nonzero target error. `stationary` is a local numerical outcome, not global
optimality or a proof that another branch cannot approach the target. Cancellation,
exhausted budgets and numerical failure retain the previous committed state.

`solveAsync` supports the same preference options and revision checks. A
`maxTangentStep` can bound individual drag steps. Applications that need branch
tracking across large movements should provide intermediate targets. Run
`example/geometric_drag.dart` for a circle drag checked against its independently
known closest point.

## Diagnostics and transactions

Inspect `status`, `constraintResiduals`, `components`, `stats`, and
`localDegreesOfFreedom`. Numerical rank is computed only below bounded size
limits; larger components report unavailable. Rank describes local equality
tangent mobility, not higher-order behavior at singularities or one-sided motion
at active inequality bounds. Locally dependent constraint IDs are diagnostic;
they are not automatic instructions to delete globally meaningful constraints.

`values` on a result is a candidate; only `isSuccess` means required constraints
passed. Session `committedValues` retains the last accepted state after failure,
including edited fixed inputs. `solveAsync` yields between component/nonlinear
steps and checks cancellation/deadlines and revision changes. A residual callback
or one linear-backend step remains synchronous. Stale results cannot overwrite
newer edits; arbitrary side effects inside callbacks cannot be rolled back.

## Validation and measurement

The geometric checkpoints pass 26 numerical, 10 primitive and 19 preference tests: independent
derivative/linear-system oracles, required-tolerance checks, sparse chains,
duplicate equations, quaternion motion, unit scaling, failed-edit rollback,
component reuse, circles, sketches, mates, and asynchronous revision handling.
Preference tests include independent closest-point/weighted-optimum checks,
hard constraints under a 1e20 soft weight, quaternion targets, a 160-parameter
sparse cluster, unit changes and repeated dragging. Platform parity runs use
the same tests rather than screenshots of rendered geometry.

`dart run benchmark/geometry.dart` compares cold build/compile/solve and repeated
one-radius edits for 100 independent 3D circles, with independent radius/plane
validation after every result. A Dart 3.14.0 native development run measured:

| Path | p50 (us) | p95 (us) | Solved / reused components |
|---|---:|---:|---:|
| Cold build + compile + solve | 8,328 | 14,107 | 100 / 0 |
| One-radius edit + solve | 450 | 1,538 | 1 / 99 |

There were three warm-up pairs and 25 measured pairs in alternating order.
Hardware was not pinned. These numbers compare two paths in this implementation;
they do not establish a speedup over another solver, browser performance, or
arbitrary tightly coupled assemblies. Work counters demonstrate actual reuse.

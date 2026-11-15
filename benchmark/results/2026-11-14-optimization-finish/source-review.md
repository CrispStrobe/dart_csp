# Independent source review of the final optimization candidates

Reviewed commit: `120b6177bd542910dcd4bab82bc0b9920e9fbf2e`.
This review reads source, tests and prior validation records. It does not run
new tests, builds or benchmarks, and it makes no independent speedup claim.

## Result

No correctness blocker was found in either active candidate. Both changes are
narrow, preserve numerical acceptance and callback boundaries, and have useful
behavioral regression coverage. Retention must still follow the completed
bounded measurements, including adverse rows and process order. The earlier
argument-placeholder and QR-permutation experiments are absent from the active
source despite their histories being preserved.

The current `lib` tree is `e5862443488e1b1378f084d8774236a16eaac5b8` and the
`test` tree is `b0fae52c00e64741ea8b0202bea28c2f2d2617e1`. Both exactly match
the corresponding trees at saved passing validation commit `545a1ab`.

## Fused conjugate-gradient reductions

Commit `ad8d23704e50c1bf41412f086e66de4a87bfb21b` changes only four
reductions in `SparseCgGeometrySolver.solve`, in
`lib/src/geometry/numeric.dart`. Current lines 255–264, 275–278, 307–312 and
316–319 fuse the initial `r dot z`, `p dot A p`, restart `r dot z`, and next
`r dot z` into preceding elementwise passes.

The former `geometryDot` (lines 26–31) and each replacement start at positive
zero, traverse ascending indices, multiply operands in the same order and
perform the same sequential accumulation. Each product reads the typed-array
element after its assignment. Arrays are separately owned within the solve;
there is no intervening callback or public observation of the old pass
boundary. Numerical checks, the original-system residual verification,
restart condition, stopping polls, budgets and status precedence are unchanged.
An intermediate nonfinite initial sum can now occur before a later invalid
preconditioner is found, but that private scalar is not returned and floating
arithmetic does not throw; the same failure result takes precedence.

The four tests in `test/geometry_cg_test.dart` use an independent dense
original-equation oracle for mixed/duplicate/empty CSR rows and nonuniform
damping, cancellation at every iteration boundary, nested solves, retained
snapshots and nonfinite-dot status precedence. They do not establish that the
true-residual restart branch executes; that is a coverage limit, not a newly
identified defect. The reduction-order argument applies to the restart site.

The intended benefit is fewer vector traversals on actual CG paths. QR-only
and sparse-direct paths have no intended arithmetic reduction. Unfavorable
timings in those paths remain real observations even if code-layout or runtime
variation is a plausible explanation.

## Default Euclidean contraction

Commit `1358300253e173ba8efe64cd062e6e0cba7882a4`, corrected by
`e0d77a775714a4bd66b45a90e366ea68bc37db59`, adds a private final subclass
for library-created default manifolds and specializes their ambient-to-tangent
contraction in `lib/src/geometry/solver.dart`.

Only instances of `_DefaultEuclideanGeometryManifold` (lines 50–52, 167,
1856–1857) take the shortcut. A public Euclidean manifold, user subclass,
product or quaternion follows the old path. The type check uses `is`, so an
overridden `runtimeType` cannot impersonate the private type. Defaults retain
their Euclidean `is` relationship, but their exact runtime type is observably
different; this is an already documented API-facing detail.

The first tangent column retains the full reduction (lines 1860–1868). Any NaN
or infinity in that ambient row therefore still produces a nonfinite first
column before this parameter row is written, preserving the old retained
backend-buffer failure behavior. Later columns add the finite ambient value
to positive zero, preserving the old identity reduction's zero sign. Scaling,
overflow checks and writes remain in their old order (lines 1870–1878).

Default tangent matrices remain allocated and populated. The optimization
does not skip `plusJacobian` calls (lines 1804–1807), move cancellation points,
change ownership or change custom tangent maps observed by callbacks. No
public callback receives the private default tangent buffer. The 15 focused
tests cover scaling/zero signs, dynamic custom maps, type impersonation,
retained custom outputs, nonfinite ambient and tangent entries, retained
backend failure writes, overflow, AD, forks, cancellation and recovery.
The recovery test correctly reapplies the fixed-target edit after cancellation.

The intended shortcut helps dimensions greater than one. For a default block
of dimension `a`, contraction visits `a + (a - 1)` ambient terms instead of
`a * a`, while keeping the original full first column. Scalar default blocks
still do their original one-column reduction and incur the identity/branch
checks. Scalar-engine timings therefore matter as adverse workload controls.

## Preserved but inactive experiments

The unmeasured `088df75a334296b6c5d26940cdeb431d121bc0d9` placeholder candidate
is not active: lines 1142–1145 still allocate the original ambient-sized
coordinate buffers for every layout argument. Its prior behavioral tests and
review can remain as historical evidence; ancestry inclusion did not promote it.

The rejected `748febd527cda9eeb611cdf2dcba3c9c3af388ec` QR-permutation
candidate is also absent: `numeric.dart:742` still uses
`Int32List.fromList(List<int>.generate(n, (i) => i))`. Current `numeric.dart`
differs from `080e0fe` solely by the four CG fusions. There is no hidden QR
change in the measured active source.

## Source mapping for the final decision

| Retained choice | `numeric.dart` | `solver.dart` |
| --- | --- | --- |
| Both candidates | Current reviewed file | Current reviewed file |
| CG only | Current reviewed file | File at `46288eb` |
| Default contraction only | File at `080e0fe` | Current reviewed file |
| Neither candidate | File at `080e0fe` | File at `46288eb` |

The packed source at `4325386` and `080e0fe` has identical production/test
trees for this purpose. Preserve both meaningful regression test files and
their portable test-list registrations regardless of the performance decision.
Avoid reverting the whole candidate commits, which also contain useful tests,
documentation and CI registrations. A new retained combination needs matching
correctness evidence and the bounded qualification required by the existing
plan before claims about that combination.

## Reviewed file identities

| File | SHA-256 |
| --- | --- |
| `lib/src/geometry/numeric.dart` | `bce973eaf51c3bac3f2aa1774366e15d88a26e96f97516402f7a30499e2f0a49` |
| `lib/src/geometry/solver.dart` | `e4ed2d1ef84279c98b409c4464c3deacb2febf1381ba4714af465ff3d20cd938` |
| `test/geometry_cg_test.dart` | `d8608e1e3fbbfde615faf9ffa815eefada405b6c6a43824c1b37dd745225bc2b` |
| `test/geometry_default_manifold_test.dart` | `0565c35d7d52245426f19424290ece337d8e61ffb29e8ec37cbebbd6e2a2cc94` |

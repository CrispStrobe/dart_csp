# Optimization completion — 2026-11-14

## Recovery checkpoint

This branch starts at `eb8a9df4454fe17a83d97900b35bf4e607e291b2` on
`perf/cg-resume-2026-11-14`, preserving the original main
`46288eb23f04c2a2f2210088fe568285bea6114f`, the provisional CG fusion
`ad8d23704e50c1bf41412f086e66de4a87bfb21b`, both saved comparison rounds,
frozen source/build inputs, reviews and prior correctness evidence.

The previous local measurement cohort is incomplete. Its two saved rounds
have accepted geometry and a repeatable warm coupled-500 2D improvement,
but several controls vary substantially. Neither universal nonregression nor
a final CG retention decision is established.

The current local workspace filled during exact Dart runtime recovery.
Subsequent sandbox processes cannot start (no space left on device), including
removal of the SDK ZIP created by this task. The sandbox policy disallows
escalated cleanup; desktop runtime is unavailable. No user source was deleted
or changed locally. Validation will therefore run on a fresh GitHub Actions
host, if repository workflow execution is available.

## Bounded execution plan

1. Recover pinned Dart 3.14.0 and the exact committed dependency lock.
2. Rebuild before/after snapshots and finish all compilation before timing.
3. Run four fresh balanced rounds on one Actions host using the existing
   physical oracle, identical fixtures/adapters, sequential processes, CPU
   affinity, bounded timeouts, eight warmups and 21 measured operations.
   Do not combine this host's timings with the previous host's observations.
4. Preserve exact raw evidence and a concise machine-readable summary after
   each completed round, pushing incrementally to this remote branch.
5. Review repeated adverse cases with bounded identical-executable controls.
   Make an explicit retention decision; do not tune solver thresholds or
   tolerances to these fixtures.
6. Independently assess structural work/allocation elimination, retaining only
   changes with meaningful semantic regressions and measured support.
7. Run native, JavaScript and WebAssembly correctness gates for the retained
   source. Save source, validation, favorable and adverse measurements, final
   decisions and remaining limits remotely before stopping.

## Constraints

Keep physical acceptance, tolerances, resource budgets, solver selection,
custom-manifold behavior, cancellation and result ownership unchanged.
The already reviewed argument-placeholder candidate at
`088df75a334296b6c5d26940cdeb431d121bc0d9` remains a separate candidate.
Prepared binaries and source must have provenance; source timing claims must
identify the measured commit. Workflow artifacts complement, rather than
replace, durable branch checkpoints.

## Default-manifold contraction candidate

The candidate marks only library-created default Euclidean manifolds with a
private final subtype. Their ambient-to-tangent multiplication is an identity,
so each output coefficient reads its corresponding ambient derivative instead
of reducing a full matrix column. Adding to positive zero preserves the old
reduction's signed-zero result. Scaling order and finite checks remain.

Explicit public Euclidean instances, subclasses, products and other custom
manifolds retain the existing matrix product. All tangent-map buffers and
callbacks remain. This deliberately avoids cached generic identity detection:
a custom callback can retain and later mutate its output buffer during residual
evaluation, and the old path observes that mutation.

The default object's runtime type becomes a private Euclidean subtype; its
public interface and Euclidean subtype relationship remain. No exact runtime
type guarantee was found in the API. The focused regressions cover the matrix
sent to a recording backend, signed zero/scaling, changing custom maps, retained
buffer mutation, runtimeType impersonation, nonfinite values, overflow and
automatic-differentiation fork/cancellation/recovery.

This source checkpoint is unvalidated until its remote workflow completes.

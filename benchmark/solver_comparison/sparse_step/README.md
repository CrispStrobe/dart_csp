# Dart sparse direct linear-step experiment

This benchmark-only lane keeps the existing `dart_2d_analytic` geometry and nonlinear
session engine. It changes only the large `GeometryLinearSolver` backend. Production
`lib/` is unchanged. This isolates a practical next investment from comparisons
between entirely different solvers.

## Exact scope

The input CSR Jacobian and residual already contain Dart's row normalization and
scaled tangent coordinates. The backend solves exactly

```
(J'J + damping * diag(diagonal)) step = -J' residual
```

The passed diagonal is preserved, including the outer solver's isotropic metric.
There is no extra damping, weighting, variable scaling, rank cutoff, or fallback
to another nonlinear optimizer. Up to two iterative refinement solves reuse the
same factorization and the same equation. Eigen success alone cannot establish
convergence: the shim and an independent Dart computation both check the original
system's relative residual against the supplied tolerance. The check in Dart is
included in timing.

At the existing default threshold (at most 64 columns and 262144 augmented dense
entries), the existing dense QR implementation remains in use. Larger components
use Eigen `SimplicialLDLT` with AMD ordering. The normal-matrix pattern and symbolic
factorization are prepared on the first linear call for each Jacobian and reused
as its numerical values change. Cold operations discard every previous native
workspace before the operation timer; allocation and symbolic analysis of the new
workspace take place inside its first timed linear solve. Warm operations retain
the workspace across edits. FFI input/output copies are timed and counted.
The cache relies on compiled Jacobians' fixed structural pattern: mutating a
Jacobian object's public `rowOffsets` or `columnIndices` in place is unsupported
by this benchmark adapter. Its changing `values` are copied on every call.

The existing Dart implementation continues to own residuals and derivatives,
parameter manifolds and scales, trust-region acceptance and damping updates,
hard feasibility and physical tolerances, diagnostic rank/cache logic, preference
projection, revision handling, and transactional coordinate commits. The common
benchmark oracle continues to enforce fixed points and branch orientation.
Replacing this interface does not change the separate nullspace-projection path
or add large-model rank diagnostics.

This is a native experiment, not evidence of browser portability. A factorization
is synchronous: cancellation is polled before and after the native call, but cannot
interrupt Eigen while it is factoring. The benchmark process deadline remains the
outer bound. `linear_iterations` counts dense QR pivots or a sparse factorization
plus refinement solves; it must not be compared as if it were a CG iteration count.

## Reproduce

Use the same Eigen source as the Ceres benchmark: version 3.4.0 at commit
`3147391d946bb4b6c68edd901f2add6ac1f31f8c`. `build.sh` checks the actual source HEAD and
requires a clean checkout before invoking CMake. `EIGEN_MPL2_ONLY` is defined, and
only Eigen's sparse Cholesky/ordering implementation is included. No SuiteSparse
or METIS dependency is used.

```sh
EIGEN_SOURCE_DIR=/absolute/path/to/eigen-src DART=/absolute/path/to/dart \
  bash benchmark/solver_comparison/sparse_step/build.sh
dart run benchmark/solver_comparison/sparse_step/verify_linear.dart \
  benchmark/solver_comparison/sparse_step/build/libdart_csp_sparse_step.so
benchmark/solver_comparison/sparse_step/build/dart-sparse-adapter REQUEST.json
```

Requests follow the shared schema with engine `dart_2d_analytic_sparse_direct`.
The host reuses `DartComparisonRunner` with its optional linear-solver injection;
other Dart hosts retain their existing default. The shared library defaults to
the executable's directory; a second positional argument or
`DART_CSP_SPARSE_STEP_LIBRARY` can override it.

`verify_linear.dart` cross-checks the returned step and independent residual against
both existing dense QR and CG on overdetermined, damped underdetermined, nonuniform
metric, and sparse chain systems. It also covers duplicate CSR columns, symbolic
reuse across a numerical zero, cold reset, singular undamped input, invalid/nonfinite
input, zero iteration budget, and cancellation. Large geometric acceptance must
also be checked by the common Python oracle; the linear checks do not substitute
for that.

The completed qualification is recorded in `linear_verification.jsonl` (15 checks
passed) and `physical_verification.json` (32 requests, 96 operations, zero adapter
errors or oracle disagreements). Both direct and freshly rebuilt stock hosts were
checked on the small smoke corpus. The direct backend additionally accepted every
500- and 2000-coordinate ladder and triangle-free Laman operation in cold and warm
modes. No formal latency claims are derived from these correctness runs, and their
timings are deliberately omitted. `build-manifest.json` records both AOT binaries,
the shared library, source hashes, verified Eigen pin, and compiler configuration.

```sh
python3 benchmark/solver_comparison/sparse_step/verify_geometry.py \
  > benchmark/solver_comparison/sparse_step/physical_verification.json
DART=/absolute/path/to/dart CMAKE=/absolute/path/to/cmake \
  python3 benchmark/solver_comparison/sparse_step/write_manifest.py \
  > benchmark/solver_comparison/sparse_step/build-manifest.json
```

The geometry verification also requires the stock AOT host built from the same
shared adapter core at `build/solver_comparison/dart-adapter-control`; preserve the
original baseline binary when creating this control.

Per-operation output includes symbolic analyses, numeric factorizations/refinement
solves, timed FFI bytes copied, original-system relative residuals, normal-matrix
nonzeros, and failed native linear steps. A failed linear solve is returned to
Dart's existing damping/status policy and is never silently relabeled as success.

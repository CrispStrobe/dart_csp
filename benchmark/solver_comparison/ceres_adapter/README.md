# Ceres native geometry comparison adapter

This adapter executes the common physical 2D fixture protocol against real Ceres
Solver. It implements point distance, horizontal, vertical and coincident
constraints as native C++ analytic residuals. It is a focused numerical/session
comparison, not a replacement implementation of Dart CSP's CAD diagnostics,
transactions, soft-target dragging or 3D feature set.

## Build and run

Run `bash benchmark/solver_comparison/ceres_adapter/build.sh` from the repository.
The script installs CMake, fetches pinned sources and puts all downloaded/build
files under the sibling `upstream/toolchains` directory. Override that location
with `CERES_BENCH_TOOLCHAINS` and build parallelism with `CERES_BENCH_JOBS`.
No system package installation or elevated permissions are needed.
The build writes `ceres-adapter-build/build-manifest.json` with actual compiler
and CMake versions, dependency commits, source hashes, binary SHA-256 and settings.
Before compilation and again before writing the manifest, it checks every pinned
dependency for tracked changes, untracked/ignored files and changed submodules.
It also compares every tracked source blob to the pinned Git object, so a local
`skip-worktree`/`assume-unchanged` flag cannot hide a source edit. Each dependency
has a content SHA-256 and tracked-file count in the new manifest. Builds and caches
must stay outside those source checkouts.

The historical committed `build-manifest.json` predates these checks. Its original
dependency commit IDs remain useful, but they do not retrospectively establish
clean dependency bytes. That original record is preserved without alteration.

The resulting `ceres-adapter-build/ceres_geometry_adapter REQUEST.json` writes
one flushed JSON object per operation to standard output. Request parsing is
outside timing; malformed requests fail on standard error with exit code 2.

## Exact dependency pins

| Dependency | Version label | Git commit |
| --- | --- | --- |
| Ceres | Header version 2.3.0, reviewed source snapshot | `e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72` |
| Eigen | 3.4.0 | `3147391d946bb4b6c68edd901f2add6ac1f31f8c` |
| Abseil | 20250127, Ceres's own submodule | `9ac7062b1860d895fb5a8cbf58c3e9ef8f674b5f` |
| nlohmann/json | 3.12.0 | `55f93686c01528224f448c19128836e7df245f72` |
| CMake | Python wheel 4.2.3 | Version pinned by the build script |

Ceres is built static in Release mode, with Eigen sparse support enabled and
SuiteSparse, Eigen METIS, LAPACK, CUDA/cuDSS, examples, tests, benchmarks and
fixed-size Schur specializations disabled. `EIGEN_MPL2_ONLY` is defined for Ceres
and the adapter. No fast-math or native-CPU optimization flag is added by this
adapter. Dependency licenses remain those of their respective projects; the
Eigen configuration deliberately excludes its non-MPL2 modules.

## Solver configuration

- One Ceres worker thread, double precision, trust-region Levenberg–Marquardt.
- At most 128 nonconstant scalar coordinates: Eigen `DENSE_QR`.
- Above 128: Eigen `SPARSE_NORMAL_CHOLESKY`.
- The threshold applies to all fixtures and is emitted through the chosen
  solver metadata. Fixed point parameters are constant two-coordinate blocks;
  they are excluded from `active_coordinates` and are not residual equations.
- Maximum 200 solver iterations by default, overridable by request
  `max_iterations`. No fixture-specific solver tuning is performed.
- Ceres's function, parameter and gradient tolerances are set to zero. A native
  iteration callback with `update_state_every_iteration=true` terminates
  successfully as soon as physical distance/H/V/coincidence errors and fixed
  point movement are within the exact requested tolerance, with the requested
  triangle orientations intact. The callback's work is included in `solve_ns`.
  Ceres can still terminate itself at an exact stationary point or on failure;
  that is not treated as proof of physical feasibility.
- The adapter does not split connected components externally. Ceres receives
  the complete sparse residual problem and chooses its normal ordering.

## Timing and state semantics

For operation `i` from `-warmups` through `samples - 1`, the adapter uses edit
`(i + warmups) % edits.length`. Negative indices are emitted as warmups.

`build_ns` includes model construction or target updates, restoration after a
rejected previous operation, and per-solve option/callback construction.
`solve_ns` wraps the real `ceres::Solve` call, including its physical stopping
callback. `elapsed_ns` starts before construction/update and ends after copying
out the returned coordinates. Input JSON parsing, final independent acceptance,
last-accepted snapshot bookkeeping and output JSON encoding are excluded.
Cold model destruction is included in the following cold construction interval.

In **cold** mode every operation starts from the supplied fixture points and a
new `ceres::Problem`. In **warm** mode the native `Problem`, residual objects,
parameter storage and mutable distance targets are retained. The first operation
constructs it; later operations report `model_reused=true`. Coordinates start
from the previous accepted solution. A rejected solve is emitted honestly and
its coordinates are restored to the last accepted snapshot before the next
operation. Ceres may redo its own preprocessing/factorization inside each Solve;
`model_reused` does not claim those internals are cached.

## Success and correctness

`reported_success` means native Ceres termination was `CONVERGENCE` or
`USER_SUCCESS`; the exact enum is in `status`. `native_usable` reports Ceres's
separate `IsSolutionUsable()` result. Neither substitutes for `accepted`, which
requires finite coordinates, each requested physical constraint, fixed anchors
and all orientation signs to pass. An inconsistent sketch may legitimately have
native convergence to a least-squares minimum while `accepted=false`.

The root Python physical oracle checks the emitted coordinates again. Internal
residual squared cost is never used as the cross-engine correctness metric.
Coincidence acceptance uses Euclidean point distance, not separate axis bounds.
No tolerance floor is applied, so scaled requests retain their passed physical
tolerance.

`iterations` counts Ceres iteration records, including its initial record when
present; it is descriptive rather than an equal-work unit across engines.
`physical_callback_checks`, chosen linear solver, dependency commits and native
termination message are emitted to make the configuration auditable.

At zero length, a distance residual has no ordinary derivative. The adapter uses
a zero subgradient there rather than NaN; a nonzero requested length remains
physically unsatisfied and cannot be accepted merely because Ceres finds that
stationary point. No hidden seed perturbation or retry is performed.

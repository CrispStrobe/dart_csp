# Pinned native Rust adapters

This executable invokes the upstream implementations, not reimplementations of
their algorithms. Cargo dependencies pin EZPZ 0.2.29 at
`915882cc731da31042ce494c89b10334ee57837a` and NeoSCAD sketch-solver 0.1.0 at
`87ad5bab1d89c1723c1ba4566f27555209a6fe4a`. The Cargo lockfile records transitive
dependencies. Neither upstream source tree is modified.

```sh
cargo build --release --locked
./target/release/geometry-rust-adapter REQUEST.json
```

The schema-v1 request selects `engine` (`ezpz`, `ezpz_analysis` or `neoscad`), `mode` (`cold` or
`warm`), a planar fixture, edits, warmups, sample count and physical tolerance.
The executable writes flushed JSON Lines: one metadata record, then one record
for every warmup and measured operation. It supports distance, horizontal,
vertical and coincidence constraints, fixed points, and signed triangle
orientations. Every edit has one value per constraint; values for nondimensional
relations are ignored.

## Timing and state

Every timer uses Rust's monotonic `Instant`. `elapsed_ns` starts before native
model construction and ends after native solving and coordinate extraction.
`build_ns` covers public native model preparation; `solve_ns` covers the native
solve API, including any internal graph/factorization preparation. JSON parsing,
serialization, independent acceptance checking and copying the accepted warm
seed are outside the timer. JSON is flushed after every sample so a process
timeout preserves earlier observations.

Both upstream public APIs reconstruct a solve. `warm` feeds the last accepted
coordinates into the next native model, while `cold` always uses the fixture's
original coordinates. Neither mode claims persistent native model reuse:
`model_reused` is always false. Fixed-point equations always target the original
fixture positions. Failed physical/branch checks do not replace the warm seed.

`active_coordinates` records the native numerical unknown count. Both solvers
retain fixed points as unknowns constrained by equations; this count therefore
includes their coordinates. `geometric_free_coordinates` separately records the
coordinates of points not marked fixed in the shared fixture.

## Native behavior versus common acceptance

`accepted` requires finite coordinates, Euclidean fixed/coincident point error
and each other physical constraint error at or below the requested tolerance,
and every required orientation sign. A native API error is always rejected;
otherwise acceptance is independent of native numerical status. Root's
Python checker independently repeats those checks against the serialized output.

EZPZ uses its default 35-iteration limit and convergence tolerance set to the
requested tolerance divided by sqrt(2), so componentwise coordinate residuals
can meet the common Euclidean tolerance. Its native `is_satisfied` threshold
remains the upstream fixed 1e-4; `reported_success` additionally requires
`converged`. The adapter calls `solve`, not `solve_analysis`, so it does not add
freedom analysis. The separate `ezpz_analysis` engine calls `solve_analysis`,
including dense QR freedom analysis, and reports the number of underconstrained
coordinates exposed by that API. This is not the number of independent degrees
of freedom. Degeneracy warnings are recorded separately.

NeoSCAD uses its native default `SolveOptions` (100 iterations per phase, plus
the upstream continuation procedure). Its native tolerance is fixed by upstream
at 1e-10 times sketch size and cannot be overridden through the public API.
`reported_success` is `Status::Solved`. Rank, conflict, continuation and branch
processing included in its public solve remain included in `solve_ns`.

These different default algorithms and diagnostics are intentional and recorded
in metadata. This adapter compares public, integration-ready behavior; it does
not claim identical inner numerical work across solvers.

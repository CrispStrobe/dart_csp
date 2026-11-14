# Geometric solver comparison and investment plan

Date: 2026-11-14.

Status: historical source assessment and historical Dart measurement audit.
The execution and recovery findings are now recorded in
[geometric-solver-comparison-results.md](geometric-solver-comparison-results.md).
References to "current main" below describe the original `5dc27dc` review
snapshot, not the later integrated main. The original assessment remains
separate from measured cross-solver evidence and its recovery limits.

## Decision

Keep `dart_csp` as the application baseline. Solvent is the most interesting
challenger for additional CAD functionality; Ceres is the most useful numerical
comparison for larger coupled systems. NeoSCAD and EZPZ merit qualification for
specific 2D workloads. No retrieved measurements establish a cross-solver speed
winner on our workload.

The comparison must use our current geometric implementation, not only the
finite-domain CSP engine. Our library already has persistent numerical sessions,
required-versus-soft constraints, 3D geometry, and transactional CAD integration.
The discrete, interval, and geometric paths have distinct contracts; none of
these candidates replaces all three.

## Frozen source snapshots

| Implementation | Reviewed commit | Version/scope |
|---|---|---|
| dart_csp | `5dc27dc0b297683d47e94ade2b4ca22ed530d429` | Package manifest 2.4.0; current main at review |
| KittyCAD/ezpz | `915882cc731da31042ce494c89b10334ee57837a` | 0.2.29 |
| neoscad/sketch-solver | `87ad5bab1d89c1723c1ba4566f27555209a6fe4a` | 0.1.0 |
| bmander/geomsolver | `64bad08b2f126f6be495f6647c180ae703e0963e` | gcs-solve 0.1.0; broader CAD stack |
| ceres-solver/ceres-solver | `e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72` | Development source with 2.3.0 header; version history marks it unreleased |

The assessment used repository source, benchmark implementations, test
implementations, and upstream CI. The initial analysis environment did not have
Dart, Rust, CMake, or a configured Ceres build. It did execute a Python reanalysis
of committed Dart measurements and inspect the EZPZ workload generator. No
fresh cross-solver timing was performed during that assessment.

## Relative fit

| Candidate | Most valuable addition | Main qualification issue | Recommended role |
|---|---|---|---|
| Solvent / geomsolver | Geometric decomposition, persisted solution branches, richer curves, more elaborate diagnostics | Broader integration surface; different drag and acceptance semantics | First functional integration experiment |
| Ceres | Numerical methods and sparse linear algebra for difficult connected systems | Geometric, interaction, and transaction contract stays ours | Numerical performance control |
| NeoSCAD sketch-solver | Deterministic replay, dimensional continuation, exactification, compact sketch diagnostics | Dense algebra and reconstruction on every solve; no persistent drag/session API | 2D correctness and behavior reference |
| EZPZ | Handwritten 2D equations, arc coverage, sparse direct factorization | Public solves reconstruct the model; wrapper and tolerance semantics need qualification | Targeted 2D performance challenger |

## Our existing implementation

The geometric path compiles dependency graphs and connected components, retains
numerical workspaces, and accepts analytic Jacobians or automatic differentiation.
Small systems use controlled Levenberg-Marquardt with augmented column-pivoted
Householder QR; larger systems use matrix-free preconditioned conjugate gradients
on damped normal equations. Sessions support repeated edits, isolated candidate
forks, cancellation/revision checks, and failed-edit rollback. [D1] [D2] [D3]

Dragging establishes required feasibility first, projects the preference gradient
into the hard Jacobian's nullspace, takes a step, restores feasibility, and
accepts only if every required constraint still passes and preference cost
improves. A large drag weight cannot purchase a required-dimension violation.
The geometry layer includes workplanes, quaternion poses, and rigid/revolute
mates. These are application semantics a replacement must preserve. [D1] [D4]

### Concrete limitations

| Limitation | Evidence and consequence |
|---|---|
| Planar points use extra coordinates/equations | `workplanePoint` uses a free 3D point and one plane equation. Native 2D libraries can represent the same sketch with less work. This is the builder's representation, not a generic-solver limitation. |
| Convenience primitives use AD | `GeometryBuilder._add` creates autodiff residuals. Analytic derivatives may reduce evaluation/allocation costs; the core supports them but the convenience layer does not exploit them. |
| Block-level sparsity includes scalar zeros | Every dependency's tangent coordinates are represented in each residual row of its block. Sparse does not mean identical scalar sparsity to another solver. |
| Large path has limited preconditioning | Dense QR defaults to at most 64 columns and 262,144 augmented entries; beyond that the backend is diagonal-preconditioned CG. There is no automatic sparse-direct fallback. |
| Numerical rank diagnostics are bounded | Default cap is 96 tangent columns and 262,144 entries. Larger components report rank/DOF unavailable. Dependencies are local, not global infeasibility certificates. |
| Exact-Jacobian reuse is narrow | Rank caches require identical numeric Jacobian entries and rank options. Linear input edits benefit; nonlinear dragging normally changes the Jacobian. |
| Reused components still have housekeeping | Runs copy pending coordinates, visit components, construct result snapshots, and copy committed state. Complete edit cost does not scale solely with the changed component. |
| CAD candidates revalidate geometry | CAD adapters revalidate all components. Compare complete fork/regenerate/validate operations rather than transferring raw-session reuse counts to CAD. |
| Sketch vocabulary is incomplete | No dedicated arc, arc-span/length, point-on-arc, spline, symmetry, midpoint, or internal-circle-tangency builder helper. These are missing validated recipes, not mathematical impossibilities. |

Sources: [D1] [D2] [D3] [D4].

The strongest reasons to retain Dart are integration and its explicit correctness
contract. Large connected nonlinear sketch performance remains an open question.

## Historical Dart performance: independently reanalysed

Current main's library tree is
`ef99105a9d7787925ae245cf10adbd040df1ad62`, identical to the measured retained
source `acc01d77156559a8854b22b6c03cd10083cc36f8`.

The reanalysis reconciled 108 saved process reports, 72 summary rows, and 432
process-level p50/p95 pairs. It recomputed the sample-based percentiles available
in 348 arrays containing 8,700 observations. All checks passed. Legacy circle,
plate, and instance reports have process percentiles without individual timing
arrays; those percentiles can be reconciled but cannot be reconstructed from
absent samples. This was measurement reanalysis, not solver execution. [D5] [D6] [D7]

### Recorded Dart AOT results

Times are milliseconds per complete operation. Each table entry is the median
of three processes' respective percentile values, not a pooled percentile.

| Fixture | Operation | Median process p50 | Median process p95 |
|---|---|---:|---:|
| 100 independent circles | Cold build, compile, solve | 2.080 | 6.959 |
| 100 independent circles | One-radius edit and solve | 0.171 | 0.250 |
| Coupled 24-point system, 72 active coordinates | Cold build, compile, solve | 1.357 | 1.688 |
| Same coupled system | Retained pitch edit and solve | 0.872 | 1.032 |
| Nonlinear four-bar, six active coordinates | Cold build, compile, solve | 0.099 | 0.197 |
| Same nonlinear four-bar | Retained angle edit and solve | 0.073 | 0.202 |
| Four-bar assembly with actual solids | Retained angle edit through CAD regeneration | 0.274 | 0.362 |

Recorded environment: Dart 3.14.0, Linux x64, AMD EPYC 9V74, shared/unpinned
container with nine available logical CPUs. These cases use three fresh
processes and 25 measured operations per process after warmup. [D5] [D6]

### Coverage limits

- The circle edit solves one component and reuses 99.
- The 72-coordinate coupled fixture is linear and its Jacobian is unchanged.
- The nonlinear linkage has only six active tangent coordinates; timed input
  angles alternate 0.6/0.9 radians and explicitly exclude near-toggle stress.
- Therefore the evidence does not establish large + coupled + nonlinear
  throughput or dependable p99 drag latency.
- Use external wall-clock timing. Internal solver elapsed statistics omit some
  setup/snapshot/commit work.
- The recorded hardware was not dedicated or pinned; unchanged controls moved.

Fixture sources: [D8] [D9] [D10].

Main's CI run 43516383046 completed successfully, including targeted Chrome
tests for geometry preferences/parametric CAD and the portable dart2js/dart2wasm
corpus. The scheduled full-browser-suite job was skipped in that run. This is
functional validation, not a browser latency measurement. [D11] [D12]

## Solvent / geomsolver

### What it adds

The language is optional: `gcs-solve` owns model and numerical functionality,
whereas `gcs-core` owns parsing/elaboration. Entity/constraint records can be
constructed and solved without a Solvent source document. The solver still
depends on its CAD kernel; this is a broader dependency than a tiny equation
library. [S1] [S2]

Distinctive implemented capabilities:

1. **Geometric decomposition/replay.** Build a cluster-solving plan once;
   suitable triangle merges use closed forms, other merges use small numerical
   solves; verify and fall back to the general solver when necessary.
2. **Explicit branch choices.** Stable construction identities and recorded
   chirality support save/load, replay, and branch changes.
3. **Richer curves.** B-splines, Bezier curves, and rational curves with fixed
   weights; contact introduces a curve-parameter unknown and uses local support.
   Ellipses also exist as language-defined parametric curves, not a dedicated
   primitive to assume is already in a record adapter.
4. **Diagnosis beyond local rank alone.** Structural matching, numerical checks,
   optional witness analysis, and some second-order checks for apparent
   infinitesimal freedoms.
5. **Bounded alternative enumeration.** Homotopy on small merge cores can expose
   alternative solutions. Defaults limit paths/steps; this is not arbitrary
   global solution enumeration. [S3] [S4] [S5] [S6]

The default numerical method is Powell DogLeg, with LM available. Dense
minimum-norm least squares covers smaller systems (120 free parameters in the
reviewed implementation); larger systems use regularized sparse normal equations
with direct LDL-transpose factorization. Compiled CSR structure is reused. [S7] [S8]

### Qualification requirements

- Dragging uses a soft pull followed by hard-only polish, not our nullspace
  preference method. It subdivides moves and guards orientations, but can accept
  and flag an unavoidable flip after exhausting the bisection budget. [S9]
- Acceptance tolerances concern scaled equation residuals; independently verify
  physical distances, angles, and branch policy. Distinguish numerical
  acceptance from settled convergence. [S10]
- Automatic dense diagnostic cross-checks default to 300 parameters; the sparse
  numerical solve itself does not report a rank. Conflict filtering among
  suspects is not an algebraic global infeasibility proof. [S5] [S7]
- One flat C ABI supports native cdylib and Wasm, with numeric buffers on frequent
  operations and JSON for variable-length reports. Dart integration still needs
  ownership, identity, status, and transaction adapters. [S11]
- Source records native panic recovery and Wasm abort behavior; recovery at the
  application boundary needs qualification. [S11]

Historical published browser medians include 1.77 ms DogLeg and 1.21 ms drag for
an 800-parameter truss. The page explicitly says measurements were recorded as
stages landed and are not maintained. Hardware/browser and timing boundaries do
not match our measurements. Do not divide those numbers by Dart's. [S8]

**Verdict:** first functional challenger for decomposition, branches, and curves.
Retain our application contract while qualifying its lower-level integration.

## NeoSCAD sketch-solver

Implemented 2D vocabulary includes points, lines, circles, arcs, dimensions,
tangency, symmetry, and sketch-oriented diagnostics. Its distinctive approach
combines drawing cleanup, dimensional continuation, and exactification of
coordinates made equal by equations. [N1] [N2]

Analytic gradients feed dense QR of the augmented LM system. This is a sensible
small-sketch formulation, but individual large connected components have dense
factorization cost. Every `Sketch::solve_with` builds a new Solver. A host can
reconstruct a sketch using last coordinates as guesses, but the public API does
not provide persistent numerical workspaces or a hard/soft drag session. [N3] [N4]

The determinism claim has a real host harness hashing coordinate bits, status,
DOF, residuals, and diagnostics across native/Wasm executions. Its 200-case
fixture includes intentional contradictions; 137 solved is not a 68.5% success
rate, and 3,382 unknowns is the sum across small cases, not one large system.
Evidence supports the covered inputs, not every compiler/input combination. [N5]

Qualification traps:

- `Status::Solved` can coexist with a separately reported orientation flip.
- Point-on-arc refers to its supporting circle; point-on-line is the infinite
  line. Line-line distance does not implicitly impose parallelism.
- Some direction residuals return zero on collapsed lines, requiring separate
  nondegeneracy checks.
- Diagnosis is local and ordered; numerical nonconvergence is not a proof of
  global inconsistency.
- Solve and conflict-reporting tolerances differ. [N2] [N3] [N6]

The core is MIT OR Apache-2.0. GPL/LGPL-derived validation corpus material is
separately excluded from the published crate. Wasm compilation support does not
include a ready Dart/JavaScript wrapper. [N7]

**Verdict:** useful small-sketch challenger and independent reference for branch
continuation, exactification, and deterministic replay. Not an obvious
replacement for our persistent interactive solver.

## KittyCAD EZPZ

Handwritten analytic derivatives cover many 2D relations, including circular-arc
length/angle, point-on-arc, tangencies, midpoint, and symmetry. Adaptive LM uses
sparse Cholesky of damped normal equations. This provides a concrete direct-solve
challenger to our large-component PCG path. [E1] [E2]

The public solve constructs a fresh Model. Sparse symbolic reuse is within one
solve, not our cross-edit session contract. Priorities solve successively larger
constraint subsets and fall back to the prior successful tier. This differs
from optimizing drag preferences while maintaining required feasibility. [E3]

Acceptance details to test independently:

- Default convergence tolerance is 1e-8; the satisfaction check uses a separate
  private 1e-4 epsilon.
- Some degenerate equations emit zero residual plus a warning. Arc length with
  a sufficiently small radius is a concrete source example.
- Freedom analysis densifies the Jacobian for QR. Residual-unsatisfied IDs are
  not minimal conflict/redundancy explanations.
- The public constraint enum does not expose arbitrary residual/AD callbacks.
  Extending geometric primitives generally requires modifying the core. [E1] [E3] [E4] [E5]

The supplied Wasm crate is a maintainer sample/test wrapper, not a general
sketch binding. Native/web wrappers, ID mapping, result translation, and
transactional state handling remain integration work. [E6]

### Upstream benchmark labeling issue

Criterion's massive-parallel benchmark multiplies a desired line count by four,
labels that value as the scalar-variable size, then passes it to a generator
that expects a line count. Labels 200/600 therefore generate 800/2,400 scalar
variables. The workload contains independent prescribed lines, not a tightly
coupled nonlinear sketch. This was verified from the generator and benchmark
source; it does not constitute a fresh Rust performance run. [E7] [E8] [E9]

**Verdict:** targeted candidate for analytic 2D equations and sparse direct
solving. The source assessment does not support making it our automatic first
replacement candidate.

## Ceres

Ceres is a useful numerical control with LM/DogLeg and multiple dense, sparse,
and iterative linear solver choices. The relevant question is whether those
methods improve accepted solutions and complete-operation latency on our
difficult connected workloads. [C1]

Its contract is least squares with parameter bounds. It does not directly
provide general hard equality constraints. Geometry can be encoded as
residuals, but our physical acceptance, hard/soft semantics, branch policy,
diagnostics, and rollback remain application responsibilities. A numerical
termination code is not a valid-sketch certificate. [C2]

A C API exists, but describes itself as minimal/work in progress. Its simple
`ceres_solve` entry does not expose the full options/summary needed for a fair
comparison. A fuller C++ adapter should evaluate residuals on the native side;
per-residual round trips into Dart would confound solver cost with callbacks.
A Ceres engine is not a drop-in implementation of our linear-step interface. [C3]

The main library is BSD-3-Clause. Dependency configuration matters: the reviewed
installation guide flags GPL components in SuiteSparse and makes that support
opt-in. No first-party ready-made Dart browser integration was verified. [C4]

**Verdict:** numerical backend control for larger coupled systems, with our
geometry/session/application contract retained around it.

## Executable comparison protocol

### Two measured contracts

| Contract | Included work |
|---|---|
| Numerical solve | Prescribed starting geometry and an already constructed model; include diagnostics inherently performed inside the solve call |
| Complete application operation | Apply Dart edit; update/rebuild model; cross binding; solve; independently validate; produce requested diagnostics; commit/rollback |

Report cold construction, module initialization, and retained edits separately.
Do not subtract estimated bridge costs from complete measurements.

### Fixture groups

| Group | What it resolves |
|---|---|
| Anchored rectangles, triangles, chains | Correctness, preparation cost, small-system overhead |
| Connected nonlinear sketches at increasing size | Sparse direct versus iterative solving, convergence and scaling |
| Many disconnected components, one edit | Persistent reuse and whole-model housekeeping |
| Dimension sweeps and pointer paths | Tail latency, hard constraints, tracking, branch continuity |
| Redundant/contradictory/near-dependent equations | Valid diagnostics and honest failure classification |
| Unit changes, large offsets, collapsed lines/radii | Physical accuracy and invalid-geometry handling |
| Structural edits, rejection, undo, forks | Rebuild cost, rollback, state isolation |
| Separate 3D/mate cases | Scope retained by a proposed replacement |

The decisive missing fixture is a connected nonlinear planar sketch at roughly
100, 500, and 2,000 free 2D coordinates, with closed loops, dimensions, tangencies,
some redundancy, and repeated moves approaching difficult configurations.
Record actual internal active coordinates, rows, and components; our stock
workplane representation differs from native 2D representations.

### Independent oracle and result handling

- Check every required distance/angle in product units with fixed tolerances.
- Check orientation/branch, positive radii, and nondegeneracy separately.
- Specify infinite-line/segment and supporting-circle/bounded-arc semantics.
- Underconstrained geometry need not equal Dart's coordinates if it satisfies
  the agreed interaction contract.
- Only score soft-target behavior after hard feasibility.
- Known contradictory fixtures must not become accepted least-squares compromises.
- A failed local solve is not proof of infeasibility.
- Preserve timeouts/failures; never improve latency tables by removing them.
- Unsupported capabilities remain explicit until their adapter is implemented.

### Timing discipline

Native: Dart AOT versus Rust release and optimized C++, on the same host.
Keep JIT separate. Pin source commits, toolchains, flags, and thread counts.
Browser: actual Dart2JS/Dart2Wasm application and real Wasm integration path on
the same browser/hardware/worker configuration. Node Wasm is a separate lane,
not a real-browser measurement.

Run one timed engine at a time. Rotate engine order between rounds, fix seeds,
retain raw observations, and record machine/toolchain provenance. Separate
runtime warmup from model-state reuse. Thousands of observations across multiple
sessions are preferable for p95, and substantially more for p99; do not infer
stable p99 from 25 samples. Report uncertainty and repeated-run variability.

## Invest next: three falsifiable experiments

### A. Planar representation and analytic derivatives

Compare the current 3D workplane builder with native 2D Dart residuals. Separate
2D representation from analytic derivative improvements by including a 2D AD
variant. Use the same physical models, tolerances, and oracle. If the gap closes,
improve the geometry layer rather than replacing the numerical engine.

### B. Difficult coupled numerical systems

Use Ceres and EZPZ, plus the other candidates' applicable paths, to challenge
Dart's iterative large-system backend. Include cases across 64 columns (Dart
linear backend), 96 columns (Dart rank defaults), 120 parameters (Solvent linear
backend), and 300 parameters (Solvent default numeric diagnostic check).
Keep representation, diagnostic costs, and alternative solver settings visible.
A migration needs a reproducible gain in correctness/reliability or complete
operation tail latency that exceeds run variability.

### C. Solvent capabilities and NeoSCAD behavioral references

Exercise Solvent decomposition/replay, branch choices, and curves through its
record/ABI boundary. Verify supported cases and failures rather than assuming
the language demo establishes our integration. Use NeoSCAD as a reference for
continuation, exactification, and repeatability on the shared 2D vocabulary.
Keep our document/session/transaction contract.

## Incremental execution and remote checkpoints

The authorized continuation should be preserved on a dedicated remote branch:

1. Commit this assessment before implementation.
2. Commit pinned manifests, fixture specification, independent oracle, and adapters.
3. Commit execution infrastructure and each meaningful implementation checkpoint.
4. Preserve raw results and exact source/toolchain provenance after each run.
5. Record failed/rejected experiments; keep them distinct from retained changes.
6. Update the results document with executed evidence, limitations, and decisions.
7. Validate retained production changes and make the branch reviewable.

Do not label unexecuted adapters as successful comparisons or unrun candidates
as slower. Do not merge experimental changes into main on the strength of this
source assessment alone.

## Sources

[D1]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/doc/geometric-solver.md
[D2]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/lib/src/geometry/numeric.dart
[D3]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/lib/src/geometry/solver.dart
[D4]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/lib/src/geometry/primitives.dart
[D5]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/doc/performance-cad-main.md
[D6]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/benchmark/results/2026-11-13-main-summary.json
[D7]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/benchmark/results/2026-11-13-main-paired.json.gz
[D8]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/benchmark/geometry.dart
[D9]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/benchmark/geometry_coupled.dart
[D10]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/benchmark/geometry_nonlinear.dart
[D11]: https://github.com/CrispStrobe/dart_csp/actions/runs/43516383046
[D12]: https://github.com/CrispStrobe/dart_csp/blob/5dc27dc0b297683d47e94ade2b4ca22ed530d429/.github/workflows/ci.yml
[S1]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/docs/contract/architecture.md
[S2]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-ffi/tests/without_a_document.rs
[S3]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/decompose.rs
[S4]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/curve.rs
[S5]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/diagnose.rs
[S6]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/homotopy.rs
[S7]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/newton.rs
[S8]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/docs/implementation-status.md
[S9]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/solve/drag.rs
[S10]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-solve/src/solve.rs
[S11]: https://github.com/bmander/geomsolver/blob/64bad08b2f126f6be495f6647c180ae703e0963e/rust/gcs-ffi/src/lib.rs
[N1]: https://docs.rs/crate/sketch-solver/0.1.0
[N2]: https://github.com/neoscad/sketch-solver/blob/87ad5bab1d89c1723c1ba4566f27555209a6fe4a/src/model.rs
[N3]: https://github.com/neoscad/sketch-solver/blob/87ad5bab1d89c1723c1ba4566f27555209a6fe4a/src/solve.rs
[N4]: https://github.com/neoscad/sketch-solver/blob/87ad5bab1d89c1723c1ba4566f27555209a6fe4a/src/linalg.rs
[N5]: https://github.com/neoscad/neoscad/blob/551bfcea09e63a202cac3f201439a7c86f922889/crates/wasm-check/src/sketches.rs
[N6]: https://github.com/neoscad/sketch-solver/blob/87ad5bab1d89c1723c1ba4566f27555209a6fe4a/src/equations.rs
[N7]: https://github.com/neoscad/sketch-solver/blob/87ad5bab1d89c1723c1ba4566f27555209a6fe4a/Cargo.toml
[E1]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz/src/constraints.rs
[E2]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz/src/solver/newton.rs
[E3]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz/src/lib.rs
[E4]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz/src/solver.rs
[E5]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz/src/solver/find_dof.rs
[E6]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz-wasm/src/lib.rs
[E7]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/ezpz/benches/solver_bench.rs
[E8]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/test_cases/massive_parallel_system/gen_big_problem.py
[E9]: https://github.com/KittyCAD/ezpz/blob/915882cc731da31042ce494c89b10334ee57837a/justfile
[C1]: https://github.com/ceres-solver/ceres-solver/blob/e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72/docs/source/nnls_solving.rst
[C2]: https://github.com/ceres-solver/ceres-solver/blob/e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72/docs/source/modeling_faqs.rst
[C3]: https://github.com/ceres-solver/ceres-solver/blob/e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72/include/ceres/c_api.h
[C4]: https://github.com/ceres-solver/ceres-solver/blob/e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72/docs/source/installation.rst

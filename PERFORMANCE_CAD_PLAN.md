# Performance and parametric 3D CAD implementation plan

Created: 2026-11-13. Audit baseline: `13f2b04925443a75b6766c969b10aefc65978a0e`.

## Objective and delivery contract

Improve the existing pure-Dart constraint solver and make it a foundation for
interactive parametric 3D CAD. Preserve the existing public APIs while adding
typed results, compiled reusable state, geometric solving, feature regeneration,
and a geometry-kernel boundary. Keep native, JavaScript, and WebAssembly support.

The user authorized execution of this entire plan and incremental preservation in
a remote feature branch. Work on `feat/performance-parametric-cad`; save this plan
first, then push small coherent checkpoints. Do not merge into main or publish a
package release as part of this work. Every checkpoint must state what was
implemented, what was tested, and what remains. Never describe a prototype,
adapter contract, candidate interval box, or unmeasured speedup as a completed
production capability.

## Baseline audit and independently reproduced defects

The audit used unmodified source and Dart 3.14.0. Reproductions established:

1. `allDifferent` and ranged GCC return two solutions instead of three for
   `x=[1,2], y=[2,3], z=[4]`. Their residual graph traversal follows the wrong
   direction from unmatched values. Preserve the graph orientation used by
   explanations; reverse only the free-value reachability traversal.
2. LCG emits `x>=3` after removing 1 from `[1,3,0,2]`, even though 0 and 2 remain.
   Bound explanations need actual numeric extrema independent of value order.
3. Outward rounding is defeated by typed-DSL auxiliary bounds. The feasible real
   equation `(1e16+1-1e16)*1=1` returns FAILURE when intermediate bounds are rounded
   to nearest before propagation. Derived domains need conservative arithmetic.
4. A finite interval `[-1e308,1e308]` returns an infinite midpoint. Midpoints,
   representable-endpoint termination, and returned coordinates need validation.
5. Standalone continuous solving conflates a split limit with infeasibility and
   accepts unchecked candidate boxes. `1e14*x*x=-1`, with `x` in
   `[-1e-7,1e-7]`, returns midpoint zero despite residual one. Geometric success
   requires evaluating the original equations with appropriate tolerances.

The main mixed solver correctly rejected the explicit negative-square probe;
the standalone candidate-box reproduction must not be attributed to that path.

## Stage 1 — Restore correctness and define result semantics

- [x] Correct allDifferent/GCC alternating-path reachability without invalidating
      Hall/capacity explanations.
- [x] Correct extrema and bound-atom recording for unsorted domains.
- [x] Make typed expression auxiliary bounds conservative, including products.
- [x] Make midpoint and endpoint-stagnation handling safe on finite doubles.
- [x] Add typed continuous results distinguishing satisfied/candidate,
      infeasible, limit, cancellation, precision limits, and numerical failure.
- [ ] Validate candidate residuals against original constraints; expose actual
      residual error and preserve compatibility wrappers honestly.
- [ ] Add independent Cartesian-product oracles, explanation regressions, and
      numerical scaling/cancellation regressions.

Acceptance: the reproduced defects have focused regressions; small loose/tight
finite-domain cases match independent enumeration; native and relevant browser
checks retain valid solutions. Rebaseline affected performance fixtures.

## Stage 2 — Compact domains and reusable compiled state

- [x] Keep declared integer ranges compact through construction and copying.
- [x] Add numeric extrema and direct bound intersections to domain operations.
- [ ] Avoid value enumeration for interval bounds propagation and useful branch
      decisions; preserve ordering and arbitrary-value compatibility.
- [ ] Add immutable compiled model structure with stable IDs and mutable solve
      sessions, explicit revisions, assumptions, and invalidation rules.
- [ ] Retain reusable graph/propagator state; reuse eligible logical state only
      while its assumptions remain valid.
- [ ] Add end-to-end range and repeated-edit benchmarks including allocations
      or structural work counters.

Acceptance: large intervals can be declared without materialization; bounds work
scales with participating variables rather than interval cardinality; edit
sessions demonstrate actual structural reuse with cold/warm solution parity.

## Stage 3 — Propagation and search performance

- [ ] Retain and repair allDifferent matching and reusable graph buffers.
- [ ] Replace pathological GCC capacity-copy expansion with compact capacitated
      reasoning and correct lower/upper occurrence handling.
- [ ] Reuse propagation queues and deduplication state; route events through
      relevant indexes and maintain real reverse clause-watch indexes.
- [ ] Avoid sorting zero-information LCV scores; avoid sorting all candidates
      when only one is needed; cache valid supports where useful.
- [ ] Improve standalone continuous propagation with dirty constraints, reusable
      buffers, linear-time term bounds, and specialized square contraction.
- [ ] Measure clause usefulness and conflict-analysis work before changing the
      current conservative backjumping policy.
- [ ] Make long propagation/numerical work respect deadlines and cancellation.

Acceptance: paired benchmarks show improvements on their stated workloads with
independent solution validity and unchanged verdicts. No unsupported multiplier
claims. Regressions or neutral changes are recorded rather than hidden.

## Stage 4 — Persistent geometric numerical solver

- [x] Add parameter/residual blocks with explicit dependencies, signed residuals,
      analytic derivatives and local automatic differentiation.
- [x] Compile an expression/dependency graph, remove fixed variables, partition
      independent components, and assemble sparse Jacobian blocks.
- [x] Implement controlled nonlinear steps, scaling, robust small-block linear
      algebra and a scalable sparse path behind a backend interface.
- [x] Warm-start edits from previous valid coordinates; retain structural caches
      and recompute only affected components.
- [ ] Separate required geometric feasibility from drag/position preferences.
- [x] Add point/line/plane/circle/workplane/frame/pose primitives, dimensional
      constraints, tangency, and assembly mate support.
- [x] Support quaternion storage with three-dimensional rotation updates.
- [x] Report residuals, numerical rank/local freedoms, redundant constraints,
      numerical failures, limits, and cancellation without calling local
      nonconvergence a proof of infeasibility.
- [x] Preserve the last valid state and reject stale asynchronous revisions.

Acceptance: anchored/underconstrained sketches and 3D assemblies solve within
declared length/angle tolerances; dragging preserves required dimensions and
intended branches; translated/rescaled and near-singular fixtures are covered.

## Stage 5 — Parametric feature regeneration and kernel boundary

- [x] Add a feature dependency DAG, parameter expressions, transactions, stable
      entity IDs, dirty regeneration, and last-valid-state behavior.
- [x] Define a geometry/B-rep kernel interface for extrusion, revolution,
      booleans, fillets, shells, validation and tessellation. Capability support
      must be explicit; unsupported operations must fail clearly.
- [x] Implement a useful executable reference path and keep native/browser kernel
      adapters separate from the portable constraint core.
- [x] Preserve semantic face/edge references through feature history, reporting
      missing/ambiguous references explicitly after topology changes.
- [x] Add an end-to-end mounting-bracket model with editable width, thickness,
      hole spacing and hole diameter, constrained sketch, solid regeneration,
      downstream reference checks and invalid-edit rollback.

Acceptance: the bracket can be regenerated by parameter edits with valid geometry
and stable references on supported operations. A kernel interface alone does not
fulfil this acceptance criterion. Document the implemented feature subset and
any external kernel requirements precisely.

Implemented fixture: a planar two-hole mounting plate, with width, height,
thickness, spacing and diameter edits. It includes a numerical constrained
sketch, analytic extrusion, mesh and semantic references. Bends and general
solid operations need another kernel backend; no bent/filleted bracket is
claimed. The sketch adapter reuses compiled structure and committed coordinates
but creates isolated candidate workspaces to preserve downstream rollback.

## Validation and performance evidence

Separate model construction, compilation, cold solving, repeated discrete edits,
geometric solving, interactive tails, and solid regeneration. Record input sizes,
fixed seeds, runtime/compiler, hardware when available, work counters, correctness
checks, and paired warm/cold timings. Existing warmed-median benchmarks remain.

Fixtures must include loose and tight allDifferent/GCC, unsorted integer domains,
large ranges, cancellation, known feasible/infeasible arithmetic, unit changes,
translated geometry, duplicate/conflicting dimensions, underconstrained sketches,
near-singular linkages, 3D mates, repeated parameter edits, and topology changes.

Use focused tests during each checkpoint and CI for the full platform matrix and
large workload sweeps. Check formatting and static analysis. Do not relax a valid
correctness assertion merely because a repaired solver changes search order or
timing; replace invalid expected solution counts with independent truth.

Provisional interactive target: ordinary sketch-edit p95 below 16.7 ms on a named
reference platform and corpus. This is a target, not a measured result. Solid
booleans/fillets require separate budgets.

## Checkpoint log

| Checkpoint | Status | Evidence / remaining work |
|---|---|---|
| Plan recorded before implementation | Pushed | `676027b`; this file saved before source edits |
| Correctness and continuous result contracts | Implemented; checkpoint | 73 discrete tests and 80 continuous/DSL tests passed; independent finite-domain oracle covers 240 seeded cases. Targeted analysis and formatting pass. Standalone composed-expression residual validation is implemented; main mixed-engine residual validation and full platform CI remain. |
| Compact domains and bounds propagation | Implemented; checkpoint | 121 focused tests pass, including billion-value solves and 90 independent fractional-bound oracle cases. `benchmark/compact.dart` compares explicit lists and compact declarations in the current engine. Compact ranges above 100,000 values explicitly reject LCG until lazy explanations are implemented; ordinary solving remains compact. |
| Geometric numerical core and primitives | Implemented; checkpoint | 26 numerical and 10 geometric tests pass. Persistent component sessions, local AD/analytic derivatives, QR/sparse PCG, quaternion manifolds, physical residual checks, rollback and async revisions are implemented. 100-circle benchmark: cold p50 8,328 us / p95 14,107 us; one-radius edit p50 450 us / p95 1,538 us, 99 components reused. This compares current cold/reused paths. Hierarchical preferences and full solid features remain. |
| Parametric feature graph and executable kernel subset | Implemented; checkpoint | 18 focused tests pass. Constrained sketches regenerate analytic plate solids and watertight meshes; invalid dimensions/solids/references roll back together. Thickness edits rebuild only solid+mesh. Cold/profile-edit/thickness-edit p50: 3.300/3.401/2.382 ms; profile edits are not faster in this exact-seed fixture. General revolution/boolean/fillet/shell operations explicitly require another backend. |

Update this log and relevant checkboxes with each meaningful remote checkpoint.
New public APIs are additive; update README, detailed guides, CHANGELOG and API
stability notes as implementation lands. Release publication remains separate.

## Architectural references

- [SolveSpace solver technology](https://solvespace.com/tech.pl)
- [Ceres modeling guidance](https://ceres-solver.readthedocs.io/latest/modeling_faqs.html)
- [Ceres nonlinear solving](https://ceres-solver.readthedocs.io/latest/nnls_solving.html)
- [Ceres parameter blocks and manifolds](https://ceres-solver.readthedocs.io/latest/nnls_modeling.html)
- [Ceres automatic derivatives](https://ceres-solver.readthedocs.io/latest/automatic_derivatives.html)
- [OCCT application framework](https://www.occt3d.com/dev/doc/overview/html/occt_user_guides__ocaf.html)
- [OCCT modeling algorithms](https://www.occt3d.com/dev/doc/overview/html/occt_user_guides__modeling_algos.html)

Implement from documented mathematics and the repository's own code. Preserve
the project's clean-room history and permissive core; dependency/backend choices
must remain explicit.

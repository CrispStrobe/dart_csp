# Geometric solver comparison: executed results and recovery

Date: 2026-11-14. Recovered comparison branch:
`bench/geometric-solver-comparison-2026-11-14` at
`43bb4dc21687a373b502d915a5e1567ea5ac3fb2`.

## Decision and integration scope

Keep Dart's geometry, sessions and CAD acceptance rules. The preserved experiment
identifies the large linear step as the strongest next investment. The 2D and
analytic-derivative variants help smaller connected sketches, but do not resolve
the stock backend's 2,000-coordinate failures. The Eigen sparse-step experiment
keeps Dart's nonlinear method and has promising saved correctness results; it
remains a **benchmark-only native prototype**, not a new production default.

The recovered branch adds benchmark adapters, fixtures, tests, documentation and
evidence. It does not modify `lib/`. This makes its source suitable for integration
without silently changing the production solver or adding an FFI requirement.
Integrating it does not certify every external solver build or promote the
experimental 2D representation to a public API.

This document closes the missing execution write-up referenced by the
[original assessment](geometric-solver-comparison.md). That assessment is pinned
to `5dc27dc`, with a later measured harness snapshot recorded in each manifest.
These are historical measurements from the interrupted attempt. The recovery
work below rechecks preserved files; it does not present them as new timings of
the integrated main.

## What survived the interruption

The [machine-readable recovery audit][audit] verifies each present archive's
SHA-256 and byte count, checks every uncompressed summary's stored digest, then
reapplies the strict record validator and physical oracle to the available saved
coordinates. No original observations or unsuccessful runs were removed.

| Saved cohort | Jobs in summary | Raw archives present / declared | Measured samples in summary | Raw evidence available |
|---|---:|---:|---:|---|
| Native screening, core | 198 | 11 / 11 | 990 | Complete archive set |
| Native screening, large ladder | 36 | 25 / 25 | 94 | Complete archive set, including timeouts |
| Native screening, coupled | 54 | 36 / 36 | 148 | Complete archive set, including timeouts |
| Backend thresholds | 108 | 24 / 24 | 540 | Complete archive set |
| Repeated small cases | 162 | 27 / 27 | 4,050 | Complete archive set |
| Repeated 100-coordinate coupled cases | 54 | 18 / 18 | 1,350 | Complete archive set |
| Repeated 500-coordinate ladder | 27 | 0 / 27 | 270 | Summary only |
| Repeated 500-coordinate coupled | 27 | 0 / 27 | 270 | Summary only |
| Repeated 2,000-coordinate ladder | 15 | 0 / 15 | 75 | Summary only |
| Repeated 2,000-coordinate coupled | 15 | 0 / 15 | 75 | Summary only |
| **Total** | **696** | **141 / 225** | **7,862** | **612 jobs with raw records; 84 summary only** |

All 141 present archives match their inventories. The 612 jobs contain **8,950
records including warmups, of which 7,172 are measured samples**. Rechecking these
records produced zero protocol errors and zero changes to the saved physical
oracle verdicts. There are 16 recorded process timeouts in the screening cohorts;
their partial output remains in the archives. "Complete archive set" describes
file preservation, not successful completion of every solver process. [audit]

The interrupted upload left **84 declared archives absent**, covering 690
measured samples. Their exact names, intended hashes, byte counts and job
membership remain in the inventories and recovery audit. Their original bytes
cannot be reconstructed from summaries, and this report does not claim to have
recovered them.

The original confirmation analysis was generated when those raw files still
existed in the prior workspace. It records 100 qualified groups across 300 jobs.
Running the existing analyzer against the files now present yields **72 qualified
groups across 216 jobs**. The remaining 28 groups are excluded because their raw
records and requests are absent. The old report is preserved; the new
[recovered confirmation analysis][recovered] and its [compressed JSON][recovered-json]
are the applicable evidence-availability view.

## Smaller connected sketches: repeated accepted results

The following retained warm-edit rows have three processes per engine, each with
five warmups and 25 measured operations. Every measured operation in these rows
passes the common geometry oracle. Values are milliseconds and are the median
of the three per-process percentiles, not a percentile over pooled samples.
The two fixture families each have 100 unfixed planar scalar coordinates. [recovered]

| Engine / representation | Ladder p50 | Ladder p95 | Triangle-free coupled p50 | Triangle-free coupled p95 |
|---|---:|---:|---:|---:|
| Dart 3D workplane AD | 3.7742 | 4.0309 | 5.3926 | 5.8867 |
| Dart 2D AD prototype | 2.3718 | 2.5843 | 3.4977 | 3.5971 |
| Dart 2D analytic prototype | 2.1790 | 2.3597 | 3.2501 | 3.4710 |
| EZPZ solve | 0.0741 | 0.0836 | 0.0941 | 0.1160 |
| EZPZ solve plus analysis | 0.1755 | 0.2225 | 0.2615 | 0.2920 |
| NeoSCAD | 5.0644 | 6.0875 | 5.4348 | 6.0793 |
| Solvent numerical | 0.4783 | 0.5830 | 0.4769 | 0.5812 |
| Solvent decomposition/replay | 0.0567 | 0.0716 | 0.6913 | 0.7208 |
| Ceres | 1.4308 | 1.6199 | 1.9921 | 2.0498 |

The representation comparison supports a concrete conclusion: eliminating the
extra workplane coordinates/equations helps these Dart cases; analytic derivatives
provide a smaller additional reduction. It does not establish a replacement
solver for the full CAD application. The adapters expose different native
diagnostics and retained-state capabilities; solve-plus-analysis is shown
separately for that reason.

The triangulated ladder is favorable to decomposition/replay. The triangle-free
Henneberg-II coupled family deliberately removes that shortcut, and its Solvent
replay row is slower than the ordinary numerical row. This is useful evidence
against selecting a backend from the easy family alone.

Timing includes native model construction/update, solve, and coordinate
extraction. It excludes process startup, request parsing, JSON output, the common
Python checker, product rendering, and a Dart-to-external-solver binding. These
are native adapter measurements from a shared Linux host, with CPU affinity and
thread limits recorded in the manifests. They are not end-to-end Flutter latency
or a stable p99 guarantee. Historical Ceres dependency cleanliness is not
retrospectively proven by its HEAD-only manifest; the stricter build gate below
applies to future builds.

## Large connected cases: the preserved failure is consequential

The raw screening cohorts include both 2,000-coordinate ladders and
2,000-coordinate triangle-free coupled frameworks, in cold and warm modes. In
each family/mode, all three stock Dart representation variants reach the process
deadline, and every emitted measured result is physically rejected. Changing
the representation or derivative implementation therefore does not remove this
large-system failure. NeoSCAD also times out before a measured result. EZPZ,
Solvent, their applicable analysis/replay variants, and Ceres complete and accept
all three requested measured operations in these screening cases. [screen]

The sample counts are small and incomplete Dart runs cannot supply a successful
latency ratio. The evidence establishes a reliability/scaling problem on these
specific fixtures, not global infeasibility or failure on every large sketch.
Both families use distance-heavy equations, known-feasible embeddings and initial
points close to a solution. They do not cover arbitrary tangencies, complicated
curves, broad convergence basins or interactive branch changes.

The repeated large-case summaries are preserved but excluded from qualified
timing here because their raw uploads are missing. The one-process screening
evidence above remains independently checkable and is sufficient to motivate
investigating the large linear step.

## Sparse direct experiment: useful evidence, limited scope

The [sparse-step prototype][sparse] retains Dart residuals, parameter scaling,
nonlinear damping and acceptance, sessions and transactions. It changes only
the `GeometryLinearSolver` used above the existing dense-QR threshold. The C++
shim uses Eigen `SimplicialLDLT` with AMD ordering on the supplied damped normal
equation, retains symbolic structure across warm edits, and allows up to two
refinement solves. Both native code and Dart independently check the residual
of the original linear system before reporting convergence.

The recovered files contain 15 reported passing linear checks and a
correctness-only physical summary of 32 requests / 96 operations. The latter
reports acceptance of all constructed feasible cases and rejection of the
contradiction controls, including cold and warm 500- and 2,000-coordinate ladders
and coupled frameworks for the direct backend. There are no adapter errors in
that saved summary. [linear-checks] [physical-checks]

This is a useful isolated experiment, but the qualification file retains
per-operation summaries rather than the full returned coordinates. The recovery
audit checks its reported feasibility outcomes; it does not independently rerun
the native library or reconstruct those missing coordinate records. No controlled
sparse-direct latency cohort was present on the recovered branch. This report
therefore makes **no sparse-direct speedup claim**.

Production adoption still needs fresh builds and full geometric/transaction
regressions, repeated whole-operation timing, memory/lifetime qualification,
portable packaging or a separate portable implementation, and explicit cancellation
behavior. The native factorization cannot be interrupted inside Eigen, and the
adapter's identity cache assumes a fixed CSR pattern for each Jacobian object.
Those are benchmark constraints, not newly imposed public solver contracts.

## Portability and external capabilities

The saved Node qualification has 84 jobs / 252 operations covering all three Dart
representations under JavaScript and WasmGC, plus Solvent's Wasm C ABI. Reapplying
the strict validator and oracle changes none of its verdicts. All feasible Dart
smoke cases pass and contradiction controls reject. Solvent's Wasm ABI rejects
the tiny-unit ladder in cold and warm modes: it reports native success but fails
the requested physical tolerance. Those six operations including warmups remain
visible in the [recovery audit][audit]. [node]

The saved Chromium attempt failed at startup because its process-singleton socket
was denied. No browser solver operation ran in that attempt. Its recorded build
hashes and Node execution are portability evidence, not a real-browser benchmark.
The [browser guide][browser] documents the ABI's tolerance-setting limitation and
the exact uncompressed module sizes without claiming equivalent export scopes.

Solvent's capability and ABI probes are retained under
`benchmark/solver_comparison/solvent_adapter/`. They preserve the prior execution
of decomposition, branch persistence, curve contact and language-free construction.
They do not implement a production replacement for Dart's hard/soft, revision or
CAD transaction contracts.

## Recovery fixes and executed checks

The open PR's early review described missing adapters and permissive validation.
The later branch checkpoints supplied the adapters, most runner checks and real
observations. This recovery found and fixed the remaining concrete problems:

1. The oracle now rejects boolean coordinates, requires a finite positive physical
   tolerance and valid operation counts, and rejects non-integer or out-of-range
   indices without coercion. It checks these even when called directly rather
   than through the runner. The runner also rejects a boolean schema version.
2. Sparse geometry qualification now requires each constructed feasible request
   to actually pass. Agreement between two rejection flags is insufficient, and
   adapter exceptions cannot count as successful contradiction rejection.
3. Ceres now checks pinned dependency revisions and actual clean source bytes
   before compilation and again when writing the manifest. Recorded content hashes
   and file counts expose source identity. Hidden `skip-worktree` edits, untracked
   or ignored source files, and changed submodules fail the gate. The historical
   HEAD-only manifest is preserved with its limitation stated explicitly.
4. The sparse prototype's 17 analyzer infos were resolved with braces, inlined
   one-use FFI native function typedefs, and redundant-argument cleanup. There is
   no numerical algorithm change in that cleanup.

Executed for these recovery fixes: **41 Python tests pass**, including focused
malformed-input, false-qualification and dependency-provenance regressions;
`bash -n` passes for the changed Ceres build script; scoped
`dart analyze --fatal-infos benchmark/solver_comparison/sparse_step` passes; and
the changed Dart files are formatted. Fresh external-solver builds and native
FFI qualification are not claimed by those checks. Integrated production tests
and later optimization measurements belong to the main integration report.

The next optimization should use a frozen integrated baseline and a separate
candidate, preserve failures, and measure complete accepted operations. Retain
the sparse-direct prototype as an explicit comparison lane while improving the
production large-system path; do not turn the saved correctness experiment into
an unmeasured default backend.

## Reproduce evidence qualification

Run from the repository root. Output below is new analysis of saved files, not a
solver execution; use a new output directory for each audit.

```sh
python3 -m unittest discover -s benchmark/solver_comparison -p 'test_*.py' -v
python3 benchmark/solver_comparison/analyze.py \
  benchmark/results/solver-comparison-2026-11-14/native-confirm-small \
  benchmark/results/solver-comparison-2026-11-14/native-confirm-coupled-small \
  benchmark/results/solver-comparison-2026-11-14/native-confirm-large-ladder \
  benchmark/results/solver-comparison-2026-11-14/native-confirm-large-coupled \
  benchmark/results/solver-comparison-2026-11-14/native-confirm-xlarge-ladder \
  benchmark/results/solver-comparison-2026-11-14/native-confirm-xlarge-coupled \
  --out build/recovered-confirm-analysis --metrics
```

The [adapter README](../benchmark/solver_comparison/README.md),
[protocol](../benchmark/solver_comparison/PROTOCOL.md),
[sparse-step guide][sparse], and [browser guide][browser] contain separate build
and fresh-execution instructions. Preserve every new run's original requests,
stdout, outcomes, manifests and compact archives before making timing claims.

[audit]: ../benchmark/results/solver-comparison-2026-11-14/recovery-audit.json
[recovered]: ../benchmark/results/solver-comparison-2026-11-14/analysis-recovered-confirm/analysis.md
[recovered-json]: ../benchmark/results/solver-comparison-2026-11-14/analysis-recovered-confirm/analysis.json.gz
[screen]: ../benchmark/results/solver-comparison-2026-11-14/analysis-native-screen/analysis.md
[sparse]: ../benchmark/solver_comparison/sparse_step/README.md
[linear-checks]: ../benchmark/solver_comparison/sparse_step/linear_verification.jsonl
[physical-checks]: ../benchmark/solver_comparison/sparse_step/physical_verification.json
[node]: ../benchmark/solver_comparison/browser/qualification/node_summary.json
[browser]: ../benchmark/solver_comparison/browser/README.md

# Further solver and CAD optimization

The second performance pass starts from `ec99344`, the completed first audit.
Its plan was saved remotely as `894f81a` before implementation. Source changes
were preserved in three separate checkpoints:

| Checkpoint | Change |
|---|---|
| `dd672cd` | Reuse complete validation of immutable reference CAD objects; use numeric tessellation keys |
| `b995a62` | Skip matching fixed points and retain SCC/reachability workspaces |
| `84b3413` | Differentiate active geometric inputs and reuse exact numerical rank diagnostics |

## Work removed

Native VM CPU samples of the baseline identified matching graph/SCC work,
domain filtering, repeated mesh validation and tessellation vertex-key creation
as relevant costs. The abbreviated samples are preserved in
[`2026-11-13-optimization-profiles.json`](../benchmark/results/2026-11-13-optimization-profiles.json).
The profiler sampled entire harness processes, including warmups and exit.
Inclusive ticks overlap and are not a wall-clock speedup calculation.

### Matching and GCC

Each global retains exact immutable domain identities only after a complete
successful propagation. A self-requeued task at that fixed point avoids graph
construction, SCC analysis and filtering. Changed or differently restored
domains force reanalysis. Reusable integer traversal arrays eliminate per-edge
DFS record creation. Queue order and propagation-local explanations are retained.

Work regressions establish one SCC pass plus one fixed-point skip for a root
pruning case, zero capacity growth over steady restored queries, invalidation
between overlapping globals, and safe recovery after interruption during SCC
construction. Three new statistics distinguish actual SCC passes, array growth
and fixed-point skips. Complete-model and per-edge support oracles remain in use.

### CAD regeneration

Private final reference-owned body/mesh classes retain their complete validation
results. Their geometry and topology are constructed internally from immutable
concrete values. Normal extrusion transactions now perform one full body
validation instead of three, and one full mesh validation instead of two.
Numeric vertex keys also replace formatted coordinate strings.

Public objects, copied bodies/meshes, and custom subclasses still receive full
checks. Application validator overrides still run at existing boundaries; a
changed application policy is not hidden by base-validation reuse. No solid or
mesh validity check was removed. Seven regressions exercise these boundaries.

### Geometric solving

Compiled automatic derivatives seed only active local ambient coordinates.
Direct public evaluation still returns full ambient blocks, and analytic callback
buffer shapes are unchanged. Rank/dependency diagnostics reuse only a complete
result for the exact same scaled/tangent numerical Jacobian and rank settings.
Physical residuals are rechecked independently. Size limits also bound retained
rank storage. Solve options are captured before callbacks can change mutable
subclass getters, and changing rank settings refreshes clean diagnostics.

The new 24-point chain has 72 active tangent coordinates, one coupled component
and 423 sparse entries. A full Jacobian pass seeds 141 coordinates rather than
216, a 34.7% reduction. Pitch edits reuse one rank result with zero new rank
factorizations. Every returned point and neighbor displacement is checked against
an independent formula. This is a linear dimensional fixture; nonlinear edits
with changed Jacobians require new rank work.

## Isolated CAD checkpoint measurement

The same `benchmark/cad.dart` ran at `ec99344` and `dd672cd` in sequential fresh
processes: three processes per revision/runtime, each with three warmup pairs and
25 measured pairs. Revision order alternated. Dart was 3.14.0 on a shared,
unpinned Linux x64 container reporting AMD EPYC 9V74. AOT compilation and the
analytic volume/mesh checks were outside timed sections.

The table reports the median of each run's p50, in milliseconds; it is not a
pooled percentile across the three processes.

| Path | JIT before → after | AOT before → after |
|---|---:|---:|
| Cold build, compile and regenerate | 3.950 → 2.166 | 2.982 → 1.455 |
| Profile edit and regenerate | 4.035 → 2.189 | 3.027 → 1.563 |
| Thickness edit and regenerate | 3.082 → 1.436 | 2.876 → 1.409 |

All six AOT median comparisons across the edit paths/runs improved. JIT medians
also improved, but tails were uneven: one after-change thickness run had p95
8.765 ms versus 4.645 ms before. The data do not establish a universal tail bound.
Full per-process summaries are in
[`2026-11-13-cad-validation-reuse.json`](../benchmark/results/2026-11-13-cad-validation-reuse.json).

## Integrated validation and comparison

At source `84b3413`, all 1,635 native tests and 299 JavaScript/Node corpus tests
pass. Full static analysis reports no issues; all 180 Dart files pass formatting.
The WebAssembly corpus and integrated paired performance run are being recorded
in the next evidence checkpoint. GitHub Actions run 144 is queued; it has not
passed CI.

The new `tool/compare_performance.py` runs identical harnesses sequentially in
JIT and AOT modes, alternates revision order and records source/harness hashes.
Copy the current matching/GCC sampling helper and new coupled harness into the
baseline worktree before comparison. The integrated result will distinguish
per-process p50 and p95 values rather than pooling different runs.

The executable reference CAD scope remains rectangular plates with circular
through-holes and positive extrusion depth. General contours, booleans, fillets,
shells and revolutions still require a separate backend. This pass changes work
and allocation within the implemented subset; it adds no external dependency.

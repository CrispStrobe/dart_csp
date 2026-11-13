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

At source `84b3413`, all 1,635 native tests and 299 tests each under JavaScript
and WebAssembly/Node pass. Full static analysis reports no issues; all 180 Dart
files pass formatting. These include 26 added regressions across the three
optimization areas. GitHub Actions run 144 is queued; it has not passed CI.
The prior local Chrome startup restriction still leaves real-browser CI as an
outstanding gate; Node executes the compiled JavaScript/WebAssembly code.

`tool/compare_performance.py` ran identical harnesses sequentially in
JIT and AOT modes, alternated revision order and recorded source/harness hashes.
Copy the current matching/GCC sampling helper and new coupled harness into the
baseline worktree before comparison. The integrated result contains 60 harness
runs: five workloads, two revisions, two runtimes and three rounds. Every
independent result check passed. Full per-process summaries and the coupled
fixture's individual timing samples are preserved in
[`2026-11-13-optimization-paired.json`](../benchmark/results/2026-11-13-optimization-paired.json).
The other harnesses report distributions rather than individual timing samples.

The following values are medians of three per-process p50 values in milliseconds.
The baseline is `ec99344`; the optimized source is `84b3413`. Matching/GCC rows
measure a batch of 12 queries; geometry/CAD rows measure one solve/regeneration.
"Cold" means creating a fresh model, not compiling the AOT executable.

| Workload | JIT before → after | AOT before → after | AOT elapsed change |
|---|---:|---:|---:|
| allDifferent, 32 variables / 36 values | 12.188 → 7.416 | 13.342 → 9.695 | −27.3% |
| allDifferent, 64 variables / 68 values | 43.925 → 29.428 | 62.249 → 45.621 | −26.7% |
| GCC, 32 variables / 8 values | 6.044 → 5.357 | 4.618 → 4.611 | −0.2%; effectively unchanged |
| GCC, 64 variables / 8 values | 10.739 → 9.709 | 15.412 → 15.459 | +0.3%; effectively unchanged |
| 100 independent circles, cold | 5.199 → 4.161 | 2.109 → 1.914 | −9.2% |
| One circle radius edit | 0.291 → 0.286 | 0.121 → 0.122 | +0.8%; effectively unchanged |
| Coupled 24-point 3D chain, cold | 2.416 → 2.303 | 1.577 → 1.762 | **+11.7% regression** |
| Coupled chain, XYZ pitch edit | 1.739 → 0.857 | 1.482 → 0.955 | −35.6% |
| CAD cold build and regeneration | 4.016 → 2.137 | 3.114 → 1.507 | −51.6% |
| CAD profile edit | 3.972 → 2.597 | 3.026 → 1.491 | −50.7% |
| CAD thickness edit | 3.161 → 1.541 | 2.938 → 1.387 | −52.8% |

The measurements support faster typical allDifferent queries, coupled dimension
edits and reference CAD regeneration. GCC improves in JIT by 9.6–11.4%, while
AOT GCC and the already-small isolated-circle edit show no demonstrated median
gain. The coupled cold AOT path is slower in all three rounds, by 0.185 ms when
comparing the aggregate medians. These timings do not identify its cause.

### Tails and limits of the comparison

Tail improvements are not uniform. In particular:

- Coupled pitch-edit AOT p95 worsens in two of three rounds: before values are
  1.606, 2.011 and 1.618 ms; after values are 16.887, 3.730 and 1.142 ms. The
  median of run-p95 values rises from 1.618 to 3.730 ms despite lower p50.
- The 64-variable allDifferent AOT first-round p95 rises from 76.622 to
  106.599 ms per 12-query batch. Its median of run-p95 values improves from
  73.050 to 53.471 ms, but this is not a uniform tail improvement.
- The 64-variable GCC AOT median of run-p95 values is effectively flat/slightly
  worse at 16.836 → 17.059 ms. One round's p50 increases by 8.2%.
- The circle-edit JIT median of run-p95 values rises from 1.167 to 1.447 ms.

Each per-process p95 uses only 25 measured samples on shared, unpinned hardware.
The full set of observations is retained; no outlier was removed and no run was
repeated to improve the table. These are neither statistical confidence bounds
nor an arbitrary-model 16.7 ms interaction guarantee. Cold coupled overhead and
tail behavior remain follow-up profiling targets. No attribution to allocation,
generated code, garbage collection or scheduling is established by timing alone.

### Work counters and independent checks

After-counters for each untimed 12-query batch are identical across all three
rounds and both runtimes:

| Workload | Decisions | Pruning passes | SCC passes | Fixed-point skips | Workspace growths |
|---|---:|---:|---:|---:|---:|
| allDifferent, 32 variables | 192 | 192 | 204 | 192 | 0 |
| allDifferent, 64 variables | 384 | 384 | 396 | 384 | 0 |
| GCC, 32 variables | 192 | 12 | 204 | 12 | 0 |
| GCC, 64 variables | 384 | 12 | 396 | 12 | 0 |

All pre-existing counters agree before/after. The baseline lacks the three new
matching counters, so the table states measured after-work without inventing
before counts. Zero workspace growth concerns traversal arrays, not total
allocation. GCC's 64-variable graph remains 73 nodes and 520 arcs. Its loose
capacity fixture skips only 12 invocations per batch, compared with 384 skips
for the 64-variable allDifferent fixture; the workloads eliminate different
amounts of redundant work.

The final reported coupled solve in every phase/run uses one component, 336
residual-block evaluations, 168 Jacobian-block evaluations, six linear solves
and 144 linear iterations before and after. These counters are not collected for
every timed sample. The independent-circle harness also preserves reported work:
100 solved components/300 linear solves cold; one solved, 99 reused and two linear
solves after a radius edit. Faster coupled edits therefore do not come from fewer
reported linear iterations or skipped components. AD seeding and rank reuse are
established separately by the focused work-counter tests. Coordinate/residual
oracles establish acceptance parity, not bitwise coordinate identity.

## Reproducing the comparison

To reproduce from this branch with Dart 3.14.0 and Python 3 available:

```sh
git worktree add --detach ../dart-csp-before ec99344
git worktree add --detach ../dart-csp-after 84b3413
cp benchmark/matching.dart benchmark/gcc.dart benchmark/sampling.dart benchmark/geometry_coupled.dart ../dart-csp-before/benchmark/
(cd ../dart-csp-before && dart pub get)
(cd ../dart-csp-after && dart pub get)
python3 tool/compare_performance.py \
  --before ../dart-csp-before --after ../dart-csp-after --dart dart \
  --benchmarks matching gcc geometry geometry_coupled cad \
  --rounds 3 --samples 25 --warmups 5 \
  --output benchmark/results/local-comparison.json
```

The configurable sample/warmup arguments apply to matching and GCC. The circle
and CAD harnesses use three warmup pairs and 25 measured pairs; the coupled
geometry harness uses five warmup pairs and 25 measured pairs. Matching/GCC
timings include their bounded per-query solution checks; CAD/geometry checks
run after the stopwatch stops. Work counters are collected outside matching/GCC
timed batches. Run without concurrent test/compiler jobs. The helper compiles
AOT executables before measurement and checks identical harness hashes.

The executable reference CAD scope remains rectangular plates with circular
through-holes and positive extrusion depth. General contours, booleans, fillets,
shells and revolutions still require a separate backend. This pass changes work
and allocation within the implemented subset; it adds no external dependency.

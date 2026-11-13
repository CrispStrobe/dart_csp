# Continued CAD performance and nonlinear assembly work

Date: 2026-11-13. This pass starts at `3b5c4c4373fa0f08d50ff5d5902714cd09cdfc92`,
the completed previous audit on `audit/performance-cad-2026-11-13`. It continues
in [draft PR #4](https://github.com/CrispStrobe/dart_csp/pull/4). The
[continuation-only comparison](https://github.com/CrispStrobe/dart_csp/compare/3b5c4c4373fa0f08d50ff5d5902714cd09cdfc92...audit/performance-cad-2026-11-13)
isolates these changes from the earlier scheduling, geometry and instance work.

## Changes and their purpose

### Transactional numerical candidates

`GeometrySolveSession.fork()` captures an idle session's pending and committed
coordinates, dirty components, local revision, diagnostic options and last
result. Each branch owns its writable values and scratch arrays. Immutable
compiled structure, diagnostic/result snapshots and private rank-cache records
are shared. Neither later edits nor a failed or stale solve can overwrite the
other branch's committed state. An active synchronous/asynchronous solve cannot
be forked because its workspace may contain a partial trial.

Clean components preserve their actual validated physical residuals, including
nonzero values inside tolerance. Dirty components and preference targets evaluate
fresh numerical derivatives before consuming candidate work arrays. Rank reuse
requires the existing exact numerical Jacobian and rank-option comparison.
Callbacks and custom manifolds still belong to the shared model; application
state captured by them is not cloned and still requires explicit invalidation.

The CAD constrained sketch and geometry adapters retain a session weakly keyed
by its successful output. The next regeneration forks the session associated
with the **previous committed output**. A rejected downstream solid, validation
or topology reference therefore cannot become the next numerical seed. Sharing
one feature declaration across documents does not share their numerical history.

Every CAD candidate marks all components dirty and physically revalidates them.
This preserves the adapter's existing behavior for callback-captured application
inputs, including inputs in components not connected to the edited dimension.
Only rank/diagnostic computation is reused after fresh numerical checks.

This is not zero-allocation or copy-on-write scratch reuse. Forks allocate fresh
scratch buffers and copy coordinate/residual state. Retaining historical output
objects also retains their associated sessions. The tradeoff is deliberate:
safe candidate isolation with reusable rank state, without speculative aliasing
of mutable numerical buffers. See [geometric-solver.md](geometric-solver.md) and
[parametric-cad.md](parametric-cad.md).

### Feature graph scaling

The graph compiles parameter-consumer and reverse dependency indexes. An edit
discovers only the affected closure, then evaluates it in the original stable
dependency-first order. Explicit DFS frames replace recursion at compilation,
allowing deep feature histories without consuming the process call stack.

Committed output/revision pairs use immutable chunks of 128 entries. A small
edit copies touched chunks and the shallow chunk directory; unchanged chunks
and immutable outputs remain shared. Public outputs and revision maps retain
read-only lookup/iteration behavior. Rejected candidates preserve the exact old
document state, and retained historical states cannot observe candidate writes.

A 4,097-feature regression changes two features: two scheduled nodes, one
traversed dependency edge, 129 prior entries copied and 33 directory references
copied. The suite retains 41 historical snapshots across 40 edits, checks a
20,000-deep reverse-listed history and compares 600 randomized DAG edits with
independent full recomputation.

Independent review found two ways user subclasses could invalidate a compiled
index: spoofing `runtimeType` to bypass node copying and overriding the public
document `features` getter used by the constructor. All node declarations are
now snapshotted, and compilation uses a private backing list. Dedicated
adversarial regressions cover both cases.

Total commit cost is not constant in document size: it still copies
`ceil(N / 128)` directory references, edited parameter maps and checks required
references. Compilation also builds extra indexes and declaration snapshots.
The [feature graph guide](cad-feature-graph.md) specifies the structural counters,
ordering, immutable Map contract and remaining costs.

### Tiny dense QR experiment rejected

The first candidate used exact scale-safe trailing-column norms for matrices
with at most 16 rows and 8 columns, avoiding cache allocation and downdate work
while sharing the existing Householder implementation. The full paired trial
did not support retaining it: AOT rank batches became 29.6% slower at 5x4,
35.1% slower at 8x4 and 36.9% slower at 16x8. The 4x8 rank batch improved 5.5%,
while AOT damped solve/projection were approximately flat. JIT also regressed
on most shapes, including a 63.0% slowdown in the damped solve batch.

The dispatch is removed. `numeric.dart` is restored byte-for-byte to the
previous audit source, retaining its guarded norm reuse, numerical validation,
budgets and cancellation. This pass does not claim a tiny-QR speedup or replace
the first measurements with selected favorable repeats. The complete
[108-report candidate trial](../benchmark/results/2026-11-13-continuation-qr-candidate-paired.json)
and [76-row summary](../benchmark/results/2026-11-13-continuation-qr-candidate-summary.json)
remain preserved. Final retained changes are measured in a separate paired run.

The useful new suite remains: 174 independently known-rank cases at scales
`1e-150`, `1` and `1e150`, 16x9 and 17x8 shapes, a larger 48x48 control,
independent damped solves, redundant nullspace projections, budgets and stops.
The benchmark includes actual CAD-sized shapes; its timings are operation
**batches**, generally 256 calls, while the 48x48 control uses eight.

## Nonlinear CAD capability and evidence

`example/nonlinear_linkage.dart` constructs a closed four-bar mechanism in a
tilted 3D workplane. Two fixed pivots, three link lengths, plane equations and
an editable signed crank angle constrain two moving points in one nonlinear
component. An independent ordinary-trigonometry/two-circle-intersection oracle
checks both assembly branches, all physical link lengths, plane membership,
fixed pivots and expected coordinates.

Tests include continuation along both branches, link-length edits, an exact
toggle, near-toggle conditioning, redundant equations, impossible dimensions,
budgets, cancellation, asynchronous edits and rollback. A numerical rank loss
at the exact toggle is a local infinitesimal diagnostic; it does not establish
finite mechanism mobility. Local convergence/failure does not select a global
branch or prove general infeasibility.

The timed nonlinear cases are regular configurations on one branch. Near-toggle
and contradictory cases are correctness coverage, not a latency claim. The
solid assembly extension connects this geometry to bar prototypes and rigid
instances; its final validation and measurements are recorded below.

## Measurement method

Paired measurements use the exact previous-audit source and frozen continuation
source. Corresponding harnesses and imported example dependencies must have
matching hashes. Runs are sequential with alternating revision order, three
fresh processes per runtime/revision, and AOT compilation outside all timers.
Independent correctness checks remain outside timed sections in these CAD and
geometry harnesses. Original physical solver/kernel validation remains inside.

Reported aggregates are medians of process p50/p95 values, not pooled
percentiles. Raw samples are retained where the harness exposes them. No samples
or processes are removed after inspection. The host is a shared, unpinned Linux
x64 container with Dart 3.14.0; wall-clock results describe these fixtures and
do not establish a universal interactive frame budget.

`tool/compare_performance.py` records source/runtime/harness provenance and
writes each completed run incrementally. `tool/summarize_performance.py`
derives the complete per-process/aggregate table without discarding samples,
including operation-batch metadata. The new summarizer was independently
reconciled against all 240 aggregate values in the prior 40-row audit summary.

### Final paired results

Pending the frozen-source paired run. No provisional speedup is asserted here.

## Integrated verification

At library source `b0cd755`, the full core native suite passes **1,750 tests**;
the expanded 37-file portable corpus passes **414 tests each** under Node
JavaScript and WebAssembly. Focused implementation gates and independent reviews
also pass. The additional solid-linkage example/tests and final full analysis
and formatting gates follow before the final checkpoint.

Browser execution remains separate: the previous local Chromium
attempt was blocked before tests by a denied process-singleton socket, and
queued GitHub Actions jobs do not count as passed gates.

## Remaining scope

The reference solid subset remains rectangular profiles with circular holes,
positive extrusion and rigid occurrences. The mechanism example does not add
general profiles, booleans, fillets, shells, revolution, collision checking,
pins or production topology repair. A broader kernel backend is still needed.

Further performance work should be driven by these paired results: distinguish
graph setup from repeated edits, rank-cache reuse from scratch allocation,
tiny-matrix crossover from larger sparse solves, and regular nonlinear
continuation from near-singular mechanisms. Full browser latency and a larger
realistic CAD corpus remain independent validation tasks.

See [PERFORMANCE_CAD_CONTINUATION.md](../PERFORMANCE_CAD_CONTINUATION.md) for
incremental remote checkpoints and the [previous audit](performance-cad-audit.md)
for historical results. Earlier measurements are not relabeled as this pass.

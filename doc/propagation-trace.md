# Propagation trace (`onPropagation` / `solveWithTrace`)

A fine-grained, opt-in event stream that lets a consumer **replay the
solver's propagation and search step by step** — which decision was made,
which value was pruned from which variable's domain by which constraint,
and whether a branch ended in a solution or a dead-end. It was added for
pedagogy-grade step-trace visualizers (watch AC-3 / GAC narrow domains in
real time), but it's a general inspection hook.

It sits *alongside* the original coarse [`CspCallback`](#the-two-hooks)
(the per-decision whole-problem domain snapshot used by the Sudoku-style
visualizers) — that hook is unchanged. The two are independent.

## Quick start

```dart
final p = Problem();
// ... build a problem ...

final trace = await p.solveWithTrace();
print(trace.result);     // Map assignment, or 'FAILURE'
print(trace.events);     // List<PropagationEvent>
print(trace.truncated);  // hit the maxEvents cap?
```

Or stream events live by registering an observer (no batching):

```dart
p.setOptions(onPropagation: (e) => print(e), maxEvents: 50000);
final result = await p.getSolution();
```

## Event kinds

Every event is a `PropagationEvent` with a `kind` ([PropagationEventKind])
that selects which fields are populated:

| `kind`          | populated fields |
|-----------------|------------------|
| `decision`      | `variable`, `value`, `depth` |
| `prune`         | `variable`, `removedValues`, `domainBefore`, `domainAfter`, `causeKind`, `causeLabel`, `causeScope` |
| `domainWipeout` | same as `prune`, with `domainAfter` empty (the immediate cause of the branch's failure) |
| `backtrack`     | `depth` |
| `backjump`      | `depth`, `targetDepth` (only when conflict-directed backjumping is enabled) |
| `solution`      | `assignment` |

Every event also carries:

- `seq` — a monotonic, 0-based, gap-free sequence number (replay order).
- `stats` — an optional frozen [SolverStats] snapshot at emit time.

### The cause mirrors MUS output

A `prune` / `domainWipeout` describes the constraint that fired with the
**same vocabulary the conflict-explanation (MUS) API uses**:

- `causeKind` — `'binary'` for an AC-3 arc, otherwise the n-ary
  constraint's `coarseKind` (`'allDifferent'`, `'linearLeq'`,
  `'cumulative'`, `'regular'`, `'gcc'`, `'diffN'`, `'clause'`,
  `'circuit'`, …) — the same set [`ConstraintRef.kind`](conflict-explanation.md)
  reports.
- `causeLabel` — the user's `label:` from the originating `addX` call (or
  `null`).
- `causeScope` — the constraint's variables (`[head, tail]` for a binary
  arc; the n-ary `vars` otherwise).
- `causeDescription` — a `kind[label](scope)` rendering, identical in shape
  to `ConstraintRef.toString()` (e.g. `binary[A≠B](A, B)`).

So a UI that already renders MUS `ConstraintRef`s can render propagation
causes with the same code.

## What gets emitted, and when

- **Prunes** are emitted from the single domain-mutation chokepoint, so
  every AC-3 arc revision and every GAC / global-propagator reduction that
  actually removes a value produces one event — including the prunes during
  the initial root propagation (before the first decision). Decision pins
  and SAC tentative pins carry no constraint cause and are *not* reported as
  prunes (a decision is its own `decision` event).
- **Decisions / backtracks / backjumps** come from the search loops (plain
  and conflict-directed-backjumping variants alike). `depth` is 0 at the
  root.
- **Solutions** are emitted at every complete-assignment leaf. For
  satisfaction solves that's the one returned solution (or each streamed
  solution); for optimization it fires at every feasible leaf, not only
  improving ones.

## Zero overhead when unset

Tracing is off unless an observer is registered. Every emission site first
checks `onPropagation == null` and returns before building any event
object, so the hot path is untouched. This is covered by a test asserting
an un-traced and a traced run report identical `decisions` / `backtracks` /
`propagations`.

## Bounding volume

`maxEvents` (default `100000`) caps the number of events per solve. Once
hit, further events are dropped and the solve is flagged:

- `PropagationTrace.truncated` (from `solveWithTrace` /
  `solveInIsolateWithTrace`), and
- `CSP.lastTraceTruncated` (a static, mirroring `CSP.lastStats`, for the
  live-observer path).

Nothing is dropped silently — the flag tells you the trace is partial.

## Crossing the isolate boundary

A `PropagationObserver` is a closure and can't be sent across an isolate
port. Two pieces make trace work off-main anyway:

1. `PropagationEvent.toMap()` / `PropagationEvent.fromMap()` serialize an
   event to/from a **plain map** (only `int` / `String` / `List` / `Map`
   values — dart2js / dart2wasm safe, no 64-bit-literal or `Uint64List`
   tricks).
2. `solveInIsolateWithTrace(build, {maxEvents, ...})` runs the solve in a
   worker isolate, where a worker-side observer batch-collects the events
   as maps; the batch is shipped back over the port once and reconstructed
   on the calling side into a `PropagationTrace`. (v1 supports the
   first-solution solve; problems are expected to be modest in size — the
   whole trace is buffered in the worker and copied once.)

## The two hooks

| | `callback` (`CspCallback`) | `onPropagation` (`PropagationObserver`) |
|---|---|---|
| Granularity | per decision | per decision **and** per prune / wipeout / backtrack / solution |
| Payload | whole-problem domain snapshot | one targeted event (var, values, cause, …) |
| Cause info | none | `kind` + `label` + `scope` |
| Delay knob | `timeStep` ms | none (synchronous) |
| Use | coarse "watch the assignment grow" | step-by-step propagation replay |

Both can be registered at once; they're independent.

## API surface

- `Problem.setOptions({..., PropagationObserver? onPropagation, int? maxEvents})`
- `Problem.solveWithTrace({consistency, cancelToken, enableConflictBackjumping, maxEvents}) → Future<PropagationTrace>`
- `solveInIsolateWithTrace(build, {consistency, cancelToken, timeout, maxEvents}) → Future<PropagationTrace>`
- `PropagationEvent` (+ `toMap` / `fromMap` / `causeDescription`), `PropagationEventKind`, `PropagationObserver`, `PropagationTrace`
- `CSP.lastTraceTruncated`
- `NaryConstraint.coarseKind` (the shared kind vocabulary)

All additive; see `CHANGELOG.md` (2.2.0).

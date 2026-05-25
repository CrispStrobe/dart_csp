# Cancellation, Timeouts, and Worker Isolates

Backtracking search is CPU-bound. On a hard CSP, a solve can run for
seconds, minutes, or longer — and the calling code often has a deadline
or an upstream caller that no longer wants the result. `dart_csp`
exposes three composable mechanisms for getting an in-flight solve to
stop:

- a **`CancellationToken`** the caller flips when it wants the solve to
  abort;
- a wrapping **`Future.timeout(...)`** that fires after a deadline; and
- a **worker isolate** running the solve off the calling isolate
  entirely.

This guide is the consolidated story for all three: the mental model
they share (cooperative checkpoints), how each one is observed by the
engine, and the trade-offs that decide which one you want.

## TL;DR — pick the right tool

| You want to… | Use |
|---|---|
| Stop on a deadline, search runs on the calling isolate | `Future.timeout(...)` *or* a `CancellationToken` fired from a `Timer` |
| Stop on an arbitrary external event (button, cancel signal, upstream future closed) | `CancellationToken` + `token.cancel()` from wherever the event lands |
| Distinguish "deadline" from "no solution exists" | `CancellationToken`; inspect `token.isCancelled` after the call |
| Keep the main isolate's event loop fully responsive | `solveInIsolate(build, ...)` (and friends), with `timeout:` for a hard deadline |
| Forward a parent-side cancel into a long-running async operation you don't own | `CancellationToken.addListener(...)` |

The three mechanisms compose: a worker-isolate solve still accepts a
`CancellationToken`, and an in-process solve still respects a
wrapping `.timeout(...)`.

## The mental model: cooperative checkpoints

Every backtracking entry point and the min-conflicts runner reach a
`_checkpoint` at well-defined points in the search loop — once per
decision for backtracking, once per ~200 iterations for min-conflicts.
At each checkpoint the engine does two things:

1. Read `cancelToken?.isCancelled`. If true, abort and return the
   literal string `'FAILURE'`.
2. Every `_yieldEveryDecisions` (currently 100) decisions, yield to
   the event loop via `await Future<void>.delayed(Duration.zero)`. This
   is what lets a wrapping `Future.timeout(...)` actually fire and what
   lets a `Timer` that calls `token.cancel()` get a turn in the first
   place.

The fast path is one integer compare plus the periodic zero-duration
yield. On every benchmark in `benchmark/benchmark.dart` the amortized
cost of this machinery is under 1% of search wall-clock.

The yield is *unconditional*: it runs whether or not the caller passed
a token. Without it, a CPU-bound `await getSolution()` would prevent
the surrounding async code (timers, stream subscriptions, HTTP
responses) from ever running, and `Future.timeout(...)` would never
fire mid-solve. With it, the solver is cooperatively responsive even
on its single isolate.

## The `CancellationToken` API

`CancellationToken` is the unified handle for "I want this solve to
stop early." It's a plain Dart object — sendable around your own code,
created with no arguments, cancelled with one method:

```dart
final token = CancellationToken();
// ... later, possibly from a Timer, a button handler, an upstream
// stream's onCancel, anywhere:
token.cancel();
```

Surface:

| Member | Behavior |
|---|---|
| `CancellationToken()` | Fresh, uncancelled token. |
| `isCancelled` | `true` after `cancel()` has been called. Single-use; once flipped, stays flipped. |
| `cancel()` | Flips `isCancelled`. Idempotent. Synchronously invokes any registered listeners in registration order; listener exceptions are caught and discarded so they can't block the caller or other listeners. |
| `addListener(void Function())` | Registers a one-shot callback to run on `cancel()`. If the token is already cancelled, the listener runs synchronously before `addListener` returns. |

Every backtracking solver entry point and `solveWithMinConflicts`
accept an optional `cancelToken:` parameter:

```dart
final token = CancellationToken();
Timer(Duration(seconds: 5), token.cancel);
final result = await p.getSolution(cancelToken: token);
if (result == 'FAILURE' && token.isCancelled) {
  // Cancelled — search was aborted before completion.
} else if (result == 'FAILURE') {
  // Proven infeasible — search exhausted the tree without success.
} else {
  // result is Map<String, dynamic> — a solution.
}
```

Solver code reads `isCancelled` directly at each checkpoint; the
`addListener` hook exists for plumbing that needs to *forward*
cancellation outside the calling isolate. The worker-isolate runner is
the canonical example: it registers a listener on the parent's token
that posts a `'cancel'` message to the worker's control port when the
token fires. Application code that needs to wire a parent cancellation
into some other async operation it owns should follow the same pattern
— register a listener rather than poll `isCancelled` in a loop.

### `'FAILURE'` is overloaded — distinguish via the token

A cancelled solve and an unsatisfiable problem both return the literal
string `'FAILURE'` (and a cancelled stream completes naturally with no
further events). This is intentional: callers can keep their existing
`if (result is Map<String, dynamic>)` gate without a new exception
type to handle. The token is the witness of cancellation:

```dart
final result = await p.getSolution(cancelToken: token);
final cancelled = token.isCancelled && result == 'FAILURE';
```

Two consequences worth knowing:

- **`maximize`/`minimize` on a cancelled token return `'FAILURE'` even
  if an improving incumbent was already found.** The current API
  doesn't expose the last-seen incumbent. If you need it, run an
  enumerating `getSolutions` and track the best yourself.
- **A pre-cancelled token short-circuits.** The backtracking solver
  returns `'FAILURE'` immediately without touching `lastStats` or
  doing any real work. Tests that assert stats activity on a cancelled
  solve must check this branch separately.

## Cooperative yields and `Future.timeout(...)`

Because the engine yields at every checkpoint, a wrapping `.timeout()`
works on an otherwise CPU-bound solve without any cancellation
plumbing:

```dart
try {
  final result = await p.getSolution().timeout(Duration(seconds: 5));
  print(result);
} on TimeoutException {
  print('Took longer than 5 seconds.');
}
```

The semantics differ from the token form in two ways:

1. **`.timeout()` throws `TimeoutException` on deadline; the token
   form returns `'FAILURE'`.** Choose based on how the rest of your
   call site wants to model "deadline".
2. **`.timeout()` returns to the caller on time, but the solve keeps
   running in the background** until it naturally yields, checks for
   listeners, and discovers nobody is awaiting the future. The CPU
   pressure on the calling isolate doesn't disappear when the
   exception fires; it disappears when the solver's *next* checkpoint
   happens (usually within a few hundred milliseconds, but it depends
   on how often the search reaches a checkpoint relative to its branch
   factor). For an in-process solve this is rarely a problem in
   practice — the next yield is bounded — but it's a real difference
   versus the isolate runner's `timeout:` parameter, which kills the
   worker outright.

If you want both — a deadline *and* the ability to distinguish "ran
out of time" from "no solution exists" — wire a `Timer` to a token:

```dart
final token = CancellationToken();
final deadline = Timer(Duration(seconds: 5), token.cancel);
try {
  final result = await p.getSolution(cancelToken: token);
  // result is Map<String, dynamic> → solution
  // result == 'FAILURE' && token.isCancelled → timeout
  // result == 'FAILURE' && !token.isCancelled → infeasible
} finally {
  deadline.cancel();
}
```

## Worker-isolate runner: when you need real parallelism

Cooperative cancellation makes an in-process solve responsive, but it
does not move the work off the calling isolate. Every yield is brief
and the CPU pressure stays on the main thread. For workloads where
you need to free the main isolate entirely — a Flutter app whose UI
must stay smooth, a server running multiple solves concurrently, or
any case where you want true wall-clock parallelism on a multi-core
machine — `lib/src/isolate_runner.dart` spawns the solve on a fresh
worker isolate.

The four in-process entry points have isolate twins, all top-level
functions exported from `dart_csp.dart`:

| In-process | Worker isolate |
|---|---|
| `Problem.getSolution` | `solveInIsolate` |
| `Problem.getSolutions` | `solveAllInIsolate` |
| `Problem.minimize` | `minimizeInIsolate` |
| `Problem.maximize` | `maximizeInIsolate` |

```dart
import 'package:dart_csp/dart_csp.dart';

// Top-level builder so the closure is sendable. The builder runs
// inside the worker, not on the caller's isolate.
Problem buildMySchedule() {
  final p = Problem();
  // ... addVariable / addConstraint / ...
  return p;
}

Future<void> main() async {
  final solution = await solveInIsolate(
    buildMySchedule,
    timeout: Duration(seconds: 30),
  );
  // CSP.lastStats has been populated with the worker's counters
  // (on normal completion).
  print(solution);
}
```

### Why a builder, not a `Problem`

A constructed `Problem` carries user-supplied predicate closures, and
in the general case those closures aren't sendable across an isolate
boundary — a predicate can transitively capture arbitrary main-isolate
state. The runner sidesteps the issue by taking a `Problem Function()`
that runs *inside* the worker; the worker constructs the `Problem`
locally, solves it, and only sends back primitive result types
(`Map<String, dynamic>` solutions, the `'FAILURE'` literal, and
`SolverStats`).

In practice this means the builder must be a top-level function, a
static method, or a closure that only captures other sendable values
(primitives, `const`-allocated values, other top-level functions).

### `cancelToken:` vs `timeout:` — and the difference that matters

Both parameters are honored by all four entry points. They look
similar but they aren't redundant:

- **`cancelToken:`** is a main-isolate `CancellationToken`. The runner
  registers a listener on it (via `addListener`) and forwards
  cancellation to the worker over the worker's control port; the
  worker has its own local `CancellationToken` driven by that message,
  and the solver aborts at the next checkpoint. The returned future
  resolves with `'FAILURE'` shortly after.

- **`timeout:`** is a built-in deadline. When it fires the runner
  posts the same cancel signal to the worker, waits a brief grace
  window (currently 250 ms) for the worker to flush its `'result'`
  message back over the port, then hard-kills the isolate via
  `Isolate.kill()`. The returned future resolves with `'FAILURE'`.

**Prefer the built-in `timeout:` over wrapping `await
solveInIsolate(...).timeout(...)`.** The built-in path actually
terminates the worker; the wrapping form returns to the caller on
time but leaves the worker isolate running, consuming CPU and memory
until it naturally completes. On a server running many concurrent
solves this difference matters — leaked workers add up.

### Stats round-trip and the `lastStats` invariant

`CSP.lastStats` is a static slot in the main isolate. The worker
fills its own `lastStats`; on normal completion it ships those stats
over the port and the runner writes them into the main isolate's slot
*before* the returned future resolves. This preserves the documented
"stats are populated by the time the future resolves" contract.

Two paths do *not* round-trip stats — by design, because the worker
didn't have a chance to flush them:

- A **pre-cancelled token** short-circuits at the runner entry; no
  isolate is even spawned.
- The **`Isolate.kill()` grace path** (`timeout:` deadline elapsed,
  worker missed the 250 ms window) hard-kills the worker without
  giving it a chance to send its final `'stats'` message.

In both cases `CSP.lastStats` retains whatever value it had before the
call. Tests that depend on stats from a worker-isolate solve must run
the solve to natural completion.

### Errors from the builder

If the builder closure itself throws (a typo in a variable name, an
invalid constraint construction, anything that wasn't caught when you
wrote it), the exception surfaces on the main isolate as an
`IsolateRunnerException` carrying the message and a stringified stack
trace. The original exception object isn't reachable across the
boundary; it's stringified inside the worker before being sent.

### Platform note

The runner is not available on Dart Web — `dart:isolate` doesn't
exist there. The test file is `@TestOn('vm')` for the same reason.
Every other dart_csp surface continues to work on every platform Dart
supports.

## Common pitfalls

- **Forgetting that `'FAILURE'` is overloaded.** A solve that returns
  `'FAILURE'` could be unsatisfiable *or* cancelled. If you have a
  token in play, check `token.isCancelled`. Without that check, a
  timed-out solve looks indistinguishable from a proven-infeasible
  one.
- **Polling instead of registering a listener.** `addListener` is the
  cancellation-bridging primitive. If you're forwarding a parent
  cancel into some other async operation (an HTTP request, a
  WebSocket, a worker isolate, ...), wire it via `addListener` —
  don't `Timer.periodic` a poll loop.
- **Wrapping a worker-isolate solve in `.timeout()`.** It works in the
  sense that your caller returns on time, but the worker isolate keeps
  running. Use the built-in `timeout:` parameter so the worker
  actually gets killed.
- **Expecting `CSP.lastStats` after a hard-kill or pre-cancel.** The
  worker didn't flush its stats; the static slot keeps its previous
  value. Only run stats assertions on solves that completed naturally.
- **Capturing main-isolate state in a builder closure.** The Dart
  isolate boundary will complain at spawn time. If you need to
  parameterize the problem per call, route the parameters through
  sendable types (primitives, lists of primitives, top-level enums)
  and reconstruct inside the builder.
- **Sharing a token across multiple solves.** A `CancellationToken`
  is single-use — `isCancelled` flips once and stays. Cancelling the
  token aborts every solve currently watching it; subsequent solves
  passed the same token will short-circuit immediately. Allocate a
  fresh token per solve unless you actually want shared cancellation.

## See also

- The README's [Cancellation and Timeouts](../README.md#cancellation-and-timeouts)
  and [Solving on a worker isolate](../README.md#solving-on-a-worker-isolate)
  sections are the user-facing quick-reference.
- [`STABILITY.md`](../STABILITY.md) classifies `CancellationToken`,
  the `cancelToken:` parameters, and the isolate-runner entry points
  as experimental. The signature and behavior may change in a future
  release; the in-process solver entry points are stable.
- [`doc/algorithms.md`](algorithms.md) covers the rest of the solver
  pipeline — the cooperative checkpoint is one piece of a larger
  search loop.

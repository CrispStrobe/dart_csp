/// Worker-isolate runner: solves a [Problem] on a fresh background
/// isolate so a long CPU-bound search doesn't block the main
/// isolate's event loop.
///
/// The cooperative-checkpoint half of this story is already in
/// `solver.dart` ([CancellationToken] + `_checkpoint` yields). That
/// alone gives in-process callers responsive `.timeout(...)` and
/// fine-grained cancellation, but a long solve still uses all of
/// the calling isolate's CPU budget — no other Dart code makes
/// forward progress until the solver yields. This file's entry
/// points spawn a worker isolate, hand it a builder closure, run
/// the solve over there, and stream the result (plus the worker's
/// final [SolverStats]) back to the caller.
///
/// **Why a builder, not a `Problem`.** Constructed `Problem`
/// instances carry user-supplied predicate closures, which in the
/// general case are not safe to send across an isolate boundary
/// (a predicate may close over arbitrary main-isolate state, even
/// transitively). The runner therefore takes a `Problem Function()`
/// that runs inside the worker; the worker builds the `Problem`
/// locally, solves it, and only sends back primitive result types
/// (solution maps, `'FAILURE'`, [SolverStats]).
library;

import 'dart:async';
import 'dart:isolate';

import 'problem.dart';
import 'solver.dart';
import 'types.dart';

/// Solves a problem on a worker isolate and returns the first
/// satisfying assignment.
///
/// The [build] closure runs inside the worker; it must produce a
/// fully-configured [Problem] when called with no arguments. The
/// closure (and everything it captures transitively) must be
/// sendable across an isolate boundary; in practice this means
/// top-level / static functions or closures that only capture
/// other sendable values.
///
/// Returns a `Map<String, dynamic>` on success or the literal
/// `'FAILURE'` if the problem has no solution, was cancelled via
/// [cancelToken], or exceeded [timeout]. Throws if [build] itself
/// throws (the exception is rewrapped as an [IsolateRunnerException]
/// with the original message and stack trace as strings).
///
/// On normal completion the worker's [SolverStats] is copied into
/// the main isolate's [CSP.lastStats], so the documented
/// "stats are populated when the returned future resolves"
/// contract still holds. Stats are not copied when the runner
/// short-circuits on a pre-cancelled token or when [Isolate.kill]
/// fires under the timeout grace path (the worker had no chance to
/// flush them).
Future<dynamic> solveInIsolate(
  Problem Function() build, {
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  CancellationToken? cancelToken,
  Duration? timeout,
}) =>
    _runOne(
      build,
      _SolverKind.solveOne,
      consistency: consistency,
      cancelToken: cancelToken,
      timeout: timeout,
    );

/// Minimizes [objective] on a worker isolate. Mirrors
/// [Problem.minimize]; see [solveInIsolate] for the runner
/// semantics.
Future<dynamic> minimizeInIsolate(
  Problem Function() build,
  String objective, {
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  CancellationToken? cancelToken,
  Duration? timeout,
}) =>
    _runOne(
      build,
      _SolverKind.minimize,
      objective: objective,
      consistency: consistency,
      cancelToken: cancelToken,
      timeout: timeout,
    );

/// Maximizes [objective] on a worker isolate. Mirrors
/// [Problem.maximize]; see [solveInIsolate] for the runner
/// semantics.
Future<dynamic> maximizeInIsolate(
  Problem Function() build,
  String objective, {
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  CancellationToken? cancelToken,
  Duration? timeout,
}) =>
    _runOne(
      build,
      _SolverKind.maximize,
      objective: objective,
      consistency: consistency,
      cancelToken: cancelToken,
      timeout: timeout,
    );

/// Runs [Problem.solveWithLcg] across [workerCount] worker isolates as a
/// **portfolio**, each with a distinct [seeds] entry, and returns the first
/// definitive answer. Mirrors [solveInIsolate]'s contract: a
/// `Map<String, dynamic>` on success or `'FAILURE'` (UNSAT / cancelled /
/// timed out). The winning worker's [SolverStats] is copied into
/// [CSP.lastStats].
///
/// Portfolio semantics: the **first worker to find a solution wins** (the
/// rest are cancelled and torn down); the aggregate is `'FAILURE'` only
/// once *every* worker has exhausted its search, so a single cancelled or
/// timed-out worker can never be mistaken for a genuine UNSAT proof. If
/// every worker throws, the first error is rethrown as an
/// [IsolateRunnerException].
///
/// Workers default to [useVsids] so distinct [seeds] actually diversify
/// the search (MRV alone is deterministic and every worker would explore
/// the identical tree). Pass [shareClauses] to turn the portfolio into a
/// **cooperative** solver: each worker exports its short learned clauses
/// (≤ [maxSharedClauseLen] literals) to the parent, which re-broadcasts
/// them to the siblings; every worker imports the others' clauses into its
/// own learned-clause pool. Clause sharing is always sound — every worker
/// solves the same problem, so a clause learned by one is a valid nogood
/// for all.
///
/// [seeds] must have length [workerCount] when provided (defaults to
/// `0..workerCount-1`). [cancelToken] propagates to every worker; [timeout]
/// applies to the whole fleet.
Future<dynamic> solveWithLcgInIsolates(
  Problem Function() build, {
  int workerCount = 4,
  List<int>? seeds,
  bool useVsids = true,
  bool useDomWdeg = false,
  bool useIterativeCdcl = true,
  bool useRestarts = false,
  int restartScale = 100,
  int? learnedClauseCap,
  bool shareClauses = false,
  int maxSharedClauseLen = 8,
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  CancellationToken? cancelToken,
  Duration? timeout,
}) =>
    _runLcgParallel(
      build,
      workerCount: workerCount,
      seeds: seeds,
      useVsids: useVsids,
      useDomWdeg: useDomWdeg,
      useIterativeCdcl: useIterativeCdcl,
      useRestarts: useRestarts,
      restartScale: restartScale,
      learnedClauseCap: learnedClauseCap,
      shareClauses: shareClauses,
      maxSharedClauseLen: maxSharedClauseLen,
      consistency: consistency,
      cancelToken: cancelToken,
      timeout: timeout,
    );

/// Runs Large Neighborhood Search across [workerCount] worker
/// isolates in parallel, each seeded differently, and returns the
/// best result.
///
/// The default pattern is **portfolio LNS**: every worker runs an
/// independent [Problem.lnsMinimize] with its own RNG seed; the
/// parent collects results when all workers finish and returns the
/// worker that found the best objective.
///
/// Pass `cooperative: true` to enable **mid-run incumbent
/// broadcasting**: whenever any worker finds a new local best, the
/// parent forwards that objective bound to every sibling worker via
/// the existing control port. Siblings use it to pre-tighten the
/// objective domain of the next iteration's sub-problem, skipping
/// iterations that provably cannot beat the global best. Workers
/// remain independent in everything else (RNG, policy state,
/// incumbent solution) — only the objective bound crosses the
/// channel. The wire-protocol message is small (a single `num`) so
/// the broadcast overhead is negligible.
///
/// [build] runs inside each worker (the closure and everything it
/// captures must be sendable). [policyBuilder] / [acceptBuilder] are
/// likewise called inside each worker so stateful policies (e.g.
/// [LnsPolicy.adaptive], [LnsAccept.lateAcceptance]) get a fresh
/// instance per worker. If omitted, defaults are
/// [LnsPolicy.random()] and [LnsAccept.improving()].
///
/// [seeds] must have length [workerCount] when provided. When null,
/// workers get seeds `0..workerCount-1`.
///
/// [cancelToken] propagates to every worker. [timeout] applies to
/// the entire fleet — when it fires, every worker is signaled to
/// cancel and the parent returns the best result among the workers
/// that have already reported in. If all workers fail or are
/// cancelled before reporting, the returned [LnsParallelResult] has
/// `bestResult.solution == 'FAILURE'` and an empty `perWorker`.
Future<LnsParallelResult> lnsMinimizeInIsolates(
  Problem Function() build,
  String objective, {
  int workerCount = 4,
  LnsPolicy Function()? policyBuilder,
  LnsAccept Function()? acceptBuilder,
  int iterationBudget = 100,
  int? iterationTimeMs,
  int? totalTimeMs,
  List<int>? seeds,
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  bool enableConflictBackjumping = false,
  bool cooperative = false,
  CancellationToken? cancelToken,
  Duration? timeout,
}) =>
    _runLnsParallel(
      build,
      objective,
      minimizing: true,
      workerCount: workerCount,
      policyBuilder: policyBuilder,
      acceptBuilder: acceptBuilder,
      iterationBudget: iterationBudget,
      iterationTimeMs: iterationTimeMs,
      totalTimeMs: totalTimeMs,
      seeds: seeds,
      consistency: consistency,
      enableConflictBackjumping: enableConflictBackjumping,
      cooperative: cooperative,
      cancelToken: cancelToken,
      timeout: timeout,
    );

/// Symmetric to [lnsMinimizeInIsolates]. See that function for the
/// runner semantics, including the `cooperative:` flag.
Future<LnsParallelResult> lnsMaximizeInIsolates(
  Problem Function() build,
  String objective, {
  int workerCount = 4,
  LnsPolicy Function()? policyBuilder,
  LnsAccept Function()? acceptBuilder,
  int iterationBudget = 100,
  int? iterationTimeMs,
  int? totalTimeMs,
  List<int>? seeds,
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  bool enableConflictBackjumping = false,
  bool cooperative = false,
  CancellationToken? cancelToken,
  Duration? timeout,
}) =>
    _runLnsParallel(
      build,
      objective,
      minimizing: false,
      workerCount: workerCount,
      policyBuilder: policyBuilder,
      acceptBuilder: acceptBuilder,
      iterationBudget: iterationBudget,
      iterationTimeMs: iterationTimeMs,
      totalTimeMs: totalTimeMs,
      seeds: seeds,
      consistency: consistency,
      enableConflictBackjumping: enableConflictBackjumping,
      cooperative: cooperative,
      cancelToken: cancelToken,
      timeout: timeout,
    );

/// Result of [lnsMinimizeInIsolates] / [lnsMaximizeInIsolates]. The
/// [bestResult] field is the best [LnsResult] across all workers;
/// [perWorker] lists every worker's result in the same order as the
/// seeds passed in. Workers that timed out or were cancelled before
/// producing a feasible incumbent contribute an entry with
/// `solution: 'FAILURE'` and empty [LnsStats]; these never compare
/// favourably during best-pick.
class LnsParallelResult {
  LnsParallelResult({required this.bestResult, required this.perWorker});

  /// The best [LnsResult] across [perWorker]. Equivalent to picking
  /// the worker whose `stats.finalObjective` is best in the
  /// problem's optimisation direction.
  final LnsResult bestResult;

  /// Per-worker results, in seed order.
  final List<LnsResult> perWorker;
}

/// Streams every satisfying assignment of the problem built by
/// [build] from a worker isolate.
///
/// The worker pushes solutions over a [SendPort]; the returned
/// stream forwards them. Listener cancellation (`subscription
/// .cancel()`) signals the worker to abort and tears the isolate
/// down. On normal stream completion the worker's [SolverStats]
/// is copied into [CSP.lastStats] before the stream is closed,
/// matching the in-process [Problem.getSolutions] contract.
Stream<Map<String, dynamic>> solveAllInIsolate(
  Problem Function() build, {
  ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  CancellationToken? cancelToken,
  Duration? timeout,
}) {
  late StreamController<Map<String, dynamic>> controller;
  _IsolateSession? session;
  Timer? timer;

  void teardown() {
    timer?.cancel();
    session?.dispose();
  }

  controller = StreamController<Map<String, dynamic>>(
    onListen: () async {
      try {
        session = await _spawn(
          build: build,
          kind: _SolverKind.solveAll,
          consistency: consistency,
          objective: null,
          onMessage: (msg) {
            final list = msg as List;
            switch (list[0] as String) {
              case 'solution':
                if (!controller.isClosed) {
                  controller.add(list[1] as Map<String, dynamic>);
                }
              case 'stats':
                CSP.lastStats = list[1] as SolverStats;
              case 'done':
                teardown();
                if (!controller.isClosed) controller.close();
              case 'error':
                if (!controller.isClosed) {
                  controller.addError(IsolateRunnerException(
                      list[1] as String, list[2] as String));
                  controller.close();
                }
                teardown();
            }
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) {
              controller.addError(IsolateRunnerException('$e', '$st'));
              controller.close();
            }
            teardown();
          },
        );
      } catch (e, st) {
        controller.addError(IsolateRunnerException('$e', '$st'));
        await controller.close();
        return;
      }
      cancelToken?.addListener(session!.signalCancel);
      if (timeout != null) {
        timer = Timer(timeout, session!.timeOut);
      }
    },
    onCancel: () async {
      session?.signalCancel();
      teardown();
    },
  );
  return controller.stream;
}

/// Thrown by the isolate-runner entry points when the worker
/// raises (either inside the user-supplied [Problem] builder or
/// inside the solver). The original message and stack trace are
/// carried as strings; the original exception object is not
/// reachable across the isolate boundary in general.
class IsolateRunnerException implements Exception {
  IsolateRunnerException(this.message, [this.workerStackTrace]);

  /// String form of the exception raised inside the worker.
  final String message;

  /// String form of the stack trace from inside the worker, or
  /// `null` if none was supplied (e.g. on a spawn-time failure).
  final String? workerStackTrace;

  @override
  String toString() =>
      'IsolateRunnerException: $message${workerStackTrace == null ? '' : '\n$workerStackTrace'}';
}

// ---------------------------------------------------------------------------
// Internals.
// ---------------------------------------------------------------------------

enum _SolverKind {
  solveOne,
  solveAll,
  minimize,
  maximize,
  lnsMinimize,
  lnsMaximize,
  solveLcg,
}

/// Pre-allocated by the runner before spawn; carries everything the
/// worker needs to bootstrap. Sendable: [parentPort] is a
/// [SendPort], the rest are primitives or a sendable closure.
class _StartMessage {
  _StartMessage({
    required this.parentPort,
    required this.kind,
    required this.build,
    required this.consistency,
    required this.objective,
    this.lnsOpts,
    this.lcgOpts,
  });

  final SendPort parentPort;
  final _SolverKind kind;
  final Problem Function() build;
  final ConsistencyLevel consistency;
  final String? objective;
  final _LnsOpts? lnsOpts;
  final _LcgOpts? lcgOpts;
}

/// Per-worker LCG configuration. Carried in [_StartMessage] when
/// [_SolverKind.solveLcg] is set. All fields are primitives, so the
/// message is sendable.
class _LcgOpts {
  _LcgOpts({
    required this.useVsids,
    required this.useDomWdeg,
    required this.useIterativeCdcl,
    required this.useRestarts,
    required this.restartScale,
    required this.shareClauses,
    required this.maxSharedClauseLen,
    this.seed,
    this.learnedClauseCap,
  });

  final bool useVsids;
  final bool useDomWdeg;
  final bool useIterativeCdcl;
  final bool useRestarts;
  final int restartScale;
  final int? seed;
  final int? learnedClauseCap;

  /// When true, the worker exports each (short) learned clause to the
  /// parent via a `['clause', List<Atom>]` reply and imports clauses the
  /// parent broadcasts back from siblings. Off ⇒ pure portfolio.
  final bool shareClauses;

  /// Only learned clauses with at most this many literals are exported
  /// (short clauses are the high-value ones to share; long ones flood the
  /// channel for little gain — the standard parallel-SAT filter).
  final int maxSharedClauseLen;
}

/// Per-worker LNS configuration. Carried in [_StartMessage] when
/// [_SolverKind.lnsMinimize] / [_SolverKind.lnsMaximize] is set.
/// Policy and accept are passed as builders (constructed inside the
/// worker) so stateful instances can't accidentally be shared
/// across isolates.
class _LnsOpts {
  _LnsOpts({
    required this.iterationBudget,
    required this.enableConflictBackjumping,
    required this.cooperative,
    this.policyBuilder,
    this.acceptBuilder,
    this.iterationTimeMs,
    this.totalTimeMs,
    this.seed,
  });

  final LnsPolicy Function()? policyBuilder;
  final LnsAccept Function()? acceptBuilder;
  final int iterationBudget;
  final int? iterationTimeMs;
  final int? totalTimeMs;
  final int? seed;
  final bool enableConflictBackjumping;

  /// When true, the worker installs a `boundHint` / `onIncumbent`
  /// pair on its `lnsMinimize` / `lnsMaximize` call: the parent can
  /// push a `['bound', num]` control message to update the worker's
  /// best-known global bound (used to tighten future sub-problems),
  /// and the worker emits `['bound', num]` reply messages on every
  /// local improvement so the parent can re-broadcast to siblings.
  final bool cooperative;
}

/// Bundle of the live ports + isolate for one in-flight worker.
/// Owned by the runner; disposed when the worker terminates.
class _IsolateSession {
  _IsolateSession(this.isolate, this.replies, this.subscription, this.control);

  final Isolate isolate;
  final ReceivePort replies;
  final StreamSubscription<dynamic> subscription;
  final SendPort control;
  bool _disposed = false;

  void signalCancel() {
    try {
      control.send('cancel');
    } catch (_) {
      // Isolate may already be torn down; the kill in dispose()
      // handles the rest.
    }
  }

  void timeOut() {
    signalCancel();
    // Grace window for the worker to ship its 'result' /
    // 'FAILURE' reply over before we hard-kill. If the worker
    // misses the window we kill it; the outer future is already
    // being resolved with 'FAILURE' by the runner's timeout
    // handler.
    Timer(const Duration(milliseconds: 250), dispose);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      isolate.kill();
    } catch (_) {
      // Already dead.
    }
    // ignore: discarded_futures
    subscription.cancel();
    replies.close();
  }
}

/// Spawns the worker and installs the single message listener.
/// Returns once the worker has published its control [SendPort].
///
/// Only one listener can attach to a [ReceivePort], so the spawn
/// helper owns it: callers route every non-`ready` worker reply
/// through the [onMessage] callback they pass in.
Future<_IsolateSession> _spawn({
  required Problem Function() build,
  required _SolverKind kind,
  required ConsistencyLevel consistency,
  required String? objective,
  required void Function(dynamic message) onMessage,
  required void Function(Object error, StackTrace stackTrace) onError,
  _LnsOpts? lnsOpts,
  _LcgOpts? lcgOpts,
}) async {
  final replies = ReceivePort();
  final readyCompleter = Completer<SendPort>();

  final subscription = replies.listen(
    (m) {
      if (!readyCompleter.isCompleted &&
          m is List &&
          m.isNotEmpty &&
          m[0] == 'ready') {
        readyCompleter.complete(m[1] as SendPort);
        return;
      }
      onMessage(m);
    },
    onError: onError,
  );

  Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      _workerEntry,
      _StartMessage(
        parentPort: replies.sendPort,
        kind: kind,
        build: build,
        consistency: consistency,
        objective: objective,
        lnsOpts: lnsOpts,
        lcgOpts: lcgOpts,
      ),
      debugName: 'dart_csp.worker',
    );
  } catch (e) {
    await subscription.cancel();
    replies.close();
    rethrow;
  }

  // Wait for the worker to publish its control port. The session
  // becomes addressable for cancellation only after this point.
  final control = await readyCompleter.future;
  return _IsolateSession(isolate, replies, subscription, control);
}

Future<dynamic> _runOne(
  Problem Function() build,
  _SolverKind kind, {
  required ConsistencyLevel consistency,
  String? objective,
  CancellationToken? cancelToken,
  Duration? timeout,
}) async {
  if (cancelToken?.isCancelled ?? false) {
    // Mirror the in-process short-circuit in CSP.solveWithRestarts
    // (line ~143 of solver.dart): pre-cancel returns FAILURE
    // without doing any real work and without touching lastStats.
    return 'FAILURE';
  }

  final completer = Completer<dynamic>();
  SolverStats? pendingStats;

  final session = await _spawn(
    build: build,
    kind: kind,
    consistency: consistency,
    objective: objective,
    onMessage: (msg) {
      final list = msg as List;
      switch (list[0] as String) {
        case 'stats':
          pendingStats = list[1] as SolverStats;
        case 'result':
          if (pendingStats != null) {
            CSP.lastStats = pendingStats;
          }
          if (!completer.isCompleted) {
            completer.complete(list[1]);
          }
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(
                IsolateRunnerException(list[1] as String, list[2] as String));
          }
      }
    },
    onError: (Object e, StackTrace st) {
      if (!completer.isCompleted) {
        completer.completeError(IsolateRunnerException('$e', '$st'));
      }
    },
  );

  Timer? timer;
  cancelToken?.addListener(session.signalCancel);

  if (timeout != null) {
    timer = Timer(timeout, () {
      session.timeOut();
      if (!completer.isCompleted) completer.complete('FAILURE');
    });
  }

  try {
    return await completer.future;
  } finally {
    timer?.cancel();
    session.dispose();
  }
}

// ---------------------------------------------------------------------------
// Worker entry. Runs inside the spawned isolate. Must be top-level
// so it's sendable as a `Isolate.spawn` entry point.
// ---------------------------------------------------------------------------

void _workerEntry(_StartMessage start) async {
  final control = ReceivePort();
  final token = CancellationToken();

  // Cooperative-LNS bound cell, shared between the control listener
  // (which receives `['bound', num]` from the parent) and the
  // boundHint callback handed to lnsMinimize / lnsMaximize. Non-null
  // only when a `cooperative` lnsOpts is in play.
  num? cooperativeBound;

  // Cooperative-LCG inbox: clauses learned by sibling workers and
  // re-broadcast by the parent as `['clause', List<Atom>]`. The control
  // listener appends here on event-loop turns; the engine drains it
  // synchronously at each `_checkpoint` via the `importClauses` hook.
  final pendingClauses = <List<Atom>>[];

  control.listen((msg) {
    if (msg == 'cancel') {
      token.cancel();
      return;
    }
    if (msg is List && msg.isNotEmpty && msg[0] == 'bound') {
      final newBound = msg[1] as num;
      // Always take the strictly-better bound. The parent enforces the
      // direction-of-improvement filter before broadcasting, so a
      // worker can just overwrite whenever the value differs.
      cooperativeBound = newBound;
      return;
    }
    if (msg is List && msg.isNotEmpty && msg[0] == 'clause') {
      pendingClauses.add((msg[1] as List).cast<Atom>());
    }
  });
  start.parentPort.send(['ready', control.sendPort]);

  try {
    final problem = start.build();
    switch (start.kind) {
      case _SolverKind.solveOne:
        final result = await problem.getSolution(
            consistency: start.consistency, cancelToken: token);
        _sendStatsIfAny(start.parentPort);
        start.parentPort.send(['result', result]);
      case _SolverKind.minimize:
        final result = await problem.minimize(start.objective!,
            consistency: start.consistency, cancelToken: token);
        _sendStatsIfAny(start.parentPort);
        start.parentPort.send(['result', result]);
      case _SolverKind.maximize:
        final result = await problem.maximize(start.objective!,
            consistency: start.consistency, cancelToken: token);
        _sendStatsIfAny(start.parentPort);
        start.parentPort.send(['result', result]);
      case _SolverKind.solveAll:
        await for (final sol in problem.getSolutions(
            consistency: start.consistency, cancelToken: token)) {
          start.parentPort.send(['solution', sol]);
        }
        _sendStatsIfAny(start.parentPort);
        start.parentPort.send(const ['done']);
      case _SolverKind.lnsMinimize:
        final opts = start.lnsOpts!;
        final result = await problem.lnsMinimize(
          start.objective!,
          policy: opts.policyBuilder?.call(),
          accept: opts.acceptBuilder?.call(),
          iterationBudget: opts.iterationBudget,
          iterationTimeMs: opts.iterationTimeMs,
          totalTimeMs: opts.totalTimeMs,
          seed: opts.seed,
          consistency: start.consistency,
          enableConflictBackjumping: opts.enableConflictBackjumping,
          cancelToken: token,
          boundHint: opts.cooperative ? () => cooperativeBound : null,
          onIncumbent: opts.cooperative
              ? (b) {
                  try {
                    start.parentPort.send(['bound', b]);
                  } catch (_) {
                    // Parent gone; nothing to do.
                  }
                }
              : null,
        );
        start.parentPort.send(['lnsResult', result]);
      case _SolverKind.lnsMaximize:
        final opts = start.lnsOpts!;
        final result = await problem.lnsMaximize(
          start.objective!,
          policy: opts.policyBuilder?.call(),
          accept: opts.acceptBuilder?.call(),
          iterationBudget: opts.iterationBudget,
          iterationTimeMs: opts.iterationTimeMs,
          totalTimeMs: opts.totalTimeMs,
          seed: opts.seed,
          consistency: start.consistency,
          enableConflictBackjumping: opts.enableConflictBackjumping,
          cancelToken: token,
          boundHint: opts.cooperative ? () => cooperativeBound : null,
          onIncumbent: opts.cooperative
              ? (b) {
                  try {
                    start.parentPort.send(['bound', b]);
                  } catch (_) {
                    // Parent gone; nothing to do.
                  }
                }
              : null,
        );
        start.parentPort.send(['lnsResult', result]);
      case _SolverKind.solveLcg:
        final opts = start.lcgOpts!;
        final result = await problem.solveWithLcg(
          consistency: start.consistency,
          cancelToken: token,
          useVsids: opts.useVsids,
          useDomWdeg: opts.useDomWdeg,
          useIterativeCdcl: opts.useIterativeCdcl,
          useRestarts: opts.useRestarts,
          restartScale: opts.restartScale,
          seed: opts.seed,
          learnedClauseCap: opts.learnedClauseCap,
          // Cooperative clause sharing: export short learned clauses to the
          // parent (which re-broadcasts to siblings) and import the
          // siblings' clauses the parent has delivered into `pendingClauses`.
          onLearnedClause: opts.shareClauses
              ? (clause) {
                  if (clause.length > opts.maxSharedClauseLen) return;
                  try {
                    start.parentPort.send(['clause', clause]);
                  } catch (_) {
                    // Parent gone; nothing to do.
                  }
                }
              : null,
          importClauses: opts.shareClauses
              ? () {
                  if (pendingClauses.isEmpty) return const <List<Atom>>[];
                  final drained = List<List<Atom>>.of(pendingClauses);
                  pendingClauses.clear();
                  return drained;
                }
              : null,
        );
        _sendStatsIfAny(start.parentPort);
        start.parentPort.send(['result', result]);
    }
  } catch (e, st) {
    try {
      start.parentPort.send(['error', '$e', '$st']);
    } catch (_) {
      // Parent already gone; nothing to do.
    }
  } finally {
    control.close();
  }
}

/// Bundles a worker's running future, the [_IsolateSession] used to
/// talk to it, and a stable index so the cooperative orchestrator
/// can route `['bound', num]` broadcasts to siblings (every worker
/// except the one that just published).
class _LnsWorkerHandle {
  _LnsWorkerHandle({
    required this.future,
    required this.session,
    required this.index,
  });

  final Future<LnsResult> future;
  final _IsolateSession session;
  final int index;
}

/// Spawns one LNS worker and returns a handle bundling its future
/// plus the [_IsolateSession] (so the cooperative orchestrator can
/// push bound broadcasts to it). [onBound] fires whenever the
/// worker publishes a `['bound', num]` reply — non-null only in
/// cooperative mode.
Future<_LnsWorkerHandle> _spawnLnsWorker({
  required Problem Function() build,
  required String objective,
  required bool minimizing,
  required _LnsOpts opts,
  required ConsistencyLevel consistency,
  required int index,
  void Function(num bound)? onBound,
  CancellationToken? cancelToken,
  Duration? timeout,
}) async {
  final completer = Completer<LnsResult>();
  final session = await _spawn(
    build: build,
    kind: minimizing ? _SolverKind.lnsMinimize : _SolverKind.lnsMaximize,
    consistency: consistency,
    objective: objective,
    lnsOpts: opts,
    onMessage: (msg) {
      final list = msg as List;
      switch (list[0] as String) {
        case 'lnsResult':
          if (!completer.isCompleted) {
            completer.complete(list[1] as LnsResult);
          }
        case 'bound':
          onBound?.call(list[1] as num);
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(
                IsolateRunnerException(list[1] as String, list[2] as String));
          }
      }
    },
    onError: (Object e, StackTrace st) {
      if (!completer.isCompleted) {
        completer.completeError(IsolateRunnerException('$e', '$st'));
      }
    },
  );

  Timer? timer;
  cancelToken?.addListener(session.signalCancel);

  if (timeout != null) {
    timer = Timer(timeout, () {
      session.timeOut();
      // The worker may still ship a partial LnsResult before the
      // grace window expires; if it doesn't, complete with a
      // FAILURE-shaped result so the parent can keep aggregating.
      if (!completer.isCompleted) {
        completer.complete(LnsResult(solution: 'FAILURE', stats: LnsStats()));
      }
    });
  }

  // ignore: discarded_futures, unawaited_futures
  completer.future.whenComplete(() {
    timer?.cancel();
    session.dispose();
  });

  return _LnsWorkerHandle(
    future: completer.future,
    session: session,
    index: index,
  );
}

Future<LnsParallelResult> _runLnsParallel(
  Problem Function() build,
  String objective, {
  required bool minimizing,
  required int workerCount,
  required LnsPolicy Function()? policyBuilder,
  required LnsAccept Function()? acceptBuilder,
  required int iterationBudget,
  required int? iterationTimeMs,
  required int? totalTimeMs,
  required List<int>? seeds,
  required ConsistencyLevel consistency,
  required bool enableConflictBackjumping,
  required bool cooperative,
  required CancellationToken? cancelToken,
  required Duration? timeout,
}) async {
  if (workerCount <= 0) {
    throw ArgumentError('workerCount must be > 0; got $workerCount');
  }
  final seedList = seeds ?? [for (var i = 0; i < workerCount; i++) i];
  if (seedList.length != workerCount) {
    throw ArgumentError(
        'seeds.length (${seedList.length}) must match workerCount '
        '($workerCount)');
  }

  if (cancelToken?.isCancelled ?? false) {
    return LnsParallelResult(
      bestResult: LnsResult(solution: 'FAILURE', stats: LnsStats()),
      perWorker: const [],
    );
  }

  // Parent-side cooperative state. Holds the best objective heard
  // from any worker so far; re-broadcast to siblings only when a
  // newly-reported bound strictly improves it (in the optimisation
  // direction). Non-cooperative runs never read or write `globalBound`.
  num? globalBound;
  final handles = <_LnsWorkerHandle>[];

  void onBoundFromWorker(int sourceIndex, num bound) {
    if (!cooperative) return;
    final improved = globalBound == null ||
        (minimizing ? bound < globalBound! : bound > globalBound!);
    if (!improved) return;
    globalBound = bound;
    // Forward to every sibling. Routing through the worker's control
    // port reuses the same SendPort used for `'cancel'`, which the
    // worker's control listener already drains on its own
    // event-loop microtasks.
    for (final h in handles) {
      if (h.index == sourceIndex) continue;
      try {
        h.session.control.send(['bound', bound]);
      } catch (_) {
        // Worker may already have shut down; broadcast best-effort.
      }
    }
  }

  // Spawn workers sequentially so each handle is in `handles` before
  // any other worker can publish a bound that needs broadcasting to
  // it. The spawn itself is cheap (the `await` is on the worker's
  // ready signal); the inner LNS loops then run concurrently as
  // Futures.
  for (var i = 0; i < workerCount; i++) {
    final h = await _spawnLnsWorker(
      build: build,
      objective: objective,
      minimizing: minimizing,
      opts: _LnsOpts(
        iterationBudget: iterationBudget,
        enableConflictBackjumping: enableConflictBackjumping,
        cooperative: cooperative,
        policyBuilder: policyBuilder,
        acceptBuilder: acceptBuilder,
        iterationTimeMs: iterationTimeMs,
        totalTimeMs: totalTimeMs,
        seed: seedList[i],
      ),
      consistency: consistency,
      index: i,
      onBound: cooperative ? (b) => onBoundFromWorker(i, b) : null,
      cancelToken: cancelToken,
      timeout: timeout,
    );
    handles.add(h);
  }

  final perWorker = await Future.wait(handles.map((h) => h.future));

  // Pick best across workers. A worker that returned 'FAILURE' (no
  // initial feasible, or cancelled before finding one) is excluded
  // from the best-of picking.
  LnsResult? best;
  for (final r in perWorker) {
    if (r.solution is! Map) continue;
    if (best == null) {
      best = r;
      continue;
    }
    final ro = r.stats.finalObjective;
    final bo = best.stats.finalObjective;
    if (ro == null || bo == null) continue;
    final better = minimizing ? ro < bo : ro > bo;
    if (better) best = r;
  }
  return LnsParallelResult(
    bestResult: best ?? LnsResult(solution: 'FAILURE', stats: LnsStats()),
    perWorker: perWorker,
  );
}

Future<dynamic> _runLcgParallel(
  Problem Function() build, {
  required int workerCount,
  required List<int>? seeds,
  required bool useVsids,
  required bool useDomWdeg,
  required bool useIterativeCdcl,
  required bool useRestarts,
  required int restartScale,
  required int? learnedClauseCap,
  required bool shareClauses,
  required int maxSharedClauseLen,
  required ConsistencyLevel consistency,
  required CancellationToken? cancelToken,
  required Duration? timeout,
}) async {
  if (workerCount <= 0) {
    throw ArgumentError('workerCount must be > 0; got $workerCount');
  }
  final seedList = seeds ?? [for (var i = 0; i < workerCount; i++) i];
  if (seedList.length != workerCount) {
    throw ArgumentError(
        'seeds.length (${seedList.length}) must match workerCount '
        '($workerCount)');
  }
  if (cancelToken?.isCancelled ?? false) return 'FAILURE';

  final completer = Completer<dynamic>();
  final sessions = <_IsolateSession>[];
  final pendingStats = List<SolverStats?>.filled(workerCount, null);
  SolverStats? winnerStats;
  // Aggregation: complete on the first SAT; otherwise wait for every
  // worker to finish. `failCount` counts genuine UNSAT exhaustions and
  // `errorCount` counts crashes; once all `workerCount` are done we
  // return 'FAILURE' if at least one genuinely exhausted, else rethrow
  // the first error (every worker crashed → not a real UNSAT proof).
  var failCount = 0;
  var errorCount = 0;
  IsolateRunnerException? firstError;
  // Stats from a worker that genuinely exhausted (proved UNSAT); surfaced
  // as CSP.lastStats when the aggregate verdict is 'FAILURE'.
  SolverStats? failStats;

  void finish(dynamic result, SolverStats? stats) {
    if (completer.isCompleted) return;
    winnerStats = stats;
    completer.complete(result);
  }

  void noteDone() {
    if (failCount + errorCount < workerCount || completer.isCompleted) return;
    if (failCount > 0) {
      finish('FAILURE', failStats);
    } else {
      completer.completeError(firstError!);
    }
  }

  // Parent-side clause relay (B): re-broadcast a worker's exported clause
  // to every sibling so each worker imports the others' learned clauses.
  void onClauseFromWorker(int sourceIndex, List<dynamic> clause) {
    if (!shareClauses) return;
    for (var j = 0; j < sessions.length; j++) {
      if (j == sourceIndex) continue;
      try {
        sessions[j].control.send(['clause', clause]);
      } catch (_) {
        // Sibling already torn down; best-effort.
      }
    }
  }

  for (var i = 0; i < workerCount; i++) {
    final idx = i;
    final session = await _spawn(
      build: build,
      kind: _SolverKind.solveLcg,
      consistency: consistency,
      objective: null,
      lcgOpts: _LcgOpts(
        useVsids: useVsids,
        useDomWdeg: useDomWdeg,
        useIterativeCdcl: useIterativeCdcl,
        useRestarts: useRestarts,
        restartScale: restartScale,
        seed: seedList[i],
        learnedClauseCap: learnedClauseCap,
        shareClauses: shareClauses,
        maxSharedClauseLen: maxSharedClauseLen,
      ),
      onMessage: (msg) {
        final list = msg as List;
        switch (list[0] as String) {
          case 'stats':
            pendingStats[idx] = list[1] as SolverStats;
          case 'clause':
            onClauseFromWorker(idx, list[1] as List<dynamic>);
          case 'result':
            final r = list[1];
            if (r is Map<String, dynamic>) {
              finish(r, pendingStats[idx]);
            } else {
              failCount++;
              failStats ??= pendingStats[idx];
              noteDone();
            }
          case 'error':
            errorCount++;
            firstError ??=
                IsolateRunnerException(list[1] as String, list[2] as String);
            noteDone();
        }
      },
      onError: (Object e, StackTrace st) {
        errorCount++;
        firstError ??= IsolateRunnerException('$e', '$st');
        noteDone();
      },
    );
    sessions.add(session);
  }

  cancelToken?.addListener(() => finish('FAILURE', null));
  Timer? timer;
  if (timeout != null) {
    timer = Timer(timeout, () => finish('FAILURE', null));
  }

  try {
    final result = await completer.future;
    if (winnerStats != null) CSP.lastStats = winnerStats;
    return result;
  } finally {
    timer?.cancel();
    for (final s in sessions) {
      s.dispose();
    }
  }
}

void _sendStatsIfAny(SendPort port) {
  final stats = CSP.lastStats;
  if (stats != null) {
    try {
      port.send(['stats', stats]);
    } catch (_) {
      // Parent gone; the result message will fail to send too and
      // get handled in the outer catch in _workerEntry.
    }
  }
}

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

enum _SolverKind { solveOne, solveAll, minimize, maximize }

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
  });

  final SendPort parentPort;
  final _SolverKind kind;
  final Problem Function() build;
  final ConsistencyLevel consistency;
  final String? objective;
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
  control.listen((msg) {
    if (msg == 'cancel') token.cancel();
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

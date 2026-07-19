/// These tests assert that cancellation *short-circuits the search*. The
/// honest measure of that is work done — decisions, backtracks, iterations —
/// not wall-clock time.
///
/// Earlier revisions asserted `stopwatch.elapsed < 10s`. That conflates two
/// different failures: cancellation not working, and the machine being busy.
/// On a loaded host these tests failed while cancellation was working
/// perfectly — one measured run took 10.7s wall-clock while reporting the
/// exact same 1520 decisions / 4218 backtracks as a 5.3s run on the same
/// input. Work counters are deterministic across those runs; wall-clock is
/// not, so wall-clock is the wrong assertion.
///
/// The bounds below are set roughly 20-50x above the work a cancelled run
/// actually does (measured, and noted per test), and far below what an
/// uncancelled search would reach. A faster machine does *more* work before
/// the cancel timer fires, so the headroom is on the correct side.
///
/// The suite-wide timeout that keeps these from being killed mid-run under
/// load lives in `dart_test.yaml`.
library;

import 'dart:async';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// N-queens encoded with predicate-only binary constraints (no
/// `allDifferent` shortcut, no symmetry breaking). For modest `n`
/// (e.g. 12) the engine still finishes fast, but for tight infeasible
/// variants (see [_hardInfeasible]) the search tree blows up enough
/// that cancellation has obvious effect.
Problem _queens(int n) {
  final p = Problem();
  final cols = [for (var i = 0; i < n; i++) 'q$i'];
  p.addVariables(cols, [for (var c = 0; c < n; c++) c]);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final di = j - i;
      p.addConstraint(
        [cols[i], cols[j]],
        (dynamic a, dynamic b) =>
            a != b && (a as int) - (b as int) != di && a - b != -di,
      );
    }
  }
  return p;
}

/// A predicate-only infeasible problem the engine cannot prove
/// infeasible without enumerating an exponential subtree: every leaf
/// fails the always-false n-ary predicate but propagation cannot
/// detect this above the workBound. This is the standard recipe for
/// a CPU-bound CSP that exercises the cancellation path.
Problem _hardInfeasible({int n = 20, int k = 6}) {
  final p = Problem();
  final names = [for (var i = 0; i < n; i++) 'x$i'];
  p.addVariables(names, [for (var v = 0; v < k; v++) v]);
  // Light binary constraints to keep propagation cheap.
  for (var i = 0; i < n - 1; i++) {
    p.addStringConstraint('${names[i]} != ${names[i + 1]}');
  }
  // Heavy n-ary predicate that always rejects: the engine has no way
  // to prove this above the work bound, so search must enumerate.
  p.addConstraint(names, (_) => false);
  return p;
}

void main() {
  group('CancellationToken', () {
    test('starts uncancelled, cancel() flips isCancelled', () {
      final t = CancellationToken();
      expect(t.isCancelled, isFalse);
      t.cancel();
      expect(t.isCancelled, isTrue);
    });

    test('cancel() is idempotent', () {
      final t = CancellationToken()..cancel();
      t.cancel();
      t.cancel();
      expect(t.isCancelled, isTrue);
    });
  });

  group('Problem.getSolution with cancellation', () {
    test('pre-cancelled token short-circuits to FAILURE', () async {
      final p = _queens(4);
      final token = CancellationToken()..cancel();
      final result = await p.getSolution(cancelToken: token);
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
    });

    test('uncancelled token does not affect feasible solve', () async {
      final p = _queens(4);
      final token = CancellationToken();
      final result = await p.getSolution(cancelToken: token);
      expect(result, isA<Map<String, dynamic>>());
      expect(token.isCancelled, isFalse);
    });

    test('cancel mid-search via Timer returns FAILURE', () async {
      final p = _hardInfeasible();
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 100), token.cancel);
      final result = await p.getSolution(cancelToken: token);
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // Enumerating this tree completely runs into the millions of
      // decisions; a cancelled run stops in the hundreds.
      expect(p.lastStats!.decisions, lessThan(20000),
          reason: 'cancel must abort search, not run the tree to exhaustion');
    });
  });

  group('Future.timeout integration', () {
    test('.timeout() fires on a CPU-bound solve', () async {
      // The user-visible payoff of the cooperative yield: a wrapping
      // `.timeout(...)` actually fires even though the engine is
      // otherwise CPU-bound.
      final p = _hardInfeasible();
      final sw = Stopwatch()..start();
      Object? caught;
      try {
        await p.getSolution().timeout(const Duration(milliseconds: 200));
      } catch (e) {
        caught = e;
      }
      sw.stop();
      expect(caught, isA<TimeoutException>(),
          reason: 'cooperative yield must let .timeout() fire');
      // Catching TimeoutException is itself the proof that `.timeout()` fired
      // rather than the search running to completion, so this bound is only a
      // backstop against the await hanging. Deliberately loose: a tight bound
      // here measures host load, not engine behaviour.
      expect(sw.elapsed, lessThan(const Duration(seconds: 60)),
          reason: 'timeout must trip rather than block until search ends');
    });
  });

  group('Problem.getSolutions stream with cancellation', () {
    test('cancellation aborts the stream early', () async {
      // Large unconstrained enumeration. Without cancel this would
      // emit 5^7 = 78125 solutions; with cancel we expect far fewer.
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd', 'e', 'f', 'g'], [1, 2, 3, 4, 5]);
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 50), token.cancel);
      final got = <Map<String, dynamic>>[];
      try {
        await for (final s in p.getSolutions(cancelToken: token)) {
          got.add(s);
        }
      } on Object {
        // The stream may or may not throw on cancel; either shape
        // is fine — what we care about is that it stopped early.
      }
      expect(token.isCancelled, isTrue);
      expect(got.length, lessThan(78125),
          reason: 'cancel must abort before full enumeration');
    });

    test('pre-cancelled token yields empty stream', () async {
      final p = _queens(4);
      final token = CancellationToken()..cancel();
      final got = await p.getSolutions(cancelToken: token).toList();
      expect(got, isEmpty);
    });
  });

  group('Optimization with cancellation', () {
    test('cancel during optimize returns FAILURE', () async {
      // Build a hard optimization with the same "infeasible n-ary"
      // recipe — but include the objective in the variable set so the
      // engine still does meaningful work before the cancel fires.
      final p = _hardInfeasible();
      p.addVariable('obj', [for (var i = 0; i < 100; i++) i]);
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 100), token.cancel);
      final result = await p.maximize('obj', cancelToken: token);
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // Measured: a cancelled run reports 100 decisions / 450 backtracks.
      expect(p.lastStats!.decisions, lessThan(20000),
          reason: 'cancel must abort the optimize loop');
    });
  });

  group('solveWithMinConflicts with cancellation', () {
    test('cancel aborts a long min-conflicts run', () async {
      // Inherently infeasible 3-coloring (cycle of length 3 with
      // 2 colors): min-conflicts can never satisfy it, so without
      // cancellation it runs the full step budget.
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [0, 1])
        ..addStringConstraint('a != b')
        ..addStringConstraint('b != c')
        ..addStringConstraint('c != a');
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 100), token.cancel);
      final result = await p.solveWithMinConflicts(
        maxSteps: 100000000,
        cancelToken: token,
      );
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // The run must stop well short of the 100-million-step budget.
      // Measured: a cancelled run lands around 130-140k iterations, so this
      // bound has ~70x headroom while still proving the budget was abandoned.
      expect(p.lastStats!.iterations, lessThan(10000000),
          reason: 'cancel must abort before the step budget is exhausted');
    });

    test('pre-cancelled token returns FAILURE without iterating', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addStringConstraint('a != b');
      final token = CancellationToken()..cancel();
      final result = await p.solveWithMinConflicts(cancelToken: token);
      expect(result, equals('FAILURE'));
      expect(p.lastStats?.iterations, equals(0));
    });
  });

  group('Problem.getSolutionWithRestarts with cancellation', () {
    test('cancel between/within restart attempts returns FAILURE', () async {
      final p = _hardInfeasible(n: 18, k: 5);
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 100), token.cancel);
      final result = await p.getSolutionWithRestarts(
        scale: 20,
        cancelToken: token,
      );
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // This bound also pins a responsiveness fix, so it is deliberately
      // tight. The restart loop runs many short attempts, each a fresh
      // engine whose internal event-loop yield only fires after 100
      // decisions — far more than an early Luby budget allows. Before the
      // fix the loop never ceded the event loop, so the Timer that sets the
      // token could not fire until a late, large attempt happened to yield:
      // the run did a machine-INDEPENDENT 1520 decisions regardless of
      // whether the cancel was requested at 100ms or at 1s. The loop now
      // yields once per attempt, so a 100ms cancel is observed after tens of
      // decisions (15-50 measured), scaling with the cancel delay rather
      // than sitting at a fixed floor. 1000 sits well below the old 1520
      // floor and far above the observed range even allowing for much
      // faster hardware (~0.3 decisions/ms of search).
      expect(p.lastStats!.decisions, lessThan(1000),
          reason: 'cancel must be observed within an attempt, not deferred '
              'to a late large Luby budget');
    });
  });

  group('Problem.getSolutionWithDomWdeg with cancellation', () {
    test('cancellation aborts dom/wdeg search', () async {
      final p = _hardInfeasible(n: 18, k: 5);
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 100), token.cancel);
      final result = await p.getSolutionWithDomWdeg(cancelToken: token);
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // Measured: 100 decisions at cancel@100ms, 800 at cancel@5s — the
      // n-ary propagation makes each decision expensive, so the count climbs
      // slowly and this bound corresponds to minutes of uninterrupted search.
      expect(p.lastStats!.decisions, lessThan(20000),
          reason: 'cancel must abort dom/wdeg search');
    });
  });
}

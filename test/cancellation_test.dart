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
      final sw = Stopwatch()..start();
      final result = await p.getSolution(cancelToken: token);
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // Generous upper bound. Without cancellation the same problem
      // would take many seconds to enumerate completely.
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)),
          reason: 'cancel should abort search within seconds');
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
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)),
          reason: 'timeout must trip within seconds, not after the '
              'search runs to completion');
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
      final sw = Stopwatch()..start();
      final result = await p.maximize('obj', cancelToken: token);
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
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
      final sw = Stopwatch()..start();
      final result = await p.solveWithMinConflicts(
        maxSteps: 100000000,
        cancelToken: token,
      );
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
      // The run should have stopped well before exhausting the
      // 100-million-step budget.
      expect(p.lastStats!.iterations, lessThan(100000000));
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
      final sw = Stopwatch()..start();
      final result = await p.getSolutionWithRestarts(
        scale: 20,
        cancelToken: token,
      );
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      // Generous bound to absorb CI variance. The same problem
      // without cancel would take many minutes — anything under a
      // minute is firmly "cancel worked".
      expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
    });
  });

  group('Problem.getSolutionWithDomWdeg with cancellation', () {
    test('cancellation aborts dom/wdeg search', () async {
      final p = _hardInfeasible(n: 18, k: 5);
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 100), token.cancel);
      final sw = Stopwatch()..start();
      final result = await p.getSolutionWithDomWdeg(cancelToken: token);
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}

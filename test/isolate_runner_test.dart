@TestOn('vm')
library;

import 'dart:async';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// All builder functions used by these tests are top-level so they
// are unambiguously sendable across the isolate boundary. Closures
// over local state in the test bodies are not guaranteed to be.

Problem buildSmallSat() {
  final p = Problem();
  p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4]);
  p.addAllDifferent(['A', 'B', 'C']);
  p.addConstraint(
      ['A', 'B'], (dynamic a, dynamic b) => (a as int) < (b as int));
  p.addConstraint(
      ['B', 'C'], (dynamic b, dynamic c) => (b as int) < (c as int));
  return p;
}

Problem buildInfeasible() {
  final p = Problem();
  p.addVariables(['A', 'B'], [1, 2]);
  // Force a contradiction so 'FAILURE' is the only possible outcome.
  p.addConstraint(['A', 'B'], (dynamic a, dynamic b) => a == b);
  p.addConstraint(['A', 'B'], (dynamic a, dynamic b) => a != b);
  return p;
}

Problem buildAllDifferentSmall() {
  final p = Problem();
  p.addVariables(['X', 'Y'], [1, 2]);
  p.addAllDifferent(['X', 'Y']);
  return p;
}

Problem buildOptimization() {
  final p = Problem();
  p.addVariables(['A', 'B'], [1, 2, 3, 4, 5]);
  p.addConstraint(
      ['A', 'B'], (dynamic a, dynamic b) => (a as int) < (b as int));
  p.addStringConstraint('A + B == 7');
  return p;
}

Problem buildHardInfeasible() {
  // Same recipe used in cancellation_test.dart for a CPU-bound
  // infeasible problem: the engine cannot prove infeasibility above
  // the work bound so it must enumerate.
  final p = Problem();
  final names = [for (var i = 0; i < 20; i++) 'x$i'];
  p.addVariables(names, [for (var v = 0; v < 6; v++) v]);
  for (var i = 0; i < names.length - 1; i++) {
    p.addStringConstraint('${names[i]} != ${names[i + 1]}');
  }
  p.addConstraint(names, (_) => false);
  return p;
}

Problem buildAlwaysThrows() {
  throw StateError('builder failed on purpose');
}

void main() {
  group('solveInIsolate', () {
    test('returns a valid solution for a feasible problem', () async {
      final result = await solveInIsolate(buildSmallSat);
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect(m['A'] as int, lessThan(m['B'] as int));
      expect(m['B'] as int, lessThan(m['C'] as int));
    });

    test('returns FAILURE for an infeasible problem', () async {
      final result = await solveInIsolate(buildInfeasible);
      expect(result, equals('FAILURE'));
    });

    test('writes worker stats into main isolates CSP.lastStats', () async {
      CSP.lastStats = null;
      await solveInIsolate(buildSmallSat);
      expect(CSP.lastStats, isNotNull);
      expect(CSP.lastStats!.elapsedMicros, greaterThan(0));
    });

    test('pre-cancelled token short-circuits to FAILURE', () async {
      final token = CancellationToken()..cancel();
      final result = await solveInIsolate(buildSmallSat, cancelToken: token);
      expect(result, equals('FAILURE'));
    });

    test('mid-search cancel via bridged token returns FAILURE', () async {
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 150), token.cancel);
      final sw = Stopwatch()..start();
      final result =
          await solveInIsolate(buildHardInfeasible, cancelToken: token);
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(token.isCancelled, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 15)),
          reason: 'cancel should abort isolate search within seconds');
    });

    test('built-in timeout aborts a long search', () async {
      final sw = Stopwatch()..start();
      final result = await solveInIsolate(buildHardInfeasible,
          timeout: const Duration(milliseconds: 200));
      sw.stop();
      expect(result, equals('FAILURE'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
    });

    test('a builder that throws surfaces as IsolateRunnerException', () async {
      await expectLater(
        () => solveInIsolate(buildAlwaysThrows),
        throwsA(isA<IsolateRunnerException>()),
      );
    });
  });

  group('solveAllInIsolate', () {
    test('streams every solution and closes cleanly', () async {
      final solutions = <Map<String, dynamic>>[];
      await for (final s in solveAllInIsolate(buildAllDifferentSmall)) {
        solutions.add(s);
      }
      // Two variables, domain {1, 2}, all-different => exactly two
      // assignments: (X=1, Y=2) and (X=2, Y=1).
      expect(solutions, hasLength(2));
      final pairs = solutions.map((s) => '${s['X']}-${s['Y']}').toSet();
      expect(pairs, equals({'1-2', '2-1'}));
    });

    test('cancel via listener.cancel() tears the worker down', () async {
      final stream = solveAllInIsolate(buildHardInfeasible);
      final sub = stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final sw = Stopwatch()..start();
      await sub.cancel();
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'subscription cancel should return quickly');
    });
  });

  group('minimizeInIsolate / maximizeInIsolate', () {
    test('minimize picks the smallest feasible objective', () async {
      final result = await minimizeInIsolate(buildOptimization, 'A');
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      // A < B and A + B == 7, A,B in [1..5].
      // Feasible (A,B): (2,5), (3,4). Minimum A = 2.
      expect(m['A'], equals(2));
      expect(m['B'], equals(5));
    });

    test('maximize picks the largest feasible objective', () async {
      final result = await maximizeInIsolate(buildOptimization, 'A');
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect(m['A'], equals(3));
      expect(m['B'], equals(4));
    });
  });
}

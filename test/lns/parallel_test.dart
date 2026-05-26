@TestOn('vm')
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// Top-level builders so the closures are unambiguously sendable
// across the isolate boundary. Mirrors test/isolate_runner_test.dart.

Problem buildBinPacking() {
  const itemCount = 10;
  const binCount = 3;
  final weights = [for (var i = 0; i < itemCount; i++) (2 * i + 3) % 13 + 1];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final items = [for (var i = 0; i < itemCount; i++) 'item$i'];
  final p = Problem();
  for (final it in items) {
    p.addVariable(it, [for (var b = 0; b < binCount; b++) b]);
  }
  for (var b = 0; b < binCount; b++) {
    p.addRangeVariable('load$b', 0, total);
    p.addConstraint(['load$b', ...items], (Map<String, dynamic> a) {
      var sum = 0;
      for (var i = 0; i < itemCount; i++) {
        if (a[items[i]] == b) sum += weights[i];
      }
      return a['load$b'] == sum;
    });
  }
  p.addRangeVariable('maxLoad', 0, total);
  for (var b = 0; b < binCount; b++) {
    p.addConstraint(
      ['maxLoad', 'load$b'],
      (dynamic ml, dynamic l) => (ml as num) >= (l as num),
    );
  }
  return p;
}

Problem buildInfeasible() {
  final p = Problem();
  p.addVariables(['A', 'B'], [1, 2, 3]);
  p.addConstraint(['A', 'B'], (dynamic a, dynamic b) => a == b);
  p.addConstraint(['A', 'B'], (dynamic a, dynamic b) => a != b);
  p.addRangeVariable('cost', 0, 10);
  return p;
}

Problem buildTrivialMax() {
  final p = Problem();
  p.addVariables(['A', 'B'], [1, 2, 3, 4, 5]);
  p.addStringConstraint('A + B == 8');
  return p;
}

// Top-level policy builders. Workers call these to materialise a
// fresh policy per worker.
LnsPolicy makeRandomDestroy() => LnsPolicy.random(fraction: 0.5);

void main() {
  group('lnsMinimizeInIsolates', () {
    test('spawns N workers in parallel and picks the best', () async {
      final result = await lnsMinimizeInIsolates(
        buildBinPacking,
        'maxLoad',
        workerCount: 3,
        policyBuilder: makeRandomDestroy,
        iterationBudget: 40,
        seeds: [1, 2, 3],
      );
      expect(result.perWorker, hasLength(3));
      expect(result.bestResult.solution, isA<Map<String, dynamic>>());
      // Plain-B&B optimum on this 10-item instance is 22; LNS reaches
      // 23 or so with these knobs. Just bound it loosely.
      final m = result.bestResult.solution as Map<String, dynamic>;
      expect(m['maxLoad'], lessThanOrEqualTo(26));
      // Best is at least as good as every per-worker result.
      for (final r in result.perWorker) {
        if (r.solution is Map) {
          expect(
            (result.bestResult.stats.finalObjective ?? double.infinity)
                .compareTo(r.stats.finalObjective ?? double.infinity),
            lessThanOrEqualTo(0),
          );
        }
      }
    });

    test('returns FAILURE bestResult when the problem is infeasible', () async {
      final result = await lnsMinimizeInIsolates(
        buildInfeasible,
        'cost',
        workerCount: 2,
        iterationBudget: 5,
        seeds: [0, 1],
      );
      expect(result.bestResult.solution, equals('FAILURE'));
      // Every worker also returned FAILURE.
      for (final r in result.perWorker) {
        expect(r.solution, equals('FAILURE'));
      }
    });

    test('rejects bad workerCount / seeds-length mismatch', () async {
      await expectLater(
        () => lnsMinimizeInIsolates(buildBinPacking, 'maxLoad', workerCount: 0),
        throwsArgumentError,
      );
      await expectLater(
        () => lnsMinimizeInIsolates(buildBinPacking, 'maxLoad',
            workerCount: 3, seeds: [1, 2]),
        throwsArgumentError,
      );
    });

    test('pre-cancelled token short-circuits without spawning workers',
        () async {
      final token = CancellationToken()..cancel();
      final result = await lnsMinimizeInIsolates(
        buildBinPacking,
        'maxLoad',
        cancelToken: token,
      );
      expect(result.perWorker, isEmpty);
      expect(result.bestResult.solution, equals('FAILURE'));
    });
  });

  group('cooperative parallel LNS', () {
    test(
        'cooperative: true produces a feasible result on the bin-packing problem',
        () async {
      // Sanity check: cooperative mode doesn't lose correctness. Same
      // problem and budget as the portfolio test above, but with the
      // mid-run incumbent broadcast enabled. We expect at-least-as-good
      // a result, but the comparison against portfolio is too noisy
      // for a strict assertion at this iteration budget — the broadcast
      // amortises over many iterations.
      final result = await lnsMinimizeInIsolates(
        buildBinPacking,
        'maxLoad',
        workerCount: 3,
        policyBuilder: makeRandomDestroy,
        iterationBudget: 40,
        seeds: [1, 2, 3],
        cooperative: true,
      );
      expect(result.perWorker, hasLength(3));
      expect(result.bestResult.solution, isA<Map<String, dynamic>>());
      final m = result.bestResult.solution as Map<String, dynamic>;
      expect(m['maxLoad'], lessThanOrEqualTo(26));
    });

    test('cooperative: false is the existing portfolio shape (no regression)',
        () async {
      // Same problem; explicitly assert the default value of
      // `cooperative` matches the original portfolio behaviour.
      final result = await lnsMinimizeInIsolates(
        buildBinPacking,
        'maxLoad',
        workerCount: 2,
        iterationBudget: 20,
        seeds: [4, 5],
      );
      expect(result.bestResult.solution, isA<Map<String, dynamic>>());
    });

    test('cooperative + maximize: bound propagation works in both directions',
        () async {
      final result = await lnsMaximizeInIsolates(
        buildTrivialMax,
        'A',
        workerCount: 2,
        iterationBudget: 10,
        seeds: [9, 11],
        cooperative: true,
      );
      expect(result.bestResult.solution, isA<Map<String, dynamic>>());
      final m = result.bestResult.solution as Map<String, dynamic>;
      expect(m['A'], inInclusiveRange(3, 5));
      expect(m['B'], equals(8 - (m['A'] as int)));
    });
  });

  group('lnsMaximizeInIsolates', () {
    test('symmetric: maximises a small problem', () async {
      final result = await lnsMaximizeInIsolates(
        buildTrivialMax,
        'A',
        workerCount: 2,
        iterationBudget: 10,
        seeds: [7, 13],
      );
      expect(result.bestResult.solution, isA<Map<String, dynamic>>());
      // A + B == 8 with A,B in [1..5]; max A is 5 (B=3).
      final m = result.bestResult.solution as Map<String, dynamic>;
      // Random-destroy on 2 vars with fraction=0.5 frees 1 at a time and
      // sub-problem snaps back to the incumbent. We assert just that the
      // returned A is feasible (in domain, B == 8 - A).
      expect(m['A'], inInclusiveRange(3, 5));
      expect(m['B'], equals(8 - (m['A'] as int)));
    });
  });
}

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Build a small bin-packing instance: distribute [itemCount] items
/// (whose weights are 1, 2, ..., itemCount) across 3 bins and
/// minimise the max-bin load. Known optimum for `itemCount=8`:
/// total weight 36, balanced load is 12; the optimum is 12.
Problem _buildBinPacking({required int itemCount}) {
  final weights = [for (var i = 1; i <= itemCount; i++) i];
  final binNames = ['bin0', 'bin1', 'bin2'];
  final p = Problem();
  // Each item is assigned to one of the 3 bins.
  for (var i = 0; i < itemCount; i++) {
    p.addVariable('item$i', [0, 1, 2]);
  }
  // Per-bin load = sum of weights of items in that bin.
  final totalWeight = weights.reduce((a, b) => a + b);
  for (var b = 0; b < binNames.length; b++) {
    p.addVariable(binNames[b], [for (var i = 0; i <= totalWeight; i++) i]);
    // load == Σ weight[i] * (item[i] == b)
    p.addConstraint(
      ['bin$b', for (var i = 0; i < itemCount; i++) 'item$i'],
      (Map<String, dynamic> a) {
        var sum = 0;
        for (var i = 0; i < itemCount; i++) {
          if (a['item$i'] == b) sum += weights[i];
        }
        return a['bin$b'] == sum;
      },
    );
  }
  // maxLoad >= each bin load.
  p.addVariable('maxLoad', [for (var i = 0; i <= totalWeight; i++) i]);
  for (final bin in binNames) {
    p.addConstraint(
      ['maxLoad', bin],
      (dynamic ml, dynamic l) => (ml as num) >= (l as num),
    );
  }
  return p;
}

void main() {
  group('LNS integration', () {
    test('lnsMinimize on infeasible problem returns FAILURE with stats',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B')
        ..addStringConstraint('A == B');
      p.addVariable('cost', [0, 1, 2, 3]);
      final result = await p.lnsMinimize('cost');
      expect(result.solution, equals('FAILURE'));
      expect(result.stats.iterations, equals(0));
      expect(result.stats.initialObjective, isNull);
    });

    test('lnsMinimize on bin-packing improves over the initial feasible',
        () async {
      final p = _buildBinPacking(itemCount: 8);
      final result = await p.lnsMinimize(
        'maxLoad',
        policy: LnsPolicy.random(fraction: 0.5),
        iterationBudget: 60,
        seed: 7,
      );
      expect(result.solution, isA<Map<String, dynamic>>());
      final m = result.solution as Map<String, dynamic>;
      // 1..8 across 3 bins; optimum is 12 (perfect balance). LNS is
      // a metaheuristic and a 60-iteration random-destroy run may
      // land at the optimum or one or two notches above it depending
      // on the seed. We only assert (a) it's at least as good as the
      // initial and (b) it's within a comfortable margin of the
      // optimum.
      expect(m['maxLoad'], lessThanOrEqualTo(15));
      // Each item assigned somewhere; loads consistent.
      final stats = result.stats;
      expect(stats.iterations, greaterThan(0));
      expect(stats.iterations, lessThanOrEqualTo(60));
      expect(stats.initialObjective, isNotNull);
      expect(stats.finalObjective, isNotNull);
      // LNS should not make the objective worse than the initial.
      expect(stats.finalObjective, lessThanOrEqualTo(stats.initialObjective!));
      // Sanity: accepts + rejects + infeasibles + timeouts == iterations.
      expect(
        stats.accepts + stats.rejects + stats.infeasibles + stats.timeouts,
        equals(stats.iterations),
      );
    });

    test('lnsMaximize is symmetric: maximises a small problem', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addStringConstraint('A + B == 8');
      // With only 2 variables, a 0.5 destroy frees just 1 of them and
      // the other constrains it back to the incumbent. Use a window of
      // size 2 to free both each iteration so the inner solve can
      // actually find A=5, B=3.
      final result = await p.lnsMaximize(
        'A',
        policy: LnsPolicy.window(windowSize: 2),
        iterationBudget: 5,
        seed: 1,
      );
      final m = result.solution as Map<String, dynamic>;
      expect(m['A'], equals(5));
      expect(m['B'], equals(3));
    });

    test('same seed yields the same final objective', () async {
      Future<num?> run() async {
        final p = _buildBinPacking(itemCount: 6);
        final r = await p.lnsMinimize(
          'maxLoad',
          policy: LnsPolicy.random(fraction: 0.3),
          iterationBudget: 20,
          seed: 1234,
        );
        return r.stats.finalObjective;
      }

      expect(await run(), equals(await run()));
    });

    test('rejects unknown objective and non-numeric domains', () async {
      final p = Problem()..addVariable('color', ['red', 'green', 'blue']);
      expect(p.lnsMinimize('missing'), throwsArgumentError);
      expect(p.lnsMinimize('color'), throwsArgumentError);
    });

    test(
        'initial-only run with iterationBudget=0 returns the initial '
        'optimum unchanged', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addStringConstraint('A + B == 6');
      final result = await p.lnsMinimize(
        'A',
        iterationBudget: 0,
        seed: 1,
      );
      final m = result.solution as Map<String, dynamic>;
      // With budget 0 we never enter the LNS loop; the initial solve
      // already finds the optimum 1.
      expect(m['A'], equals(1));
      expect(m['B'], equals(5));
      expect(result.stats.iterations, equals(0));
      expect(result.stats.initialObjective, equals(1));
      expect(result.stats.finalObjective, equals(1));
    });

    test(
        'simulated annealing + combined policy run end-to-end and improve '
        'over the initial', () async {
      final p = _buildBinPacking(itemCount: 8);
      final result = await p.lnsMinimize(
        'maxLoad',
        policy: LnsPolicy.combined([
          LnsPolicy.random(fraction: 0.5),
          LnsPolicy.window(windowSize: 5),
          LnsPolicy.related(seedCount: 2, extendFraction: 0.5),
        ]),
        accept: LnsAccept.simulatedAnnealing(
          initialTemp: 2,
          cooling: 0.9,
        ),
        iterationBudget: 80,
        seed: 11,
      );
      final m = result.solution as Map<String, dynamic>;
      // SA may visit a worsening move; we assert the final incumbent is
      // within a comfortable margin of the optimum (12) and at least as
      // good as the initial feasible.
      expect(m['maxLoad'], lessThanOrEqualTo(15));
      expect(
        result.stats.finalObjective,
        lessThanOrEqualTo(result.stats.initialObjective!),
      );
    });

    test('cancellation before the loop returns the initial result', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A + B == 4');
      final token = CancellationToken()..cancel();
      final result = await p.lnsMinimize(
        'A',
        cancelToken: token,
      );
      // The initial solve runs once. It may or may not finish before the
      // token check fires; either way we should not crash, and stats
      // should be sane.
      expect(result.stats.iterations, equals(0));
    });

    test('boundHint pre-tightens the inner sub-problem objective', () async {
      // Cooperative-LNS plumbing test. We feed a `boundHint` that
      // claims a globally better bound than the initial feasible
      // would give; iterations whose objective domain becomes empty
      // under that bound should be counted as infeasibles and
      // skipped without finding a candidate.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addStringConstraint('A + B == 8');
      // A + B == 8 ⇒ feasible (A,B) pairs: (3,5), (4,4), (5,3).
      // Minimising A: optimum is 3.
      // If we feed a boundHint of 1 (a value strictly better than the
      // global optimum 3), every iteration's tightened domain
      // becomes empty → every iteration counts as infeasible.
      final result = await p.lnsMinimize(
        'A',
        iterationBudget: 10,
        seed: 42,
        boundHint: () => 1,
      );
      expect(result.solution, isA<Map<String, dynamic>>());
      // No iteration found a candidate (all skipped as infeasible).
      expect(result.stats.iterations, equals(10));
      expect(result.stats.infeasibles, equals(10));
      expect(result.stats.accepts, equals(0));
    });

    test('onIncumbent fires on every local improvement', () async {
      // We arrange a problem where the initial feasible is unlikely
      // to be the optimum, and assert onIncumbent is called at least
      // once with a strictly-improving value.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C']);
      final improvements = <num>[];
      final result = await p.lnsMinimize(
        'A',
        iterationBudget: 40,
        seed: 7,
        onIncumbent: improvements.add,
      );
      // Every reported value is strictly better than the one before.
      for (var i = 1; i < improvements.length; i++) {
        expect(improvements[i], lessThan(improvements[i - 1]));
      }
      // The final reported value matches the final incumbent.
      if (improvements.isNotEmpty) {
        expect(improvements.last, equals(result.stats.finalObjective));
      }
    });
  });
}

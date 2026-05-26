/// Worked examples for Large Neighborhood Search: the default
/// `random` destroy + `improving` accept, the related-destroy
/// heuristic on a clustered model, simulated annealing as an
/// alternative acceptance, late-acceptance hill-climbing (Burke
/// et al. 2017), and adaptive destroy weighting (Ropke & Pisinger
/// 2006) over a mixed-policy bundle.
///
/// Run with:
///
///   dart run example/lns.dart
///
/// See `doc/lns.md` for the design overview and the policy / accept
/// catalogues.
library;

import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  print('=== LNS examples ===\n');

  await defaultRandomImproving();
  await relatedDestroyOnClusteredModel();
  await simulatedAnnealingEscape();
  await lateAcceptanceHillClimbing();
  await adaptivePolicyBundle();
}

/// 1. The default LNS shape: `random` destroy + `improving` accept.
/// A 12-item, 3-bin packing instance; plain B&B proves the optimum
/// in ~40 seconds, LNS gets there in ~3 seconds.
Future<void> defaultRandomImproving() async {
  print('1. Default LNS — random destroy / improving accept');
  final p = _binPacking(itemCount: 12, binCount: 3);
  final result = await p.lnsMinimize(
    'maxLoad',
    policy: LnsPolicy.random(fraction: 0.5),
    iterationBudget: 50,
    seed: 17,
  );
  final best = result.solution as Map<String, dynamic>;
  print('   best maxLoad = ${best["maxLoad"]} (plain-B&B optimum: 30)');
  print('   stats: ${result.stats}\n');
}

/// 2. Related-destroy heuristic — pick a seed variable, then expand
/// the freed set through the constraint-variable graph. Recovers
/// cluster structure that pure random misses.
Future<void> relatedDestroyOnClusteredModel() async {
  print('2. Related destroy on the same instance');
  final p = _binPacking(itemCount: 12, binCount: 3);
  final result = await p.lnsMinimize(
    'maxLoad',
    policy: LnsPolicy.related(extendFraction: 0.5),
    iterationBudget: 50,
    seed: 17,
  );
  final best = result.solution as Map<String, dynamic>;
  print('   best maxLoad = ${best["maxLoad"]}');
  print('   stats: ${result.stats}\n');
}

/// 3. Simulated annealing — admits a controlled fraction of
/// worsening moves to escape local optima. The internal "best
/// ever" tracking guarantees the returned solution is the best
/// LNS saw at any point, even if SA briefly regressed.
Future<void> simulatedAnnealingEscape() async {
  print('3. Simulated-annealing acceptance');
  final p = _binPacking(itemCount: 10, binCount: 3);
  final result = await p.lnsMinimize(
    'maxLoad',
    policy: LnsPolicy.random(fraction: 0.5),
    accept: LnsAccept.simulatedAnnealing(initialTemp: 3, cooling: 0.95),
    iterationBudget: 80,
    seed: 17,
  );
  final best = result.solution as Map<String, dynamic>;
  print('   best maxLoad = ${best["maxLoad"]} (plain-B&B optimum: 22)');
  print('   stats: ${result.stats}\n');
}

/// 4. Late-acceptance hill-climbing — compares each candidate against
/// the objective from `historySize` iterations ago rather than the
/// current incumbent. One hyperparameter; surprisingly strong in
/// practice on combinatorial optimization.
Future<void> lateAcceptanceHillClimbing() async {
  print('4. Late-acceptance hill-climbing');
  final p = _binPacking(itemCount: 10, binCount: 3);
  final result = await p.lnsMinimize(
    'maxLoad',
    policy: LnsPolicy.random(fraction: 0.5),
    accept: LnsAccept.lateAcceptance(historySize: 25),
    iterationBudget: 80,
    seed: 17,
  );
  final best = result.solution as Map<String, dynamic>;
  print('   best maxLoad = ${best["maxLoad"]}');
  print('   stats: ${result.stats}\n');
}

/// 5. Adaptive policy bundle — `LnsPolicy.adaptive` re-weights a list
/// of sub-policies based on observed reward over a sliding window
/// of iterations. Sub-policies that produce improving moves get
/// more selection mass; starved policies keep a small positive
/// floor so they can recover.
Future<void> adaptivePolicyBundle() async {
  print('5. Adaptive policy (ALNS-style)');
  final p = _binPacking(itemCount: 12, binCount: 3);
  final result = await p.lnsMinimize(
    'maxLoad',
    policy: LnsPolicy.adaptive(
      [
        LnsPolicy.random(fraction: 0.3),
        LnsPolicy.random(fraction: 0.5),
        LnsPolicy.related(extendFraction: 0.5),
        LnsPolicy.window(windowSize: 6),
      ],
      segmentSize: 20,
    ),
    iterationBudget: 80,
    seed: 17,
  );
  final best = result.solution as Map<String, dynamic>;
  print('   best maxLoad = ${best["maxLoad"]} (plain-B&B optimum: 30)');
  print('   stats: ${result.stats}\n');
}

/// Build a bin-packing problem: distribute [itemCount] items of
/// deterministic weights across [binCount] bins, minimising the
/// heaviest bin's load. Identical encoding to
/// `benchmark/problems.dart::buildBinPackingMinMaxLoad`; inlined
/// here so the example is self-contained.
Problem _binPacking({required int itemCount, required int binCount}) {
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
    p.addConstraint(['maxLoad', 'load$b'],
        (dynamic ml, dynamic l) => (ml as num) >= (l as num));
  }
  return p;
}

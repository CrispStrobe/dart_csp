// One-off reproduction: compare generated clauses separately from solver phases.
// Run with `dart run`, or compile to JavaScript and run with Node's `self` alias.
import 'dart:convert';
import 'dart:math';

import 'package:dart_csp/dart_csp.dart';

List<List<int>> clauses(int seed, int n, int m) {
  final rng = Random(seed);
  return [
    for (var c = 0; c < m; c++)
      (() {
        final picked = <int>{};
        while (picked.length < 3) {
          picked.add(rng.nextInt(n));
        }
        return [for (final i in picked) (rng.nextBool() ? 1 : -1) * (i + 1)];
      })(),
  ];
}

Problem problem(int n, List<List<int>> cnf) {
  final p = Problem();
  for (var i = 0; i < n; i++) {
    p.addVariable('v$i', [0, 1]);
  }
  for (final clause in cnf) {
    p.addClause(
      positive: [
        for (final literal in clause)
          if (literal > 0) 'v${literal - 1}'
      ],
      negative: [
        for (final literal in clause)
          if (literal < 0) 'v${-literal - 1}'
      ],
    );
  }
  return p;
}

Future<void> main() async {
  for (final seed in [1, 5, 13]) {
    final cnf = clauses(seed, 100, 426);
    final draw = Random(seed).nextInt(2);
    final shuffled = [0, 1]..shuffle(Random(seed));
    final singletonProblem = Problem()..addVariable('v0', [0, 1]);
    final single = await singletonProblem.solveWithLcg(seed: seed);
    final runs = <Map<String, Object?>>[];
    for (final restarts in [false, true]) {
      final result = await problem(100, cnf).solveWithLcg(
        useRestarts: restarts,
        useVsids: true,
        seed: seed,
      );
      final stats = CSP.lastStats!;
      final valid = result is Map<String, dynamic> &&
          result.length == 100 &&
          result.values.every((v) => v == 0 || v == 1) &&
          cnf.every((c) => c.any((literal) =>
              result['v${literal.abs() - 1}'] == (literal > 0 ? 1 : 0)));
      runs.add({
        'restarts_enabled': restarts,
        'valid_assignment': valid,
        'decisions': stats.decisions,
        'backtracks': stats.backtracks,
        'restarts': stats.restarts,
      });
    }
    print(jsonEncode({
      'seed': seed,
      'first_next_int_2': draw,
      'eager_shuffle_first': shuffled.first,
      'solver_single_boolean': single,
      'clauses': cnf,
      'runs': runs,
    }));
  }
}

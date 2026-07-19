// Demonstrates the ergonomics & solution-oriented APIs added in 2.3.0:
//   1. the typed modelling DSL (Model / IntVar / LinearExpr)
//   2. solution sampling & diversity
//   3. multi-objective optimization (lexicographic + Pareto)
//   4. LCG nogood / UNSAT proof logging
//   5. assumption-based incremental solving
//
// Run with:  dart run example/new_apis.dart
import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  await _dsl();
  await _sampling();
  await _multiObjective();
  await _proof();
  await _incremental();
}

/// 1. Typed modelling DSL — arithmetic instead of strings or lambdas.
Future<void> _dsl() async {
  print('== 1. Typed modelling DSL ==');
  final m = Model();
  final x = m.intVar('x', 0, 10);
  final y = m.intVar('y', 0, 10);
  (x + y * 2).le(12); // x + 2y <= 12 (scalar on the right: y * 2, not 2 * y)
  (x - y).eq(2); // x - y == 2
  x.ge(3);
  final sol = await m.problem.getSolution();
  print('  x + 2y <= 12, x - y == 2, x >= 3  ->  $sol\n');
}

/// 2. Sampling & diversity over the solution set.
Future<void> _sampling() async {
  print('== 2. Sampling & diversity ==');
  // A 3x3 Latin-square-ish problem: 3 all-different variables over 1..3.
  final p = Problem()
    ..addVariables(['a', 'b', 'c'], [1, 2, 3])
    ..addAllDifferent(['a', 'b', 'c']);

  final samples = await p.sampleSolutions(2, seed: 7);
  print('  2 uniform random solutions (seed 7): $samples');

  final diverse = await p.diverseSolutions(2, seed: 7);
  print('  2 maximally-different solutions:     $diverse\n');
}

/// 3. Multi-objective: lexicographic priority and the Pareto frontier.
Future<void> _multiObjective() async {
  print('== 3. Multi-objective optimization ==');
  // x + y == 4, both in 0..4 — a perfect trade-off.
  Problem tradeoff() => Problem()
    ..addVariables(['x', 'y'], [for (var i = 0; i <= 4; i++) i])
    ..addLinearEquals(['x', 'y'], [1, 1], 4);

  final lex = await tradeoff().lexOptimize(
      [const Objective.maximize('x'), const Objective.maximize('y')]);
  print('  lexOptimize(max x, then max y):  $lex');

  final front = await tradeoff().paretoFront(
      [const Objective.minimize('x'), const Objective.minimize('y')]);
  final points = front.map((s) => '(${s['x']},${s['y']})').join(' ');
  print('  Pareto frontier (min x, min y):  $points\n');
}

/// 4. UNSAT proof logging: capture the nogoods that refute an instance.
Future<void> _proof() async {
  print('== 4. UNSAT proof / nogood logging ==');
  // Pigeonhole CNF: 4 pigeons, 3 holes — infeasible, and it must search.
  final p = Problem();
  for (var pg = 0; pg < 4; pg++) {
    for (var h = 0; h < 3; h++) {
      p.addVariable('p${pg}_h$h', [0, 1]);
    }
    p.addClause(positive: [for (var h = 0; h < 3; h++) 'p${pg}_h$h']);
  }
  for (var h = 0; h < 3; h++) {
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
      }
    }
  }
  final r = await p.solveWithProof();
  print('  result: ${r.result}, provedUnsat: ${r.proof.provedUnsat}, '
      'learned nogoods: ${r.proof.length}\n');
}

/// 5. Assumption-based incremental solving with retractable scopes.
Future<void> _incremental() async {
  print('== 5. Incremental / assumption solving ==');
  final base = Problem()
    ..addVariables(['x', 'y'], [1, 2, 3])
    ..addStringConstraint('x != y');
  final baseConstraintsBefore = base.constraintCount;
  final s = IncrementalSolver(base);

  s.assumeEquals('x', 3);
  print('  base + {x==3}:          ${await s.countSolutions()} solutions');

  s.push();
  s.assumeEquals('y', 1);
  print('  ...push {y==1}:         ${await s.countSolutions()} solution(s)');

  s.pop();
  print('  ...pop (retract y==1):  ${await s.countSolutions()} solutions '
      '(back to just x==3)');
  print('  base mutated? ${base.constraintCount != baseConstraintsBefore}  '
      '(constraints on base unchanged at ${base.constraintCount})');
}

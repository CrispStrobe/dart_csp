/// Worked examples for the FlatZinc frontend: parse + solve via
/// `FlatZinc.solve`, lowered-problem inspection via `FlatZinc.build`,
/// search-annotation passthrough, and the MUS-via-label workflow on
/// an unsatisfiable model.
///
/// Run with:
///
///   dart run example/flatzinc.dart
///
/// See `doc/flatzinc.md` for the supported subset reference.
library;

import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  print('=== FlatZinc frontend examples ===\n');

  await trivial();
  await fourQueens();
  await sendMoreMoney();
  await heuristicHint();
  await musOnInfeasible();
}

/// 1. The smallest possible example: declare a few vars, ask for a
/// solution, look at the output.
Future<void> trivial() async {
  print('1. Trivial satisfaction');
  final out = await FlatZinc.solve('''
var 1..3: x :: output_var;
var 1..3: y :: output_var;
constraint int_ne(x, y);
solve satisfy;
''');
  print(out);
}

/// 2. n-queens, hand-written FlatZinc. Mirrors what `mzn2fzn` emits
/// for the standard n-queens MiniZinc model, give or take cosmetics.
Future<void> fourQueens() async {
  print('2. 4-queens');
  final source = StringBuffer()
    ..writeln('array[1..4] of var 1..4: q :: output_array([1..4]);')
    ..writeln('constraint all_different_int(q);');
  for (var i = 1; i <= 4; i++) {
    for (var j = i + 1; j <= 4; j++) {
      source
        ..writeln('constraint int_lin_ne([1, -1], [q[$i], q[$j]], ${j - i});')
        ..writeln(
            'constraint int_lin_ne([1, -1], [q[$i], q[$j]], ${-(j - i)});');
    }
  }
  source.writeln('solve satisfy;');
  print(await FlatZinc.solve(source.toString()));
}

/// 3. Cryptarithm via a single `int_lin_eq` — the same flattened form
/// you'd get from the canonical `SEND + MORE = MONEY` MiniZinc model.
Future<void> sendMoreMoney() async {
  print('3. SEND + MORE = MONEY');
  print(await FlatZinc.solve('''
var 1..9: s :: output_var;
var 0..9: e :: output_var;
var 0..9: n :: output_var;
var 0..9: d :: output_var;
var 1..9: m :: output_var;
var 0..9: o :: output_var;
var 0..9: r :: output_var;
var 0..9: y :: output_var;
constraint all_different_int([s, e, n, d, m, o, r, y]);
constraint int_lin_eq(
  [1000, 100, 10, 1, 1000, 100, 10, 1, -10000, -1000, -100, -10, -1],
  [s, e, n, d, m, o, r, e, m, o, n, e, y],
  0);
solve satisfy;
'''));
}

/// 4. A search annotation hints at the heuristic. The runner inspects
/// `:: int_search(vars, dom_w_deg, ...)` and routes through
/// `getSolutionWithDomWdeg`.
Future<void> heuristicHint() async {
  print('4. Search annotation routed to dom/wdeg');
  print(await FlatZinc.solve('''
array[1..6] of var 1..6: q :: output_array([1..6]);
constraint all_different_int(q);
solve :: int_search(q, dom_w_deg, indomain_min, complete) satisfy;
'''));
}

/// 5. Lower an infeasible model via `FlatZinc.build`, then drive the
/// MUS pass on the resulting `Problem`. Every constraint carries a
/// `<fzn_name>#<counter>` label, so the MUS output traces straight
/// back to the source FlatZinc.
Future<void> musOnInfeasible() async {
  print('5. MUS on a deliberately infeasible model');
  // Two pigeons, one hole — but we also require all-different on a
  // size-2 array of {1}, which is infeasible.
  final lowered = FlatZinc.build('''
array[1..2] of var 1..1: x;
constraint all_different_int(x);
solve satisfy;
''');
  final mus = await lowered.problem.findMinimalUnsatisfiableSubset();
  if (mus == null) {
    print('  (model is satisfiable — no MUS)');
    return;
  }
  print('  MUS size: ${mus.length}');
  for (final ref in mus) {
    print('    $ref');
  }
  print('');
}

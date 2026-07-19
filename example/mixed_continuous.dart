// Mixed integer / continuous modelling in the main engine.
//
// `Problem.addFloatVariable` declares a real-valued variable that lives
// in the same problem as the enumerated ones. Linear constraints may
// span both kinds; the engine enforces them with an interval (HC4)
// propagator that prunes the reals *and* the integers, so the ordinary
// integer propagators (here: allDifferent) see domains the continuous
// part has already narrowed.
//
// Run: dart run example/mixed_continuous.dart

import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  await productionMix();
  await blendWithAllDifferent();
  await minimumCost();
  await circleMeetsLine();
  await largestRectangle();
  await withTheTypedDsl();
}

/// A tiny production plan: whole units of a product, a real unit price,
/// and a budget that couples them.
Future<void> productionMix() async {
  final p = Problem();
  p.addRangeVariable('units', 0, 20); // discrete
  p.addFloatVariable('price', 0.0, 100.0); // continuous

  // Budget: 2 EUR handling per unit plus 1.5x the unit price <= 40.
  p.addLinearLeq(['units', 'price'], [2, 1.5], 40);
  // Contractual floors.
  p.addLinearGeq(['units'], [1], 12);
  p.addLinearGeq(['price'], [1], 10);

  final sol = await p.getSolution() as Map<String, dynamic>;
  final units = sol['units'] as int;
  final price = sol['price'] as double;
  print('production mix: units=$units, '
      'price=${price.toStringAsFixed(4)}, '
      'spend=${(2 * units + 1.5 * price).toStringAsFixed(4)} (<= 40)');
}

/// The discrete part keeps its usual propagators. `allDifferent` fixes
/// a permutation; a mixed linear constraint reads its weighted sum into
/// a real variable.
Future<void> blendWithAllDifferent() async {
  final p = Problem();
  p.addVariables(['a', 'b', 'c'], [1, 2, 3]);
  p.addAllDifferent(['a', 'b', 'c']);
  p.addFloatVariable('blend', 0.0, 20.0);

  // blend == 0.5a + 1.25b + 2c, and the mix must be worth at least 7.
  p.addLinearEquals(['a', 'b', 'c', 'blend'], [0.5, 1.25, 2, -1], 0);
  p.addLinearGeq(['blend'], [1], 7);

  final sol = await p.getSolution() as Map<String, dynamic>;
  print('blend: a=${sol['a']}, b=${sol['b']}, c=${sol['c']}, '
      'blend=${(sol['blend'] as double).toStringAsFixed(4)} (>= 7)');
}

/// Branch-and-bound works on a continuous objective: the search bisects
/// toward the bound and reports the optimum to within `floatEpsilon`.
Future<void> minimumCost() async {
  final p = Problem();
  p.addRangeVariable('n', 3, 9);
  p.addFloatVariable('cost', 0.0, 100.0);
  // cost >= 2n + 1.5, so the cheapest feasible n is the smallest one.
  p.addLinearGeq(['cost', 'n'], [1, -2], 1.5);

  final best = await p.minimize('cost') as Map<String, dynamic>;
  print('minimum cost: n=${best['n']}, '
      'cost=${(best['cost'] as double).toStringAsFixed(6)} '
      '(exact optimum 7.5), ${p.lastStats!.decisions} decisions');
}

/// Non-linear models work through `addFloatProduct`, which posts
/// `product == a * b`. Polynomials decompose into products plus the
/// linear constraints that combine them.
Future<void> circleMeetsLine() async {
  final p = Problem();
  p.addFloatVariable('x', 0.0, 10.0);
  p.addFloatVariable('y', 0.0, 10.0);
  p.addFloatVariable('x2', 0.0, 100.0);
  p.addFloatVariable('y2', 0.0, 100.0);

  // x² + y² == 25 (a circle) intersected with x + y == 7 (a line).
  p.addFloatProduct('x2', 'x', 'x');
  p.addFloatProduct('y2', 'y', 'y');
  p.addLinearEquals(['x2', 'y2'], [1, 1], 25);
  p.addLinearEquals(['x', 'y'], [1, 1], 7);

  final sol = await p.getSolution() as Map<String, dynamic>;
  final x = sol['x'] as double;
  final y = sol['y'] as double;
  print('circle meets line: x=${x.toStringAsFixed(4)}, '
      'y=${y.toStringAsFixed(4)} '
      '(x^2+y^2=${(x * x + y * y).toStringAsFixed(4)}, '
      'x+y=${(x + y).toStringAsFixed(4)})');
}

/// Optimizing over a product. The objective is the product variable
/// itself, which the search branches toward its bound.
Future<void> largestRectangle() async {
  final p = Problem();
  p.addFloatVariable('w', 0.0, 10.0);
  p.addFloatVariable('h', 0.0, 4.0); // a height limit
  p.addFloatVariable('area', 0.0, 40.0);
  p.addFloatProduct('area', 'w', 'h');
  p.addLinearLeq(['w', 'h'], [1, 1], 10); // a perimeter-style budget

  final best = await p.maximize('area') as Map<String, dynamic>;
  print('largest rectangle: w=${(best['w'] as double).toStringAsFixed(4)}, '
      'h=${(best['h'] as double).toStringAsFixed(4)}, '
      'area=${(best['area'] as double).toStringAsFixed(4)} '
      '(exact optimum 24), ${p.lastStats!.decisions} decisions');
}

/// The same models through the typed DSL, which names the product
/// auxiliaries for you and keeps them out of the reported solution.
Future<void> withTheTypedDsl() async {
  final m = Model();
  final units = m.intVar('units', 0, 20);
  final price = m.realVar('price', 0.0, 100.0);
  (units * 2 + price * 1.5).le(40);
  units.ge(12);
  price.ge(10);
  final sol = await m.problem.getSolution() as Map<String, dynamic>;
  print('dsl mixed: units=${sol['units']}, '
      'price=${(sol['price'] as double).toStringAsFixed(4)}');

  // Non-linear, in two lines: `*` between expressions builds a product.
  final m2 = Model();
  final x = m2.realVar('x', 0.0, 10.0);
  final y = m2.realVar('y', 0.0, 10.0);
  (x * x + y * y).eq(25);
  (x + y).eq(7);
  final s2 = await m2.problem.getSolution() as Map<String, dynamic>;
  print('dsl circle: x=${(s2['x'] as double).toStringAsFixed(4)}, '
      'y=${(s2['y'] as double).toStringAsFixed(4)} '
      '(keys: ${s2.keys.join(", ")} — no auxiliaries)');

  // Optimizing an expression directly.
  final m3 = Model();
  final w = m3.realVar('w', 0.0, 10.0);
  final h = m3.realVar('h', 0.0, 4.0);
  (w + h).le(10);
  m3.problem.setFloatEpsilon(1e-4);
  final best = await m3.maximize(w * h) as Map<String, dynamic>;
  print('dsl maximize w*h: w=${(best['w'] as double).toStringAsFixed(4)}, '
      'h=${(best['h'] as double).toStringAsFixed(4)} (optimum 24)');
}

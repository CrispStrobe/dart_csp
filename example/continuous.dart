// Continuous (real / float) variables — experimental preview.
//
// The integer engine enumerates domains, so it cannot represent fractional
// quantities. ContinuousModel solves over real intervals with branch-and-prune.
//
// Run with:  dart run example/continuous.dart
import 'package:dart_csp/dart_csp.dart';

void main() {
  // A determined linear system: x + y == 10, x - y == 4  ->  x = 7, y = 3.
  final m = ContinuousModel();
  final x = m.addVar('x', 0, 10);
  final y = m.addVar('y', 0, 10);
  (x + y).eq(10);
  (x - y).eq(4);

  final sol = m.solve(epsilon: 1e-9);
  print('x + y == 10, x - y == 4  ->  ${sol?.midpoint}');

  // A fractional solution no integer variable could hold: 2z == 1 -> z = 0.5.
  final m2 = ContinuousModel();
  final z = m2.addVar('z', 0, 1);
  (z * 2).eq(1);
  print('2z == 1                  ->  ${m2.solve()?.midpoint}');

  // An infeasible model returns null.
  final m3 = ContinuousModel();
  final w = m3.addVar('w', 0, 10);
  w.ge(5);
  w.le(3);
  print('w >= 5 and w <= 3        ->  ${m3.solve()}');

  // Non-linear: x * y == 6, x + y == 5  ->  {2, 3}.
  final m4 = ContinuousModel();
  final a = m4.addVar('a', 0, 5);
  final b = m4.addVar('b', 0, 5);
  (a * b).eq(6);
  (a + b).eq(5);
  print('a*b == 6, a + b == 5     ->  ${m4.solve(epsilon: 1e-7)?.midpoint}');

  // Non-linear: a² == 2  ->  a ≈ 1.4142.
  final m5 = ContinuousModel();
  final s = m5.addVar('s', 0, 2);
  (s * s).eq(2);
  print('s*s == 2                 ->  ${m5.solve(epsilon: 1e-9)?.midpoint}');

  // Mixed integer + continuous: n integer, x real, x == 2.5 * n, x == 7.5.
  final m6 = ContinuousModel();
  final n = m6.addIntVar('n', 1, 10);
  final xf = m6.addVar('xf', 0, 30);
  (xf - n * 2.5).eq(0);
  xf.eq(7.5);
  print('x == 2.5n, x == 7.5      ->  ${m6.solve(epsilon: 1e-7)?.midpoint}');
}

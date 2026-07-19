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
}

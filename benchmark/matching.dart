/// Bounded repeated-edit workload for retained allDifferent matching state.
///
/// Run this same program at the before/after commits to compare the matching
/// change. It does not compare two algorithms or claim a historical speedup.
library;

import 'package:dart_csp/dart_csp.dart';

Future<int> _batch(CspSolveSession session, int n) async {
  final watch = Stopwatch()..start();
  for (var edit = 0; edit < 12; edit++) {
    final result = await session.solve(assumptions: [
      for (var i = 0; i < n ~/ 2; i++)
        CspAssumption.equals('x$i', (i + edit) % (n + 4)),
    ]);
    if (!result.isSatisfied || result.solution!.values.toSet().length != n) {
      throw StateError('Invalid allDifferent result at edit $edit.');
    }
    for (var i = 0; i < n ~/ 2; i++) {
      if (result.solution!['x$i'] != (i + edit) % (n + 4)) {
        throw StateError('Assumption was not respected.');
      }
    }
  }
  return watch.elapsedMicroseconds;
}

Future<void> main() async {
  for (final n in [32, 64]) {
    final names = [for (var i = 0; i < n; i++) 'x$i'];
    final problem = Problem();
    for (final name in names) {
      problem.addRangeVariable(name, 0, n + 3);
    }
    problem.addAllDifferent(names);
    final session = problem.compile().createSession();
    await _batch(session, n);
    await _batch(session, n);
    final samples = [for (var i = 0; i < 7; i++) await _batch(session, n)]
      ..sort();
    print('variables=$n values=${n + 4} edits=12; '
        'median=${samples[3]}us p95=${samples.last}us; '
        'rootPreparations=${session.rootPreparationCount}');
    session.close();
  }
}

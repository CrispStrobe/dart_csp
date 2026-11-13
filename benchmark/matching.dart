/// Bounded repeated-edit workload for retained allDifferent matching state.
///
/// Run this same program at the before/after commits to compare the matching
/// change. It does not compare two algorithms or claim a historical speedup.
/// Use --samples=25 --warmups=5 for a longer, still bounded tail comparison.
library;

import 'package:dart_csp/dart_csp.dart';

import 'sampling.dart';

Future<int> _batch(CspSolveSession session, int n,
    {Map<String, int>? work}) async {
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
    if (work != null) collectMatchingWork(result.stats, work);
  }
  return watch.elapsedMicroseconds;
}

Future<void> main(List<String> arguments) async {
  final sampling = BenchmarkSampling.parse(arguments);
  for (final n in [32, 64]) {
    final names = [for (var i = 0; i < n; i++) 'x$i'];
    final problem = Problem();
    for (final name in names) {
      problem.addRangeVariable(name, 0, n + 3);
    }
    problem.addAllDifferent(names);
    final session = problem.compile().createSession();
    final timings = await sampling.measure(() => _batch(session, n));
    print('variables=$n values=${n + 4} edits=12; '
        '$timings; '
        'rootPreparations=${session.rootPreparationCount}');
    final work = <String, int>{};
    await _batch(session, n, work: work);
    print('  steady batch work=$work');
    session.close();
  }
}

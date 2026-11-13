/// Repeated upper-capacity GCC edits; run at before/after commits for comparison.
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
        CspAssumption.equals('x$i', (i + edit) % 8),
    ]);
    if (!result.isSatisfied) throw StateError('No GCC solution.');
    final counts = List<int>.filled(8, 0);
    for (final value in result.solution!.values) {
      counts[value as int]++;
    }
    if (counts.any((count) => count > n ~/ 2)) {
      throw StateError('A returned count exceeds its upper capacity.');
    }
    for (var i = 0; i < n ~/ 2; i++) {
      if (result.solution!['x$i'] != (i + edit) % 8) {
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
    final problem = Problem()..addVariables(names, List.generate(8, (i) => i));
    problem.addGccRanges(names, {
      for (var value = 0; value < 8; value++) value: (min: 0, max: n ~/ 2),
    });
    final session = problem.compile().createSession();
    final timings = await sampling.measure(() => _batch(session, n));
    print('variables=$n values=8 upper=${n ~/ 2} edits=12; '
        '$timings; '
        'rootPreparations=${session.rootPreparationCount}');
    final work = <String, int>{};
    await _batch(session, n, work: work);
    print('  steady batch work=$work');
    final structureSession = problem.compile().createSession();
    final structure = await structureSession.solve(maxDecisions: 0);
    print('  flow nodes=${structure.stats.gccMaxFlowNodes} '
        'arcs=${structure.stats.gccMaxFlowEdges} '
        'totalCapacity=${structure.stats.gccMaxTotalCapacity}');
    structureSession.close();
    session.close();
  }
}

/// Paired repeated-edit benchmark: fresh one-shot solves versus a prepared
/// session. Both paths use the current solver and the same exact constraints.
library;

import 'package:dart_csp/dart_csp.dart';

Problem _build(int size) {
  final problem = Problem()..addRangeVariable('selection', 0, 96);
  for (var i = 0; i < size; i++) {
    problem.addRangeVariable('fixed$i', 0, 4096);
    problem.addLinearEquals(['fixed$i'], [1], i);
  }
  return problem;
}

Future<int> _batch(Problem base, CspSolveSession session, int size,
    {required bool reuse}) async {
  final watch = Stopwatch()..start();
  for (var edit = 0; edit < 20; edit++) {
    final value = edit * 13 % 97;
    final Map<String, dynamic> solution;
    if (reuse) {
      final result = await session
          .solve(assumptions: [CspAssumption.equals('selection', value)]);
      if (!result.isSatisfied) throw StateError('Unexpected ${result.status}');
      solution = result.solution!;
    } else {
      final work = base.copy()..addLinearEquals(['selection'], [1], value);
      solution = await work.getSolution() as Map<String, dynamic>;
    }
    if (solution['selection'] != value ||
        [for (var i = 0; i < size; i++) i]
            .any((i) => solution['fixed$i'] != i)) {
      throw StateError('Invalid edit result');
    }
  }
  watch.stop();
  return watch.elapsedMicroseconds;
}

String _summary(List<int> samples) {
  samples.sort();
  return 'median=${samples[samples.length ~/ 2]}us '
      'p95=${samples[(samples.length * 0.95).ceil() - 1]}us';
}

Future<void> main() async {
  for (final size in [64, 512]) {
    final base = _build(size);
    final preparation = Stopwatch()..start();
    final session = base.compile().createSession();
    await session.solve();
    preparation.stop();
    for (var warm = 0; warm < 2; warm++) {
      await _batch(base, session, size, reuse: false);
      await _batch(base, session, size, reuse: true);
    }
    final cold = <int>[];
    final reused = <int>[];
    for (var repetition = 0; repetition < 7; repetition++) {
      if (repetition.isEven) {
        cold.add(await _batch(base, session, size, reuse: false));
        reused.add(await _batch(base, session, size, reuse: true));
      } else {
        reused.add(await _batch(base, session, size, reuse: true));
        cold.add(await _batch(base, session, size, reuse: false));
      }
    }
    print('fixed=$size edits=20 setup=${preparation.elapsedMicroseconds}us; '
        'fresh ${_summary(cold)}; session ${_summary(reused)}; '
        'rootPreparations=${session.rootPreparationCount}');
    session.close();
  }
}

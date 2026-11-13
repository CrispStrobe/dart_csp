/// Paired construction + first-solution microbenchmark for declared ranges.
///
/// Both alternatives use the same current solver. "explicit" materializes the
/// input list; "compact" keeps an IntRangeDomain. This isolates the declared
/// representation cost and is not a comparison against a historical commit.
library;

import 'package:dart_csp/dart_csp.dart';

Future<int> _run(int size, {required bool compact}) async {
  final watch = Stopwatch()..start();
  final problem = Problem();
  if (compact) {
    problem.addRangeVariable('x', 0, size);
  } else {
    problem.addVariable('x', [for (var i = 0; i <= size; i++) i]);
  }
  problem.addLinearGeq(['x'], [1], size - 3);
  final solution = await problem.getSolution();
  watch.stop();
  if (solution is! Map<String, dynamic> || solution['x'] != size - 3) {
    throw StateError('Invalid benchmark solution: $solution');
  }
  return watch.elapsedMicroseconds;
}

String _summary(List<int> samples) {
  samples.sort();
  final median = samples[samples.length ~/ 2];
  final p95 = samples[(samples.length * 0.95).ceil() - 1];
  return 'median=${median}us p95=${p95}us';
}

Future<void> main() async {
  for (final size in [10000, 100000, 1000000]) {
    for (var warm = 0; warm < 5; warm++) {
      await _run(size, compact: warm.isEven);
      await _run(size, compact: warm.isOdd);
    }
    final explicit = <int>[];
    final compact = <int>[];
    for (var repetition = 0; repetition < 15; repetition++) {
      if (repetition.isEven) {
        explicit.add(await _run(size, compact: false));
        compact.add(await _run(size, compact: true));
      } else {
        compact.add(await _run(size, compact: true));
        explicit.add(await _run(size, compact: false));
      }
    }
    print('range=0..$size; explicit ${_summary(explicit)}; '
        'compact ${_summary(compact)}');
  }
}

/// Same-harness comparison for cumulative time-table propagation.
///
/// Default durations are bounded so the historical per-time-tick implementation
/// can finish. Run --durations=1000000000 only with the swept implementation to
/// inspect scaling; that run is not a historical speedup measurement.
/// Examples:
///   dart run benchmark/cumulative.dart --samples=15 --warmups=3
///   dart run benchmark/cumulative.dart --durations=1000000000
library;

import 'package:dart_csp/dart_csp.dart';

import 'sampling.dart';

// Independent result check for this unary-resource fixture: directly test each
// pair of half-open occupied intervals rather than rebuilding a usage profile.
void _validate(Map<String, dynamic> solution, int tasks, int duration) {
  for (var i = 0; i < tasks; i++) {
    final start = solution['s$i'];
    if (start is! int) throw StateError('Noninteger benchmark start.');
    for (var j = i + 1; j < tasks; j++) {
      final other = solution['s$j'] as int;
      if (!(start + duration <= other || other + duration <= start)) {
        throw StateError('Overlapping benchmark schedule.');
      }
    }
  }
}

Future<int> _fixed(int tasks, int duration) async {
  final watch = Stopwatch()..start();
  final problem = Problem();
  final names = [for (var i = 0; i < tasks; i++) 's$i'];
  for (var i = 0; i < tasks; i++) {
    problem.addVariable(names[i], [i * duration]);
  }
  problem.addCumulative(
      names, List.filled(tasks, duration), List.filled(tasks, 1), 1,
      useEnergeticReasoning: false);
  final solution = await problem.getSolution();
  watch.stop();
  if (solution is! Map<String, dynamic>) {
    throw StateError('Fixed benchmark schedule rejected.');
  }
  _validate(solution, tasks, duration);
  for (var i = 0; i < tasks; i++) {
    if (solution[names[i]] != i * duration) {
      throw StateError('Fixed start was not preserved.');
    }
  }
  return watch.elapsedMicroseconds;
}

Future<int> _range(int duration) async {
  final watch = Stopwatch()..start();
  final problem = Problem()
    ..addVariable('s0', [0])
    ..addRangeVariable('s1', 0, duration * 2)
    ..addCumulative(['s0', 's1'], [duration, duration], [1, 1], 1,
        useEnergeticReasoning: false);
  final solution = await problem.getSolution();
  watch.stop();
  if (solution is! Map<String, dynamic>) {
    throw StateError('Range benchmark schedule rejected.');
  }
  _validate(solution, 2, duration);
  if (solution['s0'] != 0 || solution['s1'] != duration) {
    throw StateError('Expected first supported start was not returned.');
  }
  return watch.elapsedMicroseconds;
}

CspSolveSession _session(int tasks, int duration) {
  final problem = Problem();
  final names = [for (var i = 0; i < tasks; i++) 's$i'];
  for (var i = 0; i < tasks; i++) {
    problem.addRangeVariable(
        names[i], i * (duration + 10), i * (duration + 10) + 3);
  }
  problem.addCumulative(
      names, List.filled(tasks, duration), List.filled(tasks, 1), 1,
      useEnergeticReasoning: false);
  return problem.compile().createSession();
}

Future<int> _edits(CspSolveSession session, int tasks, int duration) async {
  final watch = Stopwatch()..start();
  for (var edit = 0; edit < 12; edit++) {
    final result = await session.solve(assumptions: [
      for (var i = 0; i < tasks; i++)
        CspAssumption.equals('s$i', i * (duration + 10) + (edit + i) % 4),
    ]);
    if (!result.isSatisfied) throw StateError('Prepared schedule rejected.');
    _validate(result.solution!, tasks, duration);
    for (var i = 0; i < tasks; i++) {
      if (result.solution!['s$i'] != i * (duration + 10) + (edit + i) % 4) {
        throw StateError('Prepared schedule violated an assumption.');
      }
    }
  }
  watch.stop();
  return watch.elapsedMicroseconds;
}

Future<void> main(List<String> arguments) async {
  var durations = [1000, 10000];
  final samplingArguments = <String>[];
  for (final argument in arguments) {
    if (argument.startsWith('--durations=')) {
      durations = argument.substring('--durations='.length).split(',').map((s) {
        final value = int.tryParse(s);
        if (value == null || value <= 0 || value > 1000000000) {
          throw ArgumentError('Durations must be integers in 1..1000000000.');
        }
        return value;
      }).toList();
    } else {
      samplingArguments.add(argument);
    }
  }
  final sampling = BenchmarkSampling.parse(samplingArguments);
  const tasks = 8;
  for (final duration in durations) {
    print('fixed tasks=$tasks duration=$duration; '
        '${await sampling.measure(() => _fixed(tasks, duration))}');
    print('range tasks=2 duration=$duration horizon=${duration * 2}; '
        '${await sampling.measure(() => _range(duration))}');
    final session = _session(tasks, duration);
    await _edits(session, tasks, duration); // preparation outside warm timing
    print('prepared tasks=$tasks duration=$duration edits=12; '
        '${await sampling.measure(() => _edits(session, tasks, duration))}; '
        'rootPreparations=${session.rootPreparationCount}');
    session.close();
  }
}

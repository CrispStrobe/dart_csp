/// Independent-component geometry session forks with coordinate/residual
/// oracles. The harness uses the fork API available at checkpoint 2777886.
/// Each timed sample is one operation; independent checks are outside timers.
library;

import 'dart:convert';

import 'package:dart_csp/geometry.dart';

CompiledGeometryModel _model(int count) => GeometryModel(parameters: [
      for (var i = 0; i < count; i++) ...[
        GeometryParameterBlock(
            id: 'p$i',
            values: [i + 1.0 + 1e-9, (i + 1) * .25, (i + 1) * -.125]),
        GeometryParameterBlock(id: 'd$i', values: [i + 1.0], fixed: true),
      ],
    ], constraints: [
      for (var i = 0; i < count; i++)
        GeometryResidualBlock.autoDiff(
          id: 'dimension$i',
          parameterIds: ['p$i', 'd$i'],
          residualCount: 3,
          evaluate: (p) => [
            p[0][0] - p[1][0],
            p[0][1] - p[1][0] * .25,
            p[0][2] + p[1][0] * .125,
          ],
        ),
    ]).compile();

void _checkValues(Map<String, List<double>> values, int count, double drive) {
  if (values.length != count * 2) {
    throw StateError('Incorrect parameter count.');
  }
  for (var i = 0; i < count; i++) {
    final dimension = i == 0 ? drive : i + 1.0;
    if (values['d$i']!.single != dimension) {
      throw StateError('Wrong fixed dimension in component $i.');
    }
    for (var c = 0; c < 3; c++) {
      final factor = [1.0, .25, -.125][c];
      if (!values['p$i']![c].isFinite ||
          (values['p$i']![c] - dimension * factor).abs() > 1.01e-8) {
        throw StateError('Independent coordinate check failed for $i/$c.');
      }
    }
  }
}

void _check(GeometrySolveResult result, int count, double drive,
    {required int solved}) {
  if (!result.isSuccess ||
      result.localDegreesOfFreedom != 0 ||
      !result.maxToleranceRatio.isFinite ||
      result.maxToleranceRatio > 1 ||
      result.components.length != count ||
      result.stats.componentsSolved != solved ||
      result.stats.componentsReused != count - solved) {
    throw StateError('Unexpected solve or component-reuse result.');
  }
  _checkValues(result.values, count, drive);
  for (var i = 0; i < count; i++) {
    final point = result.values['p$i']!;
    final dimension = result.values['d$i']!.single;
    final expected = [
      point[0] - dimension,
      point[1] - dimension * .25,
      point[2] + dimension * .125,
    ];
    final actual = result.constraintResiduals['dimension$i']!;
    for (var c = 0; c < 3; c++) {
      if (!expected[c].isFinite ||
          !actual[c].isFinite ||
          expected[c].abs() > 1.01e-8 ||
          (actual[c] - expected[c]).abs() > 1e-14) {
        throw StateError('Physical residual snapshot changed for $i/$c.');
      }
    }
  }
  if (solved == 0 && result.stats.residualEvaluations != 0) {
    throw StateError('A clean solve unexpectedly evaluated residuals.');
  }
}

Map<String, Object> _measurement(
    List<int> samples, List<Map<String, Object>> work) {
  final sorted = [...samples]..sort();
  return {
    'p50': sorted[sorted.length ~/ 2],
    'p95': sorted[(sorted.length * .95).ceil() - 1],
    'samples_us': samples,
    'work_per_sample': work,
  };
}

Map<String, Object> _work(GeometrySolveResult result) => {
      'components_solved': result.stats.componentsSolved,
      'components_reused': result.stats.componentsReused,
      'rank_factorizations': result.stats.rankFactorizations,
      'rank_reuses': result.stats.rankReuses,
      'residual_evaluations': result.stats.residualEvaluations,
      'jacobian_evaluations': result.stats.jacobianEvaluations,
      'linear_solves': result.stats.linearSolves,
    };

void main(List<String> arguments) {
  var samples = 25, warmups = 5;
  var counts = [100, 1000];
  var checkOnly = false;
  for (final argument in arguments) {
    if (argument == '--check-only') {
      checkOnly = true;
      continue;
    }
    final parts = argument.split('=');
    if (parts.length != 2) throw ArgumentError('Unknown argument $argument.');
    switch (parts.first) {
      case '--samples':
        samples = int.parse(parts.last);
      case '--warmups':
        warmups = int.parse(parts.last);
      case '--components':
        counts = parts.last.split(',').map(int.parse).toList();
      default:
        throw ArgumentError('Unknown argument $argument.');
    }
  }
  if (samples < 1 || warmups < 0 || counts.any((count) => count < 2)) {
    throw ArgumentError(
        'Use positive samples, nonnegative warmups and >=2 components.');
  }
  if (checkOnly) {
    samples = 1;
    warmups = 0;
  }
  final results = <Map<String, Object>>[];
  for (final count in counts) {
    final source = _model(count).createSession();
    final initial = source.solve();
    _check(initial, count, 1, solved: count);
    final direct = source.fork();
    final timings = <String, List<int>>{
      'fork_only': [],
      'clean_fork_solve': [],
      'sparse_fork_edit': [],
      'direct_sparse_edit': [],
    };
    final work = <String, List<Map<String, Object>>>{
      for (final name in timings.keys) name: [],
    };
    for (var iteration = -warmups; iteration < samples; iteration++) {
      final drive = iteration.isEven ? 1.25 : 1.5;
      final names = iteration.isEven
          ? timings.keys.toList()
          : timings.keys.toList().reversed;
      for (final name in names) {
        final watch = Stopwatch()..start();
        GeometrySolveResult? result;
        GeometrySolveSession? fork;
        switch (name) {
          case 'fork_only':
            fork = source.fork();
          case 'clean_fork_solve':
            result = source.fork().solve();
          case 'sparse_fork_edit':
            final candidate = source.fork()..setParameterValues('d0', [drive]);
            result = candidate.solve();
          case 'direct_sparse_edit':
            direct.setParameterValues('d0', [drive]);
            result = direct.solve();
        }
        watch.stop();
        if (iteration >= 0) timings[name]!.add(watch.elapsedMicroseconds);
        if (fork != null) {
          if (!identical(fork.lastResult, initial) ||
              fork.dirtyComponentCount != 0 ||
              fork.revision != source.revision) {
            throw StateError('Fork lost retained metadata.');
          }
          _checkValues(fork.values, count, 1);
          _checkValues(fork.pendingValues, count, 1);
          if (iteration >= 0) {
            work[name]!
                .add({'components_copied': count, 'solve_performed': false});
          }
        } else {
          final changed = name != 'clean_fork_solve';
          _check(result!, count, changed ? drive : 1, solved: changed ? 1 : 0);
          if (changed &&
              (result.stats.rankFactorizations != 0 ||
                  result.stats.rankReuses != 1)) {
            throw StateError('Edited component did not retain exact rank.');
          }
          if (iteration >= 0) work[name]!.add(_work(result));
        }
      }
      _checkValues(source.values, count, 1);
      _checkValues(source.pendingValues, count, 1);
      if (!identical(source.lastResult, initial)) {
        throw StateError('A candidate changed the source session.');
      }
    }
    results.add({
      'components': count,
      'active_coordinates': count * 3,
      for (final name in timings.keys)
        name: _measurement(timings[name]!, work[name]!),
    });
  }
  if (checkOnly) {
    print('Independent geometry fork, coordinate and residual checks passed.');
    return;
  }
  print(jsonEncode({
    'fixture': 'Independent 3D dimensional components; one edited component',
    'units': 'microseconds',
    'warmups': warmups,
    'samples': samples,
    'results': results,
    'independent_checks': 'passed',
    'scope': 'One operation per sample. Fork+solve timings include candidate '
        'allocation; source compilation and initial validation are excluded. '
        'Direct edits retain their own previously edited state, while fork '
        'edits start from the initial source each time. '
        'This is a numerical fixture without solid-kernel work.',
  }));
}

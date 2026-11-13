/// Fixed-topology feature graph scaling with an independently checked sparse
/// four-feature edit. Uses only the API present at 3b5c4c4 so identical harnesses
/// can measure that baseline and the new graph implementation.
///
/// Cold creation includes graph construction and initial regeneration. Warm
/// paths time one regeneration only; all independent checks are outside timers.
/// Run with --check-only for a single untimed validation of each path.
library;

import 'dart:convert';

import 'package:dart_csp/cad.dart';

final class _Value {
  const _Value(this.number);
  final int number;
}

final class _Fixture {
  _Fixture(int featureCount, int drive) {
    if (featureCount < 5) throw ArgumentError('Use at least five features.');
    document = CadFeatureDocument(
        kernel: const ReferenceCadKernel(),
        parameters: CadParameters({'drive': drive.toDouble(), 'unused': 0}),
        features: [
          CadFeatureNode(
              id: 'driven',
              parameterDependencies: ['drive'],
              evaluate: (context) {
                evaluations++;
                return CadKernelResult.success(
                    _Value(context.parameters['drive'].toInt()));
              }),
          for (var i = 0; i < featureCount - 4; i++)
            CadFeatureNode(
                id: 'fixed$i',
                evaluate: (_) {
                  evaluations++;
                  return CadKernelResult.success(_Value(i));
                }),
          for (var i = 0; i < 3; i++)
            CadFeatureNode(
                id: 'relay$i',
                dependencies: [if (i == 0) 'driven' else 'relay${i - 1}'],
                evaluate: (context) {
                  evaluations++;
                  final value = context
                          .input<_Value>(i == 0 ? 'driven' : 'relay${i - 1}')
                          .number +
                      1;
                  if (i == 2 && value < 0) {
                    return CadKernelResult.failure(CadKernelStatus.invalidInput,
                        [const CadIssue('negative_drive', 'Invalid drive.')]);
                  }
                  return CadKernelResult.success(_Value(value));
                }),
        ]);
  }
  late final CadFeatureDocument document;
  int evaluations = 0;
}

void _check(CadRegenerationResult result, int featureCount, int drive) {
  if (!result.isSuccess ||
      result.state.outputs.length != featureCount ||
      result.state.output<_Value>('driven').number != drive ||
      result.state.output<_Value>('relay2').number != drive + 3) {
    throw StateError('Feature values or graph size failed independent checks.');
  }
  for (var i = 0; i < featureCount - 4; i++) {
    if (result.state.output<_Value>('fixed$i').number != i) {
      throw StateError('Unaffected feature fixed$i changed.');
    }
  }
}

Map<String, Object> _distribution(List<int> samples) {
  final sorted = [...samples]..sort();
  return {
    'p50': sorted[sorted.length ~/ 2],
    'p95': sorted[(sorted.length * 0.95).ceil() - 1],
    'samples_us': samples,
  };
}

void main(List<String> arguments) {
  var samples = 25, warmups = 5;
  var sizes = [1000, 10000];
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
      case '--sizes':
        sizes = parts.last.split(',').map(int.parse).toList();
      default:
        throw ArgumentError('Unknown argument $argument.');
    }
  }
  if (samples < 1 || warmups < 0 || sizes.any((value) => value < 5)) {
    throw ArgumentError('Invalid sampling counts or feature sizes.');
  }
  if (checkOnly) {
    samples = 1;
    warmups = 0;
  }
  final results = <Map<String, Object>>[];
  for (final size in sizes) {
    final retained = _Fixture(size, 1);
    _check(retained.document.regenerate(), size, 1);
    final initial = retained.document.state;
    final cold = <int>[],
        edit = <int>[],
        noOp = <int>[],
        unused = <int>[],
        rejected = <int>[];
    for (var iteration = -warmups; iteration < samples; iteration++) {
      final drive = iteration.isEven ? 2 : 3;
      void runCold() {
        final watch = Stopwatch()..start();
        final fixture = _Fixture(size, drive);
        final result = fixture.document.regenerate();
        watch.stop();
        _check(result, size, drive);
        if (fixture.evaluations != size ||
            result.rebuiltFeatures.length != size) {
          throw StateError('Cold graph did not evaluate every feature once.');
        }
        if (iteration >= 0) cold.add(watch.elapsedMicroseconds);
      }

      void runEdit() {
        final before = retained.evaluations;
        final watch = Stopwatch()..start();
        final result =
            retained.document.regenerate(changes: {'drive': drive.toDouble()});
        watch.stop();
        _check(result, size, drive);
        if (retained.evaluations - before != 4 ||
            result.rebuiltFeatures.join(',') != 'driven,relay0,relay1,relay2' ||
            !identical(
                initial.outputs['fixed0'], result.state.outputs['fixed0'])) {
          throw StateError(
              'Sparse edit did not preserve unrelated output identity.');
        }
        if (iteration >= 0) edit.add(watch.elapsedMicroseconds);
      }

      if (iteration.isEven) {
        runCold();
        runEdit();
      } else {
        runEdit();
        runCold();
      }
      final committed = retained.document.state;
      final before = retained.evaluations;
      final noopWatch = Stopwatch()..start();
      final unchanged =
          retained.document.regenerate(changes: {'drive': drive.toDouble()});
      noopWatch.stop();
      if (unchanged.status != CadRegenerationStatus.unchanged ||
          !identical(unchanged.state, committed) ||
          retained.evaluations != before) {
        throw StateError(
            'No-op edit changed committed state or evaluated a feature.');
      }
      final unusedWatch = Stopwatch()..start();
      final unrelated =
          retained.document.regenerate(changes: {'unused': drive.toDouble()});
      unusedWatch.stop();
      if (unrelated.rebuiltFeatures.isNotEmpty ||
          retained.evaluations != before ||
          unrelated.state.parameters['unused'] != drive ||
          !identical(
              unrelated.state.outputs['relay2'], committed.outputs['relay2'])) {
        throw StateError(
            'Unused parameter edit evaluated features or lost values.');
      }
      final previous = retained.document.state;
      final rejectWatch = Stopwatch()..start();
      final failure = retained.document.regenerate(changes: {'drive': -10});
      rejectWatch.stop();
      if (failure.status != CadRegenerationStatus.rejected ||
          failure.failedFeature != 'relay2' ||
          !identical(failure.state, previous) ||
          retained.evaluations - before != 4) {
        throw StateError(
            'Rejected candidate leaked into the committed document.');
      }
      if (iteration >= 0) {
        noOp.add(noopWatch.elapsedMicroseconds);
        unused.add(unusedWatch.elapsedMicroseconds);
        rejected.add(rejectWatch.elapsedMicroseconds);
      }
    }
    results.add({
      'feature_count': size,
      'affected_features': 4,
      'warmups': warmups,
      'samples': samples,
      'cold_build_regenerate': _distribution(cold),
      'sparse_edit': _distribution(edit),
      'no_op_edit': _distribution(noOp),
      'unused_parameter_edit': _distribution(unused),
      'rejected_edit': _distribution(rejected),
    });
  }
  if (checkOnly) {
    print('Feature graph cold/sparse/no-op/unused/rejected checks passed.');
    return;
  }
  print(jsonEncode({
    'fixture':
        'fixed-topology wide CAD feature DAG with a four-feature driven branch',
    'units': 'microseconds',
    'scope':
        'graph bookkeeping with scalar immutable outputs; not kernel or nonlinear solve time',
    'independent_value_identity_evaluation_and_rollback_checks': 'passed',
    'results': results,
  }));
}

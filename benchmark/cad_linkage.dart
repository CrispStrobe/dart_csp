/// Articulated solid CAD paths with independent physical and retention checks.
///
/// Cold timing includes model/graph construction, solving, four analytic bar
/// extrusions and four meshes. Retained paths time regeneration only. The
/// independent circle-intersection, pivot, normal and volume/export oracles
/// run after each timer stops; original solver/kernel validation stays inside.
/// APIs and imported examples are present at checkpoint 2777886.
library;

import 'dart:convert';

import 'package:dart_csp/cad.dart';

import '../example/nonlinear_linkage.dart' show checkFourBarSolution;
import '../example/parametric_linkage.dart';

const _moving = ['crank', 'coupler', 'rocker'];
const _allFeatures = [
  'linkage',
  'ground.profile',
  'ground.body',
  'ground.mesh',
  'crank.profile',
  'crank.body',
  'crank.mesh',
  'coupler.profile',
  'coupler.body',
  'coupler.mesh',
  'rocker.profile',
  'rocker.body',
  'rocker.mesh',
  'ground',
  'crank',
  'coupler',
  'rocker',
];

class _WorkKernel extends ReferenceCadKernel {
  final extrusions = <String, int>{}, tessellations = <String, int>{};

  @override
  CadKernelResult<CadBody> extrude({
    required String featureId,
    required CadPlanarProfile profile,
    required double depth,
  }) {
    extrusions.update(featureId, (value) => value + 1, ifAbsent: () => 1);
    return super.extrude(featureId: featureId, profile: profile, depth: depth);
  }

  @override
  CadKernelResult<CadMesh> tessellate(CadBody body,
      {double chordError = 0.05}) {
    tessellations.update(body.featureId, (value) => value + 1,
        ifAbsent: () => 1);
    return super.tessellate(body, chordError: chordError);
  }

  (Map<String, int>, Map<String, int>) snapshot() =>
      (Map.of(extrusions), Map.of(tessellations));
}

class _Fixture {
  _Fixture({bool downstreamGate = false}) {
    document = buildParametricLinkage(kernel: kernel, downstreamFeatures: [
      if (downstreamGate)
        CadFeatureNode(
            id: 'gate',
            dependencies: ['linkage', 'rocker'],
            parameterDependencies: ['angle'],
            evaluate: (context) {
              candidateAtGate = context.input<GeometrySolveResult>('linkage');
              return context.parameters['angle'] > 1
                  ? CadKernelResult.failure(CadKernelStatus.invalidInput,
                      [const CadIssue('fixture_gate', 'Downstream rejection.')])
                  : CadKernelResult.success(
                      context.input<CadBodyInstance>('rocker'));
            }),
    ]);
  }

  final kernel = _WorkKernel();
  late final CadFeatureDocument document;
  GeometrySolveResult? candidateAtGate;

  void initialize() {
    final result = document.regenerate();
    _checkSuccess(result);
  }
}

class _Measurements {
  final samples = <int>[];
  final work = <Map<String, Object>>[];

  void add(int elapsed, Map<String, Object> counters) {
    samples.add(elapsed);
    work.add(counters);
  }

  Map<String, Object> toJson() {
    final sorted = [...samples]..sort();
    return {
      'p50': sorted[sorted.length ~/ 2],
      'p95': sorted[(sorted.length * .95).ceil() - 1],
      'samples_us': samples,
      'work_per_sample': work,
    };
  }
}

(T, int) _timed<T>(T Function() operation, {required bool checkOnly}) {
  if (checkOnly) return (operation(), 0);
  final watch = Stopwatch()..start();
  final result = operation();
  watch.stop();
  return (result, watch.elapsedMicroseconds);
}

void _checkSuccess(CadRegenerationResult result) {
  if (!result.isSuccess) {
    throw StateError('Articulated assembly failed: ${result.issues}');
  }
  checkParametricLinkage(result.state);
}

void _checkRebuilt(CadRegenerationResult result, List<String> expected) {
  if (result.rebuiltFeatures.join(',') != expected.join(',')) {
    throw StateError('Unexpected regenerated features: '
        '${result.rebuiltFeatures} versus $expected.');
  }
}

void _checkRetained(CadDocumentState before, CadDocumentState after,
    {String? changedPart}) {
  for (final part in linkageParts) {
    for (final kind in ['profile', 'body', 'mesh']) {
      final retained = identical(
          before.outputs['$part.$kind'], after.outputs['$part.$kind']);
      if (retained != (part != changedPart)) {
        throw StateError('Unexpected prototype retention for $part.$kind.');
      }
    }
  }
  if (!identical(before.outputs['ground'], after.outputs['ground'])) {
    throw StateError('A moving-assembly edit replaced the fixed ground.');
  }
}

Map<String, Object> _work(
  _WorkKernel kernel,
  (Map<String, int>, Map<String, int>) before,
  CadRegenerationResult result, {
  required Set<String> rebuiltParts,
  GeometrySolveResult? solved,
}) {
  final extrusions = <String, int>{}, tessellations = <String, int>{};
  for (final part in linkageParts) {
    final id = '$part.body';
    final e = (kernel.extrusions[id] ?? 0) - (before.$1[id] ?? 0);
    final t = (kernel.tessellations[id] ?? 0) - (before.$2[id] ?? 0);
    final expected = rebuiltParts.contains(part) ? 1 : 0;
    if (e != expected || t != expected) {
      throw StateError('Unexpected kernel work for $part: $e extrusions, '
          '$t tessellations; expected $expected each.');
    }
    extrusions[part] = e;
    tessellations[part] = t;
  }
  final stats = solved?.stats;
  return {
    'extrusions_by_part': extrusions,
    'tessellations_by_part': tessellations,
    'rebuilt_features': result.rebuiltFeatures,
    'scheduled_features': result.stats.scheduledFeatures,
    'dependency_edges_visited': result.stats.dependencyEdgesVisited,
    'state_entries_copied': result.stats.stateEntriesCopied,
    'state_directory_entries_copied': result.stats.stateDirectoryEntriesCopied,
    // A retained result's old work is deliberately not attributed to a new
    // placement-only regeneration. Null means no solve was invoked this time.
    'geometry_solve_invoked': solved != null,
    'residual_evaluations': stats?.residualEvaluations ?? 0,
    'jacobian_evaluations': stats?.jacobianEvaluations ?? 0,
    'linear_solves': stats?.linearSolves ?? 0,
    'linear_iterations': stats?.linearIterations ?? 0,
    'nonlinear_iterations': stats?.nonlinearIterations ?? 0,
    'components_solved': stats?.componentsSolved ?? 0,
    'components_reused': stats?.componentsReused ?? 0,
    'rank_factorizations': stats?.rankFactorizations ?? 0,
    'rank_reuses': stats?.rankReuses ?? 0,
  };
}

void main(List<String> arguments) {
  var warmups = 5, samples = 25, checkOnly = false;
  for (final argument in arguments) {
    if (argument == '--check-only') {
      checkOnly = true;
      continue;
    }
    final parts = argument.split('=');
    if (parts.length != 2) throw ArgumentError('Unknown argument $argument.');
    switch (parts.first) {
      case '--warmups':
        warmups = int.parse(parts.last);
      case '--samples':
        samples = int.parse(parts.last);
      default:
        throw ArgumentError('Unknown argument $argument.');
    }
  }
  if (warmups < 0 || samples < 1) {
    throw ArgumentError('Warmups must be nonnegative and samples positive.');
  }
  if (checkOnly) {
    warmups = 0;
    samples = 1;
  }

  final angle = _Fixture()..initialize();
  final shape = _Fixture()..initialize();
  final layers = _Fixture()..initialize();
  final rejected = _Fixture(downstreamGate: true)..initialize();
  final history = [
    angle.document.state,
    shape.document.state,
    layers.document.state,
    rejected.document.state,
  ];
  final measurements = {
    for (final name in [
      'cold_build_solve_solids_meshes',
      'retained_angle_edit',
      'selective_coupler_length_edit',
      'placement_only_layer_edit',
      'downstream_rejected_angle_edit',
    ])
      name: _Measurements(),
  };
  for (var iteration = -warmups; iteration < samples; iteration++) {
    void record(String name, int elapsed, Map<String, Object> work) {
      if (iteration >= 0) measurements[name]!.add(elapsed, work);
    }

    void runCold() {
      final ((fixture, result), elapsed) = _timed(() {
        final fixture = _Fixture();
        return (fixture, fixture.document.regenerate());
      }, checkOnly: checkOnly);
      _checkSuccess(result);
      _checkRebuilt(result, _allFeatures);
      record(
          'cold_build_solve_solids_meshes',
          elapsed,
          _work(fixture.kernel, ({}, {}), result,
              rebuiltParts: linkageParts.toSet(),
              solved: result.state.output<GeometrySolveResult>('linkage')));
    }

    void runEdit(_Fixture fixture, String name, Map<String, double> changes,
        List<String> rebuilt,
        {String? changedPart, bool solve = true}) {
      final before = fixture.document.state, counts = fixture.kernel.snapshot();
      final (result, elapsed) = _timed(
          () => fixture.document.regenerate(changes: changes),
          checkOnly: checkOnly);
      _checkSuccess(result);
      _checkRebuilt(result, rebuilt);
      _checkRetained(before, result.state, changedPart: changedPart);
      final geometry = result.state.output<GeometrySolveResult>('linkage');
      if (identical(before.outputs['linkage'], geometry) == solve) {
        throw StateError('Unexpected geometry result retention for $name.');
      }
      record(
          name,
          elapsed,
          _work(fixture.kernel, counts, result,
              rebuiltParts: {if (changedPart != null) changedPart},
              solved: solve ? geometry : null));
    }

    void runRejection() {
      final before = rejected.document.state;
      final counts = rejected.kernel.snapshot();
      rejected.candidateAtGate = null;
      final (result, elapsed) = _timed(
          () => rejected.document.regenerate(changes: {'angle': 1.2}),
          checkOnly: checkOnly);
      final candidate = rejected.candidateAtGate;
      if (result.status != CadRegenerationStatus.rejected ||
          result.failedFeature != 'gate' ||
          !identical(result.state, before) ||
          !identical(rejected.document.state, before) ||
          candidate == null ||
          identical(candidate, before.outputs['linkage'])) {
        throw StateError(
            'Downstream rejection failed to preserve exact state.');
      }
      _checkRebuilt(result, ['linkage', ..._moving, 'gate']);
      checkFourBarSolution(candidate, angle: 1.2);
      checkParametricLinkage(before);
      record(
          'downstream_rejected_angle_edit',
          elapsed,
          _work(rejected.kernel, counts, result,
              rebuiltParts: const {}, solved: candidate));
      // A fresh valid edit proves the rejected solve did not become committed
      // history. Its work is outside the rejected-operation timer and counters.
      final recovery = rejected.document
          .regenerate(changes: {'angle': iteration.isEven ? 0.8 : 0.9});
      _checkSuccess(recovery);
      _checkRebuilt(recovery, ['linkage', ..._moving, 'gate']);
      _checkRetained(before, recovery.state);
      _work(rejected.kernel, counts, recovery,
          rebuiltParts: const {},
          solved: recovery.state.output<GeometrySolveResult>('linkage'));
    }

    final operations = <void Function()>[
      runCold,
      () => runEdit(angle, 'retained_angle_edit',
          {'angle': iteration.isEven ? 0.9 : 1.1}, ['linkage', ..._moving]),
      () => runEdit(
          shape,
          'selective_coupler_length_edit',
          {'coupler_length': iteration.isEven ? 3.1 : 3.2},
          [
            'linkage',
            'coupler.profile',
            'coupler.body',
            'coupler.mesh',
            ..._moving,
          ],
          changedPart: 'coupler'),
      () => runEdit(layers, 'placement_only_layer_edit',
          {'layer_spacing': iteration.isEven ? 0.3 : 0.35}, _moving,
          solve: false),
      runRejection,
    ];
    for (final operation
        in iteration.isEven ? operations : operations.reversed) {
      operation();
    }
  }
  for (final state in history) {
    checkParametricLinkage(state);
  }
  if (checkOnly) {
    print('Articulated solid paths, independent physical checks, exact kernel '
        'work, retained history and downstream rollback checks passed.');
    return;
  }
  print(jsonEncode({
    'fixture':
        'tilted 3D four-bar assembly with four two-hole solids and meshes',
    'units': 'microseconds',
    'operations_per_batch': 1,
    'feature_count': 17,
    'rejected_fixture_feature_count': 18,
    'warmup_iterations': warmups,
    'measured_iterations': samples,
    'measurements': {
      for (final entry in measurements.entries)
        entry.key: {
          'feature_count':
              entry.key == 'downstream_rejected_angle_edit' ? 18 : 17,
          ...entry.value.toJson(),
        },
    },
    'independent_physical_reuse_rollback_checks': 'passed',
    'counter_alignment': 'work_per_sample[i] describes samples_us[i]; no-solve '
        'placement edits report zero new physical work, not retained statistics',
    'scope': 'regular branch +1; layered reference solids without pins, bearings '
        'or collision; rejected row includes a solved candidate and downstream '
        'gate, with successful recovery checked outside its timer and counters',
  }));
}

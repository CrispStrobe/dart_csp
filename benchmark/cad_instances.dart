/// Current cold/regeneration comparison, not an old-release speedup claim.
/// Both paths solve the same two-plate placement; checks and work-record
/// collection run outside complete-operation timers. Raw samples retain
/// acquisition order, aligned with their physical-work records.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:dart_csp/cad.dart';

import '../example/parametric_assembly.dart';

// Ordinary benchmark builds explicitly keep operation tracing disabled.
// ignore: avoid_redundant_argument_values
const _profile = bool.fromEnvironment('dart_csp_profile', defaultValue: false);

class _WorkKernel extends ReferenceCadKernel {
  var extrusions = 0, tessellations = 0;
  @override
  CadKernelResult<CadBody> extrude({
    required String featureId,
    required CadPlanarProfile profile,
    required double depth,
  }) {
    extrusions++;
    return super.extrude(featureId: featureId, profile: profile, depth: depth);
  }

  @override
  CadKernelResult<CadMesh> tessellate(CadBody body,
      {double chordError = 0.05}) {
    tessellations++;
    return super.tessellate(body, chordError: chordError);
  }
}

const _allFeatures = [
  'profile',
  'plate',
  'mesh',
  'base',
  'assembly',
  'upright'
];
const _poseFeatures = ['assembly', 'upright'];

void _check(CadFeatureDocument document, double expectedGap) {
  final state = document.state, parameters = state.parameters;
  final prototype = state.output<CadBody>('plate');
  final upright = state.output<CadBodyInstance>('upright');
  final geometry = state.output<GeometrySolveResult>('assembly');
  final mesh = state.output<CadMesh>('mesh');
  final position = upright.placement.translation;
  final normal = upright.placement.transformDirection(const CadPoint3(0, 0, 1));
  final expectedVolume =
      (parameters['width'] * parameters['height'] - math.pi * 4) *
          parameters['thickness'];
  if (![
        prototype.volume,
        expectedVolume,
        mesh.signedVolume,
        geometry.maxToleranceRatio,
        position.x,
        position.y,
        position.z,
        normal.x,
        normal.y,
        normal.z
      ].every((value) => value.isFinite) ||
      parameters['gap'] != expectedGap ||
      !geometry.isSuccess ||
      geometry.maxToleranceRatio > 1 ||
      (prototype.volume - expectedVolume).abs() > 1e-6 ||
      position.x.abs() > 1e-7 ||
      (position.y - parameters['height'] / 2 - parameters['gap']).abs() >
          1e-7 ||
      (position.z - parameters['height'] / 2).abs() > 1e-7 ||
      normal.x.abs() > 1e-9 ||
      (normal.y - 1).abs() > 1e-9 ||
      normal.z.abs() > 1e-9 ||
      mesh.validate().isNotEmpty ||
      !identical(upright.body, prototype) ||
      !identical(state.output<CadBodyInstance>('base').body, prototype)) {
    throw StateError(
        'Independent assembly coordinate/volume/reuse check failed.');
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
      'p99': sorted[(sorted.length * .99).ceil() - 1],
      'samples_us': samples,
      'work_per_sample': work,
    };
  }
}

Map<String, Object> _work(_WorkKernel kernel, (int, int) beforeCounts,
    CadRegenerationResult result, CadDocumentState? previous) {
  final cold = previous == null;
  final features = cold ? _allFeatures : _poseFeatures;
  final extrusions = kernel.extrusions - beforeCounts.$1;
  final tessellations = kernel.tessellations - beforeCounts.$2;
  final geometry = result.state.output<GeometrySolveResult>('assembly');
  final invoked = !identical(previous?.outputs['assembly'], geometry);
  final bodyReused = previous != null &&
      identical(previous.outputs['plate'], result.state.outputs['plate']);
  final meshReused = previous != null &&
      identical(previous.outputs['mesh'], result.state.outputs['mesh']);
  if (result.rebuiltFeatures.join(',') != features.join(',') ||
      result.stats.scheduledFeatures != features.length ||
      extrusions != (cold ? 1 : 0) ||
      tessellations != (cold ? 1 : 0) ||
      !invoked ||
      bodyReused != !cold ||
      meshReused != !cold) {
    throw StateError(
        'Assembly rebuild/solve/kernel work or retention changed.');
  }
  final stats = geometry.stats;
  return {
    'gap': result.state.parameters['gap'],
    'extrusions': extrusions,
    'tessellations': tessellations,
    'rebuilt_features': result.rebuiltFeatures,
    'scheduled_features': result.stats.scheduledFeatures,
    'dependency_edges_visited': result.stats.dependencyEdgesVisited,
    'state_chunks_copied': result.stats.stateChunksCopied,
    'state_entries_copied': result.stats.stateEntriesCopied,
    'state_directory_entries_copied': result.stats.stateDirectoryEntriesCopied,
    'prototype_reused': bodyReused,
    'mesh_reused': meshReused,
    'geometry_solve_invoked': invoked,
    'residual_evaluations': stats.residualEvaluations,
    'jacobian_evaluations': stats.jacobianEvaluations,
    'linear_solves': stats.linearSolves,
    'linear_iterations': stats.linearIterations,
    'nonlinear_iterations': stats.nonlinearIterations,
    'components_solved': stats.componentsSolved,
    'components_reused': stats.componentsReused,
    'rank_factorizations': stats.rankFactorizations,
    'rank_reuses': stats.rankReuses,
    'jacobian_nonzeros': stats.jacobianNonzeros,
    'auto_diff_derivative_coordinates': stats.autoDiffDerivativeCoordinates,
  };
}

void main(List<String> arguments) {
  var warmups = 5, samples = 40, checkOnly = false;
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
    // Exercise both gap values and both operation orders without timing.
    warmups = 0;
    samples = 2;
  }
  final kernel = _WorkKernel();
  final document = buildParametricPlateAssembly(kernel: kernel);
  if (!document.regenerate().isSuccess) {
    throw StateError('Initial assembly failed.');
  }
  _check(document, 5);
  final body = document.state.outputs['plate'],
      mesh = document.state.outputs['mesh'];
  final cold = _Measurements(), edits = _Measurements();
  for (var i = 0; i < warmups + samples; i++) {
    final gap = i.isEven ? 12.0 : 5.0;
    for (final path in i.isEven ? [0, 1] : [1, 0]) {
      final previous = path == 0 ? null : document.state;
      final beforeCounts =
          path == 0 ? (0, 0) : (kernel.extrusions, kernel.tessellations);
      final caseName =
          path == 0 ? 'cold_build_solve_regenerate' : 'solved_pose_edit';
      if (_profile) {
        developer.Timeline.startSync('cad_operation/$caseName', arguments: {
          'iteration': i - warmups,
          'case': caseName,
        });
      }
      final watch = checkOnly ? null : (Stopwatch()..start());
      late final _WorkKernel operationKernel;
      late final CadFeatureDocument candidate;
      late final CadRegenerationResult result;
      try {
        operationKernel = path == 0 ? _WorkKernel() : kernel;
        candidate = path == 0
            ? buildParametricPlateAssembly(gap: gap, kernel: operationKernel)
            : document;
        result = path == 0
            ? candidate.regenerate()
            : candidate.regenerate(changes: {'gap': gap});
      } finally {
        watch?.stop();
        if (_profile) developer.Timeline.finishSync();
      }
      if (!result.isSuccess) throw StateError('${result.issues}');
      _check(candidate, gap);
      final work = _work(operationKernel, beforeCounts, result, previous);
      if (path == 1) {
        if (!identical(candidate.state.outputs['plate'], body) ||
            !identical(candidate.state.outputs['mesh'], mesh) ||
            !identical(
                candidate.state.outputs['base'], previous!.outputs['base']) ||
            kernel.extrusions != 1 ||
            kernel.tessellations != 1) {
          throw StateError('Pose edit rebuilt a reusable solid or mesh.');
        }
      }
      if (i >= warmups) {
        (path == 0 ? cold : edits).add(watch?.elapsedMicroseconds ?? 0, work);
      }
    }
  }
  print(jsonEncode({
    'fixture': 'two perpendicular instances of one parametric plate',
    'units': 'microseconds',
    'operations_per_batch': 1,
    'feature_count': _allFeatures.length,
    'check_only': checkOnly,
    'operation_tracing_enabled': _profile,
    'warmup_pairs': warmups,
    'measured_pairs': samples,
    'cold_build_solve_regenerate': cold.toJson(),
    'solved_pose_edit': {...edits.toJson(), 'rebuilt_features': _poseFeatures},
    'retained_document_total_extrusions': kernel.extrusions,
    'retained_document_total_tessellations': kernel.tessellations,
    'coordinate_volume_reuse_checks': 'passed',
    'counter_alignment': 'work_per_sample[i] describes samples_us[i]; kernel '
        'deltas and fresh geometry statistics belong to that complete operation',
    'timed_work': 'cold model/kernel construction and regeneration, or retained '
        'gap edit and regeneration; independent checks and work capture are '
        'outside timers; check-only reports zero placeholders without timing',
    'scope': 'current cold versus repeated pose-only paths; numerical workspace '
        'is isolated per candidate; not an old-release comparison or collision guarantee',
  }));
}

/// Current cold/regeneration comparison, not an old-release speedup claim.
/// Both paths solve the same two-plate placement; checks run outside timing.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_csp/cad.dart';

import '../example/parametric_assembly.dart';

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

void _check(CadFeatureDocument document) {
  final state = document.state, parameters = state.parameters;
  final prototype = state.output<CadBody>('plate');
  final upright = state.output<CadBodyInstance>('upright');
  final geometry = state.output<GeometrySolveResult>('assembly');
  final position = upright.placement.translation;
  final normal = upright.placement.transformDirection(const CadPoint3(0, 0, 1));
  final expectedVolume =
      (parameters['width'] * parameters['height'] - math.pi * 4) *
          parameters['thickness'];
  if (!geometry.isSuccess ||
      geometry.maxToleranceRatio > 1 ||
      (prototype.volume - expectedVolume).abs() > 1e-6 ||
      position.x.abs() > 1e-7 ||
      (position.y - parameters['height'] / 2 - parameters['gap']).abs() >
          1e-7 ||
      (position.z - parameters['height'] / 2).abs() > 1e-7 ||
      normal.x.abs() > 1e-9 ||
      (normal.y - 1).abs() > 1e-9 ||
      normal.z.abs() > 1e-9 ||
      state.output<CadMesh>('mesh').validate().isNotEmpty ||
      !identical(upright.body, prototype) ||
      !identical(state.output<CadBodyInstance>('base').body, prototype)) {
    throw StateError(
        'Independent assembly coordinate/volume/reuse check failed.');
  }
}

Map<String, num> _distribution(List<int> samples) {
  samples.sort();
  return {
    'p50': samples[samples.length ~/ 2],
    'p95': samples[(samples.length * 0.95).ceil() - 1]
  };
}

void main() {
  const warmups = 5, repetitions = 40;
  final kernel = _WorkKernel();
  final document = buildParametricPlateAssembly(kernel: kernel);
  if (!document.regenerate().isSuccess) {
    throw StateError('Initial assembly failed.');
  }
  final body = document.state.outputs['plate'],
      mesh = document.state.outputs['mesh'];
  final cold = <int>[], edits = <int>[];
  var rebuilt = <String>[];
  for (var i = 0; i < warmups + repetitions; i++) {
    final gap = i.isEven ? 12.0 : 5.0;
    for (final path in i.isEven ? [0, 1] : [1, 0]) {
      final watch = Stopwatch()..start();
      final candidate =
          path == 0 ? buildParametricPlateAssembly(gap: gap) : document;
      final result = path == 0
          ? candidate.regenerate()
          : candidate.regenerate(changes: {'gap': gap});
      watch.stop();
      if (!result.isSuccess) throw StateError('${result.issues}');
      _check(candidate);
      if (path == 1) {
        rebuilt = result.rebuiltFeatures;
        if (!identical(candidate.state.outputs['plate'], body) ||
            !identical(candidate.state.outputs['mesh'], mesh) ||
            kernel.extrusions != 1 ||
            kernel.tessellations != 1) {
          throw StateError('Pose edit rebuilt a reusable solid or mesh.');
        }
      }
      if (i >= warmups) {
        (path == 0 ? cold : edits).add(watch.elapsedMicroseconds);
      }
    }
  }
  print(jsonEncode({
    'fixture': 'two perpendicular instances of one parametric plate',
    'units': 'microseconds',
    'warmup_pairs': warmups,
    'measured_pairs': repetitions,
    'cold_build_solve_regenerate': _distribution(cold),
    'solved_pose_edit': {..._distribution(edits), 'rebuilt_features': rebuilt},
    'retained_document_total_extrusions': kernel.extrusions,
    'retained_document_total_tessellations': kernel.tessellations,
    'coordinate_volume_reuse_checks': 'passed',
    'scope': 'current cold versus repeated pose-only paths; numerical workspace '
        'is isolated per candidate; not an old-release comparison or collision guarantee',
  }));
}

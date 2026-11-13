import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

import '../example/parametric_linkage.dart';

class _WorkKernel extends ReferenceCadKernel {
  final extrusions = <String, int>{}, tessellations = <String, int>{};
  @override
  CadKernelResult<CadBody> extrude(
      {required String featureId,
      required CadPlanarProfile profile,
      required double depth}) {
    extrusions.update(featureId, (n) => n + 1, ifAbsent: () => 1);
    return super.extrude(featureId: featureId, profile: profile, depth: depth);
  }

  @override
  CadKernelResult<CadMesh> tessellate(CadBody body,
      {double chordError = 0.05}) {
    tessellations.update(body.featureId, (n) => n + 1, ifAbsent: () => 1);
    return super.tessellate(body, chordError: chordError);
  }
}

void main() {
  test('solid linkage places both assembly branches with independent pivots',
      () {
    for (final branch in [1, -1]) {
      final document = buildParametricLinkage(branch: branch);
      final result = document.regenerate();
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      checkParametricLinkage(result.state, branch: branch);
      final edited = document.regenerate(changes: {'angle': 1.1});
      expect(edited.isSuccess, isTrue, reason: '${edited.issues}');
      checkParametricLinkage(edited.state, branch: branch);
    }
  });

  test('angle edits retain all four bodies and meshes plus fixed ground', () {
    final kernel = _WorkKernel();
    final document = buildParametricLinkage(kernel: kernel);
    expect(document.regenerate().isSuccess, isTrue);
    final before = document.state;
    for (final angle in [0.9, 1.2, 0.6]) {
      final result = document.regenerate(changes: {'angle': angle});
      expect(result.isSuccess, isTrue, reason: '${result.issues}');
      expect(result.rebuiltFeatures, ['linkage', 'crank', 'coupler', 'rocker']);
      checkParametricLinkage(result.state);
      expect(
          identical(result.state.outputs['ground'], before.outputs['ground']),
          isTrue);
      for (final part in linkageParts) {
        expect(kernel.extrusions['$part.body'], 1);
        expect(kernel.tessellations['$part.body'], 1);
        for (final kind in ['body', 'mesh']) {
          expect(
              identical(result.state.outputs['$part.$kind'],
                  before.outputs['$part.$kind']),
              isTrue);
        }
      }
    }
    checkParametricLinkage(before);
  });

  test('link length edit rebuilds only its affected prototype and mesh', () {
    final kernel = _WorkKernel();
    final document = buildParametricLinkage(kernel: kernel);
    expect(document.regenerate().isSuccess, isTrue);
    final before = document.state;
    final result = document.regenerate(changes: {'coupler_length': 3.2});
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    expect(result.rebuiltFeatures, [
      'linkage',
      'coupler.profile',
      'coupler.body',
      'coupler.mesh',
      'crank',
      'coupler',
      'rocker'
    ]);
    checkParametricLinkage(result.state);
    for (final part in linkageParts) {
      expect(kernel.extrusions['$part.body'], part == 'coupler' ? 2 : 1);
      expect(kernel.tessellations['$part.body'], part == 'coupler' ? 2 : 1);
      for (final kind in ['body', 'mesh']) {
        expect(
            identical(before.outputs['$part.$kind'],
                result.state.outputs['$part.$kind']),
            part != 'coupler');
      }
    }
    checkParametricLinkage(before);
  });

  test('layer edit repositions instances without rebuilding solve or solids',
      () {
    final document = buildParametricLinkage();
    expect(document.regenerate().isSuccess, isTrue);
    final before = document.state;
    final result = document.regenerate(changes: {'layer_spacing': 0.35});
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    expect(result.rebuiltFeatures, ['crank', 'coupler', 'rocker']);
    expect(
        identical(result.state.outputs['linkage'], before.outputs['linkage']),
        isTrue);
    checkParametricLinkage(result.state);
    final committed = document.state;
    final rejected = document.regenerate(changes: {'layer_spacing': -1});
    expect(rejected.status, CadRegenerationStatus.rejected);
    expect(identical(document.state, committed), isTrue);
  });

  test('impossible dimensions and invalid profiles preserve exact assembly',
      () {
    final document = buildParametricLinkage();
    expect(document.regenerate().isSuccess, isTrue);
    final before = document.state;
    final impossible = document.regenerate(changes: {
      'coupler_length': 0.2,
      'rocker_length': 0.2,
    });
    expect(impossible.status, CadRegenerationStatus.rejected);
    expect(impossible.failedFeature, 'linkage');
    expect(identical(impossible.state, before), isTrue);
    final invalid = document.regenerate(changes: {'hole_radius': 0.4});
    expect(invalid.status, CadRegenerationStatus.rejected);
    expect(identical(invalid.state, before), isTrue);
    final recovered = document.regenerate(changes: {'angle': 0.8});
    expect(recovered.isSuccess, isTrue, reason: '${recovered.issues}');
    checkParametricLinkage(recovered.state);
    checkParametricLinkage(before);
  });

  test('failure after solved placements cannot become the next committed seed',
      () {
    final document = buildParametricLinkage(downstreamFeatures: [
      CadFeatureNode(
          id: 'gate',
          dependencies: ['rocker'],
          parameterDependencies: ['angle'],
          evaluate: (context) => context.parameters['angle'] > 1
              ? CadKernelResult.failure(CadKernelStatus.invalidInput,
                  [const CadIssue('fixture_gate', 'Rejected downstream.')])
              : CadKernelResult.success(
                  context.input<CadBodyInstance>('rocker'))),
    ]);
    expect(document.regenerate().isSuccess, isTrue);
    final before = document.state;
    final rejected = document.regenerate(changes: {'angle': 1.2});
    expect(rejected.status, CadRegenerationStatus.rejected);
    expect(rejected.failedFeature, 'gate');
    expect(rejected.rebuiltFeatures,
        ['linkage', 'crank', 'coupler', 'rocker', 'gate']);
    expect(identical(rejected.state, before), isTrue);
    final recovered = document.regenerate(changes: {'angle': 0.9});
    expect(recovered.isSuccess, isTrue, reason: '${recovered.issues}');
    checkParametricLinkage(recovered.state);
    checkParametricLinkage(before);
  });
}

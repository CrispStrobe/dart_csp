/// Two perpendicular occurrences of one parametric plate, positioned by the
/// 3D geometric solver. Rigid placement shares the analytic body and local mesh;
/// this is a multi-solid assembly, not a fused or filleted bracket.
library;

import 'dart:math' as math;

import 'package:dart_csp/cad.dart';

CadFeatureDocument buildParametricPlateAssembly({
  double width = 40,
  double height = 30,
  double thickness = 3,
  double gap = 5,
  CadKernel kernel = const ReferenceCadKernel(),
}) {
  final geometry = GeometryBuilder();
  final base = geometry.pose('base', fixed: true);
  final upright = geometry.pose('upright',
      translation: Vec3(0, height / 2 + gap, height / 2),
      quaternion: [math.sqrt(0.5), -math.sqrt(0.5), 0, 0]);
  geometry.dimension('gap', gap, lower: 1e-9);
  geometry.dimension('height', height, lower: 1e-9);
  geometry.mateAxes('normal', base, Vec3.unitY, upright, Vec3.unitZ,
      sameDirection: true);
  geometry.mateAxes('horizontal', base, Vec3.unitX, upright, Vec3.unitX,
      sameDirection: true);
  geometry.addResidual(GeometryResidualBlock.autoDiff(
      id: 'clearance',
      parameterIds: [upright.translationId, 'gap', 'height'],
      residualCount: 3,
      evaluate: (p) => [
            p[0][0],
            p[0][1] - p[2][0] / 2 - p[1][0],
            p[0][2] - p[2][0] / 2,
          ]));
  return CadFeatureDocument(
      kernel: kernel,
      parameters: CadParameters({
        'width': width,
        'height': height,
        'thickness': thickness,
        'gap': gap,
      }),
      features: [
        CadFeatureNode.rectangularProfile(
            id: 'profile',
            width: CadExpression.parameter('width'),
            height: CadExpression.parameter('height'),
            holes: [
              CadHoleExpression(
                  id: 'mount',
                  centerX: CadExpression.constant(0),
                  centerY: CadExpression.constant(0),
                  radius: CadExpression.constant(2)),
            ]),
        CadFeatureNode.extrude(
            id: 'plate',
            profile: 'profile',
            depth: CadExpression.parameter('thickness')),
        CadFeatureNode.tessellate(
            id: 'mesh',
            body: 'plate',
            chordError: CadExpression.constant(0.02)),
        CadFeatureNode.instance(
            id: 'base', body: 'plate', placement: CadPlacementExpression()),
        constrainedGeometryFeature(
            id: 'assembly',
            model: geometry.compile(),
            dimensionBindings: {
              'gap': CadExpression.parameter('gap'),
              'height': CadExpression.parameter('height'),
            }),
        CadFeatureNode.instanceFromPose(
            id: 'upright', body: 'plate', geometry: 'assembly', pose: upright),
      ],
      requiredReferences: const [
        TopologyRef(
            featureId: 'base', semanticId: 'top', kind: CadTopologyKind.face),
        TopologyRef(
            featureId: 'upright',
            semanticId: 'hole.mount.wall',
            kind: CadTopologyKind.face),
      ]);
}

void main() {
  final document = buildParametricPlateAssembly();
  final initial = document.regenerate();
  if (!initial.isSuccess) throw StateError('${initial.issues}');
  final localMesh = document.state.output<CadMesh>('mesh');
  final prototype = document.state.output<CadBody>('plate');
  final edit = document.regenerate(changes: {'gap': 12});
  if (!edit.isSuccess) throw StateError('${edit.issues}');
  if (!identical(localMesh, document.state.output<CadMesh>('mesh')) ||
      !identical(prototype, document.state.output<CadBody>('plate'))) {
    throw StateError(
        'A pose edit must reuse the analytic body and local mesh.');
  }
  final upright = document.state.output<CadBodyInstance>('upright');
  final top = document.state.resolve(const TopologyRef(
      featureId: 'upright', semanticId: 'top', kind: CadTopologyKind.face));
  final normal = ((top.entity! as CadFace).surface as CadPlaneSurface).normal;
  print('Gap edit rebuilt: ${edit.rebuiltFeatures.join(', ')}.');
  print('Both plate occurrences share ${localMesh.triangles.length} local '
      'triangles. Upright top normal: $normal.');
  print('Renderer matrix: ${upright.placement.toColumnMajorMatrix4()}.');
  final exported = upright.placement.transformMesh(localMesh);
  if (!exported.isSuccess) throw StateError('${exported.issues}');
  print('Materialized upright mesh volume: ${exported.value!.signedVolume}.');

  final committed = document.state;
  final rejected = document.regenerate(changes: {'gap': -1});
  if (rejected.isSuccess || !identical(document.state, committed)) {
    throw StateError('Invalid assembly dimensions must roll back together.');
  }
  print(
      'Invalid gap rejected; assembly revision ${committed.revision} retained.');
}

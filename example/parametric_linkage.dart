/// An articulated four-bar solid assembly in a tilted 3D workplane.
///
/// Four two-hole rectangular bars occupy separate parallel layers. Their pivot
/// axes are coaxial at solved joints, but pins, bearings, collision detection
/// and fused solid operations are not modeled. Angle edits retain all local
/// analytic bodies and display meshes. This is a local assembly-branch example.
library;

import 'dart:math' as math;

import 'package:dart_csp/cad.dart';

import 'nonlinear_linkage.dart';

const linkageParts = ['ground', 'crank', 'coupler', 'rocker'];
const _normal = CadPoint3(0.64, -0.48, 0.6);
final _frame = CadRigidTransform(
    translation: const CadPoint3(7, -3, 2), quaternion: [0.8, 0.4, 0.2, 0.4]);

/// Quaternion columns are u=(.6,.8,0), v=(-.48,.36,.8), n=(.64,-.48,.6).
/// Compose a local Z rotation and midpoint/layer translation through that frame.
CadRigidTransform _placement(
    List<double> start, List<double> end, int layer, double spacing) {
  final dx = end[0] - start[0], dy = end[1] - start[1], dz = end[2] - start[2];
  final x = (start[0] + end[0]) / 2 - 7;
  final y = (start[1] + end[1]) / 2 + 3;
  final z = (start[2] + end[2]) / 2 - 2;
  final angle =
      math.atan2(-0.48 * dx + 0.36 * dy + 0.8 * dz, 0.6 * dx + 0.8 * dy);
  if (!spacing.isFinite || spacing <= 0) {
    throw ArgumentError('Layer spacing must be positive and finite.');
  }
  return _frame.compose(CadRigidTransform.axisAngle(
      axis: const CadPoint3(0, 0, 1),
      angle: angle,
      translation: CadPoint3(
          0.6 * x + 0.8 * y, -0.48 * x + 0.36 * y + 0.8 * z, layer * spacing)));
}

CadFeatureDocument buildParametricLinkage({
  double angle = linkageInitialAngle,
  double crankLength = linkageCrankLength,
  double couplerLength = linkageCouplerLength,
  double rockerLength = linkageRockerLength,
  int branch = 1,
  CadKernel kernel = const ReferenceCadKernel(),
  Iterable<CadFeatureNode> downstreamFeatures = const [],
}) {
  final features = <CadFeatureNode>[
    constrainedGeometryFeature(
        id: 'linkage',
        model: buildFourBarLinkage(branch: branch),
        dimensionBindings: {
          'input_angle': CadExpression.parameter('angle'),
          for (final part in linkageParts.skip(1))
            '${part}_length': CadExpression.parameter('${part}_length'),
        }),
  ];
  for (final part in linkageParts) {
    final length = part == 'ground'
        ? CadExpression.constant(linkageGroundLength)
        : CadExpression.parameter('${part}_length');
    features.addAll([
      CadFeatureNode.rectangularProfile(
          id: '$part.profile',
          width: length + CadExpression.parameter('end_margin') * 2,
          height: CadExpression.parameter('bar_width'),
          holes: [
            CadHoleExpression(
                id: 'start',
                centerX: -length / 2,
                centerY: CadExpression.constant(0),
                radius: CadExpression.parameter('hole_radius')),
            CadHoleExpression(
                id: 'end',
                centerX: length / 2,
                centerY: CadExpression.constant(0),
                radius: CadExpression.parameter('hole_radius')),
          ]),
      CadFeatureNode.extrude(
          id: '$part.body',
          profile: '$part.profile',
          depth: CadExpression.parameter('thickness')),
      CadFeatureNode.tessellate(
          id: '$part.mesh',
          body: '$part.body',
          chordError: CadExpression.constant(0.003)),
    ]);
  }
  features.add(CadFeatureNode(
      id: 'ground',
      dependencies: ['ground.body'],
      evaluate: (context) => CadKernelResult.success(CadBodyInstance(
          featureId: 'ground',
          body: context.input<CadBody>('ground.body'),
          placement: _frame.compose(CadRigidTransform(
              translation: const CadPoint3(linkageGroundLength / 2, 0, 0)))))));
  for (final part in const [
    ('crank', 'a', 'b', 1),
    ('coupler', 'b', 'c', 2),
    ('rocker', 'd', 'c', 3),
  ]) {
    features.add(CadFeatureNode(
        id: part.$1,
        dependencies: ['${part.$1}.body', 'linkage'],
        parameterDependencies: ['layer_spacing'],
        evaluate: (context) {
          final geometry = context.input<GeometrySolveResult>('linkage');
          if (!geometry.isSuccess) {
            throw StateError('Only a successful linkage solve may place bars.');
          }
          return CadKernelResult.success(CadBodyInstance(
              featureId: part.$1,
              body: context.input<CadBody>('${part.$1}.body'),
              placement: _placement(
                  geometry.values[part.$2]!,
                  geometry.values[part.$3]!,
                  part.$4,
                  context.parameters['layer_spacing'])));
        }));
  }
  return CadFeatureDocument(
      kernel: kernel,
      parameters: CadParameters({
        'angle': angle,
        'crank_length': crankLength,
        'coupler_length': couplerLength,
        'rocker_length': rockerLength,
        'bar_width': 0.45,
        'end_margin': 0.3,
        'hole_radius': 0.1,
        'thickness': 0.12,
        'layer_spacing': 0.2,
      }),
      features: [
        ...features,
        ...downstreamFeatures
      ],
      requiredReferences: [
        for (final part in linkageParts)
          for (final hole in ['start', 'end'])
            TopologyRef(
                featureId: part,
                semanticId: 'hole.$hole.wall',
                kind: CadTopologyKind.face),
      ]);
}

void _pointCheck(CadPoint3 actual, CadPoint3 expected,
    {double tolerance = 5e-7}) {
  if (!actual.isFinite || (actual - expected).length > tolerance) {
    throw StateError('Independent placed point check failed: '
        '$actual versus $expected.');
  }
}

/// Uses the independent circle-intersection solution and explicit basis
/// coefficients to check actual semantic hole axes/centers, normals and volumes.
/// Mesh export is checked separately from the renderer's retained local mesh.
void checkParametricLinkage(CadDocumentState state, {int branch = 1}) {
  final p = state.parameters;
  final geometry = state.output<GeometrySolveResult>('linkage');
  checkFourBarSolution(geometry,
      angle: p['angle'],
      crankLength: p['crank_length'],
      couplerLength: p['coupler_length'],
      rockerLength: p['rocker_length'],
      branch: branch);
  final oracle = fourBarOracle(
      angle: p['angle'],
      crankLength: p['crank_length'],
      couplerLength: p['coupler_length'],
      rockerLength: p['rocker_length'],
      branch: branch);
  final points = {
    'a': const CadPoint3(7, -3, 2),
    'd': const CadPoint3(9.4, 0.2, 2),
    'b': CadPoint3(oracle.crank.x, oracle.crank.y, oracle.crank.z),
    'c': CadPoint3(oracle.joint.x, oracle.joint.y, oracle.joint.z),
  };
  for (final part in const [
    ('ground', 'a', 'd', 0),
    ('crank', 'a', 'b', 1),
    ('coupler', 'b', 'c', 2),
    ('rocker', 'd', 'c', 3),
  ]) {
    final name = part.$1;
    final body = state.output<CadBody>('$name.body');
    final mesh = state.output<CadMesh>('$name.mesh');
    final instance = state.output<CadBodyInstance>(name);
    final length = name == 'ground' ? linkageGroundLength : p['${name}_length'];
    final volume = ((length + 2 * p['end_margin']) * p['bar_width'] -
            2 * math.pi * p['hole_radius'] * p['hole_radius']) *
        p['thickness'];
    if (!identical(instance.body, body) ||
        (instance.volume - volume).abs() > 1e-12 ||
        mesh.validate().isNotEmpty) {
      throw StateError('Independent analytic volume/prototype check failed.');
    }
    for (final hole in [('start', part.$2), ('end', part.$3)]) {
      final expected =
          points[hole.$2]! + _normal.scaled(part.$4 * p['layer_spacing']);
      final wall = (instance
              .resolve(CadTopologyKind.face, 'hole.${hole.$1}.wall')
              .entity! as CadFace)
          .surface as CadCylinderSurface;
      _pointCheck(wall.origin, expected);
      _pointCheck(wall.axis, _normal, tolerance: 1e-12);
      if ((wall.radius - p['hole_radius']).abs() > 1e-12 || !wall.inward) {
        throw StateError('A placed pivot cylinder changed radius/orientation.');
      }
      for (final level in ['bottom', 'top']) {
        final circle = (instance
                .resolve(CadTopologyKind.edge, 'hole.${hole.$1}.$level')
                .entity! as CadEdge)
            .curve as CadCircleCurve;
        _pointCheck(circle.center,
            expected + _normal.scaled(level == 'top' ? p['thickness'] : 0));
        _pointCheck(circle.normal, _normal, tolerance: 1e-12);
      }
    }
    final top =
        (instance.resolve(CadTopologyKind.face, 'top').entity! as CadFace)
            .surface as CadPlaneSurface;
    _pointCheck(top.normal, _normal, tolerance: 1e-12);
    final expectedMid = (points[part.$2]! + points[part.$3]!).scaled(0.5) +
        _normal.scaled(part.$4 * p['layer_spacing'] + p['thickness']);
    _pointCheck(top.origin, expectedMid);
    final export = instance.placement.transformMesh(mesh);
    if (!export.isSuccess ||
        (export.value!.signedVolume - mesh.signedVolume).abs() > 1e-10 ||
        (export.value!.signedVolume - volume).abs() >
            4 * math.pi * p['hole_radius'] * mesh.chordError * p['thickness'] +
                1e-9) {
      throw StateError(
          'Placed mesh winding or independent volume bound failed.');
    }
  }
}

void main() {
  final document = buildParametricLinkage();
  final initial = document.regenerate();
  if (!initial.isSuccess) throw StateError('${initial.issues}');
  checkParametricLinkage(initial.state);
  final edit = document.regenerate(changes: {'angle': 1.1});
  if (!edit.isSuccess) throw StateError('${edit.issues}');
  checkParametricLinkage(edit.state);
  for (final part in linkageParts) {
    for (final kind in ['body', 'mesh']) {
      if (!identical(initial.state.outputs['$part.$kind'],
          edit.state.outputs['$part.$kind'])) {
        throw StateError('An angle edit rebuilt a reusable prototype.');
      }
    }
  }
  print('Angle edit rebuilt ${edit.rebuiltFeatures.join(', ')}.');
  print('Four analytic bars and local meshes retained; three moving '
      'instances have independently checked coaxial pivot axes.');
  final committed = document.state;
  final failed = document.regenerate(changes: {
    'coupler_length': 0.2,
    'rocker_length': 0.2,
  });
  if (failed.isSuccess || !identical(document.state, committed)) {
    throw StateError('An impossible edit did not preserve the last assembly.');
  }
  print('Impossible dimensions rejected; previous assembly retained. '
      'Layered multi-solid example: pins and collision checks are not modeled.');
}

/// Executable parametric CAD example: a two-hole mounting plate.
///
/// Run `dart run example/parametric_bracket.dart`. Dimensions use one
/// consistent unit (millimetres here). The reference backend supports this
/// analytic extrusion; it does not claim bent brackets, fillets or booleans.
library;

import 'package:dart_csp/cad.dart';

CadFeatureDocument buildParametricBracket({
  double width = 100,
  double height = 40,
  double thickness = 6,
  double holeSpacing = 60,
  double holeDiameter = 8,
  double chordError = 0.02,
  CadKernel kernel = const ReferenceCadKernel(),
}) {
  final w = CadExpression.parameter('width');
  final h = CadExpression.parameter('height');
  final spacing = CadExpression.parameter('holeSpacing');
  final radius = CadExpression.parameter('holeDiameter') / 2;
  final sketch = _buildSketch(width, height, holeSpacing, holeDiameter / 2);
  return CadFeatureDocument(
    kernel: kernel,
    parameters: CadParameters({
      'width': width,
      'height': height,
      'thickness': thickness,
      'holeSpacing': holeSpacing,
      'holeDiameter': holeDiameter,
      'chordError': chordError,
    }),
    features: [
      constrainedSketchFeature(
        id: 'sketch',
        model: sketch,
        dimensionBindings: {
          'width': w,
          'height': h,
          'spacing': spacing,
          'radius': radius,
        },
        buildProfile: (geometry, parameters) {
          final p = geometry.values;
          final lo = p['corner.sw']!, hi = p['corner.ne']!;
          final left = p['hole.left']!, right = p['hole.right']!;
          // Independent checks at the geometry -> kernel boundary.
          const tolerance = 1e-6;
          if ((hi[0] - lo[0] - parameters['width']).abs() > tolerance ||
              (hi[1] - lo[1] - parameters['height']).abs() > tolerance ||
              (right[0] - left[0] - parameters['holeSpacing']).abs() >
                  tolerance ||
              left[0] >= right[0]) {
            throw StateError('The solved sketch changed its intended branch.');
          }
          return CadRectangularProfile(
            width: hi[0] - lo[0],
            height: hi[1] - lo[1],
            holes: [
              CadCircularHole(
                  id: 'left',
                  centerX: left[0],
                  centerY: left[1],
                  radius: p['radius']!.single),
              CadCircularHole(
                  id: 'right',
                  centerX: right[0],
                  centerY: right[1],
                  radius: p['radius']!.single),
            ],
          );
        },
      ),
      sketchProfileFeature(id: 'profile', sketch: 'sketch'),
      CadFeatureNode.extrude(
          id: 'plate',
          profile: 'profile',
          depth: CadExpression.parameter('thickness')),
      CadFeatureNode.tessellate(
          id: 'mesh',
          body: 'plate',
          chordError: CadExpression.parameter('chordError')),
    ],
    requiredReferences: const [
      TopologyRef(
          featureId: 'plate', semanticId: 'top', kind: CadTopologyKind.face),
      TopologyRef(
          featureId: 'plate',
          semanticId: 'hole.left.wall',
          kind: CadTopologyKind.face),
      TopologyRef(
          featureId: 'plate',
          semanticId: 'hole.right.wall',
          kind: CadTopologyKind.face),
    ],
  );
}

CompiledGeometryModel _buildSketch(
    double width, double height, double spacing, double radius) {
  final b = GeometryBuilder();
  final plane = GeometryWorkplane(origin: Vec3.zero, normal: Vec3.unitZ);
  final origin = b.point3('origin', Vec3.zero, fixed: true);
  final axis = b.point3('axis.x', Vec3.unitX, fixed: true);
  final sw = b.workplanePoint('corner.sw', plane, -width / 2, -height / 2);
  final ne = b.workplanePoint('corner.ne', plane, width / 2, height / 2);
  final left = b.workplanePoint('hole.left', plane, -spacing / 2, 0);
  final right = b.workplanePoint('hole.right', plane, spacing / 2, 0);
  b.dimension('width', width, lower: 1e-12);
  b.dimension('height', height, lower: 1e-12);
  final span = b.dimension('spacing', spacing, lower: 1e-12);
  b.dimension('radius', radius, lower: 1e-12);
  b.addResidual(GeometryResidualBlock.autoDiff(
      id: 'rectangle',
      parameterIds: [sw.id, ne.id, 'width', 'height'],
      residualCount: 5,
      evaluate: (p) => [
            p[0][0] + p[1][0],
            p[0][1] + p[1][1],
            p[0][2] + p[1][2],
            p[1][0] - p[0][0] - p[2][0],
            p[1][1] - p[0][1] - p[3][0],
          ]));
  b.pointOnLine('left.centerline', left, GeometryLine(origin, axis));
  b.pointOnLine('right.centerline', right, GeometryLine(origin, axis));
  b.distance('hole.spacing', left, right, span);
  b.addResidual(GeometryResidualBlock.autoDiff(
      id: 'hole.symmetry',
      parameterIds: [left.id, right.id],
      residualCount: 1,
      evaluate: (p) => [p[0][0] + p[1][0]]));
  return b.compile();
}

void main() {
  final document = buildParametricBracket();
  final initial = document.regenerate();
  if (!initial.isSuccess) {
    throw StateError('Initial model failed: ${initial.issues}');
  }
  final body = document.state.output<CadBody>('plate');
  final mesh = document.state.output<CadMesh>('mesh');
  final sketch = document.state.output<CadSolvedSketch>('sketch');
  print('Two-hole mounting plate: ${body.volume.toStringAsFixed(3)} mm^3, '
      '${body.faces.length} analytic faces, ${mesh.triangles.length} display triangles.');
  print('Required sketch residual ratio: ${sketch.geometry.maxToleranceRatio}; '
      'local freedoms: ${sketch.geometry.localDegreesOfFreedom}.');

  final thicknessEdit = document.regenerate(changes: {'thickness': 8});
  if (!thicknessEdit.isSuccess) throw StateError('${thicknessEdit.issues}');
  print('Thickness edit rebuilt: ${thicknessEdit.rebuiltFeatures.join(', ')}.');

  final profileEdit =
      document.regenerate(changes: {'width': 120, 'holeSpacing': 80});
  if (!profileEdit.isSuccess) throw StateError('${profileEdit.issues}');
  print(
      'Width/spacing edit rebuilt: ${profileEdit.rebuiltFeatures.join(', ')}.');

  final validState = document.state;
  final rejected = document.regenerate(changes: {'holeDiameter': 42});
  if (rejected.isSuccess || !identical(document.state, validState)) {
    throw StateError(
        'An invalid hole must fail without replacing valid geometry.');
  }
  print(
      'Invalid diameter rejected; revision ${document.state.revision} retained: '
      '${rejected.issues.first.message}');
}

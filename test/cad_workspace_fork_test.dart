import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

import '../example/parametric_bracket.dart';

CompiledGeometryModel _geometry({double Function()? coefficient}) =>
    GeometryModel(parameters: [
      GeometryParameterBlock(id: 'point', values: [1, 0]),
      GeometryParameterBlock(id: 'dimension', values: [1], fixed: true),
    ], constraints: [
      GeometryResidualBlock.autoDiff(
        id: 'x',
        parameterIds: ['point', 'dimension'],
        residualCount: 1,
        evaluate: (p) => [p[0][0] - p[1][0]],
      ),
      GeometryResidualBlock.autoDiff(
        id: 'y',
        parameterIds: ['point'],
        residualCount: 1,
        evaluate: (p) => [p[0][1] * (coefficient?.call() ?? 1)],
      ),
    ]).compile();

void main() {
  for (final asSketch in [false, true]) {
    test('captured state in an unedited component is revalidated: $asSketch',
        () {
      var capturedTarget = 0.0;
      final model = GeometryModel(parameters: [
        GeometryParameterBlock(id: 'x', values: [1]),
        GeometryParameterBlock(id: 'y', values: [0]),
        GeometryParameterBlock(id: 'size', values: [1], fixed: true),
      ], constraints: [
        GeometryResidualBlock.autoDiff(
          id: 'x-size',
          parameterIds: ['x', 'size'],
          residualCount: 1,
          evaluate: (p) => [p[0][0] - p[1][0]],
        ),
        GeometryResidualBlock.autoDiff(
          id: 'captured-y',
          parameterIds: ['y'],
          residualCount: 1,
          evaluate: (p) => [p[0][0] - capturedTarget],
        ),
      ]).compile();
      final bindings = {'size': CadExpression.parameter('size')};
      final feature = asSketch
          ? constrainedSketchFeature(
              id: 'shape',
              model: model,
              dimensionBindings: bindings,
              buildProfile: (_, parameters) =>
                  CadRectangularProfile(width: parameters['size'], height: 1))
          : constrainedGeometryFeature(
              id: 'shape', model: model, dimensionBindings: bindings);
      final document = CadFeatureDocument(
        kernel: const ReferenceCadKernel(),
        parameters: CadParameters({'size': 1}),
        features: [feature],
      );
      expect(document.regenerate().isSuccess, isTrue);
      capturedTarget = 7;
      expect(document.regenerate(changes: {'size': 2}).isSuccess, isTrue);
      final result = asSketch
          ? document.state.output<CadSolvedSketch>('shape').geometry
          : document.state.output<GeometrySolveResult>('shape');
      expect(result.values['x']!.single, closeTo(2, 1e-8));
      expect(result.values['y']!.single, closeTo(7, 1e-8));
      expect(result.stats.componentsSolved, 2);
      expect(result.stats.rankReuses, 2);
    });
  }

  test('CAD profile edits reuse exact rank and retain immutable prior outputs',
      () {
    final document = buildParametricBracket();
    expect(document.regenerate().isSuccess, isTrue);
    final old = document.state;
    final oldSketch = old.output<CadSolvedSketch>('sketch');
    expect(oldSketch.geometry.stats.rankFactorizations, greaterThan(0));
    expect(document.regenerate(changes: {'width': 120}).isSuccess, isTrue);
    final next = document.state.output<CadSolvedSketch>('sketch');
    expect(next.geometry.stats.rankReuses, 2);
    expect(next.geometry.stats.rankFactorizations, 0);
    expect(next.geometry.stats.residualEvaluations, greaterThan(0));
    expect(next.geometry.values['width'], [120]);
    expect(oldSketch.geometry.values['width'], [100]);
    expect(old.parameters['width'], 100);
    expect(old.output<CadBody>('plate').bounds.max.x, 50);
  });

  test('downstream solid rejection never seeds the next numerical candidate',
      () {
    final document = buildParametricBracket();
    expect(document.regenerate().isSuccess, isTrue);
    final old = document.state;
    expect(
        document.regenerate(changes: {
          'width': 120,
          'holeDiameter': 42,
        }).isSuccess,
        isFalse);
    expect(identical(document.state, old), isTrue);
    expect(document.regenerate(changes: {'holeSpacing': 65}).isSuccess, isTrue);
    final sketch = document.state.output<CadSolvedSketch>('sketch');
    expect(sketch.geometry.values['width'], [100]);
    expect(sketch.geometry.values['radius'], [4]);
    final left = sketch.geometry.values['hole.left']![0];
    final right = sketch.geometry.values['hole.right']![0];
    expect(right - left, closeTo(65, 1e-7));
    // The unchanged rectangle reuses rank. The nonlinear hole-distance
    // Jacobian may differ by rounding after its new spacing is solved.
    expect(sketch.geometry.stats.rankReuses, greaterThanOrEqualTo(1));
  });

  test('shared geometry feature declarations retain independent documents', () {
    final feature = constrainedGeometryFeature(
      id: 'geometry',
      model: _geometry(),
      dimensionBindings: {'dimension': CadExpression.parameter('size')},
    );
    CadFeatureDocument make(double size) => CadFeatureDocument(
          kernel: const ReferenceCadKernel(),
          parameters: CadParameters({'size': size}),
          features: [feature],
        );
    final first = make(2), second = make(7);
    expect(first.regenerate().isSuccess, isTrue);
    expect(second.regenerate().isSuccess, isTrue);
    expect(first.regenerate(changes: {'size': 3}).isSuccess, isTrue);
    expect(second.regenerate(changes: {'size': 8}).isSuccess, isTrue);
    final a = first.state.output<GeometrySolveResult>('geometry');
    final b = second.state.output<GeometrySolveResult>('geometry');
    expect(a.values['point']![0], closeTo(3, 1e-8));
    expect(b.values['point']![0], closeTo(8, 1e-8));
    expect(a.stats.rankReuses, 1);
    expect(b.stats.rankReuses, 1);
  });

  test('fresh callback derivatives invalidate retained rank after regeneration',
      () {
    var coefficient = 1.0;
    final feature = constrainedGeometryFeature(
      id: 'geometry',
      model: _geometry(coefficient: () => coefficient),
      dimensionBindings: {'dimension': CadExpression.parameter('size')},
    );
    final document = CadFeatureDocument(
      kernel: const ReferenceCadKernel(),
      parameters: CadParameters({'size': 1}),
      features: [feature],
    );
    expect(document.regenerate().isSuccess, isTrue);
    expect(
        document.state
            .output<GeometrySolveResult>('geometry')
            .localDegreesOfFreedom,
        0);
    coefficient = 0;
    expect(document.regenerate(changes: {'size': 2}).isSuccess, isTrue);
    final singular = document.state.output<GeometrySolveResult>('geometry');
    expect(singular.localDegreesOfFreedom, 1);
    expect(singular.stats.rankReuses, 0);
    expect(singular.stats.rankFactorizations, 2);
  });

  test('geometry candidate rejected downstream cannot replace committed rank',
      () {
    var coefficient = 1.0;
    final document = CadFeatureDocument(
      kernel: const ReferenceCadKernel(),
      parameters: CadParameters({'size': 1}),
      features: [
        constrainedGeometryFeature(
          id: 'geometry',
          model: _geometry(coefficient: () => coefficient),
          dimensionBindings: {'dimension': CadExpression.parameter('size')},
        ),
        CadFeatureNode(
          id: 'guard',
          dependencies: ['geometry'],
          evaluate: (context) {
            final solved = context.input<GeometrySolveResult>('geometry');
            return solved.values['dimension']!.single < 0
                ? CadKernelResult.failure(CadKernelStatus.invalidInput,
                    [const CadIssue('negative', 'Negative size rejected.')])
                : CadKernelResult.success(solved);
          },
        ),
      ],
    );
    expect(document.regenerate().isSuccess, isTrue);
    final old = document.state;
    coefficient = 0;
    expect(document.regenerate(changes: {'size': -2}).isSuccess, isFalse);
    expect(identical(document.state, old), isTrue);
    coefficient = 1;
    expect(document.regenerate(changes: {'size': 4}).isSuccess, isTrue);
    final result = document.state.output<GeometrySolveResult>('geometry');
    expect(result.localDegreesOfFreedom, 0);
    expect(result.stats.rankReuses, 1);
    expect(result.stats.rankFactorizations, 0);
    expect(result.values['point']![0], closeTo(4, 1e-8));
  });
}

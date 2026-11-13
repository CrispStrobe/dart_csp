import 'dart:math' as math;

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

import '../example/parametric_bracket.dart';

void _checkModel(CadFeatureDocument document) {
  final state = document.state, p = state.parameters;
  final sketch = state.output<CadSolvedSketch>('sketch');
  expect(sketch.geometry.isSuccess, isTrue);
  expect(sketch.geometry.maxToleranceRatio, lessThanOrEqualTo(1));
  expect(sketch.geometry.localDegreesOfFreedom, 0);
  final values = sketch.geometry.values;
  final left = values['hole.left']!, right = values['hole.right']!;
  expect(right[0] - left[0], closeTo(p['holeSpacing'], 1e-7));
  expect(left[0] + right[0], closeTo(0, 1e-7));
  expect(left[1].abs() + left[2].abs(), lessThan(1e-7));
  expect(right[1].abs() + right[2].abs(), lessThan(1e-7));
  final body = state.output<CadBody>('plate');
  final expected = (p['width'] * p['height'] -
          2 * math.pi * math.pow(p['holeDiameter'] / 2, 2)) *
      p['thickness'];
  expect(body.volume, closeTo(expected, 1e-4));
  expect(document.kernel.validate(body), isEmpty);
  expect(state.output<CadMesh>('mesh').validate(), isEmpty);
  for (final reference in document.requiredReferences) {
    expect(state.resolve(reference).status, CadTopologyResolutionStatus.found);
  }
}

void main() {
  test('constrained sketch regenerates an analytic solid and closed mesh', () {
    final document = buildParametricBracket();
    expect(document.regenerate().isSuccess, isTrue);
    expect(document.state.output<CadSolvedSketch>('sketch').seededFromPrevious,
        isFalse);
    _checkModel(document);
    final firstSketch = document.state.outputs['sketch'];
    final thickness = document.regenerate(changes: {'thickness': 8});
    expect(thickness.rebuiltFeatures, ['plate', 'mesh']);
    expect(identical(document.state.outputs['sketch'], firstSketch), isTrue);
    _checkModel(document);
    final edit = document.regenerate(changes: {
      'width': 120,
      'height': 50,
      'holeSpacing': 80,
      'holeDiameter': 10,
    });
    expect(edit.isSuccess, isTrue, reason: '${edit.issues}');
    expect(edit.rebuiltFeatures, ['sketch', 'profile', 'plate', 'mesh']);
    expect(document.state.output<CadSolvedSketch>('sketch').seededFromPrevious,
        isTrue);
    _checkModel(document);
  });

  test('solid failure retains parameters, sketch and semantic references', () {
    final document = buildParametricBracket();
    expect(document.regenerate().isSuccess, isTrue);
    final old = document.state;
    final bad =
        document.regenerate(changes: {'holeDiameter': 42, 'width': 120});
    expect(bad.status, CadRegenerationStatus.rejected);
    expect(bad.failedFeature, 'plate');
    expect(identical(document.state, old), isTrue);
    expect(document.state.parameters['holeDiameter'], 8);
    expect(document.state.parameters['width'], 100);
    final retry = document.regenerate(changes: {'holeSpacing': 65});
    expect(retry.isSuccess, isTrue, reason: '${retry.issues}');
    expect(document.state.parameters['width'], 100);
    _checkModel(document);
  });

  test('invalid sketch input rolls back before kernel evaluation', () {
    final document = buildParametricBracket();
    expect(document.regenerate().isSuccess, isTrue);
    final old = document.state;
    final bad = document.regenerate(changes: {'holeSpacing': -1});
    expect(bad.status, CadRegenerationStatus.rejected);
    expect(bad.failedFeature, 'sketch');
    expect(identical(document.state, old), isTrue);
    _checkModel(document);
  });

  test('sketch bindings reject unknown or non-fixed dimensions', () {
    final builder = GeometryBuilder();
    builder.dimension('free', 1, fixed: false);
    final model = builder.compile();
    for (final name in ['free', 'missing']) {
      expect(
          () => constrainedSketchFeature(
                id: 'sketch',
                model: model,
                dimensionBindings: {name: CadExpression.parameter('x')},
                buildProfile: (_, __) =>
                    CadRectangularProfile(width: 1, height: 1),
              ),
          throwsArgumentError);
    }
  });

  test('only committed previous output is visible to a feature evaluator', () {
    final seen = <double?>[];
    final document = CadFeatureDocument(
      kernel: const ReferenceCadKernel(),
      parameters: CadParameters({'x': 1}),
      features: [
        CadFeatureNode(
          id: 'first',
          parameterDependencies: ['x'],
          evaluate: (context) {
            seen.add(context.previousOutput<double>());
            return CadKernelResult.success(context.parameters['x']);
          },
        ),
        CadFeatureNode(
          id: 'second',
          dependencies: ['first'],
          evaluate: (context) => context.input<double>('first') < 0
              ? CadKernelResult.failure(CadKernelStatus.invalidInput,
                  [const CadIssue('negative', 'Negative input rejected.')])
              : CadKernelResult.success(context.input<double>('first')),
        ),
      ],
    );
    expect(document.regenerate().isSuccess, isTrue);
    expect(document.regenerate(changes: {'x': -1}).isSuccess, isFalse);
    expect(document.regenerate(changes: {'x': 2}).isSuccess, isTrue);
    expect(seen, [null, 1, 1]);
  });
}

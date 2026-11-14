import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

CompiledGeometryModel _model({bool Function()? fail}) => GeometryModel(
      parameters: [
        GeometryParameterBlock(id: 'x', values: [0.25]),
        GeometryParameterBlock(id: 'target', values: [0.25], fixed: true),
      ],
      constraints: [
        GeometryResidualBlock(
          id: 'dimension',
          parameterIds: ['x', 'target'],
          residualCount: 2,
          tolerances: [1e-8, 1],
          evaluate: (values, residuals, jacobians) {
            if (fail?.call() ?? false) {
              residuals.fillRange(0, residuals.length, double.nan);
              return;
            }
            residuals[0] = values[0][0] - values[1][0];
            residuals[1] = values[1][0] * 0.1;
            if (jacobians != null) {
              jacobians[0][0] = 1;
              jacobians[0][1] = 0;
              jacobians[1][0] = -1;
              jacobians[1][1] = 0.1;
            }
          },
        ),
      ],
    ).compile();

void _check(GeometrySolveResult result, double target) {
  expect(result.isSuccess, isTrue, reason: result.message);
  expect(result.values['x']!.single, closeTo(target, 1e-8));
  expect(result.values['target'], [target]);
  expect(result.constraintResiduals['dimension']![1], target * 0.1);
  expect(result.components.single.parameterIds, ['x']);
  expect(result.components.single.constraintIds, ['dimension']);
}

Map<String, List<double>> _copy(Map<String, List<double>> source) => {
      for (final entry in source.entries) entry.key: [...entry.value],
    };

void main() {
  test('published coordinate, residual and diagnostic collections reject edits',
      () {
    final result = _model().createSession().solve();
    _check(result, 0.25);
    expect(() => result.values['new'] = [1], throwsUnsupportedError);
    expect(result.values.clear, throwsUnsupportedError);
    expect(() => result.values['x']![0] = 1, throwsUnsupportedError);
    expect(
        () => result.constraintResiduals['new'] = [1], throwsUnsupportedError);
    expect(result.constraintResiduals.clear, throwsUnsupportedError);
    expect(() => result.constraintResiduals['dimension']![0] = 1,
        throwsUnsupportedError);
    expect(() => result.components.single.parameterIds[0] = 'changed',
        throwsUnsupportedError);
    expect(() => result.components.single.constraintIds.add('changed'),
        throwsUnsupportedError);
  });

  test('published snapshots survive fork edits, failures and later recovery',
      () {
    var fail = false;
    final source = _model(fail: () => fail).createSession();
    final first = source.solve();
    _check(first, 0.25);
    final firstValues = _copy(first.values);
    final firstResiduals = _copy(first.constraintResiduals);
    final firstSessionValues = source.values;

    final fork = source.fork()..setParameterValues('target', [0.75]);
    final forkResult = fork.solve();
    _check(forkResult, 0.75);
    final forkValues = _copy(forkResult.values);
    final forkResiduals = _copy(forkResult.constraintResiduals);

    source.setParameterValues('target', [0.5]);
    final edited = source.solve();
    _check(edited, 0.5);
    final editedValues = _copy(edited.values);
    final editedResiduals = _copy(edited.constraintResiduals);

    fail = true;
    source.invalidateConstraint('dimension');
    final rejected = source.solve();
    expect(rejected.status, GeometrySolveStatus.numericalFailure);
    expect(rejected.constraintResiduals['dimension']![0].isNaN, isTrue);
    expect(source.committedValues, editedValues);

    fail = false;
    source.invalidateConstraint('dimension');
    source.setParameterValues('target', [0.6]);
    _check(source.solve(), 0.6);

    expect(first.values, firstValues);
    expect(firstSessionValues, firstValues);
    expect(first.constraintResiduals, firstResiduals);
    expect(forkResult.values, forkValues);
    expect(forkResult.constraintResiduals, forkResiduals);
    expect(edited.values, editedValues);
    expect(edited.constraintResiduals, editedResiduals);
    expect(rejected.constraintResiduals['dimension']![0].isNaN, isTrue);
    for (final result in [first, forkResult, edited, rejected]) {
      expect(result.components.single.parameterIds, ['x']);
      expect(result.components.single.constraintIds, ['dimension']);
    }
  });
}

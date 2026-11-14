import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

void _constantResidual(List<Float64List> values, Float64List residuals,
    List<Float64List>? jacobians) {
  residuals[0] = 1;
}

class _MutableResidual extends GeometryResidualBlock {
  _MutableResidual()
      : super(
            id: 'required',
            parameterIds: ['x'],
            residualCount: 1,
            evaluate: _constantResidual);

  String currentId = 'required';
  final currentParameters = ['x'];
  int currentCount = 1;
  final currentTolerances = [1e-8];
  final currentScales = [1.0];
  GeometryResidualEvaluator currentEvaluator = _constantResidual;

  @override
  String get id => currentId;
  @override
  List<String> get parameterIds => currentParameters;
  @override
  int get residualCount => currentCount;
  @override
  List<double> get tolerances => currentTolerances;
  @override
  List<double> get scales => currentScales;
  @override
  GeometryResidualEvaluator get evaluate => currentEvaluator;
}

class _MutableParameter extends GeometryParameterBlock {
  _MutableParameter()
      : super(
            id: 'x',
            values: [0],
            lowerBounds: [-2],
            upperBounds: [2],
            scales: [2]);

  String currentId = 'x';
  final currentValues = [0.0];
  final currentLower = [-2.0];
  final currentUpper = [2.0];
  final currentScales = [2.0];
  bool currentFixed = false;

  @override
  String get id => currentId;
  @override
  List<double> get values => currentValues;
  @override
  List<double> get lowerBounds => currentLower;
  @override
  List<double> get upperBounds => currentUpper;
  @override
  List<double> get scales => currentScales;
  @override
  bool get fixed => currentFixed;
}

class _MutableModel extends GeometryModel {
  _MutableModel(this.currentParameters, this.currentConstraints)
      : super(parameters: currentParameters, constraints: currentConstraints);

  final List<GeometryParameterBlock> currentParameters;
  final List<GeometryResidualBlock> currentConstraints;
  @override
  List<GeometryParameterBlock> get parameters => currentParameters;
  @override
  List<GeometryResidualBlock> get constraints => currentConstraints;
}

void main() {
  test('callback getter mutation cannot loosen a compiled physical tolerance',
      () {
    final declaration = _MutableResidual();
    final model = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [0], fixed: true)
    ], constraints: [
      declaration
    ]).compile();
    final session = model.createSession();
    final result = session.solve(shouldCancel: () {
      declaration.currentTolerances[0] = 2;
      return false;
    });
    expect(result.isSuccess, isFalse);
    expect(result.constraintResiduals['required'], [1]);
    expect(result.maxToleranceRatio, 1e8);
    expect(session.committedValues, isNull);
    expect(model.constraints.single.tolerances, [1e-8]);
    // A newly compiled model intentionally captures the changed declaration.
    expect(
        GeometryModel(parameters: model.parameters, constraints: [declaration])
            .compile()
            .createSession()
            .solve()
            .isSuccess,
        isTrue);
  });

  test('residual layout, evaluator and scaling are captured together', () {
    final declaration = _MutableResidual();
    final model = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [0], fixed: true)
    ], constraints: [
      declaration
    ]).compile();
    declaration.currentId = 'replacement';
    declaration.currentParameters.clear();
    declaration.currentCount = 0;
    declaration.currentTolerances.clear();
    declaration.currentScales[0] = double.infinity;
    declaration.currentEvaluator = (values, residuals, jacobians) {
      residuals.fillRange(0, residuals.length, 0);
    };
    final result = model.createSession().solve();
    expect(result.isSuccess, isFalse);
    expect(result.constraintResiduals, {
      'required': [1.0]
    });
    expect(result.components.single.equationCount, 1);
    expect(model.constraints.single.parameterIds, ['x']);
    expect(model.constraints.single.scales, [1]);
    expect(() => model.constraints.single.tolerances[0] = 2,
        throwsUnsupportedError);
  });

  test('parameter metadata and coordinates cannot change after compilation',
      () {
    final declaration = _MutableParameter();
    final model =
        GeometryModel(parameters: [declaration], constraints: []).compile();
    declaration.currentId = 'replacement';
    declaration.currentValues[0] = 20;
    declaration.currentLower[0] = -100;
    declaration.currentUpper[0] = 100;
    declaration.currentScales[0] = 99;
    declaration.currentFixed = true;
    final session = model.createSession();
    expect(session.parameterValues('x'), [0]);
    expect(model.activeTangentDimension, 1);
    expect(model.parameters.single.fixed, isFalse);
    expect(model.parameters.single.scales, [2]);
    expect(() => session.setParameterValues('x', [3]), throwsArgumentError);
    session.setParameterValues('x', [1]);
    expect(session.solve().values, {
      'x': [1.0]
    });
    expect(() => model.parameters.single.values[0] = 2, throwsUnsupportedError);
  });

  test('model subclass lists cannot rewrite the compiled dependency graph', () {
    final source = _MutableModel([
      GeometryParameterBlock(id: 'x', values: [0], fixed: true)
    ], [
      _MutableResidual()
    ]);
    final compiled = source.compile();
    source.currentParameters.clear();
    source.currentConstraints.clear();
    expect(compiled.parameters.single.id, 'x');
    expect(compiled.constraints.single.id, 'required');
    expect(compiled.createSession().solve().isSuccess, isFalse);
    expect(compiled.parameters.clear, throwsUnsupportedError);
    expect(compiled.constraints.clear, throwsUnsupportedError);
  });

  test('invalid current metadata is rejected before constructing a graph', () {
    final constraint = _MutableResidual()..currentTolerances[0] = double.nan;
    expect(
        () => GeometryModel(parameters: [
              GeometryParameterBlock(id: 'x', values: [0])
            ], constraints: [
              constraint
            ]).compile(),
        throwsArgumentError);
    final parameter = _MutableParameter()..currentScales[0] = 0;
    expect(
        () => GeometryModel(parameters: [parameter], constraints: []).compile(),
        throwsArgumentError);
  });

  test('compiled automatic derivatives retain active-coordinate dispatch', () {
    final constraint = GeometryResidualBlock.autoDiff(
        id: 'target',
        parameterIds: ['x', 'target'],
        residualCount: 1,
        evaluate: (p) => [p[0][0] - p[1][0]]);
    final model = GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [2]),
      GeometryParameterBlock(id: 'target', values: [2], fixed: true)
    ], constraints: [
      constraint
    ]).compile();
    final result = model.createSession().solve();
    expect(result.isSuccess, isTrue);
    expect(result.stats.autoDiffDerivativeCoordinates, 1);
    final residuals = Float64List(1);
    final jacobians = [Float64List(1), Float64List(1)];
    model.constraints.single.evaluate([
      Float64List.fromList([2]),
      Float64List.fromList([3])
    ], residuals, jacobians);
    expect(residuals, [-1]);
    expect(jacobians[0], [1]);
    expect(jacobians[1], [-1]);
  });
}

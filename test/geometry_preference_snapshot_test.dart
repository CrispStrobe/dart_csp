import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

class _MutablePreferenceOptions extends GeometryPreferenceOptions {
  double currentTargetTolerance = 1e-7;
  int currentMaxIterations = 64;

  @override
  double get targetTolerance => currentTargetTolerance;
  @override
  int get maxIterations => currentMaxIterations;
}

class _MutableTarget extends GeometryParameterTarget {
  _MutableTarget({
    required List<double> desired,
    required double targetWeight,
    required List<double> targetScales,
  })  : currentValues = [...desired],
        currentWeight = targetWeight,
        currentScales = [...targetScales],
        super(
          parameterId: 'x',
          values: desired,
          weight: targetWeight,
          coordinateScales: targetScales,
        );

  final List<double> currentValues;
  double currentWeight;
  final List<double> currentScales;

  @override
  List<double> get values => currentValues;
  @override
  double get weight => currentWeight;
  @override
  List<double> get coordinateScales => currentScales;
}

GeometrySolveSession _session() => GeometryModel(parameters: [
      GeometryParameterBlock(id: 'x', values: [0]),
    ], constraints: []).compile().createSession();

void main() {
  test('callback mutation cannot report an unmet drag as targetReached', () {
    final session = _session();
    final options = _MutablePreferenceOptions();
    final result = session.solve(
      preferences: [
        GeometryParameterTarget(parameterId: 'x', values: [10])
      ],
      preferenceOptions: options,
      shouldCancel: () {
        options.currentTargetTolerance = double.infinity;
        return false;
      },
    );
    expect(result.isSuccess, isTrue);
    expect(result.preferenceReport!.status,
        GeometryPreferenceStatus.targetReached);
    expect(result.values['x']!.single, closeTo(10, 1e-7));
    expect(result.preferenceReport!.maxTargetError, lessThanOrEqualTo(1e-7));
  });

  test('the captured preference iteration budget governs the complete run', () {
    final options = _MutablePreferenceOptions();
    final session = _session();
    final result = session.solve(
      preferences: [
        GeometryParameterTarget(parameterId: 'x', values: [10])
      ],
      preferenceOptions: options,
      shouldCancel: () {
        options.currentMaxIterations = 0;
        return false;
      },
    );
    expect(result.isSuccess, isTrue);
    expect(result.values['x']!.single, closeTo(10, 1e-7));
    // The changed options apply on the next invocation, not retroactively.
    final next = session.solve(
      preferences: [
        GeometryParameterTarget(parameterId: 'x', values: [20])
      ],
      preferenceOptions: options,
    );
    expect(next.status, GeometrySolveStatus.iterationLimit);
    expect(session.committedValues!['x']!.single, closeTo(10, 1e-7));
  });

  test('target weight, scales and coordinates remain one captured objective',
      () {
    final target =
        _MutableTarget(desired: [10], targetWeight: 3, targetScales: [2]);
    final session = _session();
    final result = session.solve(
      preferences: [
        GeometryParameterTarget(parameterId: 'x', values: [2]),
        target,
      ],
      shouldCancel: () {
        target.currentValues[0] = -100;
        target.currentWeight = 1e20;
        target.currentScales[0] = 1e10;
        return false;
      },
    );
    expect(result.isSuccess, isTrue, reason: result.message);
    // Minimize (x-2)^2 + 3*((x-10)/2)^2: x=(2+7.5)/(1+0.75).
    expect(result.values['x']!.single, closeTo(38 / 7, 1e-7));
    expect(
        result.preferenceReport!.status, GeometryPreferenceStatus.stationary);
    final x = result.values['x']!.single;
    expect(result.preferenceReport!.finalCost,
        closeTo(0.5 * ((x - 2) * (x - 2) + 0.75 * (x - 10) * (x - 10)), 1e-9));
  });

  test('an async yield does not expose live preference options or target lists',
      () async {
    final session = _session();
    final options = _MutablePreferenceOptions();
    final target =
        _MutableTarget(desired: [4], targetWeight: 1, targetScales: [1]);
    final pending =
        session.solveAsync(preferences: [target], preferenceOptions: options);
    options.currentMaxIterations = 0;
    options.currentTargetTolerance = double.infinity;
    target.currentValues[0] = 100;
    target.currentScales[0] = double.nan;
    final result = await pending;
    expect(result.isSuccess, isTrue, reason: result.message);
    expect(result.values['x']!.single, closeTo(4, 1e-7));
    expect(result.preferenceReport!.maxTargetError, lessThanOrEqualTo(1e-7));
  });

  test('mutable target definitions are validated before entering a solve', () {
    final session = _session();
    final target =
        _MutableTarget(desired: [4], targetWeight: 1, targetScales: [1]);
    target.currentWeight = -1;
    expect(() => session.solve(preferences: [target]), throwsArgumentError);
    expect(session.committedValues, isNull);
    target.currentWeight = 1;
    target.currentScales[0] = double.nan;
    expect(() => session.solve(preferences: [target]), throwsArgumentError);
    target.currentScales[0] = 1;
    final result = session.solve(preferences: [target]);
    expect(result.isSuccess, isTrue);
    expect(result.values['x']!.single, closeTo(4, 1e-7));
  });
}

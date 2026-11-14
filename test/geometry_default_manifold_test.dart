import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

class _CaptureSolver implements GeometryLinearSolver {
  final captures = <Float64List>[];

  @override
  GeometryLinearStep solve(
    SparseGeometryJacobian jacobian,
    Float64List residual, {
    required double damping,
    required Float64List diagonal,
    int maxIterations = 1000,
    double relativeTolerance = 1e-8,
    bool Function()? shouldStop,
  }) {
    captures.add(Float64List.fromList(jacobian.values));
    return GeometryLinearStep(
      GeometryLinearStatus.cancelled,
      Float64List(jacobian.columns),
      iterations: 0,
      relativeResidual: double.infinity,
    );
  }
}

class _MutableEuclidean extends EuclideanGeometryManifold {
  _MutableEuclidean({this.reportedType}) : super(3);

  final Type? reportedType;
  final matrix = Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  Float64List? retainedOutput;
  int jacobianCalls = 0;

  @override
  Type get runtimeType => reportedType ?? super.runtimeType;

  @override
  void plusJacobian(Float64List base, Float64List out) {
    jacobianCalls++;
    out.setAll(0, matrix);
    retainedOutput = out;
  }

  @override
  void plus(Float64List base, Float64List delta, Float64List out) {
    for (var row = 0; row < 3; row++) {
      var shift = 0.0;
      for (var col = 0; col < 3; col++) {
        shift += matrix[row * 3 + col] * delta[col];
      }
      out[row] = base[row] + shift;
    }
  }
}

GeometrySolveSession _session({
  GeometryManifold? manifold,
  List<double> jacobian = const [2, -3, -0.0, 7, 4, -5],
  List<double> parameterScales = const [2, 4, 0.5],
  void Function()? duringDerivative,
}) =>
    GeometryModel(
      parameters: [
        GeometryParameterBlock(
          id: 'x',
          values: [0, 0, 0],
          scales: parameterScales,
          manifold: manifold,
        ),
      ],
      constraints: [
        GeometryResidualBlock(
          id: 'required',
          parameterIds: ['x'],
          residualCount: 2,
          scales: [5, 0.25],
          evaluate: (values, residuals, jacobians) {
            residuals.setAll(0, [1, 2]);
            if (jacobians != null) {
              duringDerivative?.call();
              jacobians[0].setAll(0, jacobian);
            }
          },
        ),
      ],
    ).compile().createSession();

void _expectCapture(GeometrySolveSession session, List<double> expected) {
  final backend = _CaptureSolver();
  final result = session.solve(linearSolver: backend);
  expect(result.status, GeometrySolveStatus.cancelled);
  expect(backend.captures, hasLength(1));
  expect(backend.captures.single, expected);
  expect(1 / backend.captures.single[2], double.infinity);
  expect(session.committedValues, isNull);
}

void main() {
  for (final kind in ['default', 'explicit', 'subclass']) {
    test('$kind Euclidean derivatives preserve scaling and positive zero', () {
      final GeometryManifold? manifold = switch (kind) {
        'explicit' => const EuclideanGeometryManifold(3),
        'subclass' => _MutableEuclidean(),
        _ => null,
      };
      final session = _session(manifold: manifold);
      expect(session.model.parameters.single.manifold,
          isA<EuclideanGeometryManifold>());
      _expectCapture(session, [0.8, -2.4, 0.0, 56, 64, -10]);
      if (manifold is _MutableEuclidean) {
        expect(manifold.jacobianCalls, greaterThan(0));
      }
    });
  }

  test('custom Jacobian changes are observed after each invalidation', () {
    final manifold = _MutableEuclidean();
    final session = _session(manifold: manifold);
    _expectCapture(session, [0.8, -2.4, 0.0, 56, 64, -10]);
    final calls = manifold.jacobianCalls;
    manifold.matrix.setAll(0, [1, 0.5, 0, 0, 2, 0, 0, 0, 1]);
    session.markAllDirty();
    _expectCapture(session, [0.8, -4, 0.0, 56, 184, -10]);
    expect(manifold.jacobianCalls, greaterThan(calls));
    manifold.matrix.setAll(0, [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    session.markAllDirty();
    _expectCapture(session, [0.8, -2.4, 0.0, 56, 64, -10]);
  });

  test('a custom runtimeType cannot impersonate a default manifold', () {
    final defaultType =
        GeometryParameterBlock(id: 'probe', values: [0]).manifold.runtimeType;
    final manifold = _MutableEuclidean(reportedType: defaultType)
      ..matrix.setAll(0, [1, 0.5, 0, 0, 2, 0, 0, 0, 1]);
    expect(manifold.runtimeType, defaultType);
    _expectCapture(
        _session(manifold: manifold), [0.8, -4, 0.0, 56, 184, -10]);
    expect(manifold.jacobianCalls, greaterThan(0));
  });

  test('residual callbacks can still update a retained custom tangent map', () {
    final manifold = _MutableEuclidean();
    final session = _session(
      manifold: manifold,
      duringDerivative: () => manifold.retainedOutput![1] = 0.5,
    );
    _expectCapture(session, [0.8, -1.6, 0.0, 56, 120, -10]);
  });

  test('nonfinite retained custom maps fail before the linear backend', () {
    final manifold = _MutableEuclidean();
    final session = _session(
      manifold: manifold,
      duringDerivative: () => manifold.retainedOutput![1] = double.nan,
    );
    final backend = _CaptureSolver();
    final result = session.solve(linearSolver: backend);
    expect(result.status, GeometrySolveStatus.numericalFailure);
    expect(result.message, contains('Non-finite Jacobian'));
    expect(backend.captures, isEmpty);
    expect(session.committedValues, isNull);
  });

  for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
    test('default derivatives reject $bad in a later ambient column', () {
      final session = _session(jacobian: [1, 2, bad, 7, 4, -5]);
      final backend = _CaptureSolver();
      final result = session.solve(linearSolver: backend);
      expect(result.status, GeometrySolveStatus.numericalFailure);
      expect(result.message, contains('Non-finite Jacobian'));
      expect(backend.captures, isEmpty);
      expect(session.committedValues, isNull);
    });
  }

  test('default derivative scaling still rejects overflow', () {
    final session = _session(jacobian: [1e308, 2, 3, 7, 4, -5]);
    final backend = _CaptureSolver();
    expect(session.solve(linearSolver: backend).status,
        GeometrySolveStatus.numericalFailure);
    expect(backend.captures, isEmpty);
    expect(session.committedValues, isNull);
  });

  test('default AD derivatives survive fork, cancellation and recovery', () {
    final session = GeometryModel(
      parameters: [
        GeometryParameterBlock(id: 'x', values: [0, 0, 0]),
        GeometryParameterBlock(
            id: 'target', values: [2, -1, 0.5], fixed: true),
      ],
      constraints: [
        GeometryResidualBlock.autoDiff(
          id: 'target',
          parameterIds: ['x', 'target'],
          residualCount: 3,
          evaluate: (p) => [
            p[0][0] - p[1][0],
            p[0][1] - p[1][1],
            p[0][2] - p[1][2],
          ],
        ),
      ],
    ).compile().createSession();
    final first = session.solve();
    expect(first.isSuccess, isTrue, reason: first.message);
    for (var i = 0; i < 3; i++) {
      expect(first.values['x']![i], closeTo([2, -1, 0.5][i], 1e-8));
    }
    final original = [...first.values['x']!];
    final fork = session.fork()..setParameterValues('target', [1, 2, 3]);
    expect(fork.solve(shouldCancel: () => true).status,
        GeometrySolveStatus.cancelled);
    expect(fork.committedValues!['x'], original);
    final recovered = fork.solve();
    expect(recovered.isSuccess, isTrue, reason: recovered.message);
    for (var i = 0; i < 3; i++) {
      expect(recovered.values['x']![i], closeTo(i + 1, 1e-8));
    }
    expect(session.committedValues!['x'], original);
    expect(first.values['x'], original);
  });
}

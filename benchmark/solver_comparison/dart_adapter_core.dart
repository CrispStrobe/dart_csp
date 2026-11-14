/// IO-free benchmark adapters over the unchanged production geometry solver.
/// The two-dimensional representations are benchmark prototypes, not new APIs.
library;

import 'dart:math' as math;

import 'package:dart_csp/geometry.dart';

typedef JsonObject = Map<String, Object?>;

const dartComparisonEngines = {
  'dart_3d_ad',
  'dart_2d_ad',
  'dart_2d_analytic',
};

enum ComparisonConstraintKind { distance, horizontal, vertical, coincident }

final class ComparisonConstraint {
  const ComparisonConstraint(this.kind, this.a, this.b, this.value);

  final ComparisonConstraintKind kind;
  final int a;
  final int b;
  final double? value;
}

final class ComparisonFixture {
  ComparisonFixture({
    required this.id,
    required this.points,
    required this.fixed,
    required this.constraints,
    required this.orientations,
  });

  final String id;
  final List<List<double>> points;
  final Set<int> fixed;
  final List<ComparisonConstraint> constraints;
  final List<(int, int, int, double)> orientations;
}

final class ComparisonRequest {
  ComparisonRequest({
    required this.engine,
    required this.mode,
    required this.warmups,
    required this.samples,
    required this.tolerance,
    required this.fixture,
    required this.edits,
  });

  factory ComparisonRequest.fromJson(JsonObject json) {
    if (json['schema_version'] != 1) {
      throw ArgumentError('Only schema_version=1 is supported.');
    }
    final engine = json['engine'];
    final mode = json['mode'];
    if (engine is! String || !dartComparisonEngines.contains(engine)) {
      throw ArgumentError('Unknown Dart comparison engine: $engine.');
    }
    if (mode is! String || (mode != 'cold' && mode != 'warm')) {
      throw ArgumentError('mode must be cold or warm.');
    }
    final warmups = _integer(json['warmups'], 'warmups');
    final samples = _integer(json['samples'], 'samples');
    final tolerance = _number(json['tolerance'], 'tolerance');
    if (warmups < 0 || samples < 0 || tolerance <= 0) {
      throw ArgumentError('Counts must be nonnegative and tolerance positive.');
    }
    final f = _object(json['fixture'], 'fixture');
    final id = f['id'];
    if (id is! String) throw ArgumentError('fixture.id must be a string.');
    final points = <List<double>>[];
    for (final value in _list(f['points'], 'points')) {
      final point = _list(value, 'point');
      if (point.length != 2) throw ArgumentError('Points must have x and y.');
      points.add([
        _number(point[0], 'point.x'),
        _number(point[1], 'point.y'),
      ]);
    }
    if (points.isEmpty) throw ArgumentError('points must be nonempty.');
    int pointIndex(Object? value) {
      final index = _integer(value, 'point index');
      if (index < 0 || index >= points.length) {
        throw ArgumentError('Point index out of range.');
      }
      return index;
    }

    final fixed = <int>{};
    for (final value in _list(f['fixed'], 'fixed')) {
      if (!fixed.add(pointIndex(value))) {
        throw ArgumentError('Fixed point indices must be distinct.');
      }
    }
    final constraints = <ComparisonConstraint>[];
    for (final value in _list(f['constraints'], 'constraints')) {
      final c = _object(value, 'constraint');
      final kindName = c['kind'];
      if (kindName is! String) throw ArgumentError('Missing constraint kind.');
      final kind = ComparisonConstraintKind.values.byName(kindName);
      final a = pointIndex(c['a']);
      final b = pointIndex(c['b']);
      if (a == b) throw ArgumentError('Constraint endpoints must be distinct.');
      final target = c['value'] == null ? null : _number(c['value'], 'value');
      if (kind == ComparisonConstraintKind.distance &&
          (target == null || target < 0)) {
        throw ArgumentError('Distances need a nonnegative value.');
      }
      constraints.add(ComparisonConstraint(kind, a, b, target));
    }
    final orientations = <(int, int, int, double)>[];
    for (final value
        in _list(f['orientations'] ?? <Object?>[], 'orientations')) {
      final orientation = _list(value, 'orientation');
      if (orientation.length != 4) {
        throw ArgumentError('Orientations require three indices and a sign.');
      }
      final sign = _number(orientation[3], 'orientation sign');
      if (sign == 0) throw ArgumentError('Orientation signs must be nonzero.');
      orientations.add((
        pointIndex(orientation[0]),
        pointIndex(orientation[1]),
        pointIndex(orientation[2]),
        sign
      ));
    }
    final edits = <List<double>>[];
    for (final value in _list(json['edits'], 'edits')) {
      final edit = _object(value, 'edit');
      final targets = [
        for (final v in _list(edit['values'], 'edit.values'))
          _number(v, 'edit target'),
      ];
      if (targets.length != constraints.length) {
        throw ArgumentError('Each edit requires one value per constraint.');
      }
      for (var i = 0; i < constraints.length; i++) {
        if (constraints[i].kind == ComparisonConstraintKind.distance &&
            targets[i] < 0) {
          throw ArgumentError('Edited distances must be nonnegative.');
        }
      }
      edits.add(targets);
    }
    if (edits.isEmpty) throw ArgumentError('At least one edit is required.');
    return ComparisonRequest(
      engine: engine,
      mode: mode,
      warmups: warmups,
      samples: samples,
      tolerance: tolerance,
      fixture: ComparisonFixture(
          id: id,
          points: points,
          fixed: fixed,
          constraints: constraints,
          orientations: orientations),
      edits: edits,
    );
  }

  final String engine;
  final String mode;
  final int warmups;
  final int samples;
  final double tolerance;
  final ComparisonFixture fixture;
  final List<List<double>> edits;
}

JsonObject _object(Object? value, String name) {
  if (value is! JsonObject) throw ArgumentError('$name must be an object.');
  return value;
}

List<Object?> _list(Object? value, String name) {
  if (value is! List<Object?>) throw ArgumentError('$name must be an array.');
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) throw ArgumentError('$name must be an integer.');
  return value;
}

double _number(Object? value, String name) {
  if (value is! num || !value.isFinite) {
    throw ArgumentError('$name must be a finite number.');
  }
  return value.toDouble();
}

/// Public for derivative-oracle tests and reuse in alternate benchmark hosts.
GeometryResidualBlock planarComparisonResidual({
  required int index,
  required ComparisonConstraint constraint,
  required double tolerance,
  required bool analytic,
}) {
  final kind = constraint.kind;
  final parameters = [
    'p${constraint.a}',
    'p${constraint.b}',
    if (kind == ComparisonConstraintKind.distance) 'd$index',
  ];
  final count = kind == ComparisonConstraintKind.coincident ? 2 : 1;
  final rowTolerance = count == 2 ? tolerance / math.sqrt(2) : tolerance;
  if (!analytic) {
    return GeometryResidualBlock.autoDiff(
      id: 'c$index',
      parameterIds: parameters,
      residualCount: count,
      tolerance: rowTolerance,
      evaluate: (p) {
        final dx = p[1][0] - p[0][0];
        final dy = p[1][1] - p[0][1];
        return switch (kind) {
          ComparisonConstraintKind.distance => [
              Dual.norm([dx, dy]) - p[2][0]
            ],
          ComparisonConstraintKind.horizontal => [dy],
          ComparisonConstraintKind.vertical => [dx],
          ComparisonConstraintKind.coincident => [dx, dy],
        };
      },
    );
  }
  return GeometryResidualBlock(
    id: 'c$index',
    parameterIds: parameters,
    residualCount: count,
    tolerance: rowTolerance,
    evaluate: (p, residual, jacobians) {
      final dx = p[1][0] - p[0][0];
      final dy = p[1][1] - p[0][1];
      if (jacobians != null) {
        for (final block in jacobians) {
          block.fillRange(0, block.length, 0);
        }
      }
      switch (kind) {
        case ComparisonConstraintKind.distance:
          final length = geometryNorm([dx, dy]);
          residual[0] = length - p[2][0];
          if (jacobians != null) {
            // Match Dual.norm's zero subgradient at coincident endpoints.
            final ux = length == 0 ? 0.0 : dx / length;
            final uy = length == 0 ? 0.0 : dy / length;
            jacobians[0][0] = -ux;
            jacobians[0][1] = -uy;
            jacobians[1][0] = ux;
            jacobians[1][1] = uy;
            // Analytic callbacks retain their full ambient block contract,
            // even when the dimension is fixed during the compiled solve.
            jacobians[2][0] = -1;
          }
        case ComparisonConstraintKind.horizontal:
          residual[0] = dy;
          if (jacobians != null) {
            jacobians[0][1] = -1;
            jacobians[1][1] = 1;
          }
        case ComparisonConstraintKind.vertical:
          residual[0] = dx;
          if (jacobians != null) {
            jacobians[0][0] = -1;
            jacobians[1][0] = 1;
          }
        case ComparisonConstraintKind.coincident:
          residual[0] = dx;
          residual[1] = dy;
          if (jacobians != null) {
            jacobians[0][0] = -1;
            jacobians[0][3] = -1;
            jacobians[1][0] = 1;
            jacobians[1][3] = 1;
          }
      }
    },
  );
}

CompiledGeometryModel _build(ComparisonRequest request, List<double> targets) {
  final fixture = request.fixture;
  if (request.engine == 'dart_3d_ad') {
    final builder = GeometryBuilder(lengthTolerance: request.tolerance);
    final plane = GeometryWorkplane(origin: Vec3.zero, normal: Vec3.unitZ);
    final points = [
      for (var i = 0; i < fixture.points.length; i++)
        builder.workplanePoint(
            'p$i', plane, fixture.points[i][0], fixture.points[i][1],
            fixed: fixture.fixed.contains(i)),
    ];
    for (var i = 0; i < fixture.constraints.length; i++) {
      final constraint = fixture.constraints[i];
      final a = points[constraint.a], b = points[constraint.b];
      switch (constraint.kind) {
        case ComparisonConstraintKind.distance:
          final dimension = builder.dimension('d$i', targets[i], lower: 0);
          builder.distance('c$i', a, b, dimension);
        case ComparisonConstraintKind.horizontal:
          builder.pointOnPlane('c$i', b, GeometryPlane(a, Vec3.unitY));
        case ComparisonConstraintKind.vertical:
          builder.pointOnPlane('c$i', b, GeometryPlane(a, Vec3.unitX));
        case ComparisonConstraintKind.coincident:
          builder.coincidence('c$i', a, b);
      }
    }
    return builder.compile();
  }
  return GeometryModel(
    parameters: [
      for (var i = 0; i < fixture.points.length; i++)
        GeometryParameterBlock(
            id: 'p$i',
            values: fixture.points[i],
            fixed: fixture.fixed.contains(i)),
      for (var i = 0; i < fixture.constraints.length; i++)
        if (fixture.constraints[i].kind == ComparisonConstraintKind.distance)
          GeometryParameterBlock(
              id: 'd$i',
              values: [targets[i]],
              fixed: true,
              lowerBounds: const [0]),
    ],
    constraints: [
      for (var i = 0; i < fixture.constraints.length; i++)
        planarComparisonResidual(
            index: i,
            constraint: fixture.constraints[i],
            tolerance: request.tolerance,
            analytic: request.engine == 'dart_2d_analytic'),
    ],
  ).compile();
}

final class PhysicalAcceptance {
  const PhysicalAcceptance(
      this.accepted, this.maxError, this.orientationMismatches);
  final bool accepted;
  final double? maxError;
  final int orientationMismatches;
}

/// Physical meanings are evaluated independently of the solver's residuals.
PhysicalAcceptance checkComparisonGeometry(ComparisonFixture fixture,
    List<double> targets, List<List<double>> points, double tolerance) {
  if (points.length != fixture.points.length ||
      points.any((p) => p.length != 2 || p.any((v) => !v.isFinite))) {
    return PhysicalAcceptance(false, null, fixture.orientations.length);
  }
  var maxError = 0.0;
  for (final index in fixture.fixed) {
    maxError = math.max(
        maxError,
        geometryNorm([
          points[index][0] - fixture.points[index][0],
          points[index][1] - fixture.points[index][1],
        ]));
  }
  for (var i = 0; i < fixture.constraints.length; i++) {
    final c = fixture.constraints[i];
    final dx = points[c.b][0] - points[c.a][0];
    final dy = points[c.b][1] - points[c.a][1];
    final error = switch (c.kind) {
      ComparisonConstraintKind.distance =>
        (geometryNorm([dx, dy]) - targets[i]).abs(),
      ComparisonConstraintKind.horizontal => dy.abs(),
      ComparisonConstraintKind.vertical => dx.abs(),
      ComparisonConstraintKind.coincident => geometryNorm([dx, dy]),
    };
    if (!error.isFinite) {
      return PhysicalAcceptance(false, null, fixture.orientations.length);
    }
    maxError = math.max(maxError, error);
  }
  var mismatches = 0;
  for (final (a, b, c, sign) in fixture.orientations) {
    final bx = points[b][0] - points[a][0];
    final by = points[b][1] - points[a][1];
    final cx = points[c][0] - points[a][0];
    final cy = points[c][1] - points[a][1];
    final scale = [bx.abs(), by.abs(), cx.abs(), cy.abs()].reduce(math.max);
    final cross = scale == 0
        ? 0.0
        : (bx / scale) * (cy / scale) - (by / scale) * (cx / scale);
    if (!cross.isFinite || sign * cross <= 0) mismatches++;
  }
  return PhysicalAcceptance(
      maxError <= tolerance && mismatches == 0, maxError, mismatches);
}

final _clockFrequency = Stopwatch().frequency;
int _nanoseconds(int ticks) => ticks * 1000000000 ~/ _clockFrequency;
double? _finite(double value) => value.isFinite ? value : null;

/// One instance owns the persistent model/session for one complete edit trace.
final class DartComparisonRunner {
  DartComparisonRunner(this.request)
      : _acceptedSeed = [
          for (final p in request.fixture.points) [...p]
        ];

  final ComparisonRequest request;
  CompiledGeometryModel? _compiled;
  GeometrySolveSession? _session;
  List<List<double>> _acceptedSeed;
  bool _needsCoordinateReset = false;

  JsonObject metadata() => {
        'record': 'metadata',
        'schema_version': 1,
        'engine': request.engine,
        'adapter': 'dart_geometry_comparison/1',
        'production_solver': 'unchanged package:dart_csp/geometry.dart',
        'representation': request.engine == 'dart_3d_ad'
            ? 'stock GeometryBuilder workplanePoint with three coordinates and plane rows'
            : 'benchmark-only two-coordinate residual blocks; fixed dimension inputs',
        'derivatives':
            request.engine == 'dart_2d_analytic' ? 'analytic' : 'automatic',
        'lifecycle':
            'cold builds every operation; warm retains compiled model and session',
        'rejected_candidate':
            'next timed update restores last physically accepted coordinates',
        'acceptance':
            'physical tolerance and branch signs; numerical status recorded separately',
        'native_max_iterations': 100,
        'native_max_linear_iterations': 1000,
        'native_rank_parameter_limit': 96,
        'native_rank_entry_limit': 262144,
        'native_dense_parameter_limit': 64,
        'native_solver_options': {
          'initial_damping': 1e-3,
          'linear_tolerance': 1e-8,
          'gradient_tolerance': 1e-14,
          'step_tolerance': 1e-14,
          'rank_tolerance': 1e-10,
        },
        'physical_tolerance': request.tolerance,
        'timing':
            'monotonic Stopwatch; build/update through coordinate extraction; excludes JSON and shared acceptance',
      };

  JsonObject step(int index) {
    final targets =
        request.edits[(index + request.warmups) % request.edits.length];
    final warm = request.mode == 'warm';
    final threeDimensional = request.engine == 'dart_3d_ad';
    final modelReused = warm && _compiled != null;
    final coordinateReset = warm && _needsCoordinateReset;
    final watch = Stopwatch()..start();
    var buildTicks = 0, solveTicks = 0;
    GeometrySolveResult? result;
    String? error;
    var coordinates = <List<double>>[];
    var maxZ = 0.0;
    try {
      if (!modelReused) {
        _compiled = _build(request, targets);
        _session = _compiled!.createSession();
      } else {
        if (coordinateReset) {
          for (var i = 0; i < _acceptedSeed.length; i++) {
            _session!.setParameterValues('p$i', [
              ..._acceptedSeed[i],
              if (threeDimensional) 0.0,
            ]);
          }
        }
        for (var i = 0; i < request.fixture.constraints.length; i++) {
          if (request.fixture.constraints[i].kind ==
              ComparisonConstraintKind.distance) {
            _session!.setParameterValues('d$i', [targets[i]]);
          }
        }
      }
      buildTicks = watch.elapsedTicks;
      result = _session!.solve();
      solveTicks = watch.elapsedTicks - buildTicks;
      coordinates = [
        for (var i = 0; i < request.fixture.points.length; i++)
          [result.values['p$i']![0], result.values['p$i']![1]],
      ];
      if (threeDimensional) {
        for (var i = 0; i < request.fixture.points.length; i++) {
          maxZ = math.max(maxZ, result.values['p$i']![2].abs());
        }
      }
    } catch (exception) {
      error = '$exception';
      if (buildTicks == 0) {
        buildTicks = watch.elapsedTicks;
      } else {
        solveTicks = watch.elapsedTicks - buildTicks;
      }
      coordinates = [
        for (final p in warm ? _acceptedSeed : request.fixture.points) [...p],
      ];
    }
    watch.stop();
    final physical = checkComparisonGeometry(
        request.fixture, targets, coordinates, request.tolerance);
    final accepted = error == null &&
        physical.accepted &&
        maxZ.isFinite &&
        maxZ <= request.tolerance;
    if (warm) {
      if (accepted) {
        _acceptedSeed = [
          for (final p in coordinates) [...p]
        ];
        // A conservative native status can pass the independent oracle without
        // committing internally. Honor the common accepted seed in that case.
        _needsCoordinateReset = !(result?.isSuccess ?? false);
      } else {
        _needsCoordinateReset = true;
      }
    }
    final compiled = _compiled;
    final stats = result?.stats;
    return {
      'schema_version': 1,
      'engine': request.engine,
      'mode': request.mode,
      'fixture_id': request.fixture.id,
      'index': index,
      'warmup': index < 0,
      'build_ns': _nanoseconds(buildTicks),
      'solve_ns': _nanoseconds(solveTicks),
      'elapsed_ns': _nanoseconds(watch.elapsedTicks),
      'coordinates': [
        for (final p in coordinates) [for (final v in p) _finite(v)]
      ],
      'reported_success': result?.isSuccess ?? false,
      'status': result?.status.name ?? 'adapter_error',
      'adapter_error': error,
      'accepted': accepted,
      'iterations': stats?.nonlinearIterations,
      'model_reused': modelReused,
      'session_reused': modelReused,
      'coordinate_seed_reset': coordinateReset,
      'active_coordinates': compiled?.activeTangentDimension ?? 0,
      'equations':
          compiled?.constraints.fold<int>(0, (n, c) => n + c.residualCount) ??
              0,
      'geometric_free_coordinates':
          2 * (request.fixture.points.length - request.fixture.fixed.length),
      'parameter_blocks': compiled?.parameters.length,
      'components': compiled?.componentCount,
      'jacobian_nonzeros': compiled?.jacobianNonzeros,
      'components_solved': stats?.componentsSolved,
      'components_reused': stats?.componentsReused,
      'residual_evaluations': stats?.residualEvaluations,
      'jacobian_evaluations': stats?.jacobianEvaluations,
      'auto_diff_derivative_coordinates': stats?.autoDiffDerivativeCoordinates,
      'linear_solves': stats?.linearSolves,
      'linear_iterations': stats?.linearIterations,
      'rank_factorizations': stats?.rankFactorizations,
      'rank_reuses': stats?.rankReuses,
      'local_degrees_of_freedom': result?.localDegreesOfFreedom,
      'engine_max_tolerance_ratio':
          result == null ? null : _finite(result.maxToleranceRatio),
      'physical_max_error': physical.maxError,
      'orientation_mismatches': physical.orientationMismatches,
      'max_z': threeDimensional ? _finite(maxZ) : null,
    };
  }
}

/// Shared native/browser entry point. Validation and JSON encoding are untimed.
Iterable<JsonObject> evaluateDartComparisonRequest(JsonObject json) sync* {
  final request = ComparisonRequest.fromJson(json);
  final runner = DartComparisonRunner(request);
  yield runner.metadata();
  for (var index = -request.warmups; index < request.samples; index++) {
    yield runner.step(index);
  }
}

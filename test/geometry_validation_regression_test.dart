import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

GeometrySolveResult fixedAngle(Vec3 a, Vec3 b, double radians,
    {Vec3? normal, double tolerance = 1e-10}) {
  final builder = GeometryBuilder(angleTolerance: tolerance);
  final origin = builder.point3('origin', Vec3.zero, fixed: true);
  final first = builder.point3('first', a, fixed: true);
  final second = builder.point3('second', b, fixed: true);
  final target = builder.dimension('angle', radians);
  builder.angle('angle relation', GeometryLine(origin, first),
      GeometryLine(origin, second), target,
      normal: normal);
  return builder.compile().createSession().solve();
}

void main() {
  group('scale-safe vector arithmetic', () {
    test('Vec3 and dual norms preserve tiny and huge finite lengths', () {
      for (final scale in [1e-300, 1e-200, 1.0, 1e200, 1e300]) {
        final vector = Vec3(3 * scale, 4 * scale, 0);
        expect(vector.length / scale, closeTo(5, 1e-14));
        final norm = Dual.norm([
          Dual.variable(vector.x, 0, 2),
          Dual.variable(vector.y, 1, 2),
          Dual.constant(0, 2),
        ]);
        expect(norm.value / scale, closeTo(5, 1e-14));
        expect(norm.derivatives[0], closeTo(0.6, 1e-14));
        expect(norm.derivatives[1], closeTo(0.8, 1e-14));
      }
      expect(const Vec3(1e-320, 0, 0).length, 1e-320);
      expect(Dual.norm([Dual.constant(1e-320)]).value, 1e-320);
      final zero = Dual.norm([Dual.variable(0, 0, 1)]);
      expect(zero.value, 0);
      expect(zero.derivatives, [0]);
    });

    test('normalization uses finite analytic tangent derivatives', () {
      for (final scale in [1e-300, 1e-200, 1.0, 1e200, 1e300]) {
        final direction = Dual.normalized([
          Dual.variable(3 * scale, 0, 2),
          Dual.variable(4 * scale, 1, 2),
        ]);
        expect(direction[0].value, closeTo(0.6, 1e-14));
        expect(direction[1].value, closeTo(0.8, 1e-14));
        expect(direction[0].derivatives[0] * scale, closeTo(0.128, 1e-14));
        expect(direction[0].derivatives[1] * scale, closeTo(-0.096, 1e-14));
        expect(direction[1].derivatives[0] * scale, closeTo(-0.096, 1e-14));
        expect(direction[1].derivatives[1] * scale, closeTo(0.072, 1e-14));
      }
      // The length itself overflows, but the direction remains well-defined.
      final huge = Dual.normalized([
        Dual.constant(1.7e308),
        Dual.constant(1.7e308),
        Dual.constant(1.7e308),
      ]);
      for (final coordinate in huge) {
        expect(coordinate.value, closeTo(1 / math.sqrt(3), 1e-15));
      }
      expect(Dual.normalized([Dual.constant(1e-320)]).single.value, 1);
      expect(() => Dual.normalized([Dual.constant(0)]), throwsStateError);
    });

    test('atan2 value and derivatives survive extreme coordinate scales', () {
      for (final scale in [1e-300, 1e-200, 1.0, 1e200, 1e308]) {
        final x = Dual.variable(scale, 0, 2);
        final y = Dual.variable(scale, 1, 2);
        final angle = y.atan2(x);
        expect(angle.value, closeTo(math.pi / 4, 1e-15));
        expect(angle.derivatives[0] * scale, closeTo(-0.5, 1e-14));
        expect(angle.derivatives[1] * scale, closeTo(0.5, 1e-14));
        // Correlated derivatives expose overflowing intermediate numerators.
        final movingY = Dual(scale, Float64List.fromList([scale]));
        final movingX = Dual(scale, Float64List.fromList([-scale]));
        expect(movingY.atan2(movingX).derivatives.single, closeTo(1, 1e-14));
      }
      expect(Dual.constant(1e-320).atan2(Dual.constant(1e-320)).value,
          closeTo(math.pi / 4, 1e-15));
      final tinyY =
          Dual(double.minPositive, Float64List.fromList([double.minPositive]));
      final tinyX =
          Dual(double.minPositive, Float64List.fromList([-double.minPositive]));
      expect(tinyY.atan2(tinyX).derivatives.single, 1);
      // A residual-only evaluation has no derivative entries to reveal NaN;
      // the origin must still be rejected explicitly.
      expect(() => Dual.constant(0).atan2(Dual.constant(0)), throwsStateError);
      expect(() => Dual.variable(0, 0, 1).atan2(Dual.constant(0, 1)),
          throwsStateError);
    });
  });

  group('physical length acceptance', () {
    test('a tiny nonzero fixed distance cannot satisfy a zero dimension', () {
      final builder = GeometryBuilder(lengthTolerance: 1e-220);
      final origin = builder.point3('origin', Vec3.zero, fixed: true);
      final point =
          builder.point3('point', const Vec3(1e-200, 0, 0), fixed: true);
      final target = builder.dimension('zero', 0);
      builder.distance('distance', origin, point, target);
      final result = builder.compile().createSession().solve();
      expect(result.isSuccess, isFalse);
      expect(result.constraintResiduals['distance']!.single, 1e-200);
    });

    test('correct fixed distances stay valid across representable scales', () {
      for (final scale in [1e-200, 1.0, 1e300]) {
        final builder = GeometryBuilder(lengthTolerance: scale * 1e-12);
        final origin = builder.point3('origin', Vec3.zero, fixed: true);
        final point =
            builder.point3('point', Vec3(3 * scale, 4 * scale, 0), fixed: true);
        final target = builder.dimension('target', 5 * scale);
        builder.distance('distance', origin, point, target);
        final result = builder.compile().createSession().solve();
        expect(result.isSuccess, isTrue, reason: '$scale: ${result.message}');
        expect(result.constraintResiduals['distance']!.single.abs(),
            lessThanOrEqualTo(scale * 1e-12));
      }
    });

    test('different tiny line lengths are not reported as equal', () {
      final builder = GeometryBuilder(lengthTolerance: 1e-220);
      final origin = builder.point3('origin', Vec3.zero, fixed: true);
      final a = builder.point3('a', const Vec3(1e-200, 0, 0), fixed: true);
      final b = builder.point3('b', const Vec3(0, 2e-200, 0), fixed: true);
      builder.equalLengths(
          'equal', GeometryLine(origin, a), GeometryLine(origin, b));
      final result = builder.compile().createSession().solve();
      expect(result.isSuccess, isFalse);
      expect(result.constraintResiduals['equal']!.single.abs(), 1e-200);
    });
  });

  group('signed planar angle contract', () {
    test('a tiny nonzero angle is distinguished from zero', () {
      for (final normal in [null, Vec3.unitZ]) {
        final mismatch = fixedAngle(Vec3.unitX, const Vec3(1, 1e-200, 0), 0,
            normal: normal, tolerance: 1e-220);
        expect(mismatch.isSuccess, isFalse);
        expect(mismatch.constraintResiduals['angle relation']!.first, 1e-200);
        expect(
            fixedAngle(Vec3.unitX, const Vec3(1, 1e-200, 0), 1e-200,
                    normal: normal, tolerance: 1e-220)
                .isSuccess,
            isTrue);
      }
    });

    test('fixed tilted lines cannot satisfy a signed planar angle', () {
      final result = fixedAngle(
          const Vec3(1, 0, 1), const Vec3(0, 1, 1), math.pi / 4,
          normal: Vec3.unitZ);
      expect(result.isSuccess, isFalse);
      final residuals = result.constraintResiduals['angle relation']!;
      expect(residuals, hasLength(3));
      expect(residuals[1], closeTo(1 / math.sqrt(2), 1e-15));
      expect(residuals[2], closeTo(1 / math.sqrt(2), 1e-15));
      // These directions have unsigned 3D angle pi/3, not pi/4.
      expect(
          fixedAngle(const Vec3(1, 0, 1), const Vec3(0, 1, 1), math.pi / 3)
              .isSuccess,
          isTrue);
    });

    test(
        'coplanar orientation covers zero, acute, opposite and negative angles',
        () {
      for (final radians in [0.0, 1e-12, math.pi / 4, math.pi, -math.pi / 2]) {
        for (final scale in [1e-200, 1.0, 1e200]) {
          final result = fixedAngle(
              Vec3(scale, 0, 0),
              Vec3(scale * math.cos(radians), scale * math.sin(radians), 0),
              radians,
              normal: const Vec3(0, 0, 1e300));
          expect(result.isSuccess, isTrue,
              reason: 'angle=$radians scale=$scale: ${result.message}');
        }
      }
      expect(
          fixedAngle(Vec3.unitX, Vec3.unitY, -math.pi / 2,
                  normal: const Vec3(0, 0, -1e-300))
              .isSuccess,
          isTrue);
      expect(
          fixedAngle(const Vec3(1e-320, 0, 0), const Vec3(0, 1e-320, 0),
                  math.pi / 2,
                  normal: Vec3.unitZ)
              .isSuccess,
          isTrue);
      expect(
          fixedAngle(const Vec3(1.7e308, 1.7e308, 0),
                  const Vec3(-1.7e308, 1.7e308, 0), math.pi / 2,
                  normal: Vec3.unitZ)
              .isSuccess,
          isTrue);
    });

    test('a direction parallel to the normal has no valid signed angle', () {
      final result = fixedAngle(Vec3.unitZ, Vec3.unitX, 0, normal: Vec3.unitZ);
      expect(result.status, GeometrySolveStatus.numericalFailure);
      expect(result.message, contains('atan2'));
      expect(fixedAngle(Vec3.zero, Vec3.unitX, 0, normal: Vec3.unitZ).status,
          GeometrySolveStatus.numericalFailure);
    });

    test('adjustable tilted directions solve angle and coplanarity together',
        () {
      final builder = GeometryBuilder();
      final origin = builder.point3('origin', Vec3.zero, fixed: true);
      final a = builder.point3('a', const Vec3(1, 0, 1));
      final b = builder.point3('b', const Vec3(0, 1, 1));
      final target = builder.dimension('angle', math.pi / 4);
      final length = builder.dimension('length', 1);
      builder.distance('a length', origin, a, length);
      builder.distance('b length', origin, b, length);
      builder.angle('angle relation', GeometryLine(origin, a),
          GeometryLine(origin, b), target,
          normal: Vec3.unitZ);
      final result = builder.compile().createSession().solve();
      expect(result.isSuccess, isTrue,
          reason: '${result.status}: ${result.message}');
      final av = result.values[a.id]!, bv = result.values[b.id]!;
      final al = math.sqrt(av[0] * av[0] + av[1] * av[1] + av[2] * av[2]);
      final bl = math.sqrt(bv[0] * bv[0] + bv[1] * bv[1] + bv[2] * bv[2]);
      expect(al, closeTo(1, builder.lengthTolerance));
      expect(bl, closeTo(1, builder.lengthTolerance));
      expect((av[2] / al).abs(), lessThanOrEqualTo(builder.angleTolerance));
      expect((bv[2] / bl).abs(), lessThanOrEqualTo(builder.angleTolerance));
      final measured = math.atan2(
          av[0] * bv[1] - av[1] * bv[0], av[0] * bv[0] + av[1] * bv[1]);
      expect(measured, closeTo(math.pi / 4, builder.angleTolerance));
    });

    test('an invalid signed-angle edit preserves the last valid parameters',
        () {
      final builder = GeometryBuilder();
      final origin = builder.point3('origin', Vec3.zero, fixed: true);
      final a = builder.point3('a', Vec3.unitX, fixed: true);
      final b = builder.point3('b', Vec3.unitY, fixed: true);
      final target = builder.dimension('angle', math.pi / 2);
      builder.angle('angle relation', GeometryLine(origin, a),
          GeometryLine(origin, b), target,
          normal: Vec3.unitZ);
      final session = builder.compile().createSession();
      expect(session.solve().isSuccess, isTrue);
      final before = session.committedValues;
      session.setParameterValues(a.id, [0, 0, 1]);
      expect(session.solve().status, GeometrySolveStatus.numericalFailure);
      expect(session.committedValues, before);
      expect(session.parameterValues(a.id), [1, 0, 0]);
      session.setParameterValues(a.id, [1, 0, 1]);
      expect(session.solve().isSuccess, isFalse);
      expect(session.committedValues, before);
      expect(session.parameterValues(a.id), [1, 0, 0]);
    });
  });

  test('invalid pose construction leaves the builder unchanged and retryable',
      () {
    for (final quaternion in <List<double>>[
      [0, 0, 0, 0],
      [1, 0, 0],
      [1, double.nan, 0, 0],
      [2, 0, 0, 0],
    ]) {
      final builder = GeometryBuilder()..point3('existing', Vec3.zero);
      expect(() => builder.pose('pose', quaternion: quaternion),
          throwsArgumentError);
      expect(builder.build().parameters.map((p) => p.id), ['existing']);
      builder.pose('pose');
      expect(builder.build().parameters.map((p) => p.id),
          ['existing', 'pose.translation', 'pose.rotation']);
    }
    final builder = GeometryBuilder();
    expect(
        () => builder.pose('pose',
            translation: const Vec3(double.infinity, 0, 0)),
        throwsArgumentError);
    expect(builder.build().parameters, isEmpty);
    builder.pose('pose');
    expect(builder.build().parameters, hasLength(2));
  });
}

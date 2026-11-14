import 'dart:math' as math;

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

// The historical implementation validated and computed area before reading
// these three radii for its two circles and cylinder. Its later construction
// snapshot then saw radius one again and accepted the inconsistent boundary.
class _ChangingHole extends CadCircularHole {
  _ChangingHole() : super(id: 'mount', centerX: 0, centerY: 0, radius: 1);

  var radiusReads = 0;

  @override
  double get radius {
    radiusReads++;
    return radiusReads >= 7 && radiusReads <= 9 ? 100 : 1;
  }
}

class _ChangingProfile extends CadRectangularProfile {
  _ChangingProfile()
      : super(width: 20, height: 10, holes: const [
          CadCircularHole(id: 'mount', centerX: 0, centerY: 0, radius: 1),
        ]);

  var widthReads = 0, heightReads = 0, holesReads = 0;

  @override
  double get width => ++widthReads == 1 ? 20 : -1;

  @override
  double get height => ++heightReads == 1 ? 10 : -1;

  @override
  List<CadCircularHole> get holes {
    holesReads++;
    return holesReads == 1
        ? super.holes
        : const [
            CadCircularHole(id: 'invalid', centerX: 0, centerY: 0, radius: 100)
          ];
  }
}

class _UnavailableHolesProfile extends CadRectangularProfile {
  _UnavailableHolesProfile({required super.width, required super.height});

  @override
  List<CadCircularHole> get holes => throw StateError('Holes unavailable.');
}

void _checkUnitHole(CadBody body) {
  expect(body.volume, closeTo((200 - math.pi) * 2, 1e-12));
  final circles =
      body.edges.map((edge) => edge.curve).whereType<CadCircleCurve>().toList();
  expect(circles, hasLength(2));
  for (final circle in circles) {
    expect(circle.radius, 1);
    expect(circle.center.x, 0);
    expect(circle.center.y, 0);
  }
  final cylinder = body.faces
      .map((face) => face.surface)
      .whereType<CadCylinderSurface>()
      .single;
  expect(cylinder.radius, 1);
  expect(cylinder.inward, isTrue);
  const kernel = ReferenceCadKernel();
  expect(kernel.validate(body), isEmpty);
  expect(kernel.tessellate(body).isSuccess, isTrue);
}

void main() {
  test('extrusion captures hole fields before validating or building geometry',
      () {
    final hole = _ChangingHole();
    final result = const ReferenceCadKernel().extrude(
      featureId: 'plate',
      profile: CadRectangularProfile(width: 20, height: 10, holes: [hole]),
      depth: 2,
    );
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    _checkUnitHole(result.value!);
    expect(hole.radiusReads, 1);
  });

  test('extrusion uses one owned snapshot of public profile getters', () {
    final profile = _ChangingProfile();
    final result = const ReferenceCadKernel().extrude(
      featureId: 'plate',
      profile: profile,
      depth: 2,
    );
    expect(result.isSuccess, isTrue, reason: '${result.issues}');
    _checkUnitHole(result.value!);
    expect(profile.widthReads, 1);
    expect(profile.heightReads, 1);
    expect(profile.holesReads, 1);
  });

  test('invalid dimensions reject before reading an unavailable holes getter',
      () {
    for (final (width, height, depth) in [
      (-1.0, 10.0, 2.0),
      (20.0, 0.0, 2.0),
      (20.0, 10.0, double.nan),
    ]) {
      final result = const ReferenceCadKernel().extrude(
          featureId: 'plate',
          profile: _UnavailableHolesProfile(width: width, height: height),
          depth: depth);
      expect(result.status, CadKernelStatus.invalidInput);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, 'invalid_dimensions');
    }
  });
}

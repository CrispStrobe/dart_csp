import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  test('range cardinality and endpoints remain consecutive on each runtime',
      () {
    var boundary = 1;
    for (var power = 0; power < 53; power++) {
      boundary *= 2;
    }
    expect(IntRangeDomain(boundary, boundary).toList(), [boundary]);
    if (boundary + 1 == boundary) {
      expect(() => IntRangeDomain(0, boundary), throwsArgumentError);
      expect(() => IntRangeDomain(boundary, boundary + 2), throwsArgumentError);
      expect(
          () => IntRangeDomain(-boundary - 2, -boundary), throwsArgumentError);
    } else {
      expect(IntRangeDomain(boundary, boundary + 2).toList(),
          [boundary, boundary + 1, boundary + 2]);
    }
  });

  test('native endpoint filters neither wrap nor lose a value', () async {
    var boundary = 1;
    for (var power = 0; power < 53; power++) {
      boundary *= 2;
    }
    if (boundary + 1 == boundary) {
      return; // The JS runtime has different limits.
    }
    var half = boundary;
    for (var power = 53; power < 62; power++) {
      half *= 2;
    }
    final largest = half + (half - 1);
    final smallest = -largest - 1;
    expect(() => IntRangeDomain(0, largest), throwsArgumentError);
    for (final bounds in [
      (largest - 2, largest, largest - 10),
      (smallest, smallest + 2, smallest + 10)
    ]) {
      final problem = Problem()
        ..addRangeVariable('x', bounds.$1, bounds.$2)
        ..addVariable('y', [bounds.$1 + 1])
        ..addVariable('z', [bounds.$3])
        ..addAllDifferent(['x', 'y', 'z']);
      final solutions = await problem.getAllSolutions();
      expect(solutions.map((solution) => solution['x']).toSet(),
          {bounds.$1, bounds.$2});
    }
  });

  test('billion-value ranges remain compact through model copying', () {
    final p = Problem()..addRangeVariable('x', -500000000, 500000000);
    final domain = p.variables['x']!;
    expect(domain, isA<IntRangeDomain>());
    expect(domain.length, 1000000001);
    expect(domain.first, -500000000);
    expect(domain.last, 500000000);
    expect(domain[500000000], 0);
    expect(identical(p.copy().variables['x'], domain), isTrue);
  });

  test('compact domains preserve numeric list membership and indexed order',
      () {
    final domain = IntRangeDomain(-2, 3);
    expect(domain.toList(), [-2, -1, 0, 1, 2, 3]);
    expect(domain.contains(1.0), isTrue);
    expect(domain.contains(1.5), isFalse);
    expect(domain.contains(double.nan), isFalse);
    expect(domain.contains(double.infinity), isFalse);
    expect(domain.indexOf(0), 2);
    expect(domain.indexOf(0, 3), -1);
    expect(domain.lastIndexOf(0, 1), -1);
    expect(() => domain[6], throwsRangeError);
    expect(() => domain[-1], throwsRangeError);
    expect(() => domain[0] = 4, throwsUnsupportedError);
    expect(() => domain.length = 0, throwsUnsupportedError);
    expect(() => IntRangeDomain(3, 2), throwsArgumentError);
  });

  test('ordinary caller-owned domains still copy and retain value order', () {
    final values = [1, 3, 0, 2];
    final p = Problem()..addVariable('x', values);
    values[0] = 99;
    expect(p.variables['x'], [1, 3, 0, 2]);
    final copy = p.copy();
    copy.variables['x']![0] = 8;
    expect(p.variables['x'], [1, 3, 0, 2]);
  });
}

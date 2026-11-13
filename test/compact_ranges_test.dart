import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
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

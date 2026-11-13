import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('compact integer solving', () {
    test('a billion-value unconstrained domain has a lazy first branch',
        () async {
      final problem = Problem()..addRangeVariable('x', 0, 1000000000);
      expect(await problem.getSolution(), {'x': 0});
      expect(problem.lastStats!.decisions, 1);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('large positive-coefficient equality contracts without enumeration',
        () async {
      final problem = Problem()
        ..addRangeVariable('x', 0, 1000000000)
        ..addVariable('y', [1])
        ..addLinearEquals(['x', 'y'], [2, 3], 1999999999);
      expect(await problem.getSolution(), {'x': 999999998, 'y': 1});
      expect(problem.lastStats!.decisions, 0);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('negative coefficients contract the correct end of a large range',
        () async {
      final problem = Problem()
        ..addRangeVariable('x', 0, 1000000000)
        ..addLinearLeq(['x'], [-3], -2999999970)
        ..addLinearLeq(['x'], [1], 999999995);
      expect(await problem.getSolution(), {'x': 999999990});
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('mixed float-linear constraints use compact integer bounds', () async {
      final problem = Problem()
        ..addRangeVariable('x', 0, 1000000000)
        ..addFloatVariable('fraction', 0.5, 0.5)
        ..addLinearGeq(['x', 'fraction'], [1, 2], 999999999)
        ..addLinearLeq(['x'], [1], 999999999);
      final solution = await problem.getSolution();
      expect(solution, {'x': 999999998, 'fraction': 0.5});
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('large-range optimization does not scan the objective domain',
        () async {
      final problem = Problem()..addRangeVariable('x', -1000000000, 1000000000);
      expect(await problem.minimize('x'), {'x': -1000000000});
      expect(await problem.maximize('x'), {'x': 1000000000});
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('generic domain iteration retains caller order', () async {
      final problem = Problem()..addVariable('x', [3, 1, 2]);
      expect(await problem.getSolution(), {'x': 3});
      expect(await problem.getAllSolutions(), [
        {'x': 3},
        {'x': 1},
        {'x': 2},
      ]);
    });

    test('bitset bounds handle the sign bit and word boundaries', () async {
      for (final value in [-64, -1, 0, 63, 64]) {
        final problem = Problem()
          ..addRangeVariable('x', -64, 64)
          ..addLinearEquals(['x'], [1], value);
        expect(await problem.getSolution(), {'x': value});
      }
    });

    test('large-range LCG chooses a value without enumerating the range',
        () async {
      final problem = Problem()..addRangeVariable('x', 0, 1000000000);
      for (final iterative in [false, true]) {
        expect(
            await problem.solveWithLcg(useIterativeCdcl: iterative), {'x': 0});
        expect(CSP.lastImplicationTrail!.length, lessThan(10));
      }
    });

    test('range contractions match independent fractional arithmetic oracle',
        () async {
      final random = Random(452901);
      const coefficients = [-3, -0.1, 0.1, 0.5, 2];
      for (var sample = 0; sample < 90; sample++) {
        final center = random.nextInt(2001) - 1000;
        final low = center - 4;
        final high = center + 4;
        final coefficient = coefficients[sample % coefficients.length];
        final bound = coefficient * (center + random.nextDouble() - 0.5);
        final op = sample % 3;
        bool accepts(int value) => switch (op) {
              0 => coefficient * value == bound,
              1 => coefficient * value <= bound,
              _ => coefficient * value >= bound,
            };
        final expected = <int>{
          for (var value = low; value <= high; value++)
            if (accepts(value)) value,
        };
        final problem = Problem()
          ..addRangeVariable('x', -1500, 1500)
          ..addLinearGeq(['x'], [1], low)
          ..addLinearLeq(['x'], [1], high);
        switch (op) {
          case 0:
            problem.addLinearEquals(['x'], [coefficient], bound);
          case 1:
            problem.addLinearLeq(['x'], [coefficient], bound);
          default:
            problem.addLinearGeq(['x'], [coefficient], bound);
        }
        final actual = {
          for (final solution in await problem.getAllSolutions())
            solution['x'] as int,
        };
        expect(actual, expected,
            reason: 'sample=$sample coefficient=$coefficient bound=$bound');
      }
    });
  });
}

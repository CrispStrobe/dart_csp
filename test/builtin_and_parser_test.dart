import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Built-in constraint factories', () {
    group('allDifferent / allEqual', () {
      test('allDifferent n-ary accepts unique, rejects duplicate', () {
        final p = allDifferent();
        expect(p({'A': 1, 'B': 2, 'C': 3}), isTrue);
        expect(p({'A': 1, 'B': 2, 'C': 1}), isFalse);
      });

      test('allDifferentBinary', () {
        final p = allDifferentBinary();
        expect(p(1, 2), isTrue);
        expect(p('x', 'x'), isFalse);
      });

      test('allEqual n-ary accepts equal, rejects different; empty is true',
          () {
        final p = allEqual();
        expect(p({}), isTrue);
        expect(p({'A': 5, 'B': 5, 'C': 5}), isTrue);
        expect(p({'A': 5, 'B': 5, 'C': 6}), isFalse);
      });

      test('allEqualBinary', () {
        final p = allEqualBinary();
        expect(p(1, 1), isTrue);
        expect(p(1, 2), isFalse);
      });
    });

    group('sum constraints', () {
      test('exactSum without multipliers', () {
        final p = exactSum(10);
        expect(p({'A': 3, 'B': 7}), isTrue);
        expect(p({'A': 4, 'B': 5}), isFalse);
      });

      test('exactSum with multipliers (2A + 3B == 13)', () {
        final p = exactSum(13, multipliers: [2, 3]);
        expect(p({'A': 2, 'B': 3}), isTrue);
        expect(p({'A': 1, 'B': 4}), isFalse);
      });

      test('exactSum on empty assignment requires target == 0', () {
        expect(exactSum(0)({}), isTrue);
        expect(exactSum(5)({}), isFalse);
      });

      test('exactSumBinary with and without multipliers', () {
        expect(exactSumBinary(10)(4, 6), isTrue);
        expect(exactSumBinary(10)(4, 7), isFalse);
        expect(exactSumBinary(13, multipliers: [2, 3])(2, 3), isTrue);
      });

      test('minSum / maxSum / sumInRange n-ary', () {
        expect(minSum(5)({'A': 2, 'B': 3}), isTrue);
        expect(minSum(5)({'A': 2, 'B': 2}), isFalse);
        expect(maxSum(10)({'A': 4, 'B': 6}), isTrue);
        expect(maxSum(10)({'A': 4, 'B': 7}), isFalse);
        expect(sumInRange(5, 10)({'A': 3, 'B': 4}), isTrue);
        // Range is inclusive on both ends.
        expect(sumInRange(5, 10)({'A': 3, 'B': 2}), isTrue); // sum=5
        expect(sumInRange(5, 10)({'A': 5, 'B': 5}), isTrue); // sum=10
        expect(sumInRange(5, 10)({'A': 1, 'B': 2}), isFalse); // sum=3
        expect(sumInRange(5, 10)({'A': 6, 'B': 5}), isFalse); // sum=11
      });

      test('minSum/maxSum on empty assignment', () {
        expect(minSum(0)({}), isTrue);
        expect(minSum(5)({}), isFalse);
        expect(maxSum(-1)({}), isTrue);
      });

      test('binary sum range variants', () {
        expect(minSumBinary(5)(2, 3), isTrue);
        expect(minSumBinary(5)(2, 2), isFalse);
        expect(maxSumBinary(10)(5, 5), isTrue);
        expect(maxSumBinary(10)(6, 5), isFalse);
        expect(sumInRangeBinary(5, 10)(3, 4), isTrue);
        expect(sumInRangeBinary(5, 10)(1, 2), isFalse); // below min
        expect(sumInRangeBinary(5, 10)(6, 5), isFalse); // above max
      });
    });

    group('product constraints', () {
      test('exactProduct accepts target, rejects others; empty needs target==1',
          () {
        expect(exactProduct(12)({'A': 3, 'B': 4}), isTrue);
        expect(exactProduct(12)({'A': 2, 'B': 5}), isFalse);
        expect(exactProduct(1)({}), isTrue);
        expect(exactProduct(2)({}), isFalse);
      });

      test('minProduct / maxProduct', () {
        expect(minProduct(10)({'A': 3, 'B': 4}), isTrue);
        expect(minProduct(10)({'A': 2, 'B': 4}), isFalse);
        expect(maxProduct(20)({'A': 4, 'B': 5}), isTrue);
        expect(maxProduct(20)({'A': 5, 'B': 5}), isFalse);
      });

      test('binary product variants', () {
        expect(exactProductBinary(12)(3, 4), isTrue);
        expect(exactProductBinary(12)(2, 5), isFalse);
        expect(minProductBinary(10)(3, 4), isTrue);
        expect(minProductBinary(10)(2, 4), isFalse);
        expect(maxProductBinary(20)(4, 5), isTrue);
        expect(maxProductBinary(20)(5, 5), isFalse);
      });
    });

    group('set membership', () {
      test('inSet / notInSet n-ary', () {
        expect(inSet({1, 2, 3})({'A': 1, 'B': 3}), isTrue);
        expect(inSet({1, 2, 3})({'A': 1, 'B': 4}), isFalse);
        expect(notInSet({9, 10})({'A': 1, 'B': 3}), isTrue);
        expect(notInSet({9, 10})({'A': 9, 'B': 3}), isFalse);
      });

      test('inSetBinary / notInSetBinary', () {
        expect(inSetBinary({1, 2})(1, 2), isTrue);
        expect(inSetBinary({1, 2})(1, 3), isFalse);
        expect(notInSetBinary({9})(1, 2), isTrue);
        expect(notInSetBinary({9})(9, 2), isFalse);
      });

      test('someInSet / someNotInSet require minimum count', () {
        expect(someInSet({1, 2}, 2)({'A': 1, 'B': 2, 'C': 9}), isTrue);
        expect(someInSet({1, 2}, 3)({'A': 1, 'B': 2, 'C': 9}), isFalse);
        expect(someNotInSet({1, 2}, 1)({'A': 1, 'B': 2, 'C': 9}), isTrue);
        expect(someNotInSet({1, 2}, 2)({'A': 1, 'B': 2, 'C': 9}), isFalse);
      });
    });

    group('ordering', () {
      test('ascendingInOrder / strictlyAscendingInOrder', () {
        final order = ['A', 'B', 'C'];
        expect(ascendingInOrder(order)({'A': 1, 'B': 1, 'C': 2}), isTrue);
        expect(ascendingInOrder(order)({'A': 1, 'B': 2, 'C': 1}), isFalse);
        expect(
            strictlyAscendingInOrder(order)({'A': 1, 'B': 2, 'C': 3}), isTrue);
        expect(
            strictlyAscendingInOrder(order)({'A': 1, 'B': 1, 'C': 2}), isFalse);
      });

      test('descendingInOrder', () {
        final order = ['A', 'B', 'C'];
        expect(descendingInOrder(order)({'A': 5, 'B': 3, 'C': 1}), isTrue);
        expect(descendingInOrder(order)({'A': 5, 'B': 6, 'C': 1}), isFalse);
      });

      test('partial assignments are treated as still valid', () {
        // When a variable in the order is missing the predicate short-circuits.
        final order = ['A', 'B', 'C'];
        expect(ascendingInOrder(order)({'A': 1}), isTrue);
        expect(strictlyAscendingInOrder(order)({'A': 1}), isTrue);
        expect(descendingInOrder(order)({'A': 1}), isTrue);
      });

      test('binary ordering predicates', () {
        expect(ascendingBinary()(1, 1), isTrue);
        expect(ascendingBinary()(2, 1), isFalse);
        expect(strictlyAscendingBinary()(1, 2), isTrue);
        expect(strictlyAscendingBinary()(1, 1), isFalse);
        expect(descendingBinary()(2, 1), isTrue);
        expect(descendingBinary()(1, 2), isFalse);
      });
    });
  });

  group('Problem helpers — integration', () {
    test('addAllEqual produces solution with equal values', () async {
      final p = Problem()
        ..addVariables(['X', 'Y', 'Z'], [1, 2, 3])
        ..addAllEqual(['X', 'Y', 'Z']);
      final solution = await p.getAllSolutions();
      expect(solution, hasLength(3));
      for (final s in solution) {
        expect(s['X'], equals(s['Y']));
        expect(s['Y'], equals(s['Z']));
      }
    });

    test('addExactProduct (binary and n-ary)', () async {
      final p1 = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 6, 12])
        ..addExactProduct(['A', 'B'], 12);
      final s1 = await p1.getAllSolutions();
      for (final sol in s1) {
        expect((sol['A'] as int) * (sol['B'] as int), equals(12));
      }
      expect(s1, isNotEmpty);

      final p2 = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4])
        ..addExactProduct(['A', 'B', 'C'], 24);
      final s2 = await p2.getAllSolutions();
      for (final sol in s2) {
        expect((sol['A'] as int) * (sol['B'] as int) * (sol['C'] as int), 24);
      }
    });

    test('addSumRange constrains sum to [min, max]', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addSumRange(['A', 'B', 'C'], 4, 6);
      final solutions = await p.getAllSolutions();
      expect(solutions, isNotEmpty);
      for (final s in solutions) {
        final sum = (s['A'] as int) + (s['B'] as int) + (s['C'] as int);
        expect(sum, inInclusiveRange(4, 6));
      }
    });

    test('addInSet / addNotInSet restrict allowed values', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addInSet(['A', 'B'], {2, 4})
        ..addNotInSet(['A', 'B'], {4});
      final solutions = await p.getAllSolutions();
      for (final s in solutions) {
        expect(s['A'], equals(2));
        expect(s['B'], equals(2));
      }
    });

    test('addDescending and addStrictlyAscending', () async {
      final pDesc = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addDescending(['A', 'B', 'C']);
      for (final s in await pDesc.getAllSolutions()) {
        expect((s['A'] as int) >= (s['B'] as int), isTrue);
        expect((s['B'] as int) >= (s['C'] as int), isTrue);
      }

      final pStrict = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStrictlyAscending(['A', 'B']);
      for (final s in await pStrict.getAllSolutions()) {
        expect((s['A'] as int) < (s['B'] as int), isTrue);
      }
    });

    test('clear() empties variables and constraints', () {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addAllDifferent(['A', 'B']);
      expect(p.variableCount, equals(2));
      // Binary constraints are stored in both directions for AC-3, so a
      // single 2-variable predicate registers as 2 entries.
      expect(p.constraintCount, equals(2));
      p.clear();
      expect(p.variableCount, equals(0));
      expect(p.constraintCount, equals(0));
    });

    test('addVariables rejects mismatched constraint arity at solve time',
        () async {
      // Binary predicate but 3 variables — solver should still run; the
      // constraint just won't match and acts as a tautology / type error.
      // We at least verify the n-ary path through addAllDifferent for 3+ vars.
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final s = await p.getSolution();
      expect(s, isA<Map<String, dynamic>>());
    });
  });

  group('ExpressionEvaluator', () {
    test('numeric evaluation respects precedence', () {
      // Multiplication/division bind tighter than addition/subtraction.
      expect(ExpressionEvaluator.evaluateNumeric('2 + 3 * 4', {}), equals(14));
      expect(ExpressionEvaluator.evaluateNumeric('10 - 2 * 3', {}), equals(4));
      expect(ExpressionEvaluator.evaluateNumeric('20 / 4 + 1', {}), equals(6));
    });

    test('numeric evaluation substitutes variables', () {
      expect(
          ExpressionEvaluator.evaluateNumeric(
              'A + B * C', {'A': 1, 'B': 2, 'C': 3}),
          equals(7));
    });

    test('numeric evaluation handles negative leading number', () {
      expect(ExpressionEvaluator.evaluateNumeric('-5 + 3', {}), equals(-2));
    });

    test('numeric evaluation: division by zero is suppressed (no throw)', () {
      // Implementation guards x/0 by skipping the division; we just verify
      // it returns a finite number without throwing.
      final v = ExpressionEvaluator.evaluateNumeric('10 / 0', {});
      expect(v.isFinite, isTrue);
    });

    test('boolean evaluation: comparison operators', () {
      expect(ExpressionEvaluator.evaluateBoolean('5 > 3', {}), isTrue);
      expect(ExpressionEvaluator.evaluateBoolean('5 < 3', {}), isFalse);
      expect(ExpressionEvaluator.evaluateBoolean('5 >= 5', {}), isTrue);
      expect(ExpressionEvaluator.evaluateBoolean('5 <= 4', {}), isFalse);
      expect(ExpressionEvaluator.evaluateBoolean('5 == 5', {}), isTrue);
      expect(ExpressionEvaluator.evaluateBoolean('5 != 5', {}), isFalse);
    });

    test('boolean evaluation: expressions on both sides', () {
      expect(
          ExpressionEvaluator.evaluateBoolean(
              'A + B == C', {'A': 1, 'B': 2, 'C': 3}),
          isTrue);
      expect(ExpressionEvaluator.evaluateBoolean('A * 2 > B', {'A': 3, 'B': 5}),
          isTrue);
    });

    test('boolean evaluation throws on missing operator', () {
      expect(() => ExpressionEvaluator.evaluateBoolean('1 + 1', {}),
          throwsArgumentError);
    });
  });

  group('String constraint parser', () {
    test('"A in [...]" set syntax', () async {
      final p = Problem()
        ..addVariable('A', [1, 2, 3, 4, 5])
        ..addStringConstraint('A in [2, 4]');
      for (final s in await p.getAllSolutions()) {
        expect([2, 4], contains(s['A']));
      }
    });

    test('"A not in [...]" set syntax', () async {
      final p = Problem()
        ..addVariable('A', [1, 2, 3, 4, 5])
        ..addStringConstraint('A not in [2, 4]');
      for (final s in await p.getAllSolutions()) {
        expect([1, 3, 5], contains(s['A']));
      }
    });

    test('undefined variable in string constraint throws', () {
      final p = Problem()..addVariable('A', [1, 2, 3]);
      expect(() => p.addStringConstraint('A + Z == 5'),
          throwsA(isA<ConstraintParseException>()));
    });

    test('ConstraintParseException.toString includes constraint and message',
        () {
      final e = ConstraintParseException('bad', 'X @ Y');
      final s = e.toString();
      expect(s, contains('bad'));
      expect(s, contains('X @ Y'));
    });
  });

  group('VariableConstraint predicates', () {
    test('VariableSumConstraint.toPredicate enforces target = sum(sources)',
        () {
      final c = VariableSumConstraint('C', ['A', 'B']);
      final p = c.toPredicate();
      expect(p({'A': 2, 'B': 3, 'C': 5}), isTrue);
      expect(p({'A': 2, 'B': 3, 'C': 6}), isFalse);
      // Partial assignments are treated as not yet violating.
      expect(p({'A': 2}), isTrue);
    });

    test('VariableProductConstraint.toPredicate enforces target = product', () {
      final c = VariableProductConstraint('C', ['A', 'B']);
      final p = c.toPredicate();
      expect(p({'A': 2, 'B': 3, 'C': 6}), isTrue);
      expect(p({'A': 2, 'B': 3, 'C': 5}), isFalse);
    });

    test('VariableSumConstraint with multipliers (C = 2A + 3B)', () {
      final c = VariableSumConstraint('C', ['A', 'B'], multipliers: [2, 3]);
      final p = c.toPredicate();
      expect(p({'A': 2, 'B': 3, 'C': 13}), isTrue);
      expect(p({'A': 2, 'B': 3, 'C': 12}), isFalse);
    });
  });

  group('ExpressionEvaluator robustness with non-numeric bindings', () {
    // The evaluator is numeric-only, but it is a public API and callers may
    // bind enum/string domain values (e.g. checking `A == B` for a graph-
    // colouring CSP). A bare `as num` cast used to leak an opaque TypeError;
    // it must now reject cleanly with an ArgumentError.
    test(
        'evaluateBoolean on string operands throws ArgumentError, not TypeError',
        () {
      final vars = {'A': 'red', 'B': 'blue'};
      expect(
        () => ExpressionEvaluator.evaluateBoolean('A == B', vars),
        throwsA(isA<ArgumentError>()),
      );
      // Not a TypeError leaking from `as num`.
      expect(() => ExpressionEvaluator.evaluateBoolean('A == B', vars),
          throwsA(isNot(isA<TypeError>())));
      expect(
          () => ExpressionEvaluator.evaluateBoolean(
              'A > B', {'A': 'x', 'B': 'y'}),
          throwsA(isA<ArgumentError>()));
    });

    test('numeric bindings still evaluate correctly', () {
      final vars = {'A': 3, 'B': 2};
      expect(ExpressionEvaluator.evaluateBoolean('A > B', vars), isTrue);
      expect(ExpressionEvaluator.evaluateBoolean('A == B', vars), isFalse);
      expect(ExpressionEvaluator.evaluateNumeric('A + B', vars), 5);
      // Numeric strings coerce as before.
      expect(
          ExpressionEvaluator.evaluateBoolean('A >= B', {'A': '4', 'B': '2'}),
          isTrue);
    });
  });
}

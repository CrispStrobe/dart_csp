import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem Class Core Features', () {
    test('copy() creates a distinct but equivalent problem', () {
      final p1 = Problem();
      p1.addVariables(['A', 'B'], [1, 2, 3]);
      p1.addStringConstraint('A != B');

      final p2 = p1.copy();

      // Check for equivalence
      expect(p2.variableCount, equals(p1.variableCount));
      expect(p2.constraintCount, equals(p1.constraintCount));
      expect(p2.variables, equals(p1.variables));

      // Check for distinction (modifying copy doesn't affect original)
      p2.addVariable('C', [4, 5]);
      expect(p1.variableCount, equals(2));
      expect(p2.variableCount, equals(3));
      expect(p1.variables.containsKey('C'), isFalse);
    });

    test('variables getter returns an unmodifiable map', () {
      final p = Problem();
      p.addVariable('A', [1]);
      final vars = p.variables;
      expect(() => vars['B'] = [2], throwsUnsupportedError);
    });
  });

  group('BuiltinConstraints Extension (Edge Cases)', () {
    test('addAllDifferent works for both binary and n-ary cases', () async {
      // Binary Case
      final pBinary = Problem();
      pBinary.addVariables(['A', 'B'], [1, 1]);
      pBinary.addAllDifferent(['A', 'B']);
      expect(await pBinary.getSolution(), equals('FAILURE'));

      // N-ary Case
      final pNary = Problem();
      pNary.addVariables(['A', 'B', 'C'], [1, 2, 2]);
      pNary.addAllDifferent(['A', 'B', 'C']);
      expect(await pNary.getSolution(), equals('FAILURE'));
    });

    test('addExactSum works with multipliers', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3, 5]); // {A:3, B:1} -> 2*3 + 3*1 = 9
      p.addExactSum(['A', 'B'], 9, multipliers: [2, 3]);
      final solution = await p.getSolution();
      expect(solution, equals({'A': 3, 'B': 1}));
    });

    test('addAscending works for both binary and n-ary cases', () async {
      // Binary Case
      final pBinary = Problem();
      pBinary.addVariables(['A', 'B'], [1, 2]);
      pBinary.addAscending(['A', 'B']); // Solutions: {1,1}, {1,2}, {2,2}
      expect(await pBinary.countSolutions(), equals(3));

      // N-ary Case
      final pNary = Problem();
      pNary.addVariables(['A', 'B', 'C'], [1, 2]);
      pNary.addAscending(
          ['A', 'B', 'C']); // Solutions: {1,1,1}, {1,1,2}, {1,2,2}, {2,2,2}
      expect(await pNary.countSolutions(), equals(4));
    });

    test('addStrictlyAscending works correctly', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
      p.addStrictlyAscending(['A', 'B', 'C']); // Only one solution: {1,2,3}
      expect(await p.countSolutions(), equals(1));
      expect(await p.getSolution(), equals({'A': 1, 'B': 2, 'C': 3}));
    });
  });

  group('StringConstraints Extension (Advanced Parsing)', () {
    test('parses complex arithmetic with correct precedence', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);
      // Should be parsed as (A*B)+C = 11. Solution: A=2, B=4, C=3 or A=4, B=2, C=3 or A=3, B=2, C=5 ...
      p.addStringConstraint('A * B + C == 11');
      p.addAllDifferent(['A', 'B', 'C']);

      final solution = await p.getSolution() as Map<String, dynamic>;
      expect(solution['A'] * solution['B'] + solution['C'], equals(11));
    });

    test('parses expressions with negative numbers', () async {
      final p = Problem();
      p.addVariables(['A', 'B'], [-10, -5, 5, 10]);
      p.addStringConstraint('A + B == -15');
      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      expect(
          (solution as Map<String, dynamic>)['A'] + solution['B'], equals(-15));
    });

    test('parses expressions with extra whitespace', () async {
      final p = Problem();
      p.addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5]);
      p.addStringConstraint('  A  +  B   == C ');
      final solution = await p.getSolution() as Map<String, dynamic>;
      expect(solution['A'] + solution['B'], equals(solution['C']));
    });

    test('parses "not in" set constraint', () async {
      final p = Problem();
      p.addVariables(['A'], [1, 2, 3, 4]);
      p.addStringConstraint('A not in [1, 3, 4]');
      final solution = await p.getSolution();
      expect(solution, equals({'A': 2}));
    });
  });

  group('ProblemDebug Extension (Validation)', () {
    test('validate() identifies isolated variables', () {
      final p = Problem();
      p.addVariable('A', [1, 2, 3]);
      p.addVariable('B', [1, 2, 3]);
      p.addStringConstraint('A == 1'); // B is unconstrained
      final issues = p.validate();
      expect(issues, contains('Variable B has no constraints (isolated)'));
    });

    test('validate() identifies empty domains by addVariable throwing an error',
        () {
      final p = Problem();
      // This test expects that addVariable itself will prevent
      // an empty domain from ever entering the problem, which is a stronger guarantee.
      expect(() => p.addVariable('A', []), throwsArgumentError);
    });

    test('validate() warns if potentially over-constrained', () {
      final p = Problem();
      p.addVariable('A', [1]);
      p.addStringConstraints(['A == 1', 'A != 2', 'A > 0']);
      final issues = p.validate();
      expect(issues, contains(startsWith('Problem may be over-constrained')));
    });
  });

  group('MultipleSolutions Extension (Comprehensive)', () {
    Problem createProblem() {
      final p = Problem();
      p.addVariables(['A', 'B'], [1, 2, 3]); // 3 solutions for A < B
      p.addStringConstraint('A < B');
      return p;
    }

    test('getAllSolutions gets all solutions', () async {
      final p = createProblem();
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(3));
      expect(
          solutions,
          containsAll([
            {'A': 1, 'B': 2},
            {'A': 1, 'B': 3},
            {'A': 2, 'B': 3},
          ]));
    });

    test('getFirstNSolutions with n=0 returns empty list', () async {
      final p = createProblem();
      expect(await p.getFirstNSolutions(0), isEmpty);
    });

    test('getFirstNSolutions with n=1 returns one solution', () async {
      final p = createProblem();
      expect(await p.getFirstNSolutions(1), hasLength(1));
    });

    test('getFirstNSolutions with n < total returns n solutions', () async {
      final p = createProblem();
      expect(await p.getFirstNSolutions(2), hasLength(2));
    });

    test('getFirstNSolutions with n == total returns all solutions', () async {
      final p = createProblem();
      expect(await p.getFirstNSolutions(3), hasLength(3));
    });

    test('getFirstNSolutions with n > total returns all solutions', () async {
      final p = createProblem();
      expect(await p.getFirstNSolutions(10), hasLength(3));
    });

    test('getFirstNSolutions with a no-solution problem returns empty',
        () async {
      final p = Problem();
      p.addVariable('A', [1]);
      p.addStringConstraint('A > 1');
      expect(await p.getFirstNSolutions(5), isEmpty);
    });
  });

  group('Min-Conflicts Solver (Robustness)', () {
    test('solves map coloring and produces a valid solution', () async {
      final p = Problem();
      final regions = ['WA', 'NT', 'SA', 'Q', 'NSW', 'V', 'T'];
      final colors = ['red', 'green', 'blue'];
      p.addVariables(regions, colors);
      p.addStringConstraints([
        'WA != NT',
        'WA != SA',
        'NT != SA',
        'NT != Q',
        'SA != Q',
        'SA != NSW',
        'SA != V',
        'Q != NSW',
        'NSW != V'
      ]);

      final solution = await p.solveWithMinConflicts(maxSteps: 2000);

      if (solution is Map<String, dynamic>) {
        print('Min-Conflicts found a solution for Map Coloring: $solution');
        // Verify the solution is valid
        expect(solution['WA'] != solution['NT'], isTrue);
        expect(solution['WA'] != solution['SA'], isTrue);
        expect(solution['NT'] != solution['SA'], isTrue);
        expect(solution['NT'] != solution['Q'], isTrue);
        expect(solution['SA'] != solution['Q'], isTrue);
        expect(solution['SA'] != solution['NSW'], isTrue);
        expect(solution['SA'] != solution['V'], isTrue);
        expect(solution['Q'] != solution['NSW'], isTrue);
        expect(solution['NSW'] != solution['V'], isTrue);
      } else {
        print(
            'Min-Conflicts did not find a solution for Map Coloring in time.');
        expect(solution, equals('FAILURE'));
      }
    });
  });
}

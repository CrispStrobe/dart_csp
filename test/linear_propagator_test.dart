import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('LinearConstraints — addLinearEquals', () {
    test('basic 3-var equality with positive coeffs', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addLinearEquals(['A', 'B', 'C'], [1, 1, 1], 9);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        solutions.add(s);
        expect((s['A'] as int) + (s['B'] as int) + (s['C'] as int), equals(9));
      }
      // Solutions where A+B+C = 9 with each in 1..5 — there are 19
      // ordered triples (1+3+5, 1+4+4, 2+2+5, 2+3+4, 3+3+3, plus all
      // permutations).
      expect(solutions.length, equals(19));
    });

    test('weighted equality (multipliers)', () async {
      // 2X + 3Y = 12, X,Y ∈ [0..6].
      // Solutions: (0,4), (3,2), (6,0).
      final p = Problem()
        ..addVariables(['X', 'Y'], [0, 1, 2, 3, 4, 5, 6])
        ..addLinearEquals(['X', 'Y'], [2, 3], 12);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        solutions.add(s);
        expect(2 * (s['X'] as int) + 3 * (s['Y'] as int), equals(12));
      }
      expect(solutions.length, equals(3));
    });

    test('mixed-sign coefficients: 2A - B = 3', () async {
      // 2A - B = 3, A,B ∈ [0..5].
      // Solutions: A=2,B=1; A=3,B=3; A=4,B=5. (A=1,B=-1 invalid; A=0
      // gives B=-3.)
      final p = Problem()
        ..addVariables(['A', 'B'], [0, 1, 2, 3, 4, 5])
        ..addLinearEquals(['A', 'B'], [2, -1], 3);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        solutions.add(s);
        expect(2 * (s['A'] as int) - (s['B'] as int), equals(3));
      }
      expect(solutions.length, equals(3));
    });

    test('infeasible equality returns FAILURE', () async {
      // A+B = 100 with both in [1..3].
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addLinearEquals(['A', 'B'], [1, 1], 100);
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('zero coefficient leaves that var unconstrained', () async {
      // A + 0*B = 3 with A,B ∈ [1..3]. B is unconstrained — A is forced.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addLinearEquals(['A', 'B'], [1, 0], 3);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        solutions.add(s);
        expect(s['A'], equals(3));
      }
      expect(solutions.length, equals(3)); // B ranges over [1,2,3]
    });

    test('matches addExactSum predicate behavior on the same inputs', () async {
      // Two parallel problems: one with the predicate-only addExactSum,
      // one with the linear propagator. Both should enumerate the same
      // solution set; the linear version should make fewer decisions.
      final pPred = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addExactSum(['A', 'B', 'C'], 9);
      final pLin = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addLinearEquals(['A', 'B', 'C'], [1, 1, 1], 9);

      final predSols = <String>{};
      await for (final s in pPred.getSolutions()) {
        predSols.add(s.entries.map((e) => '${e.key}=${e.value}').join(','));
      }
      final linSols = <String>{};
      await for (final s in pLin.getSolutions()) {
        linSols.add(s.entries.map((e) => '${e.key}=${e.value}').join(','));
      }
      expect(linSols, equals(predSols));
    });
  });

  group('LinearConstraints — addLinearLeq / addLinearGeq', () {
    test('addLinearLeq: A + B + C <= 5', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [0, 1, 2, 3, 4, 5])
        ..addLinearLeq(['A', 'B', 'C'], [1, 1, 1], 5);
      var count = 0;
      await for (final s in p.getSolutions()) {
        expect((s['A'] as int) + (s['B'] as int) + (s['C'] as int),
            lessThanOrEqualTo(5));
        count++;
      }
      // Number of triples (A,B,C) ∈ [0..5]³ with A+B+C ≤ 5
      // = C(5+3, 3) = 56.
      expect(count, equals(56));
    });

    test('addLinearGeq: A + B + C >= 12', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [0, 1, 2, 3, 4, 5])
        ..addLinearGeq(['A', 'B', 'C'], [1, 1, 1], 12);
      var count = 0;
      await for (final s in p.getSolutions()) {
        expect((s['A'] as int) + (s['B'] as int) + (s['C'] as int),
            greaterThanOrEqualTo(12));
        count++;
      }
      // Number of triples (A,B,C) ∈ [0..5]³ with A+B+C ≥ 12: by
      // symmetry with the ≤ 3 case (5+5+5 - sum ≤ 15-12 = 3) =
      // C(3+3,3) = 20.
      expect(count, equals(20));
    });

    test('addLinearLeq with weighted coefficients', () async {
      // 2X + Y <= 6, X,Y ∈ [0..3].
      final p = Problem()
        ..addVariables(['X', 'Y'], [0, 1, 2, 3])
        ..addLinearLeq(['X', 'Y'], [2, 1], 6);
      await for (final s in p.getSolutions()) {
        expect(2 * (s['X'] as int) + (s['Y'] as int), lessThanOrEqualTo(6));
      }
    });

    test('entailed inequality (sMax already ≤ bound) does no pruning',
        () async {
      // A+B <= 100 with A,B ∈ [1..5] — trivially satisfied.
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addLinearLeq(['A', 'B'], [1, 1], 100);
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(25)); // 5 × 5
    });

    test('infeasible inequality returns FAILURE', () async {
      // A+B >= 100 with A,B ∈ [1..5].
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addLinearGeq(['A', 'B'], [1, 1], 100);
      expect(await p.getSolution(), equals('FAILURE'));
    });
  });

  group('LinearConstraints — propagator pruning is real', () {
    test('linear propagator detects root infeasibility GAC cannot', () async {
      // 5 vars in [0..9] with sum=100. Max possible sum is 45, so the
      // problem is trivially infeasible. The linear propagator
      // computes sMax = 45 < 100 during initial propagation and bails
      // out at the root with zero decisions. The predicate-only
      // encoding's GAC revise bails out at the root (free
      // neighborhood = 10⁴ = 10000 > 4096 work bound), so search has
      // to descend at least one level before propagation can wipe
      // out a domain.
      final pPred = Problem()
        ..addVariables(
            ['A', 'B', 'C', 'D', 'E'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addExactSum(['A', 'B', 'C', 'D', 'E'], 100);
      expect(await pPred.getSolution(), equals('FAILURE'));
      // Capture before the next solve clobbers the shared lastStats.
      final predDecisions = pPred.lastStats!.decisions;

      final pLin = Problem()
        ..addVariables(
            ['A', 'B', 'C', 'D', 'E'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addLinearEquals(['A', 'B', 'C', 'D', 'E'], [1, 1, 1, 1, 1], 100);
      expect(await pLin.getSolution(), equals('FAILURE'));
      final linDecisions = pLin.lastStats!.decisions;

      expect(linDecisions, equals(0),
          reason: 'linear propagator must prove infeasibility at the root');
      expect(predDecisions, greaterThan(0),
          reason: 'predicate-only GAC bails — search has to descend first');
    });

    test('SEND + MORE = MONEY solved with linear constraints', () async {
      // Classic cryptarithmetic, expressed as a single linear equation.
      const letters = ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'];
      final p = Problem();
      for (final l in letters) {
        p.addVariable(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      }
      p
        ..addAllDifferent(letters)
        ..addStringConstraint('S != 0')
        ..addStringConstraint('M != 0');
      // SEND + MORE = MONEY:
      //   1000S + 100E + 10N + D + 1000M + 100O + 10R + E
      //   = 10000M + 1000O + 100N + 10E + Y
      // Rearranged to coefficient form:
      //   1000S + 91E + (-90)N + D + (-9000)M + (-900)O + 10R + (-1)Y = 0
      p.addLinearEquals(
        ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'],
        [1000, 91, -90, 1, -9000, -900, 10, -1],
        0,
      );
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      // Verify the actual arithmetic.
      int word(List<String> ws) =>
          ws.fold(0, (acc, l) => acc * 10 + (s[l] as int));
      expect(word(['S', 'E', 'N', 'D']) + word(['M', 'O', 'R', 'E']),
          equals(word(['M', 'O', 'N', 'E', 'Y'])));
    });
  });

  group('LinearConstraints — validation', () {
    test('throws on mismatched vars/coeffs length', () {
      final p = Problem()..addVariables(['A', 'B'], [1, 2, 3]);
      expect(() => p.addLinearEquals(['A', 'B'], [1, 2, 3], 5),
          throwsA(isA<ArgumentError>()));
    });

    test('throws on unknown variable', () {
      final p = Problem()..addVariables(['A'], [1, 2, 3]);
      expect(() => p.addLinearEquals(['A', 'B'], [1, 1], 5),
          throwsA(isA<ArgumentError>()));
    });

    test('throws on empty variable list', () {
      final p = Problem();
      expect(() => p.addLinearEquals([], [], 0), throwsA(isA<ArgumentError>()));
    });

    test('throws on non-numeric domain', () {
      final p = Problem()..addVariables(['A', 'B'], ['red', 'green', 'blue']);
      expect(() => p.addLinearEquals(['A', 'B'], [1, 1], 0),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('LinearConstraints — single variable / unary case', () {
    test('addLinearEquals on one var pins the value', () async {
      // 2X = 6 with X ∈ [1..5] → X = 3.
      final p = Problem()
        ..addVariables(['X'], [1, 2, 3, 4, 5])
        ..addLinearEquals(['X'], [2], 6);
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map<String, dynamic>)['X'], equals(3));
    });

    test('addLinearLeq on one var prunes the upper end', () async {
      // 3X <= 10 with X ∈ [1..5] → X ≤ 3.
      final p = Problem()
        ..addVariables(['X'], [1, 2, 3, 4, 5])
        ..addLinearLeq(['X'], [3], 10);
      final solutions = <int>[];
      await for (final s in p.getSolutions()) {
        solutions.add(s['X'] as int);
      }
      expect(solutions.toSet(), equals({1, 2, 3}));
    });
  });

  group('LinearConstraints — composition with other constraints', () {
    test('composes with allDifferent', () async {
      // A+B+C = 10, all distinct, each ∈ [1..9].
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addLinearEquals(['A', 'B', 'C'], [1, 1, 1], 10);
      var count = 0;
      await for (final s in p.getSolutions()) {
        expect((s['A'] as int) + (s['B'] as int) + (s['C'] as int), equals(10));
        expect({s['A'], s['B'], s['C']}.length, equals(3));
        count++;
      }
      // Distinct positive triples summing to 10: {1,2,7},{1,3,6},{1,4,5},
      // {2,3,5} — 4 sets × 6 permutations = 24.
      expect(count, equals(24));
    });

    test('composes with minimize (integrated B&B)', () async {
      // Minimize X subject to 2X + 3Y >= 20, X,Y ∈ [0..10].
      // 3·10 = 30, so X=0 needs Y ≥ 20/3 → Y ≥ 7. Feasible at X=0,Y=7.
      final p = Problem()
        ..addVariables(['X', 'Y'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ..addLinearGeq(['X', 'Y'], [2, 3], 20);
      final result = await p.minimize('X');
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(0));
      expect(
          2 * (s['X'] as int) + 3 * (s['Y'] as int), greaterThanOrEqualTo(20));
    });
  });
}

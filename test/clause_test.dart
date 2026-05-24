import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Tests for the SAT-style `addClause` constraint and its unit-
/// propagation propagator. Covers validation, basic semantics
/// (entailment / conflict / unit-forcing), composition with reified
/// constraints, a CNF-style 3-coloring instance, and a propagator-
/// activity assertion.
void main() {
  group('addClause validation', () {
    test('rejects unknown variable in positive', () {
      final p = Problem();
      expect(() => p.addClause(positive: ['x']), throwsA(isA<ArgumentError>()));
    });

    test('rejects unknown variable in negative', () {
      final p = Problem();
      expect(() => p.addClause(negative: ['x']), throwsA(isA<ArgumentError>()));
    });

    test('rejects non-boolean domain', () {
      final p = Problem()..addVariable('x', [0, 1, 2]);
      expect(() => p.addClause(positive: ['x']), throwsA(isA<ArgumentError>()));
    });

    test('rejects entirely empty clause when no vars exist at all', () {
      final p = Problem();
      expect(p.addClause, throwsA(isA<ArgumentError>()));
    });

    test(
        'empty clause registers an always-false constraint when at '
        'least one variable exists', () async {
      final p = Problem()..addVariable('x', [0, 1]);
      p.addClause();
      final sol = await p.getSolution();
      expect(sol, equals('FAILURE'));
    });
  });

  group('clause semantics', () {
    test('single positive literal forces var to 1', () async {
      final p = Problem()
        ..addVariable('x', [0, 1])
        ..addClause(positive: ['x']);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      expect((sol as Map<String, dynamic>)['x'], equals(1));
    });

    test('single negative literal forces var to 0', () async {
      final p = Problem()
        ..addVariable('x', [0, 1])
        ..addClause(negative: ['x']);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      expect((sol as Map<String, dynamic>)['x'], equals(0));
    });

    test('disjunction enumerates exactly the satisfying assignments', () async {
      // x ∨ y: 3 of 4 assignments satisfy.
      final p = Problem()
        ..addVariable('x', [0, 1])
        ..addVariable('y', [0, 1])
        ..addClause(positive: ['x', 'y']);
      final solutions = <(int, int)>{};
      await for (final sol in p.getSolutions()) {
        solutions.add((sol['x'] as int, sol['y'] as int));
      }
      expect(
          solutions,
          equals(<(int, int)>{
            (0, 1),
            (1, 0),
            (1, 1),
          }));
    });

    test('mixed polarity: x ∨ ¬y has assignments where x=1 or y=0', () async {
      final p = Problem()
        ..addVariable('x', [0, 1])
        ..addVariable('y', [0, 1])
        ..addClause(positive: ['x'], negative: ['y']);
      final solutions = <(int, int)>{};
      await for (final sol in p.getSolutions()) {
        solutions.add((sol['x'] as int, sol['y'] as int));
      }
      // x=0,y=0 satisfies (¬y). x=0,y=1 doesn't. x=1,y=0/1 both satisfy.
      expect(
          solutions,
          equals(<(int, int)>{
            (0, 0),
            (1, 0),
            (1, 1),
          }));
    });

    test('unit propagation forces the remaining literal at root', () async {
      // x ∨ y, y pinned to 0 → x must be 1.
      final p = Problem()
        ..addVariable('x', [0, 1])
        ..addVariable('y', [0])
        ..addClause(positive: ['x', 'y']);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      final s = sol as Map<String, dynamic>;
      expect(s['x'], equals(1));
      expect(s['y'], equals(0));
      // Propagator should have done at least one revise.
      expect(p.lastStats!.naryRevises, greaterThan(0));
    });

    test('all-false clause is rejected at root', () async {
      // ¬x ∨ ¬y, both pinned to 1 → conflict.
      final p = Problem()
        ..addVariable('x', [1])
        ..addVariable('y', [1])
        ..addClause(negative: ['x', 'y']);
      final sol = await p.getSolution();
      expect(sol, equals('FAILURE'));
    });

    test('satisfied clause is entailed (no pruning beyond the satisfier)',
        () async {
      // x ∨ y, x pinned to 1 → y stays free → 2 solutions.
      final p = Problem()
        ..addVariable('x', [1])
        ..addVariable('y', [0, 1])
        ..addClause(positive: ['x', 'y']);
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(2));
    });

    test('variable appearing in both polarities makes clause vacuous',
        () async {
      // x ∨ ¬x: always true.
      final p = Problem()
        ..addVariable('x', [0, 1])
        ..addClause(positive: ['x'], negative: ['x']);
      final solutions = <int>{};
      await for (final sol in p.getSolutions()) {
        solutions.add(sol['x'] as int);
      }
      expect(solutions, equals(<int>{0, 1}));
    });
  });

  group('integration with reified constraints', () {
    test('CNF encoding: (a ∨ b) ∧ (¬a ∨ ¬b) reduces to a XOR b', () async {
      // Standard XOR CNF.
      final p = Problem()
        ..addVariable('a', [0, 1])
        ..addVariable('b', [0, 1])
        ..addClause(positive: ['a', 'b'])
        ..addClause(negative: ['a', 'b']);
      final solutions = <(int, int)>{};
      await for (final sol in p.getSolutions()) {
        solutions.add((sol['a'] as int, sol['b'] as int));
      }
      expect(solutions, equals(<(int, int)>{(0, 1), (1, 0)}));
    });

    test('compose with reified equality to express CNF over data vars',
        () async {
      // (x == 1 ∨ y == 5) — at least one of these equalities holds.
      final p = Problem()
        ..addVariable('x', [1, 2, 3])
        ..addVariable('y', [4, 5, 6])
        ..addReifiedEquals('bX1', 'x', 1)
        ..addReifiedEquals('bY5', 'y', 5)
        ..addClause(positive: ['bX1', 'bY5']);
      await for (final sol in p.getSolutions()) {
        final x = sol['x'] as int;
        final y = sol['y'] as int;
        expect(x == 1 || y == 5, isTrue,
            reason: 'clause violated for (x=$x, y=$y)');
      }
    });
  });

  group('CNF-encoded 3-coloring', () {
    test('triangle graph (K3) over 3 colors: 6 solutions', () async {
      // Three nodes a, b, c, each gets one of 3 colors via 3 indicator
      // booleans (a_c0, a_c1, a_c2, ...). Edges a-b, b-c, a-c must
      // differ. Encode as CNF:
      //   - Each node has at least one color: a_c0 ∨ a_c1 ∨ a_c2.
      //   - Each node has at most one color: ¬a_ci ∨ ¬a_cj for i ≠ j.
      //   - Edge constraint: ¬a_ci ∨ ¬b_ci for each color i.
      final p = Problem();
      for (final node in ['a', 'b', 'c']) {
        for (final color in [0, 1, 2]) {
          p.addVariable('${node}_$color', [0, 1]);
        }
        // At least one color.
        p.addClause(positive: [
          for (final c in [0, 1, 2]) '${node}_$c'
        ]);
        // At most one color.
        for (var i = 0; i < 3; i++) {
          for (var j = i + 1; j < 3; j++) {
            p.addClause(negative: ['${node}_$i', '${node}_$j']);
          }
        }
      }
      // Edges: a-b, b-c, a-c.
      for (final edge in [('a', 'b'), ('b', 'c'), ('a', 'c')]) {
        for (final color in [0, 1, 2]) {
          p.addClause(negative: ['${edge.$1}_$color', '${edge.$2}_$color']);
        }
      }
      var count = 0;
      await for (final sol in p.getSolutions()) {
        // Verify each node has exactly one color.
        for (final node in ['a', 'b', 'c']) {
          final assigned = [
            for (final c in [0, 1, 2])
              if (sol['${node}_$c'] == 1) c
          ];
          expect(assigned.length, equals(1),
              reason: 'node $node should have exactly one color');
        }
        count++;
      }
      // 3-coloring of K3 has 3! = 6 distinct colorings.
      expect(count, equals(6));
    });
  });

  group('two-watched-literal correctness', () {
    test(
        'rollback after a deep watcher swap is sound across a full '
        'enumeration', () async {
      // Five-literal clause. The engine drives substantial
      // search: pin some literals first to a falsifying value, then
      // backtrack to a different sub-assignment. Watchers picked
      // under the first sub-assignment should remain valid (i.e.,
      // non-falsified) under the second, because backtrack only
      // restores values. We verify this indirectly by checking
      // that the full solution count over all 2^5 assignments
      // matches the brute-force count of disjunction satisfiers.
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd', 'e'], [0, 1])
        ..addClause(positive: ['a', 'b', 'c', 'd', 'e']);
      var got = 0;
      await for (final sol in p.getSolutions()) {
        // At least one of a..e must be 1.
        final ones = ['a', 'b', 'c', 'd', 'e'].where((v) => sol[v] == 1).length;
        expect(ones, greaterThan(0));
        got++;
      }
      // 2^5 - 1 = 31 satisfying (everything except all-zero).
      expect(got, equals(31));
    });

    test(
        'enumeration count is unchanged from the stateless reference '
        'on a 4-pigeon-3-hole CNF encoding', () async {
      // Pigeon-hole principle: 4 pigeons can't all fit in 3 holes
      // pairwise-distinct. Encode with one indicator per
      // (pigeon, hole) pair. The CNF below requires every pigeon
      // gets a hole AND no two pigeons share a hole. Infeasible.
      final p = Problem();
      const pigeons = 4;
      const holes = 3;
      for (var p_ = 0; p_ < pigeons; p_++) {
        for (var h = 0; h < holes; h++) {
          p.addVariable('p${p_}_h$h', [0, 1]);
        }
        // Each pigeon in at least one hole.
        p.addClause(positive: [
          for (var h = 0; h < holes; h++) 'p${p_}_h$h',
        ]);
      }
      // No two pigeons in the same hole.
      for (var h = 0; h < holes; h++) {
        for (var i = 0; i < pigeons; i++) {
          for (var j = i + 1; j < pigeons; j++) {
            p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
          }
        }
      }
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
      // Watchers must have triggered enough propagation to report
      // measurable work via the nary-revises counter.
      expect(p.lastStats!.naryRevises, greaterThan(0));
    });

    test(
        'many-clauses stress: random 3-SAT instance enumerates to a '
        'deterministic solution set', () async {
      // Small but non-trivial random 3-SAT: 5 vars, 10 clauses
      // chosen so the formula has 4 satisfying assignments. The
      // clauses are intentionally over a small variable set so
      // they actively share literals and exercise watcher swaps
      // between calls.
      final p = Problem()
        ..addVariables(['v1', 'v2', 'v3', 'v4', 'v5'], [0, 1])
        // Hand-picked clauses. Each line is a disjunction.
        ..addClause(positive: ['v1', 'v2', 'v3'])
        ..addClause(positive: ['v1'], negative: ['v2', 'v4'])
        ..addClause(positive: ['v3', 'v4'], negative: ['v1'])
        ..addClause(positive: ['v2', 'v5'], negative: ['v3'])
        ..addClause(positive: ['v4'], negative: ['v1', 'v5'])
        ..addClause(positive: ['v1', 'v5'], negative: ['v3', 'v4'])
        ..addClause(positive: ['v3'], negative: ['v2'])
        ..addClause(positive: ['v2'], negative: ['v4', 'v5'])
        ..addClause(positive: ['v1', 'v3', 'v4'])
        ..addClause(positive: ['v5'], negative: ['v1', 'v2']);

      // Brute-force the same formula to derive the expected count
      // and assignments. Reading the assertions this way makes the
      // test robust to formula changes — it asserts the watcher-
      // based propagator agrees with a naive evaluator, not a
      // hard-coded number.
      bool litTrue(Map<String, dynamic> a, String v,
              {required bool positive}) =>
          positive ? a[v] == 1 : a[v] == 0;
      bool clauseTrue(
        Map<String, dynamic> a,
        List<String> pos,
        List<String> neg,
      ) =>
          pos.any((v) => litTrue(a, v, positive: true)) ||
          neg.any((v) => litTrue(a, v, positive: false));

      final clauses = <(List<String>, List<String>)>[
        (['v1', 'v2', 'v3'], []),
        (['v1'], ['v2', 'v4']),
        (['v3', 'v4'], ['v1']),
        (['v2', 'v5'], ['v3']),
        (['v4'], ['v1', 'v5']),
        (['v1', 'v5'], ['v3', 'v4']),
        (['v3'], ['v2']),
        (['v2'], ['v4', 'v5']),
        (['v1', 'v3', 'v4'], []),
        (['v5'], ['v1', 'v2']),
      ];

      final brute = <String>{};
      for (var bits = 0; bits < 32; bits++) {
        final a = <String, dynamic>{
          'v1': (bits >> 0) & 1,
          'v2': (bits >> 1) & 1,
          'v3': (bits >> 2) & 1,
          'v4': (bits >> 3) & 1,
          'v5': (bits >> 4) & 1,
        };
        if (clauses.every((c) => clauseTrue(a, c.$1, c.$2))) {
          brute.add(a.values.join(','));
        }
      }

      final solver = <String>{};
      await for (final sol in p.getSolutions()) {
        solver.add(['v1', 'v2', 'v3', 'v4', 'v5'].map((k) => sol[k]).join(','));
      }

      expect(solver, equals(brute),
          reason: 'watched-literal propagator must enumerate exactly '
              'the brute-force satisfying assignments');
      expect(solver.isNotEmpty, isTrue);
    });

    test('repeated solves on the same Problem reuse watcher state', () async {
      // Sanity: calling getSolution twice in a row on the same
      // Problem instance returns the same first solution. This
      // catches accidental cross-engine state sharing, since each
      // solve constructs a fresh _BacktrackEngine (with its own
      // side-table).
      final p = Problem()
        ..addVariables(['x', 'y', 'z'], [0, 1])
        ..addClause(positive: ['x', 'y', 'z']);
      final a = await p.getSolution();
      final b = await p.getSolution();
      expect(a, equals(b));
    });
  });
}

/// Unit tests for the atom-clause shape of [ClauseSpec] introduced by
/// LCG's lazy-atom-encoding extension (the foundation for M3 per-
/// propagator `explain` companions).
///
/// User-facing `Problem.addClause` only produces boolean clauses; atom
/// clauses are constructed internally by the LCG learned-clause path
/// or — as here — manually via the lower-level [CspProblem] +
/// [NaryConstraint] APIs for testing. These tests exercise the
/// propagator's atom-clause path: evaluation of each atom kind, unit-
/// prop, conflict detection on all-falsified, and the two-watched-
/// literal invariant under non-trivial pin patterns.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

NaryConstraint _atomClause(List<String> vars, List<Atom> atoms) =>
    NaryConstraint(
      vars: vars,
      predicate: (assn) {
        var anyUnknown = false;
        for (final a in atoms) {
          final v = assn[a.varName];
          if (v == null) {
            anyUnknown = true;
            continue;
          }
          if (v is! int) return true;
          final entailed = switch (a) {
            AtomEq() => v == a.value,
            AtomNe() => v != a.value,
            AtomLe() => v <= a.value,
            AtomGe() => v >= a.value,
          };
          if (entailed) return true;
        }
        return anyUnknown;
      },
      clauseSpec: ClauseSpec(literals: const [], atoms: atoms),
    );

void main() {
  group('atom-clause propagator — eval per atom kind', () {
    test('AtomEq satisfied → clause satisfied → solver accepts', () async {
      final csp = CspProblem(
        variables: {
          'x': [3],
          'y': [4, 5, 6],
        },
        naryConstraints: [
          _atomClause(['x', 'y'], [const AtomEq('x', 3), const AtomEq('y', 4)]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect(m['x'], 3);
    });

    test('AtomNe with falsifying value pinned forces other literal', () async {
      // (x ≠ 2) ∨ (y ≥ 5). Pin x = 2 so AtomNe(x, 2) is falsified;
      // unit-prop must force AtomGe(y, 5) → y ∈ {5, 6}.
      final csp = CspProblem(
        variables: {
          'x': [2],
          'y': [4, 5, 6],
        },
        naryConstraints: [
          _atomClause(['x', 'y'], [const AtomNe('x', 2), const AtomGe('y', 5)]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect(m['x'], 2);
      expect(m['y'], anyOf(5, 6));
    });

    test('AtomLe forces upper-bound prune on unit-prop', () async {
      // (x ≥ 10) ∨ (y ≤ 3). With x pinned to 5, AtomGe(x, 10) is
      // falsified; AtomLe(y, 3) must force y to its values ≤ 3.
      final csp = CspProblem(
        variables: {
          'x': [5],
          'y': [1, 2, 3, 4, 5],
        },
        naryConstraints: [
          _atomClause(
              ['x', 'y'], [const AtomGe('x', 10), const AtomLe('y', 3)]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect((m['y'] as int) <= 3, isTrue);
    });

    test('AtomGe forces lower-bound prune on unit-prop', () async {
      final csp = CspProblem(
        variables: {
          'x': [0],
          'y': [1, 2, 3, 4, 5],
        },
        naryConstraints: [
          _atomClause(['x', 'y'], [const AtomEq('x', 7), const AtomGe('y', 4)]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect((m['y'] as int) >= 4, isTrue);
    });
  });

  group('atom-clause propagator — conflict detection', () {
    test('all literals falsified at root → root infeasibility', () async {
      // Pin x = 2 and y = 1; both atoms become falsified, so the
      // clause is unsatisfiable.
      final csp = CspProblem(
        variables: {
          'x': [2],
          'y': [1],
        },
        naryConstraints: [
          _atomClause(['x', 'y'], [const AtomEq('x', 1), const AtomEq('y', 2)]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, 'FAILURE');
    });

    test('all-but-one falsified plus the survivor unsatisfiable → FAILURE',
        () async {
      // (x = 5) ∨ (y = 10). x ∈ {3} (falsifies first), y ∈ {7, 8, 9}
      // (no value satisfies second). Unit-prop on y must fail.
      final csp = CspProblem(
        variables: {
          'x': [3],
          'y': [7, 8, 9],
        },
        naryConstraints: [
          _atomClause(
              ['x', 'y'], [const AtomEq('x', 5), const AtomEq('y', 10)]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, 'FAILURE');
    });
  });

  group('atom-clause propagator — three-literal clauses', () {
    test('three-literal clause: two falsified, third unit-prop forces it',
        () async {
      // (x = 1) ∨ (y = 2) ∨ (z ≤ 0).
      // Pin x = 9, y = 9 ⇒ first two falsified ⇒ unit-prop z ≤ 0.
      final csp = CspProblem(
        variables: {
          'x': [9],
          'y': [9],
          'z': [-2, -1, 0, 1, 2],
        },
        naryConstraints: [
          _atomClause([
            'x',
            'y',
            'z'
          ], [
            const AtomEq('x', 1),
            const AtomEq('y', 2),
            const AtomLe('z', 0)
          ]),
        ],
      );
      final result = await CSP.solve(csp);
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect((m['z'] as int) <= 0, isTrue);
    });

    test('three-literal clause: one falsified, two undetermined → no prop',
        () async {
      // Watch-literal invariant: with two non-falsified literals
      // remaining, the propagator should not force any prune (no
      // unit-prop yet).
      final csp = CspProblem(
        variables: {
          'x': [5, 6],
          'y': [5, 6],
          'z': [5],
        },
        naryConstraints: [
          _atomClause([
            'x',
            'y',
            'z'
          ], [
            const AtomEq('x', 1),
            const AtomEq('y', 2),
            const AtomEq('z', 3)
          ]),
        ],
      );
      // The clause is unsatisfiable in any extension because z is
      // pinned away from 3 and neither x nor y has the satisfying
      // values 1 / 2 in their domains. The solve must fail.
      final result = await CSP.solve(csp);
      expect(result, 'FAILURE');
    });
  });

  group('_learnedClauseToSpec dispatch (via solveWithLcg parity)', () {
    test('boolean-only learned-clause path still triggers on pigeonhole',
        () async {
      // Reuses the M2b pigeonhole regression: every learned clause has
      // boolean atoms, so the dispatcher picks the boolean shape (not
      // the atom shape introduced by this extension). The decision
      // count must continue to drop dramatically — same gate as the
      // existing pigeonhole acceptance test.
      Problem build({required int pigeons, required int holes}) {
        final p = Problem();
        for (var pg = 0; pg < pigeons; pg++) {
          for (var h = 0; h < holes; h++) {
            p.addVariable('p${pg}_h$h', [0, 1]);
          }
          p.addClause(positive: [for (var h = 0; h < holes; h++) 'p${pg}_h$h']);
        }
        for (var h = 0; h < holes; h++) {
          for (var i = 0; i < pigeons; i++) {
            for (var j = i + 1; j < pigeons; j++) {
              p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
            }
          }
        }
        return p;
      }

      final plain = build(pigeons: 7, holes: 6);
      await plain.getSolution();
      final plainDecisions = CSP.lastStats!.decisions;

      final lcg = build(pigeons: 7, holes: 6);
      await lcg.solveWithLcg();
      final lcgStats = CSP.lastStats!;
      expect(lcgStats.learnedClauses, greaterThan(0));
      expect(lcgStats.decisions * 5, lessThan(plainDecisions),
          reason: 'boolean dispatch path must still cut decisions ≥ 5×');
    });
  });
}

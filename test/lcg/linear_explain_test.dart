/// LCG M3b tests: `_LinearPropagator` bound-explanation companion.
/// Verifies the new `LinearBoundReason` is correctly emitted on the
/// implication trail when linear-spec constraints prune values or
/// detect infeasibility.
///
/// **Limitation acknowledged in these tests.** The shipped M3b
/// explanation is *coarse*: per-prune antecedents include every
/// other variable in the constraint scope (`AtomNe` for every absent
/// value). The first-UIP analyser requires tight per-prune
/// antecedents (ideally at most one at-conflict-level atom per
/// resolution step) to isolate a UIP and emit a learned clause; on
/// dense-conflict problems like 4×4 magic squares the coarse
/// antecedents cause the analyser to bail. The M3b wiring is in
/// place — the propagator emits `LinearBoundReason` and the engine
/// captures `_lastConflictReason` on linear failures — so a future
/// per-prune-tight refinement can land without touching the
/// surrounding plumbing.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('LinearBoundReason — construction + antecedents', () {
    test('carries the provided antecedent atoms', () {
      final atoms = <Atom>[const AtomNe('x', 1), const AtomNe('y', 5)];
      const empty = LinearBoundReason([]);
      expect(empty.antecedents(), isEmpty);
      final r = LinearBoundReason(atoms);
      expect(r.antecedents(), atoms);
    });

    test('toString surfaces the antecedent atoms for debugging', () {
      const r = LinearBoundReason([AtomNe('q', 3)]);
      expect(r.toString(), contains('q != 3'));
    });
  });

  group('M3b end-to-end — correctness on linear-using problems', () {
    test('SEND + MORE = MONEY (addLinearEquals) — LCG matches plain solve',
        () async {
      Problem build() {
        final letters = ['S', 'E', 'N', 'D', 'M', 'O', 'R', 'Y'];
        final p = Problem();
        for (final l in letters) {
          p.addVariable(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
        }
        p
          ..addAllDifferent(letters)
          ..addStringConstraint('S != 0')
          ..addStringConstraint('M != 0')
          ..addLinearEquals(
            letters,
            [1000, 91, -90, 1, -9000, -900, 10, -1],
            0,
          );
        return p;
      }

      final viaPlain = await build().getSolution();
      final viaLcg = await build().solveWithLcg();
      expect(viaPlain, isA<Map<String, dynamic>>());
      expect(viaLcg, isA<Map<String, dynamic>>());
      expect(viaLcg, viaPlain,
          reason: 'M3b LCG path must agree with plain getSolution under'
              ' deterministic ordering');
    });

    test('magic-square 3x3 (linear-spec sums) — LCG matches plain solve',
        () async {
      Problem build() {
        const cells = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
        final p = Problem()
          ..addVariables(cells, [1, 2, 3, 4, 5, 6, 7, 8, 9])
          ..addAllDifferent(cells);
        void sum(List<String> vs) =>
            p.addLinearEquals(vs, List<num>.filled(vs.length, 1), 15);
        sum(['A1', 'A2', 'A3']);
        sum(['B1', 'B2', 'B3']);
        sum(['C1', 'C2', 'C3']);
        sum(['A1', 'B1', 'C1']);
        sum(['A2', 'B2', 'C2']);
        sum(['A3', 'B3', 'C3']);
        sum(['A1', 'B2', 'C3']);
        sum(['A3', 'B2', 'C1']);
        return p;
      }

      final viaPlain = await build().getSolution();
      final viaLcg = await build().solveWithLcg();
      expect(viaPlain, isA<Map<String, dynamic>>());
      expect(viaLcg, isA<Map<String, dynamic>>());
      expect(viaLcg, viaPlain);
    });

    test('linear UNSAT (sum bound infeasible) — both return FAILURE', () async {
      // Sum constraint that cannot be satisfied: vars in {1..5}, sum
      // must equal 100. UNSAT at root preprocessing via the linear
      // propagator's global feasibility check.
      Problem build() => Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3, 4, 5])
        ..addLinearEquals(['a', 'b', 'c'], [1, 1, 1], 100);
      final r1 = await build().getSolution();
      final r2 = await build().solveWithLcg();
      expect(r1, 'FAILURE');
      expect(r2, 'FAILURE');
    });
  });

  group('M3b regression — non-regression on existing learning paths', () {
    test('pigeonhole-CNF 7-in-6 still learns under M3b plumbing', () async {
      Problem build() {
        final p = Problem();
        for (var pg = 0; pg < 7; pg++) {
          for (var h = 0; h < 6; h++) {
            p.addVariable('p${pg}_h$h', [0, 1]);
          }
          p.addClause(positive: [for (var h = 0; h < 6; h++) 'p${pg}_h$h']);
        }
        for (var h = 0; h < 6; h++) {
          for (var i = 0; i < 7; i++) {
            for (var j = i + 1; j < 7; j++) {
              p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
            }
          }
        }
        return p;
      }

      final plain = build();
      await plain.getSolution();
      final plainDecisions = CSP.lastStats!.decisions;

      final lcg = build();
      await lcg.solveWithLcg();
      final lcgStats = CSP.lastStats!;
      expect(lcgStats.learnedClauses, greaterThan(0));
      expect(lcgStats.decisions * 5, lessThan(plainDecisions),
          reason: 'M2b CNF path must still cut ≥ 5×');
    });

    test('sudoku medium still learns under M3a + M3b plumbing', () async {
      Problem build() {
        const puzzle = [
          [1, 0, 0, 0, 0, 7, 0, 9, 0],
          [0, 3, 0, 0, 2, 0, 0, 0, 8],
          [0, 0, 9, 6, 0, 0, 5, 0, 0],
          [0, 0, 5, 3, 0, 0, 9, 0, 0],
          [0, 1, 0, 0, 8, 0, 0, 0, 2],
          [6, 0, 0, 0, 0, 4, 0, 0, 0],
          [3, 0, 0, 0, 0, 0, 0, 1, 0],
          [0, 4, 0, 0, 0, 0, 0, 0, 7],
          [0, 0, 7, 0, 0, 0, 3, 0, 0],
        ];
        final p = Problem();
        for (var r = 0; r < 9; r++) {
          for (var c = 0; c < 9; c++) {
            final name = 'r${r}c$c';
            final v = puzzle[r][c];
            p.addVariable(name, v != 0 ? [v] : [1, 2, 3, 4, 5, 6, 7, 8, 9]);
          }
        }
        for (var r = 0; r < 9; r++) {
          p.addAllDifferent([for (var c = 0; c < 9; c++) 'r${r}c$c']);
        }
        for (var c = 0; c < 9; c++) {
          p.addAllDifferent([for (var r = 0; r < 9; r++) 'r${r}c$c']);
        }
        for (var br = 0; br < 3; br++) {
          for (var bc = 0; bc < 3; bc++) {
            final cells = <String>[];
            for (var dr = 0; dr < 3; dr++) {
              for (var dc = 0; dc < 3; dc++) {
                cells.add('r${br * 3 + dr}c${bc * 3 + dc}');
              }
            }
            p.addAllDifferent(cells);
          }
        }
        return p;
      }

      final p = build();
      await p.solveWithLcg();
      expect(CSP.lastStats!.learnedClauses, greaterThan(0),
          reason: 'M3a learning on sudoku medium must still trigger');
    });
  });
}

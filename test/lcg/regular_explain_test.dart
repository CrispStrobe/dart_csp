/// LCG M3d tests: `_RegularPropagator` layered-DFA explanation companion.
///
/// The `regular` constraint accepts an assignment iff its value sequence
/// traces a path from the DFA start to an accepting state. M3d gives it
/// the same M3-tighten treatment as M3a/M3c: each pruned value's "why"
/// (the *other* positions' value removals that killed every supporting
/// layered-DFA path) collapses into a single synthetic [AtomInScc] bridge
/// so the first-UIP analyser converges and learns clauses on
/// regular-shaped conflicts.
///
/// **Why the showcase is UNSAT.** `regular` is GAC-strong: on a
/// *satisfiable* grid the layered reachability sweep prunes to a solution
/// at (or very near) the root, so no search conflict arises and nothing
/// is learned. Learning manifests on UNSAT instances, where the engine
/// explores the whole tree and the regular propagator detects the
/// conflicts. The acceptance criterion therefore pairs UNSAT learning
/// activation (learnedClauses > 0, naryRevises > 0) with a broad
/// verdict-parity sweep against full enumeration (the independent
/// gold standard) over both SAT and UNSAT, binary and ternary grids —
/// an unsound explanation flips a verdict or yields an invalid/wrong
/// assignment, which the sweep surfaces immediately.
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// DFA over binary symbols accepting sequences of any length with
/// *exactly* [k] ones. State = number of ones read so far (0..k); a
/// (k+1)-th one falls into the trap.
Dfa _exactlyKOnes(int k) {
  final trap = k + 1;
  final transitions = <int, Map<dynamic, int>>{
    for (var s = 0; s <= k; s++) s: {0: s, 1: s + 1 > k ? trap : s + 1},
    trap: {0: trap, 1: trap},
  };
  return Dfa(
      numStates: k + 2, start: 0, accepting: {k}, transitions: transitions);
}

/// DFA over symbols 0..[maxSym] accepting sequences whose symbol sum is
/// exactly [target]. State = partial sum (0..target); overshoot traps.
Dfa _sumDfa(int target, int maxSym) {
  final trap = target + 1;
  final transitions = <int, Map<dynamic, int>>{
    for (var s = 0; s <= target; s++)
      s: {
        for (var sym = 0; sym <= maxSym; sym++)
          sym: s + sym > target ? trap : s + sym,
      },
    trap: {for (var sym = 0; sym <= maxSym; sym++) sym: trap},
  };
  return Dfa(
      numStates: target + 2,
      start: 0,
      accepting: {target},
      transitions: transitions);
}

/// `R`×`C` grid where each row's symbols sum to `rowS[r]` and each
/// column's to `colS[c]`, with cell domain 0..[maxSym]. Every row and
/// column is a `regular` constraint, so the grid is dispatched entirely
/// through `_RegularPropagator` — no allDifferent / linear involvement.
Problem _grid(int R, int C, List<int> rowS, List<int> colS, int maxSym) {
  final p = Problem();
  for (var r = 0; r < R; r++) {
    for (var c = 0; c < C; c++) {
      p.addVariable('x${r}_$c', [for (var v = 0; v <= maxSym; v++) v]);
    }
  }
  Dfa dfa(int target) =>
      maxSym == 1 ? _exactlyKOnes(target) : _sumDfa(target, maxSym);
  for (var r = 0; r < R; r++) {
    p.addRegular([for (var c = 0; c < C; c++) 'x${r}_$c'], dfa(rowS[r]));
  }
  for (var c = 0; c < C; c++) {
    p.addRegular([for (var r = 0; r < R; r++) 'x${r}_$c'], dfa(colS[c]));
  }
  return p;
}

bool _validGrid(
    Map<String, dynamic> sol, int R, int C, List<int> rowS, List<int> colS) {
  for (var r = 0; r < R; r++) {
    var s = 0;
    for (var c = 0; c < C; c++) {
      s += sol['x${r}_$c'] as int;
    }
    if (s != rowS[r]) return false;
  }
  for (var c = 0; c < C; c++) {
    var s = 0;
    for (var r = 0; r < R; r++) {
      s += sol['x${r}_$c'] as int;
    }
    if (s != colS[c]) return false;
  }
  return true;
}

void main() {
  group('RegularReason', () {
    test('passes its antecedent atoms through unchanged', () {
      const atoms = [AtomEq('a', 1), AtomInScc('h', 7)];
      const r = RegularReason(atoms);
      expect(r.antecedents(), atoms);
      expect(r.toString(), contains('a = 1'));
    });

    test('empty reason has no antecedents', () {
      expect(const RegularReason([]).antecedents(), isEmpty);
    });
  });

  group('M3d end-to-end — regular grid learning (UNSAT showcase)', () {
    // A 5×5 binary grid with incompatible row/column "exactly-k-ones"
    // margins. UNSAT, but only jointly so: each row / column is locally
    // satisfiable, so the regular propagators must search the tree and
    // detect the conflicts — exactly the conditions M3d explains.
    const R = 5;
    const C = 5;
    const rowK = [2, 4, 2, 4, 2];
    const colK = [2, 1, 3, 4, 1];

    test('proves UNSAT and matches plain backtracking', () async {
      final plain = await _grid(R, C, rowK, colK, 1).getSolution();
      expect(plain, 'FAILURE', reason: 'instance must be jointly UNSAT');
      final lcg = await _grid(R, C, rowK, colK, 1).solveWithLcg();
      expect(lcg, 'FAILURE', reason: 'LCG verdict must match plain');
    });

    test('the regular propagator is active and learns clauses', () async {
      await _grid(R, C, rowK, colK, 1).solveWithLcg(useVsids: true, seed: 1);
      final st = CSP.lastStats!;
      expect(st.naryRevises, greaterThan(0),
          reason: 'regular propagator must do real pruning');
      expect(st.learnedClauses, greaterThanOrEqualTo(1),
          reason: 'M3d explanation must drive at least one learned clause');
    });

    test('learning holds across randomized VSIDS orders', () async {
      for (var seed = 0; seed < 8; seed++) {
        final lcg = await _grid(R, C, rowK, colK, 1)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(lcg, 'FAILURE', reason: 'seed=$seed verdict must stay UNSAT');
        expect(CSP.lastStats!.learnedClauses, greaterThanOrEqualTo(1),
            reason: 'seed=$seed must still learn from regular conflicts');
      }
    });
  });

  group('M3d soundness — verdict parity vs full enumeration', () {
    // The primary soundness net: across many random grids (SAT + UNSAT,
    // binary + ternary) and decision orders, `solveWithLcg` must agree
    // with the enumeration verdict; every SAT answer must be a valid
    // assignment; and a unique solution must be returned exactly. An
    // unsound learned clause shows up as a flipped verdict or a
    // wrong/invalid assignment.
    test('binary + ternary random grids agree with enumeration', () async {
      final rng = Random(20240529);
      var instances = 0;
      var satSeen = 0;
      var unsatSeen = 0;
      var uniqueChecked = 0;
      for (var t = 0; t < 160; t++) {
        final maxSym = rng.nextInt(2) + 1; // 1 (binary) or 2 (ternary)
        final R = 3 + rng.nextInt(2); // 3..4
        final C = 3 + rng.nextInt(2);
        // Half the instances get realizable (SAT) margins from a random
        // matrix; the other half get free random margins (often UNSAT).
        final List<int> rowS;
        final List<int> colS;
        if (t.isEven) {
          final m = [
            for (var r = 0; r < R; r++)
              [for (var c = 0; c < C; c++) rng.nextInt(maxSym + 1)]
          ];
          rowS = [for (var r = 0; r < R; r++) m[r].reduce((a, b) => a + b)];
          colS = [
            for (var c = 0; c < C; c++)
              [for (var r = 0; r < R; r++) m[r][c]].reduce((a, b) => a + b)
          ];
        } else {
          rowS = [for (var r = 0; r < R; r++) rng.nextInt(C * maxSym + 1)];
          colS = [for (var c = 0; c < C; c++) rng.nextInt(R * maxSym + 1)];
        }

        final all = await _grid(R, C, rowS, colS, maxSym).getAllSolutions();
        final sat = all.isNotEmpty;
        final unique = all.length == 1;
        if (sat) {
          satSeen++;
        } else {
          unsatSeen++;
        }
        final canonical =
            unique ? {for (final k in all.first.keys) k: all.first[k]} : null;

        for (var seed = 0; seed < 4; seed++) {
          instances++;
          final r = await _grid(R, C, rowS, colS, maxSym)
              .solveWithLcg(useVsids: true, seed: seed);
          if (sat) {
            expect(r, isA<Map<String, dynamic>>(),
                reason: 't=$t seed=$seed must stay SAT '
                    'rowS=$rowS colS=$colS maxSym=$maxSym');
            final m = r as Map<String, dynamic>;
            expect(_validGrid(m, R, C, rowS, colS), isTrue,
                reason: 't=$t seed=$seed returned an invalid grid');
            if (canonical != null) {
              uniqueChecked++;
              for (final k in canonical.keys) {
                expect(m[k], canonical[k],
                    reason: 't=$t seed=$seed unique cell $k mismatch');
              }
            }
          } else {
            expect(r, 'FAILURE',
                reason: 't=$t seed=$seed must stay UNSAT '
                    'rowS=$rowS colS=$colS maxSym=$maxSym');
          }
        }
      }
      // Sanity: the sweep actually covered both verdicts.
      expect(satSeen, greaterThan(0));
      expect(unsatSeen, greaterThan(0));
      expect(instances, greaterThan(0));
      expect(uniqueChecked, greaterThanOrEqualTo(0));
    });
  });
}

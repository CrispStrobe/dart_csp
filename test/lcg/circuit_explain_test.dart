/// LCG M3g tests: `_CircuitPropagator` cycle-detection explanation
/// companion — the last opaque propagator.
///
/// `circuit` forces a single Hamiltonian cycle over the successor
/// variables. Every prune/conflict is driven by the current **fixed
/// edges** (singleton-pinned successors): the chain-closing prune follows
/// from the chain's edges, the successor-uniqueness prune from the one
/// owning edge. M3g explains each with `AtomEq(vars[i], v)` atoms (the
/// assignment shape that unlocked allDifferent/GCC) collapsed through one
/// synthetic [AtomInScc] bridge; conflicts use a coarse all-fixed-edges
/// bridge.
///
/// Validation mirrors the other M3 companions: learning activation on a
/// constraint-dominated instance plus a verdict-parity sweep against full
/// enumeration (an unsound clause flips a verdict or returns a non-cycle).
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// `n`-node circuit; `vars[i]` is node `i`'s successor. [forbidden] holds
/// `"i->v"` arcs to drop from the domains (every node keeps at least one
/// successor). Dispatched through `_CircuitPropagator`.
Problem _circuit(int n, Set<String> forbidden) {
  final p = Problem();
  final vars = [for (var i = 0; i < n; i++) 'c$i'];
  for (var i = 0; i < n; i++) {
    final dom = [
      for (var v = 0; v < n; v++)
        if (i != v && !forbidden.contains('$i->$v')) v
    ];
    if (dom.isEmpty) dom.add((i + 1) % n);
    p.addVariable(vars[i], dom);
  }
  p.addCircuit(vars);
  return p;
}

/// True iff [sol]'s successor map is a single Hamiltonian cycle over
/// `0..n-1`.
bool _isHamiltonianCycle(Map<String, dynamic> sol, int n) {
  final next = [for (var i = 0; i < n; i++) sol['c$i'] as int];
  final seen = <int>{};
  var cur = 0;
  for (var step = 0; step < n; step++) {
    if (cur < 0 || cur >= n || !seen.add(cur)) return false;
    cur = next[cur];
  }
  return cur == 0 && seen.length == n;
}

void main() {
  group('CircuitReason', () {
    test('passes its antecedent atoms through unchanged', () {
      const atoms = [AtomEq('c0', 1), AtomInScc('h', 7)];
      const r = CircuitReason(atoms);
      expect(r.antecedents(), atoms);
      expect(r.toString(), contains('c0 = 1'));
    });

    test('empty reason has no antecedents', () {
      expect(const CircuitReason([]).antecedents(), isEmpty);
    });
  });

  group('M3g end-to-end — circuit learning', () {
    test('UNSAT circuit proves UNSAT, is active, and learns', () async {
      const n = 5;
      const forbidden = {
        '0->4',
        '1->2',
        '1->4',
        '2->0',
        '2->4',
        '3->0',
        '3->4'
      };
      final plain = await _circuit(n, forbidden).getSolution();
      expect(plain, 'FAILURE', reason: 'instance must be UNSAT');
      for (var seed = 0; seed < 6; seed++) {
        final lcg = await _circuit(n, forbidden)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(lcg, 'FAILURE', reason: 'seed=$seed verdict must match plain');
        final st = CSP.lastStats!;
        expect(st.naryRevises, greaterThan(0),
            reason: 'seed=$seed circuit propagator must prune');
        expect(st.learnedClauses, greaterThanOrEqualTo(1),
            reason: 'seed=$seed must learn from cycle-detection conflicts');
      }
    });

    test('SAT circuit with search learns and returns a Hamiltonian cycle',
        () async {
      const n = 5;
      const forbidden = {'0->1', '1->4', '2->4', '3->4'};
      var anyLearned = false;
      for (var seed = 0; seed < 8; seed++) {
        final r = await _circuit(n, forbidden)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(r, isA<Map<String, dynamic>>(),
            reason: 'seed=$seed must stay SAT despite learning');
        expect(_isHamiltonianCycle(r as Map<String, dynamic>, n), isTrue,
            reason: 'seed=$seed returned a non-cycle');
        if (CSP.lastStats!.learnedClauses > 0) anyLearned = true;
      }
      expect(anyLearned, isTrue,
          reason: 'at least one decision order must exercise learning');
    });
  });

  group('M3g soundness — verdict parity vs full enumeration', () {
    test('random circuits agree with enumeration', () async {
      final rng = Random(20240601);
      var satSeen = 0;
      var unsatSeen = 0;
      var learned = 0;
      for (var t = 0; t < 140; t++) {
        final n = 4 + rng.nextInt(3); // 4..6
        final forbidden = <String>{};
        for (var i = 0; i < n; i++) {
          for (var v = 0; v < n; v++) {
            if (i == v) continue;
            if (rng.nextInt(3) == 0) forbidden.add('$i->$v');
          }
        }

        final all = await _circuit(n, forbidden).getAllSolutions();
        final sat = all.isNotEmpty;
        final unique = all.length == 1;
        final canon =
            unique ? {for (final k in all.first.keys) k: all.first[k]} : null;
        if (sat) {
          satSeen++;
        } else {
          unsatSeen++;
        }

        for (var seed = 0; seed < 4; seed++) {
          final r = await _circuit(n, forbidden)
              .solveWithLcg(useVsids: true, seed: seed);
          if (CSP.lastStats!.learnedClauses > 0) learned++;
          if (sat) {
            expect(r, isA<Map<String, dynamic>>(),
                reason:
                    't=$t seed=$seed must stay SAT n=$n forbidden=$forbidden');
            final m = r as Map<String, dynamic>;
            expect(_isHamiltonianCycle(m, n), isTrue,
                reason: 't=$t seed=$seed returned a non-cycle');
            if (canon != null) {
              for (final k in canon.keys) {
                expect(m[k], canon[k],
                    reason: 't=$t seed=$seed unique cell $k mismatch');
              }
            }
          } else {
            expect(r, 'FAILURE',
                reason:
                    't=$t seed=$seed must stay UNSAT n=$n forbidden=$forbidden');
          }
        }
      }
      expect(satSeen, greaterThan(0));
      expect(unsatSeen, greaterThan(0));
      expect(learned, greaterThan(0),
          reason: 'the sweep must exercise the M3g learning path');
    });
  });
}

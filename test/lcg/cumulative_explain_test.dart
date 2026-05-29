/// LCG M3e tests: `_CumulativePropagator` time-table explanation companion.
///
/// A start value `s` is pruned from task `i` when some time
/// `t ∈ [s, s + dur_i)` is already loaded — by the compulsory parts of
/// *other* tasks — to within less than `dem_i` of the capacity. M3e
/// explains that prune with the contributing tasks' compulsory-part
/// **bounds** (`AtomLe(start_k, lst_k)` / `AtomGe(start_k, est_k)`, plus
/// `AtomEq` for a pinned task), collapsed through one synthetic
/// [AtomInScc] bridge so the first-UIP analyser converges. This is the
/// first consumer of the bound-atom trail emission (the M3e/M3f
/// prerequisite).
///
/// Unlike `regular` (GAC-strong), the time-table propagator is *not* GAC,
/// so even satisfiable instances need real search and learn clauses — a
/// stronger soundness exercise (an unsound learned clause would exclude a
/// real schedule, surfacing as FAILURE-on-SAT or a wrong assignment). The
/// acceptance criterion pairs UNSAT + SAT learning activation with a broad
/// verdict-parity sweep against full enumeration.
library;

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// `n` tasks sharing a resource of [capacity]; each start ranges over
/// `[0, horizon]`. Dispatched entirely through `_CumulativePropagator`.
Problem _rcpsp(
    int n, int horizon, List<int> durs, List<int> dems, int capacity) {
  final p = Problem();
  final starts = [for (var i = 0; i < n; i++) 's$i'];
  for (var i = 0; i < n; i++) {
    p.addVariable(starts[i], [for (var t = 0; t <= horizon; t++) t]);
  }
  p.addCumulative(starts, durs, dems, capacity);
  return p;
}

/// True iff [sol] schedules every task within the resource [capacity] at
/// all times (the cumulative feasibility check).
bool _validSchedule(Map<String, dynamic> sol, int n, List<int> durs,
    List<int> dems, int capacity) {
  final usage = <int, int>{};
  for (var i = 0; i < n; i++) {
    final s = sol['s$i'] as int;
    for (var t = s; t < s + durs[i]; t++) {
      usage[t] = (usage[t] ?? 0) + dems[i];
      if (usage[t]! > capacity) return false;
    }
  }
  return true;
}

void main() {
  group('CumulativeReason', () {
    test('passes its antecedent atoms through unchanged', () {
      const atoms = [AtomGe('s0', 2), AtomInScc('h', 7)];
      const r = CumulativeReason(atoms);
      expect(r.antecedents(), atoms);
      expect(r.toString(), contains('s0 >= 2'));
    });

    test('empty reason has no antecedents', () {
      expect(const CumulativeReason([]).antecedents(), isEmpty);
    });
  });

  group('M3e end-to-end — cumulative learning', () {
    test('UNSAT instance proves UNSAT, is active, and learns', () async {
      // 5 tasks, capacity 2, that cannot be packed into the horizon.
      const n = 5;
      const horizon = 6;
      const durs = [1, 3, 3, 2, 3];
      const dems = [2, 2, 1, 1, 2];
      const cap = 2;
      final plain = await _rcpsp(n, horizon, durs, dems, cap).getSolution();
      expect(plain, 'FAILURE', reason: 'instance must be UNSAT');
      for (var seed = 0; seed < 6; seed++) {
        final lcg = await _rcpsp(n, horizon, durs, dems, cap)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(lcg, 'FAILURE', reason: 'seed=$seed verdict must match plain');
        final st = CSP.lastStats!;
        expect(st.naryRevises, greaterThan(0),
            reason: 'seed=$seed cumulative propagator must prune');
        expect(st.learnedClauses, greaterThanOrEqualTo(1),
            reason: 'seed=$seed must learn from time-table conflicts');
      }
    });

    test('SAT instance with search learns and returns a valid schedule',
        () async {
      // Not GAC, so this satisfiable instance still searches and learns;
      // the unique-up-to-validity check is the real soundness exercise.
      const n = 4;
      const horizon = 4;
      const durs = [3, 3, 3, 1];
      const dems = [1, 1, 2, 3];
      const cap = 3;
      var anyLearned = false;
      for (var seed = 0; seed < 8; seed++) {
        final r = await _rcpsp(n, horizon, durs, dems, cap)
            .solveWithLcg(useVsids: true, seed: seed);
        expect(r, isA<Map<String, dynamic>>(),
            reason: 'seed=$seed must stay SAT despite learning');
        expect(_validSchedule(r as Map<String, dynamic>, n, durs, dems, cap),
            isTrue,
            reason: 'seed=$seed returned an over-capacity schedule');
        if (CSP.lastStats!.learnedClauses > 0) anyLearned = true;
      }
      expect(anyLearned, isTrue,
          reason: 'at least one decision order must exercise learning');
    });
  });

  group('M3e soundness — verdict parity vs full enumeration', () {
    test('random RCPSP instances agree with enumeration', () async {
      final rng = Random(20240530);
      var satSeen = 0;
      var unsatSeen = 0;
      var learned = 0;
      for (var t = 0; t < 120; t++) {
        final n = 3 + rng.nextInt(3); // 3..5
        final horizon = 3 + rng.nextInt(4); // 3..6
        final durs = [for (var i = 0; i < n; i++) 1 + rng.nextInt(3)];
        final cap = 2 + rng.nextInt(2); // 2..3
        final dems = [for (var i = 0; i < n; i++) 1 + rng.nextInt(cap)];

        final all = await _rcpsp(n, horizon, durs, dems, cap).getAllSolutions();
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
          final r = await _rcpsp(n, horizon, durs, dems, cap)
              .solveWithLcg(useVsids: true, seed: seed);
          if (CSP.lastStats!.learnedClauses > 0) learned++;
          if (sat) {
            expect(r, isA<Map<String, dynamic>>(),
                reason: 't=$t seed=$seed must stay SAT '
                    'n=$n h=$horizon durs=$durs dems=$dems cap=$cap');
            final m = r as Map<String, dynamic>;
            expect(_validSchedule(m, n, durs, dems, cap), isTrue,
                reason: 't=$t seed=$seed invalid schedule');
            if (canon != null) {
              for (final k in canon.keys) {
                expect(m[k], canon[k],
                    reason: 't=$t seed=$seed unique cell $k mismatch');
              }
            }
          } else {
            expect(r, 'FAILURE',
                reason: 't=$t seed=$seed must stay UNSAT '
                    'n=$n h=$horizon durs=$durs dems=$dems cap=$cap');
          }
        }
      }
      expect(satSeen, greaterThan(0));
      expect(unsatSeen, greaterThan(0));
      expect(learned, greaterThan(0),
          reason: 'the sweep must exercise the M3e learning path');
    });
  });
}

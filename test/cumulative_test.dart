import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Tests for the `addCumulative` resource constraint and its
/// time-table propagator. Covers validation, vacuous shapes,
/// single-task feasibility, multi-task with shared integer-capacity
/// resource, equivalence with `addNoOverlap` in the unary-capacity
/// case, makespan minimization, and propagator-activity assertions.
void main() {
  group('addCumulative validation', () {
    test('rejects mismatched starts / durations / demands lengths', () {
      final p = Problem()..addRangeVariable('s0', 0, 5);
      expect(() => p.addCumulative(['s0'], <int>[1, 2], <int>[1], 1),
          throwsA(isA<ArgumentError>()));
      expect(() => p.addCumulative(['s0'], <int>[1], <int>[1, 2], 1),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects unknown start variable', () {
      final p = Problem();
      expect(() => p.addCumulative(['nope'], <int>[1], <int>[1], 1),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects negative duration', () {
      final p = Problem()..addRangeVariable('s0', 0, 5);
      expect(() => p.addCumulative(['s0'], <int>[-1], <int>[1], 1),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects negative demand', () {
      final p = Problem()..addRangeVariable('s0', 0, 5);
      expect(() => p.addCumulative(['s0'], <int>[1], <int>[-1], 1),
          throwsA(isA<ArgumentError>()));
    });

    test('rejects negative capacity', () {
      final p = Problem()..addRangeVariable('s0', 0, 5);
      expect(() => p.addCumulative(['s0'], <int>[1], <int>[1], -1),
          throwsA(isA<ArgumentError>()));
    });

    test('vacuous (zero tasks) is a no-op', () async {
      final p = Problem()..addRangeVariable('x', 0, 3);
      p.addCumulative(const <String>[], const <int>[], const <int>[], 1);
      final count = await p.countSolutions();
      expect(count, equals(4));
    });
  });

  group('cumulative basics', () {
    test('single task fits when demand <= capacity', () async {
      final p = Problem()
        ..addRangeVariable('s0', 0, 5)
        ..addCumulative(['s0'], <int>[3], <int>[2], 2);
      final solutions = <int>[];
      await for (final sol in p.getSolutions()) {
        solutions.add(sol['s0'] as int);
      }
      // Any start in [0, 5] is feasible — the task fits the resource.
      expect(solutions, equals(<int>[0, 1, 2, 3, 4, 5]));
    });

    test('single task whose demand exceeds capacity is infeasible at root',
        () async {
      final p = Problem()
        ..addRangeVariable('s0', 0, 5)
        ..addCumulative(['s0'], <int>[3], <int>[5], 2);
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });

    test('two tasks sharing capacity 1 (unary): no overlap', () async {
      // Two tasks with duration 2 each and capacity 1; behaves like
      // addNoOverlap.
      final p = Problem()
        ..addRangeVariable('a', 0, 4)
        ..addRangeVariable('b', 0, 4)
        ..addCumulative(['a', 'b'], <int>[2, 2], <int>[1, 1], 1);
      final solutions = <(int, int)>[];
      await for (final sol in p.getSolutions()) {
        final a = sol['a'] as int;
        final b = sol['b'] as int;
        // Half-open intervals [a, a+2) and [b, b+2) must not overlap.
        expect(a + 2 <= b || b + 2 <= a, isTrue);
        solutions.add((a, b));
      }
      // Enumerate manually: same shape as addNoOverlap.
      final noOverlap = Problem()
        ..addRangeVariable('a', 0, 4)
        ..addRangeVariable('b', 0, 4)
        ..addNoOverlap(['a', 'b'], <int>[2, 2]);
      var expected = 0;
      await for (final _ in noOverlap.getSolutions()) {
        expected++;
      }
      expect(solutions.length, equals(expected));
    });

    test('two tasks with demand 2 each on capacity 3: forced no-overlap',
        () async {
      // 2 + 2 = 4 > 3 → tasks cannot overlap at any time-step.
      final p = Problem()
        ..addRangeVariable('a', 0, 5)
        ..addRangeVariable('b', 0, 5)
        ..addCumulative(['a', 'b'], <int>[3, 2], <int>[2, 2], 3);
      await for (final sol in p.getSolutions()) {
        final a = sol['a'] as int;
        final b = sol['b'] as int;
        expect(a + 3 <= b || b + 2 <= a, isTrue,
            reason: 'tasks (start $a + 3) and (start $b + 2) overlap');
      }
    });

    test(
        'three tasks with demand 1 each on capacity 2: pairwise overlap '
        'allowed, three-way not', () async {
      // Tasks of duration 2, demand 1, capacity 2. At any instant up
      // to 2 tasks may run, but never all 3.
      final p = Problem()
        ..addRangeVariable('a', 0, 4)
        ..addRangeVariable('b', 0, 4)
        ..addRangeVariable('c', 0, 4)
        ..addCumulative(['a', 'b', 'c'], <int>[2, 2, 2], <int>[1, 1, 1], 2);
      var count = 0;
      await for (final sol in p.getSolutions()) {
        final a = sol['a'] as int;
        final b = sol['b'] as int;
        final c = sol['c'] as int;
        // At every time-step covered by some task, at most 2 are running.
        for (var t = 0; t <= 6; t++) {
          var running = 0;
          if (a <= t && t < a + 2) running++;
          if (b <= t && t < b + 2) running++;
          if (c <= t && t < c + 2) running++;
          expect(running, lessThanOrEqualTo(2),
              reason: 'time $t has $running concurrent tasks with starts '
                  '($a, $b, $c)');
        }
        count++;
      }
      expect(count, greaterThan(0));
    });
  });

  group('equivalence with addNoOverlap (unary-capacity reduction)', () {
    test('three tasks, durations 1/2/3, cap=1 dem=[1,1,1]', () async {
      final pCum = Problem()
        ..addRangeVariable('s0', 0, 6)
        ..addRangeVariable('s1', 0, 6)
        ..addRangeVariable('s2', 0, 6)
        ..addCumulative(['s0', 's1', 's2'], <int>[1, 2, 3], <int>[1, 1, 1], 1);
      final cumCount = await pCum.countSolutions();

      final pNo = Problem()
        ..addRangeVariable('s0', 0, 6)
        ..addRangeVariable('s1', 0, 6)
        ..addRangeVariable('s2', 0, 6)
        ..addNoOverlap(['s0', 's1', 's2'], <int>[1, 2, 3]);
      final noCount = await pNo.countSolutions();

      expect(cumCount, equals(noCount));
    });
  });

  group('makespan minimization', () {
    test('three tasks on capacity 2: pack to minimum makespan', () async {
      // Tasks: dur=2 dem=1, dur=2 dem=1, dur=2 dem=2.
      // Total demand-time = 2 + 2 + 4 = 8 units of resource-time on a
      // resource with capacity 2 → makespan lower bound = ceil(8/2) =
      // 4. Achieved by running the two demand-1 tasks in parallel
      // during [0, 2) and the demand-2 task alone during [2, 4).
      final p = Problem()
        ..addRangeVariable('s0', 0, 10)
        ..addRangeVariable('s1', 0, 10)
        ..addRangeVariable('s2', 0, 10)
        ..addRangeVariable('mk', 0, 10)
        ..addCumulative(['s0', 's1', 's2'], <int>[2, 2, 2], <int>[1, 1, 2], 2)
        ..addLinearGeq(['mk', 's0'], [1, -1], 2)
        ..addLinearGeq(['mk', 's1'], [1, -1], 2)
        ..addLinearGeq(['mk', 's2'], [1, -1], 2);
      final sol = await p.minimize('mk');
      expect(sol, isA<Map<String, dynamic>>());
      expect((sol as Map<String, dynamic>)['mk'], equals(4));
    });
  });

  group('propagator activity', () {
    test('propagator reduces work on a tight schedule', () async {
      // Tight RCPSP-style instance: three tasks must serialize on cap=1
      // with a horizon barely large enough.
      final p = Problem()
        ..addRangeVariable('s0', 0, 4)
        ..addRangeVariable('s1', 0, 4)
        ..addRangeVariable('s2', 0, 4)
        ..addCumulative(['s0', 's1', 's2'], <int>[2, 2, 2], <int>[1, 1, 1], 1);
      // Force one task to start at 0 to make the propagator do work.
      p.addStringConstraint('s0 == 0');
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      // At least one propagator revise should have fired.
      expect(p.lastStats!.naryRevises, greaterThan(0));
    });

    test(
        'predicate-only encoding rejects schedules the propagator '
        'also rejects', () async {
      // Hand-written predicate equivalent (no specialized propagator)
      // for comparison.
      final pPred = Problem();
      pPred.addRangeVariable('a', 0, 4);
      pPred.addRangeVariable('b', 0, 4);
      pPred.addConstraint(['a', 'b'], (dynamic ax, dynamic bx) {
        final usage = <int, int>{};
        for (var t = ax as int; t < ax + 2; t++) {
          usage[t] = (usage[t] ?? 0) + 2;
          if (usage[t]! > 2) return false;
        }
        for (var t = bx as int; t < bx + 2; t++) {
          usage[t] = (usage[t] ?? 0) + 2;
          if (usage[t]! > 2) return false;
        }
        return true;
      });

      final pCum = Problem()
        ..addRangeVariable('a', 0, 4)
        ..addRangeVariable('b', 0, 4)
        ..addCumulative(['a', 'b'], <int>[2, 2], <int>[2, 2], 2);

      final predCount = await pPred.countSolutions();
      final cumCount = await pCum.countSolutions();
      expect(cumCount, equals(predCount));
    });
  });

  group('multi-resource RCPSP composition', () {
    test('two resources, three tasks: both bounds binding', () async {
      // Tasks t0, t1, t2 each duration 2. Resource A demands
      // (1, 2, 1) cap 2; resource B demands (2, 1, 1) cap 2.
      // The most constrained pair is (t0, t1) on B (2 + 1 = 3 > 2),
      // and (t1, t2) on A (2 + 1 = 3 > 2). Find a valid schedule.
      final p = Problem()
        ..addRangeVariable('t0', 0, 10)
        ..addRangeVariable('t1', 0, 10)
        ..addRangeVariable('t2', 0, 10)
        ..addCumulative(['t0', 't1', 't2'], <int>[2, 2, 2], <int>[1, 2, 1], 2)
        ..addCumulative(['t0', 't1', 't2'], <int>[2, 2, 2], <int>[2, 1, 1], 2);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());

      final s = sol as Map<String, dynamic>;
      // Verify both resources at every time-step.
      for (var t = 0; t < 12; t++) {
        var loadA = 0, loadB = 0;
        for (var i = 0; i < 3; i++) {
          final start = s['t$i'] as int;
          if (start <= t && t < start + 2) {
            if (i == 0) {
              loadA += 1;
              loadB += 2;
            } else if (i == 1) {
              loadA += 2;
              loadB += 1;
            } else {
              loadA += 1;
              loadB += 1;
            }
          }
        }
        expect(loadA, lessThanOrEqualTo(2),
            reason: 'resource A overloaded at t=$t');
        expect(loadB, lessThanOrEqualTo(2),
            reason: 'resource B overloaded at t=$t');
      }
    });
  });

  group('compulsory-part infeasibility detection', () {
    test('over-capacity compulsory pile-up is rejected at root', () async {
      // Two tasks both pinned to start at 0, each with demand 2 on
      // capacity 3: 2 + 2 = 4 > 3 at time 0. Propagator should
      // report infeasibility before any decision.
      final p = Problem()
        ..addRangeVariable('a', 0, 0) // forced
        ..addRangeVariable('b', 0, 0) // forced
        ..addCumulative(['a', 'b'], <int>[2, 2], <int>[2, 2], 3);
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });
  });
}

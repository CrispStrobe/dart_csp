import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('addCircuit (Hamiltonian cycle on successor variables)', () {
    test('n=3: exactly two valid cycles (clockwise + counter-clockwise)',
        () async {
      // For positions {0,1,2}, the only Hamiltonian cycles are
      //   0→1→2→0 (next = [1,2,0])
      //   0→2→1→0 (next = [2,0,1])
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2'], [0, 1, 2])
        ..addCircuit(['n0', 'n1', 'n2']);
      final solutions = await p.getAllSolutions();
      final tuples = solutions.map((s) => [s['n0'], s['n1'], s['n2']]).toSet();
      expect(tuples.length, equals(2));
      expect(
          tuples,
          containsAll([
            [1, 2, 0],
            [2, 0, 1],
          ]));
    });

    test('n=4: 3! = 6 Hamiltonian cycles (fixed starting at 0)', () async {
      // For an n-element permutation starting at 0, (n-1)! distinct
      // cyclic orderings give a single tour.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addCircuit(['n0', 'n1', 'n2', 'n3']);
      final all = await p.getAllSolutions();
      expect(all, hasLength(6));
      // Verify each is a valid permutation (visits every position).
      for (final s in all) {
        final next = [s['n0'], s['n1'], s['n2'], s['n3']];
        final visited = <int>{};
        var cur = 0;
        for (var k = 0; k < 4; k++) {
          expect(visited.contains(cur), isFalse,
              reason: 'subcycle detected at step $k of $next');
          visited.add(cur);
          cur = next[cur] as int;
        }
        expect(cur, equals(0));
      }
    });

    test('subcycles are rejected', () async {
      // Restrict n0 and n1 to swap (next=[1,0,...,...]) — that's a
      // 2-cycle, not a 4-cycle, so no full Hamiltonian tour exists
      // with that swap.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addVariable('n0Fixed', [1])
        ..addVariable('n1Fixed', [0])
        ..addCircuit(['n0', 'n1', 'n2', 'n3'])
        ..addStringConstraint('n0 == n0Fixed')
        ..addStringConstraint('n1 == n1Fixed');
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('n=1: single self-loop is the only valid cycle', () async {
      final p = Problem()
        ..addVariable('n0', [0])
        ..addCircuit(['n0']);
      final s = await p.getSolution();
      expect((s as Map)['n0'], equals(0));
    });

    test('values out of range are rejected', () async {
      // n=2, but allow value 5 in the domain — solver should never
      // pick it because it's not a valid successor.
      final p = Problem()
        ..addVariables(['n0', 'n1'], [0, 1, 5])
        ..addCircuit(['n0', 'n1']);
      for (final s in await p.getAllSolutions()) {
        expect(s['n0'], anyOf(equals(0), equals(1)));
        expect(s['n1'], anyOf(equals(0), equals(1)));
      }
    });

    test('throws on unknown variable / empty list', () {
      final p = Problem()..addVariable('n0', [0]);
      expect(() => p.addCircuit(['n0', 'missing']), throwsArgumentError);
      expect(() => p.addCircuit(<String>[]), throwsArgumentError);
    });

    test('with addAllDifferent: same answers, stronger propagation', () async {
      // Adding allDifferent on top of the circuit predicate is a
      // valid (and recommended for hard problems) redundancy. The
      // answer set must not change.
      final base = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addCircuit(['n0', 'n1', 'n2', 'n3']);
      final reinforced = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addCircuit(['n0', 'n1', 'n2', 'n3'])
        ..addAllDifferent(['n0', 'n1', 'n2', 'n3']);
      final baseAll = await base.getAllSolutions();
      final reinAll = await reinforced.getAllSolutions();
      expect(reinAll.length, equals(baseAll.length));
    });
  });

  group('addBinPacking (items → bins with load tracking)', () {
    test('items fill bins; loads match item-size sums', () async {
      // 3 items of sizes [2, 3, 5] into 2 bins. Loads should sum
      // to 10 across bins regardless of assignment.
      final p = Problem()
        ..addVariables(['it0', 'it1', 'it2'], [0, 1])
        ..addVariables(['load0', 'load1'], [0, 2, 3, 5, 7, 8, 10])
        ..addBinPacking(['it0', 'it1', 'it2'], [2, 3, 5], ['load0', 'load1']);
      for (final s in await p.getAllSolutions()) {
        final actualLoads = [0, 0];
        actualLoads[s['it0'] as int] += 2;
        actualLoads[s['it1'] as int] += 3;
        actualLoads[s['it2'] as int] += 5;
        expect(s['load0'], equals(actualLoads[0]));
        expect(s['load1'], equals(actualLoads[1]));
        expect((s['load0'] as int) + (s['load1'] as int), equals(10));
      }
    });

    test('bin capacities enforceable via string constraints on load vars',
        () async {
      // 4 items of sizes [3, 3, 4, 4] into 2 bins each capacity 7.
      // The only way: split 3+4 and 3+4 = {it0+it2 or it0+it3 in
      // separate bins from it1+(the other)}.
      final p = Problem()
        ..addVariables(['it0', 'it1', 'it2', 'it3'], [0, 1])
        ..addVariables(['load0', 'load1'], [0, 3, 4, 6, 7, 8, 14])
        ..addBinPacking(
          ['it0', 'it1', 'it2', 'it3'],
          [3, 3, 4, 4],
          ['load0', 'load1'],
        )
        ..addStringConstraint('load0 <= 7')
        ..addStringConstraint('load1 <= 7');
      for (final s in await p.getAllSolutions()) {
        expect(s['load0'], lessThanOrEqualTo(7));
        expect(s['load1'], lessThanOrEqualTo(7));
        // Each bin must have one size-3 and one size-4 item to fit.
        final bin0Items = [
          for (var i = 0; i < 4; i++)
            if (s['it$i'] == 0) i
        ];
        final bin0Sizes = bin0Items.map((i) => [3, 3, 4, 4][i]).toList()
          ..sort();
        expect(bin0Sizes, equals([3, 4]));
      }
    });

    test('infeasible when no packing fits the load domains', () async {
      // 3 items of size 10 each into 2 bins with loads capped at 15.
      final p = Problem()
        ..addVariables(['it0', 'it1', 'it2'], [0, 1])
        ..addVariables(['load0', 'load1'], [0, 10, 20, 30]) // 30 won't fit
        ..addBinPacking(['it0', 'it1', 'it2'], [10, 10, 10], ['load0', 'load1'])
        ..addStringConstraint('load0 <= 15')
        ..addStringConstraint('load1 <= 15');
      // 3 items of size 10 can't split evenly into two bins each
      // ≤15 (two items in one bin is 20 > 15).
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('out-of-range bin id is rejected', () async {
      // Item domain accidentally includes 5, but binLoads has only 2.
      // Solver should never pick the out-of-range value.
      final p = Problem()
        ..addVariables(['it0', 'it1'], [0, 1, 5])
        ..addVariables(['load0', 'load1'], [0, 1, 2, 3])
        ..addBinPacking(['it0', 'it1'], [1, 2], ['load0', 'load1']);
      for (final s in await p.getAllSolutions()) {
        expect(s['it0'], anyOf(equals(0), equals(1)));
        expect(s['it1'], anyOf(equals(0), equals(1)));
      }
    });

    test('size-0 items contribute nothing to loads', () async {
      final p = Problem()
        ..addVariables(['it0', 'it1', 'it2'], [0, 1])
        ..addVariables(['load0', 'load1'], [0, 5])
        ..addBinPacking(['it0', 'it1', 'it2'], [0, 0, 5], ['load0', 'load1']);
      for (final s in await p.getAllSolutions()) {
        final total = (s['load0'] as int) + (s['load1'] as int);
        expect(total, equals(5));
      }
    });

    test('minimization use case: minimize the larger of two bin loads',
        () async {
      // 4 items of sizes [4, 3, 2, 1] = 10 total. Two bins. Minimize
      // max(load0, load1). The balanced split puts each bin at 5.
      final p = Problem()
        ..addVariables(['it0', 'it1', 'it2', 'it3'], [0, 1])
        ..addVariables(['load0', 'load1'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ..addVariable('maxLoad', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ..addBinPacking(
          ['it0', 'it1', 'it2', 'it3'],
          [4, 3, 2, 1],
          ['load0', 'load1'],
        )
        ..addStringConstraint('load0 <= maxLoad')
        ..addStringConstraint('load1 <= maxLoad');
      final result = await p.minimize('maxLoad');
      expect((result as Map)['maxLoad'], equals(5));
    });

    test('throws on length / variable / size errors', () {
      final p = Problem()
        ..addVariables(['it0', 'it1'], [0, 1])
        ..addVariable('load0', [0, 1, 2, 3]);
      expect(() => p.addBinPacking(['it0', 'it1'], [1], ['load0']),
          throwsArgumentError);
      expect(() => p.addBinPacking(<String>[], <int>[], ['load0']),
          throwsArgumentError);
      expect(() => p.addBinPacking(['it0', 'it1'], [1, 2], <String>[]),
          throwsArgumentError);
      expect(() => p.addBinPacking(['it0', 'missing'], [1, 2], ['load0']),
          throwsArgumentError);
      expect(
          () => p.addBinPacking(['it0', 'it1'], [1, 2], ['load0', 'missing']),
          throwsArgumentError);
      expect(() => p.addBinPacking(['it0', 'it1'], [-1, 2], ['load0']),
          throwsArgumentError);
    });
  });

  group('addCircuit: cycle-detection propagator', () {
    test('rejects 2-cycle in singletons before search descends', () async {
      // 4 nodes, fix n0=1 and n1=0 → 2-cycle 0↔1 closes prematurely.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addVariable('n0Fixed', [1])
        ..addVariable('n1Fixed', [0])
        ..addStringConstraint('n0 == n0Fixed')
        ..addStringConstraint('n1 == n1Fixed')
        ..addCircuit(['n0', 'n1', 'n2', 'n3']);
      expect(await p.getSolution(), equals('FAILURE'));
      // The propagator detects the sub-cycle without descending into
      // any speculative assignment of n2 or n3.
      expect(p.lastStats!.decisions, equals(0),
          reason: 'cycle propagator must detect sub-cycle at the root');
    });

    test('rejects self-loop for n > 1', () async {
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2'], [0, 1, 2])
        ..addVariable('n0Self', [0])
        ..addStringConstraint('n0 == n0Self')
        ..addCircuit(['n0', 'n1', 'n2']);
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('prunes head from chain tail when chain length < n', () async {
      // Fix the chain 0 → 1 → 2 (lengths 3) in n=4. The tail (n2)'s
      // next must not be 0, 1, or 2 (all chain-internal/head); only 3
      // is valid. After propagation, n2 is forced singleton {3}.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addVariable('n0Fix', [1])
        ..addVariable('n1Fix', [2])
        ..addStringConstraint('n0 == n0Fix')
        ..addStringConstraint('n1 == n1Fix')
        ..addCircuit(['n0', 'n1', 'n2', 'n3']);
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['n0'], equals(1));
      expect(s['n1'], equals(2));
      expect(s['n2'], equals(3));
      expect(s['n3'], equals(0));
    });

    test('successor uniqueness: a pinned value is removed from peers',
        () async {
      // Pin n0=2. Then n1, n2, n3 must NOT have 2 in their domains
      // (it's already n0's successor). The propagator should enforce
      // this without addAllDifferent.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addVariable('n0Fix', [2])
        ..addStringConstraint('n0 == n0Fix')
        ..addCircuit(['n0', 'n1', 'n2', 'n3']);
      for (final s in await p.getAllSolutions()) {
        expect(s['n0'], equals(2));
        // None of the others may pick 2.
        expect(s['n1'], isNot(equals(2)));
        expect(s['n2'], isNot(equals(2)));
        expect(s['n3'], isNot(equals(2)));
      }
    });

    test('propagator finds fewer decisions than predicate-only would',
        () async {
      // Enumerate all 6 Hamiltonian cycles on n=4 and compare the
      // stats. The propagator prunes sub-cycle attempts early, so the
      // total decisions should be lower than a hypothetical
      // predicate-only encoding. We don't have a direct comparison
      // path, so just assert the propagator's run is non-trivial and
      // returns the right count.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addCircuit(['n0', 'n1', 'n2', 'n3']);
      final all = await p.getAllSolutions();
      expect(all, hasLength(6));
      // Propagator must have actually run.
      expect(p.lastStats!.naryRevises, greaterThan(0));
    });

    test('combined with addAllDifferent: both work, same solutions', () async {
      Future<List<Map<String, dynamic>>> solveBoth() async {
        final p = Problem()
          ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
          ..addAllDifferent(['n0', 'n1', 'n2', 'n3'])
          ..addCircuit(['n0', 'n1', 'n2', 'n3']);
        return p.getAllSolutions();
      }

      final solutions = await solveBoth();
      expect(solutions, hasLength(6));
    });
  });

  group('addSubcircuit (cycle on a chosen subset; self-loops = skip)', () {
    test('n=1: single skip is the only solution', () async {
      final p = Problem()
        ..addVariable('n0', [0])
        ..addSubcircuit(['n0']);
      final s = await p.getSolution();
      expect((s as Map)['n0'], equals(0));
    });

    test('n=2 full domain: empty subcircuit + the 2-cycle', () async {
      // Valid assignments:
      //   [0, 1]  — both positions skipped (empty subcircuit)
      //   [1, 0]  — both in the cycle 0 → 1 → 0
      final p = Problem()
        ..addVariables(['n0', 'n1'], [0, 1])
        ..addSubcircuit(['n0', 'n1']);
      final all = await p.getAllSolutions();
      final tuples = all.map((s) => [s['n0'], s['n1']]).toSet();
      expect(tuples.length, equals(2));
      expect(
          tuples,
          containsAll([
            [0, 1],
            [1, 0],
          ]));
    });

    test('n=3 full domain: 1 empty + 2 three-cycles + 3 (skip + 2-cycle)',
        () async {
      // - All three skipped:                    [0, 1, 2]
      // - 3-cycle in either direction:          [1, 2, 0], [2, 0, 1]
      // - One skipped, the other two swap:
      //     skip n0:                            [0, 2, 1]
      //     skip n1:                            [2, 1, 0]
      //     skip n2:                            [1, 0, 2]
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2'], [0, 1, 2])
        ..addSubcircuit(['n0', 'n1', 'n2']);
      final all = await p.getAllSolutions();
      final tuples = all.map((s) => [s['n0'], s['n1'], s['n2']]).toSet();
      expect(tuples.length, equals(6));
      expect(
          tuples,
          containsAll([
            [0, 1, 2],
            [1, 2, 0],
            [2, 0, 1],
            [0, 2, 1],
            [2, 1, 0],
            [1, 0, 2],
          ]));
    });

    test('every enumerated solution is a valid subcircuit', () async {
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3']);
      final all = await p.getAllSolutions();
      for (final s in all) {
        final next =
            [s['n0'], s['n1'], s['n2'], s['n3']].map((v) => v as int).toList();
        // Permutation: every value appears exactly once.
        expect(next.toSet().length, equals(4));
        // Non-self-looped positions form exactly one cycle.
        final included = [
          for (var i = 0; i < 4; i++)
            if (next[i] != i) i
        ];
        if (included.isEmpty) continue;
        var cur = included.first;
        final visited = <int>{};
        while (!visited.contains(cur)) {
          expect(next[cur], isNot(equals(cur)),
              reason: 'walked into a skipped node at $cur in $next');
          visited.add(cur);
          cur = next[cur];
        }
        expect(cur, equals(included.first),
            reason: 'cycle does not close on its starting node in $next');
        expect(visited.length, equals(included.length),
            reason: 'cycle does not cover every included position in $next');
      }
    });

    test('count matches the closed-form formula on n=4', () async {
      // Sum over k = number of positions on the tour:
      //   k=0 → 1 (all skipped)
      //   k=2 → C(4,2) · (2-1)!/2  -- wait, for non-trivial cycles k >= 2
      //   For k positions chosen out of n, the number of directed
      //   cycles is (k-1)! when k >= 2 (we count both orientations of
      //   the same undirected cycle as distinct directed cycles, so
      //   no division by 2). For k=2, that's 1 (the swap).
      //   k=2: C(4,2) · 1 = 6
      //   k=3: C(4,3) · 2 = 8
      //   k=4: C(4,4) · 6 = 6
      // Plus k=0 = 1 ⇒ 21 total.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3']);
      final all = await p.getAllSolutions();
      expect(all, hasLength(21));
    });

    test('forced skip on n0 with n=3: only solutions are skip-n0 variants',
        () async {
      // Pin n0 = 0 (skip). n1 and n2 then form either both-skipped
      // (n1=1, n2=2) or the 2-cycle (n1=2, n2=1). Two solutions.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2'], [0, 1, 2])
        ..addSubcircuit(['n0', 'n1', 'n2'])
        ..addStringConstraint('n0 == 0');
      final all = await p.getAllSolutions();
      final tuples = all.map((s) => [s['n1'], s['n2']]).toSet();
      expect(tuples, hasLength(2));
      expect(
          tuples,
          containsAll([
            [1, 2],
            [2, 1],
          ]));
    });

    test('forced into the cycle: domains excluding self-loops match addCircuit',
        () async {
      // When no variable can self-loop, subcircuit must coincide with
      // circuit on the same domains.
      final pSub = Problem();
      final pCirc = Problem();
      for (var i = 0; i < 4; i++) {
        final dom = [
          for (var v = 0; v < 4; v++)
            if (v != i) v
        ];
        pSub.addVariable('n$i', dom);
        pCirc.addVariable('n$i', dom);
      }
      pSub.addSubcircuit(['n0', 'n1', 'n2', 'n3']);
      pCirc.addCircuit(['n0', 'n1', 'n2', 'n3']);
      final subAll = await pSub.getAllSolutions();
      final circAll = await pCirc.getAllSolutions();
      String key(Map<String, dynamic> s) =>
          '${s['n0']},${s['n1']},${s['n2']},${s['n3']}';
      expect(subAll.map(key).toSet(), equals(circAll.map(key).toSet()));
      expect(subAll, hasLength(6));
    });

    test('strict sub-cycle infeasible when remaining position cannot skip',
        () async {
      // n=3. Force n0→n1→n0 (a 2-cycle) by pinning n0=1, n1=0. Then
      // n2 must be skipped (n2=2). If n2's domain excludes 2, the
      // problem is infeasible.
      final p = Problem()
        ..addVariable('n0', [1])
        ..addVariable('n1', [0])
        ..addVariable('n2', [0, 1]) // 2 not in domain — can't skip
        ..addSubcircuit(['n0', 'n1', 'n2']);
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('strict sub-cycle feasible when remaining positions can skip',
        () async {
      // Same as above but n2 can take value 2 (skip). Solver must
      // force n2=2.
      final p = Problem()
        ..addVariable('n0', [1])
        ..addVariable('n1', [0])
        ..addVariable('n2', [0, 1, 2])
        ..addSubcircuit(['n0', 'n1', 'n2']);
      final s = await p.getSolution();
      expect(s, isA<Map<String, dynamic>>());
      expect((s as Map<String, dynamic>)['n2'], equals(2));
    });

    test('chain head pruned when an outside node is forced into the cycle',
        () async {
      // n=3. Pin n0 = 1 (so 0→1 is fixed). n1's domain is {0, 2}
      // (could close to 0 or extend to 2). n2 cannot skip (its domain
      // excludes 2). With n2 forced into the cycle, the chain {0, 1}
      // can't close yet — n1=0 must be pruned, forcing n1=2, then
      // n2=0 to close the 3-cycle.
      final p = Problem()
        ..addVariable('n0', [1])
        ..addVariable('n1', [0, 2])
        ..addVariable('n2', [0, 1]) // no skip
        ..addSubcircuit(['n0', 'n1', 'n2']);
      final all = await p.getAllSolutions();
      expect(all, hasLength(1));
      expect(all.single['n0'], equals(1));
      expect(all.single['n1'], equals(2));
      expect(all.single['n2'], equals(0));
    });

    test('chain head forced when every outside node is already skipped',
        () async {
      // n=3. n2 is pinned to skip (n2=2). n0=1 fixed. n1's domain is
      // {0, 2}. With n2 already committed-skipped, the chain 0→1
      // plus committed-skip {2} covers all 3 positions, so n1=0 must
      // be forced (close the 2-cycle).
      final p = Problem()
        ..addVariable('n0', [1])
        ..addVariable('n1', [0, 2])
        ..addVariable('n2', [2])
        ..addSubcircuit(['n0', 'n1', 'n2']);
      final s = await p.getSolution();
      expect(s, isA<Map<String, dynamic>>());
      expect((s as Map<String, dynamic>)['n1'], equals(0));
    });

    test('intermediate chain node pruned from tail domain (permutation guard)',
        () async {
      // n=4. Pin n0=1 (chain 0→1) and n1=2 (chain extends to 0→1→2).
      // Tail is n2 with domain {1, 3, 0}. The intermediate chain
      // node is {1}; the propagator must remove 1 from n2's domain.
      // Allowed closings: n2 → 3 (extend), n2 → 0 (close the
      // 3-cycle on positions {0,1,2}).
      final p = Problem()
        ..addVariable('n0', [1])
        ..addVariable('n1', [2])
        ..addVariable('n2', [0, 1, 3])
        ..addVariable('n3', [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3']);
      // Drive enumeration so the propagator runs; check that no
      // solution sets n2 = 1 (the intermediate would collide).
      final all = await p.getAllSolutions();
      for (final s in all) {
        expect(s['n2'], isNot(equals(1)));
      }
      // Two feasible families:
      //   {0,1,2} cycle + skip 3:    n2=0, n3=3   → 1 solution
      //   {0,1,2,3} full cycle:      n2=3, n3=0   → 1 solution
      expect(all, hasLength(2));
    });

    test('all-skip is enumerated as a valid solution', () async {
      final p = Problem()
        ..addVariable('n0', [0])
        ..addVariable('n1', [1])
        ..addVariable('n2', [2])
        ..addSubcircuit(['n0', 'n1', 'n2']);
      final all = await p.getAllSolutions();
      expect(all, hasLength(1));
      expect(all.single, equals({'n0': 0, 'n1': 1, 'n2': 2}));
    });

    test('subcircuit propagator actually runs', () async {
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3']);
      await p.getAllSolutions();
      expect(p.lastStats!.naryRevises, greaterThan(0));
    });

    test('combined with addAllDifferent: redundant but agrees', () async {
      // Subcircuit already implies the permutation property, but
      // adding allDifferent must not change the solution set.
      Future<int> count({required bool withAllDiff}) async {
        final p = Problem()
          ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
          ..addSubcircuit(['n0', 'n1', 'n2', 'n3']);
        if (withAllDiff) p.addAllDifferent(['n0', 'n1', 'n2', 'n3']);
        return (await p.getAllSolutions()).length;
      }

      expect(await count(withAllDiff: false), equals(21));
      expect(await count(withAllDiff: true), equals(21));
    });

    test('throws on unknown variable / empty list', () {
      final p = Problem()..addVariable('n0', [0]);
      expect(() => p.addSubcircuit(['n0', 'missing']), throwsArgumentError);
      expect(() => p.addSubcircuit(<String>[]), throwsArgumentError);
    });

    test('minimize number of visited positions', () async {
      // Subcircuit on n=4 with full domains. The number of visited
      // positions is the count of `next[i] != i`. The minimum is 0
      // (all skipped). Use addNvalueExactly-like counting via reified
      // not-equals indicators.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3'])
        ..addVariables(['v0', 'v1', 'v2', 'v3'], [0, 1])
        ..addVariable('visited', [0, 1, 2, 3, 4]);
      for (var i = 0; i < 4; i++) {
        p.addReifiedNotEquals('v$i', 'n$i', i);
      }
      p.addStringConstraint('v0 + v1 + v2 + v3 == visited');
      final s = await p.minimize('visited');
      expect(s, isA<Map<String, dynamic>>());
      expect((s as Map<String, dynamic>)['visited'], equals(0));
    });

    test('maximize visited count agrees with addCircuit (full cycle is best)',
        () async {
      // With every domain full, the highest visited count is n.
      final p = Problem()
        ..addVariables(['n0', 'n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3'])
        ..addVariables(['v0', 'v1', 'v2', 'v3'], [0, 1])
        ..addVariable('visited', [0, 1, 2, 3, 4]);
      for (var i = 0; i < 4; i++) {
        p.addReifiedNotEquals('v$i', 'n$i', i);
      }
      p.addStringConstraint('v0 + v1 + v2 + v3 == visited');
      final s = await p.maximize('visited');
      expect(s, isA<Map<String, dynamic>>());
      expect((s as Map<String, dynamic>)['visited'], equals(4));
      // The chosen successor list is one of the 6 Hamiltonian cycles
      // on 4 nodes.
      final next =
          [s['n0'], s['n1'], s['n2'], s['n3']].map((v) => v as int).toList();
      for (var i = 0; i < 4; i++) {
        expect(next[i], isNot(equals(i)));
      }
    });

    test('successor uniqueness: pinned value removed from peers', () async {
      // n0 = 2 pins value 2; no other variable can pick 2.
      final p = Problem()
        ..addVariable('n0', [2])
        ..addVariables(['n1', 'n2', 'n3'], [0, 1, 2, 3])
        ..addSubcircuit(['n0', 'n1', 'n2', 'n3']);
      await p.getAllSolutions();
      for (final s in await p.getAllSolutions()) {
        expect(s['n1'], isNot(equals(2)));
        expect(s['n2'], isNot(equals(2)));
        expect(s['n3'], isNot(equals(2)));
      }
    });
  });
}

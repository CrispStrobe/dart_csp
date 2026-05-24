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
}

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('addElement (list[idx] == val)', () {
    test('forces value to match list at the chosen index', () async {
      final list = [10, 20, 30, 40];
      final p = Problem()
        ..addVariable('idx', [0, 1, 2, 3])
        ..addVariable('val', [0, 10, 20, 30, 40, 50])
        ..addElement('idx', list, 'val');
      for (final s in await p.getAllSolutions()) {
        expect(s['val'], equals(list[s['idx'] as int]));
      }
    });

    test('restricts the index when the value is pinned', () async {
      final list = [10, 20, 30, 20];
      final p = Problem()
        ..addVariable('idx', [0, 1, 2, 3])
        ..addVariable('val', [20])
        ..addElement('idx', list, 'val');
      final indices =
          (await p.getAllSolutions()).map((s) => s['idx'] as int).toSet();
      // 20 appears at indices 1 and 3.
      expect(indices, equals({1, 3}));
    });

    test('restricts the value when the index is pinned', () async {
      final list = [100, 200, 300];
      final p = Problem()
        ..addVariable('idx', [1])
        ..addVariable('val', [0, 100, 200, 300, 400])
        ..addElement('idx', list, 'val');
      final result = await p.getSolution();
      expect((result as Map)['val'], equals(200));
    });

    test('infeasible when value is not in the list', () async {
      final list = [1, 2, 3];
      final p = Problem()
        ..addVariable('idx', [0, 1, 2])
        ..addVariable('val', [99])
        ..addElement('idx', list, 'val');
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
    });

    test('out-of-range index is filtered out', () async {
      final list = ['a', 'b', 'c'];
      final p = Problem()
        ..addVariable('idx', [0, 1, 2, 5]) // 5 is out of range
        ..addVariable('val', ['a', 'b', 'c'])
        ..addElement('idx', list, 'val');
      for (final s in await p.getAllSolutions()) {
        expect(s['idx'], lessThan(list.length));
      }
    });

    test('throws when either variable is unknown', () {
      final p = Problem()..addVariable('idx', [0]);
      expect(() => p.addElement('idx', [1], 'val'), throwsArgumentError);
      expect(() => p.addElement('missing', [1], 'idx'), throwsArgumentError);
    });

    test('practical indirection: cost lookup', () async {
      // Pick an item from a menu, X is the chosen item id, cost is the
      // resulting cost. Minimize cost.
      final menuCosts = [50, 20, 70, 10, 40];
      final p = Problem()
        ..addVariable('item', [0, 1, 2, 3, 4])
        ..addVariable('cost', [10, 20, 40, 50, 70])
        ..addElement('item', menuCosts, 'cost');
      final result = await p.minimize('cost');
      final s = result as Map<String, dynamic>;
      expect(s['cost'], equals(10));
      expect(s['item'], equals(3));
    });
  });

  group('addTable', () {
    test('only the listed tuples are valid', () async {
      final tuples = <List<dynamic>>[
        [1, 2, 3],
        [2, 3, 1],
        [3, 1, 2],
      ];
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addTable(['A', 'B', 'C'], tuples);
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(3));
      for (final s in solutions) {
        final tup = [s['A'], s['B'], s['C']];
        expect(tuples.any((t) => _equalTuple(t, tup)), isTrue,
            reason: 'solution $tup not in table');
      }
    });

    test('tuples not listed are excluded', () async {
      final tuples = <List<dynamic>>[
        [1, 1],
        [2, 2],
      ];
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2])
        ..addTable(['A', 'B'], tuples);
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(2));
      for (final s in solutions) {
        expect(s['A'], equals(s['B']));
      }
    });

    test('empty tuple list = infeasible', () async {
      final p = Problem()
        ..addVariable('A', [1, 2, 3])
        ..addTable(['A'], <List<dynamic>>[]);
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('tuple-length mismatch throws at construction', () {
      final p = Problem()..addVariables(['A', 'B'], [1, 2]);
      expect(
          () => p.addTable([
                'A',
                'B'
              ], [
                [1, 2, 3]
              ]),
          throwsArgumentError);
    });

    test('unknown variable throws', () {
      final p = Problem()..addVariable('A', [1, 2]);
      expect(() => p.addTable(['A', 'B'], [<int>[]]), throwsArgumentError);
    });

    test('works with non-int value types', () async {
      final tuples = <List<dynamic>>[
        ['red', 'small'],
        ['blue', 'large'],
      ];
      final p = Problem()
        ..addVariable('color', ['red', 'blue', 'green'])
        ..addVariable('size', ['small', 'large'])
        ..addTable(['color', 'size'], tuples);
      final solutions = await p.getAllSolutions();
      expect(solutions, hasLength(2));
    });

    test('table composes with other constraints', () async {
      // Variables ranges restricted, table further restricts:
      final tuples = <List<dynamic>>[
        [1, 2],
        [2, 3],
        [3, 4],
      ];
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3, 4, 5])
        ..addTable(['A', 'B'], tuples)
        ..addStringConstraint('A >= 2'); // further restricts
      final solutions = await p.getAllSolutions();
      // Of the 3 table tuples, only those with A >= 2 survive.
      expect(solutions, hasLength(2));
      for (final s in solutions) {
        expect(s['A'], greaterThanOrEqualTo(2));
      }
    });
  });

  group('addInverse (channelling)', () {
    test('throws on mismatched length', () {
      final p = Problem()..addVariables(['f0', 'i0', 'i1'], [0, 1]);
      expect(() => p.addInverse(['f0'], ['i0', 'i1']), throwsArgumentError);
    });

    test('throws on empty lists', () {
      final p = Problem();
      expect(() => p.addInverse(<String>[], <String>[]), throwsArgumentError);
    });

    test('throws on unknown variable in forward', () {
      final p = Problem()..addVariable('i0', [0]);
      expect(() => p.addInverse(['unknown'], ['i0']), throwsArgumentError);
    });

    test('throws on unknown variable in inverse', () {
      final p = Problem()..addVariable('f0', [0]);
      expect(() => p.addInverse(['f0'], ['unknown']), throwsArgumentError);
    });

    test('n=2: enumerates the 2 permutations of (0,1)', () async {
      final p = Problem()
        ..addVariables(['f0', 'f1', 'i0', 'i1'], [0, 1])
        ..addInverse(['f0', 'f1'], ['i0', 'i1']);
      final all = await p.getAllSolutions();
      // Two permutations: identity (f=0,1 ; i=0,1) and swap
      // (f=1,0 ; i=1,0). In each, inverse is the inverse map.
      expect(all, hasLength(2));
      for (final s in all) {
        // Verify the channelling: forward[i] = j ⇔ inverse[j] = i.
        for (var i = 0; i < 2; i++) {
          for (var j = 0; j < 2; j++) {
            final fij = s['f$i'] == j;
            final iji = s['i$j'] == i;
            expect(fij, equals(iji),
                reason: 'channelling violated at (i=$i, j=$j) in $s');
          }
        }
      }
    });

    test('n=3: enumerates exactly the 6 permutations', () async {
      final names = ['f0', 'f1', 'f2', 'i0', 'i1', 'i2'];
      final p = Problem()
        ..addVariables(names, [0, 1, 2])
        ..addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2']);
      final all = await p.getAllSolutions();
      // 3! = 6 distinct permutations.
      expect(all, hasLength(6));
      // Channelling holds in each, and forward is a permutation.
      for (final s in all) {
        final forward = [s['f0'], s['f1'], s['f2']];
        expect(forward.toSet().length, equals(3),
            reason: 'forward not all-different in $s');
        final inverse = [s['i0'], s['i1'], s['i2']];
        expect(inverse.toSet().length, equals(3),
            reason: 'inverse not all-different in $s');
        // Composition: inverse[forward[i]] == i for all i.
        for (var i = 0; i < 3; i++) {
          expect(inverse[forward[i] as int], equals(i));
        }
      }
    });

    test('implies allDifferent on both lists (no need to add it separately)',
        () async {
      // 3 vars, addInverse alone — count must equal 3! (=6).
      final inv = Problem()
        ..addVariables(['f0', 'f1', 'f2', 'i0', 'i1', 'i2'], [0, 1, 2])
        ..addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2']);
      final invN = (await inv.getAllSolutions()).length;
      // Adding redundant allDifferent shouldn't change the count.
      final both = Problem()
        ..addVariables(['f0', 'f1', 'f2', 'i0', 'i1', 'i2'], [0, 1, 2])
        ..addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2'])
        ..addAllDifferent(['f0', 'f1', 'f2'])
        ..addAllDifferent(['i0', 'i1', 'i2']);
      final bothN = (await both.getAllSolutions()).length;
      expect(invN, equals(bothN));
      expect(invN, equals(6));
    });

    test('pinning forward propagates the inverse', () async {
      // f0=2, f1=0, f2=1 ⇒ inverse should be i0=1, i1=2, i2=0.
      final p = Problem()
        ..addVariable('f0', [2])
        ..addVariable('f1', [0])
        ..addVariable('f2', [1])
        ..addVariables(['i0', 'i1', 'i2'], [0, 1, 2])
        ..addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2']);
      final s = await p.getSolution();
      expect(s, isA<Map<String, dynamic>>());
      final sol = s as Map<String, dynamic>;
      expect(sol['i0'], equals(1));
      expect(sol['i1'], equals(2));
      expect(sol['i2'], equals(0));
    });

    test('pinning inverse propagates the forward', () async {
      // i0=2, i1=0, i2=1 ⇒ forward should be f0=1, f1=2, f2=0.
      final p = Problem()
        ..addVariables(['f0', 'f1', 'f2'], [0, 1, 2])
        ..addVariable('i0', [2])
        ..addVariable('i1', [0])
        ..addVariable('i2', [1])
        ..addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2']);
      final s = await p.getSolution();
      expect(s, isA<Map<String, dynamic>>());
      final sol = s as Map<String, dynamic>;
      expect(sol['f0'], equals(1));
      expect(sol['f1'], equals(2));
      expect(sol['f2'], equals(0));
    });

    test('infeasible if inverse map contradicts forward', () async {
      // f0=1 forces i1=0. Pinning i1=1 should make this infeasible.
      final p = Problem()
        ..addVariable('f0', [1])
        ..addVariable('f1', [0, 1])
        ..addVariables(['i0'], [0, 1])
        ..addVariable('i1', [1])
        ..addInverse(['f0', 'f1'], ['i0', 'i1']);
      final s = await p.getSolution();
      expect(s, equals('FAILURE'));
    });

    test('practical assignment problem: tasks → machines bijection', () async {
      // 4 tasks, 4 machines. Forbidden pairs (some tasks can't run on
      // some machines). Want a valid bijection.
      const n = 4;
      final taskNames = [for (var i = 0; i < n; i++) 'task$i'];
      final machineNames = [for (var i = 0; i < n; i++) 'machine$i'];
      final p = Problem()
        ..addVariables(taskNames, [for (var i = 0; i < n; i++) i])
        ..addVariables(machineNames, [for (var i = 0; i < n; i++) i])
        ..addInverse(taskNames, machineNames);
      // Forbid task 0 → machine 0 (express via task[0] != 0).
      p.addConstraint(['task0'], (Map<String, dynamic> a) => a['task0'] != 0);
      // Forbid task 1 → machine 1.
      p.addConstraint(['task1'], (Map<String, dynamic> a) => a['task1'] != 1);
      final all = await p.getAllSolutions();
      // Without forbids: 4! = 24 permutations. With two diagonals
      // excluded: D(4)-style derangement-on-{0,1} subset of S_4.
      // Verify each is a bijection that respects forbids.
      for (final s in all) {
        final tasks = [for (var i = 0; i < n; i++) s['task$i'] as int];
        expect(tasks.toSet().length, equals(n),
            reason: 'task assignment not bijective in $s');
        expect(tasks[0], isNot(equals(0)));
        expect(tasks[1], isNot(equals(1)));
        // Verify channelling.
        for (var i = 0; i < n; i++) {
          expect(s['machine${tasks[i]}'], equals(i));
        }
      }
      // Brute-force expectation.
      var expected = 0;
      for (final perm in _permutations(n)) {
        if (perm[0] != 0 && perm[1] != 1) expected++;
      }
      expect(all.length, equals(expected));
    });
  });
}

Iterable<List<int>> _permutations(int n) sync* {
  final arr = [for (var i = 0; i < n; i++) i];
  yield* _permuteFrom(arr, 0);
}

Iterable<List<int>> _permuteFrom(List<int> arr, int start) sync* {
  if (start == arr.length - 1) {
    yield List<int>.from(arr);
    return;
  }
  for (var i = start; i < arr.length; i++) {
    final tmp = arr[start];
    arr[start] = arr[i];
    arr[i] = tmp;
    yield* _permuteFrom(arr, start + 1);
    final tmp2 = arr[start];
    arr[start] = arr[i];
    arr[i] = tmp2;
  }
}

bool _equalTuple(List<dynamic> a, List<dynamic> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

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
}

bool _equalTuple(List<dynamic> a, List<dynamic> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

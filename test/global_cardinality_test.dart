import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('addAmong (variable count)', () {
    test('count variable tracks the number of vars in the value set', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addVariable('n', [0, 1, 2, 3])
        ..addAmong(['a', 'b', 'c'], {1, 2}, 'n');
      for (final s in await p.getAllSolutions()) {
        final actual =
            ['a', 'b', 'c'].where((v) => s[v] == 1 || s[v] == 2).length;
        expect(s['n'], equals(actual));
      }
    });

    test('forces vars when n is pinned to the maximum', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addVariable('n', [2])
        ..addAmong(['a', 'b'], {1, 2}, 'n');
      for (final s in await p.getAllSolutions()) {
        expect(s['a'], anyOf(equals(1), equals(2)));
        expect(s['b'], anyOf(equals(1), equals(2)));
      }
    });

    test('forces vars when n is pinned to zero', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addVariable('n', [0])
        ..addAmong(['a', 'b'], {1, 2}, 'n');
      for (final s in await p.getAllSolutions()) {
        expect(s['a'], equals(3));
        expect(s['b'], equals(3));
      }
    });

    test('infeasible when n cannot be reached', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2])
        ..addVariable('n', [3]) // can't have 3 hits with only 2 vars
        ..addAmong(['a', 'b'], {1, 2}, 'n');
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('empty value set: count is always 0', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addVariable('n', [0, 1, 2])
        ..addAmong(['a', 'b'], <dynamic>{}, 'n');
      for (final s in await p.getAllSolutions()) {
        expect(s['n'], equals(0));
      }
    });

    test('throws on unknown variables', () {
      final p = Problem()..addVariable('a', [1, 2]);
      expect(() => p.addAmong(['a'], {1}, 'missing'), throwsArgumentError);
      expect(() => p.addAmong(['missing'], {1}, 'a'), throwsArgumentError);
      expect(() => p.addAmong(<String>[], {1}, 'a'), throwsArgumentError);
    });
  });

  group('addAmongExactly (fixed count)', () {
    test('exactly k of vars must be in the value set', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3, 4])
        ..addAmongExactly(['a', 'b', 'c'], {1, 2}, 2);
      for (final s in await p.getAllSolutions()) {
        final n = ['a', 'b', 'c'].where((v) => s[v] == 1 || s[v] == 2).length;
        expect(n, equals(2));
      }
    });

    test('k=0 forces all vars outside the set', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addAmongExactly(['a', 'b'], {1, 2}, 0);
      for (final s in await p.getAllSolutions()) {
        expect(s['a'], equals(3));
        expect(s['b'], equals(3));
      }
    });

    test('k=n forces all vars in the set', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2, 3])
        ..addAmongExactly(['a', 'b'], {1, 2}, 2);
      for (final s in await p.getAllSolutions()) {
        expect({1, 2}.contains(s['a']), isTrue);
        expect({1, 2}.contains(s['b']), isTrue);
      }
    });

    test('k out of range throws', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(() => p.addAmongExactly(['a', 'b'], {1}, -1), throwsArgumentError);
      expect(() => p.addAmongExactly(['a', 'b'], {1}, 3), throwsArgumentError);
    });

    test('single-variable case still routes through n-ary', () async {
      // Guards the arity-dispatch gotcha: vars.length == 1 must not be
      // treated as binary even though _addNary handles it.
      final p = Problem()
        ..addVariable('a', [1, 2, 3])
        ..addAmongExactly(['a'], {2}, 1);
      final s = await p.getSolution();
      expect((s as Map)['a'], equals(2));
    });
  });

  group('addNvalue (variable count)', () {
    test('count variable equals number of distinct values', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2])
        ..addVariable('n', [1, 2, 3])
        ..addNvalue(['a', 'b', 'c'], 'n');
      for (final s in await p.getAllSolutions()) {
        final distinct = <dynamic>{s['a'], s['b'], s['c']}.length;
        expect(s['n'], equals(distinct));
      }
    });

    test('n=1 forces all vars equal', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addVariable('n', [1])
        ..addNvalue(['a', 'b', 'c'], 'n');
      for (final s in await p.getAllSolutions()) {
        expect(s['a'], equals(s['b']));
        expect(s['b'], equals(s['c']));
      }
    });

    test('n=length forces all vars distinct (alldifferent-equivalent)',
        () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addVariable('n', [3])
        ..addNvalue(['a', 'b', 'c'], 'n');
      final all = await p.getAllSolutions();
      // 3! = 6 distinct-value tuples over {1,2,3}.
      expect(all, hasLength(6));
      for (final s in all) {
        final set = <dynamic>{s['a'], s['b'], s['c']};
        expect(set.length, equals(3));
      }
    });

    test('throws on unknown variables', () {
      final p = Problem()..addVariable('a', [1, 2]);
      expect(() => p.addNvalue(['a'], 'missing'), throwsArgumentError);
      expect(() => p.addNvalue(['missing'], 'a'), throwsArgumentError);
      expect(() => p.addNvalue(<String>[], 'a'), throwsArgumentError);
    });
  });

  group('addNvalueExactly (fixed count)', () {
    test('exactly k distinct values', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addNvalueExactly(['a', 'b', 'c'], 2);
      for (final s in await p.getAllSolutions()) {
        final set = <dynamic>{s['a'], s['b'], s['c']};
        expect(set.length, equals(2));
      }
    });

    test('k out of range throws', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(() => p.addNvalueExactly(['a', 'b'], 0), throwsArgumentError);
      expect(() => p.addNvalueExactly(['a', 'b'], 3), throwsArgumentError);
    });

    test('minimization: chromatic-number-style optimization', () async {
      // Three "people" each have a "color"; we want the fewest colors.
      final p = Problem()
        ..addVariables(['p1', 'p2', 'p3'], [1, 2, 3])
        ..addVariable('nColors', [1, 2, 3])
        ..addNvalue(['p1', 'p2', 'p3'], 'nColors');
      final result = await p.minimize('nColors');
      expect((result as Map)['nColors'], equals(1));
    });
  });

  group('addGcc (exact counts)', () {
    test('each value occurs the required number of times', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3])
        ..addGcc(['a', 'b', 'c', 'd'], {1: 2, 2: 1, 3: 1});
      for (final s in await p.getAllSolutions()) {
        final hist = <dynamic, int>{};
        for (final v in ['a', 'b', 'c', 'd']) {
          hist[s[v]] = (hist[s[v]] ?? 0) + 1;
        }
        expect(hist[1], equals(2));
        expect(hist[2], equals(1));
        expect(hist[3], equals(1));
      }
    });

    test('values not in the map are unconstrained', () async {
      // 4 vars over {1,2,3}: pin value 1 at exactly 1 occurrence; 2/3 free.
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3])
        ..addGcc(['a', 'b', 'c', 'd'], {1: 1});
      for (final s in await p.getAllSolutions()) {
        final ones = ['a', 'b', 'c', 'd'].where((v) => s[v] == 1).length;
        expect(ones, equals(1));
      }
    });

    test('all-different equivalent: each value count = 1', () async {
      // 3 vars over {1,2,3} with each digit count = 1 ≡ allDifferent.
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addGcc(['a', 'b', 'c'], {1: 1, 2: 1, 3: 1});
      final all = await p.getAllSolutions();
      expect(all, hasLength(6)); // 3! permutations
      for (final s in all) {
        final set = <dynamic>{s['a'], s['b'], s['c']};
        expect(set.length, equals(3));
      }
    });

    test('infeasible when total required exceeds variable count', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(() => p.addGcc(['a', 'b'], {1: 2, 2: 1}), throwsArgumentError);
    });

    test('negative count throws at construction', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(() => p.addGcc(['a', 'b'], {1: -1}), throwsArgumentError);
    });

    test('unknown variable throws', () {
      final p = Problem()..addVariable('a', [1, 2]);
      expect(() => p.addGcc(['a', 'b'], {1: 1}), throwsArgumentError);
      expect(() => p.addGcc(<String>[], {1: 1}), throwsArgumentError);
    });

    test('shift roster: morning=3, afternoon=2, night=1 across 6 slots',
        () async {
      const slots = ['s1', 's2', 's3', 's4', 's5', 's6'];
      final p = Problem()
        ..addVariables(slots, ['morning', 'afternoon', 'night'])
        ..addGcc(slots, {'morning': 3, 'afternoon': 2, 'night': 1});
      final s = await p.getSolution();
      final map = s as Map<String, dynamic>;
      final hist = <String, int>{};
      for (final slot in slots) {
        hist[map[slot] as String] = (hist[map[slot] as String] ?? 0) + 1;
      }
      expect(hist['morning'], equals(3));
      expect(hist['afternoon'], equals(2));
      expect(hist['night'], equals(1));
    });
  });

  group('addGccRanges (ranged counts)', () {
    test('each value occurs within the given range', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3])
        ..addGccRanges(
            ['a', 'b', 'c', 'd'], {1: (min: 1, max: 2), 2: (min: 1, max: 3)});
      for (final s in await p.getAllSolutions()) {
        final hist = <dynamic, int>{};
        for (final v in ['a', 'b', 'c', 'd']) {
          hist[s[v]] = (hist[s[v]] ?? 0) + 1;
        }
        final n1 = hist[1] ?? 0;
        final n2 = hist[2] ?? 0;
        expect(n1, inInclusiveRange(1, 2));
        expect(n2, inInclusiveRange(1, 3));
      }
    });

    test('min=max collapses to exact count', () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addGccRanges(['a', 'b', 'c'], {1: (min: 1, max: 1)});
      for (final s in await p.getAllSolutions()) {
        final ones = ['a', 'b', 'c'].where((v) => s[v] == 1).length;
        expect(ones, equals(1));
      }
    });

    test('infeasible when sum of mins exceeds variable count', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(
          () => p.addGccRanges(
              ['a', 'b'], {1: (min: 2, max: 2), 2: (min: 1, max: 1)}),
          throwsArgumentError);
    });

    test('malformed range throws', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(() => p.addGccRanges(['a', 'b'], {1: (min: -1, max: 2)}),
          throwsArgumentError);
      expect(() => p.addGccRanges(['a', 'b'], {1: (min: 2, max: 1)}),
          throwsArgumentError);
    });

    test('composes with other constraints: at most 2 morning, at least 1 night',
        () async {
      const slots = ['s1', 's2', 's3', 's4'];
      final p = Problem()
        ..addVariables(slots, ['morning', 'afternoon', 'night'])
        ..addGccRanges(slots, {
          'morning': (min: 0, max: 2),
          'night': (min: 1, max: 4),
        });
      for (final s in await p.getAllSolutions()) {
        final hist = <String, int>{};
        for (final slot in slots) {
          final v = s[slot] as String;
          hist[v] = (hist[v] ?? 0) + 1;
        }
        expect(hist['morning'] ?? 0, lessThanOrEqualTo(2));
        expect(hist['night'] ?? 0, greaterThanOrEqualTo(1));
      }
    });
  });

  group('addGcc: network-flow propagator', () {
    test('detects insufficient capacity at the root', () async {
      // 5 vars over {1, 2}, but specify exact-count 3 for value 1 and
      // 3 for value 2 — sum=6 > 5. addGcc validates this at
      // construction.
      final p = Problem()..addVariables(['a', 'b', 'c', 'd', 'e'], [1, 2]);
      expect(() => p.addGcc(['a', 'b', 'c', 'd', 'e'], {1: 3, 2: 3}),
          throwsArgumentError);
    });

    test('propagator detects infeasibility when required value is gone',
        () async {
      // Variables don't include the required value at all. Capacity
      // check + value indexing catches it without descending.
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [2, 3])
        ..addGcc(['a', 'b', 'c'], {1: 1, 2: 1, 3: 1});
      expect(await p.getSolution(), equals('FAILURE'));
      expect(p.lastStats!.decisions, equals(0),
          reason: 'must detect missing required value at root');
    });

    test('all-different-equivalent GCC matches addAllDifferent solutions',
        () async {
      // Each digit count = 1 ≡ allDifferent.
      Problem buildGcc() => Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3, 4])
        ..addGcc(['a', 'b', 'c', 'd'], {1: 1, 2: 1, 3: 1, 4: 1});
      Problem buildAllDiff() => Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3, 4])
        ..addAllDifferent(['a', 'b', 'c', 'd']);

      final gccSols = (await buildGcc().getAllSolutions())
          .map((s) => '${s['a']}${s['b']}${s['c']}${s['d']}')
          .toSet();
      final allDiffSols = (await buildAllDiff().getAllSolutions())
          .map((s) => '${s['a']}${s['b']}${s['c']}${s['d']}')
          .toSet();
      expect(gccSols, equals(allDiffSols));
      expect(gccSols.length, equals(24)); // 4!
    });

    test('upper-bound only: enumerates correctly and propagator activates',
        () async {
      // Pure upper-bound case: value 1 occurs at most 2 times.
      final p = Problem()
        ..addVariables(['a', 'b', 'c', 'd'], [1, 2, 3])
        ..addGccRanges([
          'a',
          'b',
          'c',
          'd'
        ], {
          1: (min: 0, max: 2),
        });
      var count = 0;
      await for (final s in p.getSolutions()) {
        final ones = ['a', 'b', 'c', 'd'].where((v) => s[v] == 1).length;
        expect(ones, lessThanOrEqualTo(2));
        count++;
      }
      // Out of 3^4 = 81 assignments, subtract those with > 2 ones:
      // ones=3: C(4,3) * 2 = 8.  ones=4: 1.  Total bad = 9.
      // Good = 81 - 9 = 72.
      expect(count, equals(72));
      // Propagator must have done real work.
      expect(p.lastStats!.naryRevises, greaterThan(0));
    });

    test('exact-count GCC: large rostering with full GAC pruning', () async {
      // 6 slots, each in {morning, afternoon, night}. Exact counts
      // sum to 6, so each value is exactly determined in count.
      const slots = ['s1', 's2', 's3', 's4', 's5', 's6'];
      final p = Problem()
        ..addVariables(slots, ['morning', 'afternoon', 'night'])
        ..addGcc(slots, {'morning': 3, 'afternoon': 2, 'night': 1});
      var count = 0;
      await for (final s in p.getSolutions()) {
        final hist = <String, int>{};
        for (final slot in slots) {
          hist[s[slot] as String] = (hist[s[slot] as String] ?? 0) + 1;
        }
        expect(hist['morning'], equals(3));
        expect(hist['afternoon'], equals(2));
        expect(hist['night'], equals(1));
        count++;
      }
      // 6! / (3! · 2! · 1!) = 60 distinct sequences.
      expect(count, equals(60));
    });
  });

  group('among + nvalue + gcc composition (puzzle regression)', () {
    test('mini-rostering: 5 days, 3 shifts, gcc + among + nvalue together',
        () async {
      // 5 days, shifts in {M, A, N}. Each shift used at most 3 times.
      // Among days, exactly 2 are "M" (morning). At least 2 distinct
      // shifts used overall.
      const days = ['mon', 'tue', 'wed', 'thu', 'fri'];
      final p = Problem()
        ..addVariables(days, ['M', 'A', 'N'])
        ..addVariable('nShifts', [2, 3])
        ..addGccRanges(days, {
          'M': (min: 0, max: 3),
          'A': (min: 0, max: 3),
          'N': (min: 0, max: 3),
        })
        ..addAmongExactly(days, {'M'}, 2)
        ..addNvalue(days, 'nShifts');
      for (final s in await p.getAllSolutions()) {
        final hist = <String, int>{};
        for (final d in days) {
          hist[s[d] as String] = (hist[s[d] as String] ?? 0) + 1;
        }
        expect(hist['M'], equals(2));
        for (final c in hist.values) {
          expect(c, lessThanOrEqualTo(3));
        }
        final distinct = hist.keys.toSet().length;
        expect(distinct, anyOf(equals(2), equals(3)));
        expect(s['nShifts'], equals(distinct));
      }
    });
  });
}

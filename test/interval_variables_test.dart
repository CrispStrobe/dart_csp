import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Tests for the new `_IntervalRep` domain representation and its
/// user-facing surface (`addRangeVariable`, `addNoOverlap`).
///
/// The rep itself is private to `lib/src/solver.dart`. These tests
/// hit observable behavior: enumeration counts, scheduling
/// correctness, propagator activity on large contiguous-int domains
/// that previously fell back to a list rep.
void main() {
  group('addRangeVariable basics', () {
    test('rejects empty range', () {
      final p = Problem();
      expect(
          () => p.addRangeVariable('x', 10, 5), throwsA(isA<ArgumentError>()));
    });

    test('rejects duplicate variable', () {
      final p = Problem()..addRangeVariable('x', 0, 10);
      expect(
          () => p.addRangeVariable('x', 0, 5), throwsA(isA<ArgumentError>()));
    });

    test('singleton range produces a single solution', () async {
      final p = Problem()..addRangeVariable('x', 7, 7);
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map<String, dynamic>)['x'], equals(7));
    });

    test('small range enumerates correctly (still uses bitset rep)', () async {
      final p = Problem()..addRangeVariable('x', 0, 4);
      final solutions = <int>{};
      await for (final s in p.getSolutions()) {
        solutions.add(s['x'] as int);
      }
      expect(solutions, equals({0, 1, 2, 3, 4}));
    });

    test('large contiguous range works end-to-end (interval rep)', () async {
      // Span 2001 > _bitsetMaxSpan (1024): falls into the interval rep.
      // Without the interval rep this would have allocated a 2001-element
      // List<dynamic> per variable for storage and iteration.
      final p = Problem()
        ..addRangeVariable('x', 0, 2000)
        ..addStringConstraint('x >= 1995');
      final solutions = <int>{};
      await for (final s in p.getSolutions()) {
        solutions.add(s['x'] as int);
      }
      expect(solutions, equals({1995, 1996, 1997, 1998, 1999, 2000}));
    });
  });

  group('interval rep semantics', () {
    test(
        'linear propagator on a wide range stays compact and finds the '
        'optimum quickly', () async {
      // start + duration = end, with start in [0, 10000] and end
      // forced to <= 50. Bounds-consistency linear should tighten the
      // ranges aggressively. Without interval rep this would have
      // allocated two 10001-element List<dynamic> domains.
      final p = Problem()
        ..addRangeVariable('start', 0, 10000)
        ..addRangeVariable('duration', 1, 5)
        ..addRangeVariable('end', 0, 10000)
        ..addLinearEquals(['start', 'duration', 'end'], [1, 1, -1], 0)
        ..addStringConstraint('end <= 50');
      final result = await p.minimize('end');
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['end'], equals(1));
      expect(s['start'], equals(0));
      expect(s['duration'], equals(1));
    });

    test('predicate with interior holes promotes (still solves correctly)',
        () async {
      // x in [0, 1500], only even values allowed. The first time the
      // predicate runs (in generic GAC support search) it would create
      // an interior-hole filter on the interval rep, which must
      // promote to a list rep without losing values.
      final p = Problem()
        ..addRangeVariable('x', 0, 1500)
        ..addConstraint(
            ['x'], (Map<String, dynamic> a) => (a['x'] as int) % 2 == 0)
        ..addStringConstraint('x >= 1490');
      final solutions = <int>{};
      await for (final s in p.getSolutions()) {
        solutions.add(s['x'] as int);
      }
      // Even values in [1490, 1500]: 1490, 1492, 1494, 1496, 1498, 1500.
      expect(solutions, equals({1490, 1492, 1494, 1496, 1498, 1500}));
    });

    test('regular constraint works on interval-rep variables', () async {
      // DFA: at-most-2 ones. Domain is bitset-sized (each variable in
      // [0, 1]) but we use addRangeVariable to exercise the helper
      // path even on small ranges.
      final dfa = Dfa(
        numStates: 4,
        start: 0,
        accepting: {0, 1, 2},
        transitions: {
          0: {0: 0, 1: 1},
          1: {0: 1, 1: 2},
          2: {0: 2, 1: 3},
          3: {0: 3, 1: 3},
        },
      );
      final names = [for (var i = 0; i < 5; i++) 'v$i'];
      final p = Problem();
      for (final n in names) {
        p.addRangeVariable(n, 0, 1);
      }
      p.addRegular(names, dfa);
      var count = 0;
      await for (final s in p.getSolutions()) {
        final ones = names.where((n) => s[n] == 1).length;
        expect(ones, lessThanOrEqualTo(2));
        count++;
      }
      // C(5,0) + C(5,1) + C(5,2) = 1 + 5 + 10 = 16.
      expect(count, equals(16));
    });

    test('search commits singletons preserving interval rep', () async {
      // 5 vars over [0, 2000] with linear sum = 5000 and a strict
      // ordering. The solver must commit each variable to a single
      // value at the leaf; the _setDomain([candidate]) path must
      // produce a valid 1-element interval rep without dropping the
      // value on trail rollback.
      final names = [for (var i = 0; i < 5; i++) 'x$i'];
      final p = Problem();
      for (final n in names) {
        p.addRangeVariable(n, 0, 2000);
      }
      p
        ..addLinearEquals(names, [1, 1, 1, 1, 1], 5000)
        ..addStringConstraint('x0 < x1')
        ..addStringConstraint('x1 < x2')
        ..addStringConstraint('x2 < x3')
        ..addStringConstraint('x3 < x4');
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      final values = names.map((n) => s[n] as int).toList();
      var sum = 0;
      for (final v in values) {
        sum += v;
      }
      expect(sum, equals(5000));
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
    });
  });

  group('addNoOverlap (unary-resource scheduling)', () {
    test('rejects mismatched lengths', () {
      final p = Problem()
        ..addRangeVariable('a', 0, 10)
        ..addRangeVariable('b', 0, 10);
      expect(
          () => p.addNoOverlap(['a', 'b'], [3]), throwsA(isA<ArgumentError>()));
    });

    test('rejects negative duration', () {
      final p = Problem()..addRangeVariable('a', 0, 10);
      expect(() => p.addNoOverlap(['a'], [-1]), throwsA(isA<ArgumentError>()));
    });

    test('rejects unknown start variable', () {
      final p = Problem();
      expect(
          () => p.addNoOverlap(['ghost'], [3]), throwsA(isA<ArgumentError>()));
    });

    test('two tasks on a horizon: enumerates non-overlapping schedules',
        () async {
      // Two tasks, durations 3 and 2, horizon 7. The latest legal
      // start times are 4 and 5 respectively (a + 3 <= 7, b + 2 <= 7).
      // Encode the horizon directly in the range bounds.
      final p = Problem()
        ..addRangeVariable('a', 0, 4)
        ..addRangeVariable('b', 0, 5)
        ..addNoOverlap(['a', 'b'], [3, 2]);
      final solutions = <(int, int)>{};
      await for (final s in p.getSolutions()) {
        final a = s['a'] as int;
        final b = s['b'] as int;
        expect(a + 3 <= b || b + 2 <= a, isTrue);
        solutions.add((a, b));
      }
      // For each (a, b) with a in [0,4] and b in [0,5]:
      //   if a + 3 <= b: b >= a + 3 (b in {a+3, ..., 5})
      //   if b + 2 <= a: a >= b + 2 (b in {0, ..., a - 2})
      // a=0: b in {3,4,5} → 3 pairs
      // a=1: b in {4,5}   → 2 pairs
      // a=2: b in {5} or b=0       → 2 pairs
      // a=3: b in {} or b in {0,1} → 2 pairs
      // a=4: b in {} or b in {0,1,2} → 3 pairs
      // Total: 3 + 2 + 2 + 2 + 3 = 12.
      expect(solutions.length, equals(12));
    });

    test('three tasks on one machine: pack with minimum makespan', () async {
      // Three tasks with durations 4, 3, 2 on a single machine.
      // makespan = max(end times). The optimum makespan is 4+3+2 = 9
      // since they cannot overlap.
      final p = Problem()
        ..addRangeVariable('s0', 0, 20)
        ..addRangeVariable('s1', 0, 20)
        ..addRangeVariable('s2', 0, 20)
        ..addRangeVariable('mk', 0, 20)
        ..addNoOverlap(['s0', 's1', 's2'], [4, 3, 2])
        ..addLinearGeq(['mk', 's0'], [1, -1], 4) // mk >= s0 + 4
        ..addLinearGeq(['mk', 's1'], [1, -1], 3) // mk >= s1 + 3
        ..addLinearGeq(['mk', 's2'], [1, -1], 2); // mk >= s2 + 2
      final result = await p.minimize('mk');
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['mk'], equals(9));
    });

    test('vacuous case (zero tasks) is satisfied', () async {
      final p = Problem()..addNoOverlap(<String>[], <int>[]);
      final result = await p.getSolution();
      expect(result, equals(<String, dynamic>{}));
    });

    test(
        'enumeration set matches addCumulative(capacity=1, demand=1) '
        'on a non-trivial instance', () async {
      // Equivalence test for the dispatch: addNoOverlap should now be
      // semantically identical to addCumulative with unit demand and
      // unit capacity. We pick a horizon and task mix where the
      // distinction (if any) between pairwise-disjunction and time-
      // table propagation would show up as different solution sets.
      List<String> sortedKey(Map<String, dynamic> m) {
        final entries = m.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return [for (final e in entries) '${e.key}=${e.value}'];
      }

      Problem buildNo() => Problem()
        ..addRangeVariable('s0', 0, 8)
        ..addRangeVariable('s1', 0, 8)
        ..addRangeVariable('s2', 0, 8)
        ..addNoOverlap(['s0', 's1', 's2'], [3, 2, 2]);

      Problem buildCum() => Problem()
        ..addRangeVariable('s0', 0, 8)
        ..addRangeVariable('s1', 0, 8)
        ..addRangeVariable('s2', 0, 8)
        ..addCumulative(['s0', 's1', 's2'], [3, 2, 2], [1, 1, 1], 1);

      final noSet = <String>{};
      await for (final s in buildNo().getSolutions()) {
        noSet.add(sortedKey(s).join(','));
      }
      final cumSet = <String>{};
      await for (final s in buildCum().getSolutions()) {
        cumSet.add(sortedKey(s).join(','));
      }
      expect(noSet, equals(cumSet),
          reason: 'addNoOverlap and addCumulative(capacity=1, demand=1) '
              'must enumerate identical solution sets');
      expect(noSet, isNotEmpty);
    });
  });
}

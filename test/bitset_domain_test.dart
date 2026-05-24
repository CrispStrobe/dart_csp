import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// These tests exercise the internal bitset-vs-list domain dispatch
/// indirectly: each case picks a domain shape that hits a different
/// branch of the eligibility check, and asserts that the solver
/// still produces the right answers. The dispatch itself is private
/// (`_DomainRep` and friends live in `lib/src/solver.dart`), so the
/// tests target observable behavior.
void main() {
  group('bitset-eligible domains (ascending int, span ≤ 1024)', () {
    test('small contiguous int domain solves correctly', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3, 4, 5])
        ..addAllDifferent(['A', 'B', 'C'])
        ..addStringConstraint('A < B')
        ..addStringConstraint('B < C');
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect((s['A'] as int) < (s['B'] as int), isTrue);
      expect((s['B'] as int) < (s['C'] as int), isTrue);
    });

    test('ascending non-contiguous int domain works (sparse bitset values)',
        () async {
      // [1, 3, 5, 7] — strictly ascending, span 7 ≤ 1024, so bitset.
      // The propagator-side domain iteration must still see exactly
      // these 4 values, not the integers 2/4/6.
      final p = Problem()
        ..addVariables(['X', 'Y'], [1, 3, 5, 7])
        ..addStringConstraint('X + Y == 10');
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        expect([1, 3, 5, 7], contains(s['X']));
        expect([1, 3, 5, 7], contains(s['Y']));
        expect((s['X'] as int) + (s['Y'] as int), equals(10));
        solutions.add(s);
      }
      // X+Y=10: (3,7), (5,5), (7,3). 5+5 includes the same value twice
      // — counts since there's no all-different.
      expect(solutions.length, equals(3));
    });

    test('negative-offset ascending domain works', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [-5, -4, -3, -2, -1, 0, 1, 2, 3])
        ..addLinearEquals(['A', 'B'], [1, 1], 0);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        expect((s['A'] as int) + (s['B'] as int), equals(0));
        solutions.add(s);
      }
      // Pairs (a, b) with a+b=0 in [-5..3]²: a ∈ [-3..3], b = -a. 7
      // pairs.
      expect(solutions.length, equals(7));
    });

    test('span exactly at the eligibility boundary (1024) works', () async {
      // Domain has 2 values at the extremes; span = 1024 → eligible.
      // Easy to verify correctness even though the bitset path is
      // taken.
      final p = Problem()
        ..addVariables(['X', 'Y'], [0, 1023])
        ..addStringConstraint('X != Y');
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        expect(s['X'], isNot(equals(s['Y'])));
        solutions.add(s);
      }
      expect(solutions.length, equals(2));
    });

    test('all-different on large integer domain (sudoku-ish)', () async {
      // 9 variables, domain 1..9, all-different. Régin propagator
      // walks domains via the new bitset iteration — verify correct
      // enumeration count (9! = 362880, but only sample one solution
      // for speed).
      final vars = [for (var i = 0; i < 9; i++) 'v$i'];
      final p = Problem()
        ..addVariables(vars, [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addAllDifferent(vars);
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(
          vars.map((v) => s[v]).toSet(), equals({1, 2, 3, 4, 5, 6, 7, 8, 9}));
    });
  });

  group('bitset-ineligible domains (fall back to list rep)', () {
    test('mixed-type domain (strings) solves correctly', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], ['red', 'green', 'blue'])
        ..addStringConstraint('A != B');
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(6)); // 3 × 2
    });

    test('non-monotonic int domain still solves correctly', () async {
      // Input order [3, 1, 2] is not ascending → falls back to list.
      final p = Problem()
        ..addVariables(['X', 'Y'], [3, 1, 2])
        ..addStringConstraint('X + Y == 4');
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        expect((s['X'] as int) + (s['Y'] as int), equals(4));
        solutions.add(s);
      }
      // (1,3), (3,1), (2,2). 3 pairs.
      expect(solutions.length, equals(3));
    });

    test('span > 1024 falls back to list', () async {
      // Span = 2001. List rep used.
      final p = Problem()
        ..addVariables(['X'], [0, 2000])
        ..addStringConstraint('X >= 100');
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map<String, dynamic>)['X'], equals(2000));
    });

    test('mixed int + string in same domain falls back to list', () async {
      final p = Problem()
        ..addVariables(['X'], [1, 'two', 3])
        ..addConstraint(['X'], (Map<String, dynamic> a) => a['X'] != 'two');
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        solutions.add(s);
      }
      expect(solutions.length, equals(2));
      expect(solutions.map((s) => s['X']).toSet(), equals({1, 3}));
    });

    test('double-valued domain falls back to list', () async {
      // Doubles are not int → list rep.
      final p = Problem()
        ..addVariables(['X', 'Y'], [1.5, 2.5, 3.5])
        ..addLinearEquals(['X', 'Y'], [1, 1], 5.0);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        expect((s['X'] as double) + (s['Y'] as double), closeTo(5.0, 0.001));
        solutions.add(s);
      }
      // (1.5, 3.5), (2.5, 2.5), (3.5, 1.5).
      expect(solutions.length, equals(3));
    });
  });

  group('rep type round-trips correctly through propagators', () {
    test('linear propagator preserves bitset rep across trail rollback',
        () async {
      // Enumerate all solutions — the engine builds and rolls back
      // many trail entries. Any rep-handling bug would show up as
      // missing or duplicated solutions.
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [0, 1, 2, 3, 4, 5])
        ..addLinearEquals(['A', 'B', 'C'], [1, 1, 1], 6);
      final solutions = <String>{};
      await for (final s in p.getSolutions()) {
        expect((s['A'] as int) + (s['B'] as int) + (s['C'] as int), equals(6));
        solutions.add('${s['A']},${s['B']},${s['C']}');
      }
      // Number of (A,B,C) ∈ [0..5]³ with A+B+C=6.
      // Unbounded stars-and-bars: C(6+2, 2) = 28. Subtract 3
      // overcounts where one variable equals 6 and the others are 0.
      expect(solutions.length, equals(25));
    });

    test('regular propagator preserves bitset rep across trail rollback',
        () async {
      // DFA: at-most-one 'b' (encoded as integers 0/1).
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {0, 1},
        transitions: {
          0: {0: 0, 1: 1},
          1: {0: 1},
        },
      );
      final vars = [for (var i = 0; i < 6; i++) 'v$i'];
      final p = Problem()
        ..addVariables(vars, [0, 1])
        ..addRegular(vars, dfa);
      var count = 0;
      await for (final s in p.getSolutions()) {
        final ones = vars.where((v) => s[v] == 1).length;
        expect(ones, lessThanOrEqualTo(1));
        count++;
      }
      // all-zeros + 6 single-one positions = 7.
      expect(count, equals(7));
    });

    test('integrated B&B with bitset domain finds the optimum', () async {
      final p = Problem()
        ..addVariables(['X', 'Y'], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ..addLinearGeq(['X', 'Y'], [2, 3], 20);
      final result = await p.minimize('X');
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(s['X'], equals(0));
    });

    test(
        'allDifferent propagator on bitset domains: heavy pruning '
        'preserves correctness', () async {
      // 6-queens via all-different on file-index domains plus binary
      // diagonal constraints. Domain [1..6] is bitset-eligible; the
      // Régin propagator filters each queen's domain many times during
      // search. Any rep-type drift in the rep-aware filter path would
      // show up here as missing or duplicated solutions.
      final queens = [for (var i = 0; i < 6; i++) 'Q$i'];
      final p = Problem()
        ..addVariables(queens, [1, 2, 3, 4, 5, 6])
        ..addAllDifferent(queens);
      for (var i = 0; i < 6; i++) {
        for (var j = i + 1; j < 6; j++) {
          final d = (j - i).abs();
          p.addConstraint([queens[i], queens[j]],
              (dynamic a, dynamic b) => ((a as num) - (b as num)).abs() != d);
        }
      }
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(4)); // 6-queens has 4 solutions
    });

    test(
        'gcc propagator on bitset domains: exact-count rostering '
        'enumerates correctly', () async {
      // Six workers, three shifts (0=morning, 1=afternoon, 2=night),
      // each shift assigned exactly twice. Domain [0..2] is bitset-
      // eligible; the network-flow GCC propagator does the bulk of
      // pruning via the rep-aware filter.
      final workers = [for (var i = 0; i < 6; i++) 'w$i'];
      final p = Problem()
        ..addVariables(workers, [0, 1, 2])
        ..addGcc(workers, {0: 2, 1: 2, 2: 2});
      var count = 0;
      final seen = <String>{};
      await for (final s in p.getSolutions()) {
        final assignment = workers.map((v) => s[v] as int).toList();
        // Each shift appears exactly twice.
        final counts = <int, int>{};
        for (final v in assignment) {
          counts[v] = (counts[v] ?? 0) + 1;
        }
        expect(counts, equals({0: 2, 1: 2, 2: 2}));
        seen.add(assignment.join(','));
        count++;
      }
      // 6! / (2!·2!·2!) = 720 / 8 = 90 distinct assignments.
      expect(count, equals(90));
      expect(seen.length, equals(90));
    });

    test(
        'circuit propagator on bitset domains: enumerates all tours '
        'of length 5', () async {
      // 5-position Hamiltonian circuit over indices [0..4]. Domain is
      // bitset-eligible; the circuit propagator's prunes (chain-tail
      // pruning, successor uniqueness, force-tail-to-head) all flow
      // through the rep-aware filter path.
      final positions = [for (var i = 0; i < 5; i++) 'p$i'];
      final p = Problem()
        ..addVariables(positions, [0, 1, 2, 3, 4])
        ..addCircuit(positions);
      var count = 0;
      await for (final s in p.getSolutions()) {
        // Verify each result is a true single Hamiltonian cycle.
        final next = [for (final v in positions) s[v] as int];
        final visited = <int>{};
        var cur = 0;
        for (var step = 0; step < 5; step++) {
          visited.add(cur);
          cur = next[cur];
        }
        expect(visited.length, equals(5));
        expect(cur, equals(0));
        count++;
      }
      // (n-1)! Hamiltonian cycles for n=5 starting from position 0.
      expect(count, equals(24));
    });
  });
}

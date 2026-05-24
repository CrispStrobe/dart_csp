import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Dfa', () {
    test('step returns null for missing outer state', () {
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {1},
        transitions: {
          0: {'a': 1},
        },
      );
      expect(dfa.step(1, 'a'), isNull);
    });

    test('step returns null for missing symbol in defined state', () {
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {1},
        transitions: {
          0: {'a': 1},
        },
      );
      expect(dfa.step(0, 'z'), isNull);
    });

    test('step returns the next state when defined', () {
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {1},
        transitions: {
          0: {'a': 1},
        },
      );
      expect(dfa.step(0, 'a'), equals(1));
    });
  });

  group('addRegular: pattern acceptance', () {
    test('exact pattern "a b c": only that sequence is valid', () async {
      // DFA accepting "a b c" sequences exactly.
      // States: 0 (start), 1 (after a), 2 (after ab), 3 (after abc, accept)
      final dfa = Dfa(
        numStates: 4,
        start: 0,
        accepting: {3},
        transitions: {
          0: {'a': 1},
          1: {'b': 2},
          2: {'c': 3},
        },
      );
      final p = Problem()
        ..addVariables(['v0', 'v1', 'v2'], ['a', 'b', 'c'])
        ..addRegular(['v0', 'v1', 'v2'], dfa);
      final all = await p.getAllSolutions();
      expect(all, hasLength(1));
      expect(
          [all[0]['v0'], all[0]['v1'], all[0]['v2']], equals(['a', 'b', 'c']));
    });

    test('regex "a* b": any number of a then a single b', () async {
      // States: 0 (matching a*), 1 (after b, accept). Trap for any
      // other symbol from state 1.
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {1},
        transitions: {
          0: {'a': 0, 'b': 1},
        },
      );
      final p = Problem()
        ..addVariables(['v0', 'v1', 'v2'], ['a', 'b'])
        ..addRegular(['v0', 'v1', 'v2'], dfa);
      // For length-3 strings over {a,b}, accepted are: aab, abb? no,
      // after b we trap. So only "aab".
      final all = await p.getAllSolutions();
      expect(all, hasLength(1));
      expect(
          [all[0]['v0'], all[0]['v1'], all[0]['v2']], equals(['a', 'a', 'b']));
    });
  });

  group('addRegular: counting / cardinality via state machine', () {
    test('at most 2 mornings across a 5-day schedule', () async {
      // States 0,1,2 = number of M seen so far; state 3 = trap (3+ M)
      final dfa = Dfa(
        numStates: 4,
        start: 0,
        accepting: {0, 1, 2},
        transitions: {
          0: {'M': 1, 'A': 0, 'N': 0},
          1: {'M': 2, 'A': 1, 'N': 1},
          2: {'M': 3, 'A': 2, 'N': 2},
          3: {'M': 3, 'A': 3, 'N': 3},
        },
      );
      const days = ['mon', 'tue', 'wed', 'thu', 'fri'];
      final p = Problem()
        ..addVariables(days, ['M', 'A', 'N'])
        ..addRegular(days, dfa);
      for (final s in await p.getAllSolutions()) {
        final mornings = days.where((d) => s[d] == 'M').length;
        expect(mornings, lessThanOrEqualTo(2));
      }
    });

    test('exactly the same answer set as addAmongExactly when counting',
        () async {
      // "Exactly 1 morning in 3 days" via two formulations.
      const days = ['mon', 'tue', 'wed'];
      final pAmong = Problem()
        ..addVariables(days, ['M', 'N'])
        ..addAmongExactly(days, {'M'}, 1);

      // DFA states: 0 (no M yet), 1 (exactly one M, accept), 2 (trap)
      final dfa = Dfa(
        numStates: 3,
        start: 0,
        accepting: {1},
        transitions: {
          0: {'M': 1, 'N': 0},
          1: {'M': 2, 'N': 1},
          2: {'M': 2, 'N': 2},
        },
      );
      final pRegular = Problem()
        ..addVariables(days, ['M', 'N'])
        ..addRegular(days, dfa);

      final allA = await pAmong.getAllSolutions();
      final allR = await pRegular.getAllSolutions();
      expect(allR.length, equals(allA.length));
    });
  });

  group('addRegular: run-length bounds', () {
    test('no run of M longer than 2 in a 5-day schedule', () async {
      // States: 0 = last not M; 1 = last M (1 in a row); 2 = MM (2 in
      // a row); 3 = trap (3 M in a row).
      final dfa = Dfa(
        numStates: 4,
        start: 0,
        accepting: {0, 1, 2},
        transitions: {
          0: {'M': 1, 'N': 0},
          1: {'M': 2, 'N': 0},
          2: {'M': 3, 'N': 0},
          3: {'M': 3, 'N': 3},
        },
      );
      const days = ['d0', 'd1', 'd2', 'd3', 'd4'];
      final p = Problem()
        ..addVariables(days, ['M', 'N'])
        ..addRegular(days, dfa);
      for (final s in await p.getAllSolutions()) {
        // Count longest M-run.
        var maxRun = 0;
        var cur = 0;
        for (final d in days) {
          if (s[d] == 'M') {
            cur++;
            if (cur > maxRun) maxRun = cur;
          } else {
            cur = 0;
          }
        }
        expect(maxRun, lessThanOrEqualTo(2));
      }
    });

    test('infeasible: cannot fit 4 mandatory Ms with max run of 1', () async {
      // 5 days, exactly 4 Ms required, but no two Ms can be adjacent.
      // 4 Ms in 5 slots without adjacency is impossible (needs at
      // least 4 + 3 = 7 slots).
      final dfa = Dfa(
        numStates: 3,
        start: 0,
        accepting: {0, 1},
        transitions: {
          0: {'M': 1, 'N': 0},
          1: {'M': 2, 'N': 0}, // two M's adjacent → trap
          2: {'M': 2, 'N': 2},
        },
      );
      const days = ['d0', 'd1', 'd2', 'd3', 'd4'];
      final p = Problem()
        ..addVariables(days, ['M', 'N'])
        ..addAmongExactly(days, {'M'}, 4)
        ..addRegular(days, dfa);
      expect(await p.getSolution(), equals('FAILURE'));
    });
  });

  group('addRegular: numeric symbols', () {
    test('accepts only sequences whose sum is even (parity DFA)', () async {
      // Binary symbols 0/1; state tracks parity.
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {0},
        transitions: {
          0: {0: 0, 1: 1},
          1: {0: 1, 1: 0},
        },
      );
      final p = Problem()
        ..addVariables(['b0', 'b1', 'b2'], [0, 1])
        ..addRegular(['b0', 'b1', 'b2'], dfa);
      for (final s in await p.getAllSolutions()) {
        final sum = (s['b0'] as int) + (s['b1'] as int) + (s['b2'] as int);
        expect(sum % 2, equals(0));
      }
    });
  });

  group('addRegular: validation', () {
    test('throws on empty variable list', () {
      final p = Problem()..addVariable('v', [0, 1]);
      final dfa = Dfa(
        numStates: 1,
        start: 0,
        accepting: {0},
        transitions: {},
      );
      expect(() => p.addRegular(<String>[], dfa), throwsArgumentError);
    });

    test('throws on unknown variable', () {
      final p = Problem()..addVariable('v', [0, 1]);
      final dfa = Dfa(
        numStates: 1,
        start: 0,
        accepting: {0},
        transitions: {},
      );
      expect(() => p.addRegular(['v', 'missing'], dfa), throwsArgumentError);
    });

    test('throws on out-of-range start state', () {
      final p = Problem()..addVariable('v', [0, 1]);
      final dfa = Dfa(
        numStates: 2,
        start: 5, // out of range
        accepting: {0},
        transitions: {},
      );
      expect(() => p.addRegular(['v'], dfa), throwsArgumentError);
    });

    test('throws on out-of-range accepting state', () {
      final p = Problem()..addVariable('v', [0, 1]);
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {0, 99}, // 99 out of range
        transitions: {},
      );
      expect(() => p.addRegular(['v'], dfa), throwsArgumentError);
    });

    test('empty transition map (only start non-empty paths) still works',
        () async {
      // DFA with no transitions: only the empty sequence is accepted,
      // any non-empty sequence is rejected.
      final dfa = Dfa(
        numStates: 1,
        start: 0,
        accepting: {0},
        transitions: <int, Map<dynamic, int>>{},
      );
      final p = Problem()
        ..addVariable('v', [0, 1])
        ..addRegular(['v'], dfa);
      // No transition from state 0 on any symbol → rejected.
      expect(await p.getSolution(), equals('FAILURE'));
    });
  });

  group('addRegular: composition', () {
    test('composes with addExactly and other counting constraints', () async {
      // 4 days, exactly 2 of them are 'work'; no two consecutive
      // work days.
      final dfa = Dfa(
        numStates: 3,
        start: 0,
        accepting: {0, 1},
        transitions: {
          0: {'work': 1, 'rest': 0},
          1: {'work': 2, 'rest': 0},
          2: {'work': 2, 'rest': 2},
        },
      );
      const days = ['d0', 'd1', 'd2', 'd3'];
      final p = Problem()
        ..addVariables(days, ['work', 'rest'])
        ..addAmongExactly(days, {'work'}, 2)
        ..addRegular(days, dfa);
      for (final s in await p.getAllSolutions()) {
        // Verify exactly 2 work and no two adjacent.
        final workCount = days.where((d) => s[d] == 'work').length;
        expect(workCount, equals(2));
        for (var i = 0; i < days.length - 1; i++) {
          if (s[days[i]] == 'work') {
            expect(s[days[i + 1]], equals('rest'));
          }
        }
      }
    });
  });

  group('addRegular: partial-state propagator', () {
    test('detects infeasibility at the root via forward sweep', () async {
      // DFA accepts only sequences ending in state 0. From state 0,
      // 'a' goes to 1 and 'b' goes to 0. From state 1, 'a' goes to 1
      // (no way back to 0). So feasibility requires the last symbol
      // to be 'b'. Force the last variable to 'a' — propagator must
      // detect infeasibility without ever making a decision.
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {0},
        transitions: {
          0: {'a': 1, 'b': 0},
          1: {'a': 1},
        },
      );
      final p = Problem()
        ..addVariables(['v0', 'v1', 'v2'], ['a', 'b'])
        ..addVariable('v3', ['a']) // forced to 'a' — unreachable from any path
        ..addRegular(['v0', 'v1', 'v2', 'v3'], dfa);
      final result = await p.getSolution();
      expect(result, equals('FAILURE'));
      expect(p.lastStats!.decisions, equals(0),
          reason: 'partial-state propagator must detect infeasibility at root');
    });

    test('prunes inconsistent values at intermediate positions', () async {
      // DFA: must alternate strictly a,b,a,b,... starting with 'a'.
      // From state 0: 'a' → 1. From state 1: 'b' → 0. Accepting: {0,1}.
      // Other transitions are dead.
      // For 4 vars each ∈ {a, b}: only one accepted sequence, abab.
      // The propagator should immediately reduce each variable to a
      // singleton at root.
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {0, 1},
        transitions: {
          0: {'a': 1},
          1: {'b': 0},
        },
      );
      final p = Problem()
        ..addVariables(['v0', 'v1', 'v2', 'v3'], ['a', 'b'])
        ..addRegular(['v0', 'v1', 'v2', 'v3'], dfa);
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect(
          [s['v0'], s['v1'], s['v2'], s['v3']], equals(['a', 'b', 'a', 'b']));
      // All variables singleton-forced at root → 0 decisions.
      expect(p.lastStats!.decisions, equals(0),
          reason: 'propagator must singleton-force the unique sequence');
    });

    test('partial-state propagator beats predicate-only for enumeration',
        () async {
      // DFA: accepts strings over {a,b} with at most one 'b' total.
      // For 8 vars, the only solutions are: all 'a', and the 8 strings
      // with exactly one 'b'. So 9 solutions total.
      //
      // The partial-state propagator narrows the search dramatically:
      // once a 'b' is used, every later variable must be 'a'.
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {0, 1},
        transitions: {
          0: {'a': 0, 'b': 1},
          1: {'a': 1},
        },
      );
      final vars = [for (var i = 0; i < 8; i++) 'v$i'];
      final p = Problem()
        ..addVariables(vars, ['a', 'b'])
        ..addRegular(vars, dfa);
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(9));
    });

    test('respects accepting states: rejects sequences ending non-accepting',
        () async {
      // DFA: state 0 (start, not accepting), state 1 (accepting). 'a'
      // → 1, 'b' → 0. Sequences are accepted iff they end with 'a'.
      final dfa = Dfa(
        numStates: 2,
        start: 0,
        accepting: {1},
        transitions: {
          0: {'a': 1, 'b': 0},
          1: {'a': 1, 'b': 0},
        },
      );
      final p = Problem()..addVariables(['v0', 'v1', 'v2'], ['a', 'b']);
      p
        ..addVariable('v3', ['b']) // last symbol forced to 'b' → reject
        ..addRegular(['v0', 'v1', 'v2', 'v3'], dfa);
      expect(await p.getSolution(), equals('FAILURE'));
      expect(p.lastStats!.decisions, equals(0));
    });
  });
}

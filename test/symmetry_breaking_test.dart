import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('lexLeq / lexLt factory', () {
    test('lexLeq accepts equal, strictly-less, and forbids strictly-greater',
        () {
      final p = lexLeq(['A1', 'A2'], ['B1', 'B2']);
      // A == B is allowed.
      expect(p({'A1': 1, 'A2': 2, 'B1': 1, 'B2': 2}), isTrue);
      // A < B at position 0 is allowed.
      expect(p({'A1': 1, 'A2': 9, 'B1': 2, 'B2': 0}), isTrue);
      // A < B at position 1 (with equal prefix) is allowed.
      expect(p({'A1': 1, 'A2': 1, 'B1': 1, 'B2': 2}), isTrue);
      // A > B at position 0 is forbidden.
      expect(p({'A1': 2, 'A2': 0, 'B1': 1, 'B2': 9}), isFalse);
      // A > B at position 1 (with equal prefix) is forbidden.
      expect(p({'A1': 1, 'A2': 9, 'B1': 1, 'B2': 2}), isFalse);
    });

    test('lexLt rejects equal, accepts strictly-less only', () {
      final p = lexLt(['A1', 'A2'], ['B1', 'B2']);
      expect(p({'A1': 1, 'A2': 2, 'B1': 1, 'B2': 2}), isFalse); // equal
      expect(p({'A1': 1, 'A2': 1, 'B1': 1, 'B2': 2}), isTrue);
      expect(p({'A1': 1, 'A2': 9, 'B1': 1, 'B2': 2}), isFalse);
    });

    test('partial assignments do not yet violate', () {
      // Empty / partial assignments must not falsely reject; backtracking
      // relies on this.
      final p = lexLeq(['A1', 'A2'], ['B1', 'B2']);
      expect(p({}), isTrue);
      expect(p({'A1': 5}), isTrue);
      expect(p({'A1': 5, 'B1': 5}), isTrue); // tie so far → keep going
    });

    test('works on string-typed Comparable values', () {
      final p = lexLeq(['L1'], ['R1']);
      expect(p({'L1': 'alpha', 'R1': 'beta'}), isTrue);
      expect(p({'L1': 'gamma', 'R1': 'beta'}), isFalse);
    });

    test('mismatched-length sequences throw at construction', () {
      expect(() => lexLeq(['A1'], ['B1', 'B2']), throwsArgumentError);
      expect(
          () => lexLt(['A1', 'A2', 'A3'], ['B1', 'B2']), throwsArgumentError);
    });
  });

  group('Problem.addLexLeq / addLexLt — integration', () {
    test('two interchangeable 2-row blocks: lex-leq cuts solutions in half',
        () async {
      // Without symmetry-breaking: arbitrary integer values from 1..3
      // for four cells in two rows of 2. With addLexLeq, the row whose
      // values come first lex must be ≤ the second row.

      // Baseline (no symmetry-breaking).
      final base = Problem()..addVariables(['A1', 'A2', 'B1', 'B2'], [1, 2, 3]);
      final baseAll = await base.getAllSolutions();
      expect(baseAll, hasLength(3 * 3 * 3 * 3));

      // With lex-leq between (A1,A2) and (B1,B2).
      final sym = Problem()
        ..addVariables(['A1', 'A2', 'B1', 'B2'], [1, 2, 3])
        ..addLexLeq(['A1', 'A2'], ['B1', 'B2']);
      final symAll = await sym.getAllSolutions();

      // Every base solution either has row A <= row B (kept) or > (cut).
      // Solutions where rows are equal are kept. Count manually.
      var expected = 0;
      for (final s in baseAll) {
        final a = [s['A1'] as int, s['A2'] as int];
        final b = [s['B1'] as int, s['B2'] as int];
        if (a[0] < b[0] || (a[0] == b[0] && a[1] <= b[1])) expected++;
      }
      expect(symAll, hasLength(expected));
      // Every kept solution must satisfy the lex order.
      for (final s in symAll) {
        final a = [s['A1'] as int, s['A2'] as int];
        final b = [s['B1'] as int, s['B2'] as int];
        expect(a[0] < b[0] || (a[0] == b[0] && a[1] <= b[1]), isTrue,
            reason: 'kept solution violates lex-leq: $s');
      }
    });

    test('addLexLt forbids the equal case as well', () async {
      final sym = Problem()
        ..addVariables(['A1', 'A2', 'B1', 'B2'], [1, 2])
        ..addLexLt(['A1', 'A2'], ['B1', 'B2']);
      for (final s in await sym.getAllSolutions()) {
        final a = [s['A1'] as int, s['A2'] as int];
        final b = [s['B1'] as int, s['B2'] as int];
        // (a) must be strictly less than (b).
        final strictlyLess = a[0] < b[0] || (a[0] == b[0] && a[1] < b[1]);
        expect(strictlyLess, isTrue, reason: 'addLexLt allowed $s');
      }
    });

    test('addLexLeq throws on length mismatch', () {
      final p = Problem()..addVariables(['A', 'B'], [1, 2, 3]);
      expect(() => p.addLexLeq(['A'], ['B', 'A']), throwsArgumentError);
    });

    test('addLexLeq throws on unknown variable', () {
      final p = Problem()..addVariable('A', [1, 2, 3]);
      expect(() => p.addLexLeq(['A'], ['Z']), throwsArgumentError);
    });

    test('practical use: 2x2 worker assignment, interchangeable workers',
        () async {
      // Two workers W1, W2 each pick two days from {Mon, Tue, Wed, Thu}
      // (encoded 1..4). All four picks distinct. Without symmetry
      // breaking, swapping W1 and W2 is a redundant solution. lexLeq
      // on (W1Day1, W1Day2) ≤ (W2Day1, W2Day2) keeps a canonical
      // representative.

      final base = Problem()
        ..addVariables(['W1Day1', 'W1Day2', 'W2Day1', 'W2Day2'], [1, 2, 3, 4])
        ..addAllDifferent(['W1Day1', 'W1Day2', 'W2Day1', 'W2Day2']);
      final baseN = (await base.getAllSolutions()).length;

      final sym = Problem()
        ..addVariables(['W1Day1', 'W1Day2', 'W2Day1', 'W2Day2'], [1, 2, 3, 4])
        ..addAllDifferent(['W1Day1', 'W1Day2', 'W2Day1', 'W2Day2'])
        ..addLexLt(['W1Day1', 'W1Day2'], ['W2Day1', 'W2Day2']);
      final symN = (await sym.getAllSolutions()).length;

      // Every solution has a strict-lex twin (its W1↔W2 swap), so the
      // lex-broken count is exactly baseN / 2.
      expect(symN, equals(baseN ~/ 2));
      expect(baseN, equals(symN * 2));
    });
  });

  group('valuePrecedence factory', () {
    test('returns true on partial / pre-violation assignments', () {
      final p = valuePrecedence(['a', 'b', 'c'], 'r', 'g');
      // Empty / partial: no violation yet.
      expect(p({}), isTrue);
      expect(p({'a': null}), isTrue);
      // First positions don't have 'g' before 'r'.
      expect(p({'a': 'r', 'b': 'g', 'c': 'g'}), isTrue);
      expect(p({'a': 'x', 'b': 'r', 'c': 'g'}), isTrue);
    });

    test('rejects when [later] appears before [earlier]', () {
      final p = valuePrecedence(['a', 'b', 'c'], 'r', 'g');
      expect(p({'a': 'g', 'b': 'r', 'c': 'r'}), isFalse);
      // 'g' at position 1, 'r' nowhere earlier.
      expect(p({'a': 'x', 'b': 'g', 'c': 'r'}), isFalse);
    });

    test('accepts when [later] never appears', () {
      final p = valuePrecedence(['a', 'b', 'c'], 'r', 'g');
      expect(p({'a': 'x', 'b': 'y', 'c': 'z'}), isTrue);
      expect(p({'a': 'r', 'b': 'r', 'c': 'x'}), isTrue);
    });

    test('handles partial assignment conservatively', () {
      final p = valuePrecedence(['a', 'b', 'c'], 'r', 'g');
      // Unassigned 'a', then 'g' at b: predicate cannot yet conclude
      // a violation because 'a' might still become 'r'.
      expect(p({'b': 'g'}), isTrue);
    });

    test('works on integer values too', () {
      // Useful for problems whose value domain is `int` (e.g.,
      // numeric color indices, bin IDs).
      final p = valuePrecedence(['a', 'b', 'c'], 0, 1);
      expect(p({'a': 0, 'b': 1, 'c': 1}), isTrue);
      expect(p({'a': 1, 'b': 0, 'c': 0}), isFalse);
    });
  });

  group('Problem.addValuePrecedence — validation', () {
    test('throws on fewer than 2 values', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2]);
      expect(
          () => p.addValuePrecedence(['a', 'b'], <int>[]), throwsArgumentError);
      expect(() => p.addValuePrecedence(['a', 'b'], [1]), throwsArgumentError);
    });

    test('throws on duplicate values', () {
      final p = Problem()..addVariables(['a', 'b'], [1, 2, 3]);
      expect(
          () => p.addValuePrecedence(['a', 'b'], [1, 1]), throwsArgumentError);
      expect(() => p.addValuePrecedence(['a', 'b'], [1, 2, 1]),
          throwsArgumentError);
    });

    test('throws on unknown variable', () {
      final p = Problem()..addVariable('a', [1, 2]);
      expect(
          () => p.addValuePrecedence(['a', 'z'], [1, 2]), throwsArgumentError);
    });
  });

  group('Problem.addValuePrecedence — integration', () {
    test('triangle K3 + 3 colors: 6 solutions → 1 canonical', () async {
      // Triangle K3 over 3 colors. Without symmetry breaking, each
      // valid coloring has 3! = 6 equivalent relabelings, all enumerated.
      final base = Problem()
        ..addVariables(['a', 'b', 'c'], ['r', 'g', 'b'])
        ..addAllDifferent(['a', 'b', 'c']);
      final baseAll = await base.getAllSolutions();
      expect(baseAll, hasLength(6));

      // With canonical color order r ≺ g ≺ b: exactly one representative
      // (a='r', b='g', c='b').
      final sym = Problem()
        ..addVariables(['a', 'b', 'c'], ['r', 'g', 'b'])
        ..addAllDifferent(['a', 'b', 'c'])
        ..addValuePrecedence(['a', 'b', 'c'], ['r', 'g', 'b']);
      final symAll = await sym.getAllSolutions();
      expect(symAll, hasLength(1));
      expect(symAll.first['a'], equals('r'));
      expect(symAll.first['b'], equals('g'));
      expect(symAll.first['c'], equals('b'));
    });

    test('5-node path graph + 3 interchangeable colors: 3! shrink', () async {
      // Path v1-v2-v3-v4-v5. Adjacent nodes must differ. Without
      // symmetry breaking, every solution has 3! = 6 color-relabelings.
      final names = ['v1', 'v2', 'v3', 'v4', 'v5'];
      final base = Problem()..addVariables(names, ['x', 'y', 'z']);
      for (var i = 0; i + 1 < names.length; i++) {
        base.addConstraint(
            [names[i], names[i + 1]], (dynamic a, dynamic b) => a != b);
      }
      final baseN = (await base.getAllSolutions()).length;

      final sym = Problem()..addVariables(names, ['x', 'y', 'z']);
      for (var i = 0; i + 1 < names.length; i++) {
        sym.addConstraint(
            [names[i], names[i + 1]], (dynamic a, dynamic b) => a != b);
      }
      sym.addValuePrecedence(names, ['x', 'y', 'z']);
      final symN = (await sym.getAllSolutions()).length;

      // Every base solution falls into a color-permutation orbit of
      // size 3! = 6 (every path coloring uses all three colors at
      // least once, since adjacency forbids repeating after a single
      // step). The broken set has one representative per orbit.
      expect(baseN, equals(symN * 6));
    });

    test('not every value need appear: 3 vars, 4 canonical colors', () async {
      // 3 variables, 4 colors. Some colors may not appear.
      // Without sym break: 4^3 = 64 solutions.
      // With sym break under [c0, c1, c2, c3]: orbits collapse to
      // exactly the number of distinct value-MULTISETS of size 3 over
      // 4 colors where, for each color used, all earlier-canonical
      // colors are also used.
      // - All same: c0,c0,c0 (1 orbit, canonical: c0,c0,c0)
      // - Two distinct: a 'c0,c1' multiset arrangement; canonical
      //   placements are the ones where c0 strictly precedes c1.
      // - Three distinct: c0,c1,c2.
      // Enumerate brute and assert agreement.
      final names = ['a', 'b', 'c'];
      final p = Problem()
        ..addVariables(names, ['c0', 'c1', 'c2', 'c3'])
        ..addValuePrecedence(names, ['c0', 'c1', 'c2', 'c3']);
      final all = await p.getAllSolutions();
      // Brute force: enumerate all 4^3 = 64 assignments, keep those
      // that satisfy precedence on each consecutive pair.
      const colors = ['c0', 'c1', 'c2', 'c3'];
      bool precedes(List<String> seq, String earlier, String later) {
        for (final v in seq) {
          if (v == later) return false;
          if (v == earlier) return true;
        }
        return true;
      }

      var brute = 0;
      for (final a in colors) {
        for (final b in colors) {
          for (final c in colors) {
            final seq = [a, b, c];
            if (precedes(seq, 'c0', 'c1') &&
                precedes(seq, 'c1', 'c2') &&
                precedes(seq, 'c2', 'c3')) {
              brute++;
            }
          }
        }
      }
      expect(all, hasLength(brute));
      // Spot check: c0,c0,c0 must be in the set.
      expect(all.any((s) => s['a'] == 'c0' && s['b'] == 'c0' && s['c'] == 'c0'),
          isTrue);
      // And c1,... anywhere first must NOT be (no c0 precedes).
      expect(all.any((s) => s['a'] == 'c1'), isFalse);
    });

    test('values outside the canonical set are unconstrained', () async {
      // 'r' and 'g' are interchangeable; 'unique' is special.
      final names = ['a', 'b'];
      final p = Problem()
        ..addVariables(names, ['r', 'g', 'unique'])
        ..addValuePrecedence(names, ['r', 'g']);
      final all = await p.getAllSolutions();
      // Enumerate: out of 9 = 3*3, allowed are those without 'g' before 'r'.
      //   (a,b) ∈ {r,g,unique}²:
      //   - 'g' at a with no 'r' before: forbidden iff b is something that
      //     doesn't make a-precedes-g-without-r false. Actually: the
      //     constraint scans left to right; if a='g' (no 'r' seen yet),
      //     forbidden. So a != 'g' OR a == 'r' already. Wait, predicate
      //     checks: a='g' → return false. So a must NOT be 'g' (or it
      //     skipped first). Then b can be anything.
      // Forbidden: a='g'. → 3 cases (b ∈ {r,g,unique}).
      // Plus: a='unique', b='g' (no 'r' before). → 1 case.
      // Total forbidden = 4. Allowed = 5.
      expect(all, hasLength(5));
      // No solution has a='g'.
      expect(all.any((s) => s['a'] == 'g'), isFalse);
      // 'unique' present:
      expect(all.any((s) => s['a'] == 'unique'), isTrue);
    });

    test('composes with allDifferent: cuts solution count by k!', () async {
      // 4 vars each in {1..4}, all-different. Without sym break:
      // 4! = 24 permutations. With sym break under [1,2,3,4]: only
      // the identity remains.
      final names = ['v0', 'v1', 'v2', 'v3'];
      final p = Problem()
        ..addVariables(names, [1, 2, 3, 4])
        ..addAllDifferent(names)
        ..addValuePrecedence(names, [1, 2, 3, 4]);
      final all = await p.getAllSolutions();
      expect(all, hasLength(1));
      expect(all.first, {'v0': 1, 'v1': 2, 'v2': 3, 'v3': 4});
    });
  });
}

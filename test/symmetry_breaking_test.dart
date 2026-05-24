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
}

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Build a fresh N-queens problem with the standard binary
/// constraints (no row/column reuse, no diagonal attacks).
Problem _queens(int n) {
  final p = Problem();
  final cols = [for (var i = 1; i <= n; i++) i];
  final names = [for (var i = 1; i <= n; i++) 'Q$i'];
  p.addVariables(names, cols);
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final qi = names[i];
      final qj = names[j];
      final di = j - i;
      p.addConstraint(
          <String>[qi, qj],
          (dynamic a, dynamic b) =>
              a != b && (a as int) - (b as int) != di && a - b != -di);
    }
  }
  return p;
}

void main() {
  group('Problem.solveWithLcg — parity vs getSolution (M1)', () {
    test('trivial sat: returns a solution shape matching getSolution',
        () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      final viaPlain = await p.getSolution();
      final viaLcg = await p.solveWithLcg();
      expect(viaPlain, isA<Map<String, dynamic>>());
      expect(viaLcg, isA<Map<String, dynamic>>());
      // Both must satisfy the constraint.
      final mLcg = viaLcg as Map<String, dynamic>;
      expect(mLcg['A'] != mLcg['B'], isTrue);
    });

    test('unsat returns FAILURE on both paths', () async {
      final p = Problem()
        ..addVariables(['A', 'B'], [1])
        ..addStringConstraint('A != B');
      expect(await p.getSolution(), 'FAILURE');
      expect(await p.solveWithLcg(), 'FAILURE');
    });

    test('4-queens: solveWithLcg finds the same set of valid placements',
        () async {
      // Both runs explore the same tree (same picker, same propagation),
      // so they return identical first solutions.
      final pPlain = _queens(4);
      final pLcg = _queens(4);
      final viaPlain = await pPlain.getSolution();
      final viaLcg = await pLcg.solveWithLcg();
      expect(viaPlain, isA<Map<String, dynamic>>());
      expect(viaLcg, isA<Map<String, dynamic>>());
      expect(viaLcg, viaPlain,
          reason: 'M1 LCG path must match plain getSolution exactly');
    });

    test('8-queens: solveWithLcg yields a valid placement', () async {
      final p = _queens(8);
      final result = await p.solveWithLcg();
      expect(result, isA<Map<String, dynamic>>());
      final m = result as Map<String, dynamic>;
      expect(m.length, 8);
      // No two queens share a column.
      final cols = m.values.cast<int>().toSet();
      expect(cols.length, 8);
    });

    test('global all-different problem matches plain solve', () async {
      Problem makeProblem() => Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);

      final viaPlain = await makeProblem().getSolution();
      final viaLcg = await makeProblem().solveWithLcg();
      expect(viaLcg, viaPlain,
          reason: 'M1 LCG must not change deterministic search order');
    });

    test('lastStats is populated after solveWithLcg', () async {
      CSP.lastStats = null;
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      await p.solveWithLcg();
      expect(CSP.lastStats, isNotNull);
    });

    test('cancellation: a pre-cancelled token returns FAILURE', () async {
      final token = CancellationToken()..cancel();
      final p = Problem()
        ..addVariables(['A', 'B'], [1, 2, 3])
        ..addStringConstraint('A != B');
      final result = await p.solveWithLcg(cancelToken: token);
      expect(result, 'FAILURE');
    });
  });
}

@TestOn('vm || browser')
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Domain representations must work under **dart2js**, where `int` is a JS
/// double and `Uint64List` cannot be allocated at all (it throws
/// `UnsupportedError` on construction).
///
/// The bitset rep was already disabled on dart2js at the dispatcher
/// ([_classifyDomain]), but two *promotion* sites were not: an
/// interval-backed variable turns into a bitset the first time a filter
/// punches a hole in its range. That is not an exotic path — it is what
/// happens to every contiguous integer domain under an all-different
/// propagator, i.e. every Sudoku-shaped model. The result was that on the
/// web the solver threw `Unsupported operation: Uint64List not supported on
/// the web` during the very first propagation, and every caller saw an
/// unsolvable problem.
///
/// The whole suite never ran on a browser platform, so nothing caught it.
/// These tests exist to be run with `dart test -p chrome` as well as on the
/// VM; on the VM they are ordinary solver tests and stay green either way.
void main() {
  group('contiguous integer domains solve on every platform', () {
    /// The minimal reproduction: contiguous domain + all-different is exactly
    /// the shape that promotes an interval to a bitset.
    test('all-different over a contiguous domain', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
        ..addAllDifferent(['A', 'B', 'C', 'D']);
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      expect({s['A'], s['B'], s['C'], s['D']}, hasLength(4));
    });

    /// A 4x4 Sudoku: rows, columns and boxes all-different over 1..4, which
    /// is the model the CrispSudoku Killer engine builds (at 9x9) and the
    /// case that actually failed in the browser.
    test('a 4x4 Sudoku model solves', () async {
      final names = <String>[];
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          names.add('c${r}_$c');
        }
      }
      final p = Problem()..addVariables(names, [1, 2, 3, 4]);
      for (var i = 0; i < 4; i++) {
        p.addAllDifferent([for (var c = 0; c < 4; c++) 'c${i}_$c']);
        p.addAllDifferent([for (var r = 0; r < 4; r++) 'c${r}_$i']);
      }
      for (var br = 0; br < 4; br += 2) {
        for (var bc = 0; bc < 4; bc += 2) {
          p.addAllDifferent([
            for (var r = br; r < br + 2; r++)
              for (var c = bc; c < bc + 2; c++) 'c${r}_$c',
          ]);
        }
      }
      final result = await p.getSolution();
      expect(result, isA<Map<String, dynamic>>());
      final s = result as Map<String, dynamic>;
      for (var r = 0; r < 4; r++) {
        expect({for (var c = 0; c < 4; c++) s['c${r}_$c']}, hasLength(4));
      }
      for (var c = 0; c < 4; c++) {
        expect({for (var r = 0; r < 4; r++) s['c${r}_$c']}, hasLength(4));
      }
    });

    /// Cage-sum arithmetic on top of all-different — the other half of the
    /// Killer model — over a contiguous domain.
    test('sum constraints over a contiguous domain', () async {
      final p = Problem()
        ..addVariables(['X', 'Y', 'Z'], [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..addAllDifferent(['X', 'Y', 'Z'])
        ..addLinearEquals(['X', 'Y', 'Z'], [1, 1, 1], 24);
      final solutions = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        expect((s['X'] as int) + (s['Y'] as int) + (s['Z'] as int), equals(24));
        solutions.add(s);
      }
      // Distinct digits 1..9 summing to 24 with 3 cells: {7,8,9} is the only
      // set, in 6 orderings.
      expect(solutions, hasLength(6));
    });

    /// Enumerating every solution walks far more of the search tree — and so
    /// far more filter/promotion paths — than finding one.
    test('exhaustive enumeration over a contiguous domain', () async {
      final p = Problem()
        ..addVariables(['A', 'B', 'C'], [1, 2, 3])
        ..addAllDifferent(['A', 'B', 'C']);
      var count = 0;
      await for (final _ in p.getSolutions()) {
        count++;
      }
      expect(count, equals(6)); // 3! permutations
    });
  });
}

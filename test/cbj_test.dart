import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Tests for conflict-directed backjumping (CBJ, Prosser 1993) on the
/// backtracking engine. Covers the flag wiring (CBJ off keeps the new
/// stats at zero; CBJ on still solves the problem), correctness
/// (CBJ enumerates the same solution set as plain backtracking on
/// classic problems), composition (CBJ + restarts / dom-wdeg /
/// forward checking / optimization), measurable backjump activity on
/// a hand-crafted instance, and edge cases (unsat, trivial sat,
/// empty conflict at root).
void main() {
  group('CBJ wiring', () {
    test('flag off keeps backjump stats at zero', () async {
      final p = _nQueens(6);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
      expect(p.lastStats!.backjumps, 0);
      expect(p.lastStats!.backjumpLevelsSkipped, 0);
    });

    test('flag on still solves 6-queens', () async {
      final p = _nQueens(6);
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertValidQueens(sol as Map<String, dynamic>, 6);
    });

    test('flag is accepted on every backtracking entry point', () async {
      // Just exercise the plumbing — every entry point must accept the
      // parameter and pass it through to the engine without throwing.
      final p1 = _nQueens(5);
      expect(await p1.getSolution(enableConflictBackjumping: true),
          isA<Map<String, dynamic>>());
      final p2 = _nQueens(5);
      final stream = p2.getSolutions(enableConflictBackjumping: true);
      expect(await stream.first, isA<Map<String, dynamic>>());
      final p3 = _nQueens(5);
      expect(
          await p3.getSolutionWithRestarts(
              enableConflictBackjumping: true, seed: 1, scale: 50),
          isA<Map<String, dynamic>>());
      final p4 = _nQueens(5);
      expect(await p4.getSolutionWithDomWdeg(enableConflictBackjumping: true),
          isA<Map<String, dynamic>>());
      final p5 = _smallOptimization();
      expect(await p5.minimize('c', enableConflictBackjumping: true),
          isA<Map<String, dynamic>>());
      final p6 = _smallOptimization();
      expect(await p6.maximize('c', enableConflictBackjumping: true),
          isA<Map<String, dynamic>>());
    });
  });

  group('CBJ correctness — enumeration matches plain backtracking', () {
    test('6-queens enumeration: same solution set with CBJ on/off', () async {
      final solsA = await _nQueens(6).getSolutions().toList();
      final solsB = await _nQueens(6)
          .getSolutions(enableConflictBackjumping: true)
          .toList();
      expect(solsB.length, solsA.length);
      final keysA = solsA.map((s) => _queensKey(s, 6)).toSet();
      final keysB = solsB.map((s) => _queensKey(s, 6)).toSet();
      expect(keysB, keysA);
    });

    test('map-coloring enumeration: same set with CBJ on/off', () async {
      final solsA = await _mapColoring().getSolutions().toList();
      final solsB = await _mapColoring()
          .getSolutions(enableConflictBackjumping: true)
          .toList();
      expect(solsB.length, solsA.length);
      final keysA =
          solsA.map((s) => _mapColoringKey(s, _mapColoringRegions)).toSet();
      final keysB =
          solsB.map((s) => _mapColoringKey(s, _mapColoringRegions)).toSet();
      expect(keysB, keysA);
    });

    test('minimize: CBJ on and off both find the optimum', () async {
      // Optimization problem: x + y + z subject to x + y + z >= 10
      // and each in {1..5}. Optimum is 10 (any partition summing to 10).
      Problem mk() {
        final p = Problem()
          ..addVariables(['x', 'y', 'z'], [1, 2, 3, 4, 5])
          ..addVariable('c', [10, 11, 12, 13, 14, 15]);
        p.addLinearGeq(['x', 'y', 'z'], [1, 1, 1], 10);
        p.addLinearEquals(['x', 'y', 'z', 'c'], [1, 1, 1, -1], 0);
        return p;
      }

      final a = mk();
      final b = mk();
      final solA = await a.minimize('c');
      final solB = await b.minimize('c', enableConflictBackjumping: true);
      expect((solA as Map)['c'], 10);
      expect((solB as Map)['c'], 10);
    });
  });

  group('CBJ engagement', () {
    test('pigeonhole-via-pairwise triggers backjumps', () async {
      // Five vars X1..X5 in {1, 2, 3, 4} with pairwise binary
      // inequality (deliberately not using `addAllDifferent`, whose
      // Régin propagator detects the pigeonhole infeasibility at the
      // root). Pairwise inequality only reduces neighbouring domains
      // after a value is committed, so the wipeout surfaces deep in
      // the search tree (when the fifth assigned variable runs out
      // of values). At that depth the conflict set is non-empty and
      // CBJ's `backjumps` counter must be greater than zero.
      Problem mk() {
        final p = Problem()
          ..addVariables(['X1', 'X2', 'X3', 'X4', 'X5'], [1, 2, 3, 4]);
        for (var i = 1; i <= 5; i++) {
          for (var j = i + 1; j <= 5; j++) {
            p.addConstraint(['X$i', 'X$j'], (dynamic a, dynamic b) => a != b);
          }
        }
        return p;
      }

      final p = mk();
      final result = await p.getSolution(enableConflictBackjumping: true);
      expect(result, 'FAILURE');
      expect(p.lastStats!.backjumps, greaterThan(0));
    });
  });

  group('CBJ composition with other search modes', () {
    test('CBJ + forward checking finds a 6-queens solution', () async {
      final p = _nQueens(6);
      final sol = await p.getSolution(
        consistency: ConsistencyLevel.forwardChecking,
        enableConflictBackjumping: true,
      );
      expect(sol, isA<Map<String, dynamic>>());
      _assertValidQueens(sol as Map<String, dynamic>, 6);
    });

    test('CBJ + restarts finds a 6-queens solution', () async {
      final p = _nQueens(6);
      final sol = await p.getSolutionWithRestarts(
        enableConflictBackjumping: true,
        seed: 7,
        scale: 50,
      );
      expect(sol, isA<Map<String, dynamic>>());
      _assertValidQueens(sol as Map<String, dynamic>, 6);
    });

    test('CBJ + dom/wdeg finds a 6-queens solution', () async {
      final p = _nQueens(6);
      final sol =
          await p.getSolutionWithDomWdeg(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      _assertValidQueens(sol as Map<String, dynamic>, 6);
    });
  });

  group('CBJ edge cases', () {
    test('unsat returns FAILURE; matches plain BT', () async {
      // 2-coloring of K4 is unsatisfiable.
      Problem mk() {
        final p = Problem()..addVariables(['a', 'b', 'c', 'd'], [0, 1]);
        for (final pair in [
          ['a', 'b'],
          ['a', 'c'],
          ['a', 'd'],
          ['b', 'c'],
          ['b', 'd'],
          ['c', 'd'],
        ]) {
          p.addConstraint([pair[0], pair[1]], (dynamic x, dynamic y) => x != y);
        }
        return p;
      }

      expect(await mk().getSolution(), 'FAILURE');
      expect(
          await mk().getSolution(enableConflictBackjumping: true), 'FAILURE');
    });

    test('trivially sat: single var, single value', () async {
      final p = Problem()..addVariable('x', [42]);
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      expect((sol as Map)['x'], 42);
      expect(p.lastStats!.backjumps, 0);
      expect(p.lastStats!.backjumpLevelsSkipped, 0);
    });

    test('no-constraint problem solves without backjumps', () async {
      final p = Problem()..addVariables(['a', 'b', 'c'], [1, 2, 3]);
      final sol = await p.getSolution(enableConflictBackjumping: true);
      expect(sol, isA<Map<String, dynamic>>());
      expect(p.lastStats!.backjumps, 0);
    });
  });
}

// -----------------------------------------------------------------------------
// Test helpers.
// -----------------------------------------------------------------------------

Problem _nQueens(int n) {
  final p = Problem();
  for (var i = 0; i < n; i++) {
    p.addVariable('Q$i', List<int>.generate(n, (k) => k));
  }
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final offset = j - i;
      p.addConstraint(['Q$i', 'Q$j'], (dynamic a, dynamic b) {
        final ai = a as int, bj = b as int;
        return ai != bj && (ai - bj).abs() != offset;
      });
    }
  }
  return p;
}

void _assertValidQueens(Map<String, dynamic> sol, int n) {
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final ci = sol['Q$i'] as int;
      final cj = sol['Q$j'] as int;
      expect(ci != cj, isTrue, reason: 'rows $i,$j share column $ci');
      expect((ci - cj).abs() != j - i, isTrue,
          reason: 'rows $i,$j are diagonal: $ci,$cj');
    }
  }
}

String _queensKey(Map<String, dynamic> sol, int n) =>
    List<int>.generate(n, (i) => sol['Q$i'] as int).join(',');

const _mapColoringRegions = [
  'WA',
  'NT',
  'Q',
  'NSW',
  'V',
  'SA',
  'T',
];

Problem _mapColoring() {
  final p = Problem();
  for (final r in _mapColoringRegions) {
    p.addVariable(r, ['red', 'green', 'blue']);
  }
  for (final pair in const [
    ['WA', 'NT'],
    ['WA', 'SA'],
    ['NT', 'SA'],
    ['NT', 'Q'],
    ['Q', 'SA'],
    ['Q', 'NSW'],
    ['NSW', 'SA'],
    ['NSW', 'V'],
    ['V', 'SA'],
  ]) {
    p.addConstraint([pair[0], pair[1]], (dynamic a, dynamic b) => a != b);
  }
  return p;
}

String _mapColoringKey(Map<String, dynamic> sol, List<String> regions) =>
    regions.map((r) => sol[r]).join(',');

Problem _smallOptimization() {
  // c = a + b, each in {1..3}. minimize c → 2, maximize c → 6.
  final p = Problem()
    ..addVariables(['a', 'b'], [1, 2, 3])
    ..addVariable('c', [2, 3, 4, 5, 6]);
  p.addLinearEquals(['a', 'b', 'c'], [1, 1, -1], 0);
  return p;
}

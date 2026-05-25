/// Smoke tests for the three demos rewritten in the clean-room
/// remediation. These are not deep correctness checks; they just
/// pin the demos against silent regressions where a future API
/// change would cause `dart run example/demo.dart` to print
/// `FAILURE` instead of a real solution.
///
/// The Sudoku, magic-square, and other existing demos already have
/// their own dedicated tests in this directory.
library;

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

import '../example/demo.dart' as demo;

void main() {
  group('Bundesländer map-coloring demo', () {
    test('adjacency map is symmetric', () {
      final adj = demo.germanStateAdjacencies();
      for (final entry in adj.entries) {
        for (final neighbour in entry.value) {
          expect(
            adj[neighbour],
            contains(entry.key),
            reason:
                '${entry.key} lists $neighbour but $neighbour does not list ${entry.key}',
          );
        }
      }
    });

    test('produces a valid 4-coloring', () async {
      final adj = demo.germanStateAdjacencies();
      final palette = ['red', 'green', 'blue', 'yellow'];
      final regions = adj.keys.toList()..sort();

      final p = Problem();
      p.addVariables(regions, palette);
      final emitted = <String>{};
      for (final entry in adj.entries) {
        final a = entry.key;
        for (final b in entry.value) {
          final edge = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
          if (emitted.add(edge)) {
            p.addConstraint([a, b], (dynamic ca, dynamic cb) => ca != cb);
          }
        }
      }

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final map = solution as Map<String, dynamic>;
      expect(map.keys, unorderedEquals(adj.keys));
      for (final entry in adj.entries) {
        for (final neighbour in entry.value) {
          expect(
            map[entry.key],
            isNot(equals(map[neighbour])),
            reason: '${entry.key} and $neighbour ended up the same colour',
          );
        }
      }
    });
  });

  group('8-queens demo', () {
    test('returns a valid placement on an 8x8 board', () async {
      const n = 8;
      final p = Problem();
      final rows = [for (var i = 0; i < n; i++) 'r$i'];
      p.addVariables(rows, [for (var i = 0; i < n; i++) i]);
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final rowDelta = j - i;
          p.addConstraint([rows[i], rows[j]], (dynamic colI, dynamic colJ) {
            final ci = colI as int;
            final cj = colJ as int;
            if (ci == cj) return false;
            return (ci - cj).abs() != rowDelta;
          });
        }
      }

      final solution = await p.getSolution();
      expect(solution, isA<Map<String, dynamic>>());
      final assignment = solution as Map<String, dynamic>;
      final columns = [for (var i = 0; i < n; i++) assignment['r$i'] as int];
      expect(columns.toSet().length, equals(n),
          reason: 'two queens share a column');
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          expect((columns[i] - columns[j]).abs(), isNot(equals(j - i)),
              reason: 'queens on rows $i and $j attack along a diagonal');
        }
      }
    });
  });

  group('Manual-vs-builder ordering demo', () {
    test('both demo functions complete without throwing', () async {
      // The demos print to stdout and return void; the contract we
      // pin here is that neither path throws.
      await demo.solveAscendingChainManually();
      await demo.solveAscendingChainWithBuilder();
    });
  });
}

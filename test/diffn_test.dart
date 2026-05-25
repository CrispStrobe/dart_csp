import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Tests for `addDiffN`: 2D rectangle non-overlap constraint.
void main() {
  group('addDiffN validation', () {
    test('throws on length mismatch among the four lists', () {
      final p = Problem()..addVariables(['x0', 'y0', 'x1', 'y1'], [0, 1, 2, 3]);
      // ys shorter than xs.
      expect(() => p.addDiffN(['x0', 'x1'], ['y0'], [1, 1], [1, 1]),
          throwsArgumentError);
      // widths shorter.
      expect(() => p.addDiffN(['x0', 'x1'], ['y0', 'y1'], [1], [1, 1]),
          throwsArgumentError);
      // heights shorter.
      expect(() => p.addDiffN(['x0', 'x1'], ['y0', 'y1'], [1, 1], [1]),
          throwsArgumentError);
    });

    test('throws on unknown x variable', () {
      final p = Problem()..addVariable('y0', [0]);
      expect(
          () => p.addDiffN(['unknown'], ['y0'], [1], [1]), throwsArgumentError);
    });

    test('throws on unknown y variable', () {
      final p = Problem()..addVariable('x0', [0]);
      expect(
          () => p.addDiffN(['x0'], ['unknown'], [1], [1]), throwsArgumentError);
    });

    test('throws on negative width', () {
      final p = Problem()..addVariables(['x0', 'y0'], [0]);
      expect(() => p.addDiffN(['x0'], ['y0'], [-1], [1]), throwsArgumentError);
    });

    test('throws on negative height', () {
      final p = Problem()..addVariables(['x0', 'y0'], [0]);
      expect(() => p.addDiffN(['x0'], ['y0'], [1], [-1]), throwsArgumentError);
    });

    test('accepts empty rectangle list (no-op)', () {
      final p = Problem();
      // Doesn't throw; nothing to enforce.
      p.addDiffN([], [], [], []);
    });

    test('accepts single rectangle (nothing to constrain)', () async {
      final p = Problem()
        ..addVariable('x0', [0, 1])
        ..addVariable('y0', [0, 1])
        ..addDiffN(['x0'], ['y0'], [2], [2]);
      // One rectangle alone has no pair to overlap with — every
      // assignment over (x0, y0) is feasible.
      final all = await p.getAllSolutions();
      expect(all, hasLength(4));
    });
  });

  group('addDiffN semantics', () {
    test('two non-overlapping unit rectangles can sit anywhere disjoint',
        () async {
      // Two 1×1 rectangles in a 3×3 grid. The constraint just
      // forbids the same cell.
      final p = Problem()
        ..addVariables(['x0', 'y0', 'x1', 'y1'], [0, 1, 2])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [1, 1], [1, 1]);
      final all = await p.getAllSolutions();
      // 9 × 9 raw assignments — subtract the 9 same-cell pairs.
      expect(all, hasLength(9 * 9 - 9));
      for (final s in all) {
        final same = s['x0'] == s['x1'] && s['y0'] == s['y1'];
        expect(same, isFalse, reason: 'overlap not rejected: $s');
      }
    });

    test('two 2×2 rectangles can occupy diagonally-opposite corners', () async {
      // 4×4 placement area; two 2×2 boxes.
      final p = Problem()
        ..addVariables(['x0', 'y0', 'x1', 'y1'], [0, 1, 2])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [2, 2], [2, 2]);
      // Lower-left at (0,0) and (2,2): separated on both x and y.
      final placements = <String>{};
      for (final s in await p.getAllSolutions()) {
        placements.add('${s['x0']},${s['y0']}|${s['x1']},${s['y1']}');
      }
      // Verify the diagonal placements appear.
      expect(placements.contains('0,0|2,2'), isTrue);
      expect(placements.contains('2,2|0,0'), isTrue);
      // No placement may have boxes at the same corner.
      for (final p in placements) {
        final parts = p.split('|');
        expect(parts[0], isNot(equals(parts[1])),
            reason: 'identical corners allowed: $p');
      }
    });

    test('infeasible when two rectangles cannot coexist', () async {
      // Two 2×2 rectangles in a 2×2 grid → exactly one can fit.
      final p = Problem()
        ..addVariables(['x0', 'y0', 'x1', 'y1'], [0])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [2, 2], [2, 2]);
      // Both boxes pinned to (0,0). Overlap exact → FAILURE.
      expect(await p.getSolution(), equals('FAILURE'));
    });

    test('zero-width rectangle never conflicts with anything', () async {
      final p = Problem()
        ..addVariables(['x0', 'y0', 'x1', 'y1'], [0, 1, 2])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [0, 2], [2, 2]);
      // x0/y0's rectangle has zero width, ignored. Only the second
      // 2×2 rectangle contributes — no pair to constrain. All
      // combos feasible.
      final all = await p.getAllSolutions();
      expect(all, hasLength(3 * 3 * 3 * 3));
    });

    test('zero-height rectangle never conflicts with anything', () async {
      final p = Problem()
        ..addVariables(['x0', 'y0', 'x1', 'y1'], [0, 1, 2])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [2, 2], [0, 2]);
      // x0/y0 has zero height, ignored.
      final all = await p.getAllSolutions();
      expect(all, hasLength(3 * 3 * 3 * 3));
    });

    test('rectangles touching at an edge do NOT overlap (half-open boxes)',
        () async {
      // Two 1×1 rectangles. Place at (0,0) and (1,0): box 1 is
      // [0,1) × [0,1), box 2 is [1,2) × [0,1) — they touch at x=1
      // but the half-open intervals don't overlap.
      final p = Problem()
        ..addVariable('x0', [0])
        ..addVariable('y0', [0])
        ..addVariable('x1', [1])
        ..addVariable('y1', [0])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [1, 1], [1, 1]);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
    });
  });

  group('addDiffN integration', () {
    test('1D reduction: addDiffN with height=1 forbids same-x overlap',
        () async {
      // Two 1D segments on the x-axis (heights = 1, all y = 0).
      // addDiffN with both ys pinned at 0 reduces to 1D no-overlap
      // on the x-axis.
      const n = 3;
      final p = Problem();
      for (var i = 0; i < n; i++) {
        p.addVariable('x$i', [0, 1, 2, 3, 4, 5]);
        p.addVariable('y$i', [0]);
      }
      p.addDiffN(
          [for (var i = 0; i < n; i++) 'x$i'],
          [for (var i = 0; i < n; i++) 'y$i'],
          List<int>.filled(n, 2),
          List<int>.filled(n, 1));
      // Equivalently: addNoOverlap with widths-as-durations.
      // Validate that every solution gives 3 non-overlapping 1D
      // intervals on the x-axis.
      for (final s in await p.getAllSolutions()) {
        final ranges = [
          for (var i = 0; i < n; i++)
            (start: s['x$i'] as int, end: (s['x$i'] as int) + 2)
        ];
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            final a = ranges[i];
            final b = ranges[j];
            final overlap = a.start < b.end && b.start < a.end;
            expect(overlap, isFalse,
                reason: '1D segments overlap in $s: $a vs $b');
          }
        }
      }
    });

    test('packing 4 unit rectangles in a 2×2 grid: enumerate all', () async {
      // The 4 boxes must tile the 2×2 grid exactly. There are
      // 4! = 24 distinct labelled tilings (each box at its own cell).
      const n = 4;
      final p = Problem();
      for (var i = 0; i < n; i++) {
        p.addVariable('x$i', [0, 1]);
        p.addVariable('y$i', [0, 1]);
      }
      p.addDiffN(
          [for (var i = 0; i < n; i++) 'x$i'],
          [for (var i = 0; i < n; i++) 'y$i'],
          List<int>.filled(n, 1),
          List<int>.filled(n, 1));
      final all = await p.getAllSolutions();
      // Each of 4 boxes occupies a distinct cell of the 2×2 grid:
      // 4! = 24 tilings.
      expect(all, hasLength(24));
      // Every solution covers exactly the 4 cells once.
      for (final s in all) {
        final cells = <String>{};
        for (var i = 0; i < n; i++) {
          cells.add('${s['x$i']},${s['y$i']}');
        }
        expect(cells.length, equals(4));
      }
    });

    test('mixed sizes: 2×1 + 1×2 + 1×1 in a 3×2 area', () async {
      // Three rectangles: a 2×1 horizontal bar, a 1×2 vertical bar,
      // and a 1×1 single cell. They have to fit into a 3×2 area
      // without overlap.
      final p = Problem()
        ..addVariable('x0', [0, 1]) // 2×1 fits at x ∈ {0, 1}
        ..addVariable('y0', [0, 1]) // 2×1 fits at y ∈ {0, 1}
        ..addVariable('x1', [0, 1, 2]) // 1×2 fits at x ∈ {0, 1, 2}
        ..addVariable('y1', [0]) // 1×2 fits at y = 0 only
        ..addVariable('x2', [0, 1, 2]) // 1×1 anywhere
        ..addVariable('y2', [0, 1])
        ..addDiffN(
            ['x0', 'x1', 'x2'], ['y0', 'y1', 'y2'], [2, 1, 1], [1, 2, 1]);
      final all = await p.getAllSolutions();
      // Verify each solution is overlap-free.
      for (final s in all) {
        final rects = [
          (x: s['x0'] as int, y: s['y0'] as int, w: 2, h: 1),
          (x: s['x1'] as int, y: s['y1'] as int, w: 1, h: 2),
          (x: s['x2'] as int, y: s['y2'] as int, w: 1, h: 1),
        ];
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            final a = rects[i];
            final b = rects[j];
            final overlapX = a.x < b.x + b.w && b.x < a.x + a.w;
            final overlapY = a.y < b.y + b.h && b.y < a.y + a.h;
            expect(overlapX && overlapY, isFalse,
                reason: 'rects overlap in $s: $a vs $b');
          }
        }
      }
      expect(all.isNotEmpty, isTrue, reason: 'expected at least one tiling');
    });

    test('square packing: 2 squares of size 2 in a 4×2 strip', () async {
      // Two 2×2 squares in a 4×2 area. Side-by-side along x:
      // (0,0) and (2,0), or (2,0) and (0,0).
      final p = Problem()
        ..addVariables(['x0', 'x1'], [0, 1, 2])
        ..addVariable('y0', [0])
        ..addVariable('y1', [0])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [2, 2], [2, 2]);
      final all = await p.getAllSolutions();
      // Pairs (x0, x1) with both ∈ {0,1,2} and the 2-unit squares
      // not overlapping on the x-axis: x0 + 2 <= x1 OR x1 + 2 <= x0.
      // i.e. (0, 2) and (2, 0). That's 2 placements.
      expect(all, hasLength(2));
    });

    test('feasible when boxes separate on only one axis', () async {
      // Two 2×2 boxes, separable on y only. Pin x to same column.
      final p = Problem()
        ..addVariable('x0', [0])
        ..addVariable('x1', [0])
        ..addVariables(['y0', 'y1'], [0, 1, 2, 3])
        ..addDiffN(['x0', 'x1'], ['y0', 'y1'], [2, 2], [2, 2]);
      final all = await p.getAllSolutions();
      // y0 + 2 <= y1  OR  y1 + 2 <= y0
      // (0,2), (0,3), (1,3), (2,0), (3,0), (3,1) — 6 placements.
      expect(all, hasLength(6));
    });
  });
}

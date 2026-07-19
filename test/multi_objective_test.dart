import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('lexOptimize', () {
    test('priority order: minimize x first, then maximize y', () async {
      // x,y in 0..5, no constraints. min x -> x=0; then max y -> y=5.
      final p = Problem()
        ..addVariables(['x', 'y'], [for (var i = 0; i <= 5; i++) i]);
      final sol = await p.lexOptimize([
        const Objective.minimize('x'),
        const Objective.maximize('y'),
      ]);
      expect(sol, isA<Map<String, dynamic>>());
      expect(sol['x'], 0);
      expect(sol['y'], 5);
    });

    test('the second objective cannot trade away the first', () async {
      // Constraint x + y == 5, x,y in 0..5. max x -> x=5,y=0. Then min y is
      // already forced to 0. Swapping priority: max y first -> y=5,x=0.
      Problem build() => Problem()
        ..addVariables(['x', 'y'], [for (var i = 0; i <= 5; i++) i])
        ..addLinearEquals(['x', 'y'], [1, 1], 5);

      final xFirst = await build().lexOptimize([
        const Objective.maximize('x'),
        const Objective.maximize('y'),
      ]);
      expect(xFirst['x'], 5);
      expect(xFirst['y'], 0);

      final yFirst = await build().lexOptimize([
        const Objective.maximize('y'),
        const Objective.maximize('x'),
      ]);
      expect(yFirst['y'], 5);
      expect(yFirst['x'], 0);
    });

    test('does not mutate the receiver', () async {
      final p = Problem()..addVariables(['x'], [1, 2, 3]);
      final before = p.constraintCount;
      await p.lexOptimize([const Objective.minimize('x')]);
      expect(p.constraintCount, before);
      // still fully solvable with all original solutions
      expect(await p.countSolutions(), 3);
    });

    test('returns FAILURE when unsatisfiable', () async {
      final p = Problem()
        ..addVariables(['x'], [1, 2])
        ..addStringConstraint('x != 1')
        ..addStringConstraint('x != 2');
      expect(await p.lexOptimize([const Objective.minimize('x')]), 'FAILURE');
    });

    test('single objective matches minimize', () async {
      final p = Problem()..addVariables(['x'], [3, 1, 2]);
      final sol = await p.lexOptimize([const Objective.minimize('x')]);
      expect(sol['x'], 1);
    });

    test('empty / duplicate objectives throw', () {
      final p = Problem()..addVariables(['x'], [1]);
      expect(() => p.lexOptimize([]), throwsArgumentError);
      expect(
          () => p.lexOptimize(
              [const Objective.minimize('x'), const Objective.maximize('x')]),
          throwsArgumentError);
    });
  });

  group('paretoFront', () {
    // Classic bi-objective: choose (x, y) with x + y == 4, x,y in 0..4,
    // minimize x and minimize y. They trade off perfectly: the frontier is
    // exactly {(0,4),(1,3),(2,2),(3,1),(4,0)} — every feasible point is
    // Pareto-optimal because reducing one raises the other.
    Problem tradeoff() => Problem()
      ..addVariables(['x', 'y'], [for (var i = 0; i <= 4; i++) i])
      ..addLinearEquals(['x', 'y'], [1, 1], 4);

    test('enumerates the full non-dominated frontier', () async {
      final front = await tradeoff().paretoFront([
        const Objective.minimize('x'),
        const Objective.minimize('y'),
      ]);
      final points = front.map((s) => '${s['x']},${s['y']}').toSet();
      expect(points, {'0,4', '1,3', '2,2', '3,1', '4,0'});
    });

    test('no point in the frontier dominates another', () async {
      final front = await tradeoff().paretoFront([
        const Objective.minimize('x'),
        const Objective.minimize('y'),
      ]);
      bool dominates(Map<String, dynamic> a, Map<String, dynamic> b) {
        final axLe = (a['x'] as int) <= (b['x'] as int);
        final ayLe = (a['y'] as int) <= (b['y'] as int);
        final strict = (a['x'] as int) < (b['x'] as int) ||
            (a['y'] as int) < (b['y'] as int);
        return axLe && ayLe && strict;
      }

      for (final a in front) {
        for (final b in front) {
          if (!identical(a, b)) expect(dominates(a, b), isFalse);
        }
      }
    });

    test('dominated points are excluded from the frontier', () async {
      // x,y in 0..2 unconstrained, minimize both. Only (0,0) is
      // non-dominated; everything else is dominated by it.
      final p = Problem()
        ..addVariables(['x', 'y'], [for (var i = 0; i <= 2; i++) i]);
      final front = await p.paretoFront([
        const Objective.minimize('x'),
        const Objective.minimize('y'),
      ]);
      expect(front, hasLength(1));
      expect(front.single['x'], 0);
      expect(front.single['y'], 0);
    });

    test('three objectives (nary exclusion path)', () async {
      // x+y+z == 3, minimize all three; frontier is every feasible split.
      final p = Problem()
        ..addVariables(['x', 'y', 'z'], [for (var i = 0; i <= 3; i++) i])
        ..addLinearEquals(['x', 'y', 'z'], [1, 1, 1], 3);
      final front = await p.paretoFront([
        const Objective.minimize('x'),
        const Objective.minimize('y'),
        const Objective.minimize('z'),
      ]);
      // Every point with x+y+z==3 is Pareto-optimal (lowering any coordinate
      // forces raising another). Count of non-negative integer solutions to
      // x+y+z=3 is C(5,2) = 10.
      expect(front, hasLength(10));
      for (final s in front) {
        expect((s['x'] as int) + (s['y'] as int) + (s['z'] as int), 3);
      }
    });

    test('maxPoints caps the returned frontier', () async {
      final front = await tradeoff().paretoFront(
        [const Objective.minimize('x'), const Objective.minimize('y')],
        maxPoints: 2,
      );
      expect(front, hasLength(2));
    });

    test('mixed min/max directions', () async {
      // x + y == 4; maximize x and maximize y is contradictory-ish but the
      // frontier under (max x, max y) is still the full trade-off set.
      final front = await tradeoff().paretoFront([
        const Objective.maximize('x'),
        const Objective.maximize('y'),
      ]);
      expect(front.map((s) => '${s['x']},${s['y']}').toSet(),
          {'0,4', '1,3', '2,2', '3,1', '4,0'});
    });

    test('unsatisfiable problem yields an empty frontier', () async {
      final p = Problem()
        ..addVariables(['x'], [1])
        ..addStringConstraint('x != 1');
      expect(await p.paretoFront([const Objective.minimize('x')]), isEmpty);
    });
  });
}

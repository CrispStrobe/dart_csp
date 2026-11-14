import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  test('integer set assumptions keep their posted values across caller edits',
      () async {
    final allowed = <dynamic>{1, 3};
    final solver = IncrementalSolver(Problem()..addRangeVariable('x', 0, 4))
      ..assumeInSet('x', allowed);
    final description = solver.assumptions.single;
    allowed
      ..clear()
      ..add(2);
    expect(
        (await solver.materialize().getAllSolutions())
            .map((solution) => solution['x']),
        [1, 3]);
    expect(solver.assumptions.single, description);
    expect((await solver.solveWarm())['x'], isIn([1, 3]));
    allowed.clear();
    expect((await solver.solveWarm())['x'], isIn([1, 3]));
    solver.resetAssumptions();
    solver.assumeInSet('x', {2});
    expect(await solver.solveWarm(), {'x': 2});
  });

  test('predicate set assumptions copy noninteger and empty caller sets',
      () async {
    final allowed = <dynamic>{'red'};
    final solver =
        IncrementalSolver(Problem()..addVariable('colour', ['red', 'blue']))
          ..assumeInSet('colour', allowed);
    allowed
      ..clear()
      ..add('blue');
    expect(await solver.solve(), {'colour': 'red'});
    expect(await solver.solveWarm(), {'colour': 'red'});

    final empty = <dynamic>{};
    final impossible =
        IncrementalSolver(Problem()..addVariable('colour', ['red', 'blue']))
          ..assumeInSet('colour', empty);
    empty.add('red');
    expect(await impossible.solve(), 'FAILURE');
    expect(await impossible.solveWarm(), 'FAILURE');
  });

  test('predicate scope keeps its original arity and variable names', () async {
    for (final names in [
      ['x'],
      ['x', 'y'],
      ['x', 'y', 'z'],
    ]) {
      final original = [...names];
      final solver =
          IncrementalSolver(Problem()..addVariables(['x', 'y', 'z'], [0, 1]))
            ..assumePredicate(
                names,
                (assignment) =>
                    original.every((name) => assignment[name] == 1));
      final description = solver.assumptions.single;
      names
        ..clear()
        ..add('unknown');
      for (final result in [await solver.solve(), await solver.solveWarm()]) {
        expect(result, isA<Map<String, dynamic>>());
        for (final name in original) {
          expect((result as Map<String, dynamic>)[name], 1);
        }
      }
      expect(solver.assumptions.single, description);
    }
  });

  test('large compact ranges support all integer assumption forms', () async {
    final base = Problem()..addRangeVariable('x', 0, 1000000000);
    final solver = IncrementalSolver(base);
    solver.assumeEquals('x', 765432100);
    expect(await solver.solve(), {'x': 765432100});
    solver.resetAssumptions();
    solver.assumeNotEquals('x', 0);
    expect(await solver.solve(), {'x': 1});
    solver.resetAssumptions();
    solver.assumeInSet('x', {654321000});
    expect(await solver.solve(), {'x': 654321000});
    expect(identical(solver.materialize().variables['x'], base.variables['x']),
        isTrue);
    expect(base.variables['x'], isA<IntRangeDomain>());
  });
}

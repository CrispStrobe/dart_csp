import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

bool _holds(Atom atom, Map<String, dynamic> assignment) {
  final value = assignment[atom.varName] as int;
  return switch (atom) {
    AtomEq() => value == atom.value,
    AtomNe() => value != atom.value,
    AtomGe() => value >= atom.value,
    AtomLe() => value <= atom.value,
    AtomInScc() => throw StateError('Synthetic atom was not expanded.'),
  };
}

Set<Atom>? _premises(
    List<ImplicationEntry> trail, int before, List<Atom> atoms) {
  final result = <Atom>{};
  for (final atom in atoms) {
    var found = -1;
    for (var i = before - 1; i >= 0; i--) {
      if (trail[i].prunedAtom == atom) {
        found = i;
        break;
      }
    }
    if (found < 0 ||
        trail[found].reason is DecisionReason ||
        trail[found].reason is UnknownReason) {
      if (atom.isSynthetic) return null;
      result.add(atom);
      continue;
    }
    final antecedents = trail[found].reason.antecedents();
    if (atom.isSynthetic &&
        antecedents.isEmpty &&
        trail[found].decisionLevel > 0) {
      return null; // Existing opaque synthetic-cut fallback is not a proof.
    }
    final expanded = _premises(trail, found, antecedents);
    if (expanded == null) return null;
    result.addAll(expanded);
  }
  return result;
}

int _checkEntailment(
    List<ImplicationEntry> trail, List<Map<String, dynamic>> oracle) {
  var checked = 0;
  for (var i = 0; i < trail.length; i++) {
    final entry = trail[i];
    if (entry.prunedAtom.isSynthetic ||
        entry.reason is DecisionReason ||
        entry.reason is UnknownReason) {
      continue;
    }
    final premises = _premises(trail, i, entry.reason.antecedents());
    if (premises == null) continue;
    for (final assignment in oracle) {
      if (premises.every((atom) => _holds(atom, assignment))) {
        expect(_holds(entry.prunedAtom, assignment), isTrue,
            reason: '${entry.prunedAtom} is not entailed by $premises; '
                'independent counterexample $assignment');
      }
    }
    checked++;
  }
  return checked;
}

Problem _twoPrunes() => Problem()
  ..addVariable('a', [0, 3])
  ..addVariable('b', [1, 3])
  ..addVariable('x', [0, 1, 2])
  ..addVariable('u', [-1])
  ..addVariable('v', [-2])
  ..addAllDifferent(['a', 'x', 'u'])
  ..addAllDifferent(['b', 'x', 'v'])
  ..addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);

void main() {
  test('an oversized irregular explanation fails explicitly', () async {
    final problem = Problem()
      ..addRangeVariable('x', 0, 100001)
      ..addConstraint(
          ['x'], (Map<String, dynamic> a) => a['x'] == 0 || a['x'] == 100001);
    await expectLater(problem.solveWithLcg(), throwsUnsupportedError);
  });

  test('mixed-value scopes use opaque reasons instead of dropping premises',
      () async {
    final problem = Problem()
      ..addVariable('t', ['a', 'b'])
      ..addVariable('w', [3, 4])
      ..addVariable('x', [0, 1, 2, 3])
      ..addVariable('y', [0, 1, 'a', 3])
      ..addVariable('z', [0, 1])
      ..addVariable('d1', ['c'])
      ..addVariable('d2', [5])
      ..addAllDifferent(['y', 't', 'd1'])
      ..addAllDifferent(['y', 'w', 'd2'])
      ..addAllDifferent(['x', 'y', 'z']);
    final result = await problem.solveWithLcg();
    expect(result, isA<Map<String, dynamic>>());
    final xPrunes = CSP.lastImplicationTrail!.where((entry) =>
        entry.prunedAtom == const AtomNe('x', 0) ||
        entry.prunedAtom == const AtomNe('x', 1));
    expect(xPrunes.length, 2);
    expect(xPrunes.every((entry) => entry.reason is UnknownReason), isTrue);
  });

  test('a cumulative bound retains both partial-removal premises', () async {
    final oracle = <Map<String, dynamic>>[
      for (final a in [0, 3])
        for (final b in [1, 3])
          for (final x in [0, 1, 2])
            if (a != b && a != x && b != x)
              {'a': a, 'b': b, 'x': x, 'u': -1, 'v': -2},
    ];
    expect(await _twoPrunes().solveWithLcg(),
        {'a': 0, 'b': 1, 'x': 2, 'u': -1, 'v': -2});
    final trail = CSP.lastImplicationTrail!;
    final index =
        trail.indexWhere((entry) => entry.prunedAtom == const AtomGe('x', 2));
    expect(index, greaterThanOrEqualTo(0));
    final premises =
        _premises(trail, index, trail[index].reason.antecedents())!;
    expect(premises, contains(const AtomEq('a', 0)));
    expect(premises, contains(const AtomEq('b', 1)));
    expect(_checkEntailment(trail, oracle), greaterThanOrEqualTo(4));
    for (var seed = 0; seed < 24; seed++) {
      await _twoPrunes()
          .solveWithLcg(useIterativeCdcl: seed.isEven, seed: seed);
      _checkEntailment(CSP.lastImplicationTrail!, oracle);
    }
  });

  test('billion-range arithmetic and exact unit atoms keep short trails',
      () async {
    for (final iterative in [false, true]) {
      final equation = Problem()
        ..addRangeVariable('x', -1000000000, 1000000000)
        ..addVariable('y', [3])
        ..addLinearEquals(['x', 'y'], [2, 1], 1800000001);
      expect(await equation.solveWithLcg(useIterativeCdcl: iterative),
          {'x': 899999999, 'y': 3});
      expect(CSP.lastImplicationTrail!.length, lessThan(20));
      final point = Problem()
        ..addRangeVariable('x', 0, 1000000000)
        ..addAtomClause([const AtomEq('x', 765432100)]);
      expect(await point.solveWithLcg(useIterativeCdcl: iterative),
          {'x': 765432100});
      expect(CSP.lastImplicationTrail!.length, lessThan(10));
      final excluded = Problem()
        ..addRangeVariable('x', 0, 1000000000)
        ..addAtomClause([const AtomNe('x', 0)])
        ..addAtomClause([const AtomNe('x', 500000000)]);
      expect(
          await excluded.solveWithLcg(useIterativeCdcl: iterative), {'x': 1});
      expect(CSP.lastImplicationTrail!.map((entry) => entry.prunedAtom),
          containsAll([const AtomNe('x', 0), const AtomNe('x', 500000000)]));
      expect(CSP.lastImplicationTrail!.length, lessThan(12));
    }
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('sparse holes survive bounds, optimization, rollback and lazy shuffle',
      () async {
    Problem build() {
      final problem = Problem()..addRangeVariable('x', 0, 1000000000);
      for (var hole = 101; hole < 120; hole++) {
        problem.addAtomClause([AtomNe('x', hole)]);
      }
      return problem
        ..addLinearGeq(['x'], [1], 100)
        ..addLinearLeq(['x'], [1], 120);
    }

    expect(await build().getAllSolutions(), [
      {'x': 100},
      {'x': 120}
    ]);
    expect(await build().minimize('x'), {'x': 100});
    expect(await build().maximize('x'), {'x': 120});
    for (var seed = 0; seed < 20; seed++) {
      final result = await build().solveWithLcg(
          seed: seed, useIterativeCdcl: seed.isEven, useRestarts: seed.isEven);
      expect([100, 120], contains((result as Map<String, dynamic>)['x']));
    }
    final session = build().compile().createSession();
    for (final value in [100, 110, 120, 100, 119, 120]) {
      final result =
          await session.solve(assumptions: [CspAssumption.equals('x', value)]);
      expect(
          result.status,
          value == 100 || value == 120
              ? CspSolveStatus.satisfied
              : CspSolveStatus.infeasible);
    }
    expect(session.rootPreparationCount, 1);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('compact bound premises survive Hall and capacity explanation cuts',
      () async {
    for (final gcc in [false, true]) {
      final problem = Problem()
        ..addVariable('b', [1, 3])
        ..addRangeVariable('x', 0, 1000000000)
        ..addVariable('y', [0, 1])
        ..addVariable('z', [0, 1, 2, 3])
        ..addLinearLeq(['x'], [1], 3)
        ..addLinearLeq(['x', 'b'], [1, -1], 0);
      if (gcc) {
        problem.addGccRanges([
          'x',
          'y',
          'z'
        ], {
          for (var value = 0; value <= 3; value++) value: (min: 0, max: 1),
        });
      } else {
        problem.addAllDifferent(['x', 'y', 'z']);
      }
      final oracle = <Map<String, dynamic>>[
        for (final b in [1, 3])
          for (var x = 0; x <= b; x++)
            for (final y in [0, 1])
              for (var z = 0; z <= 3; z++)
                if ({x, y, z}.length == 3) {'b': b, 'x': x, 'y': y, 'z': z},
      ];
      await problem.solveWithLcg();
      final trail = CSP.lastImplicationTrail!;
      expect(
          trail.any((entry) =>
              entry.prunedAtom.isSynthetic &&
              entry.reason.antecedents().contains(const AtomLe('x', 1))),
          isTrue);
      expect(_checkEntailment(trail, oracle), greaterThan(0));
    }
  });

  test('80 sparse ranged models match an independent bounded oracle', () async {
    final random = Random(827461);
    for (var sample = 0; sample < 80; sample++) {
      final center = 400000000 + random.nextInt(20);
      final holes = {
        for (var i = 0; i < 3; i++) center - 3 + random.nextInt(7)
      };
      final split = center - 2 + random.nextInt(5);
      final cutoff = random.nextInt(5) - 2;
      final linear = center - 2 + random.nextInt(5);
      bool accepts(int x, int y) =>
          !holes.contains(x) && (x <= split || y >= cutoff) && x - y <= linear;
      final expected = <String>{
        for (var x = center - 3; x <= center + 3; x++)
          for (var y = -2; y <= 2; y++)
            if (accepts(x, y)) '$x,$y',
      };
      final problem = Problem()
        ..addRangeVariable('x', 0, 1000000000)
        ..addRangeVariable('y', -2, 2)
        ..addLinearGeq(['x'], [1], center - 3)
        ..addLinearLeq(['x'], [1], center + 3);
      for (final hole in holes) {
        problem.addAtomClause([AtomNe('x', hole)]);
      }
      problem
        ..addAtomClause([AtomLe('x', split), AtomGe('y', cutoff)])
        ..addLinearLeq(['x', 'y'], [1, -1], linear);
      final solutions = await problem.getAllSolutions();
      expect({
        for (final solution in solutions) '${solution['x']},${solution['y']}'
      }, expected, reason: 'sparse sample=$sample');
      final oracle = <Map<String, dynamic>>[
        for (var x = center - 3; x <= center + 3; x++)
          for (var y = -2; y <= 2; y++)
            if (accepts(x, y)) {'x': x, 'y': y},
      ];
      for (final iterative in [false, true]) {
        final result = await problem.solveWithLcg(
            useIterativeCdcl: iterative, seed: sample);
        if (expected.isEmpty) {
          expect(result, 'FAILURE');
        } else {
          final solution = result as Map<String, dynamic>;
          expect(expected, contains('${solution['x']},${solution['y']}'));
          _checkEntailment(CSP.lastImplicationTrail!, oracle);
        }
      }
    }
  });
}

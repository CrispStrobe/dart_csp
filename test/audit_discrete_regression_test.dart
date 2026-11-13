import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// These oracles enumerate the declared Cartesian product directly. Comparing
// two solver modes alone cannot detect pruning bugs shared by both modes.
Set<String> _oracle(List<List<int>> domains, bool Function(List<int>) accepts) {
  final solutions = <String>{};
  final values = List<int>.filled(domains.length, 0);

  void visit(int index) {
    if (index == domains.length) {
      if (accepts(values)) solutions.add(values.join(','));
      return;
    }
    for (final value in domains[index]) {
      values[index] = value;
      visit(index + 1);
    }
  }

  visit(0);
  return solutions;
}

Problem _variables(List<List<int>> domains) {
  final problem = Problem();
  for (var i = 0; i < domains.length; i++) {
    problem.addVariable('x$i', domains[i]);
  }
  return problem;
}

String _key(Map<String, dynamic> solution, int count) =>
    [for (var i = 0; i < count; i++) solution['x$i']].join(',');

Future<void> _checkAgainstOracle(Problem Function() build, int count,
    Set<String> expected, String context) async {
  final solutions = await build().getAllSolutions();
  final actual = {for (final solution in solutions) _key(solution, count)};
  expect(actual, expected, reason: context);
  expect(solutions.length, actual.length,
      reason: '$context: no duplicate discrete assignments');

  for (final iterative in [false, true]) {
    final solution = await build().solveWithLcg(useIterativeCdcl: iterative);
    if (expected.isEmpty) {
      expect(solution, 'FAILURE', reason: '$context iterative=$iterative');
    } else {
      expect(solution, isA<Map<String, dynamic>>(),
          reason: '$context iterative=$iterative');
      final key = _key(solution as Map<String, dynamic>, count);
      expect(expected.contains(key), isTrue,
          reason: '$context iterative=$iterative returned $key');
    }
  }
}

List<List<int>> _randomDomains(Random rng, int count, int valueCount) => [
      for (var i = 0; i < count; i++)
        (() {
          final domain = <int>[
            for (var value = -1; value < valueCount - 1; value++)
              if (rng.nextInt(3) != 0) value,
          ];
          if (domain.isEmpty) domain.add(rng.nextInt(valueCount) - 1);
          if (rng.nextBool()) domain.shuffle(rng);
          return domain;
        })(),
    ];

void main() {
  group('independent allDifferent/GCC audit regressions', () {
    const slackDomains = [
      [1, 2],
      [2, 3],
      [4],
    ];
    const slackSolutions = {'1,2,4', '1,3,4', '2,3,4'};

    test('allDifferent retains an alternating path to a free value', () async {
      await _checkAgainstOracle(
        () => _variables(slackDomains)..addAllDifferent(['x0', 'x1', 'x2']),
        3,
        slackSolutions,
        'loose allDifferent',
      );
    });

    test('GCC retains an alternating path to a free capacity copy', () async {
      await _checkAgainstOracle(
        () => _variables(slackDomains)
          ..addGccRanges([
            'x0',
            'x1',
            'x2'
          ], {
            for (var value = 1; value <= 4; value++) value: (min: 0, max: 1),
          }),
        3,
        slackSolutions,
        'loose GCC',
      );
    });

    test('120 loose and tight allDifferent instances match brute force',
        () async {
      final rng = Random(918273);
      for (var sample = 0; sample < 120; sample++) {
        final count = 3 + rng.nextInt(2);
        final valueCount = count - 1 + sample % 3;
        final domains = _randomDomains(rng, count, valueCount);
        final vars = [for (var i = 0; i < count; i++) 'x$i'];
        final expected = _oracle(
            domains, (values) => values.toSet().length == values.length);
        await _checkAgainstOracle(
          () => _variables(domains)..addAllDifferent(vars),
          count,
          expected,
          'allDifferent sample=$sample domains=$domains',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('120 ranged and exact GCC instances match brute force', () async {
      final rng = Random(736291);
      for (var sample = 0; sample < 120; sample++) {
        final count = 3 + rng.nextInt(2);
        final valueCount = count - 1 + sample % 3;
        final domains = _randomDomains(rng, count, valueCount);
        final vars = [for (var i = 0; i < count; i++) 'x$i'];
        final ranges = <int, ({int min, int max})>{};
        if (sample % 4 == 0) {
          for (var value = -1; value < valueCount - 1; value++) {
            ranges[value] = (min: 0, max: 1);
          }
        } else if (sample % 4 == 1) {
          final counts = List<int>.filled(valueCount, 0);
          for (var i = 0; i < count; i++) {
            counts[rng.nextInt(valueCount)]++;
          }
          for (var i = 0; i < valueCount; i++) {
            ranges[i - 1] = (min: counts[i], max: counts[i]);
          }
        } else {
          var lowerBudget = count;
          for (var value = -1; value < valueCount - 1; value++) {
            if (sample % 4 == 3 && rng.nextBool()) continue;
            final upper = rng.nextInt(count + 1);
            final lower =
                sample % 4 == 2 ? 0 : rng.nextInt(min(upper, lowerBudget) + 1);
            ranges[value] = (min: lower, max: upper);
            lowerBudget -= lower;
          }
        }
        final expected = _oracle(domains, (values) {
          for (final entry in ranges.entries) {
            final occurrences =
                values.where((value) => value == entry.key).length;
            if (occurrences < entry.value.min ||
                occurrences > entry.value.max) {
              return false;
            }
          }
          return true;
        });
        await _checkAgainstOracle(
          () => _variables(domains)..addGccRanges(vars, ranges),
          count,
          expected,
          'GCC sample=$sample domains=$domains ranges=$ranges',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('LCG bounds on unsorted domains', () {
    for (final example in [
      (domain: [1, 3, 0, 2], removed: 1, fixed: 0),
      (domain: [2, 1, 0, 3], removed: 3, fixed: 2),
    ]) {
      test('bound atoms hold after pruning ${example.domain}', () async {
        final p = Problem()
          ..addVariable('x', example.domain)
          ..addConstraint(
              ['x'], (Map<String, dynamic> a) => a['x'] != example.removed)
          ..addConstraint(
              ['x'], (Map<String, dynamic> a) => a['x'] == example.fixed);

        expect(await p.solveWithLcg(), {'x': example.fixed});
        final trail = CSP.lastImplicationTrail!;
        expect(trail, isNotEmpty);
        var boundCount = 0;
        for (final entry in trail) {
          final atom = entry.prunedAtom;
          if (atom is AtomGe) {
            boundCount++;
            expect(example.fixed, greaterThanOrEqualTo(atom.value),
                reason: 'root implication $atom is not entailed');
          } else if (atom is AtomLe) {
            boundCount++;
            expect(example.fixed, lessThanOrEqualTo(atom.value),
                reason: 'root implication $atom is not entailed');
          }
        }
        expect(boundCount, greaterThan(0));
      });
    }
  });
}

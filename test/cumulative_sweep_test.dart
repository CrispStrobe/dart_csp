import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

class _PollingToken extends CancellationToken {
  _PollingToken([this.limit]);

  final int? limit;
  var polls = 0;

  @override
  bool get isCancelled {
    polls++;
    if (limit != null && polls >= limit!) cancel();
    return super.isCancelled;
  }
}

Problem _model(List<List<dynamic>> domains, List<int> durations,
    List<int> demands, int capacity,
    {bool energetic = true}) {
  final problem = Problem();
  final names = [for (var i = 0; i < domains.length; i++) 's$i'];
  for (var i = 0; i < names.length; i++) {
    problem.addVariable(names[i], domains[i]);
  }
  problem.addCumulative(names, durations, demands, capacity,
      useEnergeticReasoning: energetic);
  return problem;
}

// Deliberately different from the event-swept implementation: small fixtures
// are checked by enumerating every occupied integer time in each schedule.
bool _valid(List<dynamic> starts, List<int> durations, List<int> demands,
    int capacity) {
  final usage = <int, int>{};
  for (var i = 0; i < starts.length; i++) {
    if (durations[i] == 0 || demands[i] == 0) continue;
    final start = starts[i];
    if (start is! int) return false;
    for (var t = start; t < start + durations[i]; t++) {
      usage[t] = (usage[t] ?? 0) + demands[i];
      if (usage[t]! > capacity) return false;
    }
  }
  return true;
}

String _key(Map<String, dynamic> solution, int count) =>
    [for (var i = 0; i < count; i++) solution['s$i']].join(',');

Set<String> _oracle(List<List<dynamic>> domains, List<int> durations,
    List<int> demands, int capacity) {
  final answer = <String>{};
  final starts = List<dynamic>.filled(domains.length, null);
  void visit(int i) {
    if (i == starts.length) {
      if (_valid(starts, durations, demands, capacity)) {
        answer.add(starts.join(','));
      }
      return;
    }
    for (final value in domains[i]) {
      starts[i] = value;
      visit(i + 1);
    }
  }

  visit(0);
  return answer;
}

Problem _hugePrefix() => Problem()
  ..addVariable('fixed', [0])
  ..addRangeVariable('moving', 0, 1000000000)
  ..addCumulative(['fixed', 'moving'], [1000000000, 1], [1, 1], 1);

Problem _manyAdjacent(int duration) {
  final problem = Problem();
  final names = [for (var i = 0; i < 80; i++) 's$i'];
  for (var i = 0; i < names.length; i++) {
    problem.addVariable(names[i], [i * duration]);
  }
  problem.addCumulative(names, List.filled(names.length, duration),
      List.filled(names.length, 1), 1,
      useEnergeticReasoning: false);
  return problem;
}

void main() {
  test('unsorted, negative, inactive and noninteger cases match an oracle',
      () async {
    final random = Random(746183);
    for (var sample = 0; sample < 100; sample++) {
      final count = 2 + random.nextInt(3);
      final domains = <List<dynamic>>[
        for (var i = 0; i < count; i++)
          ([
            for (var start = -3; start <= 2; start++)
              if (random.nextBool()) start,
            if (sample % 4 == 0) 'inactive',
            if (sample % 5 == 0) 0.5,
          ]..shuffle(random)),
      ];
      for (final domain in domains) {
        if (domain.isEmpty) domain.add(-1);
      }
      final durations = [for (var i = 0; i < count; i++) random.nextInt(5)];
      final demands = [for (var i = 0; i < count; i++) random.nextInt(4)];
      final capacity = random.nextInt(5);
      final expected = _oracle(domains, durations, demands, capacity);
      for (final energetic in [false, true]) {
        Problem build() =>
            _model(domains, durations, demands, capacity, energetic: energetic);
        final all = await build().getAllSolutions();
        expect({for (final solution in all) _key(solution, count)}, expected,
            reason: 'sample=$sample energetic=$energetic');
        for (final iterative in [false, true]) {
          final result = await build()
              .solveWithLcg(useIterativeCdcl: iterative, seed: sample % 7);
          if (expected.isEmpty) {
            expect(result, 'FAILURE');
          } else {
            expect(expected,
                contains(_key(result as Map<String, dynamic>, count)));
          }
        }
      }
    }
  });

  test('billion-unit adjacent tasks and negative starts are half-open',
      () async {
    final problem = _model([
      [-1000000000],
      [0],
      [1000000000],
    ], [
      1000000000,
      1000000000,
      1000000000
    ], [
      1,
      1,
      1
    ], 1);
    expect(await problem.getSolution(),
        {'s0': -1000000000, 's1': 0, 's2': 1000000000});
    final overlap = _model([
      [0],
      [999999999],
    ], [
      1000000000,
      1000000000
    ], [
      1,
      1
    ], 1);
    expect(await overlap.getSolution(), 'FAILURE');
  });

  test('billion-value prefix contraction solves with no decisions', () async {
    final session = _hugePrefix().compile().createSession();
    final result = await session.solve(maxDecisions: 0);
    expect(result.status, CspSolveStatus.satisfied);
    expect(result.solution, {'fixed': 0, 'moving': 1000000000});
    expect(result.stats.decisions, 0);
    session.close();
    for (final iterative in [false, true]) {
      expect(await _hugePrefix().solveWithLcg(useIterativeCdcl: iterative),
          {'fixed': 0, 'moving': 1000000000});
      expect(CSP.lastImplicationTrail!.length, lessThan(20));
    }
  });

  test('billion-value suffix contraction solves with no decisions', () async {
    final problem = Problem()
      ..addVariable('fixed', [0])
      ..addRangeVariable('moving', -1000000000, 999999999)
      ..addCumulative(['fixed', 'moving'], [1000000000, 1000000000], [1, 1], 1);
    expect(await problem.getSolution(), {'fixed': 0, 'moving': -1000000000});
    expect(problem.lastStats!.decisions, 0);
  });

  test('compact sparse holes can jump into the next forbidden segment',
      () async {
    for (final iterative in [false, true]) {
      final problem = Problem()
        ..addRangeVariable('moving', 0, 1000000000)
        ..addVariable('a', [0])
        ..addVariable('b', [11])
        ..addAtomClause([const AtomNe('moving', 10)])
        ..addAtomClause([const AtomNe('moving', 12)])
        ..addCumulative(['a', 'b', 'moving'], [10, 1, 1], [1, 1, 1], 1,
            useEnergeticReasoning: false);
      final result = await problem.solveWithLcg(useIterativeCdcl: iterative);
      expect(result, {'moving': 13, 'a': 0, 'b': 11});
      expect(CSP.lastImplicationTrail!.length, lessThan(30));
    }
  });

  test('retained compact interior starts are checked on pins and rollback',
      () async {
    final problem = Problem()
      ..addVariable('fixed', [500000000])
      ..addRangeVariable('moving', 0, 1000000000)
      ..addCumulative(['fixed', 'moving'], [100000000, 100000000], [1, 1], 1,
          useEnergeticReasoning: false);
    final session = problem.compile().createSession();
    for (final start in [
      0,
      400000000,
      400000001,
      500000000,
      599999999,
      600000000,
      1000000000,
      0,
    ]) {
      final expected = start <= 400000000 || start >= 600000000;
      final result = await session.solve(
          assumptions: [CspAssumption.equals('moving', start)],
          maxDecisions: 0);
      expect(result.status,
          expected ? CspSolveStatus.satisfied : CspSolveStatus.infeasible);
      if (expected) expect(result.solution!['moving'], start);
    }
    expect(session.rootPreparationCount, 1);
    session.close();
  });

  test('polling work for a fixed schedule is independent of duration',
      () async {
    final counts = <int>[];
    for (final duration in [10, 1000000000]) {
      final token = _PollingToken();
      final session = _manyAdjacent(duration).compile().createSession();
      expect((await session.solve(cancelToken: token)).isSatisfied, isTrue);
      counts.add(token.polls);
      session.close();
    }
    expect(counts.first, greaterThan(20));
    expect(counts[1], counts[0]);
    expect(counts.first, lessThan(1000));
  });

  test('interrupted profile work restores a reusable session', () async {
    final session = _manyAdjacent(1000000000).compile().createSession();
    final stopped = await session.solve(cancelToken: _PollingToken(12));
    expect(stopped.status, CspSolveStatus.cancelled);
    expect(stopped.stats.decisions, 0);
    expect(stopped.stats.backtracks, 0);
    final retry = await session.solve();
    expect(retry.isSatisfied, isTrue);
    expect(session.rootPreparationCount, 2);
    session.close();
  });

  test('interruption does not create an LCG conflict', () async {
    for (final iterative in [false, true]) {
      final problem = _manyAdjacent(1000000000);
      expect(
          await problem.solveWithLcg(
              cancelToken: _PollingToken(12), useIterativeCdcl: iterative),
          'FAILURE');
      expect(problem.lastStats!.learnedClauses, 0);
      expect(problem.lastStats!.backtracks, 0);
    }
  });

  test('inactive tasks accept arbitrary finite-domain values in all APIs',
      () async {
    Problem build() => _model([
          ['zero-duration'],
          [0.5],
          [0],
        ], [
          0,
          1000000000,
          1
        ], [
          100,
          0,
          1
        ], 1);
    final expected = {'s0': 'zero-duration', 's1': 0.5, 's2': 0};
    expect(await build().getSolution(), expected);
    final session = build().compile().createSession();
    expect((await session.solve()).solution, expected);
    session.close();
  });

  test('active noninteger starts are rejected instead of bypassing the tag',
      () async {
    expect(
        await _model([
          [0.5]
        ], [
          1
        ], [
          1
        ], 1)
            .getSolution(),
        'FAILURE');
    final session = _model([
      [0.5, 2]
    ], [
      1
    ], [
      1
    ], 1)
        .compile()
        .createSession();
    expect((await session.solve()).solution, {'s0': 2});
    session.close();
  });

  test('mixed candidate checks sweep long tasks and snapshot caller lists',
      () async {
    final starts = ['a', 'b'];
    final durations = [1000000000, 1000000000];
    final demands = [1, 1];
    final problem = Problem()
      ..addVariable('a', [0])
      ..addVariable('b', [1000000000])
      ..addFloatVariable('real', 0, 0)
      ..addCumulative(starts, durations, demands, 1);
    starts[0] = 'missing';
    durations[0] = 2000000000;
    demands[0] = 100;
    final result = await problem.getSolutionDetailed();
    expect(result.status, MixedSolveStatus.satisfied);
    expect(result.solution, {'a': 0, 'b': 1000000000, 'real': 0.0});
  });
}

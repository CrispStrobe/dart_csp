import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

typedef Literal = ({int variable, bool positive});

bool satisfies(List<List<Literal>> clauses, int assignment) =>
    clauses.every((clause) => clause.any((literal) =>
        ((assignment >> literal.variable) & 1) == (literal.positive ? 1 : 0)));

Problem booleanProblem(int count, List<List<Literal>> clauses) {
  final p = Problem();
  for (var i = 0; i < count; i++) {
    p.addVariable('v$i', [0, 1]);
  }
  for (final clause in clauses) {
    p.addClause(positive: [
      for (final l in clause)
        if (l.positive) 'v${l.variable}'
    ], negative: [
      for (final l in clause)
        if (!l.positive) 'v${l.variable}'
    ]);
  }
  return p;
}

CspProblem rawBooleanProblem(int count, List<List<Literal>> clauses) =>
    CspProblem(variables: {
      for (var i = 0; i < count; i++) 'v$i': <dynamic>[0, 1]
    }, naryConstraints: [
      for (final clause in clauses)
        NaryConstraint(
          vars: clause.map((l) => 'v${l.variable}').toSet().toList(),
          clauseSpec: ClauseSpec(literals: [
            for (final l in clause)
              (varName: 'v${l.variable}', positive: l.positive)
          ]),
          predicate: (assignment) => clause.any((l) =>
              !assignment.containsKey('v${l.variable}') ||
              assignment['v${l.variable}'] == (l.positive ? 1 : 0)),
        )
    ]);

int encode(Map<String, dynamic> assignment, int count) {
  var mask = 0;
  for (var i = 0; i < count; i++) {
    mask |= (assignment['v$i'] as int) << i;
  }
  return mask;
}

void main() {
  test('a non-watched variable visits no clauses despite high static adjacency',
      () async {
    const count = 512;
    final p = Problem()
      ..addVariable('a', [1])
      ..addVariable('b', [1])
      ..addVariable('trigger', [0, 1]);
    for (var i = 0; i < count; i++) {
      p.addClause(positive: ['a', 'b', 'trigger']);
    }
    final compiled = p.compile();
    expect(compiled.constraintIdsByVariable['trigger'], hasLength(count));
    final session = compiled.createSession();
    final cold = await session.solve();
    expect(cold.isSatisfied, isTrue);
    expect(cold.stats.clausePropagatorCalls, count);
    final warm = await session
        .solve(assumptions: [const CspAssumption.equals('trigger', 1)]);
    expect(warm.isSatisfied, isTrue);
    expect(warm.stats.clauseWatchVisits, 0);
    expect(warm.stats.clausePropagatorCalls, 0);
    expect(warm.stats.clauseLiteralChecks, 0);
    expect(warm.stats.clauseEnqueues, 0);
    session.close();
  });

  test('watch movement and rollback preserve independent enumeration truth',
      () async {
    final clauses = <List<Literal>>[
      [
        (variable: 0, positive: true),
        (variable: 1, positive: true),
        (variable: 2, positive: true),
        (variable: 3, positive: true)
      ],
      [
        (variable: 0, positive: false),
        (variable: 1, positive: false),
        (variable: 2, positive: false)
      ],
    ];
    final p = booleanProblem(4, clauses);
    final actual = <int>{};
    await for (final solution in p.getSolutions()) {
      actual.add(encode(solution, 4));
    }
    final expected = {
      for (var mask = 0; mask < 16; mask++)
        if (satisfies(clauses, mask)) mask
    };
    expect(actual, expected);
    expect(p.lastStats!.clauseWatchMoves, greaterThan(0));
    expect(p.lastStats!.clauseUnitPropagations, greaterThan(0));
    expect(
        p.lastStats!.clauseValuesRemoved, p.lastStats!.clauseUnitPropagations);
  });

  test(
      'failed and degenerate watches repair across successive assumption queries',
      () async {
    final p = Problem()
      ..addVariables(['a', 'b', 'c', 'd'], [0, 1])
      ..addClause(positive: ['a', 'b', 'c', 'd']);
    final session = p.compile().createSession();
    expect((await session.solve()).isSatisfied, isTrue);
    final impossible = await session.solve(assumptions: [
      for (final v in ['a', 'b', 'c', 'd']) CspAssumption.equals(v, 0),
    ]);
    expect(impossible.status, CspSolveStatus.infeasible);
    expect(impossible.stats.clauseConflicts, greaterThan(0));
    for (var round = 0; round < 3; round++) {
      for (final free in ['a', 'b', 'c', 'd']) {
        final result = await session.solve(assumptions: [
          for (final v in ['a', 'b', 'c', 'd'])
            if (v != free) CspAssumption.equals(v, 0),
        ]);
        expect(result.isSatisfied, isTrue);
        expect(result.solution![free], 1);
        expect(result.stats.decisions, 0,
            reason: 'Unit propagation must force $free.');
        expect(result.stats.clauseUnitPropagations, greaterThan(0));
      }
    }
    session.close();
  });

  test('random Boolean clauses match an exhaustive oracle', () async {
    const count = 7;
    for (var seed = 0; seed < 12; seed++) {
      final random = Random(seed);
      final clauses = <List<Literal>>[
        for (var c = 0; c < 13; c++)
          [
            for (var i = 0; i < 3 + random.nextInt(3); i++)
              (variable: random.nextInt(count), positive: random.nextBool())
          ],
      ];
      final p = booleanProblem(count, clauses);
      final expected = {
        for (var mask = 0; mask < 1 << count; mask++)
          if (satisfies(clauses, mask)) mask
      };
      final actual = <int>{};
      await for (final solution in p.getSolutions()) {
        actual.add(encode(solution, count));
      }
      expect(actual, expected, reason: 'seed=$seed');
      final learned = await CSP.solveWithLcg(rawBooleanProblem(count, clauses),
          learnedClauseCap: 2, useRestarts: true, restartScale: 2);
      expect(learned is Map<String, dynamic>, expected.isNotEmpty,
          reason: 'LCG seed=$seed');
      if (learned is Map<String, dynamic>) {
        expect(expected, contains(encode(learned, count)));
      }
    }
  });

  test('atom watches preserve bounds and disequality through session expansion',
      () async {
    bool valid(int x, int y, int z) =>
        (x <= 0 || y >= 2 || z != 1) && (x == 1 || y <= 1 || z >= 2);
    final p = Problem()
      ..addVariable('x', [2, 0, 1])
      ..addVariable('y', [1, 2, 0])
      ..addVariable('z', [0, 1, 2])
      ..addAtomClause(
          [const AtomLe('x', 0), const AtomGe('y', 2), const AtomNe('z', 1)])
      ..addAtomClause(
          [const AtomEq('x', 1), const AtomLe('y', 1), const AtomGe('z', 2)]);
    final expected = <(int, int, int)>{
      for (var x = 0; x < 3; x++)
        for (var y = 0; y < 3; y++)
          for (var z = 0; z < 3; z++)
            if (valid(x, y, z)) (x, y, z)
    };
    final actual = <(int, int, int)>{};
    await for (final solution in p.getSolutions()) {
      actual.add(
          (solution['x'] as int, solution['y'] as int, solution['z'] as int));
    }
    expect(actual, expected);
    final session = p.compile().createSession();
    for (var repeat = 0; repeat < 2; repeat++) {
      for (var x = 0; x < 3; x++) {
        for (var y = 0; y < 3; y++) {
          final result = await session.solve(assumptions: [
            CspAssumption.equals('x', x),
            CspAssumption.equals('y', y)
          ]);
          expect(
              result.isSatisfied, expected.any((e) => e.$1 == x && e.$2 == y));
          if (result.isSatisfied) {
            expect(valid(x, y, result.solution!['z'] as int), isTrue);
          }
        }
      }
    }
    session.close();
  });

  test('small learned-clause pools remove reverse indexes and retain verdicts',
      () async {
    const pigeons = 4, holes = 3;
    final clauses = <List<Literal>>[
      for (var p = 0; p < pigeons; p++)
        [
          for (var h = 0; h < holes; h++)
            (variable: p * holes + h, positive: true)
        ],
      for (var h = 0; h < holes; h++)
        for (var p = 0; p < pigeons; p++)
          for (var q = p + 1; q < pigeons; q++)
            [
              (variable: p * holes + h, positive: false),
              (variable: q * holes + h, positive: false)
            ],
    ];
    expect([
      for (var mask = 0; mask < 1 << (pigeons * holes); mask++)
        if (satisfies(clauses, mask)) mask
    ], isEmpty);
    final result = await CSP.solveWithLcg(
        rawBooleanProblem(pigeons * holes, clauses),
        learnedClauseCap: 1,
        useRestarts: true,
        restartScale: 2);
    expect(result, 'FAILURE');
    final stats = CSP.lastStats!;
    expect(stats.learnedClauses, greaterThan(1));
    expect(stats.forgottenClauses, greaterThan(0));
    expect(stats.clauseForgetPasses, greaterThan(0));
    expect(stats.forgottenUnusedClauses,
        lessThanOrEqualTo(stats.forgottenClauses));
    expect(stats.learnedClauseUses, greaterThan(0));
    expect(stats.lcgAnalysisCalls, greaterThan(0));
    expect(stats.lcgAnalysisTrailEntries, greaterThan(0));
    expect(stats.lcgAnalysisReasons, greaterThan(0));
    expect(stats.lcgAnalysisReasonLiterals, greaterThan(0));
    expect(stats.lcgAnalysisResolutions, greaterThan(0));
    expect(
        stats.lcgLearnedLiterals, greaterThanOrEqualTo(stats.learnedClauses));
    expect(stats.lcgAnalysisMicros, greaterThanOrEqualTo(0));
  });

  test('an imported clause initializes even when its scope has no seed',
      () async {
    // These two clauses imply v1=1 without unit propagation at the root.
    // VSIDS initially picks v0, which is outside the imported clause's scope.
    final clauses = <List<Literal>>[
      [(variable: 1, positive: true), (variable: 2, positive: true)],
      [(variable: 1, positive: true), (variable: 2, positive: false)],
    ];
    var imported = false;
    final result = await CSP.solveWithLcg(rawBooleanProblem(3, clauses),
        useVsids: true, importClauses: () {
      if (imported) return const [];
      imported = true;
      return const [
        [AtomEq('v1', 1)]
      ];
    });
    expect(result, isA<Map<String, dynamic>>());
    final assignment = result as Map<String, dynamic>;
    expect(satisfies(clauses, encode(assignment, 3)), isTrue);
    expect(assignment['v1'], 1);
    expect(CSP.lastStats!.importedClauses, 1);
    expect(CSP.lastStats!.learnedClauseUses, 1);
    expect(CSP.lastStats!.clauseUnitPropagations, 1);
    expect(CSP.lastStats!.decisions, 2);
  });

  test('analysis work instrumentation preserves the exact learned clause', () {
    const trail = [
      ImplicationEntry(
          prunedAtom: AtomEq('a', 1),
          reason: DecisionReason(),
          trailIndex: 0,
          decisionLevel: 1),
      ImplicationEntry(
          prunedAtom: AtomEq('b', 1),
          reason: DecisionReason(),
          trailIndex: 1,
          decisionLevel: 2),
      ImplicationEntry(
          prunedAtom: AtomEq('c', 1),
          reason: ClauseReason([AtomEq('a', 1), AtomEq('b', 1)]),
          trailIndex: 2,
          decisionLevel: 2),
    ];
    const reason = ClauseReason([AtomEq('b', 1), AtomEq('c', 1)]);
    final without = firstUipAnalyse(trail, reason)!;
    final work = AnalysisWork();
    final withWork = firstUipAnalyse(trail, reason, work: work)!;
    expect(withWork.learnedClause, without.learnedClause);
    expect(withWork.uipAtom, without.uipAtom);
    expect(withWork.backjumpLevel, without.backjumpLevel);
    expect(work.trailEntries, 3);
    expect(work.reasonExpansions, 2);
    expect(work.reasonLiterals, 4);
    expect(work.resolutions, 1);
    work.reset();
    expect(work.reasonExpansions, 0);
  });

  test('new work counters survive serialization and snapshots', () {
    final counters = <String, int>{
      'clauseWatchVisits': 1,
      'clauseEnqueues': 2,
      'clausePropagatorCalls': 3,
      'clauseLiteralChecks': 4,
      'clauseWatchMoves': 5,
      'clauseWatchRepairs': 6,
      'clauseUnitPropagations': 7,
      'clauseValuesRemoved': 8,
      'clauseConflicts': 9,
      'learnedClauseUses': 10,
      'forgottenUnusedClauses': 11,
      'clauseForgetPasses': 12,
      'lcgAnalysisCalls': 13,
      'lcgAnalysisMicros': 14,
      'lcgAnalysisTrailEntries': 15,
      'lcgAnalysisReasons': 16,
      'lcgAnalysisReasonLiterals': 17,
      'lcgAnalysisResolutions': 18,
      'lcgLearnedLiterals': 19,
    };
    final stats = SolverStats.fromMap(counters);
    final copy = stats.snapshot();
    for (final entry in counters.entries) {
      expect(copy.toMap()[entry.key], entry.value);
    }
    stats.clauseWatchVisits = 900;
    expect(copy.clauseWatchVisits, 1);
    final legacy = SolverStats.fromMap({'decisions': 3});
    expect(legacy.decisions, 3);
    for (final name in counters.keys) {
      expect(legacy.toMap()[name], 0);
    }
  });
}

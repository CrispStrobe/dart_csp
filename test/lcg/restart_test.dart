/// LCG M4 — Luby restarts with learned-clause + activity retention
/// (`useRestarts: true` on `solveWithLcg`, iterative CDCL engine).
///
/// A restart drops the search tree back to the root but keeps the
/// learned-clause pool, the activity / wdeg tables, and the per-variable
/// saved phase (Pipatsrisawat & Darwiche 2007). Coverage:
///
///   1. **Soundness** — Inkala (allDiff + GCC) with restarts *forced* by a
///      tiny budget still solves the unique puzzle correctly across seeds
///      (the restart-to-root + learned-clause-pool path on integer / atom
///      clauses).
///   2. **Verdict parity** — on random 3-SAT, restarts-on agrees with plain
///      backtracking on SAT/UNSAT and returns a valid assignment.
///   3. **Retained search state** — fixed, tiny clauses force a restart,
///      then expose saved-phase selection and learned-clause propagation
///      through public decision snapshots. These checks do not require a
///      particular random search order or a performance improvement.
library;

// These tests target the iterative engine specifically, so they keep
// `useIterativeCdcl: true` explicit even though it is now the default.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

const _hardestSudoku = [
  [8, 0, 0, 0, 0, 0, 0, 0, 0],
  [0, 0, 3, 6, 0, 0, 0, 0, 0],
  [0, 7, 0, 0, 9, 0, 2, 0, 0],
  [0, 5, 0, 0, 0, 7, 0, 0, 0],
  [0, 0, 0, 0, 4, 5, 7, 0, 0],
  [0, 0, 0, 1, 0, 0, 0, 3, 0],
  [0, 0, 1, 0, 0, 0, 0, 6, 8],
  [0, 0, 8, 5, 0, 0, 0, 1, 0],
  [0, 9, 0, 0, 0, 0, 4, 0, 0],
];

Problem _sudoku(List<List<int>> puzzle, {required bool gcc}) {
  final p = Problem();
  for (var r = 0; r < 9; r++) {
    for (var c = 0; c < 9; c++) {
      final v = puzzle[r][c];
      p.addVariable('r${r}c$c', v != 0 ? [v] : [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }
  }
  void group(List<String> cells) {
    if (gcc) {
      p.addGcc(cells, {for (var v = 1; v <= 9; v++) v: 1});
    } else {
      p.addAllDifferent(cells);
    }
  }

  for (var r = 0; r < 9; r++) {
    group([for (var c = 0; c < 9; c++) 'r${r}c$c']);
  }
  for (var c = 0; c < 9; c++) {
    group([for (var r = 0; r < 9; r++) 'r${r}c$c']);
  }
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      group([
        for (var dr = 0; dr < 3; dr++)
          for (var dc = 0; dc < 3; dc++) 'r${br * 3 + dr}c${bc * 3 + dc}'
      ]);
    }
  }
  return p;
}

class _Cnf {
  const _Cnf(this.variables, this.clauses);

  final List<String> variables;

  // Signed, one-based variable indices, independent of the solver's clauses.
  final List<List<int>> clauses;

  Problem build({CspCallback? callback}) {
    final p = Problem();
    for (final variable in variables) {
      p.addVariable(variable, [0, 1]);
    }
    for (final clause in clauses) {
      p.addClause(
        positive: [
          for (final literal in clause)
            if (literal > 0) variables[literal - 1]
        ],
        negative: [
          for (final literal in clause)
            if (literal < 0) variables[-literal - 1]
        ],
      );
    }
    if (callback != null) p.setOptions(timeStep: 0, callback: callback);
    return p;
  }

  bool satisfies(Map<String, dynamic> assignment) =>
      assignment.length == variables.length &&
      variables.every((variable) =>
          assignment[variable] == 0 || assignment[variable] == 1) &&
      clauses.every((clause) => clause.any((literal) =>
          (assignment[variables[literal.abs() - 1]] == 1) == (literal > 0)));

  List<Map<String, int>> exhaustiveSolutions() {
    // Only the three-variable fixtures use this exhaustive oracle.
    expect(variables.length, lessThanOrEqualTo(3));
    return [
      for (var mask = 0; mask < 1 << variables.length; mask++)
        {
          for (var i = 0; i < variables.length; i++)
            variables[i]: (mask >> i) & 1,
        },
    ].where(satisfies).toList();
  }
}

/// Random instances exercise verdicts and assignments, not search-work ratios.
/// A seed does not promise the same fixture or solver order across runtimes.
_Cnf _randSat(int seed, {int n = 100, int m = 426}) {
  final rng = Random(seed);
  final clauses = <List<int>>[];
  for (var c = 0; c < m; c++) {
    final picked = <int>{};
    while (picked.length < 3) {
      picked.add(rng.nextInt(n));
    }
    clauses.add([
      for (final i in picked)
        if (rng.nextBool()) i + 1 else -(i + 1),
    ]);
  }
  return _Cnf([for (var i = 0; i < n; i++) 'v$i'], clauses);
}

typedef _Decision = ({
  Map<String, int> assigned,
  Map<String, List<dynamic>> unassigned,
});

Future<
    ({
      dynamic result,
      SolverStats stats,
      List<_Decision> decisions,
      List<List<Atom>> learned,
    })> _recordedSolve(_Cnf fixture, {bool useVsids = false}) async {
  final decisions = <_Decision>[];
  final learned = <List<Atom>>[];
  final problem = fixture.build(callback: (assigned, unassigned) {
    decisions.add((
      assigned: {
        for (final entry in assigned.entries)
          entry.key: entry.value.single as int,
      },
      unassigned: {
        for (final entry in unassigned.entries) entry.key: [...entry.value],
      },
    ));
  });
  final result = await problem.solveWithLcg(
    useIterativeCdcl: true,
    useRestarts: true,
    restartScale: 1,
    useVsids: useVsids,
    onLearnedClause: (clause) => learned.add([...clause]),
  );
  return (
    result: result,
    stats: CSP.lastStats!.snapshot(),
    decisions: decisions,
    learned: learned,
  );
}

void _expectLearnedSound(_Cnf fixture, List<List<Atom>> learned) {
  final solutions = fixture.exhaustiveSolutions();
  expect(solutions, isNotEmpty);
  expect(learned, isNotEmpty);
  for (final clause in learned) {
    expect(clause, isNotEmpty);
    for (final atom in clause) {
      expect(fixture.variables, contains(atom.varName));
      expect(atom.isSynthetic, isFalse);
    }
    for (final solution in solutions) {
      expect(
        clause.any((atom) {
          final actual = solution[atom.varName]!;
          return switch (atom) {
            AtomEq(:final value) => actual == value,
            AtomNe(:final value) => actual != value,
            AtomLe(:final value) => actual <= value,
            AtomGe(:final value) => actual >= value,
            AtomInScc() => false,
          };
        }),
        isTrue,
        reason: 'Learned $clause must retain the original solution $solution',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('restart soundness (Inkala, restarts forced)', () {
    test('allDiff + GCC solved correctly with restarts firing', () async {
      final ref = await _sudoku(_hardestSudoku, gcc: false).getSolution()
          as Map<String, dynamic>;
      for (final gcc in [false, true]) {
        for (var seed = 0; seed < 6; seed++) {
          // restartScale 3 forces several restarts on a puzzle that
          // otherwise converges in ~26 backtracks.
          final r = await _sudoku(_hardestSudoku, gcc: gcc).solveWithLcg(
              useIterativeCdcl: true,
              useRestarts: true,
              restartScale: 3,
              useVsids: true,
              seed: seed);
          expect(r, isA<Map<String, dynamic>>(),
              reason: 'gcc=$gcc seed=$seed must stay SAT under restarts');
          final m = r as Map<String, dynamic>;
          for (final k in ref.keys) {
            expect(m[k], ref[k], reason: 'gcc=$gcc seed=$seed cell $k');
          }
        }
      }
    });

    test('restarts actually fire under the tiny budget', () async {
      await _sudoku(_hardestSudoku, gcc: false).solveWithLcg(
          useIterativeCdcl: true,
          useRestarts: true,
          restartScale: 3,
          useVsids: true,
          seed: 0);
      expect(CSP.lastStats!.restarts, greaterThan(0));
    });
  });

  group('restart verdict parity (random 3-SAT)', () {
    test('restarts-on agrees with plain backtracking on SAT/UNSAT', () async {
      // Smaller instances (n=60) so a forced-restart sweep stays fast; the
      // verdict-parity property is size-independent.
      for (var seed = 0; seed < 8; seed++) {
        final fixture = _randSat(seed, n: 60, m: 256);
        final plain = await fixture.build().getSolution();
        final r = await fixture.build().solveWithLcg(
            useIterativeCdcl: true,
            useRestarts: true,
            restartScale: 20,
            useVsids: true,
            seed: seed);
        final plainSat = plain is Map<String, dynamic>;
        final rSat = r is Map<String, dynamic>;
        expect(rSat, plainSat, reason: 'seed=$seed verdict mismatch');
        if (plain is Map<String, dynamic>) {
          expect(fixture.satisfies(plain), isTrue,
              reason: 'seed=$seed plain assignment must satisfy every clause');
        }
        if (r is Map<String, dynamic>) {
          expect(fixture.satisfies(r), isTrue,
              reason: 'seed=$seed LCG assignment must satisfy every clause');
        }
      }
    });
  });

  group('restart retained search state (fixed clauses)', () {
    test('saved phase and activity survive a forced restart', () async {
      // x=0, y=0 forces a conflict. Learning x OR y asserts y=1 and
      // bumps y's activity above x's. At restart, y is selected first;
      // its saved value must be 1 even though its restored domain starts at 0.
      const fixture = _Cnf([
        'x',
        'y',
        'z'
      ], [
        [1, 2, 3],
        [2, -3],
      ]);
      final run = await _recordedSolve(fixture, useVsids: true);
      expect(run.result, isA<Map<String, dynamic>>());
      expect(fixture.satisfies(run.result as Map<String, dynamic>), isTrue);
      _expectLearnedSound(fixture, run.learned);
      expect(run.stats.restarts, 1);
      expect(run.stats.learnedClauses, 1);
      expect(run.decisions.length, greaterThanOrEqualTo(3));
      expect(run.decisions[0].assigned, {'x': 0});
      expect(run.decisions[1].assigned, {'x': 0, 'y': 0});
      expect(run.decisions[2].assigned, {'y': 1},
          reason: 'The restart must retain both VSIDS activity and saved y=1');
      expect(
          run.decisions[2].unassigned,
          {
            'x': [0, 1],
            'z': [0, 1],
          },
          reason:
              'The abandoned decision levels must have rolled back to root');
    });

    test('learned clause still unit-propagates after a forced restart',
        () async {
      // The original clauses do not unit-propagate y after x=0. The learned
      // x OR y must survive restart and force y=1 before the next z decision.
      const fixture = _Cnf([
        'x',
        'y',
        'z'
      ], [
        [1, 2, 3],
        [1, 2, -3],
      ]);
      final run = await _recordedSolve(fixture);
      expect(run.result, isA<Map<String, dynamic>>());
      expect(fixture.satisfies(run.result as Map<String, dynamic>), isTrue);
      _expectLearnedSound(fixture, run.learned);
      expect(run.stats.restarts, 1);
      expect(run.stats.learnedClauses, 1);
      expect(run.stats.learnedClauseUses, greaterThan(0));
      expect(run.decisions, hasLength(4),
          reason: 'After restart, y must be propagated, not decided again');
      expect(run.decisions[0].assigned, {'x': 0});
      expect(run.decisions[1].assigned, {'x': 0, 'y': 0});
      expect(run.decisions[2].assigned, {'x': 0});
      expect(run.decisions[2].unassigned, {
        'y': [0, 1],
        'z': [0, 1],
      });
      expect(run.decisions[3].assigned.keys, containsAll(['x', 'y', 'z']));
      expect(run.decisions[3].assigned['x'], 0);
      expect(run.decisions[3].assigned['y'], 1);
      expect(run.decisions[3].unassigned, isEmpty);
    });
  });
}

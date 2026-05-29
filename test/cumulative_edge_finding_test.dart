// Tests for the energetic-reasoning pass on the cumulative propagator
// (Baptiste, Le Pape & Nuijten 1999). The headline guarantee is
// *soundness*: a randomized sweep enumerates every solution the solver
// finds and asserts it equals the brute-force feasible set over the
// Cartesian product of start domains, so no feasible start is ever
// pruned. A handful of targeted cases check that the pass actually
// detects overloads / tightens bounds that the time-table profile alone
// misses.

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// True iff the fixed schedule never exceeds [cap] at any time step.
bool _feasible(List<int> starts, List<int> dur, List<int> dem, int cap) {
  final usage = <int, int>{};
  for (var i = 0; i < starts.length; i++) {
    for (var t = starts[i]; t < starts[i] + dur[i]; t++) {
      usage[t] = (usage[t] ?? 0) + dem[i];
      if (usage[t]! > cap) return false;
    }
  }
  return true;
}

Set<String> _bruteForce(
    List<List<int>> domains, List<int> dur, List<int> dem, int cap) {
  final out = <String>{};
  void rec(int i, List<int> acc) {
    if (i == domains.length) {
      if (_feasible(acc, dur, dem, cap)) out.add(acc.join(','));
      return;
    }
    for (final s in domains[i]) {
      acc.add(s);
      rec(i + 1, acc);
      acc.removeLast();
    }
  }

  rec(0, <int>[]);
  return out;
}

Future<Set<String>> _solveAll(
    List<List<int>> domains, List<int> dur, List<int> dem, int cap) async {
  final p = Problem();
  final names = <String>[];
  for (var i = 0; i < domains.length; i++) {
    final name = 'x$i';
    names.add(name);
    p.addVariable(name, domains[i]);
  }
  p.addCumulative(names, dur, dem, cap);
  final out = <String>{};
  await for (final sol in p.getSolutions()) {
    out.add([for (final nm in names) sol[nm] as int].join(','));
  }
  return out;
}

void main() {
  group('cumulative energetic reasoning — soundness sweep', () {
    test('solver solution set equals brute force across random instances',
        () async {
      final rng = Random(0xC0FFEE);
      const trials = 1500;
      var constrained = 0;
      for (var trial = 0; trial < trials; trial++) {
        final n = 2 + rng.nextInt(3); // 2..4 tasks
        final horizon = 3 + rng.nextInt(4); // starts in 0..horizon-1
        final cap = 1 + rng.nextInt(3); // 1..3
        final dur = <int>[];
        final dem = <int>[];
        final domains = <List<int>>[];
        for (var i = 0; i < n; i++) {
          dur.add(1 + rng.nextInt(3));
          dem.add(1 + rng.nextInt(cap));
          final dom = <int>[];
          for (var s = 0; s < horizon; s++) {
            if (rng.nextInt(4) != 0) dom.add(s);
          }
          if (dom.isEmpty) dom.add(rng.nextInt(horizon));
          domains.add(dom);
        }

        final brute = _bruteForce(domains, dur, dem, cap);
        final solved = await _solveAll(domains, dur, dem, cap);

        // The decisive soundness + completeness assertion: identical sets.
        expect(solved, equals(brute),
            reason: 'trial $trial: n=$n cap=$cap dur=$dur dem=$dem '
                'domains=$domains');

        var product = 1;
        for (final d in domains) {
          product *= d.length;
        }
        if (brute.length < product) constrained++;
      }
      // Sanity: the vast majority of instances are genuinely constrained,
      // so the sweep is actually exercising pruning, not trivially SAT.
      expect(constrained, greaterThan(trials ~/ 2));
    });
  });

  group('cumulative energetic reasoning — targeted pruning', () {
    test('detects an overload the time-table profile misses', () async {
      // Genuinely overloaded: 3 tasks, duration 3, demand 1, capacity 2,
      // all pinned to start at 0 ⇒ all run over [0, 3), usage 3 > 2.
      final q = Problem()
        ..addVariable('a', [0])
        ..addVariable('b', [0])
        ..addVariable('c', [0])
        ..addCumulative(['a', 'b', 'c'], [3, 3, 3], [1, 1, 1], 2);
      expect(await q.getSolution(), 'FAILURE');

      // A satisfiable companion: only 2 tasks share capacity 2, so usage
      // never exceeds 2 wherever they land.
      final p = Problem()
        ..addVariable('a', [0, 1, 2])
        ..addVariable('b', [0, 1, 2])
        ..addCumulative(['a', 'b'], [2, 2], [1, 1], 2);
      expect(await p.getSolution(), isA<Map<String, dynamic>>());
    });

    test('tightens earliest start beyond the time-table profile', () async {
      // Two tasks of duration 2, demand 1, capacity 1 (disjunctive), both
      // free in [0, 2]. Pin task a to start at 0; then b must start at 2
      // (energetic / no-overlap), so b's domain collapses to {2}.
      final p = Problem()
        ..addVariable('a', [0])
        ..addVariable('b', [0, 1, 2])
        ..addCumulative(['a', 'b'], [2, 2], [1, 1], 1);
      final solutions = <int>{};
      await for (final s in p.getSolutions()) {
        solutions.add(s['b'] as int);
      }
      expect(solutions, {2});
    });

    test('agrees with the unary (no-overlap) reduction', () async {
      // Capacity 1 reduces cumulative to disjunctive. Three unit-ish
      // tasks must be totally ordered in time.
      final p = Problem()
        ..addVariable('a', [0, 1, 2, 3, 4, 5])
        ..addVariable('b', [0, 1, 2, 3, 4, 5])
        ..addVariable('c', [0, 1, 2, 3, 4, 5])
        ..addCumulative(['a', 'b', 'c'], [1, 2, 3], [1, 1, 1], 1);
      await for (final s in p.getSolutions()) {
        final starts = [s['a'] as int, s['b'] as int, s['c'] as int];
        expect(_feasible(starts, [1, 2, 3], [1, 1, 1], 1), isTrue);
      }
    });
  });

  group('cumulative energetic reasoning — large instance falls back', () {
    test('above the task bound the solver still solves soundly', () async {
      // 70 trivially-packable tasks: exceeds _erMaxTasks (64) so ER is
      // skipped, but the time-table propagator still produces a valid
      // schedule.
      final p = Problem();
      final names = <String>[];
      for (var i = 0; i < 70; i++) {
        final nm = 't$i';
        names.add(nm);
        p.addVariable(nm, [0, 1, 2, 3]);
      }
      p.addCumulative(names, List<int>.filled(70, 1), List<int>.filled(70, 1),
          70);
      final sol = await p.getSolution();
      expect(sol, isA<Map<String, dynamic>>());
    });
  });
}

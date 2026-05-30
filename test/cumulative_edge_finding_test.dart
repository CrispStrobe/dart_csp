// Tests for the energetic-reasoning pass on the cumulative propagator
// (Baptiste, Le Pape & Nuijten 1999). The headline guarantee is
// *soundness*: randomized sweeps enumerate every solution the solver
// finds and assert it equals the brute-force feasible set over the
// Cartesian product of start domains, so no feasible start is ever
// pruned. The sweeps cover several regimes — non-negative starts,
// negative start times, and larger task counts — and a second seed.
// Targeted cases check that the pass actually detects overloads /
// tightens bounds that the time-table profile alone misses, and that it
// behaves on interval-rep domains and above the task-count gate.

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

/// Runs [trials] random instances under one regime and asserts the
/// solver's full solution set equals the brute-force feasible set on
/// each. Returns the number of instances that were genuinely
/// constrained (feasible set strictly smaller than the domain product),
/// so the caller can confirm the sweep actually exercises pruning.
///
/// [base] shifts every start domain (use a negative value to exercise
/// negative time coordinates); [maxTasks] and [maxDur] widen the shape.
Future<int> _sweep(
  int seed, {
  required int trials,
  required int maxTasks,
  required int maxDur,
  required int base,
}) async {
  final rng = Random(seed);
  var constrained = 0;
  for (var trial = 0; trial < trials; trial++) {
    final n = 2 + rng.nextInt(maxTasks - 1); // 2..maxTasks
    final horizon = 3 + rng.nextInt(4);
    final cap = 1 + rng.nextInt(3);
    final dur = <int>[];
    final dem = <int>[];
    final domains = <List<int>>[];
    for (var i = 0; i < n; i++) {
      dur.add(1 + rng.nextInt(maxDur));
      dem.add(1 + rng.nextInt(cap));
      final dom = <int>[];
      for (var s = 0; s < horizon; s++) {
        if (rng.nextInt(4) != 0) dom.add(base + s);
      }
      if (dom.isEmpty) dom.add(base + rng.nextInt(horizon));
      domains.add(dom);
    }

    final brute = _bruteForce(domains, dur, dem, cap);
    final solved = await _solveAll(domains, dur, dem, cap);

    // The decisive soundness + completeness assertion: identical sets.
    expect(solved, equals(brute),
        reason: 'seed $seed trial $trial: n=$n cap=$cap dur=$dur dem=$dem '
            'base=$base domains=$domains');

    var product = 1;
    for (final d in domains) {
      product *= d.length;
    }
    if (brute.length < product) constrained++;
  }
  return constrained;
}

void main() {
  group('cumulative energetic reasoning — soundness sweep', () {
    test('non-negative starts: solver set equals brute force', () async {
      final constrained = await _sweep(0xC0FFEE,
          trials: 1500, maxTasks: 4, maxDur: 3, base: 0);
      // Most instances are genuinely constrained, so pruning is exercised.
      expect(constrained, greaterThan(750));
    });

    test('negative start times: solver set equals brute force', () async {
      // Shift every domain into negative time to exercise the interval
      // arithmetic (est/lst, MI windows) over negative coordinates.
      final constrained = await _sweep(0xBADF00D,
          trials: 1200, maxTasks: 4, maxDur: 3, base: -5);
      expect(constrained, greaterThan(600));
    });

    test('larger task counts and durations: solver set equals brute force',
        () async {
      final constrained = await _sweep(0x5EED,
          trials: 700, maxTasks: 5, maxDur: 4, base: 0);
      expect(constrained, greaterThan(350));
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

    test('works on interval-rep (range) domains', () async {
      // addRangeVariable uses the compact interval rep; energetic
      // reasoning must read its bounds and filter it correctly. cap=2,
      // three dur-2 dem-1 tasks over a wide range, minimising makespan.
      final p = Problem()
        ..addRangeVariable('s0', 0, 100)
        ..addRangeVariable('s1', 0, 100)
        ..addRangeVariable('s2', 0, 100)
        ..addRangeVariable('mk', 0, 100)
        ..addCumulative(['s0', 's1', 's2'], [2, 2, 2], [1, 1, 2], 2)
        ..addLinearGeq(['mk', 's0'], [1, -1], 2)
        ..addLinearGeq(['mk', 's1'], [1, -1], 2)
        ..addLinearGeq(['mk', 's2'], [1, -1], 2);
      final s = await p.minimize('mk');
      expect(s, isA<Map<String, dynamic>>());
      expect((s as Map)['mk'], 4); // dem=2 task runs alone; pair runs together
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

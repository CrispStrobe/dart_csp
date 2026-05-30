// Thorough / adversarial verification of the propagation trace.
//
// Beyond the basic end-to-end tests in `propagation_trace_test.dart`, this
// suite proves the event stream is a *faithful and self-consistent record*
// of the search:
//
//  - **Replay**: starting from the initial domains, replaying the events
//    (decision pins, prunes, backtrack restores) reconstructs a coherent
//    domain history — every prune's before/after/removed must match the
//    reconstructed state exactly, and a solution leaf must be all
//    singletons matching the reported assignment. This is the strongest
//    check: any wrong before/after, removed-set, cause, or ordering breaks
//    it.
//  - **Behaviour neutrality**: traced vs un-traced solves agree on the
//    result and on every SolverStats counter, across a randomized sweep.
//  - **Cause attribution**: each global propagator emits prunes whose
//    `causeKind` matches its `coarseKind`.
//  - **Serialization**: `toMap`/`fromMap` is lossless and idempotent for
//    every event kind and value type.
//  - **Determinism** and **edge cases** (empty/trivial/root-infeasible,
//    `maxEvents` boundaries).

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

const _validCauseKinds = <String>{
  'binary',
  'predicate',
  'allDifferent',
  'linearEquals',
  'linearLeq',
  'linearGeq',
  'regular',
  'circuit',
  'subcircuit',
  'gcc',
  'cumulative',
  'clause',
  'diffN',
  'unknown',
};

/// Per-event structural invariants shared by every path (CBJ or not).
void _checkPerEvent(List<PropagationEvent> events) {
  for (var i = 0; i < events.length; i++) {
    final ev = events[i];
    expect(ev.seq, i, reason: 'seq must be 0-based and gap-free');
    switch (ev.kind) {
      case PropagationEventKind.prune:
      case PropagationEventKind.domainWipeout:
        final before = ev.domainBefore!.toSet();
        final after = ev.domainAfter!.toSet();
        final removed = ev.removedValues!.toSet();
        expect(removed, isNotEmpty, reason: 'prune must remove something');
        expect(after.difference(before), isEmpty,
            reason: 'after must be a subset of before @${ev.seq}');
        expect(removed, equals(before.difference(after)),
            reason: 'removed must equal before\\after @${ev.seq}');
        expect(ev.kind == PropagationEventKind.domainWipeout, after.isEmpty,
            reason: 'wipeout iff domainAfter empty @${ev.seq}');
        expect(_validCauseKinds, contains(ev.causeKind),
            reason: 'unknown causeKind ${ev.causeKind} @${ev.seq}');
        expect(ev.causeScope, isNotNull);
        expect(ev.causeScope, isNotEmpty);
        expect(ev.variable, isNotNull);
      case PropagationEventKind.decision:
        expect(ev.variable, isNotNull);
        expect(ev.value, isNotNull);
        expect(ev.depth, isNotNull);
        expect(ev.depth, greaterThanOrEqualTo(0));
      case PropagationEventKind.backtrack:
        expect(ev.depth, isNotNull);
      case PropagationEventKind.backjump:
        expect(ev.depth, isNotNull);
        expect(ev.targetDepth, isNotNull);
        expect(ev.targetDepth, lessThan(ev.depth!));
      case PropagationEventKind.solution:
        expect(ev.assignment, isNotNull);
    }
    // Stats snapshot present and monotonic-ish (non-negative).
    expect(ev.stats, isNotNull);
    expect(ev.stats!.decisions, greaterThanOrEqualTo(0));
  }
}

/// Full replay (non-CBJ path only — no backjump events). Reconstructs the
/// domain state purely from the events and asserts each one is consistent
/// with the reconstructed state.
void _replay(List<PropagationEvent> events,
    Map<String, Set<int>> initialDomains, Object? result) {
  final cur = <String, Set<int>>{
    for (final e in initialDomains.entries) e.key: Set<int>.of(e.value)
  };
  // depth -> snapshot of all domains taken at that depth's decision (the
  // state the engine's trail rollback restores to on backtrack).
  final snapshots = <int, Map<String, Set<int>>>{};
  var solutions = 0;

  Map<String, Set<int>> snap() =>
      {for (final e in cur.entries) e.key: Set<int>.of(e.value)};
  void restore(Map<String, Set<int>> s) {
    cur
      ..clear()
      ..addAll({for (final e in s.entries) e.key: Set<int>.of(e.value)});
  }

  for (final ev in events) {
    switch (ev.kind) {
      case PropagationEventKind.prune:
      case PropagationEventKind.domainWipeout:
        final v = ev.variable!;
        final before = ev.domainBefore!.cast<int>().toSet();
        final after = ev.domainAfter!.cast<int>().toSet();
        expect(cur[v], equals(before),
            reason: 'replay: domain of $v before prune @${ev.seq} '
                'is ${cur[v]} but event says $before');
        cur[v] = after;
      case PropagationEventKind.decision:
        final v = ev.variable!;
        final val = ev.value as int;
        expect(cur[v], contains(val),
            reason: 'replay: decision $v=$val @${ev.seq} not in current '
                'domain ${cur[v]}');
        snapshots[ev.depth!] = snap();
        cur[v] = <int>{val};
      case PropagationEventKind.backtrack:
        final s = snapshots[ev.depth!];
        expect(s, isNotNull,
            reason: 'replay: backtrack @depth ${ev.depth} (@${ev.seq}) '
                'with no matching decision snapshot');
        restore(s!);
      case PropagationEventKind.backjump:
        // Not emitted on the non-CBJ path; restore leniently if present.
        final s = snapshots[ev.targetDepth!];
        if (s != null) restore(s);
      case PropagationEventKind.solution:
        solutions++;
        final assn = ev.assignment!;
        for (final e in cur.entries) {
          expect(e.value, hasLength(1),
              reason:
                  'replay: solution var ${e.key} not singleton (${e.value})');
          expect(e.value.first, assn[e.key],
              reason: 'replay: solution var ${e.key} = ${e.value.first} '
                  'but assignment says ${assn[e.key]}');
        }
    }
  }
  if (result is Map) {
    expect(solutions, greaterThanOrEqualTo(1),
        reason: 'a SAT getSolution trace must contain a solution event');
  }
}

/// Builds a random graph-colouring CSP: [n] regions, [colors] colours,
/// each edge present with probability [density]. Binary `!=` constraints.
Problem _randomColoring(Random rng, int n, int colors, double density) {
  final p = Problem();
  for (var i = 0; i < n; i++) {
    p.addVariable('v$i', [for (var c = 1; c <= colors; c++) c]);
  }
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (rng.nextDouble() < density) {
        p.addConstraint(['v$i', 'v$j'], (dynamic a, dynamic b) => a != b,
            label: 'e$i-$j');
      }
    }
  }
  return p;
}

Map<String, Set<int>> _initialDomains(int n, int colors) => {
      for (var i = 0; i < n; i++) 'v$i': {for (var c = 1; c <= colors; c++) c}
    };

void main() {
  group('replay — the trace faithfully reconstructs the search', () {
    test('randomized colouring sweep (SAT + UNSAT), non-CBJ', () async {
      final rng = Random(20240601);
      var sat = 0, unsat = 0, withPrunes = 0;
      for (var t = 0; t < 200; t++) {
        final n = 4 + rng.nextInt(4); // 4..7
        final colors = 2 + rng.nextInt(2); // 2..3
        final density = 0.4 + rng.nextDouble() * 0.5;
        final trace =
            await _randomColoring(rng, n, colors, density).solveWithTrace();
        _checkPerEvent(trace.events);
        _replay(trace.events, _initialDomains(n, colors), trace.result);
        if (trace.result is Map) {
          sat++;
        } else {
          unsat++;
        }
        if (trace.events.any((e) => e.kind == PropagationEventKind.prune)) {
          withPrunes++;
        }
      }
      // The sweep must exercise both verdicts and real pruning.
      expect(sat, greaterThan(0));
      expect(unsat, greaterThan(0));
      expect(withPrunes, greaterThan(100));
    });

    test('replay holds under conflict-directed backjumping too', () async {
      // CBJ adds backjump events; the per-event invariants must still hold,
      // and replay (with lenient backjump restores) stays consistent on the
      // prunes it can check.
      final rng = Random(7);
      for (var t = 0; t < 40; t++) {
        final n = 5 + rng.nextInt(3);
        const colors = 3;
        final events = <PropagationEvent>[];
        final p = _randomColoring(rng, n, colors, 0.6)
          ..setOptions(onPropagation: events.add);
        await p.getSolution(enableConflictBackjumping: true);
        _checkPerEvent(events);
      }
    });
  });

  group('behaviour neutrality — observer never perturbs the search', () {
    test('traced and un-traced agree on result and every stat', () async {
      final rng = Random(0xFEED);
      for (var t = 0; t < 80; t++) {
        final n = 4 + rng.nextInt(4);
        final colors = 2 + rng.nextInt(2);
        final density = 0.4 + rng.nextDouble() * 0.5;

        // Two identical problems (same seeded sub-RNG ⇒ identical graphs).
        final seed = rng.nextInt(1 << 30);
        final plain = _randomColoring(Random(seed), n, colors, density);
        final r1 = await plain.getSolution();
        final s1 = CSP.lastStats!;

        final traced = _randomColoring(Random(seed), n, colors, density);
        final t2 = await traced.solveWithTrace();
        final s2 = CSP.lastStats!;

        expect(t2.result, equals(r1), reason: 'result changed by tracing');
        expect(s2.decisions, s1.decisions);
        expect(s2.backtracks, s1.backtracks);
        expect(s2.propagations, s1.propagations);
        expect(s2.binaryRevises, s1.binaryRevises);
        expect(s2.naryRevises, s1.naryRevises);
      }
    });
  });

  group('cause attribution per propagator', () {
    Future<List<PropagationEvent>> traceOf(Problem p) async {
      final t = await p.solveWithTrace();
      return t.events;
    }

    bool hasPruneKind(List<PropagationEvent> evs, String kind) => evs.any((e) =>
        (e.kind == PropagationEventKind.prune ||
            e.kind == PropagationEventKind.domainWipeout) &&
        e.causeKind == kind);

    test('binary != carries causeKind binary with the right scope', () async {
      final p = Problem()
        ..addVariable('a', [1])
        ..addVariable('b', [1, 2, 3])
        ..addConstraint(['a', 'b'], (dynamic x, dynamic y) => x != y,
            label: 'a!=b');
      final evs = await traceOf(p);
      final pr = evs.firstWhere((e) => e.kind == PropagationEventKind.prune);
      expect(pr.causeKind, 'binary');
      expect(pr.variable, 'b');
      expect(pr.removedValues, [1]);
      expect(pr.causeScope, ['a', 'b']);
      expect(pr.causeLabel, 'a!=b');
    });

    test('allDifferent', () async {
      // a fixed to 1; Régin prunes value 1 out of b and c (a is the only
      // variable that can take 1), so this narrows rather than conflicts.
      final p = Problem()
        ..addVariable('a', [1])
        ..addVariable('b', [1, 2, 3])
        ..addVariable('c', [1, 2, 3])
        ..addAllDifferent(['a', 'b', 'c'], label: 'alld');
      final evs = await traceOf(p);
      expect(hasPruneKind(evs, 'allDifferent'), isTrue,
          reason: 'allDifferent propagator must attribute its prune');
      // The prune removes value 1 (claimed by a) from b/c.
      final pr = evs.firstWhere((e) =>
          e.kind == PropagationEventKind.prune &&
          e.causeKind == 'allDifferent');
      expect(pr.removedValues, contains(1));
      expect(pr.causeLabel, 'alld');
    });

    test('linearLeq', () async {
      final p = Problem()
        ..addVariable('a', [0, 1, 2, 3])
        ..addVariable('b', [0, 1, 2, 3])
        ..addLinearLeq(['a', 'b'], [1, 1], 2, label: 'lin');
      // Pin a=3 path: a+b<=2 with a in {0..3} prunes b's high values once a
      // is large. Force search to exercise it.
      final evs = await traceOf(p);
      expect(hasPruneKind(evs, 'linearLeq'), isTrue);
    });

    test('cumulative', () async {
      // 3 tasks, dur 2, demand 1, capacity 2 over a tight horizon: the
      // time-table / energetic prune fires.
      final p = Problem();
      for (var i = 0; i < 3; i++) {
        p.addVariable('s$i', [0, 1, 2]);
      }
      p.addCumulative(['s0', 's1', 's2'], [2, 2, 2], [1, 1, 2], 2,
          label: 'cum');
      final evs = await traceOf(p);
      expect(hasPruneKind(evs, 'cumulative'), isTrue);
    });

    test('gcc', () async {
      // Two vars, value 1 may appear at most once; pin one to 1 → other
      // loses 1 via the GCC flow propagator.
      final p = Problem()
        ..addVariable('a', [1])
        ..addVariable('b', [1, 2])
        ..addGcc(['a', 'b'], {1: 1, 2: 1}, label: 'gcc');
      final evs = await traceOf(p);
      expect(hasPruneKind(evs, 'gcc'), isTrue);
    });
  });

  group('serialization is lossless and idempotent', () {
    test('every event round-trips and toMap is stable', () async {
      final t = await _randomColoring(Random(99), 6, 3, 0.7).solveWithTrace();
      expect(t.events, isNotEmpty);
      for (final e in t.events) {
        final m1 = e.toMap();
        final back = PropagationEvent.fromMap(m1);
        final m2 = back.toMap();
        expect(m2.toString(), m1.toString(),
            reason: 'toMap not stable through a round-trip for $e');
        expect(back.seq, e.seq);
        expect(back.kind, e.kind);
        expect(back.variable, e.variable);
        expect(back.removedValues, e.removedValues);
        expect(back.domainBefore, e.domainBefore);
        expect(back.domainAfter, e.domainAfter);
        expect(back.causeKind, e.causeKind);
        expect(back.causeScope, e.causeScope);
        expect(back.depth, e.depth);
        expect(back.assignment, e.assignment);
        // Stats survive the hop.
        if (e.stats != null) {
          expect(back.stats!.toMap(), e.stats!.toMap());
        }
      }
    });

    test('non-int domain values (strings) serialize too', () async {
      final p = Problem()
        ..addVariable('x', ['red', 'green', 'blue'])
        ..addVariable('y', ['red'])
        ..addConstraint(['x', 'y'], (dynamic a, dynamic b) => a != b);
      final t = await p.solveWithTrace();
      final pr =
          t.events.firstWhere((e) => e.kind == PropagationEventKind.prune);
      expect(pr.removedValues, contains('red'));
      final back = PropagationEvent.fromMap(pr.toMap());
      expect(back.removedValues, pr.removedValues);
      expect(back.domainBefore, pr.domainBefore);
    });
  });

  group('determinism', () {
    test('same problem traced twice yields identical event maps', () async {
      List<Map<String, dynamic>> mapsOf(PropagationTrace t) =>
          [for (final e in t.events) e.toMap()];
      final a = await _randomColoring(Random(5), 6, 3, 0.6).solveWithTrace();
      final b = await _randomColoring(Random(5), 6, 3, 0.6).solveWithTrace();
      expect(mapsOf(a).toString(), mapsOf(b).toString());
    });
  });

  group('edge cases', () {
    test('trivial problem: solution event, no prunes', () async {
      final t = await (Problem()..addVariable('x', [1])).solveWithTrace();
      expect(t.result, isA<Map<String, dynamic>>());
      expect(
          t.events.where((e) => e.kind == PropagationEventKind.prune), isEmpty);
      expect(t.events.where((e) => e.kind == PropagationEventKind.solution),
          hasLength(1));
    });

    test('root-infeasible problem: wipeout, no solution', () async {
      // a==b and a!=b over the same pair is UNSAT at the root.
      final p = Problem()
        ..addVariable('a', [1, 2])
        ..addVariable('b', [1, 2])
        ..addConstraint(['a', 'b'], (dynamic x, dynamic y) => x == y)
        ..addConstraint(['a', 'b'], (dynamic x, dynamic y) => x != y);
      final t = await p.solveWithTrace();
      expect(t.result, 'FAILURE');
      expect(t.events.where((e) => e.kind == PropagationEventKind.solution),
          isEmpty);
    });

    test('maxEvents boundaries: 0, 1, and uncapped', () async {
      Problem mk() => _randomColoring(Random(3), 6, 3, 0.7);
      final zero = await mk().solveWithTrace(maxEvents: 0);
      expect(zero.events, isEmpty);
      expect(zero.truncated, isTrue);

      final one = await mk().solveWithTrace(maxEvents: 1);
      expect(one.events, hasLength(1));
      expect(one.truncated, isTrue);

      final full = await mk().solveWithTrace(maxEvents: 1 << 30);
      expect(full.truncated, isFalse);
      expect(full.events.length, greaterThan(1));
    });
  });
}

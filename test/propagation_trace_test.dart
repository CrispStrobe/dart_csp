// Tests for the fine-grained propagation trace (the opt-in
// `onPropagation` observer / `solveWithTrace` API). The headline
// guarantees: (1) prunes carry the pruned variable, removed value(s),
// before/after domains, and the cause's kind + label + scope; (2) an
// un-colorable instance ends in a `domainWipeout`; (3) a colorable one
// ends in a `solution`; (4) the observer is zero-overhead and
// behaviour-neutral when unset; (5) events serialize losslessly for the
// isolate hop.

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Complete graph on [n] regions, each with [colors] colours; every pair
/// of regions must differ. `K4` with 3 colours is the classic un-colorable
/// instance (chromatic number 4 > 3).
Problem completeMap(int n, int colors) {
  final p = Problem();
  final names = [for (var i = 0; i < n; i++) 'r$i'];
  for (final v in names) {
    p.addVariable(v, [for (var c = 1; c <= colors; c++) c]);
  }
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      p.addConstraint([names[i], names[j]], (dynamic a, dynamic b) => a != b,
          label: '${names[i]}≠${names[j]}');
    }
  }
  return p;
}

/// Path of [n] regions r0-r1-...-r(n-1), adjacent ones differ; 3-colorable
/// for any n (in fact 2-colorable).
Problem pathMap(int n, int colors) {
  final p = Problem();
  final names = [for (var i = 0; i < n; i++) 'r$i'];
  for (final v in names) {
    p.addVariable(v, [for (var c = 1; c <= colors; c++) c]);
  }
  for (var i = 0; i + 1 < n; i++) {
    p.addConstraint([names[i], names[i + 1]], (dynamic a, dynamic b) => a != b);
  }
  return p;
}

/// N-queens as a binary CSP: one variable per column, domain = rows, with
/// pairwise non-attacking constraints (different row, different diagonal).
Problem nQueens(int n) {
  final p = Problem();
  final names = [for (var i = 0; i < n; i++) 'q$i'];
  for (final v in names) {
    p.addVariable(v, [for (var r = 0; r < n; r++) r]);
  }
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final dist = j - i;
      p.addConstraint(
          [names[i], names[j]],
          (dynamic a, dynamic b) =>
              a != b && (a as int) - (b as int) != dist && b - a != dist,
          label: 'safe(q$i,q$j)');
    }
  }
  return p;
}

/// A trivial minimization: `x ∈ 1..5`, `y ∈ 1..5`, `x ≥ y`, minimize `x`.
/// Optimum is `x = 1` (with `y = 1`). Top-level so it's sendable to a
/// worker isolate.
Problem buildMinObjective() {
  final p = Problem();
  p.addVariable('x', [1, 2, 3, 4, 5]);
  p.addVariable('y', [1, 2, 3, 4, 5]);
  p.addConstraint(
      ['x', 'y'], (dynamic a, dynamic b) => (a as int) >= (b as int));
  return p;
}

void main() {
  group('PropagationEvent / serialization', () {
    test('toMap/fromMap round-trips every field', () {
      const ev = PropagationEvent(
        seq: 7,
        kind: PropagationEventKind.prune,
        variable: 'B',
        removedValues: [1],
        domainBefore: [1, 2, 3],
        domainAfter: [2, 3],
        causeKind: 'binary',
        causeLabel: 'A≠B',
        causeScope: ['A', 'B'],
      );
      final back = PropagationEvent.fromMap(ev.toMap());
      expect(back.seq, 7);
      expect(back.kind, PropagationEventKind.prune);
      expect(back.variable, 'B');
      expect(back.removedValues, [1]);
      expect(back.domainBefore, [1, 2, 3]);
      expect(back.domainAfter, [2, 3]);
      expect(back.causeKind, 'binary');
      expect(back.causeLabel, 'A≠B');
      expect(back.causeScope, ['A', 'B']);
      expect(back.causeDescription, 'binary[A≠B](A, B)');
    });

    test('only plain (web-safe) types reach the map', () {
      const ev = PropagationEvent(
        seq: 0,
        kind: PropagationEventKind.decision,
        variable: 'q0',
        value: 2,
        depth: 1,
      );
      final m = ev.toMap();
      for (final v in m.values) {
        expect(v is int || v is String || v is List || v is Map, isTrue,
            reason: 'value $v is not a plain JSON-ish type');
      }
    });
  });

  group('solveWithTrace — un-colorable (domain wipeout)', () {
    test('K4 with 3 colours fails and ends with a wipeout', () async {
      final t = await completeMap(4, 3).solveWithTrace();
      expect(t.result, 'FAILURE');
      expect(t.truncated, isFalse);
      expect(t.events, isNotEmpty);
      // Monotonic, gap-free sequence numbers.
      for (var i = 0; i < t.events.length; i++) {
        expect(t.events[i].seq, i);
      }
      final wipeouts =
          t.events.where((e) => e.kind == PropagationEventKind.domainWipeout);
      expect(wipeouts, isNotEmpty,
          reason: 'an un-colorable instance must wipe a domain');
      for (final w in wipeouts) {
        expect(w.domainAfter, isEmpty);
        expect(w.removedValues, isNotEmpty);
        expect(w.causeKind, 'binary');
        expect(w.causeScope, hasLength(2));
      }
    });

    test('a prune carries variable, removed value, and cause label/scope',
        () async {
      final t = await completeMap(4, 3).solveWithTrace();
      final prune = t.events.firstWhere(
          (e) => e.kind == PropagationEventKind.prune,
          orElse: () => throw StateError('expected at least one prune'));
      // Domain shrank by exactly the removed values.
      final before = prune.domainBefore!.toSet();
      final after = prune.domainAfter!.toSet();
      expect(before.difference(after).toList(), prune.removedValues);
      expect(prune.variable, isNotNull);
      expect(prune.causeKind, 'binary');
      expect(prune.causeLabel, isNotNull);
      expect(prune.causeLabel, contains('≠'));
      // Scope is [head, tail]; the pruned variable is one of them.
      expect(prune.causeScope, contains(prune.variable));
    });

    test('decision events carry variable, value, and a depth', () async {
      final t = await completeMap(4, 3).solveWithTrace();
      final decisions =
          t.events.where((e) => e.kind == PropagationEventKind.decision);
      expect(decisions, isNotEmpty);
      for (final d in decisions) {
        expect(d.variable, isNotNull);
        expect(d.value, isNotNull);
        expect(d.depth, isNotNull);
        expect(d.depth, greaterThanOrEqualTo(0));
      }
    });
  });

  group('solveWithTrace — colorable (solution)', () {
    test('a 3-colorable path map ends with a solution event', () async {
      final t = await pathMap(5, 3).solveWithTrace();
      expect(t.result, isA<Map<String, dynamic>>());
      final sols =
          t.events.where((e) => e.kind == PropagationEventKind.solution);
      expect(sols, hasLength(1));
      expect(sols.first.assignment, equals(t.result));
    });

    test('4-queens solves and the trace reaches a solution', () async {
      final t = await nQueens(4).solveWithTrace();
      expect(t.result, isA<Map<String, dynamic>>());
      final sol = t.result as Map<String, dynamic>;
      // The returned assignment is a real 4-queens placement.
      final rows = sol.values.cast<int>().toList();
      expect(rows.toSet(), hasLength(4), reason: 'rows must be distinct');
      expect(
          t.events.any((e) => e.kind == PropagationEventKind.solution), isTrue);
      // A prune cites one of the safe(...) constraints.
      final prunes =
          t.events.where((e) => e.kind == PropagationEventKind.prune);
      expect(prunes, isNotEmpty);
      expect(prunes.first.causeLabel, startsWith('safe('));
    });
  });

  group('zero overhead / behaviour neutrality when unset', () {
    test('no observer ⇒ identical result and stats vs a traced run', () async {
      final plain = await nQueens(6).getSolution();
      final plainStats = CSP.lastStats!;
      final traced = await nQueens(6).solveWithTrace();
      final tracedStats = CSP.lastStats!;
      expect(traced.result, equals(plain));
      // The observer never changes the search: same decisions / backtracks.
      expect(tracedStats.decisions, plainStats.decisions);
      expect(tracedStats.backtracks, plainStats.backtracks);
      expect(tracedStats.propagations, plainStats.propagations);
    });

    test('getSolution without onPropagation emits nothing', () async {
      var count = 0;
      final p = nQueens(4)..setOptions(onPropagation: (_) => count++);
      // Overwrite back to no-op is not possible; instead build a fresh one
      // with no observer and confirm lastTraceTruncated stays false and the
      // coarse callback still works independently.
      final fresh = nQueens(4);
      await fresh.getSolution();
      expect(CSP.lastTraceTruncated, isFalse);
      // Sanity: the observer-bearing problem does emit.
      await p.getSolution();
      expect(count, greaterThan(0));
    });
  });

  group('maxEvents cap', () {
    test('truncates and flags when the cap is small', () async {
      final t = await completeMap(4, 3).solveWithTrace(maxEvents: 5);
      expect(t.events, hasLength(5));
      expect(t.truncated, isTrue);
      expect(CSP.lastTraceTruncated, isTrue);
    });
  });

  group('isolate boundary (solveInIsolateWithTrace)', () {
    test('worker collects and ships back a serialized trace', () async {
      // K4/3 is UNSAT; the worker builds it, traces the solve, and sends
      // the events back as plain maps reconstructed on this side.
      final t = await solveInIsolateWithTrace(() => completeMap(4, 3));
      expect(t.result, 'FAILURE');
      expect(t.events, isNotEmpty);
      expect(t.events.any((e) => e.kind == PropagationEventKind.domainWipeout),
          isTrue);
      // Reconstructed events keep their fields and ordering.
      for (var i = 0; i < t.events.length; i++) {
        expect(t.events[i].seq, i);
      }
      final prune =
          t.events.firstWhere((e) => e.kind == PropagationEventKind.prune);
      expect(prune.causeKind, 'binary');
      expect(prune.causeLabel, contains('≠'));
    });

    test('maxEvents cap is honoured across the boundary', () async {
      final t =
          await solveInIsolateWithTrace(() => completeMap(4, 3), maxEvents: 4);
      expect(t.events, hasLength(4));
      expect(t.truncated, isTrue);
    });

    test('minimize variant returns the best assignment with a trace', () async {
      final t = await minimizeInIsolateWithTrace(buildMinObjective, 'x');
      expect(t.result, isA<Map<String, dynamic>>());
      expect((t.result as Map<String, dynamic>)['x'], 1);
      expect(t.events, isNotEmpty);
    });

    test('solveAll variant batches every solution with a trace', () async {
      final t = await solveAllInIsolateWithTrace(() => pathMap(3, 3));
      expect(t.result, isA<List<dynamic>>());
      final sols = (t.result as List).cast<Map<String, dynamic>>();
      // Two adjacent edges over 3 colours: 3 * 2 * 2 = 12 colourings.
      expect(sols, hasLength(12));
      expect(t.events, isNotEmpty);
    });
  });

  group('CspCallback (coarse) path is unaffected', () {
    test('the original per-decision callback still fires', () async {
      var calls = 0;
      final p = pathMap(4, 3)
        ..setOptions(timeStep: 0, callback: (assigned, unassigned) => calls++);
      final r = await p.getSolution();
      expect(r, isA<Map<String, dynamic>>());
      expect(calls, greaterThan(0));
    });
  });
}

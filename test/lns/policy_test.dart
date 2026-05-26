import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

LnsContext _ctx({
  required List<String> names,
  required int seed,
  int iteration = 0,
  Map<String, Set<String>>? adjacency,
}) =>
    LnsContext(
      variableNames: names,
      bestSolution: {for (final n in names) n: 0},
      bestObjective: 0,
      iteration: iteration,
      rng: Random(seed),
      constraintAdjacency: adjacency ?? {for (final n in names) n: <String>{}},
    );

void main() {
  group('LnsPolicy.random', () {
    test('frees ceil(n * fraction) variables, at least 1', () {
      final names = List<String>.generate(10, (i) => 'v$i');
      final pol = LnsPolicy.random(fraction: 0.3);
      final freed = pol.select(_ctx(names: names, seed: 1));
      expect(freed.length, equals(3));
      expect(freed.toSet().length, equals(3),
          reason: 'freed variables must be distinct');
      for (final v in freed) {
        expect(names, contains(v));
      }
    });

    test('always frees at least 1 variable even with tiny fractions', () {
      final names = List<String>.generate(5, (i) => 'v$i');
      final pol = LnsPolicy.random(fraction: 0.01);
      expect(pol.select(_ctx(names: names, seed: 1)).length, equals(1));
    });

    test('same seed across two contexts yields the same destroyed set', () {
      final names = List<String>.generate(20, (i) => 'v$i');
      final pol = LnsPolicy.random(fraction: 0.25);
      final a = pol.select(_ctx(names: names, seed: 42));
      final b = pol.select(_ctx(names: names, seed: 42));
      expect(a, equals(b));
    });

    test('rejects out-of-range fractions', () {
      expect(() => LnsPolicy.random(fraction: 0), throwsArgumentError);
      expect(() => LnsPolicy.random(fraction: 1.5), throwsArgumentError);
    });
  });

  group('LnsPolicy.window', () {
    test('returns a contiguous window in declaration order', () {
      final names = List<String>.generate(8, (i) => 'v$i');
      final pol = LnsPolicy.window(windowSize: 3);
      final freed = pol.select(_ctx(names: names, seed: 7));
      expect(freed.length, equals(3));
      // Contiguous by declaration order.
      final firstIdx = names.indexOf(freed.first);
      expect(freed, equals(names.sublist(firstIdx, firstIdx + 3)));
    });

    test('clamps windowSize larger than the variable count', () {
      final names = List<String>.generate(3, (i) => 'v$i');
      final pol = LnsPolicy.window(windowSize: 100);
      expect(pol.select(_ctx(names: names, seed: 1)), equals(names));
    });

    test('rejects non-positive windowSize', () {
      expect(() => LnsPolicy.window(windowSize: 0), throwsArgumentError);
    });
  });

  group('LnsPolicy.related', () {
    test('expands a seed through the constraint-variable adjacency', () {
      // Two disconnected components of size 5; the policy should grow
      // exclusively within whichever component the seed lands in.
      final names = [
        'a0',
        'a1',
        'a2',
        'a3',
        'a4',
        'b0',
        'b1',
        'b2',
        'b3',
        'b4'
      ];
      final adjacency = <String, Set<String>>{
        'a0': {'a1', 'a2'},
        'a1': {'a0', 'a3'},
        'a2': {'a0', 'a4'},
        'a3': {'a1'},
        'a4': {'a2'},
        'b0': {'b1', 'b2'},
        'b1': {'b0', 'b3'},
        'b2': {'b0', 'b4'},
        'b3': {'b1'},
        'b4': {'b2'},
      };
      final pol = LnsPolicy.related(extendFraction: 0.5);
      // Try a few seeds and verify every freed-set is entirely in one
      // component.
      for (var s = 0; s < 20; s++) {
        final freed = pol.select(_ctx(
          names: names,
          seed: s,
          adjacency: adjacency,
        ));
        expect(freed.length, equals(5));
        final allA = freed.every((v) => v.startsWith('a'));
        final allB = freed.every((v) => v.startsWith('b'));
        expect(allA || allB, isTrue,
            reason: 'related-destroy crossed a disconnected component '
                'boundary (seed $s, freed $freed)');
      }
    });

    test('falls back to random expansion when adjacency is empty', () {
      // No edges at all → should still return seedCount variables.
      final names = List<String>.generate(6, (i) => 'v$i');
      final pol = LnsPolicy.related(seedCount: 2, extendFraction: 0.0);
      final freed = pol.select(_ctx(names: names, seed: 3));
      expect(freed.length, equals(2));
    });

    test('rejects non-positive seedCount and out-of-range extendFraction', () {
      expect(() => LnsPolicy.related(seedCount: 0), throwsArgumentError);
      expect(
          () => LnsPolicy.related(extendFraction: -0.1), throwsArgumentError);
      expect(() => LnsPolicy.related(extendFraction: 1.1), throwsArgumentError);
    });
  });

  group('LnsPolicy.combined', () {
    test('round-trips through every sub-policy when weights are uniform', () {
      final names = List<String>.generate(6, (i) => 'v$i');
      final tagA = _TaggedPolicy('a');
      final tagB = _TaggedPolicy('b');
      final pol = LnsPolicy.combined([tagA, tagB]);
      final picks = <String>{};
      for (var s = 0; s < 50; s++) {
        final freed = pol.select(_ctx(names: names, seed: s));
        picks.add(freed.first.startsWith('a') ? 'a' : 'b');
      }
      expect(picks, equals({'a', 'b'}));
    });

    test('honours explicit weights (degenerate 1.0/0.0)', () {
      final names = List<String>.generate(4, (i) => 'v$i');
      final tagA = _TaggedPolicy('a');
      final tagB = _TaggedPolicy('b');
      final pol = LnsPolicy.combined([tagA, tagB], weights: [1.0, 0.0]);
      for (var s = 0; s < 10; s++) {
        final freed = pol.select(_ctx(names: names, seed: s));
        expect(freed.first.startsWith('a'), isTrue);
      }
    });

    test('rejects empty policy lists, mismatched weights, all-zero weights',
        () {
      expect(() => LnsPolicy.combined([]), throwsArgumentError);
      expect(
          () => LnsPolicy.combined([LnsPolicy.random()], weights: [0.5, 0.5]),
          throwsArgumentError);
      expect(
          () => LnsPolicy.combined([LnsPolicy.random(), LnsPolicy.random()],
              weights: [0.0, 0.0]),
          throwsArgumentError);
      expect(
          () => LnsPolicy.combined([LnsPolicy.random(), LnsPolicy.random()],
              weights: [1.0, -0.1]),
          throwsArgumentError);
    });
  });

  group('LnsPolicy.adaptive', () {
    test(
        'rejects empty policy lists, bad smoothingFactor, bad segmentSize, '
        'negative rewards', () {
      expect(() => LnsPolicy.adaptive([]), throwsArgumentError);
      expect(
          () => LnsPolicy.adaptive([LnsPolicy.random()], smoothingFactor: -0.1),
          throwsArgumentError);
      expect(
          () => LnsPolicy.adaptive([LnsPolicy.random()], smoothingFactor: 1.1),
          throwsArgumentError);
      expect(() => LnsPolicy.adaptive([LnsPolicy.random()], segmentSize: 0),
          throwsArgumentError);
      expect(() => LnsPolicy.adaptive([LnsPolicy.random()], rewardBest: -1),
          throwsArgumentError);
    });

    test(
        'starts with uniform weights and shifts toward the rewarded '
        'sub-policy across a segment', () {
      final names = List<String>.generate(6, (i) => 'v$i');
      final tagA = _TaggedPolicy('a');
      final tagB = _TaggedPolicy('b');
      final pol = LnsPolicy.adaptive(
        [tagA, tagB],
        segmentSize: 50,
        smoothingFactor: 0.5,
      );
      // Drive 50 iterations where ONLY policy A's picks count as
      // improvements. We need to reach inside the policy to check the
      // weights — adaptive exposes `weights` on the impl, so we cast.
      // (Adaptive policy is the only policy that benefits from inspecting
      //  its weights; the cast keeps the public LnsPolicy interface clean.)
      for (var i = 0; i < 50; i++) {
        final ctx = _ctx(names: names, seed: i, iteration: i);
        final picked = pol.select(ctx);
        final pickedA = picked.first.startsWith('a');
        pol.observe(
          ctx: ctx,
          accepted: pickedA,
          improvedBest: pickedA,
        );
      }
      // After one segment, policy A should have higher weight than B.
      // `pol` is an LnsAdaptivePolicy so `.weights` is directly available.
      expect(pol.weights[0], greaterThan(pol.weights[1]),
          reason: 'adaptive should up-weight the rewarded sub-policy '
              '(weights=${pol.weights})');
    });

    test('weights stay positive even after a sub-policy never wins', () {
      final names = List<String>.generate(6, (i) => 'v$i');
      final tagA = _TaggedPolicy('a');
      final tagB = _TaggedPolicy('b');
      final pol = LnsPolicy.adaptive(
        [tagA, tagB],
        segmentSize: 20,
        smoothingFactor: 0.9, // aggressive update — B's weight collapses fast
      );
      // Run 5 segments where A is always rewarded and B is rejected.
      for (var i = 0; i < 100; i++) {
        final ctx = _ctx(names: names, seed: i, iteration: i);
        final picked = pol.select(ctx);
        final pickedA = picked.first.startsWith('a');
        pol.observe(ctx: ctx, accepted: pickedA, improvedBest: pickedA);
      }
      expect(pol.weights[1], greaterThan(0),
          reason: 'a starved sub-policy must keep a positive weight floor');
    });
  });
}

/// Test helper: a policy whose `select` returns a single variable
/// prefixed with the given tag (one of "a"/"b") so the combined-policy
/// test can read which sub-policy fired without inspecting internals.
class _TaggedPolicy implements LnsPolicy {
  _TaggedPolicy(this.tag);
  final String tag;

  @override
  List<String> select(LnsContext ctx) => ['${tag}_${ctx.variableNames.first}'];
}

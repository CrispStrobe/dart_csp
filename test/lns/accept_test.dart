import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('LnsAccept.improving', () {
    final acc = LnsAccept.improving();
    final rng = Random(0);

    test('accepts strict improvement when minimising', () {
      expect(
          acc.accept(
              candidate: 5,
              incumbent: 10,
              iteration: 0,
              minimizing: true,
              rng: rng),
          isTrue);
    });

    test('rejects same value when minimising', () {
      expect(
          acc.accept(
              candidate: 10,
              incumbent: 10,
              iteration: 0,
              minimizing: true,
              rng: rng),
          isFalse);
    });

    test('rejects worsening when minimising', () {
      expect(
          acc.accept(
              candidate: 11,
              incumbent: 10,
              iteration: 0,
              minimizing: true,
              rng: rng),
          isFalse);
    });

    test('symmetric behaviour for maximisation', () {
      expect(
          acc.accept(
              candidate: 11,
              incumbent: 10,
              iteration: 0,
              minimizing: false,
              rng: rng),
          isTrue);
      expect(
          acc.accept(
              candidate: 10,
              incumbent: 10,
              iteration: 0,
              minimizing: false,
              rng: rng),
          isFalse);
      expect(
          acc.accept(
              candidate: 9,
              incumbent: 10,
              iteration: 0,
              minimizing: false,
              rng: rng),
          isFalse);
    });
  });

  group('LnsAccept.simulatedAnnealing', () {
    test('always accepts improvements', () {
      final acc = LnsAccept.simulatedAnnealing();
      expect(
          acc.accept(
              candidate: 5,
              incumbent: 10,
              iteration: 0,
              minimizing: true,
              rng: Random(1)),
          isTrue);
      expect(
          acc.accept(
              candidate: 50,
              incumbent: 0,
              iteration: 100,
              minimizing: false,
              rng: Random(1)),
          isTrue);
    });

    test('non-strictly improving (equal) is rejected', () {
      final acc = LnsAccept.simulatedAnnealing();
      expect(
          acc.accept(
              candidate: 10,
              incumbent: 10,
              iteration: 0,
              minimizing: true,
              rng: Random(1)),
          isFalse);
    });

    test(
        'admits some fraction of worsening moves at high temperature, '
        'fewer as it cools', () {
      // Δ = 1, T_0 = 1 → p_0 = exp(-1) ≈ 0.368. After 1000 iterations
      // at cooling 0.99, T_1000 ≈ 1 * 0.99^1000 ≈ 4.3e-5, so the
      // accept probability is essentially zero.
      final acc = LnsAccept.simulatedAnnealing(cooling: 0.99);
      var earlyAccepts = 0;
      var lateAccepts = 0;
      for (var i = 0; i < 200; i++) {
        if (acc.accept(
            candidate: 11,
            incumbent: 10,
            iteration: 0,
            minimizing: true,
            rng: Random(i))) {
          earlyAccepts++;
        }
        if (acc.accept(
            candidate: 11,
            incumbent: 10,
            iteration: 1000,
            minimizing: true,
            rng: Random(i + 10000))) {
          lateAccepts++;
        }
      }
      expect(earlyAccepts, greaterThan(20),
          reason: 'SA at high temperature should admit some worsening moves '
              '(got $earlyAccepts/200)');
      expect(lateAccepts, lessThan(5),
          reason: 'SA at low temperature should reject almost all worsening '
              'moves (got $lateAccepts/200)');
    });

    test('rejects invalid initialTemp / cooling', () {
      expect(() => LnsAccept.simulatedAnnealing(initialTemp: 0),
          throwsArgumentError);
      expect(
          () => LnsAccept.simulatedAnnealing(cooling: 0), throwsArgumentError);
      expect(() => LnsAccept.simulatedAnnealing(cooling: 1.5),
          throwsArgumentError);
    });
  });

  group('LnsAccept.lateAcceptance', () {
    test('rejects non-positive historySize', () {
      expect(
          () => LnsAccept.lateAcceptance(historySize: 0), throwsArgumentError);
    });

    test(
        'initial history seeds to the current incumbent, so an improving '
        'move is accepted', () {
      final acc = LnsAccept.lateAcceptance(historySize: 5);
      // First call: history initialised to incumbent=10 across all 5 slots.
      // Candidate 8 < 10 → accept (beats both history and incumbent).
      expect(
          acc.accept(
              candidate: 8,
              incumbent: 10,
              iteration: 0,
              minimizing: true,
              rng: Random(0)),
          isTrue);
    });

    test(
        'accepts a worsening move when it still beats an older history '
        'entry', () {
      final acc = LnsAccept.lateAcceptance(historySize: 3);
      // Iter 0: incumbent=10, accept 5 → history[0] = 5.
      acc.accept(
          candidate: 5,
          incumbent: 10,
          iteration: 0,
          minimizing: true,
          rng: Random(0));
      // Iter 1: incumbent=5, accept 4 → history[1] = 4.
      acc.accept(
          candidate: 4,
          incumbent: 5,
          iteration: 1,
          minimizing: true,
          rng: Random(0));
      // Iter 2: incumbent=4, accept 3 → history[2] = 3.
      acc.accept(
          candidate: 3,
          incumbent: 4,
          iteration: 2,
          minimizing: true,
          rng: Random(0));
      // Iter 3 → v = 0, history[0] = 5 (older). incumbent is now 3.
      // Candidate 4 is worse than incumbent 3 BUT beats history[0]=5.
      // Standard LAHC accept criterion → accepted.
      expect(
          acc.accept(
              candidate: 4,
              incumbent: 3,
              iteration: 3,
              minimizing: true,
              rng: Random(0)),
          isTrue);
    });

    test('rejects a candidate that beats neither incumbent nor history', () {
      final acc = LnsAccept.lateAcceptance(historySize: 3);
      // Drive history down to 3.
      acc.accept(
          candidate: 3,
          incumbent: 10,
          iteration: 0,
          minimizing: true,
          rng: Random(0));
      acc.accept(
          candidate: 3,
          incumbent: 3,
          iteration: 1,
          minimizing: true,
          rng: Random(0));
      acc.accept(
          candidate: 3,
          incumbent: 3,
          iteration: 2,
          minimizing: true,
          rng: Random(0));
      // Iter 3: every history slot is 3, incumbent is 3, candidate 10
      // is worse than both → reject.
      expect(
          acc.accept(
              candidate: 10,
              incumbent: 3,
              iteration: 3,
              minimizing: true,
              rng: Random(0)),
          isFalse);
    });

    test('symmetric for maximisation', () {
      final acc = LnsAccept.lateAcceptance(historySize: 1);
      // Iter 0: history initialised to incumbent=10. Candidate=20 beats
      // both history (10) and incumbent (10) → accept. history[0]=20.
      expect(
          acc.accept(
              candidate: 20,
              incumbent: 10,
              iteration: 0,
              minimizing: false,
              rng: Random(0)),
          isTrue);
      // Iter 1: v=0, history[0]=20, incumbent=20. Candidate=15 beats
      // neither → reject.
      expect(
          acc.accept(
              candidate: 15,
              incumbent: 20,
              iteration: 1,
              minimizing: false,
              rng: Random(0)),
          isFalse);
    });
  });
}

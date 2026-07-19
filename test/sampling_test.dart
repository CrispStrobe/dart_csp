import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// A problem with a known, enumerable solution set: two independent
/// variables over 0..n-1 with no constraints has exactly n*n solutions.
Problem _grid(int n) =>
    Problem()..addVariables(['a', 'b'], [for (var i = 0; i < n; i++) i]);

int _hamming(Map<String, dynamic> x, Map<String, dynamic> y) {
  var d = 0;
  for (final k in x.keys) {
    if (x[k] != y[k]) d++;
  }
  return d;
}

void main() {
  group('sampleSolutions', () {
    test('returns exactly k solutions when the space is larger than k',
        () async {
      final got = await _grid(5).sampleSolutions(4, seed: 1);
      expect(got, hasLength(4));
      // Every sample is a distinct, valid assignment.
      for (final s in got) {
        expect(s['a'], inInclusiveRange(0, 4));
        expect(s['b'], inInclusiveRange(0, 4));
      }
      expect(got.map((s) => '${s['a']},${s['b']}').toSet(), hasLength(4),
          reason: 'without replacement -> all distinct');
    });

    test('returns all solutions when k exceeds the solution count', () async {
      final got = await _grid(2).sampleSolutions(100, seed: 1);
      expect(got, hasLength(4)); // 2*2 solutions
    });

    test('is deterministic for a fixed seed, varies across seeds', () async {
      final a = await _grid(6).sampleSolutions(3, seed: 42);
      final b = await _grid(6).sampleSolutions(3, seed: 42);
      final c = await _grid(6).sampleSolutions(3, seed: 7);
      String key(List<Map<String, dynamic>> l) =>
          l.map((s) => '${s['a']},${s['b']}').join('|');
      expect(key(a), key(b), reason: 'same seed -> same sample');
      expect(key(a), isNot(key(c)), reason: 'different seed -> different');
    });

    test('is roughly uniform over the solution set', () async {
      // Draw 1 sample many times with varying seeds; every one of the 9
      // solutions of the 3x3 grid should show up.
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final s = (await _grid(3).sampleSolutions(1, seed: seed)).single;
        seen.add('${s['a']},${s['b']}');
      }
      expect(seen, hasLength(9),
          reason: 'all 9 solutions sampled at least once');
    });

    test('k = 0 returns empty; negative k throws', () async {
      expect(await _grid(3).sampleSolutions(0), isEmpty);
      expect(() => _grid(3).sampleSolutions(-1), throwsArgumentError);
    });

    test('unsatisfiable problem yields no samples', () async {
      final p = Problem()
        ..addVariables(['a', 'b'], [1, 2])
        ..addStringConstraint('a == b')
        ..addStringConstraint('a != b');
      expect(await p.sampleSolutions(5), isEmpty);
    });
  });

  group('randomSolution', () {
    test('returns a valid solution, deterministic for a seed', () async {
      final a = await _grid(4).randomSolution(seed: 3);
      final b = await _grid(4).randomSolution(seed: 3);
      expect(a, isNotNull);
      expect(a, equals(b));
    });

    test('returns null when unsatisfiable', () async {
      final p = Problem()
        ..addVariables(['a'], [1])
        ..addStringConstraint('a != 1');
      expect(await p.randomSolution(), isNull);
    });
  });

  group('diverseSolutions', () {
    test('returns k mutually distinct solutions', () async {
      final got = await _grid(5).diverseSolutions(4, seed: 1);
      expect(got, hasLength(4));
      final keys = got.map((s) => '${s['a']},${s['b']}').toSet();
      expect(keys, hasLength(4));
    });

    test('greedy set is at least as spread out as a naive prefix', () async {
      // Sum of pairwise Hamming distance for the diverse set should beat
      // just taking the first k enumerated solutions.
      int spread(List<Map<String, dynamic>> sols) {
        var total = 0;
        for (var i = 0; i < sols.length; i++) {
          for (var j = i + 1; j < sols.length; j++) {
            total += _hamming(sols[i], sols[j]);
          }
        }
        return total;
      }

      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [for (var i = 0; i < 4; i++) i]);
      final diverse = await p.diverseSolutions(4, seed: 1);
      final prefix = <Map<String, dynamic>>[];
      await for (final s in p.getSolutions()) {
        prefix.add(s);
        if (prefix.length == 4) break;
      }
      expect(spread(diverse), greaterThanOrEqualTo(spread(prefix)));
    });

    test('returns all solutions when pool has at most k', () async {
      final got = await _grid(2).diverseSolutions(10);
      expect(got, hasLength(4));
    });

    test('maxPool bounds the candidate set', () async {
      // Only the first 3 solutions are pooled, so at most 3 come back.
      final got = await _grid(10).diverseSolutions(5, maxPool: 3, seed: 1);
      expect(got, hasLength(3));
    });

    test('argument validation', () async {
      expect(() => _grid(3).diverseSolutions(-1), throwsArgumentError);
      expect(
          () => _grid(3).diverseSolutions(2, maxPool: 0), throwsArgumentError);
      expect(await _grid(3).diverseSolutions(0), isEmpty);
    });
  });
}

// Solution sampling and diversity, layered on the [Problem.getSolutions]
// enumeration stream.
//
// These complement the exact [Problem.countSolutions]: rather than *how
// many* solutions exist, they answer *give me some* — uniformly at random,
// or spread out across the solution space. All three are engine-free; they
// only consume the public enumeration stream.

import 'dart:math';

import 'problem.dart';
import 'types.dart';

/// Sampling and diversity helpers over a [Problem]'s solution set.
extension SolutionSampling on Problem {
  /// Returns up to [k] solutions drawn **uniformly at random without
  /// replacement** from the full solution set.
  ///
  /// Implemented with reservoir sampling (Vitter's Algorithm R) over
  /// [getSolutions], so every k-subset of solutions is equally likely and
  /// only [k] solutions are ever held in memory. The trade-off is time: the
  /// enumeration stream is consumed to the end, so cost scales with the
  /// *total* number of solutions, not with [k]. For a problem with an
  /// enormous solution set, prefer bounding the model or using
  /// [randomSolution] with a search-order seed if approximate randomness is
  /// acceptable.
  ///
  /// With a fixed [seed] the result is deterministic (the enumeration order
  /// is deterministic, so the same seed selects the same subset). Returns
  /// fewer than [k] — possibly empty — if the problem has fewer than [k]
  /// solutions. Throws [ArgumentError] if [k] is negative.
  Future<List<Map<String, dynamic>>> sampleSolutions(
    int k, {
    int? seed,
    CancellationToken? cancelToken,
  }) async {
    if (k < 0) throw ArgumentError.value(k, 'k', 'must be >= 0');
    if (k == 0) return [];
    final rng = Random(seed);
    final reservoir = <Map<String, dynamic>>[];
    var seen = 0;
    await for (final sol in getSolutions(cancelToken: cancelToken)) {
      seen++;
      if (reservoir.length < k) {
        reservoir.add(sol);
      } else {
        // Replace a random reservoir slot with probability k/seen; this
        // keeps every seen-so-far solution equally likely to survive.
        final j = rng.nextInt(seen);
        if (j < k) reservoir[j] = sol;
      }
    }
    return reservoir;
  }

  /// A single solution drawn uniformly at random, or `null` if the problem
  /// is unsatisfiable. Convenience wrapper over [sampleSolutions] with
  /// `k == 1`; the same enumeration cost applies.
  Future<Map<String, dynamic>?> randomSolution({
    int? seed,
    CancellationToken? cancelToken,
  }) async {
    final s = await sampleSolutions(1, seed: seed, cancelToken: cancelToken);
    return s.isEmpty ? null : s.first;
  }

  /// Returns up to [k] solutions chosen to be **mutually different** — a
  /// greedy maximum-diversity set under Hamming distance (the number of
  /// variables assigned different values between two solutions).
  ///
  /// The algorithm collects a candidate pool of at most [maxPool] solutions
  /// from [getSolutions], then greedily builds the result: start from one
  /// solution, and repeatedly add the pooled solution whose minimum Hamming
  /// distance to the already-chosen set is largest. This is the standard
  /// greedy approximation — exact maximum-diversity selection is NP-hard —
  /// and it is what powers "give me a handful of genuinely different"
  /// results (e.g. distinct puzzle layouts).
  ///
  /// [maxPool] bounds both memory and quality: only the first [maxPool]
  /// enumerated solutions are considered, so a larger pool gives more
  /// diverse picks at higher cost. With a fixed [seed] the choice of the
  /// initial solution (and hence the whole greedy chain) is deterministic.
  /// Returns all pooled solutions if the pool has at most [k] of them.
  /// Throws [ArgumentError] if [k] is negative or [maxPool] < 1.
  Future<List<Map<String, dynamic>>> diverseSolutions(
    int k, {
    int maxPool = 1000,
    int? seed,
    CancellationToken? cancelToken,
  }) async {
    if (k < 0) throw ArgumentError.value(k, 'k', 'must be >= 0');
    if (maxPool < 1) {
      throw ArgumentError.value(maxPool, 'maxPool', 'must be >= 1');
    }
    if (k == 0) return [];

    final pool = <Map<String, dynamic>>[];
    await for (final sol in getSolutions(cancelToken: cancelToken)) {
      pool.add(sol);
      if (pool.length >= maxPool) break;
    }
    if (pool.length <= k) return pool;

    final rng = Random(seed);
    final chosen = <Map<String, dynamic>>[
      pool.removeAt(rng.nextInt(pool.length))
    ];
    while (chosen.length < k && pool.isNotEmpty) {
      var bestIdx = 0;
      var bestMinDist = -1;
      for (var i = 0; i < pool.length; i++) {
        var minDist = 1 << 30;
        for (final c in chosen) {
          final d = _hamming(pool[i], c);
          if (d < minDist) minDist = d;
          if (minDist <= bestMinDist) break; // can't beat the incumbent
        }
        if (minDist > bestMinDist) {
          bestMinDist = minDist;
          bestIdx = i;
        }
      }
      chosen.add(pool.removeAt(bestIdx));
    }
    return chosen;
  }
}

/// Number of variables assigned different values between two solutions.
/// Both maps come from the same [Problem], so they share a key set.
int _hamming(Map<String, dynamic> a, Map<String, dynamic> b) {
  var d = 0;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) d++;
  }
  return d;
}

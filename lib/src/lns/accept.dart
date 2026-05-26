/// Acceptance strategies for Large Neighborhood Search.
///
/// An [LnsAccept] decides whether each iteration's candidate solution
/// should replace the current incumbent. The textbook default is
/// improving-only ([LnsAccept.improving]); [LnsAccept.simulatedAnnealing]
/// admits a controlled fraction of worsening moves to escape local
/// optima on hard instances.
// LnsAccept is a one-member abstract class on purpose: its factory
// constructors discriminate between builtin strategies, but a bare
// typedef cannot host a `factory` constructor.
// ignore_for_file: one_member_abstracts
library;

import 'dart:math';

/// Decides whether each iteration's candidate solution should replace
/// the current incumbent.
abstract class LnsAccept {
  /// Strict improvement only. Converges to a local optimum.
  factory LnsAccept.improving() => _ImprovingLnsAccept();

  /// Simulated-annealing acceptance: improvements are always accepted;
  /// worsening moves are accepted with probability `exp(-Δ / T)`,
  /// where Δ is the absolute objective gap and the temperature
  /// `T = initialTemp × cooling^iteration`. The textbook cooling
  /// schedule; pair with a problem-tuned [initialTemp] (close to the
  /// expected objective jump per iteration) and a [cooling] near 1
  /// for slow annealing or below ~0.95 for aggressive annealing.
  factory LnsAccept.simulatedAnnealing({
    double initialTemp = 1.0,
    double cooling = 0.995,
  }) =>
      _SimulatedAnnealingLnsAccept(initialTemp, cooling);

  /// Late-acceptance hill-climbing (Burke et al. 2017). Maintains a
  /// circular buffer of the previous [historySize] incumbent
  /// objectives and accepts a candidate iff it is at least as good as
  /// either the current incumbent or the historical entry at position
  /// `iteration mod historySize`. Empirically strong on combinatorial
  /// optimization; the only hyperparameter is the history length,
  /// which controls how aggressively the search escapes local optima
  /// (larger = more permissive). Burke et al. report values in the
  /// 50-5000 range across their experiments.
  ///
  /// The acceptance is **stateful** — each `LnsAccept.lateAcceptance`
  /// instance owns its own history. Reuse one instance per LNS run
  /// and don't share across concurrent runs.
  factory LnsAccept.lateAcceptance({int historySize = 100}) =>
      _LateAcceptanceLnsAccept(historySize);

  /// Returns `true` if [candidate] should replace the current incumbent
  /// with objective [incumbent]. Implementations may use [iteration]
  /// (for cooling schedules) and [rng] (for randomised acceptance).
  /// [minimizing] is `true` when the host LNS is minimising.
  bool accept({
    required num candidate,
    required num incumbent,
    required int iteration,
    required bool minimizing,
    required Random rng,
  });
}

class _ImprovingLnsAccept implements LnsAccept {
  @override
  bool accept({
    required num candidate,
    required num incumbent,
    required int iteration,
    required bool minimizing,
    required Random rng,
  }) =>
      minimizing ? candidate < incumbent : candidate > incumbent;
}

class _LateAcceptanceLnsAccept implements LnsAccept {
  _LateAcceptanceLnsAccept(this.historySize) {
    if (historySize <= 0) {
      throw ArgumentError('LnsAccept.lateAcceptance: historySize must be > 0; '
          'got $historySize');
    }
  }

  final int historySize;
  late final List<num> _history = List<num>.filled(historySize, 0);
  bool _initialised = false;

  @override
  bool accept({
    required num candidate,
    required num incumbent,
    required int iteration,
    required bool minimizing,
    required Random rng,
  }) {
    if (!_initialised) {
      for (var i = 0; i < historySize; i++) {
        _history[i] = incumbent;
      }
      _initialised = true;
    }
    final v = iteration % historySize;
    final older = _history[v];
    // Classic LAHC (Burke et al. 2017): accept iff candidate beats
    // either the older history entry OR the current incumbent. The
    // OR-with-incumbent clause is what keeps the search descending
    // monotonically toward a local optimum even when the history is
    // full of stale large values.
    final beatsOlder = minimizing ? candidate < older : candidate > older;
    final beatsIncumbent =
        minimizing ? candidate < incumbent : candidate > incumbent;
    final accepted = beatsOlder || beatsIncumbent;
    // History records the post-acceptance incumbent so future
    // comparisons reflect the actual search trajectory.
    _history[v] = accepted ? candidate : incumbent;
    return accepted;
  }
}

class _SimulatedAnnealingLnsAccept implements LnsAccept {
  _SimulatedAnnealingLnsAccept(this.initialTemp, this.cooling) {
    if (initialTemp <= 0) {
      throw ArgumentError(
          'LnsAccept.simulatedAnnealing: initialTemp must be > 0; '
          'got $initialTemp');
    }
    if (cooling <= 0 || cooling > 1) {
      throw ArgumentError(
          'LnsAccept.simulatedAnnealing: cooling must be in (0, 1]; '
          'got $cooling');
    }
  }

  final double initialTemp;
  final double cooling;

  @override
  bool accept({
    required num candidate,
    required num incumbent,
    required int iteration,
    required bool minimizing,
    required Random rng,
  }) {
    final improving =
        minimizing ? candidate < incumbent : candidate > incumbent;
    if (improving) return true;
    if (candidate == incumbent) return false;
    final delta =
        (minimizing ? candidate - incumbent : incumbent - candidate).toDouble();
    final t = initialTemp * pow(cooling, iteration).toDouble();
    if (t <= 0) return false;
    final p = exp(-delta / t);
    return rng.nextDouble() < p;
  }
}

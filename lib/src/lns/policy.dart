/// Destroy policies for Large Neighborhood Search.
///
/// A destroy policy selects, for each LNS iteration, the variables to
/// "free" — those will be unpinned for the inner re-solve while every
/// other variable stays fixed to its value in the current incumbent.
/// See `doc/lns.md` for the full picture and
/// `extension LargeNeighborhoodSearch on Problem` for the entry points.
// LnsPolicy is a one-member abstract class on purpose: its factory
// constructors discriminate between builtin policies, but a bare
// typedef cannot host a `factory` constructor.
// ignore_for_file: one_member_abstracts
library;

import 'dart:math';

/// Read-only context passed to [LnsPolicy.select] each iteration. Holds
/// everything a policy needs to make its decision: the variable name
/// list (in declaration order), the current best solution and its
/// objective, the iteration counter, the shared RNG, and a constraint-
/// variable adjacency map (built once at LNS start).
class LnsContext {
  LnsContext({
    required this.variableNames,
    required this.bestSolution,
    required this.bestObjective,
    required this.iteration,
    required this.rng,
    required this.constraintAdjacency,
  });

  /// All variable names in the host [Problem], in declaration order.
  /// Includes internal indicator variables for set-valued helpers; a
  /// destroy policy that addresses set variables by user name must
  /// filter accordingly.
  final List<String> variableNames;

  /// The current best solution. Keys are variable names; values are
  /// the assigned values from the most recent accepted candidate. The
  /// map is the raw solver assignment — set-variable indicators have
  /// not been materialised back to `Set<dynamic>` because LNS pins by
  /// the underlying CSP variable.
  final Map<String, dynamic> bestSolution;

  /// The objective value of [bestSolution].
  final num bestObjective;

  /// Zero-based iteration counter. The first call sees `0`.
  final int iteration;

  /// Shared RNG. Deterministic when the caller passed `seed:` to
  /// `lnsMinimize` / `lnsMaximize`; otherwise time-seeded. All
  /// randomness inside a policy should go through this instance to
  /// keep runs reproducible.
  final Random rng;

  /// `constraintAdjacency[v]` is the set of other variable names that
  /// share at least one constraint with `v`. Built once at LNS start
  /// from the host problem's binary and n-ary constraints. Used by
  /// [LnsPolicy.related] but available to user policies as well.
  final Map<String, Set<String>> constraintAdjacency;
}

/// Selects which variables to free each LNS iteration. The five
/// builtin factory constructors cover the textbook policies; user
/// policies can `implements LnsPolicy` with a single `select` method.
/// Stateful policies that need per-iteration feedback should extend
/// [LnsAdaptivePolicy] instead (which adds the `observe` hook).
abstract class LnsPolicy {
  /// Pick a uniformly random fraction of variables to free each
  /// iteration. The textbook starting point (Shaw 1998 used
  /// 0.15-0.4). At least one variable is always freed so the inner
  /// solve has something to search over.
  factory LnsPolicy.random({double fraction = 0.2}) =>
      _RandomLnsPolicy(fraction);

  /// Pick a contiguous window of [windowSize] variables (by
  /// declaration order) starting at a random offset each iteration.
  /// Cheap, but useful on scheduling problems where adjacent
  /// variables share constraints.
  factory LnsPolicy.window({required int windowSize}) =>
      _WindowLnsPolicy(windowSize);

  /// Shaw 1998's "related" destroy heuristic. Pick [seedCount] random
  /// seed variables, then extend the freed set via the constraint-
  /// variable adjacency graph until at least
  /// `max(seedCount, (n × extendFraction).round())` variables are
  /// freed (capped at the variable count). Recovers cluster structure
  /// that pure random destroys miss.
  factory LnsPolicy.related({
    int seedCount = 1,
    double extendFraction = 0.2,
  }) =>
      _RelatedLnsPolicy(seedCount, extendFraction);

  /// Weighted-random pick from a list of sub-policies each iteration.
  /// If [weights] is null, sub-policies are picked uniformly. Lays
  /// the groundwork for Adaptive LNS (Ropke & Pisinger 2006) by
  /// making "multiple destroys per run" first-class.
  factory LnsPolicy.combined(
    List<LnsPolicy> policies, {
    List<double>? weights,
  }) =>
      _CombinedLnsPolicy(policies, weights);

  /// Adaptive Large Neighborhood Search (Ropke & Pisinger 2006). Like
  /// [LnsPolicy.combined], but each sub-policy's selection probability
  /// adjusts based on its observed reward. After each iteration the
  /// orchestrator calls `observe` on the returned [LnsAdaptivePolicy]
  /// with `accepted` and `improvedBest` flags; the policy accumulates
  /// per-policy score and pick count over a window of [segmentSize]
  /// iterations, then re-normalises weights as
  ///
  ///     w_new = (1 - smoothingFactor) * w_old +
  ///             smoothingFactor * (segmentScore / segmentPicks)
  ///
  /// at each segment boundary. [rewardBest] is awarded when the
  /// candidate improved the global best-so-far; [rewardAccepted] is
  /// awarded when the candidate was accepted by the acceptance
  /// strategy but did not improve the best-so-far (e.g. an SA-
  /// admitted worsening move); rejected candidates score zero. The
  /// defaults match the textbook prototype (σ values from
  /// Ropke-Pisinger normalised to a [0, 5] range).
  ///
  /// The policy is **stateful** — reuse one instance per LNS run.
  /// Returns the more specific [LnsAdaptivePolicy] so callers can
  /// inspect `weights` and call `observe` without a cast; the
  /// orchestrator type-checks `policy is LnsAdaptivePolicy` to
  /// decide whether to dispatch `observe`.
  static LnsAdaptivePolicy adaptive(
    List<LnsPolicy> policies, {
    double smoothingFactor = 0.1,
    int segmentSize = 100,
    double rewardBest = 5,
    double rewardAccepted = 1,
  }) =>
      _AdaptiveLnsPolicy(
        policies,
        smoothingFactor: smoothingFactor,
        segmentSize: segmentSize,
        rewardBest: rewardBest,
        rewardAccepted: rewardAccepted,
      );

  /// Returns the variable names to free this iteration. Every other
  /// variable is pinned to its value in the current incumbent for the
  /// inner re-solve. May read [ctx.iteration], [ctx.bestSolution],
  /// [ctx.constraintAdjacency], and [ctx.rng].
  List<String> select(LnsContext ctx);
}

/// Extension of [LnsPolicy] for stateful policies that need per-
/// iteration feedback from the LNS orchestrator. The orchestrator
/// type-checks (`if (policy is LnsAdaptivePolicy) policy.observe(…)`)
/// and dispatches; pure-`LnsPolicy` impls don't need to know about
/// this hook.
///
/// Subclass when writing custom adaptive destroys; the shipped
/// [LnsPolicy.adaptive] factory returns an [LnsAdaptivePolicy].
abstract class LnsAdaptivePolicy implements LnsPolicy {
  /// Called by the LNS orchestrator after each iteration. [accepted]
  /// is true when the acceptance strategy admitted the candidate;
  /// [improvedBest] is true when the accepted candidate strictly
  /// improved the best objective seen so far. The implementation
  /// typically updates internal weights / scores from this signal.
  void observe({
    required LnsContext ctx,
    required bool accepted,
    required bool improvedBest,
  });

  /// Current per-sub-policy selection weights, in the same order as
  /// the policies passed at construction. Useful for inspecting the
  /// adapted distribution after a run; the underlying impl updates
  /// these in place across segments.
  List<double> get weights;
}

class _RandomLnsPolicy implements LnsPolicy {
  _RandomLnsPolicy(this.fraction) {
    if (fraction <= 0 || fraction > 1) {
      throw ArgumentError(
          'LnsPolicy.random: fraction must be in (0, 1]; got $fraction');
    }
  }

  final double fraction;

  @override
  List<String> select(LnsContext ctx) {
    final n = ctx.variableNames.length;
    if (n == 0) return const [];
    final k = max(1, (n * fraction).round()).clamp(1, n);
    final shuffled = List<String>.of(ctx.variableNames)..shuffle(ctx.rng);
    return shuffled.sublist(0, k);
  }
}

class _WindowLnsPolicy implements LnsPolicy {
  _WindowLnsPolicy(this.windowSize) {
    if (windowSize <= 0) {
      throw ArgumentError(
          'LnsPolicy.window: windowSize must be >= 1; got $windowSize');
    }
  }

  final int windowSize;

  @override
  List<String> select(LnsContext ctx) {
    final n = ctx.variableNames.length;
    if (n == 0) return const [];
    final w = windowSize.clamp(1, n);
    final maxStart = n - w;
    final start = maxStart <= 0 ? 0 : ctx.rng.nextInt(maxStart + 1);
    return ctx.variableNames.sublist(start, start + w);
  }
}

class _RelatedLnsPolicy implements LnsPolicy {
  _RelatedLnsPolicy(this.seedCount, this.extendFraction) {
    if (seedCount <= 0) {
      throw ArgumentError(
          'LnsPolicy.related: seedCount must be >= 1; got $seedCount');
    }
    if (extendFraction < 0 || extendFraction > 1) {
      throw ArgumentError(
          'LnsPolicy.related: extendFraction must be in [0, 1]; '
          'got $extendFraction');
    }
  }

  final int seedCount;
  final double extendFraction;

  @override
  List<String> select(LnsContext ctx) {
    final n = ctx.variableNames.length;
    if (n == 0) return const [];
    final target = max(seedCount, (n * extendFraction).round()).clamp(1, n);

    final shuffled = List<String>.of(ctx.variableNames)..shuffle(ctx.rng);
    final freed = <String>{};
    final frontier = <String>[];
    final seeds = min(seedCount, n);
    for (var i = 0; i < seeds; i++) {
      freed.add(shuffled[i]);
      frontier.add(shuffled[i]);
    }

    // BFS-style expansion through the constraint-variable graph until
    // we hit the target size. Neighbours are visited in random order
    // so different iterations grow different clusters even when the
    // seeds happen to overlap.
    while (freed.length < target && frontier.isNotEmpty) {
      final v = frontier.removeAt(ctx.rng.nextInt(frontier.length));
      final neighbours = ctx.constraintAdjacency[v];
      if (neighbours == null || neighbours.isEmpty) continue;
      final candidates = neighbours.where((n) => !freed.contains(n)).toList()
        ..shuffle(ctx.rng);
      for (final c in candidates) {
        if (freed.length >= target) break;
        freed.add(c);
        frontier.add(c);
      }
    }

    return freed.toList(growable: false);
  }
}

class _CombinedLnsPolicy implements LnsPolicy {
  _CombinedLnsPolicy(this.policies, List<double>? weights)
      : weights = _normaliseWeights(policies.length, weights) {
    if (policies.isEmpty) {
      throw ArgumentError('LnsPolicy.combined: policies must not be empty');
    }
  }

  final List<LnsPolicy> policies;
  final List<double> weights;

  static List<double> _normaliseWeights(int n, List<double>? input) {
    if (input == null) {
      return List<double>.filled(n, 1.0 / n);
    }
    if (input.length != n) {
      throw ArgumentError(
          'LnsPolicy.combined: weights.length (${input.length}) '
          'must equal policies.length ($n)');
    }
    var total = 0.0;
    for (final w in input) {
      if (w < 0) {
        throw ArgumentError(
            'LnsPolicy.combined: weights must be non-negative; got $w');
      }
      total += w;
    }
    if (total <= 0) {
      throw ArgumentError(
          'LnsPolicy.combined: at least one weight must be positive');
    }
    return [for (final w in input) w / total];
  }

  @override
  List<String> select(LnsContext ctx) {
    final r = ctx.rng.nextDouble();
    var acc = 0.0;
    for (var i = 0; i < policies.length; i++) {
      acc += weights[i];
      if (r < acc) return policies[i].select(ctx);
    }
    // Float drift safety net — pick the last with positive weight.
    return policies.last.select(ctx);
  }
}

class _AdaptiveLnsPolicy implements LnsAdaptivePolicy {
  _AdaptiveLnsPolicy(
    this.policies, {
    required this.smoothingFactor,
    required this.segmentSize,
    required this.rewardBest,
    required this.rewardAccepted,
  })  : weights = List<double>.filled(policies.length, 1.0),
        _segmentScore = List<double>.filled(policies.length, 0),
        _segmentPicks = List<int>.filled(policies.length, 0) {
    if (policies.isEmpty) {
      throw ArgumentError('LnsPolicy.adaptive: policies must not be empty');
    }
    if (smoothingFactor < 0 || smoothingFactor > 1) {
      throw ArgumentError(
          'LnsPolicy.adaptive: smoothingFactor must be in [0, 1]; '
          'got $smoothingFactor');
    }
    if (segmentSize <= 0) {
      throw ArgumentError(
          'LnsPolicy.adaptive: segmentSize must be > 0; got $segmentSize');
    }
    if (rewardBest < 0 || rewardAccepted < 0) {
      throw ArgumentError('LnsPolicy.adaptive: rewards must be non-negative');
    }
  }

  final List<LnsPolicy> policies;
  final double smoothingFactor;
  final int segmentSize;
  final double rewardBest;
  final double rewardAccepted;

  /// Current selection weights, one per sub-policy. Public so callers
  /// can inspect the adapted distribution after a run. Re-normalised
  /// every [segmentSize] iterations during a run.
  @override
  final List<double> weights;
  final List<double> _segmentScore;
  final List<int> _segmentPicks;
  int? _lastPickedIndex;

  @override
  List<String> select(LnsContext ctx) {
    var total = 0.0;
    for (final w in weights) {
      total += w;
    }
    var r = ctx.rng.nextDouble() * total;
    var idx = policies.length - 1;
    for (var i = 0; i < policies.length; i++) {
      r -= weights[i];
      if (r < 0) {
        idx = i;
        break;
      }
    }
    _lastPickedIndex = idx;
    _segmentPicks[idx]++;
    return policies[idx].select(ctx);
  }

  @override
  void observe({
    required LnsContext ctx,
    required bool accepted,
    required bool improvedBest,
  }) {
    final idx = _lastPickedIndex;
    if (idx == null) return;
    final reward = improvedBest
        ? rewardBest
        : accepted
            ? rewardAccepted
            : 0.0;
    _segmentScore[idx] += reward;
    // Re-normalise at each segment boundary. ctx.iteration is the
    // index of the iteration that just completed (the orchestrator
    // passes it in *before* incrementing), so `(iteration + 1)`
    // counts iterations seen so far.
    final completed = ctx.iteration + 1;
    if (completed % segmentSize == 0) {
      for (var i = 0; i < weights.length; i++) {
        if (_segmentPicks[i] > 0) {
          final segmentAvg = _segmentScore[i] / _segmentPicks[i];
          weights[i] =
              weights[i] * (1 - smoothingFactor) + smoothingFactor * segmentAvg;
          // Guard against a degenerate zero-weight scenario by
          // floor-ing weights at a small positive value — otherwise a
          // bad early segment can permanently exile a sub-policy.
          if (weights[i] < 1e-6) weights[i] = 1e-6;
        }
        _segmentScore[i] = 0;
        _segmentPicks[i] = 0;
      }
    }
  }
}

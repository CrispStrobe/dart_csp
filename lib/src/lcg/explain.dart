/// Explanation graph for Lazy Clause Generation (LCG) M1.
///
/// Every prune the engine performs records an [ImplicationEntry] on
/// a trail parallel to the engine's existing `_trail`. The entry
/// pairs the *pruned atom* (what changed) with an [ImplicationReason]
/// (why it changed). M2's first-UIP conflict analysis walks this
/// trail backward from a propagation failure to extract a learned
/// clause.
///
/// M1 scope: types + the per-prune wiring. M1 lands [UnknownReason]
/// as a placeholder; concrete per-propagator reason subclasses
/// (`AllDifferentReason`, `LinearBoundReason`, etc.) are M3 work.
///
/// See `LCG_PLAN.md` §2 for the contract.
library;

import 'atom.dart';

/// Why a prune happened. Conflict analysis calls [antecedents] to
/// resolve the prune against the literals that forced it. Will grow
/// concrete per-propagator subclasses in M3.
// ignore: one_member_abstracts
abstract class ImplicationReason {
  const ImplicationReason();

  /// The atoms whose joint truth at the time of the prune forced
  /// [ImplicationEntry.prunedAtom]'s negation. The first-UIP loop
  /// resolves the working clause against these.
  ///
  /// Concrete subclasses materialise antecedents lazily where
  /// reconstruction is cheap (Chuffed's approach) and eagerly where
  /// the propagator state isn't trail-preserved.
  List<Atom> antecedents();
}

/// Placeholder reason used during M1 before per-propagator
/// explanation companions exist. Has no antecedents, so M2 conflict
/// analysis treats any prune carrying an [UnknownReason] as opaque
/// — analysis stops there. Once M3 lands per-propagator subclasses
/// of [ImplicationReason], the engine routes prunes through those
/// instead and this type goes away from runtime paths.
class UnknownReason extends ImplicationReason {
  const UnknownReason();

  @override
  List<Atom> antecedents() => const [];

  @override
  String toString() => 'UnknownReason';
}

/// A decision-site pin recorded on the implication trail. Decision
/// pins have no antecedents — they're the search's free choices —
/// so they form the roots of the implication graph.
class DecisionReason extends ImplicationReason {
  const DecisionReason();

  @override
  List<Atom> antecedents() => const [];

  @override
  String toString() => 'DecisionReason';
}

/// One entry on the implication trail. The trail is append-only
/// during propagation and rolled back in lockstep with the engine's
/// domain trail.
class ImplicationEntry {
  const ImplicationEntry({
    required this.prunedAtom,
    required this.reason,
    required this.trailIndex,
    required this.decisionLevel,
  });

  /// The atom whose truth was forced by this prune.
  final Atom prunedAtom;

  /// Why the prune happened.
  final ImplicationReason reason;

  /// Position in the engine's `_trail` this entry corresponds to.
  /// Used for trail rollback: on rollback to mark `m`, every entry
  /// with `trailIndex >= m` is popped.
  final int trailIndex;

  /// Decision level (number of decision pins committed before this
  /// entry was appended). `0` ≡ root-level propagation (no decisions
  /// made yet).
  final int decisionLevel;

  @override
  String toString() =>
      'ImplicationEntry($prunedAtom, $reason, trailIndex=$trailIndex, dl=$decisionLevel)';
}

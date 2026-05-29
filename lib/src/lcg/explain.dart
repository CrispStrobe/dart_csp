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

/// Reason emitted by `_AllDifferentPropagator` (M3a) when the Régin
/// matching prunes a value (or fails outright). The natural
/// explanation is the **Hall set** that covers the prune: a subset of
/// variables whose union of current domains has cardinality ≤
/// |subset|, so the pruned value is forced. The propagator already
/// computes the SCC decomposition of the residual matching graph;
/// reading the Hall set off it is just collecting the variables in
/// the SCC containing the pruned value.
///
/// For a per-variable prune (multiple values pruned from one variable
/// in a single propagator call), the Hall set is the union of SCCs
/// of all pruned values. The antecedent atoms are then `AtomNe(h, k)`
/// for every Hall-set variable `h` and every value `k` declared in
/// `h`'s domain at problem-construction time but absent from `h`'s
/// current domain — i.e., "given that these values are missing from
/// these variables, the prune is forced." For a constraint-level
/// conflict (the matching can't satisfy every variable, or a
/// post-prune domain is empty) the Hall set is the entire constraint
/// scope.
///
/// `antecedents()` returns the precomputed list; M2's first-UIP loop
/// resolves the working clause against this list while walking the
/// implication trail backward. Reference: Régin 1994 + Quimper &
/// Walsh 2008.
class AllDifferentReason extends ImplicationReason {
  const AllDifferentReason(this.antecedentAtoms);

  /// Atoms whose joint truth at the time of the prune forced
  /// [ImplicationEntry.prunedAtom]'s negation. Each entry has the
  /// shape `AtomNe(varName, value)` — "this value is currently
  /// missing from this variable's domain."
  final List<Atom> antecedentAtoms;

  @override
  List<Atom> antecedents() => antecedentAtoms;

  @override
  String toString() => 'AllDifferentReason(${antecedentAtoms.join(", ")})';
}

/// Reason emitted by `_LinearPropagator` (M3b) when bounds-consistency
/// propagation prunes a value from one variable's domain in a linear
/// arithmetic constraint `Σ cᵢxᵢ ∘ b`.
///
/// The propagator computes each variable's residual interval
/// `[Sⱼ_min, Sⱼ_max]` from the *other* variables' current min/max
/// bounds. A value `v` of `xⱼ` survives only if `cⱼ·v + S` satisfies
/// the comparison for some `S` in that interval. The natural
/// explanation is bounds-shaped — "the other variables have bounds
/// `[lbᵢ, ubᵢ]`, so v must be in this range" — but the dart_csp
/// implication trail only emits `AtomEq` / `AtomNe` entries today, so
/// `AtomLe` / `AtomGe` antecedents wouldn't resolve against trail
/// entries. The M3b explanation falls back to the coarse-but-sound
/// shape used by M3a: `AtomNe(xᵢ, k)` for every other variable `xᵢ`
/// in the constraint and every value `k` declared in `xᵢ`'s original
/// domain but absent from its current domain.
///
/// Sound: bounds consistency depends only on each variable's
/// min/max, which is a function of which values remain in the
/// domain. Any state where these absences continue to hold has the
/// same min/max bounds (or narrower) for the other variables, so the
/// same prune is forced. The learned clause is wider than the tight
/// "other-variable bounds" version would be; M5 / a future trail-
/// encoding refinement could swap to bound atoms once the trail
/// emits them.
class LinearBoundReason extends ImplicationReason {
  const LinearBoundReason(this.antecedentAtoms);

  /// Atoms whose joint truth at the time of the prune forced
  /// [ImplicationEntry.prunedAtom]'s negation. Each entry has the
  /// shape `AtomNe(varName, value)` — "this value is currently
  /// missing from this variable's domain."
  final List<Atom> antecedentAtoms;

  @override
  List<Atom> antecedents() => antecedentAtoms;

  @override
  String toString() => 'LinearBoundReason(${antecedentAtoms.join(", ")})';
}

/// Reason emitted by `_GccPropagator` (M3c) when the Régin network-flow
/// matching prunes a value (or the constraint fails outright).
///
/// The global cardinality constraint generalises allDifferent with
/// per-value multiplicity: each value `v` has up to `upper[v]` "copies"
/// in the matching graph. A value is pruned from a variable when *every*
/// copy of it is unavailable to that variable — each copy is either held
/// by a variable pinned to `v` (assignment) or trapped in a tight SCC
/// (a Régin Hall set, generalised over copies). The explanation mirrors
/// `AllDifferentReason`'s shape: the antecedents are synthetic
/// [AtomInScc] bridges (committed by the propagator) that collapse each
/// such argument into a single resolvable atom, so the first-UIP walk
/// converges instead of drowning in a flat absence list.
///
/// `antecedents()` returns the precomputed bridge list; the analyser
/// resolves the working clause against it. Reference: Régin 1996.
class GccFlowReason extends ImplicationReason {
  const GccFlowReason(this.antecedentAtoms);

  /// Atoms whose joint truth at the time of the prune forced
  /// [ImplicationEntry.prunedAtom]'s negation — synthetic [AtomInScc]
  /// bridges (and, for assignment-style prunes, the on-trail
  /// `AtomEq(owner, value)` they resolve to).
  final List<Atom> antecedentAtoms;

  @override
  List<Atom> antecedents() => antecedentAtoms;

  @override
  String toString() => 'GccFlowReason(${antecedentAtoms.join(", ")})';
}

/// Reason emitted by `_ClausePropagator` when a clause unit-props.
///
/// Given a clause `(L1 ∨ L2 ∨ … ∨ Lk)` whose every literal but `Li`
/// has been falsified, the propagator forces `Li`'s satisfying value
/// and records the antecedent atoms — one per falsified other
/// literal. Each falsified literal `(v, positive)` is currently
/// pinned to its falsifying value, so the antecedent atom is
/// `AtomEq(v, positive ? 0 : 1)`.
///
/// `antecedents()` returns the list captured at prune time; the
/// first-UIP analyser resolves the working clause against this list
/// while walking the implication trail backward.
class ClauseReason extends ImplicationReason {
  const ClauseReason(this.antecedentAtoms);

  /// The atoms that, taken jointly with the pruned atom's
  /// negation, are unsatisfiable. M2's first-UIP loop resolves
  /// out the most-recent of these in turn.
  final List<Atom> antecedentAtoms;

  @override
  List<Atom> antecedents() => antecedentAtoms;

  @override
  String toString() => 'ClauseReason(${antecedentAtoms.join(", ")})';
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

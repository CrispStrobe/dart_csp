/// Atom encoding for Lazy Clause Generation (LCG).
///
/// An *atom* is a single literal-style claim about a CSP variable's
/// integer domain: `x = v`, `x ≠ v`, `x ≤ v`, or `x ≥ v`. The four
/// shapes cover every prune the existing specialised propagators
/// make — value removal ([AtomNe]), assignment ([AtomEq]), and the
/// bounds tightening that linear / cumulative propagators emit
/// ([AtomLe] / [AtomGe]). Boolean variables fold into the integer
/// shape as `x = 0` / `x = 1`.
///
/// LCG conflict analysis (M2) walks an implication trail built from
/// these atoms; this M1 file lands the atom encoding and a minimal
/// public [DomainView] interface so the trail can be inspected and
/// tested without exposing engine internals.
///
/// See `LCG_PLAN.md` §2 for the architectural sketch and §4 for the
/// lazy-vs-eager encoding decision.
library;

/// Read-only view of a single variable's current integer domain.
///
/// Atoms call methods on this view to decide whether they are
/// entailed by the engine's current domain state. The engine's
/// internal `_DomainRep` implementations are private; tests and
/// future LCG components consume domains through this narrow public
/// surface.
abstract interface class DomainView {
  /// True iff [v] is still in the domain.
  bool contains(int v);

  /// Smallest integer currently in the domain. Undefined when
  /// [isEmpty]; callers must guard.
  int get minValue;

  /// Largest integer currently in the domain. Undefined when
  /// [isEmpty]; callers must guard.
  int get maxValue;

  /// True iff the domain contains a single value.
  bool get isSingleton;

  /// True iff the domain is empty (every value pruned).
  bool get isEmpty;
}

/// Sealed atom hierarchy. Four concrete subtypes — [AtomEq],
/// [AtomNe], [AtomLe], [AtomGe] — cover every prune shape the
/// existing engine produces.
sealed class Atom {
  const Atom();

  /// The variable this atom refers to.
  String get varName;

  /// The integer value carried by the atom (interpretation depends
  /// on the subtype: a specific value for [AtomEq] / [AtomNe], a
  /// bound for [AtomLe] / [AtomGe]).
  int get value;

  /// Logical negation: `(x = v).negate()` → `(x ≠ v)`, and so on.
  /// Used by first-UIP conflict analysis (M2).
  Atom negate();

  /// True iff the current domain of [varName] (passed as [dom])
  /// guarantees this atom holds. Used by the clause propagator to
  /// decide whether a literal is satisfied / falsified / unset under
  /// the current trail state.
  bool isEntailedBy(DomainView dom);

  /// Whether this atom is a *synthetic* bridge atom — one that is not a
  /// real, assertable domain literal but exists only to chain a
  /// propagator's explanation through first-UIP resolution (see
  /// [AtomInScc]). Synthetic atoms must never survive into a learned
  /// clause and must never be chosen as a UIP; the analyser resolves
  /// *through* them. Real domain atoms ([AtomEq] / [AtomNe] / [AtomLe]
  /// / [AtomGe]) return false.
  bool get isSynthetic => false;
}

/// `varName = value` — the variable is pinned to exactly [value].
final class AtomEq extends Atom {
  const AtomEq(this.varName, this.value);
  @override
  final String varName;
  @override
  final int value;

  @override
  Atom negate() => AtomNe(varName, value);

  @override
  bool isEntailedBy(DomainView dom) => dom.isSingleton && dom.contains(value);

  @override
  bool operator ==(Object other) =>
      other is AtomEq && other.varName == varName && other.value == value;

  @override
  int get hashCode => Object.hash('eq', varName, value);

  @override
  String toString() => '$varName = $value';
}

/// `varName ≠ value` — [value] has been pruned from the variable's
/// domain.
final class AtomNe extends Atom {
  const AtomNe(this.varName, this.value);
  @override
  final String varName;
  @override
  final int value;

  @override
  Atom negate() => AtomEq(varName, value);

  @override
  bool isEntailedBy(DomainView dom) => !dom.contains(value);

  @override
  bool operator ==(Object other) =>
      other is AtomNe && other.varName == varName && other.value == value;

  @override
  int get hashCode => Object.hash('ne', varName, value);

  @override
  String toString() => '$varName != $value';
}

/// `varName ≤ value` — the variable's current upper bound is at
/// most [value].
final class AtomLe extends Atom {
  const AtomLe(this.varName, this.value);
  @override
  final String varName;
  @override
  final int value;

  @override
  Atom negate() => AtomGe(varName, value + 1);

  @override
  bool isEntailedBy(DomainView dom) => !dom.isEmpty && dom.maxValue <= value;

  @override
  bool operator ==(Object other) =>
      other is AtomLe && other.varName == varName && other.value == value;

  @override
  int get hashCode => Object.hash('le', varName, value);

  @override
  String toString() => '$varName <= $value';
}

/// `varName ≥ value` — the variable's current lower bound is at
/// least [value].
final class AtomGe extends Atom {
  const AtomGe(this.varName, this.value);
  @override
  final String varName;
  @override
  final int value;

  @override
  Atom negate() => AtomLe(varName, value - 1);

  @override
  bool isEntailedBy(DomainView dom) => !dom.isEmpty && dom.minValue >= value;

  @override
  bool operator ==(Object other) =>
      other is AtomGe && other.varName == varName && other.value == value;

  @override
  int get hashCode => Object.hash('ge', varName, value);

  @override
  String toString() => '$varName >= $value';
}

/// Synthetic *intermediate* atom committed by `_AllDifferentPropagator`
/// to bridge a whole Hall set into a single resolvable literal during
/// first-UIP analysis (LCG M3-tighten, `LCG_PLAN.md` §3 task 1).
///
/// A tight Hall set `H` confines `|H|` variables to a value-set of
/// cardinality `|H|`, which is what forces every value outside that set
/// to be pruned from `H`'s variables. The coarse explanation lists, for
/// every prune, the absences across the whole Hall set — but those
/// absences include *sibling* at-conflict-level prunes, so resolving one
/// re-introduces another and the first-UIP walk never converges to a
/// single UIP (the diagnosed magic-square dead-end).
///
/// `AtomInScc` collapses the scope: the propagator commits **one**
/// `AtomInScc` per Hall set (its [value] is a per-solve unique id so two
/// committed atoms never collide on the trail), with the Hall set's
/// defining absences as its antecedents, and every per-prune reason for
/// values ruled out by that Hall set references the *single* atom.
/// Resolving the siblings then collapses them to one `AtomInScc`, which
/// the analyser resolves through to the absences.
///
/// **Synthetic, not assertable.** Unlike a linear bound atom
/// (`AtomGe` / `AtomLe`, which *is* a real domain literal and a
/// legitimate UIP), "this Hall set is tight" is not a domain literal —
/// its negation is meaningless as a clause literal. So [negate] and
/// [isEntailedBy] throw, and [isSynthetic] is true: the first-UIP loop
/// must resolve through it (never stop at it, never let it reach the
/// learned clause).
final class AtomInScc extends Atom {
  const AtomInScc(this.varName, this.value);

  /// A representative variable of the Hall set (for debugging only;
  /// identity is carried by [value]).
  @override
  final String varName;

  /// Per-solve unique id distinguishing this committed Hall-set atom
  /// from every other. Not a domain value.
  @override
  final int value;

  @override
  bool get isSynthetic => true;

  @override
  Atom negate() => throw StateError(
      'AtomInScc is synthetic and must never be negated into a learned '
      'clause; the analyser must resolve through it');

  @override
  bool isEntailedBy(DomainView dom) => throw StateError(
      'AtomInScc is synthetic and must never be evaluated as a clause '
      'literal');

  @override
  bool operator ==(Object other) =>
      other is AtomInScc && other.varName == varName && other.value == value;

  @override
  int get hashCode => Object.hash('inScc', varName, value);

  @override
  String toString() => 'inScc($varName, #$value)';
}

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

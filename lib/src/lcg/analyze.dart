/// First-UIP conflict analysis for Lazy Clause Generation (LCG).
///
/// Pure function over an implication trail and a conflict reason —
/// no engine state, no side effects. M2a's deliverable: a verified
/// analyser that produces correct learned clauses on hand-crafted
/// trails. M2b will wire it into the engine to drive backjumps and
/// post the learned clauses into the search.
///
/// References:
///   - Marques-Silva & Sakallah (1996). "GRASP: A search algorithm
///     for propositional satisfiability." DAC.
///   - Eén & Sörensson (2003). "An extensible SAT-solver." SAT.
///   - Feydy & Stuckey (2009). "Lazy clause generation
///     reengineered." CP.
library;

import 'atom.dart';
import 'explain.dart';

/// Result of a successful first-UIP analysis pass.
///
/// The learned clause is a *disjunction* over atoms: posting it
/// forces the search to avoid a configuration that just produced
/// a conflict. The [uipAtom] is the "asserting" literal — after
/// backjumping to [backjumpLevel] and applying the learned clause,
/// the negation of `uipAtom` becomes unit-implied.
class AnalysisResult {
  const AnalysisResult({
    required this.learnedClause,
    required this.backjumpLevel,
    required this.uipAtom,
  });

  /// Atoms forming the learned disjunction. Each atom is the
  /// *negation* of one that was entailed at conflict time: posting
  /// the clause `(a1 ∨ a2 ∨ … ∨ ak)` forbids re-entering that
  /// conjunction of negations.
  final List<Atom> learnedClause;

  /// Decision level to backjump to. The second-highest decision
  /// level among atoms in the working clause (i.e., excluding the
  /// UIP itself). Zero when the clause is a unit (only the UIP
  /// survives) — backjump to the root.
  final int backjumpLevel;

  /// The Unique Implication Point — the single atom in the
  /// working clause at the conflict's decision level. After
  /// backjumping and posting the learned clause, the negation of
  /// `uipAtom` becomes the asserting literal.
  final Atom uipAtom;

  @override
  String toString() => 'AnalysisResult(learnedClause: $learnedClause, '
      'backjumpLevel: $backjumpLevel, uipAtom: $uipAtom)';
}

/// Walks the implication [trail] backward from a propagation failure
/// described by [conflictReason], producing a learned clause via the
/// textbook first-UIP loop.
///
/// Returns null when:
///   - the trail is empty (no decisions made, no clause to learn);
///   - the conflict's antecedents are all at decision level 0 (the
///     problem is unsatisfiable from the root);
///   - the analyser can't isolate a single UIP, typically because
///     a non-clause propagator's prune feeds the conflict and its
///     M1 [UnknownReason] placeholder blocks resolution. The
///     learned clause is unsound in that case so we conservatively
///     refuse to emit one. M3's per-propagator explanation
///     companions will eliminate this fallback.
///
/// Soundness: every learned clause is a logical consequence of the
/// constraints plus the conflict antecedents. The analyser does not
/// invent atoms; every atom in the returned clause is the negation
/// of an atom currently entailed (i.e., present on [trail] or among
/// [conflictReason]'s antecedents).
///
/// When [trace] is non-null it receives a human-readable line for each
/// significant analysis step — the initial working clause, every
/// resolution, and the terminal UIP decision (or the bail reason).
/// This is diagnostic-only instrumentation (it never changes the
/// result) and exists to support the M3-tighten work, where the
/// convergence behaviour on CSP-shaped reasons has to be inspected
/// step by step. Leave it null on the hot path.
AnalysisResult? firstUipAnalyse(
    List<ImplicationEntry> trail, ImplicationReason conflictReason,
    {void Function(String message)? trace}) {
  if (trail.isEmpty) {
    trace?.call('bail: empty trail');
    return null;
  }

  final antecedents = conflictReason.antecedents();
  if (antecedents.isEmpty) {
    trace?.call('bail: conflict reason has no antecedents');
    return null;
  }

  // Map atom → latest trail-entry index for O(1) "is this on the
  // trail and at what level" lookups. Atoms can in principle appear
  // multiple times if the same prune is re-derived through different
  // paths; the latest occurrence wins.
  final indexOf = <Atom, int>{};
  for (var i = 0; i < trail.length; i++) {
    indexOf[trail[i].prunedAtom] = i;
  }

  // Conflict level = max decision level among the conflict's
  // antecedents that are on the trail.
  var conflictLevel = -1;
  for (final a in antecedents) {
    final idx = indexOf[a];
    if (idx == null) continue;
    final dl = trail[idx].decisionLevel;
    if (dl > conflictLevel) conflictLevel = dl;
  }
  if (conflictLevel <= 0) {
    trace?.call('bail: conflictLevel <= 0 (root-level unsat)');
    return null;
  }

  final workingClause = <Atom>{};
  var countAtLevel = 0;

  void addToClause(Atom a) {
    if (!workingClause.add(a)) return;
    final idx = indexOf[a];
    if (idx == null) return;
    if (trail[idx].decisionLevel == conflictLevel) countAtLevel++;
  }

  void removeFromClause(Atom a) {
    if (!workingClause.remove(a)) return;
    final idx = indexOf[a];
    if (idx == null) return;
    if (trail[idx].decisionLevel == conflictLevel) countAtLevel--;
  }

  for (final a in antecedents) {
    addToClause(a);
  }
  if (trace != null) {
    trace('conflictLevel=$conflictLevel, '
        'initial working clause=$workingClause (atLevel=$countAtLevel)');
  }

  // Walk backward, resolving away at-level atoms one at a time
  // until exactly one remains (the UIP).
  for (var i = trail.length - 1; i >= 0 && countAtLevel > 1; i--) {
    final entry = trail[i];
    if (entry.decisionLevel != conflictLevel) continue;
    if (!workingClause.contains(entry.prunedAtom)) continue;
    final newAntecedents = entry.reason.antecedents();
    if (newAntecedents.isEmpty) continue; // Decision or opaque.
    removeFromClause(entry.prunedAtom);
    for (final a in newAntecedents) {
      addToClause(a);
    }
    trace?.call('resolve ${entry.prunedAtom} against ${entry.reason} → '
        '$workingClause (atLevel=$countAtLevel)');
  }

  // Identify the UIP: the most-recent at-level atom in
  // [workingClause]. The textbook 1-UIP loop converges to a single
  // at-level atom *iff* every propagation reason carries at most one
  // at-level antecedent (true for boolean clauses). CSP propagators
  // like allDifferent and bounds-consistency linear naturally
  // produce reasons over the whole implicated scope, so multiple
  // at-level atoms may survive — that's a "multi-UIP" working
  // clause. We accept it: the learned clause is then non-asserting
  // (won't immediately unit-prop at the backjump level), but it's
  // still a sound logical implicate of the constraint store and
  // forbids the specific conflict combination, which constrains
  // future propagation. The engine handles `backjumpLevel == depth`
  // by re-propagating in place (see [_BacktrackEngine._searchOneLcg]).
  Atom? uip;
  var maxIdx = -1;
  var atLevelCount = 0;
  for (final a in workingClause) {
    final idx = indexOf[a];
    if (idx == null) continue;
    if (trail[idx].decisionLevel != conflictLevel) continue;
    atLevelCount++;
    if (idx > maxIdx) {
      maxIdx = idx;
      uip = a;
    }
  }
  if (uip == null || atLevelCount != 1) {
    trace?.call('bail: no single UIP (atLevelCount=$atLevelCount) — '
        'working clause=$workingClause');
    return null;
  }

  // Backjump level: max decision level among non-UIP atoms in
  // the working clause. Zero for a unit clause.
  var backjumpLevel = 0;
  for (final a in workingClause) {
    if (a == uip) continue;
    final idx = indexOf[a];
    if (idx == null) continue;
    final dl = trail[idx].decisionLevel;
    if (dl > backjumpLevel) backjumpLevel = dl;
  }

  trace?.call('learned: uip=$uip, backjumpLevel=$backjumpLevel, '
      'clause=${[for (final a in workingClause) a.negate()]}');
  return AnalysisResult(
    learnedClause: [for (final a in workingClause) a.negate()],
    backjumpLevel: backjumpLevel,
    uipAtom: uip,
  );
}

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
    this.minimisedLiterals = 0,
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

  /// Number of literals removed by recursive clause minimisation (0 when
  /// minimisation was disabled or removed nothing). Diagnostic only.
  final int minimisedLiterals;

  @override
  String toString() => 'AnalysisResult(learnedClause: $learnedClause, '
      'backjumpLevel: $backjumpLevel, uipAtom: $uipAtom, '
      'minimisedLiterals: $minimisedLiterals)';
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
/// When [minimize] is true the learned clause is passed through a
/// recursive (self-subsuming) minimisation pass (Sörensson & Eén 2009)
/// before it is returned: any non-UIP literal that is *implied* by the
/// conjunction of the remaining literals — via the same implication
/// trail — is dropped. The result is a shorter, logically stronger
/// implicate. Soundness relies on the implication trail being a DAG in
/// trail order (every reason's antecedents are strictly earlier on the
/// trail), so removing the redundant set simultaneously is equivalent
/// to removing them latest-first, each step provably preserving the
/// implicate. See [_minimiseClause]. Off by default — callers that want
/// the smaller clause (the iterative CDCL engine) opt in.
AnalysisResult? firstUipAnalyse(
    List<ImplicationEntry> trail, ImplicationReason conflictReason,
    {void Function(String message)? trace, bool minimize = false}) {
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
  // At-conflict-level atoms split into real (assertable domain literals,
  // legitimate UIP candidates) and synthetic ([AtomInScc] bridges that
  // must be resolved through — never a UIP, never in a learned clause).
  var realAtLevel = 0;
  var synthAtLevel = 0;

  void addToClause(Atom a) {
    if (!workingClause.add(a)) return;
    final idx = indexOf[a];
    if (idx == null) return;
    if (trail[idx].decisionLevel != conflictLevel) return;
    if (a.isSynthetic) {
      synthAtLevel++;
    } else {
      realAtLevel++;
    }
  }

  void removeFromClause(Atom a) {
    if (!workingClause.remove(a)) return;
    final idx = indexOf[a];
    if (idx == null) return;
    if (trail[idx].decisionLevel != conflictLevel) return;
    if (a.isSynthetic) {
      synthAtLevel--;
    } else {
      realAtLevel--;
    }
  }

  for (final a in antecedents) {
    addToClause(a);
  }
  if (trace != null) {
    trace('conflictLevel=$conflictLevel, initial working clause='
        '$workingClause (atLevel=$realAtLevel, synth=$synthAtLevel)');
  }

  // Walk backward, resolving at-conflict-level atoms one at a time.
  // The textbook 1-UIP loop stops when exactly one at-level atom
  // remains. With intermediate synthetic atoms ([AtomInScc]) the stop
  // condition tightens: we keep resolving while *either* more than one
  // real at-level atom remains *or* any synthetic at-level atom remains
  // (synthetics are bridges — they must be resolved through to their
  // real antecedents, never left as the UIP). A whole Hall set's
  // sibling prunes collapse onto a single shared [AtomInScc], which is
  // then resolved into the Hall set's defining absences — so the
  // at-level count falls instead of multiplying.
  for (var i = trail.length - 1;
      i >= 0 && (realAtLevel > 1 || synthAtLevel > 0);
      i--) {
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
        '$workingClause (atLevel=$realAtLevel, synth=$synthAtLevel)');
  }

  // Identify the UIP: the most-recent *real* at-level atom in
  // [workingClause]. Bail if any synthetic atom survived at the conflict
  // level (the walk could not resolve it through to real antecedents) or
  // if the real at-level count is not exactly one — a learned clause
  // built then would either contain a non-assertable synthetic literal
  // or be non-asserting, so we conservatively decline to emit one and
  // the engine falls back to chronological backtrack.
  Atom? uip;
  var maxIdx = -1;
  var realAtLevelFinal = 0;
  var syntheticRemaining = 0;
  for (final a in workingClause) {
    if (a.isSynthetic) {
      syntheticRemaining++;
      continue;
    }
    final idx = indexOf[a];
    if (idx == null) continue;
    if (trail[idx].decisionLevel != conflictLevel) continue;
    realAtLevelFinal++;
    if (idx > maxIdx) {
      maxIdx = idx;
      uip = a;
    }
  }
  if (uip == null || realAtLevelFinal != 1 || syntheticRemaining > 0) {
    trace?.call('bail: no single UIP (atLevel=$realAtLevelFinal, '
        'synth=$syntheticRemaining) — working clause=$workingClause');
    return null;
  }

  // Recursive (self-subsuming) clause minimisation. Drops non-UIP atoms
  // that are entailed by the rest of the clause; the UIP is preserved so
  // the clause stays asserting. Recomputes nothing else — it only
  // shrinks the set, so the UIP is still the unique at-conflict-level
  // real atom.
  var removed = 0;
  if (minimize && workingClause.length > 1) {
    removed = _minimiseClause(workingClause, uip, trail, indexOf);
    if (trace != null && removed > 0) {
      trace('minimised: removed $removed literal(s) → '
          'clause=${[for (final a in workingClause) a.negate()]}');
    }
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
    minimisedLiterals: removed,
  );
}

/// Recursive (self-subsuming) learned-clause minimisation
/// (Sörensson & Eén 2009; Van Gelder 2009). Removes from [clause] every
/// non-[uip] atom that is *redundant* — implied by the conjunction of
/// the other clause atoms through the implication [trail] — and returns
/// the number of atoms removed.
///
/// `clause` holds the *entailed* atoms (the learned clause is the
/// disjunction of their negations). An atom `a` is implied by a set `S`
/// of entailed atoms iff `a ∈ S`, or `a` sits at decision level 0 (a
/// root fact), or `a` has a non-decision reason whose every antecedent
/// is (recursively) implied by `S`. Atom `c` is *removable* when its
/// reason's antecedents are each implied by the rest of the clause — so
/// `⋀(clause) → c` and the smaller disjunction is still a sound
/// implicate.
///
/// **Soundness.** The implication trail is a DAG in trail order: every
/// reason's antecedents were already entailed when the prune was
/// recorded, so each has a strictly smaller trail index. Hence the
/// `implied` recursion can never reach `c` itself (it is the latest in
/// its own cone), and removing the whole redundant set at once is
/// equivalent to removing its members latest-trail-index-first. Each
/// such single removal preserves the implicate (the removed atom's
/// support lies strictly earlier on the trail, untouched by later
/// removals), so the simultaneous removal does too. The UIP is never
/// removed, so the clause stays asserting; the per-call memo and the
/// in-progress guard make the walk linear and cycle-proof even if some
/// reason were to violate the DAG assumption.
int _minimiseClause(Set<Atom> clause, Atom uip, List<ImplicationEntry> trail,
    Map<Atom, int> indexOf) {
  // memo: atom → "implied by the (unmutated) clause". Stable for the
  // whole pass because removal is collected then applied by removeWhere,
  // so `clause.contains` reflects the original membership throughout.
  final memo = <Atom, bool>{};
  final inProgress = <Atom>{};

  bool implied(Atom a) {
    if (clause.contains(a)) return true;
    final cached = memo[a];
    if (cached != null) return cached;
    final idx = indexOf[a];
    if (idx == null) return false; // not on trail, not in clause → a premise
    final entry = trail[idx];
    if (entry.decisionLevel == 0) return memo[a] = true; // root fact
    final ants = entry.reason.antecedents();
    if (ants.isEmpty) return memo[a] = false; // decision / opaque → premise
    if (!inProgress.add(a)) return false; // defensive cycle guard
    var all = true;
    for (final b in ants) {
      if (!implied(b)) {
        all = false;
        break;
      }
    }
    inProgress.remove(a);
    return memo[a] = all;
  }

  bool removable(Atom c) {
    final idx = indexOf[c];
    if (idx == null) return false;
    final entry = trail[idx];
    if (entry.decisionLevel == 0) return true; // root fact, always entailed
    final ants = entry.reason.antecedents();
    if (ants.isEmpty) return false; // decision / opaque premise — keep it
    for (final b in ants) {
      if (!implied(b)) return false;
    }
    return true;
  }

  final before = clause.length;
  clause.removeWhere((a) => a != uip && !a.isSynthetic && removable(a));
  return before - clause.length;
}

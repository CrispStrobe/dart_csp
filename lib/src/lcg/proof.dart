// Proof / nogood logging for the Lazy Clause Generation engine.
//
// The LCG engine already surfaces every conflict clause it derives through
// the `onLearnedClause` hook on `solveWithLcg`. This module collects that
// stream into a structured [ProofLog]: the ordered sequence of nogoods the
// search learned, a stable atom↔integer legend, and DRAT-style / readable
// emitters.
//
// Scope, stated honestly. This is a *nogood-derivation log* — the clauses
// CDCL added while refuting (or pruning) the search. It is not, on its own, a
// standalone DRAT proof checkable by an external tool such as `drat-trim`,
// because the *original* clausal encoding is generated lazily by the
// propagators and is not part of this log. What it gives you: an inspectable
// record of the learned reasoning (the core of an UNSAT refutation), with a
// stable literal numbering, ready to become a full DRAT proof once paired
// with the clausal encoding. It is distinct from the MUS tooling (which
// returns a minimal core of *original* constraints) and from the propagation
// trace (per-decision events): this is the *learned-clause* derivation.

import '../problem.dart';
import '../types.dart';
import 'atom.dart';

/// An ordered log of the nogoods (learned clauses) an LCG solve derived,
/// with a stable literal numbering for DRAT-style output.
///
/// Wire it into a solve with `Problem.solveWithProof`, or pass [record]
/// directly as the `onLearnedClause` callback of `solveWithLcg`.
class ProofLog {
  final List<List<Atom>> _clauses = [];
  final Map<Atom, int> _ids = {};
  int _counter = 0;
  bool _provedUnsat = false;

  /// Records one learned clause. Suitable as the `onLearnedClause` callback.
  /// An empty clause marks a top-level refutation.
  void record(List<Atom> clause) {
    final copy = List<Atom>.of(clause);
    _clauses.add(copy);
    for (final a in copy) {
      literal(a); // assign ids eagerly so the legend is complete
    }
    if (copy.isEmpty) _provedUnsat = true;
  }

  /// Marks the proof as an UNSAT refutation even if the engine returned
  /// exhaustion without emitting an explicit empty clause (its final
  /// top-level conflict may short-circuit before the callback fires).
  void markUnsat() => _provedUnsat = true;

  /// The learned clauses, in derivation order.
  List<List<Atom>> get clauses => List.unmodifiable(_clauses);

  /// Number of learned clauses recorded.
  int get length => _clauses.length;

  /// Whether this log constitutes a refutation — an empty clause was
  /// recorded, or [markUnsat] was called after an unsatisfiable solve.
  bool get provedUnsat => _provedUnsat;

  /// The signed DIMACS-style integer for [atom]. An atom and its negation
  /// share a magnitude and differ in sign; ids are assigned in first-seen
  /// order. Stable within one [ProofLog].
  int literal(Atom atom) {
    final existing = _ids[atom];
    if (existing != null) return existing;
    final neg = atom.negate();
    final negId = _ids[neg];
    if (negId != null) {
      final id = -negId;
      _ids[atom] = id;
      return id;
    }
    final id = ++_counter;
    _ids[atom] = id;
    _ids[neg] = -id;
    return id;
  }

  /// A legend mapping each positive literal id to a human description of the
  /// atom it stands for (e.g. `3: x = 5`). The negative id is that atom's
  /// negation.
  Map<int, String> legend() {
    final out = <int, String>{};
    _ids.forEach((atom, id) {
      if (id > 0) out[id] = atom.toString();
    });
    return Map.fromEntries(
        out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// Emits the log in DRAT clause syntax: one clause per line as
  /// space-separated signed literals terminated by `0`, an empty clause as a
  /// bare `0`. The legend is written as leading `c` comment lines so the file
  /// is self-describing.
  ///
  /// This is addition-only (a DRUP-style trace); clause *deletions* from the
  /// engine's forget policy are not logged. See the class doc for what this
  /// proof does and does not certify.
  String toDrat() {
    final buf = StringBuffer();
    buf.writeln('c dart_csp LCG nogood log (DRUP-style, addition-only)');
    buf.writeln('c literal legend (positive id : atom; negate for the '
        'complement):');
    legend().forEach((id, desc) => buf.writeln('c   $id : $desc'));
    buf.writeln('c ${_clauses.length} learned clause(s)'
        '${_provedUnsat ? ', refutation' : ''}');
    for (final clause in _clauses) {
      for (final a in clause) {
        buf.write('${literal(a)} ');
      }
      buf.writeln('0');
    }
    return buf.toString();
  }

  /// A readable rendering: each learned clause as a disjunction of atoms.
  String toReadable() {
    final buf = StringBuffer();
    buf.writeln('${_clauses.length} learned nogood(s)'
        '${_provedUnsat ? ' — UNSAT refutation' : ''}:');
    for (var i = 0; i < _clauses.length; i++) {
      final clause = _clauses[i];
      final body = clause.isEmpty
          ? '⊥ (empty clause)'
          : clause.map((a) => '($a)').join(' ∨ ');
      buf.writeln('  ${i + 1}. $body');
    }
    return buf.toString();
  }

  @override
  String toString() =>
      'ProofLog(${_clauses.length} clauses, provedUnsat: $_provedUnsat)';
}

/// Runs an LCG solve while capturing its nogood-derivation [ProofLog].
extension ProofLogging on Problem {
  /// Solves with the LCG engine and returns both the result (a
  /// `Map<String, dynamic>` solution or `'FAILURE'`) and the [ProofLog] of
  /// every nogood the search learned. For an unsatisfiable instance the
  /// proof's [ProofLog.provedUnsat] is set (unless the solve was cancelled).
  ///
  /// The parameters mirror [LcgSearch.solveWithLcg]; the proof collector is
  /// wired into its `onLearnedClause` hook, so there is no extra cost beyond
  /// storing the learned clauses.
  Future<({dynamic result, ProofLog proof})> solveWithProof({
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
    CancellationToken? cancelToken,
    bool useVsids = false,
    bool useDomWdeg = false,
    bool useIterativeCdcl = true,
    bool useRestarts = false,
    int restartScale = 100,
    int? seed,
    int? learnedClauseCap,
  }) async {
    final proof = ProofLog();
    final result = await solveWithLcg(
      consistency: consistency,
      cancelToken: cancelToken,
      useVsids: useVsids,
      useDomWdeg: useDomWdeg,
      useIterativeCdcl: useIterativeCdcl,
      useRestarts: useRestarts,
      restartScale: restartScale,
      seed: seed,
      learnedClauseCap: learnedClauseCap,
      onLearnedClause: proof.record,
    );
    // 'FAILURE' from a complete solve is a genuine refutation; a cancelled
    // solve also returns 'FAILURE' but proves nothing.
    if (result is! Map && !(cancelToken?.isCancelled ?? false)) {
      proof.markUnsat();
    }
    return (result: result, proof: proof);
  }
}

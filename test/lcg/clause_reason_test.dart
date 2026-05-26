import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('_ClausePropagator emits ClauseReason on unit-prop', () {
    test(
        'two-literal clause forces the other literal with the right antecedents',
        () async {
      // A is pinned to 1 (singleton), B ∈ {0, 1}. Clause (¬A ∨ B):
      // literal (A, false) is falsified (A == 1, not 0), so the
      // clause becomes unit on (B, true). The propagator forces
      // B = 1 with antecedents [AtomEq('A', 1)] — the falsifying
      // value of the negative literal on A.
      final p = Problem()
        ..addVariable('A', [1])
        ..addVariable('B', [0, 1])
        ..addClause(positive: ['B'], negative: ['A']);
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());

      final trail = CSP.lastImplicationTrail!;
      final clauseEntries =
          trail.where((e) => e.reason is ClauseReason).toList();
      expect(clauseEntries, isNotEmpty,
          reason: 'clause unit-prop should emit ClauseReason');
      final bEntry =
          clauseEntries.firstWhere((e) => e.prunedAtom.varName == 'B');
      final reason = bEntry.reason as ClauseReason;
      expect(reason.antecedentAtoms, contains(const AtomEq('A', 1)));
    });

    test(
        'three-literal clause with two falsified literals lists both as antecedents',
        () async {
      // A = 0 (singleton), B = 0 (singleton), C ∈ {0, 1}.
      // Clause (A ∨ B ∨ C): first two literals falsified, C forced.
      // Antecedents: [AtomEq('A', 0), AtomEq('B', 0)].
      final p = Problem()
        ..addVariable('A', [0])
        ..addVariable('B', [0])
        ..addVariable('C', [0, 1])
        ..addClause(positive: ['A', 'B', 'C']);
      final sol = await p.solveWithLcg();
      expect(sol, isA<Map<String, dynamic>>());

      final trail = CSP.lastImplicationTrail!;
      final cEntry = trail.firstWhere(
        (e) => e.prunedAtom.varName == 'C' && e.reason is ClauseReason,
        orElse: () => throw StateError('no ClauseReason entry for C'),
      );
      final reason = cEntry.reason as ClauseReason;
      expect(reason.antecedentAtoms,
          containsAll([const AtomEq('A', 0), const AtomEq('B', 0)]));
    });

    test('ClauseReason equality holds when antecedent atom lists match', () {
      const a = ClauseReason([AtomEq('X', 1), AtomEq('Y', 0)]);
      expect(a.antecedents(), [const AtomEq('X', 1), const AtomEq('Y', 0)]);
      expect(a.toString(), contains('X = 1'));
      expect(a.toString(), contains('Y = 0'));
    });
  });
}

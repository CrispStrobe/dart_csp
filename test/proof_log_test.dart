import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Pigeonhole as a Boolean CNF: `pigeons` pigeons, `holes` holes, one
/// Boolean per (pigeon, hole). Each pigeon occupies at least one hole; no
/// two pigeons share a hole. Infeasible when pigeons > holes, and — unlike a
/// GAC all-different — the weak clausal propagation forces the engine to
/// search and *learn*, so a non-empty nogood proof is produced.
Problem _pigeonholeCnf({required int pigeons, required int holes}) {
  final p = Problem();
  for (var pg = 0; pg < pigeons; pg++) {
    for (var h = 0; h < holes; h++) {
      p.addVariable('p${pg}_h$h', [0, 1]);
    }
    p.addClause(positive: [for (var h = 0; h < holes; h++) 'p${pg}_h$h']);
  }
  for (var h = 0; h < holes; h++) {
    for (var i = 0; i < pigeons; i++) {
      for (var j = i + 1; j < pigeons; j++) {
        p.addClause(negative: ['p${i}_h$h', 'p${j}_h$h']);
      }
    }
  }
  return p;
}

void main() {
  group('ProofLog literal numbering', () {
    test('an atom and its negation share magnitude, differ in sign', () {
      final log = ProofLog();
      const eq = AtomEq('x', 3);
      final ne = eq.negate(); // AtomNe('x', 3)
      final a = log.literal(eq);
      final b = log.literal(ne);
      expect(a, isPositive);
      expect(b, -a);
    });

    test('distinct atoms get distinct magnitudes; ids are stable', () {
      final log = ProofLog();
      final a = log.literal(const AtomEq('x', 1));
      final b = log.literal(const AtomEq('y', 1));
      expect(a.abs(), isNot(equals(b.abs())));
      expect(log.literal(const AtomEq('x', 1)), a, reason: 'stable on repeat');
    });

    test('Le/Ge negation pair maps consistently', () {
      final log = ProofLog();
      const le = AtomLe('x', 5);
      final ge = le.negate(); // AtomGe('x', 6)
      expect(log.literal(ge), -log.literal(le));
    });
  });

  group('ProofLog recording', () {
    test('record stores clauses and populates the legend', () {
      final log = ProofLog()
        ..record([const AtomNe('x', 1), const AtomNe('y', 2)])
        ..record([const AtomEq('z', 0)]);
      expect(log.length, 2);
      expect(log.clauses, hasLength(2));
      final legend = log.legend();
      final descs = legend.values.toSet();
      expect(descs, contains('x != 1'));
      expect(descs, contains('z = 0'));
    });

    test('an empty clause marks the log as a refutation', () {
      final log = ProofLog();
      expect(log.provedUnsat, isFalse);
      log.record(<Atom>[]);
      expect(log.provedUnsat, isTrue);
    });

    test('toDrat emits legend comments and 0-terminated clauses', () {
      final log = ProofLog()
        ..record([const AtomNe('x', 1), const AtomEq('y', 2)]);
      final drat = log.toDrat();
      expect(drat, contains('c dart_csp LCG nogood log'));
      expect(drat, contains('c   1 : x != 1'));
      // The one clause line ends with 0.
      final clauseLines = drat
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('c'))
          .toList();
      expect(clauseLines, hasLength(1));
      expect(clauseLines.single.trimRight(), endsWith('0'));
    });

    test('toReadable renders disjunctions and the empty clause', () {
      final log = ProofLog()
        ..record([const AtomNe('x', 1), const AtomNe('y', 2)])
        ..record(<Atom>[]);
      final text = log.toReadable();
      expect(text, contains('(x != 1) ∨ (y != 2)'));
      expect(text, contains('⊥ (empty clause)'));
      expect(text, contains('UNSAT refutation'));
    });
  });

  group('solveWithProof end-to-end', () {
    test('root-propagation UNSAT is a refutation with no learned clauses',
        () async {
      // 3 pigeons, 2 holes via GAC all-different: the propagator detects
      // infeasibility at the root, so there is no search and nothing to
      // learn — an empty (but valid) refutation.
      final p = Problem()
        ..addVariables(['p0', 'p1', 'p2'], [0, 1])
        ..addAllDifferent(['p0', 'p1', 'p2']);
      final r = await p.solveWithProof();
      expect(r.result, 'FAILURE');
      expect(r.proof.provedUnsat, isTrue);
    });

    test('CNF pigeonhole UNSAT: proves UNSAT and logs nogoods', () async {
      // 4 pigeons, 3 holes as CNF: weak clausal propagation forces search,
      // so the refutation actually contains learned nogoods.
      final r = await _pigeonholeCnf(pigeons: 4, holes: 3).solveWithProof();
      expect(r.result, 'FAILURE');
      expect(r.proof.provedUnsat, isTrue);
      expect(r.proof.length, greaterThan(0),
          reason: 'a searched refutation learns at least one nogood');
      expect(r.proof.toDrat(), contains('refutation'));
    });

    test('satisfiable problem: solves and does not claim a refutation',
        () async {
      final p = Problem()
        ..addVariables(['a', 'b', 'c'], [1, 2, 3])
        ..addAllDifferent(['a', 'b', 'c']);
      final r = await p.solveWithProof();
      expect(r.result, isA<Map<String, dynamic>>());
      expect(r.proof.provedUnsat, isFalse);
    });

    test('every learned clause has a legend entry', () async {
      final r = await _pigeonholeCnf(pigeons: 4, holes: 3).solveWithProof();
      expect(r.proof.provedUnsat, isTrue);
      final legendIds = r.proof.legend().keys.map((k) => k.abs()).toSet();
      for (final clause in r.proof.clauses) {
        for (final atom in clause) {
          expect(legendIds, contains(r.proof.literal(atom).abs()));
        }
      }
    });
  });
}

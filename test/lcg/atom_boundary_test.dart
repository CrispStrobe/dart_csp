import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

class _PointDomain implements DomainView {
  const _PointDomain(this.value);

  final int value;

  @override
  bool contains(int other) => value == other;
  @override
  bool get isSingleton => true;
  @override
  bool get isEmpty => false;
  @override
  int get minValue => value;
  @override
  int get maxValue => value;
}

int _powerOfTwo(int power) {
  var result = 1;
  for (var i = 0; i < power; i++) {
    result *= 2;
  }
  return result;
}

void main() {
  final boundary = _powerOfTwo(53);
  final values = [
    -boundary - 4,
    -boundary - 2,
    -boundary,
    -boundary + 1,
    -1,
    0,
    1,
    boundary - 1,
    boundary,
    boundary + 2,
    boundary + 4,
    if (identical(1, 1.0)) ...[
      -boundary * boundary,
      boundary * boundary,
    ],
  ];

  test('bound negation remains complementary and involutive across JS gaps',
      () {
    for (final value in values) {
      for (final atom in [AtomLe('x', value), AtomGe('x', value)]) {
        final opposite = atom.negate();
        expect(opposite.negate(), atom, reason: 'Double negation of $atom');
        final proof = ProofLog();
        expect(proof.literal(opposite), -proof.literal(atom),
            reason: 'Proof literals for $atom and $opposite must be opposite');
        for (final point in [...values, opposite.value]) {
          expect(atom.isEntailedBy(_PointDomain(point)),
              isNot(opposite.isEntailedBy(_PointDomain(point))),
              reason: '$atom and $opposite at x=$point');
        }
      }
    }
  });

  test('unit boundary clauses preserve supported endpoints in every solver',
      () async {
    for (final caseData in [
      (
        domain: [boundary, boundary + 2],
        atom: AtomLe('x', boundary),
        expected: boundary
      ),
      (
        domain: [-boundary - 2, -boundary],
        atom: AtomGe('x', -boundary),
        expected: -boundary
      ),
    ]) {
      Problem build() => Problem()
        ..addVariable('x', caseData.domain)
        ..addAtomClause([caseData.atom]);
      expect(await build().getSolution(), {'x': caseData.expected});
      expect(await build().getAllSolutions(), [
        {'x': caseData.expected}
      ]);
      for (final iterative in [false, true]) {
        expect(await build().solveWithLcg(useIterativeCdcl: iterative),
            {'x': caseData.expected});
      }
      final session = build().compile().createSession();
      for (var repeat = 0; repeat < 3; repeat++) {
        final result = await session.solve();
        expect(result.status, CspSolveStatus.satisfied);
        expect(result.solution, {'x': caseData.expected});
      }
      session.close();
    }
  });

  test('guarded boundary conflict learns a sound clause in both LCG engines',
      () async {
    for (final iterative in [false, true]) {
      final learned = <List<Atom>>[];
      final problem = Problem()
        ..addVariable('gate', [1, 0])
        ..addVariable('x', [boundary, boundary + 2])
        ..addAtomClause([const AtomNe('gate', 1), AtomLe('x', boundary)])
        ..addAtomClause([const AtomNe('gate', 1), AtomGe('x', boundary + 2)]);
      final result = await problem.solveWithLcg(
          useIterativeCdcl: iterative,
          onLearnedClause: (clause) => learned.add([...clause]));
      expect(result, isA<Map<String, dynamic>>());
      expect((result as Map<String, dynamic>)['gate'], 0);
      expect(learned, isNotEmpty);
      // The two independently enumerated feasible points have gate=0.
      for (final clause in learned) {
        for (final x in [boundary, boundary + 2]) {
          expect(
              clause.any((atom) =>
                  atom.isEntailedBy(_PointDomain(atom.varName == 'x' ? x : 0))),
              isTrue,
              reason: 'Learned $clause must retain gate=0, x=$x');
        }
      }
      problem.addAtomClause([const AtomEq('gate', 1)]);
      expect(
          await problem.solveWithLcg(useIterativeCdcl: iterative), 'FAILURE');
    }
  });

  test(
      'native endpoint complements fail explicitly without breaking tautologies',
      () async {
    if (identical(1, 1.0)) return;
    final half = _powerOfTwo(62);
    final largest = half + (half - 1);
    final smallest = -largest - 1;
    expect(() => AtomLe('x', largest).negate(), throwsUnsupportedError);
    expect(() => AtomGe('x', smallest).negate(), throwsUnsupportedError);
    expect(
        AtomLe('x', largest - 1).negate().negate(), AtomLe('x', largest - 1));
    expect(
        AtomGe('x', smallest + 1).negate().negate(), AtomGe('x', smallest + 1));
    for (final iterative in [false, true]) {
      final problem = Problem()
        ..addVariable('x', [smallest, largest])
        ..addAtomClause([AtomLe('x', largest)])
        ..addAtomClause([AtomGe('x', smallest)]);
      expect(await problem.solveWithLcg(useIterativeCdcl: iterative),
          {'x': smallest});
    }
  });
}

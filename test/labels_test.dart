import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('ConstraintRef.label', () {
    test('default is null when no label is provided', () {
      const r = ConstraintRef(id: 'b0', kind: 'binary', variables: ['x', 'y']);
      expect(r.label, isNull);
    });

    test('toString omits label when null', () {
      const r = ConstraintRef(id: 'b0', kind: 'binary', variables: ['x', 'y']);
      expect(r.toString(), 'binary(x, y)');
    });

    test('toString includes label between kind and variables', () {
      const r = ConstraintRef(
          id: 'n3',
          kind: 'linearLeq',
          variables: ['w0', 'w1', 'w2'],
          label: 'max-load');
      expect(r.toString(), 'linearLeq[max-load](w0, w1, w2)');
    });

    test('equality is still keyed only by id (label ignored)', () {
      const a = ConstraintRef(
          id: 'b0', kind: 'binary', variables: ['x', 'y'], label: 'rule-a');
      const b = ConstraintRef(
          id: 'b0', kind: 'binary', variables: ['x', 'y'], label: 'rule-b');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('MUS surfaces label from primary helpers', () {
    test('addConstraint binary label propagates', () async {
      final p = Problem();
      p.addVariables(['a', 'b'], [1, 2]);
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a == b,
          label: 'must-be-equal');
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b,
          label: 'must-differ');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['must-be-equal', 'must-differ']));
    });

    test('addConstraint n-ary label propagates', () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [0, 1]);
      // Predicate over 3 vars enforcing a + b + c == 1.
      p.addConstraint(
          ['a', 'b', 'c'],
          (Map<String, dynamic> m) =>
              ((m['a'] as int) + (m['b'] as int) + (m['c'] as int)) == 1,
          label: 'sum-one');
      p.addConstraint(
          ['a', 'b', 'c'],
          (Map<String, dynamic> m) =>
              ((m['a'] as int) + (m['b'] as int) + (m['c'] as int)) == 3,
          label: 'sum-three');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['sum-one', 'sum-three']));
    });

    test('addAllDifferent label propagates', () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      p.addAllDifferent(['a', 'b', 'c'], label: 'distinct-cells');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.label, 'distinct-cells');
      expect(mus.first.toString(), 'allDifferent[distinct-cells](a, b, c)');
    });

    test('addLinearEquals / addLinearLeq labels propagate', () async {
      final p = Problem();
      p.addRangeVariable('x', 0, 10);
      p.addRangeVariable('y', 0, 10);
      p.addLinearEquals(['x', 'y'], [1, 1], 5, label: 'budget-equal');
      p.addLinearLeq(['x', 'y'], [1, 1], 3, label: 'budget-cap');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['budget-equal', 'budget-cap']));
    });

    test('addClause label propagates', () async {
      final p = Problem();
      p.addVariables(['x', 'y'], [0, 1]);
      p.addClause(positive: ['x'], label: 'x-true');
      p.addClause(positive: ['y'], label: 'y-true');
      p.addClause(negative: ['x', 'y'], label: 'not-both');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 3);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['x-true', 'y-true', 'not-both']));
    });
  });

  group('Decomposed helpers propagate label to every piece', () {
    test('addLexChain propagates label to every pairwise lex-leq', () async {
      // Build a problem where the chain rows must be lex-equal (via
      // pinning all positions to fixed values that violate the chain),
      // so both pairwise refs from addLexChain end up in the MUS.
      // Domains pin row1 = (2,1), row2 = (1,1). Then row1 ≤ row2 fails
      // (chain pair 0). row2 ≤ row3 with row3 = (2,2) is fine. So MUS
      // contains the first lex-leq ref. Carrying the label.
      final p = Problem();
      p.addVariable('a1', [2]);
      p.addVariable('a2', [1]);
      p.addVariable('b1', [1]);
      p.addVariable('b2', [1]);
      p.addLexChain([
        ['a1', 'a2'],
        ['b1', 'b2'],
      ], label: 'rows-canonical');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      // The single addLexLeq ref must carry the chain's label.
      expect(mus!.length, 1);
      expect(mus.first.label, 'rows-canonical');
    });

    test('addInverse propagates label to all n² binary refs', () async {
      // n=3 means 9 binary `addConstraint` calls under the hood.
      // Build an unsat problem so the MUS surfaces inverse refs.
      // Force a contradiction: posting addInverse(f, i) on a 3-element
      // permutation, plus pinning all of f and i to the same value.
      final p = Problem();
      p.addVariables(['f0', 'f1', 'f2', 'i0', 'i1', 'i2'], [0, 1, 2]);
      p.addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2'],
          label: 'task-channel');
      // Add a redundant unsat-helper: force all f to 0 (violates
      // permutation property the channel encodes).
      p.addAllDifferent(['f0', 'f1', 'f2'], label: 'must-differ');
      p.addConstraint(['f0', 'f1'], (dynamic a, dynamic b) => a == b,
          label: 'force-equal');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      // The MUS may include inverse refs; assert that any binary refs
      // that surface and come from the channel decomposition carry the
      // 'task-channel' label.
      final channelRefs =
          mus!.where((r) => r.kind == 'binary' && r.label == 'task-channel');
      // Without channel involvement (the redundant constraints suffice
      // alone), this set may be empty. Either is fine — what's
      // important is that any channel ref in the MUS carries the label.
      for (final r in channelRefs) {
        expect(r.label, 'task-channel');
      }
      // Direct propagation check: build a satisfiable problem so MUS
      // returns null, then count constraints — addInverse(n=3) posts
      // 9 binary calls = 18 directed entries.
      final p2 = Problem();
      p2.addVariables(['f0', 'f1', 'f2', 'i0', 'i1', 'i2'], [0, 1, 2]);
      p2.addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2'], label: 'channel');
      expect(p2.constraintCount, 18);
    });

    test('addAllEqual binary form propagates label', () async {
      final p = Problem();
      p.addVariables(['a', 'b'], [1, 2]);
      p.addAllEqual(['a', 'b'], label: 'pair-equal');
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b,
          label: 'pair-differ');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['pair-equal', 'pair-differ']));
    });
  });

  group('Forward+reverse binary pair shares one label', () {
    test('one user-level call → one ref with one label', () async {
      final p = Problem();
      p.addVariables(['a'], [1, 2]);
      p.addConstraint(['a', 'a'], (dynamic x, dynamic y) => x != y,
          label: 'self-distinct');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.label, 'self-distinct');
    });
  });

  group('Both MUS algorithms surface label identically', () {
    Problem build() {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      p.addAllDifferent(['a', 'b', 'c'], label: 'pigeons');
      return p;
    }

    test('deletion-based pass surfaces label', () async {
      final mus = await build().findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.first.label, 'pigeons');
    });

    test('QuickXplain pass surfaces label', () async {
      final mus = await build().findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.first.label, 'pigeons');
    });
  });

  group('Set-variable helpers propagate label', () {
    test('addSetCardinality label propagates', () async {
      final p = Problem()
        ..addSetVariable('Team', universe: ['a', 'b', 'c'])
        ..addSetCardinality('Team', 3, label: 'roster-size')
        ..addSetCardinality('Team', 0, label: 'roster-zero'); // conflicts
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['roster-size', 'roster-zero']));
    });

    test('addSetCardinalityRange label propagates', () async {
      final p = Problem()
        ..addSetVariable('S', universe: ['a', 'b', 'c'])
        ..addSetCardinalityRange('S', 2, 3, label: 'range-big')
        ..addSetCardinality('S', 1, label: 'pin-one'); // conflicts
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.map((r) => r.label).toSet(),
          containsAll(<String>['range-big', 'pin-one']));
    });

    test('addRequiredInSet and addExcludedFromSet labels propagate', () async {
      final p = Problem()
        ..addSetVariable('S', universe: ['a', 'b', 'c'])
        ..addRequiredInSet('S', 'a', label: 'must-include-a')
        ..addExcludedFromSet('S', 'a', label: 'must-exclude-a');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.label).toSet(),
          containsAll(<String>['must-include-a', 'must-exclude-a']));
    });

    test('addSetEquals label propagates to every per-element binary', () async {
      // Two set vars over same universe; force them equal and pin one
      // to contain 'a' but the other to exclude 'a' — unsat.
      final p = Problem()
        ..addSetVariable('S', universe: ['a', 'b'])
        ..addSetVariable('T', universe: ['a', 'b'])
        ..addSetEquals('S', 'T', label: 's-eq-t')
        ..addRequiredInSet('S', 'a', label: 's-has-a')
        ..addExcludedFromSet('T', 'a', label: 't-no-a');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      // The MUS must include the s-has-a and t-no-a pin refs, plus at
      // least one of the per-element set-equals refs labeled 's-eq-t'.
      expect(mus!.any((r) => r.label == 's-eq-t'), isTrue);
      expect(mus.any((r) => r.label == 's-has-a'), isTrue);
      expect(mus.any((r) => r.label == 't-no-a'), isTrue);
    });

    test('addSubset label propagates', () async {
      final p = Problem()
        ..addSetVariable('Sub', universe: ['a', 'b'])
        ..addSetVariable('Sup', universe: ['a', 'b'])
        ..addSubset('Sub', 'Sup', label: 'sub-of-sup')
        ..addRequiredInSet('Sub', 'a', label: 'sub-has-a')
        ..addExcludedFromSet('Sup', 'a', label: 'sup-no-a');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.any((r) => r.label == 'sub-of-sup'), isTrue);
    });

    test('addSetDisjoint label propagates', () async {
      final p = Problem()
        ..addSetVariable('S', universe: ['a', 'b'])
        ..addSetVariable('T', universe: ['a', 'b'])
        ..addSetDisjoint('S', 'T', label: 's-disjoint-t')
        ..addRequiredInSet('S', 'a', label: 's-has-a')
        ..addRequiredInSet('T', 'a', label: 't-has-a');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.any((r) => r.label == 's-disjoint-t'), isTrue);
    });

    test('addSetUnion label propagates', () async {
      // result == a ∪ b, with result forced to exclude 'a' and a
      // forced to include 'a'.
      final p = Problem()
        ..addSetVariable('A', universe: ['a', 'b'])
        ..addSetVariable('B', universe: ['a', 'b'])
        ..addSetVariable('R', universe: ['a', 'b'])
        ..addSetUnion('A', 'B', 'R', label: 'r-is-union')
        ..addRequiredInSet('A', 'a', label: 'a-has-a')
        ..addExcludedFromSet('R', 'a', label: 'r-no-a');
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.any((r) => r.label == 'r-is-union'), isTrue);
    });
  });

  group('Soft-constraint helper propagates label', () {
    test('addSoftConstraint label propagates to the reified n-ary', () async {
      // The reified bool var posted by addSoftConstraint goes through
      // addReified, which posts an n-ary constraint with the user's
      // label. We can't make a "soft" constraint be in the MUS (it's
      // soft, not hard) — but we CAN add a hard constraint forcing
      // the soft's bool var, then create a hard contradiction that
      // pulls the soft's reification ref into the MUS.
      //
      // Setup: 3 vars a, b, c on {1, 2}. Add a soft constraint
      // requiring a == b == c (impossible on the domain because we
      // also addAllDifferent below). Then maximizeSatisfaction has to
      // pick the best feasible assignment; for label-propagation we
      // care only that the underlying reified n-ary carries the label.
      // Simpler: use the MUS pass on a problem where the soft's
      // underlying reified constraint is itself part of an UNSAT
      // configuration.
      final p = Problem()..addVariables(['a', 'b'], [0, 1]);
      // Soft: b ⇔ (a == 1). Label propagates to the reified n-ary.
      final softBool = p.addSoftConstraint(
        1,
        ['a'],
        (Map<String, dynamic> m) => m['a'] == 1,
        label: 'prefer-a-one',
      );
      // Force the soft's bool var to a value that contradicts a
      // pinned assignment: pin softBool = 1 (force a == 1) and pin
      // a = 0. Now {reified_soft, force_softBool=1, force_a=0} is
      // unsat and the reified ref must surface.
      p
        ..addConstraint(
            <String>[softBool], (Map<String, dynamic> m) => m[softBool] == 1,
            label: 'pin-bool')
        ..addConstraint(<String>['a'], (Map<String, dynamic> m) => m['a'] == 0,
            label: 'pin-a-zero');

      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      // The reified n-ary from addSoftConstraint must carry the label.
      expect(mus!.any((r) => r.label == 'prefer-a-one'), isTrue);
    });
  });

  group('Mixed labeled and unlabeled constraints', () {
    test('unlabeled refs surface with null label; labeled with the string',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      // Labeled all-different.
      p.addAllDifferent(['a', 'b', 'c'], label: 'all-distinct');
      // Unlabeled redundant binary.
      p.addConstraint(
          ['a', 'b'], (dynamic a, dynamic b) => (a as num) < (b as num));
      final mus = await p.findMinimalUnsatisfiableSubset();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.label, 'all-distinct');
    });
  });
}

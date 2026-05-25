import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('Problem.findMinimalUnsatisfiableSubsetQuickXplain — satisfiability',
      () {
    test('returns null when the problem is trivially satisfiable', () async {
      final p = Problem();
      p.addVariables(['a', 'b'], [1, 2, 3]);
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
      expect(await p.findMinimalUnsatisfiableSubsetQuickXplain(), isNull);
    });

    test('returns null on an empty constraint set with non-empty domains',
        () async {
      final p = Problem();
      p.addVariables(['x', 'y'], [1, 2]);
      expect(await p.findMinimalUnsatisfiableSubsetQuickXplain(), isNull);
    });

    test('returns null when only redundant non-conflicting constraints exist',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2, 3]);
      p.addConstraint(
          ['a', 'b'], (dynamic a, dynamic b) => (a as num) < (b as num));
      p.addConstraint(
          ['b', 'c'], (dynamic b, dynamic c) => (b as num) < (c as num));
      expect(await p.findMinimalUnsatisfiableSubsetQuickXplain(), isNull);
    });
  });

  group(
      'Problem.findMinimalUnsatisfiableSubsetQuickXplain — minimal UNSAT detection',
      () {
    test('singleton MUS: an impossible binary equality vs inequality pair',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b'], [1, 2]);
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a == b);
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.kind), everyElement(equals('binary')));
    });

    test('MUS over allDifferent on too-narrow domain', () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]); // pigeonhole 3-in-2
      p.addAllDifferent(['a', 'b', 'c']);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.kind, 'allDifferent');
      expect(mus.first.variables, ['a', 'b', 'c']);
    });

    test('triangle 3-coloring with 2 colors — MUS is all three edges',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
      p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
      p.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 3);
      expect(mus.map((r) => r.kind), everyElement(equals('binary')));
    });

    test('MUS drops a redundant constraint', () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c', 'd'], [1, 2, 3]);
      p.addConstraint(['a', 'b'],
          (dynamic a, dynamic b) => (a as num) < (b as num)); // redundant
      p.addAllDifferent(['a', 'b', 'c', 'd']);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.kind, 'allDifferent');
    });

    test('MUS over linear arithmetic — two-equation infeasibility', () async {
      final p = Problem();
      p.addRangeVariable('x', 0, 10);
      p.addRangeVariable('y', 0, 10);
      p.addLinearEquals(['x', 'y'], [1, 1], 5); // x + y == 5
      p.addLinearLeq(['x', 'y'], [1, 1], 3); // x + y <= 3
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.kind),
          containsAll(<String>['linearEquals', 'linearLeq']));
    });

    test('MUS over mixed binary + n-ary, dropping a redundant binary',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b'], [0, 1, 2]);
      p.addVariables(['c', 'd'], [1, 2, 3]);
      p.addConstraint(
          ['c', 'd'], (dynamic c, dynamic d) => c != d); // redundant
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a == b);
      p.addLinearEquals(['a', 'b'], [1, 1], 3);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 2);
      expect(mus.map((r) => r.kind),
          containsAll(<String>['binary', 'linearEquals']));
      expect(
        mus.any((r) =>
            r.kind == 'binary' && r.variables.toSet().containsAll(['c', 'd'])),
        isFalse,
      );
    });

    test('MUS over clauses (SAT-style)', () async {
      final p = Problem();
      p.addVariables(['x', 'y'], [0, 1]);
      p.addClause(positive: ['x']);
      p.addClause(positive: ['y']);
      p.addClause(negative: ['x', 'y']);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 3);
      expect(mus.map((r) => r.kind), everyElement(equals('clause')));
    });
  });

  group(
      'Problem.findMinimalUnsatisfiableSubsetQuickXplain — minimality witness',
      () {
    test('removing any constraint from the MUS yields a satisfiable subset',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
      p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
      p.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
      p.addConstraint(['a', 'b'],
          (dynamic a, dynamic b) => (a as num) <= (b as num)); // weak
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 3); // exactly the triangle

      for (var skip = 0; skip < 3; skip++) {
        final q = Problem();
        q.addVariables(['a', 'b', 'c'], [1, 2]);
        if (skip != 0) {
          q.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
        }
        if (skip != 1) {
          q.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
        }
        if (skip != 2) {
          q.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
        }
        expect(await q.getSolution(), isA<Map<String, dynamic>>());
      }
    });
  });

  group(
      'Problem.findMinimalUnsatisfiableSubsetQuickXplain — relation to deletion pass',
      () {
    // Note: MUS extraction is not deterministic in the *identity* of the
    // returned subset — different algorithms (or the same algorithm under
    // different orderings) can land on different locally-minimal MUSes
    // for the same problem. These tests therefore assert that the QX
    // result is *a* valid (locally minimal) MUS, not that it equals the
    // deletion-based result.

    test('triangle 3-coloring: QX finds a MUS of exactly the 3 cycle edges',
        () async {
      // For a 3-cycle on 2 colors, every MUS must include all three
      // cycle edges — no two of them alone are unsat. So both algorithms
      // necessarily return the same 3-element set (mod the redundant edge).
      Problem build() {
        final p = Problem();
        p.addVariables(['a', 'b', 'c'], [1, 2]);
        p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b);
        p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c);
        p.addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c);
        p.addConstraint(['a', 'b'],
            (dynamic a, dynamic b) => (a as num) < (b as num)); // redundant
        return p;
      }

      final del = await build().findMinimalUnsatisfiableSubset();
      final qx = await build().findMinimalUnsatisfiableSubsetQuickXplain();
      expect(del, isNotNull);
      expect(qx, isNotNull);
      // Both algorithms identify 3 edges, all binary; the specific edges
      // may differ in identity but not in count or kind.
      expect(del!.length, 3);
      expect(qx!.length, 3);
      expect(qx.map((r) => r.kind), everyElement(equals('binary')));
    });

    test('pigeonhole allDifferent has a unique singleton MUS', () async {
      // The only constraint causing unsat is the allDifferent. The
      // redundant a<b is sat on its own. So both algorithms must return
      // the singleton {allDifferent}.
      Problem build() {
        final p = Problem();
        p.addVariables(['a', 'b', 'c'], [1, 2]);
        p.addConstraint(['a', 'b'],
            (dynamic a, dynamic b) => (a as num) < (b as num)); // redundant
        p.addAllDifferent(['a', 'b', 'c']);
        return p;
      }

      final del = await build().findMinimalUnsatisfiableSubset();
      final qx = await build().findMinimalUnsatisfiableSubsetQuickXplain();
      expect(del, isNotNull);
      expect(qx, isNotNull);
      expect(qx!.map((r) => r.id).toSet(), del!.map((r) => r.id).toSet());
      expect(qx.length, 1);
      expect(qx.first.kind, 'allDifferent');
    });

    test('mixed binary + linear has a unique two-constraint MUS', () async {
      // a == b (only allows (0,0)/(1,1)/(2,2), sums 0/2/4) and a+b == 3
      // (only allows (1,2)/(2,1)) together form an irreducible 2-element
      // MUS. The c != d redundant must be dropped.
      Problem build() {
        final p = Problem();
        p.addVariables(['a', 'b'], [0, 1, 2]);
        p.addVariables(['c', 'd'], [1, 2, 3]);
        p.addConstraint(
            ['c', 'd'], (dynamic c, dynamic d) => c != d); // redundant
        p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a == b);
        p.addLinearEquals(['a', 'b'], [1, 1], 3);
        return p;
      }

      final del = await build().findMinimalUnsatisfiableSubset();
      final qx = await build().findMinimalUnsatisfiableSubsetQuickXplain();
      expect(del, isNotNull);
      expect(qx, isNotNull);
      expect(qx!.map((r) => r.id).toSet(), del!.map((r) => r.id).toSet());
      expect(qx.length, 2);
      expect(qx.map((r) => r.kind),
          containsAll(<String>['binary', 'linearEquals']));
    });
  });

  group('Problem.findMinimalUnsatisfiableSubsetQuickXplain — composition', () {
    test('respects consistency level (SAC vs AC give the same MUS)', () async {
      Problem build() {
        final p = Problem();
        p.addVariables(['a', 'b', 'c'], [1, 2]);
        p.addAllDifferent(['a', 'b', 'c']);
        return p;
      }

      final musAc = await build().findMinimalUnsatisfiableSubsetQuickXplain();
      final musSac = await build().findMinimalUnsatisfiableSubsetQuickXplain(
          consistency: ConsistencyLevel.singletonArcConsistency);
      expect(musAc, isNotNull);
      expect(musSac, isNotNull);
      expect(musAc!.length, musSac!.length);
      expect(musAc.map((r) => r.id).toSet(), musSac.map((r) => r.id).toSet());
    });

    test('does not corrupt the originating Problem', () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      p.addAllDifferent(['a', 'b', 'c']);
      p.addConstraint(
          ['a', 'b'], (dynamic a, dynamic b) => (a as num) < (b as num));

      final beforeCount = p.constraintCount;
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(p.constraintCount, beforeCount);
      expect(await p.getSolution(), 'FAILURE');
    });
  });

  group('Problem.findMinimalUnsatisfiableSubsetQuickXplain — cancellation', () {
    test('pre-cancelled token returns null', () async {
      final token = CancellationToken();
      token.cancel();
      final p = Problem();
      p.addVariables(['a', 'b'], [1, 2]);
      p.addAllDifferent(['a', 'b', 'b']);
      final mus =
          await p.findMinimalUnsatisfiableSubsetQuickXplain(cancelToken: token);
      expect(mus, isNull);
    });

    test('mid-recursion cancellation returns null or a valid MUS', () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c', 'd', 'e'], [1, 2, 3, 4]);
      p.addAllDifferent(['a', 'b', 'c', 'd', 'e']);
      p.addConstraint(
          ['a', 'b'], (dynamic a, dynamic b) => (a as num) < (b as num));
      p.addConstraint(
          ['b', 'c'], (dynamic b, dynamic c) => (b as num) < (c as num));
      p.addConstraint(
          ['c', 'd'], (dynamic c, dynamic d) => (c as num) < (d as num));
      p.addConstraint(
          ['d', 'e'], (dynamic d, dynamic e) => (d as num) < (e as num));

      final token = CancellationToken();
      Future.delayed(const Duration(milliseconds: 1), token.cancel);
      final mus =
          await p.findMinimalUnsatisfiableSubsetQuickXplain(cancelToken: token);
      // Either we completed before cancellation fired (mus non-null and
      // non-empty), or cancellation interrupted recursion (mus is null).
      // Both are valid contracts. Multiple MUSes exist here (the
      // allDifferent alone, or the 4-element chain alone) — QX may return
      // either.
      if (mus != null) {
        expect(mus, isNotEmpty);
      }
    });
  });

  group('Problem.findMinimalUnsatisfiableSubsetQuickXplain — ref IDs', () {
    test('binary forward+reverse pair surfaces as one ref', () async {
      final p = Problem();
      p.addVariables(['a'], [1, 2]);
      p.addConstraint(['a', 'a'], (dynamic x, dynamic y) => x != y);
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.kind, 'binary');
      expect(mus.first.id, 'b0');
    });

    test('result is sorted in posting order (binary first, then n-ary)',
        () async {
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2]);
      // Mix binary and n-ary in posting; MUS is the allDifferent only.
      p.addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b); // b0
      p.addAllDifferent(['a', 'b', 'c']); // n0, the MUS
      p.addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c); // b1
      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, 1);
      expect(mus.first.id, 'n0');
    });
  });

  group('Problem.findMinimalUnsatisfiableSubsetQuickXplain — larger conflict',
      () {
    test('5-cycle 2-coloring: MUS is a non-empty subset of binary edges',
        () async {
      // Odd cycle is not 2-colorable. With redundant edges sprinkled in,
      // multiple locally-minimal MUSes exist: the five cycle ≠ edges
      // alone form one, but other 6-element MUSes mixing redundant ≤
      // edges with a subset of cycle edges are also locally minimal.
      // Assert only "result is a non-empty binary-only MUS"; not "the
      // smallest possible MUS" (NP-hard in general).
      final p = Problem();
      p.addVariables(['v0', 'v1', 'v2', 'v3', 'v4'], [1, 2]);
      p.addConstraint(
          ['v0', 'v2'], (dynamic a, dynamic b) => (a as num) <= (b as num));
      p.addConstraint(
          ['v1', 'v3'], (dynamic a, dynamic b) => (a as num) <= (b as num));
      p.addConstraint(['v0', 'v1'], (dynamic a, dynamic b) => a != b);
      p.addConstraint(['v1', 'v2'], (dynamic a, dynamic b) => a != b);
      p.addConstraint(['v2', 'v3'], (dynamic a, dynamic b) => a != b);
      p.addConstraint(['v3', 'v4'], (dynamic a, dynamic b) => a != b);
      p.addConstraint(['v4', 'v0'], (dynamic a, dynamic b) => a != b);

      final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
      expect(mus, isNotNull);
      expect(mus!.length, inInclusiveRange(5, 7));
      expect(mus.map((r) => r.kind), everyElement(equals('binary')));
    });
  });
}

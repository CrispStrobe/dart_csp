// Mixed integer / continuous models solved by the main engine
// (`Problem.addFloatVariable`) — as opposed to the isolated
// `ContinuousModel` covered by `continuous_test.dart`.
//
// The engine reports each continuous variable as the midpoint of a box
// at most `floatEpsilon` wide, so equality against an exact real is
// always asserted with a tolerance. `_tol` is the slack used throughout:
// generous enough to absorb the box width plus the accumulated
// floating-point error of a few propagation rounds.

import 'dart:math';

import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

/// Solves [p] and returns the assignment, failing the test if the
/// problem turned out to be unsatisfiable.
Future<Map<String, dynamic>> _solve(Problem p) async {
  final r = await p.getSolution();
  expect(r, isA<Map<String, dynamic>>(), reason: 'expected a solution, got $r');
  return r as Map<String, dynamic>;
}

void main() {
  group('declaration', () {
    test('float variables are reported separately from enumerated ones', () {
      final p = Problem();
      p.addRangeVariable('n', 0, 5);
      p.addFloatVariable('x', -1.5, 2.5);
      expect(p.isFloatVariable('x'), isTrue);
      expect(p.isFloatVariable('n'), isFalse);
      expect(p.floatVariables.keys, ['x']);
      expect(p.floatVariables['x']!.lo, -1.5);
      expect(p.floatVariables['x']!.hi, 2.5);
      // The enumerated channel is untouched.
      expect(p.variables.keys, ['n']);
    });

    test('rejects a duplicate name in either direction', () {
      final p = Problem();
      p.addFloatVariable('x', 0, 1);
      expect(() => p.addFloatVariable('x', 0, 1), throwsArgumentError);
      expect(() => p.addVariable('x', [1, 2]), throwsArgumentError);
      final q = Problem();
      q.addVariable('y', [1, 2]);
      expect(() => q.addFloatVariable('y', 0, 1), throwsArgumentError);
    });

    test('rejects an empty or non-finite interval', () {
      final p = Problem();
      expect(() => p.addFloatVariable('a', 2, 1), throwsArgumentError);
      expect(() => p.addFloatVariable('b', 0, double.infinity),
          throwsArgumentError);
      expect(() => p.addFloatVariable('c', double.nan, 1), throwsArgumentError);
    });

    test('rejects a non-positive epsilon', () {
      final p = Problem();
      expect(() => p.setFloatEpsilon(0), throwsArgumentError);
      expect(() => p.setFloatEpsilon(-1), throwsArgumentError);
    });

    test('copy() carries the continuous channel', () async {
      final p = Problem();
      p.addFloatVariable('x', 0, 10);
      p.addLinearEquals(['x'], [1], 4);
      final c = p.copy();
      expect(c.floatVariables['x']!.hi, 10);
      final sol = await _solve(c);
      expect(sol['x'] as double, closeTo(4, _tol));
    });

    test('clear() drops the continuous channel', () {
      final p = Problem();
      p.addFloatVariable('x', 0, 1);
      p.clear();
      expect(p.floatVariables, isEmpty);
    });
  });

  group('scope restrictions', () {
    test('a predicate constraint rejects a continuous variable', () {
      final p = Problem();
      p.addRangeVariable('n', 0, 5);
      p.addFloatVariable('x', 0, 5);
      expect(
        () => p.addConstraint(['n', 'x'], (dynamic a, dynamic b) => a != b),
        throwsA(isA<ArgumentError>().having((e) => e.message.toString(),
            'message', contains('continuous variable'))),
      );
    });

    test('a global constraint rejects a continuous variable', () {
      final p = Problem();
      p.addRangeVariable('n', 0, 5);
      p.addFloatVariable('x', 0, 5);
      expect(() => p.addAllDifferent(['n', 'x']), throwsArgumentError);
    });

    test('a repeated variable in a mixed linear constraint is rejected', () {
      // Interval reasoning treats the two occurrences as independent
      // quantities, so `x - x <= -1` would look satisfiable. Requiring
      // combined coefficients keeps every revise exact.
      final p = Problem();
      p.addFloatVariable('x', 0, 5);
      expect(
          () => p.addLinearLeq(['x', 'x'], [1, -1], -1), throwsArgumentError);
    });
  });

  group('pure continuous models through the engine', () {
    test('solves a 2x2 linear system', () async {
      // x + y = 10, x - y = 2  =>  x = 6, y = 4.
      final p = Problem();
      p.addFloatVariable('x', 0, 100);
      p.addFloatVariable('y', 0, 100);
      p.addLinearEquals(['x', 'y'], [1, 1], 10);
      p.addLinearEquals(['x', 'y'], [1, -1], 2);
      final sol = await _solve(p);
      expect(sol['x'] as double, closeTo(6, _tol));
      expect(sol['y'] as double, closeTo(4, _tol));
    });

    test('respects a tightened epsilon', () async {
      final p = Problem();
      p.addFloatVariable('x', 0, 1000);
      p.setFloatEpsilon(1e-9);
      p.addLinearEquals(['x'], [3], 1);
      final sol = await _solve(p);
      expect(sol['x'] as double, closeTo(1 / 3, 1e-8));
    });

    test('detects an infeasible continuous model', () async {
      final p = Problem();
      p.addFloatVariable('x', 0, 1);
      p.addLinearGeq(['x'], [1], 2);
      expect(await p.getSolution(), 'FAILURE');
    });

    test('an inconsistent pair of equalities is infeasible', () async {
      final p = Problem();
      p.addFloatVariable('x', -10, 10);
      p.addFloatVariable('y', -10, 10);
      p.addLinearEquals(['x', 'y'], [1, 1], 1);
      p.addLinearEquals(['x', 'y'], [1, 1], 2);
      expect(await p.getSolution(), 'FAILURE');
    });
  });

  group('mixed integer / continuous', () {
    test('a linear constraint prunes across both kinds', () async {
      // 2n + 1.5x <= 40 with n >= 12 forces x <= 10.666...
      final p = Problem();
      p.addRangeVariable('n', 0, 20);
      p.addFloatVariable('x', 0, 100);
      p.addLinearLeq(['n', 'x'], [2, 1.5], 40);
      p.addLinearGeq(['n'], [1], 12);
      final sol = await _solve(p);
      final n = sol['n'] as int;
      final x = sol['x'] as double;
      expect(n, greaterThanOrEqualTo(12));
      expect(2 * n + 1.5 * x, lessThanOrEqualTo(40 + _tol));
    });

    test('the continuous part prunes the integer part', () async {
      // x in [1, 2] and m + x <= 6.5 forces m <= 5.
      final p = Problem();
      p.addRangeVariable('m', 0, 10);
      p.addFloatVariable('x', 1.0, 2.0);
      p.addLinearLeq(['m', 'x'], [1, 1], 6.5);
      final best = await p.maximize('m');
      expect((best as Map<String, dynamic>)['m'], 5);
    });

    test('integrality is enforced through the interval bound', () async {
      // 3k == z and z == 1 has no integer solution.
      final p = Problem();
      p.addRangeVariable('k', 0, 10);
      p.addFloatVariable('z', 0.0, 5.0);
      p.addLinearEquals(['k', 'z'], [3, -1], 0);
      p.addLinearEquals(['z'], [1], 1);
      expect(await p.getSolution(), 'FAILURE');
    });

    test('a global constraint still works on the discrete part', () async {
      // allDifferent pins {a,b,c} to a permutation of {1,2,3}, and the
      // mixed linear constraint reads its sum into a real.
      final p = Problem();
      p.addVariables(['a', 'b', 'c'], [1, 2, 3]);
      p.addAllDifferent(['a', 'b', 'c']);
      p.addFloatVariable('t', 0.0, 10.0);
      p.addLinearEquals(['a', 'b', 'c', 't'], [1, 1, 1, -1], 0);
      final sol = await _solve(p);
      expect({sol['a'], sol['b'], sol['c']}, {1, 2, 3});
      expect(sol['t'] as double, closeTo(6, _tol));
    });

    test('an infeasible mixed model reports FAILURE', () async {
      final p = Problem();
      p.addRangeVariable('n', 5, 10);
      p.addFloatVariable('f', 0.0, 1.0);
      p.addLinearLeq(['n', 'f'], [1, 1], 3);
      expect(await p.getSolution(), 'FAILURE');
    });

    test('dom/wdeg search handles a mixed model', () async {
      final p = Problem();
      p.addRangeVariable('n', 0, 8);
      p.addFloatVariable('x', 0.0, 20.0);
      p.addLinearEquals(['n', 'x'], [2, -1], 0);
      p.addLinearGeq(['n'], [1], 5);
      final r = await p.getSolutionWithDomWdeg();
      expect(r, isA<Map<String, dynamic>>());
      final sol = r as Map<String, dynamic>;
      expect(sol['x'] as double, closeTo(2.0 * (sol['n'] as int), _tol));
    });

    test('LCG search handles a mixed model', () async {
      final p = Problem();
      p.addRangeVariable('n', 0, 8);
      p.addFloatVariable('x', 0.0, 20.0);
      p.addLinearEquals(['n', 'x'], [2, -1], 0);
      p.addLinearGeq(['x'], [1], 9);
      final r = await p.solveWithLcg();
      expect(r, isA<Map<String, dynamic>>());
      final sol = r as Map<String, dynamic>;
      expect(sol['n'] as int, greaterThanOrEqualTo(5));
    });

    test('conflict-directed backjumping handles a mixed model', () async {
      final p = Problem();
      p.addRangeVariable('n', 0, 8);
      p.addFloatVariable('x', 0.0, 20.0);
      p.addLinearEquals(['n', 'x'], [2, -1], 0);
      p.addLinearGeq(['x'], [1], 15);
      final r = await p.getSolution(enableConflictBackjumping: true);
      expect(r, isA<Map<String, dynamic>>());
      expect((r as Map<String, dynamic>)['n'] as int, greaterThanOrEqualTo(8));
    });
  });

  group('search strategies', () {
    // Every systematic entry point must handle a mixed model. These are
    // regression guards for the enumerating paths inside each strategy
    // (impact's per-value tables, restarts' phase saving, SAC's
    // singleton pinning) that would throw on an uncountable domain if
    // their continuous gate were removed.
    Problem mixed() {
      final p = Problem();
      p.addRangeVariable('n', 0, 8);
      p.addFloatVariable('x', 0.0, 20.0);
      p.addLinearEquals(['n', 'x'], [2, -1], 0); // x == 2n
      p.addLinearGeq(['x'], [1], 9);
      return p;
    }

    void checkMixed(dynamic r) {
      expect(r, isA<Map<String, dynamic>>(), reason: 'got $r');
      final sol = r as Map<String, dynamic>;
      final n = sol['n'] as int;
      final x = sol['x'] as double;
      expect(x, closeTo(2.0 * n, _tol));
      expect(x, greaterThanOrEqualTo(9 - _tol));
    }

    test('restarts',
        () async => checkMixed(await mixed().getSolutionWithRestarts()));
    test('VSIDS activity',
        () async => checkMixed(await mixed().getSolutionWithActivity()));
    test('impact-based',
        () async => checkMixed(await mixed().getSolutionWithImpact()));
    test('last-conflict',
        () async => checkMixed(await mixed().getSolutionWithLastConflict()));
    test('singleton arc consistency', () async {
      checkMixed(await mixed()
          .getSolution(consistency: ConsistencyLevel.singletonArcConsistency));
    });
    test('forward checking', () async {
      checkMixed(await mixed()
          .getSolution(consistency: ConsistencyLevel.forwardChecking));
    });

    test('min-conflicts rejects a continuous variable', () async {
      // Local search seeds every variable with a random domain value —
      // meaningless on an interval. It used to silently omit the
      // variable and return an incomplete "assignment".
      await expectLater(mixed().solveWithMinConflicts(), throwsArgumentError);
    });

    test('LNS rejects a continuous variable', () async {
      await expectLater(mixed().lnsMinimize('n'), throwsArgumentError);
    });

    test('getSolutions enumerates boxes', () async {
      // Correct but coarse: each continuous variable contributes
      // O(range / epsilon) boxes, so this is rarely what you want.
      final p = Problem();
      p.addRangeVariable('n', 0, 2);
      p.addFloatVariable('x', 0.0, 1.0);
      p.setFloatEpsilon(0.5);
      p.addLinearLeq(['n', 'x'], [1, 1], 5);
      final all = await p.getSolutions().take(20).toList();
      expect(all, isNotEmpty);
      for (final sol in all) {
        expect((sol['n'] as int) + (sol['x'] as double),
            lessThanOrEqualTo(5 + _tol));
      }
    });
  });

  group('optimization over a continuous objective', () {
    test('minimize finds the true lower bound', () async {
      // cost >= 2n + 1.5, n >= 3  =>  min cost = 7.5 at n = 3.
      final p = Problem();
      p.addRangeVariable('n', 3, 9);
      p.addFloatVariable('cost', 0.0, 100.0);
      p.addLinearGeq(['cost', 'n'], [1, -2], 1.5);
      final r = await p.minimize('cost');
      final sol = r as Map<String, dynamic>;
      expect(sol['n'], 3);
      expect(sol['cost'] as double, closeTo(7.5, _tol));
    });

    test('maximize finds the true upper bound', () async {
      // v <= 3k + 0.5, k in {1,4,7}  =>  max v = 21.5 at k = 7.
      final p = Problem();
      p.addVariables(['k'], [1, 4, 7]);
      p.addFloatVariable('v', 0.0, 50.0);
      p.addLinearLeq(['v', 'k'], [1, -3], 0.5);
      final r = await p.maximize('v');
      final sol = r as Map<String, dynamic>;
      expect(sol['k'], 7);
      expect(sol['v'] as double, closeTo(21.5, _tol));
    });

    test('search effort is logarithmic in 1/epsilon, not linear', () async {
      // The regression guard for the branch-and-bound bug where the
      // objective cut was discarded when a bisection half was re-applied:
      // the search then walked the whole box tree (~1/epsilon nodes)
      // instead of descending it (~log2(1/epsilon) nodes).
      Future<int> decisionsFor(double eps) async {
        final p = Problem();
        p.addRangeVariable('n', 3, 9);
        p.addFloatVariable('cost', 0.0, 100.0);
        p.setFloatEpsilon(eps);
        p.addLinearGeq(['cost', 'n'], [1, -2], 1.5);
        await p.minimize('cost');
        return p.lastStats!.decisions;
      }

      // A thousandfold tighter epsilon must cost only a handful more
      // decisions. The bound is loose on purpose — the point is the
      // shape of the growth, not an exact node count.
      final coarse = await decisionsFor(1e-3);
      final fine = await decisionsFor(1e-6);
      expect(fine, lessThan(coarse + 40));
      expect(fine, lessThan(200));
    });

    test('minimize an integer objective in a model containing floats',
        () async {
      final p = Problem();
      p.addRangeVariable('m', 0, 10);
      p.addFloatVariable('w', 2.0, 3.0);
      p.addLinearGeq(['m', 'w'], [1, 1], 6.5);
      final r = await p.minimize('m');
      expect((r as Map<String, dynamic>)['m'], 4);
    });
  });

  group('precision', () {
    test('midpoint residual stays within the documented bound', () async {
      // `doc/mixed-continuous.md` promises that for `sum ci*xi == b` the
      // residual at the reported midpoint is at most `sum|ci| * eps/2`.
      // An underdetermined system is the case that exercises it — the
      // box does not collapse onto a point.
      for (final eps in [1e-2, 1e-4, 1e-6]) {
        final p = Problem();
        p.addFloatVariable('a', 0, 10);
        p.addFloatVariable('b', 0, 10);
        p.addFloatVariable('c', 0, 10);
        p.setFloatEpsilon(eps);
        p.addLinearEquals(['a', 'b', 'c'], [3, -2, 5], 12);
        final s = await _solve(p);
        final residual = 3 * (s['a'] as double) -
            2 * (s['b'] as double) +
            5 * (s['c'] as double) -
            12;
        expect(residual.abs(), lessThanOrEqualTo((3 + 2 + 5) * eps / 2),
            reason: 'eps=$eps');
      }
    });
  });

  group('soundness sweeps', () {
    test(
        'mixed linear systems: every reported solution satisfies every '
        'constraint, and infeasibility agrees with a dense scan', () async {
      final rng = Random(20260719);
      for (var trial = 0; trial < 300; trial++) {
        // One integer variable and one continuous variable, tied by two
        // random linear constraints. Small enough that a dense scan over
        // the integer values, each with an exact interval check on the
        // continuous variable, decides feasibility independently.
        const nLo = 0, nHi = 6;
        const xLo = -5.0, xHi = 5.0;
        final cs = <({double cn, double cx, LinearOp op, double b})>[];
        for (var i = 0; i < 2; i++) {
          cs.add((
            cn: (rng.nextInt(9) - 4).toDouble(),
            cx: (rng.nextInt(9) - 4).toDouble(),
            op: LinearOp.values[rng.nextInt(3)],
            b: (rng.nextInt(41) - 20) / 2.0,
          ));
        }
        // Skip degenerate systems: an equality with a zero coefficient
        // on the continuous variable makes feasibility depend on an
        // exact real equality, which no box of positive width can
        // witness — not a soundness question.
        if (cs.any((c) => c.op == LinearOp.eq && c.cx == 0)) continue;

        final p = Problem();
        p.addRangeVariable('n', nLo, nHi);
        p.addFloatVariable('x', xLo, xHi);
        p.setFloatEpsilon(1e-9);
        for (final c in cs) {
          switch (c.op) {
            case LinearOp.eq:
              p.addLinearEquals(['n', 'x'], [c.cn, c.cx], c.b);
            case LinearOp.leq:
              p.addLinearLeq(['n', 'x'], [c.cn, c.cx], c.b);
            case LinearOp.geq:
              p.addLinearGeq(['n', 'x'], [c.cn, c.cx], c.b);
          }
        }

        // Reference: for each integer n, the constraints cut the x-axis
        // into half-lines / points; intersect them exactly.
        var referenceFeasible = false;
        for (var n = nLo; n <= nHi && !referenceFeasible; n++) {
          var lo = xLo, hi = xHi;
          var ok = true;
          for (final c in cs) {
            final rhs = c.b - c.cn * n; // c.cx * x  {op}  rhs
            if (c.cx == 0) {
              ok = switch (c.op) {
                LinearOp.eq => 0 == rhs,
                LinearOp.leq => 0 <= rhs,
                LinearOp.geq => 0 >= rhs,
              };
            } else {
              final t = rhs / c.cx;
              final flip = c.cx < 0;
              switch (c.op) {
                case LinearOp.eq:
                  lo = max(lo, t);
                  hi = min(hi, t);
                case LinearOp.leq:
                  if (flip) {
                    lo = max(lo, t);
                  } else {
                    hi = min(hi, t);
                  }
                case LinearOp.geq:
                  if (flip) {
                    hi = min(hi, t);
                  } else {
                    lo = max(lo, t);
                  }
              }
            }
            if (!ok) break;
          }
          if (ok && lo <= hi) referenceFeasible = true;
        }

        final result = await p.getSolution();
        if (result is Map<String, dynamic>) {
          // Whatever the reference says, a returned witness must
          // actually satisfy the constraints — that is the hard
          // soundness claim.
          final n = (result['n'] as int).toDouble();
          final x = result['x'] as double;
          for (final c in cs) {
            final s = c.cn * n + c.cx * x;
            switch (c.op) {
              case LinearOp.eq:
                expect(s, closeTo(c.b, 1e-6), reason: 'trial $trial: $cs');
              case LinearOp.leq:
                expect(s, lessThanOrEqualTo(c.b + 1e-6),
                    reason: 'trial $trial: $cs');
              case LinearOp.geq:
                expect(s, greaterThanOrEqualTo(c.b - 1e-6),
                    reason: 'trial $trial: $cs');
            }
          }
          expect(referenceFeasible, isTrue,
              reason: 'trial $trial: solver found $result but the reference '
                  'scan says infeasible ($cs)');
        } else {
          // Reporting FAILURE on a feasible instance would be a
          // completeness bug. Allow the case where the feasible region
          // is a single point (lo == hi), which a positive-width box
          // may miss.
          if (referenceFeasible) {
            var strictlyFeasible = false;
            for (var n = nLo; n <= nHi && !strictlyFeasible; n++) {
              var lo = xLo, hi = xHi;
              var ok = true;
              for (final c in cs) {
                final rhs = c.b - c.cn * n;
                if (c.cx == 0) {
                  ok = switch (c.op) {
                    LinearOp.eq => 0 == rhs,
                    LinearOp.leq => 0 <= rhs,
                    LinearOp.geq => 0 >= rhs,
                  };
                } else {
                  final t = rhs / c.cx;
                  final flip = c.cx < 0;
                  switch (c.op) {
                    case LinearOp.eq:
                      lo = max(lo, t);
                      hi = min(hi, t);
                    case LinearOp.leq:
                      if (flip) {
                        lo = max(lo, t);
                      } else {
                        hi = min(hi, t);
                      }
                    case LinearOp.geq:
                      if (flip) {
                        hi = min(hi, t);
                      } else {
                        lo = max(lo, t);
                      }
                  }
                }
                if (!ok) break;
              }
              if (ok && hi - lo > 1e-6) strictlyFeasible = true;
            }
            expect(strictlyFeasible, isFalse,
                reason: 'trial $trial: solver reported FAILURE but the region '
                    'has positive width ($cs)');
          }
        }
      }
    });

    test('a continuous minimum matches a dense scan of the integer part',
        () async {
      final rng = Random(4242);
      for (var trial = 0; trial < 60; trial++) {
        // cost >= a*n + b  with n in [0, 8]; the optimum is attained at
        // whichever n minimizes a*n + b, which a scan computes directly.
        final a = (rng.nextInt(9) - 4).toDouble();
        final b = (rng.nextInt(21) - 10) / 2.0;
        final p = Problem();
        p.addRangeVariable('n', 0, 8);
        p.addFloatVariable('cost', -100.0, 100.0);
        p.addLinearGeq(['cost', 'n'], [1, -a], b);

        var expected = double.infinity;
        for (var n = 0; n <= 8; n++) {
          final v = a * n + b;
          if (v < expected) expected = v;
        }

        final r = await p.minimize('cost');
        expect(r, isA<Map<String, dynamic>>(),
            reason: 'trial $trial a=$a b=$b');
        final got = (r as Map<String, dynamic>)['cost'] as double;
        expect(got, closeTo(expected, 1e-4), reason: 'trial $trial a=$a b=$b');
      }
    });
  });
}

import 'dart:math' as math;

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

import '../example/nonlinear_linkage.dart';

void main() {
  test('closed four-bar solves six coupled coordinates in a tilted plane', () {
    final model = buildFourBarLinkage();
    expect(model.componentCount, 1);
    expect(model.activeTangentDimension, 6);
    final result = model.createSession().solve();
    checkFourBarSolution(result);
    expect(result.stats.linearSolves, greaterThan(0));
    expect(result.stats.nonlinearIterations, greaterThan(1));
    expect(result.values['b']![2], isNot(closeTo(2, 1e-3)));
    expect(result.values['c']![2], isNot(closeTo(2, 1e-3)));
  });

  test('continuation retains both independently checked assembly branches', () {
    for (final branch in [1, -1]) {
      final session = buildFourBarLinkage(branch: branch).createSession();
      checkFourBarSolution(session.solve(), branch: branch);
      for (final angle in [0.65, 0.85, 1.15, 1.4, 1.8, 2.1, 1.7, 0.7]) {
        session.setParameterValues('input_angle', [angle]);
        final result = session.solve();
        checkFourBarSolution(result, angle: angle, branch: branch);
        expect(result.stats.componentsSolved, 1);
        expect(result.stats.jacobianEvaluations, greaterThan(0));
      }
    }
  });

  test('link dimension edits change the nonlinear closure solution', () {
    final session = buildFourBarLinkage().createSession();
    checkFourBarSolution(session.solve());
    for (final dimensions in [
      (2.1, 3.1, 2.6),
      (1.9, 2.8, 2.4),
      (2.0, 3.0, 2.5),
    ]) {
      session.setParameterValues('crank_length', [dimensions.$1]);
      session.setParameterValues('coupler_length', [dimensions.$2]);
      session.setParameterValues('rocker_length', [dimensions.$3]);
      checkFourBarSolution(session.solve(),
          crankLength: dimensions.$1,
          couplerLength: dimensions.$2,
          rockerLength: dimensions.$3);
    }
  });

  test('exact toggle rank is infinitesimal rather than finite mobility', () {
    final expected = fourBarOracle(angle: 0, couplerLength: 1, rockerLength: 1);
    expect(expected.circleHeight, 0);
    final session = buildFourBarLinkage().createSession(initialValues: {
      'input_angle': [0],
      'coupler_length': [1],
      'rocker_length': [1],
      'b': expected.crank.toList(),
      'c': expected.joint.toList(),
    });
    final result = session.solve();
    checkFourBarSolution(result,
        angle: 0, couplerLength: 1, rockerLength: 1, expectedFreedoms: 1);
    expect(result.components.single.numericalRank, 5);
    // Two unit circles centered at local x=2 and x=4 touch only at x=3.
    // A local Jacobian null vector is not a finite feasible displacement.
    final displacedDistance = math.sqrt(1 + 0.01 * 0.01);
    expect(displacedDistance, greaterThan(1 + linkageLengthTolerance));
  });

  test('near-toggle continuation checks closure and conditioning separately',
      () {
    final expected =
        fourBarOracle(angle: 0, couplerLength: 1.1, rockerLength: 1.1);
    final session = buildFourBarLinkage().createSession(initialValues: {
      'input_angle': [0],
      'coupler_length': [1.1],
      'rocker_length': [1.1],
      'b': expected.crank.toList(),
      'c': expected.joint.toList(),
    });
    checkFourBarSolution(session.solve(),
        angle: 0, couplerLength: 1.1, rockerLength: 1.1);
    for (final length in [1.01, 1.0001, 1.000001]) {
      session.setParameterValues('coupler_length', [length]);
      session.setParameterValues('rocker_length', [length]);
      final result = session.solve();
      // With intersection height approaching zero, length errors are amplified
      // into coordinate errors. Physical closure still uses the fixed 1e-8
      // requirement; this explicitly wider coordinate check reflects that
      // conditioning, not a relaxation of the solver's hard equations.
      checkFourBarSolution(result,
          angle: 0,
          couplerLength: length,
          rockerLength: length,
          coordinateTolerance: 5e-5);
      expect(result.components.single.numericalRank, 6);
    }
  });

  test('impossible link edit fails locally and preserves the valid session',
      () {
    final session = buildFourBarLinkage().createSession();
    checkFourBarSolution(session.solve());
    final before = session.committedValues;
    session.setParameterValues('coupler_length', [0.2]);
    session.setParameterValues('rocker_length', [0.2]);
    // An independent triangle inequality establishes this fixture's
    // contradiction. A general numerical solver failure is not such a proof.
    expect(() => fourBarOracle(couplerLength: 0.2, rockerLength: 0.2),
        throwsStateError);
    final failed = session.solve();
    expect(failed.isSuccess, isFalse);
    expect(failed.localDegreesOfFreedom, isNull);
    expect(session.committedValues, before);
    expect(session.parameterValues('coupler_length'), [linkageCouplerLength]);
    session.restoreLastValid();
    expect(session.pendingValues, before);
    session.setParameterValues('input_angle', [0.9]);
    checkFourBarSolution(session.solve(), angle: 0.9);
  });

  test('budget and cancellation leave the nonlinear commit intact', () {
    final session = buildFourBarLinkage().createSession();
    checkFourBarSolution(session.solve());
    final before = session.committedValues;
    session.setParameterValues('input_angle', [1.0]);
    final limited =
        session.solve(options: const GeometrySolveOptions(maxIterations: 0));
    expect(limited.status, GeometrySolveStatus.iterationLimit);
    expect(session.committedValues, before);
    expect(session.pendingValues, before);
    session.setParameterValues('input_angle', [1.0]);
    final cancelled = session.solve(shouldCancel: () => true);
    expect(cancelled.status, GeometrySolveStatus.cancelled);
    expect(session.committedValues, before);
    expect(session.pendingValues, before);
    session.setParameterValues('input_angle', [1.0]);
    checkFourBarSolution(session.solve(), angle: 1.0);
  });

  test('unchanged solve reuses checked nonlinear geometry', () {
    final session = buildFourBarLinkage().createSession();
    checkFourBarSolution(session.solve());
    final again = session.solve();
    checkFourBarSolution(again);
    expect(again.stats.linearSolves, 0);
    expect(again.stats.componentsSolved, 0);
    expect(again.stats.componentsReused, 1);
  });

  test('duplicate link equation is diagnosed without changing branch', () {
    final result =
        buildFourBarLinkage(redundantCoupler: true).createSession().solve();
    checkFourBarSolution(result);
    final diagnostics = result.components.single;
    expect(diagnostics.dependentEquationCount, greaterThanOrEqualTo(3));
    expect(diagnostics.locallyDependentConstraintIds,
        anyElement(isIn(['coupler', 'coupler_duplicate'])));
  });

  test('asynchronous continuation has the same independent closure', () async {
    final session = buildFourBarLinkage(branch: -1).createSession();
    checkFourBarSolution(await session.solveAsync(), branch: -1);
    session.setParameterValues('input_angle', [1.1]);
    checkFourBarSolution(await session.solveAsync(), angle: 1.1, branch: -1);
  });
}

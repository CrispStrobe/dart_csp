import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

CompiledGeometryModel _model() => GeometryModel(parameters: [
      GeometryParameterBlock(id: 'a', values: [1, 2]),
      GeometryParameterBlock(id: 'b', values: [3, 4]),
      GeometryParameterBlock(id: 'target.a', values: [1], fixed: true),
      GeometryParameterBlock(id: 'target.b', values: [3], fixed: true),
    ], constraints: [
      for (final name in ['a', 'b'])
        GeometryResidualBlock.autoDiff(
          id: 'dimension.$name',
          parameterIds: [name, 'target.$name'],
          residualCount: 2,
          evaluate: (p) => [
            p[0][0] - p[1][0],
            (p[0][0] - p[1][0]) * 2,
          ],
        ),
    ]).compile();

void _check(GeometrySolveResult result, double a, double b) {
  expect(result.isSuccess, isTrue, reason: result.message);
  expect(result.values['a']![0], closeTo(a, 1e-8));
  expect(result.values['b']![0], closeTo(b, 1e-8));
  for (final name in ['a', 'b']) {
    final error =
        result.values[name]![0] - result.values['target.$name']!.single;
    expect(error.abs(), lessThanOrEqualTo(5.1e-9));
    expect(result.constraintResiduals['dimension.$name']![0],
        closeTo(error, 1e-14));
    expect(result.constraintResiduals['dimension.$name']![1],
        closeTo(2 * error, 1e-14));
  }
}

void main() {
  test('clean fork preserves accepted nonzero physical residuals exactly', () {
    final source = _model().createSession(initialValues: {
      'a': [1 + 1e-9, 2],
    });
    final first = source.solve();
    _check(first, 1, 3);
    expect(first.constraintResiduals['dimension.a']![0], isNot(0));
    final copied = source.fork().solve();
    expect(copied.constraintResiduals, first.constraintResiduals);
    expect(copied.stats.componentsReused, 2);
    expect(copied.stats.residualEvaluations, 0);
  });

  test('fork of a stale source retains new pending edits and dirty components',
      () async {
    final source = _model().createSession();
    final first = source.solve();
    source.setParameterValues('target.a', [10]);
    final future = source.solveAsync();
    source.setParameterValues('target.a', [15]);
    expect((await future).status, GeometrySolveStatus.staleRevision);
    final child = source.fork();
    expect(child.committedValues, first.values);
    source.setParameterValues('target.a', [20]);
    _check(child.solve(), 15, 3);
    expect(source.pendingValues['target.a'], [20]);
    expect(source.committedValues, first.values);
  });

  test('clean forks retain validated components and residual snapshots', () {
    final source = _model().createSession();
    final first = source.solve();
    _check(first, 1, 3);
    final child = source.fork();
    expect(identical(child.model, source.model), isTrue);
    expect(identical(child.lastResult, first), isTrue);
    expect(child.revision, source.revision);
    expect(child.dirtyComponentCount, 0);
    final reused = child.solve();
    _check(reused, 1, 3);
    expect(reused.stats.componentsReused, 2);
    expect(reused.stats.residualEvaluations, 0);
    expect(reused.stats.rankFactorizations, 0);
    expect(identical(source.lastResult, first), isTrue);
    expect(() => child.values['a']![0] = 99, throwsUnsupportedError);
  });

  test('edited fork reuses exact rank without altering its source', () {
    final source = _model().createSession();
    final first = source.solve();
    final child = source.fork()..setParameterValues('target.a', [8]);
    final edited = child.solve();
    _check(edited, 8, 3);
    expect(edited.stats.componentsSolved, 1);
    expect(edited.stats.componentsReused, 1);
    expect(edited.stats.rankReuses, 1);
    expect(edited.stats.rankFactorizations, 0);
    expect(source.values, first.values);
    expect(source.pendingValues, first.values);
    expect(source.dirtyComponentCount, 0);
    _check(source.solve(), 1, 3);
    source.setParameterValues('target.b', [12]);
    _check(source.solve(), 1, 12);
    _check(child.solve(), 8, 3);
  });

  test('dirty pending edits and last valid coordinates are copied separately',
      () {
    final source = _model().createSession();
    final first = source.solve();
    source.setParameterValues('target.a', [9]);
    final child = source.fork();
    expect(child.pendingValues['target.a'], [9]);
    expect(child.committedValues, first.values);
    source.setParameterValues('target.a', [11]);
    _check(child.solve(), 9, 3);
    expect(source.pendingValues['target.a'], [11]);
    expect(source.committedValues, first.values);
    _check(source.solve(), 11, 3);
    _check(child.solve(), 9, 3);
  });

  test('fork before first solve owns independent initial guesses', () {
    final source = _model().createSession();
    source.setParameterValues('a', [-20, 7]);
    final child = source.fork();
    expect(child.lastResult, isNull);
    expect(child.committedValues, isNull);
    source.setParameterValues('a', [40, -5]);
    _check(child.solve(), 1, 3);
    expect(child.values['a']![1], 7);
    _check(source.solve(), 1, 3);
    expect(source.values['a']![1], -5);
  });

  test('failed child and a fork of failed state preserve valid coordinates',
      () {
    final source = _model().createSession();
    final first = source.solve();
    final child = source.fork()..setParameterValues('target.a', [99]);
    final failed =
        child.solve(options: const GeometrySolveOptions(maxIterations: 0));
    expect(failed.isSuccess, isFalse);
    expect(child.pendingValues, first.values);
    expect(child.committedValues, first.values);
    expect(source.pendingValues, first.values);
    expect(identical(source.lastResult, first), isTrue);
    final retry = child.fork().solve();
    _check(retry, 1, 3);
    expect(retry.stats.rankReuses, 1);
    expect(retry.stats.componentsReused, 1);
  });

  test('rank option changes in a fork cannot change source diagnostics', () {
    final source = _model().createSession();
    final first = source.solve();
    expect(first.localDegreesOfFreedom, 2);
    final child = source.fork();
    final bounded =
        child.solve(options: const GeometrySolveOptions(rankParameterLimit: 1));
    expect(bounded.isSuccess, isTrue);
    expect(bounded.localDegreesOfFreedom, isNull);
    expect(bounded.stats.componentsSolved, 2);
    final sourceResult = source.solve();
    expect(sourceResult.localDegreesOfFreedom, 2);
    expect(sourceResult.stats.componentsReused, 2);
    expect(child.solve().localDegreesOfFreedom, 2);
  });

  test('preference changes use independent derivative and trial buffers', () {
    final source = _model().createSession();
    final first = source.solve();
    final left = source.fork(), right = source.fork();
    final a = left.solve(preferences: [
      GeometryParameterTarget(parameterId: 'a', values: [1, 20]),
    ]);
    final b = right.solve(preferences: [
      GeometryParameterTarget(parameterId: 'a', values: [1, -30]),
    ]);
    _check(a, 1, 3);
    _check(b, 1, 3);
    expect(a.values['a']![1], closeTo(20, 1e-6));
    expect(b.values['a']![1], closeTo(-30, 1e-6));
    expect(source.values, first.values);
    expect(left.values, a.values);
    expect(right.values, b.values);
  });

  test('forking from a running synchronous callback is rejected', () {
    final source = _model().createSession();
    var checked = false;
    final cancelled = source.solve(shouldCancel: () {
      expect(source.fork, throwsStateError);
      checked = true;
      return true;
    });
    expect(checked, isTrue);
    expect(cancelled.status, GeometrySolveStatus.cancelled);
    _check(source.fork().solve(), 1, 3);
  });

  test('active asynchronous sessions reject forks; revisions stay independent',
      () async {
    final source = _model().createSession();
    _check(source.solve(), 1, 3);
    final child = source.fork()..setParameterValues('target.a', [10]);
    final future = child.solveAsync();
    expect(child.fork, throwsStateError);
    source.setParameterValues('target.a', [25]);
    _check(await future, 10, 3);
    _check(source.solve(), 25, 3);
    _check(child.fork().solve(), 10, 3);
  });

  test('stale child edits never overwrite a sibling or source session',
      () async {
    final source = _model().createSession();
    final first = source.solve();
    final child = source.fork()..setParameterValues('target.a', [10]);
    final sibling = source.fork();
    final future = child.solveAsync();
    child.setParameterValues('target.a', [15]);
    expect((await future).status, GeometrySolveStatus.staleRevision);
    expect(child.pendingValues['target.a'], [15]);
    expect(source.values, first.values);
    expect(sibling.values, first.values);
    _check(child.solve(), 15, 3);
    _check(sibling.solve(), 1, 3);
  });

  test('interleaved siblings and later clean descendants own numerical state',
      () async {
    final source = _model().createSession(initialValues: {
      'a': [1 + 1e-9, 2],
    });
    final initial = source.solve();
    final left = source.fork()..setParameterValues('target.a', [7]);
    final right = source.fork()..setParameterValues('target.b', [13]);
    final results = await Future.wait([left.solveAsync(), right.solveAsync()]);
    _check(results[0], 7, 3);
    _check(results[1], 1, 13);
    expect(results[0].stats.componentsReused, 1);
    expect(results[1].stats.componentsReused, 1);
    expect(results[1].constraintResiduals['dimension.a'],
        initial.constraintResiduals['dimension.a']);

    final descendant = right.fork().fork();
    final reused = descendant.solve();
    expect(reused.constraintResiduals, results[1].constraintResiduals);
    expect(reused.stats.residualEvaluations, 0);
    descendant.setParameterValues('target.a', [-9]);
    final moved = descendant.solve(preferences: [
      GeometryParameterTarget(parameterId: 'b', values: [13, -17]),
    ]);
    _check(moved, -9, 13);
    expect(moved.values['b']![1], closeTo(-17, 1e-6));
    expect(right.values, results[1].values);
    expect(left.values, results[0].values);
    expect(source.values, initial.values);
  });
}

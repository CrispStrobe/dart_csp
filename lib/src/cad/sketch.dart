/// Geometric sketches as immutable, transactional CAD feature outputs.
library;

import '../geometry/solver.dart';
import 'features.dart';
import 'kernel.dart';

/// A physically validated sketch and the profile derived from its coordinates.
class CadSolvedSketch {
  const CadSolvedSketch({
    required this.geometry,
    required this.profile,
    required this.seededFromPrevious,
  });

  final GeometrySolveResult geometry;
  final CadPlanarProfile profile;
  final bool seededFromPrevious;
}

/// Regenerates a constrained 3D geometry or assembly model transactionally.
/// The output is its checked [GeometrySolveResult], usable by
/// [CadFeatureNode.instanceFromPose]. Candidate sessions fork the numerical
/// state associated with this feature's last committed output. Rejected
/// downstream features never become the next warm start. Every regeneration
/// revalidates required equations; exact-Jacobian rank diagnostics can be reused.
CadFeatureNode constrainedGeometryFeature({
  required String id,
  required CompiledGeometryModel model,
  required Map<String, CadExpression> dimensionBindings,
  GeometrySolveOptions options = const GeometrySolveOptions(),
}) {
  final bindings = Map<String, CadExpression>.unmodifiable(dimensionBindings);
  final sessions = Expando<GeometrySolveSession>('CAD geometry candidates');
  final declarations = {for (final block in model.parameters) block.id: block};
  for (final name in bindings.keys) {
    final block = declarations[name];
    if (block == null || !block.fixed || block.values.length != 1) {
      throw ArgumentError(
          'Geometry dimension $name must be a declared fixed scalar.');
    }
  }
  return CadFeatureNode(
    id: id,
    parameterDependencies: {
      for (final expression in bindings.values) ...expression.dependencies,
    },
    evaluate: (context) {
      final previous = context.previousOutput<GeometrySolveResult>();
      final retained = previous == null ? null : sessions[previous];
      final session = retained?.fork() ??
          model.createSession(initialValues: previous?.values);
      // A feature callback can capture application state outside dimension
      // bindings. Preserve the old adapter's complete physical revalidation,
      // while allowing rank reuse only after an exact fresh Jacobian comparison.
      if (retained != null) session.markAllDirty();
      for (final entry in bindings.entries) {
        session.setParameterValues(
            entry.key, [entry.value.evaluate(context.parameters)]);
      }
      final result = session.solve(options: options);
      if (!result.isSuccess) {
        return CadKernelResult.failure(CadKernelStatus.numericalFailure, [
          CadIssue(
              'geometry_${result.status.name}',
              result.message ??
                  'The geometry did not meet required tolerances.',
              entity: id),
        ]);
      }
      sessions[result] = session;
      return CadKernelResult.success(result);
    },
  );
}

/// Connects fixed scalar geometric parameters to CAD parameter expressions.
///
/// The compiled geometric structure is shared across regenerations. Each edit
/// uses an isolated fork of this feature's last committed numerical session,
/// so failure of a later solid or reference check cannot change the sketch used
/// by the next transaction. Scratch buffers belong to each candidate; immutable
/// rank caches survive dimension edits only when a fresh Jacobian matches.
/// Required equations are revalidated on every regeneration, including callbacks
/// that capture application state. Retained sessions are weakly keyed by output,
/// so sharing a feature declaration across documents does not share warm starts.
CadFeatureNode constrainedSketchFeature({
  required String id,
  required CompiledGeometryModel model,
  required Map<String, CadExpression> dimensionBindings,
  required CadPlanarProfile Function(
          GeometrySolveResult geometry, CadParameters parameters)
      buildProfile,
  Iterable<String> parameterDependencies = const [],
  GeometrySolveOptions options = const GeometrySolveOptions(),
}) {
  final bindings = Map<String, CadExpression>.unmodifiable(dimensionBindings);
  final sessions = Expando<GeometrySolveSession>('CAD sketch candidates');
  final declarations = {for (final block in model.parameters) block.id: block};
  for (final name in bindings.keys) {
    final block = declarations[name];
    if (block == null || !block.fixed || block.values.length != 1) {
      throw ArgumentError(
          'Sketch dimension $name must be a declared fixed scalar.');
    }
  }
  return CadFeatureNode(
    id: id,
    parameterDependencies: {
      ...parameterDependencies,
      for (final expression in bindings.values) ...expression.dependencies,
    },
    evaluate: (context) {
      final previous = context.previousOutput<CadSolvedSketch>();
      final retained = previous == null ? null : sessions[previous];
      final session = retained?.fork() ??
          model.createSession(initialValues: previous?.geometry.values);
      if (retained != null) session.markAllDirty();
      for (final entry in bindings.entries) {
        session.setParameterValues(
            entry.key, [entry.value.evaluate(context.parameters)]);
      }
      final result = session.solve(options: options);
      if (!result.isSuccess) {
        return CadKernelResult.failure(CadKernelStatus.numericalFailure, [
          CadIssue('sketch_${result.status.name}',
              result.message ?? 'The sketch did not meet required tolerances.',
              entity: id),
        ]);
      }
      final output = CadSolvedSketch(
        geometry: result,
        profile: buildProfile(result, context.parameters),
        seededFromPrevious: previous != null,
      );
      sessions[output] = session;
      return CadKernelResult.success(output);
    },
  );
}

/// Selects a validated sketch's profile for downstream kernel operations.
CadFeatureNode sketchProfileFeature({
  required String id,
  required String sketch,
}) =>
    CadFeatureNode(
      id: id,
      dependencies: [sketch],
      evaluate: (context) => CadKernelResult.success(
          context.input<CadSolvedSketch>(sketch).profile),
    );

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
/// [CadFeatureNode.instanceFromPose]. Candidate sessions share compiled
/// structure and start from committed coordinates; rejected downstream features
/// never become the next numerical warm start.
CadFeatureNode constrainedGeometryFeature({
  required String id,
  required CompiledGeometryModel model,
  required Map<String, CadExpression> dimensionBindings,
  GeometrySolveOptions options = const GeometrySolveOptions(),
}) {
  final bindings = Map<String, CadExpression>.unmodifiable(dimensionBindings);
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
      final session = model.createSession(initialValues: previous?.values);
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
      return CadKernelResult.success(result);
    },
  );
}

/// Connects fixed scalar geometric parameters to CAD parameter expressions.
///
/// The compiled geometric structure is shared across regenerations. Each edit
/// uses an isolated numerical session seeded from this feature's last committed
/// coordinates, so failure of a later solid or reference check cannot change
/// the sketch used by the next transaction. Standalone interactive geometry
/// sessions also retain numerical workspaces; this transactional adapter retains
/// structure and coordinates but allocates fresh workspaces per regeneration.
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
      final session =
          model.createSession(initialValues: previous?.geometry.values);
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
      return CadKernelResult.success(CadSolvedSketch(
        geometry: result,
        profile: buildProfile(result, context.parameters),
        seededFromPrevious: previous != null,
      ));
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

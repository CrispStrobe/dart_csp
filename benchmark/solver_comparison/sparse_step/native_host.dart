/// The existing benchmark runner, with only its large linear backend replaced.
library;

import 'dart:convert';
import 'dart:io';

import '../dart_adapter_core.dart';
import 'eigen_backend.dart';

const engine = 'dart_2d_analytic_sparse_direct';

Future<void> main(List<String> arguments) async {
  EigenSparseGeometrySolver? backend;
  try {
    if (arguments.isEmpty || arguments.length > 2) {
      throw ArgumentError(
          'usage: dart-sparse-adapter REQUEST.json [LIBRARY.so]');
    }
    final decoded = jsonDecode(await File(arguments.first).readAsString());
    if (decoded is! JsonObject || decoded['engine'] != engine) {
      throw ArgumentError('Expected a $engine request.');
    }
    final libraryPath = arguments.length == 2
        ? arguments[1]
        : Platform.environment['DART_CSP_SPARSE_STEP_LIBRARY'] ??
            '${File(Platform.resolvedExecutable).parent.path}/libdart_csp_sparse_step.so';
    backend = EigenSparseGeometrySolver(libraryPath);
    // All geometry construction and runner semantics remain the existing lane's.
    final request =
        ComparisonRequest.fromJson({...decoded, 'engine': 'dart_2d_analytic'});
    final runner = DartComparisonRunner(request, linearSolver: backend);
    final metadata = runner.metadata();
    metadata.addAll({
      'engine': engine,
      'adapter': 'dart_geometry_eigen_sparse_step/1',
      'linear_backend':
          'unchanged dense QR <=64; Eigen SimplicialLDLT/AMD above64',
      'eigen_version': '3.4.0',
      'eigen_revision': '3147391d946bb4b6c68edd901f2add6ac1f31f8c',
      'eigen_mpl2_only': true,
      'linear_system':
          '(J^T J + damping * diag(diagonal)) step = -J^T residual; inputs already scaled by Dart',
      'linear_convergence':
          'native status plus independent Dart recomputation of original-system relative residual',
      'linear_iteration_units':
          'dense QR pivots or sparse factorization plus up to two refinement solves; not CG iterations',
      'sparse_workspace':
          'pattern analyzed per Jacobian; retained warm, destroyed outside timer before each cold operation',
      'native_cancellation':
          'stop callback before and after synchronous Eigen call; factorization cannot be interrupted internally',
      'ffi_copies_and_validation_timed': true,
    });
    stdout.writeln(jsonEncode(metadata));
    await stdout.flush();
    for (var index = -request.warmups; index < request.samples; index++) {
      backend.beginOperation(cold: request.mode == 'cold');
      final record = runner.step(index);
      record['engine'] = engine;
      record.addAll(backend.metrics());
      stdout.writeln(jsonEncode(record));
      await stdout.flush();
    }
  } catch (error, stack) {
    stderr.writeln('dart-sparse-adapter: $error\n$stack');
    exitCode = 2;
  } finally {
    backend?.clear();
  }
}

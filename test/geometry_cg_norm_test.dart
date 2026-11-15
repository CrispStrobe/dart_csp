import 'dart:typed_data';

import 'package:dart_csp/geometry.dart';
import 'package:test/test.dart';

// Compare finite values and signed zero at the Float64 bit boundary. NaN
// payloads are not a portable Dart contract; their classification is checked.
String _bits(double value) {
  if (value.isNaN) return 'NaN';
  final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
  return '${bytes.getUint32(4, Endian.little).toRadixString(16)}:'
      '${bytes.getUint32(0, Endian.little).toRadixString(16)}';
}

List<String> _vectorBits(List<double> values) => values.map(_bits).toList();

// SparseGeometryJacobian methods are extensible. Retain the initial transpose
// output and change it at the next public method boundary, after p is formed.
// This exposes otherwise difficult residual-update edge cases without private
// solver access or changes to the solver's public callback schedule.
class _NormProbeJacobian extends SparseGeometryJacobian {
  _NormProbeJacobian(this.prefix)
      : super(
          rows: 1,
          columns: prefix.length + 1,
          rowOffsets: Int32List.fromList([0, 1]),
          columnIndices: Int32List.fromList([prefix.length]),
          values: Float64List.fromList([1]),
        );

  final List<double> prefix;
  final trace = <String>[];
  late Float64List retainedResidual;
  var transposeCalls = 0;

  @override
  void normalDiagonal(Float64List out) {
    trace.add('diagonal');
    out.fillRange(0, columns, 1);
  }

  @override
  void multiply(Float64List x, Float64List out) {
    trace.add('multiply:${_vectorBits(x)}');
    super.multiply(x, out);
  }

  @override
  void transposeMultiply(Float64List x, Float64List out) {
    trace.add('transpose:${_vectorBits(x)}');
    super.transposeMultiply(x, out);
    transposeCalls++;
    if (transposeCalls == 1) {
      retainedResidual = out;
    } else if (transposeCalls == 2) {
      retainedResidual.setRange(0, prefix.length, prefix);
    }
  }
}

(GeometryLinearStep, _NormProbeJacobian, int) _probe(
    GeometryLinearSolver solver, List<double> prefix) {
  final jacobian = _NormProbeJacobian(prefix);
  var polls = 0;
  final result = solver.solve(jacobian, Float64List.fromList([-1]),
      damping: 0,
      diagonal: Float64List.fromList(List.filled(jacobian.columns, 1.0)),
      maxIterations: 4,
      relativeTolerance: 0,
      shouldStop: () => ++polls == 2);
  return (result, jacobian, polls);
}

void main() {
  const candidate = SparseCgGeometrySolver();

  group('CG scaled residual norm', () {
    test('matches the separate norm pass for extremes and signed zero', () {
      final cases = <List<double>>[
        [0.0, -0.0, 0.0],
        [5e-324, -5e-324, 0.0],
        [1e-300, -3e-300, 2e-300],
        [1e200, -3e199, 1e-200, 7e199],
        [1e-200, 3e199, -1e200, 7e199],
        [1e308, -1e308, 1e-308],
        [3.0, -4.0, -0.0],
      ];
      for (final prefix in cases) {
        final (actual, jacobian, polls) = _probe(candidate, prefix);
        final norm = geometryNorm([...prefix, 0]);
        final reason = 'residual=${_vectorBits(prefix)}';
        expect(norm.isFinite, isTrue, reason: reason);
        expect(polls, norm == 0 ? 1 : 2, reason: reason);
        expect(
            jacobian.trace.map((entry) => entry.split(':').first),
            [
              'transpose',
              'diagonal',
              'multiply',
              'transpose',
              if (norm == 0) ...['multiply', 'transpose', 'transpose'],
            ],
            reason: reason);
        expect(
            actual.status,
            norm == 0
                ? GeometryLinearStatus.converged
                : GeometryLinearStatus.cancelled,
            reason: reason);
        expect(actual.iterations, 1, reason: reason);
        expect(_bits(actual.relativeResidual), _bits(norm), reason: reason);
        expect(_vectorBits(actual.step),
            _vectorBits([...List<double>.filled(prefix.length, 0), 1]),
            reason: reason);
        expect(
            _vectorBits(jacobian.retainedResidual), _vectorBits([...prefix, 0]),
            reason: reason);
      }
    });

    test('keeps first NaN or infinity precedence and finishes every write', () {
      final cases = <List<double>>[
        [double.infinity, double.nan, 2.0],
        [double.nan, double.infinity, 2.0],
        [double.negativeInfinity, double.nan, -0.0],
        [0.0, double.nan, double.infinity],
        [0.0, double.negativeInfinity, double.nan],
        [3.0, -0.0, double.nan, double.negativeInfinity],
      ];
      for (final prefix in cases) {
        final (actual, jacobian, polls) = _probe(candidate, prefix);
        final reason = 'residual=${_vectorBits(prefix)}';
        expect(actual.status, GeometryLinearStatus.numericalFailure,
            reason: reason);
        expect(actual.iterations, 1, reason: reason);
        expect(polls, 1, reason: reason);
        expect(jacobian.trace.map((entry) => entry.split(':').first),
            ['transpose', 'diagonal', 'multiply', 'transpose'],
            reason: reason);
        expect(_bits(actual.relativeResidual),
            _bits(prefix.firstWhere((value) => !value.isFinite).abs()),
            reason: reason);
        // A return/break at the first nonfinite residual would leave this
        // last nonzero step and its residual update unfinished.
        expect(actual.step.last, 1, reason: reason);
        expect(jacobian.retainedResidual.last, 0, reason: reason);
        expect(
            _vectorBits(jacobian.retainedResidual), _vectorBits([...prefix, 0]),
            reason: reason);
      }
    });

    test('reports final scaled-norm overflow after the complete update', () {
      const prefix = [1.79e308, -1.79e308];
      final (actual, jacobian, polls) = _probe(candidate, prefix);
      expect(prefix.every((value) => value.isFinite), isTrue);
      expect(actual.status, GeometryLinearStatus.numericalFailure);
      expect(actual.relativeResidual, double.infinity);
      expect(actual.iterations, 1);
      expect(polls, 1);
      expect(jacobian.trace.map((entry) => entry.split(':').first),
          ['transpose', 'diagonal', 'multiply', 'transpose']);
      expect(actual.step, [0, 0, 1]);
      expect(jacobian.retainedResidual, [...prefix, 0]);
    });
  });
}

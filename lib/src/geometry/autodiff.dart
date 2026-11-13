import 'dart:math' as math;
import 'dart:typed_data';

/// A forward-mode dual number for a *local* residual block.
///
/// Derivative vectors contain the coordinates touched by one residual, not the
/// coordinates of the complete model. This keeps automatic differentiation
/// proportional to the size of a geometric primitive.
class Dual {
  Dual(this.value, Float64List derivatives)
      : derivatives = Float64List.fromList(derivatives);

  Dual._(this.value, this.derivatives);

  factory Dual.constant(num value, [int dimension = 0]) =>
      Dual._(value.toDouble(), Float64List(dimension));

  factory Dual.variable(double value, int index, int dimension) {
    if (index < 0 || index >= dimension) {
      throw RangeError.index(index, List.filled(dimension, 0));
    }
    final derivatives = Float64List(dimension)..[index] = 1;
    return Dual._(value, derivatives);
  }

  final double value;
  final Float64List derivatives;

  Dual _coerce(Object other) {
    if (other is num) return Dual.constant(other, derivatives.length);
    if (other is! Dual || other.derivatives.length != derivatives.length) {
      throw ArgumentError('Dual operands must have the same local dimension.');
    }
    return other;
  }

  Dual _unary(double result, double derivative) {
    final out = Float64List(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      // A constant does not acquire NaNs from an irrelevant singular slope.
      out[i] = derivatives[i] == 0 ? 0 : derivative * derivatives[i];
    }
    return Dual._(result, out);
  }

  Dual operator +(Object other) {
    final b = _coerce(other);
    final out = Float64List(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = derivatives[i] + b.derivatives[i];
    }
    return Dual._(value + b.value, out);
  }

  Dual operator -(Object other) {
    final b = _coerce(other);
    final out = Float64List(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = derivatives[i] - b.derivatives[i];
    }
    return Dual._(value - b.value, out);
  }

  Dual operator -() => _unary(-value, -1);

  Dual operator *(Object other) {
    final b = _coerce(other);
    final out = Float64List(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = derivatives[i] * b.value + value * b.derivatives[i];
    }
    return Dual._(value * b.value, out);
  }

  Dual operator /(Object other) {
    final b = _coerce(other);
    final result = value / b.value;
    final out = Float64List(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = (derivatives[i] - result * b.derivatives[i]) / b.value;
    }
    return Dual._(result, out);
  }

  Dual square() => this * this;
  Dual sqrt() {
    final result = math.sqrt(value);
    return _unary(result, 0.5 / result);
  }

  Dual sin() => _unary(math.sin(value), math.cos(value));
  Dual cos() => _unary(math.cos(value), -math.sin(value));
  Dual exp() {
    final result = math.exp(value);
    return _unary(result, result);
  }

  Dual log() => _unary(math.log(value), 1 / value);
  Dual acos() => _unary(math.acos(value), -1 / math.sqrt(1 - value * value));
  Dual asin() => _unary(math.asin(value), 1 / math.sqrt(1 - value * value));
  Dual atan() => _unary(math.atan(value), 1 / (1 + value * value));

  /// atan2(this, [x]); undefined at the origin, like its geometric angle.
  Dual atan2(Dual x) {
    final b = _coerce(x);
    final out = Float64List(derivatives.length);
    final magnitude = math.max(value.abs(), b.value.abs());
    final sx = b.value / magnitude;
    final sy = value / magnitude;
    final denominator = (sx * sx + sy * sy) * magnitude;
    for (var i = 0; i < out.length; i++) {
      out[i] = (sx * derivatives[i] - sy * b.derivatives[i]) / denominator;
    }
    return Dual._(math.atan2(value, b.value), out);
  }

  Dual pow(double exponent) {
    if (exponent == 0) return Dual.constant(1, derivatives.length);
    if (exponent == 1) return this;
    return _unary(math.pow(value, exponent).toDouble(),
        exponent * math.pow(value, exponent - 1));
  }

  @override
  String toString() => 'Dual($value, $derivatives)';
}

import 'dart:math' as math;
import 'dart:typed_data';

// Residual-only evaluations use dimension zero. The empty storage cannot hold
// mutable coordinates, so it is safe to share across values and expressions.
final _emptyDerivatives = Float64List(0);
Float64List _derivativeStorage(int dimension) =>
    dimension == 0 ? _emptyDerivatives : Float64List(dimension);

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
      Dual._(value.toDouble(), _derivativeStorage(dimension));

  factory Dual.variable(double value, int index, int dimension) {
    if (index < 0 || index >= dimension) {
      throw RangeError.index(index, List.filled(dimension, 0));
    }
    final derivatives = Float64List(dimension)..[index] = 1;
    return Dual._(value, derivatives);
  }

  /// Euclidean norm without squaring unscaled coordinates.
  ///
  /// The derivative is the dot product with the unit direction. Computing it
  /// directly avoids overflowing reciprocal derivatives while scaling very
  /// small coordinates. At the origin this returns the zero subgradient;
  /// callers needing an independent equation for each coordinate should use
  /// those equations rather than a norm residual.
  factory Dual.norm(List<Dual> components) {
    final (scale, scaledLength, dimension) = _normScale(components);
    if (scale == 0) return Dual.constant(0, dimension);
    final out = _derivativeStorage(dimension);
    for (final component in components) {
      final direction = (component.value / scale) / scaledLength;
      for (var i = 0; i < dimension; i++) {
        out[i] += direction * component.derivatives[i];
      }
    }
    return Dual._(scale * scaledLength, out);
  }

  final double value;
  final Float64List derivatives;

  /// Unit direction with analytic tangent derivatives and scale-safe values.
  ///
  /// Unlike division by the raw norm, this also handles finite coordinates
  /// whose combined length exceeds the representable range. The zero vector
  /// has no direction and throws. An unrepresentable derivative remains
  /// non-finite so the geometric solver can report numerical failure.
  static List<Dual> normalized(List<Dual> components) {
    final (scale, scaledLength, dimension) = _normScale(components);
    if (scale == 0) throw StateError('A zero vector has no direction.');
    final direction = [
      for (final component in components)
        (component.value / scale) / scaledLength,
    ];
    final radial = _derivativeStorage(dimension);
    for (var j = 0; j < components.length; j++) {
      for (var i = 0; i < dimension; i++) {
        radial[i] += direction[j] * components[j].derivatives[i];
      }
    }
    return [
      for (var j = 0; j < components.length; j++)
        Dual._(
            direction[j],
            dimension == 0
                ? _emptyDerivatives
                : Float64List.fromList([
                    for (var i = 0; i < dimension; i++)
                      ((components[j].derivatives[i] -
                                  direction[j] * radial[i]) /
                              scaledLength) /
                          scale,
                  ])),
    ];
  }

  static (double, double, int) _normScale(List<Dual> components) {
    if (components.isEmpty) return (0, 0, 0);
    final dimension = components.first.derivatives.length;
    var scale = 0.0;
    for (final component in components) {
      if (component.derivatives.length != dimension) {
        throw ArgumentError('Dual components need one local dimension.');
      }
      if (!component.value.isFinite) {
        throw StateError('A geometric vector must have finite coordinates.');
      }
      scale = math.max(scale, component.value.abs());
    }
    if (scale == 0) return (0, 0, dimension);
    var sum = 0.0;
    for (final component in components) {
      final coordinate = component.value / scale;
      sum += coordinate * coordinate;
    }
    return (scale, math.sqrt(sum), dimension);
  }

  Dual _coerce(Object other) {
    if (other is num) return Dual.constant(other, derivatives.length);
    if (other is! Dual || other.derivatives.length != derivatives.length) {
      throw ArgumentError('Dual operands must have the same local dimension.');
    }
    return other;
  }

  Dual _unary(double result, double derivative) {
    final out = _derivativeStorage(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      // A constant does not acquire NaNs from an irrelevant singular slope.
      out[i] = derivatives[i] == 0 ? 0 : derivative * derivatives[i];
    }
    return Dual._(result, out);
  }

  Dual operator +(Object other) {
    final b = _coerce(other);
    final out = _derivativeStorage(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = derivatives[i] + b.derivatives[i];
    }
    return Dual._(value + b.value, out);
  }

  Dual operator -(Object other) {
    final b = _coerce(other);
    final out = _derivativeStorage(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = derivatives[i] - b.derivatives[i];
    }
    return Dual._(value - b.value, out);
  }

  Dual operator -() => _unary(-value, -1);

  Dual operator *(Object other) {
    final b = _coerce(other);
    final out = _derivativeStorage(derivatives.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = derivatives[i] * b.value + value * b.derivatives[i];
    }
    return Dual._(value * b.value, out);
  }

  Dual operator /(Object other) {
    final b = _coerce(other);
    final result = value / b.value;
    final out = _derivativeStorage(derivatives.length);
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
    final out = _derivativeStorage(derivatives.length);
    final magnitude = math.max(value.abs(), b.value.abs());
    if (magnitude == 0 || !magnitude.isFinite) {
      throw StateError(
          'atan2 requires finite coordinates away from the origin.');
    }
    final sx = b.value / magnitude;
    final sy = value / magnitude;
    final denominator = sx * sx + sy * sy;
    for (var i = 0; i < out.length; i++) {
      // Scale the derivative pair independently. This also handles subnormal
      // derivatives without rounding each weighted term to zero before the
      // final division, and prevents large opposite terms from overflowing.
      final dy = derivatives[i], dx = b.derivatives[i];
      final derivativeScale = math.max(dy.abs(), dx.abs());
      if (derivativeScale == 0) continue;
      final directional =
          (sx * (dy / derivativeScale) - sy * (dx / derivativeScale)) /
              denominator;
      final ratio = derivativeScale / magnitude;
      out[i] = ratio.isInfinite
          ? (directional * derivativeScale) / magnitude
          : ratio == 0
              ? (directional / magnitude) * derivativeScale
              : directional * ratio;
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

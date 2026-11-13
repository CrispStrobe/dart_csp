/// Compact public domain descriptions used by the model and compiled solver.
library;

import 'dart:collection';

/// An immutable, constant-storage list view of the integers in [min]..[max].
///
/// Indexed access, membership, extrema, and length are constant time. Explicit
/// iteration or conversion with `toList()` still visits every value. This view
/// preserves the existing list-shaped modeling API without allocating every
/// member of a declared range.
final class IntRangeDomain extends ListBase<int> {
  factory IntRangeDomain(int min, int max) {
    if (min > max) {
      throw ArgumentError('Empty integer range: $min > $max.');
    }
    final span = max - min;
    final cardinality = span + 1;
    if (span < 0 ||
        cardinality <= 0 ||
        cardinality <= span ||
        (span > 0 && (min + 1 <= min || max - 1 >= max))) {
      throw ArgumentError('Integer range cardinality is not representable.');
    }
    return IntRangeDomain._(min, max, cardinality);
  }

  IntRangeDomain._(this.min, this.max, this._length);

  final int min;
  final int max;
  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) =>
      throw UnsupportedError('Integer domains are immutable.');

  @override
  int get first => min;

  @override
  int get last => max;

  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    return min + index;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Integer domains are immutable.');

  @override
  bool contains(Object? element) =>
      element is num &&
      element >= min &&
      element <= max &&
      element == element.truncate();

  @override
  int indexOf(Object? element, [int start = 0]) {
    if (element is! num || !contains(element)) return -1;
    final index = element.toInt() - min;
    return index >= start ? index : -1;
  }

  @override
  int lastIndexOf(Object? element, [int? start]) {
    if (element is! num || !contains(element)) return -1;
    final index = element.toInt() - min;
    return index <= (start ?? _length - 1) ? index : -1;
  }

  @override
  String toString() =>
      _length <= 32 ? super.toString() : 'IntRangeDomain($min, $max)';
}

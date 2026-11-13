/// Compact range exclusions and exact domain-context explanations for LCG.
part of 'solver.dart';

const int _eagerLcgRangeLimit = 100000;

bool _integerDeclaredDomain(List<dynamic> domain) =>
    domain is IntRangeDomain || domain.every((value) => value is int);

/// An interval with sorted, immutable interior point exclusions. Endpoints are
/// always present, so inherited extrema and arithmetic contraction stay valid.
class _SparseIntervalRep extends _IntervalRep {
  _SparseIntervalRep._(super.min, super.max, this.holes);

  final List<int> holes;

  @override
  int get length => super.length - holes.length;

  int _holesAtMost(int value) {
    var lo = 0, hi = holes.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (holes[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  bool contains(dynamic value) {
    if (!super.contains(value)) return false;
    final position = _holesAtMost(value as int);
    return position == 0 || holes[position - 1] != value;
  }

  @override
  int valueAt(int ordinal) {
    RangeError.checkValidIndex(ordinal, this, 'ordinal', length);
    var lo = _min + ordinal, hi = lo + holes.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      final present = mid - _min + 1 - _holesAtMost(mid);
      if (present >= ordinal + 1) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  @override
  Iterable<dynamic> get values sync* {
    var hole = 0;
    for (var value = _min; value <= _max; value++) {
      if (hole < holes.length && holes[hole] == value) {
        hole++;
      } else {
        yield value;
      }
      if (value == _max) break;
    }
  }

  @override
  Iterable<int> get reversedValues sync* {
    var hole = holes.length - 1;
    for (var value = _max; value >= _min; value--) {
      if (hole >= 0 && holes[hole] == value) {
        hole--;
      } else {
        yield value;
      }
      if (value == _min) break;
    }
  }

  @override
  _DomainRep intersect(int lo, int hi) =>
      _rangeExcluding(max(lo, _min), min(hi, _max), holes);

  @override
  _DomainRep removeValue(int value) =>
      contains(value) ? _rangeExcluding(_min, _max, [...holes, value]) : this;
}

_DomainRep _rangeExcluding(int lo, int hi, Iterable<int> excluded) {
  if (lo > hi) return _IntervalRep(0, -1);
  final holes = excluded
      .where((value) => value >= lo && value <= hi)
      .toSet()
      .toList()
    ..sort();
  var start = 0, end = holes.length;
  while (start < end && holes[start] == lo) {
    if (lo == hi) return _IntervalRep(0, -1);
    lo++;
    start++;
  }
  while (start < end && holes[end - 1] == hi) {
    if (lo == hi) return _IntervalRep(0, -1);
    hi--;
    end--;
  }
  if (start == end) return _IntervalRep(lo, hi);
  return _SparseIntervalRep._(
      lo, hi, List.unmodifiable(holes.sublist(start, end)));
}

/// Exact conjunction describing a compact declared range's current subset.
/// Interior exclusions are explicit point atoms; absent prefixes/suffixes are
/// represented by bounds. Never silently drop an irregular domain's holes.
List<Atom> _compactDomainShape(
    String variable, IntRangeDomain original, _DomainRep current) {
  if (current.isEmpty) {
    // An empty domain is an inconsistent conjunction. This avoids integer
    // underflow/overflow at an original endpoint when describing a conflict.
    return [AtomEq(variable, original.min), AtomNe(variable, original.min)];
  }
  if (current.length == 1) return [AtomEq(variable, current.first as int)];
  final bounds = _numericBoundsOf(current)!;
  final lo = bounds.min as int, hi = bounds.max as int;
  final atoms = <Atom>[
    if (lo > original.min) AtomGe(variable, lo),
    if (hi < original.max) AtomLe(variable, hi),
  ];
  if (current is _SparseIntervalRep) {
    atoms.addAll([for (final hole in current.holes) AtomNe(variable, hole)]);
  } else if (current is! _IntervalRep) {
    if (hi - lo + 1 > _eagerLcgRangeLimit) {
      throw UnsupportedError('LCG cannot compactly explain a large irregular '
          'domain for $variable. Use plain solving or a bounded explicit domain.');
    }
    for (var value = lo; value <= hi; value++) {
      if (!current.contains(value)) atoms.add(AtomNe(variable, value));
      if (value == hi) break;
    }
  }
  return atoms;
}

/// A prune reason describes the newly removed values. Its resulting minimum,
/// maximum, or singleton can additionally rely on earlier removals. Include
/// that previous domain shape rather than over-claiming an absolute bound.
class _DomainContextReason extends ImplicationReason {
  _DomainContextReason(ImplicationReason reason, List<Atom> context)
      : _atoms = List.unmodifiable([...reason.antecedents(), ...context]);

  final List<Atom> _atoms;

  @override
  List<Atom> antecedents() => _atoms;
}

ImplicationReason _withDomainContext(ImplicationReason reason, String variable,
    List<dynamic> original, _DomainRep previous) {
  // An opaque reason cannot become a proof just by adding old-domain facts.
  if (reason is UnknownReason || reason is DecisionReason) return reason;
  if (original is! IntRangeDomain && original.any((value) => value is! int)) {
    return const UnknownReason();
  }
  final context = _domainShapeAntecedents(variable, original, previous);
  return context.isEmpty ? reason : _DomainContextReason(reason, context);
}

void _recordCompactRangeImplications(
    _BacktrackEngine engine,
    String variable,
    IntRangeDomain original,
    _DomainRep previous,
    _DomainRep current,
    int trailIndex,
    ImplicationReason reason) {
  if (current.isEmpty) {
    return; // The constraint-level conflict supplies a reason.
  }
  final currentShape = _compactDomainShape(variable, original, current);
  final oldBounds = _numericBoundsOf(previous)!;
  final newBounds = _numericBoundsOf(current)!;
  final derivedReason =
      _withDomainContext(reason, variable, original, previous);
  final recorded = <Atom>{};
  void record(Atom atom, ImplicationReason proof) {
    if (!recorded.add(atom)) return;
    engine._implicationTrail.add(ImplicationEntry(
      prunedAtom: atom,
      reason: proof,
      trailIndex: trailIndex,
      decisionLevel: engine._decisionLevel,
    ));
  }

  // Preserve an explicitly forced atom, even when a point exclusion moves a
  // range endpoint. Future clause reasons may refer to that exact AtomNe.
  if (reason is ClauseReason && reason.consequence != null) {
    record(reason.consequence!, reason);
  }
  if (previous.length - current.length == 1) {
    if (newBounds.min > oldBounds.min) {
      record(AtomNe(variable, oldBounds.min as int), reason);
    } else if (newBounds.max < oldBounds.max) {
      record(AtomNe(variable, oldBounds.max as int), reason);
    }
  }
  if (previous.length <= _eagerLcgRangeLimit) {
    for (final value in previous.values) {
      if (!current.contains(value)) {
        record(AtomNe(variable, value as int), reason);
      }
    }
  } else {
    for (final atom in currentShape) {
      if (atom is AtomNe && previous.contains(atom.value)) record(atom, reason);
    }
  }
  if (current.length == 1) {
    record(AtomEq(variable, current.first as int), derivedReason);
  }
  if (newBounds.min > oldBounds.min) {
    record(AtomGe(variable, newBounds.min as int), derivedReason);
  }
  if (newBounds.max < oldBounds.max) {
    record(AtomLe(variable, newBounds.max as int), derivedReason);
  }
}

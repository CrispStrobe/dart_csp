import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Test-only [DomainView] backed by an in-memory `Set<int>`. The
/// public [DomainView] contract is narrow on purpose so callers
/// (tests, future LCG components) don't depend on the engine's
/// private `_DomainRep`. This fake exercises every method an atom
/// reads.
class _FakeDomain implements DomainView {
  _FakeDomain(Iterable<int> values) : _values = Set<int>.from(values);

  final Set<int> _values;

  @override
  bool contains(int v) => _values.contains(v);

  @override
  bool get isSingleton => _values.length == 1;

  @override
  bool get isEmpty => _values.isEmpty;

  @override
  int get minValue {
    if (_values.isEmpty) {
      throw StateError('minValue on empty domain');
    }
    return _values.reduce((a, b) => a < b ? a : b);
  }

  @override
  int get maxValue {
    if (_values.isEmpty) {
      throw StateError('maxValue on empty domain');
    }
    return _values.reduce((a, b) => a > b ? a : b);
  }
}

void main() {
  group('Atom construction', () {
    test('AtomEq carries varName + value', () {
      const a = AtomEq('x', 3);
      expect(a.varName, 'x');
      expect(a.value, 3);
      expect(a.toString(), 'x = 3');
    });

    test('AtomNe / AtomLe / AtomGe carry varName + value', () {
      expect(const AtomNe('y', 5).toString(), 'y != 5');
      expect(const AtomLe('z', 7).toString(), 'z <= 7');
      expect(const AtomGe('w', -2).toString(), 'w >= -2');
    });
  });

  group('Atom.negate', () {
    test('AtomEq ↔ AtomNe', () {
      expect(const AtomEq('x', 3).negate(), const AtomNe('x', 3));
      expect(const AtomNe('x', 3).negate(), const AtomEq('x', 3));
    });

    test('AtomLe.negate → AtomGe shifted by 1', () {
      expect(const AtomLe('x', 5).negate(), const AtomGe('x', 6));
    });

    test('AtomGe.negate → AtomLe shifted by -1', () {
      expect(const AtomGe('x', 5).negate(), const AtomLe('x', 4));
    });

    test('double-negation is identity', () {
      const atoms = <Atom>[
        AtomEq('x', 3),
        AtomNe('y', 7),
        AtomLe('z', 0),
        AtomGe('w', -4),
      ];
      for (final a in atoms) {
        expect(a.negate().negate(), a, reason: 'double-neg of $a');
      }
    });
  });

  group('Atom equality and hashing', () {
    test('structural equality across all four subtypes', () {
      expect(const AtomEq('x', 3), const AtomEq('x', 3));
      expect(const AtomNe('x', 3), const AtomNe('x', 3));
      expect(const AtomLe('x', 3), const AtomLe('x', 3));
      expect(const AtomGe('x', 3), const AtomGe('x', 3));
    });

    test('different subtypes never equal', () {
      expect(const AtomEq('x', 3) == const AtomNe('x', 3), isFalse);
      expect(const AtomLe('x', 3) == const AtomGe('x', 3), isFalse);
    });

    test('different varName or value disqualifies equality', () {
      expect(const AtomEq('x', 3) == const AtomEq('y', 3), isFalse);
      expect(const AtomEq('x', 3) == const AtomEq('x', 4), isFalse);
    });

    test('equal atoms share hashCode', () {
      expect(const AtomEq('x', 3).hashCode, const AtomEq('x', 3).hashCode);
      expect(const AtomLe('q', 99).hashCode, const AtomLe('q', 99).hashCode);
    });
  });

  group('Atom.isEntailedBy', () {
    test('AtomEq entailed iff domain is the singleton {value}', () {
      expect(const AtomEq('x', 3).isEntailedBy(_FakeDomain([3])), isTrue);
      expect(const AtomEq('x', 3).isEntailedBy(_FakeDomain([3, 4])), isFalse);
      expect(const AtomEq('x', 3).isEntailedBy(_FakeDomain([4])), isFalse);
      expect(const AtomEq('x', 3).isEntailedBy(_FakeDomain([])), isFalse);
    });

    test('AtomNe entailed iff value has been pruned', () {
      expect(const AtomNe('x', 3).isEntailedBy(_FakeDomain([1, 2, 4])), isTrue);
      expect(
          const AtomNe('x', 3).isEntailedBy(_FakeDomain([1, 2, 3])), isFalse);
      expect(const AtomNe('x', 3).isEntailedBy(_FakeDomain([])), isTrue);
    });

    test('AtomLe entailed iff every surviving value is ≤ bound', () {
      expect(const AtomLe('x', 5).isEntailedBy(_FakeDomain([1, 2, 5])), isTrue);
      expect(
          const AtomLe('x', 5).isEntailedBy(_FakeDomain([1, 2, 6])), isFalse);
      // Tight: max == bound.
      expect(const AtomLe('x', 5).isEntailedBy(_FakeDomain([5])), isTrue);
      // Empty domains are vacuously not entailed (caller must guard).
      expect(const AtomLe('x', 5).isEntailedBy(_FakeDomain([])), isFalse);
    });

    test('AtomGe entailed iff every surviving value is ≥ bound', () {
      expect(const AtomGe('x', 5).isEntailedBy(_FakeDomain([5, 7, 9])), isTrue);
      expect(
          const AtomGe('x', 5).isEntailedBy(_FakeDomain([4, 7, 9])), isFalse);
      expect(const AtomGe('x', 5).isEntailedBy(_FakeDomain([5])), isTrue);
      expect(const AtomGe('x', 5).isEntailedBy(_FakeDomain([])), isFalse);
    });
  });
}

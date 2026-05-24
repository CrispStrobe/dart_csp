// lib/src/builtin_constraints.dart

/// Built-in constraint factory functions for common CSP constraint types.
/// These are much faster than generic lambda functions and provide better
/// error messages and debugging support.
library;

import 'types.dart';

/// Creates a constraint ensuring all variables have different values
///
/// This is one of the most common constraints in CSP problems.
/// Examples: Sudoku rows/columns, N-Queens, graph coloring
///
/// Usage:
/// ```dart
/// final p = Problem();
/// p.addVariables(['A', 'B', 'C'], [1, 2, 3]);
/// p.addConstraint(['A', 'B', 'C'], allDifferent());
/// ```
NaryPredicate allDifferent() => (Map<String, dynamic> assignment) {
      final values = assignment.values.toSet();
      return values.length == assignment.length; // All values must be unique
    };

/// Creates a binary all-different constraint for exactly 2 variables
/// More efficient than the n-ary version for 2 variables
BinaryPredicate allDifferentBinary() => (a, b) => a != b;

/// Creates a constraint ensuring all variables have the same value
///
/// Examples: Ensuring consistent settings across components
///
/// Usage:
/// ```dart
/// p.addConstraint(['X', 'Y', 'Z'], allEqual());
/// ```
NaryPredicate allEqual() => (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return true;

      final firstValue = assignment.values.first;
      return assignment.values.every((value) => value == firstValue);
    };

/// Binary version for exactly 2 variables
BinaryPredicate allEqualBinary() => (a, b) => a == b;

/// Creates a constraint ensuring variables sum to an exact value
///
/// Examples: Magic squares, resource allocation with exact budget
///
/// Usage:
/// ```dart
/// p.addConstraint(['A', 'B', 'C'], exactSum(15));
/// p.addConstraint(['X', 'Y'], exactSum(10, multipliers: [2, 3])); // 2*X + 3*Y = 10
/// ```
NaryPredicate exactSum(num targetSum, {List<num>? multipliers}) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return targetSum == 0;

      num sum = 0;
      var index = 0;

      for (final value in assignment.values) {
        final multiplier = multipliers?[index] ?? 1;
        sum += (value as num) * multiplier;
        index++;
      }

      return sum == targetSum;
    };

/// Creates a constraint ensuring variables sum to at least a minimum value
NaryPredicate minSum(num minimumSum, {List<num>? multipliers}) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return minimumSum <= 0;

      num sum = 0;
      var index = 0;

      for (final value in assignment.values) {
        final multiplier = multipliers?[index] ?? 1;
        sum += (value as num) * multiplier;
        index++;
      }

      return sum >= minimumSum;
    };

/// Creates a constraint ensuring variables sum to at most a maximum value
NaryPredicate maxSum(num maximumSum, {List<num>? multipliers}) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return true;

      num sum = 0;
      var index = 0;

      for (final value in assignment.values) {
        final multiplier = multipliers?[index] ?? 1;
        sum += (value as num) * multiplier;
        index++;
      }

      return sum <= maximumSum;
    };

/// Creates a constraint ensuring variables sum within a range
NaryPredicate sumInRange(num minSum, num maxSum, {List<num>? multipliers}) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return minSum <= 0 && maxSum >= 0;

      num sum = 0;
      var index = 0;

      for (final value in assignment.values) {
        final multiplier = multipliers?[index] ?? 1;
        sum += (value as num) * multiplier;
        index++;
      }

      return sum >= minSum && sum <= maxSum;
    };

// Binary versions of sum constraints for 2-variable optimization
BinaryPredicate exactSumBinary(num targetSum, {List<num>? multipliers}) {
  final m1 = multipliers?[0] ?? 1;
  final m2 = multipliers?[1] ?? 1;
  return (a, b) => ((a! as num) * m1 + (b! as num) * m2) == targetSum;
}

BinaryPredicate minSumBinary(num minimumSum, {List<num>? multipliers}) {
  final m1 = multipliers?[0] ?? 1;
  final m2 = multipliers?[1] ?? 1;
  return (a, b) => ((a! as num) * m1 + (b! as num) * m2) >= minimumSum;
}

BinaryPredicate maxSumBinary(num maximumSum, {List<num>? multipliers}) {
  final m1 = multipliers?[0] ?? 1;
  final m2 = multipliers?[1] ?? 1;
  return (a, b) => ((a! as num) * m1 + (b! as num) * m2) <= maximumSum;
}

BinaryPredicate sumInRangeBinary(num minSum, num maxSum,
    {List<num>? multipliers}) {
  final m1 = multipliers?[0] ?? 1;
  final m2 = multipliers?[1] ?? 1;
  return (a, b) {
    final sum = (a! as num) * m1 + (b! as num) * m2;
    return sum >= minSum && sum <= maxSum;
  };
}

BinaryPredicate exactProductBinary(num targetProduct) =>
    (a, b) => (a! as num) * (b! as num) == targetProduct;

BinaryPredicate minProductBinary(num minimumProduct) =>
    (a, b) => (a! as num) * (b! as num) >= minimumProduct;

BinaryPredicate maxProductBinary(num maximumProduct) =>
    (a, b) => (a! as num) * (b! as num) <= maximumProduct;

/// Creates a constraint ensuring variables multiply to an exact value
NaryPredicate exactProduct(num targetProduct) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return targetProduct == 1;

      num product = 1;
      for (final value in assignment.values) {
        product *= value as num;
      }

      return product == targetProduct;
    };

/// Creates a constraint ensuring variables multiply to at least a minimum
NaryPredicate minProduct(num minimumProduct) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return minimumProduct <= 1;

      num product = 1;
      for (final value in assignment.values) {
        product *= value as num;
      }

      return product >= minimumProduct;
    };

/// Creates a constraint ensuring variables multiply to at most a maximum
NaryPredicate maxProduct(num maximumProduct) =>
    (Map<String, dynamic> assignment) {
      if (assignment.isEmpty) return true;

      num product = 1;
      for (final value in assignment.values) {
        product *= value as num;
      }

      return product <= maximumProduct;
    };

/// Creates a constraint ensuring all variables take values from allowed set
NaryPredicate inSet(Set<dynamic> allowedValues) =>
    (Map<String, dynamic> assignment) =>
        assignment.values.every((value) => allowedValues.contains(value));

/// Creates a constraint ensuring no variables take values from forbidden set
NaryPredicate notInSet(Set<dynamic> forbiddenValues) =>
    (Map<String, dynamic> assignment) =>
        assignment.values.every((value) => !forbiddenValues.contains(value));

// Binary versions of set membership constraints for 2-variable optimization
BinaryPredicate inSetBinary(Set<dynamic> allowedValues) =>
    (a, b) => allowedValues.contains(a) && allowedValues.contains(b);

BinaryPredicate notInSetBinary(Set<dynamic> forbiddenValues) =>
    (a, b) => !forbiddenValues.contains(a) && !forbiddenValues.contains(b);

/// Creates a constraint ensuring at least N variables have values in the set
NaryPredicate someInSet(Set<dynamic> values, int minimumCount) =>
    (Map<String, dynamic> assignment) {
      final count =
          assignment.values.where((value) => values.contains(value)).length;
      return count >= minimumCount;
    };

/// Creates a constraint ensuring at least N variables have values NOT in the set
NaryPredicate someNotInSet(Set<dynamic> values, int minimumCount) =>
    (Map<String, dynamic> assignment) {
      final count =
          assignment.values.where((value) => !values.contains(value)).length;
      return count >= minimumCount;
    };

/// Creates a constraint ensuring variables are in ascending order
NaryPredicate ascendingInOrder(List<String> variableOrder) =>
    (Map<String, dynamic> assignment) {
      for (var i = 1; i < variableOrder.length; i++) {
        final current = assignment[variableOrder[i]];
        final previous = assignment[variableOrder[i - 1]];
        if (current == null || previous == null) return true;
        if ((current as num) < (previous as num)) {
          return false;
        }
      }
      return true;
    };

/// Creates a constraint ensuring variables are in strictly ascending order
NaryPredicate strictlyAscendingInOrder(List<String> variableOrder) =>
    (Map<String, dynamic> assignment) {
      for (var i = 1; i < variableOrder.length; i++) {
        final current = assignment[variableOrder[i]];
        final previous = assignment[variableOrder[i - 1]];
        if (current == null || previous == null) return true;
        if ((current as num) <= (previous as num)) {
          return false;
        }
      }
      return true;
    };

/// Creates a constraint ensuring variables are in descending order
NaryPredicate descendingInOrder(List<String> variableOrder) =>
    (Map<String, dynamic> assignment) {
      for (var i = 1; i < variableOrder.length; i++) {
        final current = assignment[variableOrder[i]];
        final previous = assignment[variableOrder[i - 1]];
        if (current == null || previous == null) return true;
        if ((current as num) > (previous as num)) {
          return false;
        }
      }
      return true;
    };

// Binary versions of ordering constraints for 2-variable optimization
BinaryPredicate ascendingBinary() => (a, b) => (a! as num) <= (b! as num);

BinaryPredicate strictlyAscendingBinary() =>
    (a, b) => (a! as num) < (b! as num);

BinaryPredicate descendingBinary() => (a, b) => (a! as num) >= (b! as num);

/// Lexicographic ≤ between two equal-length sequences of variables.
///
/// Given two ordered variable lists `left = [l1, l2, ..., ln]` and
/// `right = [r1, r2, ..., rn]`, the constraint accepts an assignment
/// iff `(l1, l2, ..., ln) ≤lex (r1, r2, ..., rn)` — that is, there
/// exists some position `k` (possibly `k = n+1`, meaning all positions
/// equal) such that `li == ri` for all `i < k` and either `k == n+1`
/// or `lk < rk`.
///
/// Standard symmetry-breaking primitive. Use it to forbid one of every
/// pair of solutions that differ only by a swap of two
/// indistinguishable rows / workers / colors / queens:
///
/// ```dart
/// // Two interchangeable workers A and B: keep the lex-smaller one.
/// p.addConstraint([...interleaved...], lexLeq(['A1','A2'], ['B1','B2']));
/// ```
///
/// Values are compared with `Comparable.compareTo`, so the variables'
/// domains must be `Comparable` (the built-in `int`, `String`, `double`,
/// etc. all are).
///
/// The predicate evaluates lazily: a partial assignment is treated as
/// "not yet violated" — returns true unless a definitive prefix
/// comparison resolves to `>`. Soundness is therefore preserved under
/// backtracking; the propagator never accepts an infeasible assignment
/// but may take some search to discover one.
NaryPredicate lexLeq(List<String> left, List<String> right) {
  if (left.length != right.length) {
    throw ArgumentError(
        'lexLeq requires equal-length sequences (got ${left.length} and ${right.length}).');
  }
  final n = left.length;
  return (Map<String, dynamic> assignment) {
    for (var i = 0; i < n; i++) {
      final l = assignment[left[i]];
      final r = assignment[right[i]];
      if (l == null || r == null) return true; // not yet decided
      final cmp = (l as Comparable).compareTo(r);
      if (cmp < 0) return true; // strictly smaller here, rest free
      if (cmp > 0) return false; // strictly greater here, violation
      // equal at i, continue to next position
    }
    // All positions equal → l == r, which satisfies ≤.
    return true;
  };
}

/// Strict lexicographic <. See [lexLeq].
NaryPredicate lexLt(List<String> left, List<String> right) {
  if (left.length != right.length) {
    throw ArgumentError(
        'lexLt requires equal-length sequences (got ${left.length} and ${right.length}).');
  }
  final n = left.length;
  return (Map<String, dynamic> assignment) {
    var allDecided = true;
    for (var i = 0; i < n; i++) {
      final l = assignment[left[i]];
      final r = assignment[right[i]];
      if (l == null || r == null) {
        allDecided = false;
        // Cannot conclude violation if some prefix var is unassigned;
        // optimistically return true and let downstream catch it.
        return true;
      }
      final cmp = (l as Comparable).compareTo(r);
      if (cmp < 0) return true; // strict less somewhere → ok
      if (cmp > 0) return false;
    }
    // All decided and all positions equal → not strictly less.
    return !allDecided;
  };
}

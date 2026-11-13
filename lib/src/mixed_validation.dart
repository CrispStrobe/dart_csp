/// Independent point checks for the mixed interval/finite-domain engine.
library;

import 'dart:math' as math;

import 'types.dart';

/// Validate model-level controls before the search starts.
void validateMixedOptions(CspProblem problem) {
  void tolerance(MixedTolerance value) {
    if (!value.absolute.isFinite ||
        value.absolute < 0 ||
        !value.relative.isFinite ||
        value.relative < 0) {
      throw ArgumentError('Mixed residual tolerances must be finite and '
          'nonnegative.');
    }
  }

  final options = problem.floatValidation;
  if (options?.defaultTolerance != null) {
    tolerance(options!.defaultTolerance!);
  }
  for (final value in options?.byLabel.values ?? const <MixedTolerance>[]) {
    tolerance(value);
  }

  // Keep the pure finite-domain setup path free of expression-index work.
  if (problem.floatAuxiliaries.isEmpty) return;

  final outputs = <String>{};
  for (final definition in problem.floatAuxiliaries) {
    if (!problem.floatVariables.containsKey(definition.output) ||
        !outputs.add(definition.output)) {
      throw ArgumentError('Generated variable ${definition.output} must have '
          'one definition and a continuous domain.');
    }
    if (!definition.constant.isFinite ||
        definition.terms.values.any((value) => !value.isFinite)) {
      throw ArgumentError('Generated expression coefficients must be finite.');
    }
  }
  final available = <String>{
    ...problem.variables.keys,
    ...problem.floatVariables.keys.where((name) => !outputs.contains(name)),
  };
  for (final definition in problem.floatAuxiliaries) {
    for (final input in definition.dependencies) {
      if (!available.contains(input)) {
        throw ArgumentError('Generated variable ${definition.output} depends '
            'on unknown, cyclic, or later generated variable $input.');
      }
    }
    available.add(definition.output);
  }
}

/// Re-evaluate generated expressions and check original model constraints.
///
/// A rejected point is not evidence that the enclosing interval is infeasible.
/// In particular callers must not learn a conflict or cut away that interval
/// solely because this check fails. No propagated auxiliary midpoint is used
/// in the evaluation of a generated expression.
MixedCandidateValidation validateMixedCandidate(
    CspProblem problem, Map<String, dynamic> raw,
    {bool precisionLimited = false}) {
  final values = Map<String, dynamic>.of(raw);
  final residuals = <MixedResidual>[];

  MixedCandidateValidation failure(String message) => MixedCandidateValidation(
      accepted: false,
      numericalFailure: true,
      precisionLimited: precisionLimited,
      candidate: values,
      residuals: residuals,
      message: message);

  for (final entry in values.entries) {
    if (entry.value is num && !(entry.value as num).isFinite) {
      return failure('Candidate ${entry.key} is not finite.');
    }
  }
  for (final name in problem.floatVariables.keys) {
    if (values[name] is! num) {
      return failure('Continuous variable $name has no numeric candidate.');
    }
  }
  for (final entry in problem.variables.entries) {
    if (!values.containsKey(entry.key) ||
        !entry.value.contains(values[entry.key])) {
      return failure('Candidate ${entry.key} is outside its finite domain.');
    }
  }

  for (final definition in problem.floatAuxiliaries) {
    double value;
    if (definition.isProduct) {
      final a = values[definition.left], b = values[definition.right];
      if (a is! num || b is! num) {
        return failure('Generated product ${definition.output} has a '
            'non-numeric input.');
      }
      value = a.toDouble() * b.toDouble();
    } else {
      final terms = <double>[definition.constant];
      for (final term in definition.terms.entries) {
        final input = values[term.key];
        if (input is! num) {
          return failure('Generated expression ${definition.output} has '
              'a non-numeric input ${term.key}.');
        }
        terms.add(term.value * input.toDouble());
      }
      value = _sum(terms);
    }
    if (!value.isFinite) {
      return failure(
          'Generated expression ${definition.output} is not finite.');
    }
    values[definition.output] = value;
  }

  // Declared domains remain hard constraints, including explicitly restricted
  // product outputs. The recomputed value need not equal the midpoint of a
  // contracted auxiliary interval: the original equations determine it.
  for (final entry in problem.floatVariables.entries) {
    final value = (values[entry.key] as num).toDouble();
    final interval = entry.value;
    final violation = value < interval.lo
        ? interval.lo - value
        : value > interval.hi
            ? value - interval.hi
            : 0.0;
    if (violation > 0) {
      residuals.add(MixedResidual(
          constraint: 'domain:${entry.key}',
          kind: 'domain',
          residual: violation,
          violation: violation,
          tolerance: 0));
    }
  }

  final fallback = MixedTolerance(
      absolute: problem.floatEpsilon, relative: problem.floatEpsilon);
  MixedTolerance tolerance(String? label) =>
      problem.floatValidation?.byLabel[label] ??
      problem.floatValidation?.defaultTolerance ??
      fallback;

  bool addResidual(int index, NaryConstraint constraint, double lhs, double rhs,
      double signed, LinearOp op, String kind) {
    final tolerances = tolerance(constraint.label);
    final allowed = tolerances.absolute +
        tolerances.relative * math.max(lhs.abs(), rhs.abs());
    if (!lhs.isFinite ||
        !rhs.isFinite ||
        !signed.isFinite ||
        !allowed.isFinite) {
      return false;
    }
    final violation = switch (op) {
      LinearOp.eq => signed.abs(),
      LinearOp.leq => math.max(0.0, signed),
      LinearOp.geq => math.max(0.0, -signed),
    };
    residuals.add(MixedResidual(
        constraint: 'nary:$index',
        kind: kind,
        label: constraint.label,
        residual: signed,
        violation: violation,
        tolerance: allowed));
    return true;
  }

  for (var i = 0; i < problem.naryConstraints.length; i++) {
    final constraint = problem.naryConstraints[i];
    final linear = constraint.floatLinearSpec;
    if (linear != null) {
      final terms = <double>[];
      for (var j = 0; j < constraint.vars.length; j++) {
        final input = values[constraint.vars[j]];
        if (input is! num) {
          return failure('Linear constraint $i has a non-numeric input.');
        }
        terms.add(linear.coeffs[j].toDouble() * input.toDouble());
      }
      final rhs = linear.bound.toDouble();
      final lhs = _sum(terms);
      // Include the right side in compensated evaluation as well: computing
      // lhs first can discard a small residual beside large cancelling terms.
      final signed = _sum(<double>[...terms, -rhs]);
      if (!addResidual(i, constraint, lhs, rhs, signed, linear.op, 'linear')) {
        return failure('Linear constraint $i has non-finite arithmetic.');
      }
    } else if (constraint.floatProduct) {
      final p = values[constraint.vars[0]];
      final a = values[constraint.vars[1]];
      final b = values[constraint.vars[2]];
      if (p is! num || a is! num || b is! num) {
        return failure('Product constraint $i has a non-numeric input.');
      }
      final lhs = p.toDouble(), rhs = a.toDouble() * b.toDouble();
      if (!addResidual(
          i, constraint, lhs, rhs, lhs - rhs, LinearOp.eq, 'product')) {
        return failure('Product constraint $i has non-finite arithmetic.');
      }
    } else {
      // Discrete predicates retain exact semantics. Never relax an integer or
      // Boolean relation using the real-valued residual tolerance.
      final scope = <String, dynamic>{
        for (final name in constraint.vars) name: values[name],
      };
      if (!constraint.predicate(scope)) {
        residuals.add(MixedResidual(
            constraint: 'nary:$i',
            kind: constraint.coarseKind,
            label: constraint.label,
            residual: 1,
            violation: 1,
            tolerance: 0));
      }
    }
  }
  for (var i = 0; i < problem.constraints.length; i++) {
    final constraint = problem.constraints[i];
    if (!constraint.predicate(
        values[constraint.head], values[constraint.tail])) {
      residuals.add(MixedResidual(
          constraint: 'binary:$i',
          kind: 'binary',
          label: constraint.label,
          residual: 1,
          violation: 1,
          tolerance: 0));
    }
  }
  final accepted = residuals.every((residual) => residual.isSatisfied);
  return MixedCandidateValidation(
      accepted: accepted,
      candidate: values,
      residuals: residuals,
      precisionLimited: precisionLimited,
      message: accepted
          ? null
          : 'The candidate fails an original constraint; '
              'the enclosing box has not been proved infeasible.');
}

// Neumaier summation retains small terms when larger terms cancel. It is a
// point evaluation, not a directed-rounding or interval-certification claim.
double _sum(Iterable<double> terms) {
  var sum = 0.0, compensation = 0.0;
  for (final value in terms) {
    final next = sum + value;
    compensation +=
        sum.abs() >= value.abs() ? (sum - next) + value : (value - next) + sum;
    sum = next;
  }
  return sum + compensation;
}

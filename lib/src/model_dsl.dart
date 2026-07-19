// A typed, operator-overloading modelling layer over [Problem].
//
// The base API models constraints either as strings (`'x + 2*y <= z'`) or as
// raw predicate lambdas. This layer adds a third, type-safe option that reads
// like arithmetic:
//
// ```dart
// final m = Model();
// final x = m.intVar('x', 0, 10);
// final y = m.intVar('y', 0, 10);
// (x + 2 * y).le(12);   // x + 2y <= 12
// x.ne(y);              // x != y
// x.eq(5);              // x == 5
// final sol = await m.problem.getSolution();
// ```
//
// It is a thin, engine-free layer: every relation lowers to the existing
// linear-constraint helpers on [Problem] (`addLinearEquals` / `addLinearLeq`
// / `addLinearGeq`) or, for `!=`, to a small predicate. There is no new
// propagator and no change to the solver.

import 'problem.dart';
import 'types.dart';

/// A linear expression `Σ cᵢ·xᵢ + k` over a single [Model]'s integer
/// variables.
///
/// Build one with the arithmetic operators — `+`, `-`, unary `-`, and `*`
/// by an integer scalar — then turn it into a posted constraint with one of
/// the relational methods ([le], [lt], [ge], [gt], [eq], [ne]). The relation
/// is posted to the model immediately; the methods return `void`.
///
/// Scalars must appear on the right of `*` (`x * 2`, not `2 * x`): Dart
/// resolves `2 * x` as `int.*` and cannot dispatch to this class. Use
/// [scaled] if you prefer a named form.
class LinearExpr {
  LinearExpr._(this._model, this._terms, this._constant);

  final Model _model;

  /// Variable name → coefficient. Never contains a zero coefficient.
  final Map<String, num> _terms;

  /// The additive constant `k`.
  final num _constant;

  /// Coerces an operand — a [LinearExpr], an [IntVar], or a [num] — into a
  /// [LinearExpr] belonging to the same model.
  LinearExpr _coerce(Object other) {
    if (other is LinearExpr) {
      if (!identical(other._model, _model)) {
        throw ArgumentError(
            'Cannot combine expressions from two different Models.');
      }
      return other;
    }
    if (other is num) return LinearExpr._(_model, const {}, other);
    throw ArgumentError(
        'Expected a LinearExpr, IntVar, or num, got ${other.runtimeType}.');
  }

  LinearExpr _combine(Object other, {required bool subtract}) {
    final o = _coerce(other);
    final terms = Map<String, num>.from(_terms);
    o._terms.forEach((v, c) {
      final delta = subtract ? -c : c;
      final next = (terms[v] ?? 0) + delta;
      if (next == 0) {
        terms.remove(v);
      } else {
        terms[v] = next;
      }
    });
    final k = subtract ? _constant - o._constant : _constant + o._constant;
    return LinearExpr._(_model, terms, k);
  }

  /// `this + other`, where `other` is a [LinearExpr], [IntVar], or [num].
  LinearExpr operator +(Object other) => _combine(other, subtract: false);

  /// `this - other`, where `other` is a [LinearExpr], [IntVar], or [num].
  LinearExpr operator -(Object other) => _combine(other, subtract: true);

  /// Unary negation: `-this`.
  LinearExpr operator -() => scaled(-1);

  /// `this * k` for an integer scalar `k`.
  LinearExpr operator *(num k) => scaled(k);

  /// Named form of `this * k`; also lets a scalar multiply read
  /// left-to-right when operator syntax is awkward.
  LinearExpr scaled(num k) {
    if (k == 0) return LinearExpr._(_model, const {}, 0);
    return LinearExpr._(
      _model,
      {for (final e in _terms.entries) e.key: e.value * k},
      _constant * k,
    );
  }

  // --- Relations -----------------------------------------------------------
  //
  // Each moves everything to the left: `this {op} other` becomes
  // `(this - other) {op} 0`, i.e. `Σ cᵢ·xᵢ {op} -k`. The variable/coefficient
  // lists and the bound `-k` are then handed to the matching Problem helper.

  /// Posts `this == other`.
  void eq(Object other) => _postLinear(other, _Rel.eq);

  /// Posts `this != other`.
  void ne(Object other) => _postLinear(other, _Rel.ne);

  /// Posts `this <= other`.
  void le(Object other) => _postLinear(other, _Rel.le);

  /// Posts `this < other` (integer semantics: `<= other - 1`).
  void lt(Object other) => _postLinear(other, _Rel.lt);

  /// Posts `this >= other`.
  void ge(Object other) => _postLinear(other, _Rel.ge);

  /// Posts `this > other` (integer semantics: `>= other + 1`).
  void gt(Object other) => _postLinear(other, _Rel.gt);

  void _postLinear(Object other, _Rel rel) {
    final diff = _combine(other, subtract: true);
    final vars = diff._terms.keys.toList();
    final coeffs = [for (final v in vars) diff._terms[v]!];
    // `Σ cᵢ·xᵢ + k {rel} 0`  ⇒  `Σ cᵢ·xᵢ {rel} -k`.
    final bound = -diff._constant;
    final p = _model.problem;

    if (vars.isEmpty) {
      // Both sides reduced to constants. `bound` is `-k`; the relation is
      // `0 {rel} bound`. If it already holds it is a no-op; if not the model
      // as written is contradictory, which is a modelling bug rather than a
      // legitimately-infeasible instance.
      final ok = switch (rel) {
        _Rel.eq => 0 == bound,
        _Rel.ne => 0 != bound,
        _Rel.le => 0 <= bound,
        _Rel.lt => 0 <= bound - 1,
        _Rel.ge => 0 >= bound,
        _Rel.gt => 0 >= bound + 1,
      };
      if (!ok) {
        throw ArgumentError(
            'Relation is unsatisfiable as written (reduces to a false '
            'constant relation). Check for cancelling terms.');
      }
      return;
    }

    switch (rel) {
      case _Rel.eq:
        p.addLinearEquals(vars, coeffs, bound);
      case _Rel.le:
        p.addLinearLeq(vars, coeffs, bound);
      case _Rel.ge:
        p.addLinearGeq(vars, coeffs, bound);
      case _Rel.lt:
        // Integer strict: Σ ≤ bound - 1.
        p.addLinearLeq(vars, coeffs, bound - 1);
      case _Rel.gt:
        // Integer strict: Σ ≥ bound + 1.
        p.addLinearGeq(vars, coeffs, bound + 1);
      case _Rel.ne:
        _postLinearNe(p, vars, coeffs, bound);
    }
  }

  /// `!=` has no linear primitive on [Problem], so it lowers to a predicate.
  /// [Problem.addConstraint] wants a [BinaryPredicate] for exactly two
  /// variables and a [NaryPredicate] otherwise, so the arities are split.
  static void _postLinearNe(
      Problem p, List<String> vars, List<num> coeffs, num bound) {
    if (vars.length == 2) {
      final c0 = coeffs[0];
      final c1 = coeffs[1];
      p.addConstraint<BinaryPredicate>(
        vars,
        (a, b) => c0 * (a as num) + c1 * (b as num) != bound,
      );
    } else {
      p.addConstraint<NaryPredicate>(vars, (assignment) {
        num sum = 0;
        for (var i = 0; i < vars.length; i++) {
          sum += coeffs[i] * (assignment[vars[i]] as num);
        }
        return sum != bound;
      });
    }
  }

  /// Sum of [exprs] (a fold of `+`). Throws if [exprs] is empty, since there
  /// is no model to attach a zero to.
  static LinearExpr sum(Iterable<LinearExpr> exprs) {
    final it = exprs.iterator;
    if (!it.moveNext()) {
      throw ArgumentError('LinearExpr.sum requires a non-empty iterable.');
    }
    var acc = it.current;
    while (it.moveNext()) {
      acc = acc + it.current;
    }
    return acc;
  }

  @override
  String toString() {
    final parts = <String>[
      for (final e in _terms.entries) '${e.value}·${e.key}',
    ];
    if (_constant != 0 || parts.isEmpty) parts.add('$_constant');
    return parts.join(' + ');
  }
}

/// A typed integer decision variable — a degenerate [LinearExpr] with a
/// single term of coefficient 1. Created via [Model.intVar].
class IntVar extends LinearExpr {
  IntVar._(Model model, this.name) : super._(model, {name: 1}, 0);

  /// The variable's name in the underlying [Problem].
  final String name;

  @override
  String toString() => name;
}

/// A lightweight modelling front-end that pairs a [Problem] with typed
/// variable creation. All solving still goes through [problem]; this only
/// changes how the model is *expressed*.
///
/// ```dart
/// final m = Model();
/// final xs = m.intVarList(['a', 'b', 'c'], 1, 9);
/// LinearExpr.sum(xs).eq(15);
/// final sol = await m.problem.getSolution();
/// ```
class Model {
  /// Wraps an existing [Problem], or creates a fresh one.
  Model([Problem? problem]) : problem = problem ?? Problem();

  /// The underlying problem. Post non-DSL constraints and run solves here.
  final Problem problem;

  /// Declares an integer variable over the inclusive range `[min, max]`.
  IntVar intVar(String name, int min, int max) {
    problem.addRangeVariable(name, min, max);
    return IntVar._(this, name);
  }

  /// Declares an integer variable whose domain is exactly [values].
  IntVar intVarWithValues(String name, List<int> values) {
    problem.addVariable(name, values);
    return IntVar._(this, name);
  }

  /// Declares several integer variables sharing the range `[min, max]`.
  List<IntVar> intVarList(List<String> names, int min, int max) =>
      [for (final n in names) intVar(n, min, max)];

  /// A reference to an already-declared variable, so DSL expressions can mix
  /// with variables added directly on [problem].
  IntVar ref(String name) {
    if (!problem.variables.containsKey(name)) {
      throw ArgumentError("No variable named '$name' has been declared.");
    }
    return IntVar._(this, name);
  }
}

enum _Rel { eq, ne, le, lt, ge, gt }

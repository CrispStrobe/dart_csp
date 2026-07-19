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
// Continuous variables join the same expressions, so a mixed model reads the
// same way — and `*` between two expressions builds a product, naming the
// auxiliary variable for you:
//
// ```dart
// final m = Model();
// final n = m.intVar('n', 1, 20);
// final price = m.realVar('price', 0, 100);
// (n * 2 + price * 1.5).le(40);   // mixed linear
// (price * price).eq(2);          // non-linear, via an auto-named aux
// ```
//
// It is a thin, engine-free layer: every relation lowers to the existing
// helpers on [Problem] (`addLinearEquals` / `addLinearLeq` / `addLinearGeq`,
// `addFloatProduct`) or, for `!=`, to a small predicate. There is no new
// propagator and no change to the solver.

import 'continuous.dart' show Interval;
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

  /// `this * other`.
  ///
  /// A scalar scales the expression linearly. Multiplying by another
  /// expression is **non-linear**: it lowers to `Problem.addFloatProduct`
  /// against a freshly-named auxiliary variable, which this returns as a
  /// single term. At least one operand must involve a continuous
  /// variable — the product of two enumerated expressions has no
  /// propagator here (see [Model.realVar]).
  LinearExpr operator *(Object other) {
    if (other is num) return scaled(other);
    final o = _coerce(other);
    // A constant operand is a scalar multiply in disguise.
    if (_terms.isEmpty) return o.scaled(_constant);
    if (o._terms.isEmpty) return scaled(o._constant);
    return _model._product(this, o);
  }

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

    // `!=` and the strict relations are defined here in terms of the
    // integer successor (`< b` means `<= b - 1`), which the reals do not
    // have — and `!=` additionally lowers to a value-enumerating
    // predicate, which cannot see a continuous domain at all. Rather than
    // silently reinterpret either one, say so.
    if (vars.any(p.isFloatVariable)) {
      final continuous = vars.where(p.isFloatVariable).join(', ');
      switch (rel) {
        case _Rel.ne:
          throw ArgumentError(
              'A `!=` relation cannot mention a continuous variable '
              '($continuous): it lowers to a predicate over enumerated '
              'values. Model the exclusion with a pair of bounds instead.');
        case _Rel.lt:
        case _Rel.gt:
          throw ArgumentError(
              'Strict `<` / `>` are integer relations (they mean `<= b - 1` '
              'and `>= b + 1`) and have no meaning over the reals in '
              '($continuous). Use le / ge — an interval solver cannot '
              'represent an open bound anyway.');
        case _Rel.eq:
        case _Rel.le:
        case _Rel.ge:
          break;
      }
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

/// A typed **continuous** decision variable — a degenerate [LinearExpr]
/// with a single term of coefficient 1. Created via [Model.realVar].
class RealVar extends LinearExpr {
  RealVar._(Model model, this.name) : super._(model, {name: 1}, 0);

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

  /// Declares a **continuous** (real-valued) variable over the closed
  /// interval `[lo, hi]`.
  ///
  /// It joins the same expressions as [intVar], so a mixed model reads
  /// like ordinary arithmetic:
  ///
  /// ```dart
  /// final n = m.intVar('units', 0, 20);
  /// final price = m.realVar('price', 0, 100);
  /// (n * 2 + price * 1.5).le(40);
  /// ```
  ///
  /// Two relations behave differently once a continuous variable is in
  /// scope, and both throw rather than guess: [LinearExpr.ne] (which
  /// lowers to a value-enumerating predicate) and the strict
  /// [LinearExpr.lt] / [LinearExpr.gt] (whose integer reading, `≤ b - 1`,
  /// is meaningless over the reals). Use [LinearExpr.le] / [LinearExpr.ge]
  /// instead.
  RealVar realVar(String name, double lo, double hi) {
    problem.addFloatVariable(name, lo, hi);
    return RealVar._(this, name);
  }

  /// Declares several continuous variables sharing the interval `[lo, hi]`.
  List<RealVar> realVarList(List<String> names, double lo, double hi) =>
      [for (final n in names) realVar(n, lo, hi)];

  /// A reference to an already-declared variable, so DSL expressions can mix
  /// with variables added directly on [problem]. Returns a [RealVar] when
  /// the name was declared continuous.
  LinearExpr ref(String name) {
    if (problem.isFloatVariable(name)) return RealVar._(this, name);
    if (!problem.variables.containsKey(name)) {
      throw ArgumentError("No variable named '$name' has been declared.");
    }
    return IntVar._(this, name);
  }

  /// Counter for the auxiliary variables introduced by expression
  /// products. The `__mul` prefix keeps them clear of user names.
  int _auxCounter = 0;

  /// The interval a linear expression can span, from its variables'
  /// declared bounds. Used to size the auxiliary variables below — an
  /// auxiliary needs a domain wide enough to hold every value the
  /// expression can take, or it would silently constrain the model.
  Interval _boundsOf(LinearExpr e) {
    var lo = e._constant.toDouble();
    var hi = lo;
    e._terms.forEach((name, coeff) {
      final c = coeff.toDouble();
      final b = _varBounds(name);
      lo += c >= 0 ? c * b.lo : c * b.hi;
      hi += c >= 0 ? c * b.hi : c * b.lo;
    });
    return Interval(lo, hi);
  }

  Interval _varBounds(String name) {
    final f = problem.floatVariables[name];
    if (f != null) return f;
    final dom = problem.variables[name];
    if (dom == null) {
      throw ArgumentError("No variable named '$name' has been declared.");
    }
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final v in dom) {
      if (v is! num) {
        throw ArgumentError("Variable '$name' has a non-numeric domain and "
            'cannot take part in arithmetic.');
      }
      final d = v.toDouble();
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    return Interval(lo, hi);
  }

  /// Reduces [e] to a single variable name: itself when it already is one
  /// with coefficient 1 and no constant, otherwise a fresh continuous
  /// auxiliary pinned to it by an equality.
  String _asVariable(LinearExpr e) {
    if (e._constant == 0 && e._terms.length == 1) {
      final only = e._terms.entries.first;
      if (only.value == 1) return only.key;
    }
    final b = _boundsOf(e);
    final aux = '__mul${_auxCounter++}';
    problem.addFloatVariable(aux, b.lo, b.hi);
    // aux == e, i.e. aux - Σcᵢxᵢ = e.constant
    final terms = <String, num>{aux: 1};
    e._terms.forEach((v, c) => terms[v] = (terms[v] ?? 0) - c);
    final vars = terms.keys.toList();
    problem.addLinearEquals(
        vars, [for (final v in vars) terms[v]!], e._constant);
    return aux;
  }

  /// Lowers `a * b` to a fresh auxiliary `p` with `p == a · b` posted,
  /// and returns `p` as a single-term expression.
  LinearExpr _product(LinearExpr a, LinearExpr b) {
    final an = _asVariable(a);
    final bn = _asVariable(b);
    if (!problem.isFloatVariable(an) && !problem.isFloatVariable(bn)) {
      throw ArgumentError(
          'Multiplying two enumerated expressions is not supported: the '
          'product propagator is an interval one, so at least one operand '
          'must involve a continuous variable (Model.realVar). Got '
          "'$an' * '$bn'.");
    }
    final ab = _varBounds(an), bb = _varBounds(bn);
    final corners = [
      ab.lo * bb.lo,
      ab.lo * bb.hi,
      ab.hi * bb.lo,
      ab.hi * bb.hi,
    ];
    final p = '__mul${_auxCounter++}';
    problem.addFloatVariable(p, corners.reduce((x, y) => x < y ? x : y),
        corners.reduce((x, y) => x > y ? x : y));
    // An implementation detail of the decomposition, not something the
    // caller modelled — keep it out of the reported solution.
    problem.hideFromSolutions(p);
    problem.addFloatProduct(p, an, bn);
    return RealVar._(this, p);
  }

  /// Minimizes [objective], which may be any expression — including a
  /// product, so `m.minimize(w * h)` works directly.
  ///
  /// The expression is materialized to a single variable if it is not
  /// one already, and that variable is reported in the result even
  /// though decomposition auxiliaries are otherwise hidden.
  Future<dynamic> minimize(LinearExpr objective) =>
      problem.minimize(_asVariable(objective));

  /// Maximizes [objective]. See [minimize].
  Future<dynamic> maximize(LinearExpr objective) =>
      problem.maximize(_asVariable(objective));
}

enum _Rel { eq, ne, le, lt, ge, gt }

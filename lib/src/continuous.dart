// Continuous (real / float) variables — an isolated interval branch-and-prune
// solver.
//
// The integer engine enumerates domains, so it cannot model continuous
// quantities (fractional durations, geometric placement, prices, rates). This
// module adds them without touching that engine: a self-contained solver over
// closed real intervals that prunes with HC4-style bound propagation and
// branches by bisection until every variable's interval is narrower than a
// tolerance.
//
// Scope & soundness, stated honestly. This is a *first slice* of the
// float-variables roadmap item:
//   * Constraints supported: linear (`Σ cᵢ·xᵢ {≤,≥,=} b`), which the DSL
//     builds from `+`, `-`, unary `-`, and `* scalar`. Non-linear terms
//     (`x * y`, `x²`) are not yet handled.
//   * It does not integrate with the integer engine — a problem is either
//     all-integer (use `Problem`) or all-continuous (use `ContinuousModel`).
//   * Arithmetic uses plain IEEE-754 doubles, not outward-directed rounding.
//     A box whose every side is ≤ `epsilon` wide and survives propagation is
//     reported as a solution; a rigorously *verified* enclosure (outward
//     rounding so floating-point error can never drop a real solution) is
//     future hardening. Treat a returned box as a high-precision witness, not
//     a formal proof.
//
// See PLAN.md for the remaining work (non-linear propagators, int/float
// integration, verified rounding).

import 'dart:math' as math;

/// A closed real interval `[lo, hi]`. Empty when `lo > hi`.
class Interval {
  const Interval(this.lo, this.hi);

  /// The degenerate interval `[v, v]`.
  const Interval.point(double v)
      : lo = v,
        hi = v;

  final double lo;
  final double hi;

  bool get isEmpty => lo > hi;
  double get width => hi - lo;

  /// The midpoint; well-defined only for a finite interval.
  double get mid => lo + (hi - lo) / 2;

  bool contains(double v) => v >= lo && v <= hi;

  /// Intersection; may be empty.
  Interval intersect(Interval o) =>
      Interval(math.max(lo, o.lo), math.min(hi, o.hi));

  Interval operator +(Interval o) => Interval(lo + o.lo, hi + o.hi);
  Interval operator -(Interval o) => Interval(lo - o.hi, hi - o.lo);

  /// Interval product: the min/max over the four endpoint products.
  Interval operator *(Interval o) {
    final products = [lo * o.lo, lo * o.hi, hi * o.lo, hi * o.hi];
    return Interval(products.reduce(math.min), products.reduce(math.max));
  }

  /// Interval division `this / d`, used to back-propagate a product
  /// constraint. When [d] straddles zero the exact result is a pair of
  /// semi-infinite rays; we return the sound *hull* `(-∞, ∞)` instead —
  /// simpler, still sound (it just yields no tightening until [d] no longer
  /// contains zero), at a modest precision cost.
  Interval divide(Interval d) {
    if (d.lo <= 0 && 0 <= d.hi) {
      return const Interval(double.negativeInfinity, double.infinity);
    }
    final quotients = [lo / d.lo, lo / d.hi, hi / d.lo, hi / d.hi];
    return Interval(quotients.reduce(math.min), quotients.reduce(math.max));
  }

  /// Scale by a real constant, preserving orientation.
  Interval scale(double c) =>
      c >= 0 ? Interval(lo * c, hi * c) : Interval(hi * c, lo * c);

  @override
  String toString() => '[${lo.toStringAsFixed(6)}, ${hi.toStringAsFixed(6)}]';
}

/// The relation of a continuous linear constraint.
enum ContinuousOp { le, ge, eq }

/// A linear expression `Σ cᵢ·xᵢ + k` over a [ContinuousModel]'s variables.
/// Build with the arithmetic operators; post a constraint with [le] / [ge] /
/// [eq]. Scalars go on the right of `*` (`x * 2.0`), as in the integer DSL.
class FloatExpr {
  FloatExpr._(this._model, this._terms, this._constant);

  final ContinuousModel _model;
  final Map<String, double> _terms; // no zero coefficients
  final double _constant;

  FloatExpr _coerce(Object other) {
    if (other is FloatExpr) {
      if (!identical(other._model, _model)) {
        throw ArgumentError(
            'Cannot combine expressions from two different ContinuousModels.');
      }
      return other;
    }
    if (other is num) {
      return FloatExpr._(_model, const {}, other.toDouble());
    }
    throw ArgumentError('Expected FloatExpr, FloatVar, or num, got '
        '${other.runtimeType}.');
  }

  FloatExpr _combine(Object other, {required bool subtract}) {
    final o = _coerce(other);
    final terms = Map<String, double>.from(_terms);
    o._terms.forEach((v, c) {
      final next = (terms[v] ?? 0) + (subtract ? -c : c);
      if (next == 0) {
        terms.remove(v);
      } else {
        terms[v] = next;
      }
    });
    return FloatExpr._(_model, terms,
        subtract ? _constant - o._constant : _constant + o._constant);
  }

  FloatExpr operator +(Object other) => _combine(other, subtract: false);
  FloatExpr operator -(Object other) => _combine(other, subtract: true);
  FloatExpr operator -() => scaled(-1);

  /// `this * other`. A scalar (`x * 2`) scales linearly. Multiplying two
  /// expressions (`x * y`, `x * x`) is non-linear: it is lowered to a fresh
  /// auxiliary variable constrained by a product relation, and this returns
  /// that auxiliary as a linear term. The linear parts of the model stay
  /// exact (no interval "dependency problem"); only the genuine products
  /// become interval-propagated primitives.
  FloatExpr operator *(Object other) {
    if (other is num) return scaled(other);
    final o = _coerce(other);
    // A constant operand is just a scalar multiply — keep it linear.
    if (_terms.isEmpty) return o.scaled(_constant);
    if (o._terms.isEmpty) return scaled(o._constant);
    // Genuine variable×variable product: decompose into an aux variable.
    final a = _model._asVariable(this);
    final b = _model._asVariable(o);
    return _model._product(a, b);
  }

  FloatExpr scaled(num k) {
    final d = k.toDouble();
    if (d == 0) return FloatExpr._(_model, const {}, 0);
    return FloatExpr._(
      _model,
      {for (final e in _terms.entries) e.key: e.value * d},
      _constant * d,
    );
  }

  /// Posts `this <= other`.
  void le(Object other) => _post(other, ContinuousOp.le);

  /// Posts `this >= other`.
  void ge(Object other) => _post(other, ContinuousOp.ge);

  /// Posts `this == other`.
  void eq(Object other) => _post(other, ContinuousOp.eq);

  void _post(Object other, ContinuousOp op) {
    final diff = _combine(other, subtract: true);
    final vars = diff._terms.keys.toList();
    if (vars.isEmpty) {
      // Constant relation: `0 {op} -k`. Satisfied → no-op; else contradictory.
      final b = -diff._constant;
      final ok = switch (op) {
        ContinuousOp.le => 0 <= b,
        ContinuousOp.ge => 0 >= b,
        ContinuousOp.eq => 0 == b,
      };
      if (!ok) {
        throw ArgumentError('Relation is unsatisfiable as written (a false '
            'constant relation — check for cancelling terms).');
      }
      return;
    }
    _model._addConstraint(_LinearC(
      vars: vars,
      coeffs: [for (final v in vars) diff._terms[v]!],
      op: op,
      bound: -diff._constant,
    ));
  }
}

/// A continuous decision variable — a [FloatExpr] with a single unit term.
class FloatVar extends FloatExpr {
  FloatVar._(ContinuousModel model, this.name) : super._(model, {name: 1}, 0);

  final String name;

  @override
  String toString() => name;
}

/// A solution: the pruned box for every variable, with a midpoint witness.
class ContinuousSolution {
  ContinuousSolution(this.box);

  /// The final narrow interval for each variable.
  final Map<String, Interval> box;

  /// A representative point — each variable at the midpoint of its box.
  Map<String, double> get midpoint =>
      {for (final e in box.entries) e.key: e.value.mid};

  @override
  String toString() => midpoint.toString();
}

/// A continuous CSP: real variables with interval domains and linear
/// constraints, solved by interval branch-and-prune.
class ContinuousModel {
  final Map<String, Interval> _domains = {};
  final List<_LinearC> _constraints = [];
  final List<_ProductC> _products = [];

  /// User-declared variables — the ones the search branches on. Auxiliary
  /// variables introduced for products are *determined* by these via
  /// propagation, so they are never bisected and never surface in a solution.
  final Set<String> _decisionVars = {};
  int _auxCounter = 0;

  /// Declares a variable over the finite interval `[lo, hi]`. Throws
  /// [ArgumentError] on a non-finite bound or `lo > hi`.
  FloatVar addVar(String name, double lo, double hi) {
    if (!lo.isFinite || !hi.isFinite) {
      throw ArgumentError(
          'Variable bounds must be finite ($name: [$lo, $hi]).');
    }
    if (lo > hi) {
      throw ArgumentError('Empty domain for $name: lo ($lo) > hi ($hi).');
    }
    if (_domains.containsKey(name)) {
      throw ArgumentError("Variable '$name' already exists.");
    }
    _domains[name] = Interval(lo, hi);
    _decisionVars.add(name);
    return FloatVar._(this, name);
  }

  /// The interval of a linear [expr] over the current variable bounds.
  Interval _evalExpr(FloatExpr expr) {
    var acc = Interval.point(expr._constant);
    expr._terms.forEach((v, c) {
      acc = acc + _domains[v]!.scale(c);
    });
    return acc;
  }

  /// Returns a single variable equal to [expr]: the variable itself if [expr]
  /// is already one, otherwise a fresh auxiliary `a` with a posted `a == expr`.
  String _asVariable(FloatExpr expr) {
    if (expr._constant == 0 && expr._terms.length == 1) {
      final only = expr._terms.entries.first;
      if (only.value == 1) return only.key;
    }
    final aux = '__aux${_auxCounter++}';
    _domains[aux] = _evalExpr(expr); // determined, not a decision var
    // a == expr  ⇒  a − Σcᵢxᵢ = expr.constant
    final terms = <String, double>{aux: 1};
    expr._terms.forEach((v, c) => terms[v] = (terms[v] ?? 0) - c);
    final vars = terms.keys.toList();
    _constraints.add(_LinearC(
      vars: vars,
      coeffs: [for (final v in vars) terms[v]!],
      op: ContinuousOp.eq,
      bound: expr._constant,
    ));
    return aux;
  }

  /// Introduces `p == a · b` and returns `p` as a linear expression.
  FloatExpr _product(String a, String b) {
    final p = '__aux${_auxCounter++}';
    _domains[p] = _domains[a]! * _domains[b]!;
    _products.add(_ProductC(product: p, a: a, b: b));
    return FloatExpr._(this, {p: 1}, 0);
  }

  void _addConstraint(_LinearC c) {
    for (final v in c.vars) {
      if (!_domains.containsKey(v)) {
        throw ArgumentError("Constraint references unknown variable '$v'.");
      }
    }
    _constraints.add(c);
  }

  /// Solves the model. Returns a [ContinuousSolution] whose every variable
  /// interval is at most [epsilon] wide, or `null` if the model is infeasible.
  ///
  /// [maxSplits] bounds the number of bisection steps; if exhausted before a
  /// solution is isolated the search reports the best-effort infeasibility
  /// (`null`). [epsilon] is the target box side length.
  ContinuousSolution? solve({double epsilon = 1e-6, int maxSplits = 100000}) {
    if (epsilon <= 0) {
      throw ArgumentError.value(epsilon, 'epsilon', 'must be > 0');
    }
    var splits = 0;

    ContinuousSolution? search(Map<String, Interval> domains) {
      final pruned = _propagate(domains);
      if (pruned == null) return null; // a domain emptied — infeasible box

      // Find the widest *decision* variable still above tolerance. Auxiliary
      // variables are functions of the decision variables, so pinning the
      // latter to within epsilon determines the former via propagation —
      // branching on aux variables would be redundant and unsound.
      String? widest;
      var maxWidth = epsilon;
      for (final v in _decisionVars) {
        final w = pruned[v]!.width;
        if (w > maxWidth) {
          maxWidth = w;
          widest = v;
        }
      }
      if (widest == null) {
        // Every decision variable is narrow — report just those (aux
        // variables are an internal detail).
        return ContinuousSolution({
          for (final v in _decisionVars) v: pruned[v]!,
        });
      }

      if (splits >= maxSplits) return null; // budget exhausted
      splits++;

      final iv = pruned[widest]!;
      final m = iv.mid;
      // Branch: lower half then upper half.
      for (final half in [Interval(iv.lo, m), Interval(m, iv.hi)]) {
        final child = Map<String, Interval>.from(pruned)..[widest] = half;
        final sol = search(child);
        if (sol != null) return sol;
      }
      return null;
    }

    return search(Map<String, Interval>.from(_domains));
  }

  /// HC4-style bound propagation to a fixpoint. Returns the tightened domains,
  /// or `null` if any domain becomes empty. Mutates a copy, not the model.
  Map<String, Interval>? _propagate(Map<String, Interval> input) {
    final domains = Map<String, Interval>.from(input);
    // Iterate to a fixpoint. Each revise can only shrink intervals, so
    // progress is monotone; the cap guards against slow asymptotic
    // convergence (bisection provides the real progress between calls).
    const maxRounds = 32;
    for (var round = 0; round < maxRounds; round++) {
      var changed = false;
      for (final c in _constraints) {
        // Target interval the weighted sum must lie in.
        final target = switch (c.op) {
          ContinuousOp.le => Interval(double.negativeInfinity, c.bound),
          ContinuousOp.ge => Interval(c.bound, double.infinity),
          ContinuousOp.eq => Interval.point(c.bound),
        };
        for (var j = 0; j < c.vars.length; j++) {
          // sum_{i != j} cᵢ·Xᵢ
          var others = const Interval(0, 0);
          for (var i = 0; i < c.vars.length; i++) {
            if (i == j) continue;
            others = others + domains[c.vars[i]]!.scale(c.coeffs[i]);
          }
          // cⱼ·Xⱼ ∈ target − others  ⇒  Xⱼ ∈ (target − others) / cⱼ
          final cjXj = target - others;
          final tightened = cjXj.scale(1 / c.coeffs[j]);
          final old = domains[c.vars[j]]!;
          final next = old.intersect(tightened);
          if (next.isEmpty) return null;
          if (_shrunk(old, next)) {
            changed = true;
            domains[c.vars[j]] = next;
          }
        }
      }

      // Product constraints: p == a·b. HC4 revise in both directions.
      for (final pc in _products) {
        final p = domains[pc.product]!;
        final a = domains[pc.a]!;
        final b = domains[pc.b]!;
        // Forward: p ∈ a·b.
        final fp = p.intersect(a * b);
        if (fp.isEmpty) return null;
        if (_shrunk(p, fp)) {
          changed = true;
          domains[pc.product] = fp;
        }
        // Backward: a ∈ p/b, b ∈ p/a.
        final fa = a.intersect(fp.divide(b));
        if (fa.isEmpty) return null;
        if (_shrunk(a, fa)) {
          changed = true;
          domains[pc.a] = fa;
        }
        final fb = b.intersect(fp.divide(domains[pc.a]!));
        if (fb.isEmpty) return null;
        if (_shrunk(b, fb)) {
          changed = true;
          domains[pc.b] = fb;
        }
      }

      if (!changed) break;
    }
    return domains;
  }

  /// Whether [next] is a *material* tightening of [old] — used to decide the
  /// propagation fixpoint. A tolerance avoids spinning on sub-ULP changes.
  static bool _shrunk(Interval old, Interval next) =>
      (next.lo - old.lo).abs() > 1e-12 || (next.hi - old.hi).abs() > 1e-12;
}

/// A product constraint `product == a · b`. The workhorse of non-linear
/// support: every `FloatExpr * FloatExpr` lowers to one of these.
class _ProductC {
  _ProductC({required this.product, required this.a, required this.b});

  final String product;
  final String a;
  final String b;
}

/// A linear constraint `Σ coeffs[i]·vars[i] {op} bound`.
class _LinearC {
  _LinearC({
    required this.vars,
    required this.coeffs,
    required this.op,
    required this.bound,
  });

  final List<String> vars;
  final List<double> coeffs;
  final ContinuousOp op;
  final double bound;
}

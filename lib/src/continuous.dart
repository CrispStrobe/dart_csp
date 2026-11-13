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
//   * Constraints supported: linear (`Σ cᵢ·xᵢ {≤,≥,=} b`) and products
//     (`x * y`, `x²`, lowered to an auxiliary variable), built from the DSL's
//     `+`, `-`, unary `-`, `* scalar`, and `* expression`.
//   * Integer variables are supported alongside continuous ones
//     ([ContinuousModel.addIntVar]) — bounds round inward to whole values and
//     the search branches them on integer boundaries — so a single model can
//     mix both. This still does not reuse the integer *engine*: a discrete
//     model that needs GAC globals (allDifferent, etc.) or its heuristics
//     should use `Problem`, which since gained continuous variables of its own
//     (`addFloatVariable` / `addFloatProduct`, see doc/mixed-continuous.md).
//     This module remains the nicer surface for pure arithmetic, thanks to its
//     expression DSL.
//   * Arithmetic uses plain IEEE-754 doubles by default. Pass
//     `rounding: IntervalRounding.outward` to [ContinuousModel.solve] for
//     conservative interval operations. `solveDetailed` distinguishes
//     exhausted search from resource/precision limits and checks the original
//     expressions at its candidate point. No end-to-end exact-real proof is
//     issued: expression folding and residual evaluation use doubles.
//
// See PLAN.md for the remaining work.

import 'dart:math' as math;
import 'dart:typed_data';

/// The midpoint of finite bounds, without overflowing their difference.
///
/// Same-sign bounds have a representable difference. Opposite-sign bounds
/// use a half-sum only when their difference overflows, preserving subnormal
/// midpoints for small intervals. A rounded endpoint is possible when no
/// representable double lies strictly between the bounds.
double intervalMidpoint(double lo, double hi) {
  final width = hi - lo;
  return width.isFinite ? lo + width / 2 : lo / 2 + hi / 2;
}

/// How interval arithmetic rounds its results.
///
/// Interval bounds are IEEE-754 doubles, so every operation on them
/// rounds — and rounding *inwards* can shrink a box past a real
/// solution. [exact] ignores that; [outward] pays a little width to
/// eliminate it.
///
/// ```dart
/// // The default: fast, and wrong by up to half an ULP per operation.
/// model.solve();
/// // Conservative primitive interval operations, with explicit outcome:
/// final result = model.solveDetailed(rounding: IntervalRounding.outward);
/// ```
///
/// **What [outward] buys, precisely.** Each defined primitive operation
/// encloses its exact-real result for the represented double operands.
/// This is necessary for safe interval exclusion. An end-to-end proof also
/// requires a checked model-construction and expression-folding contract;
/// [ContinuousSolveResult] currently issues no such certificate.
///
/// **What it does not buy.** A surviving box is still only a candidate.
/// Interval propagation is sound but not complete — a box can survive
/// every constraint without containing a solution — and that is a
/// property of the method, not of the rounding. Residual validation checks
/// numerical satisfaction at a point; certified *enclosure*
/// of a solution would need an additional existence test (an interval
/// Newton / Krawczyk step), which this library does not do.
///
/// C's `fesetround` has no Dart equivalent, so [outward] emulates
/// directed rounding by nudging each result one ULP in the safe
/// direction ([nextDown] for lower bounds, [nextUp] for upper bounds).
/// One ULP suffices because a single IEEE operation errs by at most
/// half an ULP.
enum IntervalRounding {
  /// Plain double arithmetic. Fast; bounds can be off by up to half an
  /// ULP per operation, in either direction.
  exact,

  /// Each result is nudged one ULP outward, so a computed interval is
  /// guaranteed to contain the exact real result.
  outward;

  /// Rounds [x] down when this is [outward]; identity for [exact].
  /// Use for the *lower* bound of a computed interval.
  double down(double x) => this == outward ? nextDown(x) : x;

  /// Rounds [x] up when this is [outward]; identity for [exact].
  /// Use for the *upper* bound of a computed interval.
  double up(double x) => this == outward ? nextUp(x) : x;

  /// `a + b`, with the result rounded outward under [outward].
  Interval add(Interval a, Interval b) =>
      Interval(down(a.lo + b.lo), up(a.hi + b.hi));

  /// `a - b`, with the result rounded outward under [outward].
  Interval sub(Interval a, Interval b) =>
      Interval(down(a.lo - b.hi), up(a.hi - b.lo));

  /// `a * b`, with the result rounded outward under [outward].
  Interval mul(Interval a, Interval b) {
    final p = [a.lo * b.lo, a.lo * b.hi, a.hi * b.lo, a.hi * b.hi];
    return Interval(down(p.reduce(math.min)), up(p.reduce(math.max)));
  }

  /// The range of `x * x` for one interval, preserving the repeated operand.
  ///
  /// Generic multiplication treats its operands independently. Squaring must
  /// instead have a nonnegative range, including when [a] crosses zero.
  Interval square(Interval a) {
    if (a.isEmpty) return a;
    final lo2 = a.lo * a.lo, hi2 = a.hi * a.hi;
    final upper = up(math.max(lo2, hi2));
    final lower =
        a.lo <= 0 && a.hi >= 0 ? 0.0 : math.max(0.0, down(math.min(lo2, hi2)));
    return Interval(lower, upper);
  }

  /// `a / d`, with the result rounded outward under [outward]. Zero
  /// handling matches [Interval.divide].
  Interval div(Interval a, Interval d) {
    if (d.lo <= 0 && 0 <= d.hi) {
      return const Interval(double.negativeInfinity, double.infinity);
    }
    final q = [a.lo / d.lo, a.lo / d.hi, a.hi / d.lo, a.hi / d.hi];
    return Interval(down(q.reduce(math.min)), up(q.reduce(math.max)));
  }

  /// `a * c` for a real scalar [c], with the result rounded outward
  /// under [outward] and orientation preserved.
  Interval scale(Interval a, double c) => c >= 0
      ? Interval(down(a.lo * c), up(a.hi * c))
      : Interval(down(a.hi * c), up(a.lo * c));

  /// The next representable double above [x] (`nextafter(x, +∞)`).
  ///
  /// Implemented by incrementing the bit pattern, in two 32-bit halves
  /// rather than one 64-bit word: `ByteData.getInt64` is unavailable
  /// under dart2js, and this library stays web-safe.
  static double nextUp(double x) {
    if (x.isNaN || x == double.infinity) return x;
    if (x == 0.0) return 5e-324; // smallest positive subnormal
    _bits.setFloat64(0, x);
    var hi = _bits.getUint32(0);
    var lo = _bits.getUint32(4);
    if (x > 0) {
      // Away from zero: the bit pattern increases.
      lo = (lo + 1) & 0xFFFFFFFF;
      if (lo == 0) hi = (hi + 1) & 0xFFFFFFFF;
    } else {
      // Toward zero from a negative: the bit pattern decreases.
      if (lo == 0) {
        hi = (hi - 1) & 0xFFFFFFFF;
        lo = 0xFFFFFFFF;
      } else {
        lo -= 1;
      }
    }
    _bits.setUint32(0, hi);
    _bits.setUint32(4, lo);
    return _bits.getFloat64(0);
  }

  /// The next representable double below [x] (`nextafter(x, -∞)`).
  static double nextDown(double x) => -nextUp(-x);

  /// Scratch buffer for the bit reinterpretation in [nextUp]. Shared
  /// and mutable: Dart isolates are single-threaded and [nextUp] never
  /// reenters, so one buffer avoids an allocation per call.
  static final ByteData _bits = ByteData(8);
}

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
  double get mid => intervalMidpoint(lo, hi);

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

/// The outcome of a continuous solve, independently of its candidate box.
enum ContinuousSolveStatus {
  /// A narrow box survived, but its point did not pass residual validation.
  candidate,

  /// A finite point meets every posted primitive within the requested
  /// residual tolerances. This is numerical acceptance, not an existence
  /// certificate for exact real equalities.
  satisfied,

  /// Propagation and exhaustive search eliminated every box. Consult
  /// [ContinuousSolveResult.certifiedInfeasible] before treating this as a
  /// mathematical proof.
  infeasible,

  /// Search stopped at the bisection budget, without an infeasibility claim.
  splitLimit,

  /// Doubles cannot subdivide a surviving interval to the requested width.
  precisionLimit,

  /// A non-finite intermediate or candidate prevented reliable evaluation.
  numericalFailure,

  /// The caller's cancellation/deadline callback requested a stop.
  cancelled,
}

/// Residual validation of one posted primitive at the candidate point.
///
/// Derived expressions are recomputed from decision values before these
/// diagnostics are produced. An auxiliary variable's independent midpoint
/// cannot conceal a violation amplified by a later expression.
class ContinuousResidual {
  ContinuousResidual({
    required this.constraint,
    required this.kind,
    required this.residual,
    required this.violation,
    required this.tolerance,
  });

  /// Stable within an unchanged model, e.g. `linear:0` or `product:0`.
  final String constraint;
  final String kind;

  /// The signed left-hand-side minus right-hand-side value.
  final double residual;

  /// Absolute residual for equality; the positive violation for an inequality.
  final double violation;
  final double tolerance;

  double get normalizedViolation => violation / tolerance;
  bool get isSatisfied => violation.isFinite && violation <= tolerance;
}

/// Detailed, per-call continuous outcome and residual diagnostics.
class ContinuousSolveResult {
  ContinuousSolveResult({
    required this.status,
    required this.splits,
    this.candidate,
    List<ContinuousResidual> residuals = const [],
    this.message,
    this.certifiedInfeasible = false,
  }) : residuals = List.unmodifiable(residuals);

  final ContinuousSolveStatus status;
  final int splits;

  /// A surviving box, if available; it is usable as a solution only when
  /// [status] is [ContinuousSolveStatus.satisfied].
  final ContinuousSolution? candidate;
  final List<ContinuousResidual> residuals;
  final String? message;

  /// This version does not issue end-to-end infeasibility certificates.
  /// Outward primitive arithmetic protects interval operations, but rounded
  /// expression/constant folding also needs a checked provenance contract.
  final bool certifiedInfeasible;

  bool get isSatisfied => status == ContinuousSolveStatus.satisfied;
  ContinuousSolution? get solution => isSatisfied ? candidate : null;
  double get maxNormalizedViolation => residuals.fold(0.0,
      (current, residual) => math.max(current, residual.normalizedViolation));
}

/// A continuous CSP: real variables with interval domains and linear
/// constraints, solved by interval branch-and-prune.
class ContinuousModel {
  final Map<String, Interval> _domains = {};
  final List<_LinearC> _constraints = [];
  final List<_ProductC> _products = [];

  // Construction order is topological: every derived expression references
  // only user variables or auxiliaries introduced earlier.
  final List<_AuxiliaryValue> _auxiliaryValues = [];

  /// User-declared variables — the ones the search branches on. Auxiliary
  /// variables introduced for products are *determined* by these via
  /// propagation, so they are never bisected and never surface in a solution.
  final Set<String> _decisionVars = {};

  /// Decision variables constrained to integer values. They live in the same
  /// interval machinery but their bounds are rounded inward to integers after
  /// each tightening, and the search branches them on integer boundaries.
  final Set<String> _intVars = {};
  int _auxCounter = 0;

  String _newAuxiliaryName() {
    String name;
    do {
      name = '__aux${_auxCounter++}';
    } while (_domains.containsKey(name));
    return name;
  }

  /// Slack for integer rounding, to absorb floating-point error so a bound
  /// that is an integer "plus epsilon" is not wrongly rounded past it.
  static const double _intTol = 1e-9;

  /// Declares a continuous variable over the finite interval `[lo, hi]`.
  /// Throws [ArgumentError] on a non-finite bound or `lo > hi`.
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

  /// Declares an **integer** decision variable over the inclusive range
  /// `[lo, hi]`. It participates in the same linear/product constraints as
  /// continuous variables — so a single model can mix both — but is
  /// constrained to whole values. Throws [ArgumentError] on `lo > hi`.
  FloatVar addIntVar(String name, int lo, int hi) {
    if (lo > hi) {
      throw ArgumentError('Empty domain for $name: lo ($lo) > hi ($hi).');
    }
    if (_domains.containsKey(name)) {
      throw ArgumentError("Variable '$name' already exists.");
    }
    _domains[name] = Interval(lo.toDouble(), hi.toDouble());
    _decisionVars.add(name);
    _intVars.add(name);
    return FloatVar._(this, name);
  }

  /// Rounds [iv] inward to integer bounds if [name] is an integer variable;
  /// otherwise returns it unchanged. May return an empty interval.
  Interval _snap(String name, Interval iv) {
    if (!_intVars.contains(name)) return iv;
    return Interval(
        (iv.lo - _intTol).ceilToDouble(), (iv.hi + _intTol).floorToDouble());
  }

  /// The interval of a linear [expr] over the current variable bounds.
  Interval _evalExpr(FloatExpr expr, IntervalRounding r) {
    var acc = Interval.point(expr._constant);
    expr._terms.forEach((v, c) {
      acc = r.add(acc, r.scale(_domains[v]!, c));
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
    final aux = _newAuxiliaryName();
    // Always widen this one outward: the rounding mode is a solve-time
    // choice but the aux domain is built now, and a looser initial box
    // is sound under either mode.
    _domains[aux] = _evalExpr(expr, IntervalRounding.outward);
    _auxiliaryValues
        .add(_AuxiliaryValue.linear(aux, Map.of(expr._terms), expr._constant));
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
    final p = _newAuxiliaryName();
    _domains[p] = a == b
        ? IntervalRounding.outward.square(_domains[a]!)
        : IntervalRounding.outward.mul(_domains[a]!, _domains[b]!);
    _auxiliaryValues.add(_AuxiliaryValue.product(p, a, b));
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

  /// Compatibility entry point returning a residual-validated solution.
  ///
  /// `null` can also mean a budget/precision limit, failed residual check,
  /// or numerical failure. It is not an infeasibility certificate. Use
  /// [solveDetailed] to distinguish those outcomes. [epsilon] controls the
  /// target box width and the default residual tolerances.
  ContinuousSolution? solve({
    double epsilon = 1e-6,
    int maxSplits = 100000,
    IntervalRounding rounding = IntervalRounding.exact,
  }) =>
      solveDetailed(
        epsilon: epsilon,
        maxSplits: maxSplits,
        rounding: rounding,
      ).solution;

  /// Solves with explicit termination status and original-expression checks.
  ///
  /// The midpoint of each user variable is chosen, then derived expressions
  /// are reevaluated in construction order. A primitive passes when its
  /// violation is at most `absoluteTolerance + relativeTolerance * scale`,
  /// where `scale` is the larger magnitude of its evaluated sides. Both
  /// tolerances default to [epsilon]; the absolute tolerance must be positive.
  /// These are arithmetic tolerances, not a substitute for CAD units.
  ///
  /// [shouldCancel] is checked between nodes and propagation operations. This
  /// method is synchronous: use a callback checking a deadline, or a worker;
  /// it does not yield so an event-loop timer cannot interrupt it in place.
  /// Outward arithmetic is the default here, while [solve] preserves its
  /// historical rounding default. Neither entry point certifies a solution.
  ContinuousSolveResult solveDetailed({
    double epsilon = 1e-6,
    int maxSplits = 100000,
    IntervalRounding rounding = IntervalRounding.outward,
    double? absoluteTolerance,
    double? relativeTolerance,
    bool Function()? shouldCancel,
  }) {
    if (!epsilon.isFinite || epsilon <= 0) {
      throw ArgumentError.value(epsilon, 'epsilon', 'must be finite and > 0');
    }
    if (maxSplits < 0) {
      throw ArgumentError.value(maxSplits, 'maxSplits', 'must be >= 0');
    }
    final absTol = absoluteTolerance ?? epsilon;
    final relTol = relativeTolerance ?? epsilon;
    if (!absTol.isFinite || absTol <= 0) {
      throw ArgumentError.value(
          absTol, 'absoluteTolerance', 'must be finite and > 0');
    }
    if (!relTol.isFinite || relTol < 0) {
      throw ArgumentError.value(
          relTol, 'relativeTolerance', 'must be finite and >= 0');
    }
    var splits = 0;
    final pending = <Map<String, Interval>>[Map.of(_domains)];
    try {
      while (pending.isNotEmpty) {
        _checkCancellation(shouldCancel);
        final pruned = _propagate(pending.removeLast(), rounding, shouldCancel);
        if (pruned == null) continue;

        String? branchVar;
        var branchIsInt = false;
        var maxWidth = -1.0;
        var precisionLimited = false;
        for (final v in _decisionVars) {
          final iv = pruned[v]!;
          final isInt = _intVars.contains(v);
          final needs = isInt
              ? (iv.lo - _intTol).ceilToDouble() <
                  (iv.hi + _intTol).floorToDouble()
              : iv.width > epsilon;
          if (!needs) continue;
          final mid =
              isInt ? intervalMidpoint(iv.lo, iv.hi).floorToDouble() : iv.mid;
          if (!mid.isFinite ||
              (isInt
                  ? mid >= iv.hi || mid + 1 <= mid
                  : mid <= iv.lo || mid >= iv.hi)) {
            precisionLimited = true;
            continue;
          }
          if (iv.width > maxWidth) {
            maxWidth = iv.width;
            branchVar = v;
            branchIsInt = isInt;
          }
        }
        if (branchVar == null) {
          final candidate = ContinuousSolution({
            for (final v in _decisionVars)
              v: _intVars.contains(v)
                  ? Interval.point((pruned[v]!.lo - _intTol).ceilToDouble())
                  : pruned[v]!,
          });
          final residuals = _residuals(candidate, absTol, relTol);
          return ContinuousSolveResult(
            status: precisionLimited
                ? ContinuousSolveStatus.precisionLimit
                : residuals.every((r) => r.isSatisfied)
                    ? ContinuousSolveStatus.satisfied
                    : ContinuousSolveStatus.candidate,
            candidate: candidate,
            residuals: residuals,
            splits: splits,
            message: precisionLimited
                ? 'The requested box width is below local double precision.'
                : null,
          );
        }
        if (splits >= maxSplits) {
          return ContinuousSolveResult(
            status: ContinuousSolveStatus.splitLimit,
            splits: splits,
            message:
                'The bisection budget was exhausted; feasibility is unknown.',
          );
        }
        splits++;
        final iv = pruned[branchVar]!;
        final mid = branchIsInt
            ? intervalMidpoint(iv.lo, iv.hi).floorToDouble()
            : iv.mid;
        final lower = Interval(iv.lo, mid);
        final upper = Interval(branchIsInt ? mid + 1 : mid, iv.hi);
        // Explicit depth-first stack avoids recursion overflow for many free
        // coordinates and preserves the historical lower-half-first order.
        pending.add(Map.of(pruned)..[branchVar] = upper);
        pending.add(Map.of(pruned)..[branchVar] = lower);
      }
    } on _ContinuousStop catch (stop) {
      return ContinuousSolveResult(
        status: stop.status,
        splits: splits,
        message: stop.message,
      );
    }
    return ContinuousSolveResult(
      status: ContinuousSolveStatus.infeasible,
      splits: splits,
      message: rounding == IntervalRounding.outward
          ? 'Every box was excluded using outward primitive arithmetic; '
              'no end-to-end expression certificate is issued.'
          : 'Every box was excluded using unverified floating-point arithmetic.',
    );
  }

  List<ContinuousResidual> _residuals(
      ContinuousSolution candidate, double absTol, double relTol) {
    final values = candidate.midpoint;
    for (final entry in values.entries) {
      _requireFinite(entry.value, 'Decision ${entry.key}');
    }
    for (final auxiliary in _auxiliaryValues) {
      final value = auxiliary.evaluate(values);
      _requireFinite(value, 'Derived expression ${auxiliary.name}');
      values[auxiliary.name] = value;
    }
    final residuals = <ContinuousResidual>[];
    void add(String id, String kind, double lhs, double rhs, ContinuousOp op) {
      _requireFinite(lhs, id);
      _requireFinite(rhs, id);
      final residual = lhs - rhs;
      _requireFinite(residual, '$id residual');
      final violation = switch (op) {
        ContinuousOp.eq => residual.abs(),
        ContinuousOp.le => math.max(0.0, residual),
        ContinuousOp.ge => math.max(0.0, -residual),
      };
      final tolerance = absTol + relTol * math.max(lhs.abs(), rhs.abs());
      _requireFinite(tolerance, '$id tolerance');
      residuals.add(ContinuousResidual(
        constraint: id,
        kind: kind,
        residual: residual,
        violation: violation,
        tolerance: tolerance,
      ));
    }

    for (var i = 0; i < _constraints.length; i++) {
      final c = _constraints[i];
      final lhs = _compensatedSum([
        for (var j = 0; j < c.vars.length; j++)
          c.coeffs[j] * values[c.vars[j]]!,
      ]);
      add('linear:$i', 'linear.${c.op.name}', lhs, c.bound, c.op);
    }
    for (var i = 0; i < _products.length; i++) {
      final c = _products[i];
      add('product:$i', c.a == c.b ? 'square' : 'product', values[c.product]!,
          values[c.a]! * values[c.b]!, ContinuousOp.eq);
    }
    return residuals;
  }

  /// HC4-style bound propagation to a fixpoint. Returns the tightened domains,
  /// or `null` if any domain becomes empty. Mutates a copy, not the model.
  Map<String, Interval>? _propagate(Map<String, Interval> input,
      IntervalRounding r, bool Function()? shouldCancel) {
    final domains = Map<String, Interval>.from(input);
    for (final entry in domains.entries) {
      _requireInterval(entry.value, entry.key);
    }
    // Iterate to a fixpoint. Each revise can only shrink intervals, so
    // progress is monotone; the cap guards against slow asymptotic
    // convergence (bisection provides the real progress between calls).
    const maxRounds = 32;
    for (var round = 0; round < maxRounds; round++) {
      var changed = false;
      for (final c in _constraints) {
        _checkCancellation(shouldCancel);
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
            others = r.add(others, r.scale(domains[c.vars[i]]!, c.coeffs[i]));
          }
          // cⱼ·Xⱼ ∈ target − others  ⇒  Xⱼ ∈ (target − others) / cⱼ
          final cjXj = r.sub(target, others);
          // Divide by the coefficient rather than scaling by its
          // reciprocal: `1 / c` rounds once before the multiply rounds
          // again, and under `outward` a single division is both
          // tighter and easier to reason about.
          final tightened = r.div(cjXj, Interval.point(c.coeffs[j]));
          final old = domains[c.vars[j]]!;
          // Snap tightens integer variables to whole bounds (a no-op for
          // continuous ones).
          final next = _snap(c.vars[j], old.intersect(tightened));
          _requireInterval(next, c.vars[j]);
          if (next.isEmpty) return null;
          if (_shrunk(old, next)) {
            changed = true;
            domains[c.vars[j]] = next;
          }
        }
      }

      // Product constraints: p == a·b. HC4 revise in both directions.
      for (final pc in _products) {
        _checkCancellation(shouldCancel);
        final p = domains[pc.product]!;
        final a = domains[pc.a]!;
        final b = domains[pc.b]!;
        // Forward: p ∈ a·b.
        final product = pc.a == pc.b ? r.square(a) : r.mul(a, b);
        final fp = _snap(pc.product, p.intersect(product));
        _requireInterval(fp, pc.product);
        if (fp.isEmpty) return null;
        if (_shrunk(p, fp)) {
          changed = true;
          domains[pc.product] = fp;
        }
        // Backward: a ∈ p/b, b ∈ p/a.
        final fa = _snap(pc.a, a.intersect(r.div(fp, b)));
        _requireInterval(fa, pc.a);
        if (fa.isEmpty) return null;
        if (_shrunk(a, fa)) {
          changed = true;
          domains[pc.a] = fa;
        }
        final fb = _snap(pc.b, b.intersect(r.div(fp, domains[pc.a]!)));
        _requireInterval(fb, pc.b);
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

class _ContinuousStop implements Exception {
  const _ContinuousStop(this.status, this.message);
  final ContinuousSolveStatus status;
  final String message;
}

void _checkCancellation(bool Function()? shouldCancel) {
  if (shouldCancel?.call() ?? false) {
    throw const _ContinuousStop(
        ContinuousSolveStatus.cancelled, 'The caller requested cancellation.');
  }
}

void _requireFinite(double value, String context) {
  if (!value.isFinite) {
    throw _ContinuousStop(ContinuousSolveStatus.numericalFailure,
        '$context produced a non-finite value.');
  }
}

void _requireInterval(Interval interval, String context) {
  if (interval.lo.isNaN || interval.hi.isNaN) {
    throw _ContinuousStop(ContinuousSolveStatus.numericalFailure,
        '$context produced an undefined interval bound.');
  }
}

// Neumaier summation preserves small terms across cancellation. This remains
// floating-point residual evaluation, not exact-real arithmetic certification.
double _compensatedSum(Iterable<double> terms) {
  var sum = 0.0, correction = 0.0;
  for (final term in terms) {
    final next = sum + term;
    correction +=
        sum.abs() >= term.abs() ? (sum - next) + term : (term - next) + sum;
    sum = next;
  }
  return sum + correction;
}

class _AuxiliaryValue {
  _AuxiliaryValue.linear(this.name, this.terms, this.constant)
      : a = null,
        b = null;
  _AuxiliaryValue.product(this.name, this.a, this.b)
      : terms = null,
        constant = 0;

  final String name;
  final Map<String, double>? terms;
  final double constant;
  final String? a;
  final String? b;

  double evaluate(Map<String, double> values) => terms == null
      ? values[a]! * values[b]!
      : _compensatedSum([
          constant,
          for (final entry in terms!.entries) entry.value * values[entry.key]!,
        ]);
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

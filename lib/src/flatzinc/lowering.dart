/// Lowers a parsed FlatZinc model into a `Problem` instance.
///
/// M2 expands the M1 declaration-only lowering with:
///   - parameter substitution (scalar `int:`/`bool:` and array params)
///   - aliased-var/aliased-array RHS becomes equality constraints
///   - a name-keyed handler table dispatching FlatZinc builtin
///     constraints onto `Problem.addX` calls
///
/// Constraints not in the handler table cause an [UnimplementedError]
/// with the FlatZinc name, the unhandled-builtin error policy described
/// in MINIZINC_PLAN.md §7.
library;

import '../problem.dart';
import '../types.dart' show Dfa;
import 'ast.dart';

/// Result of lowering a [FlatZincModel].
class LoweredModel {
  LoweredModel({
    required this.problem,
    required this.params,
    required this.outputScalarVars,
    required this.outputArrays,
    required this.boolVars,
    required this.solve,
  });

  final Problem problem;
  final Map<String, AstExpr> params;
  final List<String> outputScalarVars;
  final List<OutputArray> outputArrays;

  /// Names of variables declared with `var bool` (including
  /// bool-typed array elements). The output formatter consults this
  /// set to render `0`/`1` values as `false`/`true`, per the FlatZinc
  /// spec for bool outputs.
  final Set<String> boolVars;

  final SolveItem solve;
}

class OutputArray {
  OutputArray({required this.name, required this.varNames, required this.dims});

  final String name;
  final List<String> varNames;
  final List<AstRange> dims;
}

/// Default fallback range for plain `var int` declarations. FlatZinc
/// allows unbounded integer variables; we materialize them as a bounded
/// domain wide enough for typical problems. Callers that hit this
/// limit should rewrite the model to use an explicit range.
const int defaultIntMin = -1000000;
const int defaultIntMax = 1000000;

LoweredModel lower(FlatZincModel model) {
  final problem = Problem();
  final params = <String, AstExpr>{
    for (final p in model.params) p.name: p.value
  };

  // Capture per-declaration metadata that constraint handlers need:
  // which scalar names are booleans, which array names map to which
  // element variable names. Both are populated as we walk the
  // declarations.
  final scalarTypes = <String, VarType>{};
  final arrayElementNames = <String, List<String>>{};
  final boolVars = <String>{};

  // Stash pending alias constraints — `var int: x = y;` produces an
  // `x == y` binary that we post after every variable has been
  // declared (the constraint API rejects forward references).
  final pendingAliases = <_PendingAlias>[];

  for (final v in model.vars) {
    _lowerVarDecl(problem, v, pendingAliases);
    scalarTypes[v.name] = v.type;
    if (v.type is VarTypeBool) boolVars.add(v.name);
  }
  for (final a in model.arrays) {
    final elemNames = _lowerArrayDecl(problem, a, pendingAliases);
    arrayElementNames[a.name] = elemNames;
    if (a.elementType is VarTypeBool) boolVars.addAll(elemNames);
  }

  // Flush deferred alias equalities now that every name is registered.
  for (final pa in pendingAliases) {
    problem.addConstraint(
      <String>[pa.left, pa.right],
      (dynamic a, dynamic b) => a == b,
      label: 'alias',
    );
  }

  // Dispatch constraint items through the handler table. Any unknown
  // builtin throws so users (and tests) get a clear error pointing at
  // the source line.
  final ctx = LoweringContext(
    problem: problem,
    params: params,
    scalarTypes: scalarTypes,
    arrayElementNames: arrayElementNames,
  );
  for (final c in model.constraints) {
    final handler = _constraintHandlers[c.name];
    if (handler == null) {
      throw UnimplementedError(
          'FlatZinc constraint \'${c.name}\' is not yet supported by this '
          'lowering pass (parsed from line ${c.line}). See '
          'MINIZINC_PLAN.md for the constraint roadmap (M3+ adds globals; '
          'M4 adds reified variants).');
    }
    handler(ctx, c);
  }

  final outputScalars = <String>[
    for (final v in model.vars)
      if (v.isOutput) v.name,
  ];
  final outputArrays = <OutputArray>[
    for (final a in model.arrays)
      if (a.isOutput)
        OutputArray(
          name: a.name,
          varNames: arrayElementNames[a.name]!,
          dims: a.outputArrayDims ?? [AstRange(1, a.length)],
        ),
  ];

  return LoweredModel(
    problem: problem,
    params: params,
    outputScalarVars: outputScalars,
    outputArrays: outputArrays,
    boolVars: boolVars,
    solve: model.solve,
  );
}

class _PendingAlias {
  _PendingAlias(this.left, this.right);
  final String left;
  final String right;
}

void _lowerVarDecl(
    Problem problem, VarDecl v, List<_PendingAlias> pendingAliases) {
  final rhs = v.rhs;

  // Aliased to a literal: domain shrinks to a singleton, no later
  // constraint needed.
  if (rhs is AstIntLit) {
    problem.addVariable(v.name, <int>[rhs.value]);
    return;
  }
  if (rhs is AstBoolLit) {
    problem.addVariable(v.name, <int>[if (rhs.value) 1 else 0]);
    return;
  }

  // Plain (non-aliased) declaration uses the declared type. Identifier
  // aliases fall through to here too; the equality is posted afterwards
  // via `pendingAliases`.
  switch (v.type) {
    case VarTypeInt():
      problem.addRangeVariable(v.name, defaultIntMin, defaultIntMax);
    case VarTypeBool():
      problem.addVariable(v.name, <int>[0, 1]);
    case VarTypeRange(:final min, :final max):
      problem.addRangeVariable(v.name, min, max);
    case VarTypeSet(:final values):
      problem.addVariable(v.name, List<int>.from(values));
  }

  if (rhs is AstIdent) {
    // Will be resolved to a name (possibly array-element) in the
    // pendingAliases sweep — record the raw rhs identifier and stash
    // the alias for later.
    pendingAliases.add(_PendingAlias(v.name, _identToVarName(rhs)));
  }
}

List<String> _lowerArrayDecl(
    Problem problem, ArrayVarDecl a, List<_PendingAlias> pendingAliases) {
  final names = <String>[
    for (var i = 1; i <= a.length; i++) '${a.name}[$i]',
  ];

  if (a.elements != null) {
    for (var i = 0; i < a.length; i++) {
      final elem = a.elements![i];
      final elemName = names[i];
      if (elem is AstIntLit) {
        problem.addVariable(elemName, <int>[elem.value]);
      } else if (elem is AstBoolLit) {
        problem.addVariable(elemName, <int>[if (elem.value) 1 else 0]);
      } else if (elem is AstIdent) {
        _addElementByType(problem, elemName, a.elementType);
        pendingAliases.add(_PendingAlias(elemName, _identToVarName(elem)));
      } else {
        throw ArgumentError(
            'Unsupported aliased array element for \'${a.name}[${i + 1}]\': '
            '$elem');
      }
    }
    return names;
  }

  for (final elemName in names) {
    _addElementByType(problem, elemName, a.elementType);
  }
  return names;
}

void _addElementByType(Problem problem, String name, VarType t) {
  switch (t) {
    case VarTypeInt():
      problem.addRangeVariable(name, defaultIntMin, defaultIntMax);
    case VarTypeBool():
      problem.addVariable(name, <int>[0, 1]);
    case VarTypeRange(:final min, :final max):
      problem.addRangeVariable(name, min, max);
    case VarTypeSet(:final values):
      problem.addVariable(name, List<int>.from(values));
  }
}

/// FlatZinc identifier `x` → variable name `x`; `a[3]` → `a[3]`. The
/// variable map already stores array elements under those names, so
/// the conversion is just a string-format.
String _identToVarName(AstIdent id) =>
    id.index == null ? id.name : '${id.name}[${id.index}]';

// ---------------------------------------------------------------------------
// LoweringContext + handler table
// ---------------------------------------------------------------------------

/// Shared state across one lowering run. Constraint handlers receive
/// the context plus the parsed [ConstraintItem] and emit `Problem.addX`
/// calls onto `ctx.problem`. Helper accessors centralize the
/// FlatZinc-argument → Problem-argument plumbing so each handler stays
/// focused on the constraint semantics.
class LoweringContext {
  LoweringContext({
    required this.problem,
    required this.params,
    required this.scalarTypes,
    required this.arrayElementNames,
  });

  final Problem problem;
  final Map<String, AstExpr> params;
  final Map<String, VarType> scalarTypes;
  final Map<String, List<String>> arrayElementNames;

  int _counter = 0;

  /// Per-constraint unique label embedding the FlatZinc builtin name.
  /// Surfaces in MUS / conflict-explanation output, so a label like
  /// `int_lin_eq#7` traces straight back to the 7th `int_lin_eq` in
  /// the source `.fzn`.
  String labelFor(String fznName) => '$fznName#${++_counter}';

  /// Resolve an expression to a single integer constant. Throws if the
  /// expression references a non-int-literal or unresolvable parameter.
  int resolveInt(AstExpr e) {
    final r = _maybeInt(e);
    if (r == null) {
      throw ArgumentError(
          'Expected an integer constant in FlatZinc argument, got: $e');
    }
    return r;
  }

  /// Resolve an expression to a list of integer constants. Accepts
  /// either an array literal of int literals, or an identifier
  /// referencing an `array[..] of int` parameter.
  List<int> resolveIntArray(AstExpr e) {
    final lit = _resolveAsArrayLit(e);
    final out = <int>[];
    for (var i = 0; i < lit.elements.length; i++) {
      final ev = _maybeInt(lit.elements[i]);
      if (ev == null) {
        throw ArgumentError(
            'Expected an int-constant array element at position $i, got: '
            '${lit.elements[i]}');
      }
      out.add(ev);
    }
    return out;
  }

  /// Resolve an expression to a list of variable names. Accepts an
  /// array literal of identifiers (and inline int/bool literals — those
  /// get materialized as fresh singleton variables) or an identifier
  /// referencing an `array[..] of var T` declaration.
  List<String> resolveVarArray(AstExpr e) {
    if (e is AstIdent && e.index == null) {
      final arr = arrayElementNames[e.name];
      if (arr != null) return arr;
    }
    final lit = _resolveAsArrayLit(e);
    final out = <String>[];
    for (var i = 0; i < lit.elements.length; i++) {
      out.add(_resolveOperandVar(lit.elements[i]));
    }
    return out;
  }

  /// Resolve an int-or-var operand. Returns either a variable name (if
  /// the expression refers to an existing variable) or an int constant.
  IntOperand resolveIntOperand(AstExpr e) {
    final ic = _maybeInt(e);
    if (ic != null) return IntOperand.constant(ic);
    if (e is AstIdent) {
      return IntOperand.variable(_identToVarName(e));
    }
    throw ArgumentError(
        'Expected an integer or variable reference in FlatZinc argument, '
        'got: $e');
  }

  /// Resolve a bool-or-var operand the same way as [resolveIntOperand],
  /// but normalizes booleans into 0/1 ints (matching FlatZinc's bool↔int
  /// unification at the engine level).
  IntOperand resolveBoolOperand(AstExpr e) {
    if (e is AstBoolLit) return IntOperand.constant(e.value ? 1 : 0);
    return resolveIntOperand(e);
  }

  // Force the operand to be a variable, materializing a fresh
  // singleton if it's a constant. Used when a constraint API requires
  // a variable name and the FlatZinc encoder happened to inline a
  // literal.
  String _resolveOperandVar(AstExpr e) {
    final op = resolveIntOperand(e);
    return op.match(
      onVariable: (name) => name,
      onConstant: _materializeSingleton,
    );
  }

  int _materializeSingletonCounter = 0;

  String _materializeSingleton(int value) {
    final name = '__fzn_const_${++_materializeSingletonCounter}_$value';
    problem.addVariable(name, <int>[value]);
    return name;
  }

  int? _maybeInt(AstExpr e) {
    if (e is AstIntLit) return e.value;
    if (e is AstBoolLit) return e.value ? 1 : 0;
    if (e is AstIdent && e.index == null) {
      final pv = params[e.name];
      if (pv != null) return _maybeInt(pv);
    }
    return null;
  }

  AstArrayLit _resolveAsArrayLit(AstExpr e) {
    if (e is AstArrayLit) return e;
    if (e is AstIdent && e.index == null) {
      final pv = params[e.name];
      if (pv is AstArrayLit) return pv;
      if (pv != null) {
        throw ArgumentError(
            'Parameter \'${e.name}\' is not an array (got: $pv)');
      }
    }
    throw ArgumentError(
        'Expected an array literal or array parameter, got: $e');
  }
}

/// Tagged union over `String varName` and `int constant` for FlatZinc
/// operands that the spec allows as either. Hand-rolled because Dart
/// doesn't have a built-in either type that integrates with switch
/// patterns at the call site without ceremony.
class IntOperand {
  const IntOperand._({this.varName, this.constant})
      : assert(
          (varName != null) != (constant != null),
          'Exactly one of varName / constant must be set.',
        );

  factory IntOperand.variable(String name) => IntOperand._(varName: name);
  factory IntOperand.constant(int value) => IntOperand._(constant: value);

  final String? varName;
  final int? constant;

  bool get isVar => varName != null;
  bool get isConst => constant != null;

  T match<T>({
    required T Function(String name) onVariable,
    required T Function(int value) onConstant,
  }) {
    if (varName != null) return onVariable(varName!);
    return onConstant(constant!);
  }
}

typedef _Handler = void Function(LoweringContext ctx, ConstraintItem c);

final Map<String, _Handler> _constraintHandlers = <String, _Handler>{
  // Primitive integer comparisons.
  'int_eq': _handleIntCmp('=='),
  'int_ne': _handleIntCmp('!='),
  'int_lt': _handleIntCmp('<'),
  'int_le': _handleIntCmp('<='),
  'int_gt': _handleIntCmp('>'),
  'int_ge': _handleIntCmp('>='),

  // Linear integer constraints.
  'int_lin_eq': _handleIntLin('=='),
  'int_lin_le': _handleIntLin('<='),
  'int_lin_ne': _handleIntLin('!='),
  'int_lin_ge': _handleIntLin('>='),

  // Boolean linear constraints. FlatZinc gives `bool_lin_*` the same
  // shape as `int_lin_*` but with bool-typed variables; since the
  // engine stores bools as 0/1 ints anyway, the integer handler
  // handles both cases verbatim.
  'bool_lin_eq': _handleIntLin('=='),
  'bool_lin_le': _handleIntLin('<='),
  'bool_lin_ne': _handleIntLin('!='),
  'bool_lin_ge': _handleIntLin('>='),

  // Boolean primitives.
  'bool_eq': _handleBoolEq,
  'bool_not': _handleBoolNot,
  'bool_or': _handleBoolBin('||'),
  'bool_and': _handleBoolBin('&&'),
  'bool_xor': _handleBoolBin('xor'),
  'bool_clause': _handleBoolClause,
  'bool2int': _handleBool2Int,

  // Global constraints (M3). Most of these wrap an existing Problem.addX
  // method directly. The exceptions (circuit, subcircuit, inverse,
  // array_int_element) need 1-based ↔ 0-based index translation: the
  // Dart APIs assume 0-based indexing while FlatZinc uses 1-based
  // throughout, so we re-implement those four as direct predicates
  // here rather than synthesising offset variables.
  'all_different_int': _handleAllDifferent,
  'all_different': _handleAllDifferent, // common alias

  'array_int_element': _handleArrayIntElement,
  'array_bool_element': _handleArrayIntElement, // same shape, bool values
  'array_var_int_element': _handleArrayVarElement,
  'array_var_bool_element': _handleArrayVarElement,

  'circuit': _handleCircuit,
  'subcircuit': _handleSubcircuit,

  'inverse': _handleInverse,

  'count_eq': _handleCountEq,
  'nvalue': _handleNvalue,
  'global_cardinality': _handleGlobalCardinality,
  'global_cardinality_closed': _handleGlobalCardinality,

  'bin_packing_load': _handleBinPackingLoad,

  'lex_less': _handleLex(strict: true),
  'lex_lesseq': _handleLex(strict: false),

  'value_precede_chain_int': _handleValuePrecedenceChain,

  'table_int': _handleTableInt,
  'table_bool': _handleTableInt,

  'disjunctive': _handleDisjunctive,
  'cumulative': _handleCumulative,
  'diffn': _handleDiffN,

  'regular': _handleRegular,

  // Reified primitives (M4). Each `*_reif` takes the same args as its
  // non-reified counterpart plus a trailing bool variable `r` such
  // that `r ⇔ <constraint>`.
  'int_eq_reif': _handleIntCmpReif('=='),
  'int_ne_reif': _handleIntCmpReif('!='),
  'int_lt_reif': _handleIntCmpReif('<'),
  'int_le_reif': _handleIntCmpReif('<='),
  'int_gt_reif': _handleIntCmpReif('>'),
  'int_ge_reif': _handleIntCmpReif('>='),

  'int_lin_eq_reif': _handleIntLinReif('=='),
  'int_lin_le_reif': _handleIntLinReif('<='),
  'int_lin_ne_reif': _handleIntLinReif('!='),
  'int_lin_ge_reif': _handleIntLinReif('>='),

  'bool_eq_reif': _handleBoolEqReif,
  'bool_clause_reif': _handleBoolClauseReif,

  // Arithmetic primitives. mzn2fzn often emits `int_lin_eq` for
  // additive constraints, but the dedicated builtins below show up
  // for non-linear cases (abs/min/max/times/div/mod) and for
  // additive flattening when the compiler chose not to introduce
  // a linear constraint (e.g. inside generated indirection).
  'int_abs': _handleIntAbs,
  'int_negate': _handleIntNegate,
  'int_plus': _handleIntAddSub(addition: true),
  'int_minus': _handleIntAddSub(addition: false),
  'int_times': _handleIntTimes,
  'int_div': _handleIntDivMod(mod: false),
  'int_mod': _handleIntDivMod(mod: true),
  'int_min': _handleIntMinMax(minimize: true),
  'int_max': _handleIntMinMax(minimize: false),
  'int_pow': _handleIntPow,

  // Set membership.
  'set_in': _handleSetIn,

  // Array reductions over bool / int.
  'array_bool_and': _handleArrayBoolReduce(op: 'and'),
  'array_bool_or': _handleArrayBoolReduce(op: 'or'),
  'array_int_minimum': _handleArrayMinMax(minimize: true),
  'array_int_maximum': _handleArrayMinMax(minimize: false),
};

void _expectArgs(ConstraintItem c, int n) {
  if (c.args.length != n) {
    throw ArgumentError(
        'FlatZinc constraint \'${c.name}\' expects $n arguments, got '
        '${c.args.length} at line ${c.line}.');
  }
}

// ---------------------------------------------------------------------------
// Integer comparison handlers
// ---------------------------------------------------------------------------

_Handler _handleIntCmp(String op) => (ctx, c) {
      _expectArgs(c, 2);
      final a = ctx.resolveIntOperand(c.args[0]);
      final b = ctx.resolveIntOperand(c.args[1]);
      _postIntCmp(ctx, a, b, op, ctx.labelFor(c.name));
    };

void _postIntCmp(
    LoweringContext ctx, IntOperand a, IntOperand b, String op, String label) {
  final pred = _cmpPredicate(op);
  if (a.isVar && b.isVar) {
    ctx.problem.addConstraint(
      <String>[a.varName!, b.varName!],
      (dynamic x, dynamic y) => pred(x as int, y as int),
      label: label,
    );
  } else if (a.isVar) {
    final cst = b.constant!;
    ctx.problem.addConstraint(
      <String>[a.varName!],
      (Map<String, dynamic> m) => pred(m[a.varName!] as int, cst),
      label: label,
    );
  } else if (b.isVar) {
    final cst = a.constant!;
    ctx.problem.addConstraint(
      <String>[b.varName!],
      (Map<String, dynamic> m) => pred(cst, m[b.varName!] as int),
      label: label,
    );
  } else {
    if (!pred(a.constant!, b.constant!)) {
      _postUnsat(ctx.problem, label);
    }
  }
}

String _negateCmp(String op) {
  switch (op) {
    case '==':
      return '!=';
    case '!=':
      return '==';
    case '<':
      return '>=';
    case '<=':
      return '>';
    case '>':
      return '<=';
    case '>=':
      return '<';
  }
  throw StateError('Unknown comparison: $op');
}

bool Function(int, int) _cmpPredicate(String op) {
  switch (op) {
    case '==':
      return (a, b) => a == b;
    case '!=':
      return (a, b) => a != b;
    case '<':
      return (a, b) => a < b;
    case '<=':
      return (a, b) => a <= b;
    case '>':
      return (a, b) => a > b;
    case '>=':
      return (a, b) => a >= b;
  }
  throw StateError('Unknown comparison: $op');
}

void _postUnsat(Problem problem, String label) {
  // Need at least one variable to attach to; if the problem is
  // genuinely empty we can't post anything (degenerate FZN).
  if (problem.variableCount == 0) {
    throw ArgumentError(
        'FlatZinc constraint is statically unsatisfiable but the model '
        'has no variables to attach an UNSAT marker to.');
  }
  problem.addClause(label: label);
}

// ---------------------------------------------------------------------------
// Linear constraint handlers
// ---------------------------------------------------------------------------

_Handler _handleIntLin(String op) => (ctx, c) {
      _expectArgs(c, 3);
      final rawCoeffs = ctx.resolveIntArray(c.args[0]);
      final rawVars = c.args[1];
      final bound = ctx.resolveInt(c.args[2]);

      // The vars list may contain inline constants (`[x, 5, y]`). Rather
      // than introducing dummy singleton variables for those, we fold
      // constant contributions into the bound and shrink the constraint
      // to just the variable slots.
      final lit = ctx._resolveAsArrayLit(rawVars);
      if (lit.elements.length != rawCoeffs.length) {
        throw ArgumentError(
            'FlatZinc \'${c.name}\' coeffs/vars length mismatch: '
            '${rawCoeffs.length} vs ${lit.elements.length} at line ${c.line}.');
      }

      final folded = _foldLinear(ctx, lit.elements, rawCoeffs, bound);
      final coeffs = folded.coeffs;
      final varNames = folded.varNames;
      final foldedBound = folded.foldedBound;

      final label = ctx.labelFor(c.name);

      if (varNames.isEmpty) {
        // Everything folded into the bound — check the resulting
        // tautology / contradiction statically.
        if (!_linearStaticallyTrue(op, foldedBound)) {
          _postUnsat(ctx.problem, label);
        }
        return;
      }

      switch (op) {
        case '==':
          ctx.problem.addLinearEquals(varNames, coeffs.cast<num>(), foldedBound,
              label: label);
        case '<=':
          ctx.problem.addLinearLeq(varNames, coeffs.cast<num>(), foldedBound,
              label: label);
        case '>=':
          ctx.problem.addLinearGeq(varNames, coeffs.cast<num>(), foldedBound,
              label: label);
        case '!=':
          // No dedicated `!=` linear propagator; encode via predicate.
          // Bounds-consistency is not interesting on `!=` anyway, so the
          // generic n-ary path is the right fit. addConstraint dispatches
          // on the var-list length: with two variables it wants a
          // BinaryPredicate; otherwise a NaryPredicate.
          if (varNames.length == 2) {
            final c0 = coeffs[0];
            final c1 = coeffs[1];
            ctx.problem.addConstraint<bool Function(dynamic, dynamic)>(
              varNames,
              (dynamic a, dynamic b) =>
                  c0 * (a as num) + c1 * (b as num) != foldedBound,
              label: label,
            );
          } else {
            ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
              varNames,
              (Map<String, dynamic> m) {
                num s = 0;
                for (var i = 0; i < varNames.length; i++) {
                  final v = m[varNames[i]];
                  if (v is! num) return true; // partial
                  s += coeffs[i] * v;
                }
                return s != foldedBound;
              },
              label: label,
            );
          }
      }
    };

bool _linearStaticallyTrue(String op, int bound) {
  // After folding all vars away, the LHS is 0 and we compare 0 ∘ bound.
  switch (op) {
    case '==':
      return 0 == bound;
    case '<=':
      return 0 <= bound;
    case '>=':
      return 0 >= bound;
    case '!=':
      return 0 != bound;
  }
  return false;
}

/// Resolve a FlatZinc linear `(coeffs, vars, bound)` triple into a
/// canonical form the propagator can handle:
///   - inline integer-literal slots fold into the bound
///   - inline variable-typed parameters resolve to their referenced
///     variable names
///   - repeated variable names have their coefficients summed (the
///     propagator stores one entry per unique variable, so duplicates
///     would break bounds propagation)
///
/// FlatZinc emits repeated variables freely — the canonical
/// SEND+MORE=MONEY cryptarithm has `e`, `n`, `o`, `m` each appearing
/// 2-3 times across the digit columns. Without merging, the linear
/// propagator would compute the wrong residual when the same
/// variable shows up in multiple slots.
({List<int> coeffs, List<String> varNames, int foldedBound}) _foldLinear(
  LoweringContext ctx,
  List<AstExpr> elements,
  List<int> rawCoeffs,
  int bound,
) {
  // Two-pass: first pass folds constants into the bound and merges
  // variable coefficients into a name → coefficient map; second pass
  // walks the map in insertion order to produce stable output.
  final perVar = <String, int>{};
  var foldedBound = bound;
  for (var i = 0; i < elements.length; i++) {
    final operand = ctx.resolveIntOperand(elements[i]);
    if (operand.isVar) {
      final n = operand.varName!;
      perVar[n] = (perVar[n] ?? 0) + rawCoeffs[i];
    } else {
      foldedBound -= rawCoeffs[i] * operand.constant!;
    }
  }
  // Drop variables whose accumulated coefficient cancelled to zero —
  // they contribute nothing and would needlessly widen the propagator's
  // unique-variable set.
  perVar.removeWhere((_, coef) => coef == 0);
  return (
    coeffs: perVar.values.toList(growable: false),
    varNames: perVar.keys.toList(growable: false),
    foldedBound: foldedBound,
  );
}

// ---------------------------------------------------------------------------
// Boolean handlers
// ---------------------------------------------------------------------------

void _handleBoolEq(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final a = ctx.resolveBoolOperand(c.args[0]);
  final b = ctx.resolveBoolOperand(c.args[1]);
  final label = ctx.labelFor(c.name);

  // Bool equality is just integer equality once we've normalized to
  // 0/1, so reuse the int_eq machinery.
  if (a.isVar && b.isVar) {
    ctx.problem.addConstraint(
      <String>[a.varName!, b.varName!],
      (dynamic x, dynamic y) => x == y,
      label: label,
    );
  } else if (a.isVar) {
    final cst = b.constant!;
    ctx.problem.addConstraint(
      <String>[a.varName!],
      (Map<String, dynamic> m) => m[a.varName!] == cst,
      label: label,
    );
  } else if (b.isVar) {
    final cst = a.constant!;
    ctx.problem.addConstraint(
      <String>[b.varName!],
      (Map<String, dynamic> m) => m[b.varName!] == cst,
      label: label,
    );
  } else {
    if (a.constant != b.constant) _postUnsat(ctx.problem, label);
  }
}

void _handleBoolNot(LoweringContext ctx, ConstraintItem c) {
  // FlatZinc bool_not(a, b) means `b ⇔ ¬a`. Both args may be vars or
  // constants; the all-constant case is statically resolved.
  _expectArgs(c, 2);
  final a = ctx.resolveBoolOperand(c.args[0]);
  final b = ctx.resolveBoolOperand(c.args[1]);
  final label = ctx.labelFor(c.name);

  if (a.isVar && b.isVar) {
    ctx.problem.addReifiedNot(b.varName!, a.varName!, label: label);
  } else if (a.isVar) {
    // b is fixed, so a must be 1 - b.
    final expected = 1 - b.constant!;
    ctx.problem.addConstraint(
      <String>[a.varName!],
      (Map<String, dynamic> m) => m[a.varName!] == expected,
      label: label,
    );
  } else if (b.isVar) {
    final expected = 1 - a.constant!;
    ctx.problem.addConstraint(
      <String>[b.varName!],
      (Map<String, dynamic> m) => m[b.varName!] == expected,
      label: label,
    );
  } else {
    if ((a.constant! ^ 1) != b.constant) _postUnsat(ctx.problem, label);
  }
}

// bool_or(a, b, r), bool_and(a, b, r), bool_xor(a, b, r) all share
// the same three-arg shape: `r ⇔ (a op b)`. We dispatch on `op`
// inside the predicate so the engine sees a single n-ary constraint.
_Handler _handleBoolBin(String op) => (ctx, c) {
      _expectArgs(c, 3);
      final a = ctx.resolveBoolOperand(c.args[0]);
      final b = ctx.resolveBoolOperand(c.args[1]);
      final r = ctx.resolveBoolOperand(c.args[2]);
      final label = ctx.labelFor(c.name);

      bool eval(int x, int y) {
        switch (op) {
          case '||':
            return (x | y) == 1;
          case '&&':
            return (x & y) == 1;
          case 'xor':
            return (x ^ y) == 1;
        }
        throw StateError('Unknown bool op: $op');
      }

      // Fully-constant case — static evaluation.
      if (!a.isVar && !b.isVar && !r.isVar) {
        if (eval(a.constant!, b.constant!) != (r.constant == 1)) {
          _postUnsat(ctx.problem, label);
        }
        return;
      }

      // Generic path: build a variable list (deduped) and evaluate via
      // a Map-keyed predicate. addConstraint requires the binary form
      // when there are exactly 2 vars; we materialize a dummy slot in
      // that case so the predicate stays n-ary.
      final vars = <String>[];
      if (a.isVar) vars.add(a.varName!);
      if (b.isVar && !vars.contains(b.varName)) vars.add(b.varName!);
      if (r.isVar && !vars.contains(r.varName)) vars.add(r.varName!);

      int valueOf(Map<String, dynamic> m, IntOperand operand) =>
          operand.isVar ? m[operand.varName!] as int : operand.constant!;

      if (vars.length == 2) {
        // Binary path: predicate signature must be (dynamic, dynamic).
        // We capture the var names in closure so we can route the
        // positional arguments to the right operands.
        final v0 = vars[0];
        final v1 = vars[1];
        ctx.problem.addConstraint<bool Function(dynamic, dynamic)>(
          vars,
          (dynamic x0, dynamic x1) {
            final m = <String, dynamic>{v0: x0, v1: x1};
            final av = valueOf(m, a);
            final bv = valueOf(m, b);
            final rv = valueOf(m, r);
            return eval(av, bv) == (rv == 1);
          },
          label: label,
        );
      } else {
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          vars,
          (Map<String, dynamic> m) {
            final av = valueOf(m, a);
            final bv = valueOf(m, b);
            final rv = valueOf(m, r);
            return eval(av, bv) == (rv == 1);
          },
          label: label,
        );
      }
    };

void _handleBoolClause(LoweringContext ctx, ConstraintItem c) {
  // bool_clause(positive[], negative[]) — the standard SAT clause
  // form. Both arguments are array literals (or array-parameter refs);
  // each element is a bool variable or a bool literal. We rewrite
  // literals into UNSAT short-circuits or no-ops: a `true` in
  // `positive` (or `false` in `negative`) makes the whole clause
  // vacuously satisfied; the opposite literal contributes nothing.
  _expectArgs(c, 2);
  final pos = ctx._resolveAsArrayLit(c.args[0]).elements;
  final neg = ctx._resolveAsArrayLit(c.args[1]).elements;
  final label = ctx.labelFor(c.name);

  final posVars = <String>[];
  final negVars = <String>[];
  var trivially = false;
  for (final e in pos) {
    final op = ctx.resolveBoolOperand(e);
    op.match<void>(
      onVariable: posVars.add,
      onConstant: (v) {
        if (v == 1) trivially = true;
      },
    );
  }
  for (final e in neg) {
    final op = ctx.resolveBoolOperand(e);
    op.match<void>(
      onVariable: negVars.add,
      onConstant: (v) {
        if (v == 0) trivially = true;
      },
    );
  }
  if (trivially) return;
  if (posVars.isEmpty && negVars.isEmpty) {
    // Empty clause = ⊥.
    _postUnsat(ctx.problem, label);
    return;
  }
  ctx.problem.addClause(positive: posVars, negative: negVars, label: label);
}

void _handleBool2Int(LoweringContext ctx, ConstraintItem c) {
  // bool2int(b, x) — `x == b` with both treated as ints. Engine-level
  // bool and int variables are unified (both use 0/1 domains for
  // bools), so this is just an equality.
  _expectArgs(c, 2);
  final b = ctx.resolveBoolOperand(c.args[0]);
  final x = ctx.resolveIntOperand(c.args[1]);
  final label = ctx.labelFor(c.name);

  if (b.isVar && x.isVar) {
    ctx.problem.addConstraint(
      <String>[b.varName!, x.varName!],
      (dynamic bv, dynamic xv) => bv == xv,
      label: label,
    );
  } else if (b.isVar) {
    final cst = x.constant!;
    ctx.problem.addConstraint(
      <String>[b.varName!],
      (Map<String, dynamic> m) => m[b.varName!] == cst,
      label: label,
    );
  } else if (x.isVar) {
    final cst = b.constant!;
    ctx.problem.addConstraint(
      <String>[x.varName!],
      (Map<String, dynamic> m) => m[x.varName!] == cst,
      label: label,
    );
  } else {
    if (b.constant != x.constant) _postUnsat(ctx.problem, label);
  }
}

// ---------------------------------------------------------------------------
// Global constraint handlers (M3)
// ---------------------------------------------------------------------------

void _handleAllDifferent(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 1);
  final vars = ctx.resolveVarArray(c.args[0]);
  if (vars.length < 2) return; // trivially satisfied
  ctx.problem.addAllDifferent(vars, label: ctx.labelFor(c.name));
}

/// `array_int_element(idx, arr, x)` — FlatZinc semantics:
/// `arr[idx] == x`, with idx 1-indexed into the constant int array
/// `arr`. The Dart `addElement` is 0-indexed; rather than synthesise
/// an `idx - 1` variable, post a direct binary predicate with the
/// 1-based lookup baked in.
void _handleArrayIntElement(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final idxOp = ctx.resolveIntOperand(c.args[0]);
  final list = ctx.resolveIntArray(c.args[1]);
  final valOp = ctx.resolveIntOperand(c.args[2]);
  final label = ctx.labelFor(c.name);

  // Both constants: evaluate statically.
  if (idxOp.isConst && valOp.isConst) {
    final idx = idxOp.constant!;
    if (idx < 1 || idx > list.length || list[idx - 1] != valOp.constant) {
      _postUnsat(ctx.problem, label);
    }
    return;
  }

  // idx const + val var: val must equal the looked-up constant.
  if (idxOp.isConst) {
    final idx = idxOp.constant!;
    if (idx < 1 || idx > list.length) {
      _postUnsat(ctx.problem, label);
      return;
    }
    final fixed = list[idx - 1];
    ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
      <String>[valOp.varName!],
      (Map<String, dynamic> m) => m[valOp.varName!] == fixed,
      label: label,
    );
    return;
  }

  // val const + idx var: idx selects a slot containing val.
  if (valOp.isConst) {
    final target = valOp.constant!;
    ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
      <String>[idxOp.varName!],
      (Map<String, dynamic> m) {
        final i = m[idxOp.varName!];
        if (i is! int || i < 1 || i > list.length) return false;
        return list[i - 1] == target;
      },
      label: label,
    );
    return;
  }

  // Both variables: binary predicate with 1-based lookup.
  ctx.problem.addConstraint<bool Function(dynamic, dynamic)>(
    <String>[idxOp.varName!, valOp.varName!],
    (dynamic i, dynamic v) {
      if (i is! int || i < 1 || i > list.length) return false;
      return list[i - 1] == v;
    },
    label: label,
  );
}

/// `array_var_int_element(idx, arr, val)` — FlatZinc semantics:
/// `arr[idx] == val` where `arr` is an array of **variables**
/// (compare to `array_int_element` whose array is a constant int
/// list). idx is 1-indexed.
///
/// Posts a single n-ary predicate over `[idx, ...arr, val]` so the
/// engine sees one constraint touching every variable involved. The
/// predicate reads idx, indexes into the array (1-based), and
/// compares the selected variable's value to val. Constant idx /
/// val short-circuits to the same handler with a narrower variable
/// set. `array_var_bool_element` shares this code path — bool
/// element variables are 0/1 ints at the engine level so the
/// equality check is identical.
void _handleArrayVarElement(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final idxOp = ctx.resolveIntOperand(c.args[0]);
  final arr = ctx.resolveVarArray(c.args[1]);
  final valOp = ctx.resolveIntOperand(c.args[2]);
  final label = ctx.labelFor(c.name);

  // idx is a constant: collapse to an equality between arr[idx-1]
  // and val. No predicate over the rest of the array needed — the
  // engine handles equality with stronger propagation.
  if (idxOp.isConst) {
    final i = idxOp.constant!;
    if (i < 1 || i > arr.length) {
      _postUnsat(ctx.problem, label);
      return;
    }
    final selectedName = arr[i - 1];
    if (valOp.isConst) {
      // arr[i] == const: pin the selected variable.
      ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
        <String>[selectedName],
        (Map<String, dynamic> m) => m[selectedName] == valOp.constant,
        label: label,
      );
      return;
    }
    // arr[i] == val: simple two-variable equality.
    ctx.problem.addConstraint<bool Function(dynamic, dynamic)>(
      <String>[selectedName, valOp.varName!],
      (dynamic a, dynamic b) => a == b,
      label: label,
    );
    return;
  }

  // idx is a variable. Post the full n-ary predicate.
  final vars = <String>[idxOp.varName!, ...arr];
  if (valOp.isVar && !vars.contains(valOp.varName)) {
    vars.add(valOp.varName!);
  }
  final idxName = idxOp.varName!;

  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    vars,
    (Map<String, dynamic> m) {
      final i = m[idxName];
      if (i is! int || i < 1 || i > arr.length) return false;
      final selected = m[arr[i - 1]];
      final v = valOp.isVar ? m[valOp.varName!] : valOp.constant;
      return selected == v;
    },
    label: label,
  );
}

/// FlatZinc `circuit(x)`: `x[i] = j` (1..N) means node i is followed
/// by node j in a single Hamiltonian cycle. The Dart `addCircuit`
/// assumes 0-based indexing; we instead post a direct n-ary predicate
/// so the FZN domains can stay 1..N.
void _handleCircuit(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 1);
  final vars = ctx.resolveVarArray(c.args[0]);
  if (vars.isEmpty) return;
  final n = vars.length;
  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    vars,
    (Map<String, dynamic> a) {
      final next = List<int>.filled(n + 1, -1);
      for (var i = 0; i < n; i++) {
        final v = a[vars[i]];
        if (v is! int || v < 1 || v > n) return false;
        next[i + 1] = v;
      }
      final visited = List<bool>.filled(n + 1, false);
      var cur = 1;
      for (var k = 0; k < n; k++) {
        if (visited[cur]) return false;
        visited[cur] = true;
        cur = next[cur];
      }
      return cur == 1;
    },
    label: ctx.labelFor(c.name),
  );
}

/// FlatZinc `subcircuit(x)`: same as circuit, plus `x[i] = i` means
/// node i is excluded from the cycle. The remaining (non-self-loop)
/// successors must form a single cycle.
void _handleSubcircuit(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 1);
  final vars = ctx.resolveVarArray(c.args[0]);
  if (vars.isEmpty) return;
  final n = vars.length;
  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    vars,
    (Map<String, dynamic> a) {
      final next = List<int>.filled(n + 1, -1);
      for (var i = 0; i < n; i++) {
        final v = a[vars[i]];
        if (v is! int || v < 1 || v > n) return false;
        next[i + 1] = v;
      }
      // Each value used at most once across the successor list.
      final seen = List<bool>.filled(n + 1, false);
      for (var i = 1; i <= n; i++) {
        if (seen[next[i]]) return false;
        seen[next[i]] = true;
      }
      // Walk the non-self-loop component starting at the first
      // non-excluded node; that walk must close into a cycle covering
      // every non-excluded node exactly once.
      var startIdx = -1;
      for (var i = 1; i <= n; i++) {
        if (next[i] != i) {
          startIdx = i;
          break;
        }
      }
      if (startIdx == -1) return true; // every node excluded
      final visited = List<bool>.filled(n + 1, false);
      var cur = startIdx;
      var count = 0;
      while (!visited[cur]) {
        visited[cur] = true;
        count++;
        cur = next[cur];
        if (cur == startIdx) break;
      }
      if (cur != startIdx) return false;
      // Every other node must be self-looped.
      for (var i = 1; i <= n; i++) {
        if (!visited[i] && next[i] != i) return false;
      }
      return count >= 2;
    },
    label: ctx.labelFor(c.name),
  );
}

/// FlatZinc `inverse(f, invf)`: 1-based — `f[i] = j ⇔ invf[j] = i`.
/// The Dart `addInverse` is 0-based; we post a direct predicate to
/// avoid synthesising offset variables.
void _handleInverse(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final f = ctx.resolveVarArray(c.args[0]);
  final invf = ctx.resolveVarArray(c.args[1]);
  if (f.length != invf.length) {
    throw ArgumentError(
        'FlatZinc \'inverse\' requires equal-length arrays, got '
        '${f.length} and ${invf.length}.');
  }
  final n = f.length;
  final allVars = <String>[...f, ...invf];
  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    allVars,
    (Map<String, dynamic> a) {
      for (var i = 0; i < n; i++) {
        final fi = a[f[i]];
        if (fi is! int || fi < 1 || fi > n) return false;
        final back = a[invf[fi - 1]];
        if (back is! int || back != i + 1) return false;
      }
      return true;
    },
    label: ctx.labelFor(c.name),
  );
}

/// FlatZinc `count_eq(x, y, c)`: `c = |{i : x[i] == y}|`. y and c may
/// both be variables or constants. The most efficient encoding depends
/// on which of y, c are fixed:
///   - y const + c const: `addAmongExactly(x, {y}, c)`
///   - otherwise: post a single n-ary predicate over the full union of
///     variables. This is O(|x|) per check but avoids introducing |x|
///     reified equality auxiliaries.
void _handleCountEq(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final xs = ctx.resolveVarArray(c.args[0]);
  final yOp = ctx.resolveIntOperand(c.args[1]);
  final cOp = ctx.resolveIntOperand(c.args[2]);
  final label = ctx.labelFor(c.name);

  if (yOp.isConst && cOp.isConst) {
    final k = cOp.constant!;
    if (k < 0 || k > xs.length) {
      _postUnsat(ctx.problem, label);
      return;
    }
    ctx.problem.addAmongExactly(xs, <dynamic>{yOp.constant}, k, label: label);
    return;
  }

  final allVars = <String>[
    ...xs,
    if (yOp.isVar) yOp.varName!,
    if (cOp.isVar) cOp.varName!,
  ];
  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    allVars,
    (Map<String, dynamic> a) {
      final y = yOp.isVar ? a[yOp.varName!] : yOp.constant;
      final cc = cOp.isVar ? a[cOp.varName!] : cOp.constant;
      var hits = 0;
      for (final x in xs) {
        if (a[x] == y) hits++;
      }
      return hits == cc;
    },
    label: label,
  );
}

/// FlatZinc `nvalue(n, x)`: `n = |distinct values across x|`. The
/// Dart API takes args in `(x, n)` order — flip them at lowering.
void _handleNvalue(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final nOp = ctx.resolveIntOperand(c.args[0]);
  final xs = ctx.resolveVarArray(c.args[1]);
  final label = ctx.labelFor(c.name);
  if (nOp.isConst) {
    ctx.problem.addNvalueExactly(xs, nOp.constant!, label: label);
  } else {
    ctx.problem.addNvalue(xs, nOp.varName!, label: label);
  }
}

/// FlatZinc `global_cardinality(x, cover, counts)`: each element of
/// `counts` is the number of times the corresponding `cover` value
/// occurs in `x`. The Dart API only handles fixed integer counts via
/// `addGcc`; when `counts` is an array of variables we fall back to
/// per-cover-value `count_eq`-style decompositions.
void _handleGlobalCardinality(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final xs = ctx.resolveVarArray(c.args[0]);
  final cover = ctx.resolveIntArray(c.args[1]);
  final countsLit = ctx._resolveAsArrayLit(c.args[2]);
  if (cover.length != countsLit.elements.length) {
    throw ArgumentError(
        'FlatZinc \'global_cardinality\' cover/counts length mismatch: '
        '${cover.length} vs ${countsLit.elements.length}.');
  }
  final label = ctx.labelFor(c.name);

  // Try the all-const fast path: every counts[i] resolves to a constant.
  final fixedCounts = <int>[];
  var allConst = true;
  for (final e in countsLit.elements) {
    final op = ctx.resolveIntOperand(e);
    if (op.isVar) {
      allConst = false;
      break;
    }
    fixedCounts.add(op.constant!);
  }
  if (allConst) {
    final map = <dynamic, int>{
      for (var i = 0; i < cover.length; i++) cover[i]: fixedCounts[i],
    };
    ctx.problem.addGcc(xs, map, label: label);
    return;
  }

  // Variable-counts path: post one count_eq-equivalent per cover value.
  // The count variable equals the number of x[i] == cover[k]; we
  // express this as an n-ary predicate over xs + the count variable so
  // the engine sees one constraint per cover value (still small).
  for (var k = 0; k < cover.length; k++) {
    final coverVal = cover[k];
    final cOp = ctx.resolveIntOperand(countsLit.elements[k]);
    if (cOp.isConst) {
      ctx.problem.addAmongExactly(xs, <dynamic>{coverVal}, cOp.constant!,
          label: label);
      continue;
    }
    final cName = cOp.varName!;
    ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
      <String>[...xs, cName],
      (Map<String, dynamic> a) {
        var hits = 0;
        for (final v in xs) {
          if (a[v] == coverVal) hits++;
        }
        return a[cName] == hits;
      },
      label: label,
    );
  }
}

/// FlatZinc `bin_packing_load(load, bin, w)`: 1-based bin indices.
/// `bin[i] = b` puts item i (size w[i]) in bin b; load[b] is the sum
/// of sizes of items assigned to bin b. Our `addBinPacking` takes
/// `(items, sizes, binLoads)` and expects 0-based bin indices.
/// Rather than synthesise offset variables, we post a direct
/// predicate that does the 1-based bookkeeping inline.
void _handleBinPackingLoad(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final loads = ctx.resolveVarArray(c.args[0]);
  final items = ctx.resolveVarArray(c.args[1]);
  final sizes = ctx.resolveIntArray(c.args[2]);
  if (items.length != sizes.length) {
    throw ArgumentError(
        'FlatZinc \'bin_packing_load\' items/sizes length mismatch: '
        '${items.length} vs ${sizes.length}.');
  }
  final nBins = loads.length;
  final label = ctx.labelFor(c.name);
  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    <String>[...loads, ...items],
    (Map<String, dynamic> a) {
      final running = List<int>.filled(nBins + 1, 0); // 1-based bins
      for (var i = 0; i < items.length; i++) {
        final b = a[items[i]];
        if (b is! int || b < 1 || b > nBins) return false;
        running[b] += sizes[i];
      }
      for (var b = 1; b <= nBins; b++) {
        final declared = a[loads[b - 1]];
        if (declared is! num) return true; // partial
        if (declared != running[b]) return false;
      }
      return true;
    },
    label: label,
  );
}

_Handler _handleLex({required bool strict}) => (ctx, c) {
      _expectArgs(c, 2);
      final left = ctx.resolveVarArray(c.args[0]);
      final right = ctx.resolveVarArray(c.args[1]);
      if (left.length != right.length) {
        throw ArgumentError(
            'FlatZinc \'lex\' constraint requires equal-length arrays, got '
            '${left.length} and ${right.length}.');
      }
      final label = ctx.labelFor(c.name);
      if (strict) {
        ctx.problem.addLexLt(left, right, label: label);
      } else {
        ctx.problem.addLexLeq(left, right, label: label);
      }
    };

/// FlatZinc `value_precede_chain_int(c, x)`: c is an array of values;
/// successive c values must first appear in x in c's order.
void _handleValuePrecedenceChain(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final values = ctx.resolveIntArray(c.args[0]);
  final xs = ctx.resolveVarArray(c.args[1]);
  if (values.length < 2) return;
  ctx.problem.addValuePrecedence(xs, values.cast<dynamic>(),
      label: ctx.labelFor(c.name));
}

/// FlatZinc `table_int(x, t)`: `t` is a flattened 2D matrix of allowed
/// tuples, length `|x| * m` where `m` is the number of tuples.
void _handleTableInt(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final xs = ctx.resolveVarArray(c.args[0]);
  final flat = ctx.resolveIntArray(c.args[1]);
  final width = xs.length;
  if (flat.length % width != 0) {
    throw ArgumentError(
        'FlatZinc \'table_int\' flat tuple list of length ${flat.length} '
        'is not a multiple of variable count $width.');
  }
  final tuples = <List<dynamic>>[
    for (var i = 0; i < flat.length; i += width)
      <dynamic>[for (var j = 0; j < width; j++) flat[i + j]],
  ];
  ctx.problem.addTable(xs, tuples, label: ctx.labelFor(c.name));
}

/// FlatZinc `disjunctive(s, d)`: no-overlap. Durations must resolve to
/// integer constants for the Dart `addNoOverlap` API.
void _handleDisjunctive(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final starts = ctx.resolveVarArray(c.args[0]);
  final durations = ctx.resolveIntArray(c.args[1]);
  ctx.problem.addNoOverlap(starts, durations, label: ctx.labelFor(c.name));
}

/// FlatZinc `cumulative(s, d, r, b)`: durations, demands, and capacity
/// must resolve to integer constants for the Dart `addCumulative` API.
/// Variable durations/demands would require a fresh predicate-based
/// encoding; we defer that to a follow-up if it becomes needed.
void _handleCumulative(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 4);
  final starts = ctx.resolveVarArray(c.args[0]);
  final durations = ctx.resolveIntArray(c.args[1]);
  final demands = ctx.resolveIntArray(c.args[2]);
  final capacity = ctx.resolveInt(c.args[3]);
  ctx.problem.addCumulative(starts, durations, demands, capacity,
      label: ctx.labelFor(c.name));
}

/// FlatZinc `diffn(x, y, dx, dy)`: rectangular non-overlap. Widths
/// and heights must resolve to integer constants for the Dart
/// `addDiffN` API.
void _handleDiffN(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 4);
  final xs = ctx.resolveVarArray(c.args[0]);
  final ys = ctx.resolveVarArray(c.args[1]);
  final ws = ctx.resolveIntArray(c.args[2]);
  final hs = ctx.resolveIntArray(c.args[3]);
  ctx.problem.addDiffN(xs, ys, ws, hs, label: ctx.labelFor(c.name));
}

/// FlatZinc `regular(x, Q, S, T, q0, F)`. T is a flattened Q×S
/// transition table (1-based states, 0 for trap). We translate to
/// the 0-based Dart `Dfa` representation; symbol values stay verbatim
/// (FlatZinc symbols are the values of the variables in x, which we
/// preserve as the inner map's key).
void _handleRegular(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 6);
  final xs = ctx.resolveVarArray(c.args[0]);
  final q = ctx.resolveInt(c.args[1]);
  final s = ctx.resolveInt(c.args[2]);
  final flatT = ctx.resolveIntArray(c.args[3]);
  final q0 = ctx.resolveInt(c.args[4]);
  final acceptingExpr = c.args[5];
  if (flatT.length != q * s) {
    throw ArgumentError(
        'FlatZinc \'regular\' transition table length ${flatT.length} '
        'does not match Q*S = ${q * s}.');
  }
  final accepting = <int>{};
  if (acceptingExpr is AstSetLit) {
    for (final r in acceptingExpr.ranges) {
      for (var st = r.min; st <= r.max; st++) {
        accepting.add(st - 1); // 1-based → 0-based
      }
    }
  } else {
    throw ArgumentError(
        'FlatZinc \'regular\' accepting-state set must be a set literal, '
        'got: $acceptingExpr');
  }
  final transitions = <int, Map<dynamic, int>>{};
  for (var state = 1; state <= q; state++) {
    final inner = <dynamic, int>{};
    for (var sym = 1; sym <= s; sym++) {
      final dest = flatT[(state - 1) * s + (sym - 1)];
      if (dest == 0) continue; // trap
      inner[sym] = dest - 1;
    }
    transitions[state - 1] = inner;
  }
  final dfa = Dfa(
    numStates: q,
    start: q0 - 1,
    accepting: accepting,
    transitions: transitions,
  );
  ctx.problem.addRegular(xs, dfa, label: ctx.labelFor(c.name));
}

// ---------------------------------------------------------------------------
// Reified primitives (M4)
// ---------------------------------------------------------------------------

/// `int_<op>_reif(a, b, r)` — `r ⇔ (a <op> b)`. Three argument-shape
/// classes drive the dispatch:
///   - r constant: collapse to a non-reified comparison (possibly
///     negated when r = 0)
///   - r variable, one of a/b constant: use the specialized
///     `addReifiedXxx(boolVar, variable, constant)` family
///   - r variable, both a/b variables: for `==`/`!=` there's a direct
///     `addReifiedEqualsVar`; for the inequalities we fall through to
///     the generic `addReified` with a predicate
_Handler _handleIntCmpReif(String op) => (ctx, c) {
      _expectArgs(c, 3);
      final a = ctx.resolveIntOperand(c.args[0]);
      final b = ctx.resolveIntOperand(c.args[1]);
      final r = ctx.resolveBoolOperand(c.args[2]);
      final label = ctx.labelFor(c.name);

      if (r.isConst) {
        final effectiveOp = r.constant == 1 ? op : _negateCmp(op);
        _postIntCmp(ctx, a, b, effectiveOp, label);
        return;
      }
      final rName = r.varName!;
      // a, b both constants → r is statically determined.
      if (!a.isVar && !b.isVar) {
        final holds = _cmpPredicate(op)(a.constant!, b.constant!);
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          <String>[rName],
          (Map<String, dynamic> m) => m[rName] == (holds ? 1 : 0),
          label: label,
        );
        return;
      }
      // Specialized one-var-one-const reified APIs cover ==, !=, <, <=,
      // >, >= directly. Pick the right helper based on which side is
      // const and remap the operator if the constant is on the left.
      if (a.isVar && b.isConst) {
        _postReifiedVarConst(ctx, rName, a.varName!, b.constant!, op, label);
        return;
      }
      if (a.isConst && b.isVar) {
        // (const op var) is equivalent to (var op' const) with the
        // operator reversed. e.g. `5 < y` ⇔ `y > 5`.
        _postReifiedVarConst(
            ctx, rName, b.varName!, a.constant!, _swapCmp(op), label);
        return;
      }
      // Both a, b are variables. For == / != we have a specialized
      // helper; for everything else fall back to the generic reified.
      switch (op) {
        case '==':
          ctx.problem
              .addReifiedEqualsVar(rName, a.varName!, b.varName!, label: label);
        case '!=':
          // r ⇔ a != b is `r ⇔ NOT (a == b)` — we use the generic
          // addReified with a predicate to avoid introducing an
          // intermediate bool.
          ctx.problem.addReified(
            rName,
            <String>[a.varName!, b.varName!],
            (Map<String, dynamic> m) => m[a.varName!] != m[b.varName!],
            label: label,
          );
        default:
          final pred = _cmpPredicate(op);
          ctx.problem.addReified(
            rName,
            <String>[a.varName!, b.varName!],
            (Map<String, dynamic> m) =>
                pred(m[a.varName!] as int, m[b.varName!] as int),
            label: label,
          );
      }
    };

void _postReifiedVarConst(LoweringContext ctx, String rName, String varName,
    int constant, String op, String label) {
  switch (op) {
    case '==':
      ctx.problem.addReifiedEquals(rName, varName, constant, label: label);
    case '!=':
      ctx.problem.addReifiedNotEquals(rName, varName, constant, label: label);
    case '<':
      ctx.problem.addReifiedLessThan(rName, varName, constant, label: label);
    case '<=':
      ctx.problem.addReifiedLessOrEqual(rName, varName, constant, label: label);
    case '>':
      ctx.problem.addReifiedGreaterThan(rName, varName, constant, label: label);
    case '>=':
      ctx.problem
          .addReifiedGreaterOrEqual(rName, varName, constant, label: label);
    default:
      throw StateError('Unknown comparison: $op');
  }
}

/// `op` reversed when operands are swapped: `a < b` ⇔ `b > a`.
String _swapCmp(String op) {
  switch (op) {
    case '==':
    case '!=':
      return op;
    case '<':
      return '>';
    case '<=':
      return '>=';
    case '>':
      return '<';
    case '>=':
      return '<=';
  }
  throw StateError('Unknown comparison: $op');
}

/// `int_lin_<op>_reif(coeffs, vars, k, r)` — `r ⇔ Σ coeffs[i]·vars[i] <op> k`.
/// Mirrors the non-reified `_handleIntLin` but routes through the
/// generic `addReified` for variable r, and through bool-evaluation
/// when r is constant.
_Handler _handleIntLinReif(String op) => (ctx, c) {
      _expectArgs(c, 4);
      final rawCoeffs = ctx.resolveIntArray(c.args[0]);
      final rawVars = c.args[1];
      final bound = ctx.resolveInt(c.args[2]);
      final r = ctx.resolveBoolOperand(c.args[3]);
      final label = ctx.labelFor(c.name);

      // Fold inline-constant slots into the bound and merge repeated
      // variable coefficients, same as the non-reified linear handler.
      final lit = ctx._resolveAsArrayLit(rawVars);
      if (lit.elements.length != rawCoeffs.length) {
        throw ArgumentError(
            'FlatZinc \'${c.name}\' coeffs/vars length mismatch: '
            '${rawCoeffs.length} vs ${lit.elements.length} at line ${c.line}.');
      }
      final folded = _foldLinear(ctx, lit.elements, rawCoeffs, bound);
      final coeffs = folded.coeffs;
      final varNames = folded.varNames;
      final foldedBound = folded.foldedBound;

      bool linHolds(Map<String, dynamic> m) {
        num s = 0;
        for (var i = 0; i < varNames.length; i++) {
          final v = m[varNames[i]];
          if (v is! num) return false;
          s += coeffs[i] * v;
        }
        switch (op) {
          case '==':
            return s == foldedBound;
          case '!=':
            return s != foldedBound;
          case '<=':
            return s <= foldedBound;
          case '>=':
            return s >= foldedBound;
        }
        throw StateError('Unknown linear op: $op');
      }

      if (r.isConst) {
        final positive = r.constant == 1;
        if (varNames.isEmpty) {
          // Vars fully folded — evaluate the static residue.
          final holds = _linearStaticallyTrue(op, foldedBound);
          if (positive ? !holds : holds) _postUnsat(ctx.problem, label);
          return;
        }
        final effectiveOp = positive ? op : _negateLinOp(op);
        _postIntLin(ctx, effectiveOp, varNames, coeffs, foldedBound, label);
        return;
      }

      final rName = r.varName!;
      if (varNames.isEmpty) {
        final holds = _linearStaticallyTrue(op, foldedBound);
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          <String>[rName],
          (Map<String, dynamic> m) => m[rName] == (holds ? 1 : 0),
          label: label,
        );
        return;
      }
      ctx.problem.addReified(rName, varNames, linHolds, label: label);
    };

void _postIntLin(LoweringContext ctx, String op, List<String> varNames,
    List<int> coeffs, int foldedBound, String label) {
  switch (op) {
    case '==':
      ctx.problem.addLinearEquals(varNames, coeffs.cast<num>(), foldedBound,
          label: label);
    case '<=':
      ctx.problem.addLinearLeq(varNames, coeffs.cast<num>(), foldedBound,
          label: label);
    case '>=':
      ctx.problem.addLinearGeq(varNames, coeffs.cast<num>(), foldedBound,
          label: label);
    case '!=':
      if (varNames.length == 2) {
        final c0 = coeffs[0];
        final c1 = coeffs[1];
        ctx.problem.addConstraint<bool Function(dynamic, dynamic)>(
          varNames,
          (dynamic a, dynamic b) =>
              c0 * (a as num) + c1 * (b as num) != foldedBound,
          label: label,
        );
      } else {
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          varNames,
          (Map<String, dynamic> m) {
            num s = 0;
            for (var i = 0; i < varNames.length; i++) {
              final v = m[varNames[i]];
              if (v is! num) return true;
              s += coeffs[i] * v;
            }
            return s != foldedBound;
          },
          label: label,
        );
      }
  }
}

String _negateLinOp(String op) {
  switch (op) {
    case '==':
      return '!=';
    case '!=':
      return '==';
    case '<=':
      return '>=';
    case '>=':
      return '<=';
  }
  throw StateError('Unknown linear op: $op');
}

void _handleBoolEqReif(LoweringContext ctx, ConstraintItem c) {
  // r ⇔ (a == b), treating bools as the underlying 0/1 ints.
  _expectArgs(c, 3);
  final a = ctx.resolveBoolOperand(c.args[0]);
  final b = ctx.resolveBoolOperand(c.args[1]);
  final r = ctx.resolveBoolOperand(c.args[2]);
  final label = ctx.labelFor(c.name);

  if (r.isConst) {
    final effectiveOp = r.constant == 1 ? '==' : '!=';
    _postIntCmp(ctx, a, b, effectiveOp, label);
    return;
  }
  final rName = r.varName!;
  if (!a.isVar && !b.isVar) {
    final holds = a.constant == b.constant;
    ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
      <String>[rName],
      (Map<String, dynamic> m) => m[rName] == (holds ? 1 : 0),
      label: label,
    );
    return;
  }
  if (a.isVar && b.isConst) {
    ctx.problem.addReifiedEquals(rName, a.varName!, b.constant, label: label);
    return;
  }
  if (b.isVar && a.isConst) {
    ctx.problem.addReifiedEquals(rName, b.varName!, a.constant, label: label);
    return;
  }
  ctx.problem.addReifiedEqualsVar(rName, a.varName!, b.varName!, label: label);
}

void _handleBoolClauseReif(LoweringContext ctx, ConstraintItem c) {
  // r ⇔ (clause holds). Build the predicate over the union of pos +
  // neg literals (excluding any pre-resolved trivially-true/false
  // sub-literals) and route through addReified. Trivially-true
  // clauses force r = 1; empty (false) clauses force r = 0.
  _expectArgs(c, 3);
  final pos = ctx._resolveAsArrayLit(c.args[0]).elements;
  final neg = ctx._resolveAsArrayLit(c.args[1]).elements;
  final r = ctx.resolveBoolOperand(c.args[2]);
  final label = ctx.labelFor(c.name);

  final posVars = <String>[];
  final negVars = <String>[];
  var trivially = false;
  for (final e in pos) {
    final op = ctx.resolveBoolOperand(e);
    op.match<void>(
      onVariable: posVars.add,
      onConstant: (v) {
        if (v == 1) trivially = true;
      },
    );
  }
  for (final e in neg) {
    final op = ctx.resolveBoolOperand(e);
    op.match<void>(
      onVariable: negVars.add,
      onConstant: (v) {
        if (v == 0) trivially = true;
      },
    );
  }

  if (r.isConst) {
    // r is 1 → clause must hold; r is 0 → clause must fail.
    final required = r.constant == 1;
    if (trivially) {
      if (!required) _postUnsat(ctx.problem, label);
      return;
    }
    if (posVars.isEmpty && negVars.isEmpty) {
      // Empty clause is ⊥; r=1 makes the model UNSAT, r=0 is a no-op.
      if (required) _postUnsat(ctx.problem, label);
      return;
    }
    if (required) {
      ctx.problem.addClause(positive: posVars, negative: negVars, label: label);
    } else {
      // ¬(p ∨ q ∨ ¬x) is (¬p ∧ ¬q ∧ x): each positive var must be 0,
      // each negative var must be 1.
      for (final v in posVars) {
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          <String>[v],
          (Map<String, dynamic> m) => m[v] == 0,
          label: label,
        );
      }
      for (final v in negVars) {
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          <String>[v],
          (Map<String, dynamic> m) => m[v] == 1,
          label: label,
        );
      }
    }
    return;
  }

  final rName = r.varName!;
  if (trivially) {
    // Clause is always true ⇒ r must be 1.
    ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
      <String>[rName],
      (Map<String, dynamic> m) => m[rName] == 1,
      label: label,
    );
    return;
  }
  if (posVars.isEmpty && negVars.isEmpty) {
    // Empty clause ⇒ r must be 0.
    ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
      <String>[rName],
      (Map<String, dynamic> m) => m[rName] == 0,
      label: label,
    );
    return;
  }
  ctx.problem.addReified(
    rName,
    <String>{...posVars, ...negVars}.toList(),
    (Map<String, dynamic> m) {
      for (final v in posVars) {
        if (m[v] == 1) return true;
      }
      for (final v in negVars) {
        if (m[v] == 0) return true;
      }
      return false;
    },
    label: label,
  );
}

// ---------------------------------------------------------------------------
// Arithmetic primitive handlers
// ---------------------------------------------------------------------------

/// Build the variable list and per-operand readers, transparently
/// handling the var/const distinction. Returns `(uniqueVars,
/// reader-per-operand)`.
({List<String> vars, List<int Function(Map<String, dynamic>)> readers})
    _operandReaders(List<IntOperand> operands) {
  final vars = <String>[];
  final readers = <int Function(Map<String, dynamic>)>[];
  for (final op in operands) {
    if (op.isVar) {
      final n = op.varName!;
      if (!vars.contains(n)) vars.add(n);
      readers.add((m) => m[n] as int);
    } else {
      final v = op.constant!;
      readers.add((_) => v);
    }
  }
  return (vars: vars, readers: readers);
}

/// Post an arithmetic constraint over the given operands. Dispatches
/// on the unique-variable count to the right `addConstraint` path
/// (binary vs n-ary) since the engine requires different predicate
/// signatures for each.
void _postArithmetic(LoweringContext ctx, List<IntOperand> operands,
    bool Function(List<int> values) check, String label) {
  final pack = _operandReaders(operands);
  if (pack.vars.isEmpty) {
    final vals = <int>[
      for (final r in pack.readers) r(const <String, dynamic>{})
    ];
    if (!check(vals)) _postUnsat(ctx.problem, label);
    return;
  }
  if (pack.vars.length == 2) {
    final v0 = pack.vars[0];
    final v1 = pack.vars[1];
    ctx.problem.addConstraint<bool Function(dynamic, dynamic)>(
      pack.vars,
      (dynamic a, dynamic b) {
        final m = <String, dynamic>{v0: a, v1: b};
        final vals = <int>[for (final r in pack.readers) r(m)];
        return check(vals);
      },
      label: label,
    );
    return;
  }
  ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
    pack.vars,
    (Map<String, dynamic> m) {
      final vals = <int>[for (final r in pack.readers) r(m)];
      return check(vals);
    },
    label: label,
  );
}

/// `int_abs(a, b)` — `b = |a|`.
void _handleIntAbs(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final a = ctx.resolveIntOperand(c.args[0]);
  final b = ctx.resolveIntOperand(c.args[1]);
  _postArithmetic(ctx, <IntOperand>[a, b], (vs) => vs[1] == vs[0].abs(),
      ctx.labelFor(c.name));
}

/// `int_negate(a, b)` — `b = -a`.
void _handleIntNegate(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final a = ctx.resolveIntOperand(c.args[0]);
  final b = ctx.resolveIntOperand(c.args[1]);
  _postArithmetic(
      ctx, <IntOperand>[a, b], (vs) => vs[1] == -vs[0], ctx.labelFor(c.name));
}

/// `int_plus(a, b, c)` — `c = a + b`. `int_minus(a, b, c)` — `c = a - b`.
/// When all three operands are variables we route through
/// `addLinearEquals` for the stronger bounds-consistency propagator;
/// otherwise post a per-operand predicate.
_Handler _handleIntAddSub({required bool addition}) => (ctx, c) {
      _expectArgs(c, 3);
      final a = ctx.resolveIntOperand(c.args[0]);
      final b = ctx.resolveIntOperand(c.args[1]);
      final r = ctx.resolveIntOperand(c.args[2]);
      final label = ctx.labelFor(c.name);

      if (a.isVar && b.isVar && r.isVar) {
        final bCoef = addition ? 1 : -1;
        ctx.problem.addLinearEquals(
          <String>[a.varName!, b.varName!, r.varName!],
          <num>[1, bCoef, -1],
          0,
          label: label,
        );
        return;
      }
      _postArithmetic(
        ctx,
        <IntOperand>[a, b, r],
        (vs) => addition ? vs[2] == vs[0] + vs[1] : vs[2] == vs[0] - vs[1],
        label,
      );
    };

/// `int_times(a, b, c)` — `c = a * b`. Non-linear; predicate-only.
void _handleIntTimes(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final a = ctx.resolveIntOperand(c.args[0]);
  final b = ctx.resolveIntOperand(c.args[1]);
  final r = ctx.resolveIntOperand(c.args[2]);
  _postArithmetic(ctx, <IntOperand>[a, b, r], (vs) => vs[2] == vs[0] * vs[1],
      ctx.labelFor(c.name));
}

/// FlatZinc int_div / int_mod use truncating semantics: the quotient
/// truncates toward zero (Dart's `~/`) and the remainder takes the
/// sign of the dividend (Dart's `remainder`). Both reject divisor = 0.
_Handler _handleIntDivMod({required bool mod}) => (ctx, c) {
      _expectArgs(c, 3);
      final a = ctx.resolveIntOperand(c.args[0]);
      final b = ctx.resolveIntOperand(c.args[1]);
      final r = ctx.resolveIntOperand(c.args[2]);
      _postArithmetic(ctx, <IntOperand>[a, b, r], (vs) {
        if (vs[1] == 0) return false;
        if (mod) {
          return vs[2] == vs[0].remainder(vs[1]);
        }
        return vs[2] == vs[0] ~/ vs[1];
      }, ctx.labelFor(c.name));
    };

/// `int_min(a, b, c)` — `c = min(a, b)`. `int_max(a, b, c)` —
/// `c = max(a, b)`.
_Handler _handleIntMinMax({required bool minimize}) => (ctx, c) {
      _expectArgs(c, 3);
      final a = ctx.resolveIntOperand(c.args[0]);
      final b = ctx.resolveIntOperand(c.args[1]);
      final r = ctx.resolveIntOperand(c.args[2]);
      _postArithmetic(
        ctx,
        <IntOperand>[a, b, r],
        (vs) =>
            vs[2] ==
            (minimize
                ? (vs[0] < vs[1] ? vs[0] : vs[1])
                : (vs[0] > vs[1] ? vs[0] : vs[1])),
        ctx.labelFor(c.name),
      );
    };

/// `int_pow(a, b, c)` — `c = a ^ b`. Predicate-only; non-negative
/// exponent only (FlatZinc spec).
void _handleIntPow(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 3);
  final a = ctx.resolveIntOperand(c.args[0]);
  final b = ctx.resolveIntOperand(c.args[1]);
  final r = ctx.resolveIntOperand(c.args[2]);
  _postArithmetic(ctx, <IntOperand>[a, b, r], (vs) {
    if (vs[1] < 0) return false;
    var acc = 1;
    for (var i = 0; i < vs[1]; i++) {
      acc *= vs[0];
    }
    return vs[2] == acc;
  }, ctx.labelFor(c.name));
}

/// `set_in(x, S)` — variable `x` must take a value in the literal
/// set `S`. The set is provided as either a range literal (`1..10`)
/// or an explicit enumeration (`{1, 3, 5}`); the parser exposes both
/// as `AstSetLit`.
void _handleSetIn(LoweringContext ctx, ConstraintItem c) {
  _expectArgs(c, 2);
  final x = ctx.resolveIntOperand(c.args[0]);
  final setExpr = c.args[1];
  if (setExpr is! AstSetLit) {
    throw ArgumentError(
        'FlatZinc \'set_in\' second argument must be a set literal, '
        'got: $setExpr');
  }
  final allowed = <int>{};
  for (final r in setExpr.ranges) {
    for (var v = r.min; v <= r.max; v++) {
      allowed.add(v);
    }
  }
  final label = ctx.labelFor(c.name);

  if (x.isConst) {
    if (!allowed.contains(x.constant)) _postUnsat(ctx.problem, label);
    return;
  }
  ctx.problem.addInSet(<String>[x.varName!], allowed, label: label);
}

/// `array_bool_and(bs, r)` — `r ⇔ ⋀ bs`. `array_bool_or` likewise.
/// FlatZinc passes `bs` as an array literal of bool literals / bool
/// vars and `r` as a single bool var / literal.
_Handler _handleArrayBoolReduce({required String op}) => (ctx, c) {
      _expectArgs(c, 2);
      final lit = ctx._resolveAsArrayLit(c.args[0]);
      final r = ctx.resolveBoolOperand(c.args[1]);
      final label = ctx.labelFor(c.name);

      // Walk the array, classifying each element as known-true,
      // known-false, or a variable to be reduced.
      final vars = <String>[];
      var anyForcedFalse = false;
      var allForcedTrue = true;
      for (final e in lit.elements) {
        final op2 = ctx.resolveBoolOperand(e);
        if (op2.isConst) {
          if (op2.constant == 0) anyForcedFalse = true;
          if (op2.constant != 1) allForcedTrue = false;
        } else {
          allForcedTrue = false;
          vars.add(op2.varName!);
        }
      }

      // Statically resolved cases short-circuit.
      bool? resolved;
      if (op == 'and' && anyForcedFalse) resolved = false;
      if (op == 'and' && vars.isEmpty && allForcedTrue) resolved = true;
      if (op == 'or' && allForcedTrue && vars.isEmpty) resolved = true;
      // For "or": if any const is 1, the disjunction holds regardless.
      // We track that via the `vars.isEmpty && some-const-1` check below.
      var anyConstTrue = false;
      for (final e in lit.elements) {
        final op2 = ctx.resolveBoolOperand(e);
        if (op2.isConst && op2.constant == 1) anyConstTrue = true;
      }
      if (op == 'or' && anyConstTrue) resolved = true;
      if (op == 'or' && vars.isEmpty && !anyConstTrue) resolved = false;

      if (resolved != null) {
        if (r.isConst) {
          if ((r.constant == 1) != resolved) _postUnsat(ctx.problem, label);
          return;
        }
        final fixed = resolved ? 1 : 0;
        ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
          <String>[r.varName!],
          (Map<String, dynamic> m) => m[r.varName!] == fixed,
          label: label,
        );
        return;
      }

      // Otherwise route through the existing reified-and / -or helpers.
      // The constant-true elements drop out of the reduction (vacuous
      // for AND; the disjunction case is already handled above).
      if (r.isConst) {
        if (op == 'and') {
          if (r.constant == 1) {
            // All vars must be 1.
            for (final v in vars) {
              ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
                <String>[v],
                (Map<String, dynamic> m) => m[v] == 1,
                label: label,
              );
            }
          } else {
            // ¬AND — at least one of vars must be 0.
            ctx.problem.addClause(negative: vars, label: label);
          }
        } else {
          // op == 'or'
          if (r.constant == 1) {
            ctx.problem.addClause(positive: vars, label: label);
          } else {
            for (final v in vars) {
              ctx.problem.addConstraint<bool Function(Map<String, dynamic>)>(
                <String>[v],
                (Map<String, dynamic> m) => m[v] == 0,
                label: label,
              );
            }
          }
        }
        return;
      }

      if (op == 'and') {
        ctx.problem.addReifiedAnd(r.varName!, vars, label: label);
      } else {
        ctx.problem.addReifiedOr(r.varName!, vars, label: label);
      }
    };

/// `array_int_minimum(m, arr)` — `m = min(arr)`.
/// `array_int_maximum(m, arr)` — `m = max(arr)`.
_Handler _handleArrayMinMax({required bool minimize}) => (ctx, c) {
      _expectArgs(c, 2);
      final m = ctx.resolveIntOperand(c.args[0]);
      final lit = ctx._resolveAsArrayLit(c.args[1]);
      final label = ctx.labelFor(c.name);
      if (lit.elements.isEmpty) {
        throw ArgumentError(
            'FlatZinc \'${c.name}\' over an empty array is undefined.');
      }

      final operands = <IntOperand>[m];
      for (final e in lit.elements) {
        operands.add(ctx.resolveIntOperand(e));
      }

      _postArithmetic(ctx, operands, (vs) {
        // vs[0] is m; vs[1..] is the array. Find min/max and compare.
        var acc = vs[1];
        for (var i = 2; i < vs.length; i++) {
          if (minimize ? vs[i] < acc : vs[i] > acc) acc = vs[i];
        }
        return vs[0] == acc;
      }, label);
    };

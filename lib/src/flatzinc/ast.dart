/// FlatZinc AST nodes — M1 subset.
///
/// Covers variable declarations, array variable declarations, parameter
/// declarations (M2 starts using them but the AST shape lives here), the
/// solve item, and the literal forms that appear in declarations.
///
/// Sealed classes are used in preference to discriminated records so the
/// shape matches the rest of the library (cf. `_SearchResult` in
/// `solver.dart`). See MINIZINC_PLAN.md §5 for the rationale.
library;

/// Top-level parse result. The lowering pass consumes one of these.
class FlatZincModel {
  FlatZincModel({
    required this.params,
    required this.vars,
    required this.arrays,
    required this.constraints,
    required this.solve,
  });

  /// Parameter declarations (`int: n = 5;`). Stored in declaration order.
  final List<ParamDecl> params;

  /// Scalar variable declarations.
  final List<VarDecl> vars;

  /// Array-of-var declarations.
  final List<ArrayVarDecl> arrays;

  /// Constraint items (empty in M1; populated from M2 onwards).
  final List<ConstraintItem> constraints;

  /// The single `solve` directive at the bottom of every FlatZinc file.
  final SolveItem solve;
}

/// A variable's declared type. Only the cases needed for M1 are
/// represented; floats and set-of-int variables are deferred per
/// MINIZINC_PLAN.md §3.
sealed class VarType {
  const VarType();
}

/// `var int` — unbounded integer (modelled with a large bounded domain
/// at lowering time, see `lowering.dart`).
class VarTypeInt extends VarType {
  const VarTypeInt();
}

/// `var bool` — domain `[0, 1]` (FlatZinc booleans are unified with
/// integers at the engine level; see MINIZINC_PLAN.md §5 "Bool ↔ int
/// dispatch").
class VarTypeBool extends VarType {
  const VarTypeBool();
}

/// `var L..U` — inclusive integer range.
class VarTypeRange extends VarType {
  const VarTypeRange(this.min, this.max);
  final int min;
  final int max;
}

/// `var {v1, v2, ...}` — explicit enumerated integer domain.
class VarTypeSet extends VarType {
  const VarTypeSet(this.values);
  final List<int> values;
}

/// Annotation expression. M1 only inspects `output_var` and
/// `output_array(...)`; everything else is parsed and kept for later
/// milestones.
class Annotation {
  const Annotation(this.name, this.args);
  final String name;
  final List<AstExpr> args;

  /// True for `:: output_var`.
  bool get isOutputVar => name == 'output_var' && args.isEmpty;

  /// True for `:: output_array([1..N, ...])`. The array dimensions are
  /// the first (and only) argument.
  bool get isOutputArray => name == 'output_array';
}

/// Scalar variable declaration.
class VarDecl {
  VarDecl({
    required this.name,
    required this.type,
    required this.rhs,
    required this.annotations,
    required this.line,
    required this.column,
  });

  final String name;
  final VarType type;

  /// Optional right-hand side: `var int: x = 5;` or `var int: x = y;`.
  /// Used by FlatZinc to alias variables to constants or other variables.
  final AstExpr? rhs;

  final List<Annotation> annotations;

  /// Source line/column of the first token of this declaration. Used
  /// for diagnostics.
  final int line;
  final int column;

  bool get isOutput => annotations.any((a) => a.isOutputVar);
}

/// Array-of-var declaration: `array[1..N] of var T: a;` or
/// `array[1..N] of var T: a = [e1, e2, ...];` (the latter form aliases
/// each slot to an existing identifier or literal).
class ArrayVarDecl {
  ArrayVarDecl({
    required this.name,
    required this.length,
    required this.elementType,
    required this.elements,
    required this.annotations,
    required this.line,
    required this.column,
  });

  final String name;

  /// Length of the array. FlatZinc uses 1-based indexing, so the index
  /// range is always `1..length`.
  final int length;

  /// Element type of the array. Same shape as `VarDecl.type`.
  final VarType elementType;

  /// Optional aliasing right-hand side: a list of expressions that
  /// supply each element. `null` for a plain unaliased array.
  final List<AstExpr>? elements;

  final List<Annotation> annotations;

  final int line;
  final int column;

  /// True when the array carries an `output_array(...)` annotation.
  /// The dimensions of the original `array1d(...)` output are returned
  /// via [outputArrayDims].
  bool get isOutput => annotations.any((a) => a.isOutputArray);

  /// The dimensions reported in the `output_array([1..N, ...])`
  /// annotation, if present. Returns `null` if the array is not an
  /// output array.
  ///
  /// FlatZinc spells the dimensions as an array literal of ranges:
  /// `output_array([1..3])` for a 3-element 1D array,
  /// `output_array([1..2, 1..3])` for a 2×3 matrix. The parser produces
  /// `AstArrayLit([AstSetLit(...), ...])` for the argument; we unwrap
  /// that here.
  List<AstRange>? get outputArrayDims {
    for (final a in annotations) {
      if (a.isOutputArray && a.args.isNotEmpty) {
        final first = a.args.first;
        if (first is AstArrayLit) {
          final dims = <AstRange>[];
          for (final e in first.elements) {
            if (e is AstSetLit && e.ranges.length == 1) {
              dims.add(e.ranges.first);
            }
          }
          if (dims.isNotEmpty) return dims;
        }
        if (first is AstSetLit) {
          return first.ranges;
        }
      }
    }
    return null;
  }
}

/// Parameter (non-variable) declaration: `int: n = 5;` or
/// `array[1..3] of int: a = [1, 2, 3];`. M1 parses these so that M2 can
/// substitute them at lowering time without re-touching the parser.
class ParamDecl {
  ParamDecl({required this.name, required this.kind, required this.value});

  final String name;

  /// `'int'`, `'bool'`, or `'array_int'` / `'array_bool'` for the
  /// array forms.
  final String kind;
  final AstExpr value;
}

/// FlatZinc constraint item: `constraint name(arg1, arg2, ...);`.
/// M1 parses these but the lowering pass refuses to handle them; M2
/// onwards populates the handler table.
class ConstraintItem {
  ConstraintItem({
    required this.name,
    required this.args,
    required this.annotations,
    required this.line,
    required this.column,
  });

  final String name;
  final List<AstExpr> args;
  final List<Annotation> annotations;
  final int line;
  final int column;
}

/// `solve` directive — the last item in every FlatZinc file.
class SolveItem {
  SolveItem({
    required this.kind,
    required this.objective,
    required this.annotations,
  });

  /// `'satisfy'`, `'minimize'`, or `'maximize'`.
  final String kind;

  /// The objective expression for minimize/maximize. `null` when
  /// [kind] is `'satisfy'`.
  final AstExpr? objective;

  /// Search annotations (`int_search`, `seq_search`, ...). Parsed but
  /// ignored in v1 — see MINIZINC_PLAN.md §3 "Solve directives".
  final List<Annotation> annotations;
}

/// Expression node. Covers literals, identifiers, and array literals —
/// the only forms that appear inside declarations and constraint
/// arguments.
sealed class AstExpr {
  const AstExpr();
}

class AstIntLit extends AstExpr {
  const AstIntLit(this.value);
  final int value;
}

class AstBoolLit extends AstExpr {
  // The positional bool parameter is unavoidable for a single-field
  // value node; it never appears at a call site where named would help.
  // ignore: avoid_positional_boolean_parameters
  const AstBoolLit(this.value);
  final bool value;
}

/// Identifier reference, e.g. `x` or `n` or `a[3]`. The `index` field
/// is non-null for the indexed form.
class AstIdent extends AstExpr {
  const AstIdent(this.name, {this.index});
  final String name;
  final int? index;
}

/// Array literal: `[e1, e2, ...]`.
class AstArrayLit extends AstExpr {
  const AstArrayLit(this.elements);
  final List<AstExpr> elements;
}

/// Set literal, two forms:
///   - explicit enumeration: `{1, 3, 5}` → ranges = [(1,1),(3,3),(5,5)]
///   - range: `1..10` → ranges = [(1,10)]
class AstSetLit extends AstExpr {
  const AstSetLit(this.ranges);
  final List<AstRange> ranges;
}

class AstRange {
  const AstRange(this.min, this.max);
  final int min;
  final int max;
}

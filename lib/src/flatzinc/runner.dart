/// Top-level FlatZinc entry point.
///
/// Wraps `parseFlatZinc` + `lower` and exposes a single solve API.
/// The output formatter implemented here emits the standard FlatZinc
/// output format (`name = value;` per output variable plus the
/// `----------` / `==========` separators) so the same code path drives
/// the CLI in M5 and the regression test harness in M3+.
library;

import '../problem.dart';
import '../types.dart';
import 'ast.dart';
import 'lowering.dart';
import 'parser.dart';

/// Static facade so callers can write `FlatZinc.parse(source)` or
/// `FlatZinc.solve(source)`. A class is used instead of top-level
/// functions purely so the dart_csp.dart re-export surfaces a tidy
/// single name (`FlatZinc`).
abstract final class FlatZinc {
  /// Parse a FlatZinc source string into an AST. Throws
  /// [FormatException] on parse errors.
  static FlatZincModel parse(String source) => parseFlatZinc(source);

  /// Parse and lower in one step. The returned [LoweredModel] gives
  /// access to the constructed [Problem] for callers that want to
  /// inspect or solve it themselves.
  static LoweredModel build(String source) => lower(parseFlatZinc(source));

  /// Parse, lower, and solve. Returns the standard FlatZinc output
  /// string (one solution + the `----------` separator, plus the
  /// `==========` marker if the search was proven exhaustive).
  ///
  /// `all: true` enumerates every solution (each separated by
  /// `----------`) and terminates with `==========`. Use this for
  /// satisfaction problems where the caller wants the full solution
  /// set; for minimize/maximize problems FlatZinc convention is to
  /// emit every intermediate improving solution. We approximate that
  /// in M1 by reporting only the final optimal assignment — the full
  /// branch-and-bound trace can be wired up later.
  static Future<String> solve(
    String source, {
    bool all = false,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  }) async {
    final lowered = build(source);
    return solveLowered(lowered, all: all, consistency: consistency);
  }

  /// Solve a pre-lowered model. Useful for tests that want to assert
  /// against the problem structure before solving.
  static Future<String> solveLowered(
    LoweredModel lowered, {
    bool all = false,
    ConsistencyLevel consistency = ConsistencyLevel.arcConsistency,
  }) async {
    final solve = lowered.solve;
    final buf = StringBuffer();

    switch (solve.kind) {
      case 'satisfy':
        if (all) {
          var found = false;
          await for (final sol
              in lowered.problem.getSolutions(consistency: consistency)) {
            _formatSolution(buf, lowered, sol);
            found = true;
          }
          if (found) {
            buf.writeln('==========');
          } else {
            buf.writeln('=====UNSATISFIABLE=====');
          }
        } else {
          // Pick the right `getSolutionWithX` based on a FlatZinc
          // `:: int_search(...)` annotation if one is present. The
          // FlatZinc spec lets the annotation hint at variable
          // selection (input_order, first_fail, dom_w_deg, impact,
          // ...); we route to the matching Problem entry point so
          // user-authored search annotations actually take effect.
          final hint = _searchHint(lowered.solve.annotations);
          final sol = await _runSatisfy(lowered.problem, hint, consistency);
          if (sol is Map<String, dynamic>) {
            _formatSolution(buf, lowered, sol);
          } else {
            buf.writeln('=====UNSATISFIABLE=====');
          }
        }
      case 'minimize':
      case 'maximize':
        final objective = solve.objective;
        if (objective is! AstIdent) {
          throw ArgumentError(
              'FlatZinc \'solve ${solve.kind}\' objective must be an '
              'identifier in this subset, got: $objective');
        }
        // Same hint extraction the satisfy path uses — applied here so
        // a `:: int_search(...)` annotation on a minimize/maximize
        // solve directive picks the matching heuristic on the
        // optimization run too.
        final hint = _searchHint(lowered.solve.annotations);
        final result = await _runOptimize(lowered.problem, objective.name,
            minimizing: solve.kind == 'minimize',
            hint: hint,
            consistency: consistency);
        if (result is Map<String, dynamic>) {
          _formatSolution(buf, lowered, result);
          // For optimization runs, branch-and-bound has proven that no
          // further improving assignment exists.
          buf.writeln('==========');
        } else {
          buf.writeln('=====UNSATISFIABLE=====');
        }
      default:
        throw StateError('Unknown solve kind: ${solve.kind}');
    }

    return buf.toString();
  }
}

void _formatSolution(
    StringBuffer buf, LoweredModel lowered, Map<String, dynamic> sol) {
  // If the model declares no `:: output_var` / `:: output_array`
  // annotations, fall back to emitting every variable. This matches
  // the behaviour we want for hand-written FlatZinc snippets used in
  // tests — generated `.fzn` always carries annotations.
  final hasAnnotations =
      lowered.outputScalarVars.isNotEmpty || lowered.outputArrays.isNotEmpty;

  if (hasAnnotations) {
    for (final name in lowered.outputScalarVars) {
      buf.writeln('$name = ${_formatScalar(
        sol[name],
        isBool: lowered.boolVars.contains(name),
        isSet: lowered.setVars.contains(name),
      )};');
    }
    for (final arr in lowered.outputArrays) {
      buf.writeln(_formatArrayLine(arr, sol, lowered.boolVars, lowered.setVars));
    }
  } else {
    // Stable ordering: declaration order is preserved by the
    // Problem's internal LinkedHashMap.
    sol.forEach((name, value) {
      buf.writeln('$name = ${_formatScalar(
        value,
        isBool: lowered.boolVars.contains(name),
        isSet: lowered.setVars.contains(name),
      )};');
    });
  }
  buf.writeln('----------');
}

String _formatArrayLine(OutputArray arr, Map<String, dynamic> sol,
    Set<String> boolVars, Set<String> setVars) {
  final values = arr.varNames
      .map((n) => _formatScalar(sol[n],
          isBool: boolVars.contains(n), isSet: setVars.contains(n)))
      .join(', ');
  final dims = arr.dims.map((r) => '${r.min}..${r.max}').join(', ');
  // FlatZinc renders arrays as `array<N>d(d1, d2, ..., dN, [elems])`
  // where N matches the index-set count from the `output_array(...)`
  // annotation. The annotation always supplies the dimensions, so we
  // pick the constructor name based on `arr.dims.length`.
  final ctor = 'array${arr.dims.length}d';
  return '${arr.name} = $ctor($dims, [$values]);';
}

String _formatScalar(dynamic v, {bool isBool = false, bool isSet = false}) {
  // FlatZinc renders bool-typed outputs as `true` / `false`, integer
  // outputs as the underlying number, and set-typed outputs as a set
  // literal. We plumb `isBool` / `isSet` through from the LoweredModel's
  // tracking sets so the formatter knows which representation to use.
  if (v == null) return '<unset>';
  if (isSet) return _formatSet(v);
  if (isBool) {
    if (v == 1 || v == true) return 'true';
    if (v == 0 || v == false) return 'false';
  }
  return v.toString();
}

/// Renders a solved set value as a FlatZinc set literal. The set
/// variable layer returns a `Set<dynamic>` of included elements; we sort
/// the integer members and collapse contiguous runs into `lo..hi`
/// ranges, matching the form `mzn2fzn`-fed solvers emit
/// (`{}`, `{3}`, `1..4`, `{1, 3, 5}`, `1..3 union {7}` is *not* produced —
/// MiniZinc accepts the brace/range forms below).
String _formatSet(dynamic v) {
  if (v is! Set) return v.toString();
  final ints = <int>[];
  var allInts = true;
  for (final e in v) {
    if (e is int) {
      ints.add(e);
    } else {
      allInts = false;
      break;
    }
  }
  if (!allInts) {
    // Non-integer universe (shouldn't happen for FlatZinc set vars, but
    // be defensive): fall back to a plain brace enumeration.
    return '{${v.join(', ')}}';
  }
  ints.sort();
  if (ints.isEmpty) return '{}';
  // A single contiguous run renders as a range; otherwise enumerate.
  final contiguous = ints.last - ints.first == ints.length - 1;
  if (contiguous && ints.length > 1) {
    return '${ints.first}..${ints.last}';
  }
  return '{${ints.join(', ')}}';
}

/// Variable-selection hint extracted from a FlatZinc
/// `:: int_search(...)` / `:: bool_search(...)` annotation, or from
/// the first recognised inner search inside a
/// `:: seq_search([...])` block. We map the standard FlatZinc
/// `varSelect` keywords to the heuristic knobs dart_csp exposes:
///
///   - `first_fail`, `smallest`, `largest`, `input_order`        → default (MRV)
///   - `dom_w_deg`, `most_constrained`, `weighted_degree`        → dom/wdeg
///   - `activity_var`, `activity_var_min`, `vsids`               → VSIDS-style activity
///   - `impact`                                                  → IBS
///
/// FlatZinc supports many more `varSelect` keywords; unrecognised
/// values fall back to the default heuristic rather than failing the
/// solve, since the spec lets solvers ignore unsupported hints. Note
/// also that the hint applies globally — dart_csp doesn't yet support
/// per-variable-set heuristic scoping, so the first variable list in
/// a `seq_search` is effectively the one whose `varSelect` "wins";
/// subsequent search blocks contribute their varSelect only if the
/// earlier blocks didn't pick a recognised keyword.
enum _SearchHint { defaultMrv, domWdeg, vsids, impact }

_SearchHint _searchHint(List<Annotation> annotations) {
  for (final a in annotations) {
    final h = _hintFromAnnotation(a.name, a.args);
    if (h != _SearchHint.defaultMrv) return h;
  }
  return _SearchHint.defaultMrv;
}

/// Recursively extract a hint from one annotation form. `int_search` /
/// `bool_search` look at args[1] (the varSelect keyword); `seq_search`
/// walks each element of its first-arg array and returns the first
/// recognised hint inside.
_SearchHint _hintFromAnnotation(String name, List<AstExpr> args) {
  switch (name) {
    case 'int_search':
    case 'bool_search':
      if (args.length < 2) return _SearchHint.defaultMrv;
      final selExpr = args[1];
      if (selExpr is! AstIdent) return _SearchHint.defaultMrv;
      switch (selExpr.name) {
        case 'dom_w_deg':
        case 'most_constrained':
        case 'weighted_degree':
          return _SearchHint.domWdeg;
        case 'activity_var':
        case 'activity_var_min':
        case 'vsids':
          return _SearchHint.vsids;
        case 'impact':
          return _SearchHint.impact;
      }
      return _SearchHint.defaultMrv;
    case 'seq_search':
      if (args.isEmpty) return _SearchHint.defaultMrv;
      final first = args[0];
      if (first is! AstArrayLit) return _SearchHint.defaultMrv;
      for (final inner in first.elements) {
        if (inner is AstAnnotationCall) {
          final h = _hintFromAnnotation(inner.name, inner.args);
          if (h != _SearchHint.defaultMrv) return h;
        }
      }
      return _SearchHint.defaultMrv;
  }
  return _SearchHint.defaultMrv;
}

Future<dynamic> _runSatisfy(
    Problem problem, _SearchHint hint, ConsistencyLevel consistency) {
  switch (hint) {
    case _SearchHint.domWdeg:
      return problem.getSolutionWithDomWdeg(consistency: consistency);
    case _SearchHint.vsids:
      return problem.getSolutionWithActivity(consistency: consistency);
    case _SearchHint.impact:
      return problem.getSolutionWithImpact(consistency: consistency);
    case _SearchHint.defaultMrv:
      return problem.getSolution(consistency: consistency);
  }
}

Future<dynamic> _runOptimize(Problem problem, String objective,
    {required bool minimizing,
    required _SearchHint hint,
    required ConsistencyLevel consistency}) {
  final useDomWdeg = hint == _SearchHint.domWdeg;
  final useVsids = hint == _SearchHint.vsids;
  final useImpact = hint == _SearchHint.impact;
  if (minimizing) {
    return problem.minimize(objective,
        useDomWdeg: useDomWdeg,
        useVsids: useVsids,
        useImpact: useImpact,
        consistency: consistency);
  }
  return problem.maximize(objective,
      useDomWdeg: useDomWdeg,
      useVsids: useVsids,
      useImpact: useImpact,
      consistency: consistency);
}

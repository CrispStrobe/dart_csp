// Multi-objective optimization, layered on the single-objective
// branch-and-bound (`minimize` / `maximize`).
//
// Two shapes:
//   * lexicographic — optimize objectives in strict priority order, each
//     tie-broken by the next; and
//   * Pareto — enumerate the non-dominated frontier.
//
// Both work on a `copy()` of the problem, so the caller's problem is never
// mutated. Engine-free: they only post ordinary constraints and call the
// existing optimizers.

import 'problem.dart';
import 'types.dart';

/// One objective in a multi-objective problem: a numeric variable to be
/// either minimized or maximized.
class Objective {
  const Objective._(this.variable, this.maximize);

  /// Minimize [variable].
  const Objective.minimize(String variable) : this._(variable, false);

  /// Maximize [variable].
  const Objective.maximize(String variable) : this._(variable, true);

  /// The objective variable's name.
  final String variable;

  /// Whether larger is better (`true`) or smaller is better (`false`).
  final bool maximize;

  @override
  String toString() => '${maximize ? 'max' : 'min'}($variable)';
}

/// Lexicographic and Pareto optimization over a [Problem].
extension MultiObjective on Problem {
  /// Optimizes [objectives] in strict priority order (lexicographic).
  ///
  /// The first objective is optimized; its optimal value is then fixed and
  /// the second is optimized subject to that; and so on. The returned
  /// assignment is optimal for objective 1, and among all such assignments
  /// optimal for objective 2, and so on. Returns the string `'FAILURE'` if
  /// the problem is unsatisfiable.
  ///
  /// Runs on a [copy]; the receiver is not modified. Throws [ArgumentError]
  /// if [objectives] is empty or names a variable twice.
  Future<dynamic> lexOptimize(
    List<Objective> objectives, {
    CancellationToken? cancelToken,
  }) async {
    _checkObjectives(objectives);
    final work = copy();
    dynamic solution;
    for (final obj in objectives) {
      final result = obj.maximize
          ? await work.maximize(obj.variable, cancelToken: cancelToken)
          : await work.minimize(obj.variable, cancelToken: cancelToken);
      if (result is! Map<String, dynamic>) return 'FAILURE'; // 'FAILURE'
      solution = result;
      // Pin this objective at its optimum so lower-priority objectives
      // cannot trade it away.
      final value = result[obj.variable] as num;
      work.addLinearEquals([obj.variable], [1], value);
      if (cancelToken?.isCancelled ?? false) return 'FAILURE';
    }
    return solution;
  }

  /// Enumerates the Pareto frontier over [objectives]: the set of solutions
  /// none of which is dominated by another (a solution dominates another if
  /// it is at least as good on every objective and strictly better on at
  /// least one).
  ///
  /// Each returned solution has a distinct objective vector. The algorithm
  /// repeatedly finds a lexicographically-optimal solution — which is always
  /// Pareto-optimal — records it, and excludes the region it dominates, until
  /// no solution remains. Iterations therefore equal the frontier size.
  ///
  /// [maxPoints] caps how many frontier points are returned (and how many
  /// iterations run); with the default `null` the complete frontier is
  /// returned. Runs on a [copy]; the receiver is not modified. Throws
  /// [ArgumentError] if [objectives] is empty or names a variable twice.
  Future<List<Map<String, dynamic>>> paretoFront(
    List<Objective> objectives, {
    int? maxPoints,
    CancellationToken? cancelToken,
  }) async {
    _checkObjectives(objectives);
    final work = copy();
    final front = <Map<String, dynamic>>[];
    while (maxPoints == null || front.length < maxPoints) {
      if (cancelToken?.isCancelled ?? false) break;
      final result =
          await work.lexOptimize(objectives, cancelToken: cancelToken);
      if (result is! Map<String, dynamic>) break; // frontier exhausted
      front.add(result);
      final values = [for (final o in objectives) result[o.variable] as num];
      _postDominationExclusion(work, objectives, values);
    }
    return front;
  }

  void _checkObjectives(List<Objective> objectives) {
    if (objectives.isEmpty) {
      throw ArgumentError('At least one objective is required.');
    }
    final names = <String>{};
    for (final o in objectives) {
      if (!names.add(o.variable)) {
        throw ArgumentError(
            "Objective variable '${o.variable}' is listed more than once.");
      }
    }
  }

  /// Posts "the next solution must be strictly better than [values] on at
  /// least one objective" — i.e. excludes every solution dominated by or
  /// equal to the objective vector [values]. [Problem.addConstraint] needs a
  /// `BinaryPredicate` for exactly two variables and a `NaryPredicate`
  /// otherwise, so the arities are split.
  static void _postDominationExclusion(
      Problem work, List<Objective> objectives, List<num> values) {
    bool better(int i, num v) =>
        objectives[i].maximize ? v > values[i] : v < values[i];

    final vars = [for (final o in objectives) o.variable];
    if (vars.length == 2) {
      work.addConstraint<bool Function(dynamic, dynamic)>(
        vars,
        (a, b) => better(0, a as num) || better(1, b as num),
      );
    } else {
      work.addConstraint<bool Function(Map<String, dynamic>)>(vars, (m) {
        for (var i = 0; i < vars.length; i++) {
          if (better(i, m[vars[i]] as num)) return true;
        }
        return false;
      });
    }
  }
}

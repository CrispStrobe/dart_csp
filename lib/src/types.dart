/// Core type definitions for the CSP library.
library;

/// Cooperative cancellation handle for backtracking solves.
///
/// Solvers periodically check the token (currently every decision on
/// backtracking paths, yielding to the event loop every 100; every
/// 200 iterations on the min-conflicts path) and abort the search if
/// [isCancelled] is
/// true. An aborted solve returns the literal `'FAILURE'` string —
/// the same shape as an unsatisfiable problem — so callers
/// distinguish the two by inspecting [isCancelled] after the call:
///
/// ```dart
/// final token = CancellationToken();
/// Timer(Duration(seconds: 5), token.cancel);
/// final result = await p.getSolution(cancelToken: token);
/// if (result == 'FAILURE' && token.isCancelled) {
///   print('Timed out.');
/// }
/// ```
///
/// Solvers also yield to the event loop at each checkpoint, which is
/// what lets a wrapping `Future.timeout(...)` actually fire. Without
/// cooperative yields the engine is CPU-bound and the timeout never
/// gets a turn; with this token the engine yields often enough that
/// timeouts trigger within tens of milliseconds of their deadline on
/// real CSPs.
class CancellationToken {
  /// Creates a fresh, uncancelled token.
  CancellationToken();

  bool _cancelled = false;
  List<void Function()>? _listeners;

  /// Whether [cancel] has been called. Once true, stays true; tokens
  /// are single-use.
  bool get isCancelled => _cancelled;

  /// Marks this token as cancelled. Idempotent; subsequent calls are
  /// no-ops. Safe to call from a timer, a Stream listener, or any
  /// other Dart code; the next solver checkpoint observes the new
  /// state and aborts.
  ///
  /// Any listeners previously registered via [addListener] are
  /// invoked synchronously, in the order they were registered.
  /// Listener exceptions are caught and discarded so a misbehaving
  /// listener cannot prevent other listeners from running or block
  /// the cancelling caller.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final fired = _listeners;
    _listeners = null;
    if (fired != null) {
      for (final l in fired) {
        try {
          l();
        } catch (_) {
          // Swallow: cancellation must not throw back to the caller.
        }
      }
    }
  }

  /// Registers a callback invoked exactly once when [cancel] is
  /// called. If the token has already been cancelled at the time
  /// [addListener] is invoked, [listener] runs synchronously before
  /// [addListener] returns.
  ///
  /// Intended for plumbing that needs to forward cancellation
  /// outside the calling isolate (e.g. the worker-isolate runner
  /// uses this to send a cancel signal over a [SendPort] when the
  /// parent-side token fires). Solver entry points read
  /// [isCancelled] directly at every checkpoint and do not need to
  /// register a listener.
  void addListener(void Function() listener) {
    if (_cancelled) {
      try {
        listener();
      } catch (_) {
        // See cancel() for the rationale.
      }
      return;
    }
    (_listeners ??= <void Function()>[]).add(listener);
  }
}

/// Selects the level of constraint propagation the backtracking
/// engine performs at each node of the search tree.
///
/// Stronger consistency prunes more values per decision (so the
/// search tree is smaller) but pays more work per decision. The
/// right choice is problem-dependent.
enum ConsistencyLevel {
  /// Forward checking. After a value is assigned to a variable, each
  /// constraint that variable participates in is revised exactly
  /// once. A revise that further reduces a neighbor's domain does
  /// NOT trigger re-revising the constraints reachable through that
  /// neighbor — i.e., propagation does not cascade.
  ///
  /// Cheapest per decision; correct but does the least pruning.
  /// Best on problems with loose constraint graphs or where each
  /// constraint already prunes well on its own.
  forwardChecking,

  /// Arc consistency on binary constraints (AC-3, Mackworth 1977)
  /// and generalized arc consistency on n-ary constraints. After
  /// any revise reduces a domain, the constraints reachable through
  /// the changed variable are requeued and re-revised, repeating
  /// until a fixed point.
  ///
  /// The default. More pruning per decision than forward checking;
  /// almost always a net win on structured problems.
  arcConsistency,

  /// Singleton arc consistency (Debruyne & Bessière, 1997). A value
  /// `v` in `dom(x)` is SAC iff tentatively assigning `x = v` and
  /// running AC-3 to fixpoint leaves every domain non-empty. The
  /// engine enforces SAC as a preprocessing pass at the top of
  /// search (algorithm SAC-1: tentatively pin every remaining
  /// `(variable, value)` pair, prune the value if propagation
  /// fails, iterate the whole pass until no value is pruned) and
  /// then runs ordinary AC-3 / GAC during search.
  ///
  /// More expensive at the root than [arcConsistency] but never
  /// weaker — every value SAC keeps is also AC. Useful on problems
  /// where AC-3 alone leaves a lot of dead-end values in the root
  /// domain (chain CSPs, tight global constraints with structural
  /// gaps the per-constraint propagator can't see). Has no effect
  /// on the per-decision propagation cost: SAC runs once.
  singletonArcConsistency,
}

/// Statistics gathered by a single backtracking solve.
///
/// All counters are populated by the engine and exposed through
/// [Problem.lastStats] (or directly by [CSP.solve] return values
/// in future iterations).
class SolverStats {
  SolverStats({
    this.decisions = 0,
    this.backtracks = 0,
    this.propagations = 0,
    this.binaryRevises = 0,
    this.naryRevises = 0,
    this.iterations = 0,
    this.elapsedMicros = 0,
    this.backjumps = 0,
    this.backjumpLevelsSkipped = 0,
  });

  /// Number of variable choices made (calls into the recursive
  /// search that picked an unassigned variable + value).
  /// Populated only by backtracking solvers; `0` for local search.
  int decisions;

  /// Number of failed branches that were rolled back via the trail.
  /// Populated only by backtracking solvers; `0` for local search.
  int backtracks;

  /// Number of times the propagation fixed-point loop was entered
  /// (i.e., calls to `_propagate`). Populated only by backtracking
  /// solvers; `0` for local search.
  int propagations;

  /// Number of AC-3 revise calls (`_reviseBinary`) that actually
  /// changed a domain. Populated only by backtracking solvers.
  int binaryRevises;

  /// Number of GAC revise calls (`_reviseNary` or the allDifferent
  /// / linear propagators) that actually changed a domain.
  /// Populated only by backtracking solvers.
  int naryRevises;

  /// Number of local-search iterations executed. Populated only by
  /// `solveWithMinConflicts`; `0` for backtracking solvers (use
  /// [decisions] there). A run that converges may finish in fewer
  /// iterations than `maxSteps`; an unconverged run will report
  /// exactly `maxSteps`.
  int iterations;

  /// Wall-clock time for the solve in microseconds. Set by the
  /// public solve entry point that wraps the engine. Populated for
  /// every solver, including the streaming and local-search paths.
  int elapsedMicros;

  /// Number of times the conflict-directed backjumping engine returned
  /// a backjump signal up the search stack (i.e. exhausted all
  /// candidates for a variable with a non-empty conflict set). Always
  /// `0` when CBJ is not enabled for the solve, and always `0` for
  /// local search. A non-zero value with [backjumpLevelsSkipped] still
  /// `0` means CBJ ran but every conflict-driven return happened to
  /// be one-level (i.e. behaved like chronological backtracking).
  int backjumps;

  /// Total number of search levels skipped past chronological backtrack
  /// during conflict-directed backjumping — i.e. the sum, over every
  /// backjump, of `(decisionDepth - targetDepth - 1)`. A plain
  /// chronological backtrack contributes `0`; a true backjump that
  /// skips one decision contributes `1`, etc. Always `0` when CBJ is
  /// not enabled, and always `0` for local search.
  int backjumpLevelsSkipped;

  @override
  String toString() =>
      'SolverStats(decisions: $decisions, backtracks: $backtracks, '
      'propagations: $propagations, binaryRevises: $binaryRevises, '
      'naryRevises: $naryRevises, iterations: $iterations, '
      'elapsedMicros: $elapsedMicros, backjumps: $backjumps, '
      'backjumpLevelsSkipped: $backjumpLevelsSkipped)';
}

/// Type definition for a binary constraint predicate.
///
/// It takes the value of a 'head' variable and a 'tail' variable and returns
/// true if the constraint is satisfied between them. This defines a directed
/// arc from head to tail.
typedef BinaryPredicate = bool Function(dynamic headVal, dynamic tailVal);

/// Type definition for an n-ary constraint predicate.
///
/// It takes a map representing a partial assignment of variables to values
/// and returns true if the constraint is satisfied for that combination.
typedef NaryPredicate = bool Function(Map<String, dynamic> assignment);

/// Type definition for the optional callback function during the search.
///
/// This can be used for visualizing the search process, showing the state of
/// assigned and unassigned variable domains at each step of the backtracking.
typedef CspCallback = void Function(
    Map<String, List<dynamic>> assigned, Map<String, List<dynamic>> unassigned);

/// Represents a binary constraint between two variables, forming a directed arc.
///
/// For a constraint like `A > B`, you might have one `BinaryConstraint` for the
/// arc A -> B and another for B -> A to enforce full consistency.
class BinaryConstraint {
  BinaryConstraint(this.head, this.tail, this.predicate);

  /// The "source" variable in the directed constraint arc.
  final String head;

  /// The "destination" variable in the directed constraint arc.
  final String tail;

  /// The function that evaluates the constraint between a value from the head's
  /// domain and a value from the tail's domain.
  final BinaryPredicate predicate;
}

/// Represents an n-ary constraint involving two or more variables.
///
/// This is used for complex constraints that cannot be broken down into simple
/// binary relationships, such as `A + B = C`.
class NaryConstraint {
  NaryConstraint({
    required this.vars,
    required this.predicate,
    this.allDifferent = false,
    this.linearSpec,
    this.regularDfa,
    this.circuit = false,
    this.subcircuit = false,
    this.gccSpec,
    this.cumulativeSpec,
    this.clauseSpec,
  });

  /// The list of variable names involved in this constraint.
  final List<String> vars;

  /// The function that evaluates if a complete assignment for the involved
  /// variables satisfies the constraint.
  final NaryPredicate predicate;

  /// If `true`, the solver may use a specialized hyper-arc-consistent
  /// propagator (Régin 1994) instead of the generic GAC support search.
  /// The [predicate] is still invoked at assignment time so soundness
  /// does not depend on the propagator being used.
  final bool allDifferent;

  /// If non-null, the solver dispatches this constraint to a bounds-
  /// consistency propagator for linear arithmetic
  /// (Σ coeffs[i]·vars[i] ∘ bound). The [predicate] is still used at
  /// leaves so soundness does not depend on the propagator being run.
  final LinearSpec? linearSpec;

  /// If non-null, the solver dispatches this constraint to a partial-
  /// state regular-language propagator (Pesant 2004): the sequence
  /// `(vars[0], ..., vars[n-1])` must be accepted by this [Dfa]. The
  /// propagator computes per-position forward + backward reachable
  /// state sets and prunes any value whose transition lies on no
  /// accepting path. The [predicate] is still used at leaves so
  /// soundness does not depend on the propagator being run.
  final Dfa? regularDfa;

  /// If `true`, the solver dispatches this constraint to a cycle-
  /// detection propagator: `vars[i]` is interpreted as the successor
  /// of position `i` in a Hamiltonian cycle through every position.
  /// The propagator maintains the singleton-edge chains forming so
  /// far, prunes values that would close a premature sub-cycle, and
  /// enforces successor uniqueness. The [predicate] is still used at
  /// leaves so soundness does not depend on the propagator being
  /// run.
  final bool circuit;

  /// If `true`, the solver dispatches this constraint to the same
  /// cycle-detection propagator as [circuit] but in **subcircuit**
  /// mode: a self-loop `vars[i] = i` is permitted and interpreted as
  /// "position `i` is not in the cycle". The non-self-loop edges
  /// among the remaining positions must still form a single cycle
  /// (or there may be no cycle at all, with every position self-
  /// looped). The [predicate] is still used at leaves so soundness
  /// does not depend on the propagator being run. Mutually
  /// exclusive with [circuit].
  final bool subcircuit;

  /// If non-null, the solver dispatches this constraint to a
  /// network-flow propagator for the global cardinality constraint
  /// (Régin 1996): each value `v` must occur `[min, max]` times
  /// across the constraint's variables. The propagator builds a
  /// bipartite matching with value multiplicity, computes the
  /// residual graph and SCCs, and prunes any value not on some
  /// max-matching path. The [predicate] is still used at leaves so
  /// soundness does not depend on the propagator being run.
  final GccSpec? gccSpec;

  /// If non-null, the solver dispatches this constraint to a
  /// time-table cumulative propagator (Beldiceanu & Carlsson, 2002
  /// style). Each variable in [vars] is the start time of one task;
  /// per-task durations and demands and the resource capacity live
  /// in [cumulativeSpec]. The propagator computes each task's
  /// compulsory part (the interval that the task must occupy
  /// regardless of where it ends up scheduled), sums those parts
  /// into a global usage profile, and prunes every start value that
  /// would push the profile above capacity at any time. The
  /// [predicate] is still used at leaves so soundness does not
  /// depend on the propagator being run.
  final CumulativeSpec? cumulativeSpec;

  /// If non-null, the solver dispatches this constraint to a SAT-
  /// style clause propagator that performs unit propagation: the
  /// disjunction of [ClauseSpec] literals must be satisfied (at
  /// least one literal true). When all-but-one literals are
  /// falsified and none are satisfied yet, the unique remaining
  /// literal is forced to true. The [predicate] is still used at
  /// leaves so soundness does not depend on the propagator being
  /// run.
  final ClauseSpec? clauseSpec;
}

/// Describes a global cardinality constraint: each value `v` must
/// occur at least [GccSpec.bounds][v].min and at most
/// [GccSpec.bounds][v].max times across the constraint's variables.
///
/// Values that do not appear as keys in [bounds] are unconstrained
/// (their multiplicity is implicitly bounded only by the variable
/// count). Used to tag an [NaryConstraint] so the engine can
/// dispatch to a Régin-style matching propagator instead of
/// enumerating tuples through the generic n-ary predicate.
class GccSpec {
  GccSpec({required this.bounds});

  /// `bounds[v]` is the inclusive `[min, max]` range for the number
  /// of times value `v` must occur across the constraint's
  /// variables. `min` must be non-negative and `min <= max`.
  final Map<dynamic, ({int min, int max})> bounds;
}

/// Describes a SAT-style clause: a disjunction of boolean literals
/// over registered 0/1 variables. Each literal is a pair
/// `(varName, positive)` interpreted as `vars[varName] == 1` when
/// `positive` is true and `vars[varName] == 0` when `positive` is
/// false. The clause is satisfied iff at least one literal is
/// satisfied.
///
/// Used to tag an [NaryConstraint] so the engine can dispatch to a
/// unit-propagation propagator instead of enumerating tuples through
/// the generic n-ary predicate.
class ClauseSpec {
  ClauseSpec({required this.literals});

  /// Per-literal `(varName, positive)`. `vars` of the surrounding
  /// [NaryConstraint] holds the same variable names in the same
  /// order, so callers indexing literals by position can recover
  /// the var name from either source.
  final List<({String varName, bool positive})> literals;
}

/// Describes a cumulative resource constraint over a list of tasks.
///
/// Each task `i` has a constant integer [durations][i] and a constant
/// integer [demands][i]; the surrounding [NaryConstraint.vars] holds
/// the task start variables (each interpreted as a position on a
/// shared integer time axis). The constraint enforces that at every
/// time `t`, the sum of [demands][i] across tasks whose half-open
/// interval `[start_i, start_i + duration_i)` covers `t` does not
/// exceed [capacity].
///
/// Used to tag an [NaryConstraint] so the engine can dispatch to a
/// time-table propagator instead of enumerating tuples through the
/// generic n-ary predicate.
class CumulativeSpec {
  CumulativeSpec({
    required this.durations,
    required this.demands,
    required this.capacity,
  });

  /// Constant duration (in time units) for each task, in the same
  /// order as the surrounding [NaryConstraint.vars]. Must be
  /// non-negative.
  final List<int> durations;

  /// Constant resource demand for each task, in the same order as
  /// the surrounding [NaryConstraint.vars]. Must be non-negative.
  final List<int> demands;

  /// Resource capacity available at every time step. Must be
  /// non-negative.
  final int capacity;
}

/// Comparison operator for a [LinearSpec]: equality, less-or-equal, or
/// greater-or-equal.
enum LinearOp {
  /// `Σ coeffs[i]·vars[i] == bound`.
  eq,

  /// `Σ coeffs[i]·vars[i] <= bound`.
  leq,

  /// `Σ coeffs[i]·vars[i] >= bound`.
  geq,
}

/// Describes a linear arithmetic constraint over a vector of variables:
/// `Σ coeffs[i]·vars[i]  op  bound`.
///
/// Used to tag an [NaryConstraint] so the engine can dispatch to a
/// bounds-consistency propagator instead of enumerating supports
/// through the generic n-ary predicate.
///
/// Bounds consistency narrows each variable's domain to values
/// compatible with the *interval* of the partial sum
/// `Σᵢ≠ⱼ coeffs[i]·vars[i]` derived from the other variables' current
/// domain mins and maxes. It does not achieve full GAC (interior
/// values inconsistent with no extreme assignment are not pruned),
/// but it is much stronger than predicate-only enumeration on
/// arithmetic constraints with many variables.
class LinearSpec {
  LinearSpec({
    required this.coeffs,
    required this.op,
    required this.bound,
  });

  /// Coefficient for each variable, in the same order as the
  /// surrounding [NaryConstraint.vars]. Same length as `vars`.
  /// Coefficients may be positive, negative, or zero.
  final List<num> coeffs;

  /// Which comparison the linear sum is constrained by.
  final LinearOp op;

  /// Right-hand side of the comparison.
  final num bound;
}

/// A deterministic finite automaton, used by the **regular** global
/// constraint (`Problem.addRegular`).
///
/// States are integers in `[0, numStates)`. [start] is the initial
/// state; the automaton accepts a symbol sequence if it ends in a
/// state contained in [accepting]. [transitions] maps each
/// `(state, symbol)` pair to the next state — missing keys (either
/// the outer state or the inner symbol) act as a dead transition
/// (the sequence is rejected).
///
/// Symbols are `dynamic` to match the value types CSP variables
/// support (int, String, custom objects).
///
/// ```dart
/// // DFA that accepts sequences with at most 2 'M' (morning) symbols.
/// final atMostTwoMornings = Dfa(
///   numStates: 4,            // 0 = 0 M's, 1 = 1 M, 2 = 2 M, 3 = >2 (trap)
///   start: 0,
///   accepting: {0, 1, 2},    // not the trap
///   transitions: {
///     0: {'M': 1, 'A': 0, 'N': 0},
///     1: {'M': 2, 'A': 1, 'N': 1},
///     2: {'M': 3, 'A': 2, 'N': 2},
///     3: {'M': 3, 'A': 3, 'N': 3},
///   },
/// );
/// ```
class Dfa {
  Dfa({
    required this.numStates,
    required this.start,
    required this.accepting,
    required this.transitions,
  });

  /// Total number of states. States are integers in `[0, numStates)`.
  final int numStates;

  /// Initial state for any sequence read by this DFA.
  final int start;

  /// States that accept an empty (or fully-consumed) sequence.
  final Set<int> accepting;

  /// `transitions[state][symbol]` is the next state. A missing outer
  /// or inner key acts as a dead transition (the sequence is
  /// rejected).
  final Map<int, Map<dynamic, int>> transitions;

  /// Returns the next state after reading [symbol] in [state], or
  /// `null` if no transition is defined (sequence rejected).
  int? step(int state, dynamic symbol) => transitions[state]?[symbol];
}

/// Represents the full definition of a Constraint Satisfaction Problem.
///
/// This class encapsulates all the necessary components of a CSP: the variables,
/// their domains, and the constraints that bind them.
class CspProblem {
  CspProblem({
    required this.variables,
    this.constraints = const <BinaryConstraint>[],
    this.naryConstraints = const <NaryConstraint>[],
    this.timeStep = 1,
    this.cb,
  });

  /// A map where keys are variable names and values are lists (domains) of
  /// their possible values.
  Map<String, List<dynamic>> variables;

  /// A list of binary constraints restricting pairs of variables.
  List<BinaryConstraint> constraints;

  /// A list of n-ary constraints restricting groups of variables.
  List<NaryConstraint> naryConstraints;

  /// The delay in milliseconds between steps, used if a [cb] callback is provided.
  int timeStep;

  /// An optional callback function invoked at each step of the search for visualization.
  CspCallback? cb;

  /// Internal index mapping each variable to the n-ary constraints it participates in.
  /// This is built by the solver to speed up the GAC algorithm.
  Map<String, List<NaryConstraint>>? naryIndex;
}

# Lazy Clause Generation (LCG)

`Problem.solveWithLcg` is dart_csp's entry point for **Lazy Clause
Generation** — the conflict-driven nogood-learning technique that
gives modern solvers like CP-SAT (OR-Tools) and Chuffed
orders-of-magnitude speedups over non-learning solvers on hard
structured problems. LCG is dart_csp's biggest open strategic gap;
the implementation is split into six milestones (M1–M6) tracked in
[`LCG_PLAN.md`](../LCG_PLAN.md) at the repo root.

This guide documents the **M1 + M2 surface** — atom encoding, an
implication trail wired into the engine, and the first-UIP loop
that posts learned clauses + drives non-chronological backjumps —
and explains what to expect from `solveWithLcg` today versus once
M3 (per-propagator explanations) lands.

---

## What LCG does (and why it matters)

A traditional CP backtracker, on conflict, rolls back to the most
recent decision and tries a different value. The information about
*why* the conflict happened is discarded — the same dead-end may
be revisited deeper in the tree under a different prefix.

LCG turns each conflict into a **learned clause**: a logical
disjunction over atoms `(variable, op, value)` that says "this
combination of choices cannot all hold." Learned clauses are added
to a pool consulted by the engine on every subsequent decision, so
the dead-end is never revisited. On problems whose search tree
would otherwise be exponential in problem size, learning typically
replaces the exponential with a polynomial — minutes vs hours, or
solvable vs intractable.

The textbook reference is Marques-Silva & Sakallah 1996 (the first-
UIP loop, GRASP) and Eén & Sörensson 2003 (MiniSat). For CP
specifically, Ohrimenko, Stuckey & Codish 2009 ("Propagation via
lazy clause generation") and Feydy & Stuckey 2009 ("Lazy clause
generation reengineered") are the foundational papers — both
introduce the lazy-atom encoding dart_csp's plan adopts.

---

## What M1 + M2 ship

The user-facing surface looks like this:

```dart
final p = Problem()
  ..addVariables(['A', 'B', 'C', 'D'], [1, 2, 3, 4])
  ..addAllDifferent(['A', 'B', 'C', 'D']);
final solution = await p.solveWithLcg();
```

**Return contract.** Same as `getSolution` — `Map<String, dynamic>`
on success or the literal `'FAILURE'`. On problems whose conflicts
flow through the boolean clause propagator (CNF problems, encoded
boolean indicator networks), the engine learns conflict clauses
and backjumps non-chronologically; on other problems it falls back
to chronological backtrack and matches the plain `getSolution`
search tree exactly.

**Engine bookkeeping.** Every domain prune still appends an
`ImplicationEntry` to a parallel implication trail (rolled back in
lockstep with the domain trail). When the clause propagator reports
a conflict, the engine runs `firstUipAnalyse` against that trail,
posts the resulting learned clause into the constraint store via
the existing `_ClausePropagator` infrastructure, and signals a
backjump up the search stack to the clause's second-highest
decision level. The freshly posted clause then unit-props its
asserting (UIP) literal at the landing frame, prompting the next
decision under the new constraint.

**Boolean vs atom clauses.** `_ClausePropagator` understands two
literal shapes:

- **Boolean** (`ClauseSpec.literals`) — the user-facing form
  produced by `Problem.addClause`. Each literal is `(varName,
  positive)` over a `{0, 1}` variable.
- **Atom** (`ClauseSpec.atoms`) — LCG learned-clause form. Each
  literal is an `Atom` (`AtomEq` / `AtomNe` / `AtomLe` / `AtomGe`)
  and the literal is satisfied iff the atom is entailed by the
  variable's current domain. Variables can be over arbitrary
  integer domains.

The propagator dispatches on `spec.atoms != null`. The two-watched-
literal scheme works identically for both shapes — watch-literal
monotonicity holds under trail rollback for all four atom kinds
because rollback only grows domains. The engine's
`_learnedClauseToSpec` picks the boolean shape when every learned
atom resolves to a `{0, 1}` literal (cheaper per-prop eval) and
falls back to the atom shape otherwise. User code never constructs
atom clauses directly.

**Statistics.** `CSP.lastStats` now carries:

| Field             | Meaning                                                              |
|-------------------|----------------------------------------------------------------------|
| `learnedClauses`  | Conflict clauses learned and posted during this solve.               |
| `forgottenClauses`| Learned clauses dropped by the forget policy (FIFO, half-pool drop). |
| `backjumps`       | Non-chronological backjumps. Shared with CBJ; LCG bumps it too.      |

`CSP.lastImplicationTrail` continues to expose the live snapshot
for tests and tooling.

### Atom encoding

Four shapes cover every prune the existing engine produces:

| Atom        | Meaning                       |
|-------------|-------------------------------|
| `AtomEq`    | `x = v` — pinned to exactly v |
| `AtomNe`    | `x ≠ v` — value v removed     |
| `AtomLe`    | `x ≤ v` — upper-bound prune   |
| `AtomGe`    | `x ≥ v` — lower-bound prune   |
| `AtomInScc` | synthetic Hall-set *bridge* (M3-tighten; not a domain literal) |

The first four are real, assertable domain literals. `AtomInScc` is a
**synthetic bridge** (`isSynthetic == true`): it collapses a whole
allDifferent Hall-set argument into one resolvable atom so first-UIP
analysis converges (see "M3-tighten" below). It is never assertable —
`negate()` and `isEntailedBy()` throw, and the analyser resolves
*through* it (never stops at it as a UIP, never lets it reach a learned
clause).

Atoms negate logically (`AtomEq(x, v).negate()` → `AtomNe(x, v)`,
`AtomLe(x, v).negate()` → `AtomGe(x, v+1)`) and can be checked
against a `DomainView` via `isEntailedBy` — the narrow public
interface dart_csp's engine reps implement.

Domains over non-integer values (string-valued map-colouring, etc.)
are silently skipped on the implication trail; atoms are integer-
only by design. This is the scope decision in `LCG_PLAN.md` §1.

### Implication trail

Each domain mutation appends `ImplicationEntry` records to the
trail, one per pruned value (or a single `AtomEq` when the new
domain is a singleton):

```dart
class ImplicationEntry {
  final Atom prunedAtom;          // what was forced
  final ImplicationReason reason; // why
  final int trailIndex;           // matching position on engine's domain trail
  final int decisionLevel;        // # of decisions before this prune
}
```

The `reason` is one of:
- `DecisionReason()` — the entry was a free decision pin
  (search-loop `_setDomain(v, [chosenValue], cause: null)`).
- `ClauseReason(antecedents)` — a unit-prop forced by the clause
  propagator; the antecedents list captures the falsified other
  literals so first-UIP analysis can resolve through this prune.
- `AllDifferentReason(antecedents)` (M3a) — a prune emitted by the
  Régin allDifferent propagator. The antecedents are the Hall-set
  absences: `AtomNe(h, k)` for every Hall-set variable `h` and
  every value `k` declared in `h`'s original domain but absent
  from `h`'s current domain. The Hall set is extracted from the
  propagator's existing SCC decomposition: for prunes of variable
  `i`, it's the union of SCCs of all pruned values.
- `LinearBoundReason(antecedents)` (M3b) — a prune emitted by the
  bounds-consistency linear propagator. The antecedents are the
  *other* variables' current absences expressed as `AtomNe`
  atoms (coarse-but-sound: any state where those absences hold
  reproduces the same residual interval and the same prune).
- `GccFlowReason(antecedents)` (M3c) — a prune emitted by the Régin
  network-flow global-cardinality propagator. The antecedents are
  synthetic `AtomInScc` bridges (one per pruned value), each carrying
  the assignment `AtomEq(owner, v)` or the Hall-set absences of the
  variables sharing the value-copy's SCC — the M3-tighten shape
  generalised over per-value multiplicity. Activates learning on
  GCC-driven conflicts the same way M3a + `AtomInScc` does for
  allDifferent.
- `UnknownReason()` — a prune from a non-clause / non-allDifferent
  / non-linear propagator. The analyser treats `UnknownReason` as
  opaque and bails when the resolution chain hits one, so M3c–g
  still need to land to unlock learning on GCC, regular,
  cumulative, diff_n, and circuit conflicts.

- `AtomInScc(repVar, id)` (M3-tighten) — a synthetic bridge committed
  by `_AllDifferentPropagator` so a whole Hall set collapses into one
  resolvable atom. Its antecedents are the Hall set's defining
  absences (or, for assignment-style pruning, the single on-trail
  `AtomEq(owner, v)` of the pinned variable that holds the value).
  The analyser resolves through it; it never reaches a learned clause.

**M3-tighten for allDifferent (shipped).** The original M3a/M3b
companions shipped with a *coarse* "AtomNe for every absent declared
value across the implicated scope" antecedent shape. The first-UIP
analyser converges only when each resolution step adds at most one
at-conflict-level atom; the coarse shape includes many at-level atoms
per step (and references *sibling* prunes), so analysis bailed on
dense conflicts — the 4×4 magic square learned 0 clauses, with every
backtrack an analysis failure.

The structural fix (Chuffed / OR-Tools style intermediate atom
encoding) is now in place for allDifferent: `_AllDifferentPropagator`
commits a single `AtomInScc` bridge per removed value (shared across
all prunes of that value, so siblings collapse), and the analyser
resolves through it to the Hall set's defining absences — snapshotted
at propagation *entry* so they never reference this round's sibling
prunes. For assignment-style pruning ("value `v` removed because the
variable matched to it is pinned to `v`") the bridge's antecedent is
the single on-trail literal `AtomEq(owner, v)` — the "newest cause" —
which is what the degenerate singleton-SCC case (a value matched to a
pinned variable) needs and the coarse Hall-set lookup mis-handled.

Result: the 4×4 magic square now learns ≥ 5 clauses, the 3×3
converges on every conflict, and Inkala's "World's Hardest Sudoku"
learns 8 clauses (was 2). The linear bound-atom rewrite
(`LCG_PLAN.md` §3 task 2) is the remaining secondary follow-up so a
mixed allDifferent+linear conflict can converge end to end.

Two shortcuts were attempted and rolled back:

- **Relax the analyser** to accept multi-UIP clauses
  (non-asserting but theoretically sound).
- **Widen M3a's per-prune reason** to the whole constraint
  scope (eliminates the under-broad-reason worry).

Both broke Inkala's "World's Hardest Sudoku" (returned `FAILURE`
on a SAT problem). The whole-scope shortcut introduced a
circularity in resolution (the reason for `AtomNe(v, k)` includes
`AtomNe(v, k)` itself); the multi-UIP shortcut has a subtler
behavioural interaction that wasn't isolated. The Hall-set-narrow
+ strict 1-UIP shipping code is the best balance found: sudoku-
medium learns 1 clause, Inkala's hardest learns 2, dense
conflicts learn 0. See `HANDOVER.md` §0 "Recommended next pick"
for the full debug log and the structural-fix entry point.

The trail rolls back in lockstep with the engine's domain trail.
After a successful solve the trail covers every prune that survived
to the solution; after a search-detected unsat solve it is empty;
after a preprocessing-detected unsat (AC-3 wipeout before search
begins) it carries the failing antecedent chain so M2 can run
conflict analysis on it.

### Perf anchor

`benchmark/benchmark.dart` runs a `bench(lcg)` section comparing
plain backtracking (`Problem.getSolution`) and LCG
(`Problem.solveWithLcg`) on the same problem, with the standard
5-rep warm-up + 25-rep median methodology used by the other
bench sections. Sample row layout:

```
pigeonhole CNF 8-in-7 (UNSAT, harder)
  plain  NO SOLUTION  ~1.7 s   d:32780 b:65560 p:65561
  lcg    NO SOLUTION  ~0.6 s   d:1135  b:1576  p:2019
                                 learned:442/forgotten:0 bj:236/396
```

Indicative numbers from a recent local run (will vary with CPU /
JIT warm-up):

| Problem            | plain decisions | LCG decisions | ratio | plain µs | LCG µs |
|--------------------|----------------:|--------------:|------:|---------:|-------:|
| pigeonhole 6-in-5  |             374 |           106 |  3.5× |     8932 |   7547 |
| pigeonhole 7-in-6  |            3245 |           365 |  8.9× |   161446 |  79309 |
| pigeonhole 8-in-7  |           32780 |          1135 | 28.9× |  1737910 | 637857 |
| 8-queens (wash)    |              10 |            10 |  1.0× |     1979 |   2007 |

The 8-queens row is the **wash reference**: every conflict on
n-queens flows through the binary `!=` and diagonal-difference
predicates that emit `UnknownReason`, so the analyser bails and
the engine falls back to chronological backtrack. The two rows
should match on decisions and stay within noise on wall-clock —
i.e. LCG's per-prune implication-trail bookkeeping carries
negligible overhead on problems it cannot help. The pigeonhole
rows are the showcase: the decision-count ratios grow with the
problem size (~3× → ~9× → ~29×) — exactly the asymptotic pattern
the LCG literature predicts for this family. Wall-clock wins are
smaller than decision-count wins because LCG runs an extra
propagation pass at each landing site plus pays per-prune
implication-trail bookkeeping; the wins are still substantial on
the harder instances. Run `dart run benchmark/benchmark.dart`
for fresh numbers.

---

## API surface

All types live under `package:dart_csp/dart_csp.dart` (re-exported
from `lib/src/lcg/`):

- **`Problem.solveWithLcg({consistency, cancelToken, learnedClauseCap})`**
  — runner entry point. Same shape as `getSolution`. The
  `learnedClauseCap` kwarg (default 1000) bounds the learned-clause
  pool: when the pool exceeds the cap the oldest half are dropped
  via FIFO forget. Set lower for memory-constrained runs; set higher
  on extremely deep search trees where the learned clauses keep
  paying off.
- **`CSP.solveWithLcg(...)`** — the static used by the extension
  above; available for callers building their own `CspProblem`.
- **`CSP.lastImplicationTrail`** — read-only snapshot of the most
  recent run's implication trail. Null after a non-LCG solve.
  Intended for tests and tooling.
- **`Atom`** sealed hierarchy: `AtomEq`, `AtomNe`, `AtomLe`,
  `AtomGe` (`varName`, `value`, `negate()`, `isEntailedBy`).
- **`DomainView`** — `contains(int)`, `minValue`, `maxValue`,
  `isSingleton`, `isEmpty`.
- **`ImplicationReason`** abstract base + `DecisionReason` (decision
  pin), `ClauseReason` (clause unit-prop, carries antecedent atoms),
  `UnknownReason` (placeholder for non-clause propagators — M3
  replaces this per propagator).
- **`ImplicationEntry`** record type.
- **`AnalysisResult` / `firstUipAnalyse`** — pure first-UIP analyser
  exposed for tests and tooling; the engine calls it on every
  clause-propagator conflict inside `solveWithLcg`.
- **`SolverStats.learnedClauses` / `SolverStats.forgottenClauses`** —
  per-solve counters. `0` for non-LCG entry points.
- **`SolverStats.lcgAnalysisFailures`** — conflicts that carried a
  concrete (non-opaque) reason but where `firstUipAnalyse` could not
  isolate a single UIP, so no clause was learned and the engine fell
  back to chronological backtrack. The M3-tighten diagnostic: a high
  ratio of `lcgAnalysisFailures` to `learnedClauses` on a
  propagator-heavy problem means the per-prune explanations are too
  coarse to converge (see `test/lcg/m3_tighten_diagnosis_test.dart`).
  `0` for non-LCG entry points.
- **`firstUipAnalyse(..., {trace})`** — optional diagnostic callback
  that reports the working clause, each resolution step with its
  at-conflict-level count, and the terminal UIP/bail. Null on the
  hot path; used to inspect convergence during M3-tighten.

All of the above are **experimental** (`STABILITY.md`) — surface
will evolve as M3 lands.

---

## What's next

- **M2a (shipped)** delivered the first-UIP analyser as a pure
  function over the implication trail: `firstUipAnalyse(trail,
  conflictReason) → AnalysisResult?`. `_ClausePropagator` emits
  `ClauseReason` on every unit-prop, carrying the antecedent atoms.
  The analyser is verified on hand-crafted trails covering
  decision-only, multi-step resolution, cross-level antecedents,
  and opaque-reason fallbacks.
- **M2b (shipped)** wires the analyser into the engine. New
  `_searchOneLcg` mirrors the CBJ sealed-result pattern: on every
  propagation failure the engine calls `firstUipAnalyse`, converts
  the learned atoms back into a `ClauseSpec`, posts it as a
  fresh `NaryConstraint` into `_csp.naryConstraints` + `_naryIdx`,
  and signals a backjump up the recursion to the clause's second-
  highest decision level. A simple FIFO forget policy (cap 1000,
  configurable via `learnedClauseCap:`) drops the oldest half once
  the pool overflows. Acceptance gate: pigeonhole-CNF 7-in-6 cuts
  decisions ~9× vs plain backtracking; 8-in-7 cuts ~29×.
- **Lazy atom encoding (shipped)** extends `_ClausePropagator` to
  evaluate non-boolean atom literals via `Atom.isEntailedBy`, so
  learned clauses can mix `AtomEq` / `AtomNe` / `AtomLe` / `AtomGe`
  over arbitrary integer domains. M2b's "non-boolean → chronological
  backtrack" fallback is gone; M3's per-propagator `explain`
  companions can now post their atom-clauses through the same
  watch-literal infrastructure.
- **M3a (shipped)** delivers the first per-propagator explanation:
  `AllDifferentReason` carries the Hall-set antecedents extracted
  off `_AllDifferentPropagator`'s existing Régin SCC decomposition.
  Per-variable Hall sets are computed as the union of SCCs of
  pruned values; the antecedents are `AtomNe(h, k)` for every
  Hall-set variable `h` and every value `k` declared in `h`'s
  original domain but absent from `h`'s current domain. Sound:
  the Régin matching depends only on which values are in each
  variable's current domain. Acceptance: Inkala's "World's Hardest
  Sudoku" learns 2 clauses with 1 non-chronological backjump.
- **M3b (plumbing shipped, tightening deferred)** adds
  `LinearBoundReason` for the bounds-consistency linear
  propagator. Engine plumbing is identical to M3a's; the coarse
  antecedent shape limits analyser activation on dense conflicts.
  A per-prune tightening pass (see `LCG_PLAN.md` §3 M3-tighten)
  is the natural next step.
- **M3c (shipped)** extends the `AtomInScc` bridge to
  `_GccPropagator`, generalised over per-value multiplicity
  (`GccFlowReason`). A GCC with exact counts (≡ allDifferent) now
  learns on its conflicts: Inkala-as-GCC learns 8 clauses, cuts
  backtracks 48 → 42. The remaining M3 companions — `_Regular`
  (M3d), `_Cumulative` (M3e), `_DiffN` (M3f), `_Circuit` (M3g) —
  inherit the same intermediate-atom approach.
- **M3** adds per-propagator `explain` companions (allDifferent,
  linear, GCC, regular, cumulative, diff_n, circuit). Each is a
  self-contained landing — large structured CSPs see a step
  improvement after `_AllDifferentPropagator.explain` alone.
- **M4** wires LCG into restart + dom/wdeg + VSIDS state so
  learned clauses bump the picker correctly. *Attempted and
  reverted:* pairing `solveWithLcg` with VSIDS surfaced an
  order-dependent learned-but-FAILURE bug (a different decision order
  makes a SAT instance return `FAILURE`), so `solveWithLcg` stays on
  the MRV picker until that is root-caused. See `LCG_PLAN.md` §M4.
- **M5** ships `bench(lcg)`, this doc gets a worked-example
  section, and optional Sörensson–Eén clause minimisation lands.
- **M6** (optional, Tier-2) — parallel learned-clause sharing.

See [`LCG_PLAN.md`](../LCG_PLAN.md) for the full architecture,
open design questions, and references.

---

## References

- Marques-Silva, J. P. & Sakallah, K. A. (1996). "GRASP: A search
  algorithm for propositional satisfiability." DAC 1996.
- Eén, N. & Sörensson, N. (2003). "An extensible SAT-solver." SAT
  2003.
- Ohrimenko, O., Stuckey, P. J. & Codish, M. (2009). "Propagation
  via lazy clause generation." *Constraints* 14.
- Feydy, T. & Stuckey, P. J. (2009). "Lazy clause generation
  reengineered." CP 2009.
- [Chuffed solver source](https://github.com/chuffed/chuffed) —
  battle-tested reference implementation; per-propagator `explain`
  methods are good models for the dart_csp M3 work.

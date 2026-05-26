# Lazy Clause Generation (LCG) — implementation plan

A focused plan for the next session(s) to bring **conflict-driven
nogood learning** into `dart_csp`. This doc exists so a fresh
session can pick the work up cold: scope, architecture,
milestones, the per-propagator explanation contract, and the
open design questions are all here.

**Estimated effort:** 4–6 sessions. LCG is the single biggest
strategic gap PLAN.md flags. The mechanics are well-known but
the surface — explanation companions on every specialised
propagator, learned-clause storage, activity / forget policies,
restart interaction with the new dom/wdeg + VSIDS state — has
real choices to make. Each milestone below is a self-contained
landing.

LCG is the technique that makes CP-SAT (OR-Tools), Chuffed, and
the rest of the modern CP-SAT family outperform non-learning
solvers by **orders of magnitude** on hard structured instances.
On problems where dart_csp's search tree grows exponentially with
problem size, LCG typically replaces the exponential with a
polynomial — minutes-vs-hours, or solvable-vs-intractable. It is
not a marginal optimisation; it changes what class of problems
the solver can handle.

---

## 1. Scope decision: integer-domain LCG first, single-thread

Ship integer-domain LCG layered on top of the existing
`_BacktrackEngine` first. Defer set-variable / float-variable
LCG, and defer parallel learned-clause sharing.

- LCG's core idea: every propagation that prunes a domain
  produces an **explanation** — a set of literals over
  `(variable, value)` pairs that, taken together, force the
  prune. When propagation fails, the explanation graph rooted
  at the conflict is walked back through the **first-UIP**
  (Unique Implication Point) cut to produce a **learned clause**:
  a disjunction of literals stating "at least one of these
  earlier choices must be false." The learned clause is added
  to a pool and consulted by the propagator going forward.
- The existing `_ClausePropagator` machinery is the natural home
  for learned clauses: it already implements the two-watched-
  literal scheme that gives O(1) amortised per-call cost, and
  its monotone-under-trail invariant means no rollback
  bookkeeping is needed. Learned clauses become first-class
  `ClauseSpec`s posted dynamically during search.
- Each specialised propagator (allDifferent, linear, regular,
  GCC, cumulative, diff_n, circuit, clause-already) needs an
  **`explain(literal)`** companion that produces the conflict
  clause for any prune it makes. The propagator side of LCG is
  the bulk of the work and where the per-propagator scoping
  comes from (each can be added in its own session).
- Variable / value literals over the multi-valued integer
  domains dart_csp uses (`x = v`, `x ≠ v`, `x ≤ v`, `x ≥ v`)
  need a literal encoding distinct from the boolean
  `_ClausePropagator`'s `(varName, positive)` shape. The
  encoding decision (eager vs lazy literal materialisation;
  channelling boolean indicator variables vs a separate atom
  table) is the **single biggest design decision** in this plan
  and the central topic of §4.

**Out of scope for v1:** explanation for set-variable
constraints (`addSetEquals`, `addSetUnion`, etc.); float-
variable LCG (depends on float-variable support landing first);
clause-sharing between parallel workers (parallel SAT
literature; deferred until the single-thread engine is stable);
clause-minimisation post-resolution (Sörensson & Eén 2009 — a
constant-factor improvement on learned-clause quality, worth
adding once the loop works).

---

## 2. Architecture sketch

```
lib/src/lcg/
├── atom.dart        # Literal encoding: (variable, op, value) atoms +
│                    # negation, hash/equality, ↔ boolean clause literal.
├── explain.dart     # Explanation graph: ImplicationReason base class +
│                    # per-propagator concrete subclasses. Records the
│                    # antecedent literals for every prune.
├── analyze.dart     # First-UIP conflict analysis. Walks the
│                    # implication graph from the conflict back to
│                    # the first UIP, builds the learned clause.
├── learned.dart     # Learned-clause pool: storage, activity bumps,
│                    # decay, forget policy.
└── lcg.dart         # Top-level: Problem.solveWithLcg / minimizeWithLcg
                     # entry points; wires the explanation hooks into
                     # the engine.
```

The existing `_ClausePropagator` continues to handle every clause
(both user-posted and learned); learned clauses are added to the
engine via the same path user clauses take, plus a side-table
that tracks activity / age for the forget policy.

### Atom shape

```dart
sealed class Atom {
  String get varName;
  /// Is the atom currently entailed by [domains]? Used by the
  /// propagator to evaluate atom truth at propagation time.
  bool isEntailedBy(Map<String, _DomainRep> domains);
  /// Negate the atom. (x = v).negate() → (x ≠ v).
  Atom negate();
}

class AtomEq extends Atom { String varName; int value; }
class AtomNe extends Atom { String varName; int value; }
class AtomLe extends Atom { String varName; int value; }
class AtomGe extends Atom { String varName; int value; }
```

The four atom forms cover every prune the existing propagators
make — bounds tightening (`AtomLe` / `AtomGe`), value removal
(`AtomNe`), and assignment (`AtomEq`). Boolean variables fold
into the integer atom shape (`x = 0` / `x = 1`) so the existing
`_ClausePropagator` becomes a special case of the unified clause
machinery.

**Why not eager boolean encoding?** Some LCG implementations
materialise every `(variable, value)` pair as a boolean
indicator variable up front (the "eager" encoding); others (the
"lazy" encoding) only materialise atoms that actually appear in
a learned clause. Lazy is what Chuffed and OR-Tools both do —
the indicator-variable count would blow up on the bitset-domain
problems dart_csp targets. See §4 for the decision and the
caveats.

### Explanation contract

Every propagator that prunes a domain must record **why**:

```dart
abstract class ImplicationReason {
  /// The atoms whose joint truth forced the prune. Used by
  /// first-UIP analysis to walk the implication graph.
  List<Atom> antecedents();
}
```

For each prune, the engine stores `(prunedAtom, reason)` on a
new "implication trail" parallel to the existing `_trail`. The
implication trail is consulted during conflict analysis to walk
back from the conflict to the first UIP.

Concrete reasons live with their propagator:

```dart
class AllDifferentReason extends ImplicationReason { … }
class LinearBoundReason extends ImplicationReason { … }
class RegularPathReason extends ImplicationReason { … }
class GccFlowReason extends ImplicationReason { … }
class CumulativeProfileReason extends ImplicationReason { … }
class DiffNRegionReason extends ImplicationReason { … }
class ClauseUnitPropReason extends ImplicationReason { … }
```

Each subclass holds whatever propagator-specific state is needed
to reconstruct the antecedents on demand. Pre-materialising the
antecedent list at prune time is simpler but expensive; lazy
materialisation (only called during conflict analysis) is what
Chuffed does. Defer the lazy-vs-eager choice to M2 when the
first explanation companion lands.

### First-UIP loop

```
On propagation failure:
1. The failing constraint produces its own conflict explanation:
   the antecedents that, taken with the literals forced inside
   propagation, are jointly unsatisfiable.
2. Initialize the working clause to the negation of the conflict
   atoms (so the clause says "at least one of these must be
   false next time").
3. Walk the implication trail backward. At each step:
   a. Pick the most-recently-implied atom in the working clause.
   b. If exactly one atom in the working clause is at the
      current decision level → stop (that atom is the UIP).
   c. Otherwise: resolve the working clause with the reason for
      that atom (replace the atom with its antecedents'
      negations).
4. Compute the second-highest decision level in the resulting
   clause: that's the backjump target.
5. Add the learned clause to the pool.
6. Backjump to step 4's level, re-propagate the learned clause
   (it's now asserting: the UIP atom is forced after the
   backjump).
```

This is the textbook MiniSat first-UIP loop. The classic
references are Marques-Silva & Sakallah 1996 (the original
GRASP first-UIP paper) and Eén & Sörensson 2003 (MiniSat).

---

## 3. Milestones

Each milestone is a self-contained, testable increment that
delivers value even if the next milestone never lands. Land them
in order.

### M1 — Atom encoding + implication trail + LCG runner shell

- `lib/src/lcg/atom.dart` with the four `Atom` subclasses, plus
  `Atom.fromLiteral(Literal)` and `Atom.toClauseLiteral()`
  channels so the existing `_ClausePropagator` can handle
  learned atoms without further changes.
- Implication trail: new `Map<String, List<ImplicationEntry>>`
  on `_BacktrackEngine`, parallel to `_trail`. Append on every
  prune; consult during conflict analysis.
- New runner shell: `Problem.solveWithLcg` returning the same
  shapes as `getSolution`. Initially identical to
  `getSolution` — the LCG loop is a no-op until M2 ships an
  explanation. M1 lands the wiring + types only.
- Tests: assert the implication trail captures the right
  reason kinds, that the trail is rolled back correctly on
  backtrack, and that `solveWithLcg` matches `getSolution` on
  a handful of regression problems.

### M2 — Clause-propagator explanation + first-UIP loop ✅ SHIPPED

**M2a (analyser, pure function) + M2b (engine wiring + forget)
both landed.** The acceptance gate held: pigeonhole-CNF 7-in-6
cuts decisions ~9× vs plain backtracking, 8-in-7 cuts ~29× —
solidly inside the 10–100× target band the literature predicts
for this family.

- The existing `_ClausePropagator` already has a natural
  explanation: when it forces literal `L` from a clause `(L1 ∨
  L2 ∨ ... ∨ L)`, the antecedents are `(¬L1, ¬L2, ..., ¬Lk)`
  for every other-than-forced literal. Hook added via
  `ClauseReason(antecedentAtoms)`.
- First-UIP analysis lives in `lib/src/lcg/analyze.dart` as a
  pure function `firstUipAnalyse(trail, conflictReason) →
  AnalysisResult?`. Walks the implication trail backward;
  resolves clauses; stops at the first single-decision-level
  atom. Conservatively returns null when the resolution chain
  hits an opaque (non-clause) reason — sound but weaker than
  full M3 coverage.
- Analysis wired into a new `_searchOneLcg` recursion that
  mirrors the CBJ sealed-`_SearchResult` pattern. On
  propagation failure the engine analyses, posts the learned
  clause into `_csp.naryConstraints` + `_naryIdx` via the same
  `_ClausePropagator` infrastructure, and signals a
  `_LcgBackjump(targetLevel)` up the search stack. Caller frames
  roll back their own pin and either propagate the signal or
  consume it (when `targetLevel == depth`) and re-propagate so
  the learned clause's UIP literal can assert.
- Forget policy: simple FIFO cap (default 1000, configurable
  via `learnedClauseCap:`). When the pool exceeds the cap the
  oldest half are dropped from `_csp.naryConstraints`,
  `_naryIdx`, and `_clauseWatchers`. Activity-weighted forget +
  decay is a follow-up — the FIFO cap is enough for the M2b
  acceptance benchmark.
- Tests: `test/lcg/pigeonhole_test.dart` runs 6-in-5, 7-in-6,
  8-in-7 with decision-count ratio assertions plus
  forget-trigger + non-boolean fallback + mixed-domain SAT
  paths. Existing `solve_with_lcg_test.dart` parity tests
  continue to pass because non-CNF conflicts still fall back to
  chronological backtrack (the analyser bails on
  `UnknownReason`).

### M3 — Specialised propagator explanations (priority order)

Each propagator's explanation is a self-contained subtask. The
ordering below reflects PLAN.md's "most-used first" and the
literature's perf-impact ordering on MiniZinc Challenge
problems.

**M3a — `_AllDifferentPropagator` explanation. ✅ SHIPPED.** The
natural explanation for a value pruned by allDifferent is the Hall
set that covers it: a subset of variables whose union of domains
has cardinality ≤ |subset|, so the pruned value is forced. Régin
matching already identifies these as "tight" SCCs in the residual
graph; explanation extraction is reading them off the existing SCC
decomposition. References: Régin 1994 + Quimper & Walsh 2008
("Decompositions of all_different, …" — has the explanation
construction).

Implementation (`lib/src/solver.dart`): `_AllDifferentPropagator`
gained an optional `originalDomains:` constructor parameter; when
non-null (LCG mode), the propagator builds a `varsInScc` map once
per call and per-variable derives the Hall set as the union of
SCCs of pruned values. The antecedent atoms are `AtomNe(h, k)` for
every Hall-set variable `h` and every value `k` declared in `h`'s
original domain but absent from `h`'s current domain — sound
because the Régin matching depends only on which values are in
each variable's current domain. Constraint-level conflicts
(matching failure, pigeonhole, post-prune empty domain) use the
entire scope as the Hall set via the engine's new
`_allDifferentConflictReason` helper. Acceptance: Inkala's
"World's Hardest Sudoku" (2010) learns 2 clauses + 1
non-chronological backjump skipping 1 level. See
`test/lcg/all_different_explain_test.dart`.

**M3b — `_LinearPropagator` explanation. ⚠️ PLUMBING SHIPPED,
TIGHTENING DEFERRED.** Bounds-consistency propagation prunes
`x ≥ k` (or `≤ k`); the explanation is the sum of every other
variable's current bound. Mechanical — the propagator already
iterates over the coefficient list to compute the residual.

Implementation (`lib/src/solver.dart`): `_LinearPropagator` gained
an optional `originalDomains:` constructor parameter (mirroring
M3a's shape); the `applyUpdate` callback grew a `reason:` kwarg.
`_buildBoundReason` emits per-prune antecedents from the other
variables' current absences via the shared
`_domainShapeAntecedents` helper. Engine call site captures
`_lastConflictReason` via the new `_linearConflictReason` helper.

**Known limitation.** The current coarse "AtomNe-per-absent-value
across the Hall set / other-variable scope" antecedent shape
works occasionally (sudoku-medium learns 1 clause via M3a) but
fails on dense-conflict problems (4×4 magic squares with
linear-spec sums: 7 backtracks, 0 learned). The first-UIP
analyser requires resolution to converge on a single
at-conflict-level atom (the UIP); CSP propagator reasons over
multiple at-level variables can leave the working clause stuck
with multi-UIP. A **structural tightening pass** is needed before
M3c–g land — see the M3-tighten section below for the concrete
plan and the debug log from a failed shortcut attempt.

**M3-tighten — intermediate atom encoding for first-UIP
convergence. ⏳ NEXT.** Required before M3c–g; without it, the
per-propagator companions ship as plumbing only and don't drive
consistent learning. This is a multi-session refactor, not a
one-session fix.

### What's broken

The first-UIP analyser in `lib/src/lcg/analyze.dart` converges
iff every propagation reason carries ≤ 1 at-conflict-level
antecedent (textbook MiniSat invariant). Boolean unit-prop
satisfies this — one literal "falls" most recently. CSP
propagators with multi-variable scopes (allDifferent, linear,
GCC, regular, cumulative, diff_n, circuit) produce reasons with
multiple at-level antecedents, and the walk can't terminate at
a single UIP.

### Failed shortcut: just relax the analyser

Tried in the M3b shipping session: drop the `atLevelCount != 1`
guard in `firstUipAnalyse`, accept multi-UIP clauses as
non-asserting but sound implicates. The resolution invariant
preserves "working clause conjunction is unsat" at every step,
so the disjunction-of-negations is sound regardless of
convergence.

Empirical result: **Inkala's "World's Hardest Sudoku" returned
`FAILURE` on a SAT problem** with ~40 learned clauses. The
soundness argument is theoretically intact but something in the
behavioural interaction with the engine breaks. Reverted.

### Failed shortcut: widen per-prune to whole-scope

Tried: change M3a's per-prune reason from "Hall-set absences"
to "whole-constraint-scope absences." Reasoning: the wider
reason is unambiguously sound (the constraint scope's domain
configuration deterministically reproduces the propagator's
output, so `whole-scope absences → prune` holds
unconditionally).

Empirical result: **also returned `FAILURE` on Inkala** with 37
learned clauses, even with strict 1-UIP. Root cause: when the
prune is `AtomNe(v, k)` (multi-value prune of `k` from `v`),
the whole-scope reason includes `AtomNe(v, k)` itself as an
antecedent — making resolution a no-op. The walk grinds
through every at-level entry without progress, occasionally
returning "learned clauses" that are essentially the conflict
reason itself and that miss valid solutions on a path I didn't
isolate.

Reverted; all 966 tests pass on the Hall-set-narrow + strict
1-UIP code.

### The structural fix

The textbook approach (Chuffed, OR-Tools, Feydy & Stuckey 2009)
is **intermediate atom encoding**: introduce additional atom
kinds on the implication trail that act as "bridge" atoms
between propagator-emitted reasons and SAT-CDCL resolution.
Each propagator commits intermediate atoms (e.g., "this
variable is in this Hall set," "this variable's upper bound is
≤ k") as it computes them; the resolution chain then becomes:

```
prune  →  intermediate-atom  →  (multiple lower-level atoms)
```

Each step in the chain carries ≤ 1 at-conflict-level antecedent
(the intermediate atom was committed at the current level, but
its own antecedents are at lower levels). The first-UIP loop
converges naturally.

### Concrete tasks

1. **Extend `_recordImplications`** in `lib/src/solver.dart` to
   emit `AtomLe(v, ub)` / `AtomGe(v, lb)` entries when a
   propagator tightens a bound (currently only `AtomEq` /
   `AtomNe` are emitted). Monotone-under-trail for both atom
   kinds, so no extra rollback bookkeeping.

2. **Add an `AtomInScc(varName, sccId)` (or analogous) atom**
   used by `_AllDifferentPropagator`. The propagator commits
   one such atom per variable per propagator call when LCG is
   on; the SCC's defining absences become the antecedents of
   `AtomInScc`. The per-prune reason then chains through
   `AtomInScc`.

3. **Verify 1-UIP convergence by hand** on a 3-variable
   allDifferent UNSAT toy before scaling up.

4. **Acceptance gate**: 4×4 magic-square (linear-spec) learns
   ≥ 5 clauses; Inkala's hardest still finds the unique
   solution; pigeonhole-CNF still cuts ≥ 5×.

### Lessons banked for future sessions

- **Hall-set narrow IS sound** — I doubted this during debug
  and chased the wrong fix. The SCC of a pruned value is a
  tight Hall set (|H| = |dom_union(H)|) and that property is
  implied by the absences within H alone. Don't re-debate.

- **The shared `_domainShapeAntecedents` helper currently
  emits `AtomNe`-per-absent-value uniformly**, even when the
  variable's current domain is singleton (where the trail
  carries `AtomEq` for the survivor instead). That mismatch
  is harmless for soundness (the unmatched atoms are silently
  invisible to the analyser) but makes per-prune tightening
  harder — the right shape needs to *match the trail*. M3-
  tighten should use trail-shape antecedents (AtomEq for
  singletons, AtomNe for multi-value prunes) where the
  intermediate atom encoding doesn't fully cover it.

- **The empirical "learned but FAILURE" symptom is hard to
  debug from outside** — add instrumentation to dump the
  exact learned clauses and walk a specific UNSAT path by
  hand before guessing.

**M3c — `_GccPropagator` explanation.** Same idea as
allDifferent but with arbitrary counts. The flow-based propagator
identifies "saturated" arcs in its residual graph; the
explanation is the set of variables/values participating in the
saturated cut. Reference: Régin 1996 (the GCC paper).

**M3d — `_RegularPropagator` explanation.** A value pruned at
position i in the input string corresponds to a DFA state
transition that has no extension to an accepting state. The
explanation is the set of variables on the path from start to
the failing transition, projected onto their pinned values.
Reference: Pesant 2004 (the regular paper) + Beldiceanu et al.
2007 on path-based explanations.

**M3e — `_CumulativePropagator` explanation.** Time-table
prunes `start_i ≥ t` (or `≤ t`) when the resource profile at
time t exceeds capacity even with task i removed. The
explanation is the set of tasks that contribute to the
overlap interval. Reference: Vilím 2009 ("Edge finding
filtering algorithm for discrete cumulative resources in O(kn
log n)" — has explanation discussion in the appendix).

**M3f — `_DiffNPropagator` explanation.** The forbidden-region
sweep identifies a forbidden box; the explanation is the set of
rectangles whose compulsory parts cover the box. Mechanical
once the sweep state is materialised.

**M3g — `_CircuitPropagator` / `_SubcircuitPropagator`
explanation.** A removed arc has an explanation in terms of the
existing sub-tour or the cycle-detection state at that
propagation step.

**Sequencing.** M3a + M3b shipped as *plumbing* (the propagator-
to-engine wiring + reason types) but the coarse antecedent shape
limits actual learning. **M3-tighten is the next strategic pick
and is a hard prerequisite for M3c–g** — otherwise those
companions ship into the same coarse-antecedent dead end. After
M3-tighten the per-propagator companions can land in
priority order (most-used first) with each contributing
measurable learning. Estimate: M3-tighten is 2–3 sessions
(intermediate atom encoding plus engine + analyser plumbing);
M3c–g become ~1 session each on top of that.

### M4 — Restart + activity integration

LCG composes with restarts and dom/wdeg / VSIDS picker
asymmetrically:

- **Restarts.** Learned clauses persist across restart (that's
  the whole point — restart drops the search tree but not the
  knowledge). Wire the existing `solveWithRestarts` to retain
  the learned-clause pool across restarts.
- **dom/wdeg.** The learned-clause additions themselves should
  bump dom/wdeg weights for the variables they reference.
  Without this, the wdeg picker doesn't see the new structure
  the learned clauses encode.
- **VSIDS.** The classic VSIDS bump rule already handles this
  correctly — every literal in a learned clause gets its
  activity bumped at clause-add time. Verify the existing
  `_bumpActivityFor` works on the new code path.
- **Last-conflict.** Compose cleanly with first-UIP because LC
  picks the most-recent-conflict variable; first-UIP makes that
  variable explicit (it's the UIP atom).

### M5 — `bench(lcg)` + docs + clause-minimisation

- New `bench(lcg)` section in `benchmark/benchmark.dart`
  running pigeonhole, magic-square, large UNSAT CNF, and one
  RCPSP-style problem (if available — depends on whether the
  cumulative RCPSP benchmark is already there) with and without
  LCG. Same warm-up + median methodology as the existing
  sections.
- `doc/lcg.md` topical guide covering the atom encoding,
  first-UIP loop, per-propagator explanation construction,
  forget / activity / restart policies, and a worked example
  showing the learned-clause progression on a small pigeonhole
  instance.
- **Clause minimisation** (Sörensson & Eén 2009) optional in
  M5: after the learned clause is constructed, attempt to
  remove literals that are entailed by the others via single-
  step resolution. A constant-factor improvement (~30% smaller
  clauses) but worth shipping once the loop is stable.
- `PLAN.md` flips the LCG strategic-gap entry from `[ ]` to
  `[x]`; `STABILITY.md` classifies the LCG entry points as
  experimental; `README.md` gains a section.

### M6 (optional) — Parallel clause sharing

- Worker isolates each run an LCG loop with a different RNG
  seed; periodically exchange learned clauses via the existing
  `lib/src/isolate_runner.dart` wire protocol.
- A "useful clause" filter (clauses with LBD ≤ 2 — Audemard &
  Simon 2009) reduces the exchange bandwidth.
- Tests: timing comparison single-thread vs N-worker on a hard
  UNSAT problem.

Genuinely Tier-2; ship M1–M5 first.

---

## 4. The atom-encoding decision (eager vs lazy)

This is the single biggest design decision in the plan and the
one that constrains everything downstream. Two options:

**(a) Eager encoding.** Up front, materialise a boolean
indicator variable `b_{x=v}` for every `(variable, value)` pair
in the problem (and `b_{x≤v}`, `b_{x≥v}` for the bounds atoms).
Channel domain operations through these booleans so every
propagator's prunes translate directly to clause literals.

- *Pro:* every learned clause is already in a form the existing
  `_ClausePropagator` understands; no separate atom-pool
  machinery needed.
- *Con:* the number of indicator variables is `Σ_v |dom(v)|`,
  which for a moderate problem with bitset domains can be
  100k+. Each indicator is itself a constraint with the
  underlying variable. The memory + per-propagation overhead
  is real.

**(b) Lazy encoding** (Chuffed-style). Atoms exist as `(var,
op, value)` tuples; the `_ClausePropagator` learns about each
atom only when it appears in a learned clause; per-atom
indicator variables are created on demand. The "channelling"
between atom truth and domain state happens via the atom's
`isEntailedBy(domains)` method rather than via a separate
constraint.

- *Pro:* memory + per-propagation overhead scale with the
  number of *learned* atoms, not the total. Chuffed and
  OR-Tools both ship this.
- *Con:* the `_ClausePropagator` needs to be extended to know
  about lazy atoms — it currently assumes every literal is a
  `(varName, positive)` boolean. Extension is mechanical but
  non-trivial.

**Decision: ship lazy first.** The memory blow-up of eager is
prohibitive on the bitset-domain problems dart_csp targets, and
the per-propagation overhead would compete with the wins LCG is
supposed to deliver. The clause-propagator extension is the
right level of investment.

The dispatch shape inside the propagator becomes:

```dart
class _ClausePropagator {
  // ...existing fields...

  /// For lazy LCG atoms: the literal isn't a (var, bool) pair
  /// but a (var, op, value) Atom. Both kinds coexist in the
  /// same clause; the propagator dispatches per-literal.
  bool _isFalsified(Literal lit) {
    if (lit is BoolLiteral) return /* existing logic */;
    if (lit is AtomLiteral) return !lit.atom.isEntailedBy(domains);
    throw StateError(...);
  }
}
```

---

## 5. Open design questions

These are decisions worth making explicitly before the interface
gets large enough that changes hurt.

- **Where do LCG entry points live in the public API?** Options:
  (a) new `Problem.solveWithLcg` / `minimizeWithLcg` siblings,
  (b) a `useLcg:` flag on every existing entry point, (c) a
  separate `LcgEngine` class wrapping a `Problem`. Probably
  (a) for consistency with the existing `solveWith*` family;
  document in `STABILITY.md` as experimental. The flag-only
  shape (b) is tempting but the LCG path needs the implication
  trail + atom table — those are engine-level state that
  doesn't compose with non-LCG search.
- **Forget threshold.** Default is "keep clauses ≤ N old; halve
  N every 256 conflicts." Chuffed defaults to N=20000; MiniSat
  uses a different "geometric" schedule. Pick the Chuffed-style
  default and expose the threshold as a `forgetEvery:` kwarg.
- **Activity decay rate.** VSIDS activity decay (`1 / decay`)
  is shipped at `decay = 0.95`. Same decay applies to learned-
  clause activity by default; expose `clauseDecay:` for tuning.
- **Restart-frequency interaction.** Luby restarts default to
  scale 100. LCG search benefits from more aggressive restarts
  (the learned clauses survive, so each restart starts with
  more knowledge). Re-tune the default Luby scale once LCG is
  in.
- **CBJ vs LCG.** First-UIP analysis subsumes CBJ — every CBJ
  jump is also an LCG-compatible backjump, but LCG can jump
  further (to the second-highest learned-clause decision level
  instead of just the deepest conflict-causing variable).
  Decision: when LCG is enabled, ignore the `enableConflictBackjumping`
  flag and use first-UIP's backjump target. Document this
  asymmetry in `STABILITY.md`.
- **Failed-literal probing.** Sometimes called "look-ahead";
  related but distinct from LCG. Probing tries each literal in
  turn and propagates to find unit-implications. Cheap on top
  of LCG (the explanation infrastructure is already there) but
  expensive without. Defer to a follow-up.
- **Set-variable LCG.** Set variables decompose to per-element
  indicator booleans; the channels through those indicators
  already exist. Extending LCG to set variables is mechanical
  once integer LCG works but is a separate scoping doc when the
  time comes. Defer.

---

## 6. Test plan

### Unit tests

`test/lcg/atom_test.dart` — atom construction, negation,
`isEntailedBy` correctness across all three `_DomainRep` impls,
channelling to / from boolean clause literals.

`test/lcg/implication_trail_test.dart` — implication entries
appended on each prune; trail rolled back correctly on
backtrack; per-decision-level grouping consistent with the
existing `_assignedAtDepth` machinery.

`test/lcg/analyze_test.dart` — first-UIP analysis on
hand-crafted implication graphs (small enough to verify the
learned clause by hand). Cover the textbook cases:
single-decision-level conflict, multi-level resolution chain,
the UIP halting condition.

`test/lcg/explain_<propagator>_test.dart` — one file per
specialised propagator's explanation. Assert the antecedents
of each prune match the propagator's pruning condition.

### Integration tests

`test/lcg/integration_test.dart` — run `solveWithLcg` on a
handful of regression problems and assert match with `getSolution`
on satisfiable inputs and FAILURE on unsatisfiable. The interesting
assertion is on UNSAT pigeonhole: `lastStats.decisions` should
drop 10–100× vs the non-LCG run.

### Performance bench

`benchmark/benchmark.dart` gains a `bench(lcg)` section
comparing LCG vs the existing pickers on:

- Pigeonhole-CNF 8-in-7 and 9-in-8 (UNSAT, classic LCG
  showcase).
- Magic-square (SAT, structured).
- RCPSP-50 (SAT, structured with cumulative — only if the
  cumulative RCPSP benchmark has landed by then).
- A "moderate hardness" problem where LCG should be a wash or
  slight loss (the explanation-tracking overhead dominates on
  problems the search tree is already small on).

Methodology is the same warm-up + median as the existing
`bench(*)` sections.

---

## 7. References

- [Marques-Silva, J. P. & Sakallah, K. A. (1996). "GRASP: A
  search algorithm for propositional satisfiability." DAC
  1996.](https://www.cs.princeton.edu/courses/archive/fall03/cs597D/PAPERS/silva.pdf)
  The original first-UIP paper.
- [Eén, N. & Sörensson, N. (2003). "An extensible SAT-solver."
  SAT 2003.](http://minisat.se/downloads/MiniSat.pdf)
  MiniSat — the modern textbook implementation of first-UIP +
  two-watched-literal + VSIDS + restarts.
- [Ohrimenko, O., Stuckey, P. J. & Codish, M. (2009).
  "Propagation via lazy clause generation." Constraints 14.](https://people.eng.unimelb.edu.au/pstuckey/papers/lazy.pdf)
  The foundational LCG paper. Introduces the lazy encoding +
  channelling that this plan follows.
- [Feydy, T. & Stuckey, P. J. (2009). "Lazy clause generation
  reengineered." CP 2009.](https://people.eng.unimelb.edu.au/pstuckey/papers/cp09-lc.pdf)
  The Chuffed-precursor paper. Covers the lazy-encoding
  refinements + per-propagator explanation construction.
- [Audemard, G. & Simon, L. (2009). "Predicting learnt clauses
  quality in modern SAT solvers." IJCAI 2009.](https://www.ijcai.org/Proceedings/09/Papers/074.pdf)
  LBD (Literals Blocks Distance) — the standard learned-clause
  quality metric used by Glucose / Chuffed.
- [Sörensson, N. & Eén, N. (2009). "Minimizing learned
  clauses." SAT 2009.](http://minisat.se/downloads/MinimizingLearnedClauses.pdf)
  Post-resolution clause minimisation. The M5 optional add.
- [Vilím, P. (2007). "Global constraints in scheduling." PhD
  thesis, Charles University.](http://vilim.eu/petr/disertace.pdf)
  Explanations for cumulative / edge-finding propagators.
- [Régin, J.-C. (1994). "A filtering algorithm for constraints
  of difference in CSPs." AAAI 1994.](http://www.constraint.org/regin/papers/alldif.pdf)
  + Régin 1996 for GCC. The matching-based propagators dart_csp
  already implements; the same SCC decomposition that drives
  pruning also identifies the Hall sets for explanation.
- [Chuffed solver source](https://github.com/chuffed/chuffed)
  — battle-tested precedent. The first-UIP loop in `engine/`
  and the per-propagator `explain` methods are good reference
  implementations.
- [OR-Tools CP-SAT source](https://github.com/google/or-tools/tree/main/ortools/sat)
  — same. The atom-encoding decisions there mirror Chuffed's
  closely; both are good references for the corner cases the
  literature glosses over.

The Chuffed and OR-Tools implementations have been through
many rounds of MiniZinc Challenge competition. Both are
open-source and can be consulted for the corner cases this plan
doesn't fully nail down — the literature on LCG is sparse
relative to the literature on SAT-CDCL, and the "translate
SAT-CDCL to integer CP" step has more design choices than the
papers cover.

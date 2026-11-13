# Compact integer ranges

`Problem.addRangeVariable` retains an immutable `IntRangeDomain` list view.
Construction, model copying, domain classification and endpoint access use
constant storage. Existing list-shaped variable inspection remains available;
explicit iteration or `toList()` still visits every value.
Propagation traces with explicit before/after domain snapshots also enumerate
those values; their full-value payload is unsuitable for billion-value ranges.

```dart
final p = Problem()..addRangeVariable('x', 0, 1000000000);
p.addLinearEquals(['x'], [1], 765432100);
print(await p.getSolution()); // {x: 765432100}
```

Specialized linear propagation uses numeric extrema directly. Integer interval
filtering finds the retained endpoints with monotone predicate searches rather
than evaluating every integer. This preserves the arithmetic predicate's
existing behavior at fractional boundaries. Mixed float bounds intersect integer
intervals directly. Arbitrary predicates, generic GAC, and algorithms whose
meaning requires enumeration can still cost proportionally to domain size.

Value ordering avoids scoring/sorting when no binary outgoing constraint can
provide a useful score. Lazy candidates let find-first solves choose a value
without constructing a list of all alternatives. Explicit full enumeration
necessarily remains proportional to the output size.

## Compact learning and point exclusions

Both recursive and iterative LCG support billion-value ranges. Bound changes
produce bound atoms instead of one removal atom per skipped integer. Explicit
point exclusions use sorted immutable holes, preserved by arithmetic bounds,
optimization cuts, randomized ordinal selection and rollback. Unit `Eq`, `Ne`,
`Le` and `Ge` clauses filter ranges directly.

An exact domain explanation combines its bounds with its interior holes. When
several deductions together imply a stronger bound or singleton, the new reason
includes the previous domain context. For example, removing 0 under premise A,
then 1 under premise B from `{0,1,2}`, derives `x>=2` from A and B together.
Keeping only B would produce an unsound learned explanation.

The old blanket 100,000-value LCG restriction is removed. A large irregular
representation that cannot supply an exact compact shape still throws an
explicit `UnsupportedError`; it is never silently explained as a solid interval.
Small prior domains may retain eager point atoms for compatibility. Mixed-value
scopes whose missing non-integer values cannot be represented by integer atoms
use opaque reasons and conservative search instead of incomplete proofs.

This does not make arbitrary predicates or matching globals independent of
domain size: their support algorithms may still enumerate values. Storage for
sparse exclusions grows with the number of explicit holes. Ranges whose exact
cardinality or consecutive endpoints are not representable on the active
runtime are rejected, including JavaScript integer precision limits.

## Evidence

`test/compact_ranges_test.dart` and `test/compact_solver_test.dart` include
billion-value declarations/solves, mixed bounds, optimization, list compatibility,
and independent fractional-bound enumeration. `test/lazy_range_lcg_test.dart`
adds 80 independently enumerated sparse models, transitive reason entailment,
Hall/GCC bound-premise checks and short-trail billion-range fixtures. Separate
review checked 240 implication reasons and six learned clauses against bounded
oracles across both LCG engines and four decision orders. These are targeted
correctness checks, not a general proof of the solver.

Run `dart run benchmark/compact.dart` for paired warmed measurements. The
comparison is explicit-list versus compact construction/first-solving in the
current engine, not a claim against another solver or against an entire older
release. The final Dart 3.14.0 run at `689c38b` observed median microseconds of
372/57 at 10,000 values, 4,173/69 at 100,000, and 25,415/89 at 1,000,000
(list/compact, 15 paired repetitions). Hardware and concurrent load affect timing;
structural storage and
independent correctness tests provide the reproducible guarantees.

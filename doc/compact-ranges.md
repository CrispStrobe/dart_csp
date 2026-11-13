# Compact integer ranges

`Problem.addRangeVariable` retains an immutable `IntRangeDomain` list view.
Construction, model copying, domain classification and endpoint access use
constant storage. Existing list-shaped variable inspection remains available;
explicit iteration or `toList()` still visits every value.

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

## Learning limit in this checkpoint

The existing LCG explanation machinery can record one atom per removed value.
Until lazy explanations support large bound changes, a compact range larger than
100,000 values is rejected explicitly by the LCG entry point. Use ordinary
`getSolution()` for such ranges. The limit protects against hidden enumeration;
it does not claim that the mathematical problem is infeasible.

## Evidence

`test/compact_ranges_test.dart` and `test/compact_solver_test.dart` include
billion-value declarations/solves, mixed bounds, optimization, list compatibility,
and independent fractional-bound enumeration. Existing linear/interval/bitset and
mixed regressions remain in the targeted verification set (121 tests passed).

Run `dart run benchmark/compact.dart` for paired warmed measurements. The
comparison is explicit-list versus compact construction/first-solving in the
current engine, not a claim against another solver or against an entire older
release. A local Dart 3.14.0 run observed median microseconds of 241/46 at 10,000
values, 8,822/71 at 100,000, and 27,111/74 at 1,000,000 (list/compact, 15 paired
repetitions). Hardware and concurrent load affect timing; structural storage and
independent correctness tests provide the reproducible guarantees.

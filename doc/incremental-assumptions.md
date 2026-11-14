# Incremental assumption ownership and membership

`IncrementalSolver` retains a stable assumption identity so it can import
learned clauses only while their supporting assumptions remain active.
Changing the meaning of an assumption without changing its identity can make
that provenance invalid.

`assumeInSet` now shallow-copies its input at posting time; mutating the caller's set
does not alter the posted assumption. The copy retains the source set's
comparison policy. `assumePredicate` likewise copies its variable-name list,
including the arity used to adapt binary predicates. Predicate callbacks and
custom equality/hash callbacks remain application-owned, as do element objects:
keep their behavior and captured state stable, or retract and repost the
assumption after changing them.

Integer-range declarations are recognized directly when posting integer
assumptions. Posting equality or inequality over an `IntRangeDomain` does not
scan every value to establish that the domain contains integers.

## Existing integer-set dispatch limitation

For a nonempty set containing only integers and an integer domain,
`assumeInSet` posts a disjunction of ordinary integer equality atoms for the
set's **enumerated members**. It does not apply an arbitrary custom integer
set's `contains` relation to other domain values. This behavior predates the
2026-11-14 audit; the public documentation previously did not state the
restriction explicitly.

For example, a custom absolute-value-equality set whose representative is
`1` may report that it contains `-1`. The integer atomic path still posts
`x == 1`. On a domain `[-1, 1]` with a base constraint `x == -1`, that path
rejects the model. This limitation remains; comparator semantics are not
inferred from runtime type or a few sampled values.

When custom integer membership is intended, post it explicitly as a predicate:

```dart
import 'dart:collection';

import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  final allowed = HashSet<int>(
    equals: (a, b) => a.abs() == b.abs(),
    hashCode: (value) => value.abs().hashCode,
  )..add(1);

  final problem = Problem()
    ..addVariable('x', [-1, 1])
    ..addAtomClause([AtomEq('x', -1)]);
  final solver = IncrementalSolver(problem);
  final captured = UnmodifiableSetView<int>(allowed.toSet());
  solver.assumePredicate(
    ['x'],
    (assignment) => captured.contains(assignment['x']),
  );
  allowed.clear(); // The captured assumption retains its original membership.
  print(await solver.solve()); // {x: -1}
  print(await solver.solveWarm()); // {x: -1}
}
```

The predicate approach preserves the requested membership relation. An
arbitrary predicate can require domain enumeration; choose it deliberately
when that relation is needed. The audit verified this workaround on both the
starting and repaired revisions, including warm solves and mutation of the
original set. The [saved probe record](../benchmark/results/2026-11-14-integer-membership-probe.json)
preserves its source and observed results, with explicit reconstruction and
provenance limits. A future explicit membership-semantics option can make this
choice more convenient without silently changing existing integer assumptions.

For the plain integer sets used in the measured fixtures, atomic dispatch
retains exact pruning and the compact-range benefit. See the
[audit and complete measurements](performance-audit-2026-11-14.md).

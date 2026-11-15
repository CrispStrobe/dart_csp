# Independent review: geometry argument placeholders

Candidate: `088df75a334296b6c5d26940cdeb431d121bc0d9`  
Baseline: `080e0fed0b80f9ecd88d66fc20061e468be4cce5`

## Conclusion

No correctness blocker found in the production delta. The change in
`lib/src/geometry/solver.dart` replaces discarded ambient-size coordinate
buffers with argument lists initially filled by one zero-length placeholder
per `_WorkspaceScratch` instance. Performance retention remains dependent
on the independently qualified measurements.

## Reviewed invariants

- `_Workspace.arguments` has one consumer, `_SolveRun._evaluate`. Every
  argument slot is rebound to the current work or trial coordinates before
  either an analytic callback or automatic differentiation runs. Derivative
  and residual-only evaluations use the same population loop.
- Each layout retains its own growable `List<Float64List>` with the same
  length as before. The explicit `growable: true` preserves the previous
  list-comprehension behavior. Outer-list reuse and coordinate aliases are
  unchanged.
- The zero-length placeholder is local to each scratch instance. No other
  code reads initial argument contents, and no user callback or asynchronous
  yield occurs between obtaining an argument list and populating its slots.
  Public result snapshots use work coordinates and physical residual buffers,
  not these initial contents.
- Cancellation before a layout may leave private placeholders in unvisited
  lists. A subsequent evaluation rebinds every slot before use. Retry after
  an evaluation exception likewise repopulates the arguments. Stop checks,
  status precedence, and commit/rollback code are unchanged.
- `_Workspace.fork` creates independent lazy scratch rather than copying or
  sharing argument lists. Clean-component reuse does not read initial
  argument contents. Active-session solve reentry and forking remain
  rejected; another session owns separate scratch.
- Residual/Jacobian buffer shapes, parameter order, fixed-parameter handling,
  automatic differentiation dimensions, numerical operations, solver
  selection, and tolerances are unchanged.

## Allocation caveat

For a scratch instance with zero total residual dependencies, the candidate
creates one zero-length typed list that the baseline did not create. With
one dependency it replaces one ambient-size allocation with one empty
allocation; with multiple dependencies it eliminates additional initial
coordinate arrays. This is a bounded allocation-accounting caveat, not a
correctness concern or evidence of a measured timing regression.

## Review limits

This was a read-only source review of the exact candidate versus the named
baseline, including argument consumers, callback dispatch, ownership,
growability, cancellation/retry, fork, and session reentrancy paths. Existing
callback-shape/fork tests and the recorded 70-test focused validation were
reviewed. No tests, builds, or benchmarks were independently executed by this
reviewer. The review does not establish a performance gain or universal
nonregression. This report was written after the read-only review completed.

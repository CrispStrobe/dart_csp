# Independent placed-line endpoint comparison review

Reviewed `/workspace/scratch/5eda8163e92d/placement_endpoint_only` at observed
head `6165e35e8ad246ff140f4c4f4f432f03ed324a1b`, against recovered placement
`e48430a153bba4b9790314e7a0a61129941029ac`.

Source SHA-256:

- `lib/src/cad/placement.dart`:
  `6a90be7ef0653d0f0a879becf99b58a813f58b69aae9dfef55c471a8707588dd`.
- `test/cad_placement_validation_path_test.dart`:
  `e48c4c8dfdb0be175cab9dd4d8083ef8ae79b9ee1ad2ac6a87bc3e972e168dd9`.

## Conclusion

No correctness blocker found. The only production change relative to the
recovered placement file replaces the line-collapse norm predicate with
coordinate equality and adds its proof comment. It retains the recovered
dual-purpose materialization/validation implementation; the rejected split is
not present. No Dart/timing workload was run by this reviewer.

## Equivalence argument

`_placePoint` calls the private checked transform, which snapshots source
coordinate getters and constructs a concrete `CadPoint3`. It rejects nonfinite
coordinates/error bounds and over-budget precision before returning. Therefore
both endpoints at the predicate are concrete finite points. Changing read order
or short-circuiting comparisons on their stored fields cannot omit a custom
source getter or its exception.

For finite IEEE-754 endpoint coordinates with gradual underflow, the rounded
difference is zero exactly when the two coordinates compare equal; positive
and negative zero compare equal in both forms. Distinct finite representable
values cannot have a true difference smaller than the smallest subnormal.
If subtraction overflows, the difference is infinite and the original scaled
length immediately returns a nonzero infinite scale, so the edge remains
noncollapsed under both predicates.

For finite nonzero differences, `CadPoint3.length` chooses a positive maximum
absolute coordinate as scale. One normalized coordinate has magnitude one,
so its norm cannot round to zero and the final product cannot underflow below
that positive scale. The old norm is therefore zero exactly when all three
differences are zero, which is exactly the new three-coordinate equality.

Point transformation order, numerical checks, the collapse exception and all
later metadata reads are unchanged. Both validation and materialization use
the same predicate. This removes the temporary difference point and redundant
scaled norm work but does not establish a measured allocation or speed claim.

## Regression assessment

The added test exercises both public paths (`validate` and `resolve`) for:

- Equal endpoints and signed zero.
- Smallest-subnormal separation independently on all three axes.
- Opposite-sign subnormals.
- Opposite extreme finite endpoints independently on all three axes, whose
  difference overflows while the endpoints remain finite.

Its permissive backend is deliberate: it isolates placement consumption from
source-solid topology validation. The wide finite precision budget admits the
extreme finite endpoints while retaining the separate collapse test. Rejected
cases assert the original issue and exception message; accepted cases inspect
materialized endpoint coordinates. Existing tests still cover nonfinite
source/direction values, rounding-budget failures, world-space collapse,
custom getter/iterator failure order and snapshot isolation.

The regression has useful coverage of the only subtle equivalence boundaries.
Review supports advancing this small candidate to normal paired measurement,
without implying that source-level simplification guarantees better complete
operation latency.

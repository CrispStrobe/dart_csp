# Independent scalar placement-bounds source review

## Reviewed identity and conclusion

Reviewed `placement_bounds_main`, initially at local commit
`20f3de28a7df05850e56e9b50b85554ea020b19e` and confirmed with identical source
bytes at published head `47f20f6ec454e27c26a50ca08286baa853680d7b`, against main
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51`.

`lib/src/cad/placement.dart` SHA-256:
`c1960fbbb9079184229dfb8fc042554aef1155806f5180f0e928a777e5cc06ee`.

Test SHA-256 identities:

- `test/cad_placement_precision_test.dart`:
  `8f1acac4f3fbe8297c84a4c2aa05ef70879dda2c3f7b5afe1c82d3c403fc24b8`.
- `test/cad_placement_validation_path_test.dart`:
  `33d3366b981d9deb5af2018d88ae89b26f43ff47bb246ae811d468959e4c5923`.

No correctness blocker found. Review supports advancing this candidate to a
direct main-relative measurement. No Dart, test or timing workload was run
by this reviewer; performance is not inferred from source-level allocation
simplification.

The entire `CadBodyInstance` class is byte-identical to main. The only
production file differing from main is `lib/src/cad/placement.dart`; its delta
is the scalar `transformBounds` implementation, its helper and removal of the
unused `Interval` import. Recovered discarded-wrapper validation, the split
experiment and the endpoint-equality experiment are absent from this candidate.

## Numerical equivalence

For each world-coordinate row, the helper preserves the public interval
algebra's exact operation sequence:

1. Select X endpoints using coefficient `>= 0`, multiply, round lower down and
   upper up.
2. Select/multiply Y endpoints, round lower down and upper up, then add to the
   accumulated lower/upper and round each outward.
3. Repeat that scale-then-add sequence for Z.
4. Add the translation to lower and upper, rounding outward once more.

The branch choice matches `IntervalRounding.scale`, including negative zero
(`-0.0 >= 0` is true). Products, additions and outward-rounding calls are neither
regrouped nor skipped, including zero-coefficient products. The old
`Interval.point(offset)` only duplicated an already captured scalar; replacing
it by that scalar leaves both offset additions unchanged.

The helper reads immutable private rotation coefficients. Its repeated sign
comparison has no custom getter or callback; it cannot change the endpoint
choice. All row evaluations retain X/Y/Z order. Existing `nextUp`/`nextDown`
semantics for subnormals, signed zero, infinities and NaN remain unchanged.
The new record carries exactly the two doubles previously stored in an
`Interval`, without changing their precision.

## Public getters, errors and ownership

The initial condition is unchanged: `bounds.isFinite`, then ordered X, Y and Z
comparisons with short-circuiting. Invalid bounds therefore throw the same
`ArgumentError` with the same text at the same stage and consume the same
public getters.

After that check, endpoint capture remains minX/maxX, minY/maxY, minZ/maxZ,
including a fresh `bounds.min`/`bounds.max` access for every coordinate exactly
as the original `Interval` constructor arguments did. Custom getters that
change values or throw on a later read are still consumed in the same order.
All source getters finish before row arithmetic, as before. Translation is
the concrete immutable snapshot created by `CadRigidTransform` construction.

The old `Interval` constructors had no validation or external callbacks, so
omitting them does not remove a source-side failure. Both implementations
finish all three rows, create concrete bound points, then test their finiteness.
Overflow or nonfinite propagated arithmetic therefore still triggers the same
`StateError` and text after all endpoint reads. No early arithmetic-exception
check has been introduced. Outer instance validation/error classification is
unchanged because its complete class matches main.

Bounds and point outputs remain newly constructed concrete objects. No mutable
scratch buffer, cache, source alias or changed ownership contract was added.

## Regression assessment

The precision regression uses public outward interval operations and the
exported column-major matrix as an independent representation of the old
algebra. Matrix row indexing `row + 4 * column` and translation indexing
`row + 12` correctly reconstruct the private row-major rotation. Comparison
through two 32-bit words per double detects signed-zero and one-ULP changes
on native, JS and Wasm-compatible APIs.

Its 24 combinations cover identity, signed axis rotation, an arbitrary
normalized quaternion, a translated arbitrary-axis rotation, ordinary bounds,
signed zero, smallest-subnormal endpoints, large offsets, large finite bounds
and overflow. Finite oracle results must match bit for bit; nonfinite oracle
results must retain `StateError`.

The getter regression checks the complete 25-position success sequence,
injects a throwing getter at every position, and verifies immediate rejection
for a false finite flag and each unordered axis. It confirms no later getters
run after the first invalid check. Existing placement/mesh tests continue to
cover the surrounding precision, collapse, materialization and rollback
contracts; those implementations are untouched.

The source removes three temporary lists and 24 explicit `Interval` objects
per bounds transform, while introducing three two-double result records.
This is a source-structure count, not measured allocations: the compiler may
eliminate or materialize different objects. A complete-operation benchmark is
still required to assess cold and retained latency.

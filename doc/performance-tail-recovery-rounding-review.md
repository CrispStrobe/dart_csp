# Independent shared-view rounding source review

## Identity and conclusion

Reviewed `rounding_views` at clean source commit
`cd894a5dc28e25d79850fac0356ef630b52751c7` against main
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51`.

- `lib/src/continuous.dart` SHA-256:
  `9e3e72b099646b85e46b2fb982ce3100aaa88f826ecc7ed25d2d71211e66bcac`.
- `test/interval_rounding_test.dart` SHA-256:
  `7286fcc008b43b7a5cacfcc516296cb33173030d1e334f8a0503b8680526b612`.

No correctness blocker found in the storage-access substitution. The only
production file differing from main is `lib/src/continuous.dart`; its changes
are confined to `IntervalRounding.nextUp` buffer access and private shared-view
initialization. All earlier CAD placement experiments are absent. This review
runs no Dart, test or timing workload.

## Bit semantics

The new `Float64List(1)` owns exactly eight bytes at offset zero. The
`Uint32List.view` shares those bytes, has two elements and satisfies alignment
requirements. `Endian.host` selects high index 1 / low index 0 on little-endian
hosts, and high index 0 / low index 1 on big-endian hosts. Consequently the
logical integer halves are the same values previously read through ByteData's
default big-endian getters, independently of physical byte order.

The special guards for NaN, positive infinity and either signed zero are
unchanged. The positive low-word increment, mask and high-word carry are
unchanged, as are negative borrow and low-word decrement. Both logical words
are written before the result is read as a double. Negative infinity therefore
still steps to the largest negative finite value; maximum finite values still
step to infinity; subnormal and zero transitions retain their signs. The
`nextDown(x) = -nextUp(-x)` implementation is unchanged.

All word values fit in an unsigned 32-bit range. Production uses no 64-bit
integer view or whole-64-bit integer arithmetic that would be unavailable or
imprecise under dart2js. Typed-list stores use the same 32-bit truncation
semantics as the replaced uint32 setters. Existing carries/borrows already
apply explicit masks where needed.

Both views and the indices are private, isolate-local, lazily initialized
static finals. No underlying buffer escapes. `nextUp` performs only primitive
arithmetic and built-in typed-list operations; it cannot invoke a caller
callback or suspend, so shared-buffer reuse has the same non-reentrancy basis
as the existing ByteData buffer. Creating the view after the initial float
write does not copy or clear the backing bytes.

## Native, JavaScript and Wasm considerations

The installed Dart 3.14 SDK's `lib/typed_data/typed_data.dart` documents shared
view writes and host endianness, and computes `Endian.host` from a typed-list
byte observation. Its JS runtime maps Float64List/Uint32List to native typed
arrays; the two-word scheme remains web-compatible.

The installed Wasm implementation deserves separate performance treatment.
`lib/_internal/wasm/common/typed_data.dart` gives `_F64ByteBuffer` its float
storage but inherits uint32 view creation through `_SlowU32List`. Those word
accesses call `_F64ByteData` byte operations, reconstructing/reinterpreting
the float bits rather than necessarily using a direct machine uint32 load/
store. The implementation still provides the shared-view semantics needed
for correctness. Its byte writes reconstruct bits through integer operations
and `intBitsToDouble`, preserving intermediate bit patterns before the final
result read.

This SDK observation is not a measured Wasm slowdown, but it makes a universal
speedup claim unjustified. Native/JIT/AOT gains, if measured, do not establish
JavaScript or Wasm gains. Big-endian logic is supported by the API mapping and
source reasoning here; no big-endian runtime was tested by this reviewer.

Both old and new implementations already reuse their buffers. This change
should be described as a buffer-access optimization, not elimination of a
per-call allocation. It adds view/index initialization state and may change
first-use cost. Full operation timings and any portable performance claims
must come from their own measurements.

## Regression assessment

The added oracle is independent of the implementation's typed views and
32-bit carry/borrow code: ByteData serializes logical big-endian words, BigInt
combines and increments/decrements the full bit pattern, and ByteData converts
it back. Each 32-bit word passed through `toInt` remains exactly representable
on JS; the arbitrary-precision step itself avoids 64-bit double precision.

The regression compares both directions at explicit special values, all
exponent fields and both signs at low-word carry/borrow and significand
boundaries, plus 4,096 deterministic varied bit patterns. Word comparison
distinguishes positive and negative zero. NaN cases assert propagation, not
an unspecified NaN payload preservation guarantee. The existing tests retain
adjacency, inverse, monotonicity, interval enclosure and solver checks.

The implementation agent reports 41 focused native tests and 18 tests each
under Node/dart2js and Node/dart2wasm passed, plus fatal-info analysis. Those
are the agent's executed gate results; this independent review inspected code
and SDK implementation and did not rerun them.

# Independent guarded rounding source review

## Identity and conclusion

Reviewed `rounding_native_guard` at remote checkpoint
`90b4a3e1e11d3404814e51a34add4be723a3cbe5` against main
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51` and the earlier all-typed candidate
`cd894a5dc28e25d79850fac0356ef630b52751c7`.

- `lib/src/continuous.dart` SHA-256:
  `6ae21fd6dba5fc9e4fd49017fb54ddcd270773a8dc3e14f0fc2c7ca219aa83f3`.
- `test/interval_rounding_test.dart` SHA-256:
  `7286fcc008b43b7a5cacfcc516296cb33173030d1e334f8a0503b8680526b612`.

No correctness or current-target portability blocker found. The only
production file differing from main is `lib/src/continuous.dart`; all CAD
placement production code is back to main. The review inspected source and
official SDK documentation and ran no Dart, test or timing workload. The
worktree's benchmark harness changes belong to the parent's paired-measurement
setup and are outside this source review.

## Exact guarded change

The special-value guards, positive carry, negative borrow and public
`nextDown(x) = -nextUp(-x)` body are unchanged from main. Only the loads before
the shared carry/borrow body and the stores after it are conditional.

When `_nativeWordViews` is true, the code uses the same Float64List/Uint32List
shared-view operations as the all-typed candidate, with the fields renamed
`_nativeBits` and `_nativeWords`. It writes the input double, reads its logical
high and low 32-bit words, applies the unchanged arithmetic, writes both words,
then reads the resulting double.

When `_nativeWordViews` is false, it executes main's exact ByteData sequence:
`setFloat64(0, x)`, `getUint32(0)`, `getUint32(4)`, the shared arithmetic,
`setUint32(0, hi)`, `setUint32(4, lo)`, `getFloat64(0)`. The original private
ByteData buffer is restored. Neither native view nor host-word-index field is
accessed by this path. Static final initialization is lazy, so merely declaring
the unused native fields does not require their allocation during these calls.

This keeps the original web storage access while avoiding two independent
copies of the carry/borrow algorithm. It establishes source-level operation
equivalence on that path, not identical generated machine code or measured web
performance.

## Compile-time guard and portability

The guard is declared as a static const:

```dart
static const bool _nativeWordViews = bool.fromEnvironment('dart.library.io');
```

The SDK documents `dart.library.name` as a compilation-environment availability
key for `dart:name`, independent of whether that library is imported or used.
The official package guide uses `dart.library.io` for an application that can
use dart:io and a separate js_interop condition for web. Consequently this
candidate needs no dart:io import or runtime I/O operation. This is a documented
library-capability test, not an operating-system environment lookup or a
universal detector for native instruction sets. [Dart package guide](https://dart.dev/tools/pub/create-packages#conditionally-importing-and-exporting-library-files).

`bool.fromEnvironment` is guaranteed when invoked in a const context. The
static const declaration provides that context. An absent or unrecognized
value defaults to false, so an unsupported target keeps the ByteData fallback.
The result is fixed by the target compilation environment, including ahead-of-
time compilation; running generated web code under Node does not turn it into
a dart:io target. [Constructor API](https://api.dart.dev/dart-core/bool/bool.fromEnvironment.html).

Environment declarations are evaluated at compile time, and Dart compilers
can eliminate unreachable branches selected by them. This supports the intended
target-specific implementation without proving a particular optimizer's emitted
instruction sequence. [Compilation-environment documentation](https://dart.dev/libraries/core/environment-declarations).

The installed SDK's Wasm implementation gives a uint32 view over float64
storage a `_SlowU32List` representation, whose accesses pass through byte-based
reconstruction. This motivated guarding the all-typed variant. The guarded
candidate keeps main's ByteData operations on the current JS/Wasm web targets;
no Wasm speedup or slowdown was measured by this review. A hypothetical future
target that exposes dart:io can select the native view path and would need its
own performance assessment, while retaining the same typed-data semantics.

## Native bit semantics

`Float64List(1)` owns eight bytes at an aligned zero offset; the Uint32List view
shares those same bytes as two unsigned words. On little-endian platforms the
high word is index 1 and low word index 0; on big-endian platforms their indices
are reversed. Therefore the logical words match main's default-big-endian
ByteData reads regardless of the underlying order. Both words are stored before
the final float is read.

NaN and positive infinity still return before any buffer access, and either
signed zero still maps to the smallest positive subnormal. Negative infinity,
maximum finite values, carry/borrow boundaries and signed subnormal/zero
transitions retain the same arithmetic. Word operations remain 32-bit; no
whole-64-bit integer arithmetic has been introduced into production.

The views are private and isolate-local. The routine has no suspension point or
caller callback, so shared mutable scratch retains main's non-reentrancy basis.
No buffer or view escapes. Big-endian correctness here rests on API semantics
and source reasoning; this reviewer did not execute a big-endian runtime.

Both implementations already reuse their scratch buffer. The candidate changes
the access path and adds view/index first-use state; it does not remove a
per-call allocation. Native cold costs and operation-tail performance must be
judged by the parent's fresh paired measurements.

## Tests and retention boundary

The expanded regression file is byte-identical to the all-typed candidate's
reviewed test file. Its oracle uses ByteData and BigInt whole-bit-pattern
stepping, independent of the production typed views and 32-bit carry/borrow
implementation. It exercises both directions, explicit specials, both signs at
all exponent fields and word boundaries, and 4,096 deterministic varied patterns.
Bit comparisons distinguish signed zero; NaN cases require propagation rather
than unspecified payload preservation.

The implementation agent reports 18 tests passed on each of VM, Node/dart2js
and Node/dart2wasm for this guarded variant. These are reported gate results;
this reviewer did not rerun them. Broader validation and native measurements
remain the parent's responsibility. The source review supports considering
this candidate for retention if those gates and the full measured tradeoffs
support it; it does not itself establish an optimization benefit.

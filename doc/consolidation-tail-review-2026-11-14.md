# Tail and mesh branch integration review — 2026-11-14

## Reviewed boundary and decision

This review starts from remote main `b3e14fbb298c8d4f3714debbeaffaeb6d550db51`
and PR #8 head `6faf18a5b4a776755e5f47e47f520de4f1d89635`. It inspects the
actual Git objects, retained source and saved measurements; the historical PR
description alone is not the integration boundary. The user has now explicitly
requested consolidation into main, superseding the old draft/no-merge scope.

Retain PR #8's guarded native rounding implementation and its expanded tests,
tools and evidence. No correctness blocker was found in that production delta.
Preserve the rejected trial heads in ancestry without reintroducing their
production changes. The separately saved mesh candidate at
`199ce0ce3eb7310d2f2d6b7b2fc2735e8a1ff6f9` also has no source-level correctness
blocker; performance acceptance still requires a fresh measured comparison.

This document is a source/evidence review. Historical Dart gate results cited
below are not presented as newly executed gates. New consolidated-source tests
and the mesh performance decision belong in the consolidation report.

Newly executed lightweight checks on the reviewed PR #8 tree: all five
`tool/test_compare_performance.py` boundary tests and all three
`tool/test_profile_cad_phases.py` collector tests passed. No new Dart workload
or performance run was executed during this source review.

## Exact production boundary

`git diff origin/main origin/perf/cad-tail-2026-11-14 -- lib` changes only
`lib/src/continuous.dart`. CAD placement, mesh tessellation and numerical
geometry solver source at the PR #8 tip match main. The candidate changes the
storage access inside `IntervalRounding.nextUp`, selecting shared
`Float64List`/`Uint32List` views when the compile-time `dart.library.io` capability
is present. It preserves the original `ByteData` access otherwise.

The special-value guards, positive 32-bit carry, negative 32-bit borrow and
`nextDown(x) = -nextUp(-x)` remain unchanged. Both logical words are loaded and
stored using indices selected from `Endian.host`, so the transformation is
equivalent to the prior default-big-endian `ByteData` operations. NaN and
positive infinity return before scratch access; both signed zeros return the
smallest positive subnormal. Negative infinity, finite extremes and word
boundaries follow the same carry/borrow cases as before.

The scratch buffers and indices are private and isolate-local. There are no
suspension points or user callbacks in this operation. Both implementations
already reuse their buffers; this is an access optimization, not removal of a
per-call allocation. The retained tests compare bit words against an independent
`ByteData`/`BigInt` oracle, including all exponent fields, carry/borrow boundaries,
signed zero, subnormal transitions, special values and deterministic varied
patterns. Big-endian execution was not performed by this review.

## Branch classifications and merge treatment

All refs below are the remote snapshot read for this review. Branches remain
available; no branch deletion or history rewrite is needed.

| Branch | Head | Classification and exact file treatment |
|---|---|---|
| `perf/cad-tail-2026-11-14` | `6faf18a` | Retained PR #8 source/evidence. Merge this before recovering the side-branch ancestry. |
| `perf/coupler-followup-2026-11-14` | `199ce0c` | Distinct candidate: `lib/src/cad/reference_kernel.dart` plus `test/cad_reuse_test.dart`. Keep isolated until performance qualification, then merge or explicitly record rejection. |
| `bench/coupler-followup-2026-11-14` | `2a8db09` | Its changed `tool/profile_cad_phases.py` and new `tool/test_profile_cad_phases.py` are already byte-identical in PR #8. An ancestry merge needs no source change. |
| `bench/cad-tail-recovery-2026-11-14` | `d566649` | Its changed `tool/compare_performance.py` and new `tool/test_compare_performance.py` are already byte-identical in PR #8. An ancestry merge needs no source change. |
| `bench/interval-rounding-portable-2026-11-14` | `868a612` | Its added `benchmark/interval_rounding.dart` and `tool/run_dart_node.cjs` are already byte-identical in PR #8. An ancestry merge needs no source change. |
| `perf/rounding-native-guard-2026-11-14` | `90b4a3e` | Its `lib/src/continuous.dart` and `test/interval_rounding_test.dart` are already byte-identical in PR #8. An ancestry merge needs no source change. |
| `perf/rounding-native-views-2026-11-14` | `cfe961b` | Superseded all-target typed-view trial. Retain PR #8's guarded `continuous.dart`; the expanded rounding test is already identical. |
| `perf/cad-validation-tightloop-2026-11-14` | `4522355` | Withdrawn split-validation trial. Preserve history, retain PR #8/main `lib/src/cad/placement.dart`. |
| `perf/cad-endpoint-only-2026-11-14` | `6165e35` | Withdrawn endpoint-only trial. Preserve history, retain PR #8/main placement and PR #8's broader validation-path test. |
| `perf/cad-endpoint-equality-2026-11-14` | `eb2bc52` | Withdrawn split-plus-endpoint trial. Preserve history, retain PR #8/main placement and PR #8's broader validation-path test. |
| `perf/cad-bounds-main-2026-11-14` | `47f20f6` | Withdrawn scalar-bounds trial. Preserve history, retain PR #8/main placement. Precision tests are already identical; PR #8's validation-path test additionally retains endpoint extreme-scale cases. |
| `perf/cad-bounds-scalars-2026-11-14` | `50189cc` | Withdrawn scalar-bounds-on-split trial. Preserve history, retain the same PR #8/main production and broader test decisions. |
| `perf/cad-transaction-allocations-2026-11-14` | `c820fbf` | Already an ancestor of PR #8. Its placement production trial was subsequently withdrawn. Do not reapply it. |
| `perf/geometry-allocations-2026-11-14` | `e14bd4c` | Already an ancestor of PR #8. Its numerical-result allocation trial was subsequently withdrawn. Do not reapply it. |
| `bench/cad-tail-evidence-2026-11-14` | `6338c45` | Already an ancestor of PR #8; its evidence and harness work are retained. |

The classifications were checked by finding each side branch's merge base with
PR #8, enumerating its changed files, and comparing those files with the PR #8
tip. In particular, a direct comparison of a historical branch's entire tree
against current main can show older missing fixes; that is not the same as the
branch's intended three-way delta. The separate solver-comparison branch needs
its own additive-change review and is outside this table.

For withdrawn experiments, record an explicit merge resolution preserving the
retained implementation. An indiscriminate merge of every branch can reinstate
code that was deliberately rejected. The PR #8 placement test is a superset of
the older endpoint/bounds tests: it retains public getter/failure ordering and
signed-zero/extreme-scale line-collapse coverage together.

## Mesh candidate correctness review

The production patch was introduced at
`504c795962b265241bd2284eb08d9c3f7299dd8d`; the later `199ce0c` commit only
corrects the portable fingerprint test representation.

In `_MeshBuilder.quad`, the old code interns corners in the sequence
`a, b, c, a, c, d`, emitting triangles `(a,b,c)` and `(a,c,d)`. The candidate
interns `a, b, c`, emits the first triangle, then interns `d` and emits the
second using the saved indices. The first encounter order of all four corners
and the triangle append order are unchanged. Repeated hash lookups for `a`
and `c` are removed.

All quad callers construct concrete `CadPoint3` instances inside tessellation.
The retained `_ExtrusionData` contains owned, captured profile scalars, and
extrusion/tessellation checks finite valid dimensions and geometry before the
quad calls. The points used for these calls have no custom getters or mutation
callbacks. This matters because skipping a repeated lookup would not preserve
semantics for arbitrary changing public point implementations. The optimization
is confined to the private builder and these owned inputs.

Record-key equality identifies positive and negative zero, as in the old
implementation. The first insertion still determines which original coordinate
object is retained, so signed-zero ownership is preserved. No map layout,
triangle orientation, face ID, vertex acquisition order or validation policy
changes.

The cap change constructs its concrete top-center point once before the fan
loop. The center is already a privately constructed point with fixed scalar
coordinates. Reusing that object preserves its values and the first-insertion
ordering while eliminating repeated identical point construction. Every bottom
triangle, top triangle and final mesh validation call remains in place. The
candidate does not add a validation bypass.

The new regression covers ordered full-mesh fingerprints for a box, two offset
holes and both signed-zero hole centers; zero signs are also checked exactly.
Coordinates are quantized to a documented 1e-9 grid for portable trigonometric
differences, while triangle indices and face IDs are included exactly. A
separate thin-scale case preserves the ordered unresolved-area diagnostics.
The saved focused evidence includes exact native before/after probes and logs
for native, Node JavaScript and Node WebAssembly. Those logs are historical
evidence and should accompany, rather than replace, the consolidated gate.

**Correctness recommendation:** eligible for a fresh measured trial. No source
blocker found. Do not label it a retained speedup until complete-operation
benchmarks establish its effect and preserve any adverse tails.

## What the interrupted trace actually preserves

The saved archive
`benchmark/results/2026-11-14-coupler-jit-operation-profile.json.gz` has SHA-256
`c3960e5cf5ec9b12929a2f85d2c0d90ae36b98bcf8cf97195282317094fc337c`.
Its original status is `running`. It contains five analyzed reports and a sixth
report whose exact process output and trace were saved before analysis.

The sixth report is JIT round 3, candidate, with process exit 0, no timeout,
and recorded elapsed time 6.662 seconds. This review verified its saved trace
and stdout hashes and reconstructed the missing analysis using the retained
collector. The stdout SHA-256 is
`22d926cf1e9f9762c1e776099b378f3ba7e85a0cd90d439e5620b93a035c9fc7`.
The trace SHA-256 is
`59cc664a33fa0d5185b1dafb027bf45d792e44ac0d4b603723ef151f07e3a57a`.
The reconstruction contains 36,021 events, 2,200 operation spans and no unmatched
GC event. All five operations have 400 measured samples after 40 warmups.

| Instrumented coupler statistic | Round 1 before → after | Round 2 before → after | Round 3 before → after |
|---|---:|---:|---:|
| Median, microseconds | 678.5 → 560.5 | 738 → 575.5 | 670 → 629.5 |
| p95, microseconds | 998 → 859 | 1,192 → 926 | 1,044 → 1,053 |
| p99, microseconds | 1,810 → 1,364 | 1,997 → 1,688 | 1,531 → 1,633 |
| Operations overlapping same-thread GC | 59 → 26 | 61 → 35 | 42 → 58 |

This is three of four planned pairs. It remains an incomplete, instrumented
diagnostic, not a completed retention cohort. The original archive should not
be overwritten or relabeled as completed. Reconstruction of a saved successful
process does not recover the two missing reports or supply a final frozen-source
identity check.

None of the six reports has same-thread compiler overlap in measured coupler
operations. Some slow samples overlap background compilation, some overlap GC,
and others overlap neither recorded category. Background compiler function names
include model/component construction, feature-store building, mesh-builder
construction and independent checker work. Temporal overlap cannot establish
which event caused a latency sample, nor measure allocated bytes or blocked
time. These incomplete traces do not resolve the uninstrumented p99 regression.

## Performance interpretation and next measurement

Retain the original native-rounding cohort's reported JIT coupler p99 increase
of 56.2% and its all-four-pair adverse direction. The fresh uninstrumented repeat
at `c73ecb3` has median 623 → 569 microseconds, p95 901.5 → 917 and p99
1,382 → 1,997, with two faster and two slower p99 pairs. It confirms typical-time
gains while leaving the tail cost unresolved. The incomplete instrumented
cohort above cannot overturn either normal cohort.

The bounded next experiment is the mesh candidate against PR #8's retained
source, using identical complete-operation harnesses and alternating fresh
JIT/AOT processes. Freeze source/package mappings and harness bytes, run timing
sequentially, retain per-operation work and raw samples, and report cold and
retained-operation median/p95/p99 together. This isolates mesh work without
mixing in the previously rejected placement or numerical-allocation trials.
Do not use VM GC flags as a library fix or treat a faster aggregate as proof of
uniformly better tails.

The broader sparse linear-backend investigation is a separate investment. Its
large-system convergence gains should not be mixed into a tiny CAD mesh timing
claim, and it requires its own numerical acceptance, failure and portability
review.

# Independent recovery and placement source review

## Reviewed source and conclusion

Reviewed candidate `4522355c01f36b122726473c0934d7678f2af937` against recovered
checkpoint `e48430a153bba4b9790314e7a0a61129941029ac` and baseline main
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51`.

`lib/src/cad/placement.dart` SHA-256:
`1da71474e82b16dd2665345d32c9c79ff9af58293af7f166a010fa417dfdf90f`.

No correctness blocker was found in the split validation implementation.
This is a read-only source review; no timing or Dart workload was run by the
reviewer. Retention still depends on the parent's fresh measurements and gates.

- `_place` and `_placePoint`, from the materialization method through the end of
  the file, are byte-identical to baseline main. Resolved world topology still
  creates fresh concrete wrappers and immutable loop/edge-list snapshots.
- The rigid-transform implementation, including `_checkedPoint`, TwoSum,
  outward-rounding order, coefficient/error budgets, direction checks and
  transformed bounds, is byte-identical to the recovered checkpoint. No
  mathematical acceptance condition or precision budget was relaxed.
- Backend validation still runs before bounds/topology validation on every
  call. Its rejection still returns early, and its thrown exceptions remain
  outside the existing placement exception handler. Bounds precede topology
  enumeration exactly as before.
- The new traversal consumes public getters in the same order as the original
  constructor arguments: vertex ID/semantic/point; curve and point/direction
  values before edge metadata; surface and point/direction values before face
  metadata and loop iteration. The apparently unused metadata expression
  statements are intentional and must not be removed: custom getters may
  throw or have side effects. The same applies to complete custom loop/edge
  iteration.
- Both point transformations and the existing line-collapse check remain in
  validation. Unsupported curves, surfaces and topology retain their errors;
  the outer handler still distinguishes `UnsupportedError` from other errors
  and preserves the feature ID.
- Omitted constructors (`CadVertex`, `CadLineCurve`, `CadCircleCurve`, `CadEdge`,
  `CadPlaneSurface`, `CadCylinderSurface`, `CadOrientedEdge`) only store their
  already consumed arguments. Omitted `CadBoundaryLoop`/`CadFace` constructors
  copy newly created private lists, so they do not contain additional custom
  getters, source iterators or validation that must be replayed.
- The recovered `cad_placement_validation_path_test.dart` specifically covers
  all these branch types, the expected getter/iterator sequence, failure at
  every sequence position, repeated backend calls, snapshot isolation, nonfinite
  directions, rounding errors and collapsed world edges. The split traversal
  should remain governed by these tests to prevent future drift from `_place`.

The intended difference from the recovered implementation is structural:
validation no longer enters a materializing method with a boolean flag and
conditional output construction at every type/loop. The expected allocation
benefit is not a measured byte count and does not itself establish faster
complete operations.

## Remaining bounded source opportunities

The line-collapse predicate currently computes `(end - start).length == 0`.
Both endpoints are finite concrete points returned by the private checked
transform. Equality of their three coordinate pairs is equivalent to zero
displacement, including signed zero, and avoids a temporary difference point
and the scaled norm's divisions/square root. This is a candidate for a separate
small experiment, not part of the reviewed source above.

`transformBounds` still allocates three lists and multiple interval wrappers per
instance; scalarizing it would require preserving custom bounds getter order
and all outward-rounding operations. Checked-point record allocation is only a
source-level suspicion: the saved traces do not show whether AOT removes those
records. `nextUp` already reuses a ByteData buffer and should not be described
as allocating per call.

## Independent reconstruction of saved operation traces

Read `benchmark/results/2026-11-14-tail-operation-profile.json.gz` and rebuilt
raw per-thread B/E/X spans and interval unions independently of the project
collector/auditor. Results are in `recovery_operation_audit.json`; script is
`recover_profile_audit.py` in this scratch workspace.

- 526,070 checks; zero findings.
- 386,466 events; 182,379 completed spans.
- 27,720 operation spans; 25,200 measured operations.
- Six unmatched compiler begins; no unmatched GC or operation span.
- Every reconstructed recorded operation identity, sample alignment and GC/
  compiler overlap agreed. Measured Stopwatch intervals fit inside their
  surrounding timeline spans.

For the AOT assembly cold operation, three traced pairs have no-GC median
times of 354.5→331, 325→318 and 377→324 microseconds. All traced full medians
also improve. Cold operations coinciding with same-thread GC change from
128/300 to 27/300 in every pair; pose edits change from 0/300 to 4/300.

These figures do not resolve the normal cohort's assembly regression. Tracing
changes the process, and the before/after no-GC subsets contain different
operations (172 versus 273 samples). Conditional no-GC medians are therefore
not a matched experiment isolating computation cost. Temporal GC overlap is
not allocated bytes, CPU attribution, causal delay or measured stop-the-world
pause duration. Preserve the normal p50 +20.6%, p95 +72.4% and p99 +630.6%
assembly-cold results until a fresh normal comparison assesses the new source.

## Comparison-runner identity safeguard

The recovered `tool/compare_performance.py` records HEAD, library-tree and lock
hashes but does not inspect package configuration. A copied package config can
point both checkouts' `package:dart_csp` imports to the same library while the
reported commits differ. It also records a dirty-lib diff without rejecting
it and does not detect untracked library files.

The minimum safeguard for a new cohort is:

1. Require exactly one `dart_csp` entry in each explicit package configuration.
2. Resolve both `rootUri` and `packageUri` against the configuration/root URIs,
   accept file URIs only, and require the effective library directory to resolve
   exactly to that checkout's `lib`. Checking `rootUri` alone misses a diverted
   `packageUri`. Follow symlinks when comparing paths.
3. Require clean committed library files, including no untracked files, and
   record package-config, source-file and dependency-lock hashes.
4. Pass the exact package configuration to each JIT/compile invocation. Use
   absolute SDK and harness paths, record argv and actual binary hashes, and
   keep baseline/candidate binaries distinct.
5. Verify package/source/harness hashes again when the cohort completes so
   concurrent edits cannot silently change later pairs.

The existing profiling collector already guards `rootUri`, rejects dirty/
untracked libraries and explicitly passes `--packages`, but it should also
validate effective `packageUri` for a new cohort. Equal lock hashes do not
establish equal installed package bytes; the resolved dependency identity
should be retained separately where feasible.

## Recovered remote boundary

PR #8 is the draft continuation on `perf/cad-tail-2026-11-14`, recovered at
`e48430a`. The prior numerical publication experiment was reverted at
`e510f1f`; only placement remained changed in production. Both isolated and
final normal benchmarks, operation traces, source candidates and focused
regressions survived remotely. The interrupted final full-validation manifest,
final synthesis and handover were not present in that checkpoint.

At the recovery snapshot, run 43575763442 had passed the six Windows/macOS
stable/beta/dev jobs; ten Linux/browser/portable/etc jobs remained queued, and
full-browser/performance jobs were skipped. This is historical recovery status,
not a claim about the current head's CI.

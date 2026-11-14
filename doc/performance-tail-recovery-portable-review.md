# Independent guarded-rounding portable primitive assessment

## Conclusion and scope

The portable primitive cohort passes **3,615 independent audit checks** with
zero findings. All 12 Node processes complete successfully, and every retained
checksum matches an independent whole-64-bit reconstruction. The saved
executable-artifact hashes are identical before/after for JavaScript and for
the Wasm module, loader and support JavaScript. This supports preservation of
the web implementation for this compiled harness.

It does **not** establish a web speedup, complete CAD latency or browser
performance. JS timers resolve these small batches only as 0 or 1,000
microseconds, making their zero process medians unsuitable for a throughput
comparison. Wasm timings have useful numerical resolution but move despite
the same recorded executable bytes; those deltas are contextual observations,
not evidence of a changed generated implementation.

The source comparison is main
`b3e14fbb298c8d4f3714debbeaffaeb6d550db51` versus guarded source
`90b4a3e1e11d3404814e51a34add4be723a3cbe5`. Only `continuous.dart` differs in
production. Its reviewed SHA-256 remains
`6ae21fd6dba5fc9e4fd49017fb54ddcd270773a8dc3e14f0fc2c7ca219aa83f3`.

## Method and exact output checks

Each runtime/revision has three fresh sequential Node processes with alternating
revision order. JS and Wasm use Dart `-O2` compilation outside measurement.
Every process measures nextUp and nextDown separately, with **50 samples after
20 warmups**, and **8,192 calls per batch** over a fixed 64-entry input corpus.
The timer includes input reads, primitive calls and preallocated output writes.
Explicit-endian ByteData checks every output after timing; no verification work
is included in the timer.

The audit independently regenerates the complete input corpus and both
expected output vectors using Python arbitrary-precision whole-64-bit integer
adjacency and IEEE special-value rules. It does not reuse the Dart carry/borrow
implementation or project collector code. Signed zero is compared by words;
NaNs are required to be NaN but normalize to one checksum token, without
claiming payload/sign preservation. The corpus includes finite sign/exponent
and word boundaries, zeros, infinities and NaNs; its 64 entries are not all
distinct values and do not represent exhaustive bit coverage.

Both directions' expected 8,192-operation checksum is **3,892,307,200**.
All **1,200 retained batch checksums** match. The two equal checksum totals do
not by themselves distinguish nextUp from nextDown; the reviewed harness also
compares **each individual output's high/low words** against its expected
vector and throws on a mismatch. Successful completion therefore supports
those checks. Actual output vectors are not serialized in the raw report, so
this audit independently reconstructs reference vectors and checksums rather
than replaying each observed output. The retained measured batches represent
9,830,400 primitive calls, in addition to warmup calls.

[The reference-vector artifact](../benchmark/results/2026-11-14-recovery-rounding-portable-reference-vectors.json) preserves the independent expected
input/output words and checksums. Its name intentionally identifies reference
vectors, not captured runtime outputs.

## Source, runtime and subprocess provenance

The audit checks all **120 subprocesses and 240 exact stdout/stderr hashes**,
including zero exit status, absence of timeout, sequential timestamps, the
complete pre/post source-identity sequence, four compile commands and all
12 Node run references. Original stdout parses exactly to the retained result.
Every compile uses the appropriate explicit package map and every Node command
uses the corresponding compile output plus the exact sampling arguments.
All stderr streams are empty.

It also checks **88 frozen/current production files**, identical harness and
launcher bytes, package/lock digests and independent URI resolution to distinct
source roots. The current Dart and Node executable hashes match their recorded
hashes. Recorded versions are Dart 3.14.0 stable and Node v24.22.1 on Linux x64.
No runtime was executed by this reviewer.

The source guard is the reviewed static const
`bool.fromEnvironment('dart.library.io')`. Current web targets take the original
ByteData storage sequence; native view loads/stores share the unchanged
carry/borrow body behind the other branch. No recorded compiler command
overrides the capability key. The raw result does not include a separate runtime
flag probe. Equal generated executable hashes corroborate the expected web
fallback for this exact harness and compiler configuration.

## Generated artifact identities

| Target / artifact | Role | Before/after hash relationship |
|---|---|---|
| JS `rounding.js` | Executable | Identical |
| JS `rounding.js.deps` | Dependency metadata | Different |
| JS `rounding.js.map` | Source map | Different |
| Wasm `rounding.wasm` | Executable module | Identical |
| Wasm `rounding.mjs` | Executable loader | Identical |
| Wasm `rounding.support.js` | Executable support | Identical |
| Wasm `rounding.wasm.map` | Source map | Different |

Identical executable SHA-256 values:

- JS: `3c5f850c5da426db8873a39122633cf517ad7106bb1474393c97a28d14794215`.
- Wasm module: `5c22937f4734217a18d70d98a0edc4b57f883204f5651c195aaff8b12a28f87b`.
- Wasm loader: `5129147c546b543dd7be001c79a20a98ba0c0aa10ba1f776a545d0234e283a78`.
- Wasm support: `282d98a8f9fc4189901b60e5cab163a01136d877656dd9aa4a594d3d0df5d2ae`.

The collector created these artifacts in a temporary directory and deleted that
directory on completion. The audit therefore cannot newly hash those files.
The byte-identity conclusion is based on their **recorded manifests**, linked
to the compile/run paths, and review of the exact hashed collector, which
rehashes every generated file before each execution and rejects a change.
The different metadata file contents are not retained, so this review does not
claim which source paths or mappings changed inside them.

## Timing observations and all rows

Each value is microseconds per 8,192-operation batch. Summaries use medians of
three process percentiles; no samples are pooled or removed. Per-process p50
uses **nearest rank, the lower middle of 50 samples**. p95 also uses nearest
rank. Derived p99 is each process maximum at this count and appears as **Max**
below. Pair counts are **faster/slower/equal**; an em dash denotes an undefined
relative change from zero.

| Operation | p50 before→after | p50 Δ; pairs | p95 before→after | p95 Δ; pairs | Max before→after | Max Δ; pairs |
|---|---:|---:|---:|---:|---:|---:|
| JS next_up | 0→0 | —; 0/0/3 | 1000→1000 | +0.0%; 1/0/2 | 1000→1000 | +0.0%; 0/0/3 |
| JS next_down | 0→0 | —; 0/0/3 | 1000→1000 | +0.0%; 1/0/2 | 1000→1000 | +0.0%; 0/0/3 |
| WASM next_up | 165→163 | −1.2%; 2/1/0 | 227→224 | −1.3%; 1/2/0 | 304→434 | +42.8%; 1/2/0 |
| WASM next_down | 138→163 | +18.1%; 1/2/0 | 196→194 | −1.0%; 1/2/0 | 202→285 | +41.1%; 1/2/0 |

Both JS rows have p50 0→0 in all three pairs. Across their 600 combined samples,
551 are zero and 49 are 1,000 microseconds. These results support correctness
and successful execution, not a resolved throughput estimate. The candidate's
second process happens to report p95 zero in both directions; interpreting that
quantized transition as a 100% speedup would be invalid.

Wasm nextUp median is 165→163 microseconds (−1.2%, two faster/one slower pair).
Its p95 aggregate decreases 1.3%, but two pairs are slower and the median paired
change is +12.0%. NextDown median is 138→163 microseconds (**+18.1%**, two
slower/one faster pair); its p95 aggregate decreases 1.0% despite two slower
pairs and a +5.9% median paired change. The apparent p95 improvement is influenced
by a baseline process with p95 1,140 microseconds. Process maxima also worsen
in aggregate for both Wasm directions. Every one of these adverse observations
is preserved, while the identical executable manifests prevent attributing
these timing differences to a different generated rounding implementation in
this harness.

## Retention context and reproducibility

This cohort supports the guarded source's portable correctness and preservation
of its web compilation path for the measured primitive program. It does not
remove the unresolved native JIT coupler p99 cost, prove no web regressions for
other applications, or characterize browser/CAD end-to-end latency. The native
retention decision should continue to state its measured median/p95 gains and
its adverse tails explicitly, alongside the broader correctness gates.

Reproduce this review without running Dart or Node using
[`tool/audit_recovery_portable.py`](../tool/audit_recovery_portable.py). The
canonical outputs are the
[audit](../benchmark/results/2026-11-14-recovery-rounding-portable-audit.json),
[independent summary](../benchmark/results/2026-11-14-recovery-rounding-portable-independent-summary.json)
and [reference vectors](../benchmark/results/2026-11-14-recovery-rounding-portable-reference-vectors.json).
The audit preserves all source/runtime/collector identities, seven artifact
comparisons, checksum reconstructions and full paired timing directions.

Raw report SHA-256:
`7cb4b5663c7b32a8f16f5200287c5582bc6468c43ad371a6d7475ff723c945a8`.

Reviewed collector SHA-256:
`8c5d2a10ed540a73031fe611ecca7023baaee9705a66f22e2e5cfd0a308061c1`.

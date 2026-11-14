# Recovered CAD performance pass — 2026-11-14

## Outcome and remaining gates

Retain the guarded native interval-rounding access change on
[`perf/cad-tail-2026-11-14`](https://github.com/CrispStrobe/dart_csp/tree/perf/cad-tail-2026-11-14),
in [draft PR #8](https://github.com/CrispStrobe/dart_csp/pull/8). It is the sole
production difference from the main baseline. Four fresh paired processes per
runtime support repeated native median/p95 gains: all four retained AOT linkage
operations improve both statistics in every pair. Their aggregate median
reductions are 11.4–39.4%, and p95 reductions are 7.3–34.5%. JIT retained linkage
medians improve 20.9–50.7%, also in every pair.

**Retention is qualified by an unresolved extreme-tail cost.** JIT coupler-length
edit p99 rises from 1,735.5 to 2,711 µs (+56.2%), worse in all four pairs. That
operation's median and p95 improve, but this is not a uniform latency improvement.
Adverse numerical controls and small AOT plate costs remain in the evidence.
No GC, compilation or allocation cause is established for the p99 change.

Formatting, static analysis, 1,802 native tests, 481 Node JS tests, 481 Node Wasm
tests and five benchmark-runner boundary tests pass on the frozen integrated
source. Chromium fails during startup because the host denies `socket()`;
zero browser assertions execute. The original validation manifest remains
`failed` for that attempt. The observed GitHub workflows have 16 active jobs
queued and two event-gated jobs skipped. Browser and platform-matrix coverage
remain open gates; the PR is draft and main is unchanged.

All experiments, including rejected changes and adverse measurements, were
saved incrementally to remote branches. This report supersedes the pending
decisions in the historical sections of `PERFORMANCE_TAIL_2026_11_14.md`.

## Source boundary and implementation

| Role | Immutable identity |
|---|---|
| Baseline main | `b3e14fbb298c8d4f3714debbeaffaeb6d550db51` |
| Recovered interrupted checkpoint | `e48430a153bba4b9790314e7a0a61129941029ac` |
| Measured native candidate | `90b4a3e1e11d3404814e51a34add4be723a3cbe5` |
| Integrated source used for complete local validation | `e8ab94bd37f7743a8c2c8352ad5b4b850769728a` |
| Baseline library tree | `6111175debbc7a3ae99631e274f24f16b28d2f25` |
| Candidate / validated library tree | `a9fc347644d9d0cfdc52c460bdc222ae2678958e` |
| Validated test tree | `d616d742e1a5fc95cf80cdc5e69c09c3b8dad9e0` |

`lib/src/continuous.dart` is the only changed production file. Native
`IntervalRounding.nextUp` reads and writes the existing floating-point value
through shared `Float64List`/`Uint32List` views, selecting high and low words
with `Endian.host`. The compile-time `dart.library.io` capability guard keeps
the original ByteData path on the measured JS and Wasm targets. The special
value guards, unsigned 32-bit carry/borrow and `nextDown` definition are
unchanged. No public API changes are introduced.

Both versions reuse scratch storage. The change targets word-access overhead;
it does not demonstrate removal of per-call allocations or reduced allocated
bytes. The CAD placement and numerical geometry implementations exactly match
main. The retained source SHA-256 is
`6ae21fd6dba5fc9e4fd49017fb54ddcd270773a8dc3e14f0fc2c7ca219aa83f3`.
See [the guarded source review](performance-tail-recovery-rounding-guard-review.md).

Regression coverage uses an independent ByteData/BigInt bit oracle across
special values, both signs, all 2,048 exponent fields and 4,096 varied bit
patterns. It checks subnormals, normal transitions, word carry/borrow and
signed-zero behavior. Tests added during rejected placement and geometry
experiments remain to protect precision, getter/throw order, immutable
snapshots and callback isolation.

## Native CAD measurements

The final target cohort has **48 process reports, 20 rows, 64,000 raw samples
and 64,000 aligned work records**. Each of three fixtures runs in both JIT and
AOT, before and after, in four fresh process pairs. Every case has **400 measured
samples after 40 warmups**. Revision order alternates; workloads run sequentially;
AOT compilation and independent physical checks are outside the timed operation.
All 32,000 paired work-record comparisons match. No samples or processes are
discarded.

The runtime is Dart 3.14.0 stable on shared Linux x64 (AMD EPYC 9V45, inherited
nine-CPU affinity). There is no dedicated-core or isolated-host claim. Each
reported value below is the **median of per-process percentiles**, not a
percentile of pooled samples. Percentage changes compare those two aggregate
values. Pair counts expose direction separately; they are not confidence
intervals. Times are microseconds and lower values are faster. At 400 samples,
p99 is still supported by a small number of upper-tail observations.

### JIT

| Operation | Median before → after (Δ) | p95 before → after (Δ) | p99 before → after (Δ) | Faster pairs: median / p95 / p99 |
|---|---:|---:|---:|---:|
| Assembly cold build | 746 → 570.5 (-23.5%) | 1,716.5 → 1,379.5 (-19.6%) | 2,606.5 → 2,688.5 (+3.1%) | 3/4 / 3/4 / 2/4 |
| Assembly pose edit | 152 → 108 (-28.9%) | 449.5 → 363 (-19.2%) | 957 → 748.5 (-21.8%) | 4/4 / 4/4 / 4/4 |
| Linkage cold build | 1,991 → 1,806 (-9.3%) | 2,963 → 2,933.5 (-1.0%) | 4,419.5 → 4,798 (+8.6%) | 4/4 / 2/4 / 1/4 |
| Linkage angle edit | 306.5 → 195 (-36.4%) | 557.5 → 432.5 (-22.4%) | 888.5 → 940 (+5.8%) | 4/4 / 3/4 / 2/4 |
| Linkage coupler-length edit | 717 → 567 (-20.9%) | 1,148 → 993 (-13.5%) | 1,735.5 → 2,711 (+56.2%) | 4/4 / 4/4 / 0/4 |
| Linkage placement-only edit | 173.5 → 85.5 (-50.7%) | 306 → 175.5 (-42.6%) | 539.5 → 352 (-34.8%) | 4/4 / 4/4 / 3/4 |
| Linkage rejected-angle edit | 270 → 166 (-38.5%) | 478.5 → 369.5 (-22.8%) | 1,117 → 746.5 (-33.2%) | 4/4 / 3/4 / 3/4 |
| Plate cold build | 778.5 → 723 (-7.1%) | 1,538.5 → 1,462 (-5.0%) | 2,456 → 2,101 (-14.5%) | 3/4 / 2/4 / 2/4 |
| Plate profile edit | 723 → 711 (-1.7%) | 1,328 → 1,377.5 (+3.7%) | 2,030 → 2,168.5 (+6.8%) | 3/4 / 2/4 / 2/4 |
| Plate thickness edit | 573 → 561.5 (-2.0%) | 1,072 → 999 (-6.8%) | 1,747 → 1,693.5 (-3.1%) | 3/4 / 3/4 / 2/4 |

### AOT

| Operation | Median before → after (Δ) | p95 before → after (Δ) | p99 before → after (Δ) | Faster pairs: median / p95 / p99 |
|---|---:|---:|---:|---:|
| Assembly cold build | 356 → 343 (-3.7%) | 600.5 → 568.5 (-5.3%) | 914.5 → 737 (-19.4%) | 2/4 / 3/4 / 3/4 |
| Assembly pose edit | 49 → 37 (-24.5%) | 99.5 → 95 (-4.5%) | 196.5 → 173 (-12.0%) | 4/4 / 2/4 / 3/4 |
| Linkage cold build | 1,842 → 1,730.5 (-6.1%) | 2,606 → 2,403 (-7.8%) | 4,211.5 → 4,213.5 (+0.0%) | 3/4 / 3/4 / 3/4 |
| Linkage angle edit | 192 → 141.5 (-26.3%) | 341 → 268.5 (-21.3%) | 618 → 490.5 (-20.6%) | 4/4 / 4/4 / 2/4 |
| Linkage coupler-length edit | 599 → 530.5 (-11.4%) | 903 → 837 (-7.3%) | 1,880.5 → 1,169.5 (-37.8%) | 4/4 / 4/4 / 3/4 |
| Linkage placement-only edit | 113 → 68.5 (-39.4%) | 179.5 → 117.5 (-34.5%) | 325 → 223 (-31.4%) | 4/4 / 4/4 / 4/4 |
| Linkage rejected-angle edit | 168 → 124 (-26.2%) | 262.5 → 205.5 (-21.7%) | 646 → 407 (-37.0%) | 4/4 / 4/4 / 2/4 |
| Plate cold build | 689.5 → 706.5 (+2.5%) | 1,008 → 1,036.5 (+2.8%) | 1,733.5 → 1,286.5 (-25.8%) | 2/4 / 3/4 / 3/4 |
| Plate profile edit | 710.5 → 719.5 (+1.3%) | 1,011 → 1,010 (-0.1%) | 1,294.5 → 1,210 (-6.5%) | 1/4 / 3/4 / 3/4 |
| Plate thickness edit | 624.5 → 637 (+2.0%) | 927.5 → 946.5 (+2.0%) | 1,403.5 → 1,295 (-7.7%) | 1/4 / 2/4 / 3/4 |

The JIT coupler p99 increase is +8.2%, +39.9%, +58.9% and +58.9% in the four
individual pairs. Slow observations appear throughout the measured sequence,
so they cannot be dismissed as only initial warmup. JIT linkage cold p99 also
increases in aggregate, with three adverse pairs. AOT angle/rejected-angle p99
aggregates improve while their pair directions split two/two. Cold assembly
aggregates improve, but AOT median pairs split two/two. These distinctions are
part of the retention decision.

The [native independent data reconstruction](../benchmark/results/2026-11-14-recovery-rounding-cad-independent.json),
[project audit](../benchmark/results/2026-11-14-recovery-rounding-cad-audit.json),
[process audit](../benchmark/results/2026-11-14-recovery-rounding-cad-process-audit.json)
and [source identity audit](../benchmark/results/2026-11-14-recovery-rounding-identity-audit.json)
record the exact counts and checks. Their scope is distinct: successful
physical oracles and equal work support comparable work, while the process
audit checks commands, statuses, exact output hashes and compile/run linkage.
The native collector did not hash each SDK/AOT executable or installed
dependency package's bytes. The separate environment record retains the
verified SDK archive hash and exact development dependency lock.

## Numerical and graph controls

The separate control cohort preserves **48 reports, 32 rows and 4,800 samples**:
three fresh alternating pairs per runtime, 25 samples and five warmups. Its
72 final physical-work snapshots pass, and all 36 paired snapshots match.
These are final snapshots, not work arrays aligned to every sample. With 25
observations, a derived nearest-rank p99 is the process maximum and must not be
treated as a stable p99 estimate.

All six JIT numerical median aggregates worsen: nonlinear cold/warm +9.6%/+15.6%,
coupled cold/warm +5.9%/+16.8%, and workspace cold/warm +24.7%/+51.2%.
Nonlinear warm, graph 1,000-feature cold (+10.3%) and graph 10,000-feature
sparse edit (+28.6%) have worse medians in all three pairs. Small graph no-op
and unused-parameter cases also have repeated increases, including 7→10 and
10→12 µs. These observations do not establish absence of collateral costs.

AOT coupled and workspace cold/warm medians improve 4.2–7.3%, with every pair
faster; their p95s improve in every pair too. These measured paths do not
execute the changed primitive. Neither their gains nor their losses are
attributed directly to the rounding implementation, and control movement is
not subtracted from target measurements. Short JIT warmup and shared-host
conditions remain limitations. All 32 rows, absolute times and paired
directions appear in the [complete controls review](performance-tail-recovery-controls-review.md).

## Portable implementation guard

A separate Node primitive cohort has **12 reports, 1,200 measured batches and
1,200 matching checksums**. Each backend uses three fresh pairs, 50 samples
after 20 warmups, and 8,192 nextUp/nextDown calls per batch. The independent
64-bit reconstruction agrees with all retained checksums; the harness also
checks every output word against expected vectors after timing. Checksums do
not substitute for those individual checks, and the saved reference vectors
are expected values, not serialized runtime output vectors.

Recorded before/after executable hashes are identical for JS, the Wasm module,
its loader and support JS. Source maps/dependency metadata differ. Generated
artifacts were temporary and are no longer available for a new independent
rehash; byte identity is supported by the recorded manifests and reviewed
collector, which rehashes artifacts before each execution.

Times below are microseconds per batch. JS samples are only zero or 1,000 µs;
every JS process median is zero, so no useful median speed ratio is available.
Wasm nextDown median rises 18.1% despite identical recorded executable bytes.
At 50 samples, the shown maximum is not a robust p99 estimate.

| Node backend / primitive | Median before → after (Δ) | p95 before → after (Δ) | Process maximum before → after (Δ) |
|---|---:|---:|---:|
| JS next_up | 0 → 0 (undefined) | 1,000 → 1,000 (+0.0%) | 1,000 → 1,000 (+0.0%) |
| JS next_down | 0 → 0 (undefined) | 1,000 → 1,000 (+0.0%) | 1,000 → 1,000 (+0.0%) |
| WASM next_up | 165 → 163 (-1.2%) | 227 → 224 (-1.3%) | 304 → 434 (+42.8%) |
| WASM next_down | 138 → 163 (+18.1%) | 196 → 194 (-1.0%) | 202 → 285 (+41.1%) |

This cohort supports the guarded web compilation path for this exact primitive
harness/compiler configuration. It establishes neither a web speedup nor
browser or full CAD performance. See [the full portable review](performance-tail-recovery-portable-review.md)
for artifact hashes, independent oracle coverage, pair directions and limits.

## Rejected experiments remain recoverable

| Experiment | Source checkpoint | Decision and material evidence |
|---|---|---|
| Recovered conditional placement materialization | `e48430a` | Withdrawn. Original final AOT assembly cold median/p95 rose 20.6%/72.4%, worse in all three pairs; operation traces did not resolve normal-timing costs. |
| Numerical result views / component cache | `e14bd4c` experiment branch | Already rejected before recovery. Cold/assembly costs and inconsistent solver effects; production geometry remains baseline. |
| Split placement validation/materialization | `4522355` | Rejected. JIT gains came with AOT retained median and assembly cold costs. |
| Direct endpoint equality | `6165e35` | Rejected. AOT edit gains came with JIT linkage and AOT assembly cold costs; original norm-based predicate remains. |
| Scalar transformed bounds | `47f20f6` | Rejected. AOT linkage cold median/p95 +4.9%/+22.2%; angle edit +6.3%/+40.4%, all four pairs worse. |
| Unconditional native/web typed views | `cfe961b` | Experimental source retained, not the selected implementation. The measured source guards web backends because cross-element views can have different runtime costs. |

The `2026-11-14-tail-*` and `2026-11-14-recovery-{split,endpoint,bounds}-*`
artifacts preserve the original cohorts, profiles, summaries and decisions.
Unmeasured combination branches are archival experiments, not additional
validated candidates. The separate solver-comparison PR #7 is outside this pass.

## Validation and CI

| Gate on integrated source `e8ab94b` | Result |
|---|---|
| Dart formatting | 217 files, zero changes |
| Static analysis with fatal infos | Passed |
| Full native suite | 1,802 tests passed |
| Node dart2js portable corpus | 481 tests passed across 47 files |
| Node dart2wasm portable corpus | 481 tests passed across the same 47 files |
| Benchmark-runner boundary checks | Five passed |
| Chromium smoke corpus | Startup blocked; zero assertions executed |
| Independent validation-log/source review | 54 consistency checks passed, zero findings |
| Remote browser and OS/SDK matrix | Queued at the saved CI observation |

All four changed/new regression files are included in the 47-file portable
corpus and 14-file browser smoke corpus. The browser list matches CI exactly.
Chrome's first fatal error is `socket() failed: Operation not permitted` in
`process_singleton_posix.cc`; ptrace/zygote errors follow. No browser assertion
result is inferred from Node success. Local native results cover this Linux
host, not macOS/Windows.

The library and test trees remained frozen throughout the run. Later commits
add reports/audit tooling/evidence only. The
[validation manifest](../benchmark/results/2026-11-14-recovery-validation.json),
[complete logs and runner](../benchmark/results/2026-11-14-recovery-validation-logs.tar.gz),
[independent review](performance-tail-recovery-validation.md) and
[time-stamped CI snapshot](../benchmark/results/2026-11-14-recovery-ci.json)
preserve the boundary and original failures. The snapshot predates the final
documentation commit; consult the live PR for subsequent CI state.

## Reproduction and evidence navigation

Use separate checkouts of baseline `b3e14fb` and candidate `90b4a3e` with clean
production libraries. Copy the same final benchmark harnesses and their fixture
dependencies from this branch into both checkouts; the runner enforces byte
identity. The measured CAD harnesses are `cad`, `cad_instances` and
`cad_linkage`; their example dependencies are `parametric_bracket.dart`,
`parametric_assembly.dart`, `parametric_linkage.dart` and `nonlinear_linkage.dart`.
Controls use `geometry_nonlinear`, `geometry_coupled`, `cad_workspace` and
`cad_graph`. The portable primitive uses `benchmark/interval_rounding.dart`
and `tool/run_dart_node.cjs`.

Install Dart 3.14.0 stable and Node v24.22.1, and restore the exact lock embedded
in [the environment record](../benchmark/results/2026-11-14-recovery-environment.json).
Resolve development packages for each root so its explicit package map points
to that checkout's own `lib/`. Keep `TMPDIR` and `PUB_CACHE` at writable paths.
The runner checks effective root plus package URI, library/config/lock/harness
hashes before and after runs, and checkpoints subprocess failures/timeouts.

```sh
python3 tool/compare_performance.py --before ../baseline --after ../candidate \
  --dart /path/to/dart --benchmarks cad_instances cad_linkage cad \
  --rounds 4 --samples 400 --warmups 40 --output native-cad.json

python3 tool/compare_performance.py --before ../baseline --after ../candidate \
  --dart /path/to/dart \
  --benchmarks geometry_nonlinear geometry_coupled cad_workspace cad_graph \
  --rounds 3 --samples 25 --warmups 5 --cad-graph-sizes 1000,10000 \
  --output controls.json

python3 tool/compare_rounding_portable.py --before ../baseline --after ../candidate \
  --dart /path/to/dart --node /path/to/node --rounds 3 \
  --samples 50 --warmups 20 --batch 8192 --output portable.json
```

Run timing cohorts sequentially and keep instrumentation separate. The exact
validation commands and ordered file lists are in the validation manifest;
its archive includes the runner used for this attempt. The Python auditors can
reconstruct distributions, paired work, process provenance and portable
reference vectors from saved JSON/gzip inputs without rerunning timing.
Some identity checks also require the corresponding local checkouts/runtime
paths; a data-only audit is not a fresh source/runtime revalidation.

The [evidence index](../benchmark/results/2026-11-14-recovery-evidence.json)
contains artifact SHA-256 values, source IDs and checkpoint references. The
primary raw files are `2026-11-14-recovery-rounding-{cad,controls,portable}-paired.json.gz`.
All target/control rows and rejected trials remain available. No performance
claim here implies statistical significance, a latency SLA, universal target
behavior or proven allocated-byte reduction.

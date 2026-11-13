# Performance and CAD validation record

This record distinguishes executed local checks from queued CI work. All code
checkpoints are preserved in `feat/performance-parametric-cad`; the review is
[draft PR #3](https://github.com/CrispStrobe/dart_csp/pull/3).

## Further optimization at `84b3413`

The follow-up source passes all 1,635 native tests, 299 JavaScript/Node tests and
299 WebAssembly/Node tests. Full static analysis reports no issues; all 180 Dart
files pass formatting. Twenty-six new regressions cover matching workspace and
fixed-point reuse, immutable CAD validation, active derivatives and exact rank
diagnostics. Source checkpoints and measurements were pushed incrementally.

Three paired JIT/AOT rounds over five fixtures preserve 60 complete harness
reports. Compiled-native median query batches improve by about 27% for
allDifferent; CAD regeneration improves by about 51–53%; coupled 3D pitch edits
improve by 35.6%. AOT GCC and the isolated-circle edit remain effectively flat.
The coupled cold AOT solve regresses by 11.7%, and several p95 paths regress;
no uniform tail improvement is claimed. See the
[full follow-up report](performance-optimization-followup.md) and
[per-process measurements](../benchmark/results/2026-11-13-optimization-paired.json)
for units, aggregation, work counters and every reported comparison.

GitHub Actions run 144 was queued when checked. Current local Node tests do not
replace the outstanding real-browser CI gate. Package/API-documentation results
below belong to the preceding checkpoint; this follow-up does not claim they
were repeated at the new source revision.

## First-pass final result at `689c38b`

| Gate | Executed result |
|---|---|
| Full native suite | 1,609 passed |
| JavaScript / Node audit corpus | 273 passed |
| WebAssembly / Node audit corpus | 273 passed |
| Static analysis | No issues with `--fatal-infos` |
| Formatting | All 174 Dart files pass |
| Package publication dry run | Zero warnings; no publication performed |
| API documentation | Generated successfully; zero errors and 20 unresolved-reference warnings whose text is present in the audit baseline |
| Executable examples | Mounting-plate regeneration and closest-point geometric drag pass |

This source is committed remotely. The final evidence commit changes only
documentation and recorded benchmark output. GitHub Actions remained queued;
local Node execution is the portable-code evidence, and real-browser CI remains
an outstanding environment gate.

## Reproducible commands

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --reporter expanded
xargs dart test -p node --compiler dart2js --reporter expanded < tool/performance_cad_tests.txt
xargs dart test -p node --compiler dart2wasm --reporter expanded < tool/performance_cad_tests.txt
dart test -p chrome --reporter expanded test/web_domain_rep_test.dart test/compiled_session_test.dart test/geometry_preferences_test.dart test/parametric_cad_test.dart
dart doc .
dart pub publish --dry-run
dart run example/parametric_bracket.dart
dart run example/geometric_drag.dart
```

The checked local runtime is Dart 3.14.0, Node 24.22.1 and Linux x64. The host
reports AMD EPYC 9V74; the container is shared/unpinned, so benchmark numbers are
fixture measurements rather than a stable hardware performance contract.

CI adds a Node 24 JavaScript/WebAssembly matrix over the bounded audit corpus and
expands the real-Chrome gate to cover compiled sessions, drag preferences and
CAD regeneration. The existing native OS/SDK matrix and scheduled full-browser
suite remain in place.

## Executed checkpoints

| Source checkpoint | Executed result |
|---|---|
| `992b97e` CAD feature layer | Full static analysis clean; 18 CAD/feature integration tests pass in an isolated checkout |
| `bbb1717` reusable CSP/continuous structure | Formatting and full analysis clean; all 1,457 native tests pass |
| `bbb1717` targeted JavaScript | 117 tests pass under Node/dart2js |
| `bbb1717` targeted WebAssembly | 94 tests pass under Node/dart2wasm |
| `bbb1717` standalone Wasm CAD | Compiles and executes the mounting-plate example with parameter edits and invalid-edit rollback |
| `ffd4b92` geometric preferences | 55 geometry tests pass; scoped analysis clean; closest-point drag example executes |
| `03edd598` retained allDifferent matching | 51 focused tests pass, including 320 independent repeated-query oracle checks |
| `03edd598` full/native and portable corpus | All 1,479 native tests pass; 139 tests each pass under JavaScript and WebAssembly/Node |
| Consolidated GCC/clause/mixed/support checkpoint | Full static analysis clean; all 1,530 native tests pass |
| `37d1cfc` portable propagation/mixed corpus | 190 tests each pass under JavaScript and WebAssembly/Node |
| Geometry/CAD validation hardening | 68 geometry and 32 CAD tests pass, including 27 new adversarial regressions; scoped analysis and formatting clean |
| Integrated sparse LCG and propagation cancellation | All 1,591 native tests pass; full static analysis clean; all 174 Dart files pass formatting |
| `78e5b29` portable corpus | All 251 Wasm tests pass; three JavaScript failures exposed domain-classification and stream-backpressure defects, then repaired in the next checkpoint without weakening assertions |
| JavaScript parity repairs | 36 focused JavaScript domain/session tests and 31 stream tests each on JavaScript/Wasm pass; independent lifecycle review clears ten probes on each native/JavaScript runtime |
| `689c38b` final executable source | 1,609 native tests and 273 tests each under JavaScript/WebAssembly pass; full analysis and formatting clean; package dry run has zero warnings |

The local Chromium attempt failed during browser startup because the execution
environment disallows a required Unix socket. No browser test assertion ran in
that attempt. Node checks execute the compiled JavaScript/Wasm numerical code;
they do not claim browser UI coverage. Real-browser CI remains necessary.

At the time of these checkpoints, GitHub Actions runs were queued. A queued run
is not a passed CI gate. Subsequent validation results belong in this record and
the implementation plan's checkpoint log.

## Benchmark evidence

- `benchmark/compact.dart`: explicit-list versus compact-domain construction and
  first solve; billion-value correctness fixtures are separate tests.
- `benchmark/compiled.dart`: fresh versus prepared finite-domain query batches;
  reports initial preparation separately and verifies every assignment.
- `benchmark/matching.dart`: same-workload before/after retained matching;
  independent uniqueness and assumption checks.
- `benchmark/gcc.dart`: same-workload before/after compact capacitated flow;
  independent occurrence checks and actual node/arc counts.
- `benchmark/geometry.dart`: cold construction/compile/solve versus one changed
  component among 100 circles; independent radius/workplane checks.
- `benchmark/cad.dart`: cold, profile-edit and thickness-edit regeneration;
  analytic-volume and closed-mesh checks. Profile edits were not faster in the
  recorded exactly-satisfied-initial-sketch fixture.

Recorded samples and their scope live in `benchmark/results/`. Work counters and
oracle tests accompany timings; no single sample establishes a universal speedup
or the provisional 16.7 ms interactive target for arbitrary models.

### Final sequential sample

The six harnesses ran sequentially after the correctness checks at `689c38b`.
Each process used its harness's warmups and result validators. The complete
runtime, commands, work counters and summaries are in
`benchmark/results/2026-11-13-final.json`.

| Fixture | Comparison or path | Median | p95 |
|---|---|---:|---:|
| Declare 0..1,000,000 and find first solution | Explicit list | 25.415 ms | 85.230 ms |
| Same range/model | Compact declaration | 0.089 ms | 0.192 ms |
| 512 fixed variables, 20 edits | Fresh solves | 15.132 ms | 15.925 ms |
| Same model/edit batch | Prepared session | 3.199 ms | 3.432 ms |
| 100 independent 3D circles | Cold build/compile/solve | 5.274 ms | 15.416 ms |
| One changed radius among those circles | Local solve | 0.256 ms | 1.157 ms |
| Two-hole plate | Cold build/regenerate | 3.850 ms | 5.109 ms |
| Same plate, width/spacing edit | Profile regeneration | 4.026 ms | 7.513 ms |
| Same plate, thickness edit | Solid/mesh regeneration | 3.250 ms | 4.280 ms |

The repeated-query fixture prepares the root once; setup is reported separately
in the raw sample. The local circle edit solves one component and reuses 99.
These are current-code path comparisons, not an older-release comparison.
Profile regeneration is slightly slower than a cold build in this exact-seed
fixture. The final 64-variable allDifferent sample has a 53.594 ms median and
147.033 ms p95 per 12-query batch, so its tail remains uneven. Compact GCC at
64 variables/eight values reports 73 nodes, 520 arcs and a 15.235 ms median per
12-query batch. Earlier controlled before/after comparisons remain in
`doc/propagation-performance.md`; samples are not interchangeable across runs.

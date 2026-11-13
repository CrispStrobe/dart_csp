# Performance and CAD validation record

This record distinguishes executed local checks from queued CI work. All code
checkpoints are preserved in `feat/performance-parametric-cad`; the review is
[draft PR #3](https://github.com/CrispStrobe/dart_csp/pull/3).

## Reproducible commands

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --reporter expanded
xargs dart test -p node --compiler dart2js --reporter expanded < tool/performance_cad_tests.txt
xargs dart test -p node --compiler dart2wasm --reporter expanded < tool/performance_cad_tests.txt
dart test -p chrome --reporter expanded test/web_domain_rep_test.dart test/compiled_session_test.dart test/geometry_preferences_test.dart test/parametric_cad_test.dart
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
- `benchmark/geometry.dart`: cold construction/compile/solve versus one changed
  component among 100 circles; independent radius/workplane checks.
- `benchmark/cad.dart`: cold, profile-edit and thickness-edit regeneration;
  analytic-volume and closed-mesh checks. Profile edits were not faster in the
  recorded exactly-satisfied-initial-sketch fixture.

Recorded samples and their scope live in `benchmark/results/`. Work counters and
oracle tests accompany timings; no single sample establishes a universal speedup
or the provisional 16.7 ms interactive target for arbitrary models.

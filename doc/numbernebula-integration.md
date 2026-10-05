# NumberNebula integration: evidence and next lanes

Verified 2026-10-05. Downstream: [CrispStrobe/NumberNebula](https://github.com/CrispStrobe/NumberNebula).
Read its [handover](https://github.com/CrispStrobe/NumberNebula/blob/main/HANDOVER.md)
and [task board](https://github.com/CrispStrobe/NumberNebula/blob/main/REMAINING_WORK.md).
This document scopes downstream work; it does not replace the general solver roadmap.

## Current public baseline

Solver main is
[`b87babf138fef35ddbcf8ba981319ae29fdb24b0`](https://github.com/CrispStrobe/dart_csp/commit/b87babf138fef35ddbcf8ba981319ae29fdb24b0).
[CI run 37172497754](https://github.com/CrispStrobe/dart_csp/actions/runs/37172497754)
completed successfully on that commit. The main workflow includes the VM OS/SDK
matrix, a targeted dart2js check per push, and a full browser suite on schedule
or workflow dispatch. Beta/dev jobs are advisory; report individual job outcomes
when evaluating future heads. Native tests alone do not establish web safety.

The app and its isolated pure Dart package both use **v2.2.0**, not moving main.
The app baseline is **1.5.22+38** at
[`8eaf252`](https://github.com/CrispStrobe/NumberNebula/commit/8eaf252bc86dfc7e44bb219613e60f2bd3450e7c).
Its [pure workflow](https://github.com/CrispStrobe/NumberNebula/actions/runs/37241614982)
validated 48 games and 60,400 cases with zero failures; its
[web workflow](https://github.com/CrispStrobe/NumberNebula/actions/runs/37241614977)
passed WASM/JS, fixture replay and deployed-browser checks.
These downstream results establish the pinned integration, not every newer solver
revision or hypothetical candidate. No solver source changes are part of this handover.

Square/Crossword generation uses solver constraints; Cargo candidates use a
small reachable-row CSP. Existing app algorithms remain available for A/B and
fallback. Sequential planning such as Sokoban is not automatically a CSP workload.

## S1 — Reproducible downstream fixtures

**Ready. Own:** a new `benchmark/numbernebula.dart` and a small synthetic fixture
set; downstream exporter only if required. Read `benchmark/benchmark.dart`,
`benchmark/problems.dart`, `example/gensq.dart`, `example/gencw.dart` and downstream
`tool/compare_algorithm_paths.dart` first.

1. Select one Square or Crossword stratum with repeated expensive/fallback cases.
   Freeze seeds, settings and constraints from the actual shared generator.
2. Build a standalone pure Dart reproduction, without Flutter or profile data.
   Verify every returned solution with independent arithmetic/domain checks.
3. Measure warmed repeated medians and tail distributions, solver counters,
   solution validity, timeouts and fallback frequency. Keep candidate/baseline
   measurements paired; generation cost is not children's solving time.
4. Add a bounded regression for any exposed correctness issue and publish the
   fixture format plus reproduction command.

**Done:** a deterministic fixture, independent validity check and repeatable
baseline report on CI. A slow case alone is not proof that a propagator is wrong.

## S2 — Narrow measured solver optimization

**Depends on S1. Own:** only the propagator/search code identified by the report,
its focused `test/` regression and benchmark entry. Inspect generic-versus-
specialized behavior before choosing a replacement.

Preserve the working path. Add an opt-in candidate where behavior/performance
is uncertain; test satisfiable and unsatisfiable verdict parity against small
brute-force instances and existing search/LCG modes. Preserve deadline/cancellation
contracts. Compare warm medians and fallback rates on the S1 workload; do not
claim wins from one cold timing. Do not broaden into an unrelated engine rewrite.

**Done:** independently valid solutions, zero verdict regressions, measured
benefit or a documented no-change result, and green VM/dart2js/WASM-relevant checks.
Run large suites and benchmarks on GitHub Actions, not a shared development host.

## S3 — Downstream adoption and retained fallback

**Depends on S2, or a separately justified existing upstream fix. Own:** downstream
`pubspec.yaml`, `pubspec.lock`, `tool/pure_dart/pubspec.yaml` and applicable lockfile,
plus integration tests/docs. Do not change only one of the two dependency pins.

Select an immutable reviewed revision/tag; show why it is needed compared with
v2.2.0. Replay frozen cases and paired legacy/candidate paths, run all-game pure
calibration, then Flutter capture/session tests and Chromium/WASM plus Firefox/JS
build/browser checks. Preserve the original algorithm and fallback until evidence
justifies a separate removal decision. Update the app version for shipping changes.

**Done:** upstream and downstream exact-head checks green, both pins aligned,
public reproduction/run links, and fallback exercised. A docs-only update changes
neither solver version nor app dependency pins.

## S4 — Browser and CI evidence maintenance

**Ready. Own:** `.github/workflows/ci.yml`, `test/web_domain_rep_test.dart` and
this guide; coordinate with anyone editing shared workflows.

Verify targeted per-push and scheduled full-browser coverage remains meaningful.
Use workflow dispatch for full dart2js coverage after representation/search changes;
classify VM-only process/isolate cases explicitly instead of weakening browser
assertions. Record exact-head job outcomes and runner costs. Add WASM regressions
when a new representation or cancellation boundary needs them.

**Done:** current evidence table and retained platform gates, with measured CI
cost improvements only when coverage is unchanged. General solver roadmap items
remain in [PLAN.md](../PLAN.md); historical counts in older handovers are not
current-head guarantees.

## Parallel boundaries and publication

S1 can run alongside app screen audits. S2 owns its engine files; S3 waits for
upstream evidence. One integrator owns shared workflow and dependency updates.
Inspect working trees and isolate unrelated uncommitted work before staging.
Public docs contain public URLs/repository-relative paths only. Keep host paths,
account information and credentials in private operational notes outside Git.

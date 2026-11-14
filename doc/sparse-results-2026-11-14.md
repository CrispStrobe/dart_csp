# Bounded sparse solver: completed measurements and retention decision

## Decision and source boundary

Retain the bounded pure-Dart sparse LDLT backend and its adaptive fill-work
policy for integration through [PR #9](https://github.com/CrispStrobe/dart_csp/pull/9).
The planned qualification, large sparse comparison, seven-round small controls,
2,000-coordinate fallback reliability experiment, and final JIT/AOT small-QR/CAD
controls are complete and saved. Independent source and evidence reviews found
no correctness blocker. Integration accepts the adverse timing observations
below in exchange for the measured large low-fill ladder benefit. Performance
remains workload dependent.

The production revision is `6cc191f3e9a7c6642afa9af7757b26e515723018`:

| Identity | Value |
|---|---|
| Baseline main | `135a6eed93b46ad7d40d0f5288686d2cd26ddd48` |
| Candidate library tree | `eb20b0ea6dc251142e6109f04bb7fe768d967db1` |
| Candidate test tree | `053478f4a4d7b097211c5cb8984ff3fb6dc1a901` |
| Compiler | Dart 3.14.0 stable, Linux x64 |
| Compiler SHA-256 | `6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b` |
| Canonical dependency-lock SHA-256 | `a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a` |

Recovery and finalization changed evidence, audit tooling and documentation.
Production and test bytes still exactly match the qualified source. Original
branches, rejected experiments, raw results and adverse observations remain
preserved. PR #9 records the final integration commit; no package release is
part of this pass.

## Resulting behavior

The default adaptive backend retains its small dense QR and medium CG thresholds.
From 256 active tangent coordinates, it can attempt a bounded sparse LDLT step.
The automatic numeric-work cap is the smaller of the configured hard cap and
32 Schur updates per raw CSR entry. Structural refusal or a failed numerical
attempt can fall back to CG within the remaining linear iteration budget.
Cancellation is terminal. All original-equation, physical acceptance and
transaction rollback checks remain in force.

The direct backend preserves duplicate-CSR contributions and exact caller
damping, with finite positive pivot checks and original-equation verification.
Its deterministic minimum-degree ordering now scans only remaining columns,
reducing a complete candidate scan to `n * (n + 1) / 2` visits while preserving
original-index tie breaking. Numeric scratch is isolated per call. The resource
caps bound selected structural work and entries, rather than wall time or bytes.
See the [configuration guide](sparse-geometry-backend.md) for limits and controls.

## Large sparse benefit and retained controls

The saved three-round comparison has 96 complete jobs and 864 accepted
operations. The 500-coordinate ladder median ratios are 0.043–0.126: elapsed
time is 87.4–95.7% lower across the two engines and cold/warm modes. The coupled
500-coordinate graph has mixed median changes, from 4.0% lower to 8.9% higher.

| 500-coordinate fixture | Engine | Lifecycle | Candidate/baseline p50 | Candidate/baseline p95 |
|---|---|---|---:|---:|
| Low-fill ladder | 2D analytic | Cold | 0.0901 | 0.1017 |
| Low-fill ladder | 3D AD | Cold | 0.1257 | 0.1118 |
| Low-fill ladder | 2D analytic | Warm | 0.0426 | 0.1265 |
| Low-fill ladder | 3D AD | Warm | 0.1027 | 0.1018 |
| Coupled graph | 2D analytic | Cold | 0.9598 | 0.9888 |
| Coupled graph | 3D AD | Cold | 1.0390 | 0.9726 |
| Coupled graph | 2D analytic | Warm | 0.9709 | 0.9031 |
| Coupled graph | 3D AD | Warm | 1.0888 | 0.8803 |

The original three-round 100-coordinate cold-ladder median regression of
37–39% remains archived. A separate seven-round confirmation has 112 complete
jobs and 2,912 accepted operations, with identical coordinates and work in
all 1,456 matched operations. Its authoritative cold-ladder median changes are
**+3.21% in 2D and +2.80% in 3D**. The corresponding p95 changes are +18.63% and
-1.51%; cold coupled 2D retains +7.94% p50. These values correct the interrupted
chat's provisional account. See the [recovery review](sparse-control-recovery-review-2026-11-14.md).

Each cohort is kept separate. Different hosts, rounds and sampling designs are
not pooled, and the confirmation does not erase the original adverse result.

## Final small-QR and CAD controls

The final cohort compares the exact baseline and candidate in clean detached
worktrees with identical harness bytes, compiler and locked dependencies. The
collector runs one process at a time on CPU 0, alternating revision order in
each of three rounds. Each process uses five warmups and 25 measured samples.
Both JIT and AOT are covered; compilation occurs outside measured sections.

All 36 reports completed. There are 240 raw distributions, 6,000 measured
samples or batches and 40 aggregate rows. All harness independent correctness
checks passed. All 2,400 CAD work records satisfy the fixture invariants and
all 1,200 before/after work pairs match exactly. No samples, reports or adverse
rows were removed.

Thirty of the 40 aggregate medians are lower, including all twelve AOT small-QR
medians (0.2–20.6% lower). That count is descriptive, not a weighting of real
application workloads. The important adverse observations are:

| Control | Baseline | Candidate | Observed change |
|---|---:|---:|---:|
| AOT plate thickness edit, p50 | 636 us | 707 us | +11.16% |
| AOT plate profile edit, p50 | 722 us | 766 us | +6.09% |
| AOT plate profile edit, p95 | 864 us | 1,040 us | +20.37% |
| JIT cold linkage, p50 | 2,681 us | 2,860 us | +6.68% |
| JIT cold linkage, p95 | 9,464 us | 12,349 us | +30.48% |
| JIT rank 4x5, p50 per 256-call batch | 202 us | 226 us | +11.88% |
| JIT rank 4x8, p95 per 256-call batch | 217 us | 2,633 us | +1,113.36% |

The cold-linkage and rank-4x8 p95 values worsen in all three process pairs.
These tails remain explicit integration costs. AOT plate profile/thickness
medians each have two faster pairs and one slower pair; the ratio of process
medians and the directions of individual pairs answer different questions.
The complete table and pair directions are retained in the
[independent source/control review](../benchmark/results/2026-11-14-sparse-final-controls/source-and-controls-review.md)
and [measurement cross-check](../benchmark/results/2026-11-14-sparse-final-controls/small-cad-crosscheck-review.md).

Three process pairs provide descriptive screening evidence, not stable tail
bounds or causal attribution. The unchanged rank implementation and no-solve
thickness path do not execute sparse factorization; these measurements alone
cannot identify the cause of their timing changes. Matching work counters do
not exclude dispatcher or compiler-layout effects. The prior native-rounding
JIT coupler p99 issue remains unresolved by this experiment.

## 2,000-coordinate convergence limit

The separate feasible `laman_free_2000` fixture completed all eight jobs and
16 operations within the 20-second per-process deadline. Both revisions returned
`iterationLimit` for every operation and failed the independent physical oracle.
All eight paired outputs have identical coordinates and all seven saved work
counters. There are no missing operations, timeouts or protocol discrepancies.

This is an unchanged convergence limit under the existing outer nonlinear
budget. It does not establish infeasibility. Every successful-solve latency ratio
is correctly null. The default resource policy can decline direct factorization
and select CG on this dense-fill graph. See the
[reliability review](sparse-dense-fill-review-2026-11-14.md).

## Validation and independent audits

The unchanged source has saved passing formatting and fatal-info analysis,
**1,862 native tests, 541 Node JavaScript tests, 541 Node WebAssembly tests and
48 Python comparison-harness tests**. The separate 36-job qualification has
108 operations: all 96 feasible operations are accepted and all twelve
contradictions are rejected. These full source gates were recovered and checked;
they were not rerun merely to restore an interrupted conversation.

The latest recovery checked all 665 manifested members of the five finalization
and integration archives. Rerunning their preserved auditors exactly reproduced
the saved reports, with zero integrity findings. The final controls pass three
independent checks: 41,604 standalone source/measurement checks, 16,890
cross-check assertions and 1,010 process checks. These overlapping check counts
are not independent experimental replicates.

The small-control collector preserves original stdout/stderr, hashes, source
and package mappings, compile/run commands, raw timings and CAD work records.
It does not serialize every numerical result for physical-oracle replay, or
retain/hash the six temporary AOT executables. The reviewed harnesses perform
their independent result checks outside each timer. The large-solver adapter
cohorts separately preserve full outputs for physical-oracle replay.

Real-browser execution remains unverified: the preserved local Chromium attempts
failed at startup before assertions. At the final pre-integration check, CI run `43603482981` for the complete
raw checkpoint `ddb6a30` remained queued; consult the final PR/main workflow
for current status. Node
portability is recorded separately from browser coverage.

## Evidence and reproduction

The final evidence is in
[`benchmark/results/2026-11-14-sparse-final-controls`](../benchmark/results/2026-11-14-sparse-final-controls).
`small-cad-evidence.json` records exact file sizes/hashes and the uncompressed
raw digest. The partial eight-report checkpoint is retained at `a821bd6` and
the complete 36-report raw checkpoint at `ddb6a30`. All later audited results
remain descendants on the same working branch, without history rewriting.

From the repository root, an archive-only audit needs both measured source
commits in Git, but does not need Dart or the old workspace:

```sh
python3 tool/audit_sparse_small_cad.py \
  benchmark/results/2026-11-14-sparse-final-controls/small-cad-paired.json.gz \
  benchmark/results/2026-11-14-sparse-final-controls/small-cad-summary.json \
  --repo . --output /path/to/recomputed-audit.json
```

Add `--check-live` only while the originally recorded worktree paths exist.
The adjacent runtime manifest, dependency lock and package configurations
preserve preparation identities. The completed collector's raw commands and
the archived source hashes document how the timing cohort was generated.

This completes the bounded sparse-solver pass. Further JIT tail attribution, difficult-start convergence work and real-browser validation are separate
follow-ups; none of their unresolved outcomes is presented as a completed pass.

# Sparse backend finalization: independent evidence audit

Audit performed on 2026-11-14 against saved checkpoint
`806b236726e70b856fc3ca4d1286936ccd340a3d`. The production source measured and
validated by that checkpoint is `6cc191f3e9a7c6642afa9af7757b26e515723018`,
library tree `eb20b0ea6dc251142e6109f04bb7fe768d967db1`. The checkpoint has the
same library tree. The comparison baseline is consolidated main
`135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.

## Recovery finding

The complete three-round timing cohort and full native/portable validation
**were saved remotely** after the handoff's last described source checkpoint.
The older completion documents and PR description still call that work
pending. Repeating the full experiment solely to recover its evidence is
unnecessary. Its adverse controls must remain visible alongside its gains.

All paths below are relative to
[`benchmark/results/2026-11-14-sparse-completion`](../benchmark/results/2026-11-14-sparse-completion).

| Archive | Bytes | Listed files | SHA-256 |
|---|---:|---:|---|
| `preparation-6cc191f.tar.gz` | 1,291,529 | 12 | `4b5ea6bd84464d8be51c6a907190208d14d8a8fe85c50f23cfd661013979ed2a` |
| `qualification-6cc191f.tar.gz` | 1,059,656 | 188 | `27bbd031088ddb2c9172ff91e7dbc9fcfd7283daf158eb822381e9590f9530c9` |
| `timing-6cc191f.tar.gz` | 4,501,469 | 493 | `927a926b20367e697a3f98f0ee44a3a2cfa7bab562251c1f2fb17d4f3e15e801` |
| `validation-6cc191f.tar.gz` | 267,688 | 21 | `771434bb9dab4dd2b1a24702171c499a0d88754ce71f0aefe00129d5384896fe` |

Each archive size/hash and every listed member size/hash matches its adjacent
evidence manifest. Preparation intentionally omits the two AOT executables;
their hashes, compiler identity, build commands/logs, source snapshots and
package-resolution inputs remain recorded. No raw qualification, timing or
validation files are listed as omitted.

The nested before/after source archives contain 181/184 files. Every file
matches its recorded hash; every tracked library, test, adapter and pubspec
file also matches its claimed Git commit. The archived validation records
276 tracked file hashes matching `6cc191f`; its two remaining inputs are the
untracked dependency lock and package configuration. Source-file hashes are
unchanged from validation start to finish. The final working-tree status only
adds the newly produced evidence directory.

## Correctness and gate audit

The audit independently read requests, unmodified native stdout and checked
records. It verified request hashes, exact operation indices, native-field
preservation, process exit/deadline status, paired physical requests and the
recorded preparation identity. It reran the archived physical oracle on every
output and recomputed per-process upper-order p50/p95, group medians and all
published ratios. There were no discrepancies.

| Cohort | Complete jobs | Operations | Warmups | Feasible accepted | Contradictions rejected |
|---|---:|---:|---:|---:|---:|
| Candidate qualification | 36 / 36 | 108 | 36 | 96 / 96 | 12 / 12 |
| Paired timing | 96 / 96 | 864 | 192 | 864 / 864 | None requested |

Qualification covers the 2,000-coordinate ladder and 500-coordinate coupled
graph, both representations and both cold/warm lifecycles. It does not cover
the 2,000-coordinate coupled graph.

Actual archived terminal output confirms:

- Formatting: 227 files inspected, none changed.
- Fatal-info analysis: no issues.
- Native tests: **1,862 passed**.
- Node JavaScript tests: **541 passed**.
- Node WebAssembly tests: **541 passed**.
- Python comparison tests: **48 passed**.

The count increase from the pasted handoff is the subsequently added exact
symbolic-work-budget regression. Real-browser coverage is still absent from
these archives: Chromium aborted before assertions because creating its
process-singleton socket was denied. Node portability is not a browser pass.

## Preserved timing results

The table reports medians of three process p50 values in milliseconds and the
published after/before ratios. Each process has two warmups and seven measured
operations. Ratios below one favor the candidate. These are descriptive
screening measurements, not stable tail estimates.

| Geometric coordinates / family | Engine | Lifecycle | Before p50 | After p50 | p50 ratio | p95 ratio |
|---|---|---|---:|---:|---:|---:|
| 500 / ladder | 2D analytic | Cold | 101.750 | 9.163 | 0.0901 | 0.1017 |
| 500 / ladder | 3D AD | Cold | 141.913 | 17.840 | 0.1257 | 0.1118 |
| 500 / ladder | 2D analytic | Warm | 145.557 | 6.208 | 0.0427 | 0.1265 |
| 500 / ladder | 3D AD | Warm | 216.862 | 22.276 | 0.1027 | 0.1018 |
| 100 / ladder | 2D analytic | Cold | 3.246 | 4.438 | 1.3672 | 1.2234 |
| 100 / ladder | 3D AD | Cold | 4.909 | 6.836 | 1.3926 | 1.0359 |
| 100 / ladder | 2D analytic | Warm | 3.164 | 2.877 | 0.9094 | 0.8672 |
| 100 / ladder | 3D AD | Warm | 5.730 | 4.702 | 0.8206 | 0.9680 |
| 100 / coupled | 2D analytic | Cold | 3.670 | 3.794 | 1.0338 | 0.7339 |
| 100 / coupled | 3D AD | Cold | 6.309 | 6.700 | 1.0619 | 1.1210 |
| 100 / coupled | 2D analytic | Warm | 3.905 | 3.870 | 0.9911 | 0.9833 |
| 100 / coupled | 3D AD | Warm | 6.432 | 6.188 | 0.9621 | 0.9459 |
| 500 / coupled | 2D analytic | Cold | 78.788 | 75.624 | 0.9598 | 0.9888 |
| 500 / coupled | 3D AD | Cold | 100.629 | 104.550 | 1.0390 | 0.9726 |
| 500 / coupled | 2D analytic | Warm | 64.006 | 62.142 | 0.9709 | 0.9031 |
| 500 / coupled | 3D AD | Warm | 89.022 | 96.927 | 1.0888 | 0.8803 |

The low-fill ladder's measured p50 reduction is 87.4–95.7%. The adaptive fill
cap removes the earlier coupled-graph slowdown of the unrestricted candidate;
the current coupled p50 outcomes span approximately -4.0% to +8.9%. Neither
finding supports a claim that every graph or lifecycle improves.

### Below-threshold cold controls

The cold 100-coordinate ladder aggregate worsens by 36.7% / 39.3%. Preserve
that result. Its 100/150 Jacobian columns are below the 256-column direct
threshold, so sparse factorization and its cache cannot explain this cost.
All **216 paired control operations** across the two 100-coordinate families
have exactly identical coordinates and iteration, linear-work, Jacobian and
residual-evaluation counters before and after.

Timing varies substantially between processes. For the cold ladder, the three
matched process-p50 ratios are approximately 0.940, 0.974, 1.397 in 2D and
0.822, 1.393, 1.003 in 3D. These supplementary observations do not replace the
prespecified ratio-of-medians above. They show why a focused confirmation is
needed before interpreting its aggregate as a stable regression. Host timing
variation is a plausible explanation; changed AOT layout/inlining around the
larger dispatcher and residual helper is another. No root cause is established.

## Remaining bounded completion work

The authoritative follow-up schedule is in
[`sparse-finalization-2026-11-14.md`](sparse-finalization-2026-11-14.md), saved in
`c5dc8153dd398beb832a7753dc6d66602bbacc88`. Its recovered-evidence audit agrees
with this review's archive identities, counts and timing aggregates. This
review adds the matched-control operation/counter check and interpretation;
it does not replace or duplicate the saved raw audit.

1. Preserve this audit and the original cohort. Rerun only the unresolved
   controls, using a fresh paired preparation for the current machine and
   identical library/adapters/package inputs. Do not pool hosts or overwrite
   the previous cohort. Follow the saved plan's seven alternating process
   pairs for the two 100-coordinate controls, with five warmups and 21 measured
   operations per job. Tiny-QR coverage is handled separately:

   ```sh
   python3 benchmark/solver_comparison/paired_dart_backends.py run \
     --prepared /path/to/current-prepared \
     --suites confirm,coupled \
     --fixtures ladder_25_components_1,laman_free_100 \
     --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
     --rounds 7 --warmups 5 --samples 21 --timeout 20 \
     --out /path/to/new/control-confirmation
   ```

2. Keep `laman_free_2000` in a separate reliability run. One paired round,
   zero warmups, two samples, both representations/lifecycles and a 20-second
   process deadline provide 8 jobs and at most 16 operations. Preserve every
   rejection/timeout; compute no successful-solve ratio unless both complete
   groups physically accept. Local failure does not prove infeasibility.

   ```sh
   python3 benchmark/solver_comparison/paired_dart_backends.py run \
     --prepared /path/to/current-prepared --suites coupled \
     --fixtures laman_free_2000 \
     --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
     --rounds 1 --warmups 0 --samples 2 --timeout 20 \
     --out /path/to/new/dense-fill-reliability
   ```

3. Run the existing `geometry_small_qr`, `cad` and `cad_linkage` controls through
   `tool/compare_performance.py`, both JIT and AOT, three alternating rounds,
   5 warmups / 25 samples. The tool builds before measurements and retains
   exact outputs and source identities. Run it sequentially with the adapter
   cohorts and all other heavy work stopped. Pin the process externally to
   one allowed CPU if desired; the tool inherits affinity.
4. Recheck current remote CI/browser status. If production bytes change,
   validate those bytes and repeat affected measurements before integration.
   If only documentation/evidence changes, the preserved source gates remain
   applicable; report that they were recovered, rather than newly executed.
5. Update the stale handover/PR description with the evidence, limitations and
   explicit retention decision, then integrate the qualified source into main
   using the existing expected-head/no-history-rewrite workflow.

Correctness acceptance requires complete requested operations, physical
acceptance of every constructed feasible case and rejection of contradictions,
no oracle disagreement and no adapter exception. The separate dense-fill
reliability cohort is expected to expose the fallback's limits rather than
provide universal qualification. Performance acceptance should preserve the
large ladder benefit while honestly bounding unresolved collateral cost.

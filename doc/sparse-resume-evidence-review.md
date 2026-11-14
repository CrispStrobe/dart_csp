# Independent sparse-backend evidence recovery review

Historical recovery review completed 2026-11-14 against `CrispStrobe/dart_csp` integration commit
`5c93ab09899cd43d394c857d218e3c0ff9ecb957`. The numerical evidence below describes that saved source only. It is not a
claim about the resumed adaptive-policy candidate or its new timings.

## Recoverable boundary

- Remote main: `135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.
- PR #9 source head: `b22bb671e505ad818c46f1a69772973ead436dd4`; still draft/open.
- Integration branch is newer: `5c93ab0` contains the sparse source history,
  independent tests, documentation, portable corpus registration, the full
  qualification, and timing cohort 1. Its production library tree is
  `960b3b699628ade1e6b5b61cecae6037f50391f4`, the same as `b22bb671`.
- No later timing cohorts, revision-3 adaptive policy, or final sparse validation
  are present in the observed branch trees. The pasted handoff extends beyond
  the last durable remote checkpoint. Preserve this distinction.
- Main CI run `43592200529` was still `queued` at inspection. There is no fresh
  real-browser pass established by that state.

## Raw evidence audit

The three saved archive hashes match the adjacent manifests:

| Archive | SHA-256 |
|---|---|
| preparation-b22bb671.tar.gz | 03685180981eb9c93f3e21dd64b604e24d575fbff99b4146478a878d6ae8df82 |
| qualification-b22bb671.tar.gz | 8abce461c471bf7df154153047eaefeb735f58a033cc4039a20a97e531f4676d |
| timing-r1-b22bb671.tar.gz | 8af816070edec78764eabfafd3b6320caba94a5793317cd11cf3b053a5ea6ac1 |

The independent check read the compressed archives directly from Git objects,
checked operation indices against every request, compared unchanged native
fields to the checked records, recomputed every physical acceptance result
using the pinned oracle, checked known feasibility, and recomputed each job's
upper-order p50/p95 from native elapsed times. No discrepancies were found.

| Cohort | Jobs complete | Records | Warmups | Physically accepted |
|---|---:|---:|---:|---:|
| Qualification | 36/36 | 108 | 36 | 96 |
| Timing round 1 | 32/32 | 288 | 64 | 288 |

Qualification's remaining 12 records are expected contradictions, all rejected.
The 96 feasible records include 2,000-coordinate ladders and the 500-coordinate
coupled framework in both representations and both lifecycles. It does not
include `laman_free_2000`.

The first timing round contains 224 measured records and 64 warmups, all accepted
with native success, and no incomplete jobs, oracle disagreements or exceptions.

## Exact first-round timings

Milliseconds; one process per row and revision, two warmups and seven measured
samples. These are descriptive screening observations, not robust tail estimates.

| Fixture | Engine | Mode | Before p50 | After p50 | Before p95 | After p95 |
|---|---|---|---:|---:|---:|---:|
| Ladder 100 | 2D analytic | cold | 3.177182 | 3.764748 | 3.829234 | 4.169681 |
| Ladder 100 | 2D analytic | warm | 2.532112 | 2.334538 | 5.051539 | 2.895573 |
| Ladder 100 | 3D AD | cold | 4.931155 | 5.064043 | 5.478361 | 5.733651 |
| Ladder 100 | 3D AD | warm | 4.094038 | 4.611910 | 7.243890 | 4.847821 |
| Ladder 500 | 2D analytic | cold | 130.796595 | 8.763283 | 149.794483 | 12.614754 |
| Ladder 500 | 2D analytic | warm | 154.315794 | 5.718488 | 403.395674 | 6.189299 |
| Ladder 500 | 3D AD | cold | 125.862506 | 18.692053 | 165.489607 | 25.146407 |
| Ladder 500 | 3D AD | warm | 208.595246 | 13.568080 | 338.756867 | 14.010499 |
| Coupled 100 | 2D analytic | cold | 4.038556 | 3.874952 | 5.812590 | 4.567383 |
| Coupled 100 | 2D analytic | warm | 5.185865 | 3.761173 | 5.556837 | 4.406975 |
| Coupled 100 | 3D AD | cold | 6.024063 | 6.338913 | 8.669955 | 7.310040 |
| Coupled 100 | 3D AD | warm | 5.921711 | 5.534334 | 6.036652 | 5.663707 |
| Coupled 500 | 2D analytic | cold | 60.104666 | 97.679369 | 68.814980 | 345.219886 |
| Coupled 500 | 2D analytic | warm | 55.362047 | 69.496002 | 58.616315 | 146.911770 |
| Coupled 500 | 3D AD | cold | 96.867165 | 314.048037 | 109.471238 | 486.231235 |
| Coupled 500 | 3D AD | warm | 84.362379 | 220.664453 | 85.866990 | 339.424974 |

The 100-coordinate fixtures are below the 256-column threshold in both
representations (the stock representation has 150 tangent columns). Their
mixed results should remain as controls; do not attribute their variation to
the direct factorization path. Stock 3D uses 1.5 times the planar coordinate
count plus plane equations; fixture labels denote geometric free coordinates.

## Structural policy recommendation

Reconstructed the CSR block pattern from the pinned physical fixtures and
adapter declarations, retaining numerical zeros, and simulated exactly the
deterministic minimum-degree tie order and Schur-update accounting. Nonzero
counts agree with saved operation counters. These are structural computations,
not measured runtime counters from the new backend.

| Fixture | Representation | Columns | Raw nnz | Factor entries | Numeric updates | Updates / nnz |
|---|---|---:|---:|---:|---:|---:|
| Ladder 500 | 2D | 500 | 1,994 | 2,738 | 6,210 | 3.11 |
| Ladder 500 | 3D | 750 | 3,741 | 5,973 | 21,115 | 5.64 |
| Ladder 2,000 | 2D | 2,000 | 7,994 | 10,988 | 24,960 | 3.12 |
| Ladder 2,000 | 3D | 3,000 | 14,991 | 23,973 | 84,865 | 5.66 |
| Coupled 500 | 2D | 500 | 1,988 | 20,342 | 884,570 | 444.95 |
| Coupled 500 | 3D | 750 | 3,732 | 45,582 | 2,985,580 | 799.99 |

Prefer an adaptive-only numeric-work budget of
`min(explicit hard maxNumericWork, 32 * raw CSR nnz)`, with overflow-safe
saturation before multiplication. An absolute smaller budget rejects some
larger low-fill graphs without relating factor work to matrix-free work.
32 is a conservative eligibility heuristic with slack above the tested ladder
patterns; it is not an empirically optimal crossover or a guarantee of speed.
Keep the explicitly chosen direct solver's existing absolute limits available.

For Coupled 500, this relative cap declines at approximately 227,943 (2D) /
472,359 (3D) symbolic work, compared with full-pattern costs 1,160,370 /
3,606,322. Low-fill ladders remain eligible. Cold calls still pay this bounded
eligibility overhead; warm unchanged structures should reuse the decline.
The exact effective cap must participate in decline-cache compatibility,
and accepted patterns must also be checked against it on every reuse.

The 2,000-coordinate dense-fill case remains important: even early rejection
requires millions of deterministic ordering scans, and CG may still reject
the geometry. Measure its reliability separately, without successful-solve
speed ratios when baseline or candidate fails.

## Completion experiment

The documented three alternating cohorts total 96 jobs, 672 measured operations
and 192 warmups across two variants, two engines, two lifecycles and four cases.
That is proportionate screening for these large timing differences. Do not
pool the previous host's one-round cohort with the newly recovered runtime;
preserve it as historical evidence and run a fresh complete three-round cohort.
The timing harness pins children to one allowed CPU and runs one solver at a
time; no builds, test suites, profiling or other heavy jobs should overlap.

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py prepare \
  --before /path/to/frozen-main --after /path/to/frozen-candidate \
  --dart /path/to/dart-sdk/bin/dart --out /path/to/new/prepared

python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared /path/to/new/prepared --variants after --purpose qualification \
  --suites smoke,confirm,coupled \
  --fixtures canonical_cell,axis_rectangle,coincidence,contradictory_distance,ladder_3_components_1,ladder_1_components_1_scale_1e-06,ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --warmups 1 --samples 2 --timeout 20 \
  --out /path/to/new/qualification

python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared /path/to/new/prepared --suites confirm,coupled \
  --fixtures ladder_25_components_1,ladder_125_components_1,laman_free_100,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 3 --warmups 2 --samples 7 --timeout 20 \
  --out /path/to/new/paired
```

Keep raw rejected/timeout records in a separate `laman_free_2000` reliability
run (one round, no warmups, one or two samples and an explicit process deadline).
Native full-suite, Node JS/Wasm and sparse-budget regressions remain source
gates independent of this performance experiment. Small QR/CG geometry and CAD
control timings are useful to bound collateral cost; the main 100-coordinate
controls exercise the medium CG path but do not replace tiny QR controls.

## Small harness finding

`paired_dart_backends.py` builds per-variant manifests by copying top-level
`status='running'`, then its checkpoint writes never refresh the lane's status.
Consequently the saved complete archives have `status='running'` in
`before/manifest.json` and `after/manifest.json`, although their parent manifest,
complete job records and summaries establish completion. This is a metadata
bug, not missing evidence. Copy current `status`, completion timestamps and
qualification/protocol results into per-variant manifests on each checkpoint
for future runs; preserve old manifests unchanged.


## Resumed-work status

The resumed pass implements the recommended relative budget separately from
this historical review. New candidate validation, performance measurements and
source identities must be reported separately; the old cohort remains unchanged.

The per-variant manifest lifecycle bug described above has been repaired for
future runs. Checkpoints now refresh collection/analysis status, completion
timestamps, paired-run protocol/qualification results, errors and each variant's
completed-job count. Tests cover a successful paired run, completed collection
with a failed feasible-warmup qualification, and interruption after one retained
job. Synthetic test timings are orchestration fixtures only.

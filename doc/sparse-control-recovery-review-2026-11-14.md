# Recovered seven-round control evidence audit — 2026-11-14

Audited remote checkpoint `f938f29c6cc41c9f73ad32e9af81be0425a37ec3` using its exact local clone. No repository instructions named `AGENTS.md` are present. No tracked files were modified.

## Recovered milestones

- `c5dc815`: recovery plan and archive audit.
- `7e1adf1`: independent source and complete prior-evidence reviews.
- `b0b4641`: new frozen builds and restored runtime verification.
- `f938f29`: completed seven-pair control confirmation and independent raw audit.

The preserved production library remains `eb20b0ea6dc251142e6109f04bb7fe768d967db1`, source `6cc191f3e9a7c6642afa9af7757b26e515723018`; baseline `135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.

## Fresh read-only verification

All 597 manifested files across the three finalization archives match exact member sets, sizes and SHA-256 digests: 574 control files, 12 preparation files and 11 runtime-validation files. The external control comparison is byte-identical to archived `comparison.json`.

Reran the saved `finalization_audit.py` against the frozen preparation and raw control archive. The result is exactly equal to the previously archived `independent-audit.json` and contains zero errors. It recomputes physical acceptance for every raw output, verifies native-field preservation, source/preparation identities, paired physical request equality, sequential job intervals, terminal manifests, process percentiles and published ratio-of-medians.

- 112 of 112 jobs complete; 56 for each revision.
- 2,912 of 2,912 operations physically accepted, comprising 2,352 measured operations and 560 warmups.
- No missing operations, timeouts, nonzero exits, parse errors, adapter errors or acceptance disagreements.
- All 1,456 before/after operation pairs have identical coordinates and the seven saved work counters.

## Authoritative control timings

These are seven process pairs, five warmups and 21 measured operations per job. Ratios are candidate/baseline medians of process p50/p95; do not pool this host with preceding cohorts.

| Family | Engine | Mode | Before p50 ms | After p50 ms | p50 ratio | p95 ratio |
|---|---|---|---:|---:|---:|---:|
| ladder_25_components_1 | dart_2d_analytic | cold | 2.765831 | 2.854582 | 1.032088 | 1.186292 |
| ladder_25_components_1 | dart_3d_ad | cold | 4.723055 | 4.855412 | 1.028024 | 0.984862 |
| ladder_25_components_1 | dart_2d_analytic | warm | 2.362820 | 2.366515 | 1.001564 | 0.988700 |
| ladder_25_components_1 | dart_3d_ad | warm | 4.170042 | 4.108780 | 0.985309 | 1.017239 |
| laman_free_100 | dart_2d_analytic | cold | 3.851877 | 4.157693 | 1.079394 | 1.033095 |
| laman_free_100 | dart_3d_ad | cold | 6.498060 | 6.303779 | 0.970102 | 0.974055 |
| laman_free_100 | dart_2d_analytic | warm | 3.679882 | 3.621074 | 0.984019 | 0.546579 |
| laman_free_100 | dart_3d_ad | warm | 6.415736 | 6.054959 | 0.943767 | 0.728396 |

The pasted progress narrative is not numerically accurate for the final saved cohort: cold ladder p50 is **+3.21% in 2D and +2.80% in 3D**, not 2% faster/unchanged. Cold-ladder p95 is **+18.63% in 2D and -1.51% in 3D**; the higher tail is 2D. The earlier +37–39% median slowdown does not reproduce at that magnitude. Cold coupled 2D retains **+7.94% p50 / +3.31% p95**. These results should be retained rather than dismissed as noise; deterministic numerical/work parity does not exclude dispatch or compiler-layout cost.

## Remaining bounded work

1. Build fresh frozen baseline/candidate adapters with the identical Dart 3.14.0 runtime, locked dependencies and adapter bytes. New host evidence must remain separate.
2. Run `laman_free_2000` separately: one round, zero warmups, two samples, both engines and cold/warm, 20-second deadline (8 jobs, at most 16 operations). Preserve all failures/timeouts and suppress success ratios for groups not fully accepted.
3. Run `geometry_small_qr`, `cad`, `cad_linkage` using `tool/compare_performance.py`: both JIT and AOT, three alternating rounds, five warmups and 25 samples; run sequentially and pinned with other heavy work stopped.
4. Audit new evidence; update stale finalization/handover/PR text with actual numbers, limitations, CI/browser status and retention decision. No full validation rerun is needed solely for evidence recovery if production bytes do not change.

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared /path/to/current-prepared --suites coupled \
  --fixtures laman_free_2000 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --warmups 0 --samples 2 --timeout 20 \
  --out /path/to/new/dense-fill-reliability

taskset -c ALLOWED_CPU python3 tool/compare_performance.py \
  --before /path/to/main --after /path/to/candidate --dart /path/to/dart \
  --benchmarks geometry_small_qr cad cad_linkage --modes jit aot \
  --rounds 3 --warmups 5 --samples 25 \
  --output /path/to/new/small-cad-controls.json
```

## Reusable local audit files

The scratch directory `evidence-audit/` contains `finalization_audit.py`, its imported `independent-audit-preserved.py`, `archive-checks.json`, archived `independent-audit.json`, and fresh `recomputed-control-audit.json`. The first script can audit a new fallback run with `--repo`, `--prepared` and `--run` paths. It treats honest feasible rejection/deadline as a reliability outcome rather than an evidence-integrity error.

This audit finishes all requested read-only computation; no solver processes are running.

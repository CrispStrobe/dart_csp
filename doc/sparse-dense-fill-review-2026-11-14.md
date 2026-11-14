# Independent 2,000-coordinate fallback reliability audit — 2026-11-14

## Finding

The archived evidence is internally consistent, but the 2,000-coordinate coupled fixture remains unqualified on both revisions. All 16 requested operations returned `iterationLimit` and failed the independent physical oracle. All 8 before/after operation pairs have exactly identical final coordinates and seven saved solver-work counters. This records an existing convergence limit retained by the candidate; it neither establishes infeasibility nor supports a successful-solve speed comparison.

## Audited scope

- Baseline: `135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.
- Candidate source: `6cc191f3e9a7c6642afa9af7757b26e515723018`; unchanged library tree `eb20b0ea6dc251142e6109f04bb7fe768d967db1`.
- Fixture: `laman_free_2000`; 2D analytic and 3D AD; cold and warm.
- One alternating paired round, zero warmups and two measured operations per job.
- All 8 jobs ran sequentially with a 20-second process deadline.

| Metric | Baseline | Candidate | Total |
|---|---:|---:|---:|
| Requested operations | 8 | 8 | 16 |
| Reported and independently checked | 8 | 8 | 16 |
| Physically accepted | 0 | 0 | 0 |
| Feasible operations rejected | 8 | 8 | 16 |
| Missing operations | 0 | 0 | 0 |
| Timed-out jobs | 0 | 0 | 0 |
| Adapter errors / acceptance disagreements | 0 | 0 | 0 |

## Verification

The preserved raw audit validates preparation/source identities, exact request hashes, paired physical requests, original native-output preservation, per-operation physical oracle verdicts, sequential process intervals, completed counts, terminal manifests and percentile calculations. Its separate reliability wrapper independently recounts requested/reported/validated/missing operations and recomputes the terminal gates. Both report zero evidence-integrity errors.

`protocol_ok` is **true** and `qualification_passed` is **false**. Every variant group has `qualified_latency: false`; all successful-latency medians and all four paired p50/p95 ratios are correctly suppressed (`null`). The recorded failed-operation durations are diagnostic only.

## Reproduction

The run includes `independent-audit.json` and the unchanged original audit plus its added wrapper. Invoke:

```sh
python3 reliability_audit.py --repo /path/to/repo \
  --prepared /path/to/prepared --run /path/to/dense-fill-reliability
```

No solver was executed by this audit and no prepared manifest or raw evidence was changed.

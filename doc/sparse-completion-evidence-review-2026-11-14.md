# Independent sparse completion evidence review

Recovery audit performed on 2026-11-14. This review describes the saved source
and evidence below; it does not qualify later source changes or reproduce
timings mentioned only in the interrupted conversation.

## Saved boundary

At recovery, the newest remote checkpoint was
`87cd622b0219601202bbefe0aa85c10e274f8bc0` on
`checkpoint/sparse-resume-2026-11-14`. It adds preparation and qualification
archives to source commit `90f237f39c1fda6617d391a2efd5af2d96f75c3f`.
PR #9's source branch still pointed to `90f237f`; the integration branch was
`5c93ab09899cd43d394c857d218e3c0ff9ecb957`, and main was
`135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.

The archived candidate library tree is
`7dff0fdea5cb39dfe532a0757dcf9b53a962a905`, and its test tree is
`a5dd7d0ac265d5bc12178eb74cd0d9516b6c1d95`. The preparation compares this
candidate against the recorded main revision. Both source snapshots were clean.

## Independent checks of preserved raw evidence

The archives are in
[`benchmark/results/2026-11-14-sparse-resume`](../benchmark/results/2026-11-14-sparse-resume).

| Archive | Bytes | SHA-256 |
|---|---:|---|
| `preparation-90f237f.tar.gz` | 1,291,084 | `6c70a028ad5da6c0bf0d0353fd6a646064c2ac8be5ba838ae3218f07df083fa5` |
| `qualification-90f237f.tar.gz` | 1,055,986 | `7a23b431f008bf733293b8a45638e99ac1042ce4d727c4349a07e5adfbfa63c9` |

The independent audit read the archives directly from the Git object tree.
Their sizes and hashes, and those of the adjacent runner logs, match the
manifests. Every file in each nested source snapshot matches its recorded hash;
source, library and test tree identifiers agree with Git. The qualification
references the exact preserved preparation manifest and Python harness bytes.

For every job, the audit checked the raw request digest, complete operation
indices including warmups, process status, and unmodified native fields in
the checked records. It reran the archived physical oracle on all outputs,
compared outcomes with each fixture's constructed feasibility, and recomputed
each job's p50 and p95 using the documented upper order statistic. There were
no discrepancies, adapter exceptions, incomplete jobs or process timeouts.

| Qualification result | Count |
|---|---:|
| Complete jobs | 36 / 36 |
| Operations, including warmups | 108 |
| Warmups | 36 |
| Feasible operations accepted | 96 / 96 |
| Contradictory operations rejected | 12 / 12 |

These records cover both the 2D analytic and stock 3D AD representations in
cold and warm modes. They include canonical relations, a contradiction,
a small-unit fixture, the 500- and 2,000-coordinate ladders, and the
500-coordinate coupled graph. They do not cover `laman_free_2000`.

## What did not reach the saved checkpoint

No observed remote branch contained the final adaptive-policy timing cohort,
complete native/JavaScript/WebAssembly gate logs, tiny-QR/CAD timing controls,
or a 2,000-coordinate coupled reliability run described or anticipated near
the end of the pasted conversation. The statement of 85–96% ladder gains is
therefore an interrupted-chat observation, not a reproducible result for this
saved candidate. The older raw timing cohort remains available and separate;
see the [historical evidence review](sparse-resume-evidence-review.md).

At this inspection, PR-head CI run `43595529134` for `90f237f` was queued.
No real-browser pass was established. Portable tests under Node, once saved,
must remain distinguished from browser execution.

## Fresh completion experiment

The continuation is making a bounded symbolic-ordering implementation change.
Its new source revision requires fresh qualification and gates; the successful
`90f237f` qualification is historical evidence, not coverage of that change.

1. Save the source, then run formatting, fatal-info analysis, the full native
   suite and the portable JavaScript/WebAssembly corpus. Preserve logs and
   exact source identities.
2. Freeze identical adapters and package inputs against main and the new
   candidate with `paired_dart_backends.py prepare`. Rerun the documented
   36-job candidate qualification on those frozen artifacts.
3. After builds and other CPU-heavy work stop, run the documented three
   alternating timing rounds: two warmups and seven samples for
   `ladder_25_components_1`, `ladder_125_components_1`, `laman_free_100` and
   `laman_free_500`, both engines and both lifecycles. This is 96 jobs and
   864 operations: 672 measured operations plus 192 warmups. Run one pinned
   solver process at a time and preserve each completed cohort remotely.
4. Measure `laman_free_2000` separately with a short process deadline and one
   or two samples. Keep rejected and incomplete results without computing
   successful-solve speed ratios for them. Add coordinated tiny-QR/CAD
   controls to assess paths outside this adapter comparison.
5. Recheck raw outcomes and calculations before updating performance claims
   or the final integration decision.

The exact harness commands and interpretation rules are in
[`PAIRED_DART.md`](../benchmark/solver_comparison/PAIRED_DART.md). Do not pool
measurements from the earlier host with the new cohort. Seven samples per
process support descriptive screening of large differences, not stable tail
latency guarantees. These fixtures start near constructed solutions and do
not establish arbitrary CAD or difficult-initial-guess performance.

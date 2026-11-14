# Performance follow-up evidence — 2026-11-14

The source candidate is `ad8d23704e50c1bf41412f086e66de4a87bfb21b`.
Its only production change against packed source
`4325386e689566a903309accd66aca3ced1159f7` fuses four CG dot products into
existing vector loops. This directory is saved incrementally; a final
retention decision requires the completed timing and independent audits.

The [plan](../../../doc/performance-tradeoff-followup-2026-11-14.md),
[causal review](causal-review.md), and [code review](cg-code-review.md)
explain the hypotheses and limits. All seven full validation gates pass:
1,876 native tests, 555 JavaScript tests, 555 WebAssembly tests, 48 comparison
tests, eight collector tests, formatting, and fatal-info analysis. Exact
logs, source hashes and commands are in the validation archive.

Each `*-evidence.json` binds all members of a tar.xz archive by size and
SHA-256. Larger archives are split into ordered `.partNNN` files listed in
the manifest. Concatenate those parts in the listed order before opening
the archive. Source archives, compiler identity, build commands/logs and
exact executable hashes are retained; rebuildable AOT executable bytes
are omitted explicitly in the relevant evidence manifests.

The prepared physical adapters and 36-job candidate qualification are
complete. Qualification was collected during correctness validation and
its elapsed times must not be used as performance evidence. The physical
qualification covers 108 operations, including warmups: 96 feasible
operations accepted and 12 contradictory operations rejected.

QR preparation preserves separate historical and fused compiler
orchestration, three source snapshots, and three executable identities.
Its A/A lane uses the same exact packed executable under both labels.
No QR timing has been collected at this preparation checkpoint.

# Independent review of the norm-fusion protocol auditor

Reviewed `evidence_audit/audit_norm_fusion.py`, its synthetic tests and
`norm-audit-inputs.md`, together with the reused raw analyzer, paired collector,
fixture generator and exact archive packer. Final reviewed auditor SHA256:
`aec3c17a6b7b38c389c6294d61d847f1f8968a7639ba37e166a4f4da0a11c53d`.
The declaration template contains that exact auditor hash. This was a read-only
review; the reviewer did not execute benchmarks, compilers, tests or old timing
cohort replays.

## Conclusion

No remaining blocking mismatch found between the adopted acceptance rules,
the input contract and the final auditor. Two concrete provenance gaps found
during review were corrected by the author before freezing: successful
pre-declaration preparation/build completion, and binding the actual compact
archive timestamp to the reported packing interval.

## Decision math and strata

- The primary cell is exactly Laman-500 / 3D AD / warm. Each of its four
  process pairs has equal weight. Its median paired p50 ratio must be at most
  0.95, at least three individual ratios must be below 1.0, and the median in
  each process-order stratum must be strictly below 1.0.
- Every cell must contain rounds 1–4 exactly once, with two before-first and
  two after-first pairs. The raw metadata audit separately verifies the
  declared parity schedule, so the decision function does not merely trust
  arbitrary order labels.
- A/A primary bounds are inclusive: overall median in [0.95, 1.05], and each
  order median in [0.90, 1.10]. No A/A result is subtracted from candidate
  ratios or used to excuse an adverse candidate result.
- Other CG cells trigger the p50 rejection only when overall median and both
  order medians strictly exceed 1.05. Untouched QR/sparse-direct control cells
  use 1.10. Primary p50 is already governed by its stronger improvement gates.
- CG-target p95 rejection requires a ratio strictly above 1.25 in at least
  three rounds spanning both orders. Control tails are descriptive and are
  not incorrectly treated as CG-target rejection cells.
- The reused analyzer recomputes the declared process percentiles from raw
  records. It keeps median paired ratios separate from ratios of median
  process statistics; it does not pool individual operations into extra
  independent replicates.

The original 17 synthetic tests meaningfully cover these boundaries and
population failures. The final suite adds five provenance tests, including
valid copied A/A build timestamps, failed/incomplete builds, late completion,
pack timestamp boundaries, and optional runner identity. The author's saved
log reports all 22 passing; the reviewer inspected the tests and log without
rerunning them.

## Inventory, physical outcomes and provenance

The fixed population arithmetic matches the collector: 16 cells and 32
processes per measurement block, 672 measured plus 256 warmup operations per
block, eight blocks, 256 processes, 5,376 measured operations and 2,048 warmups.
Qualification separately requires 72 processes and 216 operations, including
24 expected contradictory rejections and 192 accepted operations.

The final auditor regenerates exact requests from the pinned fixture generator
and compares geometry, edits and tolerances, in addition to fixture IDs and
operation counts. Each raw result is independently checked by the physical
oracle. Checked/raw records must agree, and before/after requests plus every
non-timing result field must match. The exact archive restoration is verified
against every live raw file and the saved summary; extra or missing raw files
cannot be hidden by a successful summary.

Frozen preparation hashes bind the endpoint manifests. The reused preparation
audit checks actual source archives against their hashes and Git contents,
source/library/test trees, dependency lock, adapter inputs and actual executable
bytes. Both A/A labels must reuse the same baseline executable and source
archive bytes as the candidate comparison's before lane. The production file
list must contain only `lib/src/geometry/numeric.dart`, and the complete binary
Git diff hash must match the declaration.

The final preparation boundary requires complete preparation status, successful
non-timeout builds, ordered build/preparation timestamps, and completion no
later than the declaration. It correctly accepts original build timestamps
copied into A/A; it does not require fictitious new A/A compilations or duplicate
build logs. The optional block-runner path/hash fields are all-or-none and bind
the exact saved runner bytes when supplied.

Per-job paths and recorded session identity must match the declared session
root and preparation lane. Recovery precedes qualification and collection.
Jobs and full collection/packing intervals cannot overlap, and block ordering
must exactly match norm-1, A/A-1 through norm-4, A/A-4. The final pack check
requires `status.completed_utc <= evidence.saved_utc <= status.packed_utc`, so
an accidentally early status timestamp cannot conceal later archive creation.

## Retain, revert and blocked meanings

The output semantics match the input contract:

- Invalid or incomplete raw/protocol evidence remains blocked and returns a
  nonzero auditor exit code.
- A completed valid raw experiment whose performance gates fail recommends
  revert, including when the external correctness index is missing or invalid.
- Passing performance gates plus a missing, incomplete, failing or improperly
  bound correctness index produce `blocked_missing_correctness_evidence`.
- Retain requires both passing performance gates and all required source-bound,
  hash-verified correctness records completed before the first block starts.

Exit code zero means the raw experiment audit completed successfully. It must
not be interpreted as retention: both revert and missing-correctness blocked
results can return zero. The caller must inspect `overall_decision`.

The normalized correctness index remains an explicitly documented summary of
external test/CI evidence. The auditor verifies its declared outcome, source
trees, completion boundary and artifact hashes; it does not execute the gates
or independently parse every external runner's log schema. Human/source review
must ensure those normalized records accurately describe the saved artifacts.

The complete archive/manifest/oracle path still needs its first end-to-end
exercise on this experiment's actual data. The synthetic tests do not claim to
replace that audit, and no old cohort was relabeled or replayed under these new
decision rules during this review.

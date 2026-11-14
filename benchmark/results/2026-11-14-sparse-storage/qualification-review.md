# Independent packed-factor physical qualification review

## Outcome

The frozen candidate `4325386e689566a903309accd66aca3ced1159f7` passes the
complete physical qualification and evidence-integrity audit. Baseline identity
is `d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`; qualification executes candidate
jobs only. All 36 requested jobs and all 108 operations are present, including
36 warmups and 72 measured operations. The independent physical oracle accepts
all 96 feasible operations and rejects all 12 deliberate contradictions.

There are zero missing operations, timeouts, nonzero process exits, parse-error
jobs, adapter exceptions, acceptance disagreements or qualification mismatches.
The audit's integrity and explicit experiment-contract findings are both empty.

## Verified experiment

The nine fixtures are canonical cell, axis rectangle, coincidence, contradictory
distance, a small three-cell ladder, the scaled 1e-6 ladder, 500- and
2,000-coordinate ladders, and coupled-500. Both 2D analytic and 3D autodiff engines
run cold and warm lifecycles. Each job has one warmup and two measured operations,
with a 30-second process deadline.

The preserved audit stack rechecks the intended commits and source trees,
frozen source and dependency archives, compiler/build/output identities, raw
requests and native outputs, saved checked records, sequential process inventory,
operation completeness and terminal manifests. It recomputes physical acceptance
from coordinates rather than trusting solver success or solver residuals.
Both prepared executable bytes are present and match their recorded hashes.
The supplementary `preparation-independent-check.json` binds every archived
tracked input directly to its Git blob: 183 baseline files and 184 candidate
files match byte for byte. It also checks the current SDK and both AOT binary
hashes, archive inventories, and equality of the paired package/adapter inputs.

Dart is 3.14.0 stable, executable SHA-256
`6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b`.
Source/library/test identities and all detailed checks are retained in
`qualification-audit.json` and the frozen preparation manifest.

## Interpretation and reproducibility

This is a correctness qualification. Full validation ran concurrently elsewhere
while these operations were collected, so their timestamps must not be used as a
controlled performance comparison. No before/after timing ratio is claimed.
The audit itself ran on CPU 8 and executed no Dart solver.

Replay with the preserved `audit_ordering_followup.py` wrapper, both exact source
commits, the nine requested fixtures, both engines/modes, candidate-only variants,
one round, one warmup, two samples, and `--require-complete --require-qualification`.
The expected result is `evidence_consistent: true`, `qualification_passed: true`,
and empty integrity/contract finding lists. Real-browser/platform tests and the
separate dense coupled convergence control are outside this qualification.

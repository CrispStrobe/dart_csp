# Packed sparse factor storage — 2026-11-14

## Baseline and authorized checkpoint workflow

This continuation starts from remote main
`d43a8b0fca74c6bc893d68ca6ec8190e74b423c9`, the completed exact-degree
ordering pass. The user requested further optimization and explicitly asked
for incremental saves to GitHub remote `main`. This plan, tested source,
measurement evidence and the final decision are saved in separate commits on
that branch. Existing experiments and their evidence remain in history.

## Candidate

Pack the sparse LDLT numeric factor columns into one invocation-owned
`Float64List`, replacing one typed buffer per column and its enclosing list.
Cache immutable column offsets alongside the existing symbolic shape and use
absolute positions in the existing factor-index maps. Numeric storage remains
bounded by `maxFactorEntries`; the extra immutable offsets are linear in the
column count. No cached numeric factors or shared mutable scratch are added.

The change must preserve exact ordering of assembly additions (including all
duplicate-column cross terms), divisions, Schur updates and triangular solves.
It must retain every nonfinite check, current cancellation polling location,
iteration accounting, structural work limit, public CSR mutation check and
reentrant-call isolation. New tests emphasize irregular factor-column lengths
and repeated/nested calls. This is a storage experiment, with no timing claim
until the frozen revisions have been compared.

## Measurement and retention

- Use Dart 3.14.0 stable and the canonical dependency lock from the previous
  pass; preserve exact compiler, source and build identities.
- Run focused sparse regressions, fatal-info analysis, the native suite and
  the existing Node JavaScript/WebAssembly correctness corpus.
- Prepare separate frozen baseline/candidate AOT adapters. Run the existing
  independent physical qualification before quoting solve timings.
- Measure cold/warm low-fill ladders at 500 and 2,000 coordinates, coupled-500,
  and below-threshold controls in three alternating process pairs. Run timed
  solver processes sequentially on one allowed CPU.
- Keep the coupled-2,000 convergence-limit control separate. An unsuccessful
  local solve must not be counted as a successful speedup or infeasibility
  proof.
- Compare the existing small-QR/CAD controls in JIT and AOT. Preserve raw
  samples, adverse results and process records incrementally with the result
  summaries. Independently review physical outcomes and timing calculations.
- Retain or revert the candidate explicitly after measurement. The earlier
  rejected QR, mesh, placement and numerical experiments are not reinstated.

Real-browser coverage and GitHub Actions results will be reported separately
from the local Node gates. This work does not publish a package release.

# Completing the interrupted optimization

## Durable starting point and reconciliation

The working branch is `perf/optimization-complete-2026-11-14`, recovered at
`6760a4d84b6bb67ed32fc9b1f6795a4a17a9a138`. The second local CG round was
successfully pushed before the previous conversation stopped. Its evidence
and the earlier rounds remain immutable historical cohorts.

All 42 remote branch heads and all ten pull-request heads were fetched.
All ten PRs are merged; none is open. Main at `46288eb` is already an ancestor.
Three remaining branch histories are incorporated in this reconciliation:

* `fa6a3f1`: restore missing sparse preparation and seven-round small-control
  evidence, audit tools, and the historical report section. Preserve the newer
  evidence and final sparse retention decision already on this branch.
* `748febd`: preserve ancestry without restoring the rejected QR experiment.
  Its independent CAD screen previously showed repeated regressions.
* `088df75`: preserve ancestry and focused validation without promoting the
  unmeasured argument-placeholder candidate. This repeats the mechanism
  previously evaluated at `aaca896` and reverted at `acc01d7`; the latest branch
  has no new timing evidence that reverses that decision.

Exact observed heads and integration decisions are saved in
`benchmark/results/2026-11-14-optimization-recovery/remote-reconciliation.json`.
This reconciliation does not change the production library or its tests.

## Bounded remaining work

The existing default-manifold candidate and provisional fused CG implementation
have saved passing native, Node JavaScript and Node WebAssembly gates. The
library and test tree hashes will be checked before reusing that evidence.
Recover the exact Dart 3.14.0 compiler and canonical dependency lock, and rebuild
the three frozen executable endpoints from their verified source archives.
Record both matching and differing executable hashes; do not claim that a
new binary is the saved one unless its hash agrees.

This is a new runtime session. Keep its observations separate from both earlier
incomplete timing cohorts, even if hardware and executable identities match.
Use the already declared four comparisons: packed baseline to CG, CG to default
manifold contraction, packed baseline to both, and the identical-baseline A/A
control. Run four balanced rounds of each, with the existing six fixtures
(five for A/A), two engines, cold/warm modes, eight warmups, 21 measured
operations, sequential processes, pinned CPU and 30-second process deadlines.
Finish compilation and correctness execution before collecting timings.

Every completed round is audited and packed, then pushed with an expected-head
check before the next starts. Preserve partial data on failure. All existing
geometry oracles, tolerances, resource limits, solver choices and callback
semantics remain the acceptance criteria.

The final independent audit must reconcile raw records, physical acceptance,
work/coordinate equality, timing percentiles, process order and A/A variation.
Report favorable and adverse rows. Controls reveal observed measurement
variation; they do not prove that an implementation regression is noise.
Make a separate explicit retain-or-revert decision for CG and default-manifold
contraction, run the required gates on the resulting source, update the handover,
and push the final source and conclusions to this branch.

The user requested incremental remote branch saves. No package release is part
of this work. A checkpoint is complete only after its remote ref is verified.

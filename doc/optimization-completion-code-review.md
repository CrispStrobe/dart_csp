# Independent source and harness review — 2026-11-14

## Default-manifold candidate

Reviewed source `e0d77a775714a4bd66b45a90e366ea68bc37db59` against
`eb8a9df4454fe17a83d97900b35bf4e607e291b2`. No production correctness
blocker was found. Only library-created private final Euclidean instances
use the shortcut; public/custom manifolds, retained callback output buffers,
products and quaternions retain their original path.

Column zero retains the complete multiplication/reduction, preserving rejection
of every nonfinite ambient derivative before any row entries are written.
Later direct additions preserve positive-zero normalization, scaling order and
finite checks. Preferences, cancellation boundaries and workspace ownership
are unchanged. The default object's exact runtime type changes, as documented.

The recording-backend expected matrices were independently recomputed.
Regressions exercise scaling, signed zero, dynamic custom maps, runtime-type
impersonation, retained manifold buffers, retained backend entries on failure,
overflow, AD, fork, cancellation and recovery. The review identified one test
error: cancellation rolls back the pending fixed target. That target is now
reapplied before testing recovery in `8f9630a`.

## Remote driver and workflow

Reviewed `8f9630a47166a17e1e7066344c36d469ea945f03` against the exact
paired-harness source. CLI flags, output schemas, qualification selections,
derived endpoint provenance, identical-binary A/A hashes, macOS affinity fallback,
portable test list and ordinary fast-forward evidence pushes are compatible.

One durability defect was identified: a nonzero collection command could raise
before packing its partial raw output. The completion driver now preserves
whatever output exists and checkpoints it before propagating that failure.
Candidate library/test tree hashes are checked between the tested and compiled
snapshots, so intervening evidence-only commits cannot obscure source identity.

The workflow checks out the triggering SHA, and only the newest source/script
revision in this branch proceeds. Evidence-only pushes do not trigger another
workflow. Complete and partial raw outputs remain in the always-upload artifact;
every completed collection is also packed into the branch.

These are independent read-only source reviews. Neither reviewer executed
tests or benchmarks, and neither report establishes a speedup or universal
nonregression. Actual execution status and retained-source decisions must come
from the new workflow evidence.

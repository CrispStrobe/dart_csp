# Independent review of CG residual-norm fusion

Reviewed the isolated candidate at
`/workspace/scratch/b51b355c4f64/cg_norm_candidate` against production source
`2596d1d1ab08b7ea2f60b50427ce161f1ebfc6d4`.

Candidate `lib/src/geometry/numeric.dart` SHA256:
`6e30e39dd5e62c332645291f72d6315f1422fd1c3ffd6887e9687075db37f761`.
Comparison of every library file found only that file changed, with no added
library files. Its sole change is the fused residual-norm calculation in the
CG x/r update loop, beginning at line 284. This review was read-only: no edits
to the candidate, tests, compilation, or timing were performed by the reviewer.

## Finding: no blocking source correctness issue

- The finite reduction preserves `geometryNorm`'s initial scale/sum, ascending
  component order, absolute-value/zero handling, comparison, operation
  grouping, and final square root. `r[i]` is read after its `Float64List`
  assignment, preserving the stored-value boundary.
- x/r writes retain their original per-index order. On the first nonfinite
  absolute residual, the implementation stores that value and completes every
  remaining x/r write in a separate suffix loop. It then leaves the outer
  loop. Later infinity/NaN entries cannot replace the first nonfinite result.
- Negative infinity still becomes positive infinity through `abs`. Zero
  residual norm remains positive zero. Overflow only in the final
  `scale * sqrt(sum)` still occurs after all updates and produces the same
  failure status, iteration count, and complete step.
- No callback or Jacobian dispatch boundary is crossed inside either version
  of the update loop. All `multiply`, `transposeMultiply`, `normalDiagonal`,
  and `shouldStop` calls remain in the same locations. Interleaving the scalar
  norm reduction with private-array writes does not expose a new synchronous
  user callback. Existing public subclasses continue to receive the same
  operations and arguments at the same boundaries.
- There are no new arrays, closures, shared buffers, backend changes, or work
  cap changes. Only local scalar norm state and an exceptional suffix loop
  were introduced. True-residual verification, correction/restart, and the
  final cap residual calculation remain unchanged.

Performance is not established by this review. A removed traversal can still
lose to extra loop pressure or code-generation differences; use the declared
frozen-pair comparison to make that decision.

## Test scope and maintenance

The three explicit norm tests have useful independent responsibilities:

1. Finite extremes, subnormal values, reordered magnitudes and signed zero:
   the fused result must match the separate public norm calculation, retain
   the expected step, and stop/converge at the expected callback boundary.
2. First-NaN/first-infinity precedence and full suffix writes: early exit
   would leave the last step/residual entry unfinished, which the fixture
   observes through a retained public Jacobian output buffer.
3. Finite residual entries whose final norm overflows: this distinguishes
   the final multiplication overflow from encountering a nonfinite element.

Keep the callback counts and retained-residual assertions when removing the
copied full-solver dependency. These are behavioral checks, and the public
norm is unchanged in this patch. Existing CG tests independently check the
original equations and cover cancellation, work caps and nested solves.

The full 648-case parity sweep is useful one-off evidence for exactly this
optimization: it checks bit-level outputs (classifying NaNs), method inputs,
callback traces, budgets, extreme scales, and caller-visible mutation. It is
not an independent mathematical oracle, and many Cartesian combinations do
not execute the changed loop at all. Half have a zero budget or cancel at the
first callback; other settings duplicate paths when the requested later poll
is never reached. Its copied 186-line solver/helper implementation would add
maintenance obligations unrelated to the small norm contract. The parent's
decision to preserve that sweep and frozen reference under benchmark evidence
while retaining only the three explicit tests is appropriate.

Neither the sweep's `converged > 0` nor `multipleIterations > 0` assertion
demonstrates that the true-residual correction/restart branch ran. Do not
describe it as exhaustive branch coverage. This is a nonblocking limitation
for the current local change: that branch is unchanged, and broadening tests
solely to fill it is not needed for this pass.

## Final persistent-test trim verified

The final `test/geometry_cg_norm_test.dart` is 167 lines, contains three direct
contract tests, and has SHA256
`fb830bb69c875d4b934c015dd4d9403acaf5bd2b85bd802cb20e5cfe34a6415a`.
It no longer imports the frozen solver, and
`test/support/cg_unfused_norm_reference.dart` is absent. The candidate numeric
source hash is unchanged. The trimmed tests retain explicit method schedules,
poll counts, finite bit/signed-zero checks, suffix step/residual writes, and a
direct first-nonfinite expectation independent of the copied solver. No
blocking adequacy issue found in the final trim. The owner, not this reviewer,
is executing its focused gates and the relocated differential evidence.

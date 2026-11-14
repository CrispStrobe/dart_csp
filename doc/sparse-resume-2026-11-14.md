# Sparse solver continuation — 2026-11-14

## Recovery boundary

The user requested continuation of the interrupted Dart CSP integration and
optimization, with incremental remote checkpoints and a tested final `main`.
At recovery, remote `main` is `135a6eed93b46ad7d40d0f5288686d2cd26ddd48`.
The latest complete saved integration is
`5c93ab09899cd43d394c857d218e3c0ff9ecb957`; PR #9's source branch is
`b22bb671e505ad818c46f1a69772973ead436dd4`.

The integration checkpoint contains the bounded LDLT backend, independent tests,
documentation, portable/browser corpus entries, a successful 36-job large-case
qualification and the first paired timing round. The later adaptive-policy
revisions described in the pasted conversation were not saved to any observed
remote branch. Their source and measurements must not be claimed as recovered.
The existing first-round archives remain unchanged.

All work in this continuation starts from the saved integration tree. Existing
branches and rejected experiments are retained. No history is rewritten.

## Completion plan

1. Audit the recovered numerical implementation and raw timing evidence.
2. Narrow automatic sparse-direct selection using measured structural cost;
   retain explicit caller control over the direct backend and exact original-
   equation residual verification.
3. Add independent regression coverage for the changed dispatch policy and
   public CSR mutation boundaries.
4. Run fresh paired, sequential AOT measurements against consolidated `main`,
   including below-threshold controls, the low-fill ladder and the coupled
   graph. Qualify large cases separately and preserve unsuccessful outcomes.
5. Verify formatting, fatal-info analysis, native tests, JavaScript and
   WebAssembly tests; distinguish real-browser execution and remote CI from
   compiled Node checks.
6. Save source, raw observations, validation and an updated handover remotely
   throughout, then integrate the qualified result into `main`.

## Source checkpoint and verification in progress

The adaptive backend now caps predicted Schur updates at the smaller of the
direct solver's hard numeric limit and `32 * rawNNZ`. A nullable public
`sparseNumericWorkPerNonzero` setting controls the heuristic; null retains only
the explicit hard limits. Effective limits participate in accepted-pattern
checks and declined-pattern cache keys. Multiplication saturates without
overflow. Direct calls to `SparseLdltGeometrySolver` retain their broad limits.

All 34 recovered sparse tests and 18 new independent policy/boundary tests pass.
Scoped fatal-info analysis passes. New regressions are included in both the
portable Node corpus and real-browser CI. The benchmark harness now propagates
terminal states into each variant's saved manifests; all 48 comparison Python
tests pass, including success, rejected warmup and interrupted-run metadata.

The [historical evidence review](sparse-resume-evidence-review.md) independently
reconciles all 396 saved qualification/timing operations and explains the
structural basis for the new cap. Those old measurements are not pooled with
fresh measurements. Full-source gates and new paired timings are still pending
at this checkpoint. No new performance claim is accepted yet.

Personal Context was unavailable; the pasted handoff, Git history and saved
repository evidence define the scope. Runtime setup uses officially verified
Dart 3.14.0 and Node 24.22.1. Chromium startup remains blocked by the environment's
process-singleton socket restriction before any page assertions.

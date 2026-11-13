# Main integration and continued CAD allocation work

Date: 2026-11-13. The user explicitly requested merging all existing work into
main, then continuing optimization with incremental remote preservation.

## Completed main integration

- PR #3 merged with its complete history as `b289538d732bdb9eb0ae55480c796fbe4c5a68db`.
- PR #4 merged with its complete history as `894a11d74dae312ca99578532b27cca0b51fd34f`.
- Main's resulting tree is byte-identical to audit checkpoint `7a7051a`.
- All five existing work-branch heads are ancestors of main: the original
  performance branch, audit branch, graph setup, solid benchmark and geometry
  fork branches. Prior PR #1/#2 changes were already on main.
- The main library is the validated `03c75b9` source: 1,758 native and 422
  tests each on Node JS/Wasm, fatal-info analysis and 207 formatted Dart files.
  GitHub accepted both ordinary merge operations. The current browser/platform
  CI jobs were queued; no queued check is counted as passed.

The earlier plan's no-merge boundary applied to that completed pass. The user's
new explicit merge instruction supersedes it. Branches and prior evidence are
retained, with no force-push or release tag.

## Selected optimization pass

Baseline: merged main `894a11d`. Working branch:
`perf/cad-solid-allocation-2026-11-13`.

1. **Rigid placement allocation.** Reduce temporary collections and repeated
   immutable-transform work in checked point placement. Preserve exact
   arithmetic order, conservative error bounds, scale/overflow rejection,
   exported geometry and all custom/public input validation contracts.
2. **Numerical scratch overhead.** Bind lazy scratch/typed arrays at existing
   first-use points in hot methods, and eliminate argument placeholder buffers
   that are replaced before callbacks. Preserve component laziness, fresh
   private writable storage, callback arguments, cancellation order, rank
   keys, physical validation and rollback. Keep separately reviewable source
   checkpoints for attribution.
3. **Evidence and retention decision.** Run focused correctness and independent
   reviews, then frozen native/JS/Wasm/static gates. Measure complete solid,
   placement, coupled/nonlinear, fork and graph operations against merged main.
   Run timing sequentially after correctness, retain every process/sample and
   reject candidates whose intended benefit is unsupported.
4. **Remote integration.** Push coherent source and evidence checkpoints to
   remote branches as work proceeds. Integrate verified retained changes into
   main through a PR, preserving the full history and a precise handover.

The prior report observed solid cold/angle regressions and adverse tails.
This pass targets concrete allocation work but does not assume those prior
regressions have one cause. The reference kernel remains a limited extrusion
and rigid-instance backend; no broader CAD capability is claimed.

## Checkpoints

| Stage | Status |
|---|---|
| PR #3/#4 and all existing branch work merged into main | Complete, main `894a11d` |
| Main integration record and optimization plan | Saved before implementation |
| Rigid placement candidate | Pending |
| Numerical scratch candidates | Pending |
| Frozen correctness and paired evidence | Pending |
| Verified follow-up integrated into main | Pending |

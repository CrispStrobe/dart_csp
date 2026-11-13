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
3. **Mesh link traversal.** A further concrete cold-solid allocation was found
   in complete mesh validation: degree-two vertex links use a temporary set
   and list for reachability. Walk the bounded cycle directly after the same
   degree gate, preserving disconnected/pinched-fan rejection, edge incidence,
   area arithmetic, custom point operators and positive-volume checks.
4. **Evidence and retention decision.** Run focused correctness and independent
   reviews, then frozen native/JS/Wasm/static gates. Measure complete solid,
   placement, coupled/nonlinear, fork and graph operations against merged main.
   Run timing sequentially after correctness, retain every process/sample and
   reject candidates whose intended benefit is unsupported.
5. **Remote integration.** Push coherent source and evidence checkpoints to
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
| Rigid placement candidate | `07dd51f`; 34 focused tests and independent review passed |
| Numerical scratch candidates | `aaca896` and `01f8f86` measured separately, both production changes rejected at `acc01d7`; regression retained |
| Mesh vertex-link traversal candidate | `73b6013`; 75 focused tests and independent review passed |
| Frozen correctness and paired evidence | Source `acc01d7` frozen; numerical screens (96 reports) saved; full gates in progress |
| Verified follow-up integrated into main | Pending |

## Numerical screen decision

Two independent three-round, JIT/AOT screens used four unchanged harnesses,
48 process reports and 28 summary rows each. All 8,400 raw samples and 4,800
aligned per-sample work records are retained, and independent reconciliation
found no source, sampling, percentile or physical-work mismatch.

- Placeholder removal (`894a11d` to `aaca896`) produced mixed evidence.
  Coupled AOT cold median improved 11.4%, but only one of the three paired
  processes improved. CAD JIT cold/retained medians worsened 21.6%/23.7%.
  Nonallocating controls also moved, limiting causal attribution.
- Local scratch binding (`aaca896` to `01f8f86`) worsened CAD JIT
  cold/retained medians 14.1%/24.5%, with regressions in every pair.
- Neither production candidate showed sufficient consistent benefit for
  retention. Both were merged into the integration history at `31b7c98`,
  then solver code was restored byte-for-byte to merged main at `acc01d7`.
  The new mixed-shape callback/fork isolation regression remains. This
  decision does not establish that either trial is universally slower.

The retained source has library tree
`ef99105a9d7787925ae245cf10adbd040df1ad62`; its production diff is limited to
checked placement and mesh vertex-link traversal. Numerical solver and graph
rows in the final comparison are unchanged controls.

Raw compressed reports, summaries and independent audits are in
`benchmark/results/2026-11-13-{placeholder,binding}-*`. Reproduce their
reconciliation with `tool/audit_cad_measurements.py`; gzip compression is
lossless, and hashes identify both stored and decompressed bytes.

# CSP correctness and performance audit — 2026-11-14

## Reconciled starting point

Baseline: `5dc27dc0b297683d47e94ade2b4ca22ed530d429` (`main`). All remote
branches and all five PR heads have been fetched before implementation. Every
one of the nine remote work-branch heads is an ancestor of main. PRs #3–#5
are included by ancestry; #1/#2 were squash merged as `ce10138`/`b87babf`.
GitHub reports all five PRs merged and none open. See the exact ref inventory
in `benchmark/results/2026-11-14-inventory.json`.

The previous main workflow, run `43516383046`, has now completed with all
17 active jobs successful, including the four-file real-browser smoke corpus,
Node JS/Wasm portability, and stable/beta/dev on Linux/macOS/Windows. The full
browser suite was skipped on that push; it remains a separate verification
scope. No skipped check is counted as passing.

## Work plan and acceptance

1. Audit discrete propagation/prepared sessions, geometric solver/feature-graph
   ownership, and solid/mesh validation independently. Reproduce concrete
   gaps before changing production behavior.
2. Add focused correctness regressions and repair confirmed gaps. Preserve
   sound domain pruning, conservative geometry checks, transactional rollback,
   callback isolation and cross-runtime behavior.
3. Investigate complete-operation CAD latency and allocations, with attention
   to the previously observed plate and linkage tail costs. Select bounded
   implementation changes; preserve unchanged physical work and validation.
   Do not restore the earlier rejected numerical scratch experiments.
4. Freeze source, run native/portable/static gates and independently review the
   diff. Compare identical harnesses against the reconciled baseline in fresh,
   sequential paired JIT/AOT processes. Retain raw samples and all regressions;
   distinguish timing observations from proven allocation/complexity changes.
5. Push small coherent checkpoints as work proceeds, including this plan
   before implementation, fixes, experiments and evidence. Merge verified
   retained work through a PR, retaining branch history and a current handover.

The user explicitly authorized bringing all work together and incremental
GitHub preservation. No history rewrite, branch deletion or release is needed.
The repository's existing experimental scope remains in effect.

## Progress

- Initial reconciliation and work plan: complete; source audit starting.
- Findings, measurements, source checkpoints and final gates: pending.

## Confirmed and repaired findings

| Area | Reproduced gap | Repair |
|---|---|---|
| Incremental assumptions | Caller Set/List mutation changed the meaning of an active assumption ID | Copy posting inputs, retain custom Set equality, document callback-state lifetime |
| Compact ranges | Integer classification enumerated the entire range before posting an assumption | Constant-time recognition of the final integer range type |
| Bound clauses | JavaScript rounding at 2^53 made a bound and its supposed complement overlap | Use adjacent representable integers; reject unrepresentable native complements explicitly |
| Geometric compilation | Mutable declaration getters changed tolerances/layout after graph compilation | Capture and revalidate public declaration metadata while retaining private AD dispatch |
| CAD document | Caller parameter/reference mutation invalidated retained outputs or obligations | Capture initial parameter/revision maps and private semantic-reference declarations |
| Empty CAD graph | A missing mandatory reference was ignored by the first no-op return | Validate obligations before initial success |
| Reference extrusion | Changing profile getters yielded inconsistent validated analytic geometry | Capture scalar profile declarations once before validation/construction |

Independent review found two compatibility details in initial candidates:
custom set equality must survive copying, and invalid dimensions must reject
before enumerating holes. Both corrections and their regressions are preserved
as separate remote commits. The mesh allocation candidate preserves custom
point operations, validation issue ordering and manifold/volume checks.

The current PR is [#6](https://github.com/CrispStrobe/dart_csp/pull/6). Source
checkpoints live on the audit branch and three independent fix branches.
The full source gates and performance retention decision remain pending.

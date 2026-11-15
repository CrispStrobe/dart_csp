# Completed bounded optimization comparison

## Completion record

All 16 declared blocks are complete across the two recorded sessions.
Independent audits reconcile 736 processes, 15,456 measured operations,
5,888 warmups and 10,672 equal paired non-timing records. Every physical
record is accepted and every archived run file restores byte-exactly.

Retain CG fusion and remove the default-manifold contraction specialization,
keeping all behavioral regressions. The final library is identical to measured
CG source `ad8d237` and current main `46288eb`. Source decision `6d0c0bc` and
complete final correctness evidence `9b3c4d1` are remotely preserved.
All 1,891 native, 570 Node JS, 570 Node Wasm, 51 solver-harness and 27 tooling
tests pass, with clean analysis and formatting.

Read [the final results and tradeoffs](../../../doc/optimization-final-results-2026-11-14.md),
`retention-decision.json`, the separate `saved-session-audit.md` and
`resumed-session-audit.md` reports, and `validation/validation-manifest.json`.
Full audit JSON is stored losslessly as the matching `.json.gz` files.
The protocol reports remain explicitly partial selections: completion across
two sessions is not a full single-session pass. No further timing is pending.

## Recorded recovery and protocol

Recovered branch: `perf/optimization-complete-2026-11-14` at
`120b6177bd542910dcd4bab82bc0b9920e9fbf2e`. All 42 current branch heads and
all ten original PR heads were fetched and verified as ancestors. No new
production integration is needed. See `remote-ref-audit.json` and `recovery.json`.

## Explicit session boundary

The preceding session, `d1244c09828b`, saved 13 of the 16 declared blocks:
CG rounds 1–4 and identity, combined, and A/A rounds 1–3. Its raw evidence,
recovery declaration, and progress record remain unchanged in
`../2026-11-14-optimization-final/`.

This workspace is session `b51b355c4f64`. Finish only the three missing blocks,
in their declared order: `identity-round4`, `combined-round4`, `aa-round4`.
There is no replacement cohort, favorable sample selection, or extension of
the original four-round budget. Preserve failed or partial observations too.

The exact saved executable and preparation bytes are restored and verified;
there is no recompilation for timing. Fixture, representation, lifecycle,
warmup/sample counts, CPU affinity, 30-second process deadlines, process order,
physical tolerances, and work/coordinate checks remain unchanged.

The session break is a material limitation. Analyze all four CG rounds in their
original session. Analyze the original three rounds of identity, combined, and
A/A separately from the resumed fourth-round sensitivity check. Do not claim
that the 16 blocks form one uninterrupted environment or that A/A proves an
adverse candidate result is noise. The full original single-session audit must
remain incomplete; explicit subset audits can verify each recorded session.

## Completion and saving

Push this recovery declaration before timed collection. Save each completed
block, its raw evidence, status, and summary to the remote branch, verify the
remote head, then start the next block. Compilation, tests, restoration,
packing, and audits stay outside solver collection.

Make explicit retain/revert decisions for CG fusion and default-manifold
contraction. If intended-path benefit remains unsubstantiated, reject that
candidate rather than restart measurement. Retain regression tests and all
evidence. The resulting production source must have matching native and
portable correctness evidence. Update the final report and handover, and push
the final source and conclusions. No release or main-branch merge is included.

# Finish the interrupted bounded comparison

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

# CG residual-norm fusion experiment — 2026-11-15

The interrupted experiment is closed to further timing. The provisional
candidate `50fc483` is conservatively reverted to baseline `49234b3` because
only five of the eight mandatory blocks survived the original session.
The restart repair, new numeric tests and every saved measurement remain.
Fresh retained-source validation and partial evidence replay are in progress;
see `closure/decision.md` and `progress.json`.

This separate experiment compared baseline `49234b3` with candidate
`50fc483`. The candidate fuses the existing stable residual norm into the CG
iterate-update loop. The prior sixteen-block CG/manifold experiment is complete
and is not reopened. Read `progress.json` for the current collection state and
`protocol.md` / `declaration.json` for the fixed matrix and decision rules.

## Source and correctness

The only production-file difference is the norm-update block in
`lib/src/geometry/numeric.dart`. The library trees are
`16214e4755dbd7df711bfd4901b126990b11ab45` before and
`c6b90bc3c7d14dc529a188a9b10fd3a4102d4cb1` after. Three new direct contract
tests cover scaled finite norms, first-nonfinite precedence, completed suffix
writes, callback schedules and finite-entry norm overflow. Existing independent
original-equation, cancellation and nested-solve tests remain in place.

`source-validation.tar.gz` preserves a one-off 648-configuration comparison
against the frozen baseline implementation. It checks compatibility and public
method/callback inputs; it is not an independent mathematical oracle or a claim
of exhaustive CG branch coverage. The copied baseline is outside the permanent
unit-test tree. `source-review.md` records the independent code review.

The candidate passes formatting, strict analysis, 12 focused tests, all 1,895
native tests, 578 Node JavaScript tests, 578 Node WebAssembly tests, 51 solver
harness tests and 27 tooling tests. Source inputs and the canonical dependency
lock remain unchanged through validation. Results, complete logs and hashes
are under `validation/`; the source-bound browser gate is recorded separately
in `validation-index.json`. A complete passing index is required before timing.

Both frozen endpoints pass physical qualification: 72 processes and 216 raw
operations, including 24 expected contradictory rejections. Independent replay
accepts the 192 feasible operations and finds all 108 paired non-timing records
identical. Qualification is excluded from the performance decision.

## Frozen inputs and evidence

The original preparation is preserved by `prepared-evidence.json` and its twelve
archive parts. It contains both executables, exact source archives, manifests,
compiler output and harness inputs. Both A/A labels reuse the actual baseline
executable bytes. All 28 preparation files were restored and compared byte for
byte before timing; see `prepared-restore-audit.json`. The runtime is pinned to
Dart 3.14.0 and the same dependency lock as the completed prior pass.

The first independent qualification audit exposed a checker schema error: the
runner supplies both the executable and its request-file path. Before any
measured block, the checker was corrected to require and verify that second
argument. `audit-amendment.md` preserves the original declaration, recovery
record, checker, exact patch and correction timestamp. Production inputs and
every experimental decision rule were held fixed. The qualification was not
repeated, and its original status retains its original hashes.

## Collection and decision

The eight-block order is `norm-round1`, `aa-round1`, `norm-round2`, `aa-round2`,
`norm-round3`, `aa-round3`, `norm-round4`, `aa-round4`. Every block uses the same
four fixtures, two engines and cold/warm modes, with 8 warmups and 21 measured
operations per process. There are 256 processes, 5,376 measured operations and
2,048 warmups if the declared cohort completes.

The primary endpoint is the 3D warm Laman-500 complete-operation p50. Retention
requires at least 5% median paired improvement, improvement in both process
orders and at least three of four pairs, a stable same-executable control, and
all adverse-workload/tail/correctness gates. Process pairs have equal weight.
No additional round, replacement cohort, pooled session or A/A subtraction is
allowed to rescue an uncertain result. Each completed block is pushed and its
remote ref verified before the next starts.

## Replay and recovery

Restore frozen inputs with:

```sh
python tool/pack_optimization_evidence.py restore \
  benchmark/results/2026-11-15-cg-norm-fusion/prepared-evidence.json \
  /ABSOLUTE/REPLAY/prepared
chmod +x /ABSOLUTE/REPLAY/prepared/prepared-*/before/dart-adapter \
  /ABSOLUTE/REPLAY/prepared/prepared-*/after/dart-adapter
```

Restore each recorded block using its `NAME-evidence.json` and a new destination
`/ABSOLUTE/REPLAY/runs/NAME`; restore qualification outside `runs/`. The exact
transport verifies every byte. The auditor accepts replay paths while preserving
the original session/path identities in the records. Run `audit_norm_fusion.py`
with the explicit inputs documented in `norm-audit-inputs.md` and inspect
`overall_decision`; exit zero alone also permits a valid rejection.

For an in-session continuation, `run_block.py` enforces fixed options, immutable
outputs, the preceding verified remote checkpoint and complete correctness
gates. A new session must not append timing to a partially measured cohort.
Preserve the partial evidence and make a conservative decision. Frozen bytes
and source inputs allow the completed evidence to be recovered without builds.

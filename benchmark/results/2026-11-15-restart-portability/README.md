# Restart portability follow-up — 2026-11-15

Status: portable test repair passes all five tests on VM, Node JavaScript and
Node WebAssembly; GitHub real-browser confirmation pending.

The prior CG optimization/evidence pass is complete at `5579ae3`. Its sixteen
blocks will not be restarted or pooled with new experiments. Current remote
branch and PR heads were fetched and checked: all 42 branch heads and all
11 PR heads are ancestors of that checkpoint. PR #11 passed its exact-head
CI; the later scheduled main build failed only the full-browser suite.

## Concrete failure

`test/lcg/restart_test.dart` assumes selected random SAT problems both trigger
a restart at the default 100-conflict budget and require fewer decisions with
restarts enabled. Seed 1 solves on dart2js without a restart, failing that
assumption. The preceding SAT-result assertion passed. The full native test
file passes; Node/dart2js reproduces the browser failure. Raw baseline logs
and source/runtime provenance are saved alongside the remote CI audit.

## Completion criteria

1. Distinguish workload generation from search-order differences where possible.
2. Preserve meaningful restart, phase-saving and learned-clause retention checks
   using small explicit fixtures and an independent clause oracle. Do not change
   production search semantics to force a benchmark win.
3. Cover the repaired file in per-PR native, Node JavaScript/WebAssembly and
   real-browser gates. Save source and verification checkpoints incrementally.
4. Keep performance observations separate from correctness guarantees. Any new
   CG experiment requires its own predeclared protocol and retention decision.

## Diagnosis and repair

The three selected formulas have identical clause hashes on VM and JavaScript.
All twelve diagnostic solutions satisfy every original clause. Boolean domains
use bitsets on VM/Wasm and intervals on dart2js; their eager versus lazy shuffle
paths can select opposite first values for the same RNG draw. This explains why
a shared seed cannot guarantee matching search counts or a restart trigger.
`diagnostic-summary.json` and the raw JSONL files preserve the clause identities,
first values and solve counters. These runs are diagnostics, not timing evidence.

The replacement uses two explicit three-variable formulas with a one-conflict
restart budget and no random seed. Public decision snapshots prove that saved
phase and VSIDS activity survive the root rollback, and that a learned clause
unit-propagates after restart. Exhaustive truth tables independently check all
learned clauses against every original solution. The random SAT parity sweep
now also checks each returned assignment against every original clause. The
existing Sudoku soundness sweep is preserved.

The restart file is now included in per-PR real-browser and Node portable gates.
README/LCG documentation and benchmark comments distinguish observed search
improvements from portable guarantees. The production library is unchanged.

Local real-browser attempts are retained separately: the default `google-chrome`
command is absent, and explicitly selecting the installed `/usr/bin/chromium`
fails before loading tests because its process socket is denied by this
workspace. These are not passing browser gates. GitHub CI provides the actual
browser check.

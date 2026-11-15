# Restart portability follow-up — 2026-11-15

Status: baseline saved; investigating and repairing the full-browser failure.

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

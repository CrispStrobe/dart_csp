# Portable restart regression repair

## Scope and cause

Only `test/lcg/restart_test.dart` was edited in the shared repository. No
production library file, solver option default, RNG behavior, or Git ref was
changed by this agent. The parent owns the accompanying CI/documentation work,
cross-runtime diagnostics, and remote checkpoints.

The failing gate had required seed-specific restart/performance behavior on a
random SAT instance. Its SAT assertion passed, but seed 1 fired no restarts in
dart2js. A concrete runtime-dependent search-order mechanism exists in the
production code: Boolean domains use `_BitsetRep` on native/Wasm and
`_IntervalRep` on dart2js. With no informative LCV constraints, the first path
uses eager list shuffling and the second uses lazy interval shuffling. Given
the same first `nextInt(2) = k`, an eager shuffle of `[0, 1]` yields `1 - k`
first, while the lazy interval algorithm yields `k` first. Consequently,
identical fixtures and RNG streams can legitimately take different search
paths. The parent's diagnostic independently confirmed identical generated
CNFs and valid assignments on both backends. Historical work-reduction
observations should remain benchmark evidence, not unconditional portable
correctness requirements.

## Replacement coverage

The two existing Sudoku tests were preserved. Random-SAT verdict parity still
uses eight seeds and compares plain solving with LCG/restarts, but now both
SAT assignments must contain every variable, use a domain value, and satisfy
every original signed clause. Returning a nonempty map is no longer enough.

Two tiny fixed fixtures replace the heavy-tail performance gate. Neither
passes a random seed, so neither relies on backend-specific shuffling.

1. `(x OR y OR z) AND (y OR NOT z)`, with VSIDS enabled and restart scale 1,
   forces a conflict after decisions `x=0,y=0`. The public callback observes
   the first post-restart decision `y=1`, while x and z have both been restored
   to `[0,1]`. This checks root rollback, retained activity, and saved-phase
   use. It requires exactly one restart and one learned clause.
2. `(x OR y OR z) AND (x OR y OR NOT z)`, with VSIDS disabled and restart
   scale 1, learns `x OR y`. After restart the next decision is x=0; the
   retained clause must then propagate y=1 before the next z decision.
   Exactly four public decision snapshots are required. Deleting the learned
   clause would require a fifth snapshot for deciding y again.

Each returned assignment is checked against the source CNF. An independent
eight-assignment truth-table enumeration finds all original solutions and
requires every reported learned clause to retain every one of those
solutions. Learned atoms must name a fixture variable and cannot be synthetic
SCC bridge atoms. The tests use only public APIs and snapshots.

## Validation on the final test file

Final SHA256:
`e5634a1e959a5a43f33b5d1269c884aee24a7c95a50483b8e694122366f05bb6`.

The compiler is the pinned Dart 3.14.0 executable with SHA256
`6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b`.
The canonical lock hash is
`a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a`.
The production library tree remained
`16214e4755dbd7df711bfd4901b126990b11ab45`.

All commands ran from the repository root with runtime-local `PUB_CACHE`,
`TMPDIR`, `XDG_CONFIG_HOME`, `DART_SUPPRESS_ANALYTICS=true`, and `CI=true`.
The focused process timeout was 180 seconds per gate; none timed out.

| Command after pinned `dart` | Result | Elapsed |
| --- | --- | --- |
| `analyze --fatal-infos test/lcg/restart_test.dart` | Clean, exit 0 | 1.73 s |
| `test --reporter expanded test/lcg/restart_test.dart` | 5 passed, exit 0 | 4.18 s |
| `test --reporter expanded --platform node --compiler dart2js test/lcg/restart_test.dart` | 5 passed, exit 0 | 17.02 s |
| `test --reporter expanded --platform node --compiler dart2wasm test/lcg/restart_test.dart` | 5 passed, exit 0 | 9.14 s |

Full final logs, commands, start/completion times and SHA256 values are under
`source_review/restart-fixed-final/`. `manifest.json` records the focused
gates and confirms its source inputs and lock did not change while running;
`analyze.json` records the clean analyzer invocation. The earlier
`restart-fixed-initial/` logs intentionally remain separate: all three runtime
gates passed, then the analyzer reported one style info. The final source
replaces a conditional expression with a list if-element in the random-CNF
builder, retaining the same single RNG call and generated literal per entry.

## Isolated mutation evidence

Four minimal package copies were constructed from exact source checkpoint
`2596d1d1ab08b7ea2f60b50427ce161f1ebfc6d4`, using `git archive` read-only.
Only the copied solver source was mutated. The shared production files were
verified unchanged. Each invocation selected only the two fixed restart tests
using `--name 'restart retained search state'` on the native VM.

| Isolated implementation | Expected observation | Actual result |
| --- | --- | --- |
| Unmodified control | Both fixed fixtures pass | 2 passed, exit 0 |
| Ignore saved phases in the iterative value chooser | Phase fixture fails | Expected `{y: 1}`, observed `{y: 0}`, exit 1 |
| Clear variable activity immediately after root restart rollback | Activity fixture fails | Expected `{y: 1}`, observed `{x: 0}`, exit 1 |
| Remove learned clauses from constraints, adjacency, and watched-clause indexes immediately after restart rollback | Retention fixture fails | Expected 4 decision snapshots, observed 5, exit 1 |

Each mutation left the other fixed fixture passing. No probe failed at load,
compile, or timeout; each failed at the intended semantic assertion. The
learned-clause mutation retains phases and activity, and its extra snapshot is
the redundant y=1 decision that propagation should have avoided.

These probes used test SHA256
`82ced13064845f4b84481c68132ce5a7bb63a9a12d44f99aebccefb3d8215a4b`, before the
unrelated random-builder lint correction. The selected fixed fixture code is
identical to the final test file. The exact probe source is retained as
`restart-mutations/test-input.dart` for reproducibility. The source base, test
hash, per-variant solver hashes and complete mutation diffs are recorded in
`restart-mutations/mutations.json`; separate `.patch` files and
`*-logs/{manifest.json,vm.log}` preserve each result. `results.json` captures
the expected successful control and three failing variants.

To preserve the concise mutation evidence, copy that manifest, the test input,
patch files, result file, and four log directories. The full isolated package
directories contain regenerable dependencies/build outputs and need not be
added to the repository. `prepare_restart_mutations.py` and
`run_restart_checks.py` show the isolated preparation and bounded invocation.

No full-suite claim is made here. The parent owns the final full native and
expanded portable validation boundary after the next optimization decision.

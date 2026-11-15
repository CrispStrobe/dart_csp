# Paired pure-Dart backend experiments

`paired_dart_backends.py` compares two committed library snapshots through
identical copies of the existing Dart adapter and common physical oracle.
It has separate preparation and execution stages. Preparation compiles both
AOT hosts; run mode never compiles or installs dependencies during measurements.
No FFI backend is injected by this harness.

## Prepare frozen source and executables

Create separate before/after Git worktrees at the intended commits, run the
normal package setup in each, and make sure their source/test changes are
committed. The package configuration must resolve `dart_csp` to its own worktree.
The adapter entry/core, `pubspec.yaml` and resolved `pubspec.lock` must be
byte-identical between revisions. Keep output directories outside the source
worktrees and inherit the intended `PUB_CACHE` and writable `TMPDIR`.

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py prepare \
  --before /path/to/before-worktree \
  --after /path/to/after-worktree \
  --dart /path/to/dart-sdk/bin/dart \
  --out /path/to/new/prepared-adapters
```

The preparation manifest records Git commit/library/test trees, actual source
file hashes, package inputs, compiler version and executable hash, exact compile
commands/output, and both generated AOT hashes. Each variant has a source archive
containing the exact library/test/adapter/package bytes. The shared Python harness
is copied and hashed separately. Source bytes are checked again after each build.
An incomplete or failed preparation cannot be run.

Execution checks the AOT and source-archive hashes before and after every job,
and requires the current and preserved Python harness bytes to match preparation.
It runs the frozen executables even if live worktrees later acquire documentation
changes. The recorded source archive identifies what was actually compiled.

## Qualify the candidate before timing

Use `--variants after --purpose qualification` for a correctness-only run.
The gate requires every requested operation, including warmups, to match the
fixture's constructed feasibility. Adapter exceptions, process timeouts and
incomplete output fail qualification. Solver timestamps remain in raw output
for diagnostics; they are not a controlled performance comparison.

For the planned sparse-backend experiment, smoke tests plus the 500/2,000-coordinate
ladders and the 500-coordinate coupled framework can be selected in one bounded run:

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared /path/to/prepared-adapters --variants after \
  --purpose qualification --suites smoke,confirm,coupled \
  --fixtures canonical_cell,axis_rectangle,coincidence,contradictory_distance,ladder_3_components_1,ladder_1_components_1_scale_1e-06,ladder_125_components_1,ladder_500_components_1,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 1 --warmups 1 --samples 2 --timeout 20 \
  --out /path/to/new/candidate-qualification
```

An explicitly bounded fallback case, such as `laman_free_2000`, belongs in a
separate output directory so its expected risk of rejection/deadline remains
visible. A failed local solve is not a certificate of geometric infeasibility.

## Controlled comparison

After all builds, tests and other CPU-heavy work have stopped, run three
alternating process pairs for the two 100/500-coordinate families:

```sh
python3 benchmark/solver_comparison/paired_dart_backends.py run \
  --prepared /path/to/prepared-adapters --suites confirm,coupled \
  --fixtures ladder_25_components_1,ladder_125_components_1,laman_free_100,laman_free_500 \
  --engines dart_2d_analytic,dart_3d_ad --modes cold,warm \
  --rounds 3 --warmups 2 --samples 7 --timeout 20 \
  --out /path/to/new/paired-comparison
```

For each fixture/mode/engine, the revision order reverses in the next round.
Only one solver process runs at a time. The same allowed CPU is selected for
each child by default; `--cpu none` explicitly disables pinning. Thread
environment controls match the existing runner. The timeout includes process
startup, all warmups and all measured operations.

To save progress remotely between rounds, run each block into a separate new
directory with `--rounds 1 --start-round 0`, then `--rounds 1 --start-round 1`,
and so on, keeping the prepared artifacts and all fixture/engine/mode selections
identical. `--start-round` is a nonnegative, zero-based global offset; its default
is zero. Job names and recorded rounds remain one-based, so the second block
uses `r2` and reverses the first block's process order. The manifest records the
offset and the number of rounds in that block. Finish any packing, Git commits
and remote saves before starting the next measurement block. This continues the
round schedule in new directories; it does not overwrite or automatically resume
an interrupted output directory.

The preserved historical screening suggests 500-coordinate stock operations are
roughly 55–186 ms in the relevant Dart lanes, making this a bounded first
comparison. The historical 2,000-coordinate rejected operations took roughly
4–7 seconds each. Keep those in separate short reliability cohorts, preserve
baseline failure, and do not compute successful-solve speed ratios from it.
These historical costs size the experiment; they are not a claim about a new
candidate or another machine.

## Files, checkpoints and interpretation

Every operation job uses `run.run_job` and retains:

- the exact compressed request and unmodified native stdout;
- stderr, exit code, deadline status and process wall time;
- the independent checked records, including all available warmups;
- command hash, start/completion timestamps and per-job summary.

The top manifest and per-variant summaries are written atomically before each
job starts and immediately after it completes. `in_progress` identifies the
last started job if collection is interrupted. The source and executable
checks occur outside each solver's operation timer. Existing output directories
are refused, so new runs cannot overwrite prior evidence.

Each revision receives its own standard `analyze.py` report. `comparison.json`
joins corresponding groups and publishes an after/before p50 or p95 ratio only
if both complete groups are eligible under the existing raw-evidence and physical
acceptance rules. The physical-request hash is checked across each pair.
Timeouts, rejected geometry and partial output remain in counts and raw files;
they never become successful latency ratios. Process percentiles use the upper
order statistic; aggregate values are medians of process percentiles, not pooled
sample percentiles. Seven samples per process give descriptive screening tails,
not a stable p95/p99 guarantee.

The analyzer uses each block's global round range when checking for missing
jobs. Historical manifests without `start_round` retain their original range
starting at round one. To aggregate completed blocks, pass their per-variant
directories together to `analyze.py`; keep before and after analyses separate
and retain each block's raw evidence and manifest.

Run mode with `--purpose measurement` returns failure for protocol/oracle
disagreement. Its successful collection exit does not mean every baseline
solver completed or accepted: inspect `qualification_passed`, each job's
`complete`, and qualified comparison groups. Qualification mode additionally
fails for physical rejection of a constructed feasible operation.

Once a complete run has finished, pack each variant using the existing tool:

```sh
python3 benchmark/solver_comparison/pack_results.py /path/to/run/before
python3 benchmark/solver_comparison/pack_results.py /path/to/run/after
```

Preserve the compact archives, summaries, original preparation/source manifests,
comparison/analysis, and their hashes in the remote checkpoint. Per-job files
already exist and can be checkpointed before packing if the run is interrupted.
The separate CAD and lower-level geometry control harnesses still need their
own coordinated measurements; this adapter comparison does not replace them.

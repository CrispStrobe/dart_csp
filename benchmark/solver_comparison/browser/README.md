# Browser qualification

This lane runs the shared fixtures in a real headless Chromium page. The three
Dart representations use `../dart_adapter_core.dart` unchanged. Each build
contains all three selectable representations: dart2js at `-O2`, or Dart's
WasmGC target. Playwright is the local test driver; it does not substitute Node
execution for browser execution.

`solvent_wasm` is a separate integration lane over the pinned Solvent core's
existing flat C ABI. It creates points and constraints directly, retains a
compiled `System` in warm mode, and copies numeric coordinates across Wasm
memory. It supplies no Solvent language document. The current C ABI does not
expose `SolveOpts.acceptance_tol`; that setting remains the upstream `1e-6`.
The physical oracle still uses the same requested absolute tolerance, but this
configuration difference means its timings must not be presented as a direct
browser/native speed ratio for the configured Rust-native Solvent adapter.

## Build

Run only while no controlled native timing job is active. Build artifacts stay
in the ignored `build/` directory.

```sh
DART_BIN=/path/to/dart bash benchmark/solver_comparison/browser/build.sh
bash benchmark/solver_comparison/browser/build_solvent.sh /path/to/pinned/geomsolver
```

The Solvent script requires the exact upstream revision
`64bad08b2f126f6be495f6647c180ae703e0963e`, installs `wasm32-unknown-unknown` if
needed, and builds `gcs-ffi` with the upstream lockfile. No numerical sources
are patched. The Dart Wasm bootstrap uses the generated `.mjs` module.

## Run

The runner needs Python Playwright and a local Chromium executable. It starts
a loopback-only static server for the run and shuts it down afterward. Run
browser and native lanes at separate times.

```sh
python benchmark/solver_comparison/browser/run_browser.py \
  --targets dart2js dart2wasm --suite portable \
  --warmups 3 --samples 10 --out /path/to/new/browser-results

python benchmark/solver_comparison/browser/run_browser.py \
  --targets solvent_wasm --suite portable \
  --warmups 3 --samples 10 --out /path/to/new/solvent-browser-results
```

The initial portable corpus contains canonical satisfiable and contradictory
controls, the same 20-coordinate and 100-coordinate coupled nonlinear ladders,
100 coordinates split into 25 disconnected components, and a small-unit
ladder. `--suite smoke`, `--fixtures`, `--engines`, and `--modes` select a smaller
qualification run without changing fixtures or solver settings. The selected
jobs are shuffled with a recorded deterministic seed and then run sequentially.

## Interpretation

- `elapsed_ns` retains each adapter's build/update-through-extraction boundary.
  It excludes JSON encoding and common physical acceptance. `solve_ns` records
  only the solver call. These fields use nanosecond units; browser timer
  resolution is measured and recorded separately.
- `browser_boundary_ns` clocks the full synchronous public operation from
  JavaScript, including acceptance, result encoding, and any Dart/JS or
  JS/Wasm boundary work. It excludes the Playwright transport and the host's
  result parsing. Subtracting medians is not a reliable isolated FFI cost.
- Module fetching, compilation, and instantiation are reported separately as
  `module_load_ms`; they are not included in repeated interaction latency.
- Every raw record is flushed before validation. The native runner's schema
  validator and Python physical oracle judge the returned coordinates, fixed
  anchors, branch signs, and the 3D representation's workplane `max_z`.
- Raw records, validated records, metadata, browser errors, artifacts' SHA-256
  hashes, source hashes, user agent, platform, browser version, and observed
  timer resolution remain available. A timeout preserves preceding records
  and marks the job incomplete.
- Headless compute results qualify compiler and binding portability. They do
  not establish rendering cost, mobile performance, Flutter interop overhead,
  or a full UI frame budget. Only one installed Chromium build is covered.

The browser entry point and wrapper must be built and exercised before any
portability or performance result is claimed. Merely generating these scripts
does not establish that either Wasm binary loads or solves successfully.

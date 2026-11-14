# Executable geometric solver comparison

The [assessment](../../doc/geometric-solver-comparison.md) is the original
source review. This directory contains actual pinned-engine adapters and a
shared physical checker. Read [PROTOCOL.md](PROTOCOL.md) before interpreting
timings. The protocol is a native numerical integration measurement; it does
not measure browser rendering or Dart-to-native FFI.

## Components

- `fixtures.py`: known-feasible triangulated distance ladders, disconnected
  cases, unit/offset cases, redundancy, canonical relations and a known conflict.
- `oracle.py`: independent checks of returned physical geometry and branches.
- `test_oracle.py`: positive constructed oracles and deliberately invalid outputs.
- `run.py`: sequential, CPU-pinned, rotating-order processes with immediate raw
  output preservation, per-process deadlines and independent post-run checking.
- `dart_adapter.dart` / `dart_adapter_core.dart`: production Dart engine with
  current 3D AD representation, prototype 2D AD, and prototype 2D analytic
  residuals. The production library is unchanged by these experiments.
- `rust_adapter/`: exact Git revisions of EZPZ and NeoSCAD; EZPZ solve-only and
  solve-plus-analysis are distinct engines.
- `solvent_adapter/`: exact Solvent source, numerical and decomposition replay
  variants, curve/branch/drag capability probes and a real native C ABI probe.
- `ceres_adapter/`: pinned source/dependencies, native residuals, physical
  stopping callback and configurable optimized C++ build.

## Build and run

Use Dart 3.14.0, Rust 1.100.0 and the dependency pins recorded by the adapters
to reproduce the initial experiment. Building newer tools is a separate run.
Install tools outside the repository, then:

```sh
dart pub get
mkdir -p build/solver_comparison
dart compile exe benchmark/solver_comparison/dart_adapter.dart -o build/solver_comparison/dart-adapter
cargo build --release --locked --manifest-path benchmark/solver_comparison/rust_adapter/Cargo.toml
cargo build --release --locked --manifest-path benchmark/solver_comparison/solvent_adapter/Cargo.toml
bash benchmark/solver_comparison/ceres_adapter/build.sh
python -m unittest discover -s benchmark/solver_comparison -p test_oracle.py -v
```

Create a local JSON commands map (argument arrays; no shell command strings):

```json
{
  "dart_3d_ad": ["build/solver_comparison/dart-adapter"],
  "dart_2d_ad": ["build/solver_comparison/dart-adapter"],
  "dart_2d_analytic": ["build/solver_comparison/dart-adapter"],
  "ezpz": ["benchmark/solver_comparison/rust_adapter/target/release/geometry-rust-adapter"],
  "ezpz_analysis": ["benchmark/solver_comparison/rust_adapter/target/release/geometry-rust-adapter"],
  "neoscad": ["benchmark/solver_comparison/rust_adapter/target/release/geometry-rust-adapter"],
  "solvent": ["benchmark/solver_comparison/solvent_adapter/target/release/solvent-adapter"],
  "solvent_replay": ["benchmark/solver_comparison/solvent_adapter/target/release/solvent-adapter"],
  "ceres": ["../upstream/toolchains/ceres-adapter-build/ceres_geometry_adapter"]
}
```

After all builds stop, run from repository root:

```sh
python benchmark/solver_comparison/run.py --commands build/solver_comparison/commands.json --suite screen --rounds 1 --warmups 1 --samples 3 --timeout 15 --out benchmark/results/solver-comparison-screen
```

Each process has its original compressed request/output, checked records,
stderr, and outcome summary. The root manifest includes exact source/binary
hashes, hardware, CPU affinity and execution order. Existing run directories
are never overwritten. Timeouts and incomplete jobs remain visible. A native
success/usable flag is not necessarily a hard-feasibility claim: specifically,
Ceres can converge to an infeasible least-squares compromise. The common
physical acceptance result is the comparable quantity.

Use `--fixtures`, `--engines`, `--modes`, and repeated rounds to confirm the
decision-relevant cases. A few samples can screen large failures but do not
support stable tail estimates. Do not pool distinct sketch families into one
speed score, drop failed operations, or present Node Wasm as real-browser data.

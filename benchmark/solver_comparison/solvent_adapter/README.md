# Solvent comparison adapter

This adapter pins `bmander/geomsolver` at
`64bad08b2f126f6be495f6647c180ae703e0963e` in exact Git dependencies and in the
committed Cargo lockfile. Cargo fetches the nested Rust packages directly; no
sibling checkout or hand-edited upstream source is used by the build. No production
solver code is changed. The numeric executable depends on `gcs-solve`, which
cannot depend on the Solvent language crate. No external Rust packages are
needed: the upstream JSON reader/writer is reused outside the timed region.

```sh
cargo build --locked --release --bin solvent-adapter --bin solvent-capabilities
target/release/solvent-adapter REQUEST.json
python verify_adapter.py
target/release/solvent-capabilities
cargo build --locked --release --features abi-probe --bin solvent-capabilities
python abi_probe.py
```

The shared request protocol supports `solvent` (compiled numerical System) and
`solvent_replay` (cached geometric decomposition and replay, with the upstream
numerical fallback). Both use upstream default DogLeg and recovery/retry policy.
`SolveOpts.tol` is `1e-14`; numeric hard-row acceptance uses the request tolerance.
These are upstream scaled residual criteria, not the common physical acceptance
test. The replay API receives the request tolerance to trigger fallback, but its
upstream success check is fixed at `1e-6`, and its numerical fallback uses
upstream defaults. Every operation records native reported success separately
from physical/orientation acceptance. There is no per-case option tuning.

For `cold`, every operation constructs the sketch and compiles from the supplied
fixture coordinates. For `warm`, the first operation constructs once; subsequent
operations update all distance dimensions and reuse the compiled System or plan
from the last physically accepted pose. Construction/update, compile, solve,
and coordinate extraction are included in `elapsed_ns`; request parsing, JSON
formatting, physical validation and host rollback are excluded. `solve_ns`
includes the selected upstream solving path and its default recoveries.

The adapter verifies distances, horizontal/vertical relations, Euclidean
coincidence, fixed point positions, and orientation signs after the timer. A
failed candidate is emitted for independent checking but does not become the
next warm seed. Coordinate/dimension changes and branch choices are rolled back
on rejection; the cache is discarded after an upstream panic. Upstream success
alone does not decide acceptance. `verify_adapter.py` checks agreement with the
independent oracle and separately reports known-feasible cases that were rejected.

`solvent-capabilities` reports executable probes for geometric decomposition,
branch persistence, spline contact, and interactive hard-feasibility and branch
behavior. `abi_probe.py` separately loads the native shared library with Python
ctypes and calls its exported C ABI to build a
sketch from records and solve/diagnose it without a language document; it is not
included in the core timing table.

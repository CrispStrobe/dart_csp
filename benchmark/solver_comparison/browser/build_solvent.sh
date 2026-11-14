#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  printf 'Usage: bash build_solvent.sh /path/to/pinned/geomsolver\n' >&2
  exit 2
fi
browser_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
solvent_source="$(cd -- "$1" && pwd)"
expected_revision=64bad08b2f126f6be495f6647c180ae703e0963e
actual_revision="$(git -C "$solvent_source" rev-parse HEAD)"
if [[ "$actual_revision" != "$expected_revision" ]]; then
  printf 'Unexpected Solvent source revision: %s\n' "$actual_revision" >&2
  exit 1
fi
mkdir -p "$browser_dir/build"
rustup target add wasm32-unknown-unknown
cargo build --locked --release --manifest-path "$solvent_source/rust/Cargo.toml" -p gcs-ffi --target wasm32-unknown-unknown --target-dir "$browser_dir/build/solvent-target"
cp "$browser_dir/build/solvent-target/wasm32-unknown-unknown/release/gcs.wasm" "$browser_dir/build/solvent.wasm"
rustc --version > "$browser_dir/build/rust_version.txt"
printf '%s\n' "$actual_revision" > "$browser_dir/build/solvent_revision.txt"

#!/usr/bin/env bash
set -euo pipefail
browser_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$browser_dir/../../.." && pwd)"
dart_bin="${DART_BIN:-dart}"
mkdir -p "$browser_dir/build"
cd "$repo_dir"
"$dart_bin" compile js -O2 benchmark/solver_comparison/browser/dart_entry.dart -o "$browser_dir/build/dart_adapter.js"
"$dart_bin" compile wasm benchmark/solver_comparison/browser/dart_entry.dart -o "$browser_dir/build/dart_adapter.wasm"
"$dart_bin" --version > "$browser_dir/build/dart_version.txt" 2>&1

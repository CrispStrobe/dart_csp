#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
eigen_source="${EIGEN_SOURCE_DIR:-$repo/../upstream/toolchains/eigen-src}"
expected_eigen="3147391d946bb4b6c68edd901f2add6ac1f31f8c"
cmake_bin="${CMAKE:-cmake}"
actual_eigen="$(git -C "$eigen_source" rev-parse HEAD)"
if [[ "$actual_eigen" != "$expected_eigen" ]]; then
  printf 'Expected Eigen %s, found %s\n' "$expected_eigen" "$actual_eigen" >&2
  exit 2
fi
if [[ -n "$(git -C "$eigen_source" status --porcelain --untracked-files=all)" ]]; then
  printf 'Eigen source checkout must be clean.\n' >&2
  exit 2
fi

task_tmp="${TMPDIR:-$here/build/tmp}"
mkdir -p "$task_tmp"
export TMPDIR="$task_tmp"
"$cmake_bin" -S "$here" -B "$here/build" -DCMAKE_BUILD_TYPE=Release -DEIGEN_SOURCE_DIR="$eigen_source"
"$cmake_bin" --build "$here/build" --parallel 2
cd "$repo"
"${DART:-dart}" compile exe "$here/native_host.dart" -o "$here/build/dart-sparse-adapter"

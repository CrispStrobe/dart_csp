#!/usr/bin/env bash
set -euo pipefail

adapter_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${adapter_dir}/../../.." && pwd)"
workspace_root="$(dirname "${repository_root}")"
toolchain_root="${CERES_BENCH_TOOLCHAINS:-${workspace_root}/upstream/toolchains}"
build_jobs="${CERES_BENCH_JOBS:-2}"
mkdir -p "${toolchain_root}/tmp"
export TMPDIR="${toolchain_root}/tmp"

cmake_bin="${toolchain_root}/cmake-py/cmake/data/bin/cmake"
if [[ ! -x "${cmake_bin}" ]]; then
  python3 -m pip install --no-cache-dir --target "${toolchain_root}/cmake-py" cmake==4.2.3
fi

checkout_pin() {
  local repository_url="$1"
  local destination="$2"
  local pinned_commit="$3"
  if [[ ! -d "${destination}/.git" ]]; then
    git init "${destination}"
    git -C "${destination}" remote add origin "${repository_url}"
    git -C "${destination}" fetch --depth 1 origin "${pinned_commit}"
    git -C "${destination}" checkout --detach "${pinned_commit}"
  fi
  if [[ "$(git -C "${destination}" rev-parse HEAD)" != "${pinned_commit}" ]]; then
    printf 'Unexpected source revision in %s\n' "${destination}" >&2
    exit 2
  fi
}

checkout_pin https://github.com/ceres-solver/ceres-solver.git \
  "${toolchain_root}/ceres-src" e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72
checkout_pin https://gitlab.com/libeigen/eigen.git \
  "${toolchain_root}/eigen-src" 3147391d946bb4b6c68edd901f2add6ac1f31f8c
checkout_pin https://github.com/nlohmann/json.git \
  "${toolchain_root}/json-src" 55f93686c01528224f448c19128836e7df245f72
git -C "${toolchain_root}/ceres-src" submodule update --init --depth 1 third_party/abseil-cpp
if [[ "$(git -C "${toolchain_root}/ceres-src/third_party/abseil-cpp" rev-parse HEAD)" \
      != 9ac7062b1860d895fb5a8cbf58c3e9ef8f674b5f ]]; then
  printf 'Unexpected Abseil revision\n' >&2
  exit 2
fi

"${cmake_bin}" -S "${toolchain_root}/eigen-src" -B "${toolchain_root}/eigen-build" \
  -DCMAKE_INSTALL_PREFIX="${toolchain_root}/eigen-install" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF
"${cmake_bin}" --install "${toolchain_root}/eigen-build"

"${cmake_bin}" -S "${toolchain_root}/ceres-src" -B "${toolchain_root}/ceres-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${toolchain_root}/ceres-install" \
  -DEigen3_DIR="${toolchain_root}/eigen-install/share/eigen3/cmake" \
  -DCMAKE_CXX_FLAGS=-DEIGEN_MPL2_ONLY \
  -DBUILD_TESTING=OFF -DBUILD_BENCHMARKS=OFF -DBUILD_EXAMPLES=OFF \
  -DBUILD_DOCUMENTATION=OFF -DBUILD_SHARED_LIBS=OFF \
  -DWITH_SUITESPARSE=OFF -DWITH_EIGENSPARSE=ON -DWITH_EIGENMETIS=OFF \
  -DWITH_LAPACK=OFF -DWITH_CUDA=OFF -DWITH_CUDSS=OFF \
  -DWITH_SCHUR_SPECIALIZATIONS=OFF
"${cmake_bin}" --build "${toolchain_root}/ceres-build" --parallel "${build_jobs}"
"${cmake_bin}" --install "${toolchain_root}/ceres-build"

"${cmake_bin}" -S "${adapter_dir}" -B "${toolchain_root}/ceres-adapter-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCeres_DIR="${toolchain_root}/ceres-install/lib/cmake/Ceres" \
  -DEigen3_DIR="${toolchain_root}/eigen-install/share/eigen3/cmake" \
  -Dabsl_DIR="${toolchain_root}/ceres-install/lib/cmake/absl" \
  -DNLOHMANN_JSON_INCLUDE_DIR="${toolchain_root}/json-src/single_include"
"${cmake_bin}" --build "${toolchain_root}/ceres-adapter-build" --parallel "${build_jobs}"
python3 "${adapter_dir}/write_manifest.py" --toolchains "${toolchain_root}"
printf '%s\n' "${toolchain_root}/ceres-adapter-build/ceres_geometry_adapter"

#!/usr/bin/env python3
"""Record both AOT hosts, the native library, and the actual Eigen source pin."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def output(command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()


def main():
    eigen = Path(os.environ.get("EIGEN_SOURCE_DIR", ROOT.parent / "upstream/toolchains/eigen-src"))
    expected = "3147391d946bb4b6c68edd901f2add6ac1f31f8c"
    actual = output(["git", "-C", str(eigen), "rev-parse", "HEAD"])
    dirty = output(["git", "-C", str(eigen), "status", "--porcelain", "--untracked-files=all"])
    if actual != expected or dirty:
        raise RuntimeError("Eigen source pin or clean-tree verification failed")
    artifacts = {
        "direct_host": HERE / "build/dart-sparse-adapter",
        "shared_library": HERE / "build/libdart_csp_sparse_step.so",
        "stock_control_host": ROOT / "build/solver_comparison/dart-adapter-control",
    }
    sources = list(HERE.glob("*.dart")) + list(HERE.glob("*.cpp")) + list(HERE.glob("*.py")) + [
        HERE / "CMakeLists.txt", HERE / "build.sh", HERE.parent / "dart_adapter_core.dart",
        HERE.parent / "dart_adapter.dart", ROOT / "lib/src/geometry/numeric.dart",
        ROOT / "lib/src/geometry/solver.dart",
    ]
    cache = {}
    for line in (HERE / "build/CMakeCache.txt").read_text().splitlines():
        if line.startswith(("CMAKE_BUILD_TYPE:", "CMAKE_CXX_COMPILER:", "CMAKE_CXX_FLAGS",
                            "EIGEN_SOURCE_DIR:")) and "=" in line:
            key, value = line.split("=", 1)
            cache[key] = value
    result = dict(schema_version=1, engine="dart_2d_analytic_sparse_direct",
                  stock_engine="dart_2d_analytic", eigen_revision=actual,
                  eigen_clean=True, eigen_mpl2_only=True,
                  repo_head=output(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
                  artifacts={name: dict(path=str(path), sha256=sha(path))
                             for name, path in artifacts.items()},
                  source_sha256={str(path.relative_to(ROOT)): sha(path) for path in sources},
                  compiler=output(["/usr/bin/c++", "--version"]),
                  dart=output([os.environ.get("DART", "dart"), "--version"]),
                  cmake=output([os.environ.get("CMAKE", "cmake"), "--version"]),
                  cmake_cache=cache,
                  configuration=dict(small_backend="unchanged_dense_qr", dense_parameter_limit=64,
                                     dense_entry_limit=262144, large_backend="Eigen_SimplicialLDLT_AMD",
                                     max_refinements=2, independent_dart_linear_residual=True,
                                     cold_symbolic_reuse=False, warm_symbolic_reuse=True,
                                     ffi_copies_and_validation_timed=True, production_lib_edited=False))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

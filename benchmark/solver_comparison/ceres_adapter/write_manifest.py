"""Record the actual local Ceres adapter build without running a benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess


def text(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchains', type=pathlib.Path, required=True)
    args = parser.parse_args()
    toolchains = args.toolchains.resolve()
    adapter = pathlib.Path(__file__).resolve().parent
    build = toolchains / 'ceres-adapter-build'
    binary = build / 'ceres_geometry_adapter'
    cache = dict(line.split('=', 1) for line in (build / 'CMakeCache.txt').read_text().splitlines()
                 if '=' in line and not line.startswith(('//', '#')))
    compiler = cache['CMAKE_CXX_COMPILER:FILEPATH']
    sources = {
        'ceres': toolchains / 'ceres-src',
        'eigen': toolchains / 'eigen-src',
        'abseil': toolchains / 'ceres-src/third_party/abseil-cpp',
        'json': toolchains / 'json-src',
    }
    manifest = {
        'schema_version': 1,
        'engine': 'ceres',
        'binary': str(binary),
        'binary_sha256': digest(binary),
        'source_sha256': {name: digest(adapter / name) for name in
                          ['main.cpp', 'CMakeLists.txt', 'build.sh', 'write_manifest.py']},
        'dependency_commits': {name: text(['git', '-C', str(path), 'rev-parse', 'HEAD'])
                               for name, path in sources.items()},
        'compiler': text([compiler, '--version']),
        'cmake': text([str(toolchains / 'cmake-py/cmake/data/bin/cmake'), '--version']),
        'adapter_cmake_cache': {key: value for key, value in cache.items()
                                if key.startswith(('CMAKE_BUILD_TYPE:', 'CMAKE_CXX_COMPILER:',
                                                   'CMAKE_CXX_FLAGS', 'Ceres_DIR:',
                                                   'Eigen3_DIR:', 'absl_DIR:',
                                                   'NLOHMANN_JSON_INCLUDE_DIR:'))},
        'configuration': {
            'build_type': 'Release', 'single_thread': True,
            'dense_qr_max_active_coordinates': 128,
            'large_linear_solver': 'SPARSE_NORMAL_CHOLESKY',
            'sparse_library': 'EIGEN_SPARSE',
            'suitesparse': False, 'lapack': False, 'cuda': False, 'eigen_metis': False,
            'schur_specializations': False, 'eigen_mpl2_only': True,
            'function_tolerance': 0, 'gradient_tolerance': 0, 'parameter_tolerance': 0,
            'physical_stopping_callback': True, 'default_max_iterations': 200,
        },
    }
    path = build / 'build-manifest.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(path)


if __name__ == '__main__':
    main()

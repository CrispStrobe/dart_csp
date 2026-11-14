"""Record the actual local Ceres adapter build without running a benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess

DEPENDENCY_PINS = {
    'ceres': ('ceres-src', 'e831bfef06ebd7a8daac7d76a1ca8bd33b47fa72'),
    'eigen': ('eigen-src', '3147391d946bb4b6c68edd901f2add6ac1f31f8c'),
    'abseil': ('ceres-src/third_party/abseil-cpp', '9ac7062b1860d895fb5a8cbf58c3e9ef8f674b5f'),
    'json': ('json-src', '55f93686c01528224f448c19128836e7df245f72'),
}


def text(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verified_source(path: pathlib.Path, expected: str) -> dict:
    """Bind a dependency pin to the actual clean source bytes used by the build."""
    command = ['git', '-C', str(path)]
    commit = text([*command, 'rev-parse', 'HEAD'])
    if commit != expected:
        raise ValueError(f'Unexpected dependency revision: {path}')
    status = text([*command, 'status', '--porcelain', '--untracked-files=all',
                   '--ignore-submodules=none', '--ignored=matching'])
    if status:
        raise ValueError(f'Dependency source tree must be clean: {path}')
    entries = subprocess.check_output([*command, 'ls-tree', '-r', '-z', 'HEAD']).split(b'\0')
    object_format = text([*command, 'rev-parse', '--show-object-format'])
    content_hash = hashlib.sha256()
    file_count = 0
    submodules = {}
    for entry in entries:
        if not entry:
            continue
        metadata, name = entry.split(b'\t', 1)
        mode, kind, object_id = metadata.split()
        source = path / os.fsdecode(name)
        if kind == b'commit':
            if text(['git', '-C', str(source), 'rev-parse', 'HEAD']) != object_id.decode():
                raise ValueError(f'Dependency submodule revision mismatch: {source}')
            submodules[os.fsdecode(name)] = object_id.decode()
            content_hash.update(entry + b'\0')
            continue
        data = os.fsencode(os.readlink(source)) if mode == b'120000' else source.read_bytes()
        # git status can omit a modified file marked assume-unchanged or
        # skip-worktree. Compare every source blob as well as the status gate.
        blob = hashlib.new(object_format)
        blob.update(b'blob ' + str(len(data)).encode() + b'\0')
        blob.update(data)
        if blob.hexdigest() != object_id.decode():
            raise ValueError(f'Dependency source bytes differ from pin: {source}')
        content_hash.update(name + b'\0' + mode + b'\0' + hashlib.sha256(data).digest())
        file_count += 1
    return dict(commit=commit, tree=text([*command, 'rev-parse', 'HEAD^{tree}']),
                clean=True, tracked_files=file_count,
                tracked_content_sha256=content_hash.hexdigest(), submodules=submodules)


def verified_dependencies(toolchains: pathlib.Path) -> dict:
    return {name: verified_source(toolchains / directory, commit)
            for name, (directory, commit) in DEPENDENCY_PINS.items()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchains', type=pathlib.Path, required=True)
    parser.add_argument('--verify-sources-only', action='store_true',
                        help='Require the pinned clean dependency bytes before compilation')
    args = parser.parse_args()
    toolchains = args.toolchains.resolve()
    dependencies = verified_dependencies(toolchains)
    if args.verify_sources_only:
        print('Verified pinned dependency source bytes for Ceres, Eigen, Abseil and JSON.')
        return
    adapter = pathlib.Path(__file__).resolve().parent
    build = toolchains / 'ceres-adapter-build'
    binary = build / 'ceres_geometry_adapter'
    cache = dict(line.split('=', 1) for line in (build / 'CMakeCache.txt').read_text().splitlines()
                 if '=' in line and not line.startswith(('//', '#')))
    compiler = cache['CMAKE_CXX_COMPILER:FILEPATH']
    manifest = {
        'schema_version': 1,
        'engine': 'ceres',
        'binary': str(binary),
        'binary_sha256': digest(binary),
        'source_sha256': {name: digest(adapter / name) for name in
                          ['main.cpp', 'CMakeLists.txt', 'build.sh', 'write_manifest.py']},
        'dependency_commits': {name: source['commit'] for name, source in dependencies.items()},
        'dependency_sources': dependencies,
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

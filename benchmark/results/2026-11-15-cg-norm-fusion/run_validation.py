#!/usr/bin/env python3
"""Run source-bound correctness gates before the new, separate timing cohort."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--native-tests', type=int, required=True)
    parser.add_argument('--portable-tests', type=int, required=True)
    parser.add_argument('--portable-files', type=int, required=True)
    args = parser.parse_args()
    root, runtime, out = (p.resolve() for p in
                          (args.source, args.runtime, args.output))
    helper = root / 'benchmark/results/2026-11-14-optimization-finish/validation/run_validation.py'
    spec = importlib.util.spec_from_file_location('saved_validation', helper)
    saved = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(saved)
    out.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(__file__, out / 'run_validation.py')
    dart = runtime / 'dart-sdk/bin/dart'
    env = os.environ.copy()
    overrides = {
        'PUB_CACHE': str(runtime / 'pub-cache'),
        'TMPDIR': str(runtime / 'tmp'),
        'XDG_CONFIG_HOME': str(runtime / 'config'),
        'DART_SUPPRESS_ANALYTICS': 'true',
        'CI': 'true', 'NO_COLOR': '1', 'PYTHONDONTWRITEBYTECODE': '1',
        'PYTHONPYCACHEPREFIX': str(runtime / 'python-cache'),
        'PATH': str(dart.parent) + os.pathsep + env.get('PATH', ''),
    }
    env.update(overrides)
    manifest = {
        'schema_version': 1, 'status': 'preparing', 'started_utc': saved.utc(),
        'phase': 'correctness before timing', 'source_root': str(root),
        'source_commit': saved.git(root, 'rev-parse', 'HEAD'),
        'library_tree': saved.git(root, 'rev-parse', 'HEAD:lib'),
        'test_tree': saved.git(root, 'rev-parse', 'HEAD:test'),
        'environment': overrides, 'gates': [],
        'runner_sha256': saved.digest(out / 'run_validation.py'),
        'helper': str(helper.relative_to(root)),
        'helper_sha256': saved.digest(helper),
        'browser_boundary': 'Node JS/Wasm here; real-browser gate recorded from GitHub separately.',
    }
    before = None
    try:
        if manifest['source_commit'] != args.expected_commit:
            raise ValueError('Head differs from the declared validation source')
        for name in ('lib', 'test'):
            comparison = saved.compare_tree(root, args.expected_commit, name)
            if not comparison['matches']:
                raise ValueError('Uncommitted source: ' + name)
        if saved.digest(dart) != saved.EXPECTED_DART:
            raise ValueError('Dart executable differs from the pinned runtime')
        if saved.digest(root / 'pubspec.lock') != saved.EXPECTED_LOCK:
            raise ValueError('Dependency lock differs from the pinned input')
        manifest['dart_sha256'] = saved.digest(dart)
        manifest['pubspec_lock_sha256'] = saved.digest(root / 'pubspec.lock')
        corpus_path = root / 'tool/performance_cad_tests.txt'
        corpus = corpus_path.read_text().splitlines()
        if len(corpus) != args.portable_files or len(set(corpus)) != len(corpus):
            raise ValueError('Unexpected portable corpus size or duplicates')
        if any(not (root / name).is_file() for name in corpus):
            raise ValueError('Missing portable test source')
        if 'test/lcg/restart_test.dart' not in corpus or 'test/geometry_cg_norm_test.dart' not in corpus:
            raise ValueError('New regressions must be in portable coverage')
        manifest['portable_corpus'] = corpus
        manifest['portable_corpus_sha256'] = saved.digest(corpus_path)
        shutil.copyfile(corpus_path, out / 'portable-corpus.txt')
        shutil.copyfile(root / 'pubspec.lock', out / 'dependency-lock.yaml')
        before = saved.source_snapshot(root)
        saved.write_json(out / 'source-before.json', before)
        manifest['source_inputs_before_sha256'] = before['sha256']
        manifest['status'] = 'running'
        prior = json.loads((root / saved.PRIOR).read_text())
        inherited = {gate['name']: gate for gate in prior['gates']}
        focused = ['test/geometry_cg_test.dart', 'test/geometry_cg_norm_test.dart',
                   'test/lcg/restart_test.dart']
        commands = [
            ('format', [str(dart), 'format', '--output=none', '--set-exit-if-changed', '.'], 120, None),
            ('analyze', [str(dart), 'analyze', '--fatal-infos'], 600, None),
            ('focused', [str(dart), 'test', '--reporter', 'expanded', *focused], 180, 12),
            ('native', [str(dart), 'test', '--reporter', 'expanded'], 600, args.native_tests),
            ('dart2js', [str(dart), 'test', '-p', 'node', '--compiler', 'dart2js', '--reporter', 'expanded', *corpus], 900, args.portable_tests),
            ('dart2wasm', [str(dart), 'test', '-p', 'node', '--compiler', 'dart2wasm', '--reporter', 'expanded', *corpus], 900, args.portable_tests),
        ]
        for name, count in [('python-solver-harness', 51), ('python-tool-harness', 27)]:
            command = list(inherited[name]['command'])
            command[0] = sys.executable
            commands.append((name, command, 180, count))
        for name, command, timeout, expected in commands:
            gate = saved.run_gate(name, command, root, out, env, manifest, timeout, expected)
            if not gate['passed']:
                raise ValueError('Required gate failed: ' + name)
        manifest['status'] = 'passed'
    except BaseException as error:
        manifest['status'] = 'failed'
        manifest['error'] = repr(error)
        (out / 'runner-error.log').write_text(traceback.format_exc())
    finally:
        if before is not None:
            after = saved.source_snapshot(root)
            saved.write_json(out / 'source-after.json', after)
            manifest['source_inputs_after_sha256'] = after['sha256']
            manifest['source_inputs_unchanged'] = before == after
            if before != after:
                manifest['status'] = 'failed'
                manifest['source_changes'] = [name for name in sorted(before['files'].keys() | after['files'].keys())
                                              if before['files'].get(name) != after['files'].get(name)]
        manifest['finished_utc'] = saved.utc()
        saved.write_json(out / 'validation-manifest.json', manifest)
        saved.write_json(out / 'checksums.json', {
            p.name: {'bytes': p.stat().st_size, 'sha256': saved.digest(p)}
            for p in sorted(out.iterdir()) if p.is_file() and p.name != 'checksums.json'
        })
    print(json.dumps({'status': manifest['status'], 'output': str(out),
                      'gates': [{k: g.get(k) for k in ('name', 'passed', 'tests_passed')}
                                for g in manifest['gates']]}), flush=True)
    return 0 if manifest['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())

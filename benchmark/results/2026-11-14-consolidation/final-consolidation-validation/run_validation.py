#!/usr/bin/env python3
"""Preserve complete consolidated test outputs without changing source files."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time

WORKSPACE = Path('/workspace/scratch/9a3b101dafc7')
ROOT = WORKSPACE / 'dart_csp'
OUTPUT = WORKSPACE / 'final-consolidation-validation'
DART = WORKSPACE / 'toolchains/dart-sdk/bin/dart'
ENV = os.environ.copy()
ENV.update(PUB_CACHE=str(WORKSPACE / 'toolchains/pub-cache'),
           TMPDIR=str(WORKSPACE / 'toolchains/tmp'))
ENV['PATH'] = str(DART.parent) + os.pathsep + ENV['PATH']


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def text(command):
    return subprocess.check_output(command, cwd=ROOT, env=ENV, text=True).strip()


def source_ids():
    return {key: text(['git', 'rev-parse', ref]) for key, ref in {
        'commit': 'HEAD', 'tree': 'HEAD^{tree}', 'library_tree': 'HEAD:lib',
        'test_tree': 'HEAD:test', 'tool_tree': 'HEAD:tool',
        'comparison_tree': 'HEAD:benchmark/solver_comparison',
        'workflow_tree': 'HEAD:.github/workflows',
    }.items()}


def save(manifest):
    (OUTPUT / 'validation.json').write_text(json.dumps(manifest, indent=2) + '\n')


def run(name, command, timeout, manifest):
    print(json.dumps({'starting': name, 'utc': now()}), flush=True)
    command = [str(arg) for arg in command]
    entry = dict(name=name, command=command, cwd=str(ROOT), timeout_seconds=timeout,
                 command_sha256=sha(json.dumps(command, separators=(',', ':')).encode()),
                 started_utc=now())
    start = time.monotonic()
    stdout_path, stderr_path = OUTPUT / f'{name}.stdout.log', OUTPUT / f'{name}.stderr.log'
    with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
        process = subprocess.Popen(command, cwd=ROOT, env=ENV, stdout=stdout, stderr=stderr,
                                   start_new_session=True)
        timed_out = False
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
    output = stdout_path.read_text(errors='replace')
    errors = stderr_path.read_text(errors='replace')
    count = None
    dart_summary = re.search(r'\+(\d+)[^\n]*All tests passed!', output)
    python_summary = re.search(r'Ran (\d+) tests? in ', errors)
    if dart_summary:
        count = int(dart_summary.group(1))
    elif python_summary:
        count = int(python_summary.group(1))
    source_diff = subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--',
                                 'lib', 'test', 'tool', 'benchmark/solver_comparison',
                                 '.github/workflows', 'pubspec.yaml', 'analysis_options.yaml'],
                                cwd=ROOT, capture_output=True)
    entry.update(completed_utc=now(), elapsed_seconds=time.monotonic() - start,
                 exit_code=code, timed_out=timed_out, tests_passed=count if code == 0 else None,
                 stdout_file=stdout_path.name, stdout_sha256=sha(stdout_path.read_bytes()),
                 stdout_bytes=stdout_path.stat().st_size,
                 stderr_file=stderr_path.name, stderr_sha256=sha(stderr_path.read_bytes()),
                 stderr_bytes=stderr_path.stat().st_size,
                 source_diff_exit_code=source_diff.returncode)
    manifest['commands'].append(entry)
    save(manifest)
    print(json.dumps({'completed': name, 'exit_code': code, 'tests_passed': entry['tests_passed'],
                      'seconds': entry['elapsed_seconds'], 'source_unchanged': source_diff.returncode == 0}),
          flush=True)
    if code:
        print((output + '\n' + errors)[-6000:], flush=True)


def main():
    OUTPUT.mkdir(exist_ok=False)
    selected_path = ROOT / 'tool/performance_cad_tests.txt'
    selected = [line.strip() for line in selected_path.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith('#')]
    assert len(selected) == 48 and len(set(selected)) == 48
    assert {'test/cad_reuse_test.dart', 'test/solver_comparison_adapter_test.dart'} <= set(selected)
    manifest = dict(schema_version=1, purpose='Final consolidated source correctness validation; not performance evidence',
                    started_utc=now(), source=source_ids(), initial_status=text(['git', 'status', '--porcelain']),
                    dart_version=text([str(DART), '--version']), node_version=text(['node', '--version']),
                    python_version=platform.python_version(), platform=platform.platform(),
                    runtime_sha256={'dart': sha(DART.read_bytes()),
                                    'node': sha(Path(shutil.which('node')).read_bytes())},
                    environment={key: ENV[key] for key in ('PUB_CACHE', 'TMPDIR')},
                    runner_sha256=sha(Path(__file__).read_bytes()), commands=[],
                    portable_corpus=dict(file=str(selected_path.relative_to(ROOT)), files=selected,
                                         file_count=len(selected), sha256=sha(selected_path.read_bytes()),
                                         file_sha256={name: sha((ROOT / name).read_bytes()) for name in selected}),
                    pubspec_lock_sha256=sha((ROOT / 'pubspec.lock').read_bytes()),
                    browser=dict(rerun=False, reason='Earlier Chromium startup was blocked by environment socket restriction; no new browser claim.'))
    if manifest['initial_status']:
        raise RuntimeError('Source worktree must be clean before consolidated validation')
    save(manifest)
    run('format', [DART, 'format', '--output=none', '--set-exit-if-changed', '.'], 180, manifest)
    run('analysis', [DART, 'analyze', '--fatal-infos'], 180, manifest)
    run('python_comparison', [sys.executable, '-m', 'unittest', 'discover', '-s',
                             'benchmark/solver_comparison', '-p', 'test_*.py', '-v'], 180, manifest)
    run('python_tools', [sys.executable, '-m', 'unittest', 'discover', '-s',
                        'tool', '-p', 'test_*.py', '-v'], 180, manifest)
    run('native', [DART, 'test', '--reporter', 'expanded'], 900, manifest)
    for compiler in ('dart2js', 'dart2wasm'):
        run(compiler, [DART, 'test', '-p', 'node', '--compiler', compiler,
                       '--reporter', 'expanded', *selected], 1800, manifest)
    manifest.update(completed_utc=now(), final_source=source_ids(),
                    final_status=text(['git', 'status', '--porcelain']))
    manifest['source_unchanged'] = manifest['source'] == manifest['final_source'] and not manifest['final_status']
    manifest['passed'] = manifest['source_unchanged'] and all(
        c['exit_code'] == 0 and c['source_diff_exit_code'] == 0 and not c['timed_out']
        for c in manifest['commands'])
    save(manifest)
    shutil.copyfile(__file__, OUTPUT / 'run_validation.py')
    print(json.dumps({'finished': True, 'passed': manifest['passed'], 'directory': str(OUTPUT)}), flush=True)
    return 0 if manifest['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

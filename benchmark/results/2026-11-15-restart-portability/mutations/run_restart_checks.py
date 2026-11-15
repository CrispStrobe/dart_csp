#!/usr/bin/env python3
"""Bounded focused test runner; preserves commands, logs and source hashes."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path('/workspace/scratch/b51b355c4f64')
RUNTIME = ROOT / 'runtime'
DART = RUNTIME / 'dart-sdk/bin/dart'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=ROOT / 'dart_csp')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--platforms', nargs='+', default=['vm', 'js', 'wasm'])
    parser.add_argument('--name')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(PUB_CACHE=str(RUNTIME / 'pub-cache'),
               TMPDIR=str(RUNTIME / 'tmp'),
               XDG_CONFIG_HOME=str(RUNTIME / 'config'),
               DART_SUPPRESS_ANALYTICS='true', CI='true')
    env['PATH'] = str(DART.parent) + os.pathsep + env['PATH']
    inputs = ['test/lcg/restart_test.dart', 'pubspec.lock',
              'lib/src/solver.dart', 'lib/src/problem.dart']
    manifest = {'started_utc': utc(), 'repository': str(args.repo),
                'dart': str(DART), 'dart_sha256': digest(DART),
                'source_sha256_before': {p: digest(args.repo / p) for p in inputs},
                'gates': []}
    manifest_path = args.out / 'manifest.json'
    def save():
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    for platform in args.platforms:
        command = [str(DART), 'test', '--reporter', 'expanded']
        if platform != 'vm':
            command += ['--platform', 'node', '--compiler',
                        'dart2js' if platform == 'js' else 'dart2wasm']
        if args.name:
            command += ['--name', args.name]
        command += ['test/lcg/restart_test.dart']
        gate = {'platform': platform, 'command': command,
                'started_utc': utc(), 'timeout_seconds': 180}
        log = args.out / (platform + '.log')
        start = time.monotonic()
        with log.open('wb') as output:
            proc = subprocess.Popen(command, cwd=args.repo, env=env,
                                    stdout=output, stderr=subprocess.STDOUT,
                                    start_new_session=True)
            gate['timed_out'] = False
            try:
                gate['exit_code'] = proc.wait(timeout=gate['timeout_seconds'])
            except subprocess.TimeoutExpired:
                gate['timed_out'] = True
                os.killpg(proc.pid, signal.SIGKILL)
                gate['exit_code'] = proc.wait(timeout=10)
        gate.update(completed_utc=utc(), elapsed_seconds=time.monotonic() - start,
                    log=str(log), log_sha256=digest(log))
        manifest['gates'].append(gate)
        save()
        print(json.dumps(gate), flush=True)
        print(log.read_text()[-6000:], flush=True)
        if gate['exit_code'] != 0:
            break
    manifest['completed_utc'] = utc()
    manifest['source_sha256_after'] = {p: digest(args.repo / p) for p in inputs}
    manifest['source_unchanged'] = (manifest['source_sha256_before'] ==
                                    manifest['source_sha256_after'])
    manifest['all_passed'] = (len(manifest['gates']) == len(args.platforms) and
                              all(g['exit_code'] == 0 and not g['timed_out']
                                  for g in manifest['gates']) and
                              manifest['source_unchanged'])
    save()
    raise SystemExit(0 if manifest['all_passed'] else 1)

if __name__ == '__main__':
    main()

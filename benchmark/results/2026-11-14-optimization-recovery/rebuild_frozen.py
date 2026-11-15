#!/usr/bin/env python3
"""Rebuild three archived solver inputs without altering repository source."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT.parent / 'runtime'
DART = RUNTIME / 'dart-sdk/bin/dart'
ENV = dict(os.environ, PUB_CACHE=str(RUNTIME / 'pub-cache'),
           TMPDIR=str(RUNTIME / 'tmp'), XDG_CONFIG_HOME=str(RUNTIME / 'config'),
           DART_SUPPRESS_ANALYTICS='true', CI='true')
MANIFEST = ROOT / 'rebuild-manifest.json'
LOCK = 'a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a'


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


report = {
    'schema_version': 1, 'status': 'running', 'started_utc': now(),
    'purpose': 'Recovered frozen source builds; no timing or solver execution',
    'environment': {k: ENV[k] for k in ('PUB_CACHE', 'TMPDIR', 'XDG_CONFIG_HOME',
                                       'DART_SUPPRESS_ANALYTICS', 'CI')},
    'platform': platform.platform(), 'uname': list(platform.uname()),
    'allowed_cpus': sorted(os.sched_getaffinity(0)),
    'cpu_model': next((line.split(':', 1)[1].strip()
                       for line in Path('/proc/cpuinfo').read_text().splitlines()
                       if line.startswith('model name')), ''),
    'sdk': {'zip': str(RUNTIME / 'downloads/dartsdk-linux-x64-release-3.14.0.zip'),
            'zip_sha256': digest(RUNTIME / 'downloads/dartsdk-linux-x64-release-3.14.0.zip'),
            'executable': str(DART), 'executable_sha256': digest(DART)},
    'dependency_lock_sha256': LOCK, 'variants': {},
    'cohort_note': 'New workspace recovery. Historical timings remain in their original host cohorts.'
}


def save():
    tmp = MANIFEST.with_suffix('.json.tmp')
    tmp.write_text(json.dumps(report, indent=2) + '\n')
    tmp.replace(MANIFEST)


def run_command(label, stage, command, cwd, timeout):
    directory = ROOT / 'builds' / label
    directory.mkdir(parents=True, exist_ok=True)
    row = {'command': command, 'cwd': str(cwd), 'started_utc': now(),
           'timeout_seconds': timeout,
           'stdout': str(directory / (stage + '.stdout.log')),
           'stderr': str(directory / (stage + '.stderr.log'))}
    report['variants'][label].setdefault('commands', []).append(row)
    save()
    with Path(row['stdout']).open('wb') as out, Path(row['stderr']).open('wb') as err:
        try:
            result = subprocess.run(command, cwd=cwd, env=ENV,
                                    stdout=out, stderr=err, timeout=timeout)
            row.update(exit_code=result.returncode, timed_out=False)
        except subprocess.TimeoutExpired:
            row.update(exit_code=None, timed_out=True)
    row.update(completed_utc=now(), stdout_sha256=digest(Path(row['stdout'])),
               stderr_sha256=digest(Path(row['stderr'])))
    save()
    if row['exit_code'] != 0:
        raise RuntimeError(label + ' ' + stage + ' failed; logs preserved')
    return row


try:
    assert report['sdk']['zip_sha256'] == '90f7fd75fe21e16437778df882f280910d9bbd4809c90024f21de82435dded1d'
    assert report['sdk']['executable_sha256'] == '6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b'
    report['sdk']['version'] = subprocess.check_output([str(DART), '--version'], env=ENV, text=True).strip()
    save()
    for label, cohort, variant in [('packed', 'cg', 'before'), ('cg', 'cg', 'after'),
                                   ('combined', 'identity', 'after')]:
        prep = ROOT / 'prepared-original' / cohort
        original = json.loads((prep / 'prepared.json').read_text())
        item = original['variants'][variant]
        source = ROOT / 'sources' / label
        assert digest(source / 'pubspec.lock') == LOCK
        assert all(digest(source / p) == expected for p, expected
                   in item['source']['source_sha256'].items())
        info = {
            'source': str(source), 'original_preparation_manifest': str(prep / 'prepared.json'),
            'original_preparation_manifest_sha256': digest(prep / 'prepared.json'),
            'original_source': item['source'],
            'source_archive': str(prep / item['source_archive']),
            'source_archive_sha256': digest(prep / item['source_archive']),
            'original_executable_sha256': item['executable_sha256'],
            'all_archived_source_members_verified_before_pub': True,
        }
        report['variants'][label] = info
        save()
        pub = [str(DART), 'pub', 'get', '--enforce-lockfile']
        if label != 'packed':
            pub.append('--offline')
        run_command(label, 'pub-get', pub, source, 240)
        assert digest(source / 'pubspec.lock') == LOCK
        changed = [p for p, expected in item['source']['source_sha256'].items()
                   if digest(source / p) != expected]
        assert set(changed) <= {'.dart_tool/package_config.json'}, changed
        info.update(source_changed_by_resolution=changed,
                    package_config_sha256=digest(source / '.dart_tool/package_config.json'),
                    source_sha256_after_resolution={p: digest(source / p)
                        for p in item['source']['source_sha256']})
        output = ROOT / 'builds' / label / 'dart-adapter'
        command = [str(DART), 'compile', 'exe',
                   'benchmark/solver_comparison/dart_adapter.dart', '-o', str(output)]
        run_command(label, 'compile', command, source, 300)
        assert all(digest(source / p) == expected
                   for p, expected in info['source_sha256_after_resolution'].items())
        info.update(executable=str(output), executable_bytes=output.stat().st_size,
                    executable_sha256=digest(output),
                    matches_original_executable=digest(output) == item['executable_sha256'],
                    source_unchanged_during_build=True)
        save()
        print(json.dumps({'variant': label, 'executable': str(output),
                          'sha256': info['executable_sha256'],
                          'matches_original': info['matches_original_executable']}), flush=True)
    report['status'] = 'complete'
except Exception as error:
    report.update(status='failed', error=str(error))
    raise
finally:
    report['finished_utc'] = now()
    save()

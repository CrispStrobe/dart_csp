#!/usr/bin/env python3
"""Freeze recovered executables and their actual relocated build inputs."""
import copy
import datetime
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import tarfile

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / 'rebuild-manifest.json'
rebuild = json.loads(MANIFEST.read_text())
assert rebuild['status'] == 'complete'


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive_source(path, source, inputs):
    with path.open('wb') as out:
        with gzip.GzipFile(fileobj=out, mode='wb', mtime=0, filename='') as gz:
            with tarfile.open(fileobj=gz, mode='w') as archive:
                for name, expected in sorted(inputs.items()):
                    data = (source / name).read_bytes()
                    assert hashlib.sha256(data).hexdigest() == expected
                    info = tarfile.TarInfo(name)
                    info.size, info.mode = len(data), 0o644
                    archive.addfile(info, io.BytesIO(data))


cohorts = {'cg': ('packed', 'cg'), 'identity': ('cg', 'combined'),
           'combined': ('packed', 'combined'), 'aa': ('packed', 'packed')}
rebuild['prepared_cohorts'] = {}
for cohort, labels in cohorts.items():
    original_dir = ROOT / 'prepared-original' / cohort
    original = json.loads((original_dir / 'prepared.json').read_text())
    destination = ROOT / ('prepared-' + cohort)
    destination.mkdir(exist_ok=False)
    shutil.copytree(original_dir / 'harness', destination / 'harness')
    assert all(sha(destination / 'harness' / name) == expected
               for name, expected in original['harness_sha256'].items())
    manifest = copy.deepcopy(original)
    manifest.update(
        status='complete',
        started_utc=min(rebuild['variants'][label]['commands'][-1]['started_utc']
                        for label in labels),
        finished_utc=max(rebuild['variants'][label]['commands'][-1]['completed_utc']
                         for label in labels),
        dart={'executable': rebuild['sdk']['executable'],
              'sha256': rebuild['sdk']['executable_sha256'],
              'version': rebuild['sdk']['version']},
        platform=rebuild['platform'], environment=rebuild['environment'],
        purpose=('Identical recovered executable A/A control' if cohort == 'aa'
                 else 'Frozen recovered pure-Dart AOT build; all compilation outside solver timers'),
        recovery_provenance={
            'created_utc': now(),
            'historical_manifest': str(original_dir / 'prepared.json'),
            'historical_manifest_sha256': sha(original_dir / 'prepared.json'),
            'historical_manifest_unchanged': True,
            'rebuild_manifest': str(MANIFEST),
            'compiler_and_lock_match_historical': True,
            'tracked_source_and_adapter_bytes_match_historical': True,
            'package_config_regenerated_for_new_paths': True,
            'timing_cohort': 'Fresh recovered-workspace cohort; never pool with historical runs',
            'source_status_note': 'Source commit/tree/status fields come from the archived clean checkout. Every archived source member was verified before dependency resolution; only generated package_config.json changed. This recovery uses extracted inputs rather than a Git worktree.',
            'preparation_method': 'Reuse the three recorded sequential compiles; copy frozen executable and logs without recompiling',
        })
    for variant, label in zip(('before', 'after'), labels):
        item = manifest['variants'][variant]
        built = rebuild['variants'][label]
        source = Path(built['source'])
        variant_dir = destination / variant
        variant_dir.mkdir()
        item['original_source'] = copy.deepcopy(item['source'])
        item['source'].update(root=str(source), source_sha256=built['source_sha256_after_resolution'])
        item['source']['source_status_provenance'] = 'Original archived clean checkout; all tracked source bytes reverified'
        item['source_archive'] = variant + '/source.tar.gz'
        archive_source(destination / item['source_archive'], source,
                       built['source_sha256_after_resolution'])
        item['source_archive_sha256'] = sha(destination / item['source_archive'])
        build = copy.deepcopy(built['commands'][-1])
        assert build['exit_code'] == 0 and not build['timed_out']
        for stream in ('stdout', 'stderr'):
            log = Path(build.pop(stream))
            shutil.copyfile(log, variant_dir / ('build.' + stream + '.log'))
            assert sha(variant_dir / ('build.' + stream + '.log')) == build[stream + '_sha256']
        build['command_sha256'] = hashlib.sha256(json.dumps(build['command']).encode()).hexdigest()
        build['reused_compile_label'] = label
        item['build'] = build
        item['historical_executable_sha256'] = built['original_executable_sha256']
        item['executable'] = variant + '/dart-adapter'
        shutil.copy2(built['executable'], destination / item['executable'])
        item['executable_sha256'] = sha(destination / item['executable'])
        item['executable_bytes'] = (destination / item['executable']).stat().st_size
        assert item['executable_sha256'] == built['executable_sha256']
        assert item['source']['source_commit'] == built['original_source']['source_commit']
    if cohort == 'aa':
        assert manifest['variants']['before']['executable_sha256'] == manifest['variants']['after']['executable_sha256']
    out = destination / 'prepared.json'
    out.write_text(json.dumps(manifest, indent=2) + '\n')
    rebuild['prepared_cohorts'][cohort] = {
        'directory': str(destination), 'manifest': str(out), 'manifest_sha256': sha(out),
        'labels': dict(zip(('before', 'after'), labels)),
        'harness_sha256': manifest['harness_sha256'],
        'executables': {v: {'path': str(destination / d['executable']),
                            'sha256': d['executable_sha256'], 'bytes': d['executable_bytes']}
                        for v, d in manifest['variants'].items()},
    }
    print(json.dumps({'cohort': cohort, 'prepared': str(destination),
                      'labels': rebuild['prepared_cohorts'][cohort]['labels']}))

for label, built in rebuild['variants'].items():
    strings = re.findall(rb'[\x20-\x7e]{12,}', Path(built['executable']).read_bytes())
    built['embedded_workspace_paths'] = sorted(set(
        s.decode('utf8', 'replace') for s in strings if b'/workspace/scratch/' in s))
    built['byte_identity_note'] = (
        'Compiler, lock, production source and adapter hashes match their archived inputs. '
        'Generated package config and embedded absolute adapter source paths changed with workspace relocation. '
        'Executable digest differs; no byte-identical reproduction is claimed.')
rebuild['preparation_completed_utc'] = now()
MANIFEST.write_text(json.dumps(rebuild, indent=2) + '\n')

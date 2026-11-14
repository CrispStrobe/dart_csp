"""Verify the complete saved follow-up evidence without running a solver."""
import argparse
import datetime
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def checked(data, expected, label):
    assert len(data) == expected['bytes'], label + ': size'
    assert digest(data) == expected['sha256'], label + ': digest'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('root', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    checks = []
    for manifest_path in sorted(a.root.glob('*-evidence.json')):
        manifest = json.loads(manifest_path.read_text())
        if 'archive' not in manifest:
            continue
        if 'archive_parts' in manifest:
            parts = []
            for entry in manifest['archive_parts']:
                data = (a.root / entry['file']).read_bytes()
                checked(data, entry, entry['file'])
                parts.append(data)
            data = b''.join(parts)
        else:
            data = (a.root / manifest['archive']).read_bytes()
        checked(data, {'bytes': manifest['archive_bytes'],
                       'sha256': manifest['archive_sha256']}, manifest['archive'])
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
            members = archive.getmembers()
            assert len(members) == len(manifest['files'])
            assert {m.name for m in members} == set(manifest['files'])
            for m in members:
                assert m.isfile(), m.name
                checked(archive.extractfile(m).read(), manifest['files'][m.name], m.name)
        checks.append({'manifest': manifest_path.name,
                       'archive_sha256': manifest['archive_sha256'],
                       'members_verified': len(members),
                       'parts_verified': len(manifest.get('archive_parts', []))})
    normal_checks = []
    for name in ('qr-screen', 'cad-controls'):
        folder = a.root / name
        manifest = json.loads((folder / 'evidence.json').read_text())
        assert manifest['status'] == 'completed'
        assert manifest['completed_reports'] == manifest['expected_reports'] == 36
        for filename, expected in manifest['files'].items():
            checked((folder / filename).read_bytes(), expected, name + '/' + filename)
        raw = gzip.decompress((folder / 'raw.json.gz').read_bytes())
        checked(raw, {'bytes': manifest['raw_uncompressed_bytes'],
                      'sha256': manifest['raw_uncompressed_sha256']}, name + '/raw.json')
        records = json.loads(raw)
        assert records['status'] == 'completed' and len(records['runs']) == 36
        review_manifest = folder / 'review-files.json'
        if review_manifest.exists():
            for filename, expected in json.loads(review_manifest.read_text())['files'].items():
                checked(raw if filename == 'raw.json' else (folder / filename).read_bytes(),
                        expected, name + '/' + filename)
        normal_checks.append({'cohort': name, 'reports': len(records['runs']),
                              'raw_bytes': len(raw), 'raw_sha256': digest(raw),
                              'manifest_files_verified': len(manifest['files'])})
    result = {'schema_version': 1,
              'checked_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'status': 'pass', 'findings': [],
              'archives': checks, 'normal_cohorts': normal_checks,
              'total_archive_members': sum(c['members_verified'] for c in checks),
              'note': 'Byte and membership verification of preserved archives and normal evidence; no solver workload or timing repeated.'}
    a.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'archives': len(checks),
                      'archive_members': result['total_archive_members'],
                      'normal_cohorts': len(normal_checks)}))


if __name__ == '__main__':
    main()

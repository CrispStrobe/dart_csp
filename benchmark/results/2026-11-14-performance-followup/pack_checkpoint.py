"""Preserve completed benchmark directories as hashed, bounded Git blobs."""
import argparse
import datetime
import hashlib
import io
import json
from pathlib import Path
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('name')
    parser.add_argument('--omit', action='append', default=[])
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    manifest_path = args.destination / (args.name + '-evidence.json')
    if manifest_path.exists():
        raise ValueError('Completed checkpoint must not be overwritten')
    files, omitted = {}, {}
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:xz', preset=6) as archive:
        for path in sorted(args.source.rglob('*')):
            if path.is_symlink():
                raise ValueError('Evidence must contain regular files only')
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            name = path.relative_to(args.source).as_posix()
            data = path.read_bytes()
            entry = {'bytes': len(data), 'sha256': digest(data)}
            if name in args.omit:
                omitted[name] = entry
                continue
            files[name] = entry
            member = tarfile.TarInfo(name)
            member.mode, member.size = 0o644, len(data)
            archive.addfile(member, io.BytesIO(data))
    data = buffer.getvalue()
    archive_name = args.name + '.tar.xz'
    manifest = {
        'schema_version': 1,
        'saved_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'archive': archive_name,
        'archive_bytes': len(data),
        'archive_sha256': digest(data),
        'files': files,
    }
    size = 262144
    if len(data) <= size:
        (args.destination / archive_name).write_bytes(data)
    else:
        parts = []
        for number, start in enumerate(range(0, len(data), size)):
            name = archive_name + f'.part{number:03d}'
            chunk = data[start:start + size]
            (args.destination / name).write_bytes(chunk)
            parts.append({'file': name, 'bytes': len(chunk), 'sha256': digest(chunk)})
        manifest['archive_parts'] = parts
    if omitted:
        manifest['omitted_files'] = omitted
        manifest['omission_note'] = (
            'Temporary AOT executables are omitted; exact byte counts/digests, '
            'compiler identity, build commands/logs and frozen source archives '
            'are preserved. Replaying saved audits does not rerun timings.')
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'archive': archive_name, 'bytes': len(data),
                      'members': len(files), 'omitted': len(omitted)}))


if __name__ == '__main__':
    main()

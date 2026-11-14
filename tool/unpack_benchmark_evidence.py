"""Verify and restore a manifested benchmark archive, including split archives."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile


def check_bytes(data, expected, name):
    if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']:
        raise ValueError('Evidence digest mismatch: ' + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if args.destination.exists():
        raise ValueError('Destination already exists; choose a new directory')
    if 'archive_parts' in manifest:
        chunks = []
        for part in manifest['archive_parts']:
            name = part['file']
            if Path(name).name != name:
                raise ValueError('Archive part must be a sibling filename')
            data = (args.manifest.parent / name).read_bytes()
            check_bytes(data, part, name)
            chunks.append(data)
        archive_bytes = b''.join(chunks)
    else:
        name = manifest['archive']
        if Path(name).name != name:
            raise ValueError('Archive must be a sibling filename')
        archive_bytes = (args.manifest.parent / name).read_bytes()
    check_bytes(archive_bytes, {'bytes': manifest['archive_bytes'],
                              'sha256': manifest['archive_sha256']}, manifest['archive'])
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:*') as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if len(names) != len(set(names)) or set(names) != set(manifest['files']):
            raise ValueError('Archive membership differs from manifest')
        verified = []
        for member in members:
            relative = PurePosixPath(member.name)
            if not member.isfile() or relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Archive contains a non-regular or unsafe member')
            data = archive.extractfile(member).read()
            check_bytes(data, manifest['files'][member.name], member.name)
            verified.append((relative, data))
    args.destination.mkdir(parents=True)
    for relative, data in verified:
        target = args.destination.joinpath(*relative.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    print(json.dumps({'status': 'verified_and_restored', 'files': len(verified),
                      'archive_sha256': manifest['archive_sha256'],
                      'destination': str(args.destination)}))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Preserve exact raw runs in compact, size-bounded, Git-friendly archives."""

import argparse
import gzip
import hashlib
import io
import json
import pathlib
import tarfile


def archive(root, directories):
    result = io.BytesIO()
    with gzip.GzipFile(fileobj=result, mode='wb', mtime=0, compresslevel=9) as gz:
        with tarfile.open(fileobj=gz, mode='w') as tar:
            for directory in directories:
                for path in sorted(directory.iterdir()):
                    if path.is_file():
                        tar.add(path, arcname=str(path.relative_to(root)), recursive=False)
    return result.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=pathlib.Path)
    parser.add_argument('--target-bytes', type=int, default=131072)
    args = parser.parse_args()
    root = args.run
    if (root / 'archives.json').exists():
        parser.error('already packed; original evidence must not be overwritten')
    summary = (root / 'summary.json').read_bytes()
    data = json.loads(summary)
    if not data['manifest'].get('finished_utc'):
        parser.error('run has not completed')
    (root / 'summary.json.gz').write_bytes(gzip.compress(summary, mtime=0))
    directories = [root / pathlib.Path(j['raw_directory']).name for j in data['jobs']]
    groups = []

    def split(items):
        packed = archive(root, items)
        if len(packed) > args.target_bytes and len(items) > 1:
            half = len(items) // 2
            split(items[:half])
            split(items[half:])
        else:
            groups.append((items, packed))

    # Bound temporary memory even for large runs.
    for start in range(0, len(directories), 24):
        split(directories[start:start + 24])
    entries = []
    for index, (items, packed) in enumerate(groups):
        name = f'raw-{index:03d}.tar.gz'
        (root / name).write_bytes(packed)
        entries.append(dict(file=name, bytes=len(packed),
                            sha256=hashlib.sha256(packed).hexdigest(),
                            jobs=[p.name for p in items]))
    manifest = dict(schema_version=1, exact_raw_evidence=True,
                    summary_sha256=hashlib.sha256(summary).hexdigest(),
                    archives=entries,
                    restore='Extract each raw-*.tar.gz into this run directory. '
                            'The analyzer also reads the archives directly.')
    (root / 'archives.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(dict(run=str(root), jobs=len(directories),
                          archives=len(entries), bytes=sum(e['bytes'] for e in entries))))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Archive completed sparse-solver evidence without changing its file bytes.

Example:
  python tool/archive_sparse_evidence.py /path/to/small-controls \
    --output-dir benchmark/results/2026-11-14-sparse-finalization \
    --name small-controls --baseline-revision BASE --source-revision SOURCE \
    --cohort-note 'Fresh host; do not pool with earlier timing cohorts.'

Archives contain regular files only, in sorted order, with normalized tar
metadata and a zero gzip timestamp. The companion JSON records every member's
path, byte length and SHA-256, explicit omissions, and the archive's SHA-256.
Existing deliverables are never overwritten. Run only after collection stops.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile
import tempfile


def signature(path: Path) -> tuple[int, ...]:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"Source member is not a regular file: {path}")
    return (
        info.st_dev,
        info.st_ino,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_files(source: Path) -> list[Path]:
    files = []
    for directory, names, filenames in os.walk(source, followlinks=False):
        for name in names:
            path = Path(directory) / name
            if path.is_symlink() or not path.is_dir():
                raise ValueError(f"Source contains a non-directory or symlink: {path}")
        for name in filenames:
            path = Path(directory) / name
            signature(path)  # Reject symlinks, sockets and other special files.
            files.append(path)
    return sorted(files, key=lambda path: path.relative_to(source).as_posix())


class DigestingReader:
    def __init__(self, stream):
        self.stream = stream
        self.digest = hashlib.sha256()

    def read(self, size=-1):
        block = self.stream.read(size)
        self.digest.update(block)
        return block


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--baseline-revision", required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--cohort-note", required=True)
    parser.add_argument("--exclude", action="append", default=[], metavar="RELATIVE_PATH")
    parser.add_argument("--omission-reason", default="")
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.name):
        parser.error("--name must be a safe filename component")
    if args.source.is_symlink():
        parser.error("source must not be a symlink")
    source = args.source.resolve(strict=True)
    output = args.output_dir.resolve()
    if not source.is_dir():
        parser.error("source must be a directory")
    if output == source or source in output.parents:
        parser.error("output directory must be outside the source tree")
    excludes = set(args.exclude)
    if len(excludes) != len(args.exclude):
        parser.error("duplicate exclusion")
    for name in excludes:
        relative = PurePosixPath(name)
        if (
            relative.is_absolute()
            or any(part in ("", ".", "..") for part in name.split("/"))
            or "\\" in name
        ):
            parser.error(f"exclusion must be a normalized relative file path: {name}")
    if excludes and not args.omission_reason.strip():
        parser.error("explicit exclusions require --omission-reason")

    paths = source_files(source)
    relative_paths = {path.relative_to(source).as_posix() for path in paths}
    missing = excludes - relative_paths
    if missing:
        parser.error(f"excluded files do not exist: {sorted(missing)}")
    records = []
    for path in paths:
        before = signature(path)
        checksum = sha256_file(path)
        if signature(path) != before:
            raise ValueError(f"Source changed while hashing: {path}")
        records.append(
            {
                "path": path.relative_to(source).as_posix(),
                "size_bytes": before[2],
                "sha256": checksum,
                "signature": before,
            }
        )
    included = [record for record in records if record["path"] not in excludes]
    omitted = [record for record in records if record["path"] in excludes]
    archive_path = output / f"{args.name}.raw.tar.gz"
    manifest_path = output / f"{args.name}.manifest.json"
    if archive_path.exists() or manifest_path.exists():
        parser.error("archive or manifest already exists; choose a new output/name")
    output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=".archive-", dir=output) as temporary:
        temporary_archive = Path(temporary) / archive_path.name
        with temporary_archive.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as archive:
                    for record in included:
                        path = source / record["path"]
                        if signature(path) != record["signature"]:
                            raise ValueError(f"Source changed before archiving: {path}")
                        member = tarfile.TarInfo(f"{args.name}/{record['path']}")
                        member.size = record["size_bytes"]
                        member.mode = 0o644
                        member.mtime = 0
                        with path.open("rb") as stream:
                            reader = DigestingReader(stream)
                            archive.addfile(member, reader)
                        if (
                            reader.digest.hexdigest() != record["sha256"]
                            or signature(path) != record["signature"]
                        ):
                            raise ValueError(f"Source changed while archiving: {path}")

        if source_files(source) != paths:
            raise ValueError("Source member list changed while archiving")
        for record in records:
            if signature(source / record["path"]) != record["signature"]:
                raise ValueError(f"Source changed during snapshot: {record['path']}")

        def public_record(record):
            return {key: value for key, value in record.items() if key != "signature"}

        manifest = {
            "schema_version": 1,
            "baseline_revision": args.baseline_revision,
            "source_revision": args.source_revision,
            "cohort_note": args.cohort_note,
            "archive": {
                "path": archive_path.name,
                "size_bytes": temporary_archive.stat().st_size,
                "sha256": sha256_file(temporary_archive),
                "member_prefix": f"{args.name}/",
                "member_count": len(included),
                "uncompressed_file_bytes": sum(record["size_bytes"] for record in included),
                "format": "tar PAX + gzip; sorted regular files; mode 0644; uid/gid/mtime 0; empty owner names; gzip mtime 0 and empty filename",
            },
            "members": [
                dict(public_record(record), archive_path=f"{args.name}/{record['path']}")
                for record in included
            ],
            "omissions": [
                dict(public_record(record), reason=args.omission_reason)
                for record in omitted
            ],
        }
        temporary_manifest = Path(temporary) / manifest_path.name
        temporary_manifest.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        # Rename only after all source-change checks and hashing succeed.
        os.replace(temporary_archive, archive_path)
        os.replace(temporary_manifest, manifest_path)

    print(json.dumps({"archive": str(archive_path), **manifest["archive"],
                      "manifest": str(manifest_path), "omitted_files": len(omitted)},
                     sort_keys=True))


if __name__ == "__main__":
    main()

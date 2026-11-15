#!/usr/bin/env python3
"""Compact exact benchmark evidence without changing its source files.

Pack stores gzip payloads together in a solid xz archive only when the original
gzip bytes can be reproduced exactly. Every original file and stored payload has
its own SHA-256. Restore verifies all bytes before creating its destination.

Gzip reconstruction uses the recorded zlib recipe and checks the original hash;
a future incompatible zlib must fail rather than write different gzip bytes.
``restore --payloads-only`` always recovers the verified, uncompressed evidence
as content-addressed files plus its complete original-path mapping. Unsupported
gzip streams are stored literally. The legacy archive format is untouched.
"""
from __future__ import annotations

import argparse
import datetime
import gzip
import hashlib
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import re
import tarfile
import zlib


CHUNK_BYTES = 262144
SCHEMA = "optimization-exact-payloads-v1"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def describe(data):
    return {"bytes": len(data), "sha256": digest(data)}


def check(data, expected, name):
    if describe(data) != {key: expected[key] for key in ("bytes", "sha256")}:
        raise ValueError("Evidence digest mismatch: " + name)


def safe_path(name):
    path = PurePosixPath(name)
    if (not isinstance(name, str) or not name or path.is_absolute()
            or ".." in path.parts or str(path) != name or name == "."):
        raise ValueError("Unsafe evidence path: " + repr(name))
    return path


def deflate(payload, sync_flush):
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    result = compressor.compress(payload)
    if sync_flush:
        result += compressor.flush(zlib.Z_SYNC_FLUSH)
    return result + compressor.flush(zlib.Z_FINISH)


def encode(data):
    if data[:2] == b"\x1f\x8b":
        try:
            if len(data) < 18 or data[2] != 8 or data[3] & 0xe0:
                raise ValueError("Unsupported gzip header")
            payload = gzip.decompress(data)
            position = 10
            if data[3] & 4:
                position += 2 + int.from_bytes(data[position:position + 2], "little")
            if data[3] & 8:
                position = data.index(b"\0", position) + 1
            if data[3] & 16:
                position = data.index(b"\0", position) + 1
            if data[3] & 2:
                position += 2
            header, trailer = data[:position], data[-8:]
            for sync_flush in (False, True):
                if header + deflate(payload, sync_flush) + trailer == data:
                    return payload, {"encoding": "gzip-deflate-9",
                                     "header_hex": header.hex(),
                                     "trailer_hex": trailer.hex(),
                                     "sync_flush": sync_flush}
        except (ValueError, OSError, EOFError, zlib.error):
            pass
    return data, {"encoding": "literal"}


def decode(payload, entry):
    if entry["encoding"] == "literal":
        return payload
    if entry["encoding"] != "gzip-deflate-9" or type(entry["sync_flush"]) is not bool:
        raise ValueError("Unsupported evidence encoding")
    return (bytes.fromhex(entry["header_hex"])
            + deflate(payload, entry["sync_flush"])
            + bytes.fromhex(entry["trailer_hex"]))


def pack(source, destination, name):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
        raise ValueError("Checkpoint name must be a simple filename stem")
    source, destination = source.resolve(strict=True), destination.resolve()
    if not source.is_dir() or destination == source or source in destination.parents:
        raise ValueError("Source must be a directory outside the destination")
    if ((destination / (name + "-evidence.json")).exists()
            or any(destination.glob(name + ".payloads.tar.xz*"))):
        raise ValueError("Checkpoint must not overwrite existing output")
    files, payloads = {}, {}
    # Put corresponding before/after jobs near each other for solid compression.
    paths = sorted(source.rglob("*"),
                   key=lambda p: (p.relative_to(source).as_posix().split("/", 1)[-1],
                                  p.relative_to(source).as_posix()))
    for path in paths:
        if path.is_symlink():
            raise ValueError("Evidence must not contain symlinks")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError("Evidence must contain only regular files")
        relative = path.relative_to(source).as_posix()
        safe_path(relative)
        data = path.read_bytes()
        payload, recipe = encode(data)
        entry = {**describe(data), **recipe, "payload": digest(payload)}
        check(decode(payload, entry), entry, relative)
        files[relative] = entry
        payloads[entry["payload"]] = payload
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for sha, data in payloads.items():
            member = tarfile.TarInfo("payloads/" + sha)
            member.size, member.mode = len(data), 0o644
            archive.addfile(member, io.BytesIO(data))
    archive_bytes = lzma.compress(buffer.getvalue(), filters=[
        {"id": lzma.FILTER_LZMA2, "preset": 6, "dict_size": 64 * 1024 * 1024}])
    archive_name = name + ".payloads.tar.xz"
    manifest = {
        "schema": SCHEMA, "schema_version": 1,
        "saved_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "zlib_runtime_version": zlib.ZLIB_RUNTIME_VERSION,
        "gzip_recipe": {"level": 9, "wbits": -15, "memLevel": 8,
                        "strategy": "Z_DEFAULT_STRATEGY"},
        "archive": archive_name, "archive_bytes": len(archive_bytes),
        "archive_sha256": digest(archive_bytes), "files": files,
        "payloads": {sha: describe(data) for sha, data in payloads.items()},
    }
    destination.mkdir(parents=True, exist_ok=True)
    parts = []
    for number, start in enumerate(range(0, len(archive_bytes), CHUNK_BYTES)):
        part_name = archive_name + f".part{number:03d}"
        data = archive_bytes[start:start + CHUNK_BYTES]
        with (destination / part_name).open("xb") as stream:
            stream.write(data)
        parts.append({"file": part_name, **describe(data)})
    manifest["archive_parts"] = parts
    with (destination / (name + "-evidence.json")).open("x") as stream:
        stream.write(json.dumps(manifest, indent=2) + "\n")
    return {"files": len(files), "payloads": len(payloads),
            "archive_bytes": len(archive_bytes), "parts": len(parts)}


def restore(manifest_path, destination, payloads_only=False):
    if destination.exists():
        raise ValueError("Destination already exists; choose a new directory")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("schema") != SCHEMA or manifest.get("schema_version") != 1:
        raise ValueError("Unsupported evidence schema")
    original_paths = [safe_path(name) for name in manifest["files"]]
    original_names = set(manifest["files"])
    for path in original_paths:
        if any(str(parent) in original_names for parent in path.parents):
            raise ValueError("Evidence paths conflict")
    if set(manifest["payloads"]) != {entry["payload"] for entry in manifest["files"].values()}:
        raise ValueError("Payload membership differs from file mappings")
    for sha, info in manifest["payloads"].items():
        if not re.fullmatch(r"[0-9a-f]{64}", sha) or info["sha256"] != sha:
            raise ValueError("Invalid payload identity")
    chunks, part_names = [], set()
    for part in manifest["archive_parts"]:
        name = part["file"]
        if len(safe_path(name).parts) != 1 or name in part_names:
            raise ValueError("Archive parts must be unique sibling filenames")
        part_names.add(name)
        data = (manifest_path.parent / name).read_bytes()
        check(data, part, name)
        chunks.append(data)
    archive_bytes = b"".join(chunks)
    check(archive_bytes, {"bytes": manifest["archive_bytes"],
                          "sha256": manifest["archive_sha256"]}, "archive")
    payloads = {}
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:xz") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        expected = {"payloads/" + sha for sha in manifest["payloads"]}
        if len(names) != len(set(names)) or set(names) != expected:
            raise ValueError("Archive membership differs from manifest")
        for member in members:
            if not member.isfile():
                raise ValueError("Archive contains a non-regular member")
            sha = member.name.split("/")[1]
            data = archive.extractfile(member).read()
            check(data, manifest["payloads"][sha], member.name)
            payloads[sha] = data
    if payloads_only:
        verified = {"payloads/" + sha: data for sha, data in payloads.items()}
        verified["recovery-manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    else:
        verified = {}
        for name, entry in manifest["files"].items():
            data = decode(payloads[entry["payload"]], entry)
            try:
                check(data, entry, name)
            except ValueError as error:
                raise ValueError(str(error) + "; try the recorded zlib "
                                 + manifest["zlib_runtime_version"]
                                 + " or --payloads-only") from error
            verified[name] = data
    # No output exists until the entire transport and reconstructed file set pass.
    destination.mkdir(parents=True)
    for name, data in verified.items():
        target = destination.joinpath(*safe_path(name).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
    return {"status": "verified_payloads" if payloads_only else "verified_exact_files",
            "files": len(verified), "destination": str(destination)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    packing = actions.add_parser("pack")
    packing.add_argument("source", type=Path)
    packing.add_argument("destination", type=Path)
    packing.add_argument("name")
    unpacking = actions.add_parser("restore")
    unpacking.add_argument("manifest", type=Path)
    unpacking.add_argument("destination", type=Path)
    unpacking.add_argument("--payloads-only", action="store_true")
    args = parser.parse_args()
    if args.action == "pack":
        result = pack(args.source, args.destination, args.name)
    else:
        result = restore(args.manifest, args.destination, args.payloads_only)
    print(json.dumps(result))


if __name__ == "__main__":
    main()

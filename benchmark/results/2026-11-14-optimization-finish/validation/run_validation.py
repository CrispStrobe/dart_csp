#!/usr/bin/env python3
"""Bounded, sequential correctness gates for the final retained Dart source.

Run only after timed collection ends. The output directory must be new or empty.
There are no retries, source writes, dependency resolution, or remote writes.
Each started/completed gate is journaled before proceeding to the next gate.
"""

from __future__ import annotations

import argparse
import datetime as dt
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
import traceback


EXPECTED_ZIP = "90f7fd75fe21e16437778df882f280910d9bbd4809c90024f21de82435dded1d"
EXPECTED_DART = "6f40046d43f5dcd51f788e41c2da23d4e425f8581cd0a38cb6fa4631b37d064b"
EXPECTED_LOCK = "a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a"
EXPECTED_CORPUS = "6816e4ba9e89d16a013f5a58ab208fbb41a61d42c6a8d9e144fe566b5289a696"
CG_REF = "ad8d23704e50c1bf41412f086e66de4a87bfb21b"
PRIOR = "benchmark/results/2026-11-14-optimization-recovery/validation/validation-manifest.json"
FORMAT_FILES = [
    "lib/src/geometry/numeric.dart",
    "lib/src/geometry/solver.dart",
    "test/geometry_cg_test.dart",
    "test/geometry_default_manifold_test.dart",
]


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, data):
    target = Path(path)
    temp = target.with_name(target.name + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, target)


def git(root, *arguments):
    return subprocess.check_output(
        ["git", "-C", str(root), *arguments], timeout=60
    ).decode("utf-8").strip()


def source_snapshot(root):
    # The committed inputs used by all six inherited gates, plus ignored local
    # dependency resolution. Generated test/bytecode caches are not source.
    listed = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "lib", "test", "tool",
         "benchmark/solver_comparison"], timeout=60
    ).decode().split("\0")
    paths = {p for p in listed if p}
    for directory in ("lib", "test", "tool", "benchmark/solver_comparison"):
        for path in (root / directory).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts and path.suffix in (
                ".dart", ".py", ".cjs", ".js", ".json", ".yaml", ".yml", ".sh", ".txt"
            ):
                paths.add(str(path.relative_to(root)))
    paths.update([
        "pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "dart_test.yaml",
        ".dart_tool/package_config.json",
    ])
    records = {}
    for name in sorted(paths):
        path = root / name
        records[name] = digest(path) if path.is_file() else None
    serialized = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return {"sha256": hashlib.sha256(serialized).hexdigest(), "files": records}


def compare_tree(root, reference, directory):
    """Compare exact working file bytes, including added/removed files."""
    output = subprocess.check_output(
        ["git", "-C", str(root), "ls-tree", "-rz", reference, "--", directory],
        timeout=60,
    )
    expected = {}
    for item in output.split(b"\0"):
        if item:
            metadata, path = item.split(b"\t", 1)
            mode, kind, blob = metadata.decode().split()
            if kind != "blob" or mode not in ("100644", "100755"):
                raise ValueError(f"Unexpected source tree entry: {item!r}")
            expected[path.decode()] = blob
    actual = {}
    for path in sorted((root / directory).rglob("*")):
        if path.is_file():
            data = path.read_bytes()
            actual[str(path.relative_to(root))] = hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data
            ).hexdigest()
    differences = [name for name in sorted(expected.keys() | actual.keys())
                   if expected.get(name) != actual.get(name)]
    return {
        "reference": git(root, "rev-parse", reference),
        "tree": git(root, "rev-parse", f"{reference}:{directory}"),
        "file_count": len(actual), "matches": not differences,
        "different_paths": differences,
    }


def stop_group(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)


def run_gate(name, command, root, out, env, manifest, timeout, expected=None):
    stdout = out / f"{name}.stdout.log"
    stderr = out / f"{name}.stderr.log"
    gate = {
        "name": name, "command": command, "cwd": str(root),
        "started_utc": utc(), "timeout_seconds": timeout,
        "stdout": stdout.name, "stderr": stderr.name,
        "status": "running", "exit_code": None, "timed_out": False,
        "expected_tests": expected,
    }
    manifest["gates"].append(gate)
    write_json(out / "validation-manifest.json", manifest)
    print(json.dumps({"gate": name, "status": "started", "utc": gate["started_utc"]}), flush=True)
    started = time.monotonic()
    process = None
    interrupted = False
    try:
        with stdout.open("wb") as so, stderr.open("wb") as se:
            process = subprocess.Popen(command, cwd=root, env=env, stdout=so,
                                       stderr=se, start_new_session=True)
            try:
                gate["exit_code"] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                gate["timed_out"] = True
                stop_group(process)
                gate["exit_code"] = process.returncode
            except BaseException:
                interrupted = True
                stop_group(process)
                gate["exit_code"] = process.returncode
                raise
    except (OSError, subprocess.SubprocessError) as error:
        gate["launch_error"] = repr(error)
    finally:
        if process is not None and process.poll() is None:
            stop_group(process)
        gate["finished_utc"] = utc()
        gate["elapsed_seconds"] = time.monotonic() - started
        gate["interrupted"] = interrupted
        text = ""
        for channel, path in (("stdout", stdout), ("stderr", stderr)):
            if path.exists():
                gate[f"{channel}_sha256"] = digest(path)
                gate[f"{channel}_bytes"] = path.stat().st_size
                text += path.read_text(encoding="utf-8", errors="replace") + "\n"
        gate["passed"] = gate["exit_code"] == 0 and not gate["timed_out"] and not interrupted
        if expected is not None:
            if name.startswith("python-"):
                matches = re.findall(r"Ran (\d+) tests? in ", text)
                success_marker = re.search(r"^OK(?:\s*\([^\n]*\))?$", text, re.MULTILINE) is not None
                skipped = re.findall(r"skipped=(\d+)", text)
                gate["tests_skipped"] = int(skipped[-1]) if skipped else 0
            else:
                matches = re.findall(r"\+(\d+)(?:\s+~\d+)?(?:\s+-\d+)?: All tests passed!", text)
                success_marker = "All tests passed!" in text
                skipped = re.findall(r"\+\d+\s+~(\d+)(?:\s+-\d+)?: All tests passed!", text)
                gate["tests_skipped"] = int(skipped[-1]) if skipped else 0
            gate["tests_passed"] = int(matches[-1]) if matches else None
            gate["success_marker_found"] = success_marker
            gate["test_count_matches_expected"] = gate["tests_passed"] == expected
            gate["passed"] &= success_marker and gate["test_count_matches_expected"] and gate["tests_skipped"] == 0
        gate["status"] = "passed" if gate["passed"] else "failed"
        write_json(out / "validation-manifest.json", manifest)
        print(json.dumps({k: gate.get(k) for k in
              ("name", "status", "exit_code", "timed_out", "tests_passed", "elapsed_seconds")}), flush=True)
    return gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timing-complete", action="store_true", required=True,
                        help="Caller confirms timed benchmark collection has ended.")
    parser.add_argument("--expected-library-ref", default=CG_REF)
    parser.add_argument("--expected-test-ref", default="545a1ab")
    parser.add_argument("--expected-tool-tests", type=int, default=27)
    parser.add_argument("--skip-format", action="store_true")
    args = parser.parse_args()
    root, runtime, out = args.source.resolve(), args.runtime.resolve(), args.output.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error(f"Refusing to overwrite nonempty evidence directory: {out}")
    out.mkdir(parents=True, exist_ok=True)
    dart = runtime / "dart-sdk/bin/dart"
    env = os.environ.copy()
    overrides = {
        "PUB_CACHE": str(runtime / "pub-cache"),
        "TMPDIR": str(runtime / "tmp"),
        "XDG_CONFIG_HOME": str(runtime / "config"),
        "DART_SUPPRESS_ANALYTICS": "true", "CI": "true", "NO_COLOR": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONPYCACHEPREFIX": str(runtime / "python-cache"),
        "PATH": str(dart.parent) + os.pathsep + os.environ.get("PATH", ""),
    }
    env.update(overrides)
    for variable in ("PUB_CACHE", "TMPDIR", "XDG_CONFIG_HOME", "PYTHONPYCACHEPREFIX"):
        Path(overrides[variable]).mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema_version": 2, "status": "preparing", "started_utc": utc(),
        "source_root": str(root), "runtime_root": str(runtime),
        "environment": overrides, "gates": [],
        "execution_policy": "Sequential bounded gates, no retries; caller confirms timing complete.",
        "browser_boundary": "Node compiled-code tests; no real-browser claim.",
        "platform": platform.platform(),
    }
    before = None
    signal.signal(signal.SIGTERM, lambda signum, frame: (_ for _ in ()).throw(KeyboardInterrupt("SIGTERM")))
    try:
        write_json(out / "validation-manifest.json", manifest)
        shutil.copyfile(Path(__file__).resolve(), out / "run_validation.py")
        manifest["runner_sha256"] = digest(out / "run_validation.py")
        manifest["source_commit"] = git(root, "rev-parse", "HEAD")
        manifest["library_tree_at_head"] = git(root, "rev-parse", "HEAD:lib")
        manifest["test_tree_at_head"] = git(root, "rev-parse", "HEAD:test")
        manifest["working_source_diff"] = git(root, "diff", "--stat", "HEAD", "--", "lib", "test", "tool", "pubspec.yaml")
        manifest["library_comparison"] = compare_tree(root, args.expected_library_ref, "lib")
        manifest["test_comparison"] = compare_tree(root, args.expected_test_ref, "test")
        if not manifest["library_comparison"]["matches"] or not manifest["test_comparison"]["matches"]:
            raise ValueError("Working library or tests differ from the declared retained source.")
        prior_path = root / PRIOR
        prior = json.loads(prior_path.read_text())
        shutil.copyfile(prior_path, out / "prior-validation-manifest.json")
        manifest["inherited_validation_manifest"] = {"path": PRIOR, "sha256": digest(prior_path)}
        corpus = prior["portable_corpus"]
        corpus_text = "\n".join(corpus) + "\n"
        corpus_hash = hashlib.sha256(corpus_text.encode()).hexdigest()
        if len(corpus) != 54 or len(set(corpus)) != 54 or corpus_hash != EXPECTED_CORPUS:
            raise ValueError("Prior portable corpus differs from its pinned 54-file declaration.")
        if (root / "tool/performance_cad_tests.txt").read_text() != corpus_text:
            raise ValueError("Portable corpus file differs from the inherited gate command.")
        if any(not (root / name).is_file() for name in corpus):
            raise ValueError("Missing portable test source.")
        (out / "portable-corpus.txt").write_text(corpus_text)
        manifest["portable_corpus"] = corpus
        manifest["portable_corpus_sha256"] = corpus_hash
        manifest["portable_corpus_count"] = len(corpus)
        zip_path = runtime / "dart-sdk.zip"
        sdk_files = [dart, dart.parent / "dartaotruntime", dart.parent / "dartvm"]
        sdk_files += [dart.parent / "snapshots" / name for name in (
            "dartdev_aot.dart.snapshot", "gen_kernel_aot.dart.snapshot",
            "dart2js_aot.dart.snapshot", "dart2wasm_product.snapshot",
            "analysis_server_aot.dart.snapshot",
        )]
        manifest["sdk"] = {"zip": str(zip_path), "zip_sha256": digest(zip_path),
                           "executable": str(dart), "executable_sha256": digest(dart),
                           "compiler_files_sha256": {str(p.relative_to(runtime)): digest(p)
                                                     for p in sdk_files if p.is_file()}}
        if manifest["sdk"]["zip_sha256"] != EXPECTED_ZIP or manifest["sdk"]["executable_sha256"] != EXPECTED_DART:
            raise ValueError("Dart runtime does not match pinned archive and executable hashes.")
        lock = root / "pubspec.lock"
        manifest["pubspec_lock_before_sha256"] = digest(lock)
        manifest["canonical_lock_sha256"] = digest(runtime / "canonical-pubspec.lock")
        if manifest["pubspec_lock_before_sha256"] != EXPECTED_LOCK or manifest["canonical_lock_sha256"] != EXPECTED_LOCK:
            raise ValueError("Dependency lock differs from canonical pinned lock.")
        if not (root / ".dart_tool/package_config.json").is_file():
            raise ValueError("Prepare package resolution before running correctness gates.")
        shutil.copyfile(lock, out / "dependency-lock.yaml")
        shutil.copyfile(root / ".dart_tool/package_config.json", out / "package-config.json")
        node = shutil.which("node", path=env["PATH"])
        if not node:
            raise ValueError("Node is required for the declared portable gates.")
        manifest["node"] = {"executable": node, "executable_sha256": digest(node)}
        manifest["python"] = {"executable": sys.executable, "version": sys.version,
                              "executable_sha256": digest(sys.executable)}
        try:
            manifest["allowed_cpus"] = sorted(os.sched_getaffinity(0))
        except AttributeError:
            manifest["allowed_cpus"] = None
        if Path("/proc/cpuinfo").exists():
            matches = re.findall(r"^model name\s*:\s*(.+)$", Path("/proc/cpuinfo").read_text(), re.MULTILINE)
            manifest["cpu_model"] = matches[0] if matches else None
        before = source_snapshot(root)
        write_json(out / "source-inputs-before.json", before)
        manifest["source_inputs_before_sha256"] = before["sha256"]
        manifest["status"] = "running"
        write_json(out / "validation-manifest.json", manifest)
        for name, command in (("sdk-version", [str(dart), "--version"]),
                              ("node-version", [node, "--version"])):
            gate = run_gate(name, command, root, out, env, manifest, 30)
            if not gate["passed"]:
                raise ValueError(f"Required runtime metadata command failed: {name}")
        manifest["sdk"]["version"] = ((out / "sdk-version.stdout.log").read_text() +
                                       (out / "sdk-version.stderr.log").read_text()).strip()
        manifest["node"]["version"] = (out / "node-version.stdout.log").read_text().strip()
        if "Dart SDK version: 3.14.0 " not in manifest["sdk"]["version"]:
            raise ValueError("Unexpected Dart SDK version string.")
        if not args.skip_format:
            run_gate("format", [str(dart), "format", "--output=none", "--set-exit-if-changed", *FORMAT_FILES],
                     root, out, env, manifest, 120)
        inherited = {gate["name"]: gate for gate in prior["gates"]}
        for name, timeout, expected in [
            ("analyze", 600, None), ("native", 600, 1891),
            ("dart2js", 900, 570), ("dart2wasm", 900, 570),
            ("python-solver-harness", 180, 51),
            ("python-tool-harness", 180, args.expected_tool_tests),
        ]:
            command = list(inherited[name]["command"])
            command[0] = sys.executable if name.startswith("python-") else str(dart)
            if name in ("dart2js", "dart2wasm"):
                if [part for part in command if part.startswith("test/")] != corpus:
                    raise ValueError(f"Inherited {name} command and corpus disagree.")
            run_gate(name, command, root, out, env, manifest, timeout, expected)
        manifest["status"] = "passed" if all(g["passed"] for g in manifest["gates"]) else "failed"
    except BaseException as error:
        manifest["status"] = "interrupted" if isinstance(error, KeyboardInterrupt) else "failed"
        manifest["error"] = repr(error)
        (out / "runner-error.log").write_text(traceback.format_exc())
        print(json.dumps({"status": manifest["status"], "error": repr(error)}), flush=True)
    finally:
        try:
            if before is not None:
                after = source_snapshot(root)
                write_json(out / "source-inputs-after.json", after)
                manifest["source_inputs_after_sha256"] = after["sha256"]
                changes = [name for name in sorted(before["files"].keys() | after["files"].keys())
                           if before["files"].get(name) != after["files"].get(name)]
                manifest["source_input_changes_after_validation"] = changes
                manifest["pubspec_lock_after_sha256"] = digest(root / "pubspec.lock")
                manifest["canonical_lock_unchanged"] = manifest["pubspec_lock_after_sha256"] == EXPECTED_LOCK
                if changes or not manifest["canonical_lock_unchanged"]:
                    manifest["status"] = "failed"
        except Exception as error:
            manifest["final_snapshot_error"] = repr(error)
            manifest["status"] = "failed"
        manifest["finished_utc"] = utc()
        write_json(out / "validation-manifest.json", manifest)
        checksums = {p.name: {"sha256": digest(p), "bytes": p.stat().st_size}
                     for p in sorted(out.iterdir()) if p.is_file() and p.name != "checksums.json"}
        write_json(out / "checksums.json", checksums)
    print(json.dumps({"status": manifest["status"], "output": str(out),
                      "gates": [{k: g.get(k) for k in ("name", "passed", "tests_passed")}
                                for g in manifest["gates"]]}), flush=True)
    return 0 if manifest["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())

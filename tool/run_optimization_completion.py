#!/usr/bin/env python3
"""Bounded, independently checked optimization cohorts with remote checkpoints.

Run only from a dedicated GitHub Actions branch. Evidence commits never force
push. Every compiled source is committed and identified by the frozen harness.
"""
from __future__ import annotations

import copy
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tarfile
import traceback

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "perf/optimization-complete-2026-11-14"
RUN_KEY = os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
WORK = Path(os.environ["RUNNER_TEMP"]) / "dart-csp-completion" / RUN_KEY
RESULTS = WORK / "results"
LOGS = WORK / "logs"
SAVE = ROOT / "benchmark/results/2026-11-14-actions-completion" / RUN_KEY
HARNESS = ROOT / "benchmark/solver_comparison/paired_dart_backends.py"
PACKER = ROOT / "benchmark/results/2026-11-14-performance-followup/pack_checkpoint.py"
REFS = {
    "packed": "080e0fed0b80f9ecd88d66fc20061e468be4cce5",
    "cg": "ad8d23704e50c1bf41412f086e66de4a87bfb21b",
}
FIXTURES = "ladder_25_components_1,ladder_500_components_1,laman_free_100,laman_free_500"
SENTINELS = "ladder_25_components_1,ladder_500_components_1,laman_free_100"
QUALIFICATION = (
    "canonical_cell,axis_rectangle,coincidence,contradictory_distance,"
    "ladder_3_components_1,ladder_1_components_1_scale_1e-06,"
    "ladder_125_components_1,ladder_500_components_1,laman_free_500"
)
STATUS = {"schema_version": 1, "run_key": RUN_KEY, "completed": []}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def run(name, command, cwd=ROOT, timeout=900):
    command = [str(arg) for arg in command]
    print(json.dumps({"stage": name, "command": command, "started": now()}), flush=True)
    path = LOGS / (name + ".log")
    with path.open("w") as output:
        output.write(json.dumps({"command": command, "cwd": str(cwd)}) + "\n")
        output.flush()
        result = subprocess.run(command, cwd=cwd, stdout=output,
                                stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        print(path.read_text(errors="replace")[-12000:], flush=True)
        raise RuntimeError(f"{name} exited {result.returncode}; see {path.name}")
    return result


def checkpoint(stage):
    STATUS.update(stage=stage, updated_utc=now())
    dump(SAVE / "status.json", STATUS)
    shutil.copytree(LOGS, SAVE / "logs", dirs_exist_ok=True)
    git("add", "--", str(SAVE.relative_to(ROOT)))
    if subprocess.run(["git", "-C", str(ROOT), "diff", "--cached",
                       "--quiet"]).returncode == 0:
        return
    git("-c", "user.name=github-actions[bot]", "-c",
        "user.email=41898282+github-actions[bot]@users.noreply.github.com",
        "commit", "-m", f"bench: preserve {RUN_KEY} {stage}")
    # A concurrent branch update safely rejects this push. Never force or
    # silently rebase a measurement's source; the always-upload artifact remains.
    run("push-" + stage, ["git", "push", "origin", f"HEAD:refs/heads/{BRANCH}"],
        timeout=120)
    print(json.dumps({"checkpoint": stage, "commit": git("rev-parse", "HEAD")}),
          flush=True)


def pack(name, source, omit=()):
    command = [sys.executable, PACKER, source, SAVE, name]
    for path in omit:
        command += ["--omit", path]
    run("pack-" + name, command, timeout=300)


def canonical_lock():
    directory = ROOT / "benchmark/results/2026-11-14-optimization-resume"
    manifest = json.loads((directory / "cg-prepared-evidence.json").read_text())
    chunks = []
    for entry in manifest["archive_parts"]:
        data = (directory / entry["file"]).read_bytes()
        if len(data) != entry["bytes"] or digest(data) != entry["sha256"]:
            raise ValueError("Saved preparation part hash mismatch")
        chunks.append(data)
    data = b"".join(chunks)
    if digest(data) != manifest["archive_sha256"]:
        raise ValueError("Saved preparation archive hash mismatch")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:xz") as archive:
        source = archive.extractfile("before/source.tar.gz").read()
    with tarfile.open(fileobj=io.BytesIO(source), mode="r:gz") as archive:
        lock = archive.extractfile("pubspec.lock").read()
    if digest(lock) != "a82c991d417a2094312349d14b0c9f19866b5ea402f93c0c32282326a643b84a":
        raise ValueError("Canonical lock hash mismatch")
    return lock


def derive_preparation(name, before_dir, after_dir, identical=False):
    output = RESULTS / ("prepared-" + name)
    output.mkdir()
    before = json.loads((before_dir / "prepared.json").read_text())
    after = json.loads((after_dir / "prepared.json").read_text())
    if before["harness_sha256"] != after["harness_sha256"]:
        raise ValueError("Cannot combine different harnesses")
    manifest = copy.deepcopy(before)
    manifest["purpose"] = ("Identical executable control" if identical else
                           "Combined endpoints from frozen candidate preparations")
    manifest["derived_from"] = {
        str(before_dir): digest((before_dir / "prepared.json").read_bytes()),
        str(after_dir): digest((after_dir / "prepared.json").read_bytes()),
    }
    shutil.copytree(before_dir / "harness", output / "harness")
    choices = {"before": (before_dir, before["variants"]["before"]),
               "after": (before_dir, before["variants"]["before"]) if identical
               else (after_dir, after["variants"]["after"])}
    for label, (origin, item) in choices.items():
        item = copy.deepcopy(item)
        destination = output / label
        destination.mkdir()
        for field, filename in [("source_archive", "source.tar.gz"),
                                ("executable", "dart-adapter")]:
            shutil.copy2(origin / item[field], destination / filename)
            item[field] = label + "/" + filename
        manifest["variants"][label] = item
    dump(output / "prepared.json", manifest)
    if identical and (manifest["variants"]["before"]["executable_sha256"] !=
                      manifest["variants"]["after"]["executable_sha256"]):
        raise ValueError("A/A labels must use identical executable bytes")
    return output


def collect(name, prepared, fixtures, round_index, qualification=False):
    output = RESULTS / name
    command = [
        sys.executable, HARNESS, "run", "--prepared", prepared,
        "--purpose", "qualification" if qualification else "measurement",
        "--suites", "smoke,confirm,coupled" if qualification else "confirm,coupled",
        "--fixtures", fixtures, "--engines", "dart_2d_analytic,dart_3d_ad",
        "--modes", "cold,warm", "--rounds", "1",
        "--start-round", str(round_index),
        "--warmups", "1" if qualification else "8",
        "--samples", "2" if qualification else "21",
        "--timeout", "30", "--cpu", "auto" if hasattr(os, "sched_setaffinity") else "none",
        "--out", output,
    ]
    if qualification:
        command += ["--variants", "after"]
    run(name, command, timeout=1200)
    summary = json.loads((output / "comparison.json").read_text())
    # Preserve even failed comparisons before stopping.
    pack(name, output)
    dump(SAVE / (name + "-summary.json"), summary)
    STATUS["completed"].append(name)
    checkpoint(name)
    if not summary["protocol_ok"] or not summary["qualification_passed"]:
        raise RuntimeError(f"{name}: protocol or physical qualification failed")
    return output


def aggregate(name, directories):
    for variant in ["before", "after"]:
        run("analyze-" + name + "-" + variant,
            [sys.executable, ROOT / "benchmark/solver_comparison/analyze.py",
             *[directory / variant for directory in directories],
             "--metrics", "--out", RESULTS / (name + "-aggregate-" + variant)])
        pack(name + "-aggregate-" + variant,
             RESULTS / (name + "-aggregate-" + variant))


def main():
    if os.environ.get("GITHUB_REF_NAME") != BRANCH:
        raise ValueError("This bounded experiment is restricted to its dedicated branch")
    for path in [WORK, RESULTS, LOGS, SAVE]:
        path.mkdir(parents=True, exist_ok=True)
    if any(SAVE.iterdir()):
        raise ValueError("Never overwrite an existing run checkpoint")
    STATUS.update(started_utc=now(), triggering_sha=os.environ["GITHUB_SHA"],
                  branch=BRANCH, workflow_url=os.environ["GITHUB_SERVER_URL"] + "/" +
                  os.environ["GITHUB_REPOSITORY"] + "/actions/runs/" +
                  os.environ["GITHUB_RUN_ID"])
    dart = Path(shutil.which("dart")).resolve()
    version = subprocess.check_output([str(dart), "--version"], text=True).strip()
    if "Dart SDK version: 3.14.0 " not in version:
        raise ValueError("Experiment requires pinned Dart 3.14.0")
    dump(SAVE / "environment.json", {
        "started_utc": now(), "platform": platform.platform(),
        "machine": platform.machine(), "python": sys.version,
        "dart": version, "dart_executable_sha256": digest(dart.read_bytes()),
        "node": subprocess.check_output(["node", "--version"], text=True).strip(),
        "affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
        "cohort_note": "Fresh hosted-runner cohort; never pooled with prior Linux samples.",
    })
    checkpoint("started")
    lock = canonical_lock()
    (ROOT / "pubspec.lock").write_bytes(lock)
    run("candidate-pub-get", [dart, "pub", "get", "--enforce-lockfile"])
    # Formatting is source work, completed and committed before qualification.
    source_paths = ["lib/src/geometry/solver.dart",
                    "test/geometry_default_manifold_test.dart"]
    run("format-candidate", [dart, "format", *source_paths])
    if git("diff", "--name-only", "--", *source_paths):
        git("add", "--", *source_paths)
        git("-c", "user.name=github-actions[bot]", "-c",
            "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "commit", "-m", "style: format the default-manifold candidate")
        run("push-formatted-source",
            ["git", "push", "origin", f"HEAD:refs/heads/{BRANCH}"], timeout=120)
    candidate_sha = git("rev-parse", "HEAD")
    STATUS["candidate_source_sha"] = candidate_sha
    run("focused", [dart, "test", "--reporter", "expanded",
        "test/geometry_default_manifold_test.dart",
        "test/geometry_numeric_test.dart", "test/geometry_preferences_test.dart",
        "test/geometry_workspace_reuse_test.dart", "test/geometry_session_fork_test.dart",
        "test/geometry_result_snapshot_test.dart", "test/geometry_declaration_snapshot_test.dart",
        "test/geometry_cg_test.dart"])
    run("analyze", [dart, "analyze", "--fatal-infos"])
    run("native", [dart, "test", "--reporter", "expanded"], timeout=1200)
    portable = (ROOT / "tool/performance_cad_tests.txt").read_text().split()
    for compiler in ["dart2js", "dart2wasm"]:
        run(compiler, [dart, "test", "-p", "node", "--compiler", compiler,
                       "--reporter", "expanded", *portable], timeout=1200)
    run("python-solver-harness", [sys.executable, "-m", "unittest", "discover",
        "-s", "benchmark/solver_comparison", "-p", "test_*.py", "-v"])
    run("python-tool-harness", [sys.executable, "-m", "unittest", "discover",
        "-s", "tool", "-p", "test_*.py", "-v"])
    STATUS["correctness_gates"] = "passed"
    checkpoint("correctness")
    roots = {}
    for label, ref in REFS.items():
        root = WORK / label
        run("worktree-" + label, ["git", "worktree", "add", "--detach", root, ref])
        (root / "pubspec.lock").write_bytes(lock)
        run("pub-get-" + label, [dart, "pub", "get", "--enforce-lockfile"], cwd=root)
        roots[label] = root
    roots["candidate"] = ROOT
    preparations = {}
    for name, before, after in [("cg", "packed", "cg"),
                                ("identity", "cg", "candidate")]:
        prepared = RESULTS / ("prepared-" + name)
        run("prepare-" + name, [sys.executable, HARNESS, "prepare",
            "--before", roots[before], "--after", roots[after],
            "--dart", dart, "--out", prepared], timeout=900)
        preparations[name] = prepared
    preparations["combined"] = derive_preparation(
        "combined", preparations["cg"], preparations["identity"])
    preparations["aa"] = derive_preparation(
        "aa", preparations["cg"], preparations["cg"], identical=True)
    for name, prepared in preparations.items():
        pack("prepared-" + name, prepared,
             omit=("before/dart-adapter", "after/dart-adapter"))
    checkpoint("prepared")
    for name in ["cg", "identity"]:
        collect("qualification-" + name, preparations[name], QUALIFICATION, 0, True)
    # All compilation and test work has finished before timed cohorts.
    cohorts = {}
    for name in ["cg", "identity", "combined", "aa"]:
        cohorts[name] = []
        for index in range(4):
            cohorts[name].append(collect(name + "-round" + str(index + 1),
                preparations[name], SENTINELS if name == "aa" else FIXTURES, index))
    for name, directories in cohorts.items():
        aggregate(name, directories)
    STATUS.update(status="complete", finished_utc=now(),
                  next_action="Review every physical result, work counter, order stratum and A/A control before retention.")
    checkpoint("complete")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        traceback.print_exc()
        if SAVE.exists() and LOGS.exists():
            STATUS.update(status="failed", error=str(error), failed_utc=now(),
                          next_action="Inspect saved logs and partial raw workflow artifact; no performance conclusion.")
            try:
                checkpoint("failed")
            except Exception:
                traceback.print_exc()
        raise

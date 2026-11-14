#!/usr/bin/env python3
"""Collect one bounded optimization block and preserve complete or partial data.

Push the resulting checkpoint before invoking this tool for another block.
Existing outputs are never overwritten. Frozen builds must precede timing.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = [
    "axis_rectangle", "ladder_3_components_1", "ladder_25_components_1",
    "ladder_500_components_1", "laman_free_100", "laman_free_500",
]
QUALIFICATION = [
    "canonical_cell", "axis_rectangle", "coincidence", "contradictory_distance",
    "ladder_3_components_1", "ladder_1_components_1_scale_1e-06",
    "ladder_125_components_1", "ladder_500_components_1", "laman_free_500",
]


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def write_status(path, status):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(status, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cohort", choices=["cg", "identity", "combined", "aa"])
    parser.add_argument("round", type=int, choices=range(1, 5))
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--save", required=True, type=Path)
    parser.add_argument("--qualification", action="store_true")
    parser.add_argument("--cpu", default="0")
    parser.add_argument("--environment-cohort", default="2026-11-14-optimization-recovery")
    parser.add_argument("--compact-evidence", action="store_true",
                        help="Preserve exact raw evidence using the compact payload archive")
    args = parser.parse_args()
    workspace, saved = args.workspace.resolve(), args.save.resolve()
    name = ("qualification-" + args.cohort if args.qualification else
            f"{args.cohort}-round{args.round}")
    output = workspace / "runs" / name
    log = saved / (name + ".log")
    status_path = saved / (name + "-status.json")
    if (output.exists() or status_path.exists() or log.exists()
            or (saved / (name + "-summary.json")).exists()
            or (saved / (name + "-evidence.json")).exists()
            or any(saved.glob(name + ".tar.xz*"))
            or any(saved.glob(name + ".payloads.tar.xz*"))):
        raise ValueError("A completed or interrupted block must not be overwritten")
    saved.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    fixtures = QUALIFICATION if args.qualification else (
        FIXTURES[:-1] if args.cohort == "aa" else FIXTURES)
    command = [
        sys.executable, str(ROOT / "benchmark/solver_comparison/paired_dart_backends.py"),
        "run", "--prepared", str(workspace / ("prepared-" + args.cohort)),
        "--purpose", "qualification" if args.qualification else "measurement",
        "--suites", "smoke,confirm,coupled", "--fixtures", ",".join(fixtures),
        "--engines", "dart_2d_analytic,dart_3d_ad", "--modes", "cold,warm",
        "--rounds", "1", "--start-round", str(args.round - 1),
        "--warmups", "1" if args.qualification else "8",
        "--samples", "2" if args.qualification else "21",
        "--timeout", "30", "--cpu", args.cpu, "--out", str(output),
    ]
    if args.qualification:
        command += ["--variants", "after"]
    status = {
        "schema_version": 1, "name": name, "cohort": args.cohort,
        "round": args.round, "command": command, "started_utc": now(),
        "environment_cohort": args.environment_cohort,
        "compact_evidence": args.compact_evidence,
        "state": "collecting", "passed": False,
    }
    recovery_path = saved / "recovery.json"
    if recovery_path.is_file():
        recovery_bytes = recovery_path.read_bytes()
        recovery = json.loads(recovery_bytes)
        if recovery.get("timing_cohort") != args.environment_cohort:
            raise ValueError("Recovery and requested timing cohorts differ")
        status["session_id"] = recovery["session_id"]
        status["recovery_sha256"] = hashlib.sha256(recovery_bytes).hexdigest()
    write_status(status_path, status)
    error = None
    try:
        with log.open("w") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream,
                                       stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                exit_code = process.wait(timeout=900)
            except BaseException:
                # Stop the whole collection group before archiving partial data.
                # The harness otherwise may still have a solver child writing.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                if process.poll() is None:
                    process.wait(timeout=5)
                raise
        status["exit_code"] = exit_code
        summary_path = output / "comparison.json"
        if summary_path.exists():
            summary = json.loads(summary_path.read_text())
            shutil.copyfile(summary_path, saved / (name + "-summary.json"))
            status["groups"] = len(summary["groups"])
            status["measured_operations"] = sum(
                group[side]["main"]["completed"]
                for group in summary["groups"] for side in ("before", "after")
                if group.get(side) is not None)
            status["passed"] = (exit_code == 0 and summary["protocol_ok"]
                                and summary["qualification_passed"])
    except BaseException as exception:
        error = exception
        status["error"] = repr(exception)
    finally:
        status.update(completed_utc=now(), state="packing")
        write_status(status_path, status)
        if output.exists():
            try:
                pack_command = [sys.executable]
                if args.compact_evidence:
                    pack_command += [str(ROOT / "tool/pack_optimization_evidence.py"), "pack"]
                else:
                    pack_command += [str(ROOT / "benchmark/results/2026-11-14-performance-followup/pack_checkpoint.py")]
                pack_command += [str(output), str(saved), name]
                packed = subprocess.run(pack_command, cwd=ROOT, timeout=300)
                status["pack_exit_code"] = packed.returncode
                if packed.returncode:
                    status["passed"] = False
            except BaseException as exception:
                status["pack_error"] = repr(exception)
                status["passed"] = False
        else:
            status["passed"] = False
        status.update(state="ready_for_remote_checkpoint", packed_utc=now())
        write_status(status_path, status)
    print(json.dumps(status), flush=True)
    if error or not status["passed"]:
        raise RuntimeError("Collection failed; save its partial evidence before investigation") from error


if __name__ == "__main__":
    main()

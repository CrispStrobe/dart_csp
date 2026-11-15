#!/usr/bin/env python3
"""Check the declared final optimization protocol independently of run manifests.

This metadata gate complements analyze_recovery.py's raw geometry/timing audit.
The default requires all sixteen blocks; an explicit subset is marked partial.
Session provenance binds recovery.json, status hashes and original command paths,
so the audit can also run after restoring evidence to a different directory.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import itertools
import json
from pathlib import Path, PurePosixPath
import re
import sys


COHORTS = ("cg", "identity", "combined", "aa")
ENVIRONMENT_COHORT = "2026-11-14-optimization-final"
FIXTURES = (
    "axis_rectangle", "ladder_3_components_1", "ladder_25_components_1",
    "ladder_500_components_1", "laman_free_100", "laman_free_500",
)
ENGINES = ("dart_2d_analytic", "dart_3d_ad")
MODES = ("cold", "warm")
SIDES = ("before", "after")
SAMPLES, WARMUPS, TIMEOUT, CPU = 21, 8, 30, 0
FULL_TOTALS = {"blocks": 16, "processes": 736,
               "measured_operations": 15456, "warmup_operations": 5888}
# Independently anchored to the immutable recovery preparation, saved at b0820ed.
PREPARED_SHA256 = {
    "cg": "4df615088766bb50d57300d6d2f9f61bb419345db59acc077ff1499ceee93088",
    "identity": "bfcf437981ee24a63b7371a58f21a8d23d0aac5afcc1537c447d70078d4c9289",
    "combined": "6a44fbcde1157454e3c1a3ab284c932b0cac40f08905a33cb8ee6728f7b33518",
    "aa": "b7dc9bf2f5d2a14e5209ad120b014fdb561437a456f6f42c77a26913b1aa46a7",
}
ENDPOINTS = {
    "packed": ("080e0fed0b80f9ecd88d66fc20061e468be4cce5",
               "cd022f064ab615e9481175b6a63acbbe7303c84d0b99fce60edab99ba85258e2"),
    "cg": ("ad8d23704e50c1bf41412f086e66de4a87bfb21b",
           "ca390bb240d24ce553e3de3aedb55784377fc17b1696f1643a5656d7cd90e9d0"),
    "combined": ("57a0a0d68be5f2fb12b3a08734b79f8f2ded4ea4",
                 "3551aab29dbe1e46942523db16827068dbe41096e060435e0acde0faf5754280"),
}
PAIRS = {"cg": ("packed", "cg"), "identity": ("cg", "combined"),
         "combined": ("packed", "combined"), "aa": ("packed", "packed")}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    def reject(value):
        raise ValueError("Nonfinite JSON constant: " + value)
    return json.loads(path.read_bytes(), parse_constant=reject)


def stamp(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(result.tzinfo is not None, "Timestamp has no timezone")
    return result.astimezone(timezone.utc)


def session_path(value, session):
    path = PurePosixPath(value)
    require(path.parts[:4] == ("/", "workspace", "scratch", session)
            and ".." not in path.parts, "Command path belongs to another session: " + value)
    return path


def options(command):
    require(len(command) >= 3 and command[2] == "run", "Unexpected collection command")
    args = command[3:]
    require(len(args) % 2 == 0, "Malformed collection options")
    result = {}
    for name, value in zip(args[::2], args[1::2]):
        require(name.startswith("--") and name not in result, "Duplicate or malformed option")
        result[name] = value
    return result


def check_nonoverlap(intervals, label):
    ordered = sorted(intervals)
    for start, end, name in ordered:
        require(start < end, label + " interval is empty or reversed: " + name)
    for before, after in zip(ordered, ordered[1:]):
        require(before[1] <= after[0], label + " intervals overlap: " + before[2] + " / " + after[2])
    return ordered


def audit(runs, saved, cohorts=COHORTS, rounds=4, start_round=1):
    require(cohorts and len(set(cohorts)) == len(cohorts)
            and set(cohorts) <= set(COHORTS), "Unknown or duplicate cohort selection")
    require(type(rounds) is int and 1 <= rounds <= 4, "Rounds must be 1 through 4")
    require(type(start_round) is int and 1 <= start_round <= 4,
            "Start round must be 1 through 4")
    require(start_round + rounds <= 5, "Selected round range exceeds round 4")
    cohorts = tuple(c for c in COHORTS if c in cohorts)
    selected_rounds = range(start_round, start_round + rounds)
    full = cohorts == COHORTS and start_round == 1 and rounds == 4
    recovery_path = saved / "recovery.json"
    recovery = read(recovery_path)
    recovery_sha = digest(recovery_path.read_bytes())
    session = recovery["session_id"]
    require(isinstance(session, str) and re.fullmatch(r"[A-Za-z0-9_-]+", session),
            "Invalid recovery session identity")
    require(recovery["timing_cohort"] == ENVIRONMENT_COHORT
            and recovery["historical_timings_separate"] is True, "Recovery cohort mismatch")
    earliest = stamp(recovery["observed_utc"])
    expected_restored = {
        ("prepared-" + c, side, *ENDPOINTS[endpoint])
        for c in COHORTS for side, endpoint in zip(SIDES, PAIRS[c])}
    restored = recovery["restored_executables"]
    require(len(restored) == 8 and {
        (row["cohort"], row["variant"], row["source"], row["sha256"])
        for row in restored} == expected_restored, "Recovered source/executable identities differ")
    prepared = {}
    for c in cohorts:
        path = runs.parent / ("prepared-" + c) / "prepared.json"
        require(digest(path.read_bytes()) == PREPARED_SHA256[c], "Frozen preparation hash differs: " + c)
        prepared[c] = read(path)
        require(prepared[c]["status"] == "complete", "Preparation incomplete")
        for side, endpoint in zip(SIDES, PAIRS[c]):
            item = prepared[c]["variants"][side]
            require((item["source"]["source_commit"], item["executable_sha256"])
                    == ENDPOINTS[endpoint], "Prepared source/executable differs")
    expected_blocks = [f"{c}-round{n}" for n in selected_rounds for c in cohorts]
    if full:
        observed = {p.name for p in runs.iterdir() if p.is_dir()
                    and re.fullmatch(r"(?:cg|identity|combined|aa)-round\d+", p.name)}
        require(observed == set(expected_blocks), "Full block population differs from declaration")
    totals, blocks, process_intervals, block_intervals = Counter(), [], [], []
    for number in selected_rounds:
        for c in cohorts:
            name = f"{c}-round{number}"
            directory = runs / name
            m = read(directory / "manifest.json")
            status = read(saved / (name + "-status.json"))
            fixtures = FIXTURES[:-1] if c == "aa" else FIXTURES
            keys = set(itertools.product(fixtures, ENGINES, MODES, SIDES))
            expected = {
                "status": "complete", "purpose": "measurement", "rounds": 1,
                "start_round": number - 1, "samples": SAMPLES, "warmups": WARMUPS,
                "timeout_seconds": TIMEOUT, "pinned_cpu": CPU,
                "fixture_ids": list(fixtures), "engines": list(ENGINES),
                "modes": list(MODES), "variants": list(SIDES),
                "suites": "smoke,confirm,coupled", "protocol_ok": True,
                "qualification_passed": True, "prepared_manifest_sha256": PREPARED_SHA256[c],
                "preparation": prepared[c], "harness_sha256": prepared[c]["harness_sha256"],
                "platform": recovery["platform"], "cpu_model": recovery["cpu_model"],
                "allowed_cpus": recovery["affinity"],
                "thread_environment": {k: "1" for k in
                    ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "RAYON_NUM_THREADS")},
            }
            for key, value in expected.items():
                require(m.get(key) == value, f"{name}: declared {key} differs")
            status_expected = {
                "name": name, "cohort": c, "round": number,
                "environment_cohort": ENVIRONMENT_COHORT, "session_id": session,
                "recovery_sha256": recovery_sha, "state": "ready_for_remote_checkpoint",
                "passed": True, "exit_code": 0, "pack_exit_code": 0,
                "groups": len(keys) // 2, "measured_operations": len(keys) * SAMPLES,
            }
            for key, value in status_expected.items():
                require(status.get(key) == value, f"{name}: saved {key} differs")
            opts = options(status["command"])
            for key, value in {
                "--purpose": "measurement", "--suites": "smoke,confirm,coupled",
                "--fixtures": ",".join(fixtures), "--engines": ",".join(ENGINES),
                "--modes": ",".join(MODES), "--rounds": "1", "--start-round": str(number - 1),
                "--warmups": "8", "--samples": "21", "--timeout": "30", "--cpu": "0",
            }.items():
                require(opts.get(key) == value, f"{name}: command {key} differs")
            recorded_out = session_path(opts["--out"], session)
            recorded_prepared = session_path(opts["--prepared"], session)
            require(recorded_out.parts[-2:] == ("runs", name), "Recorded block output differs")
            require(recorded_prepared.name == "prepared-" + c, "Recorded preparation path differs")
            session_path(status["command"][1], session)
            status_start, status_end = stamp(status["started_utc"]), stamp(status["packed_utc"])
            start, end = stamp(m["started_utc"]), stamp(m["finished_utc"])
            require(earliest <= status_start <= start < end <= stamp(m["analysis_finished_utc"])
                    <= stamp(status["completed_utc"]) <= status_end, "Block timestamps inconsistent: " + name)
            indexed = {(row["variant"], row["job"]): row for row in m["jobs"]}
            require(len(indexed) == len(m["jobs"]) == len(keys), "Manifest job population differs: " + name)
            seen, sequence = set(), []
            for side in SIDES:
                for path in sorted((directory / side).glob("*/job.json")):
                    job = read(path)
                    key = (job["fixture_id"], job["engine"], job["mode"], side)
                    require(key in keys and key not in seen, "Unexpected or duplicate job: " + str(key))
                    seen.add(key)
                    require(job["round"] == number and job["variant"] == side
                            and job["timeout_seconds"] == TIMEOUT
                            and job["timed_out"] is False and job["returncode"] == 0
                            and job["parse_errors"] == [], "Job execution protocol differs")
                    summary = job["summary"]
                    for field, value in {"complete": True, "expected_samples": SAMPLES,
                            "completed_samples": SAMPLES, "accepted_samples": SAMPLES,
                            "expected_records": SAMPLES + WARMUPS,
                            "completed_records": SAMPLES + WARMUPS}.items():
                        require(summary.get(field) == value, "Job operation counts differ: " + field)
                    for value in job["command"]:
                        session_path(value, session)
                    require(PurePosixPath(job["command"][0]) == recorded_prepared / side / "dart-adapter",
                            "Job uses another prepared executable")
                    raw_path = session_path(job["raw_directory"], session)
                    require(raw_path == recorded_out / side / path.parent.name, "Job output belongs to another block")
                    jstart, jend = stamp(job["started_utc"]), stamp(job["completed_utc"])
                    require(start <= jstart < jend <= end, "Job falls outside its block")
                    row = indexed.pop((side, path.parent.name))
                    require(row["summary"] == summary and stamp(row["started_utc"]) == jstart
                            and stamp(row["completed_utc"]) == jend, "Manifest/job records differ")
                    process_intervals.append((jstart, jend, name + "/" + side + "/" + path.parent.name))
                    sequence.append((jstart, key))
            require(seen == keys and not indexed, "Missing declared jobs: " + name)
            declared_order = []
            for fi, fixture in enumerate(fixtures):
                for mi, mode in enumerate(MODES):
                    for ei, engine in enumerate(ENGINES):
                        sides = SIDES[::-1] if (number - 1 + fi + mi + ei) % 2 else SIDES
                        declared_order.extend((fixture, engine, mode, side) for side in sides)
            require([key for _, key in sorted(sequence)] == declared_order, "Declared process order differs: " + name)
            block_intervals.append((status_start, status_end, name))
            counts = {"blocks": 1, "processes": len(seen),
                      "measured_operations": len(seen) * SAMPLES, "warmup_operations": len(seen) * WARMUPS}
            totals.update(counts)
            blocks.append({"name": name, "counts": counts,
                           "manifest_sha256": digest((directory / "manifest.json").read_bytes()),
                           "status_sha256": digest((saved / (name + "-status.json")).read_bytes())})
    check_nonoverlap(process_intervals, "Global solver")
    ordered_blocks = check_nonoverlap(block_intervals, "Collection/packing block")
    require([name for _, _, name in ordered_blocks] == expected_blocks, "Declared block order differs")
    if full:
        require(dict(totals) == FULL_TOTALS, "Final totals differ from independent declaration")
    return {"schema_version": 1, "passed": True, "full_protocol": full,
            "scope": "complete declared experiment" if full else "explicit partial precheck only",
            "session_id": session, "environment_cohort": ENVIRONMENT_COHORT,
            "recovery_sha256": recovery_sha, "cohorts": list(cohorts),
            "start_round": start_round, "rounds": rounds,
            "expected_full_totals": FULL_TOTALS, "counts": dict(totals), "blocks": blocks,
            "global_process_nonoverlap": True, "collection_and_packing_nonoverlap": True,
            "limits": "Metadata and declared protocol only; run the independent raw geometry/work/timing audit too. "
                      "Session bindings are recorded provenance, not hardware attestation."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--saved", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--cohorts", default=",".join(COHORTS))
    parser.add_argument("--start-round", type=int, default=1,
                        help="First selected round, numbered 1 through 4 (default: 1)")
    parser.add_argument("--rounds", type=int, default=4,
                        help="Number of consecutive rounds to audit (default: 4)")
    args = parser.parse_args()
    try:
        report = audit(args.runs, args.saved, tuple(args.cohorts.split(",")),
                       args.rounds, args.start_round)
    except (ValueError, KeyError, TypeError, OSError) as error:
        report = {"schema_version": 1, "passed": False, "error": f"{type(error).__name__}: {error}"}
    report["script_sha256"] = digest(Path(__file__).read_bytes())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("blocks", "limits")}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())

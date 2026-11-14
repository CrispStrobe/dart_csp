#!/usr/bin/env python3
"""Independently reconcile the preserved complete-process CAD GC cohort.

This auditor uses only the standard library. It deliberately does not import
the collector or its regular-expression parser. Supply both worktrees so the
recorded source, lock and common harness identities can be checked against disk.
The GC columns describe whole processes; they are not timed-operation allocation
counts, allocated bytes, or summed stop-the-world pauses.
"""

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import Decimal
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys
from urllib.parse import unquote, urlparse


class Review:
    def __init__(self):
        self.checks = 0
        self.findings = []

    def check(self, condition, description):
        self.checks += 1
        if not condition:
            self.findings.append(description)

    def equal(self, actual, expected, description):
        self.check(actual == expected, description)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def text_bytes(value):
    return value.encode("utf-8", errors="surrogateescape")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def parse_gc_lines(stderr):
    """Parse comma-separated rows, independently of the collector's regex.

    Every bracketed line must be either a pipe-separated VM column header or a
    complete numeric event row. Check all numeric fields, even though ancillary
    heap columns are deliberately not used to estimate allocated bytes.
    """
    events = []
    unparsed = []
    header_lines = 0
    non_event_lines = 0
    for number, line in enumerate(stderr.splitlines(), start=1):
        stripped = line.strip()
        if not stripped.startswith("["):
            non_event_lines += 1
            continue
        if "|" in stripped and "," not in stripped:
            header_lines += 1
            continue
        try:
            if not stripped.endswith("]"):
                raise ValueError("unterminated row")
            fields = [part.strip() for part in stripped[1:-1].split(",")]
            if len(fields) != 22 or fields[-1] != "":
                raise ValueError("unexpected GC column count")
            isolate = fields[0]
            space, separator, suffix = fields[1].partition("(")
            if not isolate or not separator or not suffix.endswith(")"):
                raise ValueError("invalid isolate or space/reason column")
            reason = suffix[:-1].strip()
            space = space.strip()
            if not space or not reason or not fields[2].isdecimal():
                raise ValueError("invalid event identity")
            numeric = [Decimal(field) for field in fields[3:-1]]
            if not all(value.is_finite() for value in numeric):
                raise ValueError("nonfinite event column")
            if numeric[0] < 0 or numeric[1] < 0:
                raise ValueError("negative start or duration")
            events.append({
                "isolate": isolate,
                "stderr_line": number,
                "space": space,
                "reason": reason,
                "gc_number": int(fields[2]),
                "start_seconds": float(numeric[0]),
                "reported_duration_ms": numeric[1],
                "new_used_before_mb": numeric[2],
                "new_used_after_mb": numeric[3],
                "new_capacity_before_mb": numeric[4],
                "new_capacity_after_mb": numeric[5],
            })
        except (ValueError, ArithmeticError) as error:
            unparsed.append({"stderr_line": number, "reason": str(error)})
    return events, unparsed, header_lines, non_event_lines


def summarize_main(events):
    main = [event for event in events if event["isolate"] == "main"]
    by_group = defaultdict(list)
    for event in main:
        by_group[event["space"], event["reason"]].append(
            event["reported_duration_ms"]
        )
    return {
        "event_count": len(main),
        "counts_by_space": dict(Counter(event["space"] for event in main)),
        "counts_by_reason": dict(Counter(event["reason"] for event in main)),
        "by_space_and_reason": [
            {
                "space": space,
                "reason": reason,
                "event_count": len(durations),
                "sum_reported_event_ms": float(sum(durations, Decimal(0))),
                "max_reported_event_ms": float(max(durations)),
            }
            for (space, reason), durations in sorted(by_group.items())
        ],
        "sum_reported_event_ms": float(sum(
            (event["reported_duration_ms"] for event in main), Decimal(0)
        )),
        "max_reported_event_ms": float(max(
            (event["reported_duration_ms"] for event in main),
            default=Decimal(0),
        )),
        "rows": [
            {key: float(value) if isinstance(value, Decimal) else value
             for key, value in event.items()
             if key in ("stderr_line", "space", "reason", "gc_number",
                        "start_seconds", "reported_duration_ms")}
            for event in main
        ],
    }


def new_generation_diagnostics(events):
    """Describe rounded VM columns without inferring allocations or bytes."""
    scavenges = [event for event in events
                 if event["isolate"] == "main" and event["space"] == "Scavenge"]
    capacities = [event["new_capacity_before_mb"] for event in scavenges]
    histogram = Counter(capacities)
    segments = []
    for number, value in enumerate(capacities, start=1):
        if segments and segments[-1]["capacity_before_mb"] == float(value):
            segments[-1]["last_scavenge_index"] = number
        else:
            segments.append({"first_scavenge_index": number,
                             "last_scavenge_index": number,
                             "capacity_before_mb": float(value)})
    reduction = sum((event["new_used_before_mb"] - event["new_used_after_mb"]
                     for event in scavenges), Decimal(0))
    return {
        "new_capacity_before_median_mb": float(statistics.median(capacities)),
        "sum_rounded_new_occupancy_reduction_mb": float(reduction),
        "capacity_before_histogram": [
            {"capacity_mb": float(value), "event_count": count}
            for value, count in sorted(histogram.items())
        ],
        "capacity_before_sequence": segments,
        "units": "VM-reported MB, rounded to the printed 0.1 MB precision",
        "interpretation": (
            "Sum of each Scavenge's printed new-generation used-before minus used-after. "
            "This occupancy-reduction proxy includes promoted objects and reclaimed space; "
            "it is not measured allocation, live heap size, or bytes allocated. "
            "All events are from the whole process, including unmeasured work."
        ),
    }


def measurements(result, fixture):
    if fixture == "cad_linkage":
        return result["measurements"]
    return {key: value for key, value in result.items()
            if isinstance(value, dict) and "samples_us" in value}


def check_process(review, record, label):
    review.equal(record["exit_code"], 0, f"{label}: exit status")
    review.equal(record["timed_out"], False, f"{label}: timeout")
    for stream in ("stdout", "stderr"):
        review.equal(digest(text_bytes(record[stream])), record[f"{stream}_sha256"],
                     f"{label}: lossless {stream} hash")


def check_sources(review, data, roots):
    identities = {}
    for label, root in roots.items():
        source = data["revisions"][label]
        commit = source["commit"]
        review.equal(root.resolve(), Path(source["root"]).resolve(),
                     f"{label}: recorded worktree")
        tree = git(root, "rev-parse", f"{commit}:lib").decode().strip()
        review.equal(tree, source["committed_library_tree"],
                     f"{label}: committed library tree")
        names = git(root, "ls-tree", "-r", "--name-only", commit, "lib").decode().splitlines()
        expected_files = source["library_files_sha256"]
        review.equal(set(names), set(expected_files), f"{label}: complete library file manifest")
        for name, expected in expected_files.items():
            review.equal(digest((root / name).read_bytes()), expected,
                         f"{label}: live library file {name}")
            review.equal(digest(git(root, "show", f"{commit}:{name}")), expected,
                         f"{label}: committed library file {name}")
        review.equal(git(root, "diff", commit, "--", "lib"), b"",
                     f"{label}: live source equals frozen commit")
        review.equal(source["library_diff_sha256"], None,
                     f"{label}: no recorded uncommitted library patch")
        lock_hash = digest((root / "pubspec.lock").read_bytes())
        review.equal(lock_hash, source["pubspec_lock_sha256"],
                     f"{label}: live dependency lock")
        review.equal(digest(text_bytes(source["pubspec_lock"])), lock_hash,
                     f"{label}: embedded dependency lock")
        for fixture, harnesses in data["harnesses"].items():
            for name, expected in harnesses.items():
                review.equal(digest((root / name).read_bytes()), expected,
                             f"{label}/{fixture}: common harness/dependency {name}")
        config_path = root / ".dart_tool" / "package_config.json"
        config = json.loads(config_path.read_bytes())
        package = next(item for item in config["packages"] if item["name"] == "dart_csp")
        uri = urlparse(package["rootUri"])
        package_root = Path(unquote(uri.path))
        if not package_root.is_absolute():
            package_root = config_path.parent / package_root
        review.equal(package_root.resolve(), root.resolve(),
                     f"{label}: package resolves own source root")
        identities[label] = {
            "commit": commit,
            "library_tree": tree,
            "library_file_count": len(expected_files),
            "pubspec_lock_sha256": lock_hash,
        }
    review.equal(identities["before"]["pubspec_lock_sha256"],
                 identities["after"]["pubspec_lock_sha256"],
                 "dependency lock is identical before and after")
    review.equal(digest((roots["after"] / "tool/profile_cad_gc.py").read_bytes()),
                 data["tool_sha256"], "collector source identity")
    return identities


def audit(data_path, before, after):
    review = Review()
    compressed = data_path.read_bytes()
    raw = gzip.decompress(compressed)
    data = json.loads(raw)
    review.equal(data["schema"], "dart-csp-cad-whole-process-gc-v1", "dataset schema")
    review.equal(data["complete"], True, "dataset marked complete")
    review.equal((data["rounds"], data["samples"], data["warmups"]),
                 (3, 300, 30), "requested three rounds and 300/30 sample/warmup counts")
    roots = {"before": before, "after": after}
    identities = check_sources(review, data, roots)
    check_process(review, data["dart_version"], "SDK version")
    dart = data["dart_version"]["command"][0]
    review.equal(data["dart_version"]["command"], [dart, "--version"], "SDK version command")
    review.equal(len(data["compilations"]), 4, "four AOT compilations")
    snapshots = {}
    for record in data["compilations"]:
        fixture, revision = record["benchmark"], record["revision"]
        label = f"compile/{fixture}/{revision}"
        check_process(review, record, label)
        command = record["command"]
        review.equal(command[:5], [dart, "compile", "aot-snapshot",
                                  f"benchmark/{fixture}.dart", "-o"],
                     f"{label}: compilation command")
        review.equal(len(command), 6, f"{label}: complete compilation arguments")
        review.equal(Path(record["cwd"]).resolve(), roots[revision].resolve(),
                     f"{label}: source cwd")
        snapshots[fixture, revision] = command[-1]
    review.equal(set(snapshots), {(fixture, revision)
                 for fixture in ("cad", "cad_linkage") for revision in roots},
                 "one compilation for every fixture/revision")
    expected_sequence = [
        (mode, round_number, fixture, revision)
        for mode in ("jit", "aot")
        for round_number in (1, 2, 3)
        for fixture in ("cad", "cad_linkage")
        for revision in (("before", "after") if round_number % 2 else ("after", "before"))
    ]
    review.equal([(run["mode"], run["round"], run["benchmark"], run["revision"])
                  for run in data["runs"]], expected_sequence,
                 "complete 24-run order with alternating before/after pairs")
    parsed_runs = {}
    run_summaries = []
    sample_count = work_count = row_count = 0
    all_gc_events = main_gc_events = 0
    bracket_headers = non_event_lines = 0
    for record in data["runs"]:
        key = record["mode"], record["round"], record["benchmark"], record["revision"]
        mode, round_number, fixture, revision = key
        label = "/".join(map(str, key))
        check_process(review, record, label)
        review.equal(Path(record["cwd"]).resolve(), roots[revision].resolve(),
                     f"{label}: source cwd")
        command = ([dart, "--verbose_gc", f"benchmark/{fixture}.dart"] if mode == "jit"
                   else [str(Path(dart).with_name("dartaotruntime")), "--verbose_gc",
                         snapshots[fixture, revision]])
        command += ["--samples=300", "--warmups=30"]
        review.equal(record["command"], command, f"{label}: instrumented run command")
        result = json.loads(record["stdout"])
        review.equal(result, record["result"], f"{label}: parsed stdout preserved")
        review.equal(result["units"], "microseconds", f"{label}: timing units")
        if fixture == "cad":
            review.equal((result["measured_pairs"], result["warmup_pairs"]), (300, 30),
                         f"{label}: harness sample/warmup counts")
            review.equal(result["analytic_volume_and_mesh_checks"], "passed",
                         f"{label}: independent physical checks")
        else:
            review.equal((result["measured_iterations"], result["warmup_iterations"]),
                         (300, 30), f"{label}: harness sample/warmup counts")
            review.equal(result["operations_per_batch"], 1, f"{label}: complete-operation samples")
            review.equal(result["independent_physical_reuse_rollback_checks"], "passed",
                         f"{label}: independent physical/reuse/rollback checks")
        cases = measurements(result, fixture)
        review.equal(len(cases), 3 if fixture == "cad" else 5, f"{label}: operation count")
        for name, distribution in cases.items():
            samples = distribution["samples_us"]
            work = distribution["work_per_sample"]
            review.equal((len(samples), len(work)), (300, 300),
                         f"{label}/{name}: raw timings and aligned work")
            review.check(all(isinstance(value, (int, float)) and math.isfinite(value)
                             and value >= 0 for value in samples),
                         f"{label}/{name}: finite nonnegative timings")
            ordered = sorted(samples)
            review.equal(distribution["p50"], ordered[len(ordered) // 2],
                         f"{label}/{name}: median reconciles")
            for percentile in (95, 99):
                if f"p{percentile}" in distribution:
                    expected = ordered[math.ceil(len(ordered) * percentile / 100) - 1]
                    review.equal(distribution[f"p{percentile}"], expected,
                                 f"{label}/{name}: p{percentile} reconciles")
            sample_count += len(samples)
            work_count += len(work)
            row_count += 1
        events, unparsed, headers, other_lines = parse_gc_lines(record["stderr"])
        review.equal(unparsed, [], f"{label}: every GC row independently parsed")
        review.equal(record["gc"]["unparsed_gc_row_stderr_lines"], [],
                     f"{label}: collector reports no missed rows")
        summary = summarize_main(events)
        review.equal(summary, record["gc"]["main_isolate"],
                     f"{label}: all main GC rows/counts/reasons/durations reconciled")
        other = Counter(event["isolate"] for event in events if event["isolate"] != "main")
        review.equal(dict(other), record["gc"]["other_isolate_event_counts"],
                     f"{label}: all service-isolate row counts reconciled")
        all_gc_events += len(events)
        main_gc_events += summary["event_count"]
        bracket_headers += headers
        non_event_lines += other_lines
        scavenges = [event["reported_duration_ms"] for event in events
                     if event["isolate"] == "main" and event["space"] == "Scavenge"]
        run_summary = {
            "mode": mode, "round": round_number, "fixture": fixture, "revision": revision,
            "main_event_count": summary["event_count"],
            "counts_by_space": summary["counts_by_space"],
            "counts_by_reason": summary["counts_by_reason"],
            "service_event_counts": dict(other),
            "main_sum_reported_event_ms": summary["sum_reported_event_ms"],
            "scavenge_count": len(scavenges),
            "scavenge_sum_reported_event_ms": float(sum(scavenges, Decimal(0))),
            "scavenge_median_reported_event_ms": float(statistics.median(scavenges)),
            **new_generation_diagnostics(events),
        }
        run_summaries.append(run_summary)
        parsed_runs[key] = {"result": result, "summary": run_summary}
    paired_work_records = 0
    paired_summary = []
    for mode in ("jit", "aot"):
        for fixture in ("cad", "cad_linkage"):
            round_rows = []
            for round_number in (1, 2, 3):
                before_run = parsed_runs[mode, round_number, fixture, "before"]
                after_run = parsed_runs[mode, round_number, fixture, "after"]
                a = measurements(before_run["result"], fixture)
                b = measurements(after_run["result"], fixture)
                review.equal(a.keys(), b.keys(), f"{mode}/{round_number}/{fixture}: same operations")
                for name in a:
                    review.equal(a[name]["work_per_sample"], b[name]["work_per_sample"],
                                 f"{mode}/{round_number}/{fixture}/{name}: exact ordered work parity")
                    paired_work_records += len(a[name]["work_per_sample"])
                round_rows.append({
                    "round": round_number,
                    **{metric: {revision: parsed_runs[mode, round_number, fixture, revision]["summary"][metric]
                                for revision in roots}
                       for metric in ("scavenge_count", "scavenge_sum_reported_event_ms",
                                      "scavenge_median_reported_event_ms", "main_sum_reported_event_ms",
                                      "new_capacity_before_median_mb",
                                      "sum_rounded_new_occupancy_reduction_mb")},
                })
            medians = {}
            for metric in ("scavenge_count", "scavenge_sum_reported_event_ms",
                           "scavenge_median_reported_event_ms", "main_sum_reported_event_ms",
                           "new_capacity_before_median_mb", "sum_rounded_new_occupancy_reduction_mb"):
                values = {revision: statistics.median(row[metric][revision] for row in round_rows)
                          for revision in roots}
                values["change_percent"] = ((values["after"] / values["before"] - 1) * 100
                                            if values["before"] else None)
                medians[metric] = values
            paired_summary.append({"mode": mode, "fixture": fixture,
                                   "rounds": round_rows, "process_medians": medians})
    return {
        "schema": "dart-csp-independent-gc-review-v1",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": "passed" if not review.findings else "failed",
        "findings": review.findings,
        "checks": review.checks,
        "dataset": str(data_path.resolve()),
        "dataset_gzip_sha256": digest(compressed),
        "dataset_json_sha256": digest(raw),
        "independent_auditor_sha256": digest(Path(__file__).read_bytes()),
        "source_identities": identities,
        "harnesses": data["harnesses"],
        "scope": [
            "Independent parser uses comma-separated columns; collector parser was not imported.",
            "24 fresh runs: two runtimes, three rounds, two fixtures, two revisions; revision order alternates by round.",
            "Every raw stdout/stderr is losslessly hash-reconciled, including SDK and four compilation records.",
            "Common harness and example files match before/after; baseline contains the common benchmark overlay.",
            "GC events cover complete processes, including setup, warmups, measured operations, checks and serialization.",
            "GC reported event durations are rounded VM diagnostics; their sums are not summed stop-the-world pauses.",
            "Process duration medians below are medians of each process's sum of reported event durations.",
            "Per-event duration medians are separately named and do not identify individual operation latency.",
            "This cohort does not measure allocated bytes or establish operation-level GC causality.",
            "New-generation capacities and used-space reductions describe rounded whole-process VM columns only.",
            "Instrumented timings are reconciled for integrity only; normal timing cohort supports performance claims.",
        ],
        "counts": {
            "process_records": 1 + len(data["compilations"]) + len(data["runs"]),
            "runs": len(data["runs"]), "paired_runs": len(data["runs"]) // 2,
            "distributions": row_count,
            "raw_timing_samples": sample_count,
            "aligned_work_records": work_count,
            "exactly_equal_paired_work_records": paired_work_records,
            "all_isolate_gc_rows": all_gc_events,
            "main_isolate_gc_rows": main_gc_events,
            "service_isolate_gc_rows": all_gc_events - main_gc_events,
            "gc_header_lines": bracket_headers,
            "non_event_stderr_lines": non_event_lines,
            "unparsed_gc_rows": 0 if not any("GC row independently" in item for item in review.findings) else None,
        },
        "paired_scavenge_summaries": paired_summary,
        "runs": run_summaries,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.dataset, args.before, args.after)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ("status", "checks", "findings", "counts")}))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())

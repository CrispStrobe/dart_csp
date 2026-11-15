"""Mutation checks for the declared protocol, independent of generated manifests."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import audit_optimization_protocol as protocol


class ProtocolAuditTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.runs, self.saved = self.root / "runs", self.root / "saved"
        self.runs.mkdir()
        self.saved.mkdir()
        self.session = "synthetic-session"
        self.original = "/workspace/scratch/" + self.session + "/comparison"
        self.base = datetime(2026, 11, 14, 20, 0, tzinfo=timezone.utc)
        self.preparations = {}
        hashes = {}
        for c in protocol.COHORTS:
            prepared = {"status": "complete", "harness_sha256": {"fixture.py": "fixed"},
                        "variants": {side: {"source": {"source_commit": protocol.ENDPOINTS[label][0]},
                                             "executable_sha256": protocol.ENDPOINTS[label][1]}
                                     for side, label in zip(protocol.SIDES, protocol.PAIRS[c])}}
            path = self.root / ("prepared-" + c) / "prepared.json"
            self.write(path, prepared)
            hashes[c] = protocol.digest(path.read_bytes())
            self.preparations[c] = prepared
        patch = mock.patch.dict(protocol.PREPARED_SHA256, hashes)
        patch.start()
        self.addCleanup(patch.stop)
        recovery = {"session_id": self.session, "timing_cohort": protocol.ENVIRONMENT_COHORT,
                    "historical_timings_separate": True, "observed_utc": self.time(0),
                    "platform": "synthetic-platform", "cpu_model": "synthetic-cpu", "affinity": [0, 1],
                    "restored_executables": [
                        {"cohort": "prepared-" + c, "variant": side,
                         "source": protocol.ENDPOINTS[label][0], "sha256": protocol.ENDPOINTS[label][1]}
                        for c in protocol.COHORTS for side, label in zip(protocol.SIDES, protocol.PAIRS[c])]}
        self.write(self.saved / "recovery.json", recovery)
        self.recovery = recovery
        self.recovery_hash = protocol.digest((self.saved / "recovery.json").read_bytes())

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n")

    def time(self, seconds):
        return (self.base + timedelta(seconds=seconds)).isoformat()

    def block(self, c="cg", number=1, offset=10):
        name = f"{c}-round{number}"
        directory = self.runs / name
        fixtures = protocol.FIXTURES[:-1] if c == "aa" else protocol.FIXTURES
        out, prep = self.original + "/runs/" + name, self.original + "/prepared-" + c
        jobs, index = [], 0
        for fi, fixture in enumerate(fixtures):
            for mi, mode in enumerate(protocol.MODES):
                for ei, engine in enumerate(protocol.ENGINES):
                    sides = ("after", "before") if (number - 1 + fi + mi + ei) % 2 else ("before", "after")
                    for side in sides:
                        job_name = f"job{index:04d}"
                        summary = {"complete": True, "expected_samples": 21, "completed_samples": 21,
                                   "accepted_samples": 21, "expected_records": 29, "completed_records": 29}
                        started, finished = self.time(offset + 5 + index * 2), self.time(offset + 6 + index * 2)
                        raw = out + "/" + side + "/" + job_name
                        job = {"fixture_id": fixture, "engine": engine, "mode": mode, "round": number,
                               "variant": side, "timeout_seconds": 30, "timed_out": False, "returncode": 0,
                               "parse_errors": [], "summary": summary, "started_utc": started,
                               "completed_utc": finished, "command": [prep + "/" + side + "/dart-adapter",
                                                                         raw + "/request.json"],
                               "raw_directory": raw}
                        self.write(directory / side / job_name / "job.json", job)
                        jobs.append({"variant": side, "job": job_name, "summary": summary,
                                     "started_utc": started, "completed_utc": finished})
                        index += 1
        end = offset + 6 + index * 2
        manifest = {"status": "complete", "purpose": "measurement", "rounds": 1,
                    "start_round": number - 1, "samples": 21, "warmups": 8, "timeout_seconds": 30,
                    "pinned_cpu": 0, "fixture_ids": list(fixtures), "engines": list(protocol.ENGINES),
                    "modes": ["cold", "warm"], "variants": ["before", "after"],
                    "suites": "smoke,confirm,coupled", "protocol_ok": True, "qualification_passed": True,
                    "prepared_manifest_sha256": protocol.PREPARED_SHA256[c], "preparation": self.preparations[c],
                    "harness_sha256": self.preparations[c]["harness_sha256"],
                    "platform": self.recovery["platform"], "cpu_model": self.recovery["cpu_model"],
                    "allowed_cpus": [0, 1], "thread_environment": {k: "1" for k in
                        ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "RAYON_NUM_THREADS")},
                    "started_utc": self.time(offset + 2), "finished_utc": self.time(end),
                    "analysis_finished_utc": self.time(end + 1), "jobs": jobs}
        self.write(directory / "manifest.json", manifest)
        command = ["python", "/workspace/scratch/" + self.session + "/repo/paired_dart_backends.py", "run",
                   "--prepared", prep, "--out", out, "--purpose", "measurement", "--suites", "smoke,confirm,coupled",
                   "--fixtures", ",".join(fixtures), "--engines", ",".join(protocol.ENGINES), "--modes", "cold,warm",
                   "--rounds", "1", "--start-round", str(number - 1), "--warmups", "8", "--samples", "21",
                   "--timeout", "30", "--cpu", "0"]
        status = {"name": name, "cohort": c, "round": number, "environment_cohort": protocol.ENVIRONMENT_COHORT,
                  "session_id": self.session, "recovery_sha256": self.recovery_hash, "state": "ready_for_remote_checkpoint",
                  "passed": True, "exit_code": 0, "pack_exit_code": 0, "groups": index // 2,
                  "measured_operations": index * 21, "command": command, "started_utc": self.time(offset),
                  "completed_utc": self.time(end + 2), "packed_utc": self.time(end + 3)}
        self.write(self.saved / (name + "-status.json"), status)

    def mutate(self, path, edit):
        data = protocol.read(path)
        edit(data)
        self.write(path, data)

    def partial(self, cohorts=("cg",), rounds=1, start_round=1):
        return protocol.audit(self.runs, self.saved, cohorts, rounds, start_round)

    def test_full_declared_population_and_partial_label(self):
        for n in range(1, 5):
            for i, c in enumerate(protocol.COHORTS):
                self.block(c, n, 10 + ((n - 1) * 4 + i) * 1000)
        report = protocol.audit(self.runs, self.saved)
        self.assertTrue(report["full_protocol"])
        self.assertEqual({"blocks": 16, "processes": 736, "measured_operations": 15456,
                          "warmup_operations": 5888}, report["counts"])
        partial = self.partial()
        self.assertFalse(partial["full_protocol"])
        self.assertEqual(1008, partial["counts"]["measured_operations"])

    def test_resumed_round_four_is_a_separate_partial_selection(self):
        self.recovery["continuation"] = {"original_session_id": "previous-session",
                                         "reason": "Restore saved executables after interruption"}
        recovery_path = self.saved / "recovery.json"
        self.write(recovery_path, self.recovery)
        original_recovery = recovery_path.read_bytes()
        self.recovery_hash = protocol.digest(original_recovery)
        cohorts = ("identity", "combined", "aa")
        for i, c in enumerate(cohorts):
            self.block(c, 4, 10 + i * 1000)
        report = self.partial(cohorts, rounds=1, start_round=4)
        self.assertFalse(report["full_protocol"])
        self.assertEqual("explicit partial precheck only", report["scope"])
        self.assertEqual((4, 1), (report["start_round"], report["rounds"]))
        self.assertEqual(self.session, report["session_id"])
        self.assertEqual([c + "-round4" for c in cohorts],
                         [block["name"] for block in report["blocks"]])
        self.assertEqual({"blocks": 3, "processes": 136, "measured_operations": 2856,
                          "warmup_operations": 1088}, report["counts"])
        output = self.root / "audit.json"
        with mock.patch.object(protocol.sys, "argv", [
                "audit_optimization_protocol.py", "--runs", str(self.runs),
                "--saved", str(self.saved), "--out", str(output),
                "--cohorts", ",".join(cohorts), "--start-round", "4", "--rounds", "1"]), \
                mock.patch("builtins.print"):
            self.assertEqual(0, protocol.main())
        cli_report = protocol.read(output)
        self.assertEqual(report, {k: v for k, v in cli_report.items() if k != "script_sha256"})
        self.assertEqual(original_recovery, recovery_path.read_bytes())

    def test_invalid_round_range_is_rejected(self):
        for start, count in ((0, 1), (5, 1), (-1, 1), (True, 1), (1.5, 1),
                             (1, 0), (1, 5), (1, True), (1, 1.5),
                             (2, 4), (3, 3), (4, 2)):
            with self.subTest(start=start, count=count):
                with self.assertRaisesRegex(ValueError, "round|Rounds"):
                    self.partial(rounds=count, start_round=start)

    def test_round_four_selection_keeps_session_and_path_guards(self):
        self.block("identity", 4)
        status_path = self.saved / "identity-round4-status.json"
        original = protocol.read(status_path)
        self.write(status_path, dict(original, session_id="previous-session"))
        with self.assertRaisesRegex(ValueError, "saved session_id differs"):
            self.partial(("identity",), start_round=4)
        self.write(status_path, original)
        path = next((self.runs / "identity-round4/before").glob("*/job.json"))
        self.mutate(path, lambda j: j["command"].__setitem__(
            0, j["command"][0].replace(self.session, "previous-session")))
        with self.assertRaisesRegex(ValueError, "another session"):
            self.partial(("identity",), start_round=4)

    def test_omitted_fixture_rejected_even_if_manifest_claims_complete(self):
        self.block()
        self.mutate(self.runs / "cg-round1/manifest.json", lambda m: m["fixture_ids"].pop())
        with self.assertRaisesRegex(ValueError, "fixture_ids"):
            self.partial()

    def test_sample_drift_rejected(self):
        self.block()
        self.mutate(self.runs / "cg-round1/manifest.json", lambda m: m.update(samples=20))
        with self.assertRaisesRegex(ValueError, "samples"):
            self.partial()

    def test_cohort_and_session_mismatch_rejected(self):
        self.block()
        path = self.saved / "cg-round1-status.json"
        original = protocol.read(path)
        for field, value in (("environment_cohort", "2026-11-14-optimization-recovery"),
                             ("session_id", "old-session"), ("recovery_sha256", "0" * 64)):
            with self.subTest(field=field):
                self.write(path, dict(original, **{field: value}))
                with self.assertRaisesRegex(ValueError, field):
                    self.partial()

    def test_relabelled_old_session_job_is_rejected(self):
        self.block()
        path = next((self.runs / "cg-round1/before").glob("*/job.json"))
        self.mutate(path, lambda j: j["command"].__setitem__(0, j["command"][0].replace(self.session, "old-session")))
        with self.assertRaisesRegex(ValueError, "another session"):
            self.partial()

    def test_cross_block_overlap_is_rejected(self):
        self.block("cg", 1, 10)
        self.block("identity", 1, 40)
        with self.assertRaisesRegex(ValueError, "Global solver intervals overlap"):
            self.partial(("cg", "identity"))

    def test_preparation_and_recovered_source_drift_are_rejected(self):
        self.block()
        preparation = self.root / "prepared-cg/prepared.json"
        original = preparation.read_bytes()
        preparation.write_bytes(original + b" ")
        with self.assertRaisesRegex(ValueError, "preparation hash"):
            self.partial()
        preparation.write_bytes(original)
        self.mutate(self.saved / "recovery.json", lambda r: r["restored_executables"][0].update(source="other-source"))
        with self.assertRaisesRegex(ValueError, "source/executable identities"):
            self.partial()

    def test_default_rejects_incomplete_population(self):
        self.block()
        with self.assertRaisesRegex(ValueError, "Full block population"):
            protocol.audit(self.runs, self.saved)


if __name__ == "__main__":
    unittest.main()

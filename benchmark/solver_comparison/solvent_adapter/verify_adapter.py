#!/usr/bin/env python3
"""Correctness-only smoke: native acceptance must agree with the external oracle.

Known-feasible rejections remain reported benchmark outcomes. They are not
hidden by treating numerical termination as physical success.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from fixtures import corpus, request
from oracle import check


def main():
    errors = []
    rejected = []
    requests = records = 0
    with tempfile.TemporaryDirectory(prefix="verify-", dir=HERE / "target") as folder:
        for engine in ["solvent", "solvent_replay"]:
            for mode in ["cold", "warm"]:
                for case in corpus("smoke"):
                    req = request(case, engine, mode, 1, 2)
                    name = case["fixture"]["id"]
                    path = Path(folder) / f"{engine}_{mode}_{name}.json"
                    path.write_text(json.dumps(req))
                    proc = subprocess.run([str(HERE / "target/release/solvent-adapter"), str(path)],
                                          capture_output=True, text=True, timeout=30)
                    requests += 1
                    rows = [json.loads(line) for line in proc.stdout.splitlines()]
                    records += len(rows)
                    if proc.returncode != 0 or len(rows) != 3:
                        errors.append(dict(engine=engine, mode=mode, fixture=name,
                                           returncode=proc.returncode, records=len(rows), stderr=proc.stderr))
                    for row in rows:
                        verdict = check(req, row)
                        if verdict["accepted"] != row["accepted"]:
                            errors.append(dict(engine=engine, mode=mode, fixture=name,
                                               index=row["index"], error="oracle disagreement"))
                        if not case["fixture"]["expected_feasible"] and verdict["accepted"]:
                            errors.append(dict(engine=engine, mode=mode, fixture=name,
                                               index=row["index"], error="contradiction accepted"))
                        if case["fixture"]["expected_feasible"] and not verdict["accepted"]:
                            rejected.append(dict(engine=engine, mode=mode, fixture=name,
                                                 index=row["index"], physical_max_error=verdict["max_error"],
                                                 reported_success=row["reported_success"]))
    print(json.dumps(dict(correctness_only=True, requests=requests, records=records,
                          adapter_consistent=not errors, adapter_errors=errors,
                          known_feasible_rejections=rejected), indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

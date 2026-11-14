#!/usr/bin/env python3
"""Correctness qualification only; intentionally do not publish smoke timings."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
from fixtures import corpus, ladder, laman, request
from oracle import check
from run import validate_record


def verify_operation(req, row, previous):
    """Require the constructed fixture's outcome, not just adapter agreement."""
    validate_record(row, req, previous)
    verdict = check(req, row)
    if row.get('adapter_error'):
        raise RuntimeError('adapter exception is not a qualified physical outcome')
    if verdict['accepted'] != row['accepted']:
        raise RuntimeError('adapter acceptance disagrees with independent oracle')
    if verdict['accepted'] != req['fixture']['expected_feasible']:
        raise RuntimeError('physical result does not match constructed feasibility')
    return verdict


def main():
    direct = "dart_2d_analytic_sparse_direct"
    commands = {
        direct: HERE / "build/dart-sparse-adapter",
        "dart_2d_analytic": ROOT / "build/solver_comparison/dart-adapter-control",
    }
    jobs = [(engine, case) for engine in commands for case in corpus("smoke")]
    jobs += [(direct, case) for case in [ladder(125), ladder(500), laman(500), laman(2000)]]
    errors, outcomes = [], []
    record_count = 0
    with tempfile.TemporaryDirectory(prefix="physical-", dir=HERE / "build") as folder:
        for engine, case in jobs:
            for mode in ["cold", "warm"]:
                req = request(case, engine, mode, 1, 2)
                path = Path(folder) / "request.json"
                path.write_text(json.dumps(req))
                try:
                    proc = subprocess.run([str(commands[engine]), str(path)],
                                          capture_output=True, text=True, timeout=120)
                    rows = [json.loads(line) for line in proc.stdout.splitlines()]
                    metadata = [row for row in rows if row.get("record") == "metadata"]
                    records = [row for row in rows if row.get("record") != "metadata"]
                    if proc.returncode or len(metadata) != 1 or len(records) != 3:
                        raise RuntimeError(f"exit={proc.returncode}; rows={len(records)}; {proc.stderr}")
                    per_operation = []
                    for previous, row in enumerate(records):
                        verdict = verify_operation(req, row, previous)
                        if engine == direct:
                            if row["max_converged_linear_relative_residual"] > 1e-8:
                                raise RuntimeError("native step falsely reported convergence")
                            if mode == "cold" and row["native_linear_calls"] and not row["native_symbolic_analyses"]:
                                raise RuntimeError("cold operation reused a prior native pattern")
                            if mode == "warm" and previous and row["native_symbolic_analyses"]:
                                raise RuntimeError("warm operation unexpectedly rebuilt its native pattern")
                        per_operation.append({key: row.get(key) for key in [
                            "index", "accepted", "reported_success", "status", "iterations",
                            "linear_solves", "linear_iterations", "native_linear_calls",
                            "native_symbolic_analyses", "native_factorizations", "native_refinements",
                            "failed_native_linear_steps", "max_converged_linear_relative_residual",
                            "ffi_copy_bytes", "orientation_mismatches"]} | {
                            "oracle_max_error": verdict["max_error"],
                            "oracle_violation_count": len(verdict["violations"]),
                        })
                    record_count += len(records)
                    outcomes.append(dict(engine=engine, fixture=case["fixture"]["id"], mode=mode,
                                         expected_feasible=case["fixture"]["expected_feasible"],
                                         operations=per_operation))
                except Exception as error:
                    errors.append(dict(engine=engine, fixture=case["fixture"]["id"], mode=mode,
                                       error=str(error)))
    result = dict(correctness_only=True, timings_omitted=True,
                  requests=len(jobs) * 2, records=record_count,
                  adapter_consistent=not errors, errors=errors, outcomes=outcomes)
    print(json.dumps(result, indent=2))
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())


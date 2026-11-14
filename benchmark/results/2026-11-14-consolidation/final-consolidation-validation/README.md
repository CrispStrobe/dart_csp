# Consolidated source validation — 2026-11-14

All requested local consolidation gates passed against commit `ff3b31e0702b6cddcc64b8ad8dfa9c1d7eabcdea`.
The worktree was clean before and after execution, and source trees did not change.
The evidence in this directory was copied into the repository only after the gates
finished. These are correctness checks, not performance measurements.

| Gate | Result |
|---|---|
| Formatting | 224 Dart files; zero changes |
| Static analysis | No issues with `--fatal-infos` |
| Comparison-harness Python tests | 41 passed |
| Tool Python tests | 8 passed |
| Full native Dart suite | 1,809 passed |
| Node / dart2js | 488 passed across 48 selected files |
| Node / dart2wasm | 488 passed across the same 48 selected files |

The portable corpus includes `test/solver_comparison_adapter_test.dart` and
`test/cad_reuse_test.dart`, together with the existing numerical, CAD, snapshot,
interval, propagation and domain regressions. The exact list and each file's hash
are in `validation.json`.

## Frozen source and runtime identity

| Item | Identity |
|---|---|
| Full source tree | `e2d33e6c408dc222c5f9a5713696b0aace3c9388` |
| Library tree | `a9fc347644d9d0cfdc52c460bdc222ae2678958e` |
| Test tree | `3bc9d3b881ab7c6cdfebf995fc15db64484b7b1a` |
| Tool tree | `c339d93ef7e5dcc8ad0300317a70abe4a1640056` |
| Solver-comparison tree | `cf71b2fde510585f1364dd141759dd7932b84afa` |
| Workflow tree | `998f0fbdf2d77ff2bae7acdac93b0bd966eb11e4` |
| Dart | Dart SDK version: 3.14.0 (stable) (Wed Nov 4 16:28:39 2026 -0800) on "linux_x64" |
| Node | v24.22.1 |
| Python | 3.12.14 |

`validation.json` retains exact argument arrays, command SHA-256 values, start/end
times, exit codes, timeout status, runtime binary hashes and stdout/stderr hashes.
Every complete output is retained in its named `.log` file. `run_validation.py`
preserves the exact orchestration used; its paths describe this execution workspace.
`checksums.json` hashes the packaged evidence files.

Python test imports created three untracked `.pyc` files under `tool/__pycache__`.
Only that generated cache was removed before the final clean-worktree check;
`generated-cache-cleanup.json` records those file hashes. No tracked source was
changed by validation.

Chromium was not retried. The earlier consolidation attempt was blocked before
browser assertions by the environment's socket restriction, as recorded in the
[baseline validation](../baseline-validation/validation.json). Node portability
passes do not establish a real-browser test pass or browser performance.

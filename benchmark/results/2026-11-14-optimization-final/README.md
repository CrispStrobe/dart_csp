# Final bounded optimization comparison

This continuation recovered `93994afbc985704cabb0f71b59e5199b8c2fbad9`.
All 42 remote branch heads and all ten merged pull-request heads are already
ancestors of that commit. `recovery.json` records each observed ref and verifies
the exact restored executable digests. No further source merge was needed.

The current library and test trees match the saved passing validation at
`545a1ab`: 1,891 native tests, 570 Node JavaScript tests, 570 Node WebAssembly
tests, clean static analysis, and both Python harness suites. The actual saved
AOT executables are restored from the earlier prepared-evidence archive;
there is no recompilation and no pooling with earlier timing sessions.

## Declared measurement and decision boundary

The session identifier is `d1244c09828b`. This is the final bounded cohort;
noise or adverse observations will not trigger another restart or favorable
sample selection. Collect four rounds for each of the four existing comparisons:

| Label | Before | After |
| --- | --- | --- |
| `cg` | Packed baseline | Fused CG |
| `identity` | Fused CG | Fused CG plus default-manifold contraction |
| `combined` | Packed baseline | Both optimizations |
| `aa` | Packed baseline | The identical baseline executable |

Use the unchanged six fixtures (`axis_rectangle`, `ladder_3_components_1`,
`ladder_25_components_1`, `ladder_500_components_1`, `laman_free_100`,
`laman_free_500`), both engines, cold and warm modes, eight warmups and 21 measured
operations per process. A/A uses the first five fixtures, as already declared.
Processes run sequentially on CPU 0 with 30-second deadlines and alternate
before/after order across rounds. Planned totals are 736 processes, 15,456
measured operations and 5,888 warmup operations. These remain planned until
the final audit verifies them against the declaration, not only run manifests.
The fixed block order is `cg`, `identity`, `combined`, `aa` for round 1,
then the same sequence for rounds 2, 3 and 4.

Each completed block is packed and remotely checkpointed before the next.
Incomplete blocks are preserved and identified rather than overwritten.
Source compilation, tests, archive packing and audits stay outside timed
collection. The previous saved round remains historical corroboration.

Decide independently for CG fusion and default-manifold contraction using
physical correctness, unchanged work and coordinates, intended-path benefit,
adverse workload rows and process order. Four rounds provide descriptive
evidence, not a universal performance guarantee. A/A describes observed
variation and cannot erase a candidate regression; it does not cover
`laman_free_500`. If benefit remains unsubstantiated, explicitly reject the
candidate instead of expanding the search indefinitely. Keep the meaningful
behavioral regression tests and all favorable and adverse evidence.

The final retained source must have matching correctness evidence. Any new
combination needs its own bounded qualification before performance claims.
No package release or main-branch merge is part of this continuation.

## Evidence recovery

Frozen preparations are the exact earlier bytes, restored with:

```bash
python tool/unpack_benchmark_evidence.py \
  benchmark/results/2026-11-14-optimization-recovery/prepared-evidence.json \
  ../replayed-final
```

Each new block uses the compact payload archive. Restore it before replaying
the unchanged independent analyzer:

```bash
python tool/pack_optimization_evidence.py restore \
  benchmark/results/2026-11-14-optimization-final/cg-round1-evidence.json \
  ../replayed-final/runs/cg-round1
```

Repeat for the other block names. The transport was verified against all 250
files in an immutable historical round: every original byte count and SHA-256
matched after restoration, and archive size fell by 84.1%. Eight regression
tests cover exact recovery and rejection of corrupt or unsafe input. See
`transport-validation.json`. The new packer does not change source evidence,
the frozen timing harness, or the old archive format.

Exact gzip container reconstruction records zlib 1.3.2 and fails safely if a
future codec produces a different compressed stream. `restore --payloads-only`
recovers every verified uncompressed payload and the complete original-path
mapping without recompression, so the underlying evidence remains recoverable.

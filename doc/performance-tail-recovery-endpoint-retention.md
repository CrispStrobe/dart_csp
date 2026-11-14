# Independent endpoint-only retention review

## Decision

Reject the endpoint-only production change from the retained candidate. Its
source and extreme-scale regression remain valid, but the fresh paired cohort
does not support keeping it for the target latency workloads. Preserve the
experiment and all its evidence. This is a performance retention decision,
not a correctness rejection or a claim that coordinate equality is generally
slower than a norm calculation.

The comparison is recovered placement `e48430a153bba4b9790314e7a0a61129941029ac`
against endpoint-only `6165e35e8ad246ff140f4c4f4f432f03ed324a1b`. It does not
measure either candidate directly against main. The split-validation experiment
is absent from the endpoint-only source.

## Evidence and subprocess provenance

All 36 reports, 20 rows, 36,000 samples, 36,000 aligned work records and 18,000
exact paired work comparisons reconcile. The existing project audit passed
228,840 assertions; source-free reconstruction passed 19,003 checks with zero
findings. All 300 reported percentile values and every summary aggregate were
reconstructed without dropping samples or processes.

An additional independent subprocess audit passed 896 checks with zero
findings. It verified all 101 subprocess records, all 202 original stdout/
stderr byte hashes, six compile records and all 36 referenced benchmark
processes. Every subprocess exited successfully without timeout; timestamps
were sequential. Each retained result exactly equals parsed original stdout,
and each command/context/sampling identity matches. JIT and compilation pass
the corresponding explicit package config; AOT invocations use the distinct
recorded before/after compile outputs. Output is marked completed with both
JIT and AOT modes.

Subprocess review: `endpoint_process_audit.json`; independent checker:
`audit_process_provenance.py` in the scratch workspace. Canonical raw gzip
SHA-256: `3c08933395b6c33eaa015cb20b1a31668af772612312c7ed2ac742648051c3f4`.

The command chain and project/configuration hashes do not establish SDK/AOT
binary or installed dependency source byte identities, which were not hashed.
The recorded environment is Dart 3.14.0 on shared Linux x64, inherited affinity
on nine logical CPUs. Three process pairs do not establish significance or
deterministic latency. No timing workload was rerun by this reviewer.

## Why the candidate is not retained

All five JIT linkage aggregate medians worsen, by 5.7–12.0%. Cold, retained
angle and rejected-angle medians worsen in every pair. Rejected-angle p95 also
worsens in every pair (+20.9% aggregate), and its p99 is +59.7% with all three
pairs worse. Coupler p99 worsens in every pair (+35.2%). These are concrete
costs in the intended target workload.

AOT linkage is better on typical latency: all five median aggregates improve
1.1–5.4%, with every cold and coupler pair faster. Angle, coupler and rejected
edit p95 improve in every pair. These benefits remain part of the evidence;
they do not remove JIT costs or the AOT assembly cold median/p95 increases
(+10.1%/+17.4%, each slower in two pairs). AOT placement-only p95 also rises
11.1%, slower in two pairs.

JIT assembly medians improve, but pose-edit p99 rises 30.8% in every pair.
Plate-only controls show large movements despite never executing instance
placement. Their AOT median increases and JIT decreases cannot be attributed
to the endpoint predicate; they demonstrate environmental/context sensitivity.
The cohort does not explain these movements through allocation or GC data.

## Complete row assessment

Each entry shows aggregate percentage change followed by faster/slower/equal
pair counts. Positive means slower. Aggregates are medians of process
percentiles, not pooled percentiles; all pairs are preserved. Derived p99 has
only three observations above its cutoff in each 300-sample process and should
be treated as limited tail evidence.

| Runtime / operation | p50 Δ; pairs | p95 Δ; pairs | p99 Δ; pairs |
|---|---:|---:|---:|
| JIT assembly cold | −5.3%; 2/1/0 | −8.4%; 3/0/0 | −26.9%; 2/1/0 |
| JIT assembly pose | −9.9%; 2/1/0 | −2.2%; 2/1/0 | +30.8%; 0/3/0 |
| JIT linkage cold | +5.7%; 0/3/0 | +5.1%; 1/2/0 | +1.8%; 1/2/0 |
| JIT angle edit | +12.0%; 0/3/0 | +11.8%; 1/2/0 | +3.3%; 2/1/0 |
| JIT coupler edit | +6.5%; 1/2/0 | +23.7%; 1/2/0 | +35.2%; 0/3/0 |
| JIT placement edit | +7.8%; 1/2/0 | −2.7%; 1/2/0 | +6.1%; 1/2/0 |
| JIT rejected edit | +9.5%; 0/3/0 | +20.9%; 0/3/0 | +59.7%; 0/3/0 |
| JIT plate cold | −13.5%; 2/1/0 | −14.8%; 2/1/0 | −25.2%; 2/1/0 |
| JIT plate profile | −4.1%; 1/2/0 | −15.7%; 2/1/0 | −32.3%; 2/1/0 |
| JIT plate thickness | +0.0%; 1/2/0 | −1.9%; 2/1/0 | −25.7%; 1/2/0 |
| AOT assembly cold | +10.1%; 1/2/0 | +17.4%; 1/2/0 | +11.5%; 2/1/0 |
| AOT assembly pose | +2.2%; 1/1/1 | +17.1%; 1/2/0 | +20.2%; 2/1/0 |
| AOT linkage cold | −1.1%; 3/0/0 | +2.7%; 2/1/0 | +8.2%; 1/2/0 |
| AOT angle edit | −3.7%; 2/1/0 | −1.9%; 3/0/0 | +20.5%; 1/2/0 |
| AOT coupler edit | −3.1%; 3/0/0 | −5.1%; 3/0/0 | +18.1%; 1/2/0 |
| AOT placement edit | −5.4%; 2/0/1 | +11.1%; 1/2/0 | −34.8%; 3/0/0 |
| AOT rejected edit | −4.6%; 2/1/0 | −8.8%; 3/0/0 | −17.3%; 3/0/0 |
| AOT plate cold | +6.9%; 1/2/0 | +16.7%; 2/1/0 | +63.1%; 1/2/0 |
| AOT plate profile | +4.2%; 1/2/0 | +8.0%; 2/1/0 | +22.4%; 2/1/0 |
| AOT plate thickness | +4.8%; 1/2/0 | +4.4%; 2/1/0 | +4.5%; 2/1/0 |

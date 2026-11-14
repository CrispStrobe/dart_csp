# Independent split-validation measurement review

## Recommendation

Do not retain split validation as a standalone replacement for the recovered
placement implementation. The source review found no correctness blocker, but
the normal paired measurements do not establish an overall improvement for the
target workloads. Preserve this experiment, its source, its successful checks
and all measurements. This recommendation does not prove the split is always
slower, or that its combination with another optimization would be slower.

Comparison is recovered `e48430a153bba4b9790314e7a0a61129941029ac` versus split
candidate `4522355c01f36b122726473c0934d7678f2af937`. It is not a comparison to
main and must not be multiplied by a prior cohort's percentage changes to
estimate a main-relative result.

## Verified evidence

The project auditor `tool/audit_cad_measurements.py` passed 228,840 assertions,
including 88 committed-library byte comparisons, common harness/dependency
hashes, all sample/percentile rows and aligned work. Its output is
`split_measurement_audit.json` in the scratch workspace.

A second reconstruction (`independent_normal_audit.py`) imported no project
collector, summarizer or auditor and inspected only the raw/summary JSON.
It passed 19,003 checks with zero findings, covering:

- Complete alternating revision order and sequential nonoverlapping timestamps.
- 36 process reports, 20 summary rows and all 120 distributions.
- 36,000 raw timing samples and 36,000 aligned work records.
- All 300 reported percentile values, plus derived p99 for every distribution.
- 18,000 exact before/after per-sample physical/work-record comparisons.
- Every process p50/p95 entry, aggregate median, p50 percentage and ratio.

The independent output is `split_independent_audit.json`. These are read-only
audits; no timing workload was run by the reviewer.

## Assessment

The four JIT retained-linkage operations improve every individual p50 pair:
12/12 pairs are faster, with aggregate medians 2.4–5.0% lower. Their p95
aggregates improve 4.5–7.9%, although angle and placement have one adverse p95
pair each. This is the strongest positive evidence for the split.

All four AOT retained-linkage p50 aggregates regress 2.0–5.9%, with two of three
pairs slower in each row. The apparent AOT p95 aggregate improvements in
coupler and placement edits conceal adverse paired medians: coupler p95 is
1.0% lower between aggregate medians, but its median paired change is +13.9%;
placement p95 is 5.6% lower between aggregate medians, but its median paired
change is +1.3%. Two pairs are slower in both rows.

AOT assembly cold p50/p95 increase 8.2%/10.7%; pose-edit p50/p95 increase
2.1%/42.5%. Each has two slower pairs and one faster pair. None of the 20 p50
or p95 rows has all three pairs slower, so the evidence supports a bounded
non-retention decision rather than an assertion of universal regression.

Derived AOT p99 is adverse in every pair for three target rows: retained angle
(aggregate +29.8%), placement-only (+28.4%), and rejected angle (+29.6%).
With 300 samples, each process has only three observations in its upper one
percent; all values and pair directions are preserved rather than treated as
stable latency guarantees.

The plate-only control never executes instance-placement validation. Its
improved AOT medians/tails cannot be attributed to this source change and show
that the environment/process context varies materially. JIT assembly cold
before-process medians also fall 917→702→580 microseconds across rounds.
Alternating revision order helps but does not eliminate this variability.

## All rows

Times are microseconds. Percent changes compare medians of three process
percentiles, not pooled samples. Pair counts are faster/slower/equal.

| Runtime / case | p50 before→after | p50 Δ; pairs | p95 before→after | p95 Δ; pairs | Derived p99 Δ; pairs |
|---|---:|---:|---:|---:|---:|
| JIT assembly cold | 702→698 | −0.6%; 2/1/0 | 2062→1758 | −14.7%; 2/1/0 | −28.7%; 2/1/0 |
| JIT assembly pose | 153→154 | +0.7%; 1/2/0 | 451→455 | +0.9%; 2/1/0 | −0.1%; 3/0/0 |
| JIT linkage cold | 1914→1891 | −1.2%; 2/1/0 | 2658→2584 | −2.8%; 3/0/0 | +25.7%; 2/1/0 |
| JIT angle edit | 275→265 | −3.6%; 3/0/0 | 516→493 | −4.5%; 2/1/0 | −26.4%; 3/0/0 |
| JIT coupler edit | 659→639 | −3.0%; 3/0/0 | 1001→930 | −7.1%; 3/0/0 | −12.8%; 3/0/0 |
| JIT placement edit | 159→151 | −5.0%; 3/0/0 | 267→246 | −7.9%; 2/1/0 | −33.0%; 3/0/0 |
| JIT rejected edit | 246→240 | −2.4%; 3/0/0 | 487→453 | −7.0%; 3/0/0 | −37.6%; 2/1/0 |
| JIT plate cold | 732→735 | +0.4%; 2/1/0 | 1988→1849 | −7.0%; 1/2/0 | +35.7%; 1/2/0 |
| JIT plate profile | 709→718 | +1.3%; 1/2/0 | 1574→1528 | −2.9%; 1/2/0 | −6.8%; 2/1/0 |
| JIT plate thickness | 589→582 | −1.2%; 2/1/0 | 1258→1068 | −15.1%; 2/1/0 | −8.9%; 2/1/0 |
| AOT assembly cold | 403→436 | +8.2%; 1/2/0 | 587→650 | +10.7%; 1/2/0 | +6.7%; 1/2/0 |
| AOT assembly pose | 48→49 | +2.1%; 1/2/0 | 73→104 | +42.5%; 1/2/0 | +71.6%; 1/2/0 |
| AOT linkage cold | 1856→1825 | −1.7%; 2/1/0 | 2373→2406 | +1.4%; 1/2/0 | −8.3%; 2/1/0 |
| AOT angle edit | 177→186 | +5.1%; 1/2/0 | 271→278 | +2.6%; 1/2/0 | +29.8%; 0/3/0 |
| AOT coupler edit | 553→564 | +2.0%; 1/2/0 | 786→778 | −1.0%; 1/2/0 | +4.6%; 1/2/0 |
| AOT placement edit | 102→108 | +5.9%; 1/2/0 | 161→152 | −5.6%; 1/2/0 | +28.4%; 0/3/0 |
| AOT rejected edit | 159→164 | +3.1%; 1/2/0 | 241→257 | +6.6%; 1/2/0 | +29.6%; 0/3/0 |
| AOT plate cold | 754→744 | −1.3%; 2/1/0 | 1186→1040 | −12.3%; 3/0/0 | −52.4%; 3/0/0 |
| AOT plate profile | 764→737 | −3.5%; 1/2/0 | 1178→1018 | −13.6%; 2/1/0 | −57.7%; 3/0/0 |
| AOT plate thickness | 666→653 | −2.0%; 2/1/0 | 1096→968 | −11.7%; 2/1/0 | −29.5%; 2/1/0 |

## Limits

Three fresh process pairs on shared unpinned hardware do not establish
significance, causal allocation/GC attribution or deterministic latency.
Oracle pass records and paired work equality support unchanged executed work;
full coordinate outputs are not serialized for independent physical replay.
The normal files preserve parsed JSON, commands and timestamps, but not raw
lossless stdout, explicit exit codes or original package-config bytes. Both
current checkouts were separately inspected: their own package root and
effective library URI resolve to the intended checkout. New cohorts should
use the hardened runner to embed and recheck those identities.

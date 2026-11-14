# Independent scalar-bounds retention review

## Decision

Reject the scalar-bounds production candidate from the retained implementation.
Its source review found no correctness blocker, but direct comparison against
main shows repeated AOT costs in the target linkage workloads. Preserve the
source checkpoint, correctness regressions and complete benchmark evidence.

The comparison is main `b3e14fbb298c8d4f3714debbeaffaeb6d550db51` against bounds
candidate `47f20f6ec454e27c26a50ca08286baa853680d7b`. The candidate restores the
entire `CadBodyInstance` class to main; the only production change is the
scalar bounds transformation/helper and import cleanup. It contains none of
the recovered wrapper-elision, validation-split or endpoint-only candidates.

## Verification

The cohort has four fresh process pairs in each runtime, 400 measured samples
after 30 warmups, 48 reports and 20 summary rows. No samples/processes were
removed and no timing workload was rerun by this reviewer.

- Project auditor: 405,818 assertions passed, zero findings.
- Independent JSON/sample reconstruction: 33,243 checks passed, zero findings.
- 160 distributions, 64,000 samples and 64,000 aligned work records reconcile.
- All 400 reported percentile values and every summary aggregate reconcile.
- All 32,000 paired per-sample work records match exactly.
- Independent subprocess review: 1,136 checks passed, zero findings, across
  125 processes, 250 original stream hashes, six compiles and all 48 benchmark
  references. Every process exits successfully without timeout, timestamps
  are sequential, retained results equal parsed original stdout, and explicit
  package mappings/compile-output identities match the recorded revisions.

Scratch audit outputs are `bounds_measurement_audit.json`,
`bounds_independent_audit.json` and `bounds_process_audit.json`.
Raw JSON SHA-256:
`e4e8e106183f3206a663bade9a6e03520edfcd260d7a5a3be7238b8cf7860e85`.

## Retention assessment

AOT linkage cold p50 increases 4.9% and p95 increases 22.2%, both slower in all
four pairs. Retained angle p50 increases 6.3% and p95 increases 40.4%, also
slower in all four pairs. Rejected-angle p50 increases 5.5% in every pair;
its p95 increases 16.8%, slower in three pairs. The other AOT retained-edit
median aggregates also worsen, with three adverse pairs each. These results
provide the strongest reason not to retain this candidate for the latency goal.

JIT linkage medians improve 1.7–3.7%; cold, angle, placement and rejected-edit
medians are faster in all four pairs, and coupler is faster in three. Those
gains remain in the report. JIT p95 is mixed, including rejected-edit +8.2%
with three slower pairs. AOT placement p99 improves 25.1% in all four pairs,
despite that operation's worse median/p95 aggregates.

Several aggregate medians conceal pair directions. JIT assembly cold p50 is
4.2% lower between aggregate medians but is slower in three of four pairs;
the median paired change is +5.6%. AOT linkage cold p99 is 1.0% lower between
aggregate medians but slower in three pairs. These differences are preserved,
not resolved by selecting whichever metric favors the candidate.

JIT plate-control medians increase 16.4–17.0%, although those paths do not call
instance placement/bounds transformation. This is evidence of substantial
environment/process-context variability, not evidence that scalar bounds
execution caused the plate slowdown. It cannot identify whether host activity,
compilation context, code layout or another effect is responsible. The AOT
plate-control medians are close to unchanged. The control changes must not be
subtracted from the target rows or used to erase their repeated adverse pairs.

## All rows

Times are microseconds. Percent changes compare medians of four process
percentiles, not pooled samples. Pair counts are faster/slower/equal. Derived
p99 has four observations in each process's upper one percent and remains
limited tail evidence.

| Runtime / operation | p50 before→after | p50 Δ; pairs | p95 Δ; pairs | p99 Δ; pairs |
|---|---:|---:|---:|---:|
| JIT assembly cold | 635→608.5 | −4.2%; 1/3/0 | +2.6%; 2/2/0 | +20.4%; 1/3/0 |
| JIT assembly pose | 124.5→129.5 | +4.0%; 1/3/0 | +12.6%; 1/3/0 | +11.7%; 2/2/0 |
| JIT linkage cold | 1896.5→1834 | −3.3%; 4/0/0 | −4.6%; 3/1/0 | −1.8%; 2/2/0 |
| JIT angle edit | 272.5→262.5 | −3.7%; 4/0/0 | −0.7%; 2/2/0 | −19.1%; 3/1/0 |
| JIT coupler edit | 644→633 | −1.7%; 3/1/0 | +0.9%; 2/2/0 | −11.9%; 2/2/0 |
| JIT placement edit | 159→155.5 | −2.2%; 4/0/0 | −0.8%; 3/1/0 | +19.0%; 2/2/0 |
| JIT rejected edit | 241.5→235 | −2.7%; 4/0/0 | +8.2%; 1/3/0 | +18.0%; 3/1/0 |
| JIT plate cold | 727→846 | +16.4%; 1/3/0 | +18.1%; 1/3/0 | +23.1%; 0/4/0 |
| JIT plate profile | 693.5→810 | +16.8%; 1/3/0 | +10.6%; 0/4/0 | +14.0%; 1/3/0 |
| JIT plate thickness | 550.5→644 | +17.0%; 0/4/0 | +5.2%; 1/3/0 | +16.9%; 1/3/0 |
| AOT assembly cold | 329.5→339 | +2.9%; 1/3/0 | +7.1%; 2/2/0 | +9.5%; 1/3/0 |
| AOT assembly pose | 47→47 | +0.0%; 0/2/2 | +13.9%; 2/2/0 | +2.2%; 3/1/0 |
| AOT linkage cold | 1804→1892 | +4.9%; 0/4/0 | +22.2%; 0/4/0 | −1.0%; 1/3/0 |
| AOT angle edit | 183.5→195 | +6.3%; 0/4/0 | +40.4%; 0/4/0 | +23.3%; 2/2/0 |
| AOT coupler edit | 584.5→608 | +4.0%; 1/3/0 | +10.6%; 1/3/0 | −13.0%; 3/1/0 |
| AOT placement edit | 109→114.5 | +5.0%; 1/3/0 | +5.5%; 1/3/0 | −25.1%; 4/0/0 |
| AOT rejected edit | 163.5→172.5 | +5.5%; 0/4/0 | +16.8%; 1/3/0 | +23.2%; 2/2/0 |
| AOT plate cold | 691.5→699.5 | +1.2%; 1/2/1 | +1.3%; 2/2/0 | +12.0%; 2/2/0 |
| AOT plate profile | 717→718 | +0.1%; 1/2/1 | +2.9%; 2/2/0 | +5.0%; 2/2/0 |
| AOT plate thickness | 630→632 | +0.3%; 1/3/0 | −0.2%; 2/2/0 | +8.5%; 2/2/0 |

## Limits

Four pairs in a shared container do not establish a universal speed ranking,
causal allocation/GC attribution, significance or a latency guarantee. Source
review establishes algebra/getter/error equivalence, not measured allocated
bytes. Physical-oracle pass records and exact paired work support unchanged
operation work; full geometry is not serialized for replay. Subprocess
provenance records command/result relationships and project/configuration
hashes, not SDK/executable or installed dependency source byte identity.

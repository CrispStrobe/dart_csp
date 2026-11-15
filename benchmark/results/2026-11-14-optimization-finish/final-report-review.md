# Independent final-report consistency review

Reviewed on 2026-11-14 at 21:49:58 UTC. Primary document:
`doc/optimization-final-results-2026-11-14.md`, SHA-256
`244128f465ea16777c8d4ec436b6655ce8e45534a8431c111155443e1e41a41d`.

## Conclusion

No numerical, source-mapping, population, or retention-rationale blocker was
found. The report accurately distinguishes retaining an already present CG
implementation from adding a new speedup relative to current main. It preserves
adverse observations, bounded replication, and the two-session boundary. Final
correctness validation was explicitly pending during review; that section must
be completed from the observed gates, as already planned.

This was a read-only review of saved JSON/Markdown, script interfaces, and Git
trees. It did not rerun physical audits, tests, builds, or benchmarks.

## Verified findings

- Git tree `16214e4755dbd7df711bfd4901b126990b11ab45` is identical for the
  retained source, measured CG endpoint `ad8d237`, and main `46288eb`. The test
  tree is `b0fae52c00e64741ea8b0202bea28c2f2d2617e1`. There is no production
  library delta against main; the additional manifold regression file and
  browser/portable registrations remain.
- All six headline CG table rows reproduce from the original-session JSON's
  elapsed-operation process statistics. Ratio-of-medians and median-paired
  percentages are correctly distinguished. The large 3D cold/warm changes
  (-13.35%/-12.63% ratio of medians), four quoted paired directions, absolute
  reductions, small 2D ladder +24.48%/+20.15% summaries, and its four adverse
  p95 directions agree with the records.
- The original incremental-manifold adverse row reproduces as 6.929461 to
  8.600487 ms, +24.1148% ratio of medians and +14.2642% median paired effect.
  Its three p95 effects are all adverse. The large 3D warm and combined
  rectangle observations also agree. Resumed effects +4.16%/+17.23%, +11.18%,
  and +4.35% match the separate round-four JSON.
- The 13 original and three resumed blocks total 736 processes, 15,456
  measured operations, 5,888 warmups, 21,344 accepted raw records, 1,472
  recomputed percentiles, and 10,672 paired comparisons with zero mismatches.
  Archive member totals are 3,130 + 710 = 3,840.
- Three disjoint protocol reports pass and all have `full_protocol: false`:
  CG rounds 1–4 in `d1244c09828b`; the other three comparisons' rounds 1–3
  in that session; and their round 4 in `b51b355c4f64`. No latency population
  is pooled across sessions. The A/A caveat and absent Laman 500 sentinel are
  accurately stated.
- The remote-ref narrative matches the saved audit: 42 branch heads and all
  ten original PR heads are reachable, including PR #1/#2 through `b0820ed`.
  The pinned portable corpus currently contains exactly 54 file entries.

## Concrete corrections and replay clarifications

1. The linked `retention-review.md` refers near its opening to
   `resumed-block-audit.md`, which is not the preserved filename. Use
   `resumed-session-audit.md` there. The primary final report already points
   to the correct file.
2. Make the replay paths explicit: both raw-audit scripts' `--prepared` takes
   the common parent containing `prepared-cg`, `prepared-identity`,
   `prepared-combined`, and `prepared-aa`, rather than one prepared directory.
   Protocol `--saved` must point to `optimization-final` for both original
   selections and `optimization-finish` for the resumed selection.
3. State that `audit_resumed_blocks.py --out` needs a fresh output directory
   (or at least absent `restored/<block>` children). The script performs a
   second exact restoration and refuses to overwrite existing destinations.
   `tool/unpack_benchmark_evidence.py` likewise requires a nonexistent initial
   restoration destination. These are reproducibility clarifications, not
   additional correctness gates.

## Material limitation worth keeping visible

The full matrix preserves a particularly large individual adverse tail:
CG comparison, 3D ladder 25 cold, round 1 p95 increases from 10.694918 to
130.222576 ms (+1117.61%). Other round p95 changes are +8.73%, -6.02%, and
+9.23%. The final report's table correctly reports this row's much smaller
p50 aggregate. Naming the one-round tail explicitly would make its existing
tail caveat more concrete; it must not be characterized as a stable 12-fold
regression. No further measurement is needed for this disclosure.

No source or repository document was modified by this review.

## Resolution in the completed report

The stale filename is corrected; replay now identifies the common preparation parent, each session's saved directory, and a fresh resumed audit output. The one-round p95 spike is disclosed with its other round values. All final gates subsequently passed at 9b3c4d1; the report replaces its pending-validation section with the verified counts and manifest link.

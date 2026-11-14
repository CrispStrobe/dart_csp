# Executed geometric solver comparison

This directory preserves the actual observations behind the [source assessment](../../../doc/geometric-solver-comparison.md)
and the subsequent execution report. Each run records exact source commits,
binary and harness hashes, CPU affinity, compiler-specific metadata, identical
physical input hashes across engines, failures and deadlines.

## Recovery status

The [recovery report](../../../doc/geometric-solver-comparison-results.md) and
[`recovery-audit.json`](recovery-audit.json) distinguish preserved records from
uploads that did not reach the recovered branch. There are **84 missing raw
archives** in `native-confirm-large-{ladder,coupled}` and
`native-confirm-xlarge-{ladder,coupled}`. Their inventories, manifests and summaries
remain, but their 690 measured samples cannot be independently replayed here.

The original `analysis-native-confirm` is preserved as a historical analysis of
the prior workspace. The separate
[`analysis-recovered-confirm/analysis.md`](analysis-recovered-confirm/analysis.md)
and compressed JSON requalify the files actually present: 72 groups across 216
jobs retain complete raw evidence; 28 groups across 84 jobs are excluded from
qualified latency. Missing data is never represented as a new successful run.

## File layout

- `manifest.json`: run scope, hardware and provenance.
- `summary.json.gz`: exact original per-job summary, including incomplete jobs.
- `archives.json`: SHA-256 hashes and job membership of each raw archive.
- `raw-NNN.tar.gz`: original requests, untouched native output, independent
  checked records, stderr and job metadata, under relative job directories.

The unpacked raw directories and uncompressed summary are ignored by Git. Where
archives are present, their exact contents remain available. To inspect them, extract each archive
into its run directory and decompress `summary.json.gz` if desired. The analysis
tool also supports the archived layout. No failed case is removed from the data.

Native elapsed timings cover adapter construction/update, solving and coordinate
extraction. They exclude process startup, JSON, the independent checker and
product-side rendering/FFI. A solver's native success status is separate from
physical acceptance. Compare completeness and physical acceptance before latency.

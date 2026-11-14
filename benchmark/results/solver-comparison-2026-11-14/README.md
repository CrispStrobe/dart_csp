# Executed geometric solver comparison

This directory preserves the actual observations behind the [source assessment](../../../doc/geometric-solver-comparison.md)
and the subsequent execution report. Each run records exact source commits,
binary and harness hashes, CPU affinity, compiler-specific metadata, identical
physical input hashes across engines, failures and deadlines.

- `manifest.json`: run scope, hardware and provenance.
- `summary.json.gz`: exact original per-job summary, including incomplete jobs.
- `archives.json`: SHA-256 hashes and job membership of each raw archive.
- `raw-NNN.tar.gz`: original requests, untouched native output, independent
  checked records, stderr and job metadata, under relative job directories.

The unpacked raw directories and uncompressed summary are ignored by Git because
their exact contents are already archived. To inspect them, extract each archive
into its run directory and decompress `summary.json.gz` if desired. The analysis
tool also supports the archived layout. No failed case is removed from the data.

Native elapsed timings cover adapter construction/update, solving and coordinate
extraction. They exclude process startup, JSON, the independent checker and
product-side rendering/FFI. A solver's native success status is separate from
physical acceptance. Compare completeness and physical acceptance before latency.

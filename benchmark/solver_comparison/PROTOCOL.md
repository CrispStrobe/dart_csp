# Solver comparison protocol, version 1

This is a native adapter protocol, not a measurement of Dart FFI, a browser,
rendering, or the complete CAD feature graph. Those lanes must be labeled
separately. Source assessment: `doc/geometric-solver-comparison.md`.

## Request and output

An optimized adapter executable reads one JSON file named by its sole argument.
The request contains `schema_version: 1`, `engine`, `mode` (`cold` or `warm`),
`warmups`, `samples`, positive physical `tolerance`, `fixture`, and `edits`.

Uniform unit conversions scale both all lengths and the physical tolerance;
translation-offset tests leave tolerance unchanged. This preserves equivalent
physical accuracy rather than giving tiny-unit cases a looser relative gate.

`fixture` contains:

- `id`: stable fixture identity;
- `points`: initial `[x,y]` pairs, including fixed points;
- `fixed`: indices whose coordinates must stay at their initial values;
- `constraints`: records with `kind`, point indices `a`, `b`, and optional
  distance `value`. Kinds are `distance`, `horizontal`, `vertical`, `coincident`;
- `orientations`: `[a,b,c,sign]` records, requiring `sign * cross(b-a,c-a) > 0`;
- `expected_feasible`: the independently constructed case's expected outcome;
- optional known solution coordinates/description and logical component counts.

Each `edits` entry supplies a complete `values` array, one number per constraint.
Only distance constraints use those numbers; other kinds use zero placeholders.
For operation `i` from `-warmups` through `samples-1`, choose edit
`(i + warmups) % edits.length`. Cold operations start from fixture coordinates.
Warm operations use the previous physically accepted state; when no state has
been accepted, they start from the fixture. No separate untimed ideal solution
is injected. If the API retains model structures, use them and report that fact.

Emit and flush one JSON object per operation with:

```json
{
  "schema_version": 1,
  "engine": "name",
  "mode": "warm",
  "fixture_id": "name",
  "index": 0,
  "warmup": false,
  "build_ns": 0,
  "solve_ns": 0,
  "elapsed_ns": 0,
  "coordinates": [[0.0, 0.0]],
  "reported_success": false,
  "status": "numerical outcome",
  "accepted": false,
  "iterations": null,
  "model_reused": false,
  "active_coordinates": 0,
  "equations": 0
}
```

Extra fields for actual unknown counts, DOF, derivative/linear work, options,
diagnostic costs, errors, and provenance are encouraged. Metadata-only records
use `record: "metadata"` and are not samples. Nonfinite output is a failure;
serialize unusable values as null, never invalid JSON NaN/Infinity literals.

## Timing and acceptance

`elapsed_ns` uses a native monotonic clock from before build/update to after
coordinate extraction. `build_ns` ends when the model is ready for solving;
`solve_ns` measures the solve call. JSON encoding and the adapter's independent
physical acceptance checks are outside those measurements. An external Python
oracle rechecks all returned points and edits. Process startup, JSON transfer,
and checker cost are separately observable, not silently subtracted from an
end-to-end application claim. Work inherent in the solver API, including
unavoidable diagnosis/reconstruction, remains included.

Physical acceptance requires finite coordinates, every fixed-point Euclidean
error <= tolerance, every distance length error <= tolerance, horizontal y-error
and vertical x-error <= tolerance, coincidence Euclidean error <= tolerance,
and all required orientation signs. An adapter exception is never accepted.
Normal numerical termination status is recorded separately; a physically valid
point can pass even if the engine's stopping status is conservative. An engine
success with failing physical checks is recorded as native success with physical
rejection. Numerical convergence, particularly Ceres convergence to a least-squares
minimum, does not itself claim hard feasibility. An adapter claiming physical
acceptance when the oracle rejects is a separate acceptance disagreement.

The runner validates schema, identity, operation indices/counts and nonnegative
timings. Total time must cover build plus solve time (10 ns rounding slack).
The Dart 3D lane additionally reports and checks finite, nonnegative `max_z`.
Only an exit-zero, non-timeout job with the entire requested sequence and no
protocol errors is complete. Partial percentiles remain saved but cannot rank
as complete latency evidence. Exceptions, missing output and timeouts do not
count as successful diagnosis of an inconsistent sketch.

The shared corpus deliberately has only ordinary two-point relations. Arcs,
splines, soft dragging, 3D mates, decomposition, and language-free ABI integration
have separate capability probes. Unsupported semantics are not counted as solved.
Triangulated ladders and triangle-free Henneberg-II Laman graphs are separate
families. The latter are generically locally rigid by construction; their full
move history and independently constructed embeddings are retained. Both use
near-solution starts and dimension edits, not a broad basin-of-convergence test.

## Execution

Use frozen source and optimized native builds. Run one timed process at a time,
after all builds finish. Rotate engine order each independent round. Save raw
records incrementally, including failed and timed-out jobs. Record source SHA,
dirty status, hardware, CPU affinity, toolchains, options, fixture hashes and
command lines. Screening runs may have very few samples; never call their p99
stable. Confirm decision-relevant cases with repeated rounds and larger samples.
The timeout applies to the whole adapter process, including startup and warmups.
Percentiles use the upper order statistic at `ceil((n-1)*p)`; a three-sample p95
is its largest observation. Report normalized physical error (`error/tolerance`)
when comparing uniformly scaled cases. A physical-request hash excluding the
engine name proves cross-engine input equivalence; harness content hashes and
the source commit identify the actual implementation used.

Current Dart experiments are benchmark-only 3D AD, 2D AD, and 2D analytic
representations. They retain the production numerical engine and its tolerances;
the prototype must not be described as a shipped API improvement.

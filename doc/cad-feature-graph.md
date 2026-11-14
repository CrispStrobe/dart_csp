# Scaling the transactional CAD feature graph

The feature graph compiles fixed feature declarations into a stable evaluation
order, parameter-consumer indexes and reverse dependency lists. A changed
parameter seeds only its direct consumers; a worklist discovers their downstream
closure. A sparse edit sorts those affected topological indexes, preserving the
same dependency-first DFS order as the previous implementation. A broad edit
uses a linear ordering pass. Feature callbacks still see only declared inputs
and parameters, and their own previous **committed** output.

Compilation uses explicit DFS frames instead of process recursion. Long,
reverse-listed histories therefore do not consume call-stack depth. Duplicate
feature IDs, duplicate dependencies, missing dependencies and cycles still fail
before evaluation. The regression suite checks a 20,000-feature chain and the
existing diagnostic messages. Every declaration is snapshotted at document
construction so later getter changes cannot invalidate the compiled indexes.
The implementation does not trust `runtimeType` to identify immutable nodes,
because a subclass can override that getter. Compilation uses the private owned
list of declarations, not the overridable public `features` getter on a document
subclass. Callback-captured data must still remain immutable under the evaluator
contract.

Initial parameter values and their revision metadata are also copied and
validated at document construction. A caller's parameter subclass cannot change
committed parameter values while leaving retained feature outputs unchanged.
Required topology references capture their feature ID, semantic ID and kind;
internal validation uses that private list even when a document subclass
overrides the public `requiredReferences` getter.

Compilation handles features with no dependencies without allocating DFS frames
or duplicate-dependency sets. Regeneration shares one immutable empty parameter
scope per parameter revision, and private input/parameter maps retain their
owned snapshots without copying them twice. Retained feature contexts still
observe the exact inputs, scoped parameter values and revisions from their own
evaluation, including rejected candidates; later edits cannot alter them.

## Committed state and rollback

A document has a fixed set of feature IDs. Committed output/revision pairs use
an internal immutable vector split into chunks of 128 entries. The public
`outputs` and `featureRevisions` remain read-only `Map`s, including normal key,
value and entry iteration in stable feature order. Their API and historical
values do not depend on an accumulating chain of delta maps.

An edit stores candidate outputs separately. After every feature has passed its
validation, the candidate copies only the touched chunks and the shallow chunk
directory. Unchanged chunks and output objects remain shared. Required topology
references are then checked against that candidate. Rejection returns the exact
previous `CadDocumentState`; no changed chunk enters its historical snapshot.
Custom feature outputs and callback-captured data must remain immutable, as in
the original feature contract.

A no-op parameter edit does not copy parameter maps or feature state. Changing
an unused parameter commits its new value while reusing the complete feature
store. Changes to used parameters still copy the parameter value/revision maps;
required semantic references are still checked on a commit.
An empty graph with a missing required reference is rejected on its initial
no-op as well. An empty graph without reference obligations still reports
`unchanged`, preserving its existing no-op behavior.

## Structural work counters

`CadRegenerationResult.stats` is an additive `CadRegenerationStats` value:

| Counter | Meaning |
|---|---|
| `scheduledFeatures` | Features selected for evaluation by the changed-parameter closure, or all features on initial construction |
| `dependencyEdgesVisited` | Downstream edges inspected during dirty discovery; initial construction needs no closure walk |
| `stateChunksCopied` | Previously committed chunks copied to isolate the candidate |
| `stateEntriesCopied` | Previous output/revision entries copied within those chunks |
| `stateDirectoryEntriesCopied` | References copied in the chunk directory: `ceil(featureCount / 128)` on an edited state |

The 4,097-feature regression changes two features in separate chunks. It visits
one downstream edge, copies 129 previous entries and 33 directory references,
and retains all 41 historical states correctly across 40 edits. First
construction reports zero *previous* entries copied; it still allocates and
validates every new feature. A rejected edit that fails before snapshot assembly
reports zero snapshot-copy work.

This is not an assertion that total edit work is independent of document size.
A commit still copies the chunk directory, changed parameter maps and validates
required references. Sparse dirty discovery/evaluation depends on the affected
closure; state copying depends on touched chunks plus `ceil(N / 128)` directory
entries. Compilation uses additional indexes and memory, and cold construction
may trade that setup cost for cheaper repeated edits.

## Verification and measurement

`test/cad_graph_scaling_test.dart` verifies stable order, deep histories,
immutable Map behavior, old snapshots, no-op/unused edits, rejection and retry,
mutable declaration snapshots (including a spoofed `runtimeType` and an
overridden document `features` getter), and 600 random DAG edits against independent
full recomputation. Existing solid, reference, placement and assembly tests also
exercise the new store.

`benchmark/cad_graph.dart` uses only the API available at the preceding audit
revision, so identical copies can compare before/after implementations. It
measures fresh construction, a four-feature edit, an unchanged edit, an unused
parameter edit and a rejected edit for 1,000- and 10,000-feature graphs. Outputs
are scalar immutable values: this isolates feature-graph bookkeeping, not solid
kernel, tessellation or nonlinear solver time. Independent output, object
identity, callback-count and rollback checks run outside the timed sections.

```sh
dart run benchmark/cad_graph.dart --check-only
dart run benchmark/cad_graph.dart --samples=25 --warmups=5 --sizes=1000,10000
```

The continuation report records actual paired JIT/AOT distributions. No timing
claim is implied by the structural counters alone.

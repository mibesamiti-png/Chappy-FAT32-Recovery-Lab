# R7 first synthetic shared-source provenance gate (Team A)

**Ownership:** A Issue #1, after review/acceptance of B #89, C #91, D #90. **Starting main:** `913463815e3907930b79afec78d04bd1813a9a63`. All artifacts are generated synthetic data. No original microSD or sole ~31GB IMG access or permission. Local real-image gate is **NOT APPROVED**.

## Why this incremental R7 test matters

The R7 baseline [test](../tests/Test-A3DEvidenceBaseline.ps1) took independently collected B/C/D results and conservatively grouped *candidate extents*, but the module observations were not executed on one metered physical source stream. The new [single synthetic integration test](../tests/Test-A3DSharedReadProvenance.ps1) passes **the same nonwritable generated MemoryStream** through a single A-owned read meter across actual B (directory), C (carving) and D (opt-in observed FAT I/O) modules.

The meter is **test-only**, opens no filesystem/device paths, accepts only geometry/directory/carving/fat consumer labels, records numeric successful physical read [offset, returned count] events and calculates byte-exact distinct offsets once, including overlapping reads. A **single 120,000 returned source-byte cap** applies cumulatively across those modules, not one new cap per module. Read requests that would exceed the remaining cap throw `A7.shared_source_budget_exhausted` instead of pretending to be an EOF; no writes/SetLength allowed.

The B `directoryReadEvidence` field describes **successful directory cluster reads**, not all of B's geometry reads or volume coverage; the test directly cross-checks the B span against the source meter. D's experimental `Get-ChappyFatObservedIoEvidence` uses the same physical meter underneath its own phase logger, and the test cross-checks D's reported actual bytes against A's consumer-scoped trace. C is attributed to a carving consumer with physical read totals, but this **does not** prove that its structural/CRC checks read *exactly the proposed file extent*. Candidate read-origin attachment needs a separately reviewed per-candidate contract and cannot be inferred from scan coverage alone.

## Deterministic scorer and negative controls

- Source: A's fixed 2 MiB FAT32-like disposable M00 and P02 fixtures, seed 202611, using only nonwritable streams. Not standards-sized FAT32; parallel standards-sized A fixtures have separate tests.
- B: read event can be reconciled to a generated root directory cluster; uncertainty and small bounded scan are preserved.
- D: one opt-in trace with 2,048 source byte subcap, no FAT winner, crosslink owner inference, repair or authentic geometry claim.
- C: the clean M00 and altered P02 3MF may both be *structurally valid*, but scorer-only independent SHA verifies M00 original identity while rejecting P02 original identity. The SHA oracle is never provided to module inference.
- Meter: successful source events sum exactly to total actual bytes, unique offsets never exceed total and duplicate bytes are reported once. A separate deliberately over-budget read fails closed with **zero** returned bytes, not an artificial EOF.
- Every scenario validates unchanged input SHA-256. No original names, recovered file content, private path or raw input fragments are printed.

## Acceptance and remaining gaps

This is **one** test of a shared physical stream, an early R7 P1 integration slice, not an R7 completion or a production API. Before final R7 acceptance, A still needs source-identity binding for candidate extents/observations, conflict-aware evidence provenance across different read abstractions, a versioned adapter contract, wider negative/short-read/budget cases and non-oracle fragment-order integration on broader deterministic corpus. B/C/D original issues remain open. Do not start R8 extract/export based solely on this.

The expected CI gate is **23/23 isolated Windows PowerShell 5.1 synthetic scripts**, plus the privacy gate. Record exact-head and post-merge CI before claiming completion. The weighted roadmap remains **39%** until R4–R7 independently pass their full acceptance gates. This number is not a restored-file success rate.

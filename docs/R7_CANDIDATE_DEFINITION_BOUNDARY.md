# A R7 A7-02 — candidate ID versus ordered source extent binding (synthetic only)

Owner: Team A / Issue #1. Reviewed starting main `5318efa43770e0dfbed18212e7bae33e38681491` after A-accepted B #140, C #141, D #142. **No actual microSD or sole master IMG access is permitted**.

## Why the new A boundary is needed

The existing A-issued physical-read meter and `Resolve-A3DReadEvidence` can establish that a particular source stream **returned the bytes at specific physical offsets** under one scoped candidate-validation phase. A read receipt by itself cannot prove that an arbitrary string candidate ID refers to **exactly one ordered set of file fragments**. A caller can reuse the same ID for a different extent length: if the physical reads happen to cover both versions, each independent coverage calculation can be `source_observed` without proving that the two definitions are the same candidate.

`core/Chappy.CandidateDefinitionBoundary.psm1` adds **explicit caller-invoked, side-effect-free candidate-definition preflight**. It never opens a source, hashes or reads any user data, writes an output file, or authenticates identity. It consumes strictly bounded source-relative metadata only: <=32 proposals, 1–4 positive nonoverlapping in-range physical extents per proposal, input length <=100MiB for the artificial integration contract, a finite format allowlist, source-token and candidate-ID size bounds.

Candidate ID must equal `format:orderedOffset+length,...`. The order is preserved (A+B differs from B+A). Under one declared source token, a candidate ID with conflicting ordered extent definitions, an ID reused for another physical extent, an ID inconsistent with its own metadata, two IDs claiming the same ordered extents, a different source token, overlapping or out-of-range extents, or proposal-budget overrun must not be silently accepted as a unique reconstructed candidate. Exact duplicate declarations coalesce to one ID; they never multiply confidence.

Results never expose file bytes, true original filenames or trusted physical-source authenticity. Every result carries `originalIdentity=unknown`, `sourceAuthority=caller_supplied_unverified_not_A_meter` and `readEvidenceStatus=unattributed_pending_A_meter_receipt`. A consistent **definition** is only **eligible for a separate A-meter read-receipt check**; `independentPhysicalReceiptEligible=true` does NOT mean that such a read occurred.

## Synthetic executable P1

`tests/Test-A3DCandidateDefinitionBoundary.ps1` runs the actual existing C two-fragment 3MF scanner against generated in-memory R2 M00 bytes, then:
- Demonstrates actual physically returned bytes can cover both the C-discovered original two-fragment extents and a slightly longer **forged same-ID extent**, while independent physical-coverage results both return `source_observed`.
- Ensures the new definition boundary rejects that same-ID/different-extent collision rather than accepting source coverage as file identity.
- Exercises byte-identical duplicate claims, different IDs for the same extents, reversed ordered fragments, different source tokens, overlapping/out-of-source extents and <=32 proposal cap.
- Confirms no source mutation (artificial SHA identical), no writes, no file path/export, no actual device or master IMG. Independent scorer is NOT passed to the C scanner.

The central native Windows PowerShell 5.1 regression is extended from **38 to 39 isolated synthetic scripts**. Exact final PR-head Windows CI and post-merge main CI must pass before A marks the new A7-02 implementation as accepted; A7-02 still requires full integration/receipt gate review and cannot be signed as full R7 by this increment.

## Remaining blockers / no promotion

The new boundary is **an additive opt-in metadata guard** and does not replace the existing A 120000B shared physical source meter or existing `Resolve-A3DReadEvidence`. It does not authenticate arbitrary caller source tokens or geometry, it does not assert original content identity, and it does not automatically generate an R8 exportable file. A next needs to place this guard into a complete versioned A B/C/D evidence adapter, use A-issued physical source tokens, and preserve UNKNOWN when any definition or read scope disagrees.

Official full-gate completion remains R0–R3 = **39%**, R4/R5/R6/R7 partial. The sole real ~31GB master IMG and physical microSD remain NOT APPROVED for any access or operation; GitHub artificial test memory sources only.

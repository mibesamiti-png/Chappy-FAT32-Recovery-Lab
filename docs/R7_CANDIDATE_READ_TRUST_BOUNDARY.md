# R7 — conservative candidate-specific observed-read boundary (A, synthetic only)

**Issue:** A #1. **Base main:** f21672e09e82d6ab2db551a4efef5fdf414d96be, following accepted B #95, C #96, D #94. The generated 2MiB FAT32-like fixture is not the user's unique ~31GB IMG and is not an independently standards-certified full FAT32 volume.

## Question

A's existing Test-A3DSharedReadProvenance.ps1 measures actual B/C/D read events under one 120,000-byte cumulative source cap. This proves **physical reads occurred**, but cannot prove that any particular C carving candidate was actually validated against those bytes. A scan that happens to touch a file is insufficient evidence to attribute that read to that file. Neither CRC consistency nor the word "verified" authenticates the original source file.

The new **test-only** helper tests/helpers/Resolve-A3DReadEvidence.ps1 introduces a bounded prototype for the next adapter contract: every claim must refer to an **A-issued physical read-event ID**, be bound to the same **A-controlled source token**, carry consumer=carving, purpose=candidate_validation, and the **exact ordered candidate ID**, and cover every proposed extent before marking only **source_observed**. This does not say the bytes are structurally correct or original. The helper explicitly reports originalIdentity=unknown and integrityScope=source_read_coverage_only_not_original_integrity even on full coverage.

This contract MUST be populated by A's actual outer read meter. Treating arbitrary module-supplied event IDs as A-issued receipts would defeat the trust boundary. Existing C's aggregate read metrics and standard carving candidates lack these candidate-bound receipts; their default adapter output therefore stays **unattributed**, not falsely promoted.

## Implemented synthetic negatives

A isolated Windows PowerShell 5.1 tests/Test-A3DCandidateReadTrust.ps1 generates artificial M00 bytes (seed 202611), reads through a strictly nonwritable in-memory source, and constructs A-like physical receipts for two ordered extents. It verifies:

- Complete event-anchored candidate bytes can be marked source_observed, never authentic/original.
- Repeated physical byte ranges contribute **once** to candidate coverage; total **actual reads still include every reread** for quota enforcement.
- Whole-window scanner observations cannot be retroactively called candidate validation.
- Missing/forged IDs, cross-source receipts and same-source **different fragment ordering** fail conservative attribution.
- Unobserved second extent, repeated claimed IDs, excessive cumulative source reads, out-of-image extents, duplicate meter IDs are refused or left unknown.
- Actual synthetic input SHA-256 is unchanged. The oracle never enters the evaluator.
- No file output, API/network, original-media access, repair, copy, hash of original master or actual user-file inspection.

This PR also adds D's independent read-union negative suite (from research-only PR #94) to A's central isolated Windows regression. Expected count **24 to 26** suites. All acceptance links must be recorded only after exact PR head and post-merge main CI complete.

## Remaining R7 gates and progress

This is a **proof-of-boundary**, not a production candidate receipts interface. Before R7 completion: (1) instrument true C per-candidate validator reads without leaking oracle truth, (2) bind A actual meter-issued IDs to candidate claims, (3) test ambiguous multi-source/multi-candidate and partial/short-read scenarios, (4) broader standards-shaped and multi-seed runs with a finite cross-module budget, (5) independently validate fragment-order ambiguity. R8 extraction/export remains blocked pending R7 full acceptance.

Weighted roadmap milestones **R0–R3 fully accepted = 39%**; R4/R5/R6/R7 partial, not finished. The original physical microSD and sole ~31GB master IMG are outside this task. Real-data preflight is **NOT APPROVED**.

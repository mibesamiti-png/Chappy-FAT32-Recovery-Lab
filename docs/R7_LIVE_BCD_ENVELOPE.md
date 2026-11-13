# R7 A7-01 / A7-06 — actual B/C/D live source-read envelope (synthetic only)

Owner: Team A, Issue #1. Base main `e0bb8b2dd778760da8a8a81c6592c8eea730b6d7`. **R7 stage remains incomplete, project weighted 39%.**

## Implemented entrypoint

New `core/Chappy.LiveBcdEvidence.psm1` exports `Invoke-ChappyA7SyntheticLiveBcdEnvelope`, explicitly enabled only by `-EnableSyntheticLiveBcd`. It only accepts caller-provided nonwritable seekable **MemoryStream** generated-artificial sources of 2–100MiB; it has no image path/device/file/export interface. Default OFF reads zero bytes. A's own C# Stream wrapper limits total physically successful returned bytes to <=120000, <=512 Read calls, independently tracks numeric offsets, duplicate and unique bytes and consumer phase.

The same physical wrapper runs actual B directory geometry/candidates, B hierarchy with default-OFF strict unattested-parent protection explicitly ON (`-NeverPromoteUnattestedParentEdges`, PR #148), actual C bounded image-prefix carving, and actual D FAT observed-I/O evidence. A reconciles every consumer's declared returned byte count against the protected outer actual Stream.Read events, rejects mismatches as UNKNOWN, and normalizes candidate ID + ordered extents via A's already accepted `Resolve-ChappyCandidateDefinitionBoundary`.

Output schema: `a7_live_bcd_envelope_v1`. All outcomes stay PARTIAL and `originalIdentity=unknown`. C candidate definitions explicitly say `physicalCandidateValidation=not_performed`, and outer returned read events are expressly not cryptographically authenticated real-media provenance. B original parent/path never proven, D FAT winner/owner not selected, no extraction or write.

## Executable acceptance cases

New `tests/Test-A3DLiveBcdEnvelope.ps1` executes **actual B/C/D production functions** on generated 2MiB M00 and M02 artificial images. It checks default-OFF zero reads, actual vs unique/repeated A source observations, per-consumer totals matching real Read() return values, B strict parent confidence suppression, C candidate ID/extent consistency but no original identity, D no winner or write, SHA-before/after unchanged. Negative tests: writable MemoryStream denied before read; true 17B then zero EOF; total quota 1024B; one physical Read call cap. None can claim success or export.

A central synthetic runner isolated Windows PowerShell 5.1 script is added, 40 -> 41. Exact PR-head and post-main Windows 41/41 + privacy must pass.

## Remaining R7 blockers

A7-01 is PARTIAL: useful live B/C/D result and A actual in-process returned-byte accounting exist, but no true A-issued candidate-specific physical reread/validation receipts, no general beyond-window C data search, and only synthetic memory sources. A7-06 remains AUDIT_NEEDED: a generally reusable versioned public evidence contract and full accepted formal interface are NOT complete; `docs/INTERFACE_V1.md` remains DRAFT. Next A P1 is binding real C fragmentation ordered spans, B coverage and D paired-FAT reports to A-owned phase-scoped successful-return receipts without self-attestation. Never promote mere ZIP/CRC/3MF structure to original-byte integrity.

**Absolute protection:** physical microSD and sole ~31GB master IMG NOT APPROVED for any read/hash/scan/copy/repair/extraction/write/upload; only generated artificial in-memory sources may be used, and R8 output remains blocked.
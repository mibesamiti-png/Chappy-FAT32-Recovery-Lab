# Team A R7 — live C validator reads bound to independent A-issued receipts

**Scope:** artificial 2 MiB FAT32-like in-memory fixtures only (M00, M01, P02, seed 202611). Source main at start: `47e63e56b47b01b16cd16a8f85bc6ad20a4090d9`, after B #99, C #100, D #101 research acceptance. No user source, master 31GB IMG, physical microSD or output directory accessed.

## Integration design

Earlier A R7 [candidate read boundary](R7_CANDIDATE_READ_TRUST_BOUNDARY.md) proved that a claimed validation receipt must match a real physical read, a source token and exact ordered candidate. But that was initially based on A-generated mock observations. Now the new `tests/Test-A3DLiveCCandidateReceipts.ps1` calls the actual *C-owned research functions* `Test-CM01FiniteZipPairs` and `Test-CObservedCandidateValidation` against **one A-owned strict nonwritable Stream**.

An A-owned source meter counts each actual `Stream.Read` return and mints the evidence IDs. A marks the discovery phase as `scan`; it independently selects the ordered candidate's extent key and marks the subsequent explicit C revalidation phase `candidate_validation`. The C function gets a Stream, **never** a trusted source token or evidence ID, and is not allowed to confer authority by setting its own fields.

The test reconciles C diagnostic read-offset records with each actual A physical read event, then invokes `Resolve-A3DReadEvidence` using **only A-minted** event IDs, the A-chosen source token and exact candidate-order identity. An ordinary scan, a forged event ID, another image token or a reversed ordered fragment key cannot receive the candidate attribution. A successful attribution means **`source_observed`** only: it never proves an intact or original file. C's ZIP/CRC consistency remains separate from independent artificial original SHA scoring; P02 corruption remains a negative. Every source SHA is unchanged, all scans are capped and test-only, and writer/repair/export functions are absent.

The existing resolver's synthetic event bound increases from 128 to **256** to include 128 sector-scout reads plus candidate revalidation reads without dropping the scout history from the source budget. A's physical Stream still enforces **one total 120000-byte cumulative cap**. The new regression joins D's existing source-identity study as one standalone isolated suite each, growing the Windows PowerShell 5.1 central suite count **26 → 28**.

## Remaining gates / do not promote

The A `BeginPhase` / `candidate_validation` test harness deliberately trusts its own caller and outer meter. It is not a production API, a cryptographic signature, immutable attestation, or proof that C's generalized production carver performs this same revalidation. This test shows one bounded synthetic research path with finite sector-grid two-fragment candidates, not generic recovery. Future R7 tests must include adversarial phase confusion, multi-source stream contamination, partial read exhaustion, more layout varieties, and candidate-validator receipt integration with a versioned production contract. Only then discuss R8 synthetic separate-root export. Do not claim R7 full acceptance.

R0–R3 fully-gated weighted roadmap total remains **39%**, R4–R7 partial and R8–R10 pending. Actual 31GB master IMG/physical microSD: **NOT APPROVED** for any read/hash/copy/scan/write/repair/extraction/upload.

Final-head Windows and privacy CI plus post-main integration CI are required before marking this PR done; only report actual observed results.

# Team B B4-05 — bounded versioned directory evidence contract

**Ownership:** B, [Issue #71](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71). **Pre-code fixed contract:** [#6856884541](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71#issuecomment-6856884541). **Baseline main:** `822e6990a65b0864398caf8f6f3eaa0be853e485`, after A merged #151. **Status:** Proposed B4-05 result contract until A reviews exact-head CI and signs its gate ledger.

## Entry point and consumer behavior

`modules/directory/DirectoryEvidenceEnvelope.ps1` may be dot-sourced by a caller; it defines `Get-ChappyBDirectoryEvidenceV1`, a B-owned versioned adapter over the **actual production** scanner and hierarchy. It opens no paths/devices and writes no files. It only consumes the caller's `[IO.Stream]`:
- **Default OFF:** without `-EnableDirectoryEvidenceV1`, produces status `disabled`, no candidates and **zero reads**, even if the source is writable. Requires an actual explicit enable before any analysis.
- **Enabled:** rejects a non-readable, non-seekable or *writable* stream before reading. Caller may pass `-Geometry`, which B treats as **unattested**; B itself may read MBR/VBR. Scanner always redacts names: `-IncludeNames` is deliberately not exposed.
- Scan bounds before I/O: `MaxScanBytes` 512–32,768 (default 1024), `MaxCandidates` 1–32 (default16), `MaxDirectories` 1–16, `MaxReadSpans` 1–32, graph `MaxNodes`/`MaxEdges` 1–32, `MaxMetadataItems` 1–128, `MaxAncestorSteps` 1–512. A physical source-quota still belongs in the caller's independent outer Stream wrapper, not in B self-reported counters.
- Graph always uses `-NeverPromoteUnattestedParentEdges`, `-DetectConflictingContainerObservations` and bounded work. Every returned parent edge remains structural **partial** with unchanged reason code; *no* caller-controlled source token or self-ledger can bypass the B strict abstention.
- All exceptions are converted to fixed error reason codes. Never publish raw exception text, filenames, buffers, source hashes or local paths.

## Result: `schemaVersion=b_directory_evidence_v1`

Public-safe `[pscustomobject]` fields:
- `team=B`; `status=disabled|partial|error`; internal `scanStatus`/`graphStatus`; `scanIncomplete`.
- `originalIdentity=unknown`, `originalPathValidation=not_performed`, `canExport=false`, `canSelectFatCopy=false`, `sourceAuthority=B_scanner_report_unattested_not_A_receipt`.
- `bounds` echoes all caps; `geometry` (optional numeric data/root/cluster fields; `attestation=unattested`).
- `candidates[]` bounded numeric entry offset, parent container cluster, start cluster, size, flags, `nameAssociation` enum and structural confidence; `originalIdentity=unknown`; capped `reasonCodes`. **No filename fields**.
- `nodes[]`, `parentEdges[]` and `parentHints[]`: bounded numeric IDs/offsets plus fixed statuses/reason codes, never recovered paths. Every edge `confidence=partial`, `sourceAttestation=unattested`.
- `directoryReadSpans[]` are **only B self-reported successfully COMPLETED directory cluster reads** (offset/length/cluster), each `attestation=unattested`. They **do not cover geometry reads or short incomplete cluster bytes**.
- `metrics.bReturnedDirectoryBytes` and `bIncompleteReturnedBytes` account for successful B `Stream.Read` returns, including early short partial bytes. `metrics.bCompletedDirectoryBytes` separately counts *fully read clusters*. `bDirectoryReadCalls` counts B directory requests. Total/unique *source* returned bytes and geometry returned bytes are expressly `null`, not zero or fabricated. A independently measures those.
- On an unexpected exception, the numeric **read metrics are null/unknown**, not incorrectly reported as zero after possible partial physical reads. No candidate is promoted when a source or module fails.

## Required B4-05 acceptance coverage

`tests/Test-DirectoryR4GateResultEnvelope.ps1` is executed by existing B suite. The source stream is artificial, nonwritable, and independently event-hashed; full generator SHA is held solely by the external test scorer, never B consumer.

| Case/Unit | Expected decision | Original truth boundary |
| --- | --- | --- |
| Default disabled on all three-seed M00/M01/M04/X02 sources | zero actual reads, zero candidates/edges | no original-data inference |
| Three seeds x M00/M01/M04 (9 enabled source scans) with 1024 B B directory cap | 3 retained numeric root candidates each, total **27** instances; B-returned/completed **9216 B**; all source hashes preserved | original identity UNKNOWN9, not 27 files recovered |
| X02 geometry truncated before directory (3 scans) | error/partial and zero B directory reads/candidates, external geometry returns still recorded | UNKNOWN3, not TN |
| One fully observed artificial root-child dotdot parent on supplied synthetic geometry | one edge, only `partial`, status and reason retained, 0 probable | structural relation, not authentic original path |
| 17 B returned and then early EOF in root directory block | B actual returned 17B, completed0, successful span count0; all source bytes include 1024B geometry | no missing original candidate inferred |
| Writable source / invalid max candidate cap | refused before any source reads | safety/budget gate |
| Serialised schema | no names, raw content, path, `verified`, sourceToken or generated oracle labels | compatible candidate metadata only |

**Pre-registered source-cost control:** on three seeds x M00/M01/M04/X02 the test expects **21,504 physical successful source-returned bytes**, **9,216 B-directory returned bytes**, and **252 total `Stream.Read` calls** across 12 source scans, using 97-byte max chunked test-only outer meter. These totals include actual geometry reads for readable images and X02. Separate positive-parent (1536 physical B) and short-EOF (1041 total successful B, 17 directory) tests are kept separate. Actual reported results must be confirmed from final-head Windows CI, not inferred from this planned matrix.

## Stage and ownership limits

This B wrapper is a **production-facing proposal** (not another scanner algorithm), but A must decide how to consume it in `core/Chappy.LiveBcdEvidence.psm1` and the formal `docs/INTERFACE_V1.md`. A's existing `a7_live_bcd_envelope_v1` already physically meters the real B/C/D module source calls and separately marks source returns as **not original-media authenticity**. This B proposal deliberately does **NOT** issue A source-phase receipts, generate `sourceToken`, decide original path, repair/extract, infer FAT owner/winner, or elevate candidate identity. B4-04 and A7-01/A7-06 binding remain A-coordinated.

B4-01/B4-02 A-signed PASS, B4-03 A-signed PARTIAL, B4-04 and B4-05 pending as of this proposal. Official fully gated weighted progress **39%** from R0–R3; R4's formal 10% awaits complete gate closure. Real media trial **NOT APPROVED**: physical microSD and sole original ~31GB master IMG were not read, hashed, scanned, copied, altered, extracted or uploaded. All CI/test artifacts use generated artificial data only. No third-party source copied (Microsoft FAT32/.NET documentation concepts; The Sleuth Kit mixed-license and Linux FAT GPL source no reuse).

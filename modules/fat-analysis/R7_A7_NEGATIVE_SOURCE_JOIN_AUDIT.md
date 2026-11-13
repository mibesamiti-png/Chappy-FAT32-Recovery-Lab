# Team D — R7 adverse evidence support for A live B/C/D integration

**Issue** [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73); **Draft PR** [#177](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/177). Independent four-chat Team D role only, no Work orchestration, no A code or shared-ledger edits. Base main: `59705401d8ae8238b4fe69bfaa876fde78fab683` (2026-11-14 JST). A alone reviews/merges/signs gates.

## Formal progress and why this is a support task, not a new R6 experiment

The entire original FAT R6 synthetic research milestone and all five D6-01..05 subrows **already passed independent A review** (see `docs/R6_FORMAL_ACCEPTANCE_A_SIGNOFF.md`). Its 10 percentage points are already included in the **59% officially accepted synthetic-engineering milestones** (R0–R4, R6). This does **not** imply 59% original lost files restored, true source authenticity, or access to any real media. The current A R7 original candidate-integration milestone remains incomplete: A7-01/A7-04/A7-05/A7-06 are partially reviewed, despite narrow A7-02 and A7-03 passes. After A #176, the 22 indexed subrows show B5, C4, D5 and A2 = **16 PASS, 6 PARTIAL, 0 awaiting audit**.

A's newest `docs/TEAM_DISPATCH.md` and [Issue #73 A instruction](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6865854816) explicitly ask D to assist **R7 negative integration tests**, not create a new adaptive FAT sampler or rewrite A's production integration. A owns `core/Chappy.LiveBcdEvidence.psm1`, the candidate-specific source receipts and acceptance authority.

## R0/R1 provenance and frozen comparison

Before test code, [Issue #73 #6866188344](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6866188344) recorded baseline, bounds, synthetic source truth scope and provenance. Format facts: Microsoft FAT32 File System Specification v1.03 (copyrighted standard); TestDisk (GPL-2.0 upstream) and Sleuth Kit (component-specific licenses) are conceptual forensic comparison sources only. **No third-party code was copied or dependency added.**

Frozen A integration module blob `d59f454a658f00f33196a2dd9ad94146111d2093`; A positive independent FAT receipt test `Test-A3DLiveFatPairOuterReceipts.ps1` blob `8d433d6c7841a9b1d44e1985d7d3a4c45f7af440`; A synthetic FAT32 SPC1/SPC2 generator blob `6e90e3c1b063ced7a9685f8b20c1437a66527405`. All algorithm/sampling interfaces remain unchanged. Only D tests/docs and native Team D Windows CI step are added.

## R2 generated source matrix (scorer-only mutations, never original content)

Nine independent standards-shaped FAT32 artificial MemoryStreams, each with 65,541 data clusters, SPC1/SPC2 and test-only seeds 202625/202626. No user path/device/IMG. Original expected labels, fault offsets and hashes remain scorer-only, not analyzer hints.

| Source type | Expected A live same-session FAT receipt | What must remain uncertain |
| --- | --- | --- |
| Clean SPC1 and clean SPC2 | `A_in_process_numeric_FAT_pair_coverage_consistent` | Unverified source geometry, owner and original content |
| Backup BPB reserved 32 to 31 | `A_in_process_geometry_FAT_block_consistent` | No physical FAT reads, no winner |
| Backup BPB reserved 32 to 33 | Same explicit block | Different in-bounds numeric FAT1/FAT2 offset guesses cannot be followed |
| Equal unsupported mirrored FAT extended flags in both VBRs | Same explicit block | Equal primary/backup fields still not accepted source authenticity |
| Both FAT copies share the same planted cyclic/bad link | Numeric fixed source reads can be internally consistent | Agreement of damaged copies is NOT proof of health |
| Only FAT2 has planted missing/free link | Numeric source coverage consistent, no copy winner | One copy is not automatically original or correct |
| FAT2 contains planted remote entry60000 fault | Numeric source coverage consistent | Remote index never returned, cannot claim it is healthy |
| Strict nonwritable MemoryStream gives first 17B then true `Read()==0` before declared end | UNKNOWN, no numeric positive pair receipt | No 0-byte read may be treated as complete boot/FAT evidence |

Every complete standards-shaped fixed FAT comparison is expected to observe at most **128/65,664** fully source-returned equal-index four-byte FAT pairs, with **65,536 unseen pair indices (99.80506823%)**. The physically observed numerator measures physical *coverage*, not agreement correctness, file ownership or original integrity. A's in-process `sourceAuthenticity=not_real_media_authenticated` is a narrow synthetic instrumentation claim. A receipts are not independently authenticating a real external source.

## Independent D negative event-ledger controls

One additional strictly nonwritable generated source is passed through the already-existing A-owned `ChappyA7LiveMeterV1` class in a test-only D invocation (consumer `fat`). The real `Stream.Read` successful-return offset/length sequence is independently compared to D's actual guarded fixed FAT source-return transcript by `Compare-ChappyFatGuardedReturnedSourceEvents`, a **pure readless helper**. This deliberately does NOT modify the live A envelope, obtain A private source tokens, or create a new A-issued source receipt.

The independent test changes only *copies* of event metadata and demands `unknown` with null paired counts for reordered events, falsely reclassified B/directory events, shifted offsets, missing/replayed observations, inconsistent physical `Read` calls and a forged D paired entry count. Byte-identical original artificial sources are checked by scorer-side SHA256 before and after. All output assertions keep `originalIdentity=unknown`, `fatCopyWinner=not_selected`, `canExport=false`, `canSelectFatCopy=false`, and no repair/writer. The comparison helper cannot prove an event array is authentic; it can only reject an inconsistent one.

## Resource ceilings, scoring interpretation and team boundary

- A live invocation: 120,000 actual returned source bytes and 512 physical `Read` calls shared across B/C/D. D guarded fixed FAT phase: at most 4,096 actual returned bytes and 256 read calls (A invocation cap). D test-side source meter: 120,000/512; no writes or unbounded FAT scan.
- Count all nine source cases separately; aggregate actual/unique/repeated returned bytes **source-local**, never pretend the sums describe one user's source. Anomaly/metadata truth and stream EOF remain separate scorer categories, not original-file recovery TP/FP/FN/TN.
- Passing this D-only negative test gives A evidence to assess narrow A7-04 conflict/UNKNOWN and A7-06 safe integration. It is **not** an A-signed A7-04, A7-06 or full R7 PASS. A reviews exact final PR-head Windows PowerShell5.1 and privacy CI, then integrates in its own chat. No new formal project percentage is self-assigned.

**Absolute safety:** The original microSD and sole approximately 31GB master IMG are **NOT APPROVED for any access** (no read/hash/scan/copy/write/repair/export/extract/upload). Generated artificial MemoryStreams only. R8 separate-destination output remains blocked.
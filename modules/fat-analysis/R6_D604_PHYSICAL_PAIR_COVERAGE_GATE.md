# Team D D6-04 — Physically returned FAT-pair coverage acceptance evidence

Issue: https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73  
Draft PR: https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/149  
Base main: c52b2b6ef987f211b8a881f6708eeb342d866ee7  
**A-only gate signoff and merge. This does not approve real-data use or claim a real-file recovery rate.**

## R0 and R1 frozen before code

Registration: https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6853753361

Existing benchmark modules and their hashes:
- Fat32ObservedIoEvidence.psm1: b1f6d0ceea222335c16de9532ed49cb35a312aad.
- Fat32MirrorWindows.psm1: 2e9b0864ecc15d98bdeaa76a19167d3bbcde4555.
- Run-TeamD-R6-StandardFatCoverage.Tests.ps1: existing synthetic independent physical source meter and manually checked FAT coverage.
- New-ChappyA3DStandardFixture.ps1: generated FAT32 65,541-data-cluster source image, seed series 202611/202612/202613.

R0 references: Microsoft FAT32 specification v1.03 (copyrighted standard), CGSecurity TestDisk official docs (GPL-2.0 source), The Sleuth Kit official docs (component-dependent licenses). No external code copied or dependency added. Previous adaptive sampling was worse overall, so neither the current FAT sampling schedule nor the default production behavior is changed.

The prior D P10 test counted complete returned 4-byte FAT entries **inside tests only**. D13 exposed physical source read intervals and actual/unique counts, but no reusable D result could compare those internal claims with a separate outer source read-event observer and report conservative paired FAT coverage.

## R2 and R3 — Small bounded read-only implementation

New, opt-in D-owned Fat32PhysicalPairCoverage.psm1 exports Get-ChappyFatPhysicalPairCoverage. It is a pure numeric helper: **no Stream.Read, file open, path access or write**. It accepts a D13 observation, an independently supplied ordered list of successful **actual returned** source-event spans, and caller-supplied FAT copy offsets/length and source length. Any event/list mismatch, forged span, read-cap violation, invalid geometry, inconsistent total or unique byte accounting, source truncation or early physical zero yields **UNKNOWN and null pair counts/percentages**, not a misleading healthy or zero-coverage claim.

The source events are only **caller supplied**. Even when every D and outer span agrees, this does **NOT** authenticate a source, supply an A-issued source-token receipt, prove FAT32 geometry or name/owner/original bytes.

When the check succeeds it counts only fully physically returned 4-byte FAT entries in FAT1 and FAT2, intersects equal **numeric entry indices**, and reports the paired complete and unobserved remainder. A physically returned 1–3-byte part cannot count as a full entry. Duplicate source reads cannot inflate unique bytes or FAT coverage. The helper enumerates at most 256 success events and 2048 returned source bytes; the independently metered synthetic source uses a separate 120000B cap. The output always has an unverified geometry/source provenance and no FAT winner, file owner, original identity, repair or export authorization.

**Important existing D13 limitation:** Its geometry phase permits 1024B for primary MBR+VBR, but its older geometry parser may still try backup VBR/FSInfo and emit io.backup_vbr_truncated and io.fsinfo_truncated plus a reject status for the *unread* secondary sectors. The new D6-04 helper distinguishes that **specific recorded internal phase-budget clipping** from actual physical EOF or hard BPB contradictions. It permits only caller-geometry **numeric coverage accounting** when the sole rejection reasons are those two phase-cap effects; no geometrical trust is promoted. Bad SPC and FAT extents still produce UNKNOWN. D13 itself and all its pre-existing ABI/tests remain unchanged.

New Run-TeamD-R6-GatePhysicalCoverage.Tests.ps1 independently implements a nonwritable .NET Stream.Read observer for generated artificial images only. It tests:
- 9 generated standard-size cases: clean 1-sector/2-sector clusters, single-FAT mismatch, common-mode two-FAT cycle, far FAT2 entry60000, malformed SPC, impossible FAT size, 1100B early EOF and 1026B partial FAT return.
- Input SHA256 unchanged, actual source-return calls, actual/unique/repeated byte union, per-FAT complete 4-byte paired coverage.
- Invalid/reordered/missing/replayed/offset-shifted and over-cap outer read events, overlapping/overflow FAT geometry, writable stream rejection.
- No user IMG, no file names, no authenticated original ownership, no synthetic result promoted to a FAT winner.

## Measured Windows PS5.1 synthetic evidence

Initial code-head Windows native CI: https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43432227444 — **79 PASS, 0 FAIL** in new D6-04 suite and preceding D tests pass. This CI ran before this report-only commit; **A must verify both Windows and privacy checks on the exact final PR HEAD**.

| Source-level result across nine separate generated sources | Value |
| --- | ---: |
| Numeric candidate-only cases | 5 |
| Incomplete/malformed cases, full paired coverage UNKNOWN/null | 4 |
| Declared FAT entries per copy (valid standard-shaped cases) | 65,664 |
| Fully source-returned paired FAT entries per valid case | **64** |
| Unobserved paired entry indices per valid case | **65,600** |
| Physical pair coverage fraction (numeric candidate only) | **0.09746589%** |
| Unobserved pair fraction (NOT verified healthy) | **99.90253411%** |
| Total actually returned source bytes (sum independent runs) | **12,146 B** |
| Sum of unique physical source bytes per run | **11,854 B** |
| Repeated physical bytes across runs (within source only) | **292 B** |
| Source physical Stream.Read calls (sum) | **437** |
| Synthetic source bytes altered by diagnostic reads | **0** |

The planted remote FAT2 entry60000 was **not physically returned**. Therefore the result is **UNKNOWN**, never absence of corruption. Both equal-corrupted FATs also do not become authentic or healthy merely because the window compared equal. These units are *physical observation and interval agreement*, not restored files. No TP/FP/FN/TN for original-file recovery is asserted because original source authenticity and ownership are absent.

## R4 decision requested from Team A

D6-04 now has a reusable, opt-in, bounded D typed numeric evidence result, rather than only a test helper. Source event comparison rejects counterfeit or incomplete read interval claims; A must still bind genuine independent A-issued source-scoped physical receipts to the same underlying source, and verify integration with B/C/D before claiming source-authenticated evidence. **A decides D6-04 PASS versus PARTIAL** after exact-head Windows PS5.1 and privacy CI review. Do not change A-owned shared gate ledger from Team D.

Other D status at start: D6-01 A-signed PASS, D6-02 PARTIAL, D6-03 PARTIAL, D6-04/D6-05 AUDIT_NEEDED. Official full-stage project completion **39%** (R0–R3) and overall **4 PASS, 6 PARTIAL, 12 AUDIT_NEEDED of 22**. No R6 10-point stage credit until every original requirement is A-accepted. No invented D subjective implementation-completion percentage.

**Absolute safety:** real microSD and sole approximately 31GB master IMG remain NOT APPROVED for reading, hashing, scanning, copying, repair, writes, extraction or upload. All inputs generated in memory; R8 stays blocked.

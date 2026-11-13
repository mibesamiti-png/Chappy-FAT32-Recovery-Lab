# Team D R6 D6-03 — strict equal-but-unsafe BPB refusal, legacy D5 preserved

**Owner:** Team D / [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73) / [Draft PR #161](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/161). **Status:** D6-03 PARTIAL before A review. This document is a D-specific technical acceptance record; A alone decides final row PASS/PARTIAL, merges and updates the ledger. Four separate chats, not Work.

## R0/R1 registered before coding

[Preregistered D6-03 source/baseline/matrix and quotas on Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6859815098). Verified starting main `1f4bf2cd94b7c41ba71bcd99f4bc12bcb10381d4`.

- Microsoft *FAT32 File System Specification v1.03*: conceptual semantics of `BPB_HiddSec`, `BPB_ExtFlags` (enabled/disabled FAT mirroring and active-copy selection) and FAT32's minimum 65,525 data-cluster classification threshold. Copyrighted specification; no source code reused. CGSecurity TestDisk (GPL-2.0) and Sleuth Kit (mixed-license) source/reference for conceptual comparison only, no code imported.
- Existing **legacy D5** numerical source sampler `Fat32VbrDisagreement.psm1` initial blob `327435db53485b413d581b20513eae174eecf30e`; existing deny-only D6-03 `Fat32GeometryHypothesisGate.psm1` blob `13306c9aa5a8a197858148d1111ef063bea221d5`; A-accepted D6-05 versioned `Fat32GuardedResult.psm1`; A-generated `New-ChappyA3DStandardFixture.ps1` blob `6e90e3c1b063ced7a9685f8b20c1437a66527405`.
- Frozen runtime: D6-03 reads only MBR, primary VBR, primary-declared backup VBR and primary-declared FSInfo, at most 2,048 **physically returned** B / 256 actual Read calls. D6-05 global total at most 4,096 actually returned B /512 Read calls. Independent external nonwritable in-memory test source enforces 8,192 returned B /640 calls and measures actual/unique/repeated physical positions and true premature 0 returns. No real-media access.

## Narrow implementation and compatibility fix

The original **D5** candidate parser is an explicitly numerical historical research interface, including small 2MiB FAT32-like synthetic volumes with 503 clusters that it correctly labels as *numerically plausible*, not authenticated genuine FAT32. First code-head CI exposed a real regression when strict FAT32 eligibility rules were mistakenly applied to its legacy candidate grade. We **reversed those semantic grade changes** and put the new strict rules only in D6-03's **deny-first guard**. No changes to historical D5 sample windows, read cost, version, or legacy `plausibility` semantics.

- D5 **adds only observable BPB metadata**, exposing `hiddenSectors` and `extendedFlags` as numeric fields and comparing `hiddenSectors` between primary/backup, with no additional D5 plausibility reclassification or source reads.
- D6-03 **consumes those same already-read BPB numbers**, and *overrides only the safety gate's* per-copy grade from `plausible_unverified` to `contradicted` if any of these strict conditions applies:
  1. `BPB_ExtFlags != 0`: this **fixed two-copy mirrored diagnostic** cannot safely interpret a volume requesting single active FAT or reserved bits. A disabled-mirroring FAT32 may be structurally valid in other software; here it is **unsupported for this observer**, not automatically corrupt.
  2. `BPB_HiddSec` contradicts the independent MBR partition start sector, including when *both* BPBs agree on the wrong hidden-sector number.
  3. Numerically computed data-cluster count **below 65,525** while pretending to be FAT32, including matching in-range BPBs with a FAT16-sized geometry.
- D6-03 retains two primary/backup hypotheses with explicit per-role new reason codes, distinct `agreement` and `scanIncomplete`, numeric FAT offsets and still-unverified authenticity. The result always has `fatRegionProbeCount=0`, `fatReadAllowed=false`, `selectedCandidate=null`, `sourceDecision=not_selected`, `writePermitted=false`, original identity UNKNOWN.
- The already-accepted **D6-05** guard sees these stricter grades automatically **before** its fixed FAT phase, physically refusing any FAT-region reads on conflicts/unsupported mirror flags/MBR/threshold contradictions or true short source. Its exported versioned schema remains unchanged and no independent A-source token is invented.
- Importantly, if both BPBs match and are structurally plausible but the FAT starts are **still unverified**, an explicitly opted-in fixed bounded sampler can run. This is *candidate-only*; no winner, real owner, path, source authenticity, physical FAT health or repair can be concluded from matching BPBs.

## Held-out synthetic matrix (scorer-only mutation labels)

A-owned generated **standards-shaped FAT32** sources, seeds 202620–202621, sectors per cluster 1/2 and 65,541 data clusters; one extra intentionally **tiny 200-data-cluster FAT32-like** source produced by shrinking a generated image and adjusting MBR and both BPBs to in-bounds values, with consistent FSInfo. The diagnostic receives only the resulting generated bytes, never the damage offset, scorer class, seed or expected answer.

| Case | Expected guard result | Physical FAT reads |
| --- | --- | --- |
| Clean standard SPC1, clean standard SPC2 | `candidate_geometry_unverified` | D6-03 zero; explicitly enabled D6-05 may sample fixed |
| Backup reserve 32→31 and 32→33, both numerically in bounds | `blocked_conflicting_geometry` | Zero |
| Both boot records with `ExtFlags=0x0080` or `0x0100` | `blocked_contradicted_geometry` | Zero |
| Both or only primary or only backup `HiddenSectors=2` but MBR start=1 | `blocked_contradicted_geometry` | Zero |
| Tiny 200-cluster FAT32 lookalike, both BPBs matching | `blocked_contradicted_geometry` | Zero |
| Backup one-sector-too-small FAT capacity / both `SPC=0` | `blocked_contradicted_geometry` | Zero |
| Both matching `reserved=33` but actual source FAT data not relocated | `candidate_geometry_unverified` | An explicit bounded fixed sample may occur, but geometry and original source still UNKNOWN |
| True physical source 0 return after 1,100 returned B with 7B chunks | `blocked_insufficient_evidence` | Zero |

The pre-registered narrow scorer has **10 structural BPB conflict/unsupported positives, two clean negatives and two unscored UNKNOWN** (plausible-but-unverified shifted layout; true physically incomplete source). This is only a **planned artificial structural confusion matrix** until Windows CI confirms; no true file recovery rate can be calculated. No checker may use missing/far FAT bytes to declare a copy healthy.

The dedicated independent test is `modules/fat-analysis/tests/Run-TeamD-R6-StrictBpbBoundary.Tests.ps1`, exercised as an additional Windows PowerShell 5.1 CI step. It invokes *both* D6-03 and D6-05 on separate independently metered nonwritable sources and checks returned byte union, source calls, VBR result, total FAT probes, deny-first physical safety, unknown/winner/repair abstention, and synthetic source SHA-256 unchanged. Windows and privacy CI must pass on the **exact final PR HEAD**, not an earlier code-only commit.

## A gate decision and residual dependencies

**D6-03 original row:** this PR remedies structurally unsafe *equal* VBRs without breaking historical numerical R5/D5 research. It does not solve the independent authenticity of MBR/primary/backup or prove which FAT offset is correct. Real-source A-issued physical receipts and A7-01/A7-06 B/C/D integration remain A scope; D6-04 stays PARTIAL pending A outer physical read-event binding. A may leave D6-03 PARTIAL if its full original acceptance requires cross-team source authentication, even with all artificial cases green.

At start, A-signed 8 PASS /14 PARTIAL /0 AUDIT_NEEDED across 22 scoped R4–R7 rows; D R6 3 PASS (D6-01, D6-02, D6-05), 2 PARTIAL (D6-03, D6-04). Official fully gated project R0–R3 completion **39%**, R4–R7 full-stage points remain zero. No self-merge, no weighted progress self-credit.

**Absolute safety invariant:** real microSD and sole ~31GB master IMG remain **NOT APPROVED for any** read, hash, copy, scan, repair, extraction, write or upload. Every test uses generated synthetic in-memory strictly nonwritable sources; R8 remains blocked.

# Team D R6-P7 — sparse FAT mirror sampling blind spots (research_only)

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #113](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/113). A-assigned branch `research/d-r6-mirror-sampling-blindspots-20261112` was created at A-reviewed main `9393fce2b9651b478a6861f7c44c26636acbfb86`. Main at task start `30b800f0a9c127164e5f22db3306250edf64b969` was 3 commits ahead. Previous Team D #104 was reviewed and merged **research_only**; this P7 does not reimplement/alter its modules.

## R0 — official prior research, source and licenses

The complete R0/R1 preregistration was [posted on Issue #73 before code](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6816673794).

| Original author / published method | Relevant rationale / failure modes | Reuse/license boundary |
| --- | --- | --- |
| Microsoft Corporation, *FAT32 File System Specification v1.03* (2000), archived at https://www.osdever.net/documents/fatgen103.pdf | A FAT mirror consists of numbered four-byte entries. Comparing a small prefix cannot discover differences in unobserved distant entries. Two *identical corrupted* FAT copies can share the same wrong links. | Copyrighted document, not a permissive software license; **no text or implementation copied** |
| Christophe Grenier / CGSecurity, TestDisk official filesystem repair notes https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Independently preserved FAT and boot-sector metadata can form multiple competing hypotheses; neither disagreement nor agreement authorizes choosing or writing a winner. | GPL-2.0 source; no code copied/imported, future copying requires review |
| Brian Carrier / Sleuth Kit Labs official repo https://github.com/sleuthkit/sleuthkit and license notices https://www.sleuthkit.org/sleuthkit/licenses.php | Filesystem forensic observations are always scoped to physically observed source bytes. Unobserved FAT entries, partial reads and absent directory owners cannot prove original file integrity. | Mixed file/component licenses; **license_review_required** for reuse; none reused |

Only existing in-repository D modules and first-party PowerShell/.NET test code were invoked. The goal is measured sparse observation, not deriving a repair algorithm from third-party software.

## R1 — frozen baseline, deterministic truth and resource caps

- **Baseline (unchanged/default-OFF):** `Get-ChappyFatObservedIoEvidence -Mode MirrorAndChain`, with one 1,024-byte geometry read budget, a 64-entry first FAT-copy comparison (512B max) and fixed seven generic chain starts 2..8. This was previously accepted as **experimental/default-OFF**, not a certified original-file validator.
- **One TEST-ONLY candidate (NOT product API):** call existing unchanged `Get-ChappyFatGeometryTrust`, then existing unchanged `Get-ChappyFatMirrorWindows` on **three predetermined disjoint 16-entry windows** beginning at FAT entries **0, 128 and 256**, then unchanged `Get-ChappyFatChainAnomalyStats` for starts2..8. Nominal maximum phase budget = geometry 1,024B + three windows ×128B + chains 448B = **1,856B**. The windows are the same for every case; no mutation hint, original SHA, path, label or owner reaches the diagnostic functions.
- **Both independently invoked methods have the same physical upper bounds:** **2,048 actually returned bytes and 256 physical Stream.Read() calls per method per case**, via an independent, strictly non-writable metered in-memory input. Counts do **not** reset between phases. The baseline and candidate do not necessarily do the same work; actual byte and call costs are reported separately. No equal-speed claim.
- Deterministic A-generated ~2MiB **FAT32-like** images using `tests/helpers/New-Chappy3DDamagedFixture.ps1` SHA blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5`, seed **202611**, M00 clean/M01 legitimate nonadjacent chain/M02 FAT1-only link break/M03 both FATs same cycle/M05 cross-file link/X02 physically shortened payload. Three extra variants are created by the **external scorer only** from M00: FAT2 cluster4→8 while FAT1 cluster4→5 (both chains end EOC, ambiguous winner), reserved marker at FAT2 entry256 (outside baseline prefix), and reserved marker at FAT2 entry512 (outside both schedules). Artifact bytes and scorer original hashes remain outside algorithms.
- **Binary score applies ONLY to six explicitly selected synthetic FAT-anomaly cases:** M00 and M01 negative; M02, M03, contradictory in-window link and distant entry256 anomaly positive. M05 cross-file owner, X02 shortened source, entry512 unobserved, genuine early stop and a 32-byte budget are five **unscored UNKNOWN** cases. The score is neither generic FAT health nor original-file recovery. No ground-truth original user file is reconstructed.
- Faults: one physical source returns 7-byte chunks until 1,200 total returned bytes, and one separate source has a 32-byte physical hard cap. Physical source, file names, cryptographic source identity and original IMG cannot enter the test.

## R2 — bounded negative-controls-only implementation

Changed only `modules/fat-analysis/tests/Run-TeamD-R6-SamplingBlindspots.Tests.ps1`, this research report, and **one D-only Windows PowerShell 5.1 workflow step**. The independent scorer constructs in-memory source images; the `D20PhysicalMeter` nonwritable wrapper independently tracks the actual physical returned bytes, distinct physical byte offset union, all physical `Read()` attempts, and exact observation of scorer-planted distant offsets. It compares existing D code to a test-only fixed three-window schedule.

Any result has `scanIncomplete=true` for full FAT health, `sourceDecision=not_selected`, no authenticated original identity, no FAT copy winner and no writer. The physical observation of a reserved/mismatched FAT entry does not establish which FAT copy is true. The scorer checks actual SHA before and after method calls; no source file is exported.

## R3 — actual native Windows PowerShell 5.1 measurements

**First code+CI HEAD:** `176f1933ebd8cbca8f8d980860ecac45b505bca7`. [Native Windows PowerShell 5.1 CI #43170332212 — SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43170332212): **new P7 79/79 synthetic assertions PASS** and existing D suite steps PASS. [Code-head privacy/isolated synthetic regression #43170332568](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43170332568) was initially in progress; exact final report HEAD requires rechecking both gates after this documentation commit.

| Exactly six *selected* artificial FAT anomaly examples | Existing first-64-entry mirror+chain | Fixed 0/128/256 3-window+chain |
| --- | ---: | ---: |
| TP / FP / FN / TN | **3 / 0 / 1 / 2** | **4 / 0 / 0 / 2** |
| Recall on *4 planted* selected anomalies | 3/4 = 75% | 4/4 = 100% |
| FP on two selected normal controls | 0 | 0 |
| Unscored UNKNOWN scenarios | **5** | **5** |
| Real user original-file recovery | Not tested | Not tested |
| Authenticated FAT winner, file owner, original identity, repair | **0** | **0** |

| Physical source cost across ALL 11 artificial inputs, same source per pair | Existing baseline | Fixed candidate |
| --- | ---: | ---: |
| Actual returned bytes | **15,636 B** | **14,484 B** |
| Distinct physically returned source bytes, summed per invocation | **15,056 B** | **13,904 B** |
| Repeated source byte reads | **580 B** | **580 B** |
| Physical source `Read()` calls | **372** | **412** |
| Hard upper cap per invocation | **2,048 B / 256 calls** | **2,048 B / 256 calls** |
| Timing/peak RAM advantage | not established | not established |

**Case-specific findings (all artificially planted):**
- M00: no observed disagreement/cycle in either schedule; **not** a whole-FAT healthy verdict.
- M01: legal discontiguous fragmentation remains unflagged.
- M02: one FAT-copy mismatch detected by both, neither chooses the winner.
- M03: a shared corrupt FAT cycle is observed by both chain probes despite equal FAT copies.
- CONFLICT: FAT1 4→5→EOC and FAT2 4→8→EOC give equally plausible **terminal categories**, but different links; both schedules see one mismatch and never infer which is authentic or true file ownership.
- REMOTE256: baseline did not physically read the planted entry, **missed** anomaly; three-window candidate physically sampled and detected it.
- REMOTE512: neither schedule physically sampled the planted entry; therefore undetected **UNKNOWN**, never counted as a healthy original.
- M05 file-owner crosslink, X02 physically truncated source: the FAT-only evidence cannot establish file ownership/complete original data; remain **UNKNOWN**.
- EARLY_STOP: both modes returned only **1,200 actual B**, with physical read call caps enforced; candidate may report a *locally observed* mismatch before source exhaustion, but must not call this a complete FAT or original file.
- CAP32: both modes stopped at ≤32 actual B and refused any complete FAT/geometry claim.

**Interpretation:** the candidate reads 1,152 fewer actual bytes across these *11 fixed cases* but performs 40 more physical Read() calls. These counts do not constitute a performance/speed win or a real-world recovery rate. A fixed remote window targeting a planted location in the chosen corpus may overfit that location; other distant entry locations (such as 512) remain unsampled. More seeds, randomized corruption positions and independently selected windows are necessary before any broader recommendation.

## R4 — Team A review and next steps

Recommend **research_only**. The alternative is test-only, has no product/default switch and does not conclusively demonstrate generalized benefit because of fixed-window bias, incomplete physical coverage and higher random I/O call cost. Team A should independently inspect physical caps, fixed sample independence from scorer truth, remaining out-of-window false-health risk, and whether bounded randomized/stratified sampling is warranted as a separate assignment. Retain R6 issue OPEN, A owns R7 candidate meter/source-id and all shared interfaces. No real microSD or sole ~31GB master IMG read, hashed, copied, scanned, uploaded, exported, written or repaired; real-media approval **NOT APPROVED**.

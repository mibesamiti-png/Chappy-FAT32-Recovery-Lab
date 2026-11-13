# Team D R6 D6-05 — Stable guarded FAT result v1

**Issue:** [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73) · **A assignment:** [#6854892106](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6854892106) · **Draft PR:** [#153](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/153). A alone reviews/merges/signs the ledger. This is not an authentication of FAT geometry, source media or original-file integrity.

## R0/R1 — Before-code registration and frozen existing behavior

The [R0/R1 preregistration](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6856843245) froze: starting main 822e6990a65b0864398caf8f6f3eaa0be853e485; existing D6-03 geometry gate Fat32GeometryHypothesisGate.psm1 blob 13306c9aa5a8a197858148d1111ef063bea221d5; D13 observed FAT I/O Fat32ObservedIoEvidence.psm1 blob b1f6d0ceea222335c16de9532ed49cb35a312aad; D6-04 source physical coverage Fat32PhysicalPairCoverage.psm1 blob 0516f28ed64a6e3af228e3391f5b3f7f3b630829; and fixed FAT mirror windows blob 2e9b0864ecc15d98bdeaa76a19167d3bbcde4555. A-approved standard artificial generator seeds 202614/202615/202616 and sectors/cluster 1/2. Prior adaptive sampler #138 was worse and **is not promoted**.

R0 attribution: Microsoft FAT32 File System Specification v1.03 (copyrighted standard; conceptual reference only); CGSecurity TestDisk (GPL-2.0 upstream, documentation only); Sleuth Kit (component-specific mixed licenses, documentation only). No external code copied or dependencies added. The new adapter is independently authored Windows PowerShell 5.1 plus built-in .NET.

## R2/R3 — Real D6-05 interface gap resolved

Prior to this PR, D had separate opt-in modules to (a) reject contradictory primary/backup VBR geometry, (b) sample FAT mirrors and limited chains, and (c) reconcile fully physically returned 4-byte FAT entry pairs. **There was no single importable D interface that actually enforces VBR refusal before FAT content is read, with a stable versioned result schema and a cumulative physical byte/call cap.**

Added one separately importable, **default OFF** D module: modules/fat-analysis/Fat32GuardedResult.psm1, exporting Get-ChappyFatGuardedResult. Existing D13 and D6-03/04 fixed-sample modules remain unchanged.

- Schema: schemaVersion=1, contractVersion=d6_guarded_fat_result_v1, team=D, status and guardDecision, fatProbeState, unverified hypotheses, two indexed per-copy observations, aggregate evidence, reason codes, warnings and metrics. The same fields exist for disabled, sampled, conflicting/invalid, early source zero, exhausted budget and exception paths.
- Default OFF = zero source reads. Explicit opt-in requires readable, seekable, strictly nonwritable caller Stream. The module has **no file/device/path open or write code**.
- One outer D meter counts up to **4,096 actual returned source bytes and 512 delegated physical Read calls**, shared across all stages; source-local actual/unique/repeated byte counts and phase costs are separated.
- Run existing D6-03 primary/backup VBR hypothesis gate **FIRST**, <=2,048 returned bytes and <=256 reads. Conflicting primary/backup BPB, contradicted boot, missing or partial physical return immediately BLOCK subsequent FAT scanning: externally observed physical FAT-region Read calls must be **zero**.
- Only when two matching numerical candidate-only VBR hypotheses remain plausible and the caller explicitly opted in can the existing **fixed** D13 sampler run. Default D13 mode is MirrorOnly (128 physical 4-byte entry pairs in the standard test) with <=2,048 returned bytes. Explicit IncludeFixedChainEvidence uses existing MirrorAndChain (64 physical pairs plus fixed chain starts2..8) under the same cap.
- D6-04 compares its D13 inner successful read events with the new outer D meter's successful returned spans specifically tagged as the FAT phase. It only counts **fully actually returned 4-byte entries** in FAT1 and FAT2 and their same-index intersection. Repeated reads never expand unique coverage. Forged/incomplete source data, zero FAT bytes physically returned or budget-refused requests yield UNKNOWN, null coverage and no repaired-file claim.
- The two meters are **both D-internal**. Agreement is **NOT A-source-scoped attestation**. A7 must independently bind authoritative source tokens and full physical event receipts; D's result explicitly keeps sourceReadProvenance=internal_D_source_events_NOT_A_attested.
- Always geometryAuthenticity=unknown, sourceIdentity=unknown, originalIdentity=unknown, fileOwner=unknown, fatCopyWinner=not_selected, selectedCandidate=null, fatReadAllowed=false (no automatic follow-up authority), wholeFatVerified=false, writePermitted=false, canRepair=false, canExport=false and scanIncomplete=true. Even matching numeric BPBs are NOT authentic and cannot choose a FAT winner or true source.

## Synthetic evidence matrix and measured cost

Dedicated D-owned Windows PowerShell5.1 suite: modules/fat-analysis/tests/Run-TeamD-R6-GateGuardedResult.Tests.ps1. An independent nonwritable .NET memory Stream source observer records every actually returned byte offset, physical Read call, early zero and FAT-region call count. Original input SHA-256 before/after identical for each generated scenario. No scorer ground-truth mutation offsets, original file identity or payload is supplied to the D module.

| Case family | Artificial scenarios | Expected evidence |
| --- | --- | --- |
| Fixed default and fragmentation | clean SPC1/SPC2, healthy fragmented standard FAT32 | 128/65,664 paired 4B entry indices; 65,536 UNKNOWN; zero FAT copy winners |
| Faults within sampled or equal mirrors | FAT2-only changed index4; equal-copy cluster4 cycle with opt-in chain tracing | mismatch and cycles detected as numeric evidence; identical FATs do not prove health; chain-trace mode paired 64/65,664 |
| Out-of-window fault | FAT2 entry60000 planted | The remote entry is never read and remains UNKNOWN; 128/65,664 paired indices does not prove clean FAT |
| VBR conflicts | backup reserved sectors32→33; backup root cluster2→3 | No subsequent FAT source reads even though both BPBs can be individually plausible |
| Malformed/partial | invalid backup VBR signature, invalid primary SPC, true early zero after 1,100B with 7B chunks, physical call limit4 at 1B chunks | Stable two-copy UNKNOWN/null coverage, no subsequent FAT source reads |
| No-op and quota refusals | default OFF; writable source; invalid max-byte/max-call args; combined 2,048B budget consumed by VBR gate | Source is never read when disabled/writable; insufficient remaining FAT quota cannot be represented as a completed FAT sample |

**Preliminary code-head result** on the 12 generated core scenarios (6 bounded fixed-sample and 6 blocked) and ordinary disabled/writable/budget controls: **107/107 assertions PASS** on native Windows PS5.1 [run #43451061068](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43451061068), before adding the one further shared-2,048B-budget negative. Exact final HEAD must be separately tested again; earlier CI does not authorize merge.

The twelve separate generated sources produced **33,416 actual source-returned B, 27,216 source-local unique B summed across those scans, 6,200 repeated B and 243 physical Stream.Read calls**. The clean fixed-only baseline D13 returned 2,048B; the guarded D result on the same source returned 4,096B, therefore VBR safety preflight adds **2,048 actual physical bytes** and source-read overhead, not a free speedup. (These twelve-source totals exclude the separate baseline comparison and extra budget negative.) Default fixed sample paired fraction is approximately 0.19493%, leaving >99.8% unobserved. Opt-in chain mode paired fraction is approximately 0.09747%, leaving >99.9% unobserved. These are **numeric FAT-entry coverage measures**, not recovery probabilities.

No TP/FP/FN/TN for genuine original-file restoration is claimed. Only synthetically planted VBR conflict/no-FAT-read outcomes and numeric physical 4-byte pair coverage have defined independent scorer units. All artificial observations remain source-authenticity UNKNOWN.

## R4 residual gaps and A's acceptance decision

The new D6-05 production-facing D adapter is actually importable, default OFF, stable versioned, bounded and externally testable; it cannot silently run FAT sampling when the VBR gate refuses. But existing A live B/C/D integration may still call raw D13 until A independently switches its own adapter and binds A-issued source events. A-source token authenticity, proper candidate validation, true file ownership and source-original integrity cannot be decided by D. **A alone decides D6-05 PASS or PARTIAL and updates the shared ledger after reviewing the exact final HEAD native Windows5.1 and privacy CI.** D does not self-merge.

At preregistration the canonical R6 conditions were D6-01 PASS; D6-02/03/04 PARTIAL; D6-05 AUDIT_NEEDED. All R4–R7 rows: 4 PASS / 10 PARTIAL / 8 AUDIT_NEEDED of 22. Formal project stage progress remains **39%** (R0–R3 fully gated only). No R6 full-stage 10-point award and no claimed user-data recovery rate.

**Absolute safety:** the physical microSD and sole ~31GB master IMG are **NOT APPROVED** for ANY reading, hashing, copying, scanning, extraction, repair, writing or uploading. Every input here is generated artificial memory. R8 remains blocked.

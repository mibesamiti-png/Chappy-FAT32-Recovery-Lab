# Team D R9-P1 — longer root cycles versus far FAT anomalies, bounded evidence research

**Tracking:** Team D, [Issue #62](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/62), branch `research/d-r9-longer-cycle-quota-20261111`, frozen main SHA **`bc2fa20d4123400a2b8e9f77bc20ea5212a64dfc`**, research day 2026-11-11. No real medium or original user IMG permitted. Team A owns adoption.

## R0 original source research / licenses (recorded on Issue before implementation)

| ID | Primary original source, author | Relevant algorithmic observation, gaps | Exact code rights and decision |
| --- | --- | --- | --- |
| FAT32 v1.03 | Microsoft Corporation (Dec 2000), original FAT32 specification publicly mirrored at https://www.osdever.net/documents/fatgen103.pdf | Numeric 28-bit cluster pointers, cluster-chain termination, bad/reserved/EOC categories. Specification alone does not authenticate FAT mirrors or prove an optimal 40-entry sample | Specification/document rights, not free code license. No verbatim reuse; copying requires separate rights review |
| TestDisk 7.2 | Christophe Grenier / CGSecurity, official https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Boot/backup and FAT observational cross-checking; actual repair/write functions **out of scope** | GPL-2.0 upstream software. No imported/copied source or GNU license assumption; research concept only |
| The Sleuth Kit | Brian Carrier / Sleuth Kit Labs, https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Distinguish finite evidence from missing filesystem sections. Full-media scan unsuitable for strict sampling budget | Mixed file-specific IBM/CPL/GPL/MIT/BSD source; **license review required** for any import, none used |

The R9 window partition is an **independently authored bounded experiment**, not a faithful port of an existing licensed program. Public project has no declared single repo-wide license; no upstream text/code imported.

## R1 frozen baseline, same synthetic sources and costs

All modes are the main-SHA implementation, unchanged: `Get-ChappyFatVbrMirrorCrossEvidence` (R6, root window 8); `Get-ChappyFatStratifiedAnomalyEvidence` (R7, fixed prefix/root/midpoint); `Get-ChappyFatAdditiveAnomalyEvidence` (R8, two separately-budgeted subpasses). All are compared to only **one new experimental/default-OFF R9 sampler** and run on identical 64KiB artificial data streams. Exact per-run cap for each method: `MaxReadBytes=160`, `MaxEntries=40`; **actual reads differ and must be reported**, rather than claiming all modes have the same cost.

Corpus generator `tests/Run-TeamD-R9-LongCycleAB.Tests.ps1::New-D9Fixture`, deterministic experiment ID `D62-R9-20261111` (no RNG). 64KiB invented memory, FAT bases 4096/4608/8192/8704; two unverified geometry candidates, artificial roots 2 and 3, each FAT length 512 bytes (128 entries), dataClusterCount 32. The script independently hashes invented bytes before and after tests, never publishes source hashes/files or names.

**Predefined test conditions:** normal FAT, legal free midpoint and legal free far region, mirrored 2/3/4-link root cycles, a non-contiguous cycle with a link outside fixed observed windows (KNOWN challenging false negative), far bad/EB58/out-of-range, midpoint bad/EB58, root-free and prefix EB58, and an ordinary distant root link with EOC. Positive means *known deliberately injected suspicious FAT value/loop*, not actual user-file damage, restoration success or correctness.

## R2 one tiny experimental candidate (default OFF)

New `Fat32LongCycleRemoteEvidence.psm1` independently implements `Get-ChappyFatLongCycleRemoteEvidence`: accepts only already-open **strictly non-writable, seekable, readable** `[IO.Stream]` and exactly two unverified candidate numeric geometries. No device/file paths, writes, repair, copying, extracted data or selectable/verified original FAT.

**Allocation per hypothetical FAT1/FAT2 × primary/backup (four views):**

- FAT reserved prefix: two entries (0 and 1).
- Root chain region: up to four *contiguous* entries from declared root cluster. A fixed five-step state walker can detect a 4-link cycle **only if all four required links fall inside the sampled window**.
- Midpoint: two entries at `1+floor(clusterCount/2)`.
- Far: two entries at `1+floor(3*clusterCount/4)`.

At most **10 physical entry reads per copy × four views = 40 charged entries / 160 actual bytes** for normal candidate geometry; global upper accepted cap 256B and 40 entries, with fair per-copy quota and read/loop bounds. All reads are 4-byte chunks with accurate actual count even for short-returning streams. Geometry origin/size/contiguity/capacity/overflow validation is always performed first; no guessed shifted FAT scans.

**Coverage measures:** `observedUniqueEntries` per copy and `unknownDeclaredEntries`, `uniquePhysicalEntries` across ALL candidate/copy views using a bounded Set of numeric physical 4-byte offsets; `duplicatePhysicalEntryReads = entriesRead - uniquePhysicalEntries`. If two VBR candidates point at the same FAT address, the second read is **charged** but never increases unique physical coverage. Within one copy, overlapping root/mid/far windows are deduplicated and charged once. For missing root links or short/truncated reads return `scanIncomplete=true` and `insufficient_evidence`; never infer healthy, authentic, original-file-verified or choose a FAT/VBR.

Classification: `suspicious_samples_no_selection`, `ambiguous_samples_no_selection`, `insufficient_evidence`. Warnings include candidate geometry unverified, mirror agreement not proof, missing unsampled entry coverage and source trial NOT APPROVED. Result `experimentalDefaultOff=true`, `sourceDecision=not_selected`, `selectedCandidate=null`, `writePermitted=false`.

## R3 native Windows PowerShell 5.1 measured A/B (synthetic-only)

**Executed code HEAD:** `633ddb75dc2568cb18e7af801ec0ce5ec81cc42a`. [Team D Windows 5.1 CI #43046492107 — SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43046492107), including **R9 185/185** and older R1–R8 **537/537**, total **722/722** artificial assertions. [Privacy/integrated synthetic #43046491711 — SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43046491711). The exact-final-head CI must be verified again after this documentation update; no result is attributed to a newer untested commit.

**Exactly same 15 invented synthetic FAT cases per mode**: 11 deliberately injected positive suspicious states and 4 negative controls, no real user data; **same hard ceiling 160 bytes / 40 FAT entries per case**, but actual read counts vary.

| Observed metric | Existing R6 | Existing R7 | Existing R8 | R9 new experimental |
| --- | ---: | ---: | ---: | ---: |
| TP (11 injected suspicious conditions) | 5 | 4 | 5 | **10** |
| FP (4 artificial negatives) | 0 | 0 | 0 | **0** |
| FN | 6 | 7 | 6 | **1** |
| TN | 4 | 4 | 4 | **4** |
| Precision on chosen fixtures | 100% | 100% | 100% | **100%** |
| Recall on chosen fixtures | 45.5% | 36.4% | 45.5% | **90.9%** |
| Actual source bytes across all 15 | 2,400 B | 1,440 B | 2,400 B | **2,400 B** |
| Charged FAT entry reads across all 15 | 600 | 360 | 600 | **600** |
| Unique actually observed physical 4-byte FAT offsets | 600 | 360 | 360 | **600** |
| Duplicate reads of same physical FAT entry | 0 | 0 | **240** | **0** |
| Incomplete/uncertain-case flags | 1 | 0 | 4 | **2** |
| Stream Read() requests | 600 | 360 | 600 | **600** |
| One Windows CI stopwatch run | 329ms | 371ms | 532ms | 313ms |
| False file authenticity / chosen FAT / source write claims | 0 | 0 | 0 | **0** |
| Artificial byte-source SHA unchanged | yes, 15/15 | yes, 15/15 | yes, 15/15 | **yes, 15/15** |
| Verified real file-byte reconstructions | not applicable | not applicable | not applicable | **not applicable** |
| Reliable memory peak | not measured | not measured | not measured | **not measured** |

**Observed tradeoff:** R9 detected intentionally constructed 3/4-link *contiguous* root cycles shared by both FAT mirrors and additional bad/EB58/out-of-range markers in the 3/4 distant region. R6 follows more near-root entries but does not sample that far region; R7 uses fewer bytes but cannot trace cycles; R8 rereads overlapping prefix/root positions, consuming 40 charged entries for only 24 unique physical entries in each full normal 4-view fixture. R9 reads 10 unique physical entries per view in the selected non-overlapping geometry, but **only 10 of 128 FAT entries/copy**, so 118 entries/copy remain unknown. R9 additionally reports distinct observed 4-byte source offsets across both candidate geometries, preventing overlapping hypotheses from falsely doubling coverage.

**Known genuine limitations from synthetic negatives:** the non-contiguous cycle root `2 → 9 → 10 → 2` lies beyond all selected continuous windows, so R9 recorded a false negative rather than claiming success or a healthy original. The intentionally non-contiguous *valid* root chain also leaves R9's root evidence unknown/incomplete without claiming corrupted data. A/B negative tests for legal free midpoint/far regions did not trigger positives. An adversarial duplicate-VBR geometry points both candidates to exactly the same FAT1/FAT2 offsets; R9 charged **40 reads/160B** but independently observed only **20 distinct physical 4-byte positions**, and reported the remaining 20 charged rereads. Overlapping windows within a copy charged **28 reads/112B** for the four views, with **7 actually distinct indices per copy** rather than 40 fictitious samples.

Safety negative controls passed: gross overflow/misaligned FAT geometry and contradicted candidate, extreme 16B/4-entry and 32B/8-entry budgets, max 256B/40-entry request, 1-byte fragmented streams, premature EOF, writable-source rejection, redacted JSON canary and unchanged synthetic source SHA. **No actual file content is recovered or authenticated**.

Performance caveat: these elapsed times come from a single noisy GitHub Windows job, not a statistically meaningful speed benchmark. R9 detects 10/11 chosen anomalies but this is **not** a general recovery probability, and longer/fragmented cycles may defeat the fixed four-entry root window. Full FAT and real storage health remain unknown.

## R4 A adoption decision

**No silent adoption.** Team D recommends only an experimental **research_only** comparison pending full final-HEAD Windows PS5.1/Privacy CI and Team A review. A may adopt experimental, preserve as research-only, request revision or reject. Even if the synthetic benchmark improves, four contiguous root entries cannot guarantee finding arbitrary long/fragmented cycles and far slots are only sampled; no genuine file integrity or recovered data can be inferred. Maintain existing R6 default. Original microSD and sole ~31GB master IMG are NOT APPROVED for inspection in this task.

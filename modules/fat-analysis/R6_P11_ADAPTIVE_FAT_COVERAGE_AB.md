# Team D R6-P11 — Non-oracle observed-link adaptive FAT sampling A/B (research only)

**Scope:** Issue [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73); D branch `research/d-r6-adaptive-fat-coverage-20261112`; Draft [PR #132](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/132). Frozen R0/R1 [Issue research card](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6826717174), posted before implementation. A reviewed source base `8f145c9f4135a4cee44a5752f9ca786cfcf38a99`; new main docs-only commit `18e68046cf9b594ef406da9e45fe8e9625db2cb3` existed at start. This is **not** product recovery code, nor approval for any real-media test.

## R0 — external research, code rights

1. Microsoft Corporation, *FAT32 File System Specification v1.03* (2000), https://www.osdever.net/documents/fatgen103.pdf : BPB/FAT offset arithmetic, 28-bit FAT chain links and mirror layout. Copyrighted reference; not a code license; no verbatim material imported.
2. CGSecurity / Christophe Grenier, official TestDisk filesystem repair https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and GPL-2.0 upstream https://github.com/cgsecurity/testdisk : alternative FAT source hypotheses must not become an automatic winner. No upstream code copied or invoked; license_review_required before reuse.
3. Sleuth Kit, https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php : forensic evidence/coverage versus file-owner authentication; component licenses mixed; no source copied.

All new algorithms are independently authored test-only PowerShell 5.1 and embedded .NET code calling pre-existing D module interfaces. No legal conclusion about third-party implementation rights is implied.

## R1 — frozen comparable variants and synthetic corpus

**Fixed baseline:** the already reviewed P7/P9 *test-only* three mirrored 16-entry windows at FAT indices 0/128/256 plus existing `Get-ChappyFatGeometryTrust`, `Get-ChappyFatMirrorWindows`, and `Get-ChappyFatChainAnomalyStats` with generic start clusters 2..8.

**One candidate:** compare the same 16-entry prefix returned from both copies at FAT indices 0..15; seek the first **identical observed 28-bit next-cluster value** from entries 9..15 (ascending) in range 16..validated numeric max where an entire 16-entry window fits. On that observed, not scorer-given, value, sample 0/target/128; otherwise use fixed 0/128/256. The target may be stale, cyclic, ownerless or jointly corrupted; it is **not** evidence of authentic FAT owner/file identity. The prior seed/geometry rotating window approach from #122 was not reused or tuned.

Independent runs on the **same generated source bytes** and same caps: D maximum **2048 actually returned physical bytes**, 256 physical Read calls, outer 120000B upper bound (this isolated D source meter is NOT an A-issued shared-source receipt). Numeric BPB geometry 1024B; three 16-entry windows up to 384B; chain budget up to 448B. Complete FAT entry coverage based on **all four actual returned byte positions** per copy, intersection for paired entries. Source read requests, declared spans and in-module D metrics are insufficient without physical return evidence. CPU elapsed recorded per case as a single illustrative measurement but no controlled throughput/peak memory benchmark.

Fixture: A-reviewed `tests/helpers/New-ChappyA3DStandardFixture.ps1` creates artificial FAT32 32.5/64.5MiB, sector-per-cluster =1/2; development seed 202611 and **held-out 202612/202613**. Each has 7 scorer-labelled structural anomaly/clean cases; 3 malformed/early EOF UNKNOWN controls. Artificial scorer plants an otherwise matching FAT1/FAT2 link at cluster14 to a distant valid cluster determined by scorer `2048 + ((seed*97)%40000)`. Candidate receives no seed, position, truth or hash; it learns a potential target only from the physical sampled link. Scorer alone marks link-target FAT2 corruption, the displaced fixed index256 corruption, common-mode cycles, and independent unlinked FAT2 index60000 corruption. One separately added out-of-range observed link (index14 -> 70000, invalid under numeric geometry) is **unscored**, not added to the frozen 21 scored labels. Original file byte identity remains UNKNOWN for every case.

## R2 — D-only implementation

- New `modules/fat-analysis/tests/Run-TeamD-R6-AdaptiveFatCoverage.Tests.ps1` with independent strictly nonwritable `D25ReadMeter`, hard source bytes/Read-call limits, observed-source bytes and returned offsets held only in memory, exact complete FAT1/FAT2/paired 4-byte memberships, read duplicate accounting, and scorer-isolated source SHA checks.
- One extra Team D native PowerShell 5.1 CI step. No core/module production logic, A/B/C, shared schema, A candidate receipt, repair or output changes.
- Tests cover clean fragment link, remote link corruption, displaced window miss, single-copy FAT2 cycle, identical-two-copy cycle, unlinked remote marker, malformed sectors-per-cluster, forged FAT length, 7B short physical reads and early zero, writable source rejection, over-cap refusal and out-of-range next link rejection.

## R3 — observed Windows PowerShell 5.1 preliminary A/B (code head before final report)

Code HEAD `87a1172c509b17695288188b1a01c7e0c2e319e0`: native Windows [push CI #43241178122](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43241178122) **SUCCESS**, dedicated P11 **253/253 PASS** plus all earlier D suites success. [PR CI #43241289780](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43241289780) also **SUCCESS**. A subsequent code revision `924f98c8` added exactly three asserts for a standalone out-of-range observed-link negative; its exact-head CI and final documentation-head CI must be independently checked, not inferred from earlier green runs.

| Measured property | Fixed | Observed-link adaptive |
| --- | ---: | ---: |
| Scored artificial structural anomaly TP | **9** | **9** |
| FP | 0 | 0 |
| FN | **6** | **6** |
| TN | 6 | 6 |
| Invalid/partial-source cases excluded as UNKNOWN | **9** | **9** |
| Actual physically returned bytes across 30 independent source runs per variant | 40,276 | 40,276 |
| Sum of source-local unique offsets (NOT cross-source union) | 39,012 | 39,012 |
| Repeated returned bytes | 1,264 | 1,264 |
| Physical Stream.Read calls, including short/EOF | 1,033 | 1,033 |
| Complete physically sampled FAT1/FAT2 paired entries on each normal valid source | **48 / 65,664** | **48 / 65,664** |
| Paired coverage percentage | **0.07309942%** | **0.07309942%** |
| Original file byte identity proven | 0 | 0 |
| Authentic FAT copy selected / repair | 0 | 0 |

**Positive and negative paired tradeoff:** the candidate sees **3 remote FAT2 faults reachable from observed index14 links**, whereas fixed misses those; however candidate loses fixed window256 and misses **3 planted index256 faults** that fixed finds. Both miss **3 unlinked entry60000 faults** and detect **6 planted cluster4 single/common-mode cycles**. Hence 9/15 for both on the *selected* invented anomaly labels. That is neither evidence of global gain nor real-file recovery. Same physical cost and equal 48-entry extent, not an improvement in total coverage. Approximately **99.9269%** of FAT paired indices remain unseen even for normal numerically plausible artificial input. Unobserved entries are UNKNOWN, never declared healthy.

Early physical zero after 1100 actual returned bytes (7B chunks) and numeric-invalid BPB with SPC0 or exaggerated FAT length abstain completely: no denominator or inferred 0%-healthy verdict. Multiple returned reads at the same source offsets never increase unique coverage. User original IMG and microSD not accessed in any study.

## R4 — proposed A adoption gate

**Recommendation: `research_only` / tests+document only; do not promote adaptive sampling or rejected rotating schedules.** The advantage on one evidence class is offset by a similarly sized regression under unchanged byte/call budget, including two held-out seeds. No actual file owner, original SHA or FAT copy winner is known; no automatic repair/extract/export or modification permitted.

A should review the physical 4-byte coverage accounting, real-vs-requested source read distinction, the unscored controls, and the explicit FN exchange. Any future benefit must justify extra non-oracle evidence/budget rather than tune to planted target positions. A owns future shared source-token / candidate-specific receipt integration. A alone may merge after **exact final PR HEAD** Windows PowerShell 5.1 and privacy CI succeed. Official completed engineering gates still R0–R3 = **39%**, D internal earlier estimate about **85%**, neither a real-world recovery percentage. Real microSD and sole ~31GB master IMG trial remains **NOT APPROVED**.

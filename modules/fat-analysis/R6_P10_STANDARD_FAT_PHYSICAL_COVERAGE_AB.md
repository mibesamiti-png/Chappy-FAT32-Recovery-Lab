# Team D R6-P10 — standards-shaped FAT actual observed-entry coverage, conservative UNKNOWN

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #126](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/126). Assigned D-owned branch `research/d-r6-fat32-size-coverage-20261112` created by A at reviewed main `99562004d9aeee74d059c9ace85c10a89f79449d`, main `f66d21de6feaa0bfa907e8ab865fcee82b85d30b` when work began. Prior D #122 was merged as research_only; rotating schedule intentionally **not** promoted.

## R0 / R1 — registration before code

[Issue #73 preregistration #6825473194](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6825473194) was posted before writing P10 code, freezing exact corpus, control caps, numerator/denominator and safety.

- Microsoft Corporation, FAT32 File System Specification v1.03 (2000): https://www.osdever.net/documents/fatgen103.pdf — numeric BPB, FAT capacity and FAT copy geometry. Copyrighted reference publication, **no imported text/code**, not a permissive source license.
- Christophe Grenier / CGSecurity, official TestDisk docs https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and GPL-2.0 source https://github.com/cgsecurity/testdisk — alternative hypotheses do not permit a copy winner or repair. No upstream code copied; license review before reuse.
- Brian Carrier / Sleuth Kit Labs https://github.com/sleuthkit/sleuthkit with component notices https://www.sleuthkit.org/sleuthkit/licenses.php — physically observed evidence versus inferred file ownership. Mixed component licenses, no upstream code copied, file-level rights review required before reuse.

**Fixed comparison baseline:** unchanged D experimental/default OFF `Get-ChappyFatObservedIoEvidence -Mode MirrorAndChain -MaxReadBytes 2048` (up to 1,024 geometry, 512 mirror, 448 chain) on the same source. It emits phase spans, actual bytes and sampled mirror disagreements; it does not independently certify the percentage of all per-copy FAT entries physically observed.

**ONE tests-only improvement:** source observer records *actual returned* byte locations and in-memory values, and conservative report reconstructs candidate BPB geometry from only its returned MBR/VBR byte values; **no extra source read or leaked source content**. Accept numeric denominator only if signatures, MBR partition bounds, BPB sector/cluster/FAT fields, FAT32 >=65,525 data clusters, two non-overlapping in-bounds FAT regions, capacity entries >= dataClusterCount+2 are consistent. This is a **plausible numeric geometry candidate, NOT authenticated geometry**. Count one FAT1 or FAT2 4-byte entry only when every single physical byte of that entry was observed in the external meter; mirrored-pair numerator uses intersection of independently complete entry indices, not requested lengths, labels or the D module's own range claims. A malformed BPB or premature source zero makes denominator and confidence **UNKNOWN**, not 0%-healthy/0%-corrupt.

**Frozen artificial corpus:** A-reviewed `tests/helpers/New-ChappyA3DStandardFixture.ps1` in memory only; clean seed202611 at 512- and 1,024-byte clusters; clean seed202612 at 512B; seed202613 FAT2-only cluster4→4, seed202613 both FAT copies cluster4→4 (common-mode), seed202612 FAT2 reserved marker at distant entry60000 (not observed); synthetic zero sectors-per-cluster, synthetic oversized FAT sectors `UINT32_MAX`, synthetic 7-byte Read returns with 0-byte premature zero after 1100 returned bytes. Seed and planted offsets belong **only to the external scorer/test corpus** and are never passed as hints into D observed-I/O or conservative-coverage function. Nine separate conditions, original file identity unknown in all.

## R2 — scoped implementation and limitations

New D-only `modules/fat-analysis/tests/Run-TeamD-R6-StandardFatCoverage.Tests.ps1` with a synthetic byte-array backed nonwritable `D24ExternalSource`. Actual physical returned offset+byte values held in process memory only; reports/CI output aggregate lengths/offset **counts** and reason codes, **no raw source bytes/hashes/file names**. Outer meter rejects any request above 120,000B with no read/event; D's unchanged internal byte cap remains 2,048B per invocation. Deliberately separate from A's authoritative B/C/D shared source meter: D study is one component under equivalent ceilings, **not an A source-ID or cross-team receipt implementation**. Adds one native Windows PowerShell 5.1 Team D CI step. Does not change any default D algorithm, B/C module, A integration code or shared interface.

All valid-numeric result objects retain `geometryAuthentic=false`, `wholeFatVerified=false`, `copyWinner=not_selected`, `fileOwner=unknown`, `originalIdentity=unknown`, `writePermitted=false`. Invalid / early-stop result objects have `state=unknown`, with `fatEntries=null`, `pairCoveragePercent=null` to avoid misleading zero/healthy interpretations.

## R3 — measured same-input controlled artificial source results

Native Windows PowerShell 5.1 code HEAD `fa639bb9f9b0b8930348920d82676dbcde0446b9`: [CI run #43232441811 — SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43232441811), new P10 suite **77/77 assertions PASS, 0 FAIL** and existing Team D suites passed. Earlier run at `e6e53b7a7fa931811dfb255acbc816087fbea50e` failed at purely artificial out-of-range PowerShell uint32 literal `0xFFFFFFFF`; test used `[uint32]::MaxValue` instead, without changing planted value, truth labels or algorithms. Exact research-documentation HEAD CI to be checked separately below.

| Synthetic case | Numeric BPB candidate | Complete FAT1 entries | FAT2 entries | Mirrored pairs | Default D observed anomaly | Original file integrity |
| --- | --- | ---: | ---: | ---: | --- | --- |
| 202611 clean, 512B cluster | partial | 64 | 64 | 64 | none sampled | UNKNOWN |
| 202611 clean, 1,024B cluster | partial | 64 | 64 | 64 | none sampled | UNKNOWN |
| 202612 clean, 512B cluster | partial | 64 | 64 | 64 | none sampled | UNKNOWN |
| 202613 FAT2-only link4 mutation | partial | 64 | 64 | 64 | 1 mirror difference; 1 cycle observed | UNKNOWN |
| 202613 both copies identical link4 cycle | partial | 64 | 64 | 64 | 0 mirror differences; 2 cycles observed | UNKNOWN |
| 202612 FAT2 entry60000 mutation | partial | 64 | 64 | 64 | no local anomaly observed; remote position unread | UNKNOWN |
| 202611 zero sectors/cluster | **UNKNOWN** | — | — | — | BPB invalid | UNKNOWN |
| 202611 oversized FAT sectors | **UNKNOWN** | — | — | — | invalid numeric geometry | UNKNOWN |
| 202611 7-byte chunks + early zero after 1,100B | **UNKNOWN** | — | — | — | 16 premature source-zero attempts observed; not full extent | UNKNOWN |

For each of the six numerically consistent FAT32 candidates, denominator = **65,664 four-byte FAT entries *per FAT copy*** (FAT byte length 262,656) from actually returned numeric MBR/BPB; pair mirror coverage is **64 / 65,664 = 0.09746589%**, **uncompared 99.90253411%**. These are volume-wide *coverage proportions of observed positions*, not corruption prevalence or actual recoverability. The 64 paired indices include entries observed through prefix mirror/chain under fixed D 2,048B cap. A `mirrorDifferentEntries=0` result means no disagreement among the sampled prefix entries only. For the common-mode cycle, two mirrors appear equal but the bounded chain evidence still shows cycles. For FAT2 index60000, lack of observed differences gives no negative evidence about unobserved FAT positions.

**Scorer-only anomaly evaluation, six numerically consistent cases:** Clean negatives 3/3, invented structural corruption positives 3 (FAT2-only, common-mode, remote60000), D sample detects first two and misses remote — TP=2, FP=0, FN=1, TN=3. Three invalid/early-stop controls are **UNKNOWN**, excluded. These are artificial planted anomaly observations, NOT true original-file integrity labels. No FAT winner or repair inference.

| Actual returned source I/O, summed across 9 independent image invocations | Value |
| --- | ---: |
| Physically returned bytes | **12,720** |
| Sum of source-local unique bytes | **12,364** |
| Repeated returned bytes | **356** |
| Physical source `Read()` calls | **292** |
| Max actual return bytes per D invocation | **2,048** (hard) |
| Outer physical per-source ceiling | **120,000** |
| Original-content matches claimed by this D study | **0** |

Source input SHA unchanged in all 9 cases, scorer-only artificial payload never supplied to diagnostic. The unique count is **sum of nine separately scoped byte-location sets**, not a union over nine volumes. The 7-byte-chunk/early-zero case actually returned 1100B and recorded 16 zeros before declared source length; invalid BPB cases returned 1024B but legitimately withheld coverage denominator. Standard healthy cases each had 64 duplicate bytes from FAT chain rereads, which are not double-counted as new entry coverage.

## R4 — adoption, remaining risks and Team A request

**Recommend `research_only`, tests/docs only**: Numeric BPB plausibility is not authentication, even if volume geometry matches the seeded generator. Any unobserved FAT entry, common-mode corruption, directory owner and original file bytes remain unknown. Independent source read positions give a measurable upper bound on *what was actually observed*, not an inferred health score. No production or R7 receipt schema integration in this branch.

Team A should review physical-event-only numerator, numeric denominator rejection, high unknown fraction, early EOF and test-only source scope; decide whether a future bounded D P1 should integrate actual external observed coverage into A-owned candidate receipts *after standards-shaped synthetic integration*. R6 remains OPEN for crosslink owner, wider FAT coverage and stronger metadata trust. R8 extraction remains blocked. Full roadmap R0–R3 weighted **39%** accepted; R6 internal estimate approximately **85%** (synthetic sampling, geometry/EOF/physical evidence studied but complete FAT and real file identity unsolved) — never a real-data recovery percentage.

**Absolute safety:** Generated synthetic nonwritable in-memory streams ONLY. No physical microSD or sole ~31GB master IMG accessed, read, hashed, copied, scanned, written, repaired, uploaded, exported, or extracted. Real-media approval **NOT APPROVED**.
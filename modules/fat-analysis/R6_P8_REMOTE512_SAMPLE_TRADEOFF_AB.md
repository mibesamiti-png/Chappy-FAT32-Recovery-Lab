# Team D R6-P8 — remote FAT entry512 versus displaced entry128 (research_only)

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #117](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/117). Formal D-owned branch `research/d-r6-remote512-sample-tradeoff-20261112` pinned by A at reviewed `main 4a378fc32cfd6603e20b5acbbfa0328a6a718770`; main at task start `59525c560399b61f6668d321b1fb26c30ca24a84`. Prior D #113 was reviewed/merged `research_only`, its test and experimental production modules are untouched.

## R0 — prior work, original URLs and license/reuse exclusions

[Issue #73 research card 6821673723](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6821673723) was posted **before any P8 code**.

| Primary original source | Relevance and limitations | Rights and integration |
| --- | --- | --- |
| Microsoft Corporation, *FAT32 File System Specification v1.03* (2000), archive https://www.osdever.net/documents/fatgen103.pdf | FAT copies contain index-addressable 28-bit links; sampling matching entries cannot prove healthy unobserved entries, nor source-copy truth | Copyrighted specification, **no copied code/text**, reuse requires rights review |
| Christophe Grenier / CGSecurity, TestDisk filesystem repair guidance https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html ; source https://github.com/cgsecurity/testdisk | Different copies and boot records can be competing evidence; automatic repair or preferring one copy is not authorized here | Source **GPL-2.0**, no imported/copied code, `license_review_required` for reuse |
| Brian Carrier / Sleuth Kit Labs, official https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | A physical observation is scoped to actually read source byte intervals, not inferred FAT health, owner or recovered original-file bytes | Mixed component-level licenses, no source imported, `license_review_required` |

Only existing in-repository D numeric geometry, mirror and chain functions plus native Windows PowerShell 5.1/.NET test code were used. No implementation extracted from outside projects.

## R1 — exact frozen baseline, scorer oracle and equal physical quotas

- **Existing tests-only research baseline:** prior merged D P7 sampled FAT mirror windows at entries **0, 128, 256**, each exactly 16 entries/FAT copy, followed by **fixed generic chain starts 2–8**. Baseline was taken from `modules/fat-analysis/tests/Run-TeamD-R6-SamplingBlindspots.Tests.ps1`, without modifying that file or product settings.
- **One optional tests-only alternative:** exact same existing D functions in identical order and budgets, but windows **0, 256, 512**. This displaces 128, it does not add a fourth window or expand scan effort. Both schedules are hardcoded in the test before any fixture-specific scoring, NEVER selected by true mutation position or an oracle.
- **Budgets:** both use geometry maximum **1,024 actual B**; three 16-entry mirrored windows at up to **128 B each**; fixed chain-trace maximum **448 B**. Nominal returned bytes maximum 1,856 B per method in normal cases. One independent strictly non-writable, seekable physical input Stream enforces **the same hard cap 2,048 physically returned B and 256 physical `Read()` calls** over all phases for either method. No reset; each method gets its own clean read-only artificial memory buffer. Equal hard caps ≠ identical CPU time.
- **Scorer-only ground truth:** existing A helper `tests/helpers/New-Chappy3DDamagedFixture.ps1` blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5`, deterministic seed **202611** generating 2MiB FAT32-*like* M00 clean, M01 normal fragmented, M02 FAT1-copy mismatch, M03 same-corrupt-mirror cycle, M05 cross-file link without independent directory owner, X02 physically shortened payload. External test scorer clones M00 and independently plants FAT2 marker 1 at FAT entry **128, 256, 512 or 768**, FAT2 link cluster4→8 when FAT1 4→5→EOC (both possible terminals EOC), and invalid BPB sectors-per-cluster=0. The scorer knows mutated offsets, labels and artificial SHA only; **these values and no true file owner or image identity are passed into either diagnostic method**.
- **Eight scored artificial sampled-anomaly cases:** M00/M01 negative, M02/M03/CONFLICT/REMOTE128/REMOTE256/REMOTE512 positive. Exactly **six positives and two negatives**. Remaining **six UNKNOWN/excluded**: REMOTE768 outside both schedules, M05 ownership ambiguous, X02 shortened source, genuine 1,200 B premature EOF with 7 B chunks, 32 B source cap, invalid BPB. UNKNOWN is not automatically TN or recovered. No real original file reconstruction.
- **Pre-registered hypothesis:** 0/256/512 gains the planted entry512 anomaly **at the cost of losing** entry128. Both still miss planted entry768. The test must reveal a genuine tradeoff, not assert overall gains.

## R2 — one bounded D-only experimental test

New `modules/fat-analysis/tests/Run-TeamD-R6-Remote512Tradeoff.Tests.ps1` reuses the independent source-meter logic of P7, with strict `CanWrite=false`, maximum actual-returned-byte and read-call enforcement, source-local unique byte union and range-observation queries. It independently calls unchanged D geometry, mirror window and bounded chain modules for each fixed schedule. No original image filenames, source SHA or actual recovery bytes enter D functions.

New D-only Windows PowerShell 5.1 CI step in `.github/workflows/team-d-powershell51.yml`. All prior D tests/production/default-ON/OFF behavior, A source meter, B/C modules and common interface remain unmodified. This research helper never opens a device, path or writable file and cannot select a FAT source or repair anything.

**Abstention/safety:** any sparse sample keeps `scanIncomplete=true`, `fullFatVerified=false`, `sourceDecision=not_selected`, `selectedCandidate=null`, `originalIdentity=unknown`, `writePermitted=false`. M03 common-mode dual-copy cycle can still be observed, but does not prove the identity of a damaged file. Even one locally observed mismatch after the injected early EOF is an incomplete observation, never a validated complete original.

## R3 — measured native Windows PS5.1 same-input A/B

**Code+CI commit:** `38cd30f40e42ccdab9c9f8a1414493e8f51dd247`.
[Native Team D Windows PowerShell 5.1 CI #43205038835 — SUCCESS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43205038835): new R6-P8 **102/102 assertions PASS, 0 FAIL**, plus older Team D suites. [Privacy/isolated synthetic CI #43205038716](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43205038716): initial code-head check; final result to be verified independently before acceptance.

| Eight selected artificial FAT anomaly labels | Existing 0/128/256 | Candidate 0/256/512 |
| --- | ---: | ---: |
| TP | **5** | **5** |
| FP | **0** | **0** |
| FN | **1** (misses entry512) | **1** (misses entry128) |
| TN | **2** | **2** |
| Recall on selected positives | 5/6 (83.3%) | 5/6 (83.3%) |
| Unscored *UNKNOWN* conditions | **6** | **6** |
| False original-file health/FAT-winner/file-owner/repair claims | **0** | **0** |

| Physical source meter across all 14 synthetic case invocations **per method** | Old schedule | New schedule |
| --- | ---: | ---: |
| Actual physical returned bytes | **18,452 B** | **18,452 B** |
| Distinct physical returned byte positions (summed per invocation) | **17,744 B** | **17,744 B** |
| Repeated returned bytes | **708 B** | **708 B** |
| Source `Read()` calls | **462** | **462** |
| Maximum cap on **each** run | 2,048 B, 256 calls | 2,048 B, 256 calls |
| CPU speed or peak memory advantage | Not established | Not established |
| Byte-identical original-file recovery | Not assessed | Not assessed |

**Synthetic case observations:** M00 clean and M01 legal fragmentation not marked anomalous; M02 first-window mismatch, M03 equal-copy cycle, CONFLICT contradictory FAT links both observed. REMOTE256 detected by both. **REMOTE128 only detected and physically read by OLD**; **REMOTE512 only detected and physically read by NEW**. REMOTE768 physically read by neither, so remains UNKNOWN and is not credited as a healthy FAT. X02 geometry exceeds source and M05 crosslink owner remains unknown. 1,200-byte injected unexpected early source end with 7-byte chunks and 32-byte budget remain incomplete; invalid synthetic BPB is not promoted to healthy geometry. All synthetic input SHA checks before/after succeeded. **No real file was reconstructed**.

The equal TP and equal resource cost do **not** imply sampling schedules are interchangeable: they detect different distant corruptions and any fixed schedule can miss off-window damage. CPU/latency and varied/several corruption seeds were not separately benchmarked. The testing locations are deliberately selected synthetic cases, so these scores cannot be generalized to real FAT damage frequency.

## R4 — handoff to Team A and next research

**Recommendation: `research_only`, no product/default change.** This P8 shows a strict coverage tradeoff without net sensitivity or I/O cost gain on the selected artificial corpus. Team A may decide whether a later P1 should test independently randomized or multi-seed schedules under the same global source budget, weighting distant misses versus loss of known early-window detection. R7 candidate provenance and cross-file ownership need independent B/owner evidence and A-issued source identities; never infer them from FAT agreement. The Issue remains OPEN; only Team A reviews/merges.

**Safety:** only invented in-memory data on strictly nonwritable Streams. No real physical microSD or unique ~31GB master IMG read, hashed, scanned, copied, exported, uploaded, written, repaired or accessed. Real-media trial authorization **NOT APPROVED**.

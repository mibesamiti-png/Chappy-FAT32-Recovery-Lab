# Team C R5 — Ambiguous ZIP/3MF false joins, ordered identities and no original winner

**Tracking:** Team C Issue [#72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72), assigned branch `feature/c-r5-ambiguous-fragment-falsejoin-20261112`, reviewed base `e420369bb6de79e33de009cbce570315880a589f`. At R0 latest main was `d887522ecd072b7d2b5f2e15d3d698e1d0a0a74b` (one A-only update ahead). A P1 dispatch comment #6814297450; research card **posted before code** as Issue comment #6814528133. Earlier Team C PR #100 and A meter integration PR #102 merged, but A receipts are not emitted by this independent C experiment.

## R0 — primary sources, failure modes, license analysis

| Primary source | Principle and why it matters | Reuse / licensing |
| --- | --- | --- |
| [PKWARE APPNOTE](https://support.pkware.com/pkzip/appnote), original [APPNOTE.TXT](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) | ZIP central directory, EOCD, and CRC are *internal package checks*. Plausible mutated metadata can preserve structure and still be byte-different from a separately known original; forged EOCD can generate false hypotheses | Official specification cited conceptually; **no external source code, parser, format text or payload copied**. External code import requires independent license review |
| [3MF Consortium specification](https://3mf.io/spec/) and [Core spec repo](https://github.com/3MFConsortium/spec_core) | A 3MF is ZIP/OPC/XML with model relationships. A bounded ZIP/CRC match is not full 3MF conformance, provenance, or original SHA | Official Core spec repository licensed BSD-2-Clause; **no spec source or external library imported**. Notices needed only if any source is reused in future |
| Simson L. Garfinkel (2007), [*Carving contiguous and fragmented files with fast object validation*](https://www.sciencedirect.com/science/article/pii/S1742287607000369), DOI 10.1016/j.diin.2007.06.017 | File carving can create many structurally plausible fragmented objects. Rapid validation reduces hypotheses but does not independently identify which historical original was present | Research concept and bibliographic citation only, no third-party code, figures or paper text copied; third-party implementation source license **review_required** |

Chosen P1: one independent, **test-only** ordered-identity uncertainty guard. No new search method is justified by the selected artificial results; reconstructors must not promote an ambiguous format candidate to an original. Other options (full 3MF XML/OPC validation; unlimited gap/order permutations) would substantially expand scope, licensing and resource exposure and were not attempted.

## R1 — frozen baseline and fair artificial A/B

- **Current-main control:** unchanged `Test-CVariableZipPairs`, already C research/test-only; scans 2MiB synthetic FAT32-*like* source (not a standards-certified FAT32 volume), generator `New-ChappyA3DCleanFixture` seed **202611**, then test-only `New-CVariableSyntheticCase`. No real microSD, master IMG, external filenames or recovered bytes.
- **Available but explicitly privileged hypotheses:** known container type ZIP/3MF, exactly two pieces, first length drawn from `{512,544}` bytes, first and EOCD candidate starts at 512-byte grid plus phase `{0,+1}`, bounded 65,536-byte scan. No true offsets, original SHA, true fragment length, filenames, FAT pointers or A receipt IDs passed to the scanner or guard. Original SHA and planted extents are visible solely to external scorer.
- **Identical corpus on both paths:** `M01_control`, `non512_offgrid_tail`, `alternate_zip_metadata`, `fake_eocd`, `missing_tail`, `offgrid_plus_two`, `nonlisted_first_560`. The alternate case plants a CRC-consistent but byte-different central-directory metadata tail beside the true tail; the last two place an existing correct original outside scanner's allowed phase/first-length hypotheses. The missing-tail case has **no present original** and must not contribute a false FN.
- **Exact same source, validation and scan budgets per A/B path:** <=128 scanned 512B sectors, 4 start hypotheses, 8 tail hypotheses, 16 pair hypotheses, <=81,920B physical source reads per case, <=98,304B separately counted ZIP/CRC in-memory validator reads, 30s cooperative loop. Both paths call the exact same scanner independently on an equal-byte, non-writable `MemoryStream`, then compare measured source bytes, memory bytes, pairs and original source SHA invariance. No oracle enters the detector.
- **Additional guard budget:** <=16 candidate records, <=1s cooperative to classify, **0 extra physical source reads**, **0 extra in-memory ZIP validator reads**. It compares *ordered physical span IDs*, not a byte-content hash: two different physical pairings remain two hypotheses, even if their payloads happened to hash equal. Malformed spans, repeated source identity, inconsistent upstream classification, negative metrics, or over-budget/incomplete scanning -> `incomplete` and no selected original.

## R2 — implementation, safety and trust boundary

- `modules/carving/tests/R5AmbiguousFalseJoinGuard.ps1`: test-only `Resolve-CFragmentFalseJoinEvidence` takes the complete bounded scanner result. For ZIP CRC-consistent proposed fragments it checks two ordered nonoverlapping span records, creates deterministic numeric source-order keys, and returns `one_possible` / `ambiguous` / `unknown` / `incomplete`. All results `originalIdentity=unknown`, `selectedOriginal=$null`, `canAutoSelectOriginal=$false`; every source remains unattributed without the A-owned trusted physical meter. *No scanner code is changed.*
- `modules/carving/tests/R5AmbiguousFalseJoinRegression.ps1`: independently constructs and scores the seven invented test cases, two equal-budget baseline scan runs per case, positive, false metadata, missing/unsupported lengths and fake-EOCD controls. Additional deliberately malformed **scanner result metadata** tests: a duplicate physical pair must be incomplete, a claimed single winner hiding two positives must be incomplete, an injected `originalIdentity=verified` must be incomplete, negative physical read counters must be incomplete, incomplete source budget must stay incomplete. Such metadata-fault negatives are **not changes to the original data or its ground-truth labels**.
- Existing `modules/carving/tests/Test-ChappyCarving.ps1` dot-sources only these new research tests. Production carving/extraction (`Chappy.Carving.psm1`), A meter/receipt interface, B/D modules and public shared schema **unchanged**. Original physical microSD and sole ~31GB IMG were not accessed, read, hashed, copied, scanned, written, repaired, extracted, uploaded or logged.

## R3 — same artificial corpus, initial Windows PS5.1 measurements

First complete Windows [Team C synthetic CI #43155296751](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43155296751) **PASS** on code HEAD `86d62084c9f49115a988026124afa3565eb1896c`. Two additional negative-control commits and this document require **new final exact-head Windows + privacy confirmation** before A review.

| Selected artificial metric | Prior finite scanner alone | Same scanner + uncertainty guard |
| --- | ---: | ---: |
| Synthetic source scenarios | 7 | Same 7 |
| Candidate pairs evaluated | **28** | **28** |
| True-byte-equal accepted pair candidates (TP) | **4** | **4** |
| CRC-consistent but byte-wrong accepted pairs (FP) | **1** | **1** |
| Present-original missed *scenarios* (FN) | **2** | **2** |
| Rejected evaluated pairs (TN) | **23** | **23** |
| Unique / ambiguous / unknown outcomes | **3 / 1 / 3** | **3 / 1 / 3** |
| Artificial true original SHA matches | **4** | **4**, scorer only |
| Original selections / claims | 0 | **0** (explicit non-selection) |
| Actual source Stream.Read bytes across all seven cases | **482,018** | **482,018** |
| Separately counted in-memory ZIP validation reads | **76,002** | **76,002** |
| Additional physical / validator reads from gate | n/a | **0 / 0** |
| Initial summed Windows scan time | 519ms | 518ms + 6ms decision-only |

**Metric units are mixed and explicitly separated:** TP/FP/TN count candidate pair hypotheses; FN counts **present original scenarios with no correct candidate** (not independent hypothetical negatives). These denominators cannot be used as a population accuracy rate. There is **no TP/FP improvement**: the algorithm intentionally changes only downstream decision safety. Timing from one hosted Windows runner is not reproducible evidence of speedup.

Observed important cases: `alternate_zip_metadata` has **two distinct ordered physical candidate keys**, both structurally plausible ZIP/CRC joins; only one is byte-identical to the independent synthetic original SHA. The guard keeps **both** and returns ambiguous, never a CRC-selected original. `fake_eocd` rejects a false tail without discarding the one true candidate; `missing_tail` returns unknown, and `offgrid_plus_two` / `nonlisted_first_560` return unknown despite physically planted true files beyond the experiment hypotheses. No result is upgraded to actual original file integrity.

## R4 — adoption decision requested from Team A

**Proposal: `research_only`**, test-only. This P1 supplies negative regression evidence and a safe downstream consumer pattern; it does NOT justify promotion to production carving or claiming stronger file recovery. Even one structurally possible ZIP candidate remains originalIdentity unknown. A's real outer meter receipts may prove `source_observed` for a candidate, but not that a plausible join equals the true original SHA. To complete R5/R7 eventually: test broader noisy/false-positive populations, more fragment orders/sizes, OPC/XML consistency and A-bound source receipts across multiple candidates under one budget.

Real-media gate: **NOT APPROVED**. Entire study uses generated artificial data; physical microSD and sole 31GB master IMG strictly excluded.
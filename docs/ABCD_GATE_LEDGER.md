# ABCD R4–R7 Gate Evidence Ledger

**Owner A · initialized 2026-11-13 JST · FOUR INDEPENDENT CHATS (NOT WORK).**

Read [four-chat gate-closure playbook](ABCD_GATE_CLOSURE_PLAYBOOK.md) and [unchanged original formal roadmap](ABCD_SYNTHETIC_ROADMAP.md) before changing anything.

**Current official completed stage weight: 39% (R0–R3 only).** Rows below are **not a declaration of PASS**. At initialization, individual requirement evidence has NOT been re-audited against current code and the full formal gate. A's first code/CI audit has signed **3 PASS / 22 rows** (B4-01, D6-01, A7-03), recorded **4 PARTIAL** (C5-02, C5-06, D6-02, A7-02) and left **15 AUDIT_NEEDED**. These labels are narrow stage subchecks, **not** finished R4/R5/R6/R7 stages. The A7-02 PARTIAL implementation awaits final-head CI before acceptance; never infer identity from a metadata guard. Do not confuse absence of this audit with a test failure.

To sign off a row, A (or B/C/D as proposer, then A as verifier) must fill: **status**, code path with HEAD SHA, fixture case IDs, CI URL, actual I/O & UNKNOWN/false-positive scope and explicit residual risks. For `PASS`, independent evidence must cover every requirement in the row; for `PARTIAL`, name missing tests; for `MISSING`, show no implemented support; for `BLOCKED`, name the dependency. `AUDIT_NEEDED` means no completeness assertion has yet been made.

Rows are an operational index of the original formal requirements. **A must add any omitted mandatory requirement before declaring the parent R4/R5/R6/R7 milestone passed**. Do not delete, merge or weaken rows merely to increase the ratio. Every new research or implementation PR must explicitly reference the ledger row it aims to close.

## R4: Directory evidence — B, formal 10%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| B4-01 | PASS | `tests/Test-DirectoryScanner.ps1`; synthetic M00/M01/M04/X02 and #136 | Matrix of TP/FP/FN/TN, UNKNOWN and candidate/edge unit by fixture |
| B4-02 | AUDIT_NEEDED | #125/#131 B LFN/orphan/deleted tests | Validate both clean + damaged LFN, deletion, orphan coverage and candidate retention |
| B4-03 | AUDIT_NEEDED | #131/#136 forged-ledger, hidden parent and competing edge cases | Validate false parent/conflicts/cycles, no original path and physical source trust boundary |
| B4-04 | AUDIT_NEEDED | #136 B actual read transcript and A #133/#134 | Bind B-observed spans and short EOF to independent A physical returned events; do not trust B self-ledger |
| B4-05 | AUDIT_NEEDED | `modules/directory/`, A R7 adapters | Verify bounded, versioned, production-facing result shape and required malformed regression |

## R5: Formats and fragments — C, formal 15%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| C5-01 | AUDIT_NEEDED | `modules/carving/Chappy.Carving.psm1`, existing ZIP/3MF tests | Verify ZIP/3MF OPC/XML positive/negative/CRC/decoys and no false integrity claim |
| C5-02 | PARTIAL | C format tests and production module | Verify binary AND ASCII STL and G-code positives/negatives, parser caps |
| C5-03 | AUDIT_NEEDED | Existing two-fragment tests and historical C PRs | Withhold start/tail and fragment-order truth; benchmark decoys and correct order |
| C5-04 | AUDIT_NEEDED | #137 window comparisons and independent artificial SHA scorer | Full SHA vs structure only, TP/FP/FN/TN/UNKNOWN across both corpus tracks, avoid grid bias |
| C5-05 | AUDIT_NEEDED | A #133/#134 and C source/probe quotas | Actual/unique bytes, calls/probes/candidates/time/memory and true EOF safe failure |
| C5-06 | PARTIAL | Existing opt-in data-window research and C production scanner | Review whether a **usable bounded guarded candidate feature** rather than only a tests-only helper exists |

## R6: FAT evidence — D, formal 10%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| D6-01 | PASS | D cases M00/M01/M02/X02 and main fixture generator | Verify four primary regression cases and clean controls |
| D6-02 | PARTIAL | #126/#132/#138 and earlier chain anomaly tests | Complete paired mirror corruption, missing links, distant anomaly, cycles/crosslinks |
| D6-03 | AUDIT_NEEDED | A #135 conflicting VBR and D geometry module | Separate BPB/backup/mirror hypotheses and no automatic winner |
| D6-04 | AUDIT_NEEDED | #126 real observed physical FAT windows, outer A meter | Honest actual vs unique I/O, 4-byte pair coverage, remote UNKNOWN and short EOF |
| D6-05 | AUDIT_NEEDED | D module exports and tests, fixed vs adaptive #138 | Verify bounded accepted fixed-sample default and no auto FAT copy/repair; **do not promote worse adaptive variant** |

## R7: Candidate integration — A, formal 10%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| A7-01 | AUDIT_NEEDED | #123/#128 synthetic live B/C/D integration | Versioned adapters on actual B/C/D outputs under one nonwritable stream |
| A7-02 | PARTIAL | #133 candidate tokens and `tests/helpers/Merge-A3DSyntheticEvidence.ps1` | Identity conflicts: same candidate ID with different ordered extents; different ID same bytes |
| A7-03 | PASS | #133/#134 A receipts, source quota tests | Full candidate physical reread/byte-union, source/candidate phase ID, dedup/cap |
| A7-04 | AUDIT_NEEDED | #134 early EOF, #135 contradictory BPB | Reordered input, conflicting geometry and extents, forged tokens, early EOF UNKNOWN |
| A7-05 | AUDIT_NEEDED | Synthetic scorer and A evidence merger | Preserve original-byte SHA only in independent oracle; structural and unknown separate |
| A7-06 | AUDIT_NEEDED | `docs/INTERFACE_V1.md` currently DRAFT | One accepted, versioned public-safe result schema and actual live integration tests |

## First A independent code/CI acceptance audit (2026-11-13 JST)

**Reviewed snapshot after A-merged B #140 / C #141 / D #142:** `5318efa43770e0dfbed18212e7bae33e38681491`, subject to final post-main CI and later changes. Exactly **3 PASS + 4 PARTIAL + 15 AUDIT_NEEDED = 22 rows**; the seven audited entries below are *narrow acceptance subchecks*. Zero of R4/R5/R6/R7 full formal stages is signed off, so **39% official weight remains unchanged**.

| Row | Independent A disposition / code and actual evidence | Remaining scope |
| --- | --- | --- |
| **B4-01 PASS** | B original candidate parser `tests/Test-DirectoryScanner.ps1` + `tests/Test-DirectoryR4GateCorpusMatrix.ps1` on generated seeds 202611/202612/202613 x M00/M01/M04/X02: 24 independently scored candidate-size units per arm. Naive TP3 FP9 FN0 TN6 UNKNOWN6 vs conservative TP0 FP0 FN0 TN6 UNKNOWN18 (UNKNOWN **not** FN); 33792 physical-returned source B and 396 reads across 24 scans. Original parent-edge units are not present in those R2 cases and are UNKNOWN, not TN; separately independent `tests/Test-DirectoryR4ObservedParentPositiveControl.ps1` (#136) measures TP3 FP0 FN0 TN3 UNKNOWN6. A-reviewed [B #140 final Windows 1176 PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43406566309), [privacy+central 38/38](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43406566289), exact PR HEAD `5215dd3d4a9eef5e9bc624c64eae88a53af7b9af`. | Only the **B4-01 base-scored matrix** passes. Full R4 still requires B4-02/03/04/05, and the B self-ledger is NOT A source-authenticity proof. |
| **C5-02 PARTIAL** | New explicitly opt-in `modules/carving/Chappy.StlEvidence.psm1` #141 implements strict one-sector 1–8-facet binary and single-facet ASCII STL plus existing C G-code parser. 7 artificial cases x 2 STL labels: TP9 FP0 FN0 TN5, independent SHA8 exact/1 altered structural-only, source 458752 actual B/896 reads. A-reviewed [C native Windows](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43406738570) and [privacy+central 38/38](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43406738497) SUCCESS at exact `5d52d75c86fc7d78c4d55016666054bf412b1e76`. | Non-grid STL, multi-facet ASCII and binary >8 triangles remain unknown; broader STL/G-code format cases and integration required before C5-02 complete. |
| **C5-06 PARTIAL** | A verified STL is now an actual importable guarded default-OFF C module, not merely a test script. Calls require nonwritable `Stream`, bounded 65536 returned B, 128 probes, <=16 candidates, no source path/output or original identity. | Stable cross-format candidate result contract and A physical-source receipt adapter not yet signed off. |
| **D6-01 PASS** | D original generated four-case M00/M01/M02/X02 baseline in `modules/fat-analysis/tests/Run-TeamD-P02Evidence.Tests.ps1` plus independent #142 `Run-TeamD-R6-GateSharedChain.Tests.ps1` also checks M00/M01/M02/M03/M05/X02 source unchanged and copied FAT evidence/UNKNOWN. [D native final HEAD](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43407851076) and [privacy](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43407851309) SUCCESS at `66dbee01ff9d57b6951bb51d593fcd693d1fd611`, with new D6-02 test 72/72. | The base fixture regression row passes; other R6 full-gate requirements and unknown regions do not. |
| **D6-02 PARTIAL** | New additive `modules/fat-analysis/Fat32SharedChainEvidence.psm1` #142 physically observes shared numeric FAT entries in 2 hinted chains / FAT copy under <=1024 actual returned B, <=256 Read calls and <=16 traversal steps each; generates TP1 FP0 FN0 TN4 UNKNOWN1 **numeric shared-node units** and a standard-sized artificial FAT32 positive control. | Does NOT prove two real file owners, exhaustive remote anomalies or source-authentic crosslink; caller geometry untrusted, full evidence integration outstanding. |
| **A7-02 PARTIAL** | New independent `core/Chappy.CandidateDefinitionBoundary.psm1` + `tests/Test-A3DCandidateDefinitionBoundary.ps1` enforces candidate ID ↔ ordered extents/source consistency and rejects conflicting same ID definitions, replayed aliases, source mismatch and invalid bounds. C-scout actual 3MF candidate is the positive test; A can separately have physically read both conflicting definitions and MUST still reject identity ambiguity. [A PR head CI PENDING until test result](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/143). | Integrate into one versioned live A adapter with actual B/C/D and A-issued physical receipts; no original identity or source authority is established merely by metadata. |
| **A7-03 PASS** | `tests/Test-A3DStandardCCandidateReceipts.ps1`, `tests/Test-A3DLiveCCandidateReceipts.ps1`, `tests/Test-A3DCandidateReadTrust.ps1` and `tests/Test-A3DSharedReadProvenance.ps1`: 2 independent artificial standard FAT32 sources, full 887B candidate reread per source, actual read-token scoped events, unique/duplicate returned-byte accounting, global 120000B cap and receipt replay/cross-source/budget negatives. #133 [main 38/38 synthetic CI](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43246089848), #134 real 17/887 premature EOF conservatively unattributed. | PASS is **only physical candidate source-read evidence**, **never** original file, path, ownership or geometry authenticity. A7-01/02/04/05/06 and accepted R4–R6 dependencies still block full R7. |

Before changing any row to PASS again, re-check current main, row's actual source code and exact-head Windows/privacy CI. An A-signed PASS here is auditable *evidence scope*, never an authorization to inspect real media.

## Approved workflow

- Any B/C/D conversation may **propose** a row becoming PASS with code+test+CI links in its own Issue/PR. **Only A** independently verifies and updates this shared ledger and the official stage score.
- A can audit rows concurrently with B/C/D closing genuinely missing requirements; wait only for the dependencies needed by each row, not for entire teams to finish.
- Before each A merge, re-fetch current `main` and every affected branch's exact PR HEAD / Windows PS5.1 + privacy CI. After merge check main CI. Research-only negative controls may be accepted, but do **not** count as a completed functional row unless they actually prove that complete row's requirements.
- If all original requirements of a stage are demonstrably covered with verified CI and documentation, sign off that stage and add its original weight to the official 39%; otherwise keep stage partial. Do not change the fixed weights or arbitrarily assign a percentage to `AUDIT_NEEDED`.

## Safety

Real physical microSD and the sole ~31GB original master IMG: **NOT APPROVED for reading, hashing, scanning, copying, repairing, extracting, writing or uploading**. All GitHub tests use deterministic generated synthetic sources only; no verified real-world restoration rate. R8 remains blocked until R7 full gate approval, and export there will be to a separate disposable synthetic output root only.

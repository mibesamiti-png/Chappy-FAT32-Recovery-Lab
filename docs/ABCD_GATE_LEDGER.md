# ABCD R4–R7 Gate Evidence Ledger

**Owner A · initialized 2026-11-13 JST · FOUR INDEPENDENT CHATS (NOT WORK).**

Read [four-chat gate-closure playbook](ABCD_GATE_CLOSURE_PLAYBOOK.md) and [unchanged original formal roadmap](ABCD_SYNTHETIC_ROADMAP.md) before changing anything.

**Current official completed stage weight: 39% (R0–R3 only).** Rows below are **not a declaration of PASS**. At initialization, individual requirement evidence has NOT been re-audited against current code and the full formal gate. The current count is **0 independently signed-off rows / 21 rows**, with all 21 marked `AUDIT_NEEDED`, **not** 0 implemented features. Do not confuse absence of this audit with a test failure.

To sign off a row, A (or B/C/D as proposer, then A as verifier) must fill: **status**, code path with HEAD SHA, fixture case IDs, CI URL, actual I/O & UNKNOWN/false-positive scope and explicit residual risks. For `PASS`, independent evidence must cover every requirement in the row; for `PARTIAL`, name missing tests; for `MISSING`, show no implemented support; for `BLOCKED`, name the dependency. `AUDIT_NEEDED` means no completeness assertion has yet been made.

Rows are an operational index of the original formal requirements. **A must add any omitted mandatory requirement before declaring the parent R4/R5/R6/R7 milestone passed**. Do not delete, merge or weaken rows merely to increase the ratio. Every new research or implementation PR must explicitly reference the ledger row it aims to close.

## R4: Directory evidence — B, formal 10%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| B4-01 | AUDIT_NEEDED | `tests/Test-DirectoryScanner.ps1`; synthetic M00/M01/M04/X02 and #136 | Matrix of TP/FP/FN/TN, UNKNOWN and candidate/edge unit by fixture |
| B4-02 | AUDIT_NEEDED | #125/#131 B LFN/orphan/deleted tests | Validate both clean + damaged LFN, deletion, orphan coverage and candidate retention |
| B4-03 | AUDIT_NEEDED | #131/#136 forged-ledger, hidden parent and competing edge cases | Validate false parent/conflicts/cycles, no original path and physical source trust boundary |
| B4-04 | AUDIT_NEEDED | #136 B actual read transcript and A #133/#134 | Bind B-observed spans and short EOF to independent A physical returned events; do not trust B self-ledger |
| B4-05 | AUDIT_NEEDED | `modules/directory/`, A R7 adapters | Verify bounded, versioned, production-facing result shape and required malformed regression |

## R5: Formats and fragments — C, formal 15%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| C5-01 | AUDIT_NEEDED | `modules/carving/Chappy.Carving.psm1`, existing ZIP/3MF tests | Verify ZIP/3MF OPC/XML positive/negative/CRC/decoys and no false integrity claim |
| C5-02 | AUDIT_NEEDED | C format tests and production module | Verify binary AND ASCII STL and G-code positives/negatives, parser caps |
| C5-03 | AUDIT_NEEDED | Existing two-fragment tests and historical C PRs | Withhold start/tail and fragment-order truth; benchmark decoys and correct order |
| C5-04 | AUDIT_NEEDED | #137 window comparisons and independent artificial SHA scorer | Full SHA vs structure only, TP/FP/FN/TN/UNKNOWN across both corpus tracks, avoid grid bias |
| C5-05 | AUDIT_NEEDED | A #133/#134 and C source/probe quotas | Actual/unique bytes, calls/probes/candidates/time/memory and true EOF safe failure |
| C5-06 | AUDIT_NEEDED | Existing opt-in data-window research and C production scanner | Review whether a **usable bounded guarded candidate feature** rather than only a tests-only helper exists |

## R6: FAT evidence — D, formal 10%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| D6-01 | AUDIT_NEEDED | D cases M00/M01/M02/X02 and main fixture generator | Verify four primary regression cases and clean controls |
| D6-02 | AUDIT_NEEDED | #126/#132/#138 and earlier chain anomaly tests | Complete paired mirror corruption, missing links, distant anomaly, cycles/crosslinks |
| D6-03 | AUDIT_NEEDED | A #135 conflicting VBR and D geometry module | Separate BPB/backup/mirror hypotheses and no automatic winner |
| D6-04 | AUDIT_NEEDED | #126 real observed physical FAT windows, outer A meter | Honest actual vs unique I/O, 4-byte pair coverage, remote UNKNOWN and short EOF |
| D6-05 | AUDIT_NEEDED | D module exports and tests, fixed vs adaptive #138 | Verify bounded accepted fixed-sample default and no auto FAT copy/repair; **do not promote worse adaptive variant** |

## R7: Candidate integration — A, formal 10%

| Row | Status | Existing evidence to examine | Specific remaining audit/delivery |
| --- | --- | --- | --- |
| A7-01 | AUDIT_NEEDED | #123/#128 synthetic live B/C/D integration | Versioned adapters on actual B/C/D outputs under one nonwritable stream |
| A7-02 | AUDIT_NEEDED | #133 candidate tokens and `tests/helpers/Merge-A3DSyntheticEvidence.ps1` | Identity conflicts: same candidate ID with different ordered extents; different ID same bytes |
| A7-03 | AUDIT_NEEDED | #133/#134 A receipts, source quota tests | Full candidate physical reread/byte-union, source/candidate phase ID, dedup/cap |
| A7-04 | AUDIT_NEEDED | #134 early EOF, #135 contradictory BPB | Reordered input, conflicting geometry and extents, forged tokens, early EOF UNKNOWN |
| A7-05 | AUDIT_NEEDED | Synthetic scorer and A evidence merger | Preserve original-byte SHA only in independent oracle; structural and unknown separate |
| A7-06 | AUDIT_NEEDED | `docs/INTERFACE_V1.md` currently DRAFT | One accepted, versioned public-safe result schema and actual live integration tests |

## Approved workflow

- Any B/C/D conversation may **propose** a row becoming PASS with code+test+CI links in its own Issue/PR. **Only A** independently verifies and updates this shared ledger and the official stage score.
- A can audit rows concurrently with B/C/D closing genuinely missing requirements; wait only for the dependencies needed by each row, not for entire teams to finish.
- Before each A merge, re-fetch current `main` and every affected branch's exact PR HEAD / Windows PS5.1 + privacy CI. After merge check main CI. Research-only negative controls may be accepted, but do **not** count as a completed functional row unless they actually prove that complete row's requirements.
- If all original requirements of a stage are demonstrably covered with verified CI and documentation, sign off that stage and add its original weight to the official 39%; otherwise keep stage partial. Do not change the fixed weights or arbitrarily assign a percentage to `AUDIT_NEEDED`.

## Safety

Real physical microSD and the sole ~31GB original master IMG: **NOT APPROVED for reading, hashing, scanning, copying, repairing, extracting, writing or uploading**. All GitHub tests use deterministic generated synthetic sources only; no verified real-world restoration rate. R8 remains blocked until R7 full gate approval, and export there will be to a separate disposable synthetic output root only.

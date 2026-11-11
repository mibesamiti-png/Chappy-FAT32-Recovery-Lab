# Team A — research-first R4 decisions on B #45 / C #46 / D #47

**Date:** 2026-11-11. **Status:** independently reviewed exact-head artificial Windows PowerShell 5.1 + privacy CI. Source `main` baseline frozen by all three teams at `8fd97ce7306d7296f203c4561ff730b046e0c9ce`. Never tested on user's actual microSD or unique ~31 GB master IMG.

This document is a record of Team A's **adoption decisions**, not an estimate of real recovery rate. In all three research cards, published sources and licenses were surveyed prior to algorithm edits; no third-party code is reported as imported. A repository-wide license remains **undeclared**. Review every external code asset's actual license before future reuse.

## Decisions

| Team / Issue | Draft PR and tested HEAD | Same-corpus artificial A/B | R4 judgment | Production behavior |
| --- | --- | --- | --- | --- |
| B #45 | [#49](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/49) `97c95992` | 13 synthetic structural-edge cases: baseline TP2 FP3 FN0 TN8; opt-in conflict guard TP2 FP0 FN0 TN11 | **adopt_experimental** | Added `-DetectConflictingContainerObservations` **OFF by default**; retains weak candidates, reports fixed conflict codes |
| C #46 | [#51](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/51) `8c86a018` | Five chosen artificial two-fragment scenarios / nine pair tests: TP4 FP2 FN1 TN3; four byte-identical candidate pairings, but only two unique unambiguous scenarios | **research_only** | Test helper and research notes only; no production fragment discovery/reassembly |
| D #47 | [#50](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/50) `c854b1cd` | Eight artificial FAT anomalies under identical 768-byte total reads: current R6 TP3 FP0 FN3 TN2; new R7 TP5 FP0 FN1 TN2 | **research_only** | Standalone read-only opt-in R7 module retained; **R6 remains unchanged/default**, since R7 misses matching-mirror root cycle |

### Meaning and limits

- **B:** "TP/FP" denotes a **structurally probable graph relation according to complete artificial ground truth**, not a recovered original path, user filename, or real-world precision.
- **C:** Its candidate method is given **oracle-like artificial tail offsets**. The baseline contiguous-only carver has no equivalent tail-offset hints, so its 0/5 byte-complete cases and C's four matches **cannot** be treated as fair general search accuracy or speed improvement. Distinct plausible G-code and structurally valid ZIP tails remain ambiguous; **no original integrity proof** from archive structure, CRC or candidate SHA alone.
- **D:** Stratified sampling sees midpoint anomalous markers missed by root-focused R6, but **fails** to detect an identically corrupted two-link root cycle seen by R6. Neither strategy sees full FAT copies (typical sample 6/128 entries per copy in artificial controls). A decision explicitly blocks default-on integration and substitution of R6. Matching mirrors can be identically corrupted.
- Synthetic CI passes demonstrate bounded behavior against selected small invented fixtures. Missing real cases and adversarial coverage remain unknown.
- No original microSD/master IMG reads, hashes, writes, recovered files, real names, actual content, user-device scans or public uploads. **The real-image local approval gate remains NOT APPROVED**.

### Source provenance and reuse gate

B researched Microsoft FAT32 v1.03 / The Sleuth Kit / Linux VFAT directory parser; C researched Garfinkel bifragment carving / PhotoRec / 3MF Core; D researched TestDisk / The Sleuth Kit / FAT32 on-disk specification. Consult each originating Issue #45/#46/#47 R0 research card and its own PR notes for URLs, exact terms, tradeoffs and unknowns. **Researching an algorithm is not permission to copy GPL/mixed-license source.** All new code and tests were reported independently implemented, without upstream imports.

### Actual CI evidence before merge

- B #49: [Windows B 125/125 PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43029408412), [privacy and central PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43029408426).
- C #51: [Windows C PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43030176560), [privacy and central PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43030176640).
- D #50: [Windows D 472/472 PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43030028156), [privacy and central PASS](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43030028004).

### Team A integrated QA

Current A integration PR adds D R7's dedicated synthetic A/B test to `runner/Invoke-ChappySyntheticRegression.ps1`. B's R7 runs through the existing B wrapper and C's R5 runs through the existing carving wrapper; no duplicate entries for those. The resulting **15 isolated suites** must all pass **on exact PR head** and on post-merge main before recording central-gate success. Existing A 7-scenario artificial FAT32-like IMG byte match regression has a selected, constructed **10/14 exact source-slice expectation**, not a real data recovery rate.

### Next bounded studies (separately dispatched by A)

- B: test interplay of opt-in conflict observation and changing partial/incomplete graph coverage under more realistic generated but still synthetic directory layouts.
- C: **candidate fragment tail-offset discovery without an oracle** plus independent validation and equal-budget/fair old-vs-new comparison; no automatic file export.
- D: additive stratified evidence that preserves the bounded R6 root-chain cycle detection rather than replacing it; strict summed quotas.
- A: improve A/B gate automation/CI reports with explicit fairness and research-only statuses, retain local original-img trial gate as NOT APPROVED.

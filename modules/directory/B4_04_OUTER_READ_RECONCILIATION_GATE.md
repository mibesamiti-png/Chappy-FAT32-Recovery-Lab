# B4-04 — Directory returned-byte reconciliation, independent-source boundary

**Owner:** Team B, Issue [#71](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71). Pre-code frozen audit [Issue comment #6858606341](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/71#issuecomment-6858606341). Baseline main `a6aa8c137ccc5561ca23624fcdeee3c65755ecfb`, A's B/D versioned consumer PR #155 already merged. This is a **proposed B4-04 acceptance component**, not A's signed physical receipt system.

## New production-facing pure function

Dot-source `modules/directory/DirectoryReadReconciliation.ps1` and call `Compare-ChappyBDirectoryReturnedEvidenceV1 -DirectoryEnvelope $b -OuterReadEvents $outer -SourceLengthBytes $length`. It **does not open/read/write a stream, return filenames, reconstruct original paths, issue source tokens, or export anything**.

- `DirectoryEnvelope` must have B4-05 `b_directory_evidence_v1`, `sourceAuthority=B_scanner_report_unattested_not_A_receipt`, `originalIdentity=unknown`, `metrics.sourceReadAttestation=unattested`, and no export or FAT copy selection. B-supplied numeric successful **completed cluster spans** and returned bytes remain **caller-controllable**.
- `OuterReadEvents` is an independently supplied array with `Consumer=geometry|directory|carving|fat`, `OffsetBytes` and **actual positive** `ReturnedBytes`, compatible with **A's** `ChappyA7LiveReadV1` events. Geometric, carving and FAT reads are validated against bounds but **not counted** as B directory observations. A must supply its own *actual* in-process outer successful-return observations, not a copy of the B self-ledger.
- Explicit bounded comparison: <=512 external events, <=32 B completed spans, <=131072 B for one return and <=1 GiB synthetic `SourceLengthBytes`. Per-event offset/end and B span bounds are validated; completed B span lengths are compared to B completed cluster count. Returned **sum** is reconciled with B total returned bytes and independently measured **unique** intervals. Overlapping B spans, duplicate/repeated external reads, missing or shifted physical returns and fabricated B totals are denied rather than counted twice. Physical directory returns outside completed clusters equal B's **incomplete** returned byte counter; cannot be called a completed cluster. No byte comparisons, external authenticated read receipts or oracle truth are passed to B.
- Output `b_directory_outer_reconciliation_v1`, decision `consistent_unattested | partial_unknown | contradicted | unknown` and fixed reason codes. **Even perfect consistency gives only `consistent_unattested`, not `verified` or trusted A source provenance.** All outcomes: `sourceAuthenticity=not_proven`, `outerEventAuthority=caller_supplied_not_B_or_A_receipt`, `originalIdentity=unknown`, `parentConfidence=partial`, `canExport=false`, `canSelectFatCopy=false`, `additionalStreamReads=0`. A must independently bind outer stream ownership/phase/receipt and specific candidate extent proof; B must not mint A IDs.
- Incomplete B counters/null on I/O error produce `unknown`; a 17 B returned partial cluster with 0 completed spans produces `partial_unknown`; forged totals and wrong intervals produce `contradicted`. Missing outer source records never become a valid complete source. Validation errors are fail-closed without including raw exception text.

## Frozen synthetic gates and units

`tests/Test-DirectoryR4GateReadReconciliation.ps1` runs after B4-05 test in `tests/Test-DirectoryScanner.ps1` and uses **the same real B production** versioned envelope as the A consumer, with independently metered synthetic `MeteredStream` physical events reshaped to A event fields by the TEST SCORER only.

| Unit | Invented artificial input and comparison | Expected decision |
| --- | --- | --- |
| 9 control invocations | 3 seeds x M00/M01/M04, readonly 2MiB generated FAT32-like image with 1024B B directory limit and chunked <=97B physical reads | 9 `consistent_unattested`, no authenticated parent |
| Forge a 3rd completed B cluster | Same baseline, B self-ledger says extra 512B not returned by outer logger | `contradicted` |
| Shift physical directory read positions | Real outer events copied then +512B offset shift on directory phase only | `contradicted` |
| Omit a physical event | One directory return intentionally missing from supplied external transcript | `contradicted` |
| Duplicate and overlap | Insert duplicate physical event or shift one real event onto another | `contradicted` each |
| Wrong source length | B span beyond external measured source boundary | `contradicted` |
| Mislabel geometry as directory | Same actual successful return but incorrect phase | `contradicted` |
| Empty outer transcript | B self-ledger exists, independent events absent | `contradicted` |
| Event quota exhausted | More events than configured `MaxEvents` | `unknown` |
| 17/512 EOF | Artificial bounded source physically returns exactly 17 directory bytes, then zero, geometry 1024B; B completed0, spans0 | `partial_unknown` |

Predeclared expectation: 9 control scans actually return **18,432B source including geometry**, **9,216B B-directory**, **216 positive `Stream.Read` calls**, 18 completed directory spans. Distinct short EOF source additionally returns **1,041B** including 17B partial directory but **0 complete spans**. The outer count is a test-side physical read metric, NOT the count of files recovered. Synthetic seed metadata/original SHA stay in the external scorer, never in B. The comparison has no TP/FP of real files; count ledger cases by explicit `consistent_unattested/contradicted/unknown` units without pooling unrelated LFN/parent confidences.

## A integration and remaining blockers

A R7 #155 already maintains `ChappyA7LiveMeterV1` and its outer events; A may review and consume B's pure comparison with A-owned event arrays, thereby determining whether B's returned-byte ledger **agrees with** A-observed source byte coverage. **The pure B comparison cannot establish that the external event array is authentic** if another caller invents it. A must enforce nonforgeable event ownership, source-scoped IDs, candidate-specific rereads and unknown handling before declaring B4-04 PASS and accepting full R4/R7. No A-owned code or ledger was modified by B.

B4-03 remains PARTIAL (default-off strict graph if called outside B envelope), B4-01/02/05 A-signed PASS; R4 stage not accepted. Official project weighted progress **39%** from R0–R3 only, not real restoration rate. Real microSD and unique ~31GB master IMG are **NOT APPROVED for any read, hash, scan, copy, repair, extraction, write or upload** and are never used by this test. No third-party code reused: Microsoft Stream.Read and FAT fields used conceptually; TSK source mixed-licensed and Linux GPL source excluded.
# ABCD progress parameters — A-owned, verifiable (2026-11-13 JST)

**Goal:** Make four separate ChatGPT team chats comparable without inventing percent-complete numbers. Source of truth is the [22-row A-signed R4–R7 gate evidence ledger](ABCD_GATE_LEDGER.md), **not historical subjective B/C/D 81/79/86% estimates**. A edits ledger after independently reviewing actual source and final-head Windows PowerShell 5.1/privacy CI. All metrics are **synthetic engineering evidence**, not user data recovery success.

## Exact mathematical definitions

For a team with `N` registered ledger rows:
- **Verified gate-row evidence** = `PASS/N × 100%`; this is an objectively inspectable *lower bound on A-signed row completions*, **not the implementation completeness of an entire milestone**.
- **Audited / assessed condition coverage** = `(N−AUDIT_NEEDED)/N × 100%`. `PARTIAL`, `MISSING` and `BLOCKED` all count as *reviewed*, even if feature completion is 0%. This measures how much of the backlog is understood, not how much code is finished.
- **Evidenced work reach** = `(PASS+PARTIAL)/N × 100%`; only indicates the fraction of rows with **some confirmed positive implementation/test evidence**, never a weighted estimate of completed function. We do NOT convert PARTIAL to 50% PASS; `AUDIT_NEEDED` does NOT mean feature missing.
- **Gate blockers** = status `BLOCKED`; **implementation missing** = `MISSING`; **awaiting audit** = `AUDIT_NEEDED`. Preserve all three separately.
- **Official weighted project progress** = **39%**, the separately accepted full stages R0=5%, R1=10%, R2=12%, R3=12%. R4=10, R5=15, R6=10, R7=10, R8=9, R9=5, R10=2 are not credited before their **entire original formal stage criteria** have A signoff and CI. **Never automatically promote official progress because all 22 subrows became PASS.**

## Latest snapshot after A independently reviewed and merged B #148, C #150, D #149

Baseline merged main `e0bb8b2dd778760da8a8a81c6592c8eea730b6d7`; A7-01 latest live adapter remains PARTIAL pending final-head CI in A Draft. This is an evidence **snapshot**, re-run the script on main after final A merge.

| Team | Formal stage | PASS | PARTIAL | AUDIT_NEEDED | Condition evidence % (PASS/N) | Assessed % ((N−AUDIT_NEEDED)/N) | Evidenced work reach % |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| B | R4 | 2/5 | 1/5 | 2/5 | **40.0%** | 60.0% | 60.0% |
| C | R5 | 0/6 | 4/6 | 2/6 | **0.0%** | 66.7% | 66.7% |
| D | R6 | 1/5 | 3/5 | 1/5 | **20.0%** | 80.0% | 80.0% |
| A | R7 | 1/6 | 2/6 | 3/6 | **16.7%** | 50.0% | 50.0% |
| **Total** | R4–R7 | **4/22** | **10/22** | **8/22** | **18.2%** | **63.6%** | **63.6%** |

*These percentages are not full engineering completion, not a likelihood of real file recovery, not comparable to the original informal 79–86% estimates. C’s 0% verified row evidence is not 0% implemented work: four actual positive capabilities are PARTIAL but incomplete for their broad formal gate.*

## Reproduce with Windows PowerShell 5.1

```powershell
# From repository root, reads ONLY the canonical markdown ledger.
.\core\Get-ChappyABCDProgress.ps1
# Deterministic machine-readable parameters:
.\core\Get-ChappyABCDProgress.ps1 -AsJson
# A must inspect all changed rows and CI, not manually override numbers.
```

The tool rejects missing/duplicate/unknown row IDs, invalid schema/status or non-Markdown ledger paths. It only reads a `.md` text file, never opens any IMG, volume, device, source Stream or directory tree. A synthetic independent 22-row frozen fixture in `tests/Test-A3DGateProgressParameters.ps1` proves counts, team ratios, regressions and **no automatic official milestone credit**, while an extra check asserts current live ledger integrity without hardcoding its future honest PASS counts. Native Windows PowerShell 5.1 central runner grows from **39 to 40** isolated generated-artificial test scripts. The read-only test cannot change the canonical ledger file; pre/post SHA verified.

## Stage-specific next-action parameters

| Team | Highest-priority remaining proof | Class of unresolved dependency |
| --- | --- | --- |
| **B** | B4-03 misleading parent/duplicate/hidden observations; B4-04 independently A-metered source events; B4-05 versioned A interface | Parent graph and source trust |
| **C** | C5-01 full OPC/ZIP breadth beyond strict model, C5-02 broader STL/G-code, C5-03 non-oracle fragmented reconstruction, C5-04/05/06 validation/cost/interface | Candidate completeness and correct-byte reconstruction |
| **D** | D6-02 true ownership remains UNKNOWN even when same numeric FAT nodes shared; D6-03 broader inconsistent VBRs; D6-04 externally A-attributed read receipts; D6-05 accepted bounded adapter | Partial FAT coverage and source trust |
| **A** | A7-01/A7-06 one versioned live adapter joining real B/C/D module results under a shared A-issued physical returned-byte cap; A7-02 finalize candidate extent binding; A7-04/05 uncertainty | Integration and attestable evidence |

Every chat should record `rowId`, last-reviewed HEAD, exact CI and next missing acceptance evidence. An indicator becoming more favorable without evidence is a bug, not progress.

**Safety:** original physical microSD and sole ~31GB master IMG are still **NOT APPROVED for ANY access**: no reading, hashing, scanning, copying, uploading, repairing, exporting or writing. Generated artificial data only, and R8 stays blocked until full R7 acceptance.


## Prior audited snapshot, for comparable change measurement

Before this A round: 4 PASS, 6 PARTIAL, 12 AUDIT_NEEDED out of 22; assessment 45.5%. This round after B #148, C #150, D #149 and pending A live adapter: 4 PASS, 10 PARTIAL, 8 AUDIT_NEEDED out of 22; assessment 63.6% (**+18.1 percentage points reviewed**, not +18.1% engineering completeness). No new original formal stage gate passed. Verified PASS-ratio remains 18.2%, official weighted project remains 39%.

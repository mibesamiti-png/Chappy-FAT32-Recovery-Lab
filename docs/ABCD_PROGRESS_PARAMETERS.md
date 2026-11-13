# ABCD progress parameters — A-owned, verifiable (2026-11-13 JST)

**Goal:** Make four separate ChatGPT team chats comparable without inventing percent-complete numbers. Source of truth is the [22-row A-signed R4–R7 gate evidence ledger](ABCD_GATE_LEDGER.md), **not historical subjective B/C/D 81/79/86% estimates**. A edits ledger after independently reviewing actual source and final-head Windows PowerShell 5.1/privacy CI. All metrics are **synthetic engineering evidence**, not user data recovery success.

## Current stage milestone and narrow-condition parameters — seventh A round, 2026-11-14 JST

**Official whole-stage weighted project = 49%** (R0–R4 only; explicit [original R4 A signoff](docs/R4_FORMAL_ACCEPTANCE_A_SIGNOFF.md) and A signoff PR final-head/post-main CI required). B's original R4 acceptance is on generated synthetic evidence only. **This does not mean 49% of real files recovered.** Physical card/master IMG remain NOT APPROVED. Historical sections below retain their dates and earlier 39% snapshots.

| Team | Stage | Signed PASS | PARTIAL | AUDIT_NEEDED | Verified narrow rows | Entire original formal stage |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| B | R4 | 5/5 | 0 | 0 | 100.0% | **A ACCEPTED** synthetic stage, 10 points |
| C | R5 | 3/6 | 3 | 0 | 50.0% | Not accepted |
| D | R6 | 4/5 | 1 | 0 | 80.0% | Not accepted |
| A | R7 | 1/6 | 5 | 0 | 16.7% | Not accepted |
| **Total** | R4–R7 | **13/22** | **9/22** | **0** | **59.1%** | **49% official whole project** |

Only separately A-signed original milestones affect official percent. The progress script explicitly records R4 acceptance as a separate constant and MUST NOT turn R5/R6/R7 into PASS based merely on all subrows.

## Exact mathematical definitions

For a team with `N` registered ledger rows:
- **Verified gate-row evidence** = `PASS/N × 100%`; this is an objectively inspectable *lower bound on A-signed row completions*, **not the implementation completeness of an entire milestone**.
- **Audited / assessed condition coverage** = `(N−AUDIT_NEEDED)/N × 100%`. `PARTIAL`, `MISSING` and `BLOCKED` all count as *reviewed*, even if feature completion is 0%. This measures how much of the backlog is understood, not how much code is finished.
- **Evidenced work reach** = `(PASS+PARTIAL)/N × 100%`; only indicates the fraction of rows with **some confirmed positive implementation/test evidence**, never a weighted estimate of completed function. We do NOT convert PARTIAL to 50% PASS; `AUDIT_NEEDED` does NOT mean feature missing.
- **Gate blockers** = status `BLOCKED`; **implementation missing** = `MISSING`; **awaiting audit** = `AUDIT_NEEDED`. Preserve all three separately.
- **Official weighted project progress** = **49%**, independently accepted full stages R0=5%, R1=10%, R2=12%, R3=12%, **R4=10% (separate A original formal-stage signoff)**. R5=15, R6=10, R7=10, R8=9, R9=5, R10=2 are not credited until each entire formal stage passes independent A signoff and CI. **Never automatically promote official progress because all 22 subrows became PASS.**

## Latest snapshot after A independently reviewed and merged B #162, C #160, D #161

Baseline B/C/D-merged main `ceb890644f7af778a980654532930dca233fc5dc`. A #163 live B4-04 bound physical A meter passed early 44/44 code-head CI but full final-head and post-main CI are still required. The 22 index rows are a **subcheck audit**, not the original whole-stage roadmap criteria or a real-file restoration rate.

| Team | Formal stage | PASS | PARTIAL | AUDIT_NEEDED | Condition evidence % (PASS/N) | Assessed % ((N−AUDIT_NEEDED)/N) | Evidenced work reach % |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| B | R4 | 5/5 | 0/5 | 0/5 | **100.0%** | 100.0% | 100.0% |
| C | R5 | 2/6 | 4/6 | 0/6 | **33.3%** | 100.0% | 100.0% |
| D | R6 | 4/5 | 1/5 | 0/5 | **80.0%** | 100.0% | 100.0% |
| A | R7 | 1/6 | 5/6 | 0/6 | **16.7%** | 100.0% | 100.0% |
| **Total** | R4–R7 | **12/22** | **10/22** | **0/22** | **54.5%** | **100.0%** | **100.0%** |

*These percentages are not full engineering completion, not a likelihood of real file recovery, not comparable to the original informal 79–86% estimates. C now has two independently signed bounded PASS rows and four PARTIAL rows; assessed 100% does NOT mean R5 is complete.*

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


## Fourth audit snapshot — progress deltas (A review, 2026-11-14 JST)

Compared with preceding third A round (4 PASS / 10 PARTIAL / 8 AUDIT_NEEDED, **63.6%** assessed) the current **provisional** main+new-A-branch ledger has **7 PASS / 11 PARTIAL / 4 AUDIT_NEEDED, 81.8% assessed**. That is **+3 separately A-signed narrow PASS rows**, **−4 audit-needed rows**, **+18.2 percentage points of assessed gate-row coverage**. These are distinct from official project progress, which remains **39%**; they are NOT actual restoration success or full engineering completeness. A7-06 partial proposal requires final A PR-head native Windows/privacy CI. The `core/Get-ChappyABCDProgress.ps1 -AsJson` command recomputes these from newest ledger rows; no hardcoded subjective progress estimate.


## Fifth A snapshot and differential gate parameters — 2026-11-14 JST

Before this round: B 3 PASS/1 PARTIAL/1 audit; C 1/4/1; D 2/3/0; A 1/3/2. **7 PASS, 11 PARTIAL, 4 AUDIT_NEEDED** across 22; 31.8% narrow-row verified and 81.8% assessed. After A independently reviewed B #156/C #157/D #158 and drafted A fragment physical reread: B 3/2/0, C 1/5/0, D 3/2/0, A 1/5/0. **8 PASS, 14 PARTIAL, 0 AUDIT_NEEDED**, 36.4% verified, **100% audited**. D6-02 is a narrowly bounded synthetic fixed-FAT anomaly acceptance, not proof of all source clusters or actual file owners. All 22 formally indexed *subconditions* have been inspected; **14 are not complete**. Change: **+1 narrow PASS, +3 PARTIAL, -4 AUDIT_NEEDED; +18.2 percentage points of audit coverage**. None of these represent actual recovery probability. Official weighted full-stage **39%**, R0–R3 only, unchanged. A7-04/A7-05 PARTIAL tests pending final-head PS5.1+privacy CI and independent post-main acceptance.


## Sixth A verified-conditions differential snapshot — 2026-11-14 JST

Before this round: **8 PASS /14 PARTIAL /0 AUDIT_NEEDED** of 22 (36.4% signed narrow rows). After A independently signed B4-03, C5-01, D6-03 based on final-head PS5.1/privacy CI and added A-owned live directory returned span comparison B4-04 (code-head 44/44, final-head CI still mandatory), current provisional ledger **12 PASS /10 PARTIAL /0 AUDIT_NEEDED**, 54.5% narrow row verified, 100% audited. Delta **+4 narrow PASS, −4 PARTIAL, +18.1 percentage points** in narrow verified-row rate. B's 5/5 scoped checklist is **not yet a separate original formal R4 complete-stage signature**; the formal R4 acceptance must be explicitly reviewed against original multi-track hidden-parent/uncertainty requirements before adding its 10% stage weight. Formal overall project remains **39%**. None of these numerical parameters estimate recoverability of actual private media, and the only 31GB master IMG and physical card remain unapproved for any access. `core/Get-ChappyABCDProgress.ps1 -AsJson` computes current signed statuses from `docs/ABCD_GATE_LEDGER.md` without assigning PARTIAL=0.5.

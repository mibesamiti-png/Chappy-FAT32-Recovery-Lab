# Team D Issue #73 R6-P6 — contradictory or identical corrupt FAT copies (research-only)

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #104](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/104), branch `research/d-r6-dual-fat-ambiguity-20261112`, issued by A from approved `main e420369bb6de79e33de009cbce570315880a589f`. At start main was `d887522ecd072b7d2b5f2e15d3d698e1d0a0a74b` (one A-owned commit ahead); assigned branch preserved. Prior D #101 already merged research_only. No B/C/A/shared changes.

## R0 — official primary sources and licenses

The research/source/license protocol was recorded **before coding** on [Issue #73 comment 6814491678](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6814491678).

| Author/publisher/source | Principle and failure mode | Rights / reuse |
| --- | --- | --- |
| Microsoft Corporation, *FAT32 File System Specification* v1.03 (2000), https://www.osdever.net/documents/fatgen103.pdf | Mirrored FAT32 entries can agree by both sharing one corruption; copy mismatch alone never establishes which copy preserves original links. Observed subset not entire FAT. | Copyrighted document, not permissive source-code license; no spec text/code copied |
| Christophe Grenier / CGSecurity TestDisk, official https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Alternative FATs and boot records are useful independent clues but selecting/copying/repairing is an unauthorized step for this lab. | GPL-2.0 implementation; **no code copied/imported**, license review required if ever reused |
| Brian Carrier / Sleuth Kit Labs, official https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Sampled chain termination and owner provenance differ; a shared cluster does not establish a genuine recovered file or whether a cross-file link is legitimate. | Mixed component licenses; **license_review_required** for source reuse, none performed |

All new test helper code is independently written using stock Windows PowerShell 5.1/.NET and existing in-repository D functions. The original 31GB master IMG is inaccessible to this research and explicitly forbidden.

## R1 — frozen same-corpus test, corrected artificial EOC fixture before new CI

- Baseline and candidate: unchanged experimental/default-OFF `Get-ChappyFatObservedIoEvidence` from merged PR #90. `MirrorOnly` compares 128 FAT entries; `MirrorAndChain` compares 64 and probes predetermined cluster starts 2..8. No oracle hint, filename, original SHA, damage position or owner is supplied to either module. **Both cap independently at 2,048 actual returned source bytes per invocation**, including geometry; separate stream physical metering and unique-byte union.
- A fixture helper `tests/helpers/New-Chappy3DDamagedFixture.ps1` blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5`, seed **202611**. All images generated in memory (2MiB FAT32-**like**, not standards-sized FAT32) and checked with scorer-only SHA256 before and after. Existing M00 clean, M01 healthy nonadjacent fragmentation, M02 one FAT1 wrong link, M03 same corrupt cycle in both FATs, M05 both-FAT crosslink and X02 payload truncation.
- Added two **scorer-only mutations** on generated M00 bytes, while preserving untouched source: `CONFLICT` changes only FAT2 entry4, so **FAT1 4→5→EOC** while **FAT2 4→8→EOC**. FAT2's new link also points into a distinct synthetic file's chain: its ownership is unknown to D and is not certified. `REMOTE` changes FAT2 entry256 to a reserved value **outside** the fixed 64/128-entry comparison windows; source-level ground truth is kept in scorer only.
- Resource negatives: 7-byte source fragments with cutoff at **1,150 actual returned bytes**; independent **32-byte** global cap. The externally controlled source is always strictly non-writable and seekable. No filesystem path or physical device input.
- **Transparent R1 correction:** [Issue comment 6814592613](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6814592613) documents that initially proposed 4→6 contradicted the actual artificial clean generator: cluster6 is free rather than EOC. Replaced the *artificial test fixture design* with 4→8 (existing EOC) **before revised code and retest**, keeping the stated hypothesis, scored case classifications, caps and all existing D modules unchanged. The initial Windows script was **135 passed / 2 failed**, not accepted; updated script passed.

## R2 — exactly one tests-only research slice

New `modules/fat-analysis/tests/Run-TeamD-R6-DualFatAmbiguity.Tests.ps1` with one dedicated D-only Windows CI step. No edits to the production D modules, A's shared source meter, A R7 receipt interface, B/C, user paths or devices.

Each of the ten artificial cases is observed twice with fresh separately non-writable, physically metered streams of the **same exact artificial byte content**, holding equal per-mode global source byte limits (2,048 normally, 32 in the negative). The external physical meter independently counts actual returned bytes, distinct byte offsets and Read() calls; the test verifies stage byte sums, D event bounds, nonoverlapping true unique source ranges, budget limits, input SHA unchanged, no private original metadata or copy/repair authority in output.

A **supplementary independent bounded stream**, clearly **outside** the per-mode A/B resource counts, traces the one contradictory 4→5 versus 4→8 source case directly through the unchanged D `Get-ChappyFatChainAnomalyStats`. Both copies report terminal EOC. Equal terminal category does **not** mean equal chain path, file ownership, or an authenticated FAT copy.

## R3 — measured Windows PowerShell 5.1 same-fixture artificial results

**Executed code HEAD `4dcb4b47207315f4636cd64969e2b3b948f9548f`:** [Windows PS5.1 synthetic CI #43155416834](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43155416834) **SUCCESS: new D P6 137/137 assertions passed**, previous Team D CI steps passed. Matching [privacy / isolated synthetic gate #43155416690](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43155416690) must be explicitly verified; this documentation-only commit also requires exact-final-HEAD Windows and privacy rechecks.

**Precisely five scorable artificial cases** for *observed in-window FAT mismatch or a sampled cycle*: M00/M01 negatives, M02/M03/CONFLICT positives. **Five unknown/excluded**: M05 file-owner ambiguity, X02 payload truncation, REMOTE entry256 outside sampled window, M02 short-reading source and M03 32-byte cap. Do not miscount those as healthy, TN, or recovered files.

| Measured unit | MirrorOnly baseline | MirrorAndChain candidate |
| --- | ---: | ---: |
| TP / FP / FN / TN on five selected in-window synthetic abnormalities | **2 / 0 / 1 / 2** | **3 / 0 / 0 / 2** |
| Sample precision | 2/2 (100%) | 3/3 (100%) |
| Sample recall | 2/3 (66.7%) | 3/3 (100%) |
| Total actual returned source bytes, ten runs per mode | **17,566** | **13,986** |
| Per-run summed distinct source byte observations | **17,566** | **13,470** |
| Repeated physical byte reads (within mode runs) | 0 | **516** |
| Actual source Stream.Read() calls | **201** | **344** |
| Max actual returned bytes per run | ≤2,048 | ≤2,048 |
| Unsupported FAT winner / repaired source / original-file authenticity claims | 0 | 0 |
| Verified original recovered-file bytes | not applicable | not applicable |
| Reliable CPU or peak memory performance | not measured | not measured |

**Observed negatives:** M03 contains four cycle observations and **zero mirrored entry disagreements**; M02 and CONFLICT each show one FAT mismatch but no selected winner. M05 appears mirror-equal yet is scorer-labelled cross-file link; no FAT-only file ownership claim possible. REMOTE entry256 is unobserved in both scanning windows, so an apparent zero mismatch cannot be promoted to whole FAT integrity. X02's declared volume size contradicts source length. The early-stop reader returned exactly **1,150 bytes** in each mode, safely marked partial; the 32-byte source cap returned `insufficient_evidence` for geometry. A deliberately unsafe `mirror-agreement => healthy original` interpretation would falsely assert authenticity in **four known-bad/unknown scenarios** (M03, M05, X02, REMOTE); the D module makes **zero** such claims.

**Supplemental path-vs-terminal check:** separately metered **1,040 actual / 1,040 unique bytes**, 6 source Read() calls for geometry + 64-byte bounded FAT chain trace. FAT1 path 4→5→EOC and FAT2 path 4→8→EOC both report `eoc` terminal; unverified FAT remains unknown. These **extra physical reads are explicitly excluded** from the same-budget A/B counts, not hidden in them.

Fewer actual bytes in the combined candidate came with **more physical Read() calls**: 344 versus 201 across ten cases. No speed gain may be inferred. Results are on deliberately selected synthetic FAT-like arrays only, not real recovery rates, media health, or file identity. Scores from source/sampling evidence must never be interpreted as a real returned-file success rate.

## R4 — requested Team A disposition and open questions

**Recommend `research_only` / no production change.** A should review preservation of FAT copy/chain uncertainty, geometric trust and independently metered interval provenance; then decide whether to merge the tests/docs and whether its R7 evidence adapter needs a stronger *per-copy path conflict* reason code. Team D must **not** change the shared A adapter or make an unapproved source selection. Remaining R6 work includes independent directory-file owner evidence for crosslinks, broad and out-of-window FAT coverage under a global budget, full VBR/backup FSInfo confidence boundaries, and standards-shaped artificial validation.

No original physical microSD or unique ~31GB master IMG read, hashed, copied, scanned, written, repaired, exported or uploaded. Local real-image approval **NOT APPROVED**. All published data is synthetic and safe for CI.

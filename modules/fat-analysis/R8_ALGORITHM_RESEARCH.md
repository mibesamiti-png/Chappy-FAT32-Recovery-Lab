# Team D R8-P1 — additive root-chain and distant FAT evidence research

**Team/Issue**: Team D [#55](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/55). **Assigned branch:** `research/d-r8-additive-anomaly-evidence-20261111`. **Frozen baseline main HEAD:** `f079ac9fd476fb1e54ebe78a0e95d7560ce34a0a`, 2026-11-11.

**Safety:** Only deterministic 64KiB artificial memory streams. Real microSD and unique 31GB master IMG are not inspected, hashed, tested, uploaded, repaired or used. Local preflight remains NOT APPROVED. This is NOT a file restoration benchmark.

## R0 — published concepts, provenance, rights (completed before algorithm code)

| ID | Official primary source | Concept / failure mode | Code rights and decision |
| --- | --- | --- | --- |
| 1 | Christophe Grenier/CGSecurity TestDisk 7.2: https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html ; repository https://github.com/cgsecurity/testdisk | Primary/backup boot diagnostics, FAT plausibility; matching signatures or backups cannot demonstrate file originality. Do not use any write/repair techniques | GPL-2.0 code. **No upstream source reuse**, implementation independent |
| 2 | Brian Carrier/Sleuth Kit Labs TSK: https://github.com/sleuthkit/sleuthkit/wiki/The-Sleuth-Kit ; original https://github.com/sleuthkit/sleuthkit | Multiple forensic evidence views support uncertainty and independent cross-checking; sparse probes cannot establish unsampled FAT contents | Mixed file-specific IBM/CPL/GPL/MIT/BSD; **license review required before any source copy** |
| 3 | Microsoft FAT32 on-disk specification v1.03 (2000); format background https://github.com/libyal/libfsfat/blob/main/documentation/File%20Allocation%20Table%20%28FAT%29%20format.asciidoc | FAT chain values, 28-bit markers, EOC/reserved/bad links, mirrored sectors and cycles; tiny samples do not validate an entire filesystem | Specification rights distinct from software; no third-party code or substantial specification text copied |

These sources provide context, **not a proven published optimization for a 16+24 entry split**. This R8 quota allocation is a novel, independently implemented experiment. Repo-wide code license is undeclared; no external GPL/mixed-license files imported.

## R1 — frozen same-corpus comparison

**Original candidate APIs unchanged from baseline main**:

- R6 `Get-ChappyFatVbrMirrorCrossEvidence` with `RootWindowEntries=8`, `MaxReadBytes=160`, `MaxEntries=40`. Four copy views × (2 prefix + 8 root) entries = normally **40 entries/160 actual bytes**. Detects mirrored root cycles, no distant midpoint window.
- R7 `Get-ChappyFatStratifiedAnomalyEvidence` with `MaxReadBytes=160`, `MaxEntries=40`. Four copy views × (2 prefix + 2 root + 2 midpoint) = normally **24 entries/96 actual bytes**. Detects distant anomalies but does not track two-link root cycles.
- R8 **new research only/default OFF**, wraps both with **nontransferable** budgets: R6 `RootWindowEntries=2`, entry cap16 and byte cap64; then R7 entry cap24 and byte cap96, **40 entries/160 actual bytes** maximum when all candidates valid. All reads go to the same caller-provided non-writable Stream. Across passes overlapping prefix/root samples are reread and count toward usage; their union is **not** wrongly reported as 40 unique entries.

Global caller ceiling: `MaxEntries<=40` and `MaxReadBytes<=256`; the actual entry count remains ≤40, and full-case bytes used ≤160. For tighter quotas, integer multiples of four are assigned fairly across the 4 candidate/FAT copy views; missing root/remote evidence must be partial/unknown, never healthy. No fallback geometry searches or source selection.

**Exactly identical artificial corpus** from the already established R7 A/B test generator shape (`Run-TeamD-R7-StratifiedAB.Tests.ps1::New-D7Fixture`), re-expressed independently in R8 test. 64KiB byte buffer; FAT roots 2 and 3, four FAT base offsets 4096/4608/8192/8704, 512-byte FAT lengths, 32 artificial data clusters; identity `D55-R8-20261111`. Eight artificial cases:
1. Clean (negative).
2. Midpoint bad marker, same in both primary mirrors (positive).
3. Midpoint fake EB58 pattern (positive).
4. Root free link (positive).
5. Root two-link cycle **identical in both primary FAT mirrors** (positive).
6. Free midpoint entry, which is not inherently corrupt (negative).
7. Midpoint out-of-range link (positive).
8. Fake EB58 at FAT prefix (positive).

Ground truth means only that **a specific deliberately injected suspicious numeric FAT condition** was present; it does not mean actual files were damaged/recovered. All three methods use the **same 8 unchanged artificial inputs**, Windows PowerShell 5.1 and hard `160 bytes / 40 entries` upper cap per run. R7 can actually consume fewer bytes; the observed difference is disclosed rather than described as equal actual read cost. Synthetic SHA-256 is checked locally before/after; never exported as a real-image hash.

## R2 — independent bounded experiment

`Fat32AdditiveAnomalyEvidence.psm1` exports `Get-ChappyFatAdditiveAnomalyEvidence` on an already-open non-writable seekable Stream and two unverified geometry candidate records. It delegates to the unchanged local R6/R7 helpers with **strict preallocated subpass caps**. The sum of both real-read counters and entries counters is enforced, with zero additions to A/B/C production code, repair selection or source-write APIs.

- `experimentalDefaultOff=true`, `sourceDecision=not_selected`, `selectedCandidate=null`, `writePermitted=false` always.
- `crossEvidence=suspicious_samples_no_selection|ambiguous_samples_no_selection|insufficient_evidence`, plus `scanIncomplete`.
- Counts/root cycle observations and distant suspect counts separately; never infer unique coverage from repeated sample reads or rank VBR/mirror.
- Output has numeric bounds and fixed reason/warning codes only; not original filenames, sample bytes, source paths, or hashes.
- Negative tests include corrupted/missing/misaligned geometry, legal free cluster, identical mirror corruption, bounded short reads, tight quotas, and writable source rejection.

## R3 — measured A/B (pending exact-head Windows/Privacy CI)

The regression test `tests/Run-TeamD-R8-AdditiveAB.Tests.ps1` executes the three original/experimental APIs with independently known ground truth and measures TP/FP/FN/TN, actual bytes/entries, elapsed stopwatch time, source SHA invariance and false authenticity claims. **Do not treat predicted outcomes as measured** until the native Windows CI completes. If root-cycle handling or real quotas regress, update this document with failures and leave R8 research-only.

The expected *hypothesis* on selected tests: R8 might retain R6 root-cycle evidence and R7 distant markers within 40 combined entries, trading root-window depth for distant coverage. Does **not** cover arbitrary longer/fragmented chains, FAT ownership, every mirror region, authentic VBR geometry or original-file content.

## R4 — Team A adoption gate

No production replacement, no automatic adoption. A reviews exact-head PS5.1 and privacy CI, the R0 source/license record, A/B matrix, no false healthy/verified claims, strict source budget and missing coverage, and decides `adopt_experimental|research_only|revise|reject`. The master IMG approval gate remains **NOT APPROVED** independently of CI results.

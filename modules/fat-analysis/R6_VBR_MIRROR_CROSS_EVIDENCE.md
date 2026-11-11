# Team D R6-P1 — FAT mirror versus unverified VBR geometry cross-evidence

**Issue:** [#40](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/40). Experimental **artificial-data-only** forensic research. Team A review required. No repair, real IMG scan or extraction permitted.

## Data contract

`Fat32VbrMirrorCrossEvidence.psm1` exports `Get-ChappyFatVbrMirrorCrossEvidence`. Input is an already-open, readable, seekable **non-writable** `[System.IO.Stream]` plus an ordered pair of plain numeric VBR candidate records: `-Candidates @($r5.items[0], $r5.items[1])` is **NOT** correct; R5 returns its candidate records under `$r5.candidates`, so use `-Candidates $r5.candidates` when working with *artificial* data. The first record is interpreted as primary and second as backup. Neither is authenticated by R6. It does not import R5 or open any file/disk path.

Each record must have `plausibility='plausible_unverified'` and `geometry` numbers `fat1OffsetBytes`, `fat2OffsetBytes`, `fatLengthBytes`, `rootCluster`, `dataClusterCount`, `volumeEndExclusiveBytes`. Any upstream-contradicted geometry is **not rescued** by coincidental FAT evidence. Missing/invalid/huge or out-of-image geometry is an incomplete candidate, not a reason to probe guessed offsets.

## Hard sampling limits

- Exactly **two hypotheses × two FAT copies**. Each copy has **at most two windows**: fixed FAT entries 0–1 and a contiguous window of `RootWindowEntries` (2..8, default 4) beginning at the candidate's root cluster.
- `MaxReadBytes`: 16..256 (default 128), cumulative actual input bytes across **all four hypotheses**.
- `MaxEntries`: 4..40 (default 32), cumulative decoded 4-byte FAT entries across **all four hypotheses**.
- A fixed **per-copy entry quota** is the smaller of `floor(MaxReadBytes/16)` and `floor(MaxEntries/4)`; unused bytes/entries are not transferred between hypotheses, preventing one FAT from consuming the other's evidence budget.
- Every physical read requests at most four bytes; short reads are retried until completed or EOF. All offsets are checked against supplied FAT length, candidate cluster capacity, Int64 arithmetic overflow, volume end and stream length. No large allocations, recursion, device handle or unbounded chain walk.
- Root chain classification follows **only the sampled in-memory FAT entry map**, never additional unbudgeted I/O. Values outside the sampled window remain unresolved; a small observed cycle is flagged but the full chain is *never* presumed intact.
- FAT32 high four bits are masked; header/reserved-entry anomalies and root free/reserved/bad/out-of-range/cycle evidence are separately counted. Identical malformed FAT copies remain suspicious and **never imply healthy content**.
- R5's backup VBR location remains primary-supplied and unverified; this module does not locate or choose any replacement boot record, FAT copy, or repair destination.

## Numeric-only reports

`schemaVersion=1`, `team=D`, `status=ok|partial`, `scanIncomplete`, `writePermitted=false`, `selectedCandidate=null` and `sourceDecision='not_selected'` always.

`items` contains fixed-order primary/backup summaries with:
- Numeric geometry, `status=observed|partial|insufficient_evidence` and fixed `reasonCodes`.
- Two FAT-copy summaries with `entriesRead`, `bytesRead`, `prefixAnomalies`, `rootChainEvidence`, `anomalyCount`, `scanIncomplete` and fixed `reasonCodes`.
- `mirrors.commonEntries`, `matchingEntries`, `differentEntries`, `bothCopiesAgree`, plus explicit `comparisonDoesNotProveHealth=true`.
- `differingCandidateGeometry` fixed field-name codes.

`crossEvidence` may be `insufficient_evidence`, `ambiguous_equal_plausibility` or `observed_conflicts_no_selection`. **These are classifications of tiny numerical observations, never confidence-ranked guesses or authenticated file-health findings.** Even complete equal observations do not prove a geometry is correct, and every output forbids source selection or repair.

No paths, names, file contents, record bytes, hashes or original IMG excerpts are returned. Artificial fixture hash comparison is internal to tests only.

## Synthetic Windows PowerShell 5.1 validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R6-MirrorVbr.Tests.ps1
```

Synthetic 64KiB in-memory fixture: two independently plausible but offset-different FAT geometry candidates with two FAT copies each. Normal ambiguous pair; one-copy divergence; both mirrors equal on bad/free links; two-link FAT chain cycles; out-of-range/reserved/bad cluster; deceptive `EB 58 90` at FAT start; invalid/huge/misaligned/overlapping offsets; invalid root; invalid upstream candidate; 16/32/256 byte quota limits; two-byte fragmented stream reads; early EOF despite advertised length; writable stream rejection; SHA unchanged and private canary redaction. Dedicated Team D Windows PowerShell 5.1 and privacy CI must pass on the Draft PR head before integration.

**Uncertainty:** Synthetic FAT snapshots and selected probes are not an actual filesystem recovery benchmark. A verified exact SHA + security review + independent local-only approval gate is still mandatory before any original 31GB IMG read; this R6 module does not grant that approval.

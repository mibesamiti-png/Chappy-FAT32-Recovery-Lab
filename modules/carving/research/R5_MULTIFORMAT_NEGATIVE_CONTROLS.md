# Team C R5 — Multiformat negative controls (synthetic research only)

**Tracking:** [Issue #72](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/72), assigned branch `feature/c-r5-multiformat-negatives-20261112`. Team A continuation dispatch comment #6812023827. Frozen branch base `77743db19048c5e00601aa80e61a67ca41fdaac0`; latest main at research start `ae8c04311e938f86b19b91fe2c8962f884ced787`, one docs-only commit ahead of branch. Do not force-update previous merged #80/#86 branches. The research and baseline card was posted to Issue #72 first (comment #6812205948).

## R0 — primary sources and licensing

| Source | Principle and known limitations | Licensing treatment |
| --- | --- | --- |
| U.S. Library of Congress [Binary STL](https://www.loc.gov/preservation/digital/formats/fdd/fdd000505.shtml), 2025-02-25 | 80B arbitrary header, 4B LE facet count, 50B per triangle. No universal magic; plausible count and finite coordinates may coexist with altered original payload | Official descriptive metadata only. No reference parser, copyright text, images or source code copied; reuse of any external implementation would need separate license review |
| U.S. Library of Congress [ASCII STL](https://www.loc.gov/preservation/digital/formats/fdd/fdd000506.shtml), 2025-02-25 | `solid` plus ordered facet, normal, loop, 3 vertices and `endsolid`. A keyword alone does not prove well-formed content | Descriptive reference only; no grammar library or sample data copied. Original independent fixed one-facet test profile, not a general STL parser |
| PKWARE [ZIP APPNOTE](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) | Local `PK` signature != complete ZIP; central directory, EOCD and entry CRC are separate evidence. CRC is not a cryptographic original-file identity check | Specification-only; existing Team C ZIP/CRC validator reused, no PKWARE/PhotoRec implementation code imported |

Background: [3MF Consortium Core](https://3mf.io/spec/) and [spec repository](https://github.com/3MFConsortium/spec_core) (BSD-2-Clause repo) for OPC limits; [PhotoRec official guide](https://www.cgsecurity.org/wiki/PhotoRec_Data_Carving) (upstream TestDisk GPL-2.0 code not copied). Our test carries no external media/code assets. Project-wide redistribution license remains unconfirmed; do not assume permissive source reuse.

## R1 — frozen artificial comparison

- **Generator:** `tests/helpers/New-Chappy3DCleanFixture.ps1` from reviewed main, SHA(blob) `c08fe5c5b7806d2eb9ed05b5ca6a9ffa51a4cdba`; seed **202611**, `-IncludeFormatControls` yields a 2MiB FAT32-*like* image (NOT a mountable standard FAT32 volume). Known clean truth is held only in external synthetic test scorer.
- **Six deterministic variants:** clean; 1-bit binary STL vertex mutation; invalid binary STL triangle count 65,535; ASCII STL `endfacet` keyword damage; ordinary ZIP central-directory version-created-by metadata mutation; ordinary ZIP compressed payload mutation. The short fake `PK 03 04` signature decoy is present throughout. Each variant uses the SAME immutable bytes for existing baseline and new test-only candidate, and clean fixture data is never modified.
- **Four classification slots per case** = binary STL, ASCII STL, ordinary ZIP, PK decoy. Ground-truth structural labels are recorded outside the new helper; 24 slots total, 15 format-valid/9 invalid. Changed-but-still-structural binary/ZIP are **valid format labels** even when clean-original SHA does not match.
- **Baseline:** existing `Get-ChappyCarvingCandidates` with `-EnableSmallDeflateCrc` on an independent non-writable synthetic 65,536B scan, `MaxFileBytes=4096`, `MaxCandidates=16`, `MaxProbes=16`, `MaxProbeBytes=8192`, plus up to 32,768 source re-read bytes, 30s cooperative work limit. Baseline does not support STL.
- **Alternative (R2):** `Get-CMultiFormatEvidence` in `modules/carving/tests/R5MultiFormatNegativeResearch.ps1`, **NOT exported** from production. Independent 512B-aligned sector scan, at most 128 probes, <=65,536 source bytes, <=16 candidate records, <=32,768 *separate in-memory validator* read bytes, <=30s. Binary STL narrowed to printable/NUL header, 1–8 facets, zero attributes and finite floats; ASCII narrowed to precisely one complete facet and matching `solid`/`endsolid` name. ZIP reuses existing C bounded CRC validation on one local 512B sector. Partial/over-cap results return `incomplete` without candidate selection.
- **Remaining assumptions / high FN risks:** alignment to 512B sectors, one-sector file for plain ZIP, first sector has complete binary/ASCII STL, binary arbitrary headers may be rejected, binary attribute extensions excluded, ASCII multiple facets/whitespace variants rejected, and all ZIP entries' meaningful validation must fit C's current bounded parser. The method cannot reconstruct fragmented originals or fully validate 3MF OPC/XML/vendor extensions.
- **Fairness:** both algorithms see identical artificial fixture bytes and a shared outer 98,304B per-case source cap; baseline may use named 32,768B rereads, alternative restricts physical source to 65,536B but separately counts in-memory validator work. Their probes/operation costs are NOT identical, so do not claim like-for-like runtime speedup.

## R3 — actual observed A/B (initial exact-code-head CI)

Windows PowerShell 5.1 Team C [Actions #43139759850](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43139759850), initial code HEAD `3c0a3e3c7e60ece4f41001c266c73aaa2a4a82b3`, PASS; privacy [#43139759851](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43139759851), PASS. Results below are actual logs. **Final documentation HEAD CI is separately required before integration.**

| Metric; 6 invented cases × 4 slot types | Existing ZIP/G-code carver | Research-only STL/ZIP guard |
| --- | ---: | ---: |
| Structural true positives TP | 5 | **15** |
| Structural false positives FP | 0 | **0** |
| Structural false negatives FN | 10 (STL unsupported) | **0** |
| Structural true negatives TN | 9 | **9** |
| Structural precision, selected slots | 5/5 | **15/15** |
| Structural recall, selected slots | 5/15 | **15/15** |
| Format-accepted candidates matching original artificial SHA | Not separately scored | **13** |
| Format-accepted but clean-original SHA differs | Not separately scored | **2** (binary vertex, ZIP metadata) |
| False claims of verified original bytes | **0** | **0** |
| Actual physical source Stream.Read bytes / six cases | **470,238 B** | **393,216 B** |
| Separate in-memory C validator reads | Included in physical baseline bytes | **18,858 B** |
| Actual source read requests | **192** | **768** (one per sampled sector) |
| 512B sampled sectors | Signature scanner, not comparable | **768** |
| ZIP signature attempts rejected in alternative | Not measured in identical units | **13** |

An exact, fully structural STL still has no originality proof. The two format-accepted modified cases are proof that format validity cannot be promoted to original SHA identity. The positive/negative matrix is narrowly selected, not a real-world file recovery rate. More read calls in the alternative and per-format constraints can harm general accuracy outside these toy fixtures; no CPU or memory peak is claimed where not reliably measured.

**Negative fail-closed controls:** damaged triangle count, broken ASCII grammar, compressed ZIP payload corruption, fake PK signature, writable stream rejection, 1KiB read budget, truncated image and one-candidate cap; no stale prior results cherry-picked. Input image SHA-256 before/after every run identical. The detector receives neither known original SHA nor true oracle file extents; only external scorer accesses them.

## R4 — Team A proposal

**`research_only`**. Prototype demonstrates one constrained artificial STL/ZIP format discriminator and negative integrity boundaries, but does not justify automatic STL recovery, full OPC/XML validation, format-agnostic carving or original-byte verification. Production `modules/carving/Chappy.Carving.psm1` unchanged and optional export never called. Request Team A review after **final exact-head** Windows C and privacy CI, and leave Issue #72 open for additional signed-off format/fragment scope.

**Safety:** physical microSD and sole 31GB master IMG not read, hashed, copied, scanned, written, repaired, extracted, transferred or uploaded. No actual user filenames, recovered files or raw logs. Local real-media gate **NOT APPROVED**.
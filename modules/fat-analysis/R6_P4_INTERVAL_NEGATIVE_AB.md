# Team D R6-P4 — adversarial read-span provenance negative controls

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #94](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/94), A-assigned branch `research/d-r6-interval-provenance-negatives-20261112`. Accepted frozen baseline `main 4a9b9151c6f6c23d9a88685b7487f206c38ce0e9`; latest main verified at work start `32fb0e9a3e36401435113375e092cae327bd147c`. Team D's opt-in read-provenance module from merged PR #90 stays **unchanged/default OFF**.

## R0 — primary research and license exclusions

Posted source/license note to Issue #73 (comment `6812878015`) **before editing code**. No upstream code copied.

| Prior method / source | Relevant independent reasoning | License status |
| --- | --- | --- |
| Microsoft Corporation, FAT32 File System Specification v1.03 (2000): https://www.osdever.net/documents/fatgen103.pdf | BPB/FAT numeric geometry and mirror rules cannot by themselves authenticate recovered original files; observed-byte range is not owner provenance | Specification publication/copyright not a permissive source license; no source/text copied, rights review required for reuse |
| Christophe Grenier / CGSecurity, TestDisk official filesystem repair guide https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Primary/backup boot and FAT copies provide separate evidence but no automatic repair or selecting a winner | GPL-2.0 source; no copying/imported code/execution |
| Brian Carrier / Sleuth Kit Labs https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Forensic source observations are partial; unsupported ownership/recovery inferences must remain unknown | Mixed component licenses, `license_review_required`, no copying/import |

## R1 — frozen fair artificial benchmark

- Existing unchanged D method: `Get-ChappyFatObservedIoEvidence` from merged PR #90. Its `MirrorOnly` and `MirrorAndChain` modes share the original 2,048-byte maximum physical source budget and fixed probe starts 2..8; no dynamic traversal. This P4 is **only a test of edge behavior**, not a production algorithm change.
- A synthetic fixture helper `tests/helpers/New-Chappy3DDamagedFixture.ps1`, seed **202611**, invented 2MiB *FAT32-like* image. Cases M00, M02, M03, X02, and scorer-only mutation of the M00 artificial BPB bytes/cluster to zero; independent synthetic Stream with one-byte chunks and stop at 1,200 actual bytes; separate budgets 32 and 1,050.
- Each candidate receives **only** generated non-writable seekable Stream, fixed mode and source byte cap. Its caller does **not** pass the case label, original hash, inserted BPB location, file owner, original file extent or damage truth. External test scorer alone maintains the input SHA, labels and true source-read positions. It wraps underlying source in an independent non-writable physical-read observer.
- **Binary score is solely duplicate-read accounting:** positive means *actual repeated physical bytes were independently observed*; negative means no repeat. The deliberately naïve baseline assumes every successfully read byte is unique and therefore never signals duplication; the candidate flags only its observed `duplicatePhysicalBytes`. A separate independent HashSet of **actual underlying offsets returned** provides the truth used for both; no file recovery truth leaks into either method. Compare identical generated input/mode/cap for both counting rules.
- A/B reported units: TP/FP/FN/TN of physically repeated byte detection; actual source bytes returned, distinct physical union, repeated bytes, instrumented Read() calls, phase provenance, unknown due to truncation/geometry and timed run if practical. Do **not** equate this metric with FAT corruption or authentic recovered data. An unknown file/geometry is never treated as a negative.
- Caps: max 2,048 source bytes per run, 32 or 1,050 for hard-cap negatives, no more than seven fixed probes; module source read-only, no path, output or writer.

## R2 — independent negative oracle and stage provenance checks

`tests/Run-TeamD-R6-IntervalNegatives.Tests.ps1` builds a second C# observer around the generated memory stream. It independently counts actual returned source bytes, the union of distinct physical byte offsets and underlying Read() call count. A separate scorer independently rebuilds the interval union from D read events and cross-checks all four totals and the sorted disjoint output ranges. It checks each per-stage sum, stable event IDs, valid numeric FAT-copy regions and source bounds.

Negative controls require that a matching corrupt FAT1/FAT2 (M03) does not become an authenticated healthy image; X02 shortened payload geometry is never considered a complete original; invalid synthetic BPB is not promoted; unexpected zero before advertised source Length and exhausted budgets remain `partial`. Every trace remains numeric and fixed-code only, with no file-owner, original SHA or repair-winner fields. Artificial input hash is checked before and after every run.

**Research-only acceptance:** if the existing D module fails a safety invariant, keep the failing test and propose a small D-owned correction; never change synthetic labels or source oracle to manufacture a PASS. Stage R3 results and exact-head Windows/Privacy CI: **pending at documentation creation**.

## R3 — measured A/B evidence

| Criterion | Naïve sum-as-unique baseline | Existing #90 observed-unique union candidate | Notes |
| --- | ---: | ---: | --- |
| Duplicate-read TP/FP/FN/TN | pending | pending | Independent physical read-offset oracle, not file recovery |
| Bytes physically returned | pending | pending | Same runs, not separate work |
| Distinct/duplicate bytes and Read() calls | pending | pending | Independently counted |
| Incomplete/unknown runs | pending | pending | Early zero, clipping, malformed/out-of-volume geometry |
| False FAT-owner/copy selection/verified original | pending | pending | Must remain zero |
| Input SHA identical | pending | pending | Synthetic only |
| Windows PowerShell 5.1 exact HEAD | pending | pending | Includes previous D suites |
| Privacy gate exact HEAD | pending | pending | Not a security audit |

## R4 — Team A decision

Request **research_only** if measured negative controls pass and no production fix is needed. A alone decides merge, disposition and whether the source-origin convention can feed its R7 adapter. Numeric physical FAT read ranges establish **only observed source bytes**. They do not establish original file identity, cross-file owner authenticity, whole-FAT completeness, selected mirror correctness or permission to repair. Neither physical microSD nor unique ~31GB master IMG is read, hashed, copied, written, exported, uploaded or repaired; real-media approval remains **NOT APPROVED**.

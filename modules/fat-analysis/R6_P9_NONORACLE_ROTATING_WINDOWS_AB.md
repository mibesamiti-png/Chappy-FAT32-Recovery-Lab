# Team D R6-P9 — three-seed non-oracle rotating FAT windows (research_only)

**GitHub:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #122](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/122). A assigned branch `research/d-r6-nonoracle-rotating-windows-20261112` at reviewed main `6a2049d18a05c53a57987a8efe3ee9982a1a093b`; newer main `2011fbd19f4fede078c16af50b640d45dc81ea92` at kickoff. Prior D #117 was merged **research_only**, not reimplemented.

## R0 — prior published algorithms and reuse risks

The [full study pre-registration, including sources/licenses, fixed baseline, exact schedule formula, thresholds, cases, and scoring](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6823139551) was recorded **BEFORE implementation**.

- Microsoft Corporation, *FAT32 File System Specification v1.03* (2000), reference archive https://www.osdever.net/documents/fatgen103.pdf: FAT position/mirror layout and structural constraints; sample equality cannot authenticate an unread entry or an original file. Copyrighted publication, **no text or code copied**; no implied code license.
- Christophe Grenier / CGSecurity, TestDisk official repair discussion https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and official source https://github.com/cgsecurity/testdisk: competing mirror/boot hypotheses without automatic copying or repair. GPL-2.0 code, **none copied**, license review required before potential reuse.
- Brian Carrier / Sleuth Kit Labs https://github.com/sleuthkit/sleuthkit with license notices https://www.sleuthkit.org/sleuthkit/licenses.php: forensic evidence requires source provenance and explicit coverage. Component licenses **mixed**; no source copied/imported and reuse requires review.

This test-only rotating schedule is an independently written composition of **existing in-repository** FAT32 geometry, mirrored-window and chain-observation functions; it does not implement or redistribute third-party source.

## R1 — same artificial corpus, truth isolated, resource contract

**Existing baseline:** D P8 previously accepted **research-only** fixed three 16-entry FAT windows `[0,128,256]`, plus generic FAT1/FAT2 chain starts 2..8.

**One alternative:** deterministic **non-oracle rotating three-window** schedule frozen as:

```text
fatEntries = floor(fatLengthBytes / 4)
geomSalt = floor(fat1OffsetBytes / 512) + floor(fatLengthBytes / 512)
windowStarts = [
  0,
  64 + 16 * ((publicSeed * 37 + geomSalt) % 22),
  416 + 16 * ((publicSeed * 17 + fatEntries) % 72)
]
```

The only variables provided to the optional analyzer are its **strictly non-writable seekable Stream**, fixed public rotation seed and `fixed|rotate` mode. Numeric FAT geometry is read using the existing untrusted BPB parser; **no original SHA, scorer labels, planted mutation positions or candidate-owner truth enter the scheduler.** A malformed/undersized geometry produces incomplete/unknown rather than an invented valid FAT. Every fixed/candidate sample consists of **exactly three 16-entry windows** when geometry is sufficient.

For **each** independent method/case: physical source `Read()` strict cap of **2,048 actually returned bytes and 256 calls**, applied across all phases with no reset, consisting of up to 1,024B geometry, 3×128B mirror and 448B chain nominal 1,856B. An independent nonwritable, read-only source-meter counts actual returned physical source bytes, distinct offsets, re-reads and physical calls. Both schedules share the **same upper limits** but not necessarily identical latency.

Test vectors: three public synthetic fixture seeds **202611/202612/202613**, A `tests/helpers/New-Chappy3DDamagedFixture.ps1` blob `58fedb62d76f15ebb003e4440d5f9c90feba25c5` generating **2MiB FAT32-like, not standards-sized FAT32 volumes**. Cases M00 clean, M01 legal nonadjacent fragmentation, M02 FAT1-only broken link, M03 same-corrupt-mirror cycle, M05 impossible-to-prove FAT-only cross-file owner, X02 source truncation. Scorer-only clones place marker 1 in FAT2 entries128/256/512/768/3000, and FAT2 cluster4→8 when FAT1 cluster4→5→EOC (both paths EOC); separate malformed BPB, 1200-byte early physical EOF with 7-byte return chunks and 32-byte cap. Original input SHA and case truth remain in the **external artificial scorer**.

**Binary FAT anomaly label contract:** per-seed 8 scored cases (M00/M01 negative; M02/M03/CONFLICT/REMOTE128/REMOTE256/REMOTE512 positive), **24 selected cases (18 positives, 6 negatives)** across three seeds. **7 unscored cases per seed / 21 UNKNOWN:** REMOTE768 and REMOTE3000 out-of-window witnesses, M05 owner ambiguity, X02 truncation, short EOF, 32-byte quota, invalid BPB. They are NOT TN or recovered/original-file success.

## R2 — reviewable test-only candidate

Added one D-only `modules/fat-analysis/tests/Run-TeamD-R6-NonoracleRotatingWindows.Tests.ps1` and one D-only native Windows PowerShell 5.1 workflow step; no change to existing D production modules or default, A shared I/O meter, B/C, or common interface. The test derives the windows from *numeric* geometry and public seed only; synthetic mutation labels/offsets are held exclusively in scorer and used **after each observation** for evaluation. All methods forbid writable streams.

All reports keep `scanIncomplete=true`, `fullFatVerified=false`, `fatWinner=not_selected`, `fileOwner=unknown`, `originalIdentity=unknown`, `writePermitted=false`. Observed local mirror mismatch or cycle is **not a full FAT-copy authenticity proof** or file-byte identity.

## R3 — actual native Windows synthetic A/B findings

**During code development:** native Windows PowerShell 5.1 on commit `754485d24bd35cce37495e6b2d33dbf0a421506f` completed all **414 assertions PASS** and emitted the physical source totals and scores. Its **process exit was 1 due exclusively to a test-harness variable shadowing bug**: `[byte[]]$bad` overwrote `$script:bad` fail counter; source code, truth, labels and all observations were unchanged when renamed `$invalidBpbBytes` on subsequent commit `8843f99735eecb6404a37174a9160bd466232ea6`. A corrected-head clean CI **must** be independently verified; no earlier failed run is represented as CI-success.

| Exactly 24 selected artificial FAT-anomaly cases | Existing fixed 0/128/256 | Non-oracle rotating |
| --- | ---: | ---: |
| TP | **15** | **11** |
| FP | **0** | **0** |
| FN | **3** | **7** |
| TN | **6** | **6** |
| Recall on selected anomalies | 15/18 = **83.33%** | 11/18 = **61.11%** |
| Unscored UNKNOWN (different original-file/coverage question) | **21** | **21** |
| Original-content byte-identical recovery | not evaluated | not evaluated |

**Per-seed detected positives out of six planted/scored abnormal cases:** fixed **5/5/5**, rotating **4/3/4**. Deterministic *non-oracle* schedules actually selected:

| Seed | Existing fixed windows | Rotating windows |
| --- | --- | --- |
| 202611 | 0 / 128 / 256 | **0 / 128 / 1360** |
| 202612 | 0 / 128 / 256 | **0 / 368 / 480** |
| 202613 | 0 / 128 / 256 | **0 / 256 / 752** |

The fixed schedule always misses the planted entry512 on selected positives. The rotating schedule observes 128 for seed202611 and 256 for seed202613 but **fails to see several other planted positions**, including entry512 in every seed. Both deliberately miss FAT2 entry3000; those cases are scored **UNKNOWN**, not healthy. M03 common-mode dual FAT cyclic links are detected by both via bounded chain tracing, with no preferred mirror/copy/repair decision. Cross-file ownership remains unknowable without independent directory evidence.

**Source-side physical read resource totals** over **45 artificial cases per method** (90 independent strict nonwritable Stream observations):

| Measurement | Fixed | Rotating |
| --- | ---: | ---: |
| Actually returned physical source bytes | **59,772** | **59,772** |
| Source-local unique physical byte positions (sum per invocation) | **57,456** | **57,456** |
| Repeated bytes | **2,316** | **2,316** |
| Physical `Read()` calls | **1,458** | **1,458** |
| Max per individual method/case | 2,048 B / 256 calls | 2,048 B / 256 calls |
| FAT mirror coverage on fully sampled healthy synthetic case | **48/5,120 = 0.9375%** | **48/5,120 = 0.9375%** |
| FAT mirror entries not compared | **99.0625%** | **99.0625%** |
| CPU-speed or peak-memory superiority | not established | not established |

The unique sums are **summed per invocation**, NOT one physical 31GB image or a union across independent sources. These are non-representative artificial cases; even 414 passing assertions are not a real recovery success rate. The deterministic sequence and only 3 seeds can overfit any synthetic selection of planted locations; rotational diversity alone does **not** establish improvement.

## R4 — findings and A review

**Conclusion / recommendation: `research_only`, no production/default switch.** The frozen non-oracle schedule performed **worse on the pre-registered 24-case artificial corpus** at equal byte and physical request counts. No retuning of windows based on post-hoc observed corruption was attempted. This disproves any claim that rotation automatically beats the earlier fixed schedule; it does not prove fixed sampling will dominate on arbitrary real FAT distributions.

A should review the program's independence from scorer truth, physical hard caps, source location coverage, and whether future P1 requires **independently generated larger standards-shaped FAT32 volumes** and a seed schedule selected without planted positions. A continues to own candidate/source receipt integration and the R7 proof boundary. The R6 Issue stays OPEN for wider FAT coverage and independent cross-link owners. R8 real export remains blocked.

**Safety:** physical microSD and unique ~31GB master IMG never opened, read, hashed, copied, scanned, uploaded, written, exported, repaired or accessed; strictly generated in-memory streams only. Real-data approval remains **NOT APPROVED**.

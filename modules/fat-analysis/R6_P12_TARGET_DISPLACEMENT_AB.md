# Team D R6-P12 — adaptive FAT target displacement sweep

**Tracking:** Issue [#73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), preregistration comments [#6827712530](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6827712530) and count correction [#6827924511](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73#issuecomment-6827924511). New branch: `research/d-r6-p12-target-displacement-20261113`. This is an artificial, test-only analysis; it changes no production sampling API and does not authorize real-media work.

## R0 — sources, provenance and rights

| Source | Relevance and limit | License / reuse |
| --- | --- | --- |
| Microsoft Corporation, *FAT32 File System Specification* v1.03 (2000), https://www.osdever.net/documents/fatgen103.pdf | Defines numeric FAT32 links and geometry. A finite sample can establish only which complete entries were observed. | Copyrighted specification, not a source-code license. No text/code copied. |
| Christophe Grenier / CGSecurity, TestDisk 7.2 repair documentation, https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | FAT and backup evidence context; an observed link does not establish an authentic file owner or authorize a repair. | GPL-2.0 upstream. No code copied, executed or added as a dependency. |
| Sleuth Kit Labs, The Sleuth Kit and license inventory, https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Independent forensic views help expose uncertainty, while finite sampling leaves the rest unknown. | Mixed component licenses; file-level review required before any reuse. No code copied or dependency added. |

These sources inform evidence limits, not an optimal adaptive sampling algorithm. P12 measures the independently authored P11 test-only schedule; it does not propose a new production algorithm.

## R1 — frozen baseline and held-out cases

- Frozen main: `c94106c5e2053863ac210e5a8463aff554641b2e`, after the A-reviewed merge of D PR #132. The earlier `research/d-r6-adaptive-fat-coverage-20261112` branch remains preserved.
- Fixture blob `tests/helpers/New-ChappyA3DStandardFixture.ps1`: `6e90e3c1b063ced7a9685f8b20c1437a66527405`.
- Tested D blobs: `Fat32GeometryTrust.psm1` `fbfe8f6d7d34bbe7cc67fd1ccd6ec9ac0973e25b`; `Fat32MirrorWindows.psm1` `2e9b0864ecc15d98bdeaa76a19167d3bbcde4555`; `Fat32ChainStats.psm1` `77b550ef0c5dd5ef3ff1aeaf498ecac20a0cd933`; P11 test sampler `94e47282d77c94b9015a08ddfac5412a0bd06be7`.
- Fixed comparator is P11's unchanged test-only schedule: geometry parse, 16-entry mirrored FAT windows at 0/128/256, and bounded chain starts 2..8.
- Adaptive comparator is P11's unchanged rule: after a complete physical prefix at 0, use the first matching in-range observed link from paired indices 9..15 as the next window start, then sample 0/target/128; otherwise fall back to 0/128/256. It receives no scorer index, target coordinate, seed or image hash.
- Held-out seeds: 202614, 202615, 202616; SPC1 generated standards-shaped FAT32. Ten target starts per seed: 128, 143, 144, 255, 256, 257, 271, 272, 320 and 512. Each target case uses an equal observed FAT1/FAT2 link at entry14, a FAT2 mismatch at the target, and a second mismatch at 256 except when target is 256. Separate controls: a healthy equal link at 512 and a no-link fallback with a mismatch at 256.
- The original registration stated 33 images/66 runs; comment #6827924511 corrects this transcription count before CI/PR: the two separately labeled controls make **36 images/72 runs**. Seeds, positions, limits and scoring remain frozen.
- Per-method limits: geometry cap 1024 bytes; up to 384 bytes for three 16-entry mirror windows; up to 448 bytes for chain observations; maximum 2048 returned bytes, 256 read calls and 120000-byte outer cap. Every run uses a read-only artificial memory stream.
- Scorer counts an event as observed only when both copies' complete four-byte entry was physically returned and the corresponding sampled window reported a mismatch. It separately scores the target and displaced index256 event. It does not score file integrity; every original file identity remains UNKNOWN.

## R2/R3 — implementation and observed Windows PowerShell 5.1 results

`modules/fat-analysis/tests/Run-TeamD-R6-TargetDisplacement.Tests.ps1` is the only added sampler-related code. It uses the existing D modules and a physical-read meter to verify each event against actual returned source offsets. No D production module or shared A/B/C file changes.

Local Windows PowerShell 5.1 run: **351/351 assertions passed**. All 36 generated source arrays had identical SHA-256 before and after both methods. The script logs each per-case before/after hash and the fixed/adaptive event windows.

| Event observation | Fixed 0/128/256 | Adaptive 0/target/128 |
| --- | ---: | ---: |
| Target disagreement observed | 15/30 | 30/30 |
| Separate index256 disagreement observed | 27/27 | 3/27 |
| No-link fallback index256 controls observed | 3/3 | 3/3 |
| Healthy-link false disagreement | 0/3 | 0/3 |
| Event-level TP / FP / FN / TN | 45 / 0 / 15 / 3 | 36 / 0 / 24 / 3 |

The adaptive target window captured every planted target disagreement. Its overlap with the fixed 256 window preserved the second event only for target start 255; target 256 is the same event, not an independent displaced event. Elsewhere it displaced that fixed window. Across the preregistered positive events this produced **9 fewer** paired-event observations than the fixed schedule. The result explains the displacement cost for this finite position set; it is not a general FAT detection rate.

| Resource sum over 36 independent source runs per method | Fixed | Adaptive |
| --- | ---: | ---: |
| Actual returned bytes | 52,992 | 52,992 |
| Source-local unique bytes summed | 50,688 | 50,280 |
| Repeated returned bytes | 2,304 | 2,712 |
| Read calls | 864 | 864 |
| Source-local paired FAT entries summed | 1,728 | 1,677 |
| Illustrative elapsed time | 725 ms | 473 ms |

Elapsed time is a single local run, not a controlled speed benchmark. Source-local unique and paired sums are added per independent image; they are not a cross-image union. Normal geometry declares 65,664 FAT entries. Per source, fixed sampling observed 48 paired entries (0.0731%). Adaptive observed 32 entries at target128, 47 at target143 due overlap, and 48 on the other tested positions. The unsampled FAT remains UNKNOWN.

## R4 recommendation and limits

Request **`research_only`**. The sweep shows adaptive placement's benefit and displacement cost under identical actual I/O; it does not show aggregate improvement over the fixed schedule in these held-out positions. Keep the production behavior unchanged and default OFF. A must review the exact-head D Windows PowerShell 5.1 and privacy CI before deciding.

The study covers three invented seeds, one cluster geometry and selected link positions. It cannot establish a general detection probability, FAT-copy health, original file identity, authentic ownership or recovery success. No user image, microSD, file name or private data was accessed. No repair, output or write occurred. Real-data approval remains `NOT APPROVED`.

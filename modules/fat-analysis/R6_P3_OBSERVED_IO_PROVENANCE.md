# Team D R6 P3 — actually observed FAT source-read provenance (research-only)

**Tracking:** [Issue #73](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/issues/73), [Draft PR #90](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/pull/90), assigned branch `research/d-r6-observed-io-evidence-20261112`. A pinned dispatch baseline `77743db19048c5e00601aa80e61a67ca41fdaac0`; latest main inspected at R0/R1 `ae8c04311e938f86b19b91fe2c8962f884ced787`. The assigned branch was 0 ahead/1 behind latest main at start because it predates a separate A commit. No B/C/A source was edited.

## R0 — first-party prior art, ownership and licenses

The R0/R1 checkpoint was posted on Issue #73 **before editing code**.

| Approach, original source and attribution | What applies / what does not | Licensing/reuse |
| --- | --- | --- |
| Microsoft Corporation, FAT32 File System Specification v1.03 (2000), publicly mirrored https://www.osdever.net/documents/fatgen103.pdf | FAT32 numerical BPB and FAT-link positions, 28-bit link semantics, untrusted geometry. No source-read telemetry or original-content proof follows from FAT format rules alone. | Specification copyright is separate from software license. No text/code copied; verbatim reuse requires review |
| Christophe Grenier / CGSecurity, TestDisk boot/FAT repair docs https://www.cgsecurity.org/testdisk_doc/repairing_filesystem.html and https://github.com/cgsecurity/testdisk | Primary/backup boot and FAT copy evidence must be distinguished from any repaired or selected source. Its repair/writer actions are explicitly excluded. | TestDisk GPL-2.0 source; no imported/copied code or binaries |
| Brian Carrier / Sleuth Kit Labs, https://github.com/sleuthkit/sleuthkit and https://www.sleuthkit.org/sleuthkit/licenses.php | Forensic observations can be linked to exact source coordinates; missing observations and duplicate reads cannot certify full source integrity. | Mixed per-file licenses, license_review_required for copying; no third-party source copied |

All implementation code is independently authored and calls only **existing** Team D functions. No dependency or inherited third-party implementation.

## R1 — frozen artificial input, baseline and fairness

- Generated **2MiB FAT32-like** (not standards-sized FAT32) fixture `tests/helpers/New-Chappy3DDamagedFixture.ps1`, deterministic seed **202611**; case IDs M00 clean, M01 valid fragmentation, M02 one FAT-copy link broken, M03 identical two-FAT cycle, X02 truncated payload/declared volume. The external scorer owns true case labels, manifest and synthetic original SHA256.
- Test subject gets **only** a readable, seekable and strictly non-writable Stream; it derives numeric FAT offsets via existing `Get-ChappyFatGeometryTrust` and uses fixed cluster start indices **2..8**. The algorithm never gets the scorer's case ID, manifest, original SHA, file owners, mutated offsets or recovered payloads.
- Both modes have the same global **2,048 actual source bytes** hard upper bound, enforced by one stream wrapper covering the entire invocation rather than adding multiple independent source budgets. The baseline mode uses up to 1,024 bytes for geometry and 1,024 for one 128-entry mirrored FAT window. Candidate mode uses the same geometry budget, one 64-entry mirror window capped at 512 bytes, and 7 fixed starts each capped at 64 bytes = at most **1,984 bytes** under the 2,048 hard ceiling. Results disclose that actual work differs.
- No speed or memory advantage is claimed from comparable upper byte bounds alone. The stage-specific caps are **not** asserted to be equivalent work, and probes may repeat physical offsets.

## R2 — one independent default-off experiment

New `Fat32ObservedIoEvidence.psm1` exports `Get-ChappyFatObservedIoEvidence -Stream -Mode MirrorOnly|MirrorAndChain -MaxReadBytes` (32..2048, default 2048; default MirrorOnly). It does not change the existing geometry, mirror or chain implementations and does not open a path, device, writer or output file.

A small internally-created non-writable instrumentation Stream wraps a pre-opened non-writable input. It:

- Enforces the **single global actual-returned-byte cap** even when one phase or existing analyzer tries to request additional bytes; never resets its global counter between phases.
- Captures a numeric evidence ID and **[offsetBytes, endExclusiveBytes)** for each *successful underlying Read()*, the exact returned-byte count and phase provenance (`geometry`, `mirror_window_0`, or one of `chain_probe_2` through `chain_probe_8`). Reports a FAT copy index only when an observed range is contained entirely in its *unverified* numeric FAT region.
- Computes the true non-overlapping **uniqueReadRanges** union from *physically returned bytes*, not intended scan targets. `duplicatePhysicalBytes = bytesRead - uniquePhysicalBytes` is arithmetic over actual events. Also reports Read() call count, phase byte counts, global/phase cap clipping, and zero returned before advertised source length.
- Preserves numeric-only geometry rejection and incomplete/partial indicators; a legitimate partial FAT sample stays incomplete rather than `verified`. Never selects the authentic FAT or certifies original file content, ownership or file boundaries.

**R7 adapter request to Team A:** Version or formally review the source-coordinate convention, phase/evidence IDs, and per-source identity before joining spans across B/C/D modules. An interval is a **physically observed read**, not a claim that the offset belongs to a verified user file, nor independent corroboration of repeated read bytes. A cross-module union must dedupe identical physical source bytes and share one bounded source budget; counting independent module `bytesRead` sums as unique evidence is wrong. The Team D module does not change the A adapter.

## R3 — executed Windows PowerShell 5.1 synthetic A/B results

The first code-head Windows run [#43139668290](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43139668290) **SUCCESS**, dedicated new R6-P3 test **139/139 assertions PASS** and existing Team D steps PASS. First code-head [privacy + isolated synthetic regression #43139668299](https://github.com/mibesamiti-png/Chappy-FAT32-Recovery-Lab/actions/runs/43139668299) success check is reported separately in PR after final-head verification; do not treat an in-progress run as passed.

Only four of five selected cases are scored for observed mirror-mismatch/cycle; **X02 payload EOF is excluded as unknown**, not treated as a FAT negative or recovered file. Test selection is not a real-world recovery sample.

| Measurement on identical artificial fixture inputs | MirrorOnly baseline | MirrorAndChain candidate |
| --- | ---: | ---: |
| TP / FP / FN / TN, four scorable cases | **1 / 0 / 1 / 2** | **2 / 0 / 0 / 2** |
| Precision / recall, selected artificial labels | 100% / 50% | 100% / 100% |
| Unscored unknown cases | 1 (X02) | 1 (X02) |
| Total actual returned bytes across five | **10,240** | **8,004** |
| Physical unique bytes across five | **10,240** | **7,680** |
| Duplicate byte reads | 0 | **324** |
| Stream Read() requests | **20** | **101** |
| False authentic-FAT selection, original-file verification, writer | 0 | **0** |
| Synthetic input unchanged after paired runs | **5/5** | **5/5** |
| Original file reconstructed and byte-identical | not applicable | **not applicable** |
| Repeatable CPU or peak-memory benchmark | not measured | not measured |

**Case observations:** M00 M01 show no observed mirror mismatch/cycle; M01's valid nonadjacent fragmentation is not misidentified as a cycle. M02 has one observed FAT-copy mismatch. M03 has both mirrors agreeing and four observed cycle terminations. X02's geometry rejects declared volume extending beyond source length while FAT samples agree; file payload correctness remains **unknown**.

**Negative controls:** a source advertising more bytes than it returns stopped after **1,150 actual returned bytes** and was recorded partial/unknown; 7-byte-fragmented stream still preserved cycles and counted actual bytes; an input capped at 1,050 bytes and another capped at 32 bytes never exceeded the global cap; a writable input was rejected. Synthetic source SHA matched before/after. The module never returns source hashes or byte content.

**Interpretation:** fewer actual bytes but **more I/O calls** in the experimental candidate (101 vs 20 on five inputs). This is not proof of faster execution, superior reliability or restored-file integrity. It is strictly evidence provenance research to inform A's candidate adapter.

## R4 — Team A disposition requested

Recommendation: **research_only**, leaving every production/default FAT analyzer untouched. Request A independently inspect per-phase attribution, numeric offset privacy, union accuracy, cap enforcement and negative cases before choosing `adopt_experimental`, `research_only`, `revise` or `reject`. A alone decides and merges. The local real-image approval remains **NOT APPROVED**. No physical microSD or sole 31GB IMG accessed/read/hashed/copied/written/repaired/uploaded.

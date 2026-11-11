# Team D R3-P2 — EB-58 contiguous-pattern and offset hypotheses

**Status:** research / Draft PR. Read-only, synthetic CI only. No real IMG was inspected.

## Scope
- `Fat32Eb58Map.psm1`: `Get-ChappyFatEb58Map` uses a *non-writable*, readable, seekable `System.IO.Stream` plus caller-supplied volume/FAT offsets and declared FAT size. No disk or file-path APIs, no repair calls, no writes.
- Recognizes **at least `MinRunPairs` contiguous `EB 58` byte pairs** in the sampled bytes, including runs crossing 4,096-byte internal I/O boundaries, 4-byte entry alignments, 512-byte sector boundaries, and odd byte offsets.
- Returns observed start/end offsets (exclusive), pair counts, the modulo-4 and modulo-512 alignment, runs at the supplied FAT start, and counts of records omitted due to report caps.
- Detects `EB 58 90` jump-like prefix separately; when the FAT sample has both that prefix and `55 AA` at +510, emits a **VBR-like combination hypothesis only**. Neither signal proves boot-sector duplication, offset error, or device damage.
- Probes a candidate volume boot sector for signature and *plausible* FAT32 BPB geometry, and compares the derived FAT starts and FAT length against caller-provided values. BPB plausibility is not forensic authenticity.
- Emits only numeric aggregates, ranges, fixed evidence codes and flags. No raw samples, hashes, local source paths, actual private filenames or directory contents.

## Bounds and incomplete scanning
- `-ProbeBytesPerFat`: 32..65536, default 4096.
- `-MaxReadBytes`: combined volume-boot + both FAT sample budget 512..131584, default 8704.
- `-MinRunPairs`: 2..128, default 4.
- `-MaxReportedRunsPerFat`: 1..64, default 32.
- Individual read calls are at most 4096 bytes; all sample allocations are at most 65536 bytes.
- FAT samples receive equal allocated quotas after the (bounded) volume boot read.
- `items[].observedBytes` and `metrics.bytesRead` use bytes actually returned, not bytes declared or requested.
- A run reaching the sampled end is only an **observed prefix** of a potentially longer run; `reachesObservedEnd` records that uncertainty.
- Partial FAT coverage, truncated streams and capped run reporting set `scanIncomplete=true`; `status=ok` means only the *declared sampled full FAT regions* were all read and reported, not that they are healthy.
- Only caller-supplied two-FAT geometry is used, and offsets may themselves be wrong. The code refuses overflowing, overlapping and unaligned FAT ranges.

## Evidence interpretation
- `fat.eb58_repeated_region_observed`: a matching sequence appears in the sampled region. This is not alone proof of corruption.
- `fat.eb58_at_supplied_start`: run touches a user-supplied FAT start. That offset must be verified independently.
- `fat.vbr_like_combination_observed`: VBR-like prefix and trailing sector signature both observed in one FAT sample; could also be coincidence or a misleading offset.
- `geometry.supplied_offsets_disagree_with_bpb`: candidate BPB geometry disagrees with supplied FAT ranges. Candidate BPB itself may be wrong.
- `pattern.both_mirrors_have_start_pattern`: identical anomalies can affect both copies; agreement does not establish integrity.
- An unmatched or absent EB58 run in bounded sampling **does not** prove clean FAT contents elsewhere.

## Synthetic Windows PowerShell 5.1 test
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R3-Eb58.Tests.ps1
```
Tests exercise a plausible boot sector, repeated FAT-start patterns, sector-aligned and odd-offset runs, misleading offsets, a VBR copied to the FAT start, full and sparse coverage, 4096-byte boundary crossing, report-cap behavior, truncated boot/FAT, tiny budget, huge declared geometry, bad offsets, strict read-only stream, and no source mutation.

## Limitations and next task
- Pattern statistics are descriptive, not data recovery, repair proposals, or proof of physical corruption.
- No checks of independent acquisition logs, boot-sector backup equivalence, file contents, or physical device condition.
- Team A must review the patch and synthetic CI before integration.
- Issue #9 next separate P1: bounded FAT-chain anomaly statistics (free, reserved, out-of-range, cycle, EOC), with explicitly measured reads and steps.

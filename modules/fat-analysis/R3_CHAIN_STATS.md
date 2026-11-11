# Team D R3-P3 — bounded FAT32 chain anomaly statistics

**Status:** synthetic-only research / Team A review required. This does **not** establish real-data recovery or underlying microSD damage cause.

## New independent API

`Get-ChappyFatChainAnomalyStats` in `Fat32ChainStats.psm1` accepts an already-open readable/seekable **non-writable** `System.IO.Stream`. No file paths, file creation, disk I/O, physical media access, repair proposals or writes exist in this module. It does not call R2's simulation functions. It preserves the v1 response envelope (`schemaVersion`, `team`, `status`, `scanIncomplete`, `items`, `warnings`, `errors`, `metrics`) and adds per-mirror numeric summaries.

Caller-supplied inputs are **not** verified from a BPB: `Fat1OffsetBytes`, `Fat2OffsetBytes`, `FatLengthBytes`, `MaxDataCluster` (last valid data cluster), and `StartClusters` (1..16 unique starts). The caller must independently validate these geometry parameters. The module rejects offset arithmetic overflow, overlaps, incorrect alignment, FAT entries too small for the requested max data cluster and data-cluster limits beyond FAT32 semantics.

## FAT32 chain classification

At each visited FAT entry, the tool masks the upper four bits and classifies the remaining 28 bits:

| Terminal reason code | FAT32 condition | Interpretation |
| --- | --- | --- |
| `fat.chain.eoc_observed` | `0x0FFFFFF8..0x0FFFFFFF` | End-of-chain marker observed |
| `fat.chain.free_link` | `0` | Chain unexpectedly points to a free cluster |
| `fat.chain.reserved_link` | `1` or `0x0FFFFFF0..0x0FFFFFF6` | Reserved value |
| `fat.chain.bad_cluster_marker` | `0x0FFFFFF7` | Bad-cluster marker |
| `fat.chain.out_of_range_link` | Value outside caller's valid data-cluster range | Link beyond declared data clusters |
| `fat.chain.cycle_observed` | Previously seen cluster referenced | Cycle; no repeated read needed |
| `fat.chain.invalid_start` | Invalid caller start cluster | No FAT read attempted |
| `io.fat_entry_truncated`, `io.short_read` | Inaccessible or short-read entry | Incomplete observation |
| `budget.chain_steps`, `budget.fat_copy_quota` | Step, entry or read quota exhausted | Incomplete observation |

An observed anomaly is evidence of a contradiction **only under the provided unverified geometry**; it is not a repair suggestion. A normal EOC is *not* proof that the file bytes, preceding chain or source device are valid. A result with `confidence=verified` means only that the stated terminal condition was observed, not that the filesystem is healthy or the recovery is correct.

## Hard bounds, privacy and coverage

- `MaxStepsPerChain`: 1..512 (default 128)
- `MaxTotalEntries`: 2..4096 (default 512), across both FATs
- `MaxReadBytes`: 8..16384 (default 2048), across both FATs
- Maximum 16 unique starting clusters
- Each mirror gets a fixed half of the global entry and byte budgets, preventing FAT1 from exhausting FAT2's quota
- Each FAT entry is read as four bytes; short reads count actual bytes and mark that chain incomplete
- Cycles terminate with a fixed-size per-chain visited set (at most 512 items), and no unlimited traversal occurs
- The `anomalyRateAmongResolvedTracesPercent` denominator is explicitly *resolved sampled traces*, **not whole-FAT entries, total files, or recovery success probability**
- `scanIncomplete` and `status=partial` flag any unresolved trace, including read/traversal budget, truncation or short read. Other trace results remain reportable with their own status.
- Numeric start/last-observed cluster identifiers appear only as geometry metadata; do **not** upload reports derived from actual local media. No filenames, full paths, raw data snippets or image digests are returned.
- `differentMirrorTerminals` counts mutually resolved differences by start cluster. Neither mirror is declared the correct copy. Identical malformed mirror chains can still both be damaged.

## Artificial test command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R3-ChainStats.Tests.ps1
```

Test vectors are fully synthetic byte arrays with EOC, free, reserved, bad-cluster, beyond-data-range, loops, invalid start, divergent FAT copies, step and global quotas, truncated FAT, huge declared FAT geometry, upper-nibble masking and rejection of writable streams/invalid geometry. Source byte array SHA-256 is compared internally in tests, but **not exported** by the analysis module or its public JSON output. Native Windows PowerShell 5.1 CI is required before integration.

## Remaining R3 research

The next task under Issue #9 is a strictly bounded **D-owned directory/FAT consistency summary**, consuming neutral numeric records or small read-only directory probes, without importing, rewriting or relying upon Team B's directory module.

All tests in public CI remain artificial. The 31GB master IMG and physical microSD must not be modified or scanned until Team A's separate local safety approval gate is completed. No real recovered file has been verified.

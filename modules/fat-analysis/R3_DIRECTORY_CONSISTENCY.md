# Team D R3-P4 — read-only anonymous directory/FAT consistency evidence

**Research only. Draft PR / Team A review required. No actual microSD or 31GB master IMG scan is authorized.**

## Independent Team D module

`Fat32DirectoryConsistency.psm1` exports `Get-ChappyFatDirectoryConsistency`.
It accepts a caller-provided **readable, seekable, non-writable** `System.IO.Stream` and independently probes at most 16 sequential 32-byte FAT32 short-directory slots from a supplied offset. It does **not** import, modify or invoke Team B's directory scanner and cannot extract any files.

Inputs: `DirectoryOffsetBytes`, `Fat1OffsetBytes`, `Fat2OffsetBytes`, `FatLengthBytes`, `MaxDataCluster`, `DirectorySlots` (1..16), `BytesPerCluster` (power of two 512..32768), `MaxStepsPerTrace` (1..32), `MaxReadBytes` (40..4096 combined). The declared directory window must not overlap either declared FAT range; FAT copies must not overlap each other; alignment, geometry and Int64 overflow are checked. **All offsets and geometry are caller-supplied and unverified.**

### Anonymized slot probing

Only these fields are used internally for candidates: slot index, directory attribute, 32-bit start cluster (high+low halves), and declared 32-bit file size. The module does **not export or log 8.3 names, LFN bytes, samples, sector content, hashes, paths or arbitrary metadata text**. Deleted, LFN, volume-label, dot entries and unsupported attribute bits are excluded; 0x00 is treated as an end-of-directory marker.

These are **possible** short-entry candidates, not verified directory records or filenames; random data can resemble a valid entry. This limited window does not establish parent directories, fragmentation of content or genuine file identity. Directory size fields are not used as byte coverage.

For each candidate, FAT1 and FAT2 are independently walked with cycle detection, a maximum of 32 reads/trace, fixed per-copy quotas and a cumulative total byte budget shared with the directory probe. Even if copies give the same result, no source authenticity or data integrity is inferred.

| Fixed evidence code | Meaning under *unverified* geometry |
| --- | --- |
| `file.empty_zero_cluster` | Zero-byte regular file with cluster 0 is compatible |
| `file.nonempty_zero_cluster` | Nonempty regular file has no start cluster |
| `directory.zero_cluster` | Directory candidate has no start cluster |
| `entry.cluster_out_of_range` | Start cluster exceeds supplied valid range |
| `file.chain_shorter_than_size` | EOC observed before file's minimum cluster count |
| `fat.chain_eoc_compatible` | EOC reached with enough clusters for size, or directory chain reaches EOC |
| `fat.chain_free_link` | Chain points to a free entry |
| `fat.chain_reserved_link` | Chain points to reserved FAT32 link |
| `fat.chain_bad_marker` | Bad-cluster FAT marker encountered |
| `fat.chain_out_of_range` | Next cluster outside supplied data range |
| `fat.chain_cycle` | Cluster chain repeats |
| `budget.chain_steps`, `budget.fat_copy_quota` | Evidence insufficient due to explicit limits |
| `io.fat_entry_truncated`, `io.short_fat_read` | Missing/truncated FAT entry |

`consistency` is `compatible`, `conflict`, or `unknown`; unknown observations set `scanIncomplete=true`. Compatible means only no contradiction in the tested numeric constraints; it is **not verification** of file content, filename correctness, cluster ownership or recovery. Confidence of compatible/conflict observations is deliberately `partial`.

## Bounds, output and privacy

- Directory scan reads at most 16 x 32 = 512 bytes, including a terminating slot if reached.
- Combined directory + both FAT copies reads at most `MaxReadBytes` (max 4096), with a fair fixed per-FAT quota after directory reads.
- Each read requests a maximum of 32 bytes (FAT entries always four bytes). Short reads are counted and do not create artificial records.
- Maximum 16 candidate starting entries per FAT copy and at most 32 chain steps per candidate; no unbounded search or recursion.
- Output follows v1 schema: `schemaVersion`, `team`, `status`, `scanIncomplete`, `items`, `warnings`, `errors`, `metrics`; includes independent numeric mirror counts and fixed reason codes.
- The `slotsExamined`, `candidateRecords`, `conflicts`, `compatibleObservations` and `unresolved` are **sample window metrics**, not full-volume file counts or recovery rates.
- The module has no output path or file writing API. It will reject writable input streams. Local reports from any real media must never be uploaded to public GitHub.

## Synthetic Windows PowerShell 5.1 test

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\fat-analysis\tests\Run-TeamD-R3-Consistency.Tests.ps1
```

Synthetic fixtures exercise file-size/chain-length differences across mirrors, free and bad links, cycle, zero-cluster cases, directory and file distinction, deleted/LFN/dot/volume/unsupported slot skips, invalid starts, byte-budget/step-budget limits, truncated directory slots, huge sizes, arithmetic overflow, oversized declared FAT geometry, rejection of writable streams and privacy-safe JSON. Source byte array SHA-256 is compared **only inside the tests**, never in the module's reports.

The Windows test workflow and privacy gate must pass on the exact Draft PR head before Team A considers merging.

## R3 handoff

R3-P1 FAT mirror regional comparison, P2 EB58 distribution and P3 chain terminal statistics were already integrated by Team A. R3-P4 is the last of Issue #9's four explicitly assigned scoped research increments. Any new expansion beyond these deliverables needs Team A's fresh planning and review. Even after successful synthetic CI, actual 31GB data recovery is unverified and direct local source testing remains blocked by `docs/LOCAL_READONLY_APPROVAL_GATE.md`.

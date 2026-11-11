# Team B — FAT-independent directory metadata (R1 draft)

**Status:** Prototype, independent module. No image repair, FAT-chain reads, or file-content extraction.

## Entry points

- `DirectoryScanner.ps1` — dot-source to import `Get-ChappyFat32Geometry` and `Get-ChappyDirectoryCandidates`.
- `Invoke-ChappyDirectoryScan.ps1` — local CLI that opens **regular files** with `FileAccess.Read` and `FileShare.Read`; no device paths.
- `tests/Test-DirectoryScanner.ps1` — standard PowerShell 5.1 synthetic fixtures; generates and deletes a small local IMG in temporary storage. **Do not commit fixtures / results.**

## Local command (after Windows synthetic validation and A's review)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\directory\Invoke-ChappyDirectoryScan.ps1 `
  -ImagePath 'C:\SD_Backups\your_backup.img' `
  -OutputJsonPath 'C:\SD_Backups\team-b-local-report.json' `
  -PartitionOffsetBytes 4194304 `
  -MaxScanBytes 67108864 -IncludeNames
```

`-IncludeNames` is an **explicit private/local opt-in**. Without it, `name` and `shortName` are `null`. Do not upload JSON reports that contain original filenames, paths, or user file metadata.

`-MaxScanBytes` limits **data region cluster bytes read**, not total IMG size. Default is 64 MiB and the root cluster is scanned before the starting cluster range. A small budget does **not** mean complete recovery. Increase deliberately only after Windows synthetic validation and integrator review. `-StartCluster` defaults to 2. The default results cover a contiguous cluster range and root only; cross-volume discovery requires bounds that cover the desired area.

### Structured result

`schemaVersion: "1"`, `team: "B"`, `status: "ok|partial|error"`, `scanIncomplete`, `items[]`, `warnings[]`, `errors[]`, `metrics`, `geometry`. Individual items have `offsetBytes`, `containerCluster`, `startCluster`, `sizeBytes`, `isDirectory`, `deleted`, `name`, `shortName`, `nameSource`, `confidence`, `evidence`, `parentClusterHint`. Parent hint comes only from a valid `..` entry in the *candidate* directory; it is not independently established by a FAT chain.

### Detection and limitations

- MBR FAT32 partition type 0x0B / 0x0C or explicit partition offset; BPB and region bounds are validated, no FAT entry is consulted.
- Every cluster is screened independently for 8.3 entries, strict UTF-16LE LFN sequence/checksum, `.`/`..` headers, or root-anchor evidence.
- A cluster with only one short-name record (outside root and without valid dot/LFN) is **not** accepted: it may be ordinary file content. This can omit legitimate split directories. More permissive candidates should be explored in a later opt-in pass.
- File sizes are metadata claims and not verified against file content. No chain reconstruction, no guaranteed directory tree or path, no fragmented-file recovery, no backup-boot scanning, no automated exFAT handling.
- Corrupt LFNs fall back to 8.3 alias with `partial`; deleted 8.3 first byte is unknown (`?`). Invalid/path-like LFNs rejected, **never** interpreted as extraction paths.
- `confidence=probable` is *structure only*, not proof that content, size, or links are valid. False positives remain possible.
- Some FAT32 implementations may use unusual DBCS/OEM short names. Short alias decoding uses CP437 solely for display; Unicode LFNs are validated independently.
- Geometry routine refuses images truncated relative to BPB; `status=error`. Physical memory use is O(cluster size + returned candidate metadata), not O(image size), but PowerShell full-disk scans can be CPU-intensive.

## Verification status

- Static review: performed during generation (not a runtime test).
- PowerShell 5.1 synthetic tests: **not executed in this authoring environment** (Windows PowerShell not available).
- Windows real IMG: **not tested**. No recovered data or names should be represented as confirmed.
- Privacy: source image never uploaded to GitHub; no real filenames in repository.

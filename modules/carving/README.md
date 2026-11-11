# Team C: FAT-independent carving (experimental)

Only Windows PowerShell 5.1 and built-in .NET are used. The module opens no source file by itself during scanning: its caller passes a **readable, seekable stream**. Scan operations never write to that stream. Extraction uses `FileAccess.Read` for the IMG and `CreateNew` for output files.

## Local synthetic tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\modules\carving\tests\Test-ChappyCarving.ps1
```

The above is for **synthetic fixtures only**. Do not use the master IMG until Team A's review and Windows test gate pass.

## Read-only scan (small, bounded region)

```powershell
Import-Module .\modules\carving\Chappy.Carving.psm1 -Force
$stream = [IO.File]::Open('X:\local\backup.img', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $found = Get-ChappyCarvingCandidates -Stream $stream -StartOffset 0 -MaxScanBytes 67108864 -MaxFileBytes 134217728
} finally { $stream.Dispose() }
$found | Select-Object status,scanIncomplete,metrics
# Opt-in local-only report, new file only:
# Write-ChappyCarvingReport -Result $found -ReportPath 'D:\local-output\scan-0001.json'
```

The original IMG path above is *illustrative only*, not a user path. The scanner visits a bounded 64 MiB range; it does **not** analyze the full 31 GiB by default. To proceed, increase `StartOffset` in batches. ZIP validation may read ahead outside the scan range up to `MaxFileBytes` to find the archive end; `metrics.bytesRead` is the **nominal scan range, not the actual I/O count**.

## Opt-in extraction

The output directory must already exist and must differ from the source file directory. No filename from the source is ever trusted: output names derive from byte offsets. `Export-ChappyCarvingCandidate` writes into `structurally_verified`, `probable`, or `partial` subfolders with `FileMode.CreateNew`; no overwrite is permitted.

```powershell
# Only AFTER manual review of the candidate and source constraints:
# $candidate = @($found.items | Where-Object { $_.lengthBytes -gt 0 })[0]
# Export-ChappyCarvingCandidate -ImagePath 'X:\local\backup.img' -Candidate $candidate -OutputDirectory 'D:\local-output'
```

## Confidence semantics

- `verified`: ZIP references and bounds are structurally valid. STORED (method 0) entries are checked with CRC-32 only while the **whole archive CRC-check budget is at most 64 KiB**. `verified` **does not imply every entry content was checked**, and does not prove the original data survived.
- `probable`: G-code ASCII commands/comments form a plausible continuous segment; file start/end and completeness remain uncertain.
- `partial`: ZIP local header without a valid central directory (length 0; extraction blocked), or bounded/truncated/discontinuous G-code.
- `fragmentationSuspected`: optional heuristic for suspicious non-text break in G-code; does not reconstruct fragments.

A 3MF is classified from three conventional ZIP entry names: `[Content_Types].xml`, `_rels/.rels`, and `3D/*.model`. ZIP validation **does not** validate OPC/XML contents, relationships, ZIP64, encryption, deflate (method 8) decompression/CRC, or fragments. It targets single-disk ZIPs with stored/deflate entries; only small method 0 payloads receive CRC-32 checking.

## CRC-32 result fields (R2)

- ZIP candidate fields: `crc32Status` is `match`, `mismatch`, `partial`, or `not_checked`; `crc32CheckedEntries` and `crc32UncheckedEntries` give anonymous counts. These fields are also included in redacted JSON reports, without entry names or content.
- A STORED entry can be CRC-checked only when its compressed/uncompressed lengths match and the remaining **64 KiB per-ZIP budget** permits. CRC-32 uses constant-size streaming buffers, not whole-file memory reads.
- `mismatch` means at least one checked entry does not match its central-directory CRC. The candidate is downgraded to `confidence=partial` with evidence `zip.stored_crc_mismatch`. `truncated=false` is possible for corrupt-but-complete ZIPs.
- `partial` CRC status means some entries checked and others deliberately skipped. `not_checked` means zero entries checked. **Deflate entries are never CRC-checked in this round**, even though structural classification may still be `verified`.
- `match` means all considered entries were STORED and verified against the central-directory CRC under the budget. This still does not validate 3MF model XML or guarantee pre-corruption filesystem data.

## Known limitations and safety

- G-code start anchors require a recognized command/header at the beginning of a block or after a newline/zero byte; some valid G-code may be missed. Encodings other than printable ASCII are not supported yet.
- A ZIP containing internal `PK\x03\x04` strings may create additional `partial` candidates. A valid ZIP's subsequent local headers are skipped once the archive is recognized.
- ZIP signature candidate validation may repeatedly scan up to `MaxFileBytes`; performance on adversarial images remains an open issue. Candidate counts, scan bytes, entry counts, and line counts are capped.
- Returned offsets are logical offsets in the input stream, not clusters or partition-relative addresses.
- Never send real recovered files, unredacted reports, or source IMG data to GitHub.